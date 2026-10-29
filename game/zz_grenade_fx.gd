class_name ZzGrenadeFx
extends RefCounted

## arena-weapons' smoke and fire clouds, reached by path because the pack is optional (no pack: no cloud).

const SMOKE := 0
const FIRE := 1
const _PATHS := preload("zz_paths.gd")
const SCRIPT := "res://addons/arena_weapons/aw_grenade_fx.gd"


## The pack's AwGrenadeFx script, or null when it is not mounted.
static func script() -> GDScript:
	var path: String = _PATHS.rebase(SCRIPT)
	return load(path) as GDScript if ResourceLoader.exists(path) else null


## The cloud node spawned on [param fx], or null (no pack, no effects layer).
static func show(fx: DotFxManager, tree: SceneTree, kind: int, at: Vector3, radius: float, seconds: float) -> Node:
	var aw := script()

	if aw == null or fx == null:
		return null

	var info := {"fx": kind, "seconds": seconds, "radius": radius, "position": at, "victim": 0}
	return aw.call(&"show", fx, tree, info, 0) as Node
