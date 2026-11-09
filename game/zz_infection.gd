extends RefCounted
## The mod-style opening: some survivors turn after a delay and the rest hold. Off by default (`zz_infect_after`).

const CHANNEL := "zz.infection"
## The kind a turned survivor becomes when zz_infect_kind names none the catalogue has.
const FALLBACK_KIND := &"common"

## Not done: the turned survivor is an AI zombie, not a body the player drives. That needs the
## player to possess an npc (input, camera, a zombie moveset, a net codec for it), which is not small.

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
	var kind := StringName(game.config.infect_kind)
	var npc = game.horde.spawner.spawn(kind, at, &"infected")

	# An unknown kind (a typo in zz_infect_kind) falls back to the common, so a turned survivor is never just gone.
	if npc == null and kind != FALLBACK_KIND:
		DotLog.warn(CHANNEL, "unknown zz_infect_kind, turning into a common", {"kind": String(kind)})
		npc = game.horde.spawner.spawn(FALLBACK_KIND, at, &"infected")

	if npc == null:
		DotLog.warn(CHANNEL, "a turned survivor left no zombie", {"kind": String(kind)})
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
