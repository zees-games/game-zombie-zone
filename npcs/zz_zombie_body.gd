extends CharacterBody3D

## One zombie's body: where it is, how it moves, and what it looks like it is doing.
##
## [b]The brain wishes, the body moves, once a tick.[/b] dot-npc's own steering calls
## `move_and_slide` from inside the brain, once per call, with gravity only while it is
## steering — so a zombie that stopped to swing hung in the air at whatever height it stood,
## and one that both steered and was shoved slid twice. Here a brain writes [member wish] (the
## horizontal velocity it wants) and the horde calls [method advance] once per tick, which adds
## the shove ([member push]), the fall, a leap in flight, and moves it once.
##
## [b]The same scene is the server's zombie and a client's picture of one.[/b] On a client it
## never moves itself: [member mirror] is set, collision is off, and the net behaviour writes
## its position; [ZzZombieView] draws it from [member kind], [member variant], [member anim] and
## [member flags].

## What it looks like it is doing. Replicated as one small integer; a client chooses a clip by
## it, and nothing on the server reads it back.
enum Anim {
	IDLE, WALK, RUN, ATTACK, STAGGER, SIT, FEED, CROUCH, LEAP, PIN, VOMIT, SPIT, CHARGE, CARRY,
	THROW, CRY, RAGE, TONGUE, DEAD, SHAMBLE,
	# Appended, never inserted: the value is replicated in 5 bits (ZzNpcNet), so 31 is the last.
	CRAWL, SCREAM, GRAB, BLOCK,
}

## Bits of [member flags].
const FLAG_BURNING := 1
const FLAG_ENRAGED := 2
const FLAG_MOB := 4
const FLAG_STARTLED := 8
const FLAG_BILED := 16

const CHANNEL := "zz.zombie"

## A limb came off (the server's shot, or a mirror told by [member limb_mask]).
signal limb_severed(limb: StringName, info: Dictionary)

## Which kind, from the catalogue. Set by the horde as it spawns, and on a client from the
## announcement.
var kind: StringName = &"common"

## A number per zombie that picks its body, skin and tint, so a crowd is not one person.
var variant: int = 0

var anim: int = Anim.IDLE
var flags: int = 0

## Its health as last heard: the server's own, or a client's from the snapshot. A client's view
## flinches when it drops.
var health: float = -1.0

## How it fell, once it is dead: decided by the server (`ZzHorde.decide_death`), sent with
## NPC_GONE, and read by the view. Null until then, and on a client that was not told.
var death: DotPlayerDeath = null

## Its shootable limbs (`ZzZombieLimbs.attach` makes them); null for a kind without any.
var limbs: DotNpcLimbs = null

## Replicated: bit `i` is set when the `i`th limb in config order is gone. Setting it severs the missing ones.
var limb_mask: int = 0:
	set(value):
		limb_mask = value
		if limbs != null and value != limbs.mask():
			limbs.apply_mask(value)

## The horizontal velocity the brain wants this tick.
var wish: Vector3 = Vector3.ZERO

## Velocity something else put into it — a shove, a blast — that decays on its own.
var push: Vector3 = Vector3.ZERO

## A leap in progress: true from the jump until it lands. Its velocity is [member velocity].
var flying: bool = false
var landed_this_tick: bool = false

## Held in place by the game (pinning somebody, or being carried along a tongue).
var anchored: bool = false

## A client's copy: drawn, never simulated.
var mirror: bool = false

var radius: float = 0.32
var height: float = 1.75

## How fast a shove dies away, per second.
const PUSH_DECAY := 6.0

const GRAVITY := 20.0
## The fastest a zombie falls, m/s. Gravity used to add up for as long as a body was off the
## floor: one wedged beside a prop for half a minute carried hundreds of metres a second down,
## and two left the school's car park through its floor (zz-mall-floor-falls-1).
const FALL_FASTEST := 25.0
## Ticks a leap may last before the body walks again whether or not it has landed: a leaper
## or a hopping common resting on something too steep to be a floor stayed `flying` (no
## steering) for 1804 ticks, then fell out of the map.
const LEAP_LONGEST := 64 * 3

## The highest lip a grounded mover is lifted over (a converted map's stair rise is 0.42), and how far past it the lift goes.
const STEP_UP := 0.45
const STEP_REACH := 0.2

var _shape: CollisionShape3D = null


func _ready() -> void:
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)
	safe_margin = 0.02
	_shape = CollisionShape3D.new()
	_shape.name = "Shape"
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0 + 0.05)
	_shape.shape = capsule
	_shape.position = Vector3(0.0, capsule.height * 0.5, 0.0)
	add_child(_shape)

	if mirror:
		collision_layer = 0
		collision_mask = 0


## Sizes the capsule from the kind's definition.
func configure(def: DotNpcDef) -> void:
	if def == null:
		return

	kind = def.id
	radius = float(def.meta.get("radius", radius))
	height = float(def.meta.get("height", height))

	if _shape != null:
		var capsule := _shape.shape as CapsuleShape3D
		capsule.radius = radius
		capsule.height = maxf(height, radius * 2.0 + 0.05)
		_shape.position = Vector3(0.0, capsule.height * 0.5, 0.0)


## Ticks between moves (set by the brain): 1 near anybody, more far from everybody, where a
## zombie moving twice as far every second tick looks the same from thirty metres and costs
## half the sweeps. [method tick] keeps the time owed and moves it in one go.
var stride: int = 1
var _waited: int = 0

