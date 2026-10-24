#!/usr/bin/env bash
# Drives the real client with injected input and renders frames: tools/verify_ui.sh trader|crouch|nav [--zz-...]
set -euo pipefail
cd "$(dirname "$0")/.."
check="$1"; shift
# nav needs a build slow enough to watch: no cache, main thread, a small slice a tick.
slow=()
[ "$check" = nav ] && slow=(--zz-nav-cache=false --zz-nav-threads=0 --zz-nav-budget-ms=0.5)
exec xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --path . --resolution 1280x720 \
    res://tools/verify_ui.tscn -- "--check=$check" "--out=res://screenshots/verify" \
    --zz-warmup-seconds=0 --zz-start-grace-seconds=0 --zz-wanderer-density=0 "${slow[@]}" "$@"
