extends Node3D

## A converted map's lifts, doors, buttons and triggers, run from the world pack's manifest
## (dot-map's mover, volume and link records).
##
## The server owns every state change; a state is `(start tick, fraction then, direction)` and
## the pose at any tick follows from it, so a client told a state predicts the same pose as the
## server does and a rider is carried the same way. The mesh is drawn only: each solid mover
## gets a StaticBody3D here that is posed per tick and travels with its geometry.

const CHANNEL := "zz.mechanics"

## Kinds that move and collide (the others are read for their outputs only).
const SOLID_KINDS := ["slide", "rotate", "plat", "path"]
const BUTTON_KINDS := ["button", "rotate_button"]
## A brush door's classes: what a global pack's mover list holds that opens to whoever walks up, with no switch run.
const DOOR_CLASSES := ["func_door", "func_door_rotating", "func_movelinear"]
const MIN_TRAVEL := 0.05
const DEFAULT_PATH_SPEED := 2.0
## How long a door that stays open waits for nobody to be near before it closes.
const STAY_OPEN_SECONDS := 2.0
const NEAR_EVERY := 4
const VOLUME_EVERY := 2
const PRESS_PAD := 0.3
const DOOR_PAD := 1.5
const MAX_FIRES := 256
## Volumes the server runs through dot-map's DotMapVolumes; push and gravity are also read by prediction.
const VOLUME_KINDS := ["hurt", "push", "teleport", "gravity"]
const PREDICTED_KINDS := ["push", "gravity"]
## How far past a volume's brushes a body is still handed to it (its column and a margin).
const BODY_PAD := 1.0
const GameText := preload("zz_game_text.gd")
const EntityMaker := preload("zz_entity_maker.gd")
const NpcMaker := preload("zz_npc_maker.gd")
const MapCommands := preload("zz_map_commands.gd")
const LogicWaves := preload("zz_logic_waves.gd")
const LogicWinLose := preload("zz_logic_winlose.gd")
const LogicBeats := preload("zz_logic_beats.gd")
const LogicGameRules := preload("zz_logic_gamerules.gd")
## A template copy of these brush classes is solid where it stands (the others are drawn only).
const COPY_SOLID := ["func_breakable", "func_brush", "func_wall", "func_physbox", "func_physbox_multiplayer", "func_door"]
## Longest gap of ticks the map's logic is stepped through in one go.
const MAX_LOGIC_STEP := 4096

## A mover changed state (it was told, or it settled); the bridge broadcasts this index.
signal state_changed(index: int)
## The map's own logic asked the game for something: `hud_text`, `say`, `cvar`, `npc_spawn`, `maker_spawn`, `template_spawn`, `damage_force`.
signal logic_event(kind: String, data: Dictionary)
## A brush a point_template made (or killed): `(id, model, offset in metres from where the model stands, alive)`; the bridge tells clients.
signal copy_changed(id: int, model: int, offset: Vector3, alive: bool)

var tick_rate: int = 64
var authoritative: bool = true
## Whether a box (world metres) has a survivor or a zombie in it.
var occupants_fn: Callable = Callable()
## The living survivors' body points.
var points_fn: Callable = Callable()
## Where whoever is in a box (survivor or zombie) stands, nearest its centre, or null: which way a door swings away from.
var opener_fn: Callable = Callable()
## Server: where the entities' source document is (`<prefix>.doc.json`), for their keys and filters.
var source_doc_path: String = ""
## Server: every body a volume may touch, as `{id, body, position (feet), height, kind, name, class, team}`.
var bodies_fn: Callable = Callable()
## Server: `(body, amount, kind, entity_index)` for a hurt volume's hit.
var damage_fn: Callable = Callable()
## Server: `(body, Transform3D)` for a teleport and `(body, Vector3 m/s)` for a push; a player's push is predicted instead.
var move_fn: Callable = Callable()

var _ents: Variant = null
var _movers: Array[Dictionary] = []
var _volumes: Array[Dictionary] = []
var _toggles: Array[Dictionary] = []
var _toggle_base: int = 0
var _predicted: Array[Dictionary] = []
var _vol_io: DotMapIO = null
## Every entity of the map as a dot-map runtime, which owns the links: the lifts, buttons and volumes below are its targets.
var _logic: DotMapIO = null
var _logic_base: int = 0
var _logic_synced: bool = false
var _logic_busy: int = 0
var _source: Array = []
var _source_read: bool = false
var _manifest: Dictionary = {}
var _vols: DotMapVolumes = null
var _generic: Dictionary = {}
var _by_entity: Dictionary = {}
var _by_body: Dictionary = {}
var _told: Dictionary = {}
var _started: bool = false
var _posed_tick: int = -2147483648
var _unsupported_seen: Dictionary = {}
## Who pressed the input being run (a survivor's eye), for a door's side.
var _activator: Variant = null
## Built with doors_only: the logic runs, but never drives a door the document's gates stand in for.
var _doors_only: bool = false
var _world: RefCounted = null
var _put_on: Callable = Callable()
## model number to the drawn node of that model, once the map is drawn.
var _model_nodes: Dictionary = {}
## Template copies by entity index: `{model, offset, node, body}`.
var _copies: Dictionary = {}
var _last_tick: int = 0


