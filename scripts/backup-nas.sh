#!/bin/sh
#
# backup-nas.sh — sauvegarde de précaution avant toute manipulation du DXP2800
#
# STATUT : squelette non testé. À valider et compléter au sprint 0/1,
# une fois l'accès réseau stable au NAS de test disponible.
#
# Objectif : sauvegarder l'eMMC interne (ou au minimum les partitions
# UGREEN-SERVICE et USER-DATA identifiées dans docs/hardware-notes.adoc)
# vers le disque externe de sauvegarde prévu au plan, avant tout
# remplacement de firmware.

set -eu

# TODO(sprint 0) : renseigner l'adresse/le nom d'hôte du NAS une fois le
# réseau (pont GL-SFT1200) opérationnel.
NAS_HOST="${NAS_HOST:-dxp2800.local}"

# TODO(sprint 0) : renseigner le point de montage du disque externe de
# sauvegarde une fois branché sur la machine faisant office de relais.
BACKUP_DEST="${BACKUP_DEST:-/mnt/backup-ugreen}"

echo "backup-nas.sh : squelette non implémenté (TODO sprint 0/1)." >&2
echo "Cible NAS      : ${NAS_HOST}" >&2
echo "Destination    : ${BACKUP_DEST}" >&2
exit 1
