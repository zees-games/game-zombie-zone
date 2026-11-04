extends Node
## Shared start of the water probes: parses the map id, `--dir=` and `--trace`, builds a solo game on the map and seats an invulnerable walker.

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const TICK_RATE := 60
const TICK := 1.0 / TICK_RATE

var _args: Array = []
var _trace := false
var _id := &""
var _game: ZzGame
var _walker: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	pass


## Sets _args (map id first, then the probe's own), _trace, _id, _game and _walker, with the map started and 8 ticks run.
func _open_walker() -> void:
	_args = Array(OS.get_cmdline_user_args())
	var dir := ""
	_trace = _args.has("--trace")
	_args.erase("--trace")
	for a: String in _args.duplicate():
		if a.begins_with("--dir="):
			dir = a.substr(6)
			_args.erase(a)
	_id = StringName(_args[0]) if _args.size() > 0 else &"zm_4way_tunnel"
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.start_grace_seconds = 600.0
	config.map_ids = PackedStringArray([String(_id)])
	if dir != "":
		config.map_directory = dir
	_game = ZzGame.new()
	_game.config = config
	_game.tick_rate = TICK_RATE
	_game.authoritative = true
	_game.register_service = false
	add_child(_game)
	_game.set_physics_process(false)
	await get_tree().physics_frame
	_walker = _game.add_player(&"u1", "Walker")
	_walker.health.invulnerable = true
	_game.next_map_id = _id
	_game.start()
	for i in 8:
		_game.simulate(TICK)
