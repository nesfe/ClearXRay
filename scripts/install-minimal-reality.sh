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

VISION_ENABLED=0
VISION_PORT=""
read -r -p "Дополнительно развернуть профиль Vision с flow=xtls-rprx-vision на отдельном порту? [y/N]: " ENABLE_VISION
case "${ENABLE_VISION,,}" in
  y|yes|д|да)
    VISION_ENABLED=1
    VISION_PORT_DEFAULT="8443"
    read -r -p "Порт для Vision-профиля [${VISION_PORT_DEFAULT}]: " VISION_PORT
    VISION_PORT="${VISION_PORT:-$VISION_PORT_DEFAULT}"
    if ! [[ "$VISION_PORT" =~ ^[0-9]+$ ]] || (( VISION_PORT < 1 || VISION_PORT > 65535 )); then
      err "Некорректный порт для Vision-профиля: ${VISION_PORT}"
      exit 1
    fi
    if [[ "$VISION_PORT" == "22" || "$VISION_PORT" == "443" ]]; then
      err "Vision-профиль должен использовать отдельный порт, не 22 и не 443."
      exit 1
    fi
    warn "Vision-профиль с flow=xtls-rprx-vision будет открыт на ${VISION_PORT}/tcp."
    ;;
esac

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
if [[ "$VISION_ENABLED" == "1" ]]; then
  fuser -k "${VISION_PORT}/tcp" 2>/dev/null || true
fi
rm -f /root/clearxray.env \
  /root/clearxray-link.txt \
  /root/clearxray-qr.png \
  /root/clearxray-vision-link.txt \
  /root/clearxray-vision-qr.png 2>/dev/null || true
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
apt-get install -y -qq curl openssl ufw ca-certificates qrencode
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
VISION_UUID=""
VISION_PRIVATE_KEY=""
VISION_PASSWORD=""
VISION_SHORT_ID=""

if [[ "$VISION_ENABLED" == "1" ]]; then
  VISION_UUID="$("/usr/local/bin/xray" uuid)"
  VISION_KEYS="$("/usr/local/bin/xray" x25519 2>&1)"
  VISION_PRIVATE_KEY="$(awk -F': ' '/PrivateKey/ {print $2}' <<<"$VISION_KEYS")"
  VISION_PASSWORD="$(awk -F': ' '/Password \(PublicKey\)/ {print $2}' <<<"$VISION_KEYS")"
  VISION_SHORT_ID="$(openssl rand -hex 8)"
fi

if [[ -z "$SERVER_IP" || -z "$UUID" || -z "$PRIVATE_KEY" || -z "$PASSWORD" || -z "$SHORT_ID" ]]; then
  err "Не удалось сгенерировать один или несколько обязательных параметров"
  printf '%s\n' "$KEYS"
  exit 1
fi

if [[ "$VISION_ENABLED" == "1" ]] && [[ -z "$VISION_UUID" || -z "$VISION_PRIVATE_KEY" || -z "$VISION_PASSWORD" || -z "$VISION_SHORT_ID" ]]; then
  err "Не удалось сгенерировать один или несколько параметров Vision-профиля"
  printf '%s\n' "$VISION_KEYS"
  exit 1
fi

ok "IP: $SERVER_IP"
ok "UUID: $UUID"
ok "PublicKey: $PASSWORD"
ok "Short ID: $SHORT_ID"

