extends "zz_horde_state.gd"

const ZzWatchCull := preload("zz_watch_cull.gd")

## What a point inside a push volume costs to arrive at, times the usual.
const PUSH_COST := 12.0

## The mover watch and cull (game/zz_watch_cull.gd), built with each map.
var wcull: ZzWatchCull = null

## A file holding a worker count that forces the horde's NPC workers for a test run (see
## [method forced_npc_workers]). Untracked on purpose: write it, run the suites, delete it.
const FORCE_WORKERS_FILE := "res://zz_npc_workers.force"
static var _forced_workers := -2

## Every NPC worker count (sense, path, think) forced for a test run, with DotParallel.verify on:
## env ZZ_NPC_WORKERS=N, else the number in [constant FORCE_WORKERS_FILE] (the form that reaches a
## box a suite is offloaded to, which gets the worktree's files but not the caller's env). -1 unset.
static func forced_npc_workers() -> int:
	if _forced_workers == -2:
		var v := OS.get_environment("ZZ_NPC_WORKERS").strip_edges()
		if v == "" and FileAccess.file_exists(FORCE_WORKERS_FILE):
			v = FileAccess.get_file_as_string(FORCE_WORKERS_FILE).strip_edges()
		_forced_workers = v.to_int() if v.is_valid_int() and v.to_int() >= 0 else -1
		if _forced_workers >= 0:
			DotParallel.verify = true
			DotLog.info(CHANNEL, "NPC workers forced, DotParallel.verify on", {"workers": _forced_workers})
	return _forced_workers

## How the background pressure behaves. The genre's numbers: spawn well ahead and out of
## sight, peak when the worst-off survivor is struggling, rest when the team has moved on.
func _rules() -> DotNpcDirectorRules:
	var rules := DotNpcDirectorRules.new()
	rules.peak_per_player = 5.0
	rules.build_up_per_player = 2.5
	rules.relax_per_player = 0.6
	rules.absolute_cap = config.commons_cap(4)
	rules.peak_stress = 0.72
	rules.sustain_seconds = 5.0
	rules.fade_seconds = 8.0
	rules.relax_seconds = 25.0
	rules.relax_distance = 45.0
	rules.spawn_min_distance = 22.0 * spawn_distance_scale
	rules.spawn_max_distance = 60.0 * spawn_distance_scale
	rules.spawn_ahead = 35.0 * spawn_distance_scale
	rules.behind_fraction = 0.2
	rules.spawn_out_of_sight = true
	rules.spawn_burst = 3
	rules.spawn_interval = 0.6
	rules.reclaim_interval = 3.0
	rules.stress_per_damage = 1.2
	rules.stress_threat_radius = 6.0
	return rules

func _note_seeds() -> PackedVector3Array:
	var seeds := PackedVector3Array()

	for i in 4:
		var spot: Array = game.map.spawn("survivors", i)
		seeds.append(spot[0])

	# Where the horde comes from and where survivors hold: both ends of a street a car cuts in two.
	for key: String in ["zombie_spawns", "posts"]:
		for p: Variant in _doc.get(key, []):
			seeds.append(ZzMapDoc.v3(p))

	return seeds

## Costs up every point inside a live push volume for good: a zombie there is thrown along the push, so a path through one
## is walked against it. Paths still use them when nothing else joins the two ends.
func _mark_pushes(graph: DotNpcNavGraph) -> void:
	if game == null or game.map == null or game.map.mechanics == null:
		return

	var volumes: Array[DotMapVolume] = game.map.mechanics.push_volumes()

	if volumes.is_empty():
		return

	for p in nav.points:
		for vol in volumes:
			if vol.contains(p):
				var _i := graph.mark_bad(p, INF, PUSH_COST, 0.05)
				break
