extends RefCounted

## The game's own smoke and fire clouds (game/grenades/zz_grenade_cloud.gd), shown for hazards and grenades.

const SMOKE := 0
const FIRE := 1
const ZzGrenadeCloud := preload("grenades/zz_grenade_cloud.gd")


## Registers the cloud effects on [param catalogue].
static func add_defs(catalogue: DotFxCatalogue) -> void:
	ZzGrenadeCloud.add_defs(catalogue)


## The cloud node spawned on [param fx], or null when there is no effects layer.
static func show(fx: DotFxManager, tree: SceneTree, kind: int, at: Vector3, radius: float, seconds: float) -> Node:
	if fx == null:
		return null

	var info := {"fx": kind, "seconds": seconds, "radius": radius, "position": at, "victim": 0}
	return ZzGrenadeCloud.show(fx, tree, info, 0)
