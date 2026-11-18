extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")

const ZzGame := preload("../game/zz_game.gd")

const ZzMapDoc := preload("../game/zz_map_doc.gd")

const ZzCatalogue := preload("../game/zz_catalogue.gd")

const ZzEvents := preload("../game/net/zz_events.gd")

const ZzLampBudget := preload("../game/zz_lamp_budget.gd")

const ZzMap := preload("../game/zz_map.gd")

const ZzMechanics := preload("../game/zz_mechanics.gd")

const ZzPaths := preload("../game/zz_paths.gd")

const ZzTestToys := preload("zz_test_toys.gd")

## Every map the game can be sent, built the way a server builds it and looked over for the mistakes a map document makes without any error: a spawn inside a wall or over nothing, a prop the catalogue does not have (built as nothing), a prop sunk into a wall or floating, an item out of reach, and — the one this game adds — ground
## the zombies cannot cross. [b]Why this exists apart from `headless_run`.[/b] The maps are generated in zombie-zone-maps by `tools/build_maps.py`, and none of those mistakes stops a map: a doorway the nav graph does not cross is a safe room no zombie ever enters, an objective off the graph is a hold-out the horde never reaches, and
## a gate that does not cut the graph is a barrier the horde walks through. The renders find the ugly ones; this finds the rest, on every map, every time. Sections and checks are both counted; mg-smash-copter's notes say why the second matters. Adding a map adds a section and CHECKS_PER_MAP checks.

const ZzNpcs := preload("../game/zz_npcs.gd")

const MAPS := ["zz_practice", "zz_blackout_1", "zz_blackout_2", "zz_blackout_3", "zz_lot", "zz_chapel", "zz_high_school", "zz_mall", "zz_stadium", "zz_relief_camp", "zs_ravenstreet", "ze_biohazard_manor", "ze_nuke_beta", "ze_runforyourlife_1_v4", "zm_atix_helicopter", "zm_4way_tunnel", "zm_abandoned_mall", "ze_boat_escape", "ze_death_star_escape", "zm_chaos_city", "zm_pathogen"]

const CHECKS_PER_MAP := 20

const BAKE_CHECKS := 9

const WORLD_CHECKS := 4

const LAMP_CHECKS := 8

## The maps actually checked: all of MAPS, or only the practice street where `maps/` is not linked in (CI, which clones this
## repository alone). As mg-deathrun's headless_courses does: the delivered maps are checked wherever they are present, which is
## every machine that has run dot-bootstrap. Sections and checks are counted against this list.
var _maps: Array = []

var _worlds_read := 0

## A person's capsule, for "is this spawn clear".
const RADIUS := 0.4

const HEIGHT := 1.8

## Fewest survivor spawns a map may have: a team of four starts apart.
const MIN_SPAWNS := 4

## How far a point that matters (an objective, a route point) may be from the zombies' ground.
const SNAP := 2.5

var _sections_entered := 0

var _sections_finished := 0

## Shipped world maps whose spawner config was checked (three checks each).
var _spawner_worlds := 0

## World maps whose spawner checks were skipped because world/ is not linked.
var _worlds_skipped := 0

## Maps whose wire budget cut boxes: each adds the whole-floor check.
var _nav_extra_maps := 0

## The shards `game.conf` names: the whole-floor sections once as `core` (catalogue, lazy catalogue, lamps, solid props, footing,
## library) and `light` (baked light) and `worlds` (the world maps), each its own run: one `core` holding all eight was OOM-killed at heavy's 4096 MB,
## the maps dealt round-robin into `m0`..`m{MAP_SHARDS-1}`. Change MAP_SHARDS, SHARD_NAMES and game.conf's SUITE_SHARDS together.
const MAP_SHARDS := 4

const SHARD_NAMES := ["core", "light", "worlds", "m0", "m1", "m2", "m3"]

const CORE_SECTIONS := 6

const WORLD_SECTIONS := 2

## The maps this machine has: all of MAPS, or only the practice street where `maps/` is not linked.
func _linked_maps() -> Array:
	var linked := DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://maps"))
	return MAPS.duplicate() if linked else ["zz_practice"]

