extends Node
const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
## Counts the nav links of every map whose straight run is blocked in the real physics world (world hulls, boxes, props, clip): the
## importer's links are only checked against the document's boxes. `-- --maps=a,b` for some, `--list` prints each blocked link.

const ALL := ["zz_blackout_1", "zz_blackout_2", "zz_blackout_3", "zz_chapel", "zz_high_school", "zz_lot", "zz_mall", "zz_relief_camp",
	"zz_stadium", "zs_ravenstreet", "zm_4way_tunnel", "zm_abandoned_mall", "zm_atix_helicopter", "zm_chaos_city", "zm_house_outbreak",
	"zm_officeattack", "zm_pathogen", "ze_blackmesa_escape", "ze_boat_escape", "ze_death_star_escape", "ze_jurassicpark", "ze_nuke_beta",
	"ze_runforyourlife_1_v4"]
var last_hit := ""
const HEIGHTS := [0.4, 0.9]
const TRIM := 0.15

func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	var ids: Array = ALL
	var list := false
	var dir := DirAccess.open("res://maps")
	if "--all-docs" in OS.get_cmdline_user_args():
		ids = []
		for f in dir.get_files():
			if f.ends_with(".json"):
				ids.append(f.get_basename())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--maps="):
			ids = arg.substr(7).split(",")
		if arg == "--list":
			list = true
	var total := 0
	var blocked_total := 0
	var wall_total := 0
	for id: String in ids:
		var game := ZzGame.new()
		var config := ZzConfig.new()
		config.warmup_seconds = 0.0
		config.intermission_seconds = 0.0
		config.minimum_players = 0
		config.keep_progress = false
		config.map_ids = PackedStringArray([id])
		config.survival_style = 0
		game.config = config
		game.tick_rate = 30
		game.authoritative = true
		game.register_service = false
		add_child(game)
		game.set_physics_process(false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		game.start()
		for i in 6:
			game.simulate(1.0 / 30.0)
			await get_tree().physics_frame
		var map: ZzMap = game.map
		if map == null:
			print("LINKS %-26s no map" % id)
		else:
			var doc: Dictionary = ZzNpcs.with_nav_extra(map.doc, map.read_nav_extra())
			var raw: int = doc.get("nav", {}).get("links", []).size()
			var info := {}
			var builder = ZzNpcs._builder_for(doc, {}, false, PackedStringArray(), [] as Array[AABB], ZzNpcs.LINK_TEST_HEIGHTS, info)
			var links: Array = []
			for k: Array in builder._links:
				var f: Vector3 = k[0]
				var t: Vector3 = k[1]
				links.append([f.x, f.y, f.z, t.x, t.y, t.z])
			var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
			var mask: int = game.physics.layer_mask(&"world") | game.physics.layer_mask(&"prop") | game.physics.layer_mask(&"clip")
			var bad := 0
			var walls := 0
			var cuts: Array = []
			for l: Array in links:
				var hit := _hit(space, mask, l)
				if hit != Vector3.INF:
					bad += 1
					var soft: bool = c_soft(last_hit)
					if hit.y > 50.0 and not soft:
						walls += 1
					cuts.append([l, hit, last_hit])
			total += links.size()
			blocked_total += bad
			wall_total += walls
			print("LINKS %-26s %4d of %4d links kept by the game, %3d blocked, %3d of them walls (chest-high too)" % [id, links.size(), raw, bad, walls])
			if list:
				for c in cuts:
					print("      %s hit %s %s" % [c[0], c[1], c[2]])
		remove_child(game)
		game.free()
		await get_tree().process_frame
	print("LINKS TOTAL %d links, %d blocked, %d walls" % [total, blocked_total, wall_total])
	get_tree().quit(0)


## INF when clear; else the hit point, with y raised by 100 when the chest-high ray is blocked too (a wall, not a knee-high ledge).
## A mover (a door that opens) or a loose prop is not a wall.
func c_soft(what: String) -> bool:
	return what.contains("Mechanics/") or what.contains("Furniture") or what.contains("Door_")


func _hit(space: PhysicsDirectSpaceState3D, mask: int, l: Array) -> Vector3:
	var top := maxf(float(l[1]), float(l[4]))
	var found := Vector3.INF
	last_hit = ""
	var chest := false
	for rise: float in HEIGHTS:
		var a := Vector3(l[0], top + rise, l[2])
		var b := Vector3(l[3], top + rise, l[5])
		if a.distance_to(b) < 0.5:
			return Vector3.INF
		var dir := (b - a).normalized()
		a += dir * TRIM
		b -= dir * TRIM
		var query := PhysicsRayQueryParameters3D.create(a, b, mask)
		query.hit_from_inside = true
		var r := space.intersect_ray(query)
		if not r.is_empty():
			if found == Vector3.INF:
				found = r.position
				var body := r.collider as CollisionObject3D
				var owner_id := body.shape_find_owner(int(r.shape))
				var shape := body.shape_owner_get_shape(owner_id, 0)
				var xf := body.shape_owner_get_transform(owner_id)
				last_hit = "%s %s %s " % [shape.get_class(), xf.origin, (shape as BoxShape3D).size if shape is BoxShape3D else ""] + "%s/%s" % [(r.collider as Node).get_parent().name if r.collider.get_parent() else "", (r.collider as Node).name]
			chest = rise > 0.5
	if chest:
		found.y += 100.0
	return found
