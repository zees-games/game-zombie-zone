extends Node

const ZzConfig := preload("zz_config.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzNavGraph := preload("zz_nav_graph.gd")
const ZzNavNotes := preload("zz_nav_notes.gd")
const ZzNpcs := preload("zz_npcs.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")

## Every zombie: dot-npc's spawner, dot-npc-ai-director's pacing, dot-combat's health, and the
## five clocks the genre runs on top of a director.
##
## [b]The director is the background; the clocks are the events.[/b] [DotNpcDirector] keeps a
## population of commons ahead of the team that rises while they are calm and falls away once
## they are hurting — the build-up, peak and relax that makes a quiet street feel like it is
## waiting. On top of it, this file runs what a director deliberately does not:
##
## [codeblock]
## mobs       every mob_interval, a crowd spawned out of sight that KNOWS where you are
## specials   one at a time up to a cap, each from where it is most dangerous
## the brute  on its own long clock, with a warning
## panic      while an objective is held: mobs back to back until it is done
## survival   held by nights or a clock: everything above, faster and bigger by `intensity`
## waves      held by waves: the director and the clocks are off, and the survival runtime
##            (`zz_survival.gd`) releases each wave through [method spawn_wave]
## [/codeblock]
##
## [b]Barricades are on the zombies' ground on purpose.[/b] A shut gate is cut out of the graph
## so the horde goes round; a barricade is left in, so the horde paths straight at it, is
## stopped by its boxes, and breaks it down ([method barricade_in_way], [method bash]). A
## barricade cut out of the graph would leave a school with no way in, every wave spawned
## "where it cannot reach anybody", and nothing at the windows.
##
## [b]Server only.[/b] A client never builds one; it draws what the bridge tells it about.
##
## [b]A zombie's combat id comes from the game's [DotEntityTable] and carries its kind[/b], as
## game-arena's monsters do, so a survivor's session id and a zombie's id cannot collide and
## [method is_npc_entity] asks the id rather than comparing it with a constant.

const CHANNEL := "zz.horde"

## Where brains find this. See `zz_zombie_brain.gd`.
const HORDE_META := &"zz_horde"

## A zombie's scream wakes idle commons this far away, one at a time a beat apart.
const ALERT_RADIUS := 9.0

## Bile calls every common this far away.
const BILE_RADIUS := 45.0

## How far a broken bile jar splashes.
const BILE_SPLASH := 4.0

## A mob is spawned at most this many at a time, a few ticks apart, so a crowd pours out of a
## doorway rather than appearing in it.
const MOB_BURST := 6
const MOB_BURST_SECONDS := 0.4

## Commons standing about a map are at least this far from where the team starts.
const WANDERER_CLEARANCE := 28.0

signal zombie_spawned(npc: DotNpcInstance)
signal zombie_removed(npc: DotNpcInstance)
signal zombie_died(npc: DotNpcInstance, killer: StringName, damage: DotDamage)
signal mob_started(size: int)
signal special_spawned(npc: DotNpcInstance)
signal brute_spawned(npc: DotNpcInstance)

## The game this horde serves (`zz_game.gd`), untyped: it preloads this file.
var game = null
var config: ZzConfig = null

var spawner: DotNpcSpawner = null
var director: DotNpcDirector = null
var senses: DotNpcSenses = null
var squads: DotNpcAiSquads = DotNpcAiSquads.new()

## The server's `npc_skill`, `npc_reaction_scale` and `npc_reaction_min`, which move every kind
## toward easy or nightmare without making them one monster (dot-npc-ai's [DotNpcAiSkill]).
var skill: DotNpcAiSkill = DotNpcAiSkill.new()
var sounds: DotNpcAiSounds = DotNpcAiSounds.new()
var nav: DotNpcNavData = null

## The map's annotations worked into chokes, drops and holds (`ZzNavNotes`); never null.
var notes: ZzNavNotes = ZzNavNotes.new()
var catalogue: DotNpcCatalogue = null

## Whether the pacing runs: false in a start area, between maps, in warmup.
var pacing: bool = false

## Whether this is a survival map's hold (bigger mobs, quicker specials, a quicker brute).
var survival: bool = false

## How much harder the hold is than its start: 1 at first, the survival runtime raises it with
## each night or with the clock. Mobs grow by it, come more often by it, specials by its root.
var intensity: float = 1.0

## Whether the waves drive the spawning (the director, mobs, specials and brute clocks off).
var waves_mode: bool = false

## The most commons a survival wave lets be up at once (`ZzSurvival._release` sets it each
## tick; -1 none). A mob (a scream, bile, a box) fits under it: uncapped, one bile mob of
## forty on a third wave filled the server's whole cap and was where most holds ended
## (zz-survival-retune-1).
var wave_room: int = -1

## What the wave in play does to everything spawned in it: its twist.
var wave_speed_scale: float = 1.0
var wave_health_scale: float = 1.0

## Barricades this map has: id -> {bounds: AABB, centre: Vector3}. Filled by the game.
var barricades: Dictionary = {}

## Every living zombie by four-metre cell, and where it was, built once a tick before anything
## thinks ([method _rebuild_grid]). What a zombie's crowd spacing and a stand-in's threat scan
## ask instead of the spawner's `npcs_near`, which walks every zombie: ninety commons each
## asking it for their neighbours every tick was eight thousand position reads, and most of a
## big map's tick.
var _grid: Dictionary = {}
var _grid_pos: Dictionary = {}
const GRID := 4.0

## Grid cell -> barricade ids near it, so a zombie asks only about the ones beside it.
var _barricade_cells: Dictionary = {}
const BARRICADE_CELL := 4.0
## How far past a barricade's face a zombie bashes it from: its radius and an arm.
const BASH_REACH := 0.75

## Multipliers boxes stack: how often mobs come, how hard specials are, how big mobs are.
var mob_rate_scale: float = 1.0
var special_rate_scale: float = 1.0
var special_health_scale: float = 1.0
var mob_size_scale: float = 1.0
var zombie_speed_scale: float = 1.0

## Gates opened this map, so the graph is rebuilt without them.
var open_gates: PackedStringArray = PackedStringArray()

## How a zombie falls when it dies: dot-player-char's reactions, picked here on the server from
## the killing hit and sent with the zombie's end (NPC_GONE), so every screen draws the same fall.
var death_reactions: DotPlayerDeathReactions = DotPlayerDeathReactions.stock()

## Screams heard this map, for a suite and `describe`.
var screams: int = 0

var _world: Node3D = null
var _by_entity: Dictionary = {}
var _candidates: Array = []
var _survivors: Dictionary = {}
var _doc: Dictionary = {}
var _time: float = 0.0

var _next_mob: float = INF
var _next_special: float = INF
var _next_brute: float = INF
var _panic_until: float = -1.0
var _next_panic_mob: float = 0.0

## Mob commons still to come out: [kind, at, target, flags] per entry.
var _pending: Array = []
var _next_pending: float = 0.0

## Alerts waiting to land: [instance_id, at_time, who, where].
var _alerts: Array = []

## Lures: {at, until, radius}. Bile: player id -> until.
var _lures: Array = []
var _bile: Dictionary = {}

var _rng := RandomNumberGenerator.new()


# --- Setting up ------------------------------------------------------------------------------

func setup(p_game: Object, p_config: ZzConfig) -> DotResult:
	game = p_game
	config = p_config
	catalogue = ZzNpcs.catalogue(config)
	_rng.seed = config.seed_value

	_world = Node3D.new()
	_world.name = "Zombies"
	add_child(_world)

	senses = DotNpcSenses.new()
	senses.switch_ratio = 0.6
	senses.commitment_grace = 3.0
	senses.line_of_sight_enabled = true
	senses.occlusion_mask = game.world_mask()

	spawner = DotNpcSpawner.new()
	spawner.name = "Npcs"
	spawner.catalogue = catalogue
	spawner.limits = ZzNpcs.limits(config, 4)
	spawner.authoritative = true
	spawner.world_ref = DotNodeRef.of_path(NodePath("../Zombies"))
	spawner.smooth_paths = true
	spawner.allow_partial_paths = true
	# Smooth only a path's first metres: a zombie repaths every second and a half and never
	# walks the rest. Through `set` so an older dot-npc without it is simply not told.
	spawner.set(&"smooth_horizon", 16)
	spawner.occlusion_mask = game.world_mask()
	# Every zombie's own seed (`npc.seed`, what the brains draw their idle, pace and wander from)
	# comes from the session's seed and its spawn count, so a server given the same seed plays
	# the same zombies. Never their object id: see dot-npc's docs/runtime.md.
	spawner.seed_base = config.seed_value
	# Before add_child: DotNpcSpawner._ready makes its own senses when it finds none.
	spawner.senses = senses
	squads.attach(spawner)
	sounds.attach(spawner)
	skill.attach(spawner)
	spawner.set_meta(HORDE_META, self)
	add_child(spawner)
	# Every kind's brain compiled now, while the map loads, rather than as a 30 ms hitch the
	# first time each special comes (an older dot-npc has no warm()).
	if spawner.has_method(&"warm"):
		var _warmed = spawner.call(&"warm")

	spawner.spawned.connect(_on_spawned)
	spawner.removed.connect(_on_removed)
	spawner.died.connect(_on_died)

	director = DotNpcDirector.new()
	director.name = "Director"
	director.spawner = spawner
	director.rules = _rules()
	director.population = [ZzNpcs.COMMON]
	director.enabled = false
	add_child(director)

	game.combat.entity_killed.connect(_on_entity_killed)
	game.combat.damage_applied.connect(_on_damage_applied)
	return DotResult.success(self)


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
	rules.spawn_min_distance = 22.0
	rules.spawn_max_distance = 60.0
	rules.spawn_ahead = 35.0
	rules.behind_fraction = 0.2
	rules.spawn_out_of_sight = true
	rules.spawn_burst = 3
	rules.spawn_interval = 0.6
	rules.reclaim_interval = 3.0
	rules.stress_per_damage = 1.2
	rules.stress_threat_radius = 6.0
	return rules


## Builds the horde for a map: its graph, its spawn points, its route, its sleepers, and the
## commons standing about in it.
func build_for_map(doc: Dictionary) -> DotResult:
	clear()
	_doc = doc
	open_gates = PackedStringArray()
	# Sized for the team the map is built for: a dozen survivors' cap on four survivors' budget
	# had the spawner refuse two of every three of a wave.
	spawner.limits = ZzNpcs.limits(config, _planned_team())

	var built := rebuild_navigation()

	if not built.ok:
		return built

	var route := PackedVector3Array()
	for p: Array in doc.get("route", []):
		route.append(ZzMapDoc.v3(p))
	director.flow = DotNpcDirectorFlow.new(route) if route.size() >= 2 else null

	_place_sleepers()
	_place_wanderers()
	_begin_notes()
	return DotResult.success(null)


## Starts annotating the map's colliders: bake, annotate, and then [method _plan_notes]. Survival
## and exodus alike (the zombies' drops and spread are for both); only a survival map's stand-ins
## hold the chokes.
func _begin_notes() -> void:
	notes.clear()

	if game == null or game.map == null or game.physics == null:
		return

	notes.begin(config, game.map, game.physics.layer_mask(&"world") | game.physics.layer_mask(&"prop"), _note_seeds())


func _note_seeds() -> PackedVector3Array:
	var seeds := PackedVector3Array()

	for i in 4:
		var spot: Array = game.map.spawn("survivors", i)
		seeds.append(spot[0])

	return seeds


## The graph the spawner built is a plain one; the zombies' is `ZzNavGraph`, which also knows the
## drops. Swapped in after every rebuild, with the links put back.
func _adopt_links() -> void:
	var graph := ZzNavGraph.new()

	if not graph.rebuild(nav).ok:
		return

	spawner.nav = graph

	if notes.is_ready():
		notes.apply_links(graph)


func _plan_notes() -> void:
	var posts := PackedVector3Array()

	for p: Array in _doc.get("posts", []):
		posts.append(ZzMapDoc.v3(p))

	notes.plan(spawner.nav, director.spawn_points, posts)


## Where a zombie keyed [param key] should walk on its way to [param goal]: through the choke it
## was given. The goal itself with `zz_zombie_spread` off or no notes.
func waypoint_for(key: int, from: Vector3, goal: Vector3) -> Vector3:
	if not config.zombie_spread:
		return goal

	return notes.waypoint_for(key, from, goal)


func rebuild_navigation() -> DotResult:
	var props_size := Callable()

	if game.props_catalogue != null:
		props_size = func(id: StringName) -> Vector3:
			return game.props_catalogue.size_of(id) if game.props_catalogue.has(id) else Vector3.ZERO

	var started := Time.get_ticks_msec()
	nav = ZzNpcs.nav_for(_doc, props_size, open_gates)

	var valid := nav.validate()

	if not valid.ok:
		return valid.wrap("The map's navigation is not usable")

	var applied := spawner.set_nav_data(nav)

	if not applied.ok:
		return applied

	_adopt_links()

	var _from_nav := director.set_spawn_points_from_nav(nav, 6.0, DotNpcNavFilter.walking_only())
	_add_hinted_spawns()
	var kept := _keep_out_of_safe_rooms()

	DotLog.info(CHANNEL, "navigation built", {
		"map": str(_doc.get("id", "")), "points": nav.point_count(), "edges": nav.edge_count(),
		"spawns": kept, "ms": Time.get_ticks_msec() - started,
	})
	return DotResult.success(kept)


## A map's own `zombie_spawns` join the ones the graph gave: a mapper who wants a crowd to
## pour out of a particular alley says so.
func _add_hinted_spawns() -> void:
	for p: Array in _doc.get("zombie_spawns", []):
		director.spawn_points.append(ZzMapDoc.v3(p))


## Drops every spawn point inside a start or end area, and a metre round it. The graph puts
## points wherever there is floor, and a safe room is floor: the first dedicated run had six
## wanderers standing in the end room, waiting for the survivors who made it.
func _keep_out_of_safe_rooms() -> int:
	var rooms: Array[AABB] = []
	var areas: Dictionary = _doc.get("areas", {})

	for side in ["start", "end"]:
		for area: Dictionary in areas.get(side, []):
			rooms.append(ZzMapDoc.area_box(area).grow(1.0))

	var kept := PackedVector3Array()

	for p: Vector3 in director.spawn_points:
		var inside := false

		for room in rooms:
			if p.x >= room.position.x and p.x <= room.end.x and p.z >= room.position.z and p.z <= room.end.z:
				inside = true
				break

		if not inside:
			kept.append(p)

	director.spawn_points = kept
	return kept.size()


## The graph's point at each survivor's feet, for "can a zombie from there reach anybody".
func _survivor_nodes() -> PackedInt32Array:
	var out := PackedInt32Array()

	if spawner.nav == null or spawner.nav.data == null:
		return out

	for id in survivor_ids():
		var index := spawner.nav.data.nearest_point(survivor_position(id), 3.0)

		if index >= 0:
			out.append(index)

	return out


## Whether a zombie at [param p] could walk to any survivor. A graph cut by a shut gate is two
## pieces, and a mob spawned in the other one presses against the gate for the whole hold-out:
## the first dedicated run's panic did exactly that, forty commons on the far side of the
## barrier while the survivors held the switch with nothing to shoot.
func _reaches_somebody(p: Vector3, nodes: PackedInt32Array) -> bool:
	if nodes.is_empty():
		return true

	var index := spawner.nav.data.nearest_point(p, 3.0)

	for node in nodes:
		if spawner.nav.connected(index, node):
			return true

	return false


## Opens a gate: the graph is built again without it.
func open_gate(gate: String) -> void:
	if open_gates.has(gate):
		return

	open_gates.append(gate)
	var _rebuilt := rebuild_navigation()


func clear() -> void:
	notes.clear()

	if spawner != null:
		var _cleared := spawner.clear_all(DotNpcSpawner.REASON_CLEANUP)

	_pending.clear()
	_alerts.clear()
	_lures.clear()
	_bile.clear()
	_panic_until = -1.0
	survival = false
	intensity = 1.0
	waves_mode = false
	wave_room = -1
	wave_speed_scale = 1.0
	wave_health_scale = 1.0
	pacing = false
	mob_rate_scale = 1.0
	special_rate_scale = 1.0
	special_health_scale = 1.0
	mob_size_scale = 1.0
	zombie_speed_scale = 1.0

	if director != null:
		director.enabled = false


## Starts the clocks: the team has left the start area, or a night fell.
func start_pacing(p_survival: bool) -> void:
	pacing = true
	waves_mode = false
	survival = p_survival
	_next_mob = _time + _rng.randf_range(config.mob_interval_min, config.mob_interval_max) * (0.5 if survival else 1.0)
	_next_special = _time + _rng.randf_range(8.0, 20.0)

	if config.brute_interval_max > 0.0:
		_next_brute = _time + _rng.randf_range(config.brute_interval_min, config.brute_interval_max) * (0.6 if survival else 1.0)
	else:
		_next_brute = INF

	director.enabled = config.director_enabled
	DotLog.info(CHANNEL, "the horde is coming", {"survival": survival})


## A wave is on: perception, brains and panic run, and nothing spawns but what the survival
## runtime releases through [method spawn_wave], [method spawn_special] and [method spawn_brute].
func start_waves() -> void:
	pacing = true
	waves_mode = true
	survival = true
	director.enabled = false
	_next_mob = INF
	_next_special = INF
	_next_brute = INF


func stop_pacing() -> void:
	pacing = false
	waves_mode = false
	director.enabled = false


## Sleepers sit where the map put them.
func _place_sleepers() -> void:
	if not config.sleepers_enabled:
		return

	for s: Array in _doc.get("sleepers", []):
		var at := Vector3(float(s[0]), float(s[1]), float(s[2]))
		var npc := spawner.spawn(ZzNpcs.SLEEPER, at, &"map", Basis(Vector3.UP, deg_to_rad(float(s[3]))))

		if npc == null:
			DotLog.warn(CHANNEL, "a sleeper could not be placed", {"at": str(at)})


## The share of the commons cap a survival map's wanderers may take. The waves are the hold;
## the ballpark's floor area put sixty-five wanderers on it, idle in the far stands, and a wave
## had seventeen places left under the cap: its spawns were refused for minutes ("sent" fell
## back) and the team stood about. What is left of them each wave is sent in
## ([method send_map_commons]).
const SURVIVAL_WANDERER_SHARE := 0.2


## Commons standing about: clusters on the graph, never near where the team starts.
func _place_wanderers() -> void:
	if nav == null or config.wanderer_density <= 0.0:
		return

	var area := 0.0
	for f: Array in (_doc.get("nav", {}) as Dictionary).get("floors", []):
		area += (float(f[2]) - float(f[0])) * (float(f[3]) - float(f[1]))

	var share := SURVIVAL_WANDERER_SHARE if str(_doc.get("mode", "")) == "survival" else 0.8
	var wanted := mini(int(area / 100.0 * config.wanderer_density), int(config.commons_cap(_planned_team()) * share))
	var starts := _start_points()
	var candidates := director.spawn_points.duplicate()
	var placed := 0
	var guard := 0

	while placed < wanted and guard < wanted * 6 and not candidates.is_empty():
		guard += 1
		var pick := _rng.randi_range(0, candidates.size() - 1)
		var centre: Vector3 = candidates[pick]
		candidates.remove_at(pick)

		var too_near := false
		for s in starts:
			if centre.distance_to(s) < WANDERER_CLEARANCE:
				too_near = true
				break

		if too_near:
			continue

		var cluster := _rng.randi_range(1, 5)

		for i in cluster:
			if placed >= wanted:
				break

			var offset := Vector3(_rng.randf_range(-2.5, 2.5), 0.0, _rng.randf_range(-2.5, 2.5))
			var at := nav.snap(centre + offset, 2.0)
			var npc := spawner.spawn(ZzNpcs.COMMON, at, &"map", Basis(Vector3.UP, _rng.randf() * TAU))

			if npc != null:
				placed += 1

	DotLog.debug(CHANNEL, "wanderers placed", {"wanted": wanted, "placed": placed})


## The team the map in play is built for, or the survivors there are, whichever is more.
func _planned_team() -> int:
	var team: int = game.team_size() if game != null and game.has_method(&"team_size") else 4
	return maxi(team, game.survivors().size() if game != null else 1)


func _start_points() -> Array[Vector3]:
	var out: Array[Vector3] = []

	for spawn: Dictionary in (_doc.get("spawns", {}) as Dictionary).get("survivors", []):
		out.append(ZzMapDoc.v3(spawn["at"]))

	return out


# --- The tick --------------------------------------------------------------------------------

## One tick. After the survivors moved and shot, before anything reads where a zombie is.
func tick(delta: float) -> void:
	if spawner == null:
		return

	_time += delta

	if notes.tick():
		_plan_notes()

	notes.update(delta, self)
	_rebuild_candidates()
	_rebuild_grid()
	spawner.set_candidates(_candidates)
	_land_alerts()
	_advance_lures()
	_advance_bile()
	spawner.tick(delta)

	var speed := zombie_speed_scale * wave_speed_scale

	for npc in spawner.all_npcs():
		if npc.is_alive() and npc.node is ZzZombieBody:
			var b := npc.node as ZzZombieBody
			b.speed_scale = speed * (game.water_pace_at(b.global_position) if game != null else 1.0)
			b.tick(delta)

	squads.prune()
	_release_pending()

	if not pacing:
		return

	if waves_mode:
		_advance_panic()
		return

	for id: StringName in _survivors:
		var info: Dictionary = _survivors[id]

		if bool(info["alive"]):
			director.report_player(id, info["position"], float(info["health"]))

	director.rules.absolute_cap = config.commons_cap(_survivor_count())
	director.tick(delta)

	_advance_mobs()
	_advance_specials()
	_advance_brute()
	_advance_panic()


## The survivors, as perception candidates and as facts a brain asks about.
func _rebuild_candidates() -> void:
	_candidates.clear()
	_survivors.clear()

	for player in game.survivors():
		var id: StringName = player.player_id
		var state: DotFpsState = player.controller.state
		# A seat behind its loading cover is not a target: not chased, not spawned at, not counted
		# in the crowd's size (dot-game's "still loading"); it is still alive for the round.
		var alive: bool = player.is_alive() and not player.watching and game.can_be_harmed(id)

		_survivors[id] = {
			"position": state.position,
			"eye": player.eye_position(),
			"alive": alive,
			"up": player.is_up(),
			"down": player.is_down(),
			"pinned": player.is_pinned(),
			"biled": _bile.has(id),
			"health": player.health_fraction() if alive else 0.0,
			"entity": player.entity_id,
		}

		if not alive:
			continue

		var speed := state.horizontal_speed()
		var loudness := 0.0 if speed < 0.5 else lerpf(3.0, 14.0, clampf(speed / 7.0, 0.0, 1.0))

		if state.is_crouched():
			loudness *= 0.3

		_candidates.append(DotNpcSenses.Candidate.new(
			id, state.position + Vector3(0.0, 1.0, 0.0), &"survivor", loudness
		))


func _survivor_count() -> int:
	var n := 0

	for id: StringName in _survivors:
		if bool((_survivors[id] as Dictionary)["alive"]):
			n += 1

	return maxi(n, 1)


# --- What brains ask -------------------------------------------------------------------------

func survivor_position(id: StringName) -> Vector3:
	var info: Variant = _survivors.get(id)
	return (info as Dictionary)["position"] if info != null and bool((info as Dictionary)["alive"]) else Vector3.INF


func survivor_eye(id: StringName) -> Vector3:
	var info: Variant = _survivors.get(id)
	return (info as Dictionary)["eye"] if info != null else Vector3.INF


func survivor_alive(id: StringName) -> bool:
	var info: Variant = _survivors.get(id)
	return info != null and bool((info as Dictionary)["alive"])


func survivor_is(id: StringName, what: StringName) -> bool:
	var info: Variant = _survivors.get(id)
	return info != null and bool((info as Dictionary).get(what, false))


## Every living survivor's id.
func survivor_ids() -> Array[StringName]:
	var out: Array[StringName] = []

	for id: StringName in _survivors:
		if bool((_survivors[id] as Dictionary)["alive"]):
			out.append(id)

	return out


func _rebuild_grid() -> void:
	_grid.clear()
	_grid_pos.clear()
	var kill_y := float(_doc.get("kill_y", -30.0))
	var fell: Array[DotNpcInstance] = []

	for npc in spawner.all_npcs():
		if not npc.is_alive():
			continue

		var p := npc.position()

		if p.y < kill_y or not p.is_finite():
			fell.append(npc)
			continue

		_grid_pos[npc.instance_id] = p
		var key := Vector2i(floori(p.x / GRID), floori(p.z / GRID))
		var cell: Variant = _grid.get(key)

		if cell == null:
			_grid[key] = [npc]
		else:
			(cell as Array).append(npc)

	for npc in fell:
		_fell_out(npc)


## Where zombies that fell out of the map last stood on its floor, newest last (a few kept), for
## a tool or a console asking how they got there.
var fallen_from: Array[Vector3] = []
## How each of [member fallen_from] left the floor: "leapt N ticks before", or "walked".
var fallen_how: PackedStringArray = PackedStringArray()
var fallen_count: int = 0
const FALLEN_KEPT := 16


## A zombie below the map's kill_y (or somewhere not a number) is taken out of the world, and a
## wave's is owed again. Nothing used to: one that fell through the mall's floor fell for the rest
## of the hold, its brain facing it at survivors from ever further down, and a body far enough
## out made `look_at` refuse once a think (sixty-five errors in one run, zz-mall-lookat-errors-1).
func _fell_out(npc: DotNpcInstance) -> void:
	var b := npc.node as ZzZombieBody
	var from: Vector3 = b.last_floor_at if b != null else Vector3.INF
	var how := "walked"
	if b != null and b.ticks_since_leap < 64 * 60:
		how = "%s %s, leapt %d ticks before" % [npc.def.id if npc.def != null else "?", "flying" if b.flying else "falling", b.ticks_since_leap]
	fallen_from.append(from)
	fallen_how.append(how)
	fallen_count += 1

	if fallen_from.size() > FALLEN_KEPT:
		fallen_from.remove_at(0)
		fallen_how.remove_at(0)

	DotLog.warn(CHANNEL, "a zombie fell out of the map", {"kind": String(npc.def.id) if npc.def != null else "?",
		"last_on_floor": str(from.snappedf(0.1)), "at": str(npc.position().snappedf(0.1)), "how": how})

	if npc.owner_id == WAVE:
		refused_wave += 1

	var _gone := spawner.remove(npc.instance_id, DotNpcSpawner.REASON_CLEANUP)


## Living zombies within [param radius] of [param point] (in 3D), from this tick's grid.
func zombies_near(point: Vector3, radius: float) -> Array[DotNpcInstance]:
	var out: Array[DotNpcInstance] = []
	var reach := radius * radius
	var x0 := floori((point.x - radius) / GRID)
	var x1 := floori((point.x + radius) / GRID)
	var z0 := floori((point.z - radius) / GRID)
	var z1 := floori((point.z + radius) / GRID)

	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var cell: Variant = _grid.get(Vector2i(cx, cz))

			if cell == null:
				continue

			for npc: DotNpcInstance in cell:
				if npc.is_alive() and (_grid_pos[npc.instance_id] as Vector3).distance_squared_to(point) <= reach:
					out.append(npc)

	return out


## Where the zombies round [param npc] are, for its crowd spacing (dot-npc-ai's `neighbours`).
func neighbour_positions(npc: DotNpcInstance, radius: float) -> Array:
	var out: Array = []
	var here: Vector3 = _grid_pos.get(npc.instance_id, npc.position())

	for other in zombies_near(here, radius):
		if other.instance_id != npc.instance_id:
			out.append(_grid_pos[other.instance_id])

	return out


## Metres from [param at] to the nearest living survivor, flat; INF with nobody.
func nearest_survivor_distance(at: Vector3) -> float:
	var best := INF

	for id: StringName in _survivors:
		var info: Dictionary = _survivors[id]

		if bool(info["alive"]):
			var p: Vector3 = info["position"]
			best = minf(best, Vector2(p.x - at.x, p.z - at.z).length())

	return best


## How many survivors are within [param radius] of [param at], up and on their feet.
func survivors_near(at: Vector3, radius: float, exclude: StringName = &"") -> int:
	var n := 0

	for id: StringName in _survivors:
		var info: Dictionary = _survivors[id]

		if id == exclude or not bool(info["up"]):
			continue

		if (info["position"] as Vector3).distance_to(at) <= radius:
			n += 1

	return n


## Whether any living survivor can see [param point] (eye to eye height).
func seen_by_survivors(point: Vector3, height: float = 1.4) -> bool:
	for id: StringName in _survivors:
		var info: Dictionary = _survivors[id]

		if not bool(info["alive"]):
			continue

		if line_clear(info["eye"], point + Vector3(0.0, height, 0.0)):
			return true

	return false


func line_clear(from: Vector3, to: Vector3) -> bool:
	return game.clear_between(from, to)


func snap_to_nav(at: Vector3) -> Vector3:
	return nav.snap(at, 3.0) if nav != null else at


## A zombie's swing landed on [param victim]. Through the game: the difficulty, the down, the
## slowdown and the stats are all its.
func melee(npc: DotNpcInstance, victim: StringName, amount: float) -> void:
	if npc == null or not npc.is_alive():
		return

	game.zombie_hit(npc, entity_id_for(npc), victim, amount)


## Everything a special does that touches a survivor goes through the game, which owns pins
## and hazards. These are the names a special's brain calls.
func pin(npc: DotNpcInstance, victim: StringName, kind: StringName) -> bool:
	return bool(game.pins.pin(entity_id_for(npc), npc, victim, kind))


func unpin(npc: DotNpcInstance) -> void:
	game.pins.release_by(entity_id_for(npc), &"let go")


func pinning(npc: DotNpcInstance) -> StringName:
	return game.pins.victim_of(entity_id_for(npc))


func hazard(kind: StringName, at: Vector3, radius: float, seconds: float, amount: float, npc: DotNpcInstance = null) -> void:
	game.hazards.add(kind, at, radius, seconds, amount, entity_id_for(npc) if npc != null else 0)


func projectile(kind: StringName, from: Vector3, velocity: Vector3, npc: DotNpcInstance, amount: float) -> void:
	game.hazards.launch(kind, from, velocity, entity_id_for(npc) if npc != null else 0, amount)


func bile(victim: StringName, seconds: float, by: DotNpcInstance = null) -> void:
	game.bile_survivor(victim, seconds, entity_id_for(by) if by != null else 0)


func knock(victim: StringName, from: Vector3, amount: float, npc: DotNpcInstance) -> void:
	game.knock_survivor(victim, from, amount, entity_id_for(npc) if npc != null else 0)


func now() -> float:
	return spawner.now() if spawner != null else _time


# --- Alerts, lures, bile ---------------------------------------------------------------------

## A zombie screamed: every idle common within [constant ALERT_RADIUS] wakes, one after another.
func spread_alert(npc: DotNpcInstance, who: StringName, where: Vector3) -> void:
	if spawner == null or npc == null:
		return

	for other in spawner.npcs_near(npc.position(), ALERT_RADIUS):
		if other == npc or other.def.id != ZzNpcs.COMMON or other.brain == null:
			continue

		var gap := other.position().distance_to(npc.position())
		# Nearer ones first, and none at once: the room wakes over half a second.
		_alerts.append([other.instance_id, _time + 0.12 + gap * 0.05 + _rng.randf() * 0.25, who, where])


## A screamer screamed: everything idle within twice the alert radius wakes, and a mob of
## [param size] comes for [param victim] from out of sight. Returns the mob's size.
func scream(npc: DotNpcInstance, victim: StringName, size: int) -> int:
	if spawner == null or npc == null or not npc.is_alive():
		return 0

	screams += 1

	for other in spawner.npcs_near(npc.position(), ALERT_RADIUS * 2.0):
		if other != npc and other.def.id == ZzNpcs.COMMON and other.brain != null:
			var gap := other.position().distance_to(npc.position())
			_alerts.append([other.instance_id, _time + 0.1 + gap * 0.03, victim, survivor_position(victim)])

	var grown := size

	if survival:
		grown = int(round(float(size) * intensity))

	DotLog.debug(CHANNEL, "a scream", {"victim": String(victim), "mob": grown})
	return spawn_mob(maxi(int(round(float(grown) * mob_size_scale)), 0), victim)


func _land_alerts() -> void:
	if _alerts.is_empty():
		return

	var kept: Array = []

	for alert: Array in _alerts:
		if float(alert[1]) > _time:
			kept.append(alert)
			continue

		var npc := spawner.get_npc(int(alert[0]))

		if npc != null and npc.is_alive() and npc.brain != null and npc.brain.has_method(&"wake"):
			npc.brain.call(&"wake", alert[2], alert[3], 0.0)

	_alerts = kept


## Something that draws the crowd: a beeping charge, a flare. Commons within [param radius]
## go to it and stay there until [param seconds] pass.
func lure(at: Vector3, seconds: float, radius: float = 40.0) -> void:
	_lures.append({"at": at, "until": _time + seconds, "radius": radius})

	for npc in spawner.npcs_near(at, radius):
		if npc.def.id == ZzNpcs.COMMON and npc.brain != null:
			npc.brain.call(&"lure_to", at)


func _advance_lures() -> void:
	if _lures.is_empty():
		return

	var kept: Array = []

	for l: Dictionary in _lures:
		if float(l["until"]) > _time:
			kept.append(l)
			continue

		for npc in spawner.npcs_near(l["at"], float(l["radius"]) + 10.0):
			if npc.brain != null and npc.brain.has_method(&"lure_to"):
				npc.brain.call(&"lure_to", Vector3.INF)

	_lures = kept


## A survivor is covered in bile: every common in reach comes for them, and a mob is called.
## A bile jar broken at [param at]: every common within [param radius] comes to it for
## [param seconds], and the ones it splashed are drawn covered in it. Commons turning on the
## splashed ones (the genre's half of a bile jar) is not here yet: a common's brain only ever
## targets survivors.
func bile_at(at: Vector3, seconds: float, radius: float) -> void:
	lure(at, seconds, radius)

	for npc in spawner.npcs_near(at, BILE_SPLASH):
		if npc.def.id == ZzNpcs.COMMON and npc.node is ZzZombieBody:
			(npc.node as ZzZombieBody).set_flag(ZzZombieBody.FLAG_BILED, true)


func bile_on(victim: StringName, seconds: float) -> void:
	var at := survivor_position(victim)

	if at == Vector3.INF:
		return

	var fresh := not _bile.has(victim)
	_bile[victim] = maxf(float(_bile.get(victim, 0.0)), _time + seconds)

	for npc in spawner.npcs_near(at, BILE_RADIUS):
		if npc.def.id == ZzNpcs.COMMON and npc.brain != null:
			npc.brain.call(&"force_target", victim)
			(npc.node as ZzZombieBody).set_flag(ZzZombieBody.FLAG_MOB, true)

	if fresh:
		spawn_mob(int(round(float(_mob_size()) * 0.8)), victim)


func _advance_bile() -> void:
	for id: StringName in _bile.keys():
		if float(_bile[id]) <= _time:
			_bile.erase(id)


func is_biled(id: StringName) -> bool:
	return _bile.has(id)


# --- Mobs -----------------------------------------------------------------------------------

func _mob_size() -> int:
	var size := float(config.mob_size + config.mob_size_per_survivor * maxi(_survivor_count() - 1, 0))

	if survival:
		# Survival: as much bigger as the hold is harder (the runtime's intensity).
		size *= intensity

	return maxi(int(round(size * mob_size_scale)), 1)


func _advance_mobs() -> void:
	if _time < _next_mob:
		return

	var interval := _rng.randf_range(config.mob_interval_min, config.mob_interval_max)

	if survival:
		interval *= clampf(1.0 / maxf(intensity, 0.01), 0.35, 1.0) * 0.6

	_next_mob = _time + interval / maxf(mob_rate_scale, 0.05)
	spawn_mob(_mob_size())


## A mob of [param size] commons that knows where the team is, out of sight, a few at a time.
## [param target] chooses whom they all go for; empty spreads them over the team.
func spawn_mob(size: int, target: StringName = &"") -> int:
	var ids := survivor_ids()

	if waves_mode and wave_room >= 0:
		size = mini(size, maxi(wave_room - commons() - pending_commons(), 0))

	if ids.is_empty() or size <= 0:
		return 0

	var origins: Array[Vector3] = []

	for i in mini(1 + size / 12, 3):
		var spot := _spawn_point(18.0, 55.0, true)

		if spot != Vector3.INF:
			origins.append(spot)

	if origins.is_empty():
		DotLog.debug(CHANNEL, "a mob found nowhere out of sight to come from", {})
		return 0

	for i in size:
		var who := target if target != &"" else ids[i % ids.size()]
		_pending.append([ZzNpcs.COMMON, origins[i % origins.size()], who, ZzZombieBody.FLAG_MOB])

	mob_started.emit(size)
	DotLog.debug(CHANNEL, "a mob is coming", {"size": size, "from": origins.size()})
	return size


func _release_pending() -> void:
	if _pending.is_empty() or _time < _next_pending:
		return

	_next_pending = _time + MOB_BURST_SECONDS

	for i in mini(MOB_BURST, _pending.size()):
		var entry: Array = _pending.pop_front()
		var at: Vector3 = entry[1]
		var owner: StringName = entry[4] if entry.size() > 4 else &"mob"
		var npc := spawner.spawn(entry[0], nav.snap(at + Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0)), 2.5), owner)

		if npc == null:
			if owner == WAVE:
				refused_wave += 1
			continue

		(npc.node as ZzZombieBody).set_flag(int(entry[3]), true)

		if owner == WAVE and wave_health_scale != 1.0:
			_rescale_health(npc, wave_health_scale)

		if npc.brain != null and entry[2] != &"":
			npc.brain.call(&"force_target", entry[2])


