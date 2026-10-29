#!/usr/bin/env bash
# Records one clip of tools/filmstrip_scenarios.json in one view (fp or tp) with --write-movie at a
# fixed frame rate and makes its contact sheet. Needs a display: tools/filmstrip.sh runs it on a
# GPU box under xvfb.
#   tools/filmstrip_run.sh <clip> <fp|tp> [fps]
set -euo pipefail
cd "$(dirname "$0")/.."
clip=${1:?clip}; view=${2:?view}; fps=${3:-15}
out=screenshots/filmstrip
name=$clip; [[ $clip == zombie_* ]] || name=${clip}_$view
mkdir -p "$out"
log=$out/$name.log
timeout 300 xvfb-run -a godot --path . --resolution 960x540 --fixed-fps "$fps" \
  --write-movie "$out/$name.avi" --script res://tools/filmstrip_capture.gd -- "$clip" "$view" --zz-map-ids=zz_practice > "$log" 2>&1 || true
grep -E "^(clip |PASS|FAIL|SKIP|SCRIPT ERROR|ERROR)" "$log" | head -n 30
# The movie includes the cover and the wait for the round: cut it to the clip itself.
read -r first count < <(sed -n 's/^FILMSTRIP_CLIP start_frame=\([0-9]*\) frames=\([0-9]*\)/\1 \2/p' "$log")
if [[ -n ${first:-} ]]; then
  ffmpeg -v error -y -i "$out/$name.avi" -vf "select=gte(n\\,$first),setpts=N/(FRAME_RATE*TB)" -vsync passthrough -frames:v "$count" -c:v mjpeg -q:v 3 "$out/$name.cut.avi"
  mv "$out/$name.cut.avi" "$out/$name.avi"
fi
bash addons/dot_core/tools/dot_filmstrip.sh "$out/$name.avi" "$out/$name" --views "$view"
