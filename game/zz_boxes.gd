extends RefCounted

const ZzBoxInstakill := preload("zz_box_instakill.gd")
const ZzBoxSpeed := preload("zz_box_speed.gd")
const ZzController := preload("zz_controller.gd")
const ZzHazards := preload("zz_hazards.gd")
const ZzLoot := preload("zz_loot.gd")
const ZzNpcs := preload("zz_npcs.gd")
const ZzPaths := preload("zz_paths.gd")
const ZzWeapons := preload("zz_weapons.gd")

## The boxes: something a zombie drops, a survivor opens, and nobody knows what is inside.
##
## [b]Data, all of it.[/b] What box types there are, what each can do, how likely each outcome is
## and which zombies drop which are `boxes/boxes.json`, which a server owner edits. An outcome is
## a list of ACTIONS, and an action is a verb this file knows with its own parameters:
##
## [codeblock]
## {"id": "explosive", "title": "Explosive Box", "colour": "#e04a2a",
##  "drop": {"common": 3, "special": 5, "brute": 2, "map": 2},
##  "outcomes": [
##    {"id": "airstrike", "title": "Airstrike!", "weight": 4,
##     "message": "{name} called it in on the people next to them.",
##     "actions": [{"do": "airstrike", "target": "nearest", "count": 3, "damage": 60}]},
##    ...]}
## [/codeblock]
##
## The verbs are listed in [constant ACTIONS] and documented at each `_do_` method; `who` picks
## whom a survivor-side action touches (`opener`, `team`, `others`, `near`, `random`, `nearest`,
## `downed`, `dead`). An unknown verb is refused when the file is read, never skipped at the moment
## a box is opened.
##
## [b]Stacks.[/b] Anything that changes the game for a while — the horde coming twice as often,
## the specials taking half again as much — is an EFFECT with a scale and an end, and effects of
## the same kind multiply. Open two horde boxes that each double the mob rate and it is four times.
## [method effects_summary] is what the HUD shows ("Horde frenzy x4, 1:12").
##
## [b]A box is carried, then deployed.[/b] E on a box lying about puts it in the carried slot
## ([member ZzConfig.box_carry] of them); holding the deploy key for `box_deploy_seconds` opens it.
## With `box_labels` off the type of a box on the ground and in the slot is not sent
## ([method shown_item]).
##
## [b]A box that lasts is a NAMED effect.[/b] A type carries `polarity`, `impact` (self, radius,
## everyone, game), `radius`, `stacks`, `max_stacks`, `duration` ({mode: instant|seconds|round,
## min, max}, drawn uniformly when it is opened) and `survives_round`; an outcome's
## `{"do": "effect", "name": "instakill"}` starts the handler named in [constant HANDLERS] under
## that spec. The registry here owns the clock, the stack count and the end of the round
## ([method end_round]); the handler (see `zz_box_effect.gd`) owns only what the box does.

const CHANNEL := "zz.boxes"

## What every box is called on the wire when `box_labels` is off.
const UNKNOWN := &"unknown"

const FORMAT := 1

## Every verb an outcome may use.
const ACTIONS: Array[String] = [
	"heal", "temp_health", "hurt", "revive", "rescue", "give_weapon", "give_ammo", "give_item",
	"haste", "low_gravity", "heavy", "invulnerable", "damage_boost", "bile", "burn", "teleport",
	"knock", "blind", "mob", "special", "brute", "kill_zombies", "freeze_zombies", "ignite_zombies",
	"lure", "pace", "panic", "explode", "airstrike", "fire", "acid", "heal_zone", "molotov_rain",
	"drop_boxes", "message", "random", "swap", "shuffle_weapons", "clear_effects", "effect", "turret",
]

## The named boxes' handlers: effect name -> script (see zz_box_effect.gd). A later box is one line
## here, one small file, and a type in boxes.json.
const HANDLERS := {"instakill": ZzBoxInstakill, "move_speed": ZzBoxSpeed, "crawl_speed": ZzBoxSpeed}

const POLARITIES: Array[String] = ["positive", "negative", "mixed"]
const IMPACTS: Array[String] = ["self", "radius", "everyone", "game"]
const MODES: Array[String] = ["instant", "seconds", "round"]

## What `pace` may change, and its title on the HUD.
const PACE_TITLES := {
	"mob_rate": "Horde frenzy", "mob_size": "Bigger hordes", "special_rate": "Specials swarm",
	"special_health": "Hardened specials", "zombie_speed": "Fast zombies",
}

signal opened(player_id: StringName, type_id: StringName, outcome: String, message: String)
signal effects_changed()

## The game (`zz_game.gd`), untyped: it preloads this file.
var game = null

## type id -> {id, title, colour, drop: {source: weight}, outcomes: [...]}
var types: Dictionary = {}
var order: Array[StringName] = []

## Active effects: {what, scale, until, title, who}. `who` is empty for the whole game.
var effects: Array[Dictionary] = []

## Handler instances by effect name, made on first use. A game may add its own with
## [method register_handler].
var _handlers: Dictionary = {}
var _next_effect: int = 1

var _rng := RandomNumberGenerator.new()


func _init(p_game: Object) -> void:
	game = p_game
	_rng.seed = 1771


# --- Reading -------------------------------------------------------------------------------

