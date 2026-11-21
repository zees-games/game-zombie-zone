#!/usr/bin/env bash
# Zombie Zone's on-box visual QA capture (docs/visual-qa.md): gs-game's shot tool runs tools/visual_qa.gd, once for the
# survivor in the offline client and once more with --zombies for the infected on their bare stage (one process cannot hold
# both). Normally started by gs-game's driver:
#   bash addons/gs_game/tools/gs_game_visual_qa.sh --shot tools/visual_qa_shot.sh -- [--only zz_m4,zz_glock|all|none]
#        [--clips idle,fire] [--avatar] [--zombies common,brute|all]
set -euo pipefail
shot="$(dirname "$0")/../addons/gs_game/tools/gs_game_visual_qa_shot.sh"
zombies=
survivor=()
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case ${args[i]} in
    --zombies) zombies=${args[i+1]:?--zombies needs kind,kind or all}; i=$((i + 1)) ;;
    *) survivor+=("${args[i]}") ;;
  esac
done
rc=0
capture() { bash "$shot" --script tools/visual_qa.gd --keep '^ANIMFRAMES ' -- "$@" || rc=$?; }
# --only none without --avatar leaves no survivor clip, so only the infected run.
[[ " ${survivor[*]} " == *" --only none "* && " ${survivor[*]} " != *" --avatar "* ]] || capture "${survivor[@]}"
[[ -z $zombies ]] || capture "${survivor[@]}" --zombies "$zombies"
exit $rc
