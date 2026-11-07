#!/usr/bin/env bash
# The survivors' look, front, back and heads, with nothing else in the frame (see lineup.gd).
#   tools/lineup.sh --out=/some/dir [--warm]
set -euo pipefail
cd "$(dirname "$0")/.."
exec xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --path . --resolution 1280x720 --rendering-method gl_compatibility --rendering-driver opengl3 res://tools/lineup.tscn -- "$@"
