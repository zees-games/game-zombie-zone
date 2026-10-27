#!/usr/bin/env bash
# Render the game and look at it. The check no assertion in this repository makes.
#
#   tools/shot.sh --view=overview                                  # the map, from above
#   tools/shot.sh --view=cover                                     # the loading cover, before it lifts
#   tools/shot.sh --view=room --at=0,1.7,-6 --look=0,1,-14          # a free camera
#   tools/shot.sh --view=room --alone --zz-map-ids=zz_blackout_1 --at=16.6,1.6,65.4 --look=18,1.1,66   # a close-up, stand-ins left in the start room
#   tools/shot.sh --view=survivor --spawn=common:12,leaper:1        # your eyes, with a crowd coming
#   tools/shot.sh --view=third --spawn=brute:1                       # third person
#   tools/shot.sh --view=room --aim=40 --at=0,0.05,12          # the stand-ins aiming 40 degrees up, from the side
#   tools/shot.sh --view=down --spawn=common:6                       # on the floor
#   tools/shot.sh --view=strike_down --zombie=common --seconds=1.2     # a zombie kneeling over a downed survivor (strike: standing)
#   tools/shot.sh --view=ragdoll --seconds=0.6 --reaction=face_plant  # a stand-in killed, its body 0.6 s into the fall
#   tools/shot.sh --view=action --action=emote:dance --seconds=0.5   # a stand-in playing an avatar action (pose:sit)
#   tools/shot.sh --view=pinned --pin=choke                          # a friend tongued
#   tools/shot.sh --view=hit --spawn=common:6                        # confirmed hits, borrowed health, a hold-out clock
#   tools/shot.sh --view=survivor --spawn=ram:2 --hard=5          # five Hard Box stacks: mutants drawn faded
#   tools/shot.sh --view=survivor --box=mystery                      # a box on the ground
#   tools/shot.sh --view=crawl                                       # down, crawling, the speed boxes in the strip (crawl_third: the figure)
#   tools/shot.sh --view=killcam --seconds=3                         # the last stand replayed (--seconds=9: the podium)
#   tools/shot.sh --view=trader                                      # the trader menu open at the start
#   tools/shot.sh --view=deploy --seconds=2.5                        # carrying a box, primary fire held that long (deploy_third, deploy_side)
#   tools/shot.sh --view=survivor --board                            # with the Tab scoreboard open
#   tools/shot.sh --view=ads --out=res://screenshots/ads          # hip, raising and aimed: an iron sight and a scope
#   tools/shot.sh --view=crosshair --out=res://screenshots/crosshair   # the spread crosshair at rest, walking, running, crouched, aimed
#   tools/shot.sh --view=room --zz-map-ids=zm_4way_tunnel --fire=break_roof_spawn:ForceSpawn --at=...   # a maker's copies
#   tools/shot.sh --view=crates --seconds=1.2                         # a ring of crates, frames before the blast and 0, 0.35 s and --seconds after
#   tools/shot.sh --view=weapons --weapons=all --out=res://screenshots/weapons   # fire + reload sheet per gun
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
        --at=*|--look=*|--spawn=*|--zombie=*|--sever=*|--pin=*|--pin-me|--alone|--box=*|--hard=*|--workshop|--board|--name=*|--weapons=*|--aim=*|--door=*|--fire=*|--tint|--reaction=*|--action=*|--no-bake|--no-world|--standalone_content=*|--cloud-store=*|--day=*) extra+=("$arg") ;;
        *)           echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# A contact sheet is of the gun in hand: the stand-ins an exodus map seats beside the camera put
# their own rifles in the corner of every hip frame (the yellow and blue shape bottom-left).
[ "$view" = "weapons" ] && config+=("--zz-exodus-team=1")

# The crates view wants flat open ground; the default map choice can land on a converted wall.
if [ "$view" = "crates" ] && [[ " ${config[*]} " != *" --zz-map-ids="* ]]; then config+=("--zz-map-ids=zz_lot"); fi

name="$view"
for e in "${extra[@]}"; do
    case "$e" in --name=*) name="${e#*=}" ;; esac
done
[ -n "$out" ] || out="res://screenshots/${name}.png"

exec xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --path . --resolution 1280x720 \
    res://tools/shot.tscn -- "--seconds=$seconds" "--view=$view" "--out=$out" "${extra[@]}" "${config[@]}"
