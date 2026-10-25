extends SceneTree

## Writes a drawn world's solid prop boxes as JSON: `{id: [[x, y, z, sx, sy, sz, yaw], ...]}`, the
## boxes dot-map's `build_prop_collision` makes. zombie-zone-maps' `tools/solid_props.sh` merges them
## into each document, so a server with no world pack collides where a client does.
##
## [codeblock]
## godot --headless --path . --script tools/solid_props.gd -- OUT.json [id ...]
## [/codeblock]

const MESH_SCRIPT := "res://addons/dot_map/bsp/dot_map_bsp_mesh.gd"
const NPCS_SCRIPT := "res://game/zz_npcs.gd"
const GRAPH_SCRIPT := "res://addons/dot_npc/nav/dot_npc_nav_graph.gd"
const SNAP := 2.5


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
		var kept := _keep_connected(doc as Dictionary, boxes)
		if kept.size() < boxes.size():
			print(id, ": ", boxes.size() - kept.size(), " solid props left out: they seal the horde's ground")
		out[id] = kept
		print(id, ": ", kept.size(), " solid props")

	var f := FileAccess.open(args[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	quit(1 if failed else 0)


## The places the horde and the team must reach from the first seat: posts, caches, route, objectives, sleepers and spawn hints.
static func _places(doc: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for key: String in ["posts", "caches", "route", "sleepers", "zombie_spawns"]:
		for p: Array in doc.get(key, []):
			out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	for o: Dictionary in doc.get("objectives", []):
		var at: Array = o["at"]
		out.append(Vector3(float(at[0]), float(at[1]), float(at[2])))
	return out


## [param boxes] without those that cut a place the first seat reached before them: a parked car across a
## three-metre street seals the horde's ground, which no prop of the original does (it could be shoved or climbed).
## Tries them all at once and only goes box by box when that loses a place.
func _keep_connected(doc: Dictionary, boxes: Array) -> Array:
	var seat: Array = (doc.get("spawns", {}) as Dictionary).get("survivors", [])
	if boxes.is_empty() or seat.is_empty():
		return boxes
	var npcs: GDScript = load(NPCS_SCRIPT)
	var graph_class: GDScript = load(GRAPH_SCRIPT)
	var from := Vector3(float(seat[0]["at"][0]), float(seat[0]["at"][1]), float(seat[0]["at"][2]))
	var gates := PackedStringArray()
	for box: Dictionary in doc.get("boxes", []):
		if box.has("gate"):
			gates.append(str(box["gate"]))
	var places := _places(doc)
	var work := doc.duplicate()
	work.erase("solid_props")
	var reached := _reached(npcs, graph_class, work, gates, from, places)
	work["solid_props"] = boxes
	if _reached(npcs, graph_class, work, gates, from, places) == reached:
		return boxes
	var kept := []
	for box: Array in boxes:
		work["solid_props"] = kept + [box]
		if _reached(npcs, graph_class, work, gates, from, places) == reached:
			kept.append(box)
	return kept


## Which of [param places] the first seat walks to, as a string of 0 and 1.
static func _reached(npcs: GDScript, graph_class: GDScript, doc: Dictionary, gates: PackedStringArray, from: Vector3, places: Array[Vector3]) -> String:
	var size_of := func(_id: StringName) -> Vector3: return Vector3.ZERO
	var graph: RefCounted = graph_class.new(npcs.call(&"nav_for", doc, size_of, gates))
	var out := ""
	for at in places:
		out += "1" if graph.call(&"is_reachable", from, at, SNAP) else "0"
	return out
