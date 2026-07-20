# shellcheck shell=bash
#
# Variables et fonctions communes au banc QEMU de ugreen-hal.
#
# Objectif du banc : compiler et exercer src/cli/ contre un vrai FreeBSD,
# sur la machine de développement, sans dépendre du NAS ni de la CI.
#
# POURQUOI amd64 ET NON aarch64
# -----------------------------
# Le banc voisin (prod-crystal/qemu, projet clevis-zfs) utilise une image
# aarch64, qui bénéficie de l'accélération matérielle HVF sur Mac Apple
# Silicon. Ici c'est amd64 : le DXP2800 est un Intel N100, et l'intérêt
# principal est de produire un binaire *directement exécutable sur le NAS*,
# pas seulement de vérifier que le code compile.
#
# Contrepartie assumée : sur un Mac ARM, l'amd64 tourne en émulation
# logicielle (TCG), sans accélération. Le démarrage prend plusieurs minutes
# là où l'aarch64 démarre en quelques secondes. C'est sans importance pour
# l'usage visé — on compile 300 lignes de C, pas un buildworld.
#
# CE QUE CE BANC NE PEUT PAS FAIRE
# --------------------------------
# Valider le protocole SMBus. Le contrôleur LED d'UGREEN est un composant
# physique de la carte mère : il ne s'émule pas. Le banc dira que le code
# compile, que les ioctls existent et que les structures sont correctement
# remplies. Il ne dira jamais si une LED s'allume. Cela reste le travail du
# sprint 3.3, sur le matériel réel.

set -euo pipefail

QEMU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${QEMU_DIR}/.." && pwd)"
IMAGES_DIR="${QEMU_DIR}/images"
RUN_DIR="${QEMU_DIR}/run"
LOGS_DIR="${QEMU_DIR}/logs"
SSH_DIR="${QEMU_DIR}/ssh"
BUILD_DIR="${QEMU_DIR}/build"

# Image cloud FreeBSD amd64 (UFS + cloud-init).
FREEBSD_VERSION="15.0-RELEASE"
FREEBSD_IMAGE_BASENAME="FreeBSD-${FREEBSD_VERSION}-amd64-BASIC-CLOUDINIT-ufs.qcow2"
FREEBSD_IMAGE_URL="https://download.freebsd.org/releases/VM-IMAGES/${FREEBSD_VERSION}/amd64/Latest/${FREEBSD_IMAGE_BASENAME}.xz"
FREEBSD_IMAGE_XZ="${IMAGES_DIR}/${FREEBSD_IMAGE_BASENAME}.xz"
FREEBSD_IMAGE_QCOW2="${IMAGES_DIR}/${FREEBSD_IMAGE_BASENAME}"

BUILDER_DISK="${RUN_DIR}/builder.qcow2"
BUILDER_SEED="${RUN_DIR}/builder-seed.iso"
BUILDER_PIDFILE="${RUN_DIR}/builder.pid"
BUILDER_LOG="${LOGS_DIR}/builder.log"

# Port 2224 : 2222 et 2223 sont pris par le banc clevis-zfs, les deux
# doivent pouvoir tourner en même temps.
BUILDER_SSH_PORT="2224"

# L'émulation TCG n'a pas d'accélération : plus de cœurs aident réellement.
VM_CPUS="4"
VM_MEM="2048"

QEMU_BIN="$(command -v qemu-system-x86_64 || true)"
EDK2_FIRMWARE="/opt/homebrew/share/qemu/edk2-x86_64-code.fd"

SSH_KEY="${SSH_DIR}/id_ed25519"

ensure_dirs() {
  mkdir -p "${IMAGES_DIR}" "${RUN_DIR}" "${LOGS_DIR}" "${SSH_DIR}" "${BUILD_DIR}"
}

require_qemu() {
  if [[ -z "${QEMU_BIN}" ]]; then
    echo "[erreur] qemu-system-x86_64 introuvable." >&2
    echo "         Installation : brew install qemu" >&2
    exit 1
  fi
  if [[ ! -f "${EDK2_FIRMWARE}" ]]; then
    echo "[erreur] firmware EDK2 introuvable : ${EDK2_FIRMWARE}" >&2
    echo "         Ajuster EDK2_FIRMWARE dans lib/common.sh." >&2
    exit 1
  fi
}

ensure_ssh_key() {
  ensure_dirs
  if [[ ! -f "${SSH_KEY}" ]]; then
    ssh-keygen -t ed25519 -N "" -f "${SSH_KEY}" -C "ugreen-hal-qemu" >/dev/null
    echo "[ssh] paire de clés générée : ${SSH_KEY}"
  fi
}

run_ssh() {
  ssh \
    -i "${SSH_KEY}" \
    -p "${BUILDER_SSH_PORT}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o ConnectTimeout=5 \
    freebsd@127.0.0.1 \
    "$@"
}

run_scp() {
  scp \
    -i "${SSH_KEY}" \
    -P "${BUILDER_SSH_PORT}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    "$@"
}

# Attente du SSH. Le délai par défaut est généreux : sous TCG, sans
# accélération matérielle, le démarrage de FreeBSD prend plusieurs minutes.
wait_for_ssh() {
  local timeout="${1:-600}"
  local start
  start="$(date +%s)"

  echo "[vm] attente du SSH (jusqu'à ${timeout}s — l'émulation est lente)"
  while true; do
    if run_ssh "true" 2>/dev/null; then
      echo "[vm] SSH disponible"
      return 0
    fi
    local now
    now="$(date +%s)"
    if (( now - start > timeout )); then
      echo "[vm] délai dépassé après ${timeout}s." >&2
      echo "     Journal de démarrage : ${BUILDER_LOG}" >&2
      return 1
    fi
    sleep 5
  done
}

vm_alive() {
  [[ -f "${BUILDER_PIDFILE}" ]] && kill -0 "$(cat "${BUILDER_PIDFILE}")" 2>/dev/null
}
