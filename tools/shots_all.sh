#!/usr/bin/env bash
# Visual QA over every drawn world: three frames per map into screenshots/qa2/, then contact sheets of six maps.
#   tools/shots_all.sh [map ids...]
cd "$(dirname "$0")/.."
mkdir -p screenshots/qa2
only=" $* "
python3 tools/qa_views.py | while read -r id view at look; do
    [ $# -eq 0 ] || [[ "$only" == *" $id "* ]] || continue
    [ -f "screenshots/qa2/${id}_${view}.png" ] && [ -z "${REDO:-}" ] && continue
    heavy -- timeout 400 tools/shot.sh --view=room --alone --zz-map-ids="$id" --at="$at" --look="$look" --seconds=1 --zz-exodus-team=1 --zz-team-from-map=0 --zz-min-players=1 \
        --name="${id}_${view}" --out="res://screenshots/qa2/${id}_${view}.png" </dev/null >/dev/null 2>&1 || echo "FAILED $id $view"
done
