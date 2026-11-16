extends RefCounted

## Zombie Zone's own copy (2026-11-16) of the grenade code first written for fc-weapons: the game depends on no FC addon.

const ZzGrenade := preload("zz_grenade.gd")
const ZzGrenadeRules := preload("zz_grenade_rules.gd")

## One thrown grenade, stepped by the server a tick at a time: gravity, bounce, stick, fuse.
## Pure data in, data out, so a host flies it in its own world through the [code]trace[/code] callable.

const FRAG := &"frag"
const FLASH := &"flash"
const SMOKE := &"smoke"
const FIRE := &"incendiary"

var kind: StringName = FRAG
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var fuse: int = 0
var owner_entity: int = 0
var spawn: DotWeaponSpawn = null
var stuck := false
var gravity: float = 9.8
var explode_on_impact := false
var sticks := false
var bounces := 0
var rules: ZzGrenadeRules = null


## [param def] supplies the kind and flags; a spawn from DotWeaponThrown carries the fuse left after cooking.
static func from_spawn(s: DotWeaponSpawn, def: DotWeaponDef, p_rules: ZzGrenadeRules = null) -> ZzGrenade:
	var g := ZzGrenade.new()
	g.spawn = s
	g.rules = p_rules if p_rules != null else ZzGrenadeRules.new()
	g.kind = StringName(def.params.get(&"kind", FRAG))
	g.explode_on_impact = bool(def.params.get(&"explode_on_impact", false))
	g.sticks = bool(def.params.get(&"sticks", false))
	g.position = s.origin
	g.velocity = s.velocity
	g.fuse = s.fuse_ticks
	g.owner_entity = s.owner_entity
	g.gravity = 9.8 * s.gravity_scale
	return g


## True once it went off. [param trace] is `(from, to) -> {}` for clear air or `{position, normal}` for a hit.
func step(trace: Callable, tick_rate: int) -> bool:
	if fuse <= 0 and spawn.velocity == Vector3.ZERO:
		return true
	var dt := 1.0 / float(tick_rate)
	fuse -= 1

	if not stuck:
		velocity.y -= gravity * dt
		velocity *= damp_factor(rules, dt)
		var to := position + velocity * dt
		var hit: Dictionary = trace.call(position, to)
		if hit.is_empty():
			position = to
		else:
			position = hit["position"]
			bounces += 1
			if explode_on_impact:
				return true
			if sticks:
				stuck = true
				velocity = Vector3.ZERO
			else:
				_bounce(hit["normal"])

	return fuse <= 0


func _bounce(normal: Vector3) -> void:
	velocity = bounce_velocity(velocity, normal, rules)
	position += normal * 0.02
	if settles(velocity, bounces, rules):
		velocity = Vector3.ZERO


## The velocity off a surface with [param normal]: [member ZzGrenadeRules.bounce] of the speed into it comes back,
## [member ZzGrenadeRules.friction] of the speed along it stays. A host flying grenades itself shares this.
static func bounce_velocity(v: Vector3, normal: Vector3, r: ZzGrenadeRules) -> Vector3:
	var into := normal * v.dot(normal)
	return (v - into) * r.friction - into * r.bounce


## Whether a grenade that bounced [param count] times and now moves at [param v] should stop dead.
static func settles(v: Vector3, count: int, r: ZzGrenadeRules) -> bool:
	return v.length() < r.rest_speed or (r.max_bounces >= 1.0 and count >= int(r.max_bounces))


## Velocity multiplier for [param dt] seconds of air drag at [member ZzGrenadeRules.damping].
static func damp_factor(r: ZzGrenadeRules, dt: float) -> float:
	return exp(-r.damping * dt)