func load_file(path: String) -> int:
	var full := ZzPaths.rebase("res://" + path.trim_prefix("res://"))
	var text := FileAccess.get_file_as_string(full)

	if text == "":
		DotLog.warn(CHANNEL, "no box file; boxes are off", {"path": full})
		return 0

	var loaded := load_text(text)

	if not loaded.ok:
		DotLog.error(CHANNEL, "the box file is refused", {"why": loaded.error.message, "detail": loaded.error.detail})
		return 0

	DotLog.info(CHANNEL, "boxes loaded", {"types": types.size()})
	return types.size()


## Reads and checks a box document. Refuses the whole file on the first bad entry, naming it.
func load_text(text: String) -> DotResult:
	var parsed: Variant = JSON.parse_string(text)

	if not (parsed is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "The box file is not a JSON object.")

	var doc := parsed as Dictionary

	if int(doc.get("format", 0)) != FORMAT:
		return DotResult.fail(DotError.CODE_INVALID, "The box file's format is not %d." % FORMAT)

	var out := {}
	var ids: Array[StringName] = []

	for raw: Variant in doc.get("boxes", []):
		if not (raw is Dictionary):
			return DotResult.fail(DotError.CODE_INVALID, "A box is not an object.")

		var box := raw as Dictionary
		var id := StringName(str(box.get("id", "")))

		if id == &"" or out.has(id):
			return DotResult.fail(DotError.CODE_INVALID, "A box has no id, or a second one with the same id.", String(id))

		var outcomes: Array = []

		for o: Variant in box.get("outcomes", []):
			if not (o is Dictionary):
				return DotResult.fail(DotError.CODE_INVALID, "An outcome of %s is not an object." % id)

			var checked := _check_actions((o as Dictionary).get("actions", []), "%s/%s" % [id, str((o as Dictionary).get("id", "?"))])

			if not checked.ok:
				return checked

			outcomes.append({
				"id": str((o as Dictionary).get("id", "outcome")),
				"title": str((o as Dictionary).get("title", "")),
				"weight": maxf(float((o as Dictionary).get("weight", 1.0)), 0.0),
				"message": str((o as Dictionary).get("message", "")),
				"actions": (o as Dictionary).get("actions", []),
			})

		if outcomes.is_empty():
			return DotResult.fail(DotError.CODE_INVALID, "Box %s has no outcomes." % id)

		var schema := _read_schema(box, id)

		if not schema.ok:
			return schema

		out[id] = {
			"id": id,
			"title": str(box.get("title", String(id).capitalize())),
			"colour": str(box.get("colour", "#d0a040")),
			"drop": box.get("drop", {}),
			"outcomes": outcomes,
		}
		out[id].merge(schema.value)
		ids.append(id)

	if out.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "The box file has no boxes.")

	types = out
	order = ids
	return DotResult.success(types.size())


## The schema half of a box: polarity, impact, radius, stacks, max_stacks, duration, survives_round
## and params, defaulted and checked. A bad enum refuses the file, naming the box.
func _read_schema(box: Dictionary, id: StringName) -> DotResult:
	var polarity := str(box.get("polarity", "mixed"))
	var impact := str(box.get("impact", "self"))

	if not POLARITIES.has(polarity):
		return DotResult.fail(DotError.CODE_INVALID, "Box %s: polarity '%s' is not one of %s." % [id, polarity, ", ".join(POLARITIES)])

	if not IMPACTS.has(impact):
		return DotResult.fail(DotError.CODE_INVALID, "Box %s: impact '%s' is not one of %s." % [id, impact, ", ".join(IMPACTS)])

	var raw: Variant = box.get("duration", {})
	var spec: Dictionary = raw if raw is Dictionary else {}
	var mode := str(spec.get("mode", "instant"))

	if not MODES.has(mode):
		return DotResult.fail(DotError.CODE_INVALID, "Box %s: duration mode '%s' is not one of %s." % [id, mode, ", ".join(MODES)])

	var low := maxf(float(spec.get("min", 0.0)), 0.0)
	var high := maxf(float(spec.get("max", low)), low)

	return DotResult.success({
		"polarity": polarity,
		"impact": impact,
		"radius": maxf(float(box.get("radius", 0.0)), 0.0),
		"stacks": bool(box.get("stacks", true)),
		"max_stacks": maxi(int(box.get("max_stacks", 99)), 1),
		"duration": {"mode": mode, "min": low, "max": high},
		"survives_round": bool(box.get("survives_round", false)),
		"params": box.get("params", {}),
	})


func _check_actions(actions: Variant, where: String) -> DotResult:
	if not (actions is Array):
		return DotResult.fail(DotError.CODE_INVALID, "%s: 'actions' is not a list." % where)

	for a: Variant in actions:
		if not (a is Dictionary) or not ACTIONS.has(str((a as Dictionary).get("do", ""))):
			return DotResult.fail(DotError.CODE_INVALID,
				"%s: '%s' is not something a box can do." % [where, str((a as Dictionary).get("do", "?")) if a is Dictionary else str(a)],
				", ".join(ACTIONS))

		if str((a as Dictionary)["do"]) == "effect" and not HANDLERS.has(str((a as Dictionary).get("name", ""))) \
				and not _handlers.has(str((a as Dictionary).get("name", ""))):
			return DotResult.fail(DotError.CODE_INVALID, "%s: no box effect is named '%s'." % [where, str((a as Dictionary).get("name", "?"))],
				", ".join(HANDLERS.keys()))

		if str((a as Dictionary)["do"]) == "random":
			for choice: Variant in (a as Dictionary).get("choices", []):
				var inner := _check_actions(choice, where + "/random")
				if not inner.ok:
					return inner

	return DotResult.success(null)


