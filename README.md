# Minecraft (Forge 1.20.1) in Docker, with an IP allowlist

Forge 47.3.0, Minecraft 1.20.1, Java 17, via `itzg/minecraft-server` on native Docker
(Arch/EndeavourOS, firewalld). The container uses host networking.

## How the firewall works
`apply-firewall.sh` reads `allowed-ips.txt` and manages firewalld rich rules for the
Minecraft port in one zone (`ZONE`, default `public`):

| Priority | Rule | Purpose |
|---|---|---|
| -110 | drop all | temporary, held while the list is being updated |
| -100 | accept | one per allowed IP |
| -90 | drop all | permanent: everyone not listed |

Lower numbers run first. The update order is: block everyone (runtime and saved),
rebuild the allowlist, save, lift the temporary block, save again.

**Fail closed:** on a detected command or input failure (including an invalid line in
`allowed-ips.txt`), the script keeps everyone blocked, saves that, stops Minecraft
with `docker compose stop` and exits with an error. It reports whether blocking and
stopping were actually confirmed. A kill or power loss mid-update can't run the
handler, but the saved config keeps the block until the final save.

## Setup
1. `sudo pacman -Syu docker docker-compose firewalld`, then add yourself to the
   `docker` group and log in again.
2. Copy `.env.example` to `.env` (the real file is git-ignored) and edit it. The template has `EULA=FALSE`; set `EULA=TRUE` (after agreeing to https://www.minecraft.net/eula),
   `MC_UID`/`MC_GID` (`id -u`, `id -g`) and `MEMORY`. `PORT` (default 25565),
   `ONLINE_MODE` (default `TRUE`) and `BACKUP_KEEP` are also there.
   Leave `ONLINE_MODE=TRUE` unless the server is on a closed network: `FALSE` lets
   anyone join under any username, including ops.
3. Copy `allowed-ips.example.txt` to `allowed-ips.txt` (the real file is git-ignored) and put in one IPv4/IPv6 address per line.
   Everything after `#` or `//` is a comment. No hostnames or CIDR ranges.
   ```
   203.0.113.7    # Steve
   192.168.1.42   // my LAN PC
   ```
4. Check your interface's zone (`firewall-cmd --get-active-zones`) and set `ZONE`
   at the top of `apply-firewall.sh` if it isn't `public`.
5. `sudo systemctl enable --now docker firewalld`
6. Put mod `.jar` files in `./mods/`.
7. For internet play, forward port 25565/tcp on your router to this machine.

## Use
- Start: `./up.sh` (applies the firewall, then `docker compose up -d`).
  First start downloads Forge and takes a few minutes: `docker compose logs -f`.
- Change who can join: edit `allowed-ips.txt`, run `./apply-firewall.sh`.
  This affects new connections only. To disconnect anyone you removed, restart the server.
- Restart: `docker compose restart` (the firewall rules stay as they are).
- Stop: `docker compose stop` (waits for the world to save).
- After a reboot, the server does not start by itself. Run `./up.sh`.
- Check rules: `sudo firewall-cmd --list-rich-rules` (expect one `-100` accept per IP,
  one `-90` drop, no `-110`).
- Console: `docker attach minecraft`; detach with `Ctrl-P` `Ctrl-Q`. **Do not press `Ctrl-C`**, which stops the server.
  Safer: `./mc cmd <command>` (see below).
- Empty `allowed-ips.txt` blocks all remote players. Localhost always works.

## Admin helpers
`./mc` (a script in this folder, next to `up.sh`; run it from here) wraps the everyday tasks:

| Command | What it does |
|---|---|
| `./mc start` / `stop` / `restart` | start (with firewall), stop, restart |
| `./mc status` | state, health, uptime, memory, port, last log lines |
| `./mc logs` | follow the log (`Ctrl-C` here only ends the log view) |
| `./mc cmd <command>` | run a console command and show the reply, e.g. `./mc cmd op Steve` |
| `./mc players` | list online players |
| `./mc backup` | same as `./backup.sh` |

Commands are sent through the console pipe (`CREATE_CONSOLE_IN_PIPE`), so RCON stays off
and no extra port is opened. The container has a healthcheck (`mc-health`): the status
is `starting` for up to 5 minutes (modded startup is slow), then `healthy`; see `docker ps`.

### Interactive console
For a live console instead of one-off commands, run `docker attach minecraft`. Type
commands without a `/`. Detach with `Ctrl-P` then `Ctrl-Q`. **Do not press `Ctrl-C`**,
which stops the server. If the prompt looks empty, press Enter to see the latest output.

## Backups
`./backup.sh` (or `./mc backup`) pauses world saving, flushes it, archives `./minecraft`
(without logs and crash reports) to `./backups/minecraft-<time>.tar.gz`, turns saving back on
and deletes all but the newest `BACKUP_KEEP` archives. It also works while the server is
stopped. Mods are not included (they are in `./mods`). For regular backups, run it from
cron or a systemd timer, e.g. `0 4 * * * /path/to/minecraft-docker/backup.sh`.
To restore: stop the server, empty `./minecraft`, extract the archive into it, start.
Copy `./backups` somewhere off this machine as well.

## Changing the port
Change `PORT` in `.env` (the only place it is set), then run `./up.sh`.
Rules for the old port remain; remove them with `sudo firewall-cmd --permanent --zone=public --remove-rich-rule='...'`
(see the list command above) and `--reload`.

## Limits
- Saving persists any other unsaved runtime changes in firewalld.
- Traffic arriving in a different zone, or matched by rules with a lower priority
  number than -110, bypasses these rules.
- Test with one allowed and one unlisted remote IP before relying on it.

## Remove the firewall rules
Run `sudo firewall-cmd --list-rich-rules`, remove each rule that mentions the Minecraft
port with `sudo firewall-cmd --permanent --remove-rich-rule='<rule>'`, then
`sudo firewall-cmd --reload`.

## License
MIT, see [LICENSE](LICENSE).
