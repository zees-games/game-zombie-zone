extends RefCounted

## A survivor picking up a loose prop (a ball, pin, barrel, crate, tyre), carrying it in front of them and putting it down. Server side only:
## the held toy is a kinematic body moved each tick, so its transform replicates through the ordinary TOYS state with nothing new on the wire.

const KINDS: Array[StringName] = [&"ball", &"pin", &"barrel", &"crate", &"tyre"]
const REACH := 2.2
const HOLD_DISTANCE := 1.3
## Metres kept between a held prop and a wall, so it is never pushed into one.
const WALL_GAP := 0.15

## Most impulse (kg m/s) a throw gives a prop and the speed it may leave at (m/s): a crate goes slower than a ball.
const THROW_IMPULSE := 90.0
const THROW_SPEED_MAX := 14.0

## Heaviest prop (kg) a survivor lifts; the zz_prop_carry_mass cvar.
var max_mass: float = 30.0
## player id (StringName) -> toy index (int)
var held: Dictionary = {}
var _box_id: int = 0


## Whether [param player_id] has a prop in hand.
func carrying(player_id: StringName) -> bool:
	return held.has(player_id)


## Picks up the loose toy [param player_id] looks at, if it is liftable and not already held. The toy's index, or -1.
func pick_up(box: DotPropToyBox, player_id: StringName, eye: Vector3, direction: Vector3, mask: int) -> int:
	if box == null or not box.authoritative or not box.rules.enabled or not box.is_inside_tree() or held.has(player_id):
		return -1
	var query := PhysicsRayQueryParameters3D.create(eye, eye + direction.normalized() * REACH, mask | box.loose_layer)
	query.collide_with_areas = false
	var found := box.get_world_3d().direct_space_state.intersect_ray(query)
	var toy := DotPropToyBox.toy_of(found.get("collider")) if not found.is_empty() else null
	if toy == null or toy.body == null or not KINDS.has(toy.kind):
		return -1
	if float(toy.def.get("mass", 1.0)) > max_mass or held.values().has(toy.index):
		return -1
	_box_id = box.get_instance_id()
	held[player_id] = toy.index
	toy.body.linear_velocity = Vector3.ZERO
	toy.body.angular_velocity = Vector3.ZERO
	toy.body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	toy.body.freeze = true
	toy.touched_at = box._now
	return toy.index


## Puts the prop down where it is held, at rest. The toy's index, or -1 when nothing was held.
func put_down(box: DotPropToyBox, player_id: StringName) -> int:
	if not held.has(player_id):
		return -1
	var index: int = held[player_id]
	held.erase(player_id)
	var toy := box.toy(index) if box != null and is_instance_valid(box) else null
	if toy != null and toy.body != null and is_instance_valid(toy.body):
		toy.body.freeze = false
		toy.body.linear_velocity = Vector3.ZERO
		toy.body.angular_velocity = Vector3.ZERO
		toy.body.sleeping = false
		toy.touched_at = box._now
	return index


## Throws the held prop along [param direction]: put down, then given [param scale] times [constant THROW_IMPULSE] (capped, so a light ball leaves at
## THROW_SPEED_MAX and a heavy barrel slower). The toy's index, or -1 when nothing was held.
func throw_held(box: DotPropToyBox, player_id: StringName, direction: Vector3, scale: float = 1.0) -> int:
	var index := put_down(box, player_id)
	var toy := box.toy(index) if index >= 0 else null
	if toy == null or toy.body == null:
		return index
	var mass := maxf(float(toy.def.get("mass", 1.0)), 0.25)
	var speed := minf(THROW_IMPULSE * maxf(scale, 0.0) / mass, THROW_SPEED_MAX)
	toy.body.linear_velocity = (direction.normalized() + Vector3(0.0, 0.15, 0.0)).normalized() * speed
	toy.body.sleeping = false
	return index


## What the use key would do now, for a prompt: "put down" when a loose prop sits at the hold point, "pick up <kind>" when one is in reach, else "".
## Reads only bodies, so a client's mirror of the toys answers as the server does.
static func hint(box: DotPropToyBox, eye: Vector3, direction: Vector3, mask: int, lift_mass: float) -> String:
	if box == null or not box.is_inside_tree() or box.count() == 0:
		return ""
	var hold := eye + direction.normalized() * HOLD_DISTANCE
	for i in box.count():
		var toy := box.toy(i)
		if toy != null and toy.body != null and KINDS.has(toy.kind) and toy.body.freeze and toy.body.global_position.distance_to(hold) < 0.6:
			return "put down"
	var query := PhysicsRayQueryParameters3D.create(eye, eye + direction.normalized() * REACH, mask | box.loose_layer)
	query.collide_with_areas = false
	var found := box.get_world_3d().direct_space_state.intersect_ray(query)
	var toy := DotPropToyBox.toy_of(found.get("collider")) if not found.is_empty() else null
	if toy != null and toy.body != null and KINDS.has(toy.kind) and float(toy.def.get("mass", 1.0)) <= lift_mass:
		return "pick up %s" % toy.kind
	return ""


## Moves every held prop to its carrier's hold point; a carrier who is gone, dead or down drops it.
## [param carrier_of] maps a player id to its survivor, or null.
func advance(box: DotPropToyBox, carrier_of: Callable, mask: int) -> void:
	if held.is_empty():
		return
	if box == null or not is_instance_valid(box) or box.get_instance_id() != _box_id:
		held.clear()
		return
	for player_id: StringName in held.keys():
		var player: Variant = carrier_of.call(player_id)
		var toy := box.toy(held[player_id])
		if player == null or toy == null or toy.body == null or not is_instance_valid(toy.body):
			var _dropped := put_down(box, player_id)
			continue
		var eye: Vector3 = player.eye_position()
		var direction: Vector3 = player.aim_direction()
		var spot := eye + direction * HOLD_DISTANCE
		var query := PhysicsRayQueryParameters3D.create(eye, spot + direction * WALL_GAP, mask)
		query.collide_with_areas = false
		var wall := box.get_world_3d().direct_space_state.intersect_ray(query)
		if not wall.is_empty():
			spot = (wall["position"] as Vector3) - direction * (WALL_GAP + 0.1)
		toy.body.global_transform = Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.z)), spot)
		toy.touched_at = box._now
