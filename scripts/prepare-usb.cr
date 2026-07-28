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
#   4. l'empreinte (SHA-256 ou SHA-512) de l'image est vérifiée avant
#      écriture, à partir du fichier de sommes local ou publié.
#
# Licence : BSD-2-Clause — Philippe Nénert (ALOLI sas)

require "digest/sha256"
require "openssl"

module PrepareUsb
  # Images connues du projet. Les empreintes ne sont volontairement pas
  # codées en dur : elles changent à chaque version, et une valeur périmée
  # dans le code serait pire que pas de valeur du tout — elle donnerait une
  # fausse assurance. L'utilisateur la copie depuis la page officielle.
  # `url` est l'adresse de téléchargement direct, `page` la page officielle
  # où la retrouver. Les URL directes se périment à chaque version : le
  # programme les propose mais laisse toujours en coller une autre, et
  # renvoie à `page` en cas d'échec. Une URL codée en dur qui ne répond
  # plus ne doit jamais devenir un cul-de-sac.
  record Image,
    name : String,
    role : String,
    hint : String,
    page : String,
    url : String?,
    sha256_url : String?

  IMAGES = [
    Image.new(
      name: "SystemRescue",
      role: "live Linux — clone de l'eMMC du NAS (voir backup-nas.sh)",
      hint: "systemrescue-13.01-amd64.iso",
      page: "https://www.system-rescue.org/Download/",
      url: "https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/13.01/systemrescue-13.01-amd64.iso/download",
      sha256_url: "https://sourceforge.net/projects/systemrescuecd/files/sysresccd-x86/13.01/systemrescue-13.01-amd64.iso.sha256/download"
    ),
    Image.new(
      name: "zVault",
      role: "installeur — première cible d'intégration (sprints 2 à 5)",
      hint: "zVault-13.3-MASTER-202505042329-ca844f8808.iso",
      page: "https://github.com/zvaultio/Community/releases",
      url: nil,
      sha256_url: nil
    ),
    Image.new(
      name: "XigmaNAS",
      role: "installeur — seconde cible d'intégration (sprint 5bis)",
      hint: "XigmaNAS-x64-LiveCD-14.3.0.5.10566.iso",
      page: "https://sourceforge.net/projects/xigmanas/files/XigmaNAS-14.3.0.5/",
      url: nil,
      sha256_url: nil
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
        puts "  Page officielle : #{image.page}"
        return image
      end
      puts "  Saisir un numéro entre 1 et #{IMAGES.size}."
    end
  end

  def locate_iso(image : Image) : String
    title "L'image ISO"

    default = Path.home.join("Downloads", image.hint).to_s

    # Si l'image attendue est déjà là, la proposer d'emblée : c'est le cas
    # courant dès la deuxième exécution.
    if File.file?(default)
      puts "  Déjà présente : #{default}"
      puts
      return describe_iso(default) if ask_yes_no("L'utiliser ?")
    end

    puts "  1. Télécharger l'image maintenant"
    puts "  2. Utiliser un fichier déjà présent sur le disque"
    puts

    loop do
      case ask("Numéro :")
      when "1"
        destination = ask_destination(image, default)
        download(image, destination)
        return describe_iso(destination) if File.file?(destination)
      when "2"
        path = ask_existing_path(default)
        return describe_iso(path) if path
      else
        puts "  Saisir 1 ou 2."
      end
    end
  end

  def ask_destination(image : Image, default : String) : String
    puts
    puts "  Enregistrer sous : #{default}"
    puts "  (entrée vide pour l'accepter, sinon saisir un autre chemin)"
    answer = ask("Chemin :")
    answer.empty? ? default : Path[answer].expand(home: true).to_s
  end

  # Renvoie nil si l'utilisateur veut revenir au menu précédent, ce qui évite
  # de l'enfermer dans une boucle s'il s'est trompé d'option.
  def ask_existing_path(default : String) : String?
    puts
    puts "  Chemin du fichier (entrée vide pour revenir en arrière)"
    puts "  Proposition : #{default}"

    loop do
      answer = ask("Chemin :")
      return nil if answer.empty?

      path = Path[answer].expand(home: true).to_s
      return path if File.file?(path)

      puts "  Fichier introuvable : #{path}"
    end
  end

  def describe_iso(path : String) : String
    size = File.size(path)
    puts
    puts "  Trouvée : #{path}"
    puts "  Taille  : #{human_size(size)}"
    warn "Taille inhabituellement faible pour une ISO." if size < 100_000_000
    path
  end

  # Téléchargement via curl, présent d'origine sur macOS.
  #
  # -L suit les redirections, indispensable pour SourceForge et GitHub qui
  # renvoient systématiquement vers un miroir. -C - reprend un transfert
  # interrompu là où il s'est arrêté, ce qui évite de tout recommencer sur
  # une ISO de plusieurs centaines de Mo. --fail transforme une page
  # d'erreur HTTP en échec franc plutôt qu'en fichier HTML de 2 Ko
  # silencieusement enregistré à la place de l'image.
  def download(image : Image, destination : String)
    title "Téléchargement"

    suggestion = image.url
    if suggestion
      puts "  URL proposée :"
      puts "    #{suggestion}"
      puts
      warn "Cette URL est codée dans le programme et se périme à chaque"
      puts "       nouvelle version. En cas d'échec, prendre la bonne sur :"
      puts "       #{image.page}"
    else
      puts "  Aucune URL directe n'est connue pour cette image : elle change"
      puts "  à chaque publication. La récupérer sur la page officielle :"
      puts "    #{image.page}"
    end
    puts

    prompt = suggestion ? "URL (entrée vide pour accepter celle proposée) :" : "URL :"
    answer = ask(prompt)
    url = answer.empty? ? suggestion : answer

    if url.nil? || url.empty?
      raise Aborted.new("Aucune URL fournie.")
    end

    # Mémorisée pour en déduire ensuite où chercher l'empreinte, y compris
    # lorsque l'URL a été saisie à la main.
    @@last_download_url = url

    directory = File.dirname(destination)
    Dir.mkdir_p(directory) unless Dir.exists?(directory)

    puts
    ok = run_interactive("curl", [
      "--location",
      "--fail",
      "--continue-at", "-",
      "--progress-bar",
      # Sans délai d'expiration, un réseau injoignable fige le programme
      # sans un mot d'explication. 20 s suffisent largement pour établir
      # une connexion ; au-delà, mieux vaut un échec franc.
      "--connect-timeout", "20",
      # Coupure en cours de transfert : deux reprises automatiques, en
      # s'appuyant sur --continue-at pour ne pas repartir de zéro.
      "--retry", "2",
      "--retry-delay", "5",
      "--output", destination,
      url,
    ])

    unless ok
      partial = File.file?(destination) ? File.size(destination) : 0_i64

      if partial > 0 && partial < 100_000_000
        # Trop petit pour être une reprise utile, et probablement une page
        # d'erreur HTML plutôt qu'une image : à supprimer, sinon le prochain
        # passage la prendrait pour l'ISO.
        File.delete(destination)
        raise Aborted.new("Téléchargement échoué. Vérifier l'URL sur #{image.page}")
      end

      if partial > 0
        puts
        warn "Fichier partiel conservé (#{human_size(partial)}) pour permettre"
        puts "       une reprise : relancer et redemander le téléchargement,"
        puts "       curl repartira d'où il s'est arrêté."
        warn "Ce fichier INCOMPLET a la taille d'une vraie ISO. Ne jamais"
        puts "       l'écrire sur une clé sans avoir vérifié son empreinte"
        puts "       SHA-256 — c'est précisément le cas que cette"
        puts "       vérification est là pour attraper."
      end

      raise Aborted.new("Téléchargement interrompu. Page officielle : #{image.page}")
    end
  end

  # Une empreinte publiée : l'algorithme, et la valeur hexadécimale.
  # L'algorithme n'est pas fixé d'avance — SystemRescue et zVault publient
  # du SHA-256, XigmaNAS du SHA-512. Le déduire du fichier de sommes plutôt
  # que de le supposer évite de comparer une empreinte à la mauvaise.
  record Checksum, algorithm : String, hex : String

  def verify_checksum(image : Image, path : String)
    title "Vérification de l'empreinte"

    puts "  Une ISO tronquée produit une clé qui démarre à moitié — panne"
    puts "  déroutante, et coûteuse à diagnostiquer sur un NAS sans écran."
    puts

    @@last_download_url ||= image.url
    expected_name = expected_filename(image)

    # 1. Fichier de sommes déjà présent à côté de l'image : le cas le plus
    #    fréquent quand on a téléchargé ISO et somme depuis la même page.
    expected = find_local_checksum(path, expected_name)

    # 2. Sinon, tenter de le récupérer sur le réseau.
    expected ||= fetch_published_checksum(image, expected_name)

    if expected
      puts
      puts "  Empreinte #{expected.algorithm} récupérée :"
      puts "    #{expected.hex}"
    else
      puts "  L'empreinte est publiée à côté de l'image sur le site officiel :"
      puts "    #{image.page}"
      puts
      typed = ask("Empreinte attendue (entrée vide pour passer) :").downcase
      if typed.empty?
        warn "Vérification passée — à vos risques."
        return
      end
      # Algorithme déduit de la longueur : 64 hex = SHA-256, 128 = SHA-512.
      algo = typed.size == 128 ? "SHA512" : "SHA256"
      expected = Checksum.new(algo, typed)
    end

    print "  Calcul #{expected.algorithm} (peut prendre une minute)... "
    STDOUT.flush
    actual = compute_digest(path, expected.algorithm)
    puts "terminé."
    puts

    if actual == expected.hex
      puts "  Empreintes identiques. Image intègre."
    else
      puts "  Attendue : #{expected.hex}"
      puts "  Obtenue  : #{actual}"
      raise Aborted.new("Les empreintes diffèrent : l'image est corrompue ou incomplète.")
    end
  end

  # Cherche un fichier de sommes dans le même dossier que l'image. Couvre
  # les fichiers par image (<iso>.sha256) comme les récapitulatifs
  # (XigmaNAS-....SHA512-CHECKSUM, CHECKSUM.SHA256, SHA256SUMS). La sécurité
  # tient à extract_checksum, qui n'accepte une empreinte que si une ligne
  # nomme bien l'image attendue : un fichier de sommes destiné à une autre
  # ISO du même dossier est donc ignoré.
  def find_local_checksum(iso_path : String, expected_name : String) : Checksum?
    dir = File.dirname(iso_path)

    candidates = [] of String
    {".sha256", ".sha512", ".sha256sum", ".sha512sum"}.each do |suffix|
      exact = "#{iso_path}#{suffix}"
      candidates << exact if File.file?(exact)
    end
    {"*CHECKSUM*", "*SHA*SUMS", "CHECKSUM*"}.each do |pattern|
      Dir.glob(File.join(dir, pattern)).each do |match|
        candidates << match if File.file?(match)
      end
    end

    candidates.uniq.each do |file|
      content = read_text(file)
      next unless content
      if checksum = extract_checksum(content, expected_name)
        puts "  Fichier de sommes local : #{File.basename(file)}"
        return checksum
      end
    end

    nil
  end

  def read_text(path : String) : String?
    File.read(path)
  rescue
    nil
  end

  # URL réellement utilisée pour le dernier téléchargement, y compris celle
  # saisie à la main. Sert à deviner où trouver l'empreinte : les projets
  # publient presque toujours le fichier de somme à côté de l'image.
  @@last_download_url : String? = nil

  # Construit la liste des emplacements où chercher l'empreinte, du plus
  # spécifique au plus générique. Aucun n'est garanti : on les essaie dans
  # l'ordre et on s'arrête au premier qui répond.
  def checksum_candidates(image : Image) : Array(String)
    candidates = [] of String

    if declared = image.sha256_url
      candidates << declared
    end

    source = @@last_download_url
    if source
      # SourceForge suffixe ses URL de « /download » : le fichier de somme
      # se trouve donc à « …/nom.iso.sha256/download », et non après.
      base, suffix = source.ends_with?("/download") ? {source[0...-9], "/download"} : {source, ""}

      candidates << "#{base}.sha256#{suffix}"
      candidates << "#{base}.sha256sum#{suffix}"
      candidates << "#{base}.CHECKSUM.SHA256#{suffix}"

      # FreeBSD et plusieurs autres publient un fichier unique récapitulant
      # tout le répertoire, plutôt qu'un fichier par image.
      if slash = base.rindex('/')
        directory = base[0, slash]
        candidates << "#{directory}/CHECKSUM.SHA256#{suffix}"
        candidates << "#{directory}/SHA256SUMS#{suffix}"
      end
    end

    candidates.uniq
  end

  # Récupère l'empreinte publiée par le projet, plutôt que de la faire
  # recopier à la main. Renvoie nil si aucun emplacement ne répond — auquel
  # cas la saisie manuelle reste possible.
  def fetch_published_checksum(image : Image, expected_name : String) : Checksum?
    candidates = checksum_candidates(image)
    return nil if candidates.empty?

    candidates.each do |url|
      print "  Recherche de l'empreinte : #{shorten(url)}... "
      STDOUT.flush

      output = IO::Memory.new
      status = Process.run("curl", [
        "--location", "--fail", "--silent",
        "--connect-timeout", "15",
        url,
      ], output: output, error: Process::Redirect::Close)

      unless status.success?
        puts "absent."
        next
      end

      checksum = extract_checksum(output.to_s, expected_name)
      if checksum
        puts "trouvée."
        return checksum
      end

      puts "illisible."
    end

    nil
  end

  # Extrait une empreinte d'un fichier de sommes. Deux formats circulent :
  # le format BSD « SHA512 (fichier) = <hex> », et le format coreutils
  # « <hex>  fichier ». Un récapitulatif liste souvent des dizaines de
  # fichiers : prendre la première empreinte venue donnerait celle d'une
  # autre image, d'où la recherche prioritaire de la ligne nommant l'image
  # attendue.
  def extract_checksum(content : String, expected_name : String) : Checksum?
    target = expected_name.downcase

    content.each_line do |line|
      next unless line.downcase.includes?(target)
      if checksum = parse_checksum_line(line)
        return checksum
      end
    end

    # Fichier ne contenant qu'une seule empreinte, sans nom : sans ambiguïté.
    parsed = content.each_line.compact_map { |line| parse_checksum_line(line) }.to_a
    parsed.size == 1 ? parsed.first : nil
  end

  def parse_checksum_line(line : String) : Checksum?
    # Format BSD : « SHA512 (fichier) = <hex> » — l'algorithme est nommé.
    if m = line.match(/\b(SHA256|SHA512)\b.*?([0-9a-fA-F]{64,128})\b/)
      return Checksum.new(m[1].upcase, m[2].downcase)
    end

    # Format coreutils : « <hex>  fichier » — algorithme déduit de la
    # longueur (64 = SHA-256, 128 = SHA-512). On ignore SHA-1 (40) et MD5
    # (32), trop faibles pour servir de garantie d'intégrité ici.
    if m = line.match(/\b([0-9a-fA-F]{128}|[0-9a-fA-F]{64})\b/)
      hex = m[1].downcase
      algo = hex.size == 128 ? "SHA512" : "SHA256"
      return Checksum.new(algo, hex)
    end

    nil
  end

  def expected_filename(image : Image) : String
    source = @@last_download_url
    return File.basename(image.hint) unless source

    base = source.ends_with?("/download") ? source[0...-9] : source
    name = File.basename(base)
    name.empty? ? File.basename(image.hint) : name
  end

  def shorten(url : String) : String
    url.size <= 60 ? url : "#{url[0, 30]}…#{url[-28..]}"
  end

  def compute_digest(path : String, algorithm : String) : String
    digest = new_digest(algorithm)
    File.open(path) do |file|
      buffer = Bytes.new(1024 * 1024)
      while (read = file.read(buffer)) > 0
        digest.update(buffer[0, read])
      end
    end
    digest.hexfinal
  end

  # Digest::SHA256 (bibliothèque standard) et OpenSSL::Digest héritent tous
  # deux de la classe abstraite Digest, d'où le type de retour commun.
  def new_digest(algorithm : String) : Digest
    case algorithm
    when "SHA256" then Digest::SHA256.new
    when "SHA512" then OpenSSL::Digest.new("SHA512")
    else               raise Aborted.new("Algorithme d'empreinte non géré : #{algorithm}")
    end
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
    when "zVault", "XigmaNAS"
      puts "  Clé prête. Le clone de l'eMMC doit avoir été fait AVANT de"
      puts "  démarrer là-dessus (voir scripts/backup-nas.sh)."
      puts
      puts "  Au premier démarrage, noter pour la documentation :"
      puts "   - la touche réelle du menu de démarrage (Ctrl-F12 annoncée) ;"
      puts "   - les disques détectés et le comportement du réseau (igc) ;"
      puts "   - la présence d'un bus SMBus (dmesg | grep -i smb)."
      puts
      puts "  Rappel : le watchdog IT8613 doit être désactivé dans le BIOS,"
      puts "  sans quoi la machine redémarre seule au bout de 20 minutes."
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
    verify_checksum(image, iso)
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