func _merge(logs: Array) -> void:
	var absent := DotGameShardArgs.missing(PackedStringArray(logs))
	_check(logs.size() == SHARD_NAMES.size() and absent.is_empty(), "every shard's log is there (%d logs)" % logs.size(), "missing %s" % [absent])
	var entered := DotGameShardArgs.sections_entered(PackedStringArray(logs))
	var want := CORE_SECTIONS + WORLD_SECTIONS + _linked_maps().size()
	_check(entered == want, "the shards entered every section (%d of %d)" % [entered, want])
	_report_sections(1, 1, 1, 2)

## The height of the nav floor a point stands over, nearest the point's own height. The street maps are flat at y=0, but an exodus
## map is converted at the source's heights (a deck at 22 m, a stair, a bridge), and the graph's points are at those heights: a
## target flattened to 0 is 22 m from every point and was "unreached" however well the ground joined.
func _ground_y(doc: Dictionary, at: Vector3) -> float:
	var best := 0.0
	var found := false
	for f: Array in (doc.get("nav", {}) as Dictionary).get("floors", []):
		if at.x < float(f[0]) or at.x > float(f[2]) or at.z < float(f[1]) or at.z > float(f[3]):
			continue
		var y := float(f[4])
		if not found or absf(y - at.y) < absf(best - at.y):
			best = y
			found = true
	if doc.has("terrain"):
		var ground := DotMapTerrain.from_dict(doc["terrain"])
		var y := (ground.value as DotMapTerrain).height_at(at.x, at.z) if ground.ok else NAN
		if not is_nan(y) and (not found or absf(y - at.y) < absf(best - at.y)):
			best = y
	return best

const LAZY_CHECKS := 8 + 9

## The document keeps every lamp; only the nearest few are lit, and a lamp fades rather than pops.
const FOOTING_CHECKS := 5

const ZzFooting := preload("res://game/zz_footing.gd")

const SOLID_PROP_CHECKS := 6

func _visible(lamps: Array[Light3D]) -> int:
	var n := 0
	for lamp in lamps:
		n += 1 if lamp.visible else 0
	return n

## A ray down from just over [param at] finds a floor, a table or a prop within half a metre.
func _over_something(game: ZzGame, at: Vector3) -> bool:
	var space := game.get_world_3d().direct_space_state
	var mask := game.ground_mask() | game.physics.layer_mask(&"prop")
	var query := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 0.3, 0.0), at + Vector3(0.0, -0.5, 0.0), mask)
	return not space.intersect_ray(query).is_empty()

## Why a person could not stand at [param at], or "" when they can.
func _spawn_fault(game: ZzGame, at: Vector3) -> String:
	var space := game.get_world_3d().direct_space_state
	var mask := game.ground_mask() | game.physics.layer_mask(&"prop")

	var down := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 0.5, 0.0), at + Vector3(0.0, -0.6, 0.0), mask)
	if space.intersect_ray(down).is_empty():
		return "nothing under it"

	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = mask
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, HEIGHT * 0.5 + 0.08, 0.0))

	var hits := space.intersect_shape(query, 4)

	if not hits.is_empty():
		var what: Array = []
		for hit: Dictionary in hits:
			var index := game.map.prop_from_hit(hit["collider"], int(hit["shape"]))
			what.append(String(game.map.prop_id(index)) if index >= 0 else "a wall")
		return "in the way: %s" % ", ".join(what)

	return ""

func _inside_world(game: ZzGame, point: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collision_mask = game.physics.layer_mask(&"world")
	return not game.get_world_3d().direct_space_state.intersect_point(query, 1).is_empty()

## A ray down from just inside the prop's base finds a floor, a table or another prop within
## a few centimetres. A tilted prop is tested from its lowest corner's height.
func _rests_on_something(game: ZzGame, frame: Transform3D, size: Vector3) -> bool:
	var space := game.get_world_3d().direct_space_state
	var mask := game.ground_mask() | game.physics.layer_mask(&"prop")
	var base := frame.origin

	for x in [-0.3, 0.0, 0.3]:
		for z in [-0.3, 0.0, 0.3]:
			var from := frame * Vector3(size.x * x, 0.04, size.z * z)
			var query := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, base.y - 0.12, from.z), mask)
			query.hit_from_inside = false
			if not space.intersect_ray(query).is_empty():
				return true

	return false

func _world(id: StringName, drawn := false) -> ZzGame:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(id)]) if id != &"" else PackedStringArray()

	var game := ZzGame.new()
	game.name = "World_%s" % String(id)
	game.config = config
	game.tick_rate = 60
	game.authoritative = true
	game.draw_world = drawn
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return game
