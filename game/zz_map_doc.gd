extends RefCounted

const ZzMaterials := preload("zz_materials.gd")
const ZzFixtures := preload("zz_fixtures.gd")

## What a map IS: a JSON document, checked here before anything is built.
##
## [b]A map is a document, not a scene[/b], for mg-wipeout's reason, which every map-driven game
## in this family has taken since: a scene per map is content to import, to rebase inside a
## mounted pack and to keep in step across a server and every client; a document is a few tens
## of kilobytes the server reads off disk and SENDS to each client when the map changes. A
## client needs no map files, a server gets a new map by having a file dropped in a directory,
## and the two ends cannot disagree about where a wall or a chair is, because there is one copy
## and it travelled.
##
## [b]What is in one:[/b] boxes (the streets, the buildings, the barricades), props (cars, crates,
## furniture, by catalogue id), lights, where the survivors start, and how the sky looks. Then
## what makes it a zombie map rather than a room:
##
## [codeblock]
## mode          "exodus" (get from the start shelter to the end one) or "survival" (hold out)
## survivors     the team the map is built for; stand-ins fill to it (ZzConfig.team_from_map);
##               unsaid (0), the server's own number
## areas         {start: [area], end: [area]}: the safe rooms, each {min, max}
## route         the critical path the director spawns AHEAD along, start to end
## nav           {spacing, floors: [[x0, z0, x1, z1, y]], links: [[from xyz, to xyz]]}
## terrain       a converted map's displacement ground (dot-map's DotMapTerrain), with the walk mask
## items         weapons, ammo, medkits, pills and boxes lying where a mapper left them
## mechanics     true when the document's boxes leave out the world's movers, so a global pack's lifts and doors run
## traders       shelves of priced stock: {at, yaw?, pool?, slots?, spacing?, restock?}, the stock from the spawner config's pool
## spawners      weapon and supply spawners (dot-weapon docs/spawners.md): {at, pool?, tags_any?, respawn?, max?...}
## objectives    things to do on the way: press a button, hold out while the horde comes
## gates         a box with a "gate" id is a door an objective opens
## sleepers      where the crying one sits, waiting for somebody to come too close
## posts         survival: where a team holds; stand-ins spread over them
## caches        survival: where supplies are restocked in every breather, better each wave
## barricades    survival: [{id, label, health}]; a box with a "barricade" id is part of one:
##               solid, but on the zombies' ground, so they come to it and break it down
## day_environment  survival by nights: the sky by day (the map's `environment` is its night)
## [/codeblock]
##
## Every length is metres, every angle degrees. A box's `at` is its CENTRE; a prop's `at` is the
## middle of its footprint ON the floor, so a mapper places a car by where it stands.
##
## [b]Normalised into plain arrays, never vectors.[/b] What a server encodes is what this
## returned, and a vector's float32 components come back out of JSON as `0.300000011920929`:
## twice the bytes for a map of a thousand boxes and a document whose digest moves when nothing
## did. Rounded to the millimetre here, once.
##
## `maps/README.md` in zombie-zone-maps is the mapper's copy of this.


## The format this build reads. A document written for a later one is refused rather than
## half-built.
const FORMAT := 1

## The largest side of a box that counts as trim (see [method is_trim]).
const TRIM_SIZE := 0.3

const KIND := "zombiezone_map"
## The words a hidden box's `kind` may take.
const HIDDEN_KINDS: PackedStringArray = ["clip", "nodraw", "sky"]

## The largest a document may be on the wire, compressed. A WebSocket's outbound buffer is
## sixty-four kilobytes and a message past it is never sent (mg-look-at-me's finding), so a map
## must fit with room for the header.
const WIRE_LIMIT := 60000
## Kept free under the limit so a small edit to a map does not tip it over.
const WIRE_HEADROOM := 500

## A map's drawn world is the pack `zz_world_<id>` (zombie-zone-maps' tools/build_worlds.py).
const WORLD_PREFIX := "zz_world_"

const MAX_BOXES := 6000
const MAX_PROPS := 2000
const MAX_TOYS := 96
## Every lamp of the source is kept (the bake uses all of them); the game lights only the nearest few
## at once ([constant ZzMap.REALTIME_LAMPS]), so this bounds the document, not the frame.
const MAX_LIGHTS := 1024

const MAX_WATER := 24
const MAX_SOLID_PROPS := 600
const MAX_SPAWNS := 64
const MAX_ITEMS := 400
const MAX_OBJECTIVES := 16
const MAX_ROUTE := 256
const MAX_NAV_FLOORS := 800
const MAX_NAV_LINKS := 600
const MAX_SLEEPERS := 16
const MAX_AREAS := 8

## The two ways a map is played. Exodus was called "campaign" until the first play test asked
## for a name of its own; a document that still says "campaign" is read as exodus.
const EXODUS := "exodus"
const SURVIVAL := "survival"
const LEGACY_CAMPAIGN := "campaign"

const MAX_TEAM := 64
const MAX_POSTS := 64
const MAX_CACHES := 32
const MAX_BARRICADES := 96

## What a mapper may leave lying about. `box` is one of the random boxes (by `id`, or any).
const ITEM_KINDS: Array[String] = ["weapon", "ammo", "medkit", "pills", "box", "throwable", "defib"]

