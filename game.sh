#!/usr/bin/env bash
#
# game.sh -- play, host and test this game with one command each.
#
#   ./game.sh                      play it offline, in a window
#   ./game.sh play [-- ARGS]       the same; ARGS go to the game
#   ./game.sh online               run a local server plus the browser client, print the link
#   ./game.sh online down          stop it again
#   ./game.sh server               run a local dedicated server only (Ctrl+C stops it)
#   ./game.sh server check         start the server, load the game, stop; exit 0 if it worked
#   ./game.sh server -- ARGS       ARGS go to gs-server-deploy's ./server (e.g. -- --port 7000)
#   ./game.sh test                 parse every script, then run every test suite
#   ./game.sh test NAME...         run only these suites (e.g. ./game.sh test headless_net)
#   ./game.sh defs [--check]       write deployment/achievement-defs.json (the site's import files)
#   ./game.sh soak [MAP] [MIN]     bot soak on tools/soak.tscn (report in .godot/test-logs/soak-MAP.json)
#   ./game.sh suites               list the test suites
#   ./game.sh coldstart [MAP] [ARGS]  cold start (tools/cold_start.tscn): fails on a tick over 1000 ms or open over 6 s; --cold wipes the caches
#   ./game.sh shot [ARGS]          save a screenshot to screenshots/ (tools/shot.sh or tools/screenshot.sh)
#
# Options (before the command):
#   --godot PATH     the Godot 4.7 binary to use (default: $GODOT, then godot on PATH)
#   --timeout SEC    the longest one test suite may run (default 1200; headless_nav gets at least 3300
#                    unless you pass a larger --timeout)
#   --no-parse       skip the parse pass in `test`
#
# `online` and `server` use gs-server-deploy, found next to this repository (or at
# GS_SERVER_DEPLOY). gs-bootstrap puts it there. Both rebuild this game's pack first, so
# what you play is what is on disk now.
#
# The same script is in every game repository; only the settings below differ. It is
# GENERATED from gs-game-template/tools/game.sh.in and this repository's game.conf by
# gs-game-template/tools/gen-game-sh.py: edit those, never this file (the generator's
# --check mode fails when they disagree).

# --- This game ------------------------------------------------------------------
# PACK is the game's id in gs-server-deploy (empty if it has no server), EXTRA_PACKS
# are other packs it needs as id:repository pairs, and SUITES are the scenes in
# examples/ that test it.
GAME_NAME="Zombie Zone"
PACK="zombiezone"
EXTRA_PACKS="zombiezone_maps:zombie-zone-maps"
SUITES="headless_propforce headless_loadout headless_propcarry headless_classes headless_config headless_workbench headless_mapcfg headless_look headless_touch headless_run headless_maps headless_mapdrop headless_workshop headless_net headless_weapons dedicated headless_survival headless_nav headless_nav_holds headless_nav_ladder headless_nav_waves headless_start headless_buildonce headless_packs headless_mechanics headless_defib headless_ambience headless_arsenal headless_carry headless_mutant headless_gait headless_sprint headless_hazards headless_collide headless_prefetch headless_downed headless_weapon_drop headless_stats headless_consumables headless_grenades headless_native_motor headless_native_crowd headless_native_senses headless_native_brains headless_native_lod"
# --------------------------------------------------------------------------------

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

