extends RefCounted
## Builds a landed graph's stand-in search ([member ZzNavGraph.bot_filter]'s native graph) on a worker, from a copy of
## what it is built from ([method ZzNavGraph.bot_search_twin]), while the graph stays the main thread's. A cached load of
## a ladder map links on the main thread (the ladder sides ask the live space), so [ZzNavDerive] could not warm it, and
## the first stand-in's walk built it on tick 1: 1.4 s on gm_valley. Play waits for it ([method ZzHorde.nav_blocks_play]).
## `zz_nav_warm_bots` 0 builds it on first use as before.

const _Self := preload("zz_nav_warm_thread.gd")

## Milliseconds the main thread took to copy the graph.
var copy_ms := 0.0

var _graph: Variant = null
var _twin: Variant = null
var _task := -1


## Starts the build for [param graph] (a `ZzNavGraph`); null when it is built already.
static func begin(graph: Variant) -> _Self:
	if graph == null or not graph.has_method(&"has_bot_search") or graph.has_bot_search():
		return null

	var warm := _Self.new()
	var start := Time.get_ticks_usec()
	warm._graph = graph
	warm._twin = graph.bot_search_twin()
	warm.copy_ms = (Time.get_ticks_usec() - start) / 1000.0
	warm._task = WorkerThreadPool.add_task(warm._build, false, "zz nav warm bots")
	return warm


func _build() -> void:
	_twin.warm_bot_search()


func done() -> bool:
	return _task < 0 or WorkerThreadPool.is_task_completed(_task)


## Waits for the worker and hands the search to the graph. False when the graph changed meanwhile and builds it on first
## use instead.
func finish() -> bool:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

	var taken: bool = _graph.adopt_bot_search(_twin)
	_twin = null
	return taken


## [method finish], noted in [param sections] (the copy's milliseconds, and 1 when the graph took the search). Returns
## null, for the holder's field.
func land(sections: Dictionary) -> _Self:
	sections[&"nav_warm_copy"] = snappedf(copy_ms, 0.1)
	sections[&"nav_warm_taken"] = 1.0 if finish() else 0.0
	return null
