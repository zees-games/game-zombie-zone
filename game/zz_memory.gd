extends RefCounted

## The "map built" line, with resident and peak memory against the container's limit: a server
## that outgrows its limit is killed with no log line of its own (exit 137).

## Warns once the peak passes this share of the container's limit.
const NEAR_LIMIT := 0.75


static func map_built(channel: String, id: String, ms: int) -> void:
	var fields := {"id": id, "ms": ms}
	fields.merge(read())

	if near_limit(fields):
		fields["near_limit"] = true
		DotLog.warn(channel, "map built", fields)
	else:
		DotLog.info(channel, "map built", fields)


## rss_mb, peak_mb (VmRSS, VmHWM) and limit_mb (the cgroup's memory.max, 0 when none or not Linux).
static func read() -> Dictionary:
	var status := _text("/proc/self/status")
	var limit := _text("/sys/fs/cgroup/memory.max").strip_edges()
	return {
		"rss_mb": _status_mb(status, "VmRSS:"), "peak_mb": _status_mb(status, "VmHWM:"),
		"limit_mb": limit.to_int() / 1048576 if limit.is_valid_int() else 0,
	}


static func near_limit(memory: Dictionary) -> bool:
	var limit := int(memory.get("limit_mb", 0))
	return limit > 0 and int(memory.get("peak_mb", 0)) > limit * NEAR_LIMIT


## Line by line: /proc and /sys report a length of 0, so a whole-file read comes back empty.
static func _text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ) if FileAccess.file_exists(path) else null
	var lines := PackedStringArray()

	while f != null and not f.eof_reached():
		lines.append(f.get_line())

	return "\n".join(lines)


static func _status_mb(status: String, key: String) -> int:
	for line in status.split("\n"):
		if line.begins_with(key):
			return line.trim_prefix(key).strip_edges().get_slice(" ", 0).to_int() / 1024

	return 0
