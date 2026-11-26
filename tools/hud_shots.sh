#!/usr/bin/env bash
# The HUD judge's shots: five states at three resolutions, <out>/<res>/<state>.png (docs/hud-judge-brief.md).
#   tools/hud_shots.sh [OUT_DIR]        default screenshots/hud_judge
# States: pickup, downed (view down), loading (view cover), crawl, heal. Run it through gpu.sh shot so a real GPU renders
# it, then judge with: gs_game_visual_judge.sh --shots OUT_DIR --brief docs/hud-judge-brief.md --capture '...'
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-screenshots/hud_judge}"
mkdir -p "$out"
states=(pickup:pickup downed:down loading:cover crawl:crawl heal:heal)
for res in 1280x720:720p 1920x1080:1080p 2560x1440:1440p; do
    for st in "${states[@]}"; do
        dir="$out/${res#*:}"
        mkdir -p "$dir"
        # A Godot abort at quit (exit 134) after the frame was saved is not a missing shot: the file decides.
        rm -f "$dir/${st%%:*}.png"
        RESOLUTION="${res%%:*}" tools/shot.sh "--view=${st#*:}" --settled "--name=hud_${res#*:}_${st%%:*}" "--out=res://${out}/${res#*:}/${st%%:*}.png" || echo "hud_shots: shot.sh exited $? for ${res#*:} ${st%%:*}" >&2
        [ -s "$dir/${st%%:*}.png" ] || { echo "hud_shots: no frame for ${res#*:} ${st%%:*}" >&2; exit 1; }
    done
done
ls "$out"/*/*.png | wc -l
