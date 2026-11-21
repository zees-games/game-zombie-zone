extends "zz_client_board.gd"

## The shop and fitting screens of [zz_client.gd], split off so each file stays a size the
## efficiency gate allows.


## The key an action is on, as the player has it bound.
func _key(action: StringName) -> String:
	if settings != null and settings.bindings != null:
		var text := settings.bindings.key_for(action)
		if text != "":
			return text

	var row := ZzBindings.make().row_for_action(action)
	return String(row.get("default", action))


func _suspend_input(suspended: bool) -> void:
	# The button's release goes to the menu, so the aim is let go here or it sticks up.
	if suspended:
		_aiming = false

	if _sampler != null:
		_sampler.suspended = suspended

	if player != null and player.sampler != null:
		player.sampler.suspended = suspended


## Whether the local survivor stands within reach of an open trader.
func _near_trader(only_open := true) -> bool:
	if player == null or not player.can_act() or not bool(shop_state.get("menu", false)) or (only_open and not bool(shop_state.get("open", false))):
		return false
	var feet := player.feet()
	for at: Variant in shop_state.get("at", []):
		var a := at as Array
		if a.size() == 3 and feet.distance_to(Vector3(float(a[0]), float(a[1]), float(a[2]))) <= float(shop_state.get("radius", 3.5)):
			return true
	return false


func is_shop_open() -> bool:
	return _shop_menu != null and _shop_menu.is_open()


## The chat log is its own layer above the HUD and wrote over the menu's lower cards.
func _chat_shown(shown: bool) -> void:
	if chat != null and chat.window != null:
		chat.window.visible = shown


func close_shop() -> void:
	if not is_shop_open():
		return
	_shop_menu.close()
	_chat_shown(true)
	_suspend_input(false)
	platform.release_pointer(&"shop")


## Closes the menu when its trader goes or its customer leaves; keeps its balance and states current while it is up.
func _follow_shop_menu() -> void:
	if not is_shop_open():
		return
	if not _near_trader():
		if not bool(shop_state.get("open", false)) and String(shop_state.get("closed_message", "")) != "":
			game.notice.emit(String(shop_state["closed_message"]))
		close_shop()
		return
	_shop_menu.refresh(shop_state.get("items", []), player.points)



## The saved fittings, read once from the settings.
func _saved_fittings() -> Dictionary:
	if not _fittings_read and settings != null and settings.settings != null:
		_fittings_read = true
		_fittings.merge(ZzFittings.parse(settings.settings.get_string(ZzFittings.SETTING)), true)
	return _fittings


## A newly built local rig: it wears the saved fittings from now on, and the server is told
## them (offline, the game's own rig is fitted directly), since it keeps nothing between maps.
func _wear_fittings() -> void:
	if weapons == null or weapons.arsenal.attachments != null:
		return

	weapons.arsenal.attachments = ZzPacks.attachment_catalogue()
	var saved := _saved_fittings()
	ZzFittings.watch(weapons.arsenal, saved)
	var _now := ZzFittings.apply_to(weapons.arsenal, saved)

	for id: Variant in saved.keys():
		if not (saved[id] as GSWeaponFitting).is_empty():
			_send_fitting(saved[id] as GSWeaponFitting)


## Tells the authority about [param fitting]; it validates, applies and replicates it.
func _send_fitting(fitting: GSWeaponFitting) -> void:
	var base := ZzWeapons.def_of(fitting.weapon_id)

	if base == null:
		return

	if bridge != null and not _offline:
		bridge.ask_fit(base.id, ZzPacks.attachment_catalogue().encode(base, fitting))
	elif game.authoritative and player != null:
		var fitted: GSResult = game.fit_weapon(player, base.id, fitting)

		if not fitted.ok:
			game.notice.emit(fitted.error.message)


## The server refused a fit and says what it holds: that becomes the saved fitting, is worn,
## and is what the open menu shows.
func _on_fitting_resync(weapon_id: StringName, code: int) -> void:
	var base := ZzWeapons.def_of(weapon_id)

	if base == null or weapons == null:
		return

	var fitting := ZzPacks.attachment_catalogue().decode(base, code)
	var saved := _saved_fittings()
	saved[base.id] = fitting

	if settings != null and settings.settings != null:
		var _set := settings.settings.set_value(ZzFittings.SETTING, ZzFittings.format(saved))
		var _flushed := settings.settings.flush()

	var _now := ZzFittings.apply_to(weapons.arsenal, saved)
	if is_fitting_open():
		_attach_menu.show_fitting(fitting)


func is_fitting_open() -> bool:
	return _attach_menu != null and _attach_menu.visible


## Opens the fitting screen for the gun in hand, or says why not.
func open_fitting() -> void:
	if _attach_menu == null or is_fitting_open() or is_shop_open() or weapons == null:
		return

	var held := weapons.arsenal.current()
	var base := ZzWeapons.def_of(held.id()) if held != null else null
	var catalogue := ZzPacks.attachment_catalogue()

	if base == null or base.mounts.is_empty() or catalogue.choices_for(base).values().all(func(list: Array) -> bool: return list.is_empty()):
		game.notice.emit("Nothing fits this weapon.")
		return

	_using = false
	_firing = false
	_aiming = false
	_suspend_input(true)
	platform.hold_pointer(&"fitting")
	_chat_shown(false)
	_attach_menu.open(catalogue, base, weapons.arsenal.fitting_at(weapons.arsenal.current_slot()))


func close_fitting() -> void:
	if not is_fitting_open():
		return
	_attach_menu.hide()
	_chat_shown(true)
	_suspend_input(false)
	platform.release_pointer(&"fitting")