## What an objective asks: `use` a thing (hold E on it for `seconds`), then optionally hold out
## for `holdout` seconds while the horde comes; or `reach` a place.
const OBJECTIVE_KINDS: Array[String] = ["use", "reach"]

## Every top-level field, and what a missing one becomes.
const DEFAULT_ENV := {
	"sky_top": [0.32, 0.52, 0.82],
	"sky_horizon": [0.72, 0.82, 0.92],
	"ground": [0.35, 0.33, 0.30],
	"sun_pitch": -55.0,
	"sun_yaw": 30.0,
	"sun_energy": 1.1,
	"sun_colour": [1.0, 0.96, 0.88],
	"ambient": [0.62, 0.66, 0.72],
	"ambient_energy": 0.55,
	"fog": 0.0,
}


## What the converter writes when the source map says nothing of its light.
const IMPORTER_ENV := {
	"sky_top": [0.02, 0.03, 0.07], "sky_horizon": [0.08, 0.1, 0.15], "ground": [0.03, 0.03, 0.04],
	"sun_pitch": -45.0, "sun_yaw": 12.0, "sun_energy": 0.22, "sun_colour": [0.45, 0.65, 0.95],
	"ambient": [0.36, 0.4, 0.52], "ambient_energy": 0.3, "fog": 0.02,
}

## Sky names that are dark by name (dot-map's build_environment reads the same words).
const NIGHT_SKY_WORDS := ["night", "dark", "black", "space", "star"]


## True when [param env] is the converter's placeholder, so the drawn world's own entities decide.
static func is_importer_env(env: Dictionary) -> bool:
	for key: String in IMPORTER_ENV:
		if not env.has(key) or str(env[key]) != str(_floats(IMPORTER_ENV[key], 3) if IMPORTER_ENV[key] is Array else float(IMPORTER_ENV[key])):
			return false
	return true


## An `environment` block from a drawn world's own light_environment, env_fog_controller and sky
## name (dot-map's `environment_data()`); {} when it has no sun or sky to read.
static func environment_from_world(data: Dictionary) -> Dictionary:
	var sun: Dictionary = data.get("sun", {})
	if sun.is_empty() and not data.has("sky"):
		return {}
	var sky_name := str((data.get("sky", {}) as Dictionary).get("name", "")).to_lower()
	var night := false
	for word: String in NIGHT_SKY_WORDS:
		night = night or sky_name.contains(word)

	var env := (IMPORTER_ENV if night else DEFAULT_ENV).duplicate(true)
	var amb: Variant = sun.get("ambient")
	var col: Variant = sun.get("colour")
	var lum := 1.0
	if col is Array and (col as Array).size() >= 4:
		var peak := maxf(maxf(float(col[0]), float(col[1])), maxf(float(col[2]), 0.01))
		env["sun_colour"] = [float(col[0]) / peak, float(col[1]) / peak, float(col[2]) / peak]
		# Source's brightness 200 is a plain sun; the colour carries how much of it is light.
		lum = peak * float(col[3]) / 200.0
	if not sun.is_empty():
		env["sun_pitch"] = clampf(float(sun.get("pitch", -45.0)), -85.0, -5.0)
		env["sun_yaw"] = float(sun.get("yaw", 0.0)) - 90.0
	if night:
		env["sun_energy"] = clampf(sqrt(lum) * 0.35, 0.1, 0.3)
	else:
		env["sun_energy"] = clampf(sqrt(lum) * 0.9, 0.4, 1.1)
	if amb is Array and (amb as Array).size() >= 4:
		env["ambient"] = [float(amb[0]), float(amb[1]), float(amb[2])]
		if not night:
			env["ambient_energy"] = clampf(0.35 * sqrt(float(amb[3]) / 100.0), 0.22, 0.45)

	var fogged := false
	for f: Dictionary in data.get("fog", []):
		if f.get("enabled", false):
			var fc: Array = f.get("colour", [0.5, 0.5, 0.5])
			env["sky_horizon"] = [float(fc[0]), float(fc[1]), float(fc[2])]
			env["fog"] = clampf(2.0 / maxf(float(f.get("end", 60.0)) - 14.0, 6.0), 0.01, 0.12)
			fogged = true
			break
	if not fogged and night:
		env["fog"] = 0.012
	elif not fogged:
		# A day map without fog is clear air: the family's haze from 14 m washed out views hundreds of metres long.
		var off: Dictionary = (data.get("fog", []) as Array)[0] if not (data.get("fog", []) as Array).is_empty() else {}
		env["fog"] = 0.0
		env["fog_start"] = maxf(float(off.get("start", 0.0)), 60.0)
		env["fog_end"] = maxf(float(off.get("end", 0.0)), 600.0)
	return env


## Puts [param derived] (from [method environment_from_world]) into [param doc]. A hold fades between
## the placeholder night and a day, so a derived day becomes its `day_environment` and the night stays;
## a derived night, or any other mode, replaces the `environment`.
static func take_derived_light(doc: Dictionary, derived: Dictionary) -> void:
	var dark := float(derived["sun_energy"]) < 0.4  # the night branch clamps to 0.1..0.3, the day to 0.4..1.1
	if str(doc.get("mode", "")) == SURVIVAL and not doc.has("day_environment") and not dark:
		doc["day_environment"] = derived
	else:
		doc["environment"] = derived


