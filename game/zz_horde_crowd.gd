extends "zz_horde_state.gd"

## The horde's native tables: the crowd grid rebuilt each tick, the choice of which native passes run, and gs-sim's
## `GSSimBotThreat` (each zombie's height and kind) with the ranking and commons count asked of it.

const ZzBrainsFeed := preload("zz_brains_feed.gd")

## Whether [method ranked_threats] and [method commons_near] are answered natively now.
func threat_is_native() -> bool:
	return threat_native != null and crowd_native

## Whether the last [method ranked_threats] found nobody within its calm radius.
var threat_calm: bool = true

## The (at most ten) zombies a survivor at [param feet] with eyes at [param eye] would rather shoot among those within
## [param radius], best first (a special counts twelve metres closer, a sitting sleeper never), and [member threat_calm]
## says whether nobody is within [param calm_radius]. Only while [method threat_is_native].
func ranked_threats(feet: Vector3, eye: Vector3, radius: float, calm_radius: float) -> Array[GSNpcInstance]:
	var out: Array[GSNpcInstance] = []

	for i in threat_native.rank(crowd, feet, eye, radius, calm_radius):
		var npc := _crowd_npcs[i]
		if npc.is_alive():
			out.append(npc)

	threat_calm = threat_native.calm()
	return out

## How many living commons stand within [param reach] of [param point]. Only while [method threat_is_native].
func commons_near(point: Vector3, reach: float) -> int:
	return threat_native.commons(crowd, point, reach)

## Tells the native threat table [param npc]'s height and kind (the sleeper sitting until the grid's rebuild says otherwise).
func _register_threat(npc: GSNpcInstance) -> void:
	if threat_native == null:
		return

	var flags := 0

	if ZzNpcs.is_special(npc.def.id):
		flags = ClassDB.class_get_integer_constant(NATIVE_THREAT, &"SPECIAL")
	elif npc.def.id == ZzNpcs.COMMON:
		flags = ClassDB.class_get_integer_constant(NATIVE_THREAT, &"COMMON")

	threat_native.register(npc.instance_id, float(npc.def.meta.get("height", 1.7)), flags)

func _rebuild_grid() -> void:
	_pick_crowd()
	crowd.clear()
	_crowd_npcs.clear()
	_crowd_ids.clear()
	_crowd_at.clear()
	var native := crowd_native
	# Typed, so the script path pays no dynamic call per zombie.
	var script_grid: CrowdGrid = null if native else crowd
	var kill_y := float(_doc.get("kill_y", -30.0))
	var sleepers: Object = threat_native

	for npc in spawner.all_npcs():
		if not npc.is_alive():
			continue

		var p := npc.position()

		# One below the map is the watch's to remove (wcull); it must not feed the grid meanwhile.
		if p.y < kill_y or not p.is_finite():
			continue

		if sleepers != null and npc.def.id == ZzNpcs.SLEEPER:
			var _s: bool = sleepers.set_sitting(npc.instance_id, npc.brain != null and str(npc.brain.get(&"state")) == "sitting")

		if native:
			_crowd_ids.append(npc.instance_id)
			_crowd_at.append(p)
		else:
			var _i := script_grid.add(npc.instance_id, p)

		_crowd_npcs.append(npc)

	# The native grid takes the whole tick in one call.
	if native:
		crowd.fill(_crowd_ids, _crowd_at)

var _crowd_ids := PackedInt64Array()

var _crowd_at := PackedVector3Array()

## Swaps [member crowd] to the native grid or back when [member ZzConfig.native_crowd] (or the
## library) says so, the senses' native pass with [member ZzConfig.native_senses], and the brains'
## with [member ZzConfig.native_brains]; between ticks, so a tool may flip any while a round runs.
func _pick_crowd() -> void:
	if senses != null:
		senses.native_enabled = config != null and config.native_senses

	var brains := config != null and config.native_brains and ClassDB.class_exists(NATIVE_BRAINS)
	# Through `set` so an older gs-npc without pacing is simply not told.
	if spawner != null:
		spawner.set(&"pacing", config != null and config.native_pacing and ClassDB.class_exists(&"GSSimThinkPacer"))

	_pick_think(config != null and config.native_brains)
	if brains != (brains_native != null):
		brains_native = ClassDB.instantiate(NATIVE_BRAINS) if brains else null
		ZzBrainsFeed.push_barricades(self)

	var want := config != null and config.native_crowd and ClassDB.class_exists(NATIVE_CROWD)
	var threat := want and config.native_threat and ClassDB.class_exists(NATIVE_THREAT)

	if threat != (threat_native != null):
		threat_native = ClassDB.instantiate(NATIVE_THREAT) if threat else null

		if threat and spawner != null:
			for npc in spawner.all_npcs():
				_register_threat(npc)

	if want == crowd_native:
		return

	if want:
		crowd = ClassDB.instantiate(NATIVE_CROWD)
		crowd.setup(GRID)
	else:
		crowd = CrowdGrid.new(GRID)

	crowd_native = want
