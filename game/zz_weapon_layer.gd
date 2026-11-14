extends RefCounted

const ZzWeapons := preload("zz_weapons.gd")
const ZzPickupPanel := preload("zz_pickup_panel.gd")

## Weapons lying in the world, thrown with the drop key (Q) or left by the dead: dot-weapon's
## [DotWeaponDrops] under `sv_weapon_drop*`, with the survivor's hands and carry rules as the hooks.
## An empty slot in reach takes a drop (so weight and quota still apply); a full slot swaps.

const CHANNEL := "zz.weapon_layer"

## Slot 1 is the melee weapon, which a survivor never puts down.
const KEEP_SLOTS: Array[int] = [1]

## The weapon a throw takes out of the hand, and the damage of a hit (a zombie has hundreds of health at most).
const KNIFE_WEAPON := &"zz_knife"
const KNIFE_DAMAGE := 120.0

var rules := DotWeaponDropRules.new()
var drops: DotWeaponDrops = null
## The aim key throws the knife in hand ([DotWeaponKnives], `zz_knife_throw*`). A thrown knife is a
## weapon like any other, so it hurts what the horde is made of: the default is a hard hit, not a kill.
var knives: DotWeaponKnives = null
var knife_rules: Dictionary = DotWeaponKnives.DEFAULT_RULES.duplicate()
## Entity ids whose aim key was last handed to [member knives] down.
var _aim_sent: Dictionary = {}
## Entity ids whose drop key was last stepped released: stepping a released key again changes nothing,
## and [method DotWeaponDropKey.step] resolves the drop rules first (about 80 us a call), so it is skipped.
var _drop_up: Dictionary = {}
var game = null


func _init(p_game: Object) -> void:
	game = p_game


## Builds the layer under the game (both sides: the server simulates, a client draws what it is told).
func build() -> void:
	if drops != null:
		return
	drops = DotWeaponDrops.new()
	drops.name = "WeaponDrops"
	rules.auto_pickup = true
	drops.rules = rules
	drops.is_authority = game.authoritative
	drops.draws = DisplayServer.get_name() != "headless"
	drops.collision_mask = game.ragdoll_rules.collision_mask
	drops.keep_slots = KEEP_SLOTS
	drops.look_of = _look
	game.add_child(drops)
	_build_knives()
	if not drops.is_authority:
		var panel := ZzPickupPanel.new()
		panel.name = "PickupPanel"
		panel.game = game
		game.add_child(panel)


func _build_knives() -> void:
	knife_rules["damage"] = KNIFE_DAMAGE
	knives = DotWeaponKnives.new()
	knives.name = "Knives"
	knives.rules = knife_rules
	knives.weapon_id = KNIFE_WEAPON
	knives.is_authority = game.authoritative
	knives.draws = DisplayServer.get_name() != "headless"
	knives.tick_rate = game.tick_rate
	knives.player_for = func(entity: int) -> Object: return game.player_for_entity(entity)
	knives.player_ids = func() -> Array:
		var ids: Array = []
		for player in game.players.values():
			ids.append(player.entity_id)
		return ids
	knives.look_of = _look
	game.add_child(knives)


## A new round: whatever lay about goes.
func clear() -> void:
	if drops != null:
		drops.clear()
	if knives != null:
		knives.clear()


## The aim key before the survivor's weapons simulate: a knife in hand leaves it (no protection of
## any kind: a thrown knife hurts whoever the game's damage rules let it hurt).
func knife_input(player, command: DotWeaponCommand) -> void:
	var down := command.is_pressed(DotWeaponCommand.BUTTON_AIM)
	# Only a press throws; a released key the knives last saw released changes nothing there.
	if not down and not _aim_sent.has(player.entity_id):
		return
	if knives == null or not knives.is_authority or not _free(player):
		return
	if down:
		_aim_sent[player.entity_id] = true
	else:
		_aim_sent.erase(player.entity_id)
	var before := knives.count()
	knives.input(player.entity_id, player, command)
	if knives.count() != before:
		player.wanted_slot = player.weapons.arsenal.current_slot()


## Every tick, after everybody moved.
func knife_tick(tick: int, delta: float) -> void:
	if knives == null or not knives.is_authority:
		return
	knives.combat = game.combat
	knives.tick(tick, delta)


func _look(weapon_id: StringName) -> Node3D:
	var art: Variant = ZeeWeaponArtTable.table().get(ZzWeapons.resolve(weapon_id))
	if not (art is ZeeWeaponArt):
		return null
	var model := ZeeWorldModel.new()
	var _drawn := model.equip(art as ZeeWeaponArt)
	return model


