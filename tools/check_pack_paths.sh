#!/bin/bash
# Refuses a pack whose scripts reach this game's own files by an absolute res:// path that is not rebased.
# A delivered pack mounts at res://dot_cloud/<owner>/<id>/<ver>/, so load("res://game/x.gd") finds the host's file or
# nothing (null.new() then fails at run time, far from the cause). Wrap the path in the game's Paths.rebase(), use a
# relative preload, or name res://addons/ (the host's). Flags, per .gd file the pack ships:
#   1. a load-like call whose first argument is a literal "res://..." under the game's tree;
#   2. the same call (or a default argument) naming a const that holds such a literal, in the file that declares it.
# A line may opt out with a trailing `# pack-path: ok (reason)` comment.
#   tools/check_pack_paths.sh [ROOT]   exit 0 clean, 1 offenders listed
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
python3 -I - "$ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
SKIP = {".git", ".godot", "addons", "tools", "examples", "tests", "docs", "screenshots", "images", "reports", "art-src"}
FN = r"(?:\bload|\bpreload|ResourceLoader\.(?:load|exists|load_threaded_request|list_directory)|FileAccess\.(?:open|file_exists|get_file_as_string|get_file_as_bytes|get_md5|get_sha256)|DirAccess\.(?:open|dir_exists_absolute|get_files_at|get_directories_at))"
OWN = r'"res://(?!addons\b|dot_cloud\b)[^"]*"'
lit = re.compile(FN + r"\(\s*\"res://(?!addons\b|dot_cloud\b)")
const = re.compile(r"^\s*(?:static\s+)?const\s+(\w+)\s*(?::\s*\w+\s*)?:?=\s*" + OWN + r"\s*(?:#.*)?$")
bad = []
for d, dirs, files in os.walk(root):
    rel = os.path.relpath(d, root)
    dirs[:] = [x for x in dirs if not (rel == "." and x in SKIP) and not os.path.islink(os.path.join(d, x))]
    for f in files:
        if not f.endswith(".gd"):
            continue
        p = os.path.join(d, f)
        lines = open(p, encoding="utf-8", errors="replace").read().splitlines()
        consts = {m.group(1) for m in map(const.match, lines) if m}
        # A default argument (`path := CONST`) only counts when the file never rebases (it may rebase inside the body).
        rebases = any("rebase(" in l for l in lines)
        names = "|".join(map(re.escape, consts))
        use = re.compile(r"(?:" + FN + r"\(\s*" + ("" if rebases else r"|=\s*") + r")(" + names + r")\s*[),]") if consts else None
        for n, line in enumerate(lines, 1):
            code = line.split("#", 1)[0] if not line.lstrip().startswith("#") else ""
            if not code.strip() or "pack-path: ok" in line:
                continue
            if lit.search(code) or (use and use.search(code) and not const.match(line)):
                bad.append("%s:%d: %s" % (os.path.relpath(p, root), n, line.strip()))
for b in bad:
    print("check_pack_paths: " + b)
if bad:
    print("check_pack_paths: %d unrebased res:// path(s); a mounted pack would miss these files (wrap them in the game's Paths.rebase())" % len(bad))
    sys.exit(1)
print("check_pack_paths: clean")
PY
