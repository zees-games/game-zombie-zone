#!/usr/bin/env bash
# Drives the real client with injected input and renders frames: tools/verify_ui.sh trader|crouch|nav [--zz-...]
set -euo pipefail
cd "$(dirname "$0")/.."
check="$1"; shift
exec xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --path . --resolution 1280x720 \
    res://tools/verify_ui.tscn -- "--check=$check" "--out=res://screenshots/verify" \
    --zz-warmup-seconds=0 --zz-start-grace-seconds=0 --zz-wanderer-density=0 "$@"
