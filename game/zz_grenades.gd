extends RefCounted

const CHANNEL := "zz.grenades"
const ZzHazards := preload("zz_hazards.gd")
const ZzNpcs := preload("zz_npcs.gd")
const ZzPaths := preload("zz_paths.gd")

## Thrown grenades of arena-weapons (frag, sticky, flash, smoke, incendiary), flown and blown on the server.
## The pack is optional and reached by path; its events become damage, a fire area, a lure and a replicated cloud or flash.

const DIR := "res://addons/arena_weapons/"
const FLASH := &"flash"
const SMOKE := &"smoke"

var game = null
var rules: Object = null

var _grenade: GDScript = null
## arena-weapons' AwUtilityZones (API 4): victims, line of sight, blind ledger and fire pulses as the thrower.
var zones: Object = null
## id -> {g, def}
var _flying: Dictionary = {}
var _loaded := false
## `{at, reach, until}` of each going-off grenade and burning fire: who [member zones] may hurt or blind.
var _spots: Array[Dictionary] = []
## hazard area id -> dot-npc sight blocker id, for the smoke clouds up
var _blockers: Dictionary = {}


func _init(p_game: Object) -> void:
	game = p_game


## True when the pack is mounted and the weapon [param def] is one of its grenades.
func handles(def: DotWeaponDef) -> bool:
	if def == null or not def.params.has(&"kind") or not _load():
		return false

	return true


func _load() -> bool:
	if _loaded:
		return _grenade != null

	_loaded = true
	var paths := ["aw_grenade.gd", "aw_utility_zones.gd", "aw_grenade_rules.gd"]

	for file: String in paths:
		if _path(file).is_empty():
			return false

	_grenade = load(_path(paths[0]))
	var zones_script: GDScript = load(_path(paths[1]))
	rules = (load(_path(paths[2])) as GDScript).new()

	if _grenade == null or zones_script == null:
		return false

	zones = zones_script.new()
	zones.set(&"rules", rules)
	zones.set(&"victims", _victims_at_large)
	zones.set(&"los", zones_script.call(&"los_from_ray", _blocked))
	zones.set(&"damage", _damage)
	# The blast's own damage goes through the same callable, so a frag, a fire pulse and a flash's victims share one rule.
	zones.set(&"apply_blast_damage", true)
	return true


## The host's copy of an arena-weapons file first: loading a bundled copy of a class the host already declares errors "hides a global script class".
func _path(file: String) -> String:
	for path: String in [DIR + file, ZzPaths.rebase(DIR + file)]:
		if ResourceLoader.exists(path):
			return path

	return ""


## Registers the `sv_grenade_*` cvars ([param add] is the module's `add_cvar`).
func bind_cvars(add: Callable, flags: int = 0) -> void:
	if _load():
		var _bound: Variant = rules.call(&"bind_cvars", add, flags)


func count() -> int:
	return _flying.size()


## Takes a thrown spawn: flies it from the next tick, and tells clients to draw the arc.
func throw(player: Object, spawn: DotWeaponSpawn, def: DotWeaponDef) -> void:
	var g: Object = _grenade.call(&"from_spawn", spawn, def, rules)
	# The clients draw the arc under the hazards' gravity, so the server flies it under the same.
	g.set(&"gravity", ZzHazards.GRAVITY * spawn.gravity_scale)
	g.set(&"owner_entity", player.entity_id)
	var id: int = game.hazards._take_id()
	_flying[id] = {"g": g, "def": def}
	game.hazards.launched.emit(id, ZzHazards.GRENADE, spawn.origin, spawn.velocity)


func tick() -> void:
	var now: float = game.now()
	_spots = _spots.filter(func(spot: Dictionary) -> bool: return float(spot["until"]) > now)

	if zones != null:
		zones.call(&"tick", 1.0 / float(maxi(game.tick_rate, 1)))

	for id: int in _flying.keys():
		var entry: Dictionary = _flying[id]
		var g: Object = entry["g"]

		if bool(g.call(&"step", _trace, maxi(game.tick_rate, 1))):
			_flying.erase(id)
			_go_off(id, g, entry["def"])


func clear() -> void:
	_flying.clear()
	_blockers.clear()
	_spots.clear()

	if zones != null:
		zones.call(&"clear")


## True when dot-npc has the blind and sight-blocker hooks (API 6).
func has_senses() -> bool:
	return DotAddonApi.build_level("dot_npc") >= 6 and game.horde != null and game.horde.senses != null


## `{position, normal}` of the first world hit on the segment, or empty.
func _trace(from: Vector3, to: Vector3) -> Dictionary:
	var world: World3D = game.get_world_3d()

	if world == null:
		return {}

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = game.world_mask()
	var hit := world.direct_space_state.intersect_ray(query)
	return {} if hit.is_empty() else {"position": hit["position"], "normal": hit["normal"]}


## World geometry only, as AwUtilityZones.los_from_ray wants it: true when the ray hits.
func _blocked(from: Vector3, direction: Vector3, dist: float) -> bool:
	return game.ray_hit(from, from + direction * dist) != Vector3.INF


func _go_off(id: int, g: Object, def: DotWeaponDef) -> void:
	var at: Vector3 = g.get(&"position") + Vector3(0.0, 0.1, 0.0)
	g.set(&"position", at)
	var b := def.tuning as DotWeaponBallistics
	var reach := maxf(float(def.params.get(&"effect_radius", 0.0)), b.splash_radius if b != null else 0.0)
	_spots.append({"at": at, "reach": reach, "until": game.now()})
	var events: Array = zones.call(&"detonate", g, def)
	game.hazards.landed.emit(id, SMOKE, at)

	var blinded := 0.0

	for e: Dictionary in events:
		_apply(e, g)

		if String(e["event"]) == "blind" and DotEntity.is_kind(int(e["victim"]), DotEntity.KIND_NPC):
			blinded = maxf(blinded, _blind_left(int(e["victim"])))

	# One lure for the whole flash: the commons it blinded go to the bang, not at the survivors.
	if blinded > 0.0 and game.horde != null:
		game.horde.lure(at, blinded, reach)


