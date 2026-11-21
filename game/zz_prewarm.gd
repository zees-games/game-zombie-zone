extends Node
## Builds every offered weapon's first-person view once, on a spare view model under the loading
## cover, a few milliseconds a frame, so the first draw of each gun in play does not load its model
## and make its materials mid-fight. Holds the load gate's `weapons` reason until done.

const ZzWeapons := preload("zz_weapons.gd")

const SLICE_MSEC := 8
const HOLD := &"weapons"

var _spare: ZeeViewModel = null
var _arts: Array = []
var _next: int = 0
var _gate: Object = null
var _began_msec: int = 0

## Frames the spare spent building weapons (a probe reads this).
var frames: int = 0
## Weapons built so far.
var built: int = 0
## Milliseconds spent in the builds themselves, and the slowest one, for the log line.
var build_msec: int = 0
var _worst_msec: int = 0
var _worst_id: StringName = &""
## Resolved model paths asked of the loader's threads at [method begin], so the files are read and
## parsed beside the map and world loads rather than one per frame on the main thread.
var _pending: Dictionary = {}
## Scenes taken from the loader, held so the cache keeps them until each equip has used them.
var _held: Array = []
## Frames spent waiting on a thread load rather than building.
var waits: int = 0


## True where a prewarm is worth the frames: it draws nothing headless, and an open gate has no cover.
static func wanted(gate: Object) -> bool:
	return gate != null and not GSPlatform.is_headless() and not bool(gate.call(&"is_open"))


## Starts on [param camera] with a spare made like [param live]. False when there is nothing to do.
func begin(gate: Object, camera: Camera3D, live: ZeeViewModel) -> bool:
	if not wanted(gate) or camera == null or live == null:
		return false
	_arts = _offered_arts()
	if _arts.is_empty():
		return false
	_gate = gate
	_spare = ZeeViewModel.new()
	_spare.name = "WeaponPrewarm"
	_spare.feel_rules = live.feel_rules
	_spare.ads_rules = live.ads_rules
	_spare.feel = live.feel
	_spare.view_layer = live.view_layer
	_spare.finish_materials = live.finish_materials
	_spare.finish_metal = live.finish_metal
	_spare.finish_metal_roughness = live.finish_metal_roughness
	_spare.finish_polymer_roughness = live.finish_polymer_roughness
	_spare.finish_wood_roughness = live.finish_wood_roughness
	_spare.finish_lift = live.finish_lift
	_spare.visible = false
	camera.add_child(_spare)
	gate.call(&"hold", HOLD, "Preparing weapons")
	_request_models()
	_began_msec = Time.get_ticks_msec()
	get_tree().process_frame.connect(_tick)
	return true


## One art for each offered weapon that has a model, each distinct model once.
static func _offered_arts() -> Array:
	var out: Array = []
	var seen := {}
	for def in ZzWeapons.offered_defs():
		var art := ZeeWeaponArtTable.get_art(def.id)
		if art != null and art.has_model() and not seen.has(art.model_path):
			seen[art.model_path] = true
			out.append(art)
	return out


## Asks the loader's threads for every model and magazine not cached yet. A path the loader
## refuses is left to the equip, which loads it in place as before.
func _request_models() -> void:
	for art: ZeeWeaponArt in _arts:
		for path: String in _paths(art):
			var real := ZeeModelCache.resolve(path)
			if _pending.has(real) or ResourceLoader.has_cached(real) or not ResourceLoader.exists(real):
				continue
			if ResourceLoader.load_threaded_request(real, "", true) == OK:
				_pending[real] = true


static func _paths(art: ZeeWeaponArt) -> Array[String]:
	var out: Array[String] = []
	for path: String in [art.model_path, art.magazine_path]:
		if path != "":
			out.append(path)
	return out


## True once every file [param art] needs is off the loader's threads (loaded or failed).
func _ready_to_build(art: ZeeWeaponArt) -> bool:
	for path: String in _paths(art):
		var real := ZeeModelCache.resolve(path)
		if not _pending.has(real):
			continue
		var status := ResourceLoader.load_threaded_get_status(real)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
		_take(real, status)
	return true


func _take(real: String, status: int) -> void:
	_pending.erase(real)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_held.append(ResourceLoader.load_threaded_get(real))
	else:
		# The equip loads it in place and logs whatever is wrong with it.
		GSLog.warn("zz_prewarm", "thread load failed; loading in place", {"path": real, "status": status})


func _tick() -> void:
	frames += 1
	if not is_instance_valid(_spare):
		_end()
		return
	var until := Time.get_ticks_msec() + int(_gate.call(&"slice_msec", SLICE_MSEC))
	while _next < _arts.size() and Time.get_ticks_msec() < until:
		if not _ready_to_build(_arts[_next] as ZeeWeaponArt):
			waits += 1
			break
		var t0 := Time.get_ticks_msec()
		var _r := _spare.equip(_arts[_next] as ZeeWeaponArt)
		_spare.clear()
		var took := Time.get_ticks_msec() - t0
		build_msec += took
		if took > _worst_msec:
			_worst_msec = took
			_worst_id = (_arts[_next] as ZeeWeaponArt).id
		_next += 1
		built += 1
	if _next >= _arts.size():
		_end()


func _end() -> void:
	# A request left on the loader keeps its scene there; take each one so none is left behind.
	for real: String in _pending.keys():
		var _r := ResourceLoader.load_threaded_get(real)
	_pending.clear()
	_held.clear()
	if get_tree().process_frame.is_connected(_tick):
		get_tree().process_frame.disconnect(_tick)
	if is_instance_valid(_spare):
		_spare.queue_free()
	_spare = null
	if _gate != null and is_instance_valid(_gate):
		_gate.call(&"release", HOLD)
	GSLog.info("zz_prewarm", "weapon views built", {"weapons": built, "frames": frames, "waits": waits, "msec": Time.get_ticks_msec() - _began_msec,
		"build_msec": build_msec, "worst_msec": _worst_msec, "worst": _worst_id})
	queue_free()
