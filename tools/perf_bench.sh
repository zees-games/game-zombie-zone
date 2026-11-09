#!/usr/bin/env bash
# The solo-client benchmark on a GPU box: dot-game's tool (addons/dot_game/tools/dot_game_perf_bench.sh).
# Reference profile: PERF_BENCH_REF or --ref; default is the ZZ profile kept beside the arena one (headless, ph, sunken_resort,
# 3 bots, 2026-11-09; a loaded box, so a floor for comparing, to be replaced by a windowed staging02 profile).
export PERF_BENCH_REF=${PERF_BENCH_REF:-/home/christian/perf-logs/zz/profile-20261109-headless-ph-sunken_resort.json}
exec bash "$(dirname "$0")/../addons/dot_game/tools/dot_game_perf_bench.sh" "$@"
