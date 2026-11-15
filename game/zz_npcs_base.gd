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

const NAV_CACHE_VERSION := 12

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

## The points of [param nav] that pass [param filter], thinned so no two are closer than [param spacing]:
## what `DotNpcDirector.set_spawn_points_from_nav` returns, the same points in the same order (the first
## of two close ones wins), but through a grid of cells one spacing wide. The director's own loop
## compares every point with every kept one, which was 0.6 s a round on a big map.
static func thinned_points(nav: DotNpcNavData, spacing: float, filter: DotNpcNavFilter) -> PackedVector3Array:
	var kept := PackedVector3Array()

	if nav == null or nav.points.is_empty():
		return kept

	var spacing_sq := spacing * spacing
	var size := maxf(spacing, 0.001)
	var cells: Dictionary = {}

	for i in nav.points.size():
		if filter != null and not filter.passes(nav.area_of(i), nav.flags_of(i)):
			continue

		var point := nav.points[i]
		var cx := floori(point.x / size)
		var cy := floori(point.y / size)
		var cz := floori(point.z / size)
		var too_close := false

		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var bucket: Variant = cells.get(Vector3i(cx + dx, cy + dy, cz + dz))

					if bucket == null:
						continue

					for other: Vector3 in bucket:
						if other.distance_squared_to(point) < spacing_sq:
							too_close = true
							break

					if too_close:
						break
				if too_close:
					break
			if too_close:
				break

		if too_close:
			continue

		kept.append(point)
		var key := Vector3i(cx, cy, cz)

		# A packed array is a value: it goes back into the dictionary after the append.
		var bucket_in: PackedVector3Array = cells.get(key, PackedVector3Array())
		bucket_in.append(point)
		cells[key] = bucket_in

	return kept
