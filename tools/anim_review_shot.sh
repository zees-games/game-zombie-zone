#!/usr/bin/env bash
# One animation-review capture on this machine (docs/anim-review.md): tools/anim_review.gd plays the survivor's weapon and
# locomotion clips in the offline client, then (with --zombies) the infected's clips on a bare stage, each at --fps (default
# 60); ffmpeg turns the frames into labelled contact sheets and one clip per animation (first person | behind-right |
# opponent side by side at the same fps) into --clips, and the frames are dropped. Normally started by tools/anim_review.sh,
# which hands it to a GPU box.
#   tools/anim_review_shot.sh [--only zz_m4,zz_glock|all|none] [--anims idle,fire] [--avatar] [--zombies common,brute|all]
#                             [--out screenshots/anim_review] [--fps 60] [--clips DIR]
set -euo pipefail
cd "$(dirname "$0")/.."
out=screenshots/anim_review
fps=60
clips=
zombies=
survivor=()
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case ${args[i]} in
    --out) out=${args[i+1]}; i=$((i + 1)) ;;
    --fps) fps=${args[i+1]}; i=$((i + 1)) ;;
    --clips) clips=${args[i+1]}; i=$((i + 1)) ;;
    --zombies) zombies=${args[i+1]}; i=$((i + 1)) ;;
    --avatar) survivor+=(--avatar) ;;
    *) survivor+=("${args[i]}") ;;
  esac
done
[[ $fps =~ ^[0-9]+$ ]] && (( fps >= 15 )) || { echo "anim_review_shot.sh: --fps must be a whole number of at least 15, not $fps" >&2; exit 2; }
clips=${clips:-$out}
mkdir -p "$out" "$clips"
rc=0
review() {
  xvfb-run -a -s "-screen 0 960x540x24" timeout 3300 "${GODOT:-godot}" --path . --resolution 960x540 --fixed-fps "$fps" \
    --script tools/anim_review.gd -- --out "$out" --fps "$fps" "$@" 2>&1 \
    | grep -E '^ANIM(REVIEW|FRAMES) |SCRIPT ERROR|ERROR: .*anim_review' || rc=$?
}
# The survivor runs in the offline client and the infected on their own stage: two processes.
[[ " ${survivor[*]} " == *" --only none "* && " ${survivor[*]} " != *" --avatar "* ]] || review "${survivor[@]}"
[[ -z $zombies ]] || review --zombies "$zombies"
# 15 cells per second of clip, eight to a row, each cell labelled with its frame index and time.
every=$(( fps / 15 ))
sheet() {
  local pattern=$1 count=$2 dest=$3
  local rows=$(( (count / every + 8) / 8 ))
  ffmpeg -y -loglevel error -framerate "$fps" -i "$pattern" -vf \
    "scale=240:-2,drawtext=text='#%{n} %{pts\:flt}s':x=4:y=4:fontsize=14:fontcolor=white:box=1:boxcolor=black@0.6,select='not(mod(n\,$every))',tile=8x${rows}:padding=2" \
    -frames:v 1 "$dest" || echo "ANIMREVIEW_SHEET failed: $dest"
}
# The three views side by side (960 + 480 + 480 wide), every frame, frame index burnt in for the notes.
clip() {
  local d=$1 dest=$2
  ffmpeg -y -loglevel error -framerate "$fps" -i "$d/f_%03d.jpg" -framerate "$fps" -i "$d/t_%03d.jpg" -framerate "$fps" -i "$d/o_%03d.jpg" \
    -filter_complex "[0:v][1:v][2:v]hstack=inputs=3,drawtext=text='#%{n}':x=4:y=h-22:fontsize=16:fontcolor=white:box=1:boxcolor=black@0.6" \
    -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p -r "$fps" "$dest" || echo "ANIMREVIEW_CLIP failed: $dest"
}
for d in "$out"/*/_frames/*/; do
  [[ -d $d ]] || continue
  name=$(basename "$d"); w=$(dirname "$(dirname "$d")")
  n=$(find "$d" -name 'f_*.jpg' | wc -l)
  (( n > 0 )) || continue
  sheet "$d/f_%03d.jpg" "$n" "$w/${name}_fp_sheet.png"
  sheet "$d/t_%03d.jpg" "$n" "$w/${name}_tp_sheet.png"
  sheet "$d/o_%03d.jpg" "$n" "$w/${name}_op_sheet.png"
  clip "$d" "$clips/$(basename "$w")__${name}.mp4"
done
rm -rf "$out"/*/_frames
echo "anim_review_shot.sh: $(find "$out" -name '*_sheet.png' | wc -l) sheets in $out, $(find "$clips" -name '*.mp4' | wc -l) clips at $fps fps in $clips"
exit $rc
