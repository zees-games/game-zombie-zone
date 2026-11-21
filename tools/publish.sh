#!/bin/bash
# Publishes this game's pack (id game-zombie-zone). world/ and maps/ link to zombie-zone-maps (their own packs); the rest are not runtime content.
#   tools/publish.sh [--version V | --bump patch] [--site URL --token-file F --dry-run ...]   (lock: ./content.lock.json, override with --lock)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
X=(); for d in world maps tools screenshots reports art-src tests examples images docs .github; do X+=(--exclude-dir "$d"); done
# A linked addon the host shell does not own (another game's addon a checkout links) must not ship inside the pack: mounted
# under gs_cloud/<id>/<ver>/addons/ its class names do not resolve and the solo shell reports parse errors (0.1.11 did).
for l in "$HERE"/addons/*; do [ -L "$l" ] && [[ "$(basename "$l")" != gs_* ]] && X+=(--exclude-dir "addons/$(basename "$l")"); done
PUB="$HERE/../gs-cloud/tools/publish_pack.sh"; HOSTLOCK="$HERE/../gs-server-deploy/addons.lock"; GV=0.0.0
BASE=(publish --source "$HERE" --id game-zombie-zone --host-addons "$HOSTLOCK" "${X[@]}")
# Gates before an upload: every load of the game's own files goes through the game's path rebase
# (tools/check_pack_paths.sh), and publish_pack.sh boots the pack it builds mounted, under res://gs_cloud/<id>/<version>/,
# on a host built at --host-addons addons.lock's tags (gs-cloud tools/pack_boot_test.sh; exit 1 does not boot, 2 could
# not judge). Airdrift and Playlot 0.1.33, Zombie Zone 0.1.40 and Hungario 0.1.19 booted nothing on servers without it.
"$HERE/tools/check_pack_paths.sh" "$HERE"
exec "$PUB" "${BASE[@]}" --lock "$HERE/content.lock.json" "$@"
