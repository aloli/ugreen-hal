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

# Vérification de l'empreinte avant décompression. FreeBSD publie un
# CHECKSUM.SHA256 dans le même répertoire, au format :
#   SHA256 (FreeBSD-15.0-RELEASE-amd64-...qcow2.xz) = <empreinte>
#
# Une archive tronquée se manifesterait sinon par une erreur de xz
# difficile à distinguer d'un disque plein, ou pire, par une image qui
# démarre à moitié.
checksum_url="$(dirname "${FREEBSD_IMAGE_URL}")/CHECKSUM.SHA256"
echo "[image] vérification de l'empreinte"

if published="$(curl -L --fail --silent --connect-timeout 20 "${checksum_url}" \
                | grep -F "(${FREEBSD_IMAGE_BASENAME}.xz)" \
                | grep -oE '[0-9a-f]{64}' \
                | head -1)" && [[ -n "${published}" ]]; then
  computed="$(shasum -a 256 "${FREEBSD_IMAGE_XZ}" | cut -d' ' -f1)"
  if [[ "${published}" == "${computed}" ]]; then
    echo "[image] empreinte conforme"
  else
    echo "[image] EMPREINTE INCORRECTE — archive corrompue ou incomplète." >&2
    echo "        publiée  : ${published}" >&2
    echo "        calculée : ${computed}" >&2
    echo "        Le fichier est supprimé ; relancer pour retélécharger." >&2
    rm -f "${FREEBSD_IMAGE_XZ}"
    exit 1
  fi
else
  echo "[image] empreinte publiée introuvable — vérification impossible" >&2
fi

echo "[image] décompression (~600 Mo → ~3 Gio)"
xz -d -k -v "${FREEBSD_IMAGE_XZ}"

echo "[image] prête : ${FREEBSD_IMAGE_QCOW2}"
ls -lh "${FREEBSD_IMAGE_QCOW2}"
