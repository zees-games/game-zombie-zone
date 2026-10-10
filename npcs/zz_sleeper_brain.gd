extends "zz_zombie_brain.gd"

## The sleeper: sits crying where the map put her. Leave her alone.
##
## [b]A meter, not a trigger.[/b] Every survivor near her fills it — more the closer they are,
## more if they are running, a lot more if they shoot near her — and it drains when nobody is.
## Full, she screams and goes for whoever filled it most, at a sprint, and one swipe puts them on
## the floor; then she keeps at them. Shooting her is an instant start, unless the shot kills
## her, which is the genre's other answer: one perfectly placed close-range shotgun blast.
##
## The meter is replicated as a flag at half full (`FLAG_STARTLED`), so a client can make her
## crying louder and her eyes brighter: the warning has to be on screen, or this is a trap and
## not a choice.

const SITTING := &"sitting"
const RISING := &"rising"
const HUNTING := &"hunting"
const FLEEING := &"fleeing"

var meter: float = 0.0
var _blame: Dictionary = {}
var _quarry: StringName = &""
var _quarry_down_at: float = -1.0


func _build() -> void:
	character = DotNpcAiCharacter.preset(&"hard").with_seed(npc.instance_id if npc != null else 0)
	character.reaction_time = 0.05
	character.view_turn_deg = 900.0
	go(SITTING)


func damaged(amount: float, by: StringName) -> void:
	super(amount, by)

	if state == SITTING or state == RISING:
		_blame[by] = float(_blame.get(by, 0.0)) + 1000.0
		meter = tune(&"startle_seconds", 3.0)


func stagger(_direction: Vector3, _seconds: float, _strength: float = 4.0) -> void:
	pass


func _decide(delta: float) -> void:
	var b := body()
	var full := tune(&"startle_seconds", 3.0)

	match state:
		SITTING:
			halt()
			b.anim = ZzZombieBody.Anim.CRY
			_fill(delta)
			b.set_flag(ZzZombieBody.FLAG_STARTLED, meter > full * 0.5)

			if meter >= full:
				_quarry = _most_blamed()
				go(RISING)

		RISING:
			halt()
			b.anim = ZzZombieBody.Anim.RAGE
			b.set_flag(ZzZombieBody.FLAG_STARTLED, true)
			face(survivor_at(_quarry) - npc.position())

			if in_state_for() > 1.0:
				go(HUNTING)

		HUNTING:
			if not survivor_is(_quarry, &"alive"):
				go(FLEEING)
				return

			forced = _quarry
			var _fought := melee_chase(npc.def.move_speed)

			if survivor_is(_quarry, &"down"):
				if _quarry_down_at < 0.0:
					_quarry_down_at = now()

				# A few more on the floor, then she is done with them.
				if now() - _quarry_down_at > 4.0:
					go(FLEEING)

		FLEEING:
			forced = &""
			var away := npc.position() - survivor_at(_quarry) if survivor_at(_quarry) != Vector3.INF else npc.facing()
			away.y = 0.0
			go_to(horde().call(&"snap_to_nav", npc.position() + away.normalized() * 10.0), npc.def.move_speed, 1.0)
			b.anim = ZzZombieBody.Anim.RUN

			if in_state_for() > tune(&"flee_seconds", 10.0):
				horde().spawner.remove(npc.instance_id, &"reclaimed")


func _fill(delta: float) -> void:
	var near := tune(&"startle_near", 7.0)
	var any := false
	var h := horde()

	if h == null:
		return

	for id: StringName in h.call(&"survivor_ids"):
		var gap := distance_to(id)

		if gap > near:
			continue

		any = true
		var player = h.game.player_by_id(id)
		var running: bool = player != null and player.controller.state.horizontal_speed() > 3.5
		var rate := (1.0 - gap / near) * (1.8 if running else 1.0) * 1.3
		meter += rate * delta
		_blame[id] = float(_blame.get(id, 0.0)) + rate * delta

	if context.conditions.has(DotNpcAiConditions.HEAR_COMBAT):
		var heard := last_known_position()
		if heard != Vector3.INF and heard.distance_to(npc.position()) < 12.0:
			meter += 0.6 * delta * 4.0

	if not any:
		meter = maxf(meter - delta * 0.4, 0.0)


func _most_blamed() -> StringName:
	var best := &""
	var most := -1.0

	for id: StringName in _blame:
		if float(_blame[id]) > most and survivor_is(id, &"alive"):
			most = float(_blame[id])
			best = id

	if best == &"":
		for id in horde().call(&"survivor_ids"):
			return id

	return best


func describe() -> Dictionary:
	var out := super.describe()
	out["meter"] = "%.1f" % meter
	out["quarry"] = String(_quarry)
	return out