## Builds from [param world] (a DotMapBspMesh). [param put_on] is called with each body to give
## it the world's physics layer.
## [param doors_only] builds the doors a world from the global converter carries (the hinged prop doors and the
## brush doors with hulls; a boxed gate has none, so nothing collides twice), each open to anyone near it, and
## its triggers, hurts and relays, whose outputs never drive those doors.
func build(world: RefCounted, put_on: Callable, doors_only: bool = false) -> void:
	_ents = world.call(&"entities")
	_doors_only = doors_only
	_world = world
	_put_on = put_on
	var early: Variant = world.get("manifest")
	_manifest = early if early is Dictionary else {}
	var template_sources := template_models()
	var models := {}
	for model: int in world.call(&"models"):
		models[model] = true

	for mv: Variant in _ents.movers:
		if mv.model < 0 and str(mv.classname).to_lower() == "prop_door_rotating":
			_build_door(mv, put_on, doors_only)
			continue
		if mv.model < 0 or not models.has(mv.model):
			continue
		var shapes: Array = world.call(&"hull_shapes", mv.model)
		if doors_only and (shapes.is_empty() or not _is_brush_door(mv)):
			continue
		var m := _make_mover(mv, world)
		if doors_only:
			m["locked"] = false
			m["initial_locked"] = false
			m["auto"] = true
		m["idx"] = _movers.size()
		_movers.append(m)
		_by_entity[mv.entity] = {"type": &"mover", "i": m["idx"]}

		if SOLID_KINDS.has(mv.kind) and not template_sources.has(int(mv.model)):
			if not shapes.is_empty():
				var body := StaticBody3D.new()
				body.name = "Mover%d" % m["idx"]
				for s: Dictionary in shapes:
					var cs := CollisionShape3D.new()
					cs.shape = s["shape"]
					body.add_child(cs)
				add_child(body)
				if put_on.is_valid():
					put_on.call(body)
				m["body"] = body
				_by_body[body.get_instance_id()] = m["idx"]
				_place(body, _transform_of(m, float(m["from"])))

	_build_toggles(world)

	for vol: Variant in _ents.volumes:
		var v := {"vol": vol, "entity": vol.entity, "inside": false, "ready": 0, "enabled": not vol.disabled}
		if vol.kind == "multiple" or vol.kind == "once":
			_by_entity[vol.entity] = {"type": &"volume", "i": _volumes.size()}
			_volumes.append(v)
		elif not VOLUME_KINDS.has(vol.kind):
			_note_unsupported("volume " + vol.kind)

	for g: Dictionary in _ents.generic:
		_generic[int(g["entity"])] = {"rec": g}

	var manifest: Variant = world.get("manifest")
	_manifest = manifest if manifest is Dictionary else {}
	if authoritative:
		_build_logic()


static func _is_brush_door(mv: Variant) -> bool:
	return DOOR_CLASSES.has(str(mv.classname).to_lower()) and (mv.kind == "slide" or mv.kind == "rotate")


## A prop door has no brush: dot-map's DotMapDoorStandIn is its panel and body, hung at the hinge and swung as a whole.
func _build_door(mv: Variant, put_on: Callable, free_for_all: bool) -> void:
	var yaw: float = mv.panel_yaw if not is_nan(mv.panel_yaw) else mv.yaw
	var node: Node3D = DotMapDoorStandIn.build(mv, yaw, DotMapDoorStandIn.SIZE, 1)
	add_child(node)
	var body := node.get_node_or_null("col_solid") as CollisionObject3D
	if body != null and put_on.is_valid():
		put_on.call(body)
	var m := _make_mover(mv, null)
	m["idx"] = _movers.size()
	m["node"] = node
	m["door"] = true
	m["base"] = node.transform
	m["side"] = _rest_side(mv)
	m["zone"] = _door_zone(mv, node)
	if free_for_all:
		m["locked"] = false
		m["initial_locked"] = false
		m["auto"] = true
	_movers.append(m)
	_by_entity[mv.entity] = {"type": &"mover", "i": m["idx"]}


## The side a door that starts open stands on, else 1.
static func _rest_side(mv: Variant) -> float:
	if mv.spawn_side != 0.0 and mv.degrees != 0.0:
		return mv.spawn_side * signf(mv.degrees)
	return 1.0


## The door's reach: its swing about the hinge, from a metre under it (a hinge is often set above the floor) to the panel's top.
static func _door_zone(mv: Variant, node: Node3D) -> AABB:
	var width := DotMapDoorStandIn.SIZE.x
	if not is_nan(mv.panel_yaw) and mv.panel_width > 0.1:
		width = mv.panel_width
	return AABB(node.position + Vector3(-width, -1.0, -width), Vector3(width * 2.0, DotMapDoorStandIn.SIZE.y + 1.0, width * 2.0))


## Hands the drawn nodes over (from build_node): each mover's node takes its pose.
func bind_drawn(root: Node3D) -> void:
	for child in root.get_children():
		if not child.has_meta(&"model"):
			continue
		_model_nodes[int(child.get_meta(&"model"))] = child
		for m in _movers:
			if int(m["model"]) == int(child.get_meta(&"model")):
				m["node"] = child
	_posed_tick = -2147483648
	for model in template_models():
		if _model_nodes.has(model):
			(_model_nodes[model] as Node3D).visible = false
	for id: int in _copies:
		_show_copy(_copies[id] as Dictionary)


## Whether the map has volumes or logic entities to run.
func has_logic() -> bool:
	return not _volumes.is_empty() or not _generic.is_empty() or not _toggles.is_empty()


func mover_count() -> int:
	return _movers.size()


## Where the pieces of the moving hulls (boats, trains) lie at rest, for the zombies' graph: walkers climbed
## onto one and stood wedged on it. Doors and lifts are left out, they open or are gated.
func rest_blockers() -> Array[AABB]:
	var found: Array[AABB] = []

	for m in _movers:
		var body: Variant = m.get("body")

		if str(m["kind"]) != "path" or body == null:
			continue

		for c in (body as Node3D).get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
				var box: AABB = (c as CollisionShape3D).shape.get_debug_mesh().get_aabb()
				box.position += (c as Node3D).global_position
				# Down to the ground: a hull that hangs a hand above it is an overhead to the graph, yet a walker wedges under it.
				box.size.y += maxf(box.position.y, 0.0)
				box.position.y = minf(box.position.y, 0.0)
				found.append(box)

	return found


## The mover at [param index] as plain data (for checks and the debug overlay).
func mover(index: int) -> Dictionary:
	return _movers[index]


## Index of the first mover whose targetname is [param name], or -1.
func index_of(name: String) -> int:
	for m in _movers:
		if str(m["name"]).to_lower() == name.to_lower():
			return int(m["idx"])
	return -1


## Index of the mover made from brush-entity [param entity], or -1.
func index_of_entity(entity: int) -> int:
	var found: Variant = _by_entity.get(entity)
	if found == null or str((found as Dictionary)["type"]) != "mover":
		return -1
	return int((found as Dictionary)["i"])


## The mover whose body is [param ground_id], or -1.
func index_of_body(ground_id: int) -> int:
	return int(_by_body.get(ground_id, -1))


## Where mover [param index] is along its travel (0 at rest) at [param tick].
func fraction_at(index: int, tick: int) -> float:
	return _fraction(_movers[index], tick)


## The mover's world transform at [param tick].
func transform_at(index: int, tick: int) -> Transform3D:
	var m: Dictionary = _movers[index]
	return _transform_of(m, _fraction(m, tick))


