extends DotMapEntity

## game_text and game_text_tooltip: Display tells the game to put the entity's message on the HUD
## (`hud_text`), to everyone (spawnflag 1) or to the activator when one is known.


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"display":
			if enabled:
				io.event("hud_text", {"entity": index, "message": key("message"), "all": has_spawnflag(1) or not activator is Object,
						"hold": key_float("holdtime", 2.0), "color": key("color", "255 255 255"), "activator": activator})
			return true
		"settext":
			keys["message"] = param
			return true
	return false
