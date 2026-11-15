extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")

const ZzGame := preload("../game/zz_game.gd")

const ZzMechanics := preload("../game/zz_mechanics.gd")

const MapCommands := preload("../game/zz_map_commands.gd")

const ZzMap := preload("../game/zz_map.gd")

const ZzLoot := preload("../game/zz_loot.gd")

const ZzMapObjects := preload("../game/zz_map_objects.gd")

const ZzEvents := preload("../game/net/zz_events.gd")

const ZzNpcs := preload("../game/zz_npcs.gd")

const ZzNavPrune := preload("../game/zz_nav_prune.gd")

const SolidProps := preload("../tools/solid_props.gd")

const ZzPlayer := preload("../game/zz_player.gd")

## A converted map's lifts, doors, buttons and triggers: a lift on the real 4-way tunnel carries a survivor up, a door blocks and opens, a button's outputs run after their delays,
## and a map without a world has no moving parts. [b]Why the doors and links are tried on a made-up world as well.[/b] The real maps' doors are mostly boxes or objective gates; the
## ones that are movers are driven by one button or by walking up, so the chain (button, delay, relay, volume, lock) is only reachable in a fixture.

const ZzPaths := preload("../game/zz_paths.gd")

const ZzFooting := preload("../game/zz_footing.gd")

const TICK_RATE := 64

const TICK := 1.0 / float(TICK_RATE)

const LIFT_MAP := &"zm_4way_tunnel"

const SECTIONS := 18

const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")

var _entered := 0

var _finished := 0

## Checks of sections that need the drawn worlds, skipped because world/ is not linked (CI).
var _skipped := 0

## What the running section passed to _skip_without_world (-1: none), checked against what it ran when world/ is
## here, so a declared count that drifts fails locally rather than only in CI (release
## v0.1.30 and v0.1.31 failed validate on it: 77 checks ran, 79 then 83 expected).
var _declared := -1

## A world made of data, for the chain tests: the same calls a DotMapBspMesh answers.
class FakeWorld extends RefCounted:
	var ents: Variant = null
	var model_ids := PackedInt32Array()

	func _init(manifest: Dictionary) -> void:
		ents = DotMapEntities.from_manifest(manifest)
		for rec: Dictionary in manifest["movers"]:
			model_ids.append(int(rec["model"]))

	func entities() -> Variant:
		return ents

	func models() -> PackedInt32Array:
		return model_ids

	func hull_shapes(_model: int, _kinds: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 3.0, 2.0)
		var convex := ConvexPolygonShape3D.new()
		var pts := PackedVector3Array()
		for x in [-0.5, 0.5]:
			for y in [0.0, 3.0]:
				for z in [-1.0, 1.0]:
					pts.append(Vector3(x, y, z))
		convex.points = pts
		return [{"shape": convex, "kind": "solid", "brush": 0}]

## Whether this section is skipped for want of world/ (zombie-zone-maps' drawn worlds, never in CI). Loud and counted,
## so that a checkout with the worlds still runs every check and a section cannot vanish unnoticed.
func _skip_without_world(checks: int) -> bool:
	if DirAccess.dir_exists_absolute(ZzPaths.rebase("res://world")):
		_declared = checks
		return false

	_skipped += checks
	_finished += 1
	print("  SKIP  %d checks: this section needs world/ (not linked)" % checks)
	return true

func _game(id: StringName, start := false) -> ZzGame:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.start_grace_seconds = 600.0
	config.escape_grace_seconds = 0.0
	config.map_ids = PackedStringArray([String(id)])

	var game := ZzGame.new()
	game.name = "Mech%s" % id
	game.config = config
	game.tick_rate = TICK_RATE
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	if start:
		game.next_map_id = id
		game.start()
		await get_tree().physics_frame

	return game