func _make_mover(mv: Variant, world: RefCounted) -> Dictionary:
	var rec: Dictionary = mv.record
	var zone := AABB(mv.origin - Vector3.ONE * 0.5, Vector3.ONE)
	if rec.get("mins") is Array and rec.get("maxs") is Array:
		var lo := Vector3(rec["mins"][0], rec["mins"][1], rec["mins"][2])
		var hi := Vector3(rec["maxs"][0], rec["maxs"][1], rec["maxs"][2])
		zone = AABB(lo, hi - lo)

	var m := {
		"mv": mv, "entity": mv.entity, "model": mv.model, "kind": mv.kind, "name": mv.targetname,
		"origin": mv.origin, "zone": zone, "body": null, "node": null,
		"from": mv.rest_fraction() if mv.kind != "path" else 0.0, "dir": 0, "start": 0,
		"locked": mv.locked, "initial_locked": mv.locked, "ready": 0, "close_at": -1, "last_near": -1000000,
		"travel": MIN_TRAVEL, "pts": PackedVector3Array(), "len": 0.0, "posed": -1.0,
		"live": false, "auto": false, "wait": mv.wait, "toggle": mv.toggle,
	}
	m["live"] = _ents.links.fired_by(mv.entity).size() > 0

	if mv.kind == "path":
		_read_path(m, mv)
	elif mv.kind == "spin":
		m["travel"] = 1.0
	else:
		m["travel"] = maxf(mv.travel_time, MIN_TRAVEL)

	# A door nothing drives and that opens to a touch or a use opens to whoever walks up.
	var driven: bool = _ents.links.driving(mv.entity).size() > 0
	m["auto"] = (mv.kind == "slide" or mv.kind == "rotate") and (mv.touch or mv.use) and not driven
	return m


## A tracktrain's way: its origin, then each corner. Open is toward the last corner.
func _read_path(m: Dictionary, mv: Variant) -> void:
	var pts := PackedVector3Array()
	var corners: Array = mv.path()
	for c: Dictionary in corners:
		if not c.get("at") is Array:
			continue
		var at: Array = c["at"]
		pts.append(Vector3(at[0], at[1], at[2]))
	if pts.is_empty():
		m["travel"] = MIN_TRAVEL
		return
	if mv.origin.distance_to(pts[0]) > 0.5:
		pts.insert(0, mv.origin)
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var speed: float = mv.speed
	if speed <= 0.0:
		speed = float(mv.record.get("start_speed", 0.0))
	if speed <= 0.0:
		speed = DEFAULT_PATH_SPEED
	m["pts"] = pts
	m["len"] = total
	m["travel"] = maxf(total / speed, MIN_TRAVEL)


func _fraction(m: Dictionary, tick: int) -> float:
	var d := int(m["dir"])
	if d == 0:
		return float(m["from"])
	var span := float(m["travel"]) * float(tick_rate)
	return clampf(float(m["from"]) + float(d) * float(tick - int(m["start"])) / span, 0.0, 1.0)


func _transform_of(m: Dictionary, fraction: float) -> Transform3D:
	var at: Vector3 = m["origin"]
	var kind := str(m["kind"])
	if kind == "path":
		var pts: PackedVector3Array = m["pts"]
		if pts.size() < 2:
			return Transform3D(Basis.IDENTITY, at)
		var along := clampf(fraction, 0.0, 1.0) * float(m["len"])
		var here := pts[pts.size() - 1]
		for i in range(1, pts.size()):
			var seg := pts[i - 1].distance_to(pts[i])
			if along <= seg or i == pts.size() - 1:
				here = pts[i - 1].lerp(pts[i], clampf(along / maxf(seg, 0.0001), 0.0, 1.0))
				break
			along -= seg
		return Transform3D(Basis.IDENTITY, at + here - pts[0])
	if kind == "spin":
		return Transform3D(Basis.IDENTITY, at)
	if m.has("door"):
		var rest: Transform3D = m["base"]
		var turn: Transform3D = (m["mv"] as Variant).transform_at(fraction, float(m["side"]))
		return Transform3D(turn.basis * rest.basis, rest.origin)
	var rel: Transform3D = (m["mv"] as Variant).transform_at(fraction)
	return Transform3D(rel.basis, at + rel.origin)


static func _place(body: Node3D, at: Transform3D) -> void:
	body.transform = at
	if body is CollisionObject3D and body.is_inside_tree():
		PhysicsServer3D.body_set_state((body as CollisionObject3D).get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)


func _pose_mover(m: Dictionary, tick: int) -> void:
	var f := _fraction(m, tick)
	if str(m["kind"]) == "spin":
		var node: Variant = m["node"]
		if node != null and is_instance_valid(node):
			var rate: float = (m["mv"] as Variant).spin_rate()
			(node as Node3D).transform = Transform3D(Basis((m["mv"] as Variant).axis.normalized(), rate * float(tick) / float(tick_rate)), m["origin"])
		return
	if f == float(m["posed"]):
		return
	m["posed"] = f
	var xf := _transform_of(m, f)
	var body: Variant = m["body"]
	if body != null:
		_place(body, xf)
	var node2: Variant = m["node"]
	if node2 != null and is_instance_valid(node2):
		(node2 as Node3D).transform = xf

		if m.has("door"):
			var solid := (node2 as Node3D).get_node_or_null("col_solid") as CollisionObject3D

			if solid != null and solid.is_inside_tree():
				PhysicsServer3D.body_set_state(solid.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, solid.global_transform)


## Poses every body at [param tick], before a motor sweeps against them.
func pose_at(tick: int) -> void:
	if tick == _posed_tick:
		return
	_posed_tick = tick
	for m in _movers:
		if m["body"] != null or m["node"] != null:
			_pose_mover(m, tick)


## What standing on [param ground_id] does to somebody at [param at] over tick [param tick].
func carry(ground_id: int, at: Vector3, tick: int) -> Vector3:
	var i := index_of_body(ground_id)
	if i < 0:
		return Vector3.ZERO
	var m: Dictionary = _movers[i]
	if int(m["dir"]) == 0:
		return Vector3.ZERO
	var now := _transform_of(m, _fraction(m, tick))
	var next := _transform_of(m, _fraction(m, tick + 1))
	return (next * now.affine_inverse()) * at - at


# --- Replication ---------------------------------------------------------------------------

## The state of mover [param index] as `[start tick, fraction in thousandths, direction, locked]`.
func snapshot(index: int) -> Array:
	if index >= _toggle_base and index - _toggle_base < _toggles.size():
		var t: Dictionary = _toggles[index - _toggle_base]
		return [int(t.get("packed", 0)), 0, 0, 0 if bool(t["enabled"]) else 1, 1]
	var m: Dictionary = _movers[index]
	return [int(m["start"]), roundi(float(m["from"]) * 1000.0), int(m["dir"]), 1 if bool(m["locked"]) else 0,
			1 if float(m.get("side", 1.0)) > 0.0 else 0]


