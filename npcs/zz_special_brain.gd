extends "zz_zombie_brain.gd"

## What every special infected shares: it chooses its victim rather than taking whoever is
## nearest, approaches where it cannot be seen, backs off when it is losing, and claws when it is
## cornered with its ability spent.
##
## [b]A special is only frightening if it picks well.[/b] The obvious brain — run at the nearest
## survivor and use the ability in range — dies to the first person who turns round. So each one
## scores the team ([method choose_victim]): somebody alone is worth far more than somebody in a
## group, somebody looking the other way more than somebody facing it, and each kind adds what
## suits it (a spitter wants somebody who cannot move; a ram wants a straight line; a strangler
## wants the one at the back). And it approaches to a place the TEAM cannot see
## ([method hidden_spot_near]), not just the victim: a leaper that waits behind a car on the
## team's side of the street is a leaper that is shot before it jumps.
##
## [b]They work together without being told.[/b] Before using its ability a special asks whether
## the team is already busy ([method team_busy]): a mob on them, a teammate pinned, somebody
## down. If not, and its victim is not alone, it waits a few seconds out of sight for a better
## moment — which is how a strangler's pull lands in the middle of a mob, and how a leaper
## pounces on whoever went to help.

## Where it is in its approach.
const APPROACH := &"approach"
const WAIT := &"wait"
const RETREAT := &"retreat"
const CLAW := &"claw"

## Below this share of its health a special breaks off to come back later.
const RETREAT_HEALTH := 0.35

## Seconds it is willing to wait out of sight for the team to be busy.
const PATIENCE := 6.0

var victim: StringName = &""
var _hide_spot: Vector3 = Vector3.INF
var _hide_for: StringName = &""
var _hide_at_time: float = -INF
var _retreat_until: float = -1.0

## Its health when it last broke off hurt: it breaks off again only once hurt below that.
var _retreated_at_health: float = 1.0
var _cooldown_until: float = 0.0
var _waited_since: float = -1.0


func _build() -> void:
	var seed_id := npc.seed if npc != null else 0
	character = DotNpcAiCharacter.preset(&"hard").with_seed(seed_id)
	character.reaction_time = lerpf(0.2, 0.45, DotNpcAiNode.deterministic_unit(seed_id, 5011))
	character.view_turn_deg = 540.0
	character.memory_time = 20.0
	character.tactics = 0.9
	character.aggression = 0.7
	go(APPROACH)
	if npc != null:
		npc.sight_scale = 1.0


## The survivor this special should go for, or empty. Kinds add to the score with
## [method _victim_bonus]; lower is better.
func choose_victim() -> StringName:
	var h := horde()

	if h == null:
		return &""

	var best := &""
	var best_score := INF
	var here := npc.position()

	for id: StringName in h.call(&"survivor_ids"):
		if not _victim_allowed(id):
			continue

		var at: Vector3 = h.call(&"survivor_position", id)
		var score := here.distance_to(at)
		# Company is protection: every up survivor within eight metres adds twelve.
		score += 12.0 * float(int(h.call(&"survivors_near", at, 8.0, id)))
		score += _victim_bonus(id, at)

		# Sticking with a choice, so it does not dither between two equal ones.
		if id == victim:
			score -= 6.0

		if score < best_score:
			best_score = score
			best = id

	return best


## Whether [param id] can be this kind's victim at all. Up and unpinned, by default.
func _victim_allowed(id: StringName) -> bool:
	return survivor_is(id, &"up") and not survivor_is(id, &"pinned")


## A kind's own preference: negative is more attractive.
func _victim_bonus(_id: StringName, _at: Vector3) -> float:
	return 0.0


## Whether the team has its hands full: somebody pinned or down, or a mob running at them.
func team_busy() -> bool:
	var h := horde()

	if h == null:
		return false

	for id: StringName in h.call(&"survivor_ids"):
		if survivor_is(id, &"pinned") or survivor_is(id, &"down") or survivor_is(id, &"biled"):
			return true

	return bool(h.call(&"panicking")) or bool(h.call(&"mob_incoming"))


## Whether [param id] is alone: nobody else up within [param radius].
func is_alone(id: StringName, radius: float = 8.0) -> bool:
	var h := horde()
	var at := survivor_at(id)
	return h != null and at != Vector3.INF and int(h.call(&"survivors_near", at, radius, id)) == 0


## A navigable place within [param near]..[param far] of [param id] that no survivor can see,
## preferring the one closest to here. INF when there is none.
##
## Remembered for a couple of seconds, because asking the sight lines of thirty candidates is
## not something to do every tick.
func hidden_spot_near(id: StringName, near: float, far: float, need_line_to_victim: bool = false) -> Vector3:
	if _hide_for == id and now() - _hide_at_time < 2.0 and _hide_spot != Vector3.INF:
		return _hide_spot

	_hide_for = id
	_hide_at_time = now()
	_hide_spot = Vector3.INF

	var h := horde()
	var data := _nav_data()
	var at := survivor_at(id)

	if h == null or data == null or at == Vector3.INF:
		return Vector3.INF

	var candidates := data.points_within(at, far)
	var best_score := INF
	var here := npc.position()
	var eye := survivor_at(id) + Vector3(0.0, 1.5, 0.0)
	var tries := 0

	for index in candidates:
		var p := data.points[index]
		var gap := flat_distance(p, at)

		if gap < near:
			continue

		tries += 1
		if tries > 40:
			break

		var score := p.distance_to(here) + absf(gap - (near + far) * 0.5) * 0.5

		if score >= best_score:
			continue

		if need_line_to_victim:
			# Seen by the victim is the point (a tongue needs it); seen by anybody else is not.
			if not clear_line(p + Vector3(0.0, 1.6, 0.0), eye):
				continue
		elif bool(h.call(&"seen_by_survivors", p, 1.2)):
			continue

		best_score = score
		_hide_spot = p

	return _hide_spot


