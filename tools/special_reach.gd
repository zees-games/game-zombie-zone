extends Node

## Does each special reach the survivors on a survival map? For every origin (wave hints, the horde's own pick) it asks the
## graph, with the kind's nav filter, for a path to the nearest survivor, then spawns the kind there and plays `--seconds`
## (default 40) with the survivors standing at their spawns. Per map and kind: `path` origins with a path / origins,
## `reached` origins where the body got within reach of a survivor (`!n`: n of the misses had time to walk the whole path and did not, a snag), `t` median seconds to do so.
## `godot --headless --path . res://tools/special_reach.tscn -- --all|--map=zs_lens [--origins=4] [--seconds=40] [--static] [--ai]`
## (run it through `./game.sh`'s heavy queue). The common walker leads each row as the control: a snag it shares is the map's, one it does not is the kind's. The nav graph is shared by every kind but the brute (NARROW points excluded).

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")

const TICK := 1.0 / 64.0
const SNAP := 2.5
const REACH := 4.0

var _origins := 4
var _seconds := 40.0
var _static_only := false
## Let each kind's own tactics run (hiding, waiting for a moment) instead of walking the shared steering straight at the nearest survivor.
var _ai := false
## The last _sim's end state: {state, moved over its final 8 s, gap}.
var _last: Dictionary = {}
## kind -> [paths, reached, origins, snags] over all maps
var _total: Dictionary = {}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	var ids: Array[String] = []
	var all := false

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			ids.append(arg.substr(6))
		elif arg.begins_with("--origins="):
			_origins = int(arg.substr(10))
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.substr(10))
		elif arg == "--ai":
			_ai = true
		elif arg == "--static":
			_static_only = true
		elif arg == "--all":
			all = true

	if all:
		for file in DirAccess.get_files_at("res://maps"):
			if file.ends_with(".json") and not file.contains(".doc."):
				var text := FileAccess.get_file_as_string("res://maps/" + file)
				if text.contains("\"mode\": \"survival\"") or text.contains("\"mode\":\"survival\""):
					ids.append(file.trim_suffix(".json"))

	ids.sort()
	var kinds: Array[StringName] = ZzNpcs.SPECIALS.duplicate()
	kinds.append(ZzNpcs.BRUTE)
	kinds.push_front(ZzNpcs.COMMON)

	for id in ids:
		var game := await _built(id)

		if game == null:
			print("%-24s no graph" % id)
			continue

		await _map(id, game, kinds)
		game.queue_free()
		await get_tree().physics_frame

	print("--- per special over %d maps (origins with a path / reached / origins)" % ids.size())

	for kind in kinds:
		var t: Array = _total.get(kind, [0, 0, 0, 0])
		print("%-10s path %d  reached %d  of %d  snags %d" % [kind, t[0], t[1], t[2], t[3]])

	get_tree().quit()


func _map(id: String, game: Node, kinds: Array[StringName]) -> void:
	var horde = game.horde
	var data: DotNpcNavData = horde.spawner.nav.data
	var targets: Array[Vector3] = []

	for sid in horde.survivor_ids():
		targets.append(horde.survivor_position(sid))

	var origins := _pick_origins(game, data)
	var parts := PackedStringArray()

	for kind in kinds:
		var def: DotNpcDef = horde.spawner.catalogue.get_npc(kind)
		var graph := DotNpcNavGraph.new(data)

		if def != null and def.nav_exclude_flags != 0:
			graph.filter = DotNpcNavFilter.new()
			graph.filter.exclude_flags = def.nav_exclude_flags

		var paths := 0
		var reached := 0
		var times: Array[float] = []
		var stuck := 0

		for origin in origins:
			var has_path := false
			var shortest := INF

			for target in targets:
				var route := graph.find_path(origin, target, SNAP)

				if route.size() > 0:
					has_path = true
					shortest = minf(shortest, _length(route))

			paths += 1 if has_path else 0

			if not _static_only:
				var t := _sim(game, kind, origin)

				if t >= 0.0:
					reached += 1
					times.append(t)
				elif has_path and def != null and shortest / maxf(def.move_speed, 0.1) < _seconds * 0.6 \
						and not _last.is_empty() and float(_last["moved"]) < 3.0:
					# Time to arrive by a clear run, and still for the last eight seconds: a snag, not a long way round or a wait.
					stuck += 1
					print("   snag %s %s from %s path %.0f m, %s, %.0f m short, moved %.1f m" % [id, kind, origin.snapped(Vector3.ONE * 0.1), shortest, _last["state"], _last["gap"], _last["moved"]])

		times.sort()
		var med := "-" if times.is_empty() else "%.0fs" % times[times.size() / 2]
		var tot: Array = _total.get(kind, [0, 0, 0, 0])
		_total[kind] = [tot[0] + paths, tot[1] + reached, tot[2] + origins.size(), tot[3] + stuck]
		parts.append("%s %d/%d/%d%s %s" % [String(kind).left(5), paths, reached, origins.size(), "" if stuck == 0 else " !%d" % stuck, med])

	print("%-24s %s" % [id, "  ".join(parts)])