GODOT="${GODOT:-godot}"
TIMEOUT=1200
PARSE=1
# A suite that legitimately needs at least this long, as name=seconds; a larger --timeout still wins.
# headless_nav runs about 17 min on staging02, past the 1200 s default.
MIN_TIMEOUTS="headless_nav=3300"
# tools/verify_ui.sh checks that drive the real client under xvfb.
UI_CHECKS="trader crouch nav"
# A suite too long for one run, as name=shard,shard,...: `test NAME` plays each shard as its own
# `examples/NAME.tscn -- --shard SHARD` (up to $SHARD_JOBS at once, default 4) and then runs the
# suite once more as `-- --merge LOG...` over the shards' logs, which holds the whole-run checks.
# `test NAME.SHARD` plays one shard; `test NAME.merge` only the merge over logs already in .godot/test-logs.
# `suites --shards` lists the shards instead of the suite (`hv shard` runs them as separate jobs, then NAME.merge).
SUITE_SHARDS="headless_survival=core_a,core_b,core_c,core_d,core_e,zz_high_school,zz_mall,zz_stadium,zz_relief_camp headless_maps=core,light,worlds,m0,m1,m2,m3 headless_nav_waves=w0,w1,w2,w3,w4,w5"
RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; OFF=$'\033[0m'
CR=$'\r\033[K'
[ -t 1 ] || { RED=""; GRN=""; YLW=""; OFF=""; CR=""; }

die() { printf '%s%s%s\n' "$RED" "$1" "$OFF" >&2; exit "${2:-1}"; }
usage() { sed -n '3,/^#   --no-parse/p' "$ROOT/$(basename "${BASH_SOURCE[0]}")" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --godot) GODOT="${2:?--godot needs a path}"; shift 2 ;;
        --godot=*) GODOT="${1#*=}"; shift ;;
        --timeout) TIMEOUT="${2:?--timeout needs seconds}"; shift 2 ;;
        --timeout=*) TIMEOUT="${1#*=}"; shift ;;
        --no-parse) PARSE=0; shift ;;
        -h|--help|help) usage; exit 0 ;;
        *) break ;;
    esac
done

command -v "$GODOT" >/dev/null 2>&1 || die "Godot not found: '$GODOT'. Install Godot 4.7 or pass --godot PATH." 2

