#!/usr/bin/env bash
# Contact sheets of screenshots/qa2/: six maps per sheet, a row of spawn, far, spawner per map.
cd "$(dirname "$0")/../screenshots/qa2" || exit 1
ls *_spawn.png | sed 's/_spawn.png//' | split -l 6 - /tmp/qa_group_
n=0
for g in /tmp/qa_group_*; do
    n=$((n+1)); files=()
    while read -r id; do for v in spawn far spawner; do files+=("${id}_${v}.png"); done; done < "$g"
    montage "${files[@]}" -tile 3x -geometry 520x292+2+2 -label '%t' "sheet_$n.jpg"
    rm "$g"
done
