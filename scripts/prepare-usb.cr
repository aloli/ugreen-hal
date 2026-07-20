# prepare-usb.cr — préparation interactive des clés USB du projet ugreen-hal
#
# Remplace les guides commentés prepare-usb-systemrescue.sh et
# prepare-usb-zvault.sh par un programme qui déroule réellement la
# procédure, en posant les questions plutôt qu'en laissant recopier des
# commandes à la main.
#
# Usage :
#   crystal run scripts/prepare-usb.cr
#   crystal build -o /tmp/prepare-usb scripts/prepare-usb.cr && /tmp/prepare-usb
#
# Cible : macOS (diskutil). Le programme refuse de s'exécuter ailleurs.
#
# Garde-fous, dans l'ordre où ils interviennent :
#   1. seuls les disques EXTERNES et PHYSIQUES sont proposés — le disque
#      interne du Mac n'apparaît jamais dans la liste ;
#   2. le choix se fait par numéro dans une liste, jamais en saisissant un
#      chemin de périphérique (une faute de frappe sur /dev/diskN est le
#      scénario catastrophe classique) ;
#   3. la confirmation exige de recopier l'identifiant exact du disque, pas
#      un simple « oui » ;
#   4. l'empreinte SHA-256 de l'image est vérifiée avant écriture si elle
#      est fournie.
#
# Licence : BSD-2-Clause — Philippe Nénert (ALOLI sas)

require "digest/sha256"

