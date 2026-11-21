extends RefCounted

## Zombie Zone's own copy (2026-11-16) of the grenade code first written for fc-weapons: the game depends on no FC addon.

const ZzGrenade := preload("zz_grenade.gd")
const ZzGrenadeRules := preload("zz_grenade_rules.gd")
const ZzGrenadeBlast := preload("zz_grenade_blast.gd")
const ZzBlindLedger := preload("zz_blind_ledger.gd")

## Server glue for flash, smoke and incendiary grenades, driven by the host: [method detonate] when one goes off,
## [method tick] once per game tick. The game plugs in its combat through callables, so none of its classes appear here.

## What an [signal effect] shows. Wire values, so only ever appended to.
enum Fx { SMOKE, FIRE, BLIND }

## Seconds between a fire zone's damage pulses.
const FIRE_PULSE := 0.5
## How far above or below a fire's origin a body still stands in it.
const FIRE_HEIGHT := 2.0
const FIRE_TYPE := &"fire"
const UTILITY_KINDS: Array[StringName] = [&"flash", &"smoke", &"incendiary"]

## `{fx, position, radius, seconds, victim}`: for the host to send and an offline client to show.
signal effect(info: Dictionary)

var rules: ZzGrenadeRules = ZzGrenadeRules.new()
var ledger := ZzBlindLedger.new()
## `() -> Array` of `{id, position, eye, forward}` for everyone who can be hurt or blinded.
var victims: Callable = Callable()
## `(from, to) -> bool`, true when sight is clear; see [method los_from_ray].
var los: Callable = Callable()
## `(attacker, victim, amount, type: Variant, weapon) -> void`: the host's damage rules (friendly fire, armour) run inside.
var damage: Callable = Callable()
## Whether "damage" events of a blast go through [member damage] too. Off when the host's projectile layer already did them.
var apply_blast_damage := false

var _fires: Array[Dictionary] = []
var _smokes: Array[Dictionary] = []


## The loadout ids of the utility weapons in [param defs], whatever the pack calls them.
static func utility_ids(defs: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for def: GSWeaponDef in defs:
		if is_utility(def):
			out.append(def.id)
	return out


static func is_utility(def: GSWeaponDef) -> bool:
	return def != null and UTILITY_KINDS.has(StringName(def.params.get(&"kind", &"")))


## One `victims` row.
static func victim(id: int, feet: Vector3, eye: Vector3, forward: Vector3) -> Dictionary:
	return {"id": id, "position": feet, "eye": eye, "forward": forward}


## Turns a host ray test into a `los` callable. [param blocked] is `(from, direction, distance) -> bool`, true when world geometry is hit.
static func los_from_ray(blocked: Callable) -> Callable:
	return func(from: Vector3, to: Vector3) -> bool:
		var offset := to - from
		var dist := offset.length()
		return dist <= 0.0 or not bool(blocked.call(from, offset / dist, dist))


## Resolves a utility grenade that went off at its position; returns the blast's events for the host to use further.
func detonate(g: ZzGrenade, def: GSWeaponDef) -> Array[Dictionary]:
	var out := ZzGrenadeBlast.detonate(g, def, victims.call() if victims.is_valid() else [], los if los.is_valid() else _open)
	var at := g.position
	for ev in out:
		match String(ev["event"]):
			"blind":
				var left := ledger.blind(int(ev["victim"]), float(ev["seconds"]), float(ev["strength"]))
				_emit(Fx.BLIND, at, 0.0, left, int(ev["victim"]), ledger.strength(int(ev["victim"])))
			"smoke":
				_smokes.append({"left": float(ev["seconds"])})
				_emit(Fx.SMOKE, at, float(ev["radius"]), float(ev["seconds"]), 0)
			"fire":
				_fires.append({
					"position": at, "radius": float(ev["radius"]), "left": float(ev["seconds"]),
					"dps": float(ev["dps"]), "owner": int(ev["owner"]), "pulse": 0.0,
				})
				_emit(Fx.FIRE, at, float(ev["radius"]), float(ev["seconds"]), 0)
			"damage":
				if apply_blast_damage and damage.is_valid():
					damage.call(g.owner_entity, int(ev["victim"]), float(ev["damage"]), ev["type"], def.id)
	return out


## Once per game tick, server side.
func tick(delta: float) -> void:
	ledger.tick(delta)

	for i in range(_smokes.size() - 1, -1, -1):
		_smokes[i]["left"] = float(_smokes[i]["left"]) - delta
		if float(_smokes[i]["left"]) <= 0.0:
			_smokes.remove_at(i)

	for i in range(_fires.size() - 1, -1, -1):
		var zone := _fires[i]
		zone["left"] = float(zone["left"]) - delta
		zone["pulse"] = float(zone["pulse"]) - delta
		if float(zone["pulse"]) <= 0.0:
			zone["pulse"] = FIRE_PULSE
			_burn(zone)
		if float(zone["left"]) <= 0.0:
			_fires.remove_at(i)


func active_fires() -> int:
	return _fires.size()


func active_smokes() -> int:
	return _smokes.size()


func clear() -> void:
	_fires.clear()
	_smokes.clear()
	ledger.clear()


func describe() -> Dictionary:
	return {"fires": _fires.size(), "smokes": _smokes.size(), "blinded": ledger.count()}


## Each pulse is damage as the thrower, so the host's rules decide who it hurts.
func _burn(zone: Dictionary) -> void:
	if not damage.is_valid() or not victims.is_valid():
		return
	var at: Vector3 = zone["position"]
	for v: Dictionary in victims.call():
		var feet: Vector3 = v["position"]
		if Vector2(feet.x - at.x, feet.z - at.z).length() >= float(zone["radius"]) or absf(feet.y - at.y) > FIRE_HEIGHT:
			continue
		damage.call(int(zone["owner"]), int(v["id"]), float(zone["dps"]) * FIRE_PULSE, FIRE_TYPE, &"")


func _open(_from: Vector3, _to: Vector3) -> bool:
	return true


func _emit(fx: int, at: Vector3, radius: float, seconds: float, victim_id: int, strength: float = 1.0) -> void:
	effect.emit({"fx": fx, "position": at, "radius": radius, "seconds": seconds, "victim": victim_id, "strength": strength})
