extends RefCounted

## One map's navigation graph being built without stalling the game: the strict build, the looser
## one when links were dropped, and the reach check that picks between them (see
## `ZzNpcs.nav_for`), plus the disk cache. Pure arithmetic on copies of the map document, so a
## worker thread can run it; on a platform without threads the main thread calls [method advance]
## once a frame with a millisecond budget instead.
##
## The recipe comes in as Callables so this file does not name `ZzNpcs` (which names this one).

const CHANNEL := "zz.nav"

enum Step { CACHE, STRICT, KEPT, REACH_KEPT, TRY, SAVE, DONE }

## Builds a configured, not yet begun builder: `(heights: Array, info: Dictionary) -> DotNpcNavBuilder`.
var make_builder: Callable
## `(nav: DotNpcNavData) -> Vector2i`: posts and ground joined to the first spawn.
var reach: Callable
var map_id: StringName = &""
var digest := ""
## Where the finished graph is kept, "" for nowhere; and the heights the strict pass tests links at.
var cache_path := ""
var strict_heights: Array = []
## Worker tasks the builder's edge and cover passes may use when this runs on a thread.
var workers := 1
## The graph, once [method is_done].
var nav: DotNpcNavData = null
## Whether the graph came off the disk.
var from_cache := false

var _step := Step.CACHE
var _builder: DotNpcNavBuilder = null
var _strict: DotNpcNavData = null
var _kept: DotNpcNavData = null
var _kept_reach := Vector2i.ZERO
var _try := 0
var _info := {}
var _builds_expected := 1
var _builds_done := 0
var _reports := {}
var _save_error := 0
var _lock := Mutex.new()
var _task := -1
var _finished := false
var _cancelled := false
var _shown := 0.0
var _stage_name := "preparing"


## Runs to the end on this thread. What a suite and a tool use.
func run_blocking() -> DotNpcNavData:
	while not advance(0.0):
		pass

	return nav


## Starts the whole build on a [WorkerThreadPool] task; poll [method advance] for the end.
func start_thread() -> void:
	_task = WorkerThreadPool.add_task(_run_thread, false, "zz navigation")


func _run_thread() -> void:
	while not _cancelled and not step(0.0):
		pass

	_lock.lock()
	_finished = true
	_lock.unlock()


## Main thread, once a frame: true when the graph is ready (or the build was given up). With a
## thread running it only looks; without one it works for [param budget_ms].
func advance(budget_ms: float) -> bool:
	if _task >= 0:
		_lock.lock()
		var ended := _finished
		_lock.unlock()

		if ended:
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1

		return ended and _step == Step.DONE

	return step(budget_ms)


func is_done() -> bool:
	return _step == Step.DONE


## Stops a build in progress and waits for its thread. The graph stays null.
func cancel() -> void:
	_cancelled = true
	_lock.lock()
	var builder := _builder
	_lock.unlock()

	if builder != null:
		builder.cancel()

	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## 0 to 1, never going back; the name of the pass is in [method stage]. Any thread.
func progress() -> float:
	if _step == Step.DONE:
		return 1.0

	_lock.lock()
	var builder := _builder
	var expected := _builds_expected
	var done := _builds_done
	_lock.unlock()
	var inner := builder.progress() if builder != null else 0.0
	_shown = maxf(_shown, minf((float(done) + inner) / float(maxi(expected, 1)), 0.999))
	return _shown


func stage() -> String:
	_lock.lock()
	var builder := _builder
	_lock.unlock()
	return builder.stage() if builder != null else _stage_name


## Works for about [param budget_ms] (0 = to the end); true when finished.
func step(budget_ms: float) -> bool:
	var deadline := Time.get_ticks_usec() + int(budget_ms * 1000.0) if budget_ms > 0.0 else -1

	while _step != Step.DONE:
		if _cancelled:
			return false

		match _step:
			Step.CACHE:
				_do_cache()
			Step.STRICT:
				if _drive(strict_heights, deadline):
					_strict = _builder.result()
					_after_build()
					_step = Step.SAVE if int(_info["rejected"]) == 0 else Step.KEPT
					if _step == Step.SAVE:
						nav = _strict
			Step.KEPT:
				if _drive([], deadline):
					_kept = _builder.result()
					_after_build()
					_step = Step.REACH_KEPT
			Step.REACH_KEPT:
				_kept_reach = reach.call(_kept)
				_step = Step.TRY
			Step.TRY:
				_do_try(deadline)
			Step.SAVE:
				_do_save()
				_stage_name = "done"
				_step = Step.DONE

		if deadline >= 0 and Time.get_ticks_usec() >= deadline and _step != Step.DONE:
			return false

	return true


func _do_cache() -> void:
	_stage_name = "building"
	_step = Step.STRICT

	if cache_path == "" or not FileAccess.file_exists(cache_path):
		return

	var cached := DotNpcNavData.from_cache_bytes(FileAccess.get_file_as_bytes(cache_path))

	if cached != null and cached.matches(digest):
		nav = cached
		from_cache = true
		_step = Step.DONE


## Steps the current builder, making it first from [param heights]; true when it finished.
func _drive(heights: Array, deadline: int) -> bool:
	if _builder == null:
		var made: DotNpcNavBuilder = make_builder.call(heights, _info)
		made.workers = workers
		made.log_summary = false
		made.begin(map_id, digest)
		_lock.lock()
		_builder = made
		if _builds_done == 0:
			# Links were dropped, so the later passes may build again: the bar is shared out up front.
			_builds_expected = 1 if int(_info["rejected"]) == 0 else 3
		_lock.unlock()

	var budget := 0.0

	if deadline >= 0:
		budget = maxf(float(deadline - Time.get_ticks_usec()) / 1000.0, 0.05)

	return _builder.step(budget)


func _after_build() -> void:
	_lock.lock()
	_builds_done += 1
	_reports[_builder.result().get_instance_id()] = _builder.link_report()
	_builder = null
	_lock.unlock()


## The strictest link test that loses no post and under 1% of the ground, else the loose graph.
func _do_try(deadline: int) -> void:
	var tried: DotNpcNavData = _strict

	if _try == 1:
		if not _drive([strict_heights[-1]], deadline):
			return

		tried = _builder.result()
		_after_build()

	var found: Vector2i = reach.call(tried)

	if found.x >= _kept_reach.x and found.y * 100 >= _kept_reach.y * 99:
		nav = tried
		_step = Step.SAVE
		return

	_try += 1

	if _try > 1:
		nav = _kept
		_step = Step.SAVE


func _do_save() -> void:
	if cache_path == "" or nav == null:
		return

	DirAccess.make_dir_recursive_absolute(cache_path.get_base_dir())
	var file := FileAccess.open(cache_path, FileAccess.WRITE)

	if file != null:
		file.store_buffer(nav.to_cache_bytes())
		file.close()
		DotWeb.sync_filesystem()
	else:
		_save_error = FileAccess.get_open_error()


## Main thread, once after the end: the one warning about links with no point, and the cache write failure.
func flush_log() -> void:
	if nav == null:
		return

	var report: Dictionary = _reports.get(nav.get_instance_id(), {})

	if not report.is_empty():
		DotLog.warn("npc.nav", "navigation links found no point at one end", report)

	if _save_error != 0:
		DotLog.warn(CHANNEL, "the navigation cache could not be written", {"path": cache_path, "error": _save_error})
