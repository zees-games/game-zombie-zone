extends RefCounted
## Where a resolved shot left its marks: the surface a round stopped on, both faces of every wall it
## went through, and each bounce. The authority works them out (a ZZ client never traces a shot; they
## resolve server-side) and the wire carries them as IMPACT; [method place] draws them.
## game-arena draws the same from its predicted shot (arena_presentation.gd, fx.spawn_penetration_decals).

## Marks one shot may send: a shotgun volley is a handful of pellets, not a wall of data.
const MAX_MARKS := 12
## A stop this close to the shot's full reach hit nothing (open air).
const MISS_SLACK := 0.05
const DECAL := &"bullet_hole"


## `[[point, normal], ...]` for [param shot] after the combat manager resolved it. [param world] is the
## physics world and [param mask] what a hole may be drawn on; the stop of each pellet is re-cast to
## find its surface normal and refused when it is a body rather than the map.
static func collect(shot: DotShot, world: World3D, mask: int) -> Array:
	var marks: Array = []

	for p in shot.penetrations:
		for side in [["entry", "entry_normal"], ["exit", "exit_normal"]]:
			var normal: Vector3 = p.get(side[1], Vector3.ZERO)
			if marks.size() < MAX_MARKS and p.has(side[0]) and normal.length_squared() >= 0.25:
				marks.append([p[side[0]] as Vector3, normal.normalized()])

	for r in shot.ricochets:
		var normal: Vector3 = r.get("normal", Vector3.ZERO)
		if marks.size() < MAX_MARKS and r.has("point") and normal.length_squared() >= 0.25:
			marks.append([r["point"] as Vector3, normal.normalized()])

	if world == null:
		return marks

	for end in shot.impacts:
		if marks.size() >= MAX_MARKS:
			break
		var along := end - shot.origin
		var length := along.length()
		if length < 0.01 or length >= shot.max_range - MISS_SLACK:
			continue
		var dir := along / length
		var query := PhysicsRayQueryParameters3D.create(end - dir * 0.15, end + dir * 0.15, mask)
		var found := world.direct_space_state.intersect_ray(query)
		if not found.is_empty():
			marks.append([found["position"] as Vector3, (found["normal"] as Vector3).normalized()])

	return marks


## Draws [param marks] (from [method collect], or off the wire) on [param fx]. Returns how many were placed.
static func place(fx: DotFxManager, marks: Array) -> int:
	if fx == null or fx.config == null or not fx.config.penetration_decals:
		return 0

	var placed := 0

	for mark in marks:
		var normal: Vector3 = mark[1]
		var up := Vector3.UP if absf(normal.y) < 0.99 else Vector3.RIGHT
		var at := Transform3D(Basis.looking_at(-normal, up), (mark[0] as Vector3) + normal * 0.05)
		if fx.spawn_decal(DECAL, at) != null:
			placed += 1

	return placed


## The effect definition [method place] spawns: a dark mark that lives until the decal ring retires it.
static func add_def(catalogue: DotFxCatalogue, scene_path: String) -> void:
	var d := DotFxDef.new()
	d.id = DECAL
	d.kind = DotFxDef.Kind.DECAL
	d.scene_path = scene_path
	d.lifetime_ms = 600000
	d.cost = 1
	d.priority = 20
	d.max_distance = 50.0
	d.min_quality = 1
	catalogue.add(d)
