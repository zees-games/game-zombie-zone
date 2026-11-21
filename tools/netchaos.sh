#!/usr/bin/env bash
# Thin wrapper: the rig is shared (gs-game/tools/netchaos.sh); this game supplies tools/netchaos_server.tscn and netchaos_client.tscn.
cd "$(dirname "$0")/.." && exec ../gs-game/tools/netchaos.sh "$@"
