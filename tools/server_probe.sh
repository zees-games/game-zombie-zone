#!/usr/bin/env bash
# One process per row (memory is per size): tools/server_probe.sh [sizes...]  e.g. 16 64
# PHYS_ENGINE=JoltPhysics3D|GodotPhysics3D picks the 3D physics engine; PHYS_THREAD=1 runs it on its own thread (a temporary override.cfg,
# so do not run two PHYS_THREAD settings from one checkout at once); name the logs with ROW_TAG=_jolt_thr.
# ROW_EXTRA="--commons=250" for a fixed horde; RATES="64 33"; log lines go to .godot/probe-logs/.
cd "$(dirname "$0")/.." || exit 1
mkdir -p .godot/probe-logs
engine_arg=()
[ -z "${PHYS_ENGINE:-}" ] || engine_arg=(--physics-engine "$PHYS_ENGINE")
if [ -n "${PHYS_THREAD:-}" ]; then
	trap 'rm -f override.cfg' EXIT
	printf '[physics]\n3d/run_on_separate_thread=%s\n' "$([ "$PHYS_THREAD" = 1 ] && echo true || echo false)" > override.cfg
fi
for rate in ${RATES:-64 33}; do
	for n in "${@:-16 32 64 100 128}"; do
		heavy -- timeout "${PROBE_TIMEOUT:-1500}" godot --headless "${engine_arg[@]}" --path . res://tools/server_probe.tscn -- --n="$n" --rate="$rate" ${ROW_EXTRA:-} \
			> ".godot/probe-logs/n${n}_r${rate}${ROW_TAG:-}.log" 2>&1
		echo "n=$n rate=$rate exit=$?"
		grep -h '^RESULT' ".godot/probe-logs/n${n}_r${rate}${ROW_TAG:-}.log" || tail -3 ".godot/probe-logs/n${n}_r${rate}${ROW_TAG:-}.log"
	done
done