## Whether [param player] may handle a weapon now.
func _free(player) -> bool:
	return drops != null and drops.is_authority and player.weapons != null and player.weapons.arsenal != null \
		and player.is_alive() and not player.is_down() and not player.is_held()


## The drop key tapped once: the weapon in hand goes along the aim when `sv_weapon_drop_key_hold` is 0. True if one left.
func throw(player) -> bool:
	var thrown := drop_key(player, true, 0.0)
	var _released := drop_key(player, false, 0.0)
	return thrown


## The player's drop key, every tick: a press throws the weapon in hand along the aim at once, or once the key has been
## held for `sv_weapon_drop_key_hold`. True if one left.
func drop_key(player, pressed: bool, delta: float) -> bool:
	if not _free(player):
		reset_key(player)
		return false
	if not pressed and _drop_up.has(player.entity_id):
		return false
	if pressed:
		_drop_up.erase(player.entity_id)
	else:
		_drop_up[player.entity_id] = true
	var keys: Dictionary = game.get_meta(&"drop_keys", {})
	game.set_meta(&"drop_keys", keys)
	var key: DotWeaponDropKey = keys.get(player.entity_id)
	if key == null:
		key = DotWeaponDropKey.new()
		keys[player.entity_id] = key
	var arsenal: DotWeaponArsenal = player.weapons.arsenal
	var id := key.step(drops, arsenal, player.eye_position(), player.aim_direction(), player.entity_id,
		pressed, delta, player.class_def, player.controller.state.velocity)
	if id == 0:
		return false
	player.wanted_slot = arsenal.current_slot()
	DotLog.debug(CHANNEL, "threw", {"player": String(player.player_id), "drop": id})
	return true


## Forgets a hold in progress: call on death, respawn and disconnect.
func reset_key(player) -> void:
	var keys: Dictionary = game.get_meta(&"drop_keys", {})
	var key: DotWeaponDropKey = keys.get(player.entity_id)
	if key != null:
		key.reset()


## Every tick: an empty slot takes a drop in reach.
func take(player) -> void:
	if drops == null or drops.count() == 0 or not _free(player):
		return
	var at: Vector3 = player.feet() + Vector3.UP * 0.5
	var _taken := drops.take_for(player.weapons.arsenal, at, player.entity_id, player.class_def)


## The use key (E) on a dropped weapon in view, by [DotWeaponUseKey]'s shared rules.
## True while the key belongs to the weapon, so the caller leaves loot and objectives alone.
func use_key(player, held: bool, delta: float) -> bool:
	if drops == null or drops.count() == 0 or not _free(player):
		return false
	var keys: Dictionary = game.get_meta(&"use_keys", {})
	game.set_meta(&"use_keys", keys)
	var key: DotWeaponUseKey = keys.get(player.entity_id)
	if key == null:
		key = DotWeaponUseKey.new()
		keys[player.entity_id] = key
	return key.step(drops, player.weapons.arsenal, player.eye_position(), player.aim_direction(), player.entity_id, held, delta, player.class_def)


## Lets traced shots and splash push dropped weapons about (the trace is built after this layer).
func hook_shots() -> void:
	if drops == null or game.combat == null or not game.combat.trace is DotTrace:
		return
	var trace: DotTrace = game.combat.trace
	if trace.ray_observer.is_valid():
		return
	var layer := drops
	trace.ray_observer = func(from: Vector3, dir: Vector3, dist: float) -> void:
		if layer.count() == 0:
			return
		var found := layer.raycast(from, from + dir * dist)
		if not found.is_empty():
			var _pushed := layer.hit(int(found["id"]), found["point"], dir, 3.0)
	trace.sphere_observer = func(centre: Vector3, radius: float) -> void:
		if layer.count() > 0:
			var _n := layer.blast(centre, radius, 8.0)


## Called as [param player] dies, before the arsenal is disabled (a dead arsenal gives up nothing).
func drop_dead(player) -> void:
	if drops == null or not drops.is_authority or player.weapons == null or player.weapons.arsenal == null:
		return
	var at: Vector3 = player.feet() + Vector3.UP
	var _gun := drops.drop_dead(player.weapons.arsenal, at, player.controller.state.velocity * 0.5 + player.aim_direction() * 0.5 + Vector3.UP * 2.0,
		player.entity_id, player.class_def)


## Whether a death leaves a real weapon, so the client skips its look-alike prop.
func on_death() -> bool:
	return drops != null and rules.enabled and rules.on_death
