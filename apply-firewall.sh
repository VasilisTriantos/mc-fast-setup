#!/usr/bin/env bash
# Allow only the IPs in allowed-ips.txt to reach the Minecraft port (via firewalld).
#   priority -110  drop all   (temporary, held while the allowlist is being updated)
#   priority -100  accept     (one per allowed IP)
#   priority  -90  drop all   (permanent: everyone not listed)
# On a detected command or input failure everything stays blocked and Minecraft is stopped (this also
# disconnects current players, which firewall rules alone cannot do). A kill or power
# loss mid-update cannot run the handler, but the saved config keeps the block until
# the final save.
# Note: saving also persists any other unsaved runtime changes in firewalld.
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

ZONE=public     # the zone your network interface is in: firewall-cmd --get-active-zones
PROTOCOL=tcp
. ./lib.sh
PORT=$(env_get PORT)    # the single source of the port is .env
if [[ ! $PORT =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "PORT in .env must be a number from 1 to 65535 (got '$PORT')." >&2
  exit 1
fi

if [[ ! -f allowed-ips.txt ]]; then
  echo "allowed-ips.txt not found. Create it: cp allowed-ips.example.txt allowed-ips.txt" >&2
  exit 1
fi

MATCH="port port=\"$PORT\" protocol=\"$PROTOCOL\""
BLOCK_ALL="rule priority=\"-110\" $MATCH drop"
DROP="rule priority=\"-90\" $MATCH drop"

fw()  { sudo firewall-cmd --zone="$ZONE" "$@" >/dev/null; }
has() { sudo firewall-cmd --zone="$ZONE" "$@" >/dev/null 2>&1; }

# Adds a rich rule to the runtime config unless it is already there.
ensure() { has --query-rich-rule="$1" || fw --add-rich-rule="$1"; }

fail_closed() {
  trap - ERR
  set +e
  echo "FAILED: $1" >&2
  ensure "$BLOCK_ALL" && sudo firewall-cmd --runtime-to-permanent >/dev/null 2>&1
  if has --query-rich-rule="$BLOCK_ALL" && has --permanent --query-rich-rule="$BLOCK_ALL"; then
    echo "All remote players are BLOCKED (runtime and saved config)." >&2
  else
    echo "WARNING: could NOT confirm the block rule. The port may be OPEN." >&2
  fi
  if docker compose stop >/dev/null 2>&1; then
    echo "Minecraft is stopped; no players are connected." >&2
  else
    echo "WARNING: could NOT stop Minecraft. Run: docker compose stop" >&2
  fi
  exit 1
}
trap 'fail_closed "command failed at line $LINENO"' ERR

valid_v4() {
  local o; local -a octets
  [[ $1 =~ ^[0-9]+(\.[0-9]+){3}$ ]] || return 1
  IFS=. read -ra octets <<< "$1"
  for o in "${octets[@]}"; do (( 10#$o <= 255 )) || return 1; done
}

# 1. Block everyone, runtime and saved, before touching anything else.
ensure "$BLOCK_ALL"
sudo firewall-cmd --runtime-to-permanent >/dev/null

# 2. Check address format (firewalld validates IPv6 fully when the rule is added).
ips=()
while IFS= read -r line || [[ -n $line ]]; do
  ip=${line%%#*}; ip=${ip%%//*}
  ip=${ip#"${ip%%[![:space:]]*}"}; ip=${ip%"${ip##*[![:space:]]}"}
  [[ -z $ip ]] && continue
  if valid_v4 "$ip" || [[ $ip == *:* && $ip =~ ^[0-9a-fA-F:.]+$ ]]; then
    ips+=("$ip")
  else
    fail_closed "invalid IP address '$ip' (from: $line)"
  fi
done < allowed-ips.txt

# 3. Rebuild the allowlist while the block is active.
fw --remove-port="$PORT/$PROTOCOL" 2>/dev/null || true
ensure "$DROP"
rules=$(sudo firewall-cmd --zone="$ZONE" --list-rich-rules)
while IFS= read -r rule; do
  [[ $rule == *'priority="-100"'* && $rule == *"$MATCH"* ]] && fw --remove-rich-rule="$rule"
done <<< "$rules"
for ip in "${ips[@]}"; do
  family=ipv4; [[ $ip == *:* ]] && family=ipv6
  fw --add-rich-rule="rule priority=\"-100\" family=\"$family\" source address=\"$ip\" $MATCH accept"
  echo "allowed $ip"
done

# 4. Save the rebuilt allowlist (block still active), then lift the block and save again.
sudo firewall-cmd --runtime-to-permanent >/dev/null
fw --remove-rich-rule="$BLOCK_ALL"
sudo firewall-cmd --runtime-to-permanent >/dev/null
trap - ERR
echo "Done ($ZONE zone). Active rules:"; sudo firewall-cmd --zone="$ZONE" --list-rich-rules