## Mover indices that have left their rest state, for somebody who joins late.
func told_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in _told:
		out.append(int(i))
	out.sort()
	return out


## Takes a state the server sent.
func apply_state(index: int, start: int, from_thousandths: int, dir: int, locked: bool, side: float = 1.0) -> void:
	if index >= _toggle_base and index < _toggle_base + _toggles.size():
		var t: Dictionary = _toggles[index - _toggle_base]
		t["enabled"] = not locked
		if start != 0 and str(t["kind"]) == "push":
			t["packed"] = start
			t["push"] = unpack_push(start)
		_told[index] = true
		return
	if index < 0 or index >= _movers.size():
		return
	var m: Dictionary = _movers[index]
	m["start"] = start
	m["from"] = float(from_thousandths) / 1000.0
	m["dir"] = clampi(dir, -1, 1)
	m["locked"] = locked
	if m.has("door"):
		m["side"] = side
	m["posed"] = -1.0
	_posed_tick = -2147483648
	_told[index] = true


# --- Server side ---------------------------------------------------------------------------

## Everything back to the round's start. Clients are told each mover that had moved.
func reset(tick: int) -> void:
	if authoritative:
		_build_logic()
	var touched := told_indices()
	_told.clear()
	for m in _movers:
		m["from"] = (m["mv"] as Variant).rest_fraction() if str(m["kind"]) != "path" else 0.0
		if m.has("door"):
			m["side"] = _rest_side(m["mv"])
		m["dir"] = 0
		m["start"] = tick
		m["locked"] = m["initial_locked"]
		m["ready"] = 0
		m["close_at"] = -1
		m["posed"] = -1.0
	for t in _toggles:
		t.erase("push")
		t.erase("packed")
		_set_toggle(t, bool(t["initial"]))
	_told.clear()
	for v in _volumes:
		v["inside"] = false
		v["ready"] = 0
		v["enabled"] = not (v["vol"] as Variant).disabled
	_started = false
	_posed_tick = -2147483648
	for i in touched:
		state_changed.emit(i)


## One tick: the delayed outputs, doors, volumes. A client only poses.
func step(tick: int) -> void:
	_last_tick = tick
	if authoritative:
		if not _started:
			_started = true
			_start(tick)
		_logic_to(tick)
		for m in _movers:
			_advance(m, tick)
		if tick % NEAR_EVERY == 0:
			_proximity(tick)
		if tick % VOLUME_EVERY == 0:
			_volume_step(tick)
			_hazard_step()
	pose_at(tick)


func _start(tick: int) -> void:
	if _logic != null:
		_logic_to(tick)
		_logic.start()


func _advance(m: Dictionary, tick: int) -> void:
	var d := int(m["dir"])
	if d != 0:
		var f := _fraction(m, tick)
		if (d > 0 and f >= 1.0) or (d < 0 and f <= 0.0):
			m["from"] = 1.0 if d > 0 else 0.0
			m["dir"] = 0
			m["start"] = tick
			if d > 0:
				_fire(int(m["entity"]), "OnFullyOpen", tick)
				_arm_close(m, tick)
			else:
				_fire(int(m["entity"]), "OnFullyClosed", tick)
	elif int(m["close_at"]) >= 0 and tick >= int(m["close_at"]):
		if _occupied(m["zone"]):
			m["close_at"] = tick + tick_rate
		else:
			m["close_at"] = -1
			_set_dir(m, -1, tick)


func _arm_close(m: Dictionary, tick: int) -> void:
	var wait := float(m["wait"])
	if wait > 0.0 and not bool(m["toggle"]) and not bool(m["auto"]) and SOLID_KINDS.has(str(m["kind"])):
		m["close_at"] = tick + roundi(wait * float(tick_rate))


func _occupied(zone: AABB) -> bool:
	return occupants_fn.is_valid() and bool(occupants_fn.call(zone))


func _proximity(tick: int) -> void:
	for m in _movers:
		if not bool(m["auto"]) or bool(m["locked"]):
			continue
		var near := _occupied((m["zone"] as AABB).grow(DOOR_PAD))
		var open_ish: bool = int(m["dir"]) > 0 or float(m["from"]) > 0.0
		if near:
			m["last_near"] = tick
			if int(m["dir"]) <= 0 and float(m["from"]) < 1.0 and (int(m["dir"]) < 0 or not open_ish):
				_set_dir(m, 1, tick)
			elif int(m["dir"]) < 0:
				_set_dir(m, 1, tick)
		elif open_ish and int(m["dir"]) >= 0:
			var stay := float(m["wait"]) if float(m["wait"]) > 0.0 else STAY_OPEN_SECONDS
			if float(tick - int(m["last_near"])) / float(tick_rate) >= stay:
				_set_dir(m, -1, tick)


func _volume_step(tick: int) -> void:
	if _volumes.is_empty() or not points_fn.is_valid():
		return
	var pts: PackedVector3Array = points_fn.call()
	for v in _volumes:
		var vol: Variant = v["vol"]
		var any := false
		for p in pts:
			if vol.contains(p):
				any = true
				break
		var entity := int(v["entity"])
		if any and not bool(v["inside"]):
			v["inside"] = true
			if bool(v["enabled"]) and tick >= int(v["ready"]):
				_fire(entity, "OnStartTouch", tick)
				_trip(v, tick)
		elif any and bool(v["enabled"]) and tick >= int(v["ready"]) and vol.wait > 0.0:
			_trip(v, tick)
		elif not any and bool(v["inside"]):
			v["inside"] = false
			_fire(entity, "OnEndTouch", tick)
			_fire(entity, "OnEndTouchAll", tick)


func _trip(v: Dictionary, tick: int) -> void:
	var vol: Variant = v["vol"]
	_fire(int(v["entity"]), "OnTrigger", tick)
	_fire(int(v["entity"]), "OnStartTouchAll", tick)
	if vol.kind == "once" or vol.wait < 0.0:
		v["enabled"] = false
	elif vol.wait > 0.0:
		v["ready"] = tick + roundi(vol.wait * float(tick_rate))