cmd="${1:-play}"
[ $# -gt 0 ] && shift

# The addons are links that gs-bootstrap makes. Without them nothing parses, and the
# errors read like a broken game rather than a missing step.
check_addons() {
    local missing=""
    while read -r name; do
        [ -e "addons/$name/plugin.cfg" ] || [ -d "addons/$name" ] || missing="$missing $name"
    done < <(sed -n 's|^/addons/\([^/*]*\)/\{0,1\}$|\1|p' .gitignore 2>/dev/null)
    [ -z "$missing" ] || die "Missing addons:$missing
Run gs-bootstrap first: https://github.com/gamespice-platform/bootstrap" 2
    # Content links (maps, world): without them the suites run on an empty level set. A git
    # worktree gets them from tools/link_worktree.sh.
    local path src gone=""
    while IFS=$'\t' read -r path src; do
        [ -n "$path" ] && [ ! -e "${path#/}" ] && gone="$gone ${path#/} (from $src)"
    done < <(awk '/^# bootstrap-link: /{src=$3; next} src!="" && /^\//{print $0 "\t" src} {src=""}' .gitignore 2>/dev/null)
    [ -z "$gone" ] || die "Content not linked:$gone
Run gs-bootstrap, or in a git worktree: tools/link_worktree.sh <main checkout>" 2
}

deploy_dir() {
    local dir="${GS_SERVER_DEPLOY:-$ROOT/../gs-server-deploy}"
    [ -x "$dir/server" ] || die "gs-server-deploy not found at $dir (run its ./setup.sh, or set GS_SERVER_DEPLOY)." 2
    (cd "$dir" && pwd)
}

# Rebuild this game's pack, and the packs it needs, from the checkouts on disk.
pack_all() {
    [ -n "$PACK" ] || die "$GAME_NAME has no server pack." 2
    local deploy repo id pair
    deploy="$(deploy_dir)"
    for pair in $EXTRA_PACKS; do
        id="${pair%%:*}"; repo="${pair#*:}"
        echo "packing $id"
        (cd "$deploy" && ./server pack "$id" --source "$ROOT/../$repo") >/dev/null || die "could not pack $id"
    done
    if [ "${GS_PACK_ETC2_ASTC:-0}" = 1 ]; then
        # Mobile browsers: ETC2/ASTC variants too (bigger pack). gs-bootstrap's tool; default stays desktop only.
        local mob="${GS_BOOTSTRAP:-$ROOT/../gs-bootstrap}/tools/import-mobile.sh"
        [ -x "$mob" ] || die "GS_PACK_ETC2_ASTC=1 needs gs-bootstrap's tools/import-mobile.sh beside this game." 2
        "$mob" "$GODOT" . >/dev/null 2>&1 || die "mobile import failed"
    else
        "$GODOT" --headless --path . --import >/dev/null 2>&1
    fi
    echo "packing $PACK"
    (cd "$deploy" && ./server pack "$PACK" --source "$ROOT") >/dev/null || die "could not pack $PACK"
}

run_ui_check() {
    local check="$1" log=".godot/test-logs/verify_ui_$1.log" status
    mkdir -p .godot/test-logs
    timeout "$TIMEOUT" tools/verify_ui.sh "$check" >"$log" 2>&1
    status=$?
    if [ "$status" -eq 0 ] && ! grep -qE 'SCRIPT ERROR|Parse Error' "$log"; then
        printf '  %sok%s   verify_ui %s  %s\n' "$GRN" "$OFF" "$check" "$(grep -E '^VERIFY .*[0-9]+ passed' "$log" | tail -1)"
        return 0
    fi
    printf '  %sFAIL%s verify_ui %s: exited %s\n' "$RED" "$OFF" "$check" "$status"
    grep -E 'VERIFY FAIL|SCRIPT ERROR|Parse Error' "$log" | head -10 | sed 's/^/       /'
    printf '       full log: %s\n' "$log"
    return 1
}

run_suite() {
    # NAME is a suite, or SUITE.SHARD; ARGS (after NAME) go to the scene as user args.
    local scene="$1" base="${1%%.*}"
    shift
    local extra=("$@") _s
    case "$scene" in
        *.merge) extra=(--merge $(for _s in $(shards_of "$base"); do printf '.godot/test-logs/%s.%s.log ' "$base" "$_s"; done) "$@") ;;
        *.*) extra=(--shard "${scene#*.}" "$@") ;;
    esac
    local log out status summary
    [ -f "examples/$base.tscn" ] || { printf '  %s??%s   %s: no examples/%s.tscn\n' "$YLW" "$OFF" "$scene" "$base"; return 1; }
    mkdir -p .godot/test-logs
    log=".godot/test-logs/$scene.log"
    [ -t 1 ] && printf '  ..   %s' "$scene"
    local limit="$TIMEOUT" mkv
    for mkv in $MIN_TIMEOUTS; do
        [ "${mkv%%=*}" = "$base" ] && [ "$limit" -lt "${mkv#*=}" ] && limit="${mkv#*=}"
    done
    timeout "$limit" "$GODOT" --headless --path . "res://examples/$base.tscn" ${extra[@]+-- "${extra[@]}"} >"$log" 2>&1
    status=$?
    summary="$(grep -Eo '[0-9]+ (passed|checks), [0-9]+ failed' "$log" | tail -1)"
    # Section accounting: "N sections entered, M finished" from GSGameCheckSuite._report_sections.
    local acct entered finished
    acct="$(grep -Eo '^[0-9]+ sections entered, [0-9]+ finished' "$log" | tail -1)"
    if [ -n "$acct" ]; then
        entered="${acct%% *}"; finished="$(sed -E 's/.*, ([0-9]+) finished/\1/' <<< "$acct")"
        summary="$summary  [$acct]"
    else
        summary="$summary  [no section accounting]"
    fi
    if [ "$status" -eq 124 ]; then
        out="did not finish within ${limit}s"
    elif [ "$status" -ne 0 ]; then
        out="exited $status"
    elif grep -qE 'SCRIPT ERROR|Parse Error|Lambda capture' "$log"; then
        # A script error aborts one test, not the run, so the suite can still exit 0.
        out="script error in the output"
    elif grep -qE 'resources still in use at exit|ObjectDB instances? ((were|was) )?leaked|RID allocations? of type .* (were|was) leaked' "$log"; then
        # Exit 0 and "0 failed" with objects left alive: a suite that does not free what it built.
        out="leaked objects at exit (run the scene with --verbose to name them)"
    elif [ -n "$acct" ] && [ "$entered" != "$finished" ]; then
        out="$((entered - finished)) of $entered sections aborted"
    elif grep -qE '^ERROR: [0-9]+ (of [0-9]+ sections finished|checks ran)' "$log"; then
        out="section or check count does not match the declared total"
    else
        printf '%s  %sok%s   %s  %s\n' "$CR" "$GRN" "$OFF" "$scene" "$summary"
        return 0
    fi
    printf '%s  %sFAIL%s %s: %s  %s\n' "$CR" "$RED" "$OFF" "$scene" "$out" "$summary"
    grep -E 'FAIL|SCRIPT ERROR|Parse Error|ERROR' "$log" | head -15 | sed 's/^/       /'
    printf '       full log: %s\n' "$log"
    return 1
}

