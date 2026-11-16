#!/usr/bin/env bash
# The animation review loop's capture step (docs/anim-review.md, FC's loop): plays the survivor's clips for the named weapons,
# the survivor's locomotion (--avatar) and the infected's clips (--zombies), and writes labelled contact sheets per subject
# and clip (first person, behind-right, opponent), one side-by-side clip per animation (<subject>/<clip>.mp4 at --fps,
# default 60) and a PASS/FAIL report from the glitch metrics.
#   tools/anim_review.sh <weapon[,weapon]|all|none> [--anims idle,fire] [--avatar] [--zombies kind[,kind]|all] [--fps 60]
#                        [--frames] [--soft]
# Weapon ids are ZzWeapons ids (zz_m4); a subject is a weapon id, avatar, or zombie_<kind>.
# Every clip's per-frame numbers go to <subject>/<clip>_frames.tsv; a FAIL clip's (every clip's with --frames) are printed.
# The capture goes to a GPU box through gpu.sh shot (which copies the clips back with --pull) and, when no box takes it,
# through heavy here; run it as gamedev from the checkout or a ~/wt worktree. --soft keeps it here on software rendering.
set -euo pipefail
weapons=${1:?usage: anim_review.sh <weapon|all|none> [--anims X] [--avatar] [--zombies K|all] [--fps 60] [--frames] [--soft]}
shift
anims=
soft=0
frames=0
fps=60
avatar=0
zombies=
while (($#)); do
  case $1 in
    --anim | --anims) anims=$2; shift 2 ;;
    --soft) soft=1; shift ;;
    --avatar) avatar=1; shift ;;
    --zombies) zombies=$2; shift 2 ;;
    --fps) fps=$2; shift 2 ;;
    --frames) frames=1; shift ;;
    *) echo "anim_review.sh: unknown argument $1 (weapons, clips and kinds are one comma list each: zz_m4,zz_knife)" >&2; exit 2 ;;
  esac
