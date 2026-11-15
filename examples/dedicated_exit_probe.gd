## The second process a suite runs of itself, to read what its exit leaves behind.
##
## Shared by examples/dedicated.gd; kept out of it so the suite stays a suite.
extends RefCounted

## The flag the suite hands the copy of itself it runs. See [method run].
const EXIT_PROBE_FLAG := "--exit-probe"

## What the exit probe adds to a run — one section, these checks — and the copy does not.
const EXIT_PROBE_CHECKS := 3


## How long the copy may run before it is killed and this probe fails: a copy still running is
## hung, likeliest a scene whose script failed to parse (it never reaches `quit()`, prints nothing).
## `-- --exit-probe-seconds N` lowers it, which arms the deadline itself.
const EXIT_PROBE_SECONDS := 300


static func is_probe() -> bool:
	return EXIT_PROBE_FLAG in OS.get_cmdline_user_args()


static func seconds_allowed() -> int:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--exit-probe-seconds")
	if at >= 0 and at + 1 < args.size() and args[at + 1].is_valid_int():
		return maxi(1, args[at + 1].to_int())
	return EXIT_PROBE_SECONDS


## Runs this same suite in a fresh process: `[exit code, its stdout, its stderr, whether it
## had to be killed, the seconds it was allowed]`. A leak is reported after `quit()` by the
## engine, so only another process can check a run's exit (see the notes in the body).
static func run(host: Node) -> Array:
	# First, before this run opens a port, so the two never contend for a socket and this run is
	# always the second against the same `user://`, which no single run can see. On Godot 4.7.2 a
	# script that names itself, loaded after its base, cuts exit teardown short: scripts before it leak.
	var seconds := seconds_allowed()
	print("(running this suite once more in a fresh process, to read what it leaves at exit — %d s allowed)" % seconds)
	var scene := host.scene_file_path if host.scene_file_path != "" else "res://examples/dedicated.tscn"
	var exe := OS.get_executable_path()
	var args := PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		scene, "--", EXIT_PROBE_FLAG,
	])
	# Not OS.execute: it blocks, so a hung copy held this run (and, if the outer `timeout` killed
	# this run, was left holding the port). Two deadlines, as Godot dies on SIGTERM without running
	# script: coreutils `timeout` (status 124), and this loop's own, later, where it is missing.
	var wrapped := false
	for wrapper: String in ["/usr/bin/timeout", "/bin/timeout"]:
		if FileAccess.file_exists(wrapper):
			var outer := PackedStringArray(["--kill-after=10", str(seconds), exe])
			outer.append_array(args)
			exe = wrapper
			args = outer
			wrapped = true
			break

	# execute_with_pipe, as create_process captures nothing. Drained on every pass: a pipe holds
	# 64 KiB and a copy that fills it blocks on its next print, which this would report as a hang.
	# The copy's stdin is a pipe held open here, hence every suite turns the stdin console off.
	var proc := OS.execute_with_pipe(exe, args, false)
	if proc.is_empty():
		return [-1, "", "could not start %s" % exe, false, seconds]
	var pid: int = proc["pid"]
	var pipes: Array[FileAccess] = [proc["stdio"], proc["stderr"]]
	var bytes: Array[PackedByteArray] = [PackedByteArray(), PackedByteArray()]
	var deadline := Time.get_ticks_msec() + (seconds + 30) * 1000
	var hung := false
	while OS.is_process_running(pid):
		_drain(pipes, bytes)
		if Time.get_ticks_msec() > deadline:
			OS.kill(pid)
			hung = true
			break
		await host.get_tree().create_timer(0.1).timeout
	# Once more after it exits: what it wrote between the last pass and its exit is still in
	# the pipe, and the leak report is always the last thing it writes.
	_drain(pipes, bytes)

	# OS.kill has already reaped it, and asking for the exit code of a reaped pid is an error.
	var code := -1 if hung else OS.get_process_exit_code(pid)
	if wrapped and code == 124:
		hung = true
	return [code, bytes[0].get_string_from_utf8(), bytes[1].get_string_from_utf8(), hung, seconds]


static func _drain(pipes: Array[FileAccess], bytes: Array[PackedByteArray]) -> void:
	for i in pipes.size():
		while true:
			var chunk := pipes[i].get_buffer(65536)
			if chunk.is_empty():
				break
			bytes[i].append_array(chunk)


static func line_with(text: String, needle: String) -> String:
	for line in text.split("\n"):
		if line.contains(needle):
			return line.strip_edges()
	return ""


static func last_lines(text: String, count: int) -> String:
	var lines := text.strip_edges().split("\n")
	return "\n".join(lines.slice(maxi(0, lines.size() - count)))