PARSE_NOISE='ObjectDB instances?( were| was)? leaked|resources still in use|Pages in use exist at exit|at: (cleanup|clear|~PagedAllocator)|Text-based project'

# Prints each script that does not parse and returns how many. ANY output for a script,
# past the noise above, is a failure: a warning-as-error reads as nothing else.
parse_all() {
    local fails=0 f out tool=addons/gs_core/tools/gs_parse_all.gd
    local scripts
    scripts="$(git ls-files '*.gd' 2>/dev/null || find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' | sed 's|^\./||')"
    if [ -f "$tool" ] && [ -z "${PARSE_PER_FILE:-}" ]; then
        # One process loads every script: about ten times faster than a start-up per
        # file (66 scripts: 40 s against 4 s), with the same verdicts. The tool prints a
        # "PARSE> res://path" marker before each script, so output still belongs to a
        # file; what comes before the first marker or after PARSE_END belongs to none.
        local list log line cur="" curout="" finished=0
        list="$(mktemp)"; log="$(mktemp)"
        printf '%s\n' "$scripts" > "$list"
        PARSE_LIST="$list" timeout 900 "$GODOT" --headless --path . --script "res://$tool" >"$log" 2>&1
        while IFS= read -r line; do
            case "$line" in
                'PARSE> '*|'PARSE_END')
                    if [ -n "$cur" ] && [ -n "$curout" ]; then
                        printf '  %sFAIL%s %s\n%s\n' "$RED" "$OFF" "$cur" "$curout"
                        fails=$((fails + 1))
                    fi
                    cur=""; curout=""
                    [ "$line" = PARSE_END ] || cur="${line#PARSE> res://}" ;;
                'PARSED '*) finished=1 ;;
                'PARSE_FAIL '*) [ -n "$cur" ] && [ -z "$curout" ] && curout="$line" ;;
                *)  [ -n "$cur" ] || continue
                    printf '%s\n' "$line" | grep -Ev '^(Godot Engine v|$)' | grep -Eivq "$PARSE_NOISE" || continue
                    curout="${curout:+$curout$'\n'}$line" ;;
            esac
        done < "$log"
        # No PARSED line: the tool itself died or timed out, which is a failure, not a pass.
        if [ "$finished" -eq 0 ]; then
            printf '  %sFAIL%s the parse tool did not finish\n' "$RED" "$OFF"
            tail -n 20 "$log"
            fails=$((fails + 1))
        fi
        rm -f "$list" "$log"
        return "$fails"
    fi
    # An older gs-core without the tool: one process per script.
    while read -r f; do
        [ -n "$f" ] || continue
        out="$(timeout 120 "$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 \
            | grep -Ev '^(Godot Engine v|$)' | grep -Eiv "$PARSE_NOISE")"
        if [ -n "$out" ]; then
            printf '  %sFAIL%s %s\n%s\n' "$RED" "$OFF" "$f" "$out"
            fails=$((fails + 1))
        fi
    done <<< "$scripts"
    return "$fails"
}