## A point out of every survivor's sight between [param near] and [param far] metres from the
## nearest of them, ahead along the route when there is one. INF when there is none.
func _spawn_point(near: float, far: float, prefer_ahead: bool, around: StringName = &"") -> Vector3:
	var points := director.spawn_points

	if points.is_empty():
		return Vector3.INF

	var party_flow := 0.0
	var has_flow := director.flow != null and director.flow.has_route()

	if has_flow:
		for id in survivor_ids():
			party_flow = maxf(party_flow, director.flow.flow_of(survivor_position(id)))

	var nodes := _survivor_nodes()
	# Sampled, not scanned: a few hundred candidates is a few hundred sight lines.
	var tries := mini(points.size(), 90)
	var scored: Array = []

	for i in tries:
		var p: Vector3 = points[_rng.randi_range(0, points.size() - 1)]
		var nearest := INF

		if around != &"":
			nearest = p.distance_to(survivor_position(around))
		else:
			for id in survivor_ids():
				nearest = minf(nearest, p.distance_to(survivor_position(id)))

		if nearest < near or nearest > far:
			continue

		var score := -absf(nearest - (near + far) * 0.5)

		if has_flow and prefer_ahead:
			score += clampf(director.flow.flow_of(p) - party_flow, -30.0, 30.0) * 0.5

		scored.append([score, i, p])

	# [b]Scored first, looked at in order, the first unseen one kept.[/b] The same answer as
	# testing every candidate's sight and keeping the best, without the sight lines: scanned,
	# a special's spot was up to ninety candidates times a dozen survivors' eyes, over a
	# thousand rays and a 35 ms tick every time a wave sent a special (tools/survival_long_run
	# --profile). Ties keep the order they were drawn in, as the scan did.
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) > float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))

	for entry: Array in scored:
		var p: Vector3 = entry[2]

		if _reaches_somebody(p, nodes) and not seen_by_survivors(p):
			return p

	return Vector3.INF


