#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Установщик необходимо запускать от имени root."
  exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

title() { printf "\n${BLUE}ClearXRay${NC}\n"; }
step() { printf "\n${CYAN}== %s ==${NC}\n\n" "$1"; }
ok() { printf "${GREEN}[OK] %s${NC}\n" "$1"; }
warn() { printf "${YELLOW}[!] %s${NC}\n" "$1"; }
err() { printf "${RED}[ОШИБКА] %s${NC}\n" "$1"; }
info() { printf "    %s\n" "$1"; }

title
printf "Установщик минимальной конфигурации Xray REALITY\n"
printf "Режим установки: полная пересборка VPN-стека на сервере\n"

TARGET_HOST_DEFAULT="www.mix.com"
read -r -p "Хост для маскировки [${TARGET_HOST_DEFAULT}]: " TARGET_HOST
TARGET_HOST="${TARGET_HOST:-$TARGET_HOST_DEFAULT}"

warn "Будут удалены остатки Xray, Amnezia, Outline, Docker и очищены правила iptables."
warn "Порт 443/tcp будет освобождён и заново назначен для Xray REALITY."

step "Полная очистка сервера"
if command -v docker >/dev/null 2>&1; then
  warn "Обнаружен Docker. Выполняется удаление контейнеров, сетей и пакетов."
  docker stop $(docker ps -aq) 2>/dev/null || true
  docker rm $(docker ps -aq) 2>/dev/null || true
  docker network prune -f 2>/dev/null || true
  systemctl stop docker.socket docker.service 2>/dev/null || true
  apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
  apt-get purge -y docker docker.io containerd runc 2>/dev/null || true
  rm -rf /var/lib/docker /var/lib/containerd /etc/docker
  ok "Docker удалён"
else
  ok "Docker не найден"
fi

rm -rf /opt/amnezia /etc/amnezia 2>/dev/null || true
rm -rf /opt/outline /etc/outline 2>/dev/null || true
ok "Остатки Amnezia и Outline удалены"

systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true
ok "Предыдущий сервис Xray остановлен"

iptables -F 2>/dev/null || true
iptables -X 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t nat -X 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -t mangle -X 2>/dev/null || true
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true
ok "iptables очищены"

fuser -k 443/tcp 2>/dev/null || true
rm -f /root/clearxray.env /root/clearxray-link.txt 2>/dev/null || true
ok "Старые артефакты очищены"

step "Проверка TLS-хоста"
if echo | openssl s_client -connect "${TARGET_HOST}:443" -servername "${TARGET_HOST}" -verify_hostname "${TARGET_HOST}" >/tmp/clearxray-target.log 2>&1; then
  ok "Сертификат ${TARGET_HOST} успешно проверен"
else
  err "Проверка сертификата ${TARGET_HOST} не прошла"
  sed -n '1,80p' /tmp/clearxray-target.log || true
  exit 1
fi

step "Установка зависимостей"
apt-get update -qq
apt-get install -y -qq curl openssl ufw ca-certificates
ok "Системные зависимости установлены"

step "Установка Xray"
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
test -x /usr/local/bin/xray
ok "$(/usr/local/bin/xray version | head -1)"

step "Генерация параметров"
SERVER_IP="$(curl -s --max-time 10 https://api.ipify.org || true)"
UUID="$("/usr/local/bin/xray" uuid)"
KEYS="$("/usr/local/bin/xray" x25519 2>&1)"
PRIVATE_KEY="$(awk -F': ' '/PrivateKey/ {print $2}' <<<"$KEYS")"
PASSWORD="$(awk -F': ' '/Password \(PublicKey\)/ {print $2}' <<<"$KEYS")"
SHORT_ID="$(openssl rand -hex 8)"

if [[ -z "$SERVER_IP" || -z "$UUID" || -z "$PRIVATE_KEY" || -z "$PASSWORD" || -z "$SHORT_ID" ]]; then
  err "Не удалось сгенерировать один или несколько обязательных параметров"
  printf '%s\n' "$KEYS"
  exit 1
fi

ok "IP: $SERVER_IP"
ok "UUID: $UUID"
ok "PublicKey: $PASSWORD"
ok "Short ID: $SHORT_ID"

step "Запись конфига"
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "email": "main"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${TARGET_HOST}:443",
          "xver": 0,
          "serverNames": [
            "${TARGET_HOST}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

"/usr/local/bin/xray" run -test -config /usr/local/etc/xray/config.json
ok "Конфиг Xray валиден"

step "Настройка firewall"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 443/tcp comment 'Xray Reality'
ufw --force enable
ok "UFW настроен"

step "Запуск сервиса"
systemctl enable xray
systemctl restart xray
sleep 1
systemctl is-active --quiet xray
ok "Xray запущен"

if ss -ltnp | grep -q ':443'; then
  ok "Порт 443 слушает"
else
  err "Порт 443 не слушает"
  exit 1
fi

step "Сохранение параметров"
cat > /root/clearxray.env <<EOF
SERVER_IP=${SERVER_IP}
TARGET_HOST=${TARGET_HOST}
UUID=${UUID}
PASSWORD=${PASSWORD}
SHORT_ID=${SHORT_ID}
PRIVATE_KEY=${PRIVATE_KEY}
EOF

cat > /root/clearxray-link.txt <<EOF
vless://${UUID}@${SERVER_IP}:443?encryption=none&type=tcp&security=reality&sni=${TARGET_HOST}&fp=chrome&pbk=${PASSWORD}&sid=${SHORT_ID}#clearxray-${TARGET_HOST}
EOF

ok "Сохранён /root/clearxray.env"
ok "Сохранён /root/clearxray-link.txt"

step "Результат установки"
info "Сервис: Xray REALITY"
info "Порт: 443/tcp"
info "Хост маскировки: ${TARGET_HOST}"
info "Файл окружения: /root/clearxray.env"
info "Файл клиентской ссылки: /root/clearxray-link.txt"

printf "\n${GREEN}Готовая клиентская ссылка${NC}\n\n"
cat /root/clearxray-link.txt
printf "\n\n${CYAN}Полезные команды${NC}\n"
printf "  systemctl status xray\n"
printf "  journalctl -u xray -n 50 --no-pager\n"
printf "  ss -ltnp | grep 443\n"
printf "  cat /root/clearxray-link.txt\n"