## A row pressed: the new fitting is saved, worn here at once and sent to the authority.
func _fit_requested(mount: StringName, id: StringName) -> void:
	var held := weapons.arsenal.current() if weapons != null else null
	var base := ZzWeapons.def_of(held.id()) if held != null else null

	if base == null:
		return

	var catalogue := ZzPacks.attachment_catalogue()
	var toggled := catalogue.toggle(base, weapons.arsenal.fitting_at(weapons.arsenal.current_slot()), mount, id)

	if not toggled.ok:
		game.notice.emit(toggled.error.message)
		return

	var fitting := toggled.value as GSWeaponFitting
	var saved := _saved_fittings()
	saved[base.id] = fitting

	if settings != null and settings.settings != null:
		var _set := settings.settings.set_value(ZzFittings.SETTING, ZzFittings.format(saved))
		var _saved := settings.settings.flush()

	var _now := ZzFittings.apply_to(weapons.arsenal, saved)
	_send_fitting(fitting)
	if is_fitting_open():
		_attach_menu.show_fitting(fitting)


func _shop_buy(item_id: String) -> void:
	if bridge != null and not _offline:
		bridge.ask_buy(item_id)
	elif game.shop != null and player != null:
		var _sold: bool = game.shop.buy(player, item_id)
		_follow_shop_menu()


## Finished prompt lines by (kind, id), rebuilt when the Use key's name or the words change, so a
## held prompt is the same String every frame instead of a new one.
var _prompt_lines: Dictionary = {}
var _prompt_key := ""


## [param template] with {k} the Use key, {a} and {b} the words, {n} the number; built on a miss only.
func _use_line(slot: Vector2i, template: String, a: String = "", b: String = "", n: int = 0) -> String:
	var key := _key(ZzBindings.USE)

	if key != _prompt_key or _prompt_lines.size() > 96:
		_prompt_lines.clear()
		_prompt_key = key

	var held: Variant = _prompt_lines.get(slot)

	if held != null and (held as PackedStringArray)[1] == a and (held as PackedStringArray)[2] == b:
		return (held as PackedStringArray)[0]

	var line := template.replace("{k}", key).replace("{a}", a).replace("{b}", b).replace("{n}", String.num_int64(n))
	_prompt_lines[slot] = PackedStringArray([line, a, b])
	return line


func _prompt() -> String:
	if player == null or not player.can_act():
		return ""

	var eye := player.eye_position()
	var aim := player.aim_direction()

	for other in game.survivors():
		if other != player and other.is_down() and other.feet().distance_to(player.feet()) <= game.config.revive_range + 0.4:
			return _use_line(Vector2i(1, hash(other.player_id)), "{k} — pick up {a}", other.display_name)

	if player.defibs > 0:
		for other in game.survivors():
			if other != player and other.life == ZzPlayer.Life.DEAD \
					and other.feet().distance_to(player.feet()) <= game.config.defib_range + 0.4:
				return _use_line(Vector2i(2, hash(other.player_id)), "{k} — hold to shock {a} back", other.display_name)

	var best := ""
	var best_off := 0.7

	for id: int in world_view._loot:
		var node: Node3D = world_view._loot[id]
		var to := node.global_position + Vector3(0.0, 0.25, 0.0) - eye
		var along := to.dot(aim)

		if along < 0.0 or along > game.config.use_reach + 0.3:
			continue

		var off := (to - aim * along).length()

		if off < best_off:
			best_off = off
			var cost := int(node.get_meta(&"price", 0))
			best = _use_line(Vector2i(3 + maxi(cost, 0) * 4, id), "{k} — {a} ({n} points)" if cost > 0 else "{k} — {a}",
				String(node.get_meta(&"label", "pick up")), "", cost)

	if best != "":
		return best

	var index := game.current_objective()

	if index >= 0 and game.objective_states[index] == &"waiting":
		var o: Dictionary = (game.map_doc["objectives"] as Array)[index]
		if o["kind"] == "use" and eye.distance_to(ZzMapDoc.v3(o["at"])) <= float(o["radius"]) + 0.6:
			return _use_line(Vector2i(-4, index), "{k} — {a}", String(o["label"]))

	# A barricade within reach that is not whole: the same test the server mends by.
	var mend := game.barricade_to_mend(player)

	if mend >= 0:
		var entry: Dictionary = (game.map_doc["barricades"] as Array)[mend]
		var held: Dictionary = game.barricades.get(String(entry["id"]), {})
		if not held.is_empty():
			var share := int(round(100.0 * float(held["health"]) / float(held["max"])))
			return _use_line(Vector2i(5 + share * 4, mend), "{k} — {b} {a} ({n}%)", String(entry.get("label", "the barricade")),
				"mend" if bool(held["intact"]) else "rebuild", share)

	if game.map != null and game.map.toys != null:
		var act: String = game.prop_carry.hint(game.map.toys, eye, aim, game.world_mask(), game.prop_carry.max_mass)
		if act != "":
			return _use_line(Vector2i(-6, 0), "{k} — {a}", act)

	return ""


func _present_effects(delta: float) -> void:
	if audio != null:
		audio.listen_from(camera.global_position)
		audio.keep_walkers(game.players.values())
		if game.physics != null:
			audio.follow_roof(delta, camera.global_position, camera.get_world_3d().direct_space_state, game.physics.layer_mask(&"world"))

	if game.effects != null:
		game.effects.viewer_position = camera.global_position
		game.effects.advance(delta)

	if blood != null:
		blood.advance(delta)


