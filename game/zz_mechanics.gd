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
const MIN_TRAVEL := 0.05
const DEFAULT_PATH_SPEED := 2.0
## How long a door that stays open waits for nobody to be near before it closes.
const STAY_OPEN_SECONDS := 2.0
const NEAR_EVERY := 4
const VOLUME_EVERY := 2
const PRESS_PAD := 0.3
const DOOR_PAD := 1.5
const MAX_FIRES := 256

## A mover changed state (it was told, or it settled); the bridge broadcasts this index.
signal state_changed(index: int)

var tick_rate: int = 64
var authoritative: bool = true
## Whether a box (world metres) has a survivor or a zombie in it.
var occupants_fn: Callable = Callable()
## The living survivors' body points.
var points_fn: Callable = Callable()
## Where whoever is in a box (survivor or zombie) stands, nearest its centre, or null: which way a door swings away from.
var opener_fn: Callable = Callable()

var _ents: Variant = null
var _movers: Array[Dictionary] = []
var _volumes: Array[Dictionary] = []
var _generic: Dictionary = {}
var _by_entity: Dictionary = {}
var _by_body: Dictionary = {}
var _queue: Array[Array] = []
var _seq: int = 0
var _fired: Dictionary = {}
var _told: Dictionary = {}
var _started: bool = false
var _posed_tick: int = -2147483648
var _unsupported_seen: Dictionary = {}
## Who pressed the input being run (a survivor's eye), for a door's side.
var _activator: Variant = null


## Builds from [param world] (a DotMapBspMesh). [param put_on] is called with each body to give
## it the world's physics layer.
## [param doors_only] builds just the hinged prop doors (a world from the global converter draws its own brush
## doors, so the rest would collide twice); with no switch or key run there, such a door opens to anyone near it.
func build(world: RefCounted, put_on: Callable, doors_only: bool = false) -> void:
	_ents = world.call(&"entities")
	var models := {}
	for model: int in world.call(&"models"):
		models[model] = true

	for mv: Variant in _ents.movers:
		if mv.model < 0 and str(mv.classname).to_lower() == "prop_door_rotating":
			_build_door(mv, put_on, doors_only)
			continue
		if doors_only or mv.model < 0 or not models.has(mv.model):
			continue
		var m := _make_mover(mv, world)
		m["idx"] = _movers.size()
		_movers.append(m)
		_by_entity[mv.entity] = {"type": &"mover", "i": m["idx"]}

		if SOLID_KINDS.has(mv.kind):
			var shapes: Array = world.call(&"hull_shapes", mv.model)
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

	if doors_only:
		return

	for vol: Variant in _ents.volumes:
		var v := {"vol": vol, "entity": vol.entity, "inside": false, "ready": 0, "enabled": not vol.disabled}
		if vol.kind == "multiple" or vol.kind == "once":
			_by_entity[vol.entity] = {"type": &"volume", "i": _volumes.size()}
			_volumes.append(v)
		else:
			_note_unsupported("volume " + vol.kind)

	for g: Dictionary in _ents.generic:
		_by_entity[int(g["entity"])] = {"type": &"generic", "i": int(g["entity"])}
		_generic[int(g["entity"])] = {"rec": g, "enabled": true}


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
		for m in _movers:
			if int(m["model"]) == int(child.get_meta(&"model")):
				m["node"] = child
	_posed_tick = -2147483648


## Whether the map has volumes or logic entities to run.
func has_logic() -> bool:
	return not _volumes.is_empty() or not _generic.is_empty()


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
	_queue.clear()
	_fired.clear()
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
	for v in _volumes:
		v["inside"] = false
		v["ready"] = 0
		v["enabled"] = not (v["vol"] as Variant).disabled
	for e: Dictionary in _generic.values():
		e["enabled"] = true
	_started = false
	_posed_tick = -2147483648
	for i in touched:
		state_changed.emit(i)


## One tick: the delayed outputs, doors, volumes. A client only poses.
func step(tick: int) -> void:
	if authoritative:
		if not _started:
			_started = true
			_start(tick)
		_run_queue(tick)
		for m in _movers:
			_advance(m, tick)
		if tick % NEAR_EVERY == 0:
			_proximity(tick)
		if tick % VOLUME_EVERY == 0:
			_volume_step(tick)
		_run_queue(tick)
	pose_at(tick)


func _start(tick: int) -> void:
	for e: Dictionary in _generic.values():
		if str(e["rec"].get("classname", "")) == "logic_auto":
			_fire(int(e["rec"]["entity"]), "OnMapSpawn", tick)
			_fire(int(e["rec"]["entity"]), "OnNewGame", tick)


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
	if _ents == null:
		return
	for link: Dictionary in _ents.links.fired_by(entity, output):
		var times := int(link.get("times", -1))
		if times > 0:
			var key := "%d/%s/%s/%s/%s" % [entity, output, str(link["input"]), str(link["target"]), str(link["delay"])]
			var n := int(_fired.get(key, 0))
			if n >= times:
				continue
			_fired[key] = n + 1
		var due := tick + roundi(float(link.get("delay", 0.0)) * float(tick_rate))
		var targets: Array = link.get("to", [])
		if targets.is_empty():
			_note_unsupported("target " + str(link.get("target", "")))
		for t in targets:
			_seq += 1
			_queue.append([due, _seq, int(t), str(link["input"]), str(link.get("param", ""))])


func _run_queue(tick: int) -> void:
	var guard := 0
	while guard < MAX_FIRES:
		var due: Array[Array] = []
		var keep: Array[Array] = []
		for q in _queue:
			if int(q[0]) <= tick:
				due.append(q)
			else:
				keep.append(q)
		if due.is_empty():
			return
		_queue = keep
		due.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
		for q in due:
			guard += 1
			_apply_input(int(q[2]), str(q[3]), str(q[4]), tick)


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
		_mover_input(_movers[i], name, tick)
	elif what == "volume":
		_volume_input(_volumes[i], name)
	else:
		_generic_input(_generic[i], name, tick)


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


func _generic_input(e: Dictionary, name: String, tick: int) -> void:
	var cls := str(e["rec"].get("classname", ""))
	if cls != "logic_relay":
		_note_unsupported(cls + " input " + name)
		return
	match name:
		"trigger":
			if bool(e["enabled"]):
				_fire(int(e["rec"]["entity"]), "OnTrigger", tick)
		"enable":
			e["enabled"] = true
		"disable":
			e["enabled"] = false
		_:
			_note_unsupported(cls + " input " + name)


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
