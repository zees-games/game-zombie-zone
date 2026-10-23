extends SceneTree

## Renders the settings menu's Video page (the Blood splatters row visible) to
## res://screenshots/menu_video*.png, and checks the row persists. Run under xvfb-run:
## tools/menu_shot.sh

const ZzSettings := preload("../game/zz_settings.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings := ZzSettings.new()
	root.add_child(settings)
	var store := DotSettingsStoreMemory.new()
	var _built: DotResult = settings.setup(store)
	var menu: DotMenu = settings.menu
	await _frames(4)
	menu.open(&"video")
	await _frames(4)
	await _save("res://screenshots/menu_video.png")
	var row := menu.screen.find_child("Row_gore", true, false)
	if row != null:
		var sc := _scroll_of(row)
		if sc != null:
			await _frames(2)
			sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
		await _frames(4)
		await _save("res://screenshots/menu_video_gore.png")
	var before: bool = bool(settings.settings.get_value(&"gore"))
	var btn := row as BaseButton
	if btn != null:
		btn.button_pressed = not before
	await _frames(3)
	var reread: bool = bool(settings.settings.get_value(&"gore"))
	print("gore row found=%s button=%s before=%s after=%s" % [row != null, btn != null, before, reread])
	quit(0 if btn != null and reread == (not before) else 1)


func _scroll_of(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null and not p is ScrollContainer:
		p = p.get_parent()
	return p as ScrollContainer


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _save(path: String) -> void:
	await _frames(2)
	var img := root.get_viewport().get_texture().get_image()
	var _e := img.save_png(ProjectSettings.globalize_path(path))
	print("saved ", path)
