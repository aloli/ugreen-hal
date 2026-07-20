#!/bin/sh
#
# backup-nas.sh — cloner l'eMMC interne (UGOS) du DXP2800 avant toute
#                 manipulation du stockage interne
#
# STATUT : guide commenté vérifié sur documentation, non encore exécuté sur
# le matériel réel. À dérouler à la main, étape par étape.
#
# POURQUOI CE CLONE EST OBLIGATOIRE
# ---------------------------------
# UGREEN ne publie aucune image de restauration d'UGOS. Les utilisateurs
# ayant installé d'autres systèmes sur ce matériel clonent le stockage
# interne avant de le remplacer ; une éventuelle image constructeur serait
# spécifique au numéro de série de l'appareil. Sans clone préalable, le
# retour à UGOS est définitivement perdu.
# Source : forum TrueNAS, « Actual installs on uGreen hardware »
# https://forums.truenas.com/t/actual-installs-on-ugreen-hardware-observations-experiences-tips/6910
#
# POURQUOI PAS EN SSH DEPUIS UGOS
# -------------------------------
# Cloner un système de fichiers monté et en cours d'écriture produit une
# image incohérente (fichiers à moitié écrits, journal ext4 non rejoué).
# Le clone doit être fait *hors ligne*, depuis un système live démarré sur
# clé USB, l'eMMC n'étant alors pas montée.
#
# POURQUOI UN LIVE LINUX ET NON ZVAULT
# ------------------------------------
# Le stockage interne est de l'eMMC (mmc0, MMC32G, 29,2 Gio — voir
# docs/hardware-notes.adoc). Linux le pilote de façon certaine : UGOS
# tourne dessus et l'expose comme /dev/mmcblk0. Le support FreeBSD des
# contrôleurs eMMC sur cette plateforme n'est pas vérifié à ce jour ; ce
# n'est donc pas l'outil à choisir pour une opération que l'on ne veut
# faire qu'une fois. Un live SystemRescue (ou Ubuntu) fait le travail.
#
# ATTENTION : ce script est un GUIDE, pas un automate. La lecture de
# l'eMMC est inoffensive, mais l'écriture vers le disque externe ne l'est
# pas : se tromper de cible détruirait le contenu du disque de sauvegarde.
# Chaque device node doit être vérifié à l'œil avant chaque commande.

set -eu

echo "backup-nas.sh : ce script ne fait qu'afficher la procédure." >&2
echo >&2
cat >&2 <<'PROC_EOF'
Procédure (à dérouler sur le NAS, depuis un live Linux, PAS via ce script) :

  # ---------------------------------------------------------------
  # 0. AVANT D'ALLUMER — préparation
  # ---------------------------------------------------------------
  # - Clé USB avec un live Linux (SystemRescue conseillé : léger, embarque
  #   dd, ddrescue, zstd, sha256sum, gdisk).
  # - Disque externe de sauvegarde branché, formaté, AUCUNE donnée à perdre
  #   dessus.
  # - Écran HDMI + clavier USB branchés sur le NAS.

  # ---------------------------------------------------------------
  # 1. BIOS (touche Ctrl-F12 au démarrage, à confirmer)
  # ---------------------------------------------------------------
  # - DÉSACTIVER LE WATCHDOG. Le chip IT8613 redémarre la machine au bout
  #   de 20 minutes si aucun système ne le nourrit : un clone de 32 Gio
  #   peut dépasser ce délai et serait interrompu en plein vol.
  # - Régler l'ordre de démarrage sur la clé USB.

  # ---------------------------------------------------------------
  # 2. IDENTIFIER LES PÉRIPHÉRIQUES (une fois le live démarré)
  # ---------------------------------------------------------------
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL

  # Attendu, d'après docs/hardware-notes.adoc :
  #   mmcblk0      29.2G  disk           <- l'eMMC UGOS, LA SOURCE
  #     mmcblk0p1 ... p8, p128           <- ses partitions
  #     (dont p6 = UGREEN-SERVICE, p7 = USER-DATA)
  #   sda/sdb      ...    disk           <- clé USB live et disque externe
  #
  # Vérifier que l'eMMC n'est PAS montée (colonne MOUNTPOINT vide) :
  mount | grep mmcblk0 || echo "OK : eMMC non montée"

  # ---------------------------------------------------------------
  # 3. MONTER LE DISQUE EXTERNE (et lui seul en écriture)
  # ---------------------------------------------------------------
  mkdir -p /mnt/backup
  mount /dev/sdXN /mnt/backup        # <- adapter, vérifier deux fois
  df -h /mnt/backup                  # doit montrer l'espace du disque externe

  # ---------------------------------------------------------------
  # 4. RELEVÉS DE CONTEXTE (rapides, précieux plus tard)
  # ---------------------------------------------------------------
  cd /mnt/backup
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL,UUID > lsblk.txt
  sfdisk -d /dev/mmcblk0             > partitions-mmcblk0.txt
  dmidecode                          > dmidecode.txt
  cat /proc/cmdline                  > cmdline.txt

  # ---------------------------------------------------------------
  # 5. LE CLONE (lecture seule côté NAS — opération longue)
  # ---------------------------------------------------------------
  # L'eMMC fait 29,2 Gio mais est très majoritairement vide : la
  # compression ramène l'image à quelques Gio. zstd -3 est un bon
  # compromis vitesse/taille ; remplacer par `gzip` si zstd est absent.
  dd if=/dev/mmcblk0 bs=4M status=progress | zstd -3 -o ugos-emmc.img.zst

  # Les partitions de démarrage eMMC (boot0/boot1) sont distinctes du
  # disque principal et contiennent le chargeur — les prendre aussi :
  dd if=/dev/mmcblk0boot0 bs=4M of=ugos-emmc-boot0.img
  dd if=/dev/mmcblk0boot1 bs=4M of=ugos-emmc-boot1.img

  # ---------------------------------------------------------------
  # 6. VÉRIFIER (ne jamais sauter cette étape)
  # ---------------------------------------------------------------
  # Empreinte de la source :
  sha256sum /dev/mmcblk0 | tee sha256-source.txt

  # Empreinte de l'image décompressée : les deux doivent être IDENTIQUES.
  zstd -dc ugos-emmc.img.zst | sha256sum | tee sha256-image.txt

  # Si les deux empreintes diffèrent, l'image est inutilisable : recommencer
  # (cause probable : eMMC montée pendant la copie, ou watchdog non désactivé).

  sync
  cd /
  umount /mnt/backup

  # ---------------------------------------------------------------
  # 7. RANGER LA SAUVEGARDE
  # ---------------------------------------------------------------
  # Ce disque ne doit servir qu'à ça : ni support de démarrage, ni support
  # d'exécution zVault. Consigner dans docs/journal.adoc la date, la taille
  # de l'image et l'empreinte sha256 obtenue.

Une fois cette étape validée, et elle seule, le NAS peut être démarré sur
la clé zVault (voir prepare-usb-zvault.sh) sans risque de perte définitive.
PROC_EOF

exit 1
