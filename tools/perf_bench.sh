#!/usr/bin/env bash
# The solo-client benchmark on a GPU box: dot-game's tool (addons/dot_game/tools/dot_game_perf_bench.sh).
# Pinned map: zs_verystill (tools/perf_bench.gd, `--map ID` overrides). Reference profile: PERF_BENCH_REF or --ref; default is the
# windowed staging02 profile (RTX 2070, zs_verystill, 3 bots, 30 s, 2026-11-09; copy kept in tools/perf_ref/, original in
# /home/christian/perf-logs/zz/). Always pin ONE box for an A/B (`--ab DIR::--native 0 DIR::--native 1 -n 3 -- --profiler idle`).
# Motor switches in perf_bench.gd: `--native 0|1`, `--native-full 0|1`, `--motor-us 1` (per-phase timers in the sidecar).
export PERF_BENCH_REF=${PERF_BENCH_REF:-$(cd "$(dirname "$0")" && pwd)/perf_ref/profile-20261109-windowed-staging02-zs_verystill.json}
exec bash "$(dirname "$0")/../addons/dot_game/tools/dot_game_perf_bench.sh" "$@"
