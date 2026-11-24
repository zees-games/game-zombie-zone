extends GSGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzNavGraph := preload("../game/zz_nav_graph.gd")
const ZzNavLadderSeed := preload("../game/zz_nav_ladder_seed.gd")
const ZzNavNotes := preload("../game/zz_nav_notes.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const StuckMeter := preload("../tools/stuck_meter.gd")
const ZzUnstick := preload("../game/zz_unstick.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)

## Maps held by a team, and how far from a choke a stand-in counts as holding it: as far as the
## game may put the place to stand.
const MAPS := ["zz_high_school", "zz_mall", "zz_stadium", "zz_relief_camp", "zz_chapel", "zz_lot", "zs_ravenstreet"]
const NEAR := ZzNavNotes.HOLD_FARTHEST

## Seconds the stand-ins have to walk to their places before a wave comes.
const SETTLE := 45.0
const HORDE_SECONDS := 120.0

## Every shipped map, for the stuck measurement.
const ALL_MAPS := ["zz_blackout_1", "zz_blackout_2", "zz_blackout_3", "zz_chapel", "zz_high_school", "zz_lot", "zz_mall", "zz_relief_camp",
	"zz_stadium", "zs_ravenstreet", "zm_4way_tunnel", "zm_abandoned_mall", "zm_atix_helicopter", "zm_chaos_city", "zm_house_outbreak",
	"zm_officeattack", "zm_pathogen", "ze_blackmesa_escape", "ze_boat_escape", "ze_death_star_escape", "ze_jurassicpark", "ze_nuke_beta",
	"ze_runforyourlife_1_v4"]

## Maps held to a stuck band, each once a worst case: blackout_2 had a 108 s wedge on a pallet, lot and
## high_school wedged stand-ins on a low prop. The bands
## because two runs of one map differ; they catch a return to those numbers, not a 1% drift.
const STUCK_BANDS := ["zz_blackout_2", "zz_lot", "zz_high_school"]
const STANDIN_BAND := 0.15
const COMMON_BAND := 0.10
## Stand-in goal time is 40 to 140 s of a 150 s run on a held lot (same spread before the blood
## migration: 1 run in 8 and 2 in 12 were over 15%), so the ratio is taken over at least this much.
const STANDIN_MIN_GOAL := 200.0
const LONGEST_BAND := 30.0

## Simulated seconds a map is played for the stuck measurement, after the first ten.
const STUCK_SECONDS := 150.0

## What a stand-in map's team is raised to: the maps that say none are still held by a few.
const TEAM := 8

var _sections_entered := 0
var _sections_finished := 0
var _worlds: Array[ZzGame] = []
var _linked := false

## A stand-in for the horde that says how many zombies are at a choke.
class Crowd:
	extends RefCounted
	var count := 0

	class Fake:
		extends RefCounted
		var instance_id := 0

	func zombies_near(_at: Vector3, _radius: float) -> Array:
		var out: Array = []

		for i in count:
			var z := Fake.new()
			z.instance_id = i
			out.append(z)

		return out



func _world(configure: Callable = Callable()) -> ZzGame:
	for old in _worlds.duplicate():
		await _dispose(old)

	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.start_grace_seconds = 1.0
	config.common_speed_scaling = false  # timed against the old running pace
	config.escape_grace_seconds = 0.0

	if configure.is_valid():
		configure.call(config)

	var game := ZzGame.new()
	game.name = "World%d" % _worlds.size()
	game.config = config
	game.tick_rate = TICK_RATE
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	_worlds.append(game)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return game


func _dispose(game: ZzGame) -> void:
	_worlds.erase(game)

	if not is_instance_valid(game):
		return

	remove_child(game)
	game.free()
	await get_tree().process_frame


func _sim(game: ZzGame, seconds: float) -> void:
	var ticks := maxi(int(round(seconds * float(TICK_RATE))), 1)

	for i in ticks:
		game.simulate(TICK)

		if i % 8 == 7:
			await get_tree().physics_frame

	await get_tree().physics_frame


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1
