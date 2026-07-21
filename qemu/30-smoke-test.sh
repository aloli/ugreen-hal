#!/usr/bin/env bash
# Exerce ugreen-led-ctl dans la VM, sans avoir à s'y connecter à la main.
#
# Découverte du 21/07/2026 : la machine q35 de QEMU émule un contrôleur
# SMBus ICH9, auquel ichsmb(4) s'attache — le pilote même que vise le code
# sur le DXP2800. On peut donc valider ici toute la plomberie :
#
#   - le device node /dev/smb0 existe et s'ouvre ;
#   - le noyau accepte nos ioctls SMB_BWRITE et SMB_BREAD ;
#   - l'absence de réponse à l'adresse 0x74 remonte proprement, plutôt
#     que de planter ou de rester silencieuse.
#
# Ce qui reste hors de portée, et le restera : la réponse du
# microcontrôleur UGREEN. Aucun périphérique ne répond à 0x74 dans une VM.
# L'échec attendu ici est donc un SUCCÈS du test — ce qu'on vérifie, c'est
# la qualité du message d'erreur, pas l'allumage d'une LED.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

if ! vm_alive; then
  echo "[test] VM non démarrée, lancer 10-run.sh" >&2
  exit 1
fi

wait_for_ssh

section() {
  echo
  echo "=== $1"
}

section "Contrôleur SMBus vu par le noyau"
run_ssh "dmesg | grep -iE 'ichsmb|smbus' || echo '(aucune ligne smbus)'"

section "Chargement du module smb(4)"
# Ne PAS masquer l'erreur de kldload : c'est elle qui explique l'absence
# de /dev/smb0. ichsmb(4) attache le contrôleur et smbus(4) fournit le
# bus, mais aucun des deux n'expose de device node — c'est smb(4), un
# module distinct, qui crée /dev/smbN.
#
# sudo est indispensable : sans lui, kldload échoue sur « Operation not
# permitted », message qui évoque une restriction de sécurité du noyau
# (securelevel, MAC) alors qu'il ne s'agit que d'un manque de privilèges.
run_ssh "sudo kldload smb; echo \"kldload smb -> code \$?\""
run_ssh "ls -l /boot/kernel/smb.ko 2>&1 || echo '(module absent du noyau installé)'"
run_ssh "kldstat | grep -i smb || echo '(aucun module smb chargé)'"

section "Device nodes disponibles"
run_ssh "ls -l /dev/smb* 2>/dev/null || echo '(aucun /dev/smb* — smbus non exposé en espace utilisateur)'"

section "Aide du programme"
run_ssh "~/src-cli/ugreen-led-ctl 2>&1 | head -8" || true

section "Lecture d'état (échec attendu : rien ne répond à 0x74)"
run_ssh "sudo ~/src-cli/ugreen-led-ctl status power 2>&1" || true

section "Device inexistant (le message doit être explicite)"
run_ssh "sudo ~/src-cli/ugreen-led-ctl -d /dev/smb99 status power 2>&1" || true

cat <<'EOF'

--- Lecture des résultats ---

Ce qu'on VEUT voir :
  - ichsmb0 et smbus0 présents dans dmesg ;
  - /dev/smb0 existant ;
  - une erreur claire et nommée sur la lecture d'état, du type
    « SMB_BREAD (led 0): Device not configured » ou équivalent ;
  - un message parlant sur le device inexistant, pas un plantage.

Ce qui serait INQUIÉTANT :
  - une panique noyau ou un signal (le code écrirait hors des clous) ;
  - un succès silencieux : personne ne répond à 0x74 dans cette VM, donc
    un « status » qui réussirait signalerait que le programme invente ses
    données au lieu de les lire.
EOF
