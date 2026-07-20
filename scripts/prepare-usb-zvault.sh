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
  #    jamais du disque interne du Mac. Contrôler la taille affichée.

  # 4. Démonter les systèmes de fichiers, sans éjecter le périphérique
  diskutil unmountDisk /dev/diskN

  # 5. Écrire l'image (opération destructrice, sans confirmation ni retour
  #    arrière possible) :
  sudo dd if=zVault-13.3-MASTER-202505042329-ca844f8808.iso of=/dev/diskN bs=1M conv=sync
  #
  # Variante plus rapide (ajout du 20/07/2026, hors procédure officielle) :
  # sur macOS, /dev/rdiskN est le périphérique en accès brut, dix à vingt
  # fois plus rapide que /dev/diskN :
  #     sudo dd if=zVault-....iso of=/dev/rdiskN bs=1m status=progress

  # 6. Éjecter proprement
  sync
  diskutil eject /dev/diskN

Source : github.com/zvaultio/Community/wiki/zVault-Installation (15/07/2026)

ÉTAT DE LA VERSION (vérifié le 20/07/2026)
  La release 13.3-MASTER-202505042329-ca844f8808 (04/05/2025) reste la plus
  récente publiée : aucune nouvelle version en quatorze mois. À rapprocher
  du risque de gouvernance documenté dans le plan de projet — le projet
  n'est pas abandonné pour autant, mais son rythme de publication est à
  surveiller.

ORDRE DES OPÉRATIONS
  Cette clé sert au sprint 2 (démarrage externe). Elle vient APRÈS la clé
  SystemRescue et le clone de l'eMMC (voir prepare-usb-systemrescue.sh puis
  backup-nas.sh), qui doivent être faits tant que le stockage interne est
  encore intact.
PROC_EOF

exit 1
