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


## One tick of movement. On the server only.
func advance(delta: float) -> void:
	landed_this_tick = false

	if mirror or anchored:
		velocity = Vector3.ZERO
		return

	if flying:
		velocity.y -= GRAVITY * delta
		var _hit := move_and_slide()

		if is_on_floor() and velocity.y <= 0.0:
			flying = false
			landed_this_tick = true
			velocity = Vector3.ZERO

		return

	var horizontal := wish + push

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
		velocity.y -= GRAVITY * delta

	var _moved := move_and_slide()
	push = push.move_toward(Vector3.ZERO, PUSH_DECAY * delta * maxf(push.length(), 1.0))


## Starts a leap with [param launch] as its velocity.
func leap(launch: Vector3) -> void:
	flying = true
	velocity = launch
	wish = Vector3.ZERO


## Adds a shove: [param impulse] in m/s, horizontal.
func shove(impulse: Vector3) -> void:
	push += Vector3(impulse.x, 0.0, impulse.z)

	if impulse.y > 0.0 and is_on_floor():
		velocity.y = impulse.y


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