## Breaks off: runs from the nearest survivor until out of sight or [param seconds] pass.
func begin_retreat(seconds: float = 5.0) -> void:
	_retreat_until = now() + seconds
	go(RETREAT)


func retreating() -> bool:
	return state == RETREAT and now() < _retreat_until


func _retreat_step(speed: float) -> void:
	var nearest := Vector3.INF
	var here := npc.position()

	for id in _survivors():
		var at := survivor_at(id)
		if nearest == Vector3.INF or at.distance_to(here) < nearest.distance_to(here):
			nearest = at

	if nearest == Vector3.INF:
		go(APPROACH)
		return

	var away := here - nearest
	away.y = 0.0
	var goal := here + away.normalized() * 8.0
	var h := horde()
	if h != null:
		goal = h.call(&"snap_to_nav", goal)
	go_to(goal, speed, 1.0)
	body().anim = ZzZombieBody.Anim.RUN

	if now() >= _retreat_until or (h != null and not bool(h.call(&"seen_by_survivors", here, 1.2)) and in_state_for() > 1.5):
		go(APPROACH)


func _survivors() -> Array:
	var h := horde()
	return h.call(&"survivor_ids") if h != null else []


func cooled_down() -> bool:
	return now() >= _cooldown_until


func cool_down(seconds: float) -> void:
	_cooldown_until = now() + seconds


## Waits out of sight for the team to be busy, up to [constant PATIENCE]. True when it is time.
func ready_to_strike(target: StringName) -> bool:
	if team_busy() or is_alone(target):
		_waited_since = -1.0
		return true

	if _waited_since < 0.0:
		_waited_since = now()

	if now() - _waited_since >= PATIENCE:
		_waited_since = -1.0
		return true

	return false


## The default: retreat when hurt, claw when cornered, otherwise the kind's own [method _special].
func _decide(delta: float) -> void:
	var b := body()

	if retreating():
		_retreat_step(npc.def.move_speed)
		return

	if state == RETREAT:
		go(APPROACH)

	if horde() != null and horde().call(&"pinning", npc) != &"":
		_holding(delta)
		return

	# Hurt again since the last time, not merely still hurt. Checked on health alone, a hurt
	# special broke off, came back, and broke off again on its next thought, for ever: the
	# ballpark's waves went to overtime on screamers and leapers pressed against the outfield
	# wall (tools/survival_long_run --watch --detail).
	var health := npc.health_fraction()
	if health < RETREAT_HEALTH and health < _retreated_at_health - 0.05 and state != CLAW and _may_retreat():
		_retreated_at_health = health
		begin_retreat()
		return

	victim = choose_victim()

	if victim == &"":
		# Nobody it may take: whoever is nearest gets clawed, which is what a special with its
		# ability spent does in the genre.
		if not melee_chase(npc.def.move_speed):
			halt()
			b.anim = ZzZombieBody.Anim.IDLE
		return

	_special(delta)


## Whether this kind breaks off when hurt. The ram and the brute do not.
func _may_retreat() -> bool:
	return true


## The kind's own behaviour while free. Called with [member victim] chosen.
func _special(_delta: float) -> void:
	pass


## While it has hold of somebody.
func _holding(_delta: float) -> void:
	halt()
	body().anim = ZzZombieBody.Anim.PIN


## Told by the game that its hold was broken.
func pin_released(_victim: StringName, why: StringName) -> void:
	if why == &"shoved":
		cool_down(3.0)


## Close-range claws when its ability is spent and a survivor is on top of it.
func claw_if_close(speed: float, within: float = 2.5) -> bool:
	var near := &""

	for id in _survivors():
		if distance_to(id) <= within:
			near = id
			break

	if near == &"":
		return false

	forced = near
	var _fought := melee_chase(speed)
	forced = &""
	return true


## The ballistic launch from [param from] that lands on [param to] at about [param speed]
## horizontally. Clamped so it is a jump and not a flight.
static func launch_to(from: Vector3, to: Vector3, speed: float, gravity: float = 20.0) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var distance := flat.length()
	var t := maxf(distance / maxf(speed, 1.0), 0.2)
	var up := ((to.y - from.y) + 0.5 * gravity * t * t) / t
	return flat.normalized() * (distance / t) + Vector3(0.0, clampf(up, 2.0, 14.0), 0.0)


## Where [param id] will be in [param seconds], from their velocity as remembered.
func lead(id: StringName, seconds: float) -> Vector3:
	var at := survivor_at(id)
	var entry := memory.get_entry(id, now()) if memory != null else null

	if entry != null and at != Vector3.INF:
		return at + Vector3(entry.velocity.x, 0.0, entry.velocity.z) * seconds

	return at
