#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-/root/clearxray.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Файл параметров не найден: $ENV_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

LINK="vless://${UUID}@${SERVER_IP}:443?encryption=none&type=tcp&security=reality&sni=${TARGET_HOST}&fp=chrome&pbk=${PASSWORD}&sid=${SHORT_ID}#clearxray-${TARGET_HOST}"

echo "Клиентская ссылка:"
echo
printf '%s\n' "$LINK"

echo
echo "QR-код:"
echo

if command -v qrencode >/dev/null 2>&1; then
  printf '%s' "$LINK" | qrencode -t ANSIUTF8
else
  echo "qrencode не установлен. Установите пакет: apt-get install -y qrencode"
fi

if [[ "${VISION_ENABLED:-0}" == "1" ]]; then
  VISION_LINK="vless://${VISION_UUID}@${SERVER_IP}:${VISION_PORT}?encryption=none&type=tcp&security=reality&sni=${TARGET_HOST}&fp=chrome&pbk=${VISION_PASSWORD}&sid=${VISION_SHORT_ID}&flow=xtls-rprx-vision#clearxray-vision-${TARGET_HOST}-${VISION_PORT}"

  echo
  echo "Экспериментальная клиентская ссылка Vision:"
  echo
  printf '%s\n' "$VISION_LINK"

  echo
  echo "QR-код Vision:"
  echo

  if command -v qrencode >/dev/null 2>&1; then
    printf '%s' "$VISION_LINK" | qrencode -t ANSIUTF8
  else
    echo "qrencode не установлен. Установите пакет: apt-get install -y qrencode"
  fi
fi
