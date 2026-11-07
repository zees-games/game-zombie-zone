extends Node

## A pack monster's body as its brain sees it: the interface zz-historical-monsters' brain expects of a
## `ZhmBody` (`action`, `variant`, `setup`, `limb_severed`, `speed_scale()`, `attack_scale()`), backed by this
## game's [ZzZombieBody], which is what the monster really is. A child of that body, made by the generated
## brain (see `ZzPackBrains`) for its `_body()`, so it dies with it. No `class_name`: a mounted pack's brain is
## generated at run time and reaches this by path.

const ZzZombieBody := preload("zz_zombie_body.gd")

## Emitted when the real body loses a limb, same arguments.
signal limb_severed(limb: StringName, info: Dictionary)

## The brain's pose names, [code]ZhmPose.Anim[/code] in order, as [enum ZzZombieBody.Anim]. -1 (the brain
## says "let the gait decide") is not in it.
const ANIM := [
	ZzZombieBody.Anim.IDLE, ZzZombieBody.Anim.WALK, ZzZombieBody.Anim.RUN,
	ZzZombieBody.Anim.ATTACK,	# BITE
	ZzZombieBody.Anim.SCREAM,	# ROAR
	ZzZombieBody.Anim.ATTACK,	# SWEEP
	ZzZombieBody.Anim.CROUCH,	# CHARGE_WIND
	ZzZombieBody.Anim.CHARGE,
	ZzZombieBody.Anim.STAGGER,
	ZzZombieBody.Anim.CROUCH,	# STALK
	ZzZombieBody.Anim.CROUCH,	# POUNCE_WIND
	ZzZombieBody.Anim.LEAP,
	ZzZombieBody.Anim.ATTACK,	# MAUL
	ZzZombieBody.Anim.RAGE,	# SLAM_WIND
	ZzZombieBody.Anim.SLAM,
	ZzZombieBody.Anim.DEAD,
	ZzZombieBody.Anim.IDLE,	# LAND
]

var body: ZzZombieBody = null
## Which side of a combo (the brain sets it; the game's picture has no use for it, and the body's own
## `variant` picks its skin, so it is kept here).
var variant: int = 0
## The brain's pose, or -1 for the gait.
var action: int = -1:
	set(value):
		action = value
		if body != null and value >= 0 and value < ANIM.size():
			body.anim = ANIM[value]


func attach(p_body: ZzZombieBody) -> void:
	body = p_body
	if not body.limb_severed.is_connected(_on_severed):
		body.limb_severed.connect(_on_severed)


## The brain sizes its own collider and loads a model here; the game's body already has both.
func setup(_species: StringName, _body_cfg: Dictionary = {}, _limb_defs: Dictionary = {}) -> void:
	pass


func speed_scale() -> float:
	return body.limb_speed_scale() if body != null else 1.0


func attack_scale() -> float:
	return body.limb_attack_scale() if body != null else 1.0


## Once a think, after the brain: with no pose asked for, the gait the body is moving at.
func apply_gait() -> void:
	if body == null or action >= 0:
		return
	var speed := body.wish.length()
	body.anim = ZzZombieBody.Anim.IDLE if speed < 0.4 else (ZzZombieBody.Anim.RUN if speed > 5.0 else ZzZombieBody.Anim.WALK)


func _on_severed(limb: StringName, info: Dictionary) -> void:
	limb_severed.emit(limb, info)
