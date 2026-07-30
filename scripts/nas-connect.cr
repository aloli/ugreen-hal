# nas-connect.cr — connexion SSH à une unité du parc de test, par nom court.
#
# Usage :
#   crystal run scripts/nas-connect.cr -- <nom>
#   crystal run scripts/nas-connect.cr -- --list
#   crystal run scripts/nas-connect.cr -- --set <nom> <ip>
#   crystal run scripts/nas-connect.cr -- --forget <nom>
#
# La correspondance nom -> IP (nas-hosts.json) est propre à cette machine,
# non versionnée : l'adresse change à chaque redémarrage d'une unité sous
# SystemRescue (environnement live, sans état persistant). La renseigner
# à chaque session avec --set, en s'appuyant sur l'IP qu'affiche
# systemrescue-restore.sh à la fin de son exécution.

require "./nas_fleet"

def usage
  STDERR.puts <<-USAGE
  Usage :
    nas-connect <nom>              se connecter en SSH
    nas-connect --list             lister les unités connues
    nas-connect --set <nom> <ip>   enregistrer ou mettre à jour une unité
    nas-connect --forget <nom>     retirer une unité
  USAGE
  exit 1
end

args = ARGV
usage if args.empty?

case args[0]
when "--list"
  hosts = NasFleet.load_hosts
  if hosts.empty?
    puts "Aucune unité enregistrée. Utiliser --set <nom> <ip> pour en ajouter une."
  else
    hosts.each { |name, ip| puts "#{name.ljust(16)} #{ip}" }
  end
when "--set"
  usage if args.size < 3
  hosts = NasFleet.load_hosts
  hosts[args[1]] = args[2]
  NasFleet.save_hosts(hosts)
  puts "Enregistré : #{args[1]} -> #{args[2]}"
when "--forget"
  usage if args.size < 2
  hosts = NasFleet.load_hosts
  if hosts.delete(args[1])
    NasFleet.save_hosts(hosts)
    puts "Retiré : #{args[1]}"
  else
    STDERR.puts "Inconnu : #{args[1]}"
    exit 1
  end
else
  name = args[0]
  ip = NasFleet.resolve(name)

  unless ip
    STDERR.puts "Unité inconnue : #{name}"
    STDERR.puts "L'enregistrer d'abord : nas-connect --set #{name} <ip>"
    hosts = NasFleet.load_hosts
    unless hosts.empty?
      STDERR.puts
      STDERR.puts "Unités connues :"
      hosts.each { |n, i| STDERR.puts "  #{n.ljust(16)} #{i}" }
    end
    exit 1
  end

  unless File.exists?(NasFleet::SSH_KEY)
    STDERR.puts "Clé SSH introuvable : #{NasFleet::SSH_KEY}"
    exit 1
  end

  puts "Connexion à #{name} (#{ip})..."
  Process.exec("ssh", NasFleet.ssh_args(ip))
end