## A survivor's use key: the nearest live button or hand-operated door in reach, if any.
func try_press(eye: Vector3, look: Vector3, reach: float, tick: int) -> bool:
	if not authoritative:
		return false
	var best := -1
	var best_d := reach
	for m in _movers:
		var usable: bool = BUTTON_KINDS.has(str(m["kind"])) or (bool(m["mv"].use) and not bool(m["auto"]) and SOLID_KINDS.has(str(m["kind"])))
		if not usable or not bool(m["live"]) and BUTTON_KINDS.has(str(m["kind"])):
			continue
		var hit: Variant = (m["zone"] as AABB).grow(PRESS_PAD).intersects_ray(eye, look.normalized())
		if hit != null:
			var d := eye.distance_to(hit as Vector3)
			if d <= best_d:
				best_d = d
				best = int(m["idx"])
	if best < 0:
		return false
	_activator = eye
	_apply_input(_movers[best]["entity"], "Press", "", tick)
	_activator = null
	return true


# --- Outputs and inputs --------------------------------------------------------------------

func _fire(entity: int, output: String, tick: int) -> void:
	if _logic == null:
		return
	if _logic_busy == 0:
		_logic_to(tick)
	var _r := _logic.raise(entity, output, _activator)


## Steps the map's logic up to [param tick] (its clock starts at the first tick it is asked about), delivering what falls due.
func _logic_to(tick: int) -> void:
	if _logic == null or _logic_busy > 0:
		return
	if not _logic_synced:
		_logic_synced = true
		_logic_base = tick - _logic.now
	var behind := tick - _logic_base - _logic.now
	if behind > 0:
		_logic.advance(mini(behind, MAX_LOGIC_STEP))


## The tick the logic is at, for an input it delivers.
func _logic_tick() -> int:
	return _logic_base + (_logic.now if _logic != null else 0)


## Runs [param input] on [param entity] now. Public so a check can drive one.
func input(entity: int, input_name: String, tick: int) -> void:
	_apply_input(entity, input_name, "", tick)


func _apply_input(entity: int, input_name: String, _param: String, tick: int) -> void:
	var found: Variant = _by_entity.get(entity)
	if found == null:
		_note_unsupported("entity %d" % entity)
		return
	var what := str((found as Dictionary)["type"])
	var i := int((found as Dictionary)["i"])
	var name := input_name.to_lower()
	if what == "mover":
		if not _doors_only:
			_mover_input(_movers[i], name, tick)
	elif what == "volume":
		_volume_input(_volumes[i], name)
	elif what == "toggle":
		_toggle_input(_toggles[i], name, _param)


func _mover_input(m: Dictionary, name: String, tick: int) -> void:
	var button := BUTTON_KINDS.has(str(m["kind"]))
	match name:
		"lock":
			_set_locked(m, true)
		"unlock":
			_set_locked(m, false)
			m["ready"] = 0
		"press", "use", "trigger":
			if button:
				_press(m, tick)
			else:
				_toggle(m, tick)
		"open", "startforward":
			if not button:
				_open_to(m, 1, tick)
		"close", "startbackward":
			if not button:
				_open_to(m, -1, tick)
		"toggle":
			_toggle(m, tick)
		"stop":
			if int(m["dir"]) != 0:
				_set_dir(m, 0, tick)
		_:
			_note_unsupported("%s input %s" % [str(m["mv"].classname), name])


func _volume_input(v: Dictionary, name: String) -> void:
	match name:
		"enable":
			v["enabled"] = true
		"disable":
			v["enabled"] = false
		"toggle":
			v["enabled"] = not bool(v["enabled"])
		_:
			_note_unsupported("volume input " + name)


func _press(m: Dictionary, tick: int) -> void:
	if bool(m["locked"]) or tick < int(m["ready"]):
		return
	var wait := float(m["wait"])
	m["ready"] = 2147483647 if wait < 0.0 else tick + roundi(maxf(wait, 0.0) * float(tick_rate))
	_fire(int(m["entity"]), "OnPressed", tick)
	_fire(int(m["entity"]), "OnIn", tick)


func _set_locked(m: Dictionary, locked: bool) -> void:
	if bool(m["locked"]) == locked:
		return
	m["locked"] = locked
	_told[int(m["idx"])] = true
	state_changed.emit(int(m["idx"]))


func _open_to(m: Dictionary, d: int, tick: int) -> void:
	if bool(m["locked"]):
		return
	var f := _fraction(m, tick)
	if int(m["dir"]) == d or (d > 0 and f >= 1.0 and int(m["dir"]) == 0) or (d < 0 and f <= 0.0 and int(m["dir"]) == 0):
		return
	m["close_at"] = -1
	_set_dir(m, d, tick)


func _toggle(m: Dictionary, tick: int) -> void:
	var opening: bool = int(m["dir"]) > 0 or (int(m["dir"]) == 0 and float(m["from"]) >= 1.0)
	_open_to(m, -1 if opening else 1, tick)


func _set_dir(m: Dictionary, d: int, tick: int) -> void:
	var f := _fraction(m, tick)
	var before := int(m["dir"])
	if d > 0 and m.has("door") and f <= 0.0 and int(m["mv"].open_dir) == 0:
		_swing_away(m)
	m["from"] = f
	m["start"] = tick
	m["dir"] = d
	_told[int(m["idx"])] = true
	state_changed.emit(int(m["idx"]))
	if d > 0 and before <= 0:
		_fire(int(m["entity"]), "OnOpen", tick)
	elif d < 0 and before >= 0:
		_fire(int(m["entity"]), "OnClose", tick)


## Which way a door about to open turns: away from whoever opens it, as dot-map's mover node chooses.
func _swing_away(m: Dictionary) -> void:
	var at: Variant = _activator
	if at == null and opener_fn.is_valid():
		at = opener_fn.call((m["zone"] as AABB).grow(DOOR_PAD))
	m["side"] = (m["mv"] as Variant).side_away_from(at)


func _note_unsupported(what: String) -> void:
	if _unsupported_seen.has(what):
		return
	_unsupported_seen[what] = true
	DotLog.debug(CHANNEL, "an output this map uses is not run", {"what": what})


# --- Hurt, push, teleport and gravity ------------------------------------------------------

func _build_toggles(world: RefCounted) -> void:
	_toggle_base = _movers.size()
	for vol: Variant in _ents.volumes:
		if not VOLUME_KINDS.has(vol.kind):
			continue
		var t := {"vol": vol, "entity": vol.entity, "kind": vol.kind, "enabled": not vol.disabled,
				"initial": not vol.disabled, "bounds": (vol.bounds() as AABB).grow(BODY_PAD), "idx": _toggle_base + _toggles.size()}
		_by_entity[vol.entity] = {"type": &"toggle", "i": _toggles.size()}
		_toggles.append(t)
		if PREDICTED_KINDS.has(vol.kind):
			_predicted.append(t)
	if authoritative and not _toggles.is_empty():
		_build_volume_io(world)


