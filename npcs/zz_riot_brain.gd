extends "zz_special_brain.gd"

## The riot zombie: a common in riot gear, walking at the team behind its shield and clubbing
## whoever is in front. The shield is a hitbox of its own in front of it
## (`ZzHorde._register_combat`, `shield` in its meta), so shots from the front mostly stop there.
##
## [b]It keeps the shield between it and the guns.[/b] It turns to face whoever is shooting it,
## not only whoever it is after, so a team has to split its fire or shove it round (a shove
## staggers it like a common, and a staggered riot zombie shows its back). It does not retreat:
## gear like that does not run.

var _shooter: StringName = &""
var _shot_at: float = -INF


func _may_retreat() -> bool:
	return false


func _victim_bonus(id: StringName, at: Vector3) -> float:
	# The one shooting it, if they are near enough to walk to.
	return -12.0 if id == _shooter and now() - _shot_at < 4.0 else 0.0


func damaged(amount: float, by: StringName) -> void:
	super(amount, by)
	if by != &"":
		_shooter = by
		_shot_at = now()


func _special(_delta: float) -> void:
	var b := body()
	forced = victim
	var chasing := melee_chase(npc.def.move_speed)
	forced = &""

	if chasing:
		if b.anim == ZzZombieBody.Anim.RUN or b.anim == ZzZombieBody.Anim.WALK:
			b.anim = ZzZombieBody.Anim.BLOCK
	else:
		halt()
		b.anim = ZzZombieBody.Anim.BLOCK

	# Square to the gun while it walks: the last one to shoot it, if they shot it lately.
	if _shooter != &"" and now() - _shot_at < 2.0 and not swinging() and survivor_is(_shooter, &"alive"):
		face(survivor_at(_shooter) - npc.position())
