#!/usr/bin/env bash
# Démarre la VM de compilation en tâche de fond.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ensure_dirs
require_qemu

if vm_alive; then
  echo "[vm] déjà démarrée (pid $(cat "${BUILDER_PIDFILE}"))"
  exit 0
fi

if [[ ! -f "${BUILDER_DISK}" ]]; then
  echo "[vm] disque absent, lancer 01-prepare-vm.sh" >&2
  exit 1
fi

echo "[vm] démarrage de QEMU (SSH hôte sur :${BUILDER_SSH_PORT})"
echo "[vm] émulation TCG sans accélération : comptez plusieurs minutes"

# -accel tcg est explicite plutôt qu'implicite : sur un Mac Apple Silicon,
# HVF ne peut pas accélérer de l'amd64, et une erreur silencieuse de
# repli serait plus déroutante qu'un choix assumé.
"${QEMU_BIN}" \
  -name ugreen-hal-builder \
  -machine q35 \
  -accel tcg \
  -cpu qemu64 \
  -smp "${VM_CPUS}" \
  -m "${VM_MEM}" \
  -bios "${EDK2_FIRMWARE}" \
  -drive if=virtio,format=qcow2,file="${BUILDER_DISK}" \
  -drive if=virtio,format=raw,readonly=on,file="${BUILDER_SEED}" \
  -netdev user,id=net0,hostfwd=tcp::"${BUILDER_SSH_PORT}"-:22 \
  -device virtio-net-pci,netdev=net0 \
  -display none \
  -serial file:"${BUILDER_LOG}" \
  -pidfile "${BUILDER_PIDFILE}" \
  -daemonize

echo "[vm] PID $(cat "${BUILDER_PIDFILE}"), journal : ${BUILDER_LOG}"
echo "[vm] suivre le démarrage : tail -f ${BUILDER_LOG}"
