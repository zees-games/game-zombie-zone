extends RefCounted

const ZzLoot := preload("zz_loot.gd")

const ZzMapDoc := preload("zz_map_doc.gd")

const ZzNetCommand := preload("net/zz_net_command.gd")

const ZzNpcs := preload("zz_npcs.gd")

const ZzUnstick := preload("zz_unstick.gd")

const ZzWeapons := preload("zz_weapons.gd")

## The stand-in survivors: what a server fills a team with, and what a suite plays with. [b]A team-mate, not a turret.[/b] What makes a co-operative stand-in worth having is the same list a person is judged by, in this order: [codeblock] 1. a friend pinned shoot what is on them; shove it off if it is close 2. a friend down go to them and pick them up, unless something is on top of you 3. a threat the most dangerous zombie it can see: a special, then whatever is nearest; a crowd in its face gets shoved 4. itself pills at half health, a medkit when low and nothing is near 5. the team keep
## within a few metres of whoever leads, or walk the route to the end area when nobody human is leading; work the objective [/codeblock] [b]On a survival map the team is a set of posts[/b] (the map's `posts`): each stand-in holds its own, spread over them by seat, fights from it, mends the barricade nearest it when nothing is in sight, and in a breather walks to a cache when it is short of ammunition, a medkit or a proper gun. A dozen stand-ins following one leader round a school was a dozen stand-ins in one corridor and forty windows nobody was at. It walks the zombies' own navigation
## graph (`ZzHorde.nav`), so it goes round a car rather than into it. [b]It aims and shoots like the family's bots[/b]: dot-bot's [DotBotAim], one per stand-in, on the game's [DotBotSettings] (`bot_difficulty` and every `bot_*` setting, the same names as every game's). So its view turns at `bot_turn_rate` rather than snapping, its first shots at a new zombie miss by `bot_aim_error` and settle, and it fires only `bot_reaction` after it first saw that zombie -- a stand-in that turns and fires on the tick a leaper lands is a stand-in a player can tell is a machine.

const CHANNEL := "zz.bots"

## The survivors stand-ins are named after, solo and on a server; past the end of the list
## dot-bot's [DotBotNames] numbers them.
## Twenty-four, because a survival map is built for a dozen or more.
const BOT_NAMES := ["Rook", "Marlow", "Juno", "Hask", "Petra", "Odell", "Sable", "Wren",
	"Cass", "Dmitri", "Ines", "Booker", "Tamsin", "Okafor", "Lupe", "Gideon",
	"Mireille", "Shaw", "Noor", "Vance", "Ottilie", "Rafferty", "Keiko", "Bram"]

## The game (`zz_game.gd`), untyped: it preloads this file.
var game = null

## player id -> {path, path_at, goal, aim (DotBotAim), now, target_at, stuck_at, stuck_tick}
var _state: Dictionary = {}

var _rng := RandomNumberGenerator.new()

## Whether this tick's command has been aimed at something: walking then must not turn the view
## toward where it is going, or a stand-in fleeing a crowd shoots the way it runs.
var _aiming: bool = false

## Seconds since this stand-in last thought, for its aim's turn.
var _dt: float = 0.0

func _init(p_game: Object) -> void:
	game = p_game
	_rng.seed = 4401

func forget(id: StringName) -> void:
	_state.erase(id)

	if game != null and game.has_method(&"personas"):
		game.personas().release(id)

## A stand-in's aim draws from its own stream, seeded from its id, never from the object.
static func _seed_of(player) -> int:
	return hash(String(player.player_id))

func _memory(player) -> Dictionary:
	if not _state.has(player.player_id):
		_state[player.player_id] = {
			"path": PackedVector3Array(), "path_at": -100.0, "goal": Vector3.INF,
			"aim": DotBotAim.new(_seed_of(player), DotBotSettings.of(game)), "now": NAN,
			"target_at": Vector3.INF, "stuck_at": Vector3.INF, "stuck_time": 0.0, "use_until": -1.0,
		}
		_apply_persona(player.player_id, _state[player.player_id])

	return _state[player.player_id]

## Draws this stand-in's character from the server's pool, and gives it that character's aim when the persona states one.
func _apply_persona(id: StringName, memory: Dictionary) -> void:
	var persona: DotBotPersona = _class_persona(id)
	if persona == null:
		persona = game.personas().assign(id, _rng)
	memory["persona"] = persona
	memory.erase("behave")
	var own := persona.profile_over(DotBotSettings.of(game).profile)
	var settings := DotBotSettings.of(game)

	if own != null:
		settings = DotBotSettings.new()
		settings.profile = own

	memory["aim"] = DotBotAim.new(hash(String(id)), settings)

## The persona this stand-in's class names (`persona:` in its class profile), or null to draw from the pool.
func _class_persona(id: StringName) -> DotBotPersona:
	var player = game.players.get(id) if "players" in game else null
	if player == null or player.class_def == null:
		return null
	var want := str(player.class_def.attributes.get("persona", ""))
	if want == "":
		return null
	for persona: DotBotPersona in game.personas().personas:
		if String(persona.id) == want:
			return persona
	return null

## A persona was added, edited or deleted: every stand-in draws again.
func redraw_personas() -> void:
	for id: StringName in _state:
		_apply_persona(id, _state[id])
