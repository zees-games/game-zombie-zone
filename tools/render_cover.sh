#!/usr/bin/env bash
# Render a real client's loading cover against a real server in a second process, and measure every
# frame across the transitions. Modes: join (default), change (map change with a connected client),
# slow (join over a lossy, delaying relay plus a stalled server build, then a map change), all.
# Look at every PNG in screenshots/cover_<mode>/ (join also writes cover_up.png etc. in screenshots/).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p screenshots
mode="${1:-join}"
if [ "$mode" = all ]; then
	rc=0
	for m in join change slow; do "$0" "$m" || rc=1; done
	exit $rc
fi
exec xvfb-run -a "${GODOT:-godot}" --path . --resolution 800x450 res://tools/render_cover.tscn -- "mode=$mode"
