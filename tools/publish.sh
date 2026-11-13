#!/bin/bash
# Publishes this game's pack (id game-zombie-zone). world/ and maps/ link to zombie-zone-maps (their own packs); the rest are not runtime content.
#   tools/publish.sh [--version V | --bump patch] [--site URL --token-file F --dry-run ...]   (lock: ./content.lock.json, override with --lock)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
X=(); for d in world maps tools screenshots reports art-src tests examples images docs .github; do X+=(--exclude-dir "$d"); done
# A linked addon the host shell does not own (arena_weapons, optional and reached by path) must not ship inside the pack: mounted
# under dot_cloud/<id>/<ver>/addons/ its class names do not resolve and the solo shell reports parse errors (0.1.11 did).
for l in "$HERE"/addons/*; do [ -L "$l" ] && [[ "$(basename "$l")" != dot_* ]] && X+=(--exclude-dir "addons/$(basename "$l")"); done
exec "$HERE/../dot-cloud/tools/publish_pack.sh" publish --source "$HERE" --id game-zombie-zone --host-addons "$HERE/../dot-server-deploy/addons.lock" "${X[@]}" --lock "$HERE/content.lock.json" "$@"
