#!/usr/bin/env bash
# Posts an animation-review capture (tools/anim_review.sh) to a nightly review item, so the clips play in the viewer at
# their own rate: each <subject>/<clip>.mp4 as a clip with its fps, frame count and verdict in --metrics (the viewer steps
# one frame per 1/fps), and its first-person sheet as a filmstrip. Run it from the game dir after a capture.
#   tools/anim_review_post.sh <review-key> [--variant before|after] [--only zz_m4,zombie_common] [--anims fire,walk] [--fails]
# --fails posts only FAIL clips (the cheap way to show what is wrong); --variant pairs a fix's before and after.
# The review item must exist: nightly review new "ZZ animation review" --key zz-anim-<date>.
set -euo pipefail
key=${1:?usage: anim_review_post.sh <review-key> [--variant before|after] [--only w,w] [--anims a,a] [--fails]}
shift
variant= only= anims= fails=0
while (($#)); do
  case $1 in
    --variant) variant=$2; shift 2 ;;
    --only) only=,$2,; shift 2 ;;
    --anims) anims=,$2,; shift 2 ;;
    --fails) fails=1; shift ;;
    *) echo "anim_review_post.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
cd "$(dirname "$0")/.."
out=screenshots/anim_review
[[ -f $out/report.md ]] || { echo "anim_review_post.sh: no $out/report.md; run tools/anim_review.sh first" >&2; exit 2; }
nightly=${NIGHTLY:-/home/core/stack/nightly/bin/nightly}
run_nightly() { if [[ $(id -un) == core ]]; then "$nightly" "$@"; else sudo -u core "$nightly" "$@"; fi; }
# The nightly runs as core, which cannot read a gamedev worktree: hand it copies in a world-readable scratch dir.
stage=$(mktemp -d /tmp/anim-review-post.XXXXXX)
trap 'rm -rf "$stage"' EXIT
chmod 755 "$stage"
fps=$(sed -n 's/^fps: *\([0-9]*\).*/\1/p' "$out/report.md" | head -1)
fps=${fps:-60}
posted=0 failed=0
# report.md rows: | weapon | clip | verdict | why | ... |
while IFS='|' read -r _ weapon clip verdict why _; do
  weapon=$(xargs <<< "$weapon"); clip=$(xargs <<< "$clip"); verdict=$(xargs <<< "$verdict")
  [[ $verdict == PASS || $verdict == FAIL ]] || continue
  [[ -z $only || $only == *",$weapon,"* ]] || continue
  [[ -z $anims || $anims == *",$clip,"* ]] || continue
  ((fails == 0)) || [[ $verdict == FAIL ]] || continue
  mp4=$out/$weapon/$clip.mp4 sheet=$out/$weapon/${clip}_fp_sheet.png
  [[ -f $mp4 ]] || { echo "anim_review_post.sh: no $mp4" >&2; failed=$((failed + 1)); continue; }
  frames=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$mp4" 2>/dev/null || echo 0)
  why=$(xargs <<< "${why//\"/\'}" 2>/dev/null || true)
  metrics=$(printf '{"fps":"%s","frames":"%s","seconds":"%s","verdict":"%s"}' "$fps" "$frames" "$(awk -v f="$frames" -v r="$fps" 'BEGIN{printf "%.2f", f/r}')" "$verdict")
  cp "$mp4" "$stage/${weapon}__$clip.mp4"; chmod 644 "$stage/${weapon}__$clip.mp4"
  args=(--variant "$variant" --label "$clip" --metrics "$metrics" --by anim-review)
  [[ -n $variant ]] || args=("${args[@]:2}")
  [[ $verdict == FAIL && -n $why ]] && args+=(--look "$why")
  run_nightly review media "$key" "$weapon" "$stage/${weapon}__$clip.mp4" --slot clip "${args[@]}" > /dev/null || { failed=$((failed + 1)); continue; }
  if [[ -f $sheet ]]; then
    cp "$sheet" "$stage/${weapon}__${clip}_sheet.png"; chmod 644 "$stage/${weapon}__${clip}_sheet.png"
    run_nightly review media "$key" "$weapon" "$stage/${weapon}__${clip}_sheet.png" --slot filmstrip "${args[@]}" > /dev/null || failed=$((failed + 1))
  fi
  posted=$((posted + 1))
done < "$out/report.md"
echo "anim_review_post.sh: posted $posted clips to review $key${variant:+ ($variant)}, $failed failed"
((failed == 0))
