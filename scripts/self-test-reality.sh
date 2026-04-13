#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-/root/clearxray.env}"
TEST_URL="${2:-https://www.cloudflare.com}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Файл параметров не найден: $ENV_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

TMP_CONFIG="$(mktemp)"
TMP_LOG="$(mktemp)"

cleanup() {
  rm -f "$TMP_CONFIG" "$TMP_LOG"
  pkill -f "$TMP_CONFIG" 2>/dev/null || true
}
trap cleanup EXIT

echo "Запуск локальной проверки конфигурации REALITY"
echo "Сервер: ${SERVER_IP}:443"
echo "Хост маскировки: ${TARGET_HOST}"
echo "Тестовый URL: ${TEST_URL}"

cat > "$TMP_CONFIG" <<EOF
{
  "log": { "loglevel": "info" },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks",
      "settings": { "udp": false }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${SERVER_IP}",
            "port": 443,
            "users": [
              {
                "id": "${UUID}",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "serverName": "${TARGET_HOST}",
          "fingerprint": "chrome",
          "password": "${PASSWORD}",
          "shortId": "${SHORT_ID}"
        }
      }
    }
  ]
}
EOF

/usr/local/bin/xray run -test -config "$TMP_CONFIG"
echo "Временная клиентская конфигурация валидна"
nohup /usr/local/bin/xray run -config "$TMP_CONFIG" >"$TMP_LOG" 2>&1 &
PID=$!
sleep 2

if curl --socks5-hostname 127.0.0.1:10808 -I --max-time 12 "$TEST_URL"; then
  echo "Локальная проверка завершилась успешно"
else
  echo "Локальная проверка завершилась ошибкой"
  echo "--- лог временного xray-клиента ---"
  tail -n 80 "$TMP_LOG" || true
  exit 1
fi

kill "$PID" 2>/dev/null || true
