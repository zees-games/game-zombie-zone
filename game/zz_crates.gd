extends RefCounted

const ZzConfig := preload("zz_config.gd")

## Ammo piles and boxes lying on the ground as real rigid bodies (dot-props' `crate` toy, in a
## [DotPropToyBox] of their own so the map's toys keep their wire indexes): pushed by survivors and
## zombies, shot, thrown by a blast. The server simulates; a client is sent where the awake ones
## are, a few times a second ([signal moved_many]), and the loot entry's place follows the body,
## so use, buy and a stand-in's pick-up find a moved crate where it lies.

const CHANNEL := "zz.crates"
const TOY := &"crate"

## Fastest a crate sinks or climbs while it counts as "moved" for the wire, metres.
const MOVE_EPSILON := 0.01

## A batch of `[id, at, basis]` for the crates that moved since the last one.
signal moved_many(batch: Array)

var game = null

var _box: DotPropToyBox = null
var _toys: Dictionary = {}
var _sent: Dictionary = {}
var _since_sync: float = 0.0


func _init(p_game: Object) -> void:
	game = p_game
	var loot = game.loot
	var _a: int = loot.added.connect(_on_added)
	var _r: int = loot.removed.connect(_on_removed)


func enabled() -> bool:
	return game.config.physics_crates and game.authoritative


## How many crates are simulating now.
func active() -> int:
	return _box.awake_count() if _ready() else 0


func count() -> int:
	return _toys.size()


func toy_of(id: int) -> DotPropToy:
	return _toys.get(id)


## The loot id a toy stands for, or -1.
func id_of(toy: DotPropToy) -> int:
	for id: int in _toys:
		if _toys[id] == toy:
			return id
	return -1


func _ready() -> bool:
	return _box != null and is_instance_valid(_box) and _box.is_inside_tree()


func _kinds() -> PackedStringArray:
	return String(game.config.crate_kinds).split(",", false)


## The box, on the current map; rebuilt when the map was.
func _ensure() -> bool:
	if _ready():
		return true
	if game.map == null or not game.map.is_inside_tree():
		return false
	_toys.clear()
	_sent.clear()
	_box = DotPropToyBox.new()
	_box.name = "Crates"
	_box.authoritative = true
	_box.draw = false
	_box.rules = DotPropToyRules.new()
	_box.gravity = game.config.gravity
	_box.kill_y = game.map.kill_height()
	var physics = game.physics
	if physics != null:
		_box.loose_layer = physics.layer_mask(&"toy")
		_box.loose_mask = physics.collision_mask(&"toy")
		_box.solid_layer = physics.layer_mask(&"prop")
		_box.solid_mask = physics.collision_mask(&"prop")
		_box.aim_mask = physics.layer_mask(&"world") | physics.layer_mask(&"prop") | physics.layer_mask(&"toy") | physics.layer_mask(&"barricade")
	game.map.add_child(_box)
	var built := _box.build([])
	if not built.ok:
		DotLog.warn(CHANNEL, "the crate box would not build", {"why": built.error.message})
		return false
	return true


func _apply_rules() -> void:
	var cfg: ZzConfig = game.config
	_box.rules.enabled = cfg.physics_crates
	_box.rules.max_awake = clampi(cfg.crate_max_active, 1, 256)
	_box.rules.push_scale = cfg.crate_push
	_box.sleep_after = cfg.crate_sleep_seconds


func _on_added(id: int, kind: StringName, _item: StringName, at: Vector3) -> void:
	if not enabled() or not _kinds().has(String(kind)) or _toys.size() >= game.config.crate_max_bodies or not _ensure():
		return
	_apply_rules()
	var def: Dictionary = _box.catalogue.get_def(TOY).duplicate(true)
	def["mass"] = maxf(game.config.crate_mass, 0.25)
	# The size the client draws that kind at (ZzWorldView.add_loot).
	def["size"] = Vector3(0.73, 0.44, 0.3) if kind == &"ammo" else Vector3(0.55, 0.45, 0.55)
	var toy := _box.add_toy(TOY, at, 0.0, def)
	if toy != null:
		_toys[id] = toy
		_sent[id] = true


