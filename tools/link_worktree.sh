#!/usr/bin/env bash
# Links a git worktree to the addons and content directories of the main checkout:
# tools/link_worktree.sh [main checkout, default ../game-zombie-zone]. A worktree has only tracked files.
set -euo pipefail
cd "$(dirname "$0")/.."
main="$(cd "${1:-../game-zombie-zone}" && pwd)"
[ "$main" != "$(pwd)" ] || { echo "this is the main checkout" >&2; exit 2; }
n=0
for p in "$main"/* "$main"/addons/*; do
    [ -L "$p" ] || continue
    rel="${p#"$main"/}"
    if [ -e "$rel" ] || [ -L "$rel" ]; then continue; fi
    mkdir -p "$(dirname "$rel")"
    ln -s "$(readlink -f "$p")" "$rel"
    echo "linked $rel"; n=$((n + 1))
done
echo "$n linked"