done
command -v heavy > /dev/null || PATH=$HOME/bin:$HOME/.local/bin:/home/gamedev/bin:/home/gamedev/.local/bin:$PATH
command -v heavy > /dev/null || { echo "anim_review.sh: no heavy on PATH (run as gamedev)" >&2; exit 2; }
cd "$(dirname "$0")/.."
out=screenshots/anim_review
log=$out/capture.log
mkdir -p "$out"
# Only the picked subjects' old sheets go: a run for one weapon keeps every other subject's review.
subjects=()
[[ $weapons == all ]] && rm -f "$out"/zz_*/*_sheet.png "$out"/zz_*/*.mp4
[[ $weapons == all || $weapons == none ]] || IFS=, read -ra subjects <<< "$weapons"
((avatar == 0)) || subjects+=(avatar)
[[ $zombies == all ]] && rm -f "$out"/zombie_*/*_sheet.png "$out"/zombie_*/*.mp4
[[ -z $zombies || $zombies == all ]] || for k in ${zombies//,/ }; do subjects+=("zombie_$k"); done
for s in "${subjects[@]}"; do
  [[ -n $s && $s != */* && $s != .* ]] && rm -f "$out/$s"/*_sheet.png "$out/$s"/*.mp4
done
pick=(--only "$weapons")
[[ -z $anims ]] || pick+=(--anims "$anims")
((avatar == 0)) || pick+=(--avatar)
[[ -z $zombies ]] || pick+=(--zombies "$zombies")
[[ $soft == 1 ]] && export GPU_OFFLOAD=0
# The clips come back through a scratch directory at the same absolute path on the box and here.
clips=$(mktemp -d /tmp/anim-review-clips.XXXXXX)
chmod 755 "$clips"
trap 'rm -rf "$clips"' EXIT
shot=(tools/anim_review_shot.sh --out "$out" --clips "$clips" --fps "$fps" "${pick[@]}")
gpu=$(dirname "$PWD")/gpu.sh
rc=75
# --route: exit 75 when no box takes it (then heavy queues it here), else the tool's own exit code.
if [[ $soft == 0 && -x $gpu ]]; then
  rc=0
  SHOT_DIR=$PWD GPU_SHOT_WAIT=${GPU_SHOT_WAIT:-1500} "$gpu" shot --route --timeout 3500 --pull "$clips" "$(basename "$PWD")" "${shot[@]}" > "$log" 2>&1 || rc=$?
fi
if [[ $rc == 75 ]]; then
  rc=0
  heavy -- timeout 3500 "${shot[@]}" > "$log" 2>&1 || rc=$?
fi
for c in "$clips"/*__*.mp4; do
  [[ -e $c ]] || continue
  n=$(basename "$c" .mp4)
  mkdir -p "$out/${n%%__*}" && mv "$c" "$out/${n%%__*}/${n#*__}.mp4"
done
grep -E 'SCRIPT ERROR|ERROR' "$log" | head -5 >&2 || true
python3 - "$out" "$log" "$frames" "$fps" <<'PY'
import json, os, sys
out, log, all_frames, fps = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4]
rows, per_clip = [], {}
for line in open(log, errors="replace"):
    if line.startswith("ANIMREVIEW {"):
        rows.append(json.loads(line[len("ANIMREVIEW "):]))
    elif line.startswith("ANIMFRAMES {"):
        c = json.loads(line[len("ANIMFRAMES "):])
        per_clip[(c["weapon"], c["anim"])] = c["frames"]
HEAD = ["#", "t", "hop", "part", "shown", "wall", "muzzle_xyz", "weapon_xyz"]

def table(frames):
    """One row per frame: hop is the largest view-model part move from the frame before (blank while the wall swing moves)."""
    xyz = lambda v: ",".join("%.3f" % x for x in v) if v else ""
    t = [HEAD]
    for i, f in enumerate(frames):
        t.append([str(i), "%.3f" % f["t"], "%.4f" % f["hop"] if "hop" in f else "", f.get("part", ""),
            "" if "shown" not in f else ("y" if f["shown"] else "N"), "%.3f" % f["wall"] if "wall" in f else "",
            xyz(f.get("muzzle")), xyz(f.get("weapon"))])
    return t
lines = ["# Animation review", "", "fps: %s (sheets every %d frames; clips play every frame)" % (fps, max(1, int(fps) // 15)), "",
    "| subject | clip | verdict | why | first person | behind-right | opponent | clip |", "|---|---|---|---|---|---|---|---|"]
fails = 0
skipped = [r for r in rows if "pass" not in r]
rows = [r for r in rows if "pass" in r]
for r in sorted(rows, key=lambda r: (r["weapon"], r["anim"])):
    base = os.path.join(out, r["weapon"], r["anim"])
    files = [base + "_fp_sheet.png", base + "_tp_sheet.png", base + "_op_sheet.png", base + ".mp4"]
    fails += 0 if r["pass"] else 1
    why = "; ".join(r["fail"]) if r["fail"] else "worst " + ", ".join("%s %s" % kv for kv in r["worst"].items())
    if r.get("notes"):
        why += " (note: %s)" % "; ".join(r["notes"])
    lines.append("| %s | %s | %s | %s | %s |" % (r["weapon"], r["anim"], "PASS" if r["pass"] else "FAIL", why.replace("|", "/"),
        " | ".join(os.path.abspath(f) if os.path.exists(f) else "missing" for f in files)))
for r in sorted(skipped, key=lambda r: (r["weapon"], r["anim"])):
    lines.append("| %s | %s | MISSING | %s | | | | |" % (r["weapon"], r["anim"], r.get("why") or r.get("status")))
lines += ["", "%d clips, %d FAIL, %d not playable" % (len(rows), fails, len(skipped))]
open(os.path.join(out, "report.md"), "w").write("\n".join(lines) + "\n")
for r in sorted(rows, key=lambda r: (r["weapon"], r["anim"])):
    frames = per_clip.get((r["weapon"], r["anim"]))
    if not frames:
        continue
    t = table(frames)
    os.makedirs(os.path.join(out, r["weapon"]), exist_ok=True)
    open(os.path.join(out, r["weapon"], r["anim"] + "_frames.tsv"), "w").write("\n".join("\t".join(row) for row in t) + "\n")
    if all_frames or not r["pass"]:
        width = [max(len(row[c]) for row in t) for c in range(len(HEAD))]
        print("\n== %s %s %s: %s" % (r["weapon"], r["anim"], "PASS" if r["pass"] else "FAIL", "; ".join(r["fail"]) or "clean"))
        for row in t:
            print("  ".join(v.rjust(w) for v, w in zip(row, width)).rstrip())
print("anim_review: %d clips, %d PASS, %d FAIL, %d not playable; report %s" % (len(rows), len(rows) - fails, fails, len(skipped),
    os.path.abspath(os.path.join(out, "report.md"))))
if not rows and not skipped:
    sys.exit("anim_review: nothing captured (see %s; llvmpipe crashes, so wait for a GPU box with GPU_SHOT_WAIT)" % log)
PY
exit $rc
