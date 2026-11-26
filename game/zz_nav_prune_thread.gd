extends RefCounted
## Prunes a landed graph on a worker thread, then builds its [ZzNavGraph] there too, so the main thread only takes the
## result in. The prune's capsule queries were 36 s of one main-thread tick on rp_asheville with a cold cache.
##
## They ask a private physics space that nothing steps, holding copies of the world's bodies on the prune's mask as they
## stood when [method advance] copied them (a prop that moves afterward is pruned where it stood), so the worker never
## reads the space the main thread steps. The copy itself is sliced over ticks by [method advance]'s budget: one tick of
## it was 0.55 to 0.8 s on gm_balkans on a loaded box (headless_nav_stall). The answers are the ones [ZzNavPrune] gets
## on the main thread: the same shapes at the same places, with the passable bodies left out of the copy instead of
## excluded from each query.
## `zz_nav_prune_thread` 0 prunes on the main thread as before.

const ZzNavPrune := preload("zz_nav_prune.gd")
const ZzNavJob := preload("zz_nav_job.gd")
const _Self := preload("zz_nav_prune_thread.gd")

## Milliseconds the worker took over the prune and the cache write.
var prune_ms := 0.0
## Milliseconds the main thread took to copy the world's bodies, over every slice.
var copy_ms := 0.0
## Bodies copied into the private space.
var bodies := 0

## Set by `tools/cold_start.gd --prune-parity`: keeps the graph a worker prune started from and the one it ended with,
## and each copied body's transform at the copy, so the result can be checked against a main-thread prune.
static var parity := false
static var parity_before: GSNpcNavData = null
static var parity_after: GSNpcNavData = null
static var parity_bodies := {}

var _report := {}
var _space := RID()
var _copies: Array[RID] = []
var _task := -1
var _record := false
# The bodies still to copy, the world space they must still be in, the prune's mask, the passable bodies by RID, and the
# worker's call, started once the copy is whole (null after).
var _pending: Array[Node] = []
var _world_space := RID()
var _mask := 0
var _skip := {}
var _run_task := Callable()


## Whether [param data] still needs the world's collision asked of it for [param version]; false with no world to ask.
static func needs(game: Variant, data: GSNpcNavData, version: int) -> bool:
	return int(data.meta.get("pruned", 0)) < version and game != null and game.physics != null and game.is_inside_tree()


## Prunes [param data] on the main thread and rewrites the cache of [param job]: no worker, or `zz_nav_prune_thread` 0.
## [param required] is `func() -> PackedVector3Array`, the spots a body must still reach.
static func on_main(game: Variant, data: GSNpcNavData, job: ZzNavJob, required: Callable, version: int) -> void:
	if not needs(game, data, version):
		return

	var mech: Variant = _mechanics(game)
	var _dropped := ZzNavPrune.apply(data, game.get_world_3d().direct_space_state, ZzNavPrune.body_mask(game.physics), _ladders(mech), required.call(), _passable(mech))
	data.meta["pruned"] = version
	job.save(data)


## Main thread: starts pruning the landed graph of [param job] on a worker, or returns null where [method on_main] must
## (the job builds no graph off the frame, or nothing needs pruning). [param required] as [method on_main].
static func begin(game: Variant, job: ZzNavJob, required: Callable, version: int) -> RefCounted:
	if not job.make_graph.is_valid() or not needs(game, job.nav, version):
		return null

	var mech: Variant = _mechanics(game)
	var out: _Self = _Self.new()
	out._start(job, game.get_world_3d(), game.get_tree().root, ZzNavPrune.body_mask(game.physics), _ladders(mech), required.call(), _passable(mech), version)
	return out


# What a zombie body collides with, less the boards it must reach (the mechanics' walk-through bodies): a hull clip
# ceiling or solid prop that no document box describes otherwise stays on the graph and wedges bodies under it.
static func _mechanics(game: Variant) -> Variant:
	return game.map.mechanics if game.map != null else null


static func _ladders(mech: Variant) -> Array[AABB]:
	var out: Array[AABB] = []
	return mech.ladder_boxes() if mech != null else out


static func _passable(mech: Variant) -> Array[RID]:
	var out: Array[RID] = []
	return mech.walk_through_bodies() if mech != null else out


