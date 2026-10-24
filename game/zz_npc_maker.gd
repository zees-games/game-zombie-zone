extends DotMapEntity

## npc_template_maker: Spawn (or its own timer once enabled) asks the game for one zombie at the maker, up to MaxNPCCount in all.
## The live-children cap is not kept: the game does not report a zombie's death back to a maker.

var _spawned := 0
var _gen := 0
var _armed := false


func on_map_spawn(io: DotMapIO) -> void:
	if enabled:
		_arm(io)


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"spawn":
			_spawn(io, activator)
			return true
		"__beat":
			if enabled and _armed and param == str(_gen):
				_spawn(io, activator)
				_arm(io)
			return true
		"setmaxchildren":
			keys["maxnpccount"] = param
			return true
		"addmaxchildren":
			keys["maxnpccount"] = str(key_float("maxnpccount", 1.0) + param.to_float())
			return true
		"setspawnfrequency":
			keys["spawnfrequency"] = param
			return true
		"setmaxlivechildren", "setminspawndistance":
			return true
	return false


func _enabled_changed(io: DotMapIO, on: bool) -> void:
	_gen += 1
	_armed = false
	if on:
		_arm(io)


func _arm(io: DotMapIO) -> void:
	var every := key_float("spawnfrequency", 5.0)
	if every <= 0.0 or _spawned >= _limit():
		_armed = false
		return
	_gen += 1
	_armed = true
	io.schedule_self(self, "__beat", str(_gen), every)


func _limit() -> int:
	var n := int(key_float("maxnpccount", 1.0))
	return n if n >= 0 else 1 << 30


func _spawn(io: DotMapIO, activator: Variant) -> void:
	if _spawned >= _limit():
		return
	_spawned += 1
	io.event("npc_spawn", {"maker": index, "template": key("templatename"), "at": origin(io), "yaw": 0.0})
	fire(io, "OnSpawnNPC", activator)
	if _spawned >= _limit():
		fire(io, "OnAllSpawned", activator)