## Reads a document from JSON text, and checks it.
static func parse_json(text: String, origin: String = "") -> DotResult:
	var json := JSON.new()

	if json.parse(text) != OK:
		return DotResult.fail(
			DotError.CODE_PARSE, "The map is not JSON.",
			"%s line %d: %s" % [origin, json.get_error_line(), json.get_error_message()]
		)

	if typeof(json.data) != TYPE_DICTIONARY:
		return DotResult.fail(DotError.CODE_PARSE, "The map is not a JSON object.", origin)

	return validate(json.data as Dictionary)


## Checks a document and returns a normalised copy of it: every optional field present, every
## position three numbers.
static func validate(source: Dictionary) -> DotResult:
	if int(source.get("format", 0)) != FORMAT:
		return _refuse("format is %s; this build reads %d" % [str(source.get("format")), FORMAT], source)

	if str(source.get("kind", "")) != KIND:
		return _refuse("kind is '%s', not '%s'" % [str(source.get("kind", "")), KIND], source)

	var id := str(source.get("id", ""))

	if not _is_id(id):
		return _refuse("id '%s' is not lower-case letters, digits and underscores" % id, source)

	var doc := {
		"format": FORMAT,
		"kind": KIND,
		"id": id,
		"name": str(source.get("name", id)),
		"author": str(source.get("author", "")),
		"blurb": str(source.get("blurb", "")),
		"kill_y": float(source.get("kill_y", -30.0)),
		"next": str(source.get("next", "")),
		"survive_seconds": maxf(float(source.get("survive_seconds", 0.0)), 0.0),
	}

	# The creepy-ambience this map wants (ZzAudio): a mood name, or {mood, indoor, extra, volume, frequency}. A name the sound set may not have is ignored there.
	var ambient: Variant = _ambient(source.get("ambient", ""))
	if not (ambient is String and (ambient as String) == ""):
		doc["ambient"] = ambient

	# The map's own drawn geometry, a pack of its own (ZzMap.load_world); without it the boxes are
	# drawn. Only a name the converter makes, so a document cannot point a client at any pack.
	var world := str(source.get("world", ""))
	if world != "":
		if not world.begins_with(WORLD_PREFIX) or not _is_id(world):
			return _refuse("world '%s' is not %s<id>" % [world, WORLD_PREFIX], source)
		doc["world"] = world
		# What the server resolved it to (`<owner>/<pack>@<version>`), sent in MAP: the same pack
		# name, so a key from the wire can only name this map's world.
		var key := str(source.get("world_key", ""))
		if key != "" and _world_key_ok(key, world):
			doc["world_key"] = key
		# Which of the world's hulls collide where the boxes' budget dropped brushes (ZzMap.attach_world_collision).
		var wc: Variant = source.get("world_collision", {})
		if wc is Dictionary and not (wc as Dictionary).is_empty():
			doc["world_collision"] = {"models": _ints(wc.get("models", [])), "flat": _ints(wc.get("flat", [])),
					"flat_height": float(wc.get("flat_height", 0.5)), "skip": _boxes(wc.get("skip", []))}
			for crop_key: String in ["within", "band"]:
				if wc.has(crop_key) and wc[crop_key] is Array:
					doc["world_collision"][crop_key] = (wc[crop_key] as Array).map(func(v: Variant) -> float: return float(v))

	var mode := str(source.get("mode", EXODUS))

	if mode == LEGACY_CAMPAIGN:
		mode = EXODUS

	if mode != EXODUS and mode != SURVIVAL:
		return _refuse("mode is '%s'; it is exodus or survival" % mode, source)

	doc["mode"] = mode
	# 0: the map does not say, and the server's own number stands.
	doc["survivors"] = clampi(int(source.get("survivors", 0)), 0, MAX_TEAM)

	var env := DEFAULT_ENV.duplicate(true)
	var given: Variant = source.get("environment", {})

	if given is Dictionary:
		for key: String in DEFAULT_ENV:
			if (given as Dictionary).has(key):
				var value: Variant = (given as Dictionary)[key]
				env[key] = _floats(value, 3) if DEFAULT_ENV[key] is Array else float(value)

	doc["environment"] = env

	# The day of a map held by nights: the same fields, over the map's own night.
	var day: Variant = source.get("day_environment", null)

	if day is Dictionary:
		var day_env := DEFAULT_ENV.duplicate(true)
		for key: String in DEFAULT_ENV:
			if (day as Dictionary).has(key):
				var value: Variant = (day as Dictionary)[key]
				day_env[key] = _floats(value, 3) if DEFAULT_ENV[key] is Array else float(value)
		doc["day_environment"] = day_env

	var boxes: Array = []
	for raw: Variant in source.get("boxes", []):
		var box := _box(raw)
		if box.is_empty():
			return _refuse("box %d is not {at, size, mat}" % boxes.size(), source)
		boxes.append(box)

	if boxes.size() > MAX_BOXES:
		return _refuse("%d boxes; the most is %d" % [boxes.size(), MAX_BOXES], source)

	doc["boxes"] = boxes

	var props: Array = []
	for raw: Variant in source.get("props", []):
		var prop := _prop(raw)
		if prop.is_empty():
			return _refuse("prop %d is not {id, at}" % props.size(), source)
		props.append(prop)

	if props.size() > MAX_PROPS:
		return _refuse("%d props; the most is %d" % [props.size(), MAX_PROPS], source)

	doc["props"] = props

	# Toys: dot-props' DotPropToyBox placements, `{toy, at, yaw}`. Which ids exist is the
	# catalogue's to say when the map is built (an unknown one is left out and listed), so a map
	# with a toy a newer dot-props has still plays on an older server.
	var toys: Array = []
	for raw: Variant in source.get("toys", []):
		var toy := DotPropToyBox.normal_placement(raw)
		if toy.is_empty():
			return _refuse("toy %d is not {toy, at}" % toys.size(), source)
		toys.append(toy)

	if toys.size() > MAX_TOYS:
		return _refuse("%d toys; the most is %d" % [toys.size(), MAX_TOYS], source)

	doc["toys"] = toys

	var lights: Array = []
	for raw: Variant in source.get("lights", []):
		if not (raw is Dictionary) or not (raw as Dictionary).has("at"):
			return _refuse("light %d has no 'at'" % lights.size(), source)
		var light := raw as Dictionary
		var lamp := {
			"at": _floats(light["at"], 3),
			"range": clampf(float(light.get("range", 8.0)), 0.5, 80.0),
			"energy": clampf(float(light.get("energy", 1.0)), 0.0, 16.0),
			"colour": _floats(light.get("colour", [1.0, 0.95, 0.85]), 3),
		}

		# A spot: `dir` (where it points) and `cone` (half angle, degrees). Left out of an omni.
		if light.has("dir") and light.has("cone"):
			lamp["dir"] = _floats(light["dir"], 3)
			lamp["cone"] = clampf(float(light["cone"]), 5.0, 90.0)

		lights.append(lamp)

	if lights.size() > MAX_LIGHTS:
		return _refuse("%d lights; the most is %d" % [lights.size(), MAX_LIGHTS], source)

	doc["lights"] = lights

	# `wire_lamps`: how many lamps go over the wire (the importer writes it for a map of hundreds, its
	# lamps farthest-point first so the first few cover the map). The wire form adds the other two keys.
	if int(source.get("wire_lamps", 0)) > 0:
		doc["wire_lamps"] = int(source["wire_lamps"])

	if int(source.get("lights_total", 0)) > lights.size() and str(source.get("lights_digest", "")) != "":
		doc["lights_total"] = int(source["lights_total"])
		doc["lights_digest"] = str(source["lights_digest"])

	# Water: axis-aligned volumes, `{at, size, tint?}` like a box (its top is the surface). Left
	# out of a map that has none, so a map without water keeps the document it always had.
	var water: Array = []
	for raw: Variant in source.get("water", []):
		if not (raw is Dictionary) or not (raw as Dictionary).has("at") or not (raw as Dictionary).has("size"):
			return _refuse("water %d is not {at, size}" % water.size(), source)
		var pool := raw as Dictionary
		var pool_size := _floats(pool["size"], 3)
		if pool_size[0] <= 0.0 or pool_size[1] <= 0.0 or pool_size[2] <= 0.0:
			return _refuse("water %d has no volume" % water.size(), source)
		var entry := {"at": _floats(pool["at"], 3), "size": pool_size}
		if pool.has("tint"):
			entry["tint"] = _floats(_colour_list(pool["tint"]), 3)
		water.append(entry)

	if water.size() > MAX_WATER:
		return _refuse("%d water volumes; the most is %d" % [water.size(), MAX_WATER], source)

	if not water.is_empty():
		doc["water"] = water

	# Solid props of a drawn world: `[x, y, z, sx, sy, sz, yaw]` (box centre, size, degrees about Y),
	# boxes only, so a server with no world pack collides exactly where a client does. Left out of
	# a map that has none.
	var solid_props: Array = []
	for raw: Variant in source.get("solid_props", []):
		if not (raw is Array) or (raw as Array).size() != 7:
			return _refuse("solid prop %d is not [x, y, z, sx, sy, sz, yaw]" % solid_props.size(), source)
		var rec := _floats(raw, 7)
		if rec[3] <= 0.0 or rec[4] <= 0.0 or rec[5] <= 0.0:
			return _refuse("solid prop %d has no volume" % solid_props.size(), source)
		solid_props.append(rec)

	if solid_props.size() > MAX_SOLID_PROPS:
		return _refuse("%d solid props; the most is %d" % [solid_props.size(), MAX_SOLID_PROPS], source)

	if not solid_props.is_empty():
		doc["solid_props"] = solid_props

	var spawns: Variant = source.get("spawns", {})
	if not (spawns is Dictionary):
		return _refuse("'spawns' is not {survivors}", source)

	var out_spawns := {}
	var list: Array = []

	for raw: Variant in (spawns as Dictionary).get("survivors", []):
		if not (raw is Dictionary) or not (raw as Dictionary).has("at"):
			return _refuse("a survivor spawn has no 'at'", source)
		var entry := {"at": _floats((raw as Dictionary)["at"], 3), "yaw": _r(float((raw as Dictionary).get("yaw", 0.0)))}
		# The map's own start-point entity: a name an input can re-enable, and whether it begins disabled.
		var spawn_name := str((raw as Dictionary).get("name", "")).strip_edges().left(64)
		if spawn_name != "":
			entry["name"] = spawn_name
		if bool((raw as Dictionary).get("disabled", false)):
			entry["disabled"] = true
		list.append(entry)

	if list.is_empty():
		return _refuse("no spawns for the survivors", source)
	if list.size() > MAX_SPAWNS:
		return _refuse("%d survivor spawns; the most is %d" % [list.size(), MAX_SPAWNS], source)

	out_spawns["survivors"] = list
	doc["spawns"] = out_spawns

	# --- The safe areas --------------------------------------------------------
	var areas := {"start": [], "end": []}
	var given_areas: Variant = source.get("areas", {})

	if given_areas is Dictionary:
		for side in ["start", "end"]:
			for raw: Variant in (given_areas as Dictionary).get(side, []):
				var area := _area(raw)
				if area.is_empty():
					return _refuse("a %s area is not {min, max}" % side, source)
				(areas[side] as Array).append(area)
			if (areas[side] as Array).size() > MAX_AREAS:
				return _refuse("%d %s areas; the most is %d" % [(areas[side] as Array).size(), side, MAX_AREAS], source)

	if mode == EXODUS and (areas["end"] as Array).is_empty():
		return _refuse("an exodus map needs an end shelter to reach", source)

	doc["areas"] = areas

	# --- The route -------------------------------------------------------------
	var route: Array = []
	for raw: Variant in source.get("route", []):
		route.append(_floats(raw, 3))
	if route.size() > MAX_ROUTE:
		return _refuse("%d route points; the most is %d" % [route.size(), MAX_ROUTE], source)
	doc["route"] = route

	# --- Navigation ------------------------------------------------------------
	var nav_in: Variant = source.get("nav", {})
	var nav := {"spacing": 1.0, "clearance": 0.35, "floors": [], "links": []}

	if nav_in is Dictionary:
		nav["spacing"] = clampf(float((nav_in as Dictionary).get("spacing", 1.0)), 0.5, 4.0)
		nav["clearance"] = clampf(float((nav_in as Dictionary).get("clearance", 0.35)), 0.1, 1.5)
		for raw: Variant in (nav_in as Dictionary).get("floors", []):
			var f := _floats(raw, 5)
			if f[2] <= f[0] or f[3] <= f[1]:
				return _refuse("a nav floor %s is not [x0, z0, x1, z1, y] with x1 > x0 and z1 > z0" % str(raw), source)
			(nav["floors"] as Array).append(f)
		for raw: Variant in (nav_in as Dictionary).get("links", []):
			(nav["links"] as Array).append(_floats(raw, 6))

	if (nav["floors"] as Array).size() > MAX_NAV_FLOORS or (nav["links"] as Array).size() > MAX_NAV_LINKS:
		return _refuse("too many nav floors or links", source)

	var walked := 0
	if source.has("terrain"):
		if not (source["terrain"] is Dictionary):
			return _refuse("terrain is not a dictionary", source)
		var ground := DotMapTerrain.from_dict(source["terrain"])
		if not ground.ok:
			return _refuse("terrain: %s" % str(ground), source)
		walked = (ground.value as DotMapTerrain).describe()["walk"]
		doc["terrain"] = source["terrain"]

	if (nav["floors"] as Array).is_empty() and walked == 0:
		return _refuse("no nav floors: the zombies would have nowhere to walk", source)

	doc["nav"] = nav

	# --- Items -----------------------------------------------------------------
	var items: Array = []
	for raw: Variant in source.get("items", []):
		if not (raw is Dictionary) or not (raw as Dictionary).has("at"):
			return _refuse("item %d has no 'at'" % items.size(), source)
		var item := raw as Dictionary
		var kind := str(item.get("kind", ""))
		if not ITEM_KINDS.has(kind):
			return _refuse("item %d is a '%s'; it is one of %s" % [items.size(), kind, ", ".join(ITEM_KINDS)], source)
		var out_item := {"kind": kind, "at": _floats(item["at"], 3)}
		if item.has("id"):
			out_item["id"] = str(item["id"])
		if item.has("count"):
			out_item["count"] = clampi(int(item["count"]), 1, 99)
		items.append(out_item)
	if items.size() > MAX_ITEMS:
		return _refuse("%d items; the most is %d" % [items.size(), MAX_ITEMS], source)
	doc["items"] = items

	var spawners: Array = []
	for raw: Variant in source.get("spawners", []):
		if not (raw is Dictionary) or not (raw as Dictionary).has("at"):
			return _refuse("spawner %d has no 'at'" % spawners.size(), source)
		var sp: Dictionary = _as_floats((raw as Dictionary).duplicate(true))
		sp["at"] = _floats(sp["at"], 3)
		spawners.append(sp)
	if spawners.size() > MAX_ITEMS:
		return _refuse("%d spawners; the most is %d" % [spawners.size(), MAX_ITEMS], source)
	doc["spawners"] = spawners

	var traders: Array = []
	for raw: Variant in source.get("traders", []):
		if not (raw is Dictionary) or not (raw as Dictionary).has("at"):
			return _refuse("trader %d has no 'at'" % traders.size(), source)
		var tr: Dictionary = _as_floats((raw as Dictionary).duplicate(true))
		tr["at"] = _floats(tr["at"], 3)
		traders.append(tr)
	if traders.size() > MAX_ITEMS:
		return _refuse("%d traders; the most is %d" % [traders.size(), MAX_ITEMS], source)
	doc["traders"] = traders
	doc["mechanics"] = bool(source.get("mechanics", false))

	# --- Objectives ------------------------------------------------------------
	var objectives: Array = []
	for raw: Variant in source.get("objectives", []):
		if not (raw is Dictionary) or not (raw as Dictionary).has("at"):
			return _refuse("objective %d has no 'at'" % objectives.size(), source)
		var o := raw as Dictionary
		var kind := str(o.get("kind", "use"))
		if not OBJECTIVE_KINDS.has(kind):
			return _refuse("objective %d is a '%s'; it is use or reach" % [objectives.size(), kind], source)
		var opens := PackedStringArray()
		for gate: Variant in o.get("opens", []):
			opens.append(str(gate))
		objectives.append({
			"id": str(o.get("id", "objective_%d" % objectives.size())),
			"kind": kind,
			"at": _floats(o["at"], 3),
			"label": str(o.get("label", "Use")),
			"seconds": clampf(float(o.get("seconds", 2.0)), 0.0, 60.0),
			"radius": clampf(float(o.get("radius", 2.0)), 0.5, 30.0),
			"holdout": clampf(float(o.get("holdout", 0.0)), 0.0, 900.0),
			"panic": bool(o.get("panic", float(o.get("holdout", 0.0)) > 0.0)),
			"opens": opens,
			"message": str(o.get("message", "")),
		})
		# What it is, drawn: "padlock" (on the gate it opens), "lever", "radio". Unsaid or
		# unknown draws nothing.
		if ZzFixtures.PROPS.has(str(o.get("prop", ""))):
			(objectives.back() as Dictionary)["prop"] = str(o["prop"])
			(objectives.back() as Dictionary)["yaw"] = _r(float(o.get("yaw", 0.0)))
	if objectives.size() > MAX_OBJECTIVES:
		return _refuse("%d objectives; the most is %d" % [objectives.size(), MAX_OBJECTIVES], source)
	doc["objectives"] = objectives

	# --- Sleepers ----------------------------------------------------------------
	var sleepers: Array = []
	for raw: Variant in source.get("sleepers", []):
		sleepers.append(_floats(raw, 4))
	if sleepers.size() > MAX_SLEEPERS:
		return _refuse("%d sleepers; the most is %d" % [sleepers.size(), MAX_SLEEPERS], source)
	doc["sleepers"] = sleepers

	# --- Zombie spawn hints ------------------------------------------------------
	var hints: Array = []
	for raw: Variant in source.get("zombie_spawns", []):
		hints.append(_floats(raw, 3))
	doc["zombie_spawns"] = hints

	# --- Holding a survival map ----------------------------------------------------
	var posts: Array = []
	for raw: Variant in source.get("posts", []):
		posts.append(_floats(raw, 3))
	var caches: Array = []
	for raw: Variant in source.get("caches", []):
		caches.append(_floats(raw, 3))
	if posts.size() > MAX_POSTS or caches.size() > MAX_CACHES:
		return _refuse("%d posts and %d caches; the most is %d and %d" % [posts.size(), caches.size(), MAX_POSTS, MAX_CACHES], source)
	doc["posts"] = posts
	doc["caches"] = caches

	var barricades: Array = []
	var named := {}
	for raw: Variant in source.get("barricades", []):
		if not (raw is Dictionary) or not _is_id(str((raw as Dictionary).get("id", ""))):
			return _refuse("barricade %d has no id" % barricades.size(), source)
		var b := raw as Dictionary
		var entry := {"id": str(b["id"]), "label": str(b.get("label", "a barricade"))}
		if b.has("health"):
			entry["health"] = clampf(float(b["health"]), 10.0, 100000.0)
		named[entry["id"]] = true
		barricades.append(entry)
	for box: Dictionary in boxes:
		if box.has("barricade") and not named.has(box["barricade"]):
			named[box["barricade"]] = true
			barricades.append({"id": box["barricade"], "label": "a barricade"})
	if barricades.size() > MAX_BARRICADES:
		return _refuse("%d barricades; the most is %d" % [barricades.size(), MAX_BARRICADES], source)
	doc["barricades"] = barricades

	return DotResult.success(doc)