# --- Waves ------------------------------------------------------------------------------------

## The owner a wave's zombies are spawned under, which is how the wave counts what is left.
const WAVE := &"wave"

## Wave commons the spawner refused (no room, no ground), for the runtime to owe again.
var refused_wave: int = 0

## [param size] commons of a wave, released a few at a time from the map's edges (its
## `zombie_spawns`, out of sight and able to reach somebody) or, failing those, from the
## graph's own points, each sent at a survivor round the team. Returns how many were queued.
##
## [b]From the map's hints first.[/b] A survival map's hints are where the horde comes from:
## the car park, the outfield, the loading bays. Spawned anywhere out of sight instead, a wave
## came from inside the gym the team was holding, because the gym's back corner was out of
## everybody's sight.
func spawn_wave(size: int) -> int:
	var ids := survivor_ids()

	if ids.is_empty() or size <= 0:
		return 0

	var origins: Array[Vector3] = []

	for i in mini(1 + size / 8, 4):
		var spot := _wave_origin()

		if spot != Vector3.INF:
			origins.append(spot)

	if origins.is_empty():
		return 0

	for i in size:
		_pending.append([ZzNpcs.COMMON, origins[i % origins.size()], ids[(i + _rng.randi()) % ids.size()],
			ZzZombieBody.FLAG_MOB, WAVE])

	return size