## The volumes' entities (their keys, and the filters they name) in a DotMapIO that never starts: the map's own links run in [member _logic].
func _build_volume_io(world: RefCounted) -> void:
	var from_doc := {}
	var filters: Array = []
	for rec: Variant in _source_records():
		var cls := str((rec as Dictionary).get("classname", ""))
		if cls.begins_with("filter_"):
			filters.append(rec)
		from_doc[int((rec as Dictionary).get("index", -1))] = rec
	var records: Array = []
	for t in _toggles:
		var vol: Variant = t["vol"]
		var rec: Dictionary = (from_doc[int(t["entity"])] as Dictionary).duplicate() if from_doc.has(int(t["entity"])) else _synth_record(vol)
		rec["outputs"] = []
		records.append(rec)
	for f: Variant in filters:
		var copy: Dictionary = (f as Dictionary).duplicate()
		copy["outputs"] = []
		records.append(copy)
	_vol_io = DotMapIO.new()
	_vol_io.rate = maxi(tick_rate / VOLUME_EVERY, 1)
	_scale_io(_vol_io, world.get("manifest"))
	var loaded := _vol_io.load_records(records)
	if not loaded.ok:
		DotLog.warn(CHANNEL, "the map's volumes did not load", {"why": loaded.error.message})
		_vol_io = null
		return
	_vol_io.damage_fn = _volume_hurt
	_vol_io.move_fn = _volume_move
	_vol_io.event_fn = _on_logic_event
	_vols = DotMapVolumes.new()
	_vols.io = _vol_io
	for t in _toggles:
		var node := DotMapVolumeNode.new(t["vol"], _vol_io.entity_of(int(t["entity"])))
		_vols.nodes.append(node)
		var e := node.entity
		if e != null:
			e.enabled = bool(t["enabled"])


## The manifest record of a volume as an entity record, when no source document is shipped: its damage, flags, speed and gravity.
static func _synth_record(vol: Variant) -> Dictionary:
	var pairs: Array = [["spawnflags", str(vol.spawnflags)], ["target", vol.target], ["filtername", vol.filter]]
	var r: Dictionary = vol.record
	for key: String in ["damage", "gravity"]:
		if r.has(key):
			pairs.append([key, str(r[key])])
	return {"index": vol.entity, "classname": vol.classname, "targetname": vol.targetname, "pairs": pairs, "outputs": []}


func _hazard_step() -> void:
	if _vols == null or not bodies_fn.is_valid():
		return
	var near: Array = []
	for b: Dictionary in bodies_fn.call():
		var feet: Vector3 = b["position"]
		var column := AABB(feet - Vector3(0.05, 0.0, 0.05), Vector3(0.1, float(b.get("height", 1.8)), 0.1))
		for t in _toggles:
			if bool(t["enabled"]) and (t["bounds"] as AABB).intersects(column):
				near.append(b)
				break
	_vol_io.advance(1)
	_vols.step(near)


func _volume_hurt(body: Variant, amount: float, kind: String, by: Variant) -> void:
	if damage_fn.is_valid():
		damage_fn.call(body, amount, kind, (by as DotMapEntity).index if by is DotMapEntity else -1)


func _volume_move(body: Variant, motion: Variant) -> void:
	if move_fn.is_valid():
		move_fn.call(body, motion)


func _toggle_input(t: Dictionary, name: String, param: String) -> void:
	match name:
		"enable", "turnon":
			_set_toggle(t, true)
		"disable", "turnoff":
			_set_toggle(t, false)
		"toggle":
			_set_toggle(t, not bool(t["enabled"]))
		_:
			var e: DotMapEntity = _vol_io.entity_of(int(t["entity"])) if _vol_io != null else null
			if e == null or not e.accept(_vol_io, name, param, null, null):
				_note_unsupported("%s input %s" % [str(t["kind"]), name])
			elif e is DotMapPush:
				_set_push(t, (e as DotMapPush).velocity())


func _set_toggle(t: Dictionary, on: bool) -> void:
	if bool(t["enabled"]) == on:
		return
	t["enabled"] = on
	if _vol_io != null:
		var e := _vol_io.entity_of(int(t["entity"]))
		if e != null:
			e.set_enabled(_vol_io, on)
	if PREDICTED_KINDS.has(str(t["kind"])):
		_told[int(t["idx"])] = true
		state_changed.emit(int(t["idx"]))


## A push volume's velocity changed (SetPushSpeed, SetPushDirection): kept at the precision the wire carries, so prediction agrees.
func _set_push(t: Dictionary, velocity: Vector3) -> void:
	var packed := pack_push(velocity)
	if t.get("packed", 0) == packed:
		return
	t["packed"] = packed
	t["push"] = unpack_push(packed)
	_told[int(t["idx"])] = true
	state_changed.emit(int(t["idx"]))


## A push velocity as one integer for the MOVER event's start field: bit 29 set, speed in 0.1 m/s (12 bits), yaw (9) and pitch + 90 (8) in degrees.
static func pack_push(v: Vector3) -> int:
	var speed := clampi(roundi(v.length() * 10.0), 0, 4095)
	var yaw := posmod(roundi(rad_to_deg(atan2(v.z, v.x))), 360)
	var pitch := clampi(roundi(rad_to_deg(asin(clampf(v.y / maxf(v.length(), 0.0001), -1.0, 1.0)))) + 90, 0, 180)
	return (1 << 29) | speed | (yaw << 12) | (pitch << 21)


static func unpack_push(packed: int) -> Vector3:
	var speed := float(packed & 4095) / 10.0
	var yaw := deg_to_rad(float((packed >> 12) & 511))
	var pitch := deg_to_rad(float((packed >> 21) & 255) - 90.0)
	return Vector3(cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw)) * speed


## The push in m/s a survivor whose column stands at [param feet] feels from the live push volumes. Pure of the tick, so prediction and the server agree.
func push_at(feet: Vector3, height: float) -> Vector3:
	var out := Vector3.ZERO
	for t in _predicted:
		if str(t["kind"]) == "push" and _touches_player(t, feet, height):
			out += t["push"] if t.has("push") else (t["vol"] as DotMapVolume).push_velocity()
	return out


## The gravity scale a survivor at [param feet] is under (1 outside every gravity volume).
func gravity_at(feet: Vector3, height: float) -> float:
	for t in _predicted:
		if str(t["kind"]) == "gravity" and _touches_player(t, feet, height):
			return float((t["vol"] as DotMapVolume).record.get("gravity", 1.0))
	return 1.0


