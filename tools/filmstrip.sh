#!/usr/bin/env bash
# Plays the scripted clips of tools/filmstrip_scenarios.json on GPU box staging02, or GPU_SHOT_BOXES (xvfb, never the
# desktop session) and brings back screenshots/filmstrip/<clip>[_fp|_tp]_sheet.png, .mp4 and
# _report.txt (foot slide, floor contact, framing, bone pops against tools/filmstrip_thresholds.json).
#   tools/filmstrip.sh [clip...]     # default: every clip, in each of its views
#   FPS=20 tools/filmstrip.sh fire
set -euo pipefail
cd "$(dirname "$0")/.."
out=screenshots/filmstrip
mkdir -p "$out"
mapfile -t jobs < <(python3 - "$@" <<'PY'
import json, sys
doc = json.load(open("tools/filmstrip_scenarios.json"))
for c in doc["clips"]:
    if len(sys.argv) > 1 and c["name"] not in sys.argv[1:]:
        continue
    views = {**doc.get("defaults", {}), **c.get("fields", {})}.get("views", ["tp"])
    for v in views:
        print(c["name"], v)
PY
)
gpu_sh=${GPU_SH:-}
for c in /home/gamedev/godot/dot-bootstrap/tools/gpu.sh ../gpu.sh; do
  [[ -z $gpu_sh && -f $c ]] && gpu_sh=$c
done
[[ -f $gpu_sh ]] || { echo "gpu.sh not found (set GPU_SH=path)" >&2; exit 1; }
box=${GPU_SHOT_BOXES:-staging02}
host=gamedev@${box%%[ ,]*}.deacon.internal   # GPU_SHOT_BOXES=staging runs it on the laptop
for job in "${jobs[@]}"; do
  read -r clip view <<< "$job"
  name=$clip; [[ $clip == zombie_* ]] || name=${clip}_$view
  GPU_SHOT_BOXES=$box "$gpu_sh" shot game-zombie-zone tools/filmstrip_run.sh "$clip" "$view" "${FPS:-15}"
  rsync -az -e "ssh -i $HOME/.ssh/gpu-laptop -o BatchMode=yes" \
    "$host:gpu/shot/game-zombie-zone/$out/$name.mp4" "$host:gpu/shot/game-zombie-zone/$out/${name}_report.txt" "$out/"
done
echo "sheets in $out/"
