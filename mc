#!/usr/bin/env bash
# Everyday admin helper. Run ./mc with no arguments for the list of commands.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
. ./lib.sh
C=minecraft

usage() {
  cat <<U
Usage: ./mc <command>
  start             apply the firewall and start the server (same as ./up.sh)
  stop              stop the server (waits for the world to save)
  restart           restart the server (firewall rules stay as they are)
  status            container state, health, uptime, memory, port and last log lines
  logs              follow the server log (Ctrl-C only stops the log view)
  cmd <command...>  run a server console command and show its output, e.g. ./mc cmd op Steve
  players           list online players
  backup            back up the world and configs to ./backups
U
}

running() { [[ $(docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null) == true ]]; }

# Sends a console command and prints what the server logged in reply.
send() {
  local since
  running || { echo "Server is not running." >&2; return 1; }
  since=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
  docker exec --user "$(env_get MC_UID)" "$C" mc-send-to-console "$@"
  sleep 1
  docker logs --since "$since" "$C" 2>&1 | sed 's/\r$//'
}

case ${1:-} in
  start)   ./up.sh ;;
  stop)    docker compose stop ;;
  restart) docker compose restart ;;
  status)
    if ! running; then echo "Server is stopped."; exit 0; fi
    docker inspect -f 'State:   {{.State.Status}}, health: {{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}
Started: {{.State.StartedAt}}' "$C"
    docker stats --no-stream --format 'Memory:  {{.MemUsage}}  CPU: {{.CPUPerc}}' "$C"
    echo "Port:    $(env_get PORT)/tcp  online-mode: $(env_get ONLINE_MODE)"
    echo "--- last log lines ---"
    docker logs --tail 5 "$C" 2>&1 | sed 's/\r$//'
    ;;
  logs)    docker compose logs -f --tail 100 ;;
  cmd)     shift; [[ $# -gt 0 ]] || { usage; exit 1; }; send "$@" ;;
  players) send list ;;
  backup)  ./backup.sh ;;
  *)       usage; [[ -z ${1:-} || $1 == help || $1 == -h || $1 == --help ]] || exit 1 ;;
esac
