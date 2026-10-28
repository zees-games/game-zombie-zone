extends RefCounted

const ZzConfig := preload("zz_config.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzPackList := preload("zz_packs.gd")
const ZzNavGraph := preload("zz_nav_graph.gd")
const ZzNpcProfiles := preload("zz_npc_profiles.gd")
const ZzPaths := preload("zz_paths.gd")
const ZzNavJob := preload("zz_nav_job.gd")

## What can come at you, and the ground it walks on.
##
## [b]Twelve kinds, and only one is the crowd.[/b] The common infected are most of what is ever
## alive; the eleven specials are each a different answer to "what does a team that sticks
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
## screamer   keeps its distance and screams: a mob comes for whoever it saw. Thin, quick to kill,
##            and the one to shoot first.
## crawler    no legs, flat on the ground, slow; grabs the ankle of whoever walks past and holds
##            them in place, gnawing, until somebody shoves it off (the victim can still shoot).
## riot       a common in riot gear: a shield in front that a bullet barely gets through, so it
##            walks into the team's fire. Shot from the side or behind, or shoved round.
## [/codeblock]
##
## [b]Every number here is a default the catalogue carries in `meta`.[/b] A brain reads its
## numbers with [method DotNpcBrain.tune], so a server owner who wants a faster leaper edits a
## definition rather than a brain; the difficulty scales on top (see [ZzConfig]).
##
## [b]A path, never a `class_name`, for every brain[/b], because a brain in a mounted dot-cloud
## pack cannot resolve one.

const CHANNEL := "zz.npcs"

## Where built navigation graphs are kept, keyed by the map's digest. Bump the version when the
## builder's output changes for the same document (the digest cannot see code).
const NAV_CACHE_DIR := "user://nav_cache"
const NAV_CACHE_VERSION := 9

## Metres across which two pieces of the graph are joined when nothing solid is between (a floor plan whose rooms stop short of each other); a map's `nav.bridge` overrides, 0 is off.
const NAV_BRIDGE_GAP := 2.5
const NAV_COVER_RANGE := 1.2

## How far from a post the graph's nearest point may be for a stand-in to path to it.
const POST_SNAP := 2.5

const COMMON := &"common"
const LEAPER := &"leaper"
const STRANGLER := &"strangler"
const BLOATER := &"bloater"
const RAM := &"ram"
const SPITTER := &"spitter"
const RIDER := &"rider"
const BRUTE := &"brute"
const SLEEPER := &"sleeper"
const SCREAMER := &"screamer"
const CRAWLER := &"crawler"
const RIOT := &"riot"
const MUTANT := &"mutant"
const OIL_MONSTER := &"oil_monster"

## The specials the director chooses between. Not the brute (its own clock) or the sleeper
## (placed by the map).
const SPECIALS: Array[StringName] = [LEAPER, STRANGLER, BLOATER, RAM, SPITTER, RIDER, SCREAMER, CRAWLER, RIOT, MUTANT, OIL_MONSTER]

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
static var SCREAMER_BRAIN := ZzPaths.rebase("res://npcs/zz_screamer_brain.gd")
static var CRAWLER_BRAIN := ZzPaths.rebase("res://npcs/zz_crawler_brain.gd")
static var RIOT_BRAIN := ZzPaths.rebase("res://npcs/zz_riot_brain.gd")
static var MUTANT_BRAIN := ZzPaths.rebase("res://npcs/zz_mutant_brain.gd")
static var OIL_MONSTER_BRAIN := ZzPaths.rebase("res://npcs/zz_oil_monster_brain.gd")


static func is_special(kind: StringName) -> bool:
	return kind != COMMON and kind != &""


## The built-in kinds (twelve) with their `npc` profiles laid over them; [param roots] replaces the config roots (tests).
static func catalogue(config: ZzConfig = null, roots: PackedStringArray = PackedStringArray()) -> DotNpcCatalogue:
	var c := config if config != null else ZzConfig.new()
	var out := DotNpcCatalogue.new()
	out.meta = {"game": "zombiezone"}
	var set := ZzNpcProfiles.make_set(roots)
	var base_config := ZzConfig.new()
	var base := {}
	for d in builtin(base_config):
		base[d.id] = d

	var defs := builtin(c)
	for def in defs:
		ZzNpcProfiles.overlay(def, base[def.id], c, base_config, set)
	set.clear_cache()

	for pack_def in _pack_defs(c):
		defs.append(_eyes(pack_def))

	for def in defs:
		var added := out.add(def)

		if not added.ok:
			DotLog.warn(CHANNEL, "a zombie could not be catalogued", {
				"npc": String(def.id), "why": added.error.message
			})

	return out


## The thirteen kinds from code and [param c] alone, no profile; the floor the shipped ymls are written from.
static func builtin(c: ZzConfig) -> Array:
	var out: Array = []
	for def in [_common(c), _leaper(c), _strangler(c), _bloater(c), _ram(c), _spitter(c),
			_rider(c), _brute(c, 1), _sleeper(c), _screamer(c), _crawler(c), _riot(c), _mutant(c), _oil_monster(c)]:
		out.append(_eyes(def))
	return out


## An installed pack's monsters (see zz_packs.gd), each the common's numbers with the pack's
## `spawn` on top. A special's health scale applies, as it does to every special.
static func _pack_defs(c: ZzConfig) -> Array:
	var out: Array = []

	for m in ZzPackList.monsters:
		var s: Dictionary = m.spawn
		var health := float(s.get("health", 200.0)) * (c.special_health_scale() if not m.boss else 1.0)
		var brain := str(s.get("brain", "")) if s.has("brain") else COMMON_BRAIN
		var def := _def(m.id, m.title, brain, health, float(s.get("speed", 4.4)), 3 if not m.boss else 8,
			DotNpcDef.Weight.NORMAL if not m.boss else DotNpcDef.Weight.HEAVY)
		def.sight_range = 40.0
		def.sight_half_angle_deg = 90.0
		def.hearing_range = 18.0
		def.meta = {
			"damage": float(s.get("damage", 8.0)), "reach": float(s.get("reach", 1.6)),
			"attack_interval": float(s.get("attack_interval", 1.0)), "attackers": c.attackers_per_survivor,
			"body": str(s.get("body", "common")), "radius": 0.34, "height": 1.8, "pack": m.pack,
		}
		out.append(def)

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


## A common's chase speed in m/s: the slow base plus [param hard_stacks] steps, capped; a runner (or
## scaling off) keeps the old full run speed.
static func common_chase_speed(c: ZzConfig, hard_stacks: int, runner: bool) -> float:
	if not c.common_speed_scaling or runner:
		return c.common_run_speed

	return DotStackScale.ramp(c.common_speed_base, c.common_speed_per_hard_stack, c.common_speed_max, hard_stacks)


## How see-through a zombie is drawn at the Hard Box stacks now on (`zz_mutant_fade*`, `zz_common_fade`).
## [param c] is a ZzConfig; commons stay solid unless `zz_common_fade` is on.
static func fade_alpha(c: Object, kind: StringName, stacks: int) -> float:
	if int(c.get(&"mutant_fade")) != 1:
		return 1.0

	if kind == &"common" and int(c.get(&"common_fade")) != 1:
		return 1.0

	return DotStackScale.fade_alpha(stacks, float(c.get(&"mutant_fade_per_stack")), float(c.get(&"mutant_min_alpha")))


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


static func _mutant(c: ZzConfig) -> DotNpcDef:
	var def := _def(MUTANT, "Mutant", MUTANT_BRAIN, 900.0 * c.special_health_scale(), 2.4, 6, DotNpcDef.Weight.HEAVY)
	def.sight_range = 60.0
	def.sight_half_angle_deg = 120.0
	def.hearing_range = 25.0
	def.meta = {
		"damage": 14.0, "reach": 1.9, "attack_interval": 1.4,
		"zap_range": 24.0, "zap_damage": 4.0, "zap_interval": 2.5,
		"prop_chance": 0.5, "prop_range": 14.0, "prop_mass": 40.0, "pull_speed": 14.0,
		"hold_time": 1.0, "throw_speed": 22.0, "throw_range": 30.0, "throw_damage": 8.0, "throw_interval": 4.0,
		"fuel": 14.0, "fuel_regen": 1.4, "fly_speed": 8.0, "cruise_height": 7.0, "fly_from": 14.0, "fly_time": 9.0,
		"angry_health": 0.4, "charge_time": 1.4, "charge_height": 12.0, "dive_speed": 26.0,
		"slam_radius": 7.0, "slam_damage": 30.0, "slam_recover": 3.0, "dive_cooldown": 8.0,
		"body": "mutant", "radius": 0.55, "height": 2.4,
	}
	return def


## The oil monster: slides, leaves a trail, spits goo that blinds and pools. `goo_*` keys are the spit's puddle, `trail_*` the trail's
## (dot-effects' DotHazardProfile keys), `blind_*` the screen impair; none is hardcoded in the brain.
static func _oil_monster(c: ZzConfig) -> DotNpcDef:
	var def := _def(OIL_MONSTER, "Oil monster", OIL_MONSTER_BRAIN, 700.0 * c.special_health_scale(), 3.0, 6, DotNpcDef.Weight.HEAVY)
	def.sight_range = 50.0
	def.sight_half_angle_deg = 110.0
	def.hearing_range = 22.0
	def.meta = {
		"damage": 12.0, "reach": 2.0, "attack_interval": 1.6,
		"spit_range": 26.0, "spit_min": 5.0, "spit_cooldown": 7.0, "spit_speed": 16.0, "spit_damage": 8.0, "spit_windup": 0.5,
		"blind_seconds": 4.0, "blind_max_stacks": 3,
		"goo_radius": 2.6, "goo_seconds": 9.0, "goo_dps": 9.0, "goo_dps_start": 9.0, "goo_slow_factor": 0.6,
		"goo_tick_interval": 0.25, "goo_fade_seconds": 2.0, "goo_global_cap": 40,
		"trail_radius": 1.1, "trail_seconds": 6.0, "trail_dps": 5.0, "trail_dps_start": 5.0, "trail_slow_factor": 0.75,
		"trail_tick_interval": 0.5, "trail_fade_seconds": 1.5, "trail_max_per_owner": 30, "trail_global_cap": 120,
		"trail_spacing": 1.4, "trail_interval": 0.2,
		"body": "oil_monster", "radius": 0.6, "height": 2.5,
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
	def.nav_exclude_flags = ZzNavGraph.NARROW
	def.sight_range = 80.0
	def.sight_half_angle_deg = 120.0
	def.hearing_range = 40.0
	def.require_line_of_sight = false
	def.meta = {
		"damage": 24.0, "reach": 2.4, "attack_interval": 1.45, "knock": 1.0,
		"rock_range": 40.0, "rock_min": 9.0, "rock_cooldown": 9.0, "rock_damage": 24.0, "rock_speed": 24.0,
		"frustration_seconds": 25.0,
		"body": "brute", "radius": 0.7, "height": 2.9, "fit_height": 2.1,
	}
	return def


static func brute_health(c: ZzConfig, survivors: int, def: DotNpcDef = null) -> float:
	var base: float = float(def.meta.get("brute_health", c.brute_health)) if def != null else c.brute_health
	return (base + c.brute_health_per_survivor * float(maxi(survivors - 1, 0))) * c.special_health_scale()


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


## Thin and quick to kill; what it does is call the horde. Health is low on purpose: it is the
## special a team wins by noticing, not by emptying a magazine into.
static func _screamer(c: ZzConfig) -> DotNpcDef:
	var def := _def(SCREAMER, "Screamer", SCREAMER_BRAIN, 90.0 * c.special_health_scale(), 5.4, 3, DotNpcDef.Weight.LIGHT)
	def.sight_range = 55.0
	def.sight_half_angle_deg = 100.0
	def.hearing_range = 20.0
	def.meta = {
		"damage": 3.0, "reach": 1.5, "attack_interval": 1.0,
		"scream_range": 35.0, "scream_min": 9.0, "scream_seconds": 1.6, "scream_cooldown": c.screamer_cooldown,
		"scream_mob": c.screamer_mob,
		"body": "screamer", "radius": 0.28, "height": 2.0,
	}
	return def


## Low enough that a shot over the crowd's heads misses it, and slow; its danger is where it
## lies, not how fast it comes.
static func _crawler(c: ZzConfig) -> DotNpcDef:
	var def := _def(CRAWLER, "Crawler", CRAWLER_BRAIN, 150.0 * c.special_health_scale(), 2.6, 3, DotNpcDef.Weight.LIGHT)
	def.sight_range = 25.0
	def.sight_half_angle_deg = 120.0
	def.hearing_range = 14.0
	def.meta = {
		"damage": 4.0, "reach": 1.3, "attack_interval": 1.0,
		"grab_reach": 1.5, "pin_dps": c.crawler_grab_dps, "grab_cooldown": 6.0, "lunge_speed": 4.5,
		"body": "crawler", "radius": 0.34, "height": 0.75,
	}
	return def


## Walks into fire behind a shield (`shield` is the share of a frontal hit that gets through).
static func _riot(c: ZzConfig) -> DotNpcDef:
	var def := _def(RIOT, "Riot", RIOT_BRAIN, 260.0 * c.special_health_scale(), 4.4, 3, DotNpcDef.Weight.HEAVY)
	def.sight_range = 40.0
	def.sight_half_angle_deg = 90.0
	def.hearing_range = 18.0
	def.meta = {
		"damage": 9.0, "reach": 1.6, "attack_interval": 1.1, "shield": c.riot_shield,
		"body": "riot", "radius": 0.36, "height": 1.85,
	}
	return def


# --- Navigation ------------------------------------------------------------------------------

## A prop at least this tall is cut out of the graph. It was half a metre, and a pallet 0.41 m high
## (2.7 m square, chamfered) sat across a loading bay on zz_blackout_2: every zombie that met its
## corner stood there for a hundred seconds, sliding on six contacts, because the graph said the
## way was clear and the body could not step it.
const PROP_CUT_HEIGHT := 0.3
## A drawn world's solid prop is cut only above a zombie's step (STEP_UP 0.45) and below head height: a low crate in a corridor is stepped over.
const SOLID_PROP_CUT_HEIGHT := 0.5
const SOLID_PROP_HEAD := 1.8
## A box whose underside is lower than this above a point blocks it: a body does not fit under a desk top on legs.
## 1.2 cut a fixture hung across the corridor and a stairwell out of the escape maps' graphs.
const NAV_OVERHEAD := 0.9
## Maps where even 0.9 cuts the only way on (a 0.83 m fixture 0.42 m above a landing): -1 is the clearance, the old rule.
const NAV_OVERHEAD_BY_MAP := {"ze_nuke_beta": -1.0}
## A turned prop thinner than this is cut as a row of boxes along its length, not one box round its corners.
const THIN_PROP := 0.6
const THIN_STEP := 0.4
## Metres above the higher end a link is tested for a wall at (a counter top and a chest), and trimmed off each end of it.
const LINK_TEST_HEIGHTS := [0.4, 0.9]
const LINK_TEST_TRIM := 0.15
## A link that rises more than this is a drop or a climb, and is tested against the floors it crosses.
const LINK_STEEP := 1.2
## Horizontal run inside a floor slab below which a level-changing link only nicks the slab's edge.
const LINK_CLIP_MIN := 0.3
## How far (m) and how far off in height a graph point may stand from the foot or head of a ladder and still be its end.
const LADDER_REACH := 6.5
const LADDER_HEIGHT := 1.5

## The ground the zombies walk on, for one map document: its nav floors, everything solid on
## them as an obstacle, and its links between storeys.
##
## [b]Built from the same document the map was built from, so the two cannot disagree.[/b] A
## box is in the way unless the map says it is not (`"nav": false`) or it is a floor — its top
## is a nav floor's height and it lies under that floor. A prop is in the way when it is taller
## than a step. A gate is in the way while it is shut: the graph is built again when one opens
## ([param open_gates]), because a horde that pathed through a shut door would pile up against
## it, and one that never learned it had opened would never come through.
## The boxes a prop of [param size] turned [param yaw] degrees at [param at] is cut out of the ground as.
## One box round a turned door panel or fence closes the doorway beside it and leaves a mover
## standing in the cut with no line to the graph; a thin one is cut as short boxes along its length.
static func prop_obstacles(at: Vector3, yaw: float, size: Vector3) -> Array[AABB]:
	var turn := Basis(Vector3.UP, deg_to_rad(yaw))
	var half := size * 0.5
	var out: Array[AABB] = []
	var along := turn.z if half.z >= half.x else turn.x
	var long_half := maxf(half.x, half.z)
	var short_half := minf(half.x, half.z)
	var skew := absf(absf(along.x) - 0.5) < 0.49 and short_half * 2.0 < THIN_PROP and long_half > THIN_STEP

	if not skew:
		var extent := Vector3(
			absf(turn.x.x) * half.x + absf(turn.z.x) * half.z, half.y,
			absf(turn.x.z) * half.x + absf(turn.z.z) * half.z)
		out.append(AABB(at + Vector3(-extent.x, 0.0, -extent.z), Vector3(extent.x * 2.0, size.y, extent.z * 2.0)))
		return out

	var pieces := ceili(long_half * 2.0 / THIN_STEP)
	var piece_half := long_half / float(pieces)
	var across := turn.x if half.z >= half.x else turn.z
	var reach := Vector2(absf(along.x) * piece_half + absf(across.x) * short_half, absf(along.z) * piece_half + absf(across.z) * short_half)

	for i in pieces:
		var centre := at + along * (-long_half + piece_half * (2.0 * float(i) + 1.0))
		out.append(AABB(centre + Vector3(-reach.x, 0.0, -reach.y), Vector3(reach.x * 2.0, size.y, reach.y * 2.0)))

	return out


static func nav_for(doc: Dictionary, props_size: Callable, open_gates: PackedStringArray = PackedStringArray(), extra_solids: Array[AABB] = [], cache: bool = false) -> DotNpcNavData:
	var job := nav_job(doc, props_size, open_gates, extra_solids, cache, false)
	var built := job.run_blocking()
	job.flush_log()
	return built


## The same graph as [method nav_for] as a job to be stepped or run on a thread ([ZzNavJob]).
## [param isolate] copies the document, for a thread that must not see the game change it. The
## props' sizes are asked here, on the calling thread, because a catalogue is not the job's to read.
static func nav_job(doc: Dictionary, props_size: Callable, open_gates: PackedStringArray, extra_solids: Array[AABB], cache: bool, isolate: bool) -> ZzNavJob:
	var source := doc.duplicate(true) if isolate else doc
	var sizes := {}

	if props_size.is_valid():
		for prop: Dictionary in source.get("props", []):
			var id := StringName(str(prop["id"]))

			if not sizes.has(id):
				sizes[id] = props_size.call(id)

	var job := ZzNavJob.new()
	var known := props_size.is_valid()
	job.make_builder = func(heights: Array, info: Dictionary) -> DotNpcNavBuilder:
		return _builder_for(source, sizes if known else {}, known, open_gates, extra_solids, heights, info)
	job.reach = func(nav: DotNpcNavData) -> Vector2i:
		return _reach(nav, source)
	job.map_id = StringName(str(source.get("id", "map")))
	job.digest = digest_of(source, open_gates, extra_solids)
	job.strict_heights = LINK_TEST_HEIGHTS
	job.workers = 1

	if cache:
		job.cache_path = "%s/%s-%s-v%d.nav" % [NAV_CACHE_DIR, str(source.get("id", "map")).validate_filename(), job.digest.left(16), NAV_CACHE_VERSION]

	return job


## [param doc] with one climb link per ladder box in [param ladders] (metres, world): foot to head, joined to the graph's
## nearest points. Kept apart from `nav.links` because a ladder stands in a wall, which the links' wall test would drop.
static func with_ladders(doc: Dictionary, ladders: Array[AABB]) -> Dictionary:
	if ladders.is_empty():
		return doc

	var out := doc.duplicate()
	var nav: Dictionary = (doc.get("nav", {}) as Dictionary).duplicate()
	var rows: Array = []

	for box in ladders:
		var mid := box.get_center()
		rows.append([snappedf(mid.x, 0.01), snappedf(box.position.y + 0.1, 0.01), snappedf(mid.z, 0.01),
				snappedf(mid.x, 0.01), snappedf(box.end.y, 0.01), snappedf(mid.z, 0.01)])

	nav["ladders"] = rows
	out["nav"] = nav
	return out


## [param doc] with the boxes of the whole map ([param extra], from the maps pack's `hulls/<id>.nav.json`)
## added, and its floors and links joined to the document's (not replacing them: the full conversion's heights differ
## a little and its graph wandered). The graph is the server's; the wire's limits are for the client's transport. Nothing to add leaves [param doc] as it is.
static func with_nav_extra(doc: Dictionary, extra: Dictionary) -> Dictionary:
	if extra.is_empty():
		return doc

	var out := doc.duplicate()
	var boxes: Array = (doc.get("boxes", []) as Array).duplicate()

	for box: Dictionary in extra.get("boxes", []):
		# attach_world_collision takes only solid, clip and glass hulls: a nodraw brush of the whole map holds no body.
		if str(box.get("kind", "")) != "nodraw":
			boxes.append(box)

	out["boxes"] = boxes
	var nav: Dictionary = (doc.get("nav", {}) as Dictionary).duplicate()
	nav["floors"] = _joined(nav.get("floors", []), extra.get("floors", []), 4)
	nav["links"] = _joined(nav.get("links", []), extra.get("links", []), 6)
	out["nav"] = nav
	return out


## [param have] and the rows of [param more] whose first [param keys] numbers match none of its rows to a centimetre.
static func _joined(have: Array, more: Array, keys: int) -> Array:
	var seen := {}
	for row: Array in have:
		seen[_row_key(row, keys)] = true
	var out := have.duplicate()
	for row: Array in more:
		if not seen.has(_row_key(row, keys)):
			out.append(row)
	return out


static func _row_key(row: Array, keys: int) -> String:
	var parts := PackedStringArray()
	for i in keys:
		parts.append(str(roundi(float(row[i]) * 100.0)))
	return ",".join(parts)


## The map's posts whose nearest point is joined to the first survivor spawn's on [param nav]; every post when none
## is (a map whose graph has no spawn point is not judged).
static func reachable_posts(nav: DotNpcNavData, doc: Dictionary) -> Array:
	var posts: Array = doc.get("posts", [])
	var spawns: Array = (doc.get("spawns", {}) as Dictionary).get("survivors", [])

	if spawns.is_empty() or posts.is_empty():
		return posts

	var graph := DotNpcNavGraph.new(nav)
	var home := nav.nearest_point(ZzMapDoc.v3(spawns[0]["at"]), POST_SNAP)

	if home < 0:
		return posts

	var kept: Array = []

	for p: Variant in posts:
		var point := nav.nearest_point(ZzMapDoc.v3(p), POST_SNAP)

		if point >= 0 and graph.connected(home, point):
			kept.append(p)

	return kept if not kept.is_empty() else posts


## The posts and the points of the ground joined to the first survivor spawn on [param nav].
static func _reach(nav: DotNpcNavData, doc: Dictionary) -> Vector2i:
	var graph := DotNpcNavGraph.new(nav)
	var spawns: Array = (doc.get("spawns", {}) as Dictionary).get("survivors", [])

	if spawns.is_empty():
		return Vector2i.ZERO

	var home := nav.nearest_point(ZzMapDoc.v3(spawns[0]["at"]), 2.0)

	if home < 0:
		return Vector2i.ZERO

	var posts := 0

	for p: Variant in doc.get("posts", []):
		var point := nav.nearest_point(ZzMapDoc.v3(p), 2.0)

		if point >= 0 and graph.connected(home, point):
			posts += 1

	var points := 0

	for i in nav.points.size():
		if graph.connected(home, i):
			points += 1

	return Vector2i(posts, points)


static func _builder_for(doc: Dictionary, sizes: Dictionary, sizes_known: bool, open_gates: PackedStringArray, extra_solids: Array[AABB], heights: Array, info: Dictionary) -> DotNpcNavBuilder:
	var nav_doc: Dictionary = doc.get("nav", {})
	var builder := DotNpcNavBuilder.new()
	builder.spacing = float(nav_doc.get("spacing", 1.0))
	builder.point_radius = builder.spacing * 1.25
	builder.neighbour_reach = 1.6
	builder.centre_narrow_floors = true
	builder.obstacle_under_feet = float(nav_doc.get("under_feet", -1.0))
	builder.obstacle_overhead = float(nav_doc.get("overhead", NAV_OVERHEAD_BY_MAP.get(str(doc.get("id", "")), NAV_OVERHEAD)))
	builder.bridge_gap = float(nav_doc.get("bridge", NAV_BRIDGE_GAP))
	builder.clearance = float(nav_doc.get("clearance", 0.35))
	builder.generate_cover = true
	builder.cover_range = NAV_COVER_RANGE

	var floors: Array = nav_doc.get("floors", [])

	for f: Array in floors:
		var area := AABB(Vector3(float(f[0]), float(f[4]), float(f[1])),
			Vector3(float(f[2]) - float(f[0]), 0.0, float(f[3]) - float(f[1])))
		builder.add_floor(area, float(f[4]))

	if doc.has("terrain"):
		var ground := DotMapTerrain.from_dict(doc["terrain"])
		if ground.ok:
			builder.add_points((ground.value as DotMapTerrain).walk_points(builder.spacing), DotMapTerrain.WALK_RISE)

	var solids: Array[AABB] = []
	## The boxes taken for floors: no wall to a link, but a link that falls through one is no drop.
	var slabs: Array[AABB] = []

	for box: Dictionary in doc.get("boxes", []):
		if not bool(box.get("solid", true)) or ZzMapDoc.is_trim(box):
			continue

		if box.has("gate") and open_gates.has(str(box["gate"])):
			continue

		if box.has("nav") and not bool(box["nav"]):
			continue

		# Sky never collides (ZzMap), and its slab can sit just under a cellar floor, where the clearance would swallow the cellar's points.
		if str(box.get("kind", "")) == "sky":
			continue

		var bounds := _box_bounds(box)

		if not box.has("nav") and _is_floor(bounds, floors):
			slabs.append(bounds)

			# A wall or a mass whose top meets a floor is still a wall to the floors beside and below it (a cellar wall reaching the ground floor).
			if bounds.size.y > SLAB_THICK:
				var body := bounds
				body.size.y -= SLAB_TOP_CUT
				builder.add_obstacle(body)
				solids.append(body)

			continue

		builder.add_obstacle(bounds)
		solids.append(bounds)

	if sizes_known:
		for prop: Dictionary in doc.get("props", []):
			var size: Vector3 = sizes.get(StringName(str(prop["id"])), Vector3.ZERO)

			if size.y < PROP_CUT_HEIGHT:
				continue

			for bounds in prop_obstacles(ZzMapDoc.v3(prop["at"]), float(prop.get("yaw", 0.0)), size):
				builder.add_obstacle(bounds)

	# A drawn world's solid props (the boxes the bodies collide with), cut like a doc prop of that size.
	for rec: Array in doc.get("solid_props", []):
		if float(rec[4]) < SOLID_PROP_CUT_HEIGHT or float(rec[1]) - float(rec[4]) * 0.5 - _floor_under(floors, float(rec[0]), float(rec[2]), float(rec[1])) > SOLID_PROP_HEAD:
			continue

		var base := Vector3(rec[0], float(rec[1]) - float(rec[4]) * 0.5, rec[2])

		for bounds in prop_obstacles(base, float(rec[6]), Vector3(rec[3], rec[4], rec[5])):
			builder.add_obstacle(bounds)

	for bounds in extra_solids:
		builder.add_obstacle(bounds)
		solids.append(bounds)

	var rejected := 0

	for link: Array in nav_doc.get("links", []):
		var from := Vector3(float(link[0]), float(link[1]), float(link[2]))
		var to := Vector3(float(link[3]), float(link[4]), float(link[5]))

		if _link_blocked(from, to, solids, heights) or _link_through_floor(from, to, slabs):
			rejected += 1
			continue

		builder.add_link(from, to)

	for link: Array in nav_doc.get("ladders", []):
		builder.add_link(Vector3(float(link[0]), float(link[1]), float(link[2])), Vector3(float(link[3]), float(link[4]), float(link[5])), 0, LADDER_REACH, LADDER_HEIGHT)

	info["rejected"] = rejected

	if rejected > 0:
		DotLog.debug(CHANNEL, "nav links through solid geometry dropped", {"map": doc.get("id", ""), "dropped": rejected})

	return builder


## Whether the straight run from [param from] to [param to] goes through a wall: the importer
## emits links without looking, and one through a wall joins two rooms that have no door. Tested
## at knee and chest height over the higher end, shrunk at both ends so a link that starts at a wall's face
## is not judged by it. Gates count only while shut (they are in [param solids] only then).
static func _link_blocked(from: Vector3, to: Vector3, solids: Array[AABB], heights: Array) -> bool:
	var top := maxf(from.y, to.y)

	for rise: float in heights:
		var y := top + rise
		var a := Vector3(from.x, y, from.z)
		var b := Vector3(to.x, y, to.z)

		if a.distance_to(b) < 0.5:
			return false

		var dir := (b - a).normalized()
		a += dir * LINK_TEST_TRIM
		b -= dir * LINK_TEST_TRIM

		for bounds in solids:
			if bounds.end.y < y or bounds.position.y > y:
				continue

			if bounds.intersects_segment(a, b):
				return true

	return false


## Whether a link that changes level (a drop, a stair) runs through a floor slab rather than past its edge: the importer
## puts links under decks that have no hole there, and the graph then sends zombies up through a ceiling they push at for ever.
static func _link_through_floor(from: Vector3, to: Vector3, slabs: Array[AABB]) -> bool:
	if absf(from.y - to.y) <= LINK_STEEP:
		return false

	var dir := (to - from).normalized()
	var a := from + dir * LINK_TEST_TRIM
	var b := to - dir * LINK_TEST_TRIM

	for bounds in slabs:
		var enter: Variant = bounds.intersects_segment(a, b)
		var leave: Variant = bounds.intersects_segment(b, a)

		if enter == null or leave == null:
			continue

		# A ceiling is crossed through its underside for more than a nick of its edge; a drop that clips a ledge is not one.
		var p: Vector3 = enter
		var q: Vector3 = leave

		if minf(p.y, q.y) <= bounds.position.y + 0.02 and (Vector2(p.x - q.x, p.z - q.z).length() >= LINK_CLIP_MIN or Vector2(to.x - from.x, to.z - from.z).length() < LINK_CLIP_MIN):
			return true

	return false


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


## The height of the highest nav floor under (x, z) that is no higher than [param y] (a prop's middle), 0 when none: a prop's
## head clearance is measured from the floor it stands on, not from sea level (a deck at 10 m has every prop above 1.8).
static func _floor_under(floors: Array, x: float, z: float, y: float) -> float:
	var best := -INF

	for f: Array in floors:
		var h := float(f[4])

		if h <= y and h > best and x >= float(f[0]) and x <= float(f[2]) and z >= float(f[1]) and z <= float(f[3]):
			best = h

	return 0.0 if best == -INF else best


## Whether [param bounds] is a floor: its top at a nav floor's height, under that floor.
## A box taller than this that meets a floor is a wall as well; its top is cut down by SLAB_TOP_CUT so the floor's own surface stays free.
const SLAB_THICK := 1.0
const SLAB_TOP_CUT := 0.5


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
static func digest_of(doc: Dictionary, open_gates: PackedStringArray = PackedStringArray(), extra_solids: Array[AABB] = []) -> String:
	return DotNpcNavData.digest_of([
		str(doc.get("id", "")), JSON.stringify(doc.get("nav", {})), str(doc.get("terrain", {}).get("data", "")).sha256_text(),
		JSON.stringify(doc.get("boxes", [])).sha256_text(), JSON.stringify(doc.get("props", [])).sha256_text(),
		",".join(open_gates), str(extra_solids),
		NAV_OVERHEAD, str(NAV_OVERHEAD_BY_MAP), SLAB_THICK, SLAB_TOP_CUT,
		float(doc.get("nav", {}).get("spacing", 1.0)), float(doc.get("nav", {}).get("clearance", 0.35)), NAV_COVER_RANGE,
	])
