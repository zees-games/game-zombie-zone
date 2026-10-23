#!/usr/bin/env bash
# Render the settings menu's Video page (Blood splatters row) to screenshots/menu_video*.png.
# xvfb-run: --headless has a null renderer and saves empty frames.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p screenshots
exec timeout 120 xvfb-run -a godot --path . --resolution 1600x900 --script tools/menu_shot.gd