# Vendored weapon art that has drifted from the weapon addon draws as empty hands.
check_weapon_art() {
    [ -e addons/zee_weapons ] || return 0
    local tool
    tool="$(readlink -f addons/zee_weapons)/../../tools/sync-art.sh"
    [ -x "$tool" ] || return 0
    "$tool" . --check >/dev/null 2>&1 || {
        printf '  %sFAIL%s weapon art is stale: run zee-gs-weapons/tools/sync-art.sh . and commit\n' "$RED" "$OFF"
        return 1
    }
    printf '  %sok%s   weapon art is in sync\n' "$GRN" "$OFF"
}

# The shards of suite $1 (space separated), empty when it is not sharded.
shards_of() {
    local kv
    for kv in $SUITE_SHARDS; do [ "${kv%%=*}" = "$1" ] && { printf '%s' "${kv#*=}" | tr ',' ' '; return 0; }; done
}

# Plays every shard of suite $1, up to $SHARD_JOBS at once, then the suite over their logs.
run_sharded() {
    local base="$1" shard tmp logs="" bad=0 running=0
    tmp="$(mktemp -d)"
    for shard in $(shards_of "$base"); do
        ( run_suite "$base.$shard" > "$tmp/$shard.out" 2>&1; echo $? > "$tmp/$shard.rc" ) &
        running=$((running + 1))
        [ "$running" -ge "${SHARD_JOBS:-4}" ] && { wait -n; running=$((running - 1)); }
    done
    wait
    for shard in $(shards_of "$base"); do
        cat "$tmp/$shard.out"
        [ "$(cat "$tmp/$shard.rc" 2>/dev/null)" = 0 ] || bad=1
        logs="$logs .godot/test-logs/$base.$shard.log"
    done
    rm -rf "$tmp"
    if [ "$bad" -ne 0 ]; then
        printf '  %sFAIL%s %s: a shard failed, so there is nothing to merge\n' "$RED" "$OFF" "$base"
        return 1
    fi
    run_suite "$base" --merge $logs
}

# The Nightly Performance gate (addons/gs_game/tools/gs_game_perf_gate.sh): the latest recorded run against the budgets. Advisory
# unless PERF_GATE=strict; PERF_GATE=off skips it. Skipped quietly where there is no `nightly`.
perf_gate_step() {
    PERF_GAME=zz bash addons/gs_game/tools/gs_game_perf_gate.sh
}

