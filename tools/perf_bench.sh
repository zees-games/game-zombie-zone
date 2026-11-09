#!/usr/bin/env bash
# The solo-client benchmark on a GPU box: dot-game's tool (addons/dot_game/tools/dot_game_perf_bench.sh). Needs PERF_BENCH_REF or --ref for the compare.
exec bash "$(dirname "$0")/../addons/dot_game/tools/dot_game_perf_bench.sh" "$@"