## A hint the wave can come from: out of sight, at least fifteen metres from everybody, and on
## ground that reaches somebody. INF when no hint will do and no point of the graph either.
func _wave_origin() -> Vector3:
	var nodes := _survivor_nodes()
	var hints: Array = _doc.get("zombie_spawns", [])
	var order: Array = range(hints.size())
	order.shuffle()

	for i: int in order:
		var p := ZzMapDoc.v3(hints[i])
		var nearest := INF

		for id in survivor_ids():
			nearest = minf(nearest, p.distance_to(survivor_position(id)))

		if nearest < 15.0 or seen_by_survivors(p) or not _reaches_somebody(p, nodes):
			continue

		return p

	return _spawn_point(15.0, 90.0, false)


## The map's own commons (its wanderers) still alive are sent at the team, spread round it. A
## survival wave calls it as it begins: a wanderer left idle in the far stands holds a place
## under the cap the wave needs. Returns how many were sent.
func send_map_commons() -> int:
	var ids := survivor_ids()
	var sent := 0

	if ids.is_empty():
		return 0

	for npc in spawner.npcs_of(&"map"):
		if not npc.is_alive() or npc.def == null or npc.def.id != ZzNpcs.COMMON or npc.brain == null:
			continue

		npc.brain.call(&"force_target", ids[_rng.randi_range(0, ids.size() - 1)])
		sent += 1

	return sent


