#!/bin/sh
#
# systemrescue-restore.sh — remet une session SystemRescue live en état
# après un redémarrage du NAS.
#
# SystemRescue est un environnement live en RAM : rien de ce qui est
# installé ou configuré (paquets, modules, pare-feu, clés SSH) ne survit
# à un redémarrage. Seuls les réglages du BIOS (watchdog, Secure Boot,
# tous deux désactivés) sont persistants. Ce script rejoue en une fois ce
# qu'il a fallu découvrir pas à pas lors de la première séance
# (2026-07-29) — voir docs/journal.adoc et docs/essai-terrain.adoc.
#
# Usage, une fois SystemRescue démarré et le câble réseau branché sur le
# pont GL.iNet Flint déjà configuré (voir docs/reseau-banc.adoc) :
#
#   curl -sL https://raw.githubusercontent.com/aloli/ugreen-hal/development/scripts/systemrescue-restore.sh | sh
#
# Le réseau n'a besoin d'aucune configuration manuelle au préalable :
# SystemRescue obtient une adresse par DHCP dès que le câble est branché,
# ce qui suffit à exécuter ce script par curl avant toute autre étape.
#
# Toutes les commandes ci-dessous sont volontairement NON interactives :
# un script tuyauté via `curl | sh` a son entrée standard déjà occupée par
# le corps du script lui-même — le moindre prompt interactif (comme
# `passwd`) lirait la suite du script en guise de réponse et casserait
# tout. C'est pourquoi l'accès SSH se fait par clé publique et non par
# mot de passe.

set -eu

echo "[restore] chargement des modules SMBus/i2c"
# Deux appels séparés, et non `modprobe i2c-i801 i2c-dev` en une seule
# commande : constaté sur le terrain le 30/07/2026, cette forme groupée
# retourne un succès (code 0) sans charger i2c-dev, laissant i2c-i801
# seul attaché — /dev/i2c-* reste absent sans message d'erreur.
modprobe i2c-i801
modprobe i2c-dev

echo "[restore] pare-feu par défaut de l'image live : vidé"
# nftables rejette le port 22 par défaut, avec un message trompeur côté
# client (« No route to host » plutôt qu'un refus net) qui n'a rien à
# voir avec un problème de routage — piège rencontré le 28/07/2026.
nft flush ruleset 2>/dev/null || true

echo "[restore] accès SSH par clé dédiée (pas de mot de passe root)"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat >> /root/.ssh/authorized_keys <<'KEY'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICunMlx4hCLoOAjoeZQhtr7x5DKwxHbgb0Ouq1BK240x ugreen-hal-nas-bench
KEY
chmod 600 /root/.ssh/authorized_keys
systemctl enable --now sshd

echo "[restore] installation de i2c-tools"
pacman -Sy --noconfirm i2c-tools

echo "[restore] contrôleur SMBus vu par le noyau"
lspci -nn | grep -i smbus || echo "  (introuvable — vérifier lspci -nn en entier)"

echo "[restore] repérage automatique du bus SMBus I801"
bus="$(i2cdetect -l | awk '/I801/ {print $1}' | sed 's/i2c-//')"

if [ -z "${bus}" ]; then
  # Ne pas se contenter d'un message d'échec laconique : sans la sortie
  # brute, impossible de savoir si i2c-dev n'a pas chargé, si i2c-i801
  # n'a pas attaché, ou si le nom de l'adaptateur diffère simplement de
  # ce qui est attendu.
  echo "  Bus SMBus I801 introuvable. Diagnostic :" >&2
  echo "  --- i2cdetect -l ---" >&2
  i2cdetect -l >&2
  echo "  --- modules i2c chargés ---" >&2
  lsmod | grep -i i2c >&2 || echo "  (aucun)" >&2
  echo "  --- dmesg (i2c/i801/smbus) ---" >&2
  dmesg | grep -iE 'i2c|i801|smbus' >&2 || echo "  (rien)" >&2
else
  echo "  bus détecté : i2c-${bus}"
  echo "[restore] scan i2c (adresse 0x3a attendue pour le contrôleur LED)"
  i2cdetect -y -r "${bus}"
  echo
  echo "[restore] prochaine commande à tenter :"
  echo "  i2ctransfer -y ${bus} w1@0x3a 0x81 r11@0x3a"
fi

echo
echo "[restore] terminé."

# Adresse IPv4 de portée globale (exclut loopback et link-local sans
# avoir à connaître le nom de l'interface, qui peut varier).
nas_ip="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"

if [ -n "${nas_ip}" ]; then
  echo "  Adresse de ce NAS : ${nas_ip}"
  echo "  Connexion depuis la racine du dépôt ugreen-hal, sur le Mac :"
  echo "    ssh -i scripts/nas-ssh/id_ed25519 root@${nas_ip}"
else
  echo "  Adresse IP non détectée automatiquement — voir : ip -br a"
fi
