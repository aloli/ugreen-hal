#!/usr/bin/env bash
# Démarre la VM avec la console série attachée au terminal.
#
# Utile pour les images sans cloud-init (FreeBSD 13 et antérieurs), qui
# doivent être provisionnées à la main : activer sshd et autoriser la clé
# du banc. Une seule fois par disque — ensuite, 10-run.sh suffit.
#
# Aussi utile pour diagnostiquer un démarrage qui n'aboutit pas : on voit
# défiler ce que 10-run.sh se contente d'écrire dans logs/builder.log.
#
# Pour quitter QEMU depuis la console série : Ctrl-A puis X.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ensure_dirs
require_qemu

if vm_alive; then
  echo "[vm] déjà démarrée en tâche de fond (pid $(cat "${BUILDER_PIDFILE}"))" >&2
  echo "     l'arrêter d'abord : ./99-stop.sh" >&2
  exit 1
fi

if [[ ! -f "${BUILDER_DISK}" ]]; then
  echo "[vm] disque absent, lancer 01-prepare-vm.sh" >&2
  exit 1
fi

firmware_args=()
if [[ "${FIRMWARE}" == "uefi" ]]; then
  firmware_args=(
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${EDK2_CODE}"
    -drive "if=pflash,format=raw,unit=1,file=${BUILDER_VARS}"
  )
fi

seed_args=()
if [[ -f "${BUILDER_SEED}" ]]; then
  seed_args=(-drive "if=virtio,format=raw,readonly=on,file=${BUILDER_SEED}")
fi

echo "[vm] console série attachée — Ctrl-A puis X pour quitter QEMU"
echo "[vm] émulation TCG sans accélération : comptez plusieurs minutes"
echo

exec "${QEMU_BIN}" \
  -name ugreen-hal-builder \
  -machine q35 \
  -accel tcg \
  -cpu qemu64 \
  -smp "${VM_CPUS}" \
  -m "${VM_MEM}" \
  "${firmware_args[@]}" \
  -drive if=virtio,format=qcow2,file="${BUILDER_DISK}" \
  "${seed_args[@]}" \
  -netdev user,id=net0,hostfwd=tcp::"${BUILDER_SSH_PORT}"-:22 \
  -device virtio-net-pci,netdev=net0 \
  -display none \
  -serial mon:stdio
