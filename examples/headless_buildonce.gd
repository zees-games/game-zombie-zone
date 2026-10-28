extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")

## A world opened and started builds its map once; it builds again only when a setting the build reads changed in between.
##
## [codeblock]
## godot --headless --path . res://examples/headless_buildonce.tscn
## [/codeblock]

const SECTIONS := 2
const CHECKS := 8

var _entered := 0
var _finished := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	await _case(false)
	await _case(true)
	_report_sections(_entered, _finished, SECTIONS, CHECKS)


func _case(change: bool) -> void:
	_entered += 1
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray(["zz_practice"])
	var game := ZzGame.new()
	game.config = config
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	var rebuilt := [0]
	game.world_rebuilt.connect(func() -> void: rebuilt[0] += 1)
	_check(game.map_builds == 1, "opening the world builds the map once", str(game.map_builds))

	if change:
		game.map.gravity = 5.0

	game.start()
	_check(game.map_builds == (2 if change else 1), "starting builds %s" % ("it again" if change else "nothing more"), str(game.map_builds))
	_check(rebuilt[0] == 1, "a listener that came late is told the world once", str(rebuilt[0]))
	var maps := game.get_children().filter(func(n: Node) -> bool: return n.name == &"Map")
	_check(maps.size() == 1 and game.map.is_inside_tree(), "the map is attached once", str(maps.size()))
	game.queue_free()
	await get_tree().process_frame
	_finished += 1