## Commons queued to spawn and not yet out: what a release must leave room for.
func pending_commons() -> int:
	var n := 0

	for entry: Array in _pending:
		if entry[0] == ZzNpcs.COMMON:
			n += 1

	return n


## Wave zombies still alive, queued, or about to be.
func wave_alive() -> int:
	var n := 0

	for npc in spawner.npcs_of(WAVE):
		if npc.is_alive():
			n += 1

	for entry: Array in _pending:
		if entry.size() > 4 and entry[4] == WAVE:
			n += 1

	return n


## The brutes of the wave still standing.
func wave_brutes() -> int:
	var n := 0

	for npc in spawner.npcs_of(WAVE):
		if npc.is_alive() and npc.def != null and npc.def.id == ZzNpcs.BRUTE:
			n += 1

	return n


## The wave ended on its overtime: what is left of it a long way from everybody (stuck, lost)
## is tidied away, and the rest are sent at the team. Returns how many were tidied. A brute
## still standing leaves with the far ones wherever it is: sent at the team, it went on through
## the breather into the next wave (zz-survival-retune-2).
func clear_wave_stragglers(far: float = 30.0) -> int:
	var tidied := 0
	var ids := survivor_ids()

	for npc in spawner.npcs_of(WAVE):
		if not npc.is_alive():
			continue

		var nearest := INF
		for id in ids:
			nearest = minf(nearest, npc.position().distance_to(survivor_position(id)))

		if nearest > far or (npc.def != null and npc.def.id == ZzNpcs.BRUTE):
			var _gone := spawner.remove(npc.instance_id, DotNpcSpawner.REASON_CLEANUP)
			tidied += 1
		elif npc.brain != null and not ids.is_empty():
			npc.brain.call(&"force_target", ids[_rng.randi_range(0, ids.size() - 1)])

	return tidied