static func _box(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}

	var b := raw as Dictionary

	if not b.has("at") or not b.has("size"):
		return {}

	var size := _floats(b["size"], 3)

	if size[0] <= 0.0 or size[1] <= 0.0 or size[2] <= 0.0:
		return {}

	var mat := str(b.get("mat", "flat"))

	if not ZzMaterials.has(mat):
		mat = "flat"

	var out := {"at": _floats(b["at"], 3), "size": size, "mat": mat}

	if float(b.get("yaw", 0.0)) != 0.0:
		out["yaw"] = _r(float(b["yaw"]))

	if b.has("tint"):
		out["tint"] = _floats(_colour_list(b["tint"]), 3)

	# A map's own word for what this box is made of ("brick", "asphalt"; dot-map's surface kinds
	# and aliases), over the kind its `mat` would pick. Left alone here: an unknown word draws the
	# mat's usual look, so the document is never refused for a texture name.
	if b.has("surface") and str(b["surface"]) != "":
		out["surface"] = str(b["surface"])

	# Solid unless the map says not: water, a light's glow, a line painted on a floor.
	if b.has("solid") and not bool(b["solid"]):
		out["solid"] = false

	# Drawn unless the map says not: an invisible wall that keeps people in the map.
	if b.has("visible") and not bool(b["visible"]):
		out["visible"] = false

	# What an invisible box is (`clip`, `nodraw`, `sky`); older documents say nothing.
	if b.has("kind") and HIDDEN_KINDS.has(str(b["kind"])):
		out["kind"] = str(b["kind"])

	# A door an objective opens: removed, collision and all, when it does.
	if b.has("gate"):
		out["gate"] = str(b["gate"])

	# How it is drawn, when not as a box: "chain_link" (a see-through fence). An unknown look
	# is dropped, so a newer map's look on this game is a box rather than a refused map.
	if b.has("look") and ZzFixtures.LOOKS.has(str(b["look"])):
		out["look"] = str(b["look"])

	# Part of a barricade: solid while it stands, gone while it is broken, and never cut out of
	# the zombies' ground, because the horde is meant to come to it.
	if b.has("barricade") and _is_id(str(b["barricade"])) and not b.has("gate"):
		out["barricade"] = str(b["barricade"])

	# Whether the zombies treat it as something in the way. A floor, a kerb or a roof is not;
	# unsaid, anything taller than a step is.
	if b.has("nav"):
		out["nav"] = bool(b["nav"])

	return out


