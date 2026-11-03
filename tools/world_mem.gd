extends Node
## Memory of one drawn world: reads it, attaches its extras (sounds, props), and prints static memory at each step.
##   godot --headless --path . res://tools/world_mem.tscn -- --map=ze_biohazard_manor

const ZzMap := preload("../game/zz_map.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzPaths := preload("../game/zz_paths.gd")


func _ready() -> void:
	DotLog.set_level(DotLog.Level.WARN)
	_run.call_deferred()


func _mb() -> String:
	var rss := ""
	for line in FileAccess.get_file_as_string("/proc/self/status").split("\n"):
		if line.begins_with("VmHWM") or line.begins_with("VmRSS"):
			rss += " " + line.replace("\t", " ").replace("  ", " ")
	return "static %d MB (peak %d);%s" % [OS.get_static_memory_usage() / 1048576, OS.get_static_memory_peak_usage() / 1048576, rss]


func _run() -> void:
	var id := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			id = a.substr(6)
	var doc := ZzMapDoc.parse_json(FileAccess.get_file_as_string(ZzPaths.rebase("res://maps/%s.json" % id))).value as Dictionary
	var prefix := ZzPaths.rebase(ZzMap.LOCAL_WORLD % [str(doc.get("world", "")), id])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--texmax="):
			(load(ZzMap.MESH_SCRIPT) as GDScript).set("model_texture_max", int(a.substr(9)))
	print("start ", _mb())
	var read: DotResult = (load(ZzMap.MESH_SCRIPT) as GDScript).call(&"load_prefix", prefix)
	print("read ", read.ok, " ", _mb())
	var extras := ZzMap.new()
	extras.doc = doc
	var host := Node3D.new()
	if OS.get_cmdline_user_args().has("--stages"):
		var w: RefCounted = read.value
		host.add_child(w.call(&"build_environment", 8, false))
		print("environment ", _mb())
		host.add_child(w.call(&"build_sounds"))
		print("sounds ", _mb())
		var props: Node3D = w.call(&"build_props")
		print("props ", _mb())
		host.add_child(props)
		var unseen: Node3D = w.call(&"draw_unseen_boxes", doc.get("solid_props", []))
		if unseen != null:
			host.add_child(unseen)
		print("unseen ", _mb())
	else:
		extras.call(&"_attach_world_extras", read.value, host)
	print("extras ", _mb(), " children ", host.get_child_count())
	get_tree().quit(0)