## What the horde multiplies the wish by when it moves (a sprinters wave, a box that slows the
## horde). Kept apart from [member wish]: written onto the wish each tick, it compounded on a
## zombie that thinks only every second or fourth tick (a sprinters wave's far zombies ran at
## three times the pace by their next thought).
var speed_scale: float = 1.0

## Where it last stood on the floor, for the horde to say where one that fell out left the map.
var last_floor_at: Vector3 = Vector3.INF

## Ticks since it last leapt (a special's jump, a common's climb), for the same question.
var ticks_since_leap: int = 1 << 30


## Sets [member stride], spreading the strided bodies over the ticks rather than all moving on
## the same one.
func set_stride(ticks: int) -> void:
	ticks = maxi(ticks, 1)

	if ticks != stride:
		stride = ticks
		_waited = variant % ticks


## The horde's call every tick: moves now, or counts the tick toward the next strided move. A
## body in the air or being shoved moves every tick whatever its stride.
func tick(delta: float) -> void:
	_waited += 1
	ticks_since_leap += 1

	if _waited < stride and not flying and push.length_squared() < 0.0004:
		landed_this_tick = false
		return

	var ticks := _waited
	_waited = 0
	advance(delta * float(ticks), ticks)


## One move of [param ticks] ticks' worth ([param delta] is their whole time). On the server
## only. move_and_slide moves by the engine's own tick, so a strided move scales the velocity
## for the sweep and puts it back after.
func advance(delta: float, ticks: int = 1) -> void:
	landed_this_tick = false

	if mirror or anchored:
		velocity = Vector3.ZERO
		return

	if flying:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -FALL_FASTEST)
		var _hit := _sweep(ticks)

		if is_on_floor() and velocity.y <= 0.0:
			last_floor_at = global_position
			flying = false
			landed_this_tick = true
			velocity = Vector3.ZERO
		elif ticks_since_leap > LEAP_LONGEST:
			flying = false

		return

	var horizontal := wish * speed_scale + push

	# Standing still on the floor (tearing at a barricade, swinging, waiting its turn on the
	# ring): nothing to move, so no sweep. Half a big wave stands at the windows, and a
	# move_and_slide for each of them every tick was a quarter of the horde's tick.
	if horizontal.length_squared() < 0.0004 and is_on_floor() and absf(velocity.y) < 0.01:
		velocity = Vector3.ZERO
		return

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -FALL_FASTEST)

	var before := global_position
	var _moved := _sweep(ticks)

	if is_on_floor() and horizontal.length_squared() > 0.04:
		var flat := global_position - before
		flat.y = 0.0

		if flat.length() < horizontal.length() * delta * 0.3:
			_step_up(horizontal.normalized())

	if is_on_floor():
		last_floor_at = global_position

	push = push.move_toward(Vector3.ZERO, PUSH_DECAY * delta * maxf(push.length(), 1.0))


## Lifts a body stopped by a low lip (a stair foot's 0.15 m) over it. A capsule's round bottom does
## not climb one by itself, and the nav does not know a lip that low; taller than STEP_UP is a wall.
func _step_up(direction: Vector3) -> void:
	# A barricade is meant to stop it, however low its boards.
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i).get_collider() as Object

		if hit != null and hit.has_meta(&"barricade"):
			return

	# Lowest lift first: a low lip under a ceiling slab has no room for the full height.
	for rise: float in [0.15, 0.3, STEP_UP]:
		var lifted := global_transform
		lifted.origin.y += rise

		if test_move(global_transform, Vector3(0.0, rise, 0.0)) or test_move(lifted, direction * STEP_REACH):
			continue

		lifted.origin += direction * STEP_REACH

		# Set back down on the tread, so a 0.1 m lip is not a 0.45 m pop.
		var landing := KinematicCollision3D.new()

		if test_move(lifted, Vector3(0.0, -rise, 0.0), landing):
			lifted.origin.y -= landing.get_travel().length()

		global_transform = lifted
		return


## Starts a leap with [param launch] as its velocity.
func _sweep(ticks: int) -> bool:
	if ticks <= 1:
		return move_and_slide()

	velocity *= float(ticks)
	var hit := move_and_slide()
	velocity /= float(ticks)
	return hit


func leap(launch: Vector3) -> void:
	ticks_since_leap = 0
	flying = true
	velocity = launch
	wish = Vector3.ZERO


## Adds a shove: [param impulse] in m/s, horizontal.
func shove(impulse: Vector3) -> void:
	push += Vector3(impulse.x, 0.0, impulse.z)

	if impulse.y > 0.0 and is_on_floor():
		velocity.y = impulse.y


func limb_speed_scale() -> float:
	return limbs.speed_scale() if limbs != null else 1.0


func limb_attack_scale() -> float:
	return limbs.attack_scale() if limbs != null else 1.0


func on_limbs_severed(limb: StringName, info: Dictionary) -> void:
	limb_mask = limbs.mask()
	limb_severed.emit(limb, info)


func set_flag(bit: int, on: bool) -> void:
	flags = (flags | bit) if on else (flags & ~bit)


func has_flag(bit: int) -> bool:
	return (flags & bit) != 0


## Where its head is, for a headshot, a sight line, or a tongue.
func head() -> Vector3:
	return global_position + Vector3(0.0, height * 0.9, 0.0)


func chest() -> Vector3:
	return global_position + Vector3(0.0, height * 0.6, 0.0)


func describe() -> Dictionary:
	return {
		"kind": String(kind), "anim": Anim.keys()[anim], "flags": flags,
		"wish": "%.1f" % wish.length(), "push": "%.1f" % push.length(), "flying": flying,
	}
