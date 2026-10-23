extends DotFxBlood
## Blood on the surface behind a body somebody hit. The shooter casts it from their own HIT; everybody
## else gets the server's SPLAT (point and normal), so a client without that event just sees fewer decals.


## A player or NPC took a hit at [param point], seen from [param from]: blood behind it. Null for any other victim.
func on_body_hit(victim: int, point: Vector3, from: Vector3, reach: float = 4.0) -> Node3D:
	var kind := DotEntity.kind_of(victim)
	if kind != DotEntity.KIND_PLAYER and kind != DotEntity.KIND_NPC:
		return null
	return splat_behind(from, point, reach)