## At dawn the dark's own leave: every zombie further than [param far] from every survivor and
## chasing nobody goes back to wherever they go by day. Returns how many.
func dawn(far: float = 30.0) -> int:
	var gone := 0
	var ids := survivor_ids()

	for npc in spawner.all_npcs():
		if not npc.is_alive() or npc.owner_id == &"map":
			continue

		var nearest := INF
		for id in ids:
			nearest = minf(nearest, npc.position().distance_to(survivor_position(id)))

		if nearest > far:
			var _removed := spawner.remove(npc.instance_id, DotNpcSpawner.REASON_CLEANUP)
			gone += 1

	return gone


# --- Barricades --------------------------------------------------------------------------------

## The barricades of the map in play, as the game holds them: `{id: AABB}` of the intact ones.
## Called by the game whenever one breaks or is mended.
func set_barricades(bounds: Dictionary) -> void:
	barricades.clear()
	_barricade_cells.clear()

	for id: String in bounds:
		var box: AABB = bounds[id]
		barricades[id] = {"bounds": box, "centre": box.get_center()}
		var grown := box.grow(BASH_REACH + 0.5)
		for cx in range(floori(grown.position.x / BARRICADE_CELL), floori(grown.end.x / BARRICADE_CELL) + 1):
			for cz in range(floori(grown.position.z / BARRICADE_CELL), floori(grown.end.z / BARRICADE_CELL) + 1):
				var key := Vector2i(cx, cz)
				if not _barricade_cells.has(key):
					_barricade_cells[key] = []
				(_barricade_cells[key] as Array).append(id)


## The intact barricade a zombie at [param at] wanting to go [param wish] is pressed against,
## or "". Against its face (within [constant BASH_REACH] of its box, horizontally) and heading
## into it, not along it or away.
func barricade_in_way(at: Vector3, wish: Vector3) -> String:
	if _barricade_cells.is_empty():
		return ""

	var ids: Variant = _barricade_cells.get(Vector2i(floori(at.x / BARRICADE_CELL), floori(at.z / BARRICADE_CELL)))

	if ids == null:
		return ""

	for id: String in ids:
		var entry: Dictionary = barricades[id]
		var box: AABB = entry["bounds"]
		var dx := maxf(maxf(box.position.x - at.x, at.x - box.end.x), 0.0)
		var dz := maxf(maxf(box.position.z - at.z, at.z - box.end.z), 0.0)

		if dx * dx + dz * dz > BASH_REACH * BASH_REACH or at.y > box.end.y or at.y + 1.8 < box.position.y:
			continue

		# Toward the nearest point of the boards, not their middle: a zombie in the corner of a
		# four-metre window, pressed along it by the crowd, wished away from the middle and never
		# bashed (the ballpark's tunnels: a wave's last few stood there until its overtime).
		var toward := Vector3(clampf(at.x, box.position.x, box.end.x) - at.x, 0.0, clampf(at.z, box.position.z, box.end.z) - at.z)

		if toward.length_squared() < 0.0001:
			toward = (entry["centre"] as Vector3) - at
			toward.y = 0.0

		if wish.dot(toward) > 0.0:
			return id

	return ""


