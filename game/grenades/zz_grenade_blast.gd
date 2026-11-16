extends RefCounted

## Zombie Zone's own copy (2026-11-16) of the grenade code first written for fc-weapons: the game depends on no FC addon.

const ZzGrenade := preload("zz_grenade.gd")

## What a grenade does when it goes off, as plain events for the host to apply and show.
## Damage is [method DotShot.splash_at]'s linear falloff; a victim behind cover (the [code]los[/code]
## callable returns false) takes nothing.

## [param victims] are `{id, position, eye, forward}`; [param los] is `(from, to) -> bool` for clear sight.
static func detonate(g: ZzGrenade, def: DotWeaponDef, victims: Array, los: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var b := def.tuning as DotWeaponBallistics
	var radius := float(def.params.get(&"effect_radius", b.splash_radius if b != null else 0.0))
	var at := g.position
	out.append({"event": "detonated", "kind": String(g.kind), "position": at, "radius": radius})

	match g.kind:
		ZzGrenade.SMOKE:
			out.append({"event": "smoke", "position": at, "radius": radius, "seconds": g.rules.smoke_seconds})
		ZzGrenade.FIRE:
			out.append({"event": "fire", "position": at, "radius": radius, "seconds": g.rules.fire_seconds, "dps": g.rules.fire_dps, "owner": g.owner_entity})

	for v: Dictionary in victims:
		var id := int(v["id"])
		var d := at.distance_to(v["position"])
		if d >= radius or not los.call(at, v["eye"]):
			continue
		if g.kind == ZzGrenade.FLASH:
			var facing := maxf(0.0, (v["forward"] as Vector3).dot((at - (v["eye"] as Vector3)).normalized()))
			var strength := (1.0 - d / radius) * facing
			var seconds := g.rules.flash_seconds * strength
			if seconds > 0.0:
				out.append({"event": "blind", "victim": id, "seconds": seconds, "strength": strength})
		elif b != null and b.splash_damage > 0.0:
			if id == g.owner_entity and not b.splash_hurts_owner:
				continue
			var shot := DotShot.make(def.id, g.owner_entity, g.spawn.tick, 0)
			shot.splash_radius = b.splash_radius
			shot.splash_damage = b.splash_damage
			var dmg := shot.splash_at(d)
			if dmg > 0.0:
				out.append({"event": "damage", "victim": id, "damage": dmg, "type": b.damage_type})
	return out