## Door hardware and such: a box no side of which is over 0.3 m. Neither body nor nav sees it, since a
## 0.1 m latch on a jamb wedged zombies in a doorway for minutes (ze_nuke_beta) and a mover cannot use it.
static func is_trim(box: Dictionary) -> bool:
	if box.has("gate") or box.has("barricade") or not box.has("size"):
		return false

	var size := v3(box["size"])
	return maxf(size.x, maxf(size.y, size.z)) <= TRIM_SIZE


## An axis-aligned area, `{min, max}`, normalised so min is the lesser corner.
static func _area(raw: Variant) -> Dictionary:
	if not (raw is Dictionary) or not (raw as Dictionary).has("min") or not (raw as Dictionary).has("max"):
		return {}

	var a := _floats((raw as Dictionary)["min"], 3)
	var b := _floats((raw as Dictionary)["max"], 3)
	var lo := [minf(a[0], b[0]), minf(a[1], b[1]), minf(a[2], b[2])]
	var hi := [maxf(a[0], b[0]), maxf(a[1], b[1]), maxf(a[2], b[2])]

	if hi[0] - lo[0] < 0.5 or hi[2] - lo[2] < 0.5:
		return {}

	return {"min": lo, "max": hi}


## An area as an [AABB].
static func area_box(area: Dictionary) -> AABB:
	var lo := v3(area.get("min", [0, 0, 0]))
	return AABB(lo, v3(area.get("max", [0, 0, 0])) - lo)