do_test() {
    check_addons
    local fails=0 f out
    echo "importing"
    timeout 600 "$GODOT" --headless --path . --import >/dev/null 2>&1

    if [ "$PARSE" = 1 ] && [ $# -eq 0 ]; then
        echo "parsing every script"
        parse_all
        fails=$?
        [ "$fails" -eq 0 ] && printf '  %sok%s   every script parses\n' "$GRN" "$OFF"
    fi

    check_weapon_art || fails=$((fails + 1))

    echo "running the suites"
    local scene
    for scene in ${*:-$SUITES}; do
        if [ -n "$(shards_of "${scene%.tscn}")" ]; then
            run_sharded "${scene%.tscn}" || fails=$((fails + 1))
            continue
        fi
        run_suite "${scene%.tscn}" || fails=$((fails + 1))
    done
    if [ $# -eq 0 ] && command -v xvfb-run >/dev/null 2>&1; then
        for scene in $UI_CHECKS; do
            run_ui_check "$scene" || fails=$((fails + 1))
        done
    fi

    [ $# -eq 0 ] && { perf_gate_step || fails=$((fails + 1)); }

    echo
    [ "$fails" -eq 0 ] && { printf '%sall passed%s\n' "$GRN" "$OFF"; return 0; }
    printf '%s%d failed%s\n' "$RED" "$fails" "$OFF"
    return 1
}

# defs_run ADDON_DIR SPEC OUT [--check]: SPEC is "res://file.gd:static_method"; the exporter ships with the addon
# repository (gs-achievements, gs-leaderboard), found through the game's addons/ link.
defs_run() {
    local addon="$1" spec="$2" out="$3" tool; shift 3
    [ -n "$spec" ] || return 0
    tool="$(readlink -f "addons/$addon")/../../tools/export_site_defs.gd"
    [ -f "$tool" ] || die "No exporter at $tool (addons/$addon must link into its repository)." 2
    "$GODOT" --headless --path . --script "$tool" -- --source "${spec%:*}" --method "${spec##*:}" --out "$out" "$@"
}

case "$cmd" in
    defs)
        check_addons
        [ -z "${1:-}" ] || [ "$1" = "--check" ] || die "usage: ./game.sh defs [--check]" 2
        rc=0
        defs_run gs_achievements "res://game/zz_progress.gd:catalogue" deployment/achievement-defs.json "$@" || rc=1
        defs_run gs_leaderboard "" deployment/leaderboard-defs.json "$@" || rc=1
        exit "$rc"
        ;;
    play)
        check_addons
        [ "${1:-}" = "--" ] && shift
        exec "$GODOT" --path . -- "$@"
        ;;
    online)
        if [ "${1:-}" = "down" ]; then
            exec "$(deploy_dir)/play.sh" down
        fi
        case "${1:-}" in ""|-*) ;; *) PACK="$1"; shift ;; esac
        check_addons
        pack_all
        exec "$(deploy_dir)/play.sh" "$PACK"
        ;;
    server)
        sub="run"
        case "${1:-}" in run|check|config) sub="$1"; shift ;; esac
        check_addons
        pack_all
        [ "${1:-}" = "--" ] && shift
        cd "$(deploy_dir)" || exit 1
        exec ./server "$sub" --game "$PACK" "$@"
        ;;
    test)
        do_test "$@"
        ;;
    soak)
        [ -f tools/soak.tscn ] || die "$GAME_NAME has no bot soak (tools/soak.tscn)." 2
        check_addons
        soak_args=()
        [ -n "${1:-}" ] && { soak_args+=(--map "$1"); shift; }
        [ -n "${1:-}" ] && { soak_args+=(--minutes "$1"); shift; }
        mkdir -p .godot/test-logs
        timeout "$TIMEOUT" "$GODOT" --headless --path . res://tools/soak.tscn -- "${soak_args[@]}" "$@" \
            2>&1 | tee .godot/test-logs/soak.log | grep -E '^SOAK|^soak|^TRACE|SCRIPT ERROR|Parse Error|ERROR|FAIL'
        exit "${PIPESTATUS[0]}"
        ;;
    perf-gate)
        perf_gate_step
        ;;
    suites)
        if [ "${1:-}" = "--shards" ]; then
            for s in $SUITES; do
                if [ -n "$(shards_of "$s")" ]; then printf '%s\n' $(for sh in $(shards_of "$s"); do echo "$s.$sh"; done); else echo "$s"; fi
            done
            exit 0
        fi
        printf '%s\n' $SUITES
        ;;
    coldstart)
        [ -f tools/cold_start.tscn ] || die "$GAME_NAME has no tools/cold_start.tscn." 2
        check_addons
        cold_args=()
        [ -n "${1:-}" ] && { cold_args+=(--map "$1"); shift; }
        timeout "$TIMEOUT" "$GODOT" --headless --path . res://tools/cold_start.tscn -- "${cold_args[@]}" "$@" \
            2>&1 | grep -E '^COLD|SCRIPT ERROR|Parse Error|ERROR'
        exit "${PIPESTATUS[0]}"
        ;;
    shot)
        for tool in tools/shot.sh tools/screenshot.sh; do
            [ -x "$tool" ] || continue
            if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
                # The tool's own header comment is its usage.
                sed -n '2,/^[^#]/p' "$tool" | sed '$d' | sed 's/^# \{0,1\}//'
                exit 0
            fi
            exec "$tool" "$@"
        done
        die "$GAME_NAME has no screenshot tool." 2
        ;;
    *)
        usage
        exit 2
        ;;
esac; exit $?  # parsed with the case: bash re-reads the file after a long run, and an edited game.sh gave "unexpected EOF"
