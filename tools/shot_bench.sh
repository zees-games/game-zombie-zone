#!/usr/bin/env bash
# A fixed-seed frame benchmark (tools/bench.gd): prints one BENCH line. Named shot_* so heavy
# sends it to a GPU box like every other rendering tool; GPU_OFFLOAD=0 keeps it here (llvmpipe).
#
#   tools/shot_bench.sh --zz-map-ids=zm_abandoned_mall --zombies=56 [--measure=20] [--seed=7] [--at=x,y,z]
set -euo pipefail
cd "$(dirname "$0")/.."
config=("--zz-warmup-seconds=0" "--zz-start-grace-seconds=0" "--zz-wanderer-density=0" "--zz-survival-warmup-seconds=300" "--zz-director-enabled=false")
extra=()
for arg in "$@"; do
    case "$arg" in
        --zz-*) config+=("$arg") ;;
        *)      extra+=("$arg") ;;
    esac
done
exec xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --path . --resolution 1280x720 \
    res://tools/bench.tscn -- "--view=bench" "${extra[@]}" "${config[@]}"