static func _prop(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}

	var p := raw as Dictionary

	if not p.has("id") or not p.has("at"):
		return {}

	var out := {"id": str(p["id"]), "at": _floats(p["at"], 3)}

	for angle in ["yaw", "pitch", "roll"]:
		if float(p.get(angle, 0.0)) != 0.0:
			out[angle] = _r(float(p[angle]))

	return out


## The document as the wire carries it: a map with `wire_lamps` sends only that many of its lamps, the total
## and a digest of all. Applying it twice changes nothing, so both ends digest the same text.
static func wire_form(doc: Dictionary) -> Dictionary:
	var all: Array = doc.get("lights", [])
	var keep := int(doc.get("wire_lamps", 0))

	if keep <= 0 or all.size() <= keep:
		return doc

	var out := doc.duplicate()
	out["lights_total"] = all.size()
	out["lights_digest"] = JSON.stringify(all, "", true).sha256_text().substr(0, 16)

	# Lamps are the one part of a document that can shrink: a map that fits a browser's message only
	# by a few hundred bytes is one a longer name or an extra lamp pushes over, and then no web client gets it.
	out["lights"] = all.slice(0, keep)

	while keep > 0 and _deflated_size(out) > WIRE_LIMIT - WIRE_HEADROOM:
		keep /= 2
		out["lights"] = all.slice(0, keep)

	return out


