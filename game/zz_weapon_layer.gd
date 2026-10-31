extends RefCounted

const ZzWeapons := preload("zz_weapons.gd")
const ZzPickupPanel := preload("zz_pickup_panel.gd")

## Weapons lying in the world, thrown with the drop key (Q) or left by the dead: dot-weapon's
## [DotWeaponDrops] under `sv_weapon_drop*`, with the survivor's hands and carry rules as the hooks.
## An empty slot in reach takes a drop (so weight and quota still apply); a full slot swaps.

const CHANNEL := "zz.weapon_layer"

## Slot 1 is the melee weapon, which a survivor never puts down.
const KEEP_SLOTS: Array[int] = [1]

var rules := DotWeaponDropRules.new()
var drops: DotWeaponDrops = null
var game = null


func _init(p_game: Object) -> void:
	game = p_game


## Builds the layer under the game (both sides: the server simulates, a client draws what it is told).
func build() -> void:
	if drops != null:
		return
	drops = DotWeaponDrops.new()
	drops.name = "WeaponDrops"
	drops.rules = rules
	drops.is_authority = game.authoritative
	drops.draws = DisplayServer.get_name() != "headless"
	drops.collision_mask = game.ragdoll_rules.collision_mask
	drops.keep_slots = KEEP_SLOTS
	drops.look_of = _look
	game.add_child(drops)
	if not drops.is_authority:
		var panel := ZzPickupPanel.new()
		panel.name = "PickupPanel"
		panel.game = game
		game.add_child(panel)


## A new round: whatever lay about goes.
func clear() -> void:
	if drops != null:
		drops.clear()


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


## The drop key: the weapon in hand goes along the aim. True if one left.
func throw(player) -> bool:
	if not _free(player):
		return false
	var arsenal: DotWeaponArsenal = player.weapons.arsenal
	var id := drops.throw(arsenal, player.eye_position(), player.aim_direction(), player.entity_id,
		player.class_def, player.controller.state.velocity)
	if id == 0:
		return false
	player.wanted_slot = arsenal.current_slot()
	DotLog.debug(CHANNEL, "threw", {"player": String(player.player_id), "drop": id})
	return true


## Every tick: an empty slot takes a drop in reach.
func take(player) -> void:
	if drops == null or drops.count() == 0 or not _free(player):
		return
	var at: Vector3 = player.feet() + Vector3.UP * 0.5
	var _taken := drops.take_for(player.weapons.arsenal, at, player.entity_id, player.class_def)


## The use key (E) on a dropped weapon in view: a tap unloads ammo or fills an empty slot, a hold swaps.
## True while the key belongs to the weapon, so the caller leaves loot and objectives alone.
func use_key(player, held: bool, delta: float) -> bool:
	if drops == null or drops.count() == 0 or not _free(player):
		return false
	var holds: Dictionary = game.get_meta(&"use_holds", {})
	game.set_meta(&"use_holds", holds)
	var hold: DotWeaponUseHold = holds.get(player.entity_id)
	if hold == null:
		hold = DotWeaponUseHold.new()
		holds[player.entity_id] = hold
	hold.hold_time = drops.rules.resolve(player.class_def).hold_time
	var info := drops.prompt_for(player.weapons.arsenal, player.eye_position(), player.aim_direction(), player.class_def)
	var event := hold.step(held, delta, not info.is_empty())
	if event != DotWeaponUseHold.Event.NONE:
		var _used := drops.use(player.weapons.arsenal, player.eye_position(), player.aim_direction(), player.entity_id,
			player.class_def, event == DotWeaponUseHold.Event.HOLD)
	return not info.is_empty()


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