## Hint spawns spread over the list, then the horde's own pick.
func _pick_origins(game: Node, data: DotNpcNavData) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var hints: Array = game.map.doc.get("zombie_spawns", [])
	var n := mini(_origins, hints.size())

	for i in n:
		out.append(ZzMapDoc.v3(hints[(i * hints.size()) / maxi(n, 1)]))

	var own: Vector3 = game.horde.call("_wave_origin")

	if own != Vector3.INF and out.size() < _origins + 1:
		out.append(own)

	return out


func _length(route: PackedVector3Array) -> float:
	var sum := 0.0

	for i in route.size() - 1:
		sum += route[i].distance_to(route[i + 1])

	return sum


## Seconds until the kind stood within REACH of a survivor, -1 if it never did.
func _sim(game: Node, kind: StringName, origin: Vector3) -> float:
	var horde = game.horde
	var npc: DotNpcInstance = horde.spawn_special(kind, origin, &"reach_probe")

	if npc == null:
		return -1.0

	var ids: Array[StringName] = horde.survivor_ids()

	if ids.is_empty():
		horde.spawner.remove(npc.instance_id)
		return -1.0

	var reach := _reach_of(horde.spawner.catalogue.get_npc(kind))
	var best := -1.0
	var ticks := int(_seconds / TICK)
	var earlier := npc.position()
	_last = {}

	for tick in ticks:
		if npc.brain != null and tick % 64 == 0:
			var nearest: StringName = ids[0]
			var gap := INF

			for sid in ids:
				var d: float = npc.position().distance_to(horde.survivor_position(sid))

				if d < gap:
					gap = d
					nearest = sid

			if _ai:
				npc.brain.call(&"force_target", nearest)
			else:
				npc.brain.set(&"probe_goal", horde.survivor_position(nearest))

		if tick == ticks - 8 * 64:
			earlier = npc.position()

		game.simulate(TICK)

		if not npc.is_alive():
			break

		var close := INF

		for sid in ids:
			close = minf(close, npc.position().distance_to(horde.survivor_position(sid)))

		if close <= reach:
			best = tick * TICK
			break

	if npc.is_alive():
		var brain_state: Variant = npc.brain.get(&"state") if npc.brain != null else &""
		var gap_now := INF

		for sid in ids:
			gap_now = minf(gap_now, npc.position().distance_to(horde.survivor_position(sid)))

		_last = {"state": String(brain_state), "moved": npc.position().distance_to(earlier), "gap": gap_now}

	horde.spawner.remove(npc.instance_id)
	return best


## A ranged kind stands off at its minimum range (scream_min, spit_min, pounce_min) and counts as arrived there.
func _reach_of(def: DotNpcDef) -> float:
	var out := REACH

	if not _ai:
		return out

	for key in ["scream_min", "spit_min", "pounce_min", "charge_min"]:
		out = maxf(out, float(def.meta.get(key, 0.0)) + 1.0)

	return out


func _built(id: String) -> Node:
	var config := ZzConfig.new()
	config.map_ids = PackedStringArray([id])
	config.warmup_seconds = 0.0
	config.survival_warmup_seconds = 600.0
	config.minimum_players = 0
	config.keep_progress = false
	config.nav_cache = false
	config.wanderer_density = 0.0
	var game := ZzGame.new()
	game.config = config
	game.tick_rate = 64
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame
	game.next_map_id = StringName(id)
	var doc: Dictionary = game.catalogue.maps.get(StringName(id), {})

	for i in maxi(int(doc.get("survivors", 4)), 1):
		var player = game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		player.health.invulnerable = true

	game.start()
	var ticks := 0

	while ticks < 64 * 120 and not _graph_ready(game):
		for i in 32:
			game.simulate(TICK)

		ticks += 32
		await get_tree().physics_frame

	return game if _graph_ready(game) else null


func _graph_ready(game: Node) -> bool:
	var spawner = game.horde.spawner
	return spawner != null and spawner.nav != null and spawner.nav.data != null and game.map != null and not game.horde.nav_building()