static func _deflated_size(doc: Dictionary) -> int:
	return JSON.stringify(doc, "", false).to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE).size()


## What a bake of the lamps is checked against: the lamps themselves, or for a map with `wire_lamps` a digest
## of all of them (a client holds only the first few, and has the digest it was sent).
static func lamps_key(doc: Dictionary) -> Variant:
	if doc.has("lights_digest"):
		return doc["lights_digest"]

	var wired := wire_form(doc)
	return wired["lights_digest"] if wired.has("lights_digest") else doc.get("lights", [])


## A normalised document as bytes: JSON, deflated, behind both its lengths.
static func encode(doc: Dictionary) -> PackedByteArray:
	var raw := JSON.stringify(wire_form(doc), "", false).to_utf8_buffer()
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)

	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, raw.size())
	out.encode_u32(4, packed.size())
	out.append_array(packed)
	return out


static func decode(bytes: PackedByteArray) -> DotResult:
	if bytes.size() < 9:
		return DotResult.fail(DotError.CODE_PARSE, "A map on the wire was empty.")

	var size := bytes.decode_u32(0)

	if bytes.decode_u32(4) != bytes.size() - 8:
		return DotResult.fail(DotError.CODE_PARSE, "A map on the wire is not the length it says.")

	# A size this large is a corrupt header; decompressing it would allocate whatever it says.
	if size <= 0 or size > WIRE_LIMIT * 40:
		return DotResult.fail(DotError.CODE_PARSE, "A map on the wire says it is %d bytes." % size)

	var raw := bytes.slice(8).decompress(size, FileAccess.COMPRESSION_DEFLATE)

	if raw.size() != size:
		return DotResult.fail(DotError.CODE_PARSE, "A map on the wire would not decompress.")

	return parse_json(raw.get_string_from_utf8(), "wire")