func _touches_player(t: Dictionary, feet: Vector3, height: float) -> bool:
	if not bool(t["enabled"]):
		return false
	var vol: DotMapVolume = t["vol"]
	var flags := vol.spawnflags & 15
	if flags != 0 and (flags & 1) == 0:
		return false
	return (t["bounds"] as AABB).intersects(AABB(feet - Vector3(0.05, 0.0, 0.05), Vector3(0.1, height, 0.1))) and vol.touches_column(feet, height)


## Counts for checks: volumes by kind, and how many are live.
func volume_counts() -> Dictionary:
	var out := {}
	for t in _toggles:
		out[t["kind"]] = int(out.get(t["kind"], 0)) + 1
	return out


## The toggle volumes as plain data (checks): `{kind, entity, enabled, bounds}`.
func volume_toggles() -> Array[Dictionary]:
	return _toggles


# --- The map's logic -------------------------------------------------------------------------

func _scale_io(io: DotMapIO, manifest: Variant) -> void:
	if manifest is Dictionary:
		io.unit_scale = float(((manifest as Dictionary).get("units", {}) as Dictionary).get("metres_per_unit", io.unit_scale))
		io.destinations = (manifest as Dictionary).get("destinations", {})


## Every entity of the source document (`entities[]`), or [] when it is not shipped beside the world.
func _source_records() -> Array:
	if _source_read:
		return _source
	_source_read = true
	if source_doc_path != "" and FileAccess.file_exists(source_doc_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_doc_path))
		if parsed is Dictionary and (parsed as Dictionary).get("entities") is Array:
			_source = (parsed as Dictionary)["entities"]
	return _source


## Without the source document, entity records made from what the manifest keeps: every mover, volume and unknown class, with its outputs.
func _manifest_records() -> Array:
	var out: Array = []
	var seen := {}
	for g: Dictionary in _ents.generic:
		var pairs: Array = []
		for k: Variant in (g.get("keys", {}) as Dictionary):
			pairs.append([str(k), str(g["keys"][k])])
		out.append(_record_of(int(g["entity"]), str(g["classname"]), str(g.get("targetname", "")), pairs))
		seen[int(g["entity"])] = true
	for mv: Variant in _ents.movers:
		out.append(_record_of(mv.entity, str(mv.classname), str(mv.targetname), []))
		seen[mv.entity] = true
	for vol: Variant in _ents.volumes:
		if vol.entity >= 0 and not seen.has(vol.entity):
			out.append(_record_of(vol.entity, str(vol.classname), str(vol.targetname), _synth_record(vol)["pairs"]))
	return out


func _record_of(entity: int, classname: String, targetname: String, pairs: Array) -> Dictionary:
	var outs: Array = []
	for link: Dictionary in _ents.links.fired_by(entity):
		outs.append({"output": str(link["output"]), "target": str(link["target"]), "input": str(link["input"]),
				"param": str(link.get("param", "")), "delay": float(link.get("delay", 0.0)), "times": int(link.get("times", -1))})
	return {"index": entity, "classname": classname, "targetname": targetname, "pairs": pairs, "outputs": outs}


## Builds (or rebuilds, for a new round) the logic runtime from the source document, else the manifest. The mover, button and
## volume classes hand their inputs to this class; the logic classes, the makers and the texts run in dot-map and here.
func _build_logic() -> void:
	_logic = null
	_logic_synced = false
	_logic_busy = 0
	var records := _source_records()
	if records.is_empty():
		records = _manifest_records()
	if records.is_empty():
		return
	var io := DotMapIO.new()
	io.rate = tick_rate
	io.command_allow = MapCommands.allow()
	_scale_io(io, _manifest)
	io.event_fn = _on_logic_event
	var _r := io.register_class("game_text", GameText)
	_r = io.register_class("game_text_tooltip", GameText)
	_r = io.register_class("env_entity_maker", EntityMaker)
	_r = io.register_class("npc_template_maker", NpcMaker)
	var owned := {}
	for mv: Variant in _ents.movers:
		owned[str(mv.classname).to_lower()] = true
	for vol: Variant in _ents.volumes:
		owned[str(vol.classname).to_lower()] = true
	for cls: String in owned:
		_r = io.register_handler(cls, _own_input)
	_r = io.register_class("logic_waves", LogicWaves)
	_r = io.register_class("logic_winlose", LogicWinLose)
	_r = io.register_class("logic_beats", LogicBeats)
	_r = io.register_class("logic_gamerules", LogicGameRules)
	io.state_changed.connect(_on_logic_state)
	var loaded := io.load_records(records)
	if not loaded.ok:
		DotLog.warn(CHANNEL, "the map's logic did not load", {"why": loaded.error.message})
		return
	_logic = io