func title_of(type_id: StringName) -> String:
	return str((types.get(type_id, {}) as Dictionary).get("title", String(type_id)))


func colour_of(type_id: StringName) -> Color:
	var text := str((types.get(type_id, {}) as Dictionary).get("colour", "#d0a040"))
	return Color.html(text) if Color.html_is_valid(text) else Color(0.8, 0.6, 0.25)


# --- Dropping -------------------------------------------------------------------------------

## A zombie of [param kind] died at [param at]: maybe a box.
func maybe_drop(kind: StringName, at: Vector3) -> void:
	if types.is_empty():
		return

	var source := &"common"
	var chance: float = game.config.box_drop_common

	if kind == ZzNpcs.BRUTE:
		source = &"brute"
		chance = game.config.box_drop_brute
	elif ZzNpcs.is_special(kind):
		source = &"special"
		chance = game.config.box_drop_special

	if _rng.randf() >= chance:
		return

	drop(random_type(source, _rng), at)


## Puts a box of [param type_id] on the ground at [param at].
func drop(type_id: StringName, at: Vector3) -> int:
	if not types.has(type_id):
		return -1

	var loot = game.loot

	while loot.count_of(ZzLoot.BOX) >= game.config.max_boxes:
		loot.remove(loot.oldest(ZzLoot.BOX))

	var ground: Vector3 = game.ray_hit(at + Vector3(0.0, 1.0, 0.0), at + Vector3(0.0, -4.0, 0.0))
	return loot.add(ZzLoot.BOX, type_id, ground if ground != Vector3.INF else at, game.config.box_lifetime)


## A type drawn by its drop weight for [param source] (`common`, `special`, `brute`, `map`).
func random_type(source: StringName, rng: RandomNumberGenerator) -> StringName:
	var total := 0.0

	for id in order:
		total += _drop_weight(id, source)

	var roll := rng.randf() * total

	for id in order:
		roll -= _drop_weight(id, source)

		if roll <= 0.0:
			return id

	return order[0] if not order.is_empty() else &""


## How likely [param id] is to drop from [param source]: 0 when every outcome it has is a named
## effect that says it would do nothing here (a crawl box where nobody can crawl).
func _drop_weight(id: StringName, source: StringName) -> float:
	var box: Dictionary = types[id]

	if not _has_use(box):
		return 0.0

	return float((box["drop"] as Dictionary).get(String(source), 1.0))


func _has_use(box: Dictionary) -> bool:
	for outcome: Dictionary in box["outcomes"]:
		var useful := true

		for a: Dictionary in outcome["actions"]:
			if str(a.get("do", "")) != "effect":
				continue

			var handler := _handler(StringName(str(a.get("name", ""))))

			if handler != null and not handler.available(self, box.get("params", {})):
				useful = false

		if useful:
			return true

	return false


# --- Carrying ------------------------------------------------------------------------------

## What a client is told about a box of [param type_id] on the ground or in a slot: the type when
## `box_labels` is on, else one word for every box, so the type never leaves the server.
func shown_item(type_id: StringName) -> StringName:
	return type_id if game.config.box_labels else UNKNOWN


## Whether [param player] has a free slot. With `box_carry` 0 nobody carries.
func can_carry(player) -> bool:
	return game.config.box_carry > 0 and player.carried.size() < game.config.box_carry


## Puts a box of [param type_id] in [param player]'s hands.
func carry(player, type_id: StringName) -> bool:
	if not types.has(type_id) or not can_carry(player):
		return false

	player.carried.append(type_id)
	return true


## [param player] let go of the first box they carry, opened where they stand.
func deploy(player) -> void:
	if player.carried.is_empty():
		return

	var type_id: StringName = player.carried.pop_front()
	open(type_id, player, player.feet())


## Everything [param player] carries falls at their feet (a down, a death).
func drop_carried(player) -> void:
	var n := 0

	for type_id in player.carried:
		var angle := float(n) * 2.4
		var _id := drop(type_id, player.feet() + Vector3(cos(angle), 0.0, sin(angle)) * 0.7)
		n += 1

	player.carried.clear()


# --- Opening -------------------------------------------------------------------------------

## [param player] opened a box of [param type_id] at [param at].
func open(type_id: StringName, player, at: Vector3) -> void:
	var box: Dictionary = types.get(type_id, {})

	if box.is_empty():
		return

	var outcome := _pick(box["outcomes"])
	var ctx := {"opener": player, "at": at, "box": type_id}
	run(outcome["actions"], ctx)

	if ctx.get("refused", false):
		return

	var message := str(outcome["message"]).replace("{name}", player.display_name)
	opened.emit(player.player_id, type_id, str(outcome["title"]), message)

	if game.progress != null:
		game.progress.on_box(player.player_id)

	DotLog.info(CHANNEL, "a box was opened", {
		"by": String(player.player_id), "box": String(type_id), "outcome": str(outcome["id"]),
	})


