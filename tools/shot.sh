#!/usr/bin/env bash
# Render the game and look at it. The check no assertion in this repository makes.
#
#   tools/shot.sh --view=overview                                  # the map, from above
#   tools/shot.sh --view=room --at=0,1.7,-6 --look=0,1,-14          # a free camera
#   tools/shot.sh --view=survivor --spawn=common:12,leaper:1        # your eyes, with a crowd coming
#   tools/shot.sh --view=third --spawn=brute:1                       # third person
#   tools/shot.sh --view=down --spawn=common:6                       # on the floor
#   tools/shot.sh --view=pinned --pin=choke                          # a friend tongued
#   tools/shot.sh --view=survivor --box=mystery                      # a box on the ground
#   tools/shot.sh --view=survivor --board                            # with the Tab scoreboard open
#   tools/shot.sh --view=overview --zz-map-ids=zz_x --out=res://screenshots/x.png
#
# xvfb-run because this needs a rendering context: `--headless` gives a null renderer and saves
# a frame of nothing, which is worse than no screenshot because it looks like one.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p screenshots

view="survivor"
seconds="3"
out=""
config=("--zz-warmup-seconds=0" "--zz-start-grace-seconds=0" "--zz-wanderer-density=0")
extra=()

for arg in "$@"; do
    case "$arg" in
        --view=*)    view="${arg#*=}" ;;
        --seconds=*) seconds="${arg#*=}" ;;
        --out=*)     out="${arg#*=}" ;;
        --zz-*)      config+=("$arg") ;;
        --at=*|--look=*|--spawn=*|--pin=*|--box=*|--board|--name=*) extra+=("$arg") ;;
        *)           echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

name="$view"
for e in "${extra[@]}"; do
    case "$e" in --name=*) name="${e#*=}" ;; esac
done
[ -n "$out" ] || out="res://screenshots/${name}.png"

exec xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --path . --resolution 1280x720 \
    res://tools/shot.tscn -- "--seconds=$seconds" "--view=$view" "--out=$out" "${extra[@]}" "${config[@]}"