## Every survivor and zombie near a going-off grenade or a fire still burning, as AwUtilityZones wants them.
func _victims_at_large() -> Array:
	var out: Array = []
	var seen := {}

	for spot: Dictionary in _spots:
		for v: Dictionary in _victims(spot["at"], float(spot["reach"])):
			if not seen.has(v["id"]):
				seen[v["id"]] = true
				out.append(v)

	return out


func _victims(at: Vector3, reach: float) -> Array:
	var out: Array = []

	for player: Object in game.survivors_within(at, reach, reach):
		out.append({"id": player.entity_id, "position": player.feet(), "eye": player.eye_position(), "forward": player.aim_direction()})

	if game.horde != null:
		for npc in game.horde.spawner.npcs_near(at, reach):
			var entity: int = game.horde.entity_id_for(npc)

			if entity == 0:
				continue

			var forward := Vector3.FORWARD
			if npc.node is Node3D:
				forward = -(npc.node as Node3D).global_transform.basis.z

			var feet: Vector3 = npc.position()
			out.append({"id": entity, "position": feet, "eye": feet + Vector3(0.0, 1.5, 0.0), "forward": forward})

	return out


func _apply(e: Dictionary, g: Object) -> void:
	var owner: int = g.get(&"owner_entity")

	match String(e["event"]):
		"detonated":
			if StringName(e["kind"]) == &"frag":
				_bang(e["position"], float(e["radius"]), owner)
			elif StringName(e["kind"]) == FLASH:
				var _f: int = game.hazards.add(FLASH, e["position"], float(e["radius"]), 0.5, 0.0, owner)
		"blind":
			_blind(int(e["victim"]), g.get(&"position"))
		"smoke":
			var area: int = game.hazards.add(SMOKE, e["position"], float(e["radius"]), float(e["seconds"]), 0.0, owner)
			_block_sight(area, e["position"], float(e["radius"]), float(e["seconds"]))
		"fire":
			# The zone hurts, as the thrower; this area is what clients draw and what sets zombies alight.
			var seconds := float(e["seconds"])
			var _i: int = game.hazards.add(ZzHazards.FIRE, e["position"], float(e["radius"]), seconds, 0.0, owner)
			_spots.append({"at": e["position"], "reach": float(e["radius"]) + 2.0, "until": game.now() + seconds})


## The shared part of a bang: clients draw it, toys and the crowd feel it.
func _bang(at: Vector3, radius: float, _owner: int) -> void:
	game.exploded.emit(at, radius, ZzHazards.GRENADE)

	if game.horde != null:
		game.horde.blast(at, radius * 1.2)
		game.horde.sounds.emit(DotNpcAiSounds.Kind.COMBAT, at, 50.0, game.horde.now(), 0.5)


## Through combat.apply_damage, so friendly fire, armour and the difficulty are the rules every other hit follows.
func _damage(attacker: int, victim: int, amount: float, type: Variant, weapon: StringName) -> void:
	var kind: Variant = game.combat.damage_type(type as StringName) if type is StringName else type
	var hit := DotDamage.make(attacker, victim, amount, kind)
	hit.tick = game.current_tick()
	hit.weapon_id = weapon if weapon != &"" else &"fire"

	if game.player_for_entity(victim) != null:
		hit.context = {"why": game.BY_HAZARD}

	var _applied: Variant = game.combat.apply_damage(hit)


## A smoke cloud stops zombies seeing through it (hearing passes) until it ends.
func _block_sight(area: int, at: Vector3, radius: float, seconds: float) -> void:
	if not has_senses():
		return

	if not game.hazards.area_ended.is_connected(_on_area_ended):
		game.hazards.area_ended.connect(_on_area_ended)

	_blockers[area] = game.horde.senses.add_sight_blocker(at + Vector3(0.0, 1.6, 0.0), radius, seconds)


func _on_area_ended(area: int) -> void:
	if _blockers.has(area):
		if game.horde != null and game.horde.senses != null:
			game.horde.senses.remove_sight_blocker(int(_blockers[area]))

		_blockers.erase(area)


## Seconds the ledger still holds [param victim] blind: a second flash extends, none passes the cap.
func _blind_left(victim: int) -> float:
	return float(zones.get(&"ledger").call(&"remaining", victim))


## A blinded survivor's screen goes white; a blinded zombie is blind to sight and shoved off.
func _blind(victim: int, at: Vector3) -> void:
	var seconds := _blind_left(victim)
	var player: Object = game.player_for_entity(victim)

	if player != null:
		player.flash_until = maxf(player.flash_until, game.now() + seconds)
		player.flash_strength = float(zones.get(&"ledger").call(&"strength", victim))
		return

	if game.horde == null or not DotEntity.is_kind(victim, DotEntity.KIND_NPC):
		return

	var npc: DotNpcInstance = game.horde.npc_for_entity(victim)

	if npc != null and has_senses():
		npc.blind_for(game.horde.now(), seconds)

	if npc != null and npc.is_alive() and npc.brain != null and npc.brain.has_method(&"stagger"):
		var away: Vector3 = npc.position() - at
		away.y = 0.0
		npc.brain.call(&"stagger", away.normalized(), minf(seconds, 2.0), 3.0)
