#!/usr/bin/env bash
# Télécharge et décompresse l'image cloud FreeBSD amd64.
# Idempotent : ne fait rien si l'image est déjà extraite.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ensure_dirs

if [[ -f "${FREEBSD_IMAGE_QCOW2}" ]]; then
  echo "[image] déjà extraite : ${FREEBSD_IMAGE_QCOW2}"
  exit 0
fi

if [[ ! -f "${FREEBSD_IMAGE_XZ}" ]]; then
  echo "[image] téléchargement de ${FREEBSD_IMAGE_URL}"
  curl -L --fail --progress-bar --connect-timeout 20 \
    -o "${FREEBSD_IMAGE_XZ}" \
    "${FREEBSD_IMAGE_URL}"
fi

echo "[image] décompression (~600 Mo → ~3 Gio)"
xz -d -k -v "${FREEBSD_IMAGE_XZ}"

echo "[image] prête : ${FREEBSD_IMAGE_QCOW2}"
ls -lh "${FREEBSD_IMAGE_QCOW2}"
