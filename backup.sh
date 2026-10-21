#!/usr/bin/env bash
# Backs up ./minecraft (world, configs) to ./backups/minecraft-<timestamp>.tar.gz and
# keeps the newest BACKUP_KEEP archives (from .env, default 7). Mods are not included:
# they live in ./mods. Safe to run while the server is up (saving is paused meanwhile).
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
. ./lib.sh
C=minecraft
KEEP=$(env_get BACKUP_KEEP); KEEP=${KEEP:-7}
[[ $KEEP =~ ^[1-9][0-9]*$ ]] || { echo "BACKUP_KEEP in .env must be a positive number." >&2; exit 1; }

console() { docker exec --user "$(env_get MC_UID)" "$C" mc-send-to-console "$@"; }
live=false
[[ $(docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null) == true ]] && live=true

if $live; then
  # Always turn saving back on, even if the backup fails.
  trap 'console save-on >/dev/null 2>&1 || echo "WARNING: could not run save-on. Run: ./mc cmd save-on" >&2' EXIT
  since=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
  console save-off
  console save-all flush
  saved=false
  for _ in $(seq 60); do
    # Capture first: grep -q exiting early would SIGPIPE docker logs and trip pipefail.
    logs=$(docker logs --since "$since" "$C" 2>&1 || true)
    if [[ $logs == *'Saved the game'* ]]; then saved=true; break; fi
    sleep 1
  done
  $saved || { echo "Timed out waiting for the world to save; no backup made." >&2; exit 1; }
fi

mkdir -p backups
out=backups/minecraft-$(date +%Y%m%d-%H%M%S).tar.gz
tar -czf "$out.partial" --exclude='./logs' --exclude='./crash-reports' -C minecraft .
mv "$out.partial" "$out"
echo "Backup written: $out ($(du -h "$out" | cut -f1))"

# Keep only the newest $KEEP archives.
ls -1t backups/minecraft-*.tar.gz | tail -n +"$((KEEP + 1))" | xargs -r rm -v --