## A short fingerprint of a document, for a log line and for two ends to compare.
static func digest(doc: Dictionary) -> String:
	return JSON.stringify(wire_form(doc), "", true).sha256_text().substr(0, 12)


# --- Small readers ----------------------------------------------------------

## Every number in [param value] as a float, as JSON reads it back, so the document's digest survives the wire.
static func _as_floats(value: Variant) -> Variant:
	if value is int:
		return float(value)
	if value is Dictionary:
		var out := {}
		for k: Variant in value:
			out[k] = _as_floats(value[k])
		return out
	if value is Array:
		var list := []
		for v: Variant in value:
			list.append(_as_floats(v))
		return list
	return value


static func v3(value: Variant) -> Vector3:
	if value is Vector3:
		return value

	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))

	return Vector3.ZERO


static func colour(value: Variant, fallback: Color = Color.WHITE) -> Color:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 3:
		return Color(float(value[0]), float(value[1]), float(value[2]))

	return fallback


static func _floats(value: Variant, count: int) -> Array:
	var out: Array = []

	if value is Vector3:
		value = [value.x, value.y, value.z]

	if typeof(value) == TYPE_ARRAY:
		for i in range(count):
			out.append(_r(float((value as Array)[i]) if i < (value as Array).size() else 0.0))
	else:
		for i in range(count):
			out.append(0.0)

	return out


static func _colour_list(value: Variant) -> Array:
	if typeof(value) == TYPE_STRING and Color.html_is_valid(str(value)):
		var c := Color.html(str(value))
		return [c.r, c.g, c.b]

	return value if typeof(value) == TYPE_ARRAY else [1.0, 1.0, 1.0]


## Millimetres, as a double JSON prints short.
static func _r(value: float) -> float:
	return snappedf(value, 0.001)


## The numbers of a list as ints; anything else in it is dropped.
static func _ints(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for v: Variant in value:
			if v is int or v is float:
				out.append(int(v))
	return out


## The six-number boxes (`[x0, y0, z0, x1, y1, z1]`) of a list; a malformed one is dropped.
static func _boxes(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for v: Variant in value:
			var f: Variant = _as_floats(v)
			if f is Array and (f as Array).size() == 6:
				out.append(f)
	return out


## Whether [param key] is `<owner>/<world>@<version>` for exactly [param world].
static func _world_key_ok(key: String, world: String) -> bool:
	var slash := key.find("/")
	var at := key.rfind("@")
	if slash <= 0 or at <= slash or key.length() > 160:
		return false
	var owner := key.substr(0, slash)
	var version := key.substr(at + 1)
	if key.substr(slash + 1, at - slash - 1) != world or version.is_empty():
		return false
	for part: String in [owner, version]:
		for character in part:
			if not (character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.+"):
				return false
	return not owner.contains("..") and not version.contains("..")


## An `ambient` field in its safe form: a mood id, or a dictionary of ids and clamped scales; "" for nothing usable.
static func _ambient(raw: Variant) -> Variant:
	if raw is String:
		return raw if _is_id(raw) else ""
	if not (raw is Dictionary):
		return ""
	var src := raw as Dictionary
	var mood := str(src.get("mood", ""))
	if not _is_id(mood):
		return ""
	var out := {"mood": mood}
	for key: String in ["indoor", "extra"]:
		var id := str(src.get(key, ""))
		if id != "" and _is_id(id):
			out[key] = id
	if src.has("volume") and (src["volume"] is float or src["volume"] is int):
		out["volume"] = clampf(float(src["volume"]), 0.25, 2.0)
	if src.has("frequency") and (src["frequency"] is float or src["frequency"] is int):
		out["frequency"] = clampf(float(src["frequency"]), 0.0, 4.0)
	return mood if out.size() == 1 else out


static func _is_id(id: String) -> bool:
	if id.is_empty() or id.length() > 48:
		return false

	for character in id:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") \
				and character != "_":
			return false

	return true


static func _refuse(why: String, doc: Dictionary) -> DotResult:
	return DotResult.fail(
		DotError.CODE_INVALID, "The map is refused: %s." % why, str(doc.get("id", "?"))
	)
