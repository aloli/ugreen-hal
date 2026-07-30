# nas_fleet.cr — utilitaires partagés pour piloter le parc de NAS de test.
#
# Partagé par nas-connect.cr et nas-led-test.cr : résolution d'un nom
# court vers une adresse IP, et arguments SSH communs (clé dédiée à ce
# banc, distincte de la clé personnelle — voir scripts/nas-ssh/).
#
# La correspondance nom -> IP vit dans nas-hosts.json, propre à cette
# machine et à cette campagne de tests. Volontairement NON versionnée
# (voir .gitignore) : l'adresse change à chaque redémarrage d'une unité
# sous SystemRescue, environnement live sans état persistant — un fichier
# committé serait faux dès le lendemain.

require "json"

module NasFleet
  HOSTS_FILE = File.join(__DIR__, "nas-hosts.json")
  SSH_KEY    = File.join(__DIR__, "nas-ssh", "id_ed25519")

  def self.load_hosts : Hash(String, String)
    return {} of String => String unless File.exists?(HOSTS_FILE)
    Hash(String, String).from_json(File.read(HOSTS_FILE))
  rescue
    {} of String => String
  end

  def self.save_hosts(hosts : Hash(String, String))
    File.write(HOSTS_FILE, hosts.to_pretty_json)
  end

  def self.resolve(name : String) : String?
    load_hosts[name]?
  end

  # StrictHostKeyChecking=accept-new : chaque unité est réinstallée à
  # chaque redémarrage (image live), donc une nouvelle clé d'hôte à
  # chaque fois — accepter sans confirmation évite de rejouer le
  # « are you sure you want to continue connecting? » à chaque essai,
  # sans pour autant désactiver la vérification (une clé qui CHANGE en
  # cours de session, elle, resterait détectée).
  def self.ssh_args(ip : String) : Array(String)
    ["-i", SSH_KEY, "-o", "StrictHostKeyChecking=accept-new", "root@#{ip}"]
  end
end