module PrepareUsb
  # Images connues du projet. Les empreintes ne sont volontairement pas
  # codées en dur : elles changent à chaque version, et une valeur périmée
  # dans le code serait pire que pas de valeur du tout — elle donnerait une
  # fausse assurance. L'utilisateur la copie depuis la page officielle.
  record Image,
    name : String,
    role : String,
    hint : String,
    source : String

  IMAGES = [
    Image.new(
      name: "SystemRescue",
      role: "live Linux — sert à cloner l'eMMC du NAS (voir backup-nas.sh)",
      hint: "systemrescue-13.01-amd64.iso",
      source: "https://www.system-rescue.org/Download/"
    ),
    Image.new(
      name: "zVault",
      role: "installeur — démarrage externe du NAS (sprint 2)",
      hint: "zVault-13.3-MASTER-202505042329-ca844f8808.iso",
      source: "https://github.com/zvaultio/Community/releases"
    ),
  ]

  # Un disque externe candidat, tel que rapporté par diskutil.
  record Disk,
    device : String,
    size : String,
    media : String

  class Aborted < Exception
  end

  extend self

  # ------------------------------------------------------------------
  # Sortie
  # ------------------------------------------------------------------

  def title(text : String)
    puts
    puts "== #{text}"
    puts
  end

  def warn(text : String)
    puts "  /!\\  #{text}"
  end

  def ask(prompt : String) : String
    print "#{prompt} "
    STDOUT.flush
    line = STDIN.gets
    raise Aborted.new("Entrée interrompue.") if line.nil?
    line.chomp.strip
  end

  def ask_yes_no(prompt : String) : Bool
    loop do
      case ask("#{prompt} [o/n]").downcase
      when "o", "oui", "y", "yes" then return true
      when "n", "non", "no"       then return false
      else                             puts "  Répondre par o ou n."
      end
    end
  end

  # ------------------------------------------------------------------
  # Exécution de commandes
  # ------------------------------------------------------------------

  # Capture la sortie d'une commande. Lève si elle échoue.
  def capture(command : String, args : Array(String)) : String
    output = IO::Memory.new
    status = Process.run(command, args, output: output, error: STDERR)
    unless status.success?
      raise Aborted.new("Échec de : #{command} #{args.join(' ')}")
    end
    output.to_s
  end

  # Exécute une commande en laissant l'utilisateur voir et interagir
  # (indispensable pour sudo, qui demande le mot de passe sur le terminal).
  def run_interactive(command : String, args : Array(String)) : Bool
    puts "  $ #{command} #{args.join(' ')}"
    Process.run(command, args, input: STDIN, output: STDOUT, error: STDERR).success?
  end

  # ------------------------------------------------------------------
  # Étapes
  # ------------------------------------------------------------------

  def check_platform
    {% unless flag?(:darwin) %}
      STDERR.puts "Ce programme s'appuie sur diskutil et ne fonctionne que sous macOS."
      exit 1
    {% end %}
  end

  def choose_image : Image
    title "Quelle clé préparer ?"

    IMAGES.each_with_index(1) do |image, index|
      puts "  #{index}. #{image.name} — #{image.role}"
    end
    puts

    loop do
      answer = ask("Numéro :").to_i?
      if answer && (1..IMAGES.size).includes?(answer)
        image = IMAGES[answer - 1]
        puts
        puts "  Image attendue : #{image.hint}"
        puts "  Téléchargement : #{image.source}"
        return image
      end
      puts "  Saisir un numéro entre 1 et #{IMAGES.size}."
    end
  end

  def locate_iso(image : Image) : String
    title "Où se trouve l'image ?"

    default = Path.home.join("Downloads", image.hint).to_s
    puts "  Proposition : #{default}"
    puts "  (entrée vide pour l'accepter, sinon saisir un autre chemin)"
    puts

    loop do
      answer = ask("Chemin :")
      path = answer.empty? ? default : Path[answer].expand(home: true).to_s

      if File.file?(path)
        size = File.size(path)
        puts
        puts "  Trouvée : #{path}"
        puts "  Taille  : #{human_size(size)}"
        warn "Taille inhabituellement faible pour une ISO." if size < 100_000_000
        return path
      end

      puts "  Fichier introuvable : #{path}"
    end
  end

  def verify_checksum(path : String)
    title "Vérification de l'empreinte SHA-256"

    puts "  Une ISO tronquée produit une clé qui démarre à moitié — panne"
    puts "  déroutante, et coûteuse à diagnostiquer sur un NAS sans écran."
    puts "  L'empreinte est publiée à côté de l'image sur le site officiel."
    puts

    expected = ask("Empreinte attendue (entrée vide pour passer) :").downcase
    if expected.empty?
      warn "Vérification passée — à vos risques."
      return
    end

    print "  Calcul en cours (peut prendre une minute)... "
    STDOUT.flush
    actual = sha256_of(path)
    puts "terminé."
    puts

    if actual == expected
      puts "  Empreintes identiques. Image intègre."
    else
      puts "  Attendue : #{expected}"
      puts "  Obtenue  : #{actual}"
      raise Aborted.new("Les empreintes diffèrent : l'image est corrompue ou incomplète.")
    end
  end

  def sha256_of(path : String) : String
    digest = Digest::SHA256.new
    File.open(path) do |file|
      buffer = Bytes.new(1024 * 1024)
      while (read = file.read(buffer)) > 0
        digest.update(buffer[0, read])
      end
    end
    digest.final.hexstring
  end

  # Liste uniquement les disques externes physiques : le disque interne du
  # Mac ne peut donc jamais être proposé, ce qui élimine à la racine le
  # risque le plus grave de cette procédure.
  def external_disks : Array(Disk)
    raw = capture("diskutil", ["list", "external", "physical"])

    raw.lines.compact_map do |line|
      next unless line.starts_with?("/dev/disk")
      device = line.split(' ').first
      info = disk_info(device)
      Disk.new(device: device, size: info[:size], media: info[:media])
    end
  end

  def disk_info(device : String) : NamedTuple(size: String, media: String)
    raw = capture("diskutil", ["info", device])
    size = "taille inconnue"
    media = "modèle inconnu"

    raw.lines.each do |line|
      key, _, value = line.partition(':')
      value = value.strip
      case key.strip
      when "Disk Size"           then size = value
      when "Device / Media Name" then media = value
      end
    end

    {size: size, media: media}
  end

  def choose_disk : Disk
    title "Sur quelle clé écrire ?"

    disks = external_disks
    if disks.empty?
      raise Aborted.new("Aucun disque externe détecté. Brancher la clé USB, puis relancer.")
    end

    puts "  Seuls les disques EXTERNES sont proposés : le disque interne du"
    puts "  Mac ne peut pas apparaître dans cette liste."
    puts

    disks.each_with_index(1) do |disk, index|
      puts "  #{index}. #{disk.device} — #{disk.media} (#{disk.size})"
    end
    puts

    loop do
      answer = ask("Numéro :").to_i?
      return disks[answer - 1] if answer && (1..disks.size).includes?(answer)
      puts "  Saisir un numéro entre 1 et #{disks.size}."
    end
  end

  def confirm(image : Image, iso : String, disk : Disk)
    title "Dernière vérification"

    puts "  Image   : #{File.basename(iso)}"
    puts "  Cible   : #{disk.device} — #{disk.media} (#{disk.size})"
    puts
    warn "Tout le contenu de #{disk.device} sera détruit, sans retour possible."
    puts

    identifier = disk.device.lchop("/dev/")
    typed = ask("Pour confirmer, recopier l'identifiant du disque (#{identifier}) :")

    unless typed == identifier
      raise Aborted.new("Identifiant non confirmé — rien n'a été écrit.")
    end
  end

  def write(iso : String, disk : Disk)
    title "Écriture"

    puts "  Démontage des systèmes de fichiers..."
    unless run_interactive("diskutil", ["unmountDisk", disk.device])
      raise Aborted.new("Démontage impossible — un programme utilise peut-être la clé.")
    end

    # /dev/rdiskN est le périphérique en accès brut : dix à vingt fois plus
    # rapide que /dev/diskN sur macOS pour ce type d'écriture séquentielle.
    raw_device = disk.device.sub("/dev/disk", "/dev/rdisk")

    puts
    puts "  sudo va demander votre mot de passe."
    puts "  L'écriture peut durer plusieurs minutes, sans affichage continu."
    puts

    ok = run_interactive("sudo", [
      "dd",
      "if=#{iso}",
      "of=#{raw_device}",
      "bs=1m",
      "status=progress",
    ])
    raise Aborted.new("L'écriture a échoué — la clé est dans un état indéterminé.") unless ok

    puts
    puts "  Synchronisation des tampons..."
    run_interactive("sync", [] of String)

    puts "  Éjection..."
    run_interactive("diskutil", ["eject", disk.device])
  end

  def next_steps(image : Image)
    title "Terminé"

    case image.name
    when "SystemRescue"
      puts "  Clé prête. Sur le NAS :"
      puts "   1. Ctrl-F12 au démarrage pour entrer dans le BIOS."
      puts "   2. DÉSACTIVER LE WATCHDOG — le chip IT8613 redémarre la machine"
      puts "      au bout de 20 minutes si aucun système ne le nourrit, et un"
      puts "      clone de 32 Gio peut dépasser ce délai."
      puts "   3. Régler l'ordre de démarrage sur la clé USB."
      puts "   4. Dérouler la procédure de scripts/backup-nas.sh."
    when "zVault"
      puts "  Clé prête. Le clone de l'eMMC doit avoir été fait AVANT de"
      puts "  démarrer là-dessus (voir scripts/backup-nas.sh)."
      puts
      puts "  Au premier démarrage, noter pour la documentation :"
      puts "   - la touche réelle du menu de démarrage (Ctrl-F12 annoncée) ;"
      puts "   - ce que zVault détecte (disques, réseau igc, SMBus)."
    end
  end

  def human_size(bytes : Int) : String
    units = ["o", "Kio", "Mio", "Gio"]
    value = bytes.to_f
    unit = 0
    while value >= 1024 && unit < units.size - 1
      value /= 1024
      unit += 1
    end
    "%.1f %s" % {value, units[unit]}
  end

  def run
    check_platform

    puts "prepare-usb — préparation des clés USB du projet ugreen-hal"

    image = choose_image
    iso = locate_iso(image)
    verify_checksum(iso)
    disk = choose_disk
    confirm(image, iso, disk)
    write(iso, disk)
    next_steps(image)
  rescue error : Aborted
    puts
    puts "Interrompu : #{error.message}"
    exit 1
  end
end

PrepareUsb.run