## An input the logic delivers to one of this class's own entities (a lift, a button, a volume).
func _own_input(e: DotMapEntity, input_name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	if not _by_entity.has(e.index):
		return false
	var keep: Variant = _activator
	if activator is Vector3:
		_activator = activator
	_logic_busy += 1
	_apply_input(e.index, input_name, param, _logic_tick())
	_logic_busy -= 1
	_activator = keep
	return true


func _on_logic_event(kind: String, data: Dictionary) -> void:
	match kind:
		"template_spawn":
			_copy_made(data)
		"collision_pair":
			_set_pair(data)
	logic_event.emit(kind, data)


## The survival hold began wave [param number] (and [param ended] when it was cleared): every logic_waves naming it fires.
func wave_changed(number: int, ended: bool = false) -> void:
	if _logic == null:
		return
	_logic_to(_last_tick)
	for e: DotMapEntity in _logic.entities:
		if e is LogicWaves and e.alive:
			if ended:
				e.wave_ended(_logic, number)
			else:
				e.wave_started(_logic, number)
	_logic.settle()


## Whether a map's logic_beats has the wave announcer switched off.
func announcer_off() -> bool:
	if _logic == null:
		return false
	for e: DotMapEntity in _logic.entities:
		if e is LogicBeats and e.alive and e.announcer_off():
			return true
	return false


## The round was decided: every logic_winlose fires OnWin or OnLose.
func round_decided(won: bool) -> void:
	if _logic == null:
		return
	_logic_to(_last_tick)
	for e: DotMapEntity in _logic.entities:
		if e is LogicWinLose and e.alive:
			e.decided(_logic, won)
	_logic.settle()


## A zombie of the map's npc_template_maker [param maker] (an entity index) is dead, gone or never came to be.
func maker_child_gone(maker: int) -> void:
	if _logic == null:
		return
	var e := _logic.entity_of(maker)
	if e != null and e.has_method(&"child_gone"):
		e.call(&"child_gone", _logic)
		_logic.settle()


## Hands every active game_ui the buttons its holder has down; [param held_fn] is `(entity index, holder) -> Dictionary` of button names.
func feed_uis(held_fn: Callable) -> void:
	if _logic == null:
		return
	for e: DotMapEntity in _logic.active_uis():
		_logic.feed_ui(e.index, held_fn.call(e.index, (e as DotMapGameUi).player))


func _on_logic_state(e: DotMapEntity, key: String, value: Variant, _tick: int) -> void:
	if key == "alive" and value == false and _copies.has(e.index):
		_drop_copy(e.index)


# --- Template copies ---------------------------------------------------------------------------

## The brush models a point_template names, from the manifest: they are not in the map until it is asked, so they are not drawn
## or solid where they stand.
func template_models() -> Dictionary:
	var named := {}
	for rec: Variant in _manifest.get("entities", []):
		var d: Dictionary = rec
		if str(d.get("classname", "")).to_lower() != "point_template":
			continue
		for k: Variant in (d.get("keys", {}) as Dictionary):
			if str(k).to_lower().begins_with("template") and str(k).length() == 10:
				named[str(d["keys"][k]).to_lower()] = true
	var out := {}
	if named.is_empty():
		return out
	for list: String in ["movers", "volumes", "breakables", "entities"]:
		for rec: Variant in _manifest.get(list, []):
			var d: Dictionary = rec
			if d.get("model") != null and named.has(str(d.get("targetname", "")).to_lower()):
				out[int(d["model"])] = true
	return out


func _copy_made(data: Dictionary) -> void:
	var src := _logic.entity_of(int(data["source"]))
	if src == null or not src.key("model").begins_with("*"):
		return
	var offset := Vector3.ZERO
	if int(data.get("maker", -1)) >= 0:
		var maker := _logic.entity_of(int(data["maker"]))
		var tpl := _logic.entity_of(int(data["template"]))
		if maker != null and tpl != null:
			offset = maker.origin(_logic) - tpl.origin(_logic)
	var id := int(data["entity"])
	apply_copy(id, int(src.key("model").substr(1)), offset, true, src.classname)


## A copy of brush [param model] stands [param offset] from where the model does ([param alive]), or goes. A client is told the same.
func apply_copy(id: int, model: int, offset: Vector3, alive: bool, classname: String = "") -> void:
	if not alive:
		_drop_copy(id)
		return
	if _copies.has(id):
		return
	var c := {"id": id, "model": model, "offset": offset, "node": null, "body": null}
	_copies[id] = c
	_show_copy(c)
	if authoritative and _world != null and COPY_SOLID.has(classname.to_lower()):
		_solidify_copy(c)
	if authoritative:
		copy_changed.emit(id, model, offset, true)


func _show_copy(c: Dictionary) -> void:
	if c["node"] != null or not _model_nodes.has(int(c["model"])):
		return
	var from := _model_nodes[int(c["model"])] as Node3D
	var made := from.duplicate() as Node3D
	made.name = "Copy%d" % int(c["id"])
	made.visible = true
	from.get_parent().add_child(made)
	made.position = from.position + (c["offset"] as Vector3)
	c["node"] = made


func _solidify_copy(c: Dictionary) -> void:
	var shapes: Array = _world.call(&"hull_shapes", int(c["model"]))
	if shapes.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "CopyBody%d" % int(c["id"])
	for s: Dictionary in shapes:
		var cs := CollisionShape3D.new()
		cs.shape = s["shape"]
		body.add_child(cs)
	add_child(body)
	if _put_on.is_valid():
		_put_on.call(body)
	body.position = (_world.call(&"model_origin", int(c["model"])) as Vector3) + (c["offset"] as Vector3)
	c["body"] = body


func _drop_copy(id: int, tell: bool = true) -> void:
	var c: Variant = _copies.get(id)
	if c == null:
		return
	var _gone := _copies.erase(id)
	for k: String in ["node", "body"]:
		var n: Variant = (c as Dictionary)[k]
		if n is Node and is_instance_valid(n):
			(n as Node).queue_free()
	if tell and authoritative:
		copy_changed.emit(id, int((c as Dictionary)["model"]), (c as Dictionary)["offset"], false)


## The copies standing now, for a client that joins: `[{id, model, offset}]`.
func copies() -> Array:
	var out: Array = []
	for id: int in _copies:
		var c: Dictionary = _copies[id]
		out.append({"id": id, "model": c["model"], "offset": c["offset"]})
	return out


# --- Collision pairs ---------------------------------------------------------------------------

## A logic_collision_pair: the bodies of the two named entities pass through each other, or collide again. Bodies are found by
## targetname among the entities a node is bound to.
func _set_pair(data: Dictionary) -> void:
	var a := _body_named(str(data["a"]))
	var b := _body_named(str(data["b"]))
	if a == null or b == null:
		_note_unsupported("collision_pair without bodies")
		return
	if bool(data["collide"]):
		a.remove_collision_exception_with(b)
	else:
		a.add_collision_exception_with(b)


func _body_named(targetname: String) -> PhysicsBody3D:
	if _logic == null or targetname.is_empty():
		return null
	for e: DotMapEntity in _logic.find(targetname):
		if e.node is PhysicsBody3D:
			return e.node as PhysicsBody3D
		if e.node != null:
			for c in e.node.find_children("*", "PhysicsBody3D", true, false):
				return c as PhysicsBody3D
	return null


## What the map's links asked for that nothing here answers, for checks and the log:
## `{entities, unresolved (targets nothing carries), unhandled (class|input), denied commands, loop trips}`.
func logic_report() -> Dictionary:
	if _logic == null:
		return {}
	var gone := {}
	for e: DotMapEntity in _logic.entities:
		for link: Dictionary in e.links:
			var target: String = link["target"]
			if target.begins_with("!") or target.begins_with("#"):
				continue
			if _logic.resolve(target, e, null).is_empty():
				gone[target] = int(gone.get(target, 0)) + 1
	var cover := _logic.coverage()
	return {"entities": _logic.entities.size(), "unresolved": gone, "unhandled": cover["unhandled"],
			"commands_denied": cover["commands_denied"], "loop_trips": cover["loop_trips"]}


## The logic runtime itself, for checks.
func logic() -> DotMapIO:
	return _logic
