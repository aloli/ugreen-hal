#!/usr/bin/env bash
# Prépare le disque de la VM de compilation et son ISO cloud-init.
#
# Le disque est une copie de l'image de base plutôt qu'un overlay qcow2 :
# cloud-init écrit dedans, et une copie franche rend la remise à zéro
# triviale (supprimer run/builder.qcow2 et relancer ce script).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ensure_dirs
ensure_ssh_key

if [[ ! -f "${FREEBSD_IMAGE_QCOW2}" ]]; then
  echo "[prepare] image de base absente, lancer 00-fetch-image.sh" >&2
  exit 1
fi

if [[ -f "${BUILDER_DISK}" ]]; then
  echo "[prepare] ${BUILDER_DISK} existe déjà, conservé"
else
  echo "[prepare] copie de l'image de base -> ${BUILDER_DISK}"
  cp "${FREEBSD_IMAGE_QCOW2}" "${BUILDER_DISK}"
  # De la marge pour les paquets et les objets de compilation.
  qemu-img resize "${BUILDER_DISK}" 8G >/dev/null
fi

# Le magasin de variables UEFI doit être inscriptible et propre à la VM :
# on part d'une copie du gabarit fourni par QEMU plutôt que de laisser le
# firmware écrire dans le fichier partagé de l'installation Homebrew.
if [[ "${FIRMWARE}" == "uefi" ]]; then
  if [[ -f "${BUILDER_VARS}" ]]; then
    echo "[prepare] magasin de variables UEFI déjà présent, conservé"
  else
    echo "[prepare] copie du magasin de variables UEFI"
    cp "${EDK2_VARS_TEMPLATE}" "${BUILDER_VARS}"
    chmod u+w "${BUILDER_VARS}"
  fi
fi

if [[ "${FREEBSD_HAS_CLOUDINIT}" != "yes" ]]; then
  cat <<EOF

[prepare] Image ${FREEBSD_VERSION} : PAS de cloud-init.

  Les images antérieures à FreeBSD 14 ne connaissent pas cloud-init : ni
  clé SSH ni nom d'hôte ne seront injectés, et 20-build.sh ne pourra pas
  se connecter tant que la VM n'aura pas été provisionnée à la main.

  Procédure, une seule fois par disque :

    1. ./10-run-console.sh        (console série, au lieu de 10-run.sh)
    2. se connecter en root, sans mot de passe
    3. dans la VM :
         sysrc sshd_enable=YES
         service sshd start
         mkdir -p /root/.ssh && chmod 700 /root/.ssh
         # coller la clé publique ci-dessous dans /root/.ssh/authorized_keys
    4. adapter run_ssh dans lib/common.sh pour viser root plutôt que freebsd

  Clé publique à autoriser :
$(cat "${SSH_KEY}.pub" 2>/dev/null | sed 's/^/    /')

  Pour la plupart des usages, préférer une image 14.x ou 15.x et compter
  sur l'édition de liens statique : c'est nettement moins de manipulation
  pour un risque comparable.

EOF
  echo "[prepare] terminé (sans ISO cloud-init)."
  ls -lh "${BUILDER_DISK}"
  exit 0
fi

echo "[prepare] construction de l'ISO cloud-init"

# Zone de préparation dans run/ plutôt que dans le répertoire temporaire du
# système : le banc reste ainsi entièrement contenu dans son propre dossier,
# sans dépendre de TMPDIR ni des politiques d'accès qui s'y appliquent.
stage="${RUN_DIR}/seed-stage"
rm -rf "${stage}"
mkdir -p "${stage}"
trap 'rm -rf "${stage}"' EXIT

cat > "${stage}/meta-data" <<EOF
instance-id: ugreen-hal-builder-1
local-hostname: ugreen-hal-builder
EOF

cat > "${stage}/user-data" <<EOF
#cloud-config
hostname: ugreen-hal-builder
fqdn: ugreen-hal-builder.local

# Les images cloud FreeBSD n'embarquent pas sudo.
package_update: true
packages:
  - sudo

users:
  - name: freebsd
    gecos: ugreen-hal build user
    shell: /bin/sh
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    plain_text_passwd: freebsd
    ssh_authorized_keys:
      - $(cat "${SSH_KEY}.pub")

ssh_pwauth: true
disable_root: false

datasource_list: [NoCloud]
EOF

# hdiutil est l'outil natif de macOS pour fabriquer une ISO ; le volume
# DOIT s'appeler CIDATA, c'est ainsi que cloud-init reconnaît la source
# NoCloud.
hdiutil makehybrid -quiet -o "${BUILDER_SEED}.tmp" -hfs -joliet -iso \
  -default-volume-name CIDATA \
  "${stage}" >/dev/null

if [[ -f "${BUILDER_SEED}.tmp.iso" ]]; then
  mv "${BUILDER_SEED}.tmp.iso" "${BUILDER_SEED}"
else
  mv "${BUILDER_SEED}.tmp" "${BUILDER_SEED}"
fi

echo "[prepare] terminé."
ls -lh "${BUILDER_DISK}" "${BUILDER_SEED}"