# Lists the bodies of [param world] on [param mask] (less [param passable]) found under [param root] for [method advance]
# to copy into a private space, then start the worker on; the pruned graph's [ZzNavGraph] lands in [member ZzNavJob.graph] by
# [member ZzNavJob.make_graph], and the cache is rewritten pruned to [param version].
func _start(job: ZzNavJob, world: World3D, root: Node, mask: int, ladders: Array[AABB], required: PackedVector3Array, passable: Array[RID], version: int) -> void:
	if parity:
		parity_before = job.nav.duplicate(true)
		parity_bodies.clear()
		_record = true

	_open(world, root, mask, passable)
	_run_task = _run.bind(job, PhysicsServer3D.space_get_direct_state(_space), mask, ladders, required, version)


## Main thread, once a tick: copies bodies for up to [param budget_ms], starts the worker once the copy is whole, and
## says whether the worker is done.
func advance(budget_ms: float) -> bool:
	if _run_task.is_valid() and _copy_some(budget_ms):
		_task = WorkerThreadPool.add_task(_run_task, false, "zz nav prune")
		_run_task = Callable()

	return done()


## Main thread: the same copy and prune with no worker, then [method finish]; `--prune-parity` compares it.
func run_here(nav: GSNpcNavData, world: World3D, root: Node, mask: int, ladders: Array[AABB], required: PackedVector3Array, passable: Array[RID]) -> void:
	var none: Array[RID] = []
	_open(world, root, mask, passable)
	var _copied := _copy_some(INF)
	var _dropped := ZzNavPrune.run(nav, PhysicsServer3D.space_get_direct_state(_space), mask, ladders, required, none, _report)
	finish({})


func _open(world: World3D, root: Node, mask: int, passable: Array[RID]) -> void:
	var lap := Time.get_ticks_usec()
	_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(_space, false)
	_world_space = world.space
	_mask = mask

	for rid in passable:
		_skip[rid] = true

	_pending = root.find_children("*", "CollisionObject3D", true, false)
	_pending.reverse()
	copy_ms += (Time.get_ticks_usec() - lap) / 1000.0


# Copies listed bodies until [param budget_ms] is spent; true once none is left.
func _copy_some(budget_ms: float) -> bool:
	var lap := Time.get_ticks_usec()
	var until := lap + int(minf(budget_ms, 1.0e9) * 1000.0)

	while not _pending.is_empty() and Time.get_ticks_usec() < until:
		var node: Variant = _pending.pop_back()

		# Freed since it was listed, in another world, out of the tree or disabled: in no space or another one.
		if not is_instance_valid(node):
			continue

		var body := node as CollisionObject3D

		if body is Area3D or body.collision_layer & _mask == 0 or _skip.has(body.get_rid()) or PhysicsServer3D.body_get_space(body.get_rid()) != _world_space:
			continue

		_copy(body)

	bodies = _copies.size()
	copy_ms += (Time.get_ticks_usec() - lap) / 1000.0
	return _pending.is_empty()


## Whether the worker is done; [method finish] then takes none of the main thread's time.
func done() -> bool:
	return not _run_task.is_valid() and (_task < 0 or WorkerThreadPool.is_task_completed(_task))


## Main thread: waits for the worker (no wait once [method done]; none started if the copy never finished), frees the
## private space, logs what was dropped and puts the timings in [param sections] (`nav_prune_copy`, `nav_prune_thread` ms, `nav_prune_bodies`).
func finish(sections: Dictionary) -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

	for rid in _copies:
		PhysicsServer3D.free_rid(rid)

	_copies.clear()
	_pending.clear()
	_run_task = Callable()

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

	if _record:
		parity_bodies[from] = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)


func _run(job: ZzNavJob, state: PhysicsDirectSpaceState3D, mask: int, ladders: Array[AABB], required: PackedVector3Array, version: int) -> void:
	var lap := Time.get_ticks_usec()
	var nav := job.nav
	var none: Array[RID] = []
	var _dropped := ZzNavPrune.run(nav, state, mask, ladders, required, none, _report)
	nav.meta["pruned"] = version

	if parity:
		parity_after = nav.duplicate(true)

	job.write(nav)
	prune_ms = (Time.get_ticks_usec() - lap) / 1000.0

	if job.make_graph.is_valid():
		job.graph = job.make_graph.call(nav)

	# The links' ladder rays ask the private copy too.
	if job.derive.is_valid():
		job.derived = job.derive.call(nav, job.graph, state, mask)
