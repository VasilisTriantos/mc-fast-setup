#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
./apply-firewall.sh
mkdir -p minecraft mods
docker compose up -d
echo 'Follow startup: docker compose logs -f'
