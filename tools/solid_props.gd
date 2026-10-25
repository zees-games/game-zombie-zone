extends SceneTree

## Writes a drawn world's solid prop boxes as JSON: `{id: [[x, y, z, sx, sy, sz, yaw], ...]}`, the
## boxes dot-map's `build_prop_collision` makes. zombie-zone-maps' `tools/solid_props.sh` merges them
## into each document, so a server with no world pack collides where a client does.
##
## [codeblock]
## godot --headless --path . --script tools/solid_props.gd -- OUT.json [id ...]
## [/codeblock]

const MESH_SCRIPT := "res://addons/dot_map/bsp/dot_map_bsp_mesh.gd"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: solid_props.gd -- OUT.json [id ...]")
		quit(2)
		return

	var out := {}
	var failed := false

	for id in args.slice(1):
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://maps/%s.json" % id))
		if not (doc is Dictionary) or str((doc as Dictionary).get("world", "")) == "":
			printerr(id, ": no document or no world")
			failed = true
			continue
		var prefix := "res://world/%s/%s" % [(doc as Dictionary)["world"], id]
		var read: DotResult = (load(MESH_SCRIPT) as GDScript).call(&"load_prefix", prefix)
		if not read.ok:
			printerr(id, ": ", read.error.message)
			failed = true
			continue
		var body: StaticBody3D = read.value.call(&"build_prop_collision")
		var boxes := []
		if body != null:
			for child in body.get_children():
				var cs := child as CollisionShape3D
				var size := (cs.shape as BoxShape3D).size
				var o := cs.transform.origin
				var yaw := rad_to_deg(atan2(-cs.transform.basis.x.z, cs.transform.basis.x.x))
				boxes.append([snappedf(o.x, 0.001), snappedf(o.y, 0.001), snappedf(o.z, 0.001),
					snappedf(size.x, 0.001), snappedf(size.y, 0.001), snappedf(size.z, 0.001), snappedf(yaw, 0.01)])
			body.free()
		out[id] = boxes
		print(id, ": ", boxes.size(), " solid props")

	var f := FileAccess.open(args[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	quit(1 if failed else 0)
