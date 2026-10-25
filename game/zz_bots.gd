extends RefCounted

const ZzLoot := preload("zz_loot.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzNetCommand := preload("net/zz_net_command.gd")
const ZzNpcs := preload("zz_npcs.gd")
const ZzUnstick := preload("zz_unstick.gd")
const ZzWeapons := preload("zz_weapons.gd")

## The stand-in survivors: what a server fills a team with, and what a suite plays with.
##
## [b]A team-mate, not a turret.[/b] What makes a co-operative stand-in worth having is the same
## list a person is judged by, in this order:
##
## [codeblock]
## 1. a friend pinned        shoot what is on them; shove it off if it is close
## 2. a friend down          go to them and pick them up, unless something is on top of you
## 3. a threat              the most dangerous zombie it can see: a special, then whatever is
##                          nearest; a crowd in its face gets shoved
## 4. itself                pills at half health, a medkit when low and nothing is near
## 5. the team              keep within a few metres of whoever leads, or walk the route to the
##                          end area when nobody human is leading; work the objective
## [/codeblock]
##
## [b]On a survival map the team is a set of posts[/b] (the map's `posts`): each stand-in holds
## its own, spread over them by seat, fights from it, mends the barricade nearest it when
## nothing is in sight, and in a breather walks to a cache when it is short of ammunition, a
## medkit or a proper gun. A dozen stand-ins following one leader round a school was a dozen
## stand-ins in one corridor and forty windows nobody was at.
##
## It walks the zombies' own navigation graph (`ZzHorde.nav`), so it goes round a car rather
## than into it.
##
## [b]It aims and shoots like the family's bots[/b]: dot-bot's [DotBotAim], one per stand-in, on
## the game's [DotBotSettings] (`bot_difficulty` and every `bot_*` setting, the same names as
## every game's). So its view turns at `bot_turn_rate` rather than snapping, its first shots at
## a new zombie miss by `bot_aim_error` and settle, and it fires only `bot_reaction` after it
## first saw that zombie -- a stand-in that turns and fires on the tick a leaper lands is a
## stand-in a player can tell is a machine.

const CHANNEL := "zz.bots"

## The survivors stand-ins are named after, solo and on a server; past the end of the list
## dot-bot's [DotBotNames] numbers them.
## Twenty-four, because a survival map is built for a dozen or more.
const BOT_NAMES := ["Rook", "Marlow", "Juno", "Hask", "Petra", "Odell", "Sable", "Wren",
	"Cass", "Dmitri", "Ines", "Booker", "Tamsin", "Okafor", "Lupe", "Gideon",
	"Mireille", "Shaw", "Noor", "Vance", "Ottilie", "Rafferty", "Keiko", "Bram"]

## How far a bot sees a zombie, and how close a crowd has to be to be shoved.
const SIGHT := 32.0

## How near the line of fire a friend's middle may be before a stand-in holds its fire: a
## body's half-width and a little more for a shotgun's spread.
const FRIEND_CLEARANCE := 0.7

## The cone a stand-in's shot may land in around its aim: its own aim wobble plus a moving
## shotgun's spread. A friend's hitbox inside it is a friend in the line.
const FRIEND_CONE_DEGREES := 14.0

## How far inside a friend's hitbox the eye must be (metres, each way) for the shot to count as
## passing through them; see [method _holds_muzzle]. A stand-in moves about 4 cm per tick.
const MUZZLE_MARGIN := 0.08
const SHOVE_RANGE := 1.7

## How far a bot lets its leader get before it walks after them.
const FOLLOW_NEAR := 3.5
const FOLLOW_FAR := 6.0

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

	return _state[player.player_id]


## One tick of every stand-in's decisions, as commands on their controllers.
func drive(_delta: float) -> void:
	for player in game.survivors():
		if not player.is_bot or not player.is_alive() or player.watching:
			continue

		# [b]Standing posts decide every second tick[/b], like a far zombie's brain: the command
		# of the tick before is applied again (a view, a walk and a held trigger are states, not
		# events), seats alternating so half the team thinks on each tick. Anyone down, pinned,
		# shoving or mid-mend decides every tick, as does the first tick.
		var kept: Variant = _state.get(player.player_id, {}).get("last_command")
		if kept is DotFpsCommand and player.is_up() and not player.is_pinned() and player.using == &"" \
				and (game.current_tick() + _seat(player)) % 2 == 1 and game.phase != game.Phase.IDLE:
			player.controller.apply_command(kept as DotFpsCommand)
			continue

		var command := DotFpsCommand.new()
		command.yaw = player.controller.state.yaw
		command.pitch = player.controller.state.pitch
		player.actions = 0
		player.shove_held = false
		_aiming = false

		var memory := _memory(player)
		var aim: DotBotAim = memory["aim"]
		aim.view_from(command.yaw, command.pitch)
		var last_now := float(memory["now"])
		_dt = clampf(game.now() - last_now, 0.0, 0.25) if not is_nan(last_now) else 0.0
		memory["now"] = game.now()

		if game.phase != game.Phase.IDLE:
			_decide(player, command)
			_pulse_trigger(player, command)

		memory["last_command"] = command
		player.controller.apply_command(command)


func _decide(player, command: DotFpsCommand) -> void:
	var memory := _memory(player)

	if player.is_pinned() and player.pin_kind != &"grab":
		return

	# Grabbed by the ankle: shoot what holds you.
	if player.is_pinned():
		var holder = _threat(player)
		if holder != null:
			_aim_at(player, command, holder)
		return

	# Down: shoot whatever is closest, which is all a downed survivor can do.
	if player.is_down():
		var threat := _threat(player)
		if threat != null:
			_aim_at(player, command, threat)
			command.set_button(ZzNetCommand.BUTTON_FIRE, _fire_ok(player, memory, threat))
		return

	_get_out_of_hazards(player, command)

	# 1. A friend pinned: kill or shove what is on them.
	var pinned = _pinned_friend(player)

	if pinned != null and not _answers(player, pinned):
		pinned = null

	if pinned != null:
		var holder: DotNpcInstance = game.pins.holder_of(pinned.player_id)

		if holder != null:
			var gap: float = holder.position().distance_to(player.feet())

			if gap <= 2.0:
				_aim(player, command, holder.position() + Vector3(0.0, 1.0, 0.0))
				player.shove_held = (game.current_tick() % 8) < 2
			else:
				if _sees(player, _aim_point(holder)):
					_aim_at(player, command, holder)
					command.set_button(ZzNetCommand.BUTTON_FIRE, _fire_ok(player, memory, holder))
				_walk_to(player, command, holder.position(), memory)
			return

	# 2. A friend down, and nothing on top of us.
	var downed = _downed_friend(player)

	if downed != null and not _answers(player, downed):
		downed = null

	var danger := _threat(player)
	var close_danger := danger != null and danger.position().distance_to(player.feet()) < 4.0

	if downed != null and not close_danger:
		var gap: float = downed.feet().distance_to(player.feet())

		if gap <= game.config.revive_range:
			_aim(player, command, downed.feet() + Vector3(0.0, 0.3, 0.0))
			player.actions |= ZzNetCommand.ACT_USE
		else:
			_walk_to(player, command, downed.feet(), memory)
		return

	# 3. Threats.
	if danger != null:
		_aim_at(player, command, danger)
		var crowd := _crowd_within(player, SHOVE_RANGE)

		if crowd >= 2 or (danger.def.id == ZzNpcs.COMMON and danger.position().distance_to(player.feet()) < 1.3):
			player.shove_held = (game.current_tick() % 10) < 2

		command.set_button(ZzNetCommand.BUTTON_FIRE, _fire_ok(player, memory, danger))
		# Backpedal from anything in its face; otherwise keep with the team (or its post) while
		# shooting.
		if danger.position().distance_to(player.feet()) < 2.5:
			_move_world(player, command, player.feet() - danger.position())
		elif game.is_survival():
			_hold_post(player, command, memory)
		else:
			_follow(player, command, memory)
		return

	# 4. Itself.
	if player.pills > 0 and player.health_fraction() < 0.5:
		player.actions |= ZzNetCommand.ACT_PILLS
	elif player.medkits > 0 and player.real_health() < 40.0 and _crowd_within(player, 15.0) == 0:
		player.actions |= ZzNetCommand.ACT_HEAL
		return

	# Reload when nothing is happening.
	if player.weapons != null and player.weapons.arsenal != null:
		var slot: DotWeaponSlot = player.weapons.arsenal.current()
		if slot != null and slot.def.magazine > 0 and slot.magazine < slot.def.magazine * 0.5:
			command.set_button(ZzNetCommand.BUTTON_RELOAD, true)

	# A box in the hands is opened where it is quiet: standing still for a few seconds is the cost.
	if game.config.bot_open_boxes and not player.carried.is_empty() and _crowd_within(player, 15.0) == 0:
		# Released for a tick now and then while nothing has begun: a begin needs a fresh press, and a key held since a refused first press never gives another.
		if player.using == &"deploy" or game.current_tick() % 8 != 0:
			player.actions |= ZzNetCommand.ACT_DEPLOY
		return

	# Something useful lying near.
	if _pick_up(player, command, memory):
		return

	# A survival map: mend, restock, hold.
	if game.is_survival():
		if _mend(player, command, memory) or _restock(player, command, memory):
			return
		if not _objective(player, command, memory):
			_hold_post(player, command, memory)
		return

	# 5. The team, or the objective.
	if _objective(player, command, memory):
		return

	_follow(player, command, memory)


# --- Holding a survival map ------------------------------------------------------------------

## This stand-in's post: the map's posts shared out by seat (its place among the stand-ins,
## sorted by id, so it does not change while it plays), a ring round the post when there are
## more stand-ins than posts. The spawns when the map has no posts.
func _post_of(player) -> Vector3:
	var posts: Array = game.map_doc.get("posts", [])

	if posts.is_empty():
		var spot: Array = game.map.spawn("survivors", _seat(player))
		return spot[0]

	var seat := _seat(player)
	var at := ZzMapDoc.v3(posts[seat % posts.size()])
	var lap := seat / posts.size()

	if lap > 0:
		var angle := float(lap) * 2.39996
		at += Vector3(cos(angle), 0.0, sin(angle)) * 1.4

	return at


## Where this stand-in stands: behind a choke on the horde's route when the map has been
## annotated (`zz_bot_hold_chokes`), falling back along the route when that choke is overrun,
## and its post when not. The post still says which barricade it mends.
func _hold_of(player) -> Vector3:
	var horde = game.horde

	if horde != null and game.config.bot_hold_chokes and horde.notes.is_ready():
		var at: Vector3 = horde.notes.hold_for(_seat(player))

		if at != Vector3.INF:
			return at

	return _post_of(player)


func _seat(player) -> int:
	var memory := _memory(player)
	var roster: int = game.players.size()

	if int(memory.get("seat_roster", -1)) == roster:
		return int(memory["seat"])

	var ids: Array = []

	for other in game.survivors():
		if other.is_bot:
			ids.append(String(other.player_id))

	ids.sort()
	memory["seat"] = maxi(ids.find(String(player.player_id)), 0)
	memory["seat_roster"] = roster
	return int(memory["seat"])


func _hold_post(player, command: DotFpsCommand, memory: Dictionary) -> void:
	var post := _hold_of(player)

	if Vector2(post.x - player.feet().x, post.z - player.feet().z).length() > 2.0:
		_walk_to(player, command, post, memory)


## Mends the weakest barricade near its post when nothing is in sight: walks to its inside face
## and holds E until it is whole. A broken one is rebuilt first.
func _mend(player, command: DotFpsCommand, memory: Dictionary) -> bool:
	var list: Array = game.map_doc.get("barricades", [])

	if list.is_empty():
		return false

	var post := _post_of(player)
	var best := int(memory.get("mend", -1))

	# Which barricade is chosen twice a second, not every tick: the walk there is every tick.
	if game.now() >= float(memory.get("mend_until", -1.0)):
		best = _barricade_to_tend(list, post)
		memory["mend"] = best
		memory["mend_until"] = game.now() + 0.5
	elif best >= 0 and (best >= list.size() or _needs_mending(list[best]) < 0.0):
		best = -1

	if best < 0:
		return false

	if game.barricade_to_mend(player) == best:
		var box: AABB = game.map.barricade_bounds(str((list[best] as Dictionary)["id"]))
		_aim(player, command, box.get_center())
		# Held through a mend, let go for a tick between: a mend starts on the press, and a key
		# held from the last one is no press.
		if player.using == &"repair" or game.current_tick() % 4 != 0:
			player.actions |= ZzNetCommand.ACT_USE
		return true

	# Its inside face: the nearest point of the box to the post, a metre back toward the post.
	var box: AABB = game.map.barricade_bounds(str((list[best] as Dictionary)["id"]))
	var face := Vector3(clampf(post.x, box.position.x, box.end.x), 0.0, clampf(post.z, box.position.z, box.end.z))
	var back := post - face
	back.y = 0.0
	var stand := face + (back.normalized() * 1.1 if back.length() > 0.1 else Vector3.ZERO)
	_walk_to(player, command, stand, memory)
	return true


## The weakest barricade near [param post] that wants mending (broken, or under three
## quarters), as its index; -1 for none.
func _barricade_to_tend(list: Array, post: Vector3) -> int:
	var best := -1
	var best_score := INF

	for i in list.size():
		var share := _needs_mending(list[i])

		if share < 0.0:
			continue

		var box: AABB = game.map.barricade_bounds(str((list[i] as Dictionary)["id"]))
		var gap := box.get_center().distance_to(post)

		if gap > 22.0:
			continue

		var score := gap + share * 20.0

		if score < best_score:
			best = i
			best_score = score

	return best


## How whole a barricade is (0 broken .. 0.75), or -1 when it does not want mending.
func _needs_mending(entry: Dictionary) -> float:
	var held: Dictionary = game.barricades.get(str(entry["id"]), {})

	if held.is_empty():
		return -1.0

	var share := float(held["health"]) / maxf(float(held["max"]), 1.0)

	# Being torn at: a mend would be refused, and whoever stood there would be the one in reach.
	if game.barricade_torn(str(entry["id"])):
		return -1.0

	if not bool(held["intact"]):
		return 0.0

	return share if share <= 0.75 else -1.0


## In a breather, short of ammunition, a medkit or a primary: to the nearest cache that has
## something on it.
func _restock(player, command: DotFpsCommand, memory: Dictionary) -> bool:
	if game.survival == null or game.survival.waves == null or game.loot == null \
			or game.survival.waves.stage != DotNpcDirectorWaves.Stage.QUIET:
		return false

	# The opening quiet is for taking the chokes: the caches are stocked then too (the player
	# has something to find), but a stand-in without a primary walking off to them left the
	# chokes empty when wave 1 came (headless_nav). They restock from the first breather on.
	if game.survival.waves.index <= 1:
		return false

	var wants: bool = _low_on_ammo(player) or player.medkits == 0 \
		or (player.weapons != null and player.weapons.arsenal != null and not _has_primary(player))

	if not wants:
		return false

	var best := Vector3.INF
	var best_gap := 70.0

	for raw: Array in game.map_doc.get("caches", []):
		var at := ZzMapDoc.v3(raw)
		var stocked := false

		for id: int in game.loot.entries:
			if (game.loot.position_of(id) as Vector3).distance_to(at) < 1.6:
				stocked = true
				break

		var gap := at.distance_to(player.feet())

		if stocked and gap < best_gap:
			best = at
			best_gap = gap

	if best == Vector3.INF:
		return false

	_walk_to(player, command, best, memory)
	return true


## The slots a primary or heavy gun goes in, worked out once: asked every tick by every
## stand-in, the weapon tables are too long to walk each time.
var _primary_slots: Array = []


func _has_primary(player) -> bool:
	if _primary_slots.is_empty():
		for id in ZzWeapons.ids_of(&"primary") + ZzWeapons.ids_of(&"heavy"):
			var def: DotWeaponDef = ZzWeapons.def_of(id)
			if def != null and not _primary_slots.has(def.slot):
				_primary_slots.append(def.slot)

	for slot: int in _primary_slots:
		if player.weapons.arsenal.has_slot(slot):
			return true

	return false


## A semi-automatic weapon fires on the press, not while held: the trigger is let go every
## other few ticks, or a stand-in with a pistol fires once and then holds a dead trigger.
func _pulse_trigger(player, command: DotFpsCommand) -> void:
	if not command.is_pressed(ZzNetCommand.BUTTON_FIRE) or player.weapons == null:
		return

	var def: DotWeaponDef = player.weapons.current_def()

	if def != null and def.fire_mode != DotWeaponDef.Fire.AUTO and (game.current_tick() % 6) >= 3:
		command.set_button(ZzNetCommand.BUTTON_FIRE, false)


# --- Seeing -----------------------------------------------------------------------------------

## The most dangerous zombie this bot can see: a special within reach first, then the nearest.
##
## [b]Scored first, looked at in order, and the first one seen wins[/b]: a sight line is a
## raycast, and a stand-in in front of a crowd of forty that tested each one it might prefer
## cast forty a tick. Asked again only every few ticks while the one it has is alive.
func _threat(player) -> DotNpcInstance:
	if game.horde == null:
		return null

	var memory := _memory(player)
	var held: Variant = memory.get("threat")

	# Nobody in sight is an answer too: kept as long as a sighting is.
	if game.current_tick() < int(memory.get("threat_until", 0)) \
			and (held == null or (held is DotNpcInstance and (held as DotNpcInstance).is_alive())):
		return held

	var eye: Vector3 = player.eye_position()
	var scored: Array = []

	for npc in game.horde.zombies_near(player.feet(), SIGHT):
		if not npc.is_alive():
			continue

		# The sleeper is left alone unless she is up.
		if npc.def.id == ZzNpcs.SLEEPER and npc.brain != null and str(npc.brain.get(&"state")) == "sitting":
			continue

		var score := _aim_point(npc).distance_to(eye)

		if ZzNpcs.is_special(npc.def.id):
			score -= 12.0

		scored.append([score, npc])

	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var best: DotNpcInstance = null

	# The ten it would rather shoot, at most: past those, a crowd behind a wall is a crowd
	# behind a wall.
	for n in mini(scored.size(), 10):
		var npc: DotNpcInstance = scored[n][1]
		if _sees(player, _aim_point(npc)) or _sees(player, _head_point(npc)):
			best = npc
			break

	memory["threat"] = best
	# Staggered by the stand-in's own seat, so a dozen do not all look on the same tick.
	memory["threat_until"] = game.current_tick() + 3 + (hash(String(player.player_id)) & 1)
	return best


func _aim_point(npc: DotNpcInstance) -> Vector3:
	var height := float(npc.def.meta.get("height", 1.7))
	return npc.position() + Vector3(0.0, height * 0.72, 0.0)


func _head_point(npc: DotNpcInstance) -> Vector3:
	var height := float(npc.def.meta.get("height", 1.7))
	return npc.position() + Vector3(0.0, height * 0.9, 0.0)


## Where to shoot [param npc] from [param player]'s eye: the chest, or the head when only the
## head shows (over a window's boards, a person aims there; aimed at the chest, every shot
## went into the planks and the crowd at the window was never thinned).
func _shot_point(player, npc: DotNpcInstance) -> Vector3:
	var chest := _aim_point(npc)
	if _sees(player, chest):
		return chest
	var head := _head_point(npc)
	return head if _sees(player, head) else chest


func _sees(player, at: Vector3) -> bool:
	return game.clear_between(player.eye_position(), at)


func _crowd_within(player, reach: float) -> int:
	if game.horde == null:
		return 0

	var n := 0

	for npc in game.horde.zombies_near(player.feet(), reach):
		if npc.is_alive() and npc.def.id == ZzNpcs.COMMON:
			n += 1

	return n


## Fires only once it has had its reaction time on this target, with its view on its aim and
## in bursts at range ([DotBotAim.trigger]), and never through a friend.
func _fire_ok(player, memory: Dictionary, npc: DotNpcInstance) -> bool:
	var aim: DotBotAim = memory["aim"]
	if aim.target_id != npc.instance_id:
		return false
	var at: Vector3 = memory["target_at"] if memory.get("target_at", Vector3.INF) != Vector3.INF else _aim_point(npc)
	if not aim.trigger(game.now(), player.eye_position().distance_to(at)):
		return false
	if _friend_in_the_way(player, at):
		return false
	aim.note_shot(player.eye_position(), at, game.now())
	return true


## Whether another survivor stands in the line from [param player]'s eye to [param at].
##
## [b]Without it the stand-ins were their own worst enemy.[/b] Four of them bunched in the
## start room's doorway shot through each other at the first crowd, and with friendly fire on
## they lost the practice street three times in a minute; with it off, the same seed got them
## to the switch. A person does not fire through a friend's back, so neither does a stand-in.
##
## [b]Against the friend's hitboxes, not only their middle.[/b] Survivors do not collide, so a
## friend is often right beside the gun, shoulder to shoulder or half inside it. Their middle
## is then well off the line while their head and chest are on it: with the middle-only test
## four stand-ins dealt each other 200 to 500 points in every minute measured. A friend whose
## hitbox holds the eye itself is skipped, because the shot passes through them (`DotCombatManager.pass_through_sets`).
##
## [b]Under the server's `mp_teammate_passthrough`.[/b] At 2 every shot passes through every
## survivor, so nobody is in the way and a stand-in that held fire for a friend in the line
## stood behind them doing nothing while the horde arrived. At 0 a friend holding the muzzle
## is hit like anybody, so that friend is in the way after all.
func _friend_in_the_way(player, at: Vector3) -> bool:
	var level := _pass_through_level()

	if level >= DotDamageRules.PASS_THROUGH_ALWAYS:
		return false

	var eye: Vector3 = player.eye_position()
	var reach := eye.distance_to(at)
	var cone := tan(deg_to_rad(FRIEND_CONE_DEGREES))

	for other in game.survivors():
		if other == player or not other.is_alive() or other.watching:
			continue

		var middle: Vector3 = other.feet() + Vector3(0.0, 0.9, 0.0)
		var off := Geometry3D.get_closest_point_to_segment(middle, eye, at).distance_to(middle)

		# Only somebody between the gun and the target, not behind either.
		if (middle - eye).dot(at - eye) > 0.0 and middle.distance_to(eye) <= reach and off < FRIEND_CLEARANCE:
			return true

		# Nowhere near the line: no hitbox of theirs can be on it. A dozen stand-ins each
		# testing every friend's every hitbox every shot was most of what they cost.
		if off > 2.5 + reach * cone:
			continue

		var set_node: DotHitboxSet = other.hitboxes

		if set_node == null or not is_instance_valid(set_node):
			continue

		if level >= DotDamageRules.PASS_THROUGH_AT_MUZZLE and _holds_muzzle(set_node, eye):
			continue

		for box in set_node.hitboxes():
			if not box.enabled:
				continue

			var half := maxf(0.0, box.height * 0.5 - box.radius) if box.shape == DotHitbox.Shape.CAPSULE else 0.0
			var low: Vector3 = box.global_transform * Vector3(0.0, -half, 0.0)
			var high: Vector3 = box.global_transform * Vector3(0.0, half, 0.0)
			var near := Geometry3D.get_closest_points_between_segments(eye, at, low, high)
			var along: float = eye.distance_to(near[0])

			if near[0].distance_to(near[1]) < box.radius + 0.1 + along * cone:
				return true

	return false


## Whether a friend's hitboxes hold the eye with room to spare, not by a hair. The decision to
## fire is made a tick before the shot, and both stand-ins keep walking in between: an eye
## 2 cm inside a friend's capsule when it decided was 2 cm outside when the pellets left, so the
## pass-through no longer applied and a shotgun volley hit that friend at 7 mm (86 damage in one
## shot, the "102 friendly damage" that failed headless_run whenever the loot pool let a stand-in
## pick the shotgun up). An eye near the edge counts as not held, so the line test below runs.
func _holds_muzzle(set_node: DotHitboxSet, eye: Vector3) -> bool:
	if not set_node.contains_point(eye):
		return false

	for offset in [Vector3(MUZZLE_MARGIN, 0.0, 0.0), Vector3(-MUZZLE_MARGIN, 0.0, 0.0),
			Vector3(0.0, 0.0, MUZZLE_MARGIN), Vector3(0.0, 0.0, -MUZZLE_MARGIN)]:
		if not set_node.contains_point(eye + offset):
			return false

	return true


## The level the server's combat manager judges shots under (its `mp_teammate_passthrough`).
func _pass_through_level() -> int:
	if game == null or game.combat == null or game.combat.rules == null:
		return DotDamageRules.PASS_THROUGH_AT_MUZZLE
	return game.combat.rules.pass_through_level()


## Whether [param player] is one of the stand-ins that go to [param friend], pinned or down. On a
## survival map only the `bot_helpers` nearest standing survivors do, and anybody within
## `bot_helper_radius`: everyone walking to one friend left the posts empty and downed the whole
## team at one door. Elsewhere the team stays together and all answer.
func _answers(player, friend) -> bool:
	if not game.is_survival() or game.config.bot_helpers <= 0:
		return true

	var at: Vector3 = friend.feet()
	var mine: float = player.feet().distance_to(at)

	if mine <= game.config.bot_helper_radius:
		return true

	var closer := 0

	for other in game.survivors():
		if other == friend or other == player or other.is_down() or other.is_pinned() or not other.is_alive():
			continue
		if other.feet().distance_to(at) < mine:
			closer += 1

	return closer < game.config.bot_helpers


func _pinned_friend(player):
	var best = null

	for other in game.survivors():
		if other != player and other.is_pinned() and other.is_alive():
			if best == null or other.feet().distance_to(player.feet()) < best.feet().distance_to(player.feet()):
				best = other

	return best


func _downed_friend(player):
	var best = null

	for other in game.survivors():
		if other != player and other.is_down() and not other.is_pinned():
			if other.feet().distance_to(player.feet()) > 40.0:
				continue
			if best == null or other.feet().distance_to(player.feet()) < best.feet().distance_to(player.feet()):
				best = other

	return best


## Where the nearest sitting sleeper within [param reach] is, or INF.
func _sleeper_near(player, reach: float) -> Vector3:
	if game.horde == null:
		return Vector3.INF

	for npc in game.horde.zombies_near(player.feet(), reach):
		if npc.def.id == ZzNpcs.SLEEPER and npc.brain != null and str(npc.brain.get(&"state")) == "sitting":
			return npc.position()

	return Vector3.INF


# --- Moving -----------------------------------------------------------------------------------

## Aims at a zombie the way a person would: engaged with it from the first tick it is aimed at
## (its reaction starts), the view turned onto it at the settings' speed, off by the aim error
## of this engagement.
func _aim_at(player, command: DotFpsCommand, npc: DotNpcInstance) -> void:
	_aiming = true
	var memory := _memory(player)
	var aim: DotBotAim = memory["aim"]
	var eye: Vector3 = player.eye_position()
	var at := _shot_point(player, npc)
	var was: Vector3 = memory["target_at"]
	var velocity := (at - was) / _dt if aim.target_id == npc.instance_id and was != Vector3.INF and _dt > 0.0 else Vector3.ZERO
	memory["target_at"] = at
	var _new := aim.engage(npc.instance_id, eye, at, game.now())
	var view := aim.track(eye, at, velocity, game.now(), _dt)
	command.yaw = view.x
	command.pitch = clampf(view.y, -89.0, 89.0)


## Turns toward [param at] (a friend to revive, a door, a box): looking, not shooting, but
## still no faster than the settings turn a view.
func _aim(player, command: DotFpsCommand, at: Vector3) -> void:
	_aiming = true
	var aim: DotBotAim = _memory(player)["aim"]
	var view := aim.look_at_point(player.eye_position(), at, _dt)
	command.yaw = view.x
	command.pitch = clampf(view.y, -89.0, 89.0)


## Moves along [param direction] (world space), whatever the bot is aiming at.
func _move_world(_player, command: DotFpsCommand, direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)

	if flat.length() < 0.01:
		command.move = Vector2.ZERO
		return

	flat = flat.normalized()
	var yaw := deg_to_rad(command.yaw)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	command.move = Vector2(flat.dot(right), flat.dot(forward)).limit_length(1.0)


func _walk_to(player, command: DotFpsCommand, goal: Vector3, memory: Dictionary) -> void:
	var here: Vector3 = player.feet()
	var nav: DotNpcNavGraph = game.horde.spawner.nav if game.horde != null and game.horde.spawner != null else null
	var path: PackedVector3Array = memory["path"]

	if nav != null and nav.is_ready() and (game.now() - float(memory["path_at"]) > 1.0 \
			or (memory["goal"] as Vector3).distance_to(goal) > 2.0 or path.is_empty()):
		# Its own filter: the graph keeps the last searcher's, and a zombie's would send a
		# stand-in off a balcony.
		var kept = nav.filter
		if nav.has_method(&"relabel"):
			nav.filter = nav.bot_filter
		path = nav.find_smooth_path(here, goal, 2.5, true)
		nav.filter = kept
		memory["path"] = path
		memory["path_at"] = game.now()
		memory["goal"] = goal

	var next := goal

	while not path.is_empty():
		if Vector2(path[0].x - here.x, path[0].z - here.z).length() < 0.9:
			path.remove_at(0)
			memory["path"] = path
			continue
		next = path[0]
		break

	if not _aiming:
		# Not aiming at anything: look where it is going, turning there as a person would
		# rather than snapping round at every corner of the path.
		var aim: DotBotAim = memory["aim"]
		var eye: Vector3 = player.eye_position()
		var view := aim.look_at_point(eye, Vector3(next.x, eye.y, next.z), _dt)
		command.yaw = view.x
		command.pitch = view.y

	var heading := next - here
	heading.y = 0.0
	var quiet := _sleeper_near(player, 11.0)

	# Past a sleeper: at a walk, and edging away from her. Running by within seven metres is
	# what wakes her, and a stand-in that does it loses a teammate.
	if quiet != Vector3.INF:
		command.set_button(DotFpsCommand.BUTTON_WALK, true)
		var away := here - quiet
		away.y = 0.0
		if away.length() < 9.0 and heading.length() > 0.01:
			heading = heading.normalized() + away.normalized() * (9.0 - away.length()) * 0.25

	_move_world(player, command, heading)
	_unstick(player, command, memory)


func _follow(player, command: DotFpsCommand, memory: Dictionary) -> void:
	var leader = _leader(player)

	if leader == null or leader == player:
		var goal := _route_goal(player)
		if goal != Vector3.INF:
			_walk_to(player, command, goal, memory)
		return

	var gap: float = leader.feet().distance_to(player.feet())

	if gap > FOLLOW_FAR or (gap > FOLLOW_NEAR and leader.controller.state.horizontal_speed() > 1.0):
		_walk_to(player, command, leader.feet(), memory)


## Whom to keep up with: the human furthest along, or, with no humans, the bot furthest along —
## which is how a team of stand-ins walks a map at all.
func _leader(player):
	var best = null
	var best_flow := -INF
	var humans := false

	for other in game.survivors():
		if other.is_up() and not other.is_bot and not other.watching:
			humans = true
			break

	var flow = game.horde.director.flow if game.horde != null and game.horde.director != null else null

	for other in game.survivors():
		if not other.is_up() or other.watching or (humans and other.is_bot):
			continue

		var f: float = flow.flow_of(other.feet()) if flow != null and flow.has_route() else -other.feet().distance_to(player.feet())

		if best == null or f > best_flow:
			best = other
			best_flow = f

	return best


## Where a leading stand-in walks: to the objective while there is one to do (and to stand by
## it while it is held), then on into the end area.
func _route_goal(player) -> Vector3:
	var doc: Dictionary = game.map_doc
	var ends: Array = (doc.get("areas", {}) as Dictionary).get("end", [])
	var index: int = game.current_objective()

	if index >= 0:
		return ZzMapDoc.v3(((doc["objectives"] as Array)[index] as Dictionary)["at"])

	if game.is_survival():
		var spawns: Array = (doc.get("spawns", {}) as Dictionary).get("survivors", [])
		return ZzMapDoc.v3((spawns[0] as Dictionary)["at"]) if not spawns.is_empty() else Vector3.INF

	if not ends.is_empty():
		return ZzMapDoc.area_box(ends[0]).get_center() - Vector3(0.0, ZzMapDoc.area_box(ends[0]).size.y * 0.5 - 0.2, 0.0)

	return Vector3.INF


## Works the current objective when the team is there: walks to it and holds E.
func _objective(player, command: DotFpsCommand, memory: Dictionary) -> bool:
	var index: int = game.current_objective()

	if index < 0 or game.objective_states[index] != &"waiting":
		return false

	var o: Dictionary = (game.map_doc["objectives"] as Array)[index]
	var at := ZzMapDoc.v3(o["at"])

	# Only once the leader is near it: a stand-in that ran ahead and started an alarm on its own
	# is a stand-in that killed the team.
	var leader = _leader(player)

	if leader != null and leader != player and leader.feet().distance_to(at) > 12.0:
		return false

	if player.eye_position().distance_to(at) <= float(o["radius"]) + 0.4:
		_aim(player, command, at)
		if o["kind"] == "use":
			player.actions |= ZzNetCommand.ACT_USE
		return true

	_walk_to(player, command, at, memory)
	return true


## How far off an item is taken on, and how long a stand-in tries for one before leaving it be.
const PICK_UP_REACH := 7.0
const PICK_UP_GIVE_UP := 15.0


## Picks up what it needs within a few metres: a medkit without one, pills, ammo when low, a box.
func _pick_up(player, command: DotFpsCommand, memory: Dictionary) -> bool:
	var loot = game.loot

	if loot == null:
		return false

	var best := -1
	var best_gap := PICK_UP_REACH
	var kept := int(memory.get("pick", -1))

	# An item taken on is kept until it is had, gone or PICK_UP_GIVE_UP seconds old: the path to
	# one 7 m away can lead off the other way, and re-judging by straight distance each tick
	# made the stand-in alternate between it and its post, standing still.
	if kept >= 0 and (not loot.entries.has(kept) or game.now() > float(memory.get("pick_until", 0.0))):
		memory["pick"] = -1
		memory["pick_ignore"] = kept if loot.entries.has(kept) else -1
		memory["pick_ignore_until"] = game.now() + 30.0
		# A shelf behind boards holds several goods: giving up one gives up its neighbours too, or each costs a full give-up in turn.
		memory["pick_ignore_at"] = (loot.entries[kept]["at"] as Vector3) if loot.entries.has(kept) else Vector3.INF
		kept = -1

	for id: int in loot.entries:
		var e: Dictionary = loot.entries[id]
		var gap: float = (e["at"] as Vector3).distance_to(player.feet())

		if id == int(memory.get("pick_ignore", -1)) and game.now() < float(memory.get("pick_ignore_until", 0.0)):
			continue

		if game.now() < float(memory.get("pick_ignore_until", 0.0)) and (e["at"] as Vector3).distance_to(memory.get("pick_ignore_at", Vector3.INF)) < 6.5:
			continue

		if gap > best_gap and id != kept:
			continue

		# Shelf goods cost points: a stand-in that cannot pay would stand pressing use on it.
		if int(e.get("price", 0)) > player.points:
			continue

		var wanted := false

		match e["kind"]:
			ZzLoot.MEDKIT:
				wanted = player.medkits == 0
			ZzLoot.PILLS:
				wanted = player.pills == 0
			ZzLoot.AMMO:
				wanted = _low_on_ammo(player)
			ZzLoot.BOX:
				wanted = game.config.bot_open_boxes and (game.config.box_carry <= 0 or (game.boxes != null and game.boxes.can_carry(player)))
			ZzLoot.WEAPON, ZzLoot.THROWABLE:
				wanted = _wants_weapon(player, e["item"])

		if wanted and id == kept:
			best = id
			break

		if wanted:
			best = id
			best_gap = gap

	if best < 0:
		memory["pick"] = -1
		return false

	if best != kept:
		memory["pick"] = best
		memory["pick_until"] = game.now() + PICK_UP_GIVE_UP

	var at: Vector3 = loot.position_of(best)

	if player.eye_position().distance_to(at) <= game.config.use_reach:
		_aim(player, command, at + Vector3(0.0, 0.25, 0.0))
		player.actions |= ZzNetCommand.ACT_USE
		# A fresh press each time: E on a box is held, on the rest pressed.
		if loot.kind_of(best) != ZzLoot.BOX and game.current_tick() % 6 >= 3:
			player.actions &= ~ZzNetCommand.ACT_USE
	else:
		_walk_to(player, command, at, memory)

	return true


## Whether [param id] is better than what [param player] has in its slot: anything in an empty
## slot, a primary over a sidearm-only hand. A stand-in does not trade one rifle for another.
func _wants_weapon(player, id: StringName) -> bool:
	if player.weapons == null or player.weapons.arsenal == null:
		return true

	var def: DotWeaponDef = ZzWeapons.def_of(id)

	if def == null:
		return false

	return not player.weapons.arsenal.has_slot(def.slot)


func _low_on_ammo(player) -> bool:
	if player.weapons == null or player.weapons.arsenal == null:
		return false

	var arsenal: DotWeaponArsenal = player.weapons.arsenal

	for pool in arsenal.ammo().pools():
		if arsenal.ammo().count(pool) < arsenal.ammo().cap(pool) * 0.3:
			return true

	return false


## Standing in acid or fire: step out of it, whatever else.
func _get_out_of_hazards(player, command: DotFpsCommand) -> void:
	if game.hazards == null:
		return

	for id: int in game.hazards.areas:
		var a: Dictionary = game.hazards.areas[id]

		if a["kind"] == &"heal":
			continue

		var away: Vector3 = player.feet() - (a["at"] as Vector3)
		away.y = 0.0

		if away.length() < float(a["radius"]) + 0.5:
			_move_world(player, command, away if away.length() > 0.1 else Vector3.RIGHT)
			return


## Hops that have not freed a stand-in before the game steps it along (`ZzUnstick`).
const HOPS_BEFORE_NUDGE := 2

## Seconds a stand-in stays put, hopping and stepping, before it is put on clear ground.
const STUCK_BEFORE_RELOCATE := 8.0

## Metres from where it began that count as having got away.
const STUCK_AREA := 2.5

## Metres a stand-in may jitter and still be stuck (the stuck meter's own 0.75, with a little over).
const STUCK_RADIUS := 0.8


func _unstick(player, command: DotFpsCommand, memory: Dictionary) -> void:
	var here: Vector3 = player.feet()
	var mark: Vector3 = memory["stuck_at"]

	if mark == Vector3.INF or here.distance_to(mark) > STUCK_RADIUS:
		memory["stuck_at"] = here
		memory["stuck_time"] = game.now()
		memory["hops"] = 0

		# A step does not end the spell: only getting away from where it began does.
		if not memory.has("first_at") or here.distance_to(memory["first_at"]) > STUCK_AREA:
			memory["first_at"] = here
			memory["stuck_first"] = game.now()

		return

	if command.move.length() > 0.5 and game.now() - float(memory["stuck_time"]) > 1.0:
		command.set_button(DotFpsCommand.BUTTON_JUMP, true)
		memory["path"] = PackedVector3Array()
		memory["stuck_time"] = game.now()
		memory["hops"] = int(memory.get("hops", 0)) + 1

		# A hop that has not freed it twice will not: a step along where it was going, if it fits.
		if int(memory["hops"]) > HOPS_BEFORE_NUDGE:
			var yaw := deg_to_rad(command.yaw)
			var heading := Vector3(cos(yaw), 0.0, -sin(yaw)) * command.move.x + Vector3(-sin(yaw), 0.0, -cos(yaw)) * command.move.y
			var moved := ZzUnstick.nudge_player(player, heading, command.yaw)
			memory["hops"] = 0
			memory["nudges"] = int(memory.get("nudges", 0)) + (1 if moved else 0)

		# Steps have not freed it either (inside a barricade, in the lee of a prop): onto clear ground.
		if game.now() - float(memory.get("stuck_first", game.now())) > STUCK_BEFORE_RELOCATE:
			var aim: Vector3 = memory["goal"] if (memory["goal"] as Vector3) != Vector3.INF else here
			memory["stuck_first"] = game.now()

			if ZzUnstick.relocate_player(player, aim, command.yaw):
				memory["relocations"] = int(memory.get("relocations", 0)) + 1
