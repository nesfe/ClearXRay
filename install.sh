#!/usr/bin/env bash
set -euo pipefail

RAW_URL="https://raw.githubusercontent.com/nesfe/ClearXRay/main/scripts/install-minimal-reality.sh"

if [[ -f "./scripts/install-minimal-reality.sh" ]]; then
  printf 'Запуск локального установщика ClearXRay\n'
  bash "./scripts/install-minimal-reality.sh"
  exit 0
fi

printf 'Загрузка установщика ClearXRay из GitHub\n'
bash <(curl -fL --show-error --connect-timeout 15 --max-time 180 --retry 3 --retry-delay 2 "${RAW_URL}")
