extends SceneTree

## Renders the workbench with the box editor open on a box type to res://screenshots/workbench_boxes.png.
## Run under xvfb-run: tools/workbench_box_shot.sh

const ZzBoxProfiles := preload("../game/zz_box_profiles.gd")


func _initialize() -> void:
	_run.call_deferred()


func _find_editor(n: Node) -> Node:
	if n.has_method("current_kind") and n.has_method("open"):
		return n
	for c in n.get_children():
		var f := _find_editor(c)
		if f != null:
			return f
	return null


func _run() -> void:
	var wb := DotGameWorkbench.new()
	wb.listen_host_fn = func() -> bool: return true
	wb.add_set(ZzBoxProfiles.make_set(PackedStringArray(["res://cfg"])), "Boxes (odds, effects, colours, sounds)")
	root.add_child(wb)
	var started := wb.start(DotProfileRuntime.new())
	await _frames(3)
	wb.toggle()
	await _frames(6)
	var ed := _find_editor(wb.overlay) if wb.overlay != null else null
	var opened: Variant = ed.call("open", "box", "instakill") if ed != null else null
	await _frames(8)
	var img := root.get_viewport().get_texture().get_image()
	var saved := img.save_png(ProjectSettings.globalize_path("res://screenshots/workbench_boxes.png"))
	print("started=%s editor=%s opened=%s saved=%d" % [started.ok, ed != null, opened != null and opened.ok, saved])
	quit(0 if started.ok and ed != null else 1)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
