# led_probe.cr — sonde et pilote le contrôleur LED UGREEN via SMBus, en
# Crystal natif (ioctl direct), sans dépendance Python/pip.
#
# Remplace scripts/nas-led-test.py : même protocole, mêmes vérifications
# (somme de contrôle sur la lecture, registre de confirmation 0x80 sur
# l'écriture), mais sans avoir besoin d'installer i2c-tools ni smbus2 sur
# chaque unité — juste `chmod +x` puis exécuter.
#
# Compilation : voir README.adoc de ce dossier. À faire dans un
# environnement Linux (une unité du parc, ou une VM), pas sur macOS.
#
# NE JAMAIS MODIFIER CE FICHIER PENDANT UNE CAMPAGNE DE COMPARAISON entre
# plusieurs unités : c'est précisément ce qui garantit que les sorties
# sont comparables. Toute évolution du protocole de test est un commit
# dédié et daté. Voir docs/protocol-i2c-leds.adoc pour le détail du
# protocole et l'historique de cette investigation.

lib LibC
  I2C_SLAVE = 0x0703_u64
  I2C_SMBUS = 0x0720_u64

  I2C_SMBUS_WRITE = 0_u8
  I2C_SMBUS_READ  = 1_u8

  I2C_SMBUS_BYTE_DATA      = 2_u32
  I2C_SMBUS_I2C_BLOCK_DATA = 8_u32

  # union i2c_smbus_data { __u8 byte; __u16 word; __u8 block[34]; } — le
  # membre le plus grand (block, I2C_SMBUS_BLOCK_MAX + 2 = 34 octets)
  # détermine la taille de l'union ; on ne modélise que lui, c'est le
  # seul utilisé ici (lectures/écritures en bloc, plus une lecture octet
  # qui n'utilise que block[0]).
  struct I2cSmbusData
    block : StaticArray(UInt8, 34)
  end

  struct I2cSmbusIoctlData
    read_write : UInt8
    command : UInt8
    size : UInt32
    data : Pointer(I2cSmbusData)
  end

  fun ioctl(fd : Int32, request : UInt64, arg : Void*) : Int32
end

class SmbusError < Exception
end

# Enveloppe fine autour de l'ioctl I2C_SMBUS, reproduisant exactement les
# transactions du code de référence `miskcoo/ugreen_leds_controller`
# (`i2c.cpp`) : bloc I2C_SMBUS_I2C_BLOCK_DATA (sans octet de longueur
# transmis sur le bus, contrairement au « block data » SMBus standard),
# et byte_data pour le registre de confirmation.
class Smbus
  def initialize(bus_number : Int32)
    path = "/dev/i2c-#{bus_number}"
    @fd = LibC.open(path, LibC::O_RDWR)
    raise SmbusError.new("ouverture de #{path} : errno #{Errno.value.value}") if @fd < 0
  end

  def set_slave(address : UInt8) : Nil
    result = LibC.ioctl(@fd, LibC::I2C_SLAVE, Pointer(Void).new(address.to_u64))
    raise SmbusError.new("I2C_SLAVE : errno #{Errno.value.value}") if result < 0
  end

  def read_block(command : UInt8, length : Int32) : Array(UInt8)
    data = LibC::I2cSmbusData.new
    data.block[0] = length.to_u8

    args = LibC::I2cSmbusIoctlData.new(
      read_write: LibC::I2C_SMBUS_READ,
      command: command,
      size: LibC::I2C_SMBUS_I2C_BLOCK_DATA,
      data: pointerof(data)
    )

    result = LibC.ioctl(@fd, LibC::I2C_SMBUS, Pointer(Void).new(pointerof(args).address))
    raise SmbusError.new("lecture bloc (commande 0x%02x) : errno %d" % [command, Errno.value.value]) if result < 0

    (1..length).map { |i| data.block[i] }
  end

  def write_block(command : UInt8, values : Array(UInt8)) : Nil
    data = LibC::I2cSmbusData.new
    data.block[0] = values.size.to_u8
    values.each_with_index { |v, i| data.block[i + 1] = v }

    args = LibC::I2cSmbusIoctlData.new(
      read_write: LibC::I2C_SMBUS_WRITE,
      command: command,
      size: LibC::I2C_SMBUS_I2C_BLOCK_DATA,
      data: pointerof(data)
    )

    result = LibC.ioctl(@fd, LibC::I2C_SMBUS, Pointer(Void).new(pointerof(args).address))
    raise SmbusError.new("écriture bloc (commande 0x%02x) : errno %d" % [command, Errno.value.value]) if result < 0
  end

  def read_byte(command : UInt8) : UInt8
    data = LibC::I2cSmbusData.new

    args = LibC::I2cSmbusIoctlData.new(
      read_write: LibC::I2C_SMBUS_READ,
      command: command,
      size: LibC::I2C_SMBUS_BYTE_DATA,
      data: pointerof(data)
    )

    result = LibC.ioctl(@fd, LibC::I2C_SMBUS, Pointer(Void).new(pointerof(args).address))
    raise SmbusError.new("lecture octet (commande 0x%02x) : errno %d" % [command, Errno.value.value]) if result < 0

    data.block[0]
  end

  def close : Nil
    LibC.close(@fd)
  end
