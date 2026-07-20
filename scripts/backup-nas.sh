#!/bin/sh
#
# backup-nas.sh — cloner l'eMMC interne (UGOS) du DXP2800 avant toute
#                 manipulation du stockage interne
#
# STATUT : guide commenté vérifié sur documentation, non encore exécuté sur
# le matériel réel. À dérouler à la main, étape par étape.
#
# POURQUOI CE CLONE RESTE RECOMMANDÉ (nuancé le 20/07/2026)
# ----------------------------------------------------------
# Formulation précédente corrigée : ce document affirmait qu'aucune image
# de restauration n'existait. C'est trop catégorique. UGREEN publie bien un
# « System Firmware » téléchargeable par modèle (ai.ugreen.com/pages/downloads),
# au format .img, et au moins un utilisateur le décrit comme remplaçant le
# système en place par UGOS, pas comme un simple correctif applicatif.
#
# Ce qui reste incertain, et justifie le clone malgré tout :
#  - La page officielle en parle comme d'une MISE À JOUR (« Use online update
#    unless you specifically need a local firmware package », « confirm the
#    update direction ») : vocabulaire d'un système déjà en place, pas d'une
#    restauration à nu.
#  - Aucun rapport public consulté ne confirme une restauration réussie
#    depuis un eMMC réellement effacé. Le fil dédié au DXP2800 se conclut
#    sur « You should ask them ».
#  - Plusieurs sources indiquent qu'en cas de corruption totale, le fichier
#    est fourni par le support UGREEN et lié au numéro de série.
#  - L'eMMC contient des partitions propres à l'exemplaire (UGREEN-SERVICE,
#    USER-DATA) et les partitions de démarrage boot0/boot1, qu'une image
#    générique de modèle ne reproduit pas nécessairement à l'identique.
#
# Autrement dit : le retour à UGOS est probablement possible sans ce clone,
# mais ce « probablement » n'a été vérifié par personne. Le clone coûte une
# soirée et quelques Go ; le vérifier à ses dépens coûterait le NAS.
#
# Sources : https://ai.ugreen.com/pages/downloads
#           https://forums.truenas.com/t/how-to-update-dxp2800-system-firmware-downloaded-img-file-from-nas-ugreen-com-pages-downloads/62041
#           https://forums.truenas.com/t/actual-installs-on-ugreen-hardware-observations-experiences-tips/6910
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
  # 2bis. DIMENSIONNER LE SUPPORT DE DESTINATION
  # ---------------------------------------------------------------
  # L'eMMC fait 29,2 Gio (~31,4 Go commerciaux). Conséquences selon le
  # support choisi :
  #
  #  - Clé USB « 32 Go » : offre ~29,7 Gio utiles après formatage. Une
  #    image BRUTE y tiendrait de justesse (marge ~500 Mio), une image
  #    COMPRESSÉE largement. Viable, mais voir les deux pièges ci-dessous.
  #  - Disque externe 500 Go / 1 To : aucun souci, option préférable.
  #
  # PIÈGE 1 — FAT32 : les clés USB sont formatées en FAT32 d'usine, dont la
  # taille maximale par FICHIER est de 4 Gio. Une image de 29 Gio ne peut
  # pas y être écrite : dd s'interrompt à 4 Gio sur une erreur d'écriture,
  # après de longues minutes de copie. Reformater en exFAT (lisible partout)
  # ou en ext4 (si relecture sous Linux uniquement) AVANT de commencer :
  #     mkfs.exfat -n SAUVEGARDE-UGOS /dev/sdXN
  # Vérifier le système de fichiers réellement en place :
  #     lsblk -f /dev/sdX
  #
  # PIÈGE 2 — le pari de la compression : l'eMMC est quasi vide, donc zstd
  # devrait ramener l'image à quelques Go. Mais dd lit TOUS les blocs, y
  # compris l'espace libre : le gain n'est réel que si cet espace contient
  # des zéros. Sur un appareil neuf c'est probable, pas certain. Surveiller
  # la taille du fichier pendant la copie (voir étape 5) plutôt que de le
  # découvrir en fin de course.
  #
  # Repli si le support s'avère trop petit : découper l'image compressée en
  # tranches, ce qui permet aussi de rester en FAT32 :
  #     dd if=/dev/mmcblk0 bs=4M | zstd -3 | split -b 3G - ugos-emmc.img.zst.
  # (reconstruction : cat ugos-emmc.img.zst.* | zstd -d > ugos-emmc.img)
  #
  # Dans tous les cas, une clé USB n'est pas un support d'archivage durable :
  # recopier l'image sur le Mac une fois l'opération terminée.

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

  # Depuis un second terminal (Alt-F2 sous SystemRescue), surveiller que la
  # taille du fichier compressé reste compatible avec l'espace disponible —
  # utile surtout sur une clé de 32 Go, où la marge est faible :
  #     watch -n 30 'ls -lh ugos-emmc.img.zst; df -h /mnt/backup'

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
la clé zVault (voir prepare-usb.cr) sans risque de perte définitive.
PROC_EOF

exit 1
