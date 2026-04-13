#!/usr/bin/env bash
set -euo pipefail

RAW_URL="https://raw.githubusercontent.com/nesfe/ClearXRay/main/scripts/install-minimal-reality.sh"

if [[ -f "./scripts/install-minimal-reality.sh" ]]; then
  bash "./scripts/install-minimal-reality.sh"
  exit 0
fi

bash <(curl -fsSL "${RAW_URL}")
