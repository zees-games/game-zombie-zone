extends Node

## tools/bench.gd's crowd on the server half of a `--sim_host 1` bench (game/zz_sim_server.gd loads this for
## `--bench_crowd=N`): once a round runs with the player in it, every survivor is made unkillable, the player is put
## at the bench's stand, and N commons are kept alive at seeded points 8 to 40 m round it, all hunting the player.
## The same steps bench.gd takes on an in-process world, done where the horde is.

const ZzGame := preload("../game/zz_game.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzSimHost := preload("../game/zz_sim_host.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")

## Set by the sim server before this is added.
var game: ZzGame = null
var server: Node = null

var _count := 0
var _ring := Vector2(8.0, 40.0)
var _at := Vector3.INF
var _rng := RandomNumberGenerator.new()
var _stand := Vector3.INF
var _human: ZzPlayer = null


func _ready() -> void:
	_count = int(ZzSimHost.arg("--bench_crowd"))
	_rng.seed = int(ZzSimHost.arg("--bench_seed")) if ZzSimHost.arg("--bench_seed") != "" else 7
	var ring := ZzSimHost.arg("--bench_ring").split(",")
	if ring.size() == 2:
		_ring = Vector2(ring[0].to_float(), ring[1].to_float())
	var at := ZzSimHost.arg("--bench_at").split(",")
	if at.size() == 3:
		_at = Vector3(at[0].to_float(), at[1].to_float(), at[2].to_float())
	print("SIM_HOST bench crowd=%d seed=%d ring=%s" % [_count, _rng.seed, _ring])


func _physics_process(_delta: float) -> void:
	if game == null or game.phase == ZzGame.Phase.IDLE:
		return
	if _human == null or not is_instance_valid(_human):
		_human = _the_human()
		if _human == null:
			return
		for player in game.survivors():
			player.health.invulnerable = true
		_stand = _at if _at != Vector3.INF else default_stand(game)
		_human.place_at(_stand, float(game.map.spawn("survivors", 0)[1]) if _at == Vector3.INF else 0.0)
		print("SIM_HOST bench stand %s" % _stand)
		return
	var missing := _count - game.horde.spawner.all_npcs().size()
	for _i in mini(missing, 8):
		var angle := _rng.randf() * TAU
		var reach := _rng.randf_range(_ring.x, _ring.y)
		var at := _stand + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
		var npc: DotNpcInstance = game.horde.spawner.spawn(ZzNpcs.COMMON, game.horde.snap_to_nav(at), &"bench", Basis(Vector3.UP, _rng.randf() * TAU))
		if npc != null and npc.brain != null:
			npc.brain.call(&"force_target", _human.player_id)


func _the_human() -> ZzPlayer:
	for id: StringName in game.players:
		var p := game.players[id] as ZzPlayer
		if p != null and not p.is_bot:
			return p
	return null


## Where everybody is put when --at is not given: the practice street's open ground at z 12, or the first survivor
## seat on a map with nothing under that point (a converted street has a void there), and only inside a floor of the
## map's own navigation (a converted yard's slab runs past its own fence).
static func default_stand(on: ZzGame) -> Vector3:
	var usual := Vector3(0.0, 0.05, 12.0)
	var space := on.get_world_3d().direct_space_state
	var mask := on.physics.layer_mask(&"world")
	var down := PhysicsRayQueryParameters3D.create(usual + Vector3(0.0, 1.0, 0.0), usual + Vector3(0.0, -0.6, 0.0), mask)
	var inside := false
	for f in ((on.map.doc.get("nav", {}) as Dictionary).get("floors", []) as Array):
		if usual.x >= float(f[0]) and usual.x <= float(f[2]) and usual.z >= float(f[1]) and usual.z <= float(f[3]):
			inside = true
	if inside and not space.intersect_ray(down).is_empty():
		return usual
	var seat: Vector3 = on.map.spawn("survivors", 0)[0]
	return seat + Vector3(0.0, 0.05, 0.0)