func _pick(outcomes: Array) -> Dictionary:
	var total := 0.0

	for o: Dictionary in outcomes:
		total += float(o["weight"])

	var roll := _rng.randf() * total

	for o: Dictionary in outcomes:
		roll -= float(o["weight"])

		if roll <= 0.0:
			return o

	return outcomes.back()


## Runs a list of actions. Public so an admin command can run one by hand.
func run(actions: Array, ctx: Dictionary) -> void:
	for a: Dictionary in actions:
		var verb := str(a.get("do", ""))

		if not ACTIONS.has(verb):
			continue

		call("_do_" + verb, a, ctx)


# --- Whom ------------------------------------------------------------------------------------

func _who(a: Dictionary, ctx: Dictionary) -> Array:
	var opener = ctx["opener"]
	var everyone: Array = []

	for p in game.survivors():
		if p.is_alive() and not p.watching:
			everyone.append(p)

	match str(a.get("who", "opener")):
		"team":
			return everyone
		"others":
			return everyone.filter(func(p) -> bool: return p != opener)
		"near":
			var radius := float(a.get("radius", 8.0))
			return everyone.filter(func(p) -> bool: return p.feet().distance_to(ctx["at"]) <= radius)
		"random":
			return [everyone[_rng.randi_range(0, everyone.size() - 1)]] if not everyone.is_empty() else []
		"nearest":
			var sorted := everyone.duplicate()
			sorted.sort_custom(func(x, y) -> bool:
				return x.feet().distance_to(ctx["at"]) < y.feet().distance_to(ctx["at"]))
			return sorted.slice(0, int(a.get("count", 2)))
		"downed":
			return everyone.filter(func(p) -> bool: return p.is_down())
		"dead":
			return game.survivors().filter(func(p) -> bool: return not p.is_alive())
		_:
			return [opener] if opener != null and opener.is_alive() else []


# --- The verbs: survivors ------------------------------------------------------------------------

