# nas-led-test.cr — orchestre le protocole de test LED sur une unité du
# parc, et journalise le résultat.
#
# Usage :
#   crystal run scripts/nas-led-test.cr -- <nom>
#
# Envoie scripts/led-probe/led_probe (binaire natif, si compilé — voir
# scripts/led-probe/README.adoc) ou, à défaut, scripts/nas-led-test.py,
# l'exécute à distance, affiche et journalise la sortie brute dans
# docs/led-test-results/. Ni l'un ni l'autre payload ne doit être modifié
# entre deux unités d'une même campagne de comparaison.

require "./nas_fleet"

PROBE_BINARY   = File.join(__DIR__, "led-probe", "led_probe")
PYTHON_PAYLOAD = File.join(__DIR__, "nas-led-test.py")
RESULTS_DIR    = File.join(__DIR__, "..", "docs", "led-test-results")

if ARGV.empty?
  STDERR.puts "Usage : nas-led-test <nom>"
  exit 1
end

name = ARGV[0]
ip = NasFleet.resolve(name)

unless ip
  STDERR.puts "Unité inconnue : #{name}. L'enregistrer via : nas-connect --set #{name} <ip>"
  exit 1
end

use_binary = File.exists?(PROBE_BINARY)

unless use_binary || File.exists?(PYTHON_PAYLOAD)
  STDERR.puts "Aucun payload disponible (ni #{PROBE_BINARY}, ni #{PYTHON_PAYLOAD})."
  exit 1
end

remote_path = use_binary ? "/root/led_probe" : "/root/nas-led-test.py"
local_path = use_binary ? PROBE_BINARY : PYTHON_PAYLOAD

puts "[#{name}] envoi du protocole de test (#{use_binary ? "binaire natif" : "script Python, repli"})..."
scp_status = Process.run("scp", [
  "-i", NasFleet::SSH_KEY,
  "-o", "StrictHostKeyChecking=accept-new",
  local_path,
  "root@#{ip}:#{remote_path}",
])
unless scp_status.success?
  STDERR.puts "[#{name}] échec de l'envoi (scp)."
  exit 1
end

remote_command = use_binary ? "chmod +x #{remote_path} && #{remote_path}" : "python3 #{remote_path}"

puts "[#{name}] exécution..."
output = IO::Memory.new
status = Process.run("ssh", NasFleet.ssh_args(ip) + [remote_command],
  output: output, error: output)

result = output.to_s
puts result

Dir.mkdir_p(RESULTS_DIR)
stamp = Time.local.to_s("%Y%m%dT%H%M%S")
log_path = File.join(RESULTS_DIR, "#{name}-#{stamp}.txt")
File.write(log_path, result)

puts
puts "[#{name}] #{status.success? ? "terminé" : "ERREUR pendant l'exécution distante"} — journalisé dans #{log_path}"
