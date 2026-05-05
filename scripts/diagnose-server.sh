#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-/root/clearxray.env}"
TEST_URL="${2:-https://www.cloudflare.com}"

section() {
  printf '\n== %s ==\n' "$1"
}

run() {
  printf '\n$ %s\n' "$*"
  "$@" 2>&1 || true
}

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Диагностику сервера нужно запускать от имени root."
  exit 1
fi

section "System"
run hostnamectl
run date -u
run uname -a
run ip -brief addr
run ip route

section "Xray binary and service"
if command -v xray >/dev/null 2>&1; then
  run xray version
elif [[ -x /usr/local/bin/xray ]]; then
  run /usr/local/bin/xray version
else
  echo "Xray binary не найден в PATH и /usr/local/bin/xray."
fi

run systemctl status xray --no-pager
run journalctl -u xray -n 120 --no-pager

section "Ports and firewall"
run ss -ltnp
run ss -lunp
run ufw status verbose
run iptables -S
run iptables -t nat -S

section "ClearXRay files"
run ls -la /usr/local/etc/xray /root/clearxray.env /root/clearxray-link.txt

if [[ -f /usr/local/etc/xray/config.json ]]; then
  run /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json
  echo
  echo "--- /usr/local/etc/xray/config.json ---"
  sed -n '1,260p' /usr/local/etc/xray/config.json
fi

if [[ -f "$ENV_FILE" ]]; then
  section "Saved client parameters"
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  printf 'SERVER_IP=%s\n' "${SERVER_IP:-}"
  printf 'TARGET_HOST=%s\n' "${TARGET_HOST:-}"
  printf 'UUID=%s\n' "${UUID:-}"
  printf 'PASSWORD/PublicKey=%s\n' "${PASSWORD:-}"
  printf 'SHORT_ID=%s\n' "${SHORT_ID:-}"

  if [[ -f /root/clearxray-link.txt ]]; then
    echo
    echo "--- /root/clearxray-link.txt ---"
    cat /root/clearxray-link.txt
  fi

  section "External target check"
  if [[ -n "${TARGET_HOST:-}" ]]; then
    run openssl s_client -connect "${TARGET_HOST}:443" -servername "${TARGET_HOST}" -verify_hostname "${TARGET_HOST}" -brief
  fi

  section "Local client self-test"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "${SCRIPT_DIR}/self-test-reality.sh" ]]; then
    run "${SCRIPT_DIR}/self-test-reality.sh" "$ENV_FILE" "$TEST_URL"
  elif [[ -f "${SCRIPT_DIR}/self-test-reality.sh" ]]; then
    run bash "${SCRIPT_DIR}/self-test-reality.sh" "$ENV_FILE" "$TEST_URL"
  else
    echo "self-test-reality.sh не найден рядом с diagnose-server.sh."
  fi
else
  echo "Файл параметров не найден: $ENV_FILE"
fi
