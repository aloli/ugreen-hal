#!/bin/sh
#
# prepare-usb-systemrescue.sh — préparer la clé USB « live Linux » (macOS)
#
# STATUT : commandes vérifiées contre la documentation officielle du projet
# (system-rescue.org), non encore exécutées de bout en bout.
#
# À QUOI SERT CETTE CLÉ
# ---------------------
# C'est la clé de SAUVEGARDE, distincte de la clé d'installation zVault
# (voir prepare-usb-zvault.sh). Elle sert à démarrer le DXP2800 sur un
# système Linux vivant, eMMC non montée, pour en faire le clone avant
# toute écriture sur le stockage interne — voir backup-nas.sh.
#
# Pourquoi Linux et non la clé zVault : le stockage interne est de l'eMMC
# (mmc0, MMC32G, 29,2 Gio). Linux le pilote de façon certaine, UGOS tournant
# dessus et l'exposant comme /dev/mmcblk0. Le support FreeBSD des
# contrôleurs eMMC sur cette plateforme n'est pas vérifié : ce n'est pas
# l'endroit où prendre ce risque.
#
# ATTENTION : ce script est un GUIDE, pas un automate. dd écrase
# intégralement le périphérique cible, sans confirmation ni corbeille.
# Vérifier le device node à chaque étape, deux fois plutôt qu'une.

set -eu

SRC_VERSION="${SRC_VERSION:-13.01}"
SRC_ISO="${SRC_ISO:-systemrescue-${SRC_VERSION}-amd64.iso}"

echo "prepare-usb-systemrescue.sh : ce script ne fait qu'afficher la procédure." >&2
echo "Version visée : SystemRescue ${SRC_VERSION} (${SRC_ISO})" >&2
echo >&2
cat >&2 <<'PROC_EOF'
Procédure (à exécuter à la main dans le Terminal macOS, PAS via ce script) :

  # ---------------------------------------------------------------
  # 1. TÉLÉCHARGER L'IMAGE
  # ---------------------------------------------------------------
  # Page officielle : https://www.system-rescue.org/Download/
  # Version courante au 20/07/2026 : 13.01 (publiée le 06/06/2026,
  # noyau LTS 6.18.34). Vérifier sur la page qu'une version plus récente
  # n'est pas disponible.
  #
  # Choisir l'image « amd64 » : le DXP2800 est un x86_64 (Intel N100).

  # ---------------------------------------------------------------
  # 2. VÉRIFIER L'EMPREINTE (ne pas sauter : une ISO tronquée produit
  #    une clé qui démarre à moitié, symptôme difficile à diagnostiquer)
  # ---------------------------------------------------------------
  # Le projet publie un fichier .sha256 à côté de l'ISO.
  shasum -a 256 systemrescue-13.01-amd64.iso
  # Comparer à la valeur publiée sur system-rescue.org.

  # ---------------------------------------------------------------
  # 3. IDENTIFIER LA CLÉ USB
  # ---------------------------------------------------------------
  diskutil list                 # AVANT de brancher la clé
  # ... brancher la clé ...
  diskutil list                 # APRÈS : repérer le périphérique apparu
  #
  # Noter le disque ENTIER (/dev/disk4), jamais une partition
  # (/dev/disk4s1). Vérifier la taille affichée : elle doit correspondre
  # à celle de la clé, pas à celle du disque interne du Mac.

  # ---------------------------------------------------------------
  # 4. DÉMONTER (sans éjecter)
  # ---------------------------------------------------------------
  diskutil unmountDisk /dev/diskN
  # « unmountDisk » démonte les systèmes de fichiers en laissant le
  # périphérique accessible à dd. « eject » le retirerait complètement.

  # ---------------------------------------------------------------
  # 5. ÉCRIRE L'IMAGE  (opération destructrice et irréversible)
  # ---------------------------------------------------------------
  # Noter le « r » de /dev/rdiskN : c'est le périphérique en accès brut,
  # dix à vingt fois plus rapide que /dev/diskN sur macOS.
  sudo dd if=systemrescue-13.01-amd64.iso of=/dev/rdiskN bs=1m status=progress
  #
  # L'ISO de SystemRescue est hybride (isohybrid) : elle démarre telle
  # quelle en USB, en UEFI comme en BIOS hérité. Aucun outil de gravure
  # particulier n'est nécessaire.

  sync
  diskutil eject /dev/diskN

  # ---------------------------------------------------------------
  # 6. AU DÉMARRAGE SUR LE NAS
  # ---------------------------------------------------------------
  # - Touche BIOS : Ctrl-F12 (annoncée, à confirmer par observation).
  # - DÉSACTIVER LE WATCHDOG dans le BIOS avant de lancer le clone : le
  #   chip IT8613 redémarre la machine au bout de 20 minutes si aucun
  #   système ne le nourrit, et un clone de 32 Gio peut dépasser ce délai.
  # - Au menu de SystemRescue, l'entrée par défaut convient.
  # - Disposition clavier : SystemRescue démarre en QWERTY US, ce qui
  #   correspond au matériel utilisé sur ce projet. Rien à changer.
  #   (Pour une autre disposition : loadkeys fr, loadkeys be, etc.)
  #
  # Enchaîner ensuite sur la procédure de backup-nas.sh.
PROC_EOF

exit 1
