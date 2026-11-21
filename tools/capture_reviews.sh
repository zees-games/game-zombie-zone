#!/usr/bin/env bash
# Animation clips for the nightly /reviews page; see gs-game/tools/capture_reviews.sh.
cd "$(dirname "$0")/.." && exec bash ../gs-game/tools/capture_reviews.sh "$@"
