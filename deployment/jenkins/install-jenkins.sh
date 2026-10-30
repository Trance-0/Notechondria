#!/usr/bin/env bash
# Ubuntu host installer. Run as the desktop user; sudo is requested for system changes.
set -Eeuo pipefail
umask 077
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${NOTECHONDRIA_REPO_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/jenkins-install"
mkdir -p "$STATE_DIR"
LOG_FILE="$STATE_DIR/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
STAGE=preflight
log() { printf '%s INFO Jenkins.Install/%s — %s\n' "$(date -Is)" "$STAGE" "$*"; }
diagnostics() {
  local status=$?
  trap - ERR
  set +e
  sudo systemctl unmask --runtime jenkins.service >/dev/null 2>&1
  printf '\n--- BEGIN JENKINS INSTALL DIAGNOSTICS ---\n'
  printf 'Installation incomplete: Jenkins.Install/%s — exit=%s line=%s\n' "$STAGE" "$status" "${BASH_LINENO[0]}"
  printf 'Log: %s\n' "$LOG_FILE"
  uname -srm
  df -h / /var/lib/jenkins
  free -h
  dpkg-query -W jenkins openjdk-21-jre-headless 2>/dev/null
  systemctl is-active jenkins docker
  ss -ltn
  # Startup logs may contain initial passwords; redact before printing.
  sudo journalctl -u jenkins -n 60 --no-pager -o cat | python3 "$SCRIPT_DIR/redact_diagnostics.py"
  docker version --format 'Docker client={{.Client.Version}} server={{.Server.Version}}'
  printf '%s\n' '--- END JENKINS INSTALL DIAGNOSTICS ---'
  printf 'Copy the block above into chat. Full local log: %s\n' "$LOG_FILE"
  exit "$status"
}
trap diagnostics ERR
if [[ $EUID -eq 0 ]]; then
  log 'Installation cannot start — run bash ~/scripts/install-jenkins.sh as your normal user, not root.'
  false
fi
source /etc/os-release
[[ "$ID" == ubuntu ]]
[[ -f "$REPO_DIR/Jenkinsfile" && -d "$REPO_DIR/.git" ]]
command -v docker
docker info --format 'Docker server={{.ServerVersion}} architecture={{.Architecture}}'
docker compose version
sudo -v
PORT="${JENKINS_PORT:-8080}"
[[ "$PORT" =~ ^[0-9]+$ && "$PORT" -gt 0 && "$PORT" -lt 65536 ]]
if ! systemctl is-active --quiet jenkins && ss -H -ltn "sport = :$PORT" | python3 -c 'import sys; sys.exit(0 if sys.stdin.read().strip() else 1)'; then
  log "Installation cannot bind Jenkins — port $PORT is already occupied. Set JENKINS_PORT to a free port."
  false
fi
log "Preflight passed — repository=$REPO_DIR, Jenkins=http://127.0.0.1:$PORT, log=$LOG_FILE"

STAGE=packages
log 'Installing Java 21 and host tools — apt displays download and installation progress.'
sudo apt-get update
sudo apt-get install -y openjdk-21-jre-headless fontconfig curl ca-certificates git python3 rsync
sudo install -d -m 0755 /etc/apt/keyrings
KEY_FILE="$(mktemp)"
curl --fail --location --retry 3 --connect-timeout 20 --max-time 180 --progress-bar \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key -o "$KEY_FILE"
sudo install -m 0644 "$KEY_FILE" /etc/apt/keyrings/jenkins-keyring.asc
rm -f "$KEY_FILE"
printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/' | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null
sudo apt-get update
# Prevent the package's automatic startup before authentication and binding are configured.
sudo systemctl mask --runtime jenkins.service
sudo apt-get install -y jenkins
sudo systemctl stop jenkins
sudo systemctl unmask --runtime jenkins.service

STAGE=configuration
log 'Configuring the trusted local build host — Jenkins runs as the invoking user with existing Docker access.'
sudo install -d -m 0755 /etc/systemd/system/jenkins.service.d /usr/local/lib/notechondria-jenkins
sudo install -d -o "$(id -un)" -g "$(id -gn)" -m 0700 /var/lib/jenkins /var/cache/jenkins
sudo chown -R "$(id -un):$(id -gn)" /var/lib/jenkins /var/cache/jenkins
sudo python3 "$SCRIPT_DIR/configure_host.py" "$REPO_DIR" "$(id -un)" "$(id -gn)" "$PORT"

STAGE=plugins
log 'Installing Pipeline, GitHub, Git, and credential plugins — dependencies are resolved for the installed Jenkins version.'
MANAGER="$STATE_DIR/jenkins-plugin-manager-2.15.0.jar"
curl --fail --location --retry 3 --connect-timeout 20 --max-time 300 --progress-bar \
  https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.15.0/jenkins-plugin-manager-2.15.0.jar -o "$MANAGER"
printf '%s  %s\n' a86853ec2e2933f37a4b471ba65099b61e03c87a80c2ef8fe2315eb135672d43 "$MANAGER" | sha256sum -c -
WAR=/usr/share/java/jenkins.war
[[ -f "$WAR" ]] || WAR=/usr/share/jenkins/jenkins.war
timeout 30m java -jar "$MANAGER" --war "$WAR" --plugin-download-directory /var/lib/jenkins/plugins \
  --plugins workflow-aggregator pipeline-model-definition git github timestamper credentials-binding --verbose

STAGE=startup
log 'Starting Jenkins — waiting up to five minutes for the authenticated controller.'
sudo systemctl daemon-reload
sudo systemctl reset-failed jenkins
sudo systemctl enable --now jenkins
ready=false
for attempt in $(seq 1 60); do
  if curl -fsS --connect-timeout 3 --max-time 5 "http://127.0.0.1:$PORT/login" >/dev/null && [[ -f /var/lib/jenkins/.notechondria-bootstrap-complete ]]; then
    ready=true
    break
  fi
  if systemctl is-failed --quiet jenkins; then
    log 'Startup cannot complete — Jenkins service failed; collecting diagnostics immediately.'
    false
  fi
  log "Waiting for Jenkins initialization — attempt $attempt/60."
  sleep 5
done
[[ "$ready" == true ]]
python3 "$SCRIPT_DIR/verify_jenkins.py" "$PORT"
STAGE=complete
log "Installation verified — open http://127.0.0.1:$PORT/job/notechondria/ and select Build Now."
printf '\nAdmin username: admin\nPassword file (not printed in logs): /var/lib/jenkins/secrets/notechondria-admin-password\n'
printf 'Deployment env: /var/lib/jenkins/secrets/notechondria-deploy.env\n'
printf 'Install log: %s\n' "$LOG_FILE"
printf 'Collect diagnostics: bash ~/scripts/debug-jenkins.sh\n'
printf 'Future FRP target: 127.0.0.1:%s; webhook path: /github-webhook/\n' "$PORT"
