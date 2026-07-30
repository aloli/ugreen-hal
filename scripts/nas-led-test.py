#!/usr/bin/env python3
"""
nas-led-test.py — protocole de test LED, IDENTIQUE sur chaque unité.

NE JAMAIS MODIFIER CE FICHIER PENDANT UNE CAMPAGNE DE COMPARAISON entre
plusieurs unités du parc de test : c'est précisément ce qui garantit que
les sorties sont comparables. Toute évolution du protocole de test est un
commit dédié et daté, jamais une modification ad hoc pendant une séance.

Consolidé le 30/07/2026 à partir des essais manuels de la même soirée sur
le DXP2800 de test : lecture validée par somme de contrôle, tentative
d'écriture, relevé du registre de confirmation 0x80. Voir
docs/protocol-i2c-leds.adoc pour le détail du protocole et l'historique
de cette investigation.

Remplacé à terme par un binaire Crystal natif (scripts/led-probe/), qui
retire la dépendance à i2c-tools/pip — voir scripts/led-probe/README.adoc.
Ce script reste le repli si le binaire n'est pas disponible.
"""

import subprocess
import sys
import time


def sh(cmd: str) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)


def section(title: str) -> None:
    print(f"\n=== {title}")


section("Identification")
print(sh("cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name 2>/dev/null").stdout.strip() or "(inconnu)")

section("Contrôleur SMBus (lspci)")
r = sh("lspci -nn | grep -i smbus")
print(r.stdout.strip() or "(aucun contrôleur SMBus trouvé)")

section("Modules i2c")
sh("modprobe i2c-i801 2>/dev/null")
sh("modprobe i2c-dev 2>/dev/null")
print(sh("lsmod | grep -i i2c").stdout.strip() or "(aucun module i2c chargé)")

section("Bus i2c détectés (i2cdetect -l)")
buses = sh("i2cdetect -l").stdout
print(buses.strip() or "(vide — i2c-tools installé ? pacman -Sy i2c-tools)")

bus_num = None
for line in buses.splitlines():
    if "I801" in line or "SMBus" in line:
        bus_num = line.split()[0].replace("i2c-", "")
        break

if bus_num is None:
    print("\n[ARRÊT] Aucun bus SMBus I801 identifié — voir la sortie ci-dessus.")
    sys.exit(1)

print(f"\nBus retenu : i2c-{bus_num}")

ADDR = 0x3a  # chip ID 0xc5b2 sur DXP2800 — À CONFIRMER, PAS SUPPOSER, sur
             # les modèles GT (plateforme AMD, sans PCH Intel).

section(f"Scan i2c-{bus_num} (adresse {ADDR:#04x} attendue)")
print(sh(f"i2cdetect -y -r {bus_num}").stdout)

try:
    import smbus2
except ImportError:
    install = sh(f"{sys.executable} -m pip install --break-system-packages smbus2")
    if install.returncode != 0:
        print("[ARRÊT] Installation de smbus2 impossible (réseau ?) :")
        print(install.stderr.strip())
        sys.exit(1)
    import smbus2

bus = smbus2.SMBus(int(bus_num))

section(f"Lecture d'état (registre 0x81, LED power, adresse {ADDR:#04x})")
try:
    data = bus.read_i2c_block_data(ADDR, 0x81, 11)
    print("bytes    :", " ".join(f"{b:02x}" for b in data))
    checksum = sum(data[0:9]) & 0xFFFF
    received = (data[9] << 8) | data[10]
    verdict = "OK" if checksum == received else "MISMATCH"
    print(f"checksum : calculé {checksum:#06x}, reçu {received:#06x} -> {verdict}")
except Exception as e:
    print(f"ÉCHEC lecture : {e}")

section("Tentative d'écriture (power off puis on) + registre de confirmation 0x80")


def set_onoff(led_id: int, on: bool) -> list:
    block = [led_id, 0xA0, 0x01, 0x00, 0x00, 0x03, 1 if on else 0, 0x00, 0x00, 0x00]
    checksum = sum(block[1:10]) & 0xFFFF
    block += [(checksum >> 8) & 0xFF, checksum & 0xFF]
    bus.write_i2c_block_data(ADDR, led_id, block)
    return block


def confirm() -> str:
    try:
        val = bus.read_byte_data(ADDR, 0x80)
        return f"{val:#04x} ({val})"
    except Exception as e:
        return f"erreur: {e}"


try:
    written = set_onoff(0, False)
    print("écrit (off) :", " ".join(f"{x:02x}" for x in written))
    time.sleep(0.3)
    print("registre 0x80 après OFF :", confirm())

    time.sleep(2)

    written = set_onoff(0, True)
    print("écrit (on)  :", " ".join(f"{x:02x}" for x in written))
    time.sleep(0.3)
    print("registre 0x80 après ON  :", confirm())
except Exception as e:
    print(f"ÉCHEC écriture : {e}")

print("\n=== Fin. Observer la LED du bouton d'alimentation pendant les 2 s entre OFF et ON.")
