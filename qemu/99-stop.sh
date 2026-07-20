#!/usr/bin/env bash
# Arrête la VM de compilation.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

if ! vm_alive; then
  echo "[vm] déjà arrêtée"
  rm -f "${BUILDER_PIDFILE}"
  exit 0
fi

pid="$(cat "${BUILDER_PIDFILE}")"
echo "[vm] arrêt du PID ${pid}"
kill "${pid}"

for _ in $(seq 1 20); do
  if ! vm_alive; then
    rm -f "${BUILDER_PIDFILE}"
    echo "[vm] arrêtée"
    exit 0
  fi
  sleep 1
done

echo "[vm] arrêt propre refusé, envoi de SIGKILL" >&2
kill -9 "${pid}" 2>/dev/null || true
rm -f "${BUILDER_PIDFILE}"
