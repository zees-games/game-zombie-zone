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
var _blast: GDScript = null
## id -> {g, def}
var _flying: Dictionary = {}
var _loaded := false


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
	var paths := ["aw_grenade.gd", "aw_grenade_blast.gd", "aw_grenade_rules.gd"]

	for file: String in paths:
		if not ResourceLoader.exists(ZzPaths.rebase(DIR + file)):
			return false

	_grenade = load(ZzPaths.rebase(DIR + paths[0]))
	_blast = load(ZzPaths.rebase(DIR + paths[1]))
	rules = (load(ZzPaths.rebase(DIR + paths[2])) as GDScript).new()
	return _grenade != null and _blast != null


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
	for id: int in _flying.keys():
		var entry: Dictionary = _flying[id]
		var g: Object = entry["g"]

		if bool(g.call(&"step", _trace, maxi(game.tick_rate, 1))):
			_flying.erase(id)
			_go_off(id, g, entry["def"])


func clear() -> void:
	_flying.clear()


## `{position, normal}` of the first world hit on the segment, or empty.
func _trace(from: Vector3, to: Vector3) -> Dictionary:
	var world: World3D = game.get_world_3d()

	if world == null:
		return {}

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = game.world_mask()
	var hit := world.direct_space_state.intersect_ray(query)
	return {} if hit.is_empty() else {"position": hit["position"], "normal": hit["normal"]}


func _clear_air(from: Vector3, to: Vector3) -> bool:
	return game.ray_hit(from, to) == Vector3.INF


func _go_off(id: int, g: Object, def: DotWeaponDef) -> void:
	var at: Vector3 = g.get(&"position") + Vector3(0.0, 0.1, 0.0)
	g.set(&"position", at)
	var b := def.tuning as DotWeaponBallistics
	var reach := maxf(float(def.params.get(&"effect_radius", 0.0)), b.splash_radius if b != null else 0.0)
	var events: Array = _blast.call(&"detonate", g, def, _victims(at, reach), _clear_air)
	game.hazards.landed.emit(id, SMOKE, at)

	var blinded := 0.0

	for e: Dictionary in events:
		_apply(e, g, def)

		if String(e["event"]) == "blind" and DotEntity.is_kind(int(e["victim"]), DotEntity.KIND_NPC):
			blinded = maxf(blinded, float(e["seconds"]))

	# One lure for the whole flash: the commons it blinded go to the bang, not at the survivors.
	if blinded > 0.0 and game.horde != null:
		game.horde.lure(at, blinded, reach)


## Every survivor and zombie in reach, as the blast wants them.
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


func _apply(e: Dictionary, g: Object, def: DotWeaponDef) -> void:
	var owner: int = g.get(&"owner_entity")

	match String(e["event"]):
		"detonated":
			if StringName(e["kind"]) == &"frag":
				_bang(e["position"], float(e["radius"]), owner)
			elif StringName(e["kind"]) == FLASH:
				var _f: int = game.hazards.add(FLASH, e["position"], float(e["radius"]), 0.5, 0.0, owner)
		"damage":
			_damage(int(e["victim"]), float(e["damage"]), e["type"], owner, def.id)
		"blind":
			_blind(int(e["victim"]), float(e["seconds"]), g.get(&"position"))
		"smoke":
			var _s: int = game.hazards.add(SMOKE, e["position"], float(e["radius"]), float(e["seconds"]), 0.0, owner)
		"fire":
			var _i: int = game.hazards.add(ZzHazards.FIRE, e["position"], float(e["radius"]), float(e["seconds"]), float(e["dps"]), owner)


## The shared part of a bang: clients draw it, toys and the crowd feel it.
func _bang(at: Vector3, radius: float, _owner: int) -> void:
	game.exploded.emit(at, radius, ZzHazards.GRENADE)

	if game.horde != null:
		game.horde.blast(at, radius * 1.2)
		game.horde.sounds.emit(DotNpcAiSounds.Kind.COMBAT, at, 50.0, game.horde.now(), 0.5)


func _damage(victim: int, amount: float, type: Variant, owner: int, weapon: StringName) -> void:
	var hit := DotDamage.make(owner, victim, amount, type)
	hit.tick = game.current_tick()
	hit.weapon_id = weapon

	if game.player_for_entity(victim) != null:
		hit.context = {"why": game.BY_HAZARD}

	var _applied: Variant = game.combat.apply_damage(hit)


## A blinded zombie is shoved off. No sense is switched off (dot-npc has no blind hook), so
## it keeps hunting once up; the flash's lure (see [method _go_off]) is what distracts the commons.
func _blind(victim: int, seconds: float, at: Vector3) -> void:
	if game.horde == null or not DotEntity.is_kind(victim, DotEntity.KIND_NPC):
		return

	var npc: DotNpcInstance = game.horde.npc_for_entity(victim)

	if npc != null and npc.is_alive() and npc.brain != null and npc.brain.has_method(&"stagger"):
		var away: Vector3 = npc.position() - at
		away.y = 0.0
		npc.brain.call(&"stagger", away.normalized(), minf(seconds, 2.0), 3.0)