VISION_INBOUND_JSON=""
if [[ "$VISION_ENABLED" == "1" ]]; then
  ok "Vision port: ${VISION_PORT}"
  ok "Vision UUID: ${VISION_UUID}"
  ok "Vision PublicKey: ${VISION_PASSWORD}"
  ok "Vision Short ID: ${VISION_SHORT_ID}"
  VISION_INBOUND_JSON=$(cat <<EOF
,
    {
      "listen": "0.0.0.0",
      "port": ${VISION_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${VISION_UUID}",
            "flow": "xtls-rprx-vision",
            "email": "vision"
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
          "privateKey": "${VISION_PRIVATE_KEY}",
          "shortIds": [
            "${VISION_SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
EOF
)
fi

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
${VISION_INBOUND_JSON}
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
if [[ "$VISION_ENABLED" == "1" ]]; then
  ufw allow "${VISION_PORT}/tcp" comment 'Xray Reality Vision'
fi
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

if [[ "$VISION_ENABLED" == "1" ]]; then
  if ss -ltnp | grep -q ":${VISION_PORT}"; then
    ok "Порт ${VISION_PORT} слушает"
  else
    err "Порт ${VISION_PORT} не слушает"
    exit 1
  fi
fi

step "Сохранение параметров"
CLIENT_LINK="vless://${UUID}@${SERVER_IP}:443?encryption=none&type=tcp&security=reality&sni=${TARGET_HOST}&fp=chrome&pbk=${PASSWORD}&sid=${SHORT_ID}#clearxray-${TARGET_HOST}"
VISION_CLIENT_LINK=""
if [[ "$VISION_ENABLED" == "1" ]]; then
  VISION_CLIENT_LINK="vless://${VISION_UUID}@${SERVER_IP}:${VISION_PORT}?encryption=none&type=tcp&security=reality&sni=${TARGET_HOST}&fp=chrome&pbk=${VISION_PASSWORD}&sid=${VISION_SHORT_ID}&flow=xtls-rprx-vision#clearxray-vision-${TARGET_HOST}-${VISION_PORT}"
fi

cat > /root/clearxray.env <<EOF
SERVER_IP=${SERVER_IP}
TARGET_HOST=${TARGET_HOST}
UUID=${UUID}
PASSWORD=${PASSWORD}
SHORT_ID=${SHORT_ID}
PRIVATE_KEY=${PRIVATE_KEY}
VISION_ENABLED=${VISION_ENABLED}
VISION_PORT=${VISION_PORT}
VISION_UUID=${VISION_UUID}
VISION_PASSWORD=${VISION_PASSWORD}
VISION_SHORT_ID=${VISION_SHORT_ID}
VISION_PRIVATE_KEY=${VISION_PRIVATE_KEY}
EOF

printf '%s\n' "$CLIENT_LINK" > /root/clearxray-link.txt

printf '%s' "$CLIENT_LINK" | qrencode -o /root/clearxray-qr.png

if [[ "$VISION_ENABLED" == "1" ]]; then
  printf '%s\n' "$VISION_CLIENT_LINK" > /root/clearxray-vision-link.txt
  printf '%s' "$VISION_CLIENT_LINK" | qrencode -o /root/clearxray-vision-qr.png
fi

ok "Сохранён /root/clearxray.env"
ok "Сохранён /root/clearxray-link.txt"
ok "Сохранён /root/clearxray-qr.png"
if [[ "$VISION_ENABLED" == "1" ]]; then
  ok "Сохранён /root/clearxray-vision-link.txt"
  ok "Сохранён /root/clearxray-vision-qr.png"
fi

step "Результат установки"
info "Сервис: Xray REALITY"
info "Порт: 443/tcp"
info "Хост маскировки: ${TARGET_HOST}"
info "Файл окружения: /root/clearxray.env"
info "Файл клиентской ссылки: /root/clearxray-link.txt"
info "PNG QR-код: /root/clearxray-qr.png"

printf "\n${GREEN}Готовая клиентская ссылка${NC}\n\n"
cat /root/clearxray-link.txt
printf "\n\n${GREEN}QR-код для импорта в клиент${NC}\n\n"
printf '%s' "$CLIENT_LINK" | qrencode -t ANSIUTF8

if [[ "$VISION_ENABLED" == "1" ]]; then
  printf "\n\n${YELLOW}Экспериментальная клиентская ссылка Vision${NC}\n\n"
  cat /root/clearxray-vision-link.txt
  printf "\n\n${YELLOW}QR-код Vision для импорта в клиент${NC}\n\n"
  printf '%s' "$VISION_CLIENT_LINK" | qrencode -t ANSIUTF8
fi

printf "\n\n${CYAN}Полезные команды${NC}\n"
printf "  systemctl status xray\n"
printf "  journalctl -u xray -n 50 --no-pager\n"
printf "  ss -ltnp | grep 443\n"
printf "  cat /root/clearxray-link.txt\n"
printf "  qrencode -t ANSIUTF8 < /root/clearxray-link.txt\n"
if [[ "$VISION_ENABLED" == "1" ]]; then
  printf "  cat /root/clearxray-vision-link.txt\n"
  printf "  qrencode -t ANSIUTF8 < /root/clearxray-vision-link.txt\n"
fi
