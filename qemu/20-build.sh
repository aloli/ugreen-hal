#!/usr/bin/env bash
# Compile src/cli/ dans la VM FreeBSD et rapatrie le binaire.
#
# C'est ici que le code rencontre les véritables en-têtes FreeBSD
# (dev/smbus/smb.h), ce que la machine de développement — un Mac — ne peut
# pas faire. Le binaire produit est un exécutable FreeBSD/amd64, donc
# directement copiable sur le DXP2800.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ensure_dirs

if ! vm_alive; then
  echo "[build] VM non démarrée, lancer 10-run.sh" >&2
  exit 1
fi

wait_for_ssh

echo "[build] envoi de src/cli/ vers la VM"
run_ssh "rm -rf ~/src-cli && mkdir -p ~/src-cli"
run_scp "${PROJECT_DIR}/src/cli/Makefile" \
        "${PROJECT_DIR}/src/cli/ugreen-led-ctl.c" \
        freebsd@127.0.0.1:src-cli/

echo "[build] compilation"
if ! run_ssh "cd ~/src-cli && make clean >/dev/null 2>&1; make"; then
  echo >&2
  echo "[build] ÉCHEC de la compilation sous FreeBSD." >&2
  echo "        C'est précisément ce que ce banc existe pour révéler :" >&2
  echo "        le code n'a pu être vérifié sur le Mac que contre un" >&2
  echo "        en-tête reconstitué, jamais contre le vrai." >&2
  exit 1
fi

echo "[build] récupération du binaire"
run_scp freebsd@127.0.0.1:src-cli/ugreen-led-ctl \
        "${BUILD_DIR}/ugreen-led-ctl-freebsd-amd64"

echo
echo "[build] OK : ${BUILD_DIR}/ugreen-led-ctl-freebsd-amd64"
run_ssh "file ~/src-cli/ugreen-led-ctl" || true

cat <<'EOF'

Étape suivante (sprint 3.3) : copier ce binaire sur le DXP2800 démarré
sous FreeBSD/zVault, puis l'exécuter en observant la façade.

  ./ugreen-led-ctl status power     # lecture seule, sans risque
  ./ugreen-led-ctl on disk1         # première écriture réelle

Rappel avant de conclure quoi que ce soit d'un échec : une adresse fausse,
une somme de contrôle fausse et un octet de longueur en trop produisent le
MÊME symptôme — la LED ne bouge pas. Voir l'encadré « Incertitude majeure »
de docs/protocol-i2c-leds.adoc avant de partir sur une piste.
EOF
