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
  if ! curl -L --fail --progress-bar --connect-timeout 20 \
       -o "${FREEBSD_IMAGE_XZ}" \
       "${FREEBSD_IMAGE_URL}"; then
    rm -f "${FREEBSD_IMAGE_XZ}"
    echo >&2
    echo "[image] téléchargement impossible pour ${FREEBSD_VERSION}." >&2
    echo >&2
    echo "        Un 404 signifie presque toujours une version non publiée" >&2
    echo "        ou retirée : les images des branches en fin de vie sont" >&2
    echo "        supprimées des miroirs. FreeBSD 13 en fait partie." >&2
    echo >&2
    echo "        Versions publiées au 21/07/2026 : 14.3-RELEASE," >&2
    echo "        14.4-RELEASE, 15.0-RELEASE, 15.1-RELEASE." >&2
    echo >&2
    echo "        Liste à jour :" >&2
    echo "        https://download.freebsd.org/releases/VM-IMAGES/" >&2
    exit 1
  fi
fi

echo "[image] décompression (~600 Mo → ~3 Gio)"
xz -d -k -v "${FREEBSD_IMAGE_XZ}"

echo "[image] prête : ${FREEBSD_IMAGE_QCOW2}"
ls -lh "${FREEBSD_IMAGE_QCOW2}"
