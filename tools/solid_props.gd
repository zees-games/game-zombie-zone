extends SceneTree

## Writes a drawn world's solid prop boxes as JSON: `{id: [[x, y, z, sx, sy, sz, yaw], ...]}`, the
## boxes dot-map's `build_prop_collision` makes. zombie-zone-maps' `tools/solid_props.sh` merges them
## into each document, so a server with no world pack collides where a client does.
##
## [codeblock]
## godot --headless --path . --script tools/solid_props.gd -- OUT.json [--from-doc] [id ...]
## [/codeblock]
## `--from-doc` re-filters the boxes a document already has instead of rebuilding them from the world:
## run it after a change to how `ZzNpcs.nav_for` cuts solid props, which can seal ground the last filter left open.

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
	# What the world marks loose (free barrels) and the breakables holding them up, per id: `{id: {loose_toys, supports}}`.
	var loose := {}
	var failed := false
	var ids := args.slice(1)
	var from_doc := ids.has("--from-doc")
	ids.erase("--from-doc")

	for id in ids:
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://maps/%s.json" % id))
		if not (doc is Dictionary) or str((doc as Dictionary).get("world", "")) == "":
			printerr(id, ": no document or no world")
			failed = true
			continue
		var boxes := []
		var body: StaticBody3D = null
		if from_doc:
			boxes = ((doc as Dictionary).get("solid_props", []) as Array).duplicate()
		else:
			var prefix := "res://world/%s/%s" % [(doc as Dictionary)["world"], id]
			var read: DotResult = (load(MESH_SCRIPT) as GDScript).call(&"load_prefix", prefix)
			if not read.ok:
				printerr(id, ": ", read.error.message)
				failed = true
				continue
			read.value.set(&"skip_loose", true)
			loose[id] = {"loose_toys": read.value.call(&"loose_toys"), "supports": read.value.call(&"supports")}
			body = read.value.call(&"build_prop_collision")
		if body != null:
			for child in body.get_children():
				var cs := child as CollisionShape3D
				var size := (cs.shape as BoxShape3D).size
				var o := cs.transform.origin
				var yaw := rad_to_deg(atan2(-cs.transform.basis.x.z, cs.transform.basis.x.x))
				boxes.append([snappedf(o.x, 0.001), snappedf(o.y, 0.001), snappedf(o.z, 0.001),
					snappedf(size.x, 0.001), snappedf(size.y, 0.001), snappedf(size.z, 0.001), snappedf(yaw, 0.01)])
			body.free()
		var clear := _clear_of_spawns(doc as Dictionary, boxes)
		if clear.size() < boxes.size():
			print(id, ": ", boxes.size() - clear.size(), " solid props left out: they stand where a spawn does")
		boxes = clear
		var kept := _keep_connected(doc as Dictionary, boxes)
		if kept.size() < boxes.size():
			print(id, ": ", boxes.size() - kept.size(), " solid props left out: they seal the horde's ground")
		out[id] = kept
		print(id, ": ", kept.size(), " solid props")

	var f := FileAccess.open(args[0], FileAccess.WRITE)
	out["_loose"] = loose
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


## [param boxes] without those a standing person at a spawn would be inside: a stand-in's box that overlaps where the author put people is the stand-in's error, never a wall.
static func _clear_of_spawns(doc: Dictionary, boxes: Array) -> Array:
	var spawns: Dictionary = doc.get("spawns", {})
	var at: Array[Vector3] = []
	for key: String in spawns:
		for s: Variant in spawns[key]:
			if s is Dictionary and (s as Dictionary).has("at"):
				var a: Array = (s as Dictionary)["at"]
				at.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
	var out := []
	for box: Array in boxes:
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(box[6]))), Vector3(box[0], box[1], box[2]))
		var half := Vector3(box[3], box[4], box[5]) * 0.5
		var hit := false
		for p in at:
			var local := xf.affine_inverse() * (p + Vector3(0.0, 0.9, 0.0))
			if absf(local.x) < half.x + 0.3 and absf(local.z) < half.z + 0.3 and absf(local.y) < half.y + 0.8:
				hit = true
				break
		if not hit:
			out.append(box)
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
	_keep_run(npcs, graph_class, work, gates, from, places, reached, boxes, kept)
	return kept


## Adds [param run] to [param kept] whole when that loses no place, else each half in turn. A box only ever
## takes ground away, so this keeps exactly what trying them one by one keeps, in far fewer graph builds.
func _keep_run(npcs: GDScript, graph_class: GDScript, work: Dictionary, gates: PackedStringArray, from: Vector3, places: Array[Vector3], reached: String, run: Array, kept: Array) -> void:
	work["solid_props"] = kept + run
	if _reached(npcs, graph_class, work, gates, from, places) == reached:
		kept.append_array(run)
	elif run.size() > 1:
		_keep_run(npcs, graph_class, work, gates, from, places, reached, run.slice(0, run.size() / 2), kept)
		_keep_run(npcs, graph_class, work, gates, from, places, reached, run.slice(run.size() / 2), kept)


## Which of [param places] the first seat walks to, as a string of 0 and 1.
static func _reached(npcs: GDScript, graph_class: GDScript, doc: Dictionary, gates: PackedStringArray, from: Vector3, places: Array[Vector3]) -> String:
	var size_of := func(_id: StringName) -> Vector3: return Vector3.ZERO
	var graph: RefCounted = graph_class.new(npcs.call(&"nav_for", doc, size_of, gates))
	var out := ""
	for at in places:
		out += "1" if graph.call(&"is_reachable", from, at, SNAP) else "0"
	return out
