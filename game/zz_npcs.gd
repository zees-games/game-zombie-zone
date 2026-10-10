extends RefCounted

const ZzConfig := preload("zz_config.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzPaths := preload("zz_paths.gd")

## What can come at you, and the ground it walks on.
##
## [b]Nine kinds, and only one is the crowd.[/b] The common infected are most of what is ever
## alive; the eight specials are each a different answer to "what does a team that sticks
## together and shoots straight still have to fear", which is the genre's whole design:
##
## [codeblock]
## common     the crowd. Weak alone, a down in seconds when it surrounds you.
## leaper     waits crouched out of sight, then jumps from twenty metres and pins whoever strayed.
## strangler  a tongue from cover across a street: drags one survivor away and chokes them.
## bloater    slow and soft. Its vomit blinds you and calls every common in earshot to you;
##            so does its bursting, which is why you shove it rather than shoot it close.
## ram        charges in a straight line, carries whoever it hit and beats them on the floor.
## spitter    lobs acid where you are standing, or where your friend is lying pinned.
## rider      leaps onto a head and steers its victim away from help.
## brute      the boss. Throws a rock, then a car's worth of fists; you shoot it together.
## sleeper    sits crying in the dark. Leave her alone.
## [/codeblock]
##
## [b]Every number here is a default the catalogue carries in `meta`.[/b] A brain reads its
## numbers with [method DotNpcBrain.tune], so a server owner who wants a faster leaper edits a
## definition rather than a brain; the difficulty scales on top (see [ZzConfig]).
##
## [b]A path, never a `class_name`, for every brain[/b], because a brain in a mounted dot-cloud
## pack cannot resolve one.

const CHANNEL := "zz.npcs"

const COMMON := &"common"
const LEAPER := &"leaper"
const STRANGLER := &"strangler"
const BLOATER := &"bloater"
const RAM := &"ram"
const SPITTER := &"spitter"
const RIDER := &"rider"
const BRUTE := &"brute"
const SLEEPER := &"sleeper"

## The specials the director chooses between. Not the brute (its own clock) or the sleeper
## (placed by the map).
const SPECIALS: Array[StringName] = [LEAPER, STRANGLER, BLOATER, RAM, SPITTER, RIDER]

const FACTION := &"infected"

static var SCENE := ZzPaths.rebase("res://npcs/zz_zombie.tscn")
static var COMMON_BRAIN := ZzPaths.rebase("res://npcs/zz_common_brain.gd")
static var LEAPER_BRAIN := ZzPaths.rebase("res://npcs/zz_leaper_brain.gd")
static var STRANGLER_BRAIN := ZzPaths.rebase("res://npcs/zz_strangler_brain.gd")
static var BLOATER_BRAIN := ZzPaths.rebase("res://npcs/zz_bloater_brain.gd")
static var RAM_BRAIN := ZzPaths.rebase("res://npcs/zz_ram_brain.gd")
static var SPITTER_BRAIN := ZzPaths.rebase("res://npcs/zz_spitter_brain.gd")
static var RIDER_BRAIN := ZzPaths.rebase("res://npcs/zz_rider_brain.gd")
static var BRUTE_BRAIN := ZzPaths.rebase("res://npcs/zz_brute_brain.gd")
static var SLEEPER_BRAIN := ZzPaths.rebase("res://npcs/zz_sleeper_brain.gd")


static func is_special(kind: StringName) -> bool:
	return kind != COMMON and kind != &""


static func catalogue(config: ZzConfig = null) -> DotNpcCatalogue:
	var c := config if config != null else ZzConfig.new()
	var out := DotNpcCatalogue.new()
	out.meta = {"game": "zombiezone"}

	for def in [_common(c), _leaper(c), _strangler(c), _bloater(c), _ram(c), _spitter(c),
			_rider(c), _brute(c, 1), _sleeper(c)]:
		var added := out.add(_eyes(def))

		if not added.ok:
			DotLog.warn(CHANNEL, "a zombie could not be catalogued", {
				"npc": String(def.id), "why": added.error.message
			})

	return out


## The population a map runs under. Commons are cheap; a special costs what it is worth, so the
## world budget is a real ceiling on how bad things can get at once.
static func limits(config: ZzConfig, survivors: int) -> DotNpcLimits:
	var out := DotNpcLimits.new()
	out.world_budget = config.commons_cap(survivors) + 8 * (config.specials_cap(survivors) + 2)
	out.per_kind_cap = config.commons_cap(survivors)
	out.spawn_interval = 0.0
	out.burst_cap = 64

	# Far: a campaign map is long, and a mob running to the team from eighty metres behind is a
	# mob, not something to tidy away. The director reclaims what the team left behind itself.
	out.reclaim_distance = 140.0
	out.reclaim_grace = 8.0
	out.clean_up_on_leave = false

	# Every third tick. A common that notices you 45 ms late is a common nobody can tell from
	# one that noticed at once, and perception is the most expensive thing a horde does.
	out.sense_period_ticks = 3
	out.sense_candidate_cap = 24

	out.require_navigable_spawn = true
	out.spawn_snap_radius = 2.5
	return out


# --- The kinds -----------------------------------------------------------------------------

static func _def(id: StringName, title: String, brain: String, health: float, speed: float,
		cost: int, weight: DotNpcDef.Weight) -> DotNpcDef:
	var def := DotNpcDef.make(id, SCENE)
	def.display_name = title
	def.category = &"zombie"
	def.faction = FACTION
	def.brain_script_path = brain
	def.max_health = health
	def.move_speed = speed
	def.cost = cost
	def.weight = weight
	def.require_line_of_sight = true
	return def


## Every kind looks from near the top of itself: a brute over a car, a rider from knee height.
static func _eyes(def: DotNpcDef) -> DotNpcDef:
	def.eye_height = float(def.meta.get("height", 1.75)) * 0.9
	return def


## The crowd.
##
## [b]Short sight and good ears while it idles, which is what makes sneaking past one a thing a
## player can do.[/b] Its brain widens both once it is alert; the senses read the instance's
## `sight_scale`, which the brain sets.
static func _common(c: ZzConfig) -> DotNpcDef:
	var def := _def(COMMON, "Infected", COMMON_BRAIN, c.common_health, c.common_run_speed, 1, DotNpcDef.Weight.NORMAL)
	def.sight_range = 30.0
	def.sight_half_angle_deg = 75.0
	def.hearing_range = 10.0
	def.meta = {
		"damage": c.common_damage, "reach": 1.55, "attack_interval": c.common_attack_interval,
		"walk_speed": c.common_walk_speed, "squad": "horde", "attackers": c.attackers_per_survivor,
		"body": "common", "radius": 0.32, "height": 1.75,
	}
	return def


static func _leaper(c: ZzConfig) -> DotNpcDef:
	var def := _def(LEAPER, "Leaper", LEAPER_BRAIN, 250.0 * c.special_health_scale(), 7.4, 4, DotNpcDef.Weight.LIGHT)
	def.sight_range = 60.0
	def.sight_half_angle_deg = 100.0
	def.hearing_range = 20.0
	def.require_line_of_sight = false
	def.meta = {
		"damage": 5.0, "reach": 1.6, "attack_interval": 0.5,
		"pounce_min": 4.0, "pounce_max": 22.0, "pounce_speed": 16.0, "pounce_damage": 5.0,
		"pin_damage": 5.0, "pin_interval": 0.5, "stalk_speed": 3.2,
		"body": "leaper", "radius": 0.3, "height": 1.6,
	}
	return def


static func _strangler(c: ZzConfig) -> DotNpcDef:
	var def := _def(STRANGLER, "Strangler", STRANGLER_BRAIN, 250.0 * c.special_health_scale(), 4.6, 4, DotNpcDef.Weight.NORMAL)
	def.sight_range = 50.0
	def.sight_half_angle_deg = 90.0
	def.hearing_range = 18.0
	def.meta = {
		"damage": 6.0, "reach": 1.6, "attack_interval": 1.0,
		"tongue_range": 24.0, "tongue_speed": 30.0, "pull_speed": 3.2, "drag_damage": 1.5,
		"choke_damage": 5.0, "choke_interval": 1.0, "tongue_cooldown": 15.0, "tongue_health": 20.0,
		"body": "strangler", "radius": 0.32, "height": 2.0,
	}
	return def


static func _bloater(c: ZzConfig) -> DotNpcDef:
	var def := _def(BLOATER, "Bloater", BLOATER_BRAIN, 50.0, 4.0, 3, DotNpcDef.Weight.HEAVY)
	def.sight_range = 40.0
	def.sight_half_angle_deg = 90.0
	def.hearing_range = 16.0
	def.meta = {
		"damage": 4.0, "reach": 1.6, "attack_interval": 1.2,
		"vomit_range": 5.0, "vomit_half_angle": 28.0, "vomit_cooldown": 20.0, "bile_seconds": 15.0,
		"burst_radius": 3.6,
		"body": "bloater", "radius": 0.5, "height": 1.85,
	}
	return def


static func _ram(c: ZzConfig) -> DotNpcDef:
	var def := _def(RAM, "Ram", RAM_BRAIN, 600.0 * c.special_health_scale(), 5.6, 5, DotNpcDef.Weight.HEAVY)
	def.sight_range = 45.0
	def.sight_half_angle_deg = 80.0
	def.hearing_range = 16.0
	def.meta = {
		"damage": 10.0, "reach": 1.9, "attack_interval": 1.0,
		"charge_range": 26.0, "charge_min": 6.0, "charge_speed": 14.0, "charge_seconds": 2.6,
		"charge_cooldown": 12.0, "impact_damage": 10.0, "pummel_damage": 15.0, "pummel_interval": 1.1,
		"body": "ram", "radius": 0.45, "height": 2.0,
	}
	return def


static func _spitter(c: ZzConfig) -> DotNpcDef:
	var def := _def(SPITTER, "Spitter", SPITTER_BRAIN, 100.0 * c.special_health_scale(), 5.2, 3, DotNpcDef.Weight.LIGHT)
	def.sight_range = 50.0
	def.sight_half_angle_deg = 90.0
	def.hearing_range = 16.0
	def.meta = {
		"damage": 4.0, "reach": 1.6, "attack_interval": 1.0,
		"spit_range": 28.0, "spit_min": 6.0, "spit_cooldown": 18.0, "spit_speed": 15.0,
		"acid_radius": 3.2, "acid_seconds": 7.0, "acid_damage": 6.0,
		"body": "spitter", "radius": 0.3, "height": 1.9,
	}
	return def


static func _rider(c: ZzConfig) -> DotNpcDef:
	var def := _def(RIDER, "Rider", RIDER_BRAIN, 325.0 * c.special_health_scale(), 7.0, 4, DotNpcDef.Weight.LIGHT)
	def.sight_range = 45.0
	def.sight_half_angle_deg = 100.0
	def.hearing_range = 18.0
	def.meta = {
		"damage": 4.0, "reach": 1.4, "attack_interval": 0.8,
		"leap_range": 6.0, "leap_speed": 11.0, "ride_damage": 4.0, "ride_interval": 1.0,
		"ride_speed": 3.4, "leap_cooldown": 6.0,
		"body": "rider", "radius": 0.28, "height": 1.2,
	}
	return def


## The boss. Its health is set at spawn from how many survivors there are; see [method brute_health].
static func _brute(c: ZzConfig, survivors: int) -> DotNpcDef:
	var def := _def(BRUTE, "Brute", BRUTE_BRAIN, brute_health(c, survivors), 6.1, 12, DotNpcDef.Weight.HEAVY)
	def.sight_range = 80.0
	def.sight_half_angle_deg = 120.0
	def.hearing_range = 40.0
	def.require_line_of_sight = false
	def.meta = {
		"damage": 24.0, "reach": 2.4, "attack_interval": 1.45, "knock": 1.0,
		"rock_range": 40.0, "rock_min": 9.0, "rock_cooldown": 9.0, "rock_damage": 24.0, "rock_speed": 24.0,
		"frustration_seconds": 25.0,
		"body": "brute", "radius": 0.7, "height": 2.9,
	}
	return def


static func brute_health(c: ZzConfig, survivors: int) -> float:
	return (c.brute_health + c.brute_health_per_survivor * float(maxi(survivors - 1, 0))) * c.special_health_scale()


static func _sleeper(c: ZzConfig) -> DotNpcDef:
	var def := _def(SLEEPER, "Sleeper", SLEEPER_BRAIN, 1000.0 * c.special_health_scale(), 7.8, 0, DotNpcDef.Weight.NORMAL)
	def.sight_range = 14.0
	def.sight_half_angle_deg = 180.0
	def.hearing_range = 10.0
	def.require_line_of_sight = false
	def.meta = {
		"damage": 100.0, "reach": 1.7, "attack_interval": 1.0,
		"startle_near": 7.0, "startle_seconds": 3.0, "flee_seconds": 10.0,
		"body": "sleeper", "radius": 0.3, "height": 1.6,
	}
	return def


# --- Navigation ------------------------------------------------------------------------------

## The ground the zombies walk on, for one map document: its nav floors, everything solid on
## them as an obstacle, and its links between storeys.
##
## [b]Built from the same document the map was built from, so the two cannot disagree.[/b] A
## box is in the way unless the map says it is not (`"nav": false`) or it is a floor — its top
## is a nav floor's height and it lies under that floor. A prop is in the way when it is taller
## than a step. A gate is in the way while it is shut: the graph is built again when one opens
## ([param open_gates]), because a horde that pathed through a shut door would pile up against
## it, and one that never learned it had opened would never come through.
static func nav_for(doc: Dictionary, props_size: Callable, open_gates: PackedStringArray = PackedStringArray()) -> DotNpcNavData:
	var nav_doc: Dictionary = doc.get("nav", {})
	var builder := DotNpcNavBuilder.new()
	builder.spacing = float(nav_doc.get("spacing", 1.0))
	builder.point_radius = builder.spacing * 1.25
	builder.clearance = float(nav_doc.get("clearance", 0.35))
	builder.generate_cover = true
	builder.cover_range = 1.2

	var floors: Array = nav_doc.get("floors", [])

	for f: Array in floors:
		var area := AABB(Vector3(float(f[0]), float(f[4]), float(f[1])),
			Vector3(float(f[2]) - float(f[0]), 0.0, float(f[3]) - float(f[1])))
		builder.add_floor(area, float(f[4]))

	for box: Dictionary in doc.get("boxes", []):
		if not bool(box.get("solid", true)):
			continue

		if box.has("gate") and open_gates.has(str(box["gate"])):
			continue

		if box.has("nav") and not bool(box["nav"]):
			continue

		var bounds := _box_bounds(box)

		if not box.has("nav") and _is_floor(bounds, floors):
			continue

		builder.add_obstacle(bounds)

	if props_size.is_valid():
		for prop: Dictionary in doc.get("props", []):
			var size: Vector3 = props_size.call(StringName(str(prop["id"])))

			if size.y < 0.5:
				continue

			var at := ZzMapDoc.v3(prop["at"])
			var turn := Basis(Vector3.UP, deg_to_rad(float(prop.get("yaw", 0.0))))
			var half := size * 0.5
			var extent := Vector3(
				absf(turn.x.x) * half.x + absf(turn.z.x) * half.z, half.y,
				absf(turn.x.z) * half.x + absf(turn.z.z) * half.z)
			builder.add_obstacle(AABB(at + Vector3(-extent.x, 0.0, -extent.z), Vector3(extent.x * 2.0, size.y, extent.z * 2.0)))

	for link: Array in nav_doc.get("links", []):
		builder.add_link(Vector3(float(link[0]), float(link[1]), float(link[2])),
			Vector3(float(link[3]), float(link[4]), float(link[5])))

	return builder.build(StringName(str(doc.get("id", "map"))), digest_of(doc, open_gates))


## The axis-aligned bounds of a (possibly turned) box.
static func _box_bounds(box: Dictionary) -> AABB:
	var size := ZzMapDoc.v3(box["size"])
	var at := ZzMapDoc.v3(box["at"])
	var yaw := deg_to_rad(float(box.get("yaw", 0.0)))

	if yaw == 0.0:
		return AABB(at - size * 0.5, size)

	var turn := Basis(Vector3.UP, yaw)
	var half := size * 0.5
	var extent := Vector3(
		absf(turn.x.x) * half.x + absf(turn.z.x) * half.z, half.y,
		absf(turn.x.z) * half.x + absf(turn.z.z) * half.z)
	return AABB(at - extent, extent * 2.0)


## Whether [param bounds] is a floor: its top at a nav floor's height, under that floor.
static func _is_floor(bounds: AABB, floors: Array) -> bool:
	var top := bounds.end.y

	for f: Array in floors:
		if absf(top - float(f[4])) > 0.12:
			continue

		if bounds.position.x < float(f[2]) and bounds.end.x > float(f[0]) \
				and bounds.position.z < float(f[3]) and bounds.end.z > float(f[1]):
			return true

	return false


## A fingerprint of everything the graph was built from.
static func digest_of(doc: Dictionary, open_gates: PackedStringArray = PackedStringArray()) -> String:
	return DotNpcNavData.digest_of([
		str(doc.get("id", "")), JSON.stringify(doc.get("nav", {})),
		JSON.stringify(doc.get("boxes", [])).sha256_text(), JSON.stringify(doc.get("props", [])).sha256_text(),
		",".join(open_gates),
	])