func _on_removed(id: int, _by: StringName) -> void:
	var toy: Variant = _toys.get(id)
	_toys.erase(id)
	_sent.erase(id)
	# A map change frees the box and its toys before the loot is cleared.
	if is_instance_valid(toy) and _ready():
		_box.remove_toy(toy as DotPropToy)


## One server tick: survivors and zombies push, the box steps, the loot follows the bodies, and the
## moved ones go out at `crate_sync_hz`.
func tick(delta: float) -> void:
	if _toys.is_empty() or not _ready():
		return
	_apply_rules()
	if not _box.rules.enabled:
		return
	_push_survivors()
	if game.config.crate_zombie_push and game.horde != null and game.horde.spawner != null:
		_push_zombies()
	_box.advance(delta)

	var loot = game.loot
	for id: int in _toys.keys():
		var toy: DotPropToy = _toys[id]
		if not is_instance_valid(toy) or toy.body == null or not loot.exists(id):
			continue
		var at := toy.body.global_position - Vector3(0.0, float(toy.def["size"].y) * 0.5, 0.0)
		var e: Dictionary = loot.entries[id]
		# A resting crate sends nothing; a turning one does, though it has not changed place.
		if (e["at"] as Vector3).distance_to(at) > MOVE_EPSILON or not _sent.has(id) or toy.body.angular_velocity.length_squared() > 0.01:
			e["at"] = at
			_pending[id] = true
	_since_sync += delta
	if not _pending.is_empty() and _since_sync >= 1.0 / maxf(game.config.crate_sync_hz, 1.0):
		_since_sync = 0.0
		_flush()


var _pending: Dictionary = {}


func _flush() -> void:
	var batch: Array = []
	for id: int in _pending.keys():
		var toy: DotPropToy = _toys.get(id)
		if toy == null or not is_instance_valid(toy) or toy.body == null:
			continue
		var at: Vector3 = game.loot.entries[id]["at"] if game.loot.exists(id) else toy.body.global_position
		batch.append([id, at, toy.body.global_basis.get_rotation_quaternion()])
		_sent[id] = true
	_pending.clear()
	if not batch.is_empty():
		moved_many.emit(batch)


func _push_survivors() -> void:
	for pid: StringName in game.players:
		var player = game.players[pid]
		if not player.is_alive() or player.watching:
			continue
		var state = player.controller.state
		var tunables = player.controller.tunables
		var radius: float = tunables.radius if tunables != null else 0.35
		var height: float = lerpf(tunables.stand_height, tunables.crouch_height, state.crouch_fraction) if tunables != null else 1.8
		var _n := _box.push_from(state.position, state.velocity, radius, height)


func _push_zombies() -> void:
	for npc in game.horde.spawner.all_npcs():
		if not npc.is_alive():
			continue
		var v = npc.node.get(&"velocity")
		if not (v is Vector3) or (v as Vector3).length_squared() < 0.04:
			continue
		var _n := _box.push_from(npc.position(), v, 0.34, 1.7)


## A survivor's shot along [param direction] from [param origin]; the first crate on it is pushed.
func shoot(origin: Vector3, direction: Vector3, reach: float, damage: float) -> int:
	if _toys.is_empty() or not _ready() or not _box.rules.enabled:
		return -1
	return _box.shot_along(origin, direction, reach, damage, game.world_mask())


## A blast at [param at]: every crate within [param radius] is thrown away from it.
func blast(at: Vector3, radius: float, speed: float) -> int:
	if _toys.is_empty() or not _ready() or not _box.rules.enabled:
		return 0
	return _box.blast(at, radius, speed * game.config.crate_blast)


func describe() -> Dictionary:
	return {"crates": _toys.size(), "active": active(), "on": enabled()}