end

# ---------------------------------------------------------------------
# Protocole (voir docs/protocol-i2c-leds.adoc)
# ---------------------------------------------------------------------

ADDRESS = 0x3a_u8 # chip 0xc5b2 sur DXP2800 — à CONFIRMER, pas supposer,
# sur les modèles GT (plateforme AMD, sans PCH Intel).

def checksum(bytes : Array(UInt8)) : UInt16
  bytes.reduce(0) { |sum, b| sum + b }.to_u16
end

def hexdump(bytes : Array(UInt8)) : String
  bytes.map { |b| "%02x" % b }.join(" ")
end

def find_i801_bus : Int32?
  return nil unless File.exists?("/sys/class/i2c-dev")

  Dir.entries("/sys/class/i2c-dev").each do |entry|
    next unless entry.starts_with?("i2c-")
    name_path = "/sys/class/i2c-dev/#{entry}/name"
    next unless File.exists?(name_path)
    name = File.read(name_path)
    if name.includes?("I801") || name.includes?("SMBus")
      return entry.sub("i2c-", "").to_i?
    end
  end

  nil
end

def section(title : String) : Nil
  puts
  puts "=== #{title}"
end

section "Identification"
["/sys/class/dmi/id/sys_vendor", "/sys/class/dmi/id/product_name"].each do |path|
  puts File.read(path).strip if File.exists?(path)
end

section "Bus SMBus I801"
bus_number = find_i801_bus
if bus_number.nil?
  puts "(aucun bus I801/SMBus trouvé sous /sys/class/i2c-dev — modules i2c-i801/i2c-dev chargés ?)"
  exit 1
end
puts "Bus retenu : i2c-#{bus_number}"

bus = Smbus.new(bus_number)

section "Lecture d'état (registre 0x81, LED power, adresse 0x#{ADDRESS.to_s(16)})"
begin
  data = bus.read_block(0x81_u8, 11)
  puts "bytes    : #{hexdump(data)}"
  computed = checksum(data[0, 9])
  received = (data[9].to_u16 << 8) | data[10]
  verdict = computed == received ? "OK" : "MISMATCH"
  puts "checksum : calculé 0x%04x, reçu 0x%04x -> %s" % [computed, received, verdict]
rescue e : SmbusError
  puts "ÉCHEC lecture : #{e.message}"
end

section "Tentative d'écriture (power off puis on) + registre de confirmation 0x80"

def set_onoff(bus : Smbus, led_id : UInt8, on : Bool) : Array(UInt8)
  block = [led_id, 0xa0_u8, 0x01_u8, 0x00_u8, 0x00_u8, 0x03_u8, (on ? 1_u8 : 0_u8), 0x00_u8, 0x00_u8, 0x00_u8]
  sum = checksum(block[1, 9])
  block << ((sum >> 8) & 0xff).to_u8
  block << (sum & 0xff).to_u8
  bus.write_block(led_id, block)
  block
end

def confirm(bus : Smbus) : String
  value = bus.read_byte(0x80_u8)
  "0x%02x (%d)" % [value, value]
rescue e : SmbusError
  "erreur: #{e.message}"
end

begin
  written = set_onoff(bus, 0_u8, false)
  puts "écrit (off) : #{hexdump(written)}"
  sleep 0.3.seconds
  puts "registre 0x80 après OFF : #{confirm(bus)}"

  sleep 2.seconds

  written = set_onoff(bus, 0_u8, true)
  puts "écrit (on)  : #{hexdump(written)}"
  sleep 0.3.seconds
  puts "registre 0x80 après ON  : #{confirm(bus)}"
rescue e : SmbusError
  puts "ÉCHEC écriture : #{e.message}"
end

bus.close

puts
puts "=== Fin. Observer la LED du bouton d'alimentation pendant les 2 s entre OFF et ON."
