extends "zz_special_brain.gd"

## The brute: the boss. It chases whoever hurts it most, throws a slab of concrete at whoever it
## cannot reach, and every swing sends somebody flying.
##
## [b]Who it chases is who it is angry at.[/b] It keeps a grudge per survivor, the damage each
## has done to it decaying over a few seconds, and goes for the biggest — so a team can pass it
## between them, one drawing it while the rest shoot, which is the genre's whole brute fight.
## With no grudge it takes the nearest.
##
## [b]It throws when chasing would fail[/b]: the target is far, or up on something, or the path
## is long. A rock is a wind-up of a second and a half, which is the warning; it leads its target,
## so a survivor who runs in a straight line is hit and one who turns is not.
##
## [b]It cannot be shoved and it does not retreat.[/b] Fire slows its burning, not it.

const THROW := &"throw"

var _grudge: Dictionary = {}
var _throw_at: float = INF
var _throw_target: StringName = &""
var _last_hit_survivor: float = 0.0


func _build() -> void:
	super()
	character.view_turn_deg = 300.0
	character.reaction_time = 0.3


func _may_retreat() -> bool:
	return false


func stagger(_direction: Vector3, _seconds: float, _strength: float = 4.0) -> void:
	pass


func damaged(amount: float, by: StringName) -> void:
	super(amount, by)

	if by != &"":
		_grudge[by] = float(_grudge.get(by, 0.0)) + amount


func choose_victim() -> StringName:
	var best := &""
	var most := 30.0

	for id: StringName in _grudge.keys():
		_grudge[id] = float(_grudge[id]) * exp(-context.delta / 4.0)

		if not survivor_is(id, &"alive"):
			_grudge.erase(id)
			continue

		if float(_grudge[id]) > most:
			most = float(_grudge[id])
			best = id

	if best != &"":
		return best

	var nearest := &""
	var gap := INF

	for id in _survivors():
		if not survivor_is(id, &"alive"):
			continue
		var d := distance_to(id)
		if d < gap:
			gap = d
			nearest = id

	return nearest


func _special(_delta: float) -> void:
	var b := body()
	var gap := distance_to(victim)
	var at := survivor_at(victim)
	var reach := tune(&"reach", 2.4)

	# Frustrated: nobody hit for a while, it comes faster.
	var frustrated := now() - _last_hit_survivor > tune(&"frustration_seconds", 25.0)
	b.set_flag(ZzZombieBody.FLAG_ENRAGED, frustrated)
	var speed := npc.def.move_speed * (1.18 if frustrated else 1.0)

	if state == THROW:
		halt()
		b.anim = ZzZombieBody.Anim.THROW
		var aim_at := survivor_at(_throw_target)
		if aim_at != Vector3.INF:
			face(aim_at - npc.position())

		if _throw_at != INF and now() >= _throw_at:
			_throw_at = INF
			var from := npc.position() + Vector3(0.0, 3.0, 0.0)
			var rock_speed := tune(&"rock_speed", 24.0)
			var lead_at := lead(_throw_target, distance_to(_throw_target) / rock_speed) + Vector3(0.0, 1.0, 0.0)
			var h := horde()
			if h != null:
				h.call(&"projectile", &"rock", from, launch_to(from, lead_at, rock_speed, 18.0), npc, tune(&"rock_damage", 24.0))
			cool_down(tune(&"rock_cooldown", 9.0))

		if in_state_for() > 2.0:
			go(APPROACH)
		return

	if gap <= reach + 0.3 and absf(at.y - npc.position().y) < 2.0:
		halt()
		face(at - npc.position())
		b.anim = ZzZombieBody.Anim.ATTACK if swinging() else ZzZombieBody.Anim.IDLE

		if not swinging() and swing_at(victim):
			_last_hit_survivor = now()
		return

	var throwable := gap >= tune(&"rock_min", 9.0) and gap <= tune(&"rock_range", 40.0)
	var unreachable := absf(at.y - npc.position().y) > 1.8

	if cooled_down() and has_reacted() and (throwable or unreachable) \
			and clear_line(npc.position() + Vector3(0.0, 2.8, 0.0), at + Vector3(0.0, 1.2, 0.0)) \
			and (gap > 18.0 or unreachable or DotNpcAiNode.deterministic_unit(npc.instance_id, int(now())) < 0.02):
		_throw_target = victim
		_throw_at = now() + 1.5
		go(THROW)
		return

	go_to(at, speed, 1.6)
	b.anim = ZzZombieBody.Anim.RUN


## Overridden: a brute's hit lands on everybody in front of it, and throws them.
func _advance_swing() -> void:
	if not swinging():
		return

	var t := now() - _swing_at

	if not _swing_landed and t >= SWING_WINDUP * 1.6:
		_swing_landed = true
		var h := horde()
		var here := npc.position()
		var facing := npc.facing()

		for id in _survivors():
			var at := survivor_at(id)
			var to := at - here
			to.y = 0.0

			if to.length() > tune(&"reach", 2.4) + 0.6 or (to.length() > 0.4 and facing.dot(to.normalized()) < 0.2):
				continue

			if h != null:
				h.call(&"knock", id, here, tune(&"damage", 24.0), npc)
				_last_hit_survivor = now()

	if t >= (SWING_WINDUP + SWING_RECOVER) * 1.6:
		_swing_at = INF
		_next_swing = now() + maxf(tune(&"attack_interval", 1.45) - (SWING_WINDUP + SWING_RECOVER) * 1.6, 0.0)
