extends Node
## Client side: the shared pickup panel over the dropped weapon a survivor looks at, and the hold circle.
## Hooked in here because the client script is not the place for it; the local player is the one nearest the camera.

const ZzBindings := preload("zz_bindings.gd")

var game = null
var view: DotWeaponPickupView = null
var hold := DotWeaponUseHold.new()


func _process(delta: float) -> void:
	var layer: DotWeaponDrops = game.weapon_layer.drops if game != null else null
	var camera := get_viewport().get_camera_3d()
	if layer == null or camera == null or layer.count() == 0 or DisplayServer.get_name() == "headless":
		if view != null:
			view.show_prompt({})
		return
	var me = _nearest_player(camera.global_position)
	var info := {}
	if me != null and me.weapons != null and me.weapons.arsenal != null and me.is_alive() and not me.is_down():
		info = layer.prompt_for(me.weapons.arsenal, camera.global_position, -camera.global_basis.z, me.class_def)
	if view == null:
		view = DotWeaponPickupView.new()
		view.name = "PickupView"
		add_child(view)
	hold.hold_time = layer.rules.hold_time
	var pressed := InputMap.has_action(ZzBindings.USE) and Input.is_action_pressed(ZzBindings.USE)
	var _event := hold.step(pressed, delta, info.get("mode", "") == "swap")
	view.key_text = _key_text()
	view.name_of = func(id: StringName) -> String:
		var def: Variant = me.weapons.arsenal.catalogue.get_def(id)
		return def.name_or_id() if def != null else String(id)
	view.show_prompt(info, hold.progress)


func _nearest_player(at: Vector3):
	var best = null
	var best_d := 16.0
	for p in game.players.values():
		var d: float = p.eye_position().distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = p
	return best


func _key_text() -> String:
	if InputMap.has_action(ZzBindings.USE):
		for ev in InputMap.action_get_events(ZzBindings.USE):
			if ev is InputEventKey:
				var code: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
				return OS.get_keycode_string(code)
	return "E"
