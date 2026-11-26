extends RefCounted
## Prunes a landed graph on a worker thread, then builds its [ZzNavGraph] and what the horde derives from it there too,
## so the main thread only takes the result in. Asked a slice a tick on the main thread ([ZzNavPruneWarm]) the prune's
## eight million capsule queries still held single ticks of 0.4 to 18 s on a loaded box (gm_balkans, headless_nav_stall).
##
## They ask a private physics space that nothing steps, holding copies of the world's bodies on the prune's mask as they
## stood when [method begin] ran (a prop that moves afterward is pruned where it stood), so the worker never reads the
## space the main thread steps. The answers are the ones [ZzNavPrune] gets on the main thread: the same shapes at the
## same places, with the passable bodies left out of the copy instead of excluded from each query.
## `zz_nav_prune_thread` 0, or a build with no worker, prunes on the main thread in slices as before.

const ZzNavPrune := preload("zz_nav_prune.gd")
const ZzNavJob := preload("zz_nav_job.gd")
const _Self := preload("zz_nav_prune_thread.gd")

## Milliseconds the worker took over the prune and the cache write.
var prune_ms := 0.0
## Milliseconds the main thread took to copy the world's bodies.
var copy_ms := 0.0
## Bodies copied into the private space.
var bodies := 0

var _report := {}
var _space := RID()
var _copies: Array[RID] = []
var _task := -1


## Whether [param data] still needs the world's collision asked of it for [param version]; false with no world to ask.
static func needs(game: Variant, data: GSNpcNavData, version: int) -> bool:
	return data != null and int(data.meta.get("pruned", 0)) < version and game != null and game.physics != null and game.is_inside_tree()


## Main thread: starts pruning the landed graph of [param job] on a worker, or returns null where the main thread must
## (the job builds no graph off the frame, or nothing needs pruning). [param required] is `func() -> PackedVector3Array`,
## the spots a body must still reach.
static func begin(game: Variant, job: ZzNavJob, required: Callable, version: int) -> RefCounted:
	if not job.make_graph.is_valid() or not needs(game, job.nav, version):
		return null

	var mech: Variant = game.map.mechanics if game.map != null else null
	var ladders: Array[AABB] = []
	var passable: Array[RID] = []

	# What a zombie body collides with, less the boards it must reach (the mechanics' walk-through bodies): a hull clip
	# ceiling or solid prop that no document box describes otherwise stays on the graph and wedges bodies under it.
	if mech != null:
		ladders = mech.ladder_boxes()
		passable = mech.walk_through_bodies()

	var out: _Self = _Self.new()
	out._start(job, game.get_world_3d(), game.get_tree().root, ZzNavPrune.body_mask(game.physics), ladders, required.call(), passable, version)
	return out


# Copies the bodies of [param world] on [param mask] (less [param passable]) found under [param root] into a private
# space, and starts the worker; the pruned graph's [ZzNavGraph] lands in [member ZzNavJob.graph] by
# [member ZzNavJob.make_graph], and the cache is rewritten pruned to [param version].
func _start(job: ZzNavJob, world: World3D, root: Node, mask: int, ladders: Array[AABB], required: PackedVector3Array, passable: Array[RID], version: int) -> void:
	var state := _copy_world(world, root, mask, passable)
	_task = WorkerThreadPool.add_task(_run.bind(job, state, mask, ladders, required, version), false, "zz nav prune")


func _copy_world(world: World3D, root: Node, mask: int, passable: Array[RID]) -> PhysicsDirectSpaceState3D:
	var lap := Time.get_ticks_usec()
	_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(_space, false)
	var skip := {}

	for rid in passable:
		skip[rid] = true

	for node: Node in root.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D

		# A body in another world, out of the tree or disabled is in no space or another one.
		if body is Area3D or body.collision_layer & mask == 0 or skip.has(body.get_rid()) or PhysicsServer3D.body_get_space(body.get_rid()) != world.space:
			continue

		_copy(body)

	bodies = _copies.size()
	copy_ms = (Time.get_ticks_usec() - lap) / 1000.0
	return PhysicsServer3D.space_get_direct_state(_space)


## Whether the worker is done; [method finish] then takes none of the main thread's time.
func done() -> bool:
	return _task < 0 or WorkerThreadPool.is_task_completed(_task)


## Main thread: waits for the worker (no wait once [method done]), frees the private space, logs what was dropped and
## puts the timings in [param sections] (`nav_prune_copy`, `nav_prune_thread` ms, `nav_prune_bodies`).
func finish(sections: Dictionary) -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

	for rid in _copies:
		PhysicsServer3D.free_rid(rid)

	_copies.clear()

	if _space.is_valid():
		PhysicsServer3D.free_rid(_space)
		_space = RID()

	ZzNavPrune.log_report(_report)
	sections.merge({&"nav_prune_copy": copy_ms, &"nav_prune_thread": prune_ms, &"nav_prune_bodies": float(bodies)}, true)


func _copy(from: CollisionObject3D) -> void:
	var rid := from.get_rid()
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(body, from.collision_layer)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM))

	for owner_id in from.get_shape_owners():
		if from.is_shape_owner_disabled(owner_id):
			continue

		var at := from.shape_owner_get_transform(owner_id)

		for i in from.shape_owner_get_shape_count(owner_id):
			PhysicsServer3D.body_add_shape(body, from.shape_owner_get_shape(owner_id, i).get_rid(), at)

	PhysicsServer3D.body_set_space(body, _space)
	_copies.append(body)


func _run(job: ZzNavJob, state: PhysicsDirectSpaceState3D, mask: int, ladders: Array[AABB], required: PackedVector3Array, version: int) -> void:
	var lap := Time.get_ticks_usec()
	var nav := job.nav
	var none: Array[RID] = []
	var _dropped := ZzNavPrune.run(nav, state, mask, ladders, required, none, _report)
	nav.meta["pruned"] = version
	job.write(nav)
	prune_ms = (Time.get_ticks_usec() - lap) / 1000.0

	if job.make_graph.is_valid():
		job.graph = job.make_graph.call(nav)

	# The links' ladder rays ask the private copy too.
	if job.graph != null and job.derive.is_valid():
		job.derived = job.derive.call(nav, job.graph, state, mask)