## Real health: `amount` points, or `fraction` of what is missing.
func _do_heal(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		if not p.is_up():
			continue
		var amount := float(a.get("amount", 0.0))
		if a.has("fraction"):
			amount = (p.health.max_health - p.real_health()) * float(a["fraction"])
		var _landed: float = p.heal_real(amount)


## Borrowed health, which drains.
func _do_temp_health(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		var _landed: float = p.grant_temp(float(a.get("amount", 30.0)))


## Damage, from nobody. Enough of it is a down.
func _do_hurt(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		var hit := DotDamage.make(0, p.entity_id, float(a.get("amount", 20.0)), game.combat.damage_type(&"strike"))
		hit.tick = game.current_tick()
		hit.weapon_id = &"box"
		hit.context = {"why": game.BY_BOX}
		var _applied = game.combat.apply_damage(hit)


## Everybody down stands up.
func _do_revive(a: Dictionary, ctx: Dictionary) -> void:
	var who := a.duplicate()
	who["who"] = a.get("who", "downed")
	for p in _who(who, ctx):
		game.stand_up(p)


## The dead come back, beside the furthest survivor.
func _do_rescue(a: Dictionary, ctx: Dictionary) -> void:
	var who := a.duplicate()
	who["who"] = a.get("who", "dead")
	for p in _who(who, ctx):
		var _back: bool = game.rescue(p)


## A weapon: `id`, or a random one of `tier` (`sidearm`, `primary`, `heavy`, `melee`, `thrown`, `any`).
func _do_give_weapon(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		var id := StringName(str(a.get("id", "")))
		if id == &"" or not ZzWeapons.exists(id):
			id = ZzWeapons.random_of(StringName(str(a.get("tier", "primary"))), _rng)
		if game.arm(p, id):
			game._draw(p, id)


func _do_give_ammo(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		var _filled := ZzLoot.give_ammo(p)
		game.ammo_given.emit(p.player_id)


## `item`: `medkit` or `pills`.
func _do_give_item(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		match str(a.get("item", "pills")):
			"medkit":
				p.medkits = 1
			_:
				p.pills = 1


func _do_haste(a: Dictionary, ctx: Dictionary) -> void:
	_modify(a, ctx, ZzController.HASTE)


func _do_low_gravity(a: Dictionary, ctx: Dictionary) -> void:
	_modify(a, ctx, ZzController.LOW_GRAVITY)


func _do_heavy(a: Dictionary, ctx: Dictionary) -> void:
	_modify(a, ctx, ZzController.HEAVY)


func _modify(a: Dictionary, ctx: Dictionary, id: StringName) -> void:
	for p in _who(a, ctx):
		if p.is_up():
			var _on: bool = p.controller.add_modifier(id)


## Nothing hurts them for `seconds`.
func _do_invulnerable(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		_add_effect("invulnerable", 1.0, float(a.get("seconds", 10.0)), "Invulnerable", p.player_id)
		p.health.invulnerable = true


## What their shots do to zombies, times `scale`, for `seconds`.
func _do_damage_boost(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		_add_effect("damage", float(a.get("scale", 2.0)), float(a.get("seconds", 30.0)), "Damage", p.player_id)


func _do_bile(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		game.bile_survivor(p.player_id, float(a.get("seconds", 12.0)), 0)


## On fire for `seconds`: `dps` a second.
func _do_burn(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		p.burning_until = maxf(p.burning_until, game.now() + float(a.get("seconds", 4.0)))
		var _pool: int = game.hazards.add(ZzHazards.FIRE, p.feet(), 1.4, float(a.get("seconds", 4.0)), float(a.get("dps", 6.0)), 0)


## `to`: `ahead` (the furthest survivor), `behind` (the start), `random` (anywhere on the graph).
func _do_teleport(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		var to := Vector3.INF

		match str(a.get("to", "random")):
			"ahead":
				var lead = game._furthest_survivor(p.player_id)
				if lead != null:
					to = lead.feet() + Vector3(0.5, 0.2, 0.5)
			"behind":
				var spot: Array = game.map.spawn("survivors", 0)
				to = spot[0]
			_:
				if game.horde != null and game.horde.nav != null and game.horde.nav.point_count() > 0:
					to = game.horde.nav.points[_rng.randi_range(0, game.horde.nav.point_count() - 1)] + Vector3(0.0, 0.3, 0.0)

		if to != Vector3.INF and not p.is_pinned():
			p.place_at(to, p.controller.state.yaw)


func _do_knock(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		if p.is_up() and not p.is_pinned():
			var dir := Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1))
			var _k: bool = p.controller.add_modifier(ZzController.knock_toward(dir))


## A flash: their screen white for `seconds` (the client's).
func _do_blind(a: Dictionary, ctx: Dictionary) -> void:
	for p in _who(a, ctx):
		_add_effect("blind", 1.0, float(a.get("seconds", 4.0)), "Blinded", p.player_id)


## Two survivors trade places.
func _do_swap(_a: Dictionary, ctx: Dictionary) -> void:
	var opener = ctx["opener"]
	var others: Array = game.survivors().filter(func(p) -> bool: return p != opener and p.is_up() and not p.is_pinned())

	if others.is_empty() or opener == null or opener.is_pinned():
		return

	var other = others[_rng.randi_range(0, others.size() - 1)]
	var here: Vector3 = opener.feet()
	opener.place_at(other.feet() + Vector3(0.0, 0.2, 0.0), opener.controller.state.yaw)
	other.place_at(here + Vector3(0.0, 0.2, 0.0), other.controller.state.yaw)


## Everybody's hands emptied and refilled with something random of the same tiers.
func _do_shuffle_weapons(a: Dictionary, ctx: Dictionary) -> void:
	var who := a.duplicate()
	who["who"] = a.get("who", "team")

	for p in _who(who, ctx):
		for tier in [&"sidearm", &"primary"]:
			var id := ZzWeapons.random_of(tier, _rng)
			var _armed: bool = game.arm(p, id)


# --- The verbs: zombies --------------------------------------------------------------------------

## A mob now: `size` commons, or `scale` times a normal mob.
func _do_mob(a: Dictionary, ctx: Dictionary) -> void:
	if game.horde == null:
		return

	var size := int(a.get("size", 0))

	if size <= 0:
		size = int(round(float(game.horde._mob_size()) * float(a.get("scale", 1.0))))

	var target := &""
	if str(a.get("at", "")) == "opener" and ctx["opener"] != null:
		target = ctx["opener"].player_id

	var _n: int = game.horde.spawn_mob(size, target)


## `count` specials of `kind` (or any), near the opener.
func _do_special(a: Dictionary, _ctx: Dictionary) -> void:
	if game.horde == null:
		return

	for i in int(a.get("count", 1)):
		var kind := StringName(str(a.get("kind", "any")))
		if kind == &"any" or not ZzNpcs.SPECIALS.has(kind):
			kind = ZzNpcs.SPECIALS[_rng.randi_range(0, ZzNpcs.SPECIALS.size() - 1)]
		var _s = game.horde.spawn_special(kind)


## Stands a sentry turret where the opener is looking (dot-combat's DotSentry; the rules are
## `zz_turrets.gd`). `seconds`, `ammo`, `damage`, `reach` and `interval` come from the outcome. When
## there is nowhere to stand it, the opener is told and the box goes back in their hands.
func _do_turret(a: Dictionary, ctx: Dictionary) -> void:
	var opener = ctx["opener"]

	if game.turrets == null or opener == null:
		return

	var res: DotResult = game.turrets.deploy(opener, a)

	if not res.ok:
		# Not spent: the box goes back in the hands it came from, and the player is told why.
		opener.carried.push_front(ctx["box"])
		ctx["refused"] = true
		game.refused.emit(opener.player_id, str(res.error.message))
		DotLog.debug(CHANNEL, "a turret was refused", {"why": res.error.detail})


func _do_brute(_a: Dictionary, _ctx: Dictionary) -> void:
	if game.horde != null:
		var _b = game.horde.spawn_brute()


## Every zombie of `kinds` (`commons`, `specials`, `all`) within `radius` of the box dies.
func _do_kill_zombies(a: Dictionary, ctx: Dictionary) -> void:
	if game.horde == null:
		return

	var kinds := str(a.get("kinds", "commons"))

	for npc in game.horde.spawner.npcs_near(ctx["at"], float(a.get("radius", 20.0))):
		if npc.def.id == ZzNpcs.BRUTE or npc.def.id == ZzNpcs.SLEEPER:
			continue
		if kinds == "commons" and npc.def.id != ZzNpcs.COMMON:
			continue
		if kinds == "specials" and npc.def.id == ZzNpcs.COMMON:
			continue
		var hit := DotDamage.make(ctx["opener"].entity_id if ctx["opener"] != null else 0,
			game.horde.entity_id_for(npc), 100000.0, game.combat.damage_type(&"blast"))
		hit.tick = game.current_tick()
		hit.weapon_id = &"box"
		var _applied = game.combat.apply_damage(hit)


## Every zombie stands still for `seconds`.
func _do_freeze_zombies(a: Dictionary, _ctx: Dictionary) -> void:
	_add_effect("freeze", 0.0, float(a.get("seconds", 8.0)), "Zombies frozen", &"")


## Every zombie within `radius` catches fire.
func _do_ignite_zombies(a: Dictionary, ctx: Dictionary) -> void:
	if game.horde == null:
		return

	for npc in game.horde.spawner.npcs_near(ctx["at"], float(a.get("radius", 25.0))):
		game.hazards.ignite(npc, float(a.get("seconds", 6.0)))


## A beeping charge where the box was: the crowd goes to it, then it goes off.
func _do_lure(a: Dictionary, ctx: Dictionary) -> void:
	var _p: int = game.hazards.launch(ZzHazards.PIPE, ctx["at"] + Vector3(0.0, 0.5, 0.0), Vector3(0.0, 1.0, 0.0), 0, float(a.get("damage", 300.0)))


## The game's pace, changed for a while; stacks. `what`: `mob_rate`, `mob_size`, `special_rate`,
## `special_health`, `zombie_speed`. `scale` multiplies it for `seconds`.
func _do_pace(a: Dictionary, _ctx: Dictionary) -> void:
	var what := str(a.get("what", "mob_rate"))

	if not PACE_TITLES.has(what):
		return

	_add_effect(what, float(a.get("scale", 1.5)), float(a.get("seconds", 120.0)), PACE_TITLES[what], &"")


func _do_panic(a: Dictionary, _ctx: Dictionary) -> void:
	if game.horde != null:
		game.horde.panic(float(a.get("seconds", 30.0)))


## A named effect (see zz_box_effect.gd) under the box's own schema: `name` is a key of
## [constant HANDLERS]. Whom it lands on follows the box's `impact`.
func _do_effect(a: Dictionary, ctx: Dictionary) -> void:
	var _fx := activate(StringName(str(a.get("name", ""))), StringName(str(ctx.get("box", ""))), ctx)


func _do_clear_effects(_a: Dictionary, _ctx: Dictionary) -> void:
	effects = effects.filter(func(e: Dictionary) -> bool: return str(e["who"]) != "")
	effects_changed.emit()


# --- The verbs: the world ------------------------------------------------------------------------

## A blast at the box (or `at`: `random_near`), `radius`, `damage`; survivors take `survivor_scale`.
func _do_explode(a: Dictionary, ctx: Dictionary) -> void:
	var at: Vector3 = ctx["at"]

	if str(a.get("at", "")) == "random_near":
		at += Vector3(_rng.randf_range(-6, 6), 0.0, _rng.randf_range(-6, 6))

	game.explode(at, float(a.get("radius", 6.0)), float(a.get("damage", 200.0)), 0, &"box", float(a.get("survivor_scale", 0.25)))


## Shells out of the sky: `count` of them, on `target` (`nearest`: the survivors closest to the
## opener, `zombies`: the thickest crowds, `team`, `random`, `opener`), `delay` seconds apart.
func _do_airstrike(a: Dictionary, ctx: Dictionary) -> void:
	var count := int(a.get("count", 3))
	var damage := float(a.get("damage", 60.0))
	var spots: Array[Vector3] = []

	match str(a.get("target", "nearest")):
		"zombies":
			if game.horde != null:
				var all: Array = game.horde.spawner.all_npcs()
				for i in count:
					if all.is_empty():
						break
					spots.append((all[_rng.randi_range(0, all.size() - 1)] as DotNpcInstance).position())
		_:
			var who := a.duplicate()
			who["who"] = {"nearest": "nearest", "team": "team", "random": "random", "opener": "opener"}.get(str(a.get("target", "nearest")), "nearest")
			who["count"] = count
			for p in _who(who, ctx):
				spots.append(p.feet())

	var delay := float(a.get("delay", 1.2))

	for i in spots.size():
		var jitter := Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))
		var _s: int = game.hazards.strike(spots[i] + jitter, delay + float(i) * 0.35, damage, 0)


## Fire round the box.
func _do_fire(a: Dictionary, ctx: Dictionary) -> void:
	var _f: int = game.hazards.add(ZzHazards.FIRE, ctx["at"], float(a.get("radius", 4.0)), float(a.get("seconds", 10.0)), float(a.get("damage", 8.0)), 0)


func _do_acid(a: Dictionary, ctx: Dictionary) -> void:
	var _f: int = game.hazards.add(ZzHazards.ACID, ctx["at"], float(a.get("radius", 3.0)), float(a.get("seconds", 7.0)), float(a.get("damage", 4.0)), 0)


func _do_heal_zone(a: Dictionary, ctx: Dictionary) -> void:
	var _h: int = game.hazards.add(ZzHazards.HEAL, ctx["at"], float(a.get("radius", 5.0)), float(a.get("seconds", 15.0)), float(a.get("rate", 4.0)), 0)


## `count` bottles from the sky round the box, within `radius`.
func _do_molotov_rain(a: Dictionary, ctx: Dictionary) -> void:
	for i in int(a.get("count", 5)):
		var angle := _rng.randf() * TAU
		var far := _rng.randf_range(2.0, float(a.get("radius", 14.0)))
		var at: Vector3 = ctx["at"] + Vector3(cos(angle) * far, 18.0, sin(angle) * far)
		var _m: int = game.hazards.launch(ZzHazards.MOLOTOV, at, Vector3(0.0, -2.0, 0.0), 0, float(a.get("damage", 8.0)))


## `count` more boxes round this one, of `type` (or random).
func _do_drop_boxes(a: Dictionary, ctx: Dictionary) -> void:
	for i in int(a.get("count", 2)):
		var type := StringName(str(a.get("type", "")))
		if not types.has(type):
			type = random_type(&"map", _rng)
		var angle := _rng.randf() * TAU
		var _d := drop(type, ctx["at"] + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(1.0, 2.5))


func _do_message(a: Dictionary, ctx: Dictionary) -> void:
	game.notice.emit(str(a.get("text", "")).replace("{name}", ctx["opener"].display_name if ctx["opener"] != null else "Somebody"))


## `pick` of `choices` (each a list of actions), at random.
func _do_random(a: Dictionary, ctx: Dictionary) -> void:
	var choices: Array = (a.get("choices", []) as Array).duplicate()

	for i in mini(int(a.get("pick", 1)), choices.size()):
		var at := _rng.randi_range(0, choices.size() - 1)
		run(choices[at], ctx)
		choices.remove_at(at)


# --- Effects -------------------------------------------------------------------------------

## Adds a handler for [param effect_name] (a script extending zz_box_effect.gd), so a game or a
## test can have a named box without editing [constant HANDLERS].
func register_handler(effect_name: StringName, script: Script) -> void:
	_handlers[String(effect_name)] = script.new()


func _handler(effect_name: StringName) -> Object:
	var key := String(effect_name)

	if not _handlers.has(key) and HANDLERS.has(key):
		_handlers[key] = (HANDLERS[key] as Script).new()

	return _handlers.get(key)


## The seconds a box lasts, drawn uniformly from its range now: 0 for instant, -1 for the round.
## A handler may adjust the range first (Instakill's cvars).
func roll_duration(box_id: StringName, effect_name: StringName = &"") -> float:
	var box: Dictionary = types.get(box_id, {})
	var spec: Dictionary = box.get("duration", {"mode": "instant", "min": 0.0, "max": 0.0})
	var handler := _handler(effect_name)

	if handler != null:
		spec = handler.duration(game.config, spec)

	match str(spec["mode"]):
		"round":
			return -1.0
		"seconds":
			return _rng.randf_range(float(spec["min"]), maxf(float(spec["max"]), float(spec["min"])))

	return 0.0


## Starts the named effect [param effect_name] for the box [param box_id] opened as [param ctx]
## (`opener`, `at`). Returns the first entry it started or refreshed, or an empty dictionary. Who it
## lands on is the box's `impact`; a repeat of a non-stacking effect on the same holder only
## lengthens it, and a stacking one adds a stack up to `max_stacks`, then also only lengthens.
func activate(effect_name: StringName, box_id: StringName, ctx: Dictionary) -> Dictionary:
	var handler := _handler(effect_name)

	if handler == null:
		return {}

	var box: Dictionary = types.get(box_id, {})
	var seconds := roll_duration(box_id, effect_name)
	var holders: Array[StringName] = []

	match str(box.get("impact", "game")):
		"self":
			if ctx.get("opener") != null:
				holders.append((ctx["opener"] as Object).get("player_id"))
		"everyone":
			for p in _who({"who": "team"}, ctx):
				holders.append(p.player_id)
		"radius":
			for p in _who({"who": "near", "radius": float(box.get("radius", 8.0))}, ctx):
				holders.append(p.player_id)
		_:
			holders.append(&"")

	var first := {}

	for who in holders:
		var fx := _start_one(handler, effect_name, box, box_id, seconds, who, ctx)

		if first.is_empty():
			first = fx

	if not holders.is_empty():
		_apply()
		effects_changed.emit()

	return first


func _start_one(handler: Object, effect_name: StringName, box: Dictionary, box_id: StringName, seconds: float, who: StringName, ctx: Dictionary) -> Dictionary:
	var now: float = game.now()
	var until := -1.0 if seconds < 0.0 else now + seconds
	var found := _find(String(effect_name), who)

	if not found.is_empty():
		# A longer one replaces the clock; a shorter one never cuts the first short.
		found["until"] = -1.0 if (until < 0.0 or float(found["until"]) < 0.0) else maxf(float(found["until"]), until)

		if bool(box.get("stacks", false)) and int(found["stacks"]) < int(box.get("max_stacks", 1)):
			found["stacks"] = int(found["stacks"]) + 1
			handler.on_stack(self, found)

		return found

	var fx := {
		"id": _next_effect, "what": String(effect_name), "scale": 1.0, "until": until, "title": str(box.get("title", String(effect_name))),
		"who": String(who), "box": String(box_id), "stacks": 1, "max_stacks": int(box.get("max_stacks", 1)),
		"impact": str(box.get("impact", "game")), "polarity": str(box.get("polarity", "mixed")),
		"radius": float(box.get("radius", 0.0)), "survives_round": bool(box.get("survives_round", false)),
		"params": box.get("params", {}), "data": {}, "handler": handler, "started": now,
	}
	_next_effect += 1

	if seconds == 0.0:
		handler.on_start(self, fx, ctx)
		handler.on_end(self, fx)
		return fx

	effects.append(fx)
	handler.on_start(self, fx, ctx)
	return fx


func _find(what: String, who: StringName) -> Dictionary:
	for e in effects:
		if e["what"] == what and str(e["who"]) == String(who) and e.has("handler"):
			return e

	return {}


func _add_effect(what: String, scale: float, seconds: float, title: String, who: StringName) -> void:
	effects.append({"what": what, "scale": scale, "until": game.now() + seconds, "title": title, "who": String(who),
		"impact": "game" if who == &"" else "self", "stacks": 1, "survives_round": false})
	_apply()
	effects_changed.emit()


## Clears every effect, for a new map; the carried boxes go with it.
func reset() -> void:
	for p in game.survivors():
		if p.health != null:
			p.health.invulnerable = false

		p.carried.clear()

	_end(effects.duplicate())


## The round (a survival wave, or a whole map) is over: every effect that changes the game ends,
## unless its box says `survives_round`, and so does anything that was to last the round. One
## that touched only a survivor and had its own clock runs on.
func end_round() -> void:
	_end(effects.filter(func(e: Dictionary) -> bool:
		return float(e["until"]) < 0.0 or (str(e.get("impact", "game")) == "game" and not bool(e.get("survives_round", false)))))


func tick(delta: float) -> void:
	var now: float = game.now()
	_end(effects.filter(func(e: Dictionary) -> bool: return float(e["until"]) >= 0.0 and float(e["until"]) <= now))

	for e in effects:
		if e.has("handler"):
			(e["handler"] as Object).on_tick(self, e, delta)


## Takes [param gone] out of the list, tells each one's handler, undoes the old invulnerability.
func _end(gone: Array) -> void:
	if gone.is_empty():
		return

	effects = effects.filter(func(e: Dictionary) -> bool: return not gone.has(e))

	for e in gone:
		if e.has("handler"):
			(e["handler"] as Object).on_end(self, e)

		if e["what"] == "invulnerable":
			var p = game.player_by_id(StringName(str(e["who"])))
			if p != null and p.health != null and not _has(p.player_id, "invulnerable"):
				p.health.invulnerable = false

	_apply()
	effects_changed.emit()


## What a survivor's shot does to a zombie of [param kind] once the active effects have had their say.
func zombie_damage(kind: StringName, max_health: float, amount: float) -> float:
	for e in effects:
		if e.has("handler"):
			amount = (e["handler"] as Object).modify_zombie_damage(self, e, kind, max_health, amount)

	return amount


## Whether the named effect is on (for [param who], or the whole game by default).
func is_active(effect_name: StringName, who: StringName = &"") -> bool:
	return not _find(String(effect_name), who).is_empty()


## Pushes the game-wide effects into the horde.
func _apply() -> void:
	var horde = game.horde

	if horde == null:
		return

	horde.mob_rate_scale = _product("mob_rate")
	horde.mob_size_scale = _product("mob_size")
	horde.special_rate_scale = _product("special_rate")
	horde.special_health_scale = _product("special_health")
	horde.zombie_speed_scale = _product("zombie_speed") * (0.0 if _has(&"", "freeze") else 1.0)


func _product(what: String) -> float:
	var out := 1.0

	for e in effects:
		if e["what"] == what and str(e["who"]) == "":
			out *= float(e["scale"])

	return out


func _has(who: StringName, what: String) -> bool:
	for e in effects:
		if e["what"] == what and str(e["who"]) == String(who):
			return true

	return false


## What [param player_id]'s shots do, as a multiple.
func damage_scale_for(player_id: StringName) -> float:
	var out := 1.0

	for e in effects:
		if e["what"] == "damage" and str(e["who"]) == String(player_id):
			out *= float(e["scale"])

	return out


func is_blind(player_id: StringName) -> bool:
	return _has(player_id, "blind")


## What the HUD lists: one line per kind of effect, with its stack count and the longest time
## left. `[{title, stacks, seconds, who}]`.
func effects_summary() -> Array:
	var grouped := {}
	var now: float = game.now()

	for e in effects:
		var key := "%s|%s" % [e["what"], e["who"]]

		if not grouped.has(key):
			grouped[key] = {"title": e["title"], "stacks": 0, "seconds": 0.0, "who": _who_name(StringName(str(e["who"]))), "scale": 1.0}

		var g: Dictionary = grouped[key]
		g["stacks"] = int(g["stacks"]) + int(e.get("stacks", 1))
		# -1: until the round ends. It wins over any clock.
		if float(e["until"]) < 0.0 or float(g["seconds"]) < 0.0:
			g["seconds"] = -1.0
		else:
			g["seconds"] = maxf(float(g["seconds"]), float(e["until"]) - now)
		g["scale"] = float(g["scale"]) * float(e["scale"])

	return grouped.values()


## Who an effect is on, as the HUD prints it: a name, not a player key a person never sees.
func _who_name(who: StringName) -> String:
	if who == &"":
		return "everybody"

	var player = game.player_by_id(who)
	return player.display_name if player != null else String(who)


func describe() -> Dictionary:
	return {"types": types.size(), "effects": effects.size()}
