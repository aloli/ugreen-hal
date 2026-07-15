#!/bin/sh
#
# prepare-usb-zvault.sh — prépare une clé USB/SSD externe bootable zVault
#
# STATUT : squelette non testé. À valider au sprint 1, une fois une image
# zVault téléchargée et le support USB de test reçu.
#
# Objectif : écrire une image zVault sur le support USB de test dédié
# (voir « Matériel complémentaire à prévoir » dans le plan de projet),
# sans jamais cibler par erreur l'eMMC interne du NAS ou le disque
# principal de la machine hôte.

set -eu

# TODO(sprint 1) : renseigner le chemin de l'image zVault téléchargée.
ZVAULT_IMAGE="${ZVAULT_IMAGE:-}"

# TODO(sprint 1) : renseigner le device cible (ex. /dev/diskN sous macOS,
# /dev/sdX sous Linux) — à vérifier trois fois avant tout dd/écriture,
# aucune confirmation automatique ne doit être ajoutée à ce script.
TARGET_DEVICE="${TARGET_DEVICE:-}"

if [ -z "${ZVAULT_IMAGE}" ] || [ -z "${TARGET_DEVICE}" ]; then
	echo "prepare-usb-zvault.sh : squelette non implémenté (TODO sprint 1)." >&2
	echo "Renseigner ZVAULT_IMAGE et TARGET_DEVICE avant utilisation." >&2
	exit 1
fi

echo "prepare-usb-zvault.sh : squelette non implémenté (TODO sprint 1)." >&2
exit 1