func barricade_centre(id: String) -> Vector3:
	var entry: Variant = barricades.get(id)
	return (entry as Dictionary)["centre"] if entry != null else Vector3.INF


## A zombie spent [param delta] seconds tearing at barricade [param id]. Through the game, which
## owns its strength. A brute's arms are ten of a common's; a special's two.
func bash(id: String, npc: DotNpcInstance, delta: float) -> void:
	if game == null or npc == null or not npc.is_alive():
		return

	var arms := 10.0 if npc.def.id == ZzNpcs.BRUTE else 2.0 if ZzNpcs.is_special(npc.def.id) else 1.0
	game.bash_barricade(id, config.barricade_bash * arms * delta)


# --- Specials ---------------------------------------------------------------------------------

func _allowed_specials() -> Array[StringName]:
	var out: Array[StringName] = []

	for kind in ZzNpcs.SPECIALS:
		if config.special_kinds.is_empty() or config.special_kinds.has(String(kind)):
			out.append(kind)

	return out


func specials_alive() -> int:
	var n := 0

	for kind in ZzNpcs.SPECIALS:
		n += spawner.count_of(kind)

	return n


func _advance_specials() -> void:
	if _time < _next_special:
		return

	var interval := _rng.randf_range(config.special_interval_min, config.special_interval_max)

	if survival:
		interval *= clampf(1.0 / sqrt(maxf(intensity, 0.01)), 0.4, 1.0)

	_next_special = _time + interval / maxf(special_rate_scale, 0.05)

	if specials_alive() >= config.specials_cap(_survivor_count()):
		return

	var kinds := _allowed_specials()

	if kinds.is_empty():
		return

	# Prefer a kind that is not already out: two leapers at once is less frightening than a
	# leaper and a strangler, because the second is a different problem.
	var fresh: Array[StringName] = []
	for kind in kinds:
		if spawner.count_of(kind) == 0:
			fresh.append(kind)

	var pool := fresh if not fresh.is_empty() else kinds
	var _made := spawn_special(pool[_rng.randi_range(0, pool.size() - 1)])


## One special, from wherever is worst for the team. Returns it, or null. [param owner] is
## `wave` for a wave's own, which the wave counts as left until it is dead.
func spawn_special(kind: StringName, at: Vector3 = Vector3.INF, owner: StringName = &"special") -> DotNpcInstance:
	var where := at

	if where == Vector3.INF:
		# Leapers and strangler come from further off; the rest close.
		var far := 40.0 if kind == ZzNpcs.STRANGLER or kind == ZzNpcs.LEAPER else 32.0
		where = _spawn_point(14.0, far, true)

	if where == Vector3.INF:
		return null

	var npc := spawner.spawn(kind, where, owner)

	if npc == null:
		return null

	if special_health_scale * wave_health_scale != 1.0:
		_rescale_health(npc, special_health_scale * wave_health_scale)

	special_spawned.emit(npc)
	DotLog.debug(CHANNEL, "a special", {"kind": String(kind), "at": str(where)})
	return npc


func _advance_brute() -> void:
	if _time < _next_brute:
		return

	var gap := _rng.randf_range(config.brute_interval_min, config.brute_interval_max)

	if survival:
		gap *= 0.6

	_next_brute = _time + maxf(gap, 30.0)

	if spawner.count_of(ZzNpcs.BRUTE) == 0:
		var _b := spawn_brute()


func spawn_brute(at: Vector3 = Vector3.INF, owner: StringName = &"brute") -> DotNpcInstance:
	var where := at if at != Vector3.INF else _spawn_point(20.0, 45.0, true)

	if where == Vector3.INF and owner == WAVE:
		where = _wave_origin()

	if where == Vector3.INF:
		return null

	var npc := spawner.spawn(ZzNpcs.BRUTE, where, owner)

	if npc == null:
		return null

	var health := ZzNpcs.brute_health(config, _survivor_count()) * special_health_scale
	_set_health(npc, health)
	brute_spawned.emit(npc)
	DotLog.info(CHANNEL, "a brute", {"health": health, "at": str(where)})
	return npc


# --- Panic -------------------------------------------------------------------------------------

## Mobs back to back for [param seconds]: an objective being held, an alarm going off.
func panic(seconds: float) -> void:
	_panic_until = maxf(_panic_until, _time + seconds)
	_next_panic_mob = _time + 2.0
	DotLog.info(CHANNEL, "panic", {"seconds": seconds})


## Whether a mob is still pouring out, or is on its way: a special's cue that the team is busy.
func mob_incoming() -> bool:
	if not _pending.is_empty():
		return true

	for npc in spawner.npcs_of(&"mob"):
		if npc.is_alive():
			return true

	return false


func panicking() -> bool:
	return _time < _panic_until


func _advance_panic() -> void:
	if _time >= _panic_until or _time < _next_panic_mob:
		return

	_next_panic_mob = _time + _rng.randf_range(10.0, 16.0) / maxf(mob_rate_scale, 0.05)
	spawn_mob(maxi(int(_mob_size() * 0.7), 4))


# --- Shoves, blasts, health ---------------------------------------------------------------------

## A shove from [param origin] along [param facing]: every zombie in the cone staggers back.
## Returns how many it moved.
func shove(origin: Vector3, facing: Vector3, reach: float, half_angle_deg: float, attacker: int, damage: float) -> int:
	var moved := 0
	var flat := Vector3(facing.x, 0.0, facing.z).normalized()
	var limit := cos(deg_to_rad(half_angle_deg))

	for npc in spawner.npcs_near(origin, reach + 1.0):
		if not npc.is_alive():
			continue

		var to := npc.position() - origin
		to.y = 0.0

		if to.length() > reach + float(npc.def.meta.get("radius", 0.3)):
			continue

		if to.length() > 0.2 and flat.dot(to.normalized()) < limit:
			continue

		# The heavy ones do not stagger: a shove that moved a brute would be a shove nobody
		# needed to think about. The ram is shoved only while it is not charging.
		if npc.def.id == ZzNpcs.BRUTE or npc.def.id == ZzNpcs.SLEEPER:
			continue

		if npc.brain != null and npc.brain.has_method(&"stagger"):
			npc.brain.call(&"stagger", to if to.length() > 0.1 else flat, 0.9, 5.5)

		if damage > 0.0:
			var hit := DotDamage.make(attacker, entity_id_for(npc), damage, game.combat.damage_type(&"strike"))
			hit.weapon_id = &"shove"
			hit.tick = game.current_tick()
			var _applied = game.combat.apply_damage(hit)

		moved += 1

	return moved


## A blast: zombies inside stagger away from it. The damage is dot-combat's (`explode`).
func blast(at: Vector3, radius: float) -> void:
	for npc in spawner.npcs_near(at, radius):
		if npc.brain != null and npc.brain.has_method(&"stagger") and npc.def.id != ZzNpcs.BRUTE:
			var away := npc.position() - at
			npc.brain.call(&"stagger", away, 1.2, 9.0)


func _rescale_health(npc: DotNpcInstance, factor: float) -> void:
	var health: DotHealth = npc.node.get_node_or_null(^"Health")

	if health != null:
		_set_health(npc, health.max_health * factor)


func _set_health(npc: DotNpcInstance, amount: float) -> void:
	var health: DotHealth = npc.node.get_node_or_null(^"Health")

	if health == null:
		return

	health.max_health = amount
	health.health = amount
	npc.health = amount


# --- Combat ------------------------------------------------------------------------------------

func entity_id_for(npc: DotNpcInstance) -> int:
	if npc == null or npc.node == null or not is_instance_valid(npc.node):
		return 0

	return game.entities.id_for_node(npc.node)


static func is_npc_entity(entity_id: int) -> bool:
	return DotEntity.is_kind(entity_id, DotEntity.KIND_NPC)


func npc_for_entity(entity_id: int) -> DotNpcInstance:
	return _by_entity.get(entity_id)


