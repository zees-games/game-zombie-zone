extends "zz_horde_state.gd"

const ZzWatchCull := preload("zz_watch_cull.gd")

## What a point inside a push volume costs to arrive at, times the usual.
const PUSH_COST := 12.0

## Metres a push volume's box is grown by before its points are tested: far more than [method DotMapVolume.contains]'s
## 0.0001 slack, so the box never turns away a point the planes would take.
const PUSH_BOX_SLACK := 0.05

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
		if v == "" and FileAccess.file_exists(FORCE_WORKERS_FILE):  # pack-path: ok (a test-run hook in a worktree, never shipped)
			v = FileAccess.get_file_as_string(FORCE_WORKERS_FILE).strip_edges()  # pack-path: ok (as above)
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

	# Each volume's box first: the plane test per brush, for every point of a big map, was a fifth of a second
	# on the tick the graph lands. A volume with a brush that boxes to nothing keeps the exact test everywhere.
	var boxes: Array[AABB] = []

	for vol in volumes:
		boxes.append(vol.bounds().grow(PUSH_BOX_SLACK) if vol.culls_columns() else AABB())

	for p in nav.points:
		for v in volumes.size():
			if boxes[v].has_volume() and not boxes[v].has_point(p):
				continue

			if volumes[v].contains(p):
				var _i := graph.mark_bad(p, INF, PUSH_COST, 0.05)
				break

## The scenes and brains [method _request_warm] started loading on worker threads.
var _warm_paths := PackedStringArray()


## Starts loading every enabled kind's scene and brain script on worker threads, so the map build
## and the first graph overlap them (on the main thread, as the spawner's warm() does it, they
## cost about 0.9 s of a cold start). An older dot-npc without warm() loads them at first spawn.
func _request_warm() -> void:
	_drain_warm()

	if not spawner.has_method(&"warm"):
		return

	for def: DotNpcDef in catalogue.npcs:
		if def == null or not def.enabled:
			continue

		for path: String in [def.scene_path, def.brain_script_path]:
			if path != "" and not _warm_paths.has(path) and ResourceLoader.exists(path):
				if ResourceLoader.load_threaded_request(path) == OK:
					_warm_paths.append(path)


## Collects and drops any load [method _request_warm] started that no map build took: a threaded
## load nobody collects stays in the loader, and its objects outlive the game.
func _drain_warm() -> void:
	for path in _warm_paths:
		var _dropped := ResourceLoader.load_threaded_get(path)

	_warm_paths.clear()


## Waits for what [method _request_warm] started (only a load still running) and has the spawner
## hold it all. Before the first zombie of a map; a spawn earlier than this waits in load() itself.
func _collect_warm() -> void:
	if not spawner.has_method(&"warm"):
		return

	# Held here until warm() has taken them, so its load() finds each in the cache.
	var loaded: Array[Resource] = []

	for path in _warm_paths:
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			loaded.append(ResourceLoader.load_threaded_get(path))

	_warm_paths.clear()
	var _warmed = spawner.call(&"warm")

## The zombies' graph for [param data], built on the nav job's thread (half a second of adjacency and pieces that was the
## first tick of play's): only when the graph needs no physics prune first, which only the main thread may ask.
static func _graph_off_thread(data: DotNpcNavData) -> ZzNavGraph:
	if int(data.meta.get("pruned", 0)) < PRUNE_VERSION:
		return null

	var graph := ZzNavGraph.new()
	return graph if graph.rebuild(data).ok else null

## Flags the points a brute's body does not fit at, once the map's colliders are in the space.
func _mark_narrow() -> void:
	if spawner.nav.has_method(&"mark_narrow"):
		var brute: DotNpcDef = spawner.catalogue.get_npc(ZzNpcs.BRUTE)
		var radius := float(brute.meta.get("radius", 0.7)) if brute != null else 0.7
		var fit := float(brute.meta.get("fit_height", brute.meta.get("height", 2.1))) if brute != null else 2.1
		narrow_points = spawner.nav.mark_narrow(game.get_world_3d().direct_space_state,
			game.physics.layer_mask(&"world") | game.physics.layer_mask(&"prop"), radius, fit)

## The map's posts the graph joins to the survivors' start (all of them until a graph is applied).
func usable_posts() -> Array:
	return _usable_posts if _usable_posts_for == nav else _doc.get("posts", [])

## Where a zombie keyed [param key] should walk on its way to [param goal]: through the choke it
## was given. The goal itself with `zz_zombie_spread` off or no notes.
func waypoint_for(key: int, from: Vector3, goal: Vector3) -> Vector3:
	if not config.zombie_spread:
		return goal

	return notes.waypoint_for(key, from, goal)
