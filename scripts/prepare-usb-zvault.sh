#!/bin/sh
#
# prepare-usb-zvault.sh — prépare une clé USB bootable zVault (macOS)
#
# STATUT : commandes vérifiées contre le guide d'installation officiel
# (github.com/zvaultio/Community/wiki/zVault-Installation), non encore
# testées de bout en bout sur le matériel réel (à faire au sprint 1/2,
# dès réception du matériel réseau).
#
# ATTENTION : ce script est un GUIDE COMMENTÉ, pas un script automatique.
# L'écriture d'une image sur un périphérique bloc avec dd est destructrice
# et irréversible si la mauvaise cible est choisie. Il ne doit être exécuté
# qu'à la main, étape par étape, avec vérification du device node à chaque
# fois — jamais lancé tel quel sans relecture.

set -eu

# 1. Télécharger l'image ISO officielle (à faire une seule fois) :
#    https://github.com/zvaultio/Community/releases/tag/zVault-13.3-MASTER-202505042329-ca844f8808
#    Vérifier sur cette page qu'une version plus récente n'a pas été publiée
#    entre-temps.
ZVAULT_ISO="${ZVAULT_ISO:-zVault-13.3-MASTER-202505042329-ca844f8808.iso}"

echo "prepare-usb-zvault.sh : ce script ne fait qu'afficher la procédure." >&2
echo "Image attendue : ${ZVAULT_ISO}" >&2
echo >&2
cat >&2 <<'PROC_EOF'
Procédure (à exécuter à la main dans le Terminal macOS, PAS via ce script) :

  # 1. Lister les disques AVANT de brancher la clé USB
  diskutil list

  # 2. Brancher la clé USB, puis relister pour repérer le nouveau périphérique
  diskutil list
  # -> noter le nom exact, ex. /dev/disk4 (le disque ENTIER, pas /dev/disk4s1)

  # 3. Vérifier une deuxième fois qu'il s'agit bien de la clé USB de test,
  #    jamais du disque interne du Mac.

  # 4. Écrire l'image (opération destructrice, sans confirmation ni retour
  #    arrière possible) :
  sudo dd if=zVault-13.3-MASTER-202505042329-ca844f8808.iso of=/dev/diskN bs=1M conv=sync

Source : github.com/zvaultio/Community/wiki/zVault-Installation (15/07/2026)
PROC_EOF

exit 1
