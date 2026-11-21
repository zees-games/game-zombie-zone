#!/usr/bin/env bash
# One phone-size (844x390, touch on) frame of the real client: gs-game's tool, see its docs/qa.md. gpu.sh only runs tools/*.sh.
exec bash "$(dirname "$0")/../addons/gs_game/tools/gs_game_phone_shot.sh" "$@"