## Hitboxes and health, sized to the kind: a head a headshot can find, a body.
func _register_combat(npc: DotNpcInstance) -> void:
	var opened: DotResult = game.entities.open(
		DotEntity.KIND_NPC, npc.node, &"", &"", game.now()
	)

	if not opened.ok:
		DotLog.error(CHANNEL, "could not open an entity for a zombie", {
			"npc": String(npc.def.id), "why": opened.error.message,
		})
		return

	var entity: int = (opened.value as DotEntityHandle).id
	var def := npc.def
	var height := float(def.meta.get("height", 1.75))
	var radius := float(def.meta.get("radius", 0.32))

	# The health first, and that is not tidiness. A hitbox finds its owner as the nearest
	# ancestor carrying a DotHealth and remembers the answer; built before the health, every
	# hitbox settled on its own set as the owner, and every shot that hit a zombie was
	# credited to a node dot-combat had never heard of — and did nothing.
	var health := DotHealth.new()
	health.name = "Health"
	health.max_health = def.max_health
	health.max_armour = 0.0
	health.regen_per_second = 0.0
	health.set_tick_rate(game.tick_rate)
	npc.node.add_child(health)
	health.reset(game.current_tick())
	npc.health = health.health

	var set_node := DotHitboxSet.new()
	set_node.name = "Hitboxes"
	set_node.bounds_offset = Vector3(0.0, height * 0.5, 0.0)
	set_node.bounds_radius = height

	var head := DotHitbox.new()
	head.name = "Head"
	head.group = DotHitGroup.HEAD
	head.shape = DotHitbox.Shape.SPHERE
	head.radius = clampf(radius * 0.7, 0.18, 0.4)
	head.position = Vector3(0.0, height - head.radius * 1.1, 0.0)
	head.precedence = 10
	set_node.add_child(head)

	var chest := DotHitbox.new()
	chest.name = "Body"
	chest.group = DotHitGroup.CHEST
	chest.shape = DotHitbox.Shape.CAPSULE
	chest.radius = radius + 0.06
	chest.height = height * 0.82
	chest.position = Vector3(0.0, height * 0.41, 0.0)
	set_node.add_child(chest)

	# A riot zombie's shield: a hitbox of its own in front of it, nearer the gun than its body,
	# so a frontal shot stops there (nearest entry wins in dot-combat) and does `shield` of its
	# damage. From the side or behind, the body is nearer and takes it all.
	if def.meta.has("shield"):
		var shield := DotHitbox.new()
		shield.name = "Shield"
		shield.group = DotHitGroup.CHEST
		shield.shape = DotHitbox.Shape.BOX
		shield.half_extents = Vector3(0.36, height * 0.3, 0.05)
		shield.position = Vector3(0.0, height * 0.5, -(radius + 0.16))
		shield.damage_scale = clampf(float(def.meta["shield"]), 0.0, 1.0)
		shield.precedence = 20
		set_node.add_child(shield)

	npc.node.add_child(set_node)
	# Not optional: a set gathers its boxes on refresh, and one never refreshed has none — a
	# zombie every shot passed through, stopped instead by its own movement capsule.
	set_node.refresh()

	set_node.register_with(game.combat, entity)
	game.combat.register_health(entity, health)
	game.combat.set_authoritative_origin(entity, npc.position())

	_by_entity[entity] = npc


func _forget_combat(npc: DotNpcInstance) -> void:
	var entity := entity_id_for(npc)

	if entity == 0:
		return

	if game.combat != null and is_instance_valid(game.combat):
		game.combat.forget(entity)

	game.entities.close(entity, DotEntityTable.REASON_KILLED)
	_by_entity.erase(entity)


func _on_spawned(npc: DotNpcInstance) -> void:
	var b := npc.node as ZzZombieBody

	if b != null:
		b.configure(npc.def)
		b.variant = _rng.randi() & 0xFFFF

		if game.physics != null:
			var _put = game.physics.apply_to(b, &"zombie")
			b.collision_mask = game.physics.collision_mask(&"zombie")

	_register_combat(npc)
	zombie_spawned.emit(npc)


func _on_removed(npc: DotNpcInstance, _reason: StringName) -> void:
	zombie_removed.emit(npc)
	_forget_combat(npc)


func _on_died(npc: DotNpcInstance, by: StringName) -> void:
	var health: DotHealth = npc.node.get_node_or_null(^"Health") if npc.node != null else null
	var fatal: DotDamage = health.last_fatal if health != null else null
	var b := npc.node as ZzZombieBody

	if b != null:
		b.death = decide_death(npc, fatal)
	zombie_died.emit(npc, by, fatal)


## How [param npc] falls, from the hit that killed it: a headshot or a heavy weapon may throw it,
## anything else drops it. Seeded from the zombie and the tick, never `randf()`, so a test can
## say what it will be.
func decide_death(npc: DotNpcInstance, fatal: DotDamage) -> DotPlayerDeath:
	var weapon: Object = null
	var direction := Vector3.ZERO
	var headshot := false
	var amount := 0.0

	if fatal != null:
		weapon = ZzWeapons.def_of(fatal.weapon_id) if fatal.weapon_id != &"" else null
		direction = fatal.direction
		headshot = fatal.is_headshot()
		amount = fatal.amount

	var tick: int = game.current_tick() if game != null else 0
	return DotPlayerDeath.decide(death_reactions, headshot, amount, direction,
		DotPlayerDeath.seed_of(npc.seed, tick), weapon)


## dot-combat decided a death; dot-npc has to be told, so the brain hears it and the budget
## comes back.
func _on_entity_killed(entity_id: int, damage: DotDamage) -> void:
	if not is_npc_entity(entity_id):
		return

	var npc: DotNpcInstance = _by_entity.get(entity_id)

	if npc == null:
		return

	var _reported := spawner.report_death(npc.instance_id, game.key_for_entity(damage.attacker))


## A zombie was hurt: its brain hears who did it, its mirror of its health follows, and a
## heavy enough hit at close range staggers it.
func _on_damage_applied(damage: DotDamage) -> void:
	if not is_npc_entity(damage.victim) or damage.health_lost <= 0.0:
		return

	var npc: DotNpcInstance = _by_entity.get(damage.victim)

	if npc == null or not npc.is_alive():
		return

	var health: DotHealth = npc.node.get_node_or_null(^"Health")
	if health != null:
		npc.health = health.health
		if npc.node is ZzZombieBody:
			(npc.node as ZzZombieBody).health = health.health

	var by: StringName = game.key_for_entity(damage.attacker)
	npc.engaged_at = spawner.now()

	if npc.brain != null:
		(npc.brain as DotNpcBrain).damaged(damage.health_lost, by)

	# A weapon that says it burns (zed-dot-weapons' flamethrower) sets what it hits alight.
	if damage.weapon_id != &"" and game.hazards != null:
		var def := ZzWeapons.def_of(damage.weapon_id)
		if def != null and def.tags.has(&"incendiary"):
			game.hazards.ignite(npc)

	if npc.def.id == ZzNpcs.COMMON and damage.amount >= 24.0 and damage.distance < 5.0 \
			and npc.brain != null and npc.brain.has_method(&"stagger"):
		npc.brain.call(&"stagger", damage.direction, 0.35, 3.0)


# --- Admin and reporting ------------------------------------------------------------------------

func count() -> int:
	return spawner.world_count() if spawner != null else 0


func commons() -> int:
	return spawner.count_of(ZzNpcs.COMMON) if spawner != null else 0


func describe() -> Dictionary:
	return {
		"zombies": count(),
		"commons": commons(),
		"specials": specials_alive() if spawner != null else 0,
		"pacing": pacing,
		"director": director.phase_name() if director != null else "-",
		"next mob": "%.0f s" % maxf(_next_mob - _time, 0.0) if pacing else "-",
		"panic": "%.0f s" % (_panic_until - _time) if panicking() else "-",
		"nav": "%d points" % nav.point_count() if nav != null else "-",
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var facts := describe()

	for key: String in facts:
		out.append("  %-10s %s" % [key, facts[key]])

	return out
