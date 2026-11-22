#!/usr/bin/env bash
# A third-person look at an avatar (stand-in playing an emote), framed in full. Real GPU via gpu.sh.
#   tools/avatar_shot.sh
set -euo pipefail
cd "$(dirname "$0")/.."
exec tools/shot.sh --view=action --action=emote:dance --seconds=0.5 --cam=orbit --target=point --dist=2.5 --yaw=200 --pitch=-5 "$@"
