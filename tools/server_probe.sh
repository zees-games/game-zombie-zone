#!/usr/bin/env bash
# One process per row (memory is per size): tools/server_probe.sh [sizes...]  e.g. 16 64
# ROW_EXTRA="--commons=250" for a fixed horde; RATES="64 33"; log lines go to .godot/probe-logs/.
cd "$(dirname "$0")/.." || exit 1
mkdir -p .godot/probe-logs
for rate in ${RATES:-64 33}; do
	for n in "${@:-16 32 64 100 128}"; do
		heavy -- timeout "${PROBE_TIMEOUT:-1500}" godot --headless --path . res://tools/server_probe.tscn -- --n="$n" --rate="$rate" ${ROW_EXTRA:-} \
			> ".godot/probe-logs/n${n}_r${rate}${ROW_TAG:-}.log" 2>&1
		echo "n=$n rate=$rate exit=$?"
		grep -h '^RESULT' ".godot/probe-logs/n${n}_r${rate}${ROW_TAG:-}.log" || tail -3 ".godot/probe-logs/n${n}_r${rate}${ROW_TAG:-}.log"
	done
done
