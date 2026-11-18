#!/bin/bash
# Publishes this game's pack (id game-zombie-zone). world/ and maps/ link to zombie-zone-maps (their own packs); the rest are not runtime content.
#   tools/publish.sh [--version V | --bump patch] [--site URL --token-file F --dry-run ...]   (lock: ./content.lock.json, override with --lock)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
X=(); for d in world maps tools screenshots reports art-src tests examples images docs .github; do X+=(--exclude-dir "$d"); done
# A linked addon the host shell does not own (another game's addon a checkout links) must not ship inside the pack: mounted
# under dot_cloud/<id>/<ver>/addons/ its class names do not resolve and the solo shell reports parse errors (0.1.11 did).
for l in "$HERE"/addons/*; do [ -L "$l" ] && [[ "$(basename "$l")" != dot_* ]] && X+=(--exclude-dir "addons/$(basename "$l")"); done
PUB="$HERE/../dot-cloud/tools/publish_pack.sh"; HOSTLOCK="$HERE/../dot-server-deploy/addons.lock"; GV=0.0.0
BASE=(publish --source "$HERE" --id game-zombie-zone --host-addons "$HOSTLOCK" "${X[@]}")
# Gates before an upload (a --dry-run gets the first only): every load of the game's own files goes through the
# game's path rebase (tools/check_pack_paths.sh), and the pack a dry run builds boots mounted, under
# res://dot_cloud/<id>/<version>/, on a host built at addons.lock's tags (tools/pack_boot_test.sh). Airdrift and
# Playlot 0.1.33 and Zombie Zone 0.1.40 failed the second (stale trees, a renamed addon) and booted nothing on servers.
"$HERE/tools/check_pack_paths.sh" "$HERE"
case " $* " in *" --dry-run "*) ;; *)
    G=(); skip=""
    for a in "$@"; do
        if [ -n "$skip" ]; then [ "$skip" = --version ] && GV="$a"; skip=""; continue; fi
        case "$a" in --version|--bump|--out|--site|--token-file|--lock) skip="$a" ;; *) G+=("$a") ;; esac
    done
    T="$(mktemp -d)"
    if ! "$PUB" "${BASE[@]}" --version "$GV" "${G[@]}" --dry-run --out "$T/out" >&2 \
        || ! "$HERE/tools/pack_boot_test.sh" "$T/out" "$HOSTLOCK"; then
        rm -rf "$T"; echo "publish: refusing to upload (gates above); nothing was sent" >&2; exit 1
    fi
    rm -rf "$T"; set -- "$@" --no-import ;;
esac
exec "$PUB" "${BASE[@]}" --lock "$HERE/content.lock.json" "$@"
