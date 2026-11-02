extends RefCounted
## The mod-style opening: some survivors turn after a delay and the rest hold. Off by default (`zz_infect_after`).

const CHANNEL := "zz.infection"

var game = null
var clock: float = 0.0
var done: bool = false
var turned: int = 0
var _rng := RandomNumberGenerator.new()


func _init(p_game: Object) -> void:
	game = p_game
	_rng.seed = int(game.config.seed_value) ^ int(game.round_number) * 977


func tick(delta: float) -> void:
	var c = game.config
	if done or c.infect_after_seconds <= 0.0 or game.horde == null:
		return

	clock += delta
	if clock < c.infect_after_seconds:
		return

	done = true
	var living: Array = game.survivors().filter(func(p: Object) -> bool: return p.life != p.Life.DEAD)
	# The last human is never turned: a round with nobody left is a wipe, not a mode.
	var count := mini(c.infect_count, living.size() - 1)

	for i in count:
		var pick: int = _rng.randi() % living.size()
		turn(living[pick])
		living.remove_at(pick)

	if turned > 0:
		game.notice.emit("%d of you have turned." % turned)


## Kills [param player] and stands a zombie where they fell, going for the nearest survivor left.
func turn(player: Object) -> void:
	var at: Vector3 = player.feet()
	game._die(player, &"infection", &"infected")
	var npc = game.horde.spawner.spawn(StringName(game.config.infect_kind), at, &"infected")

	if npc == null:
		DotLog.warn(CHANNEL, "a turned survivor left no zombie", {"kind": game.config.infect_kind})
		return

	turned += 1
	var best := &""
	var best_d := INF
	for other: Object in game.survivors():
		if other.life == other.Life.DEAD:
			continue
		var d: float = other.feet().distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = other.player_id

	if npc.brain != null and best != &"":
		npc.brain.call(&"force_target", best)
