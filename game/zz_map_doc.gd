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
## items         weapons, ammo, medkits, pills and boxes lying where a mapper left them
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

const KIND := "zombiezone_map"

## The largest a document may be on the wire, compressed. A WebSocket's outbound buffer is
## sixty-four kilobytes and a message past it is never sent (mg-look-at-me's finding), so a map
## must fit with room for the header.
const WIRE_LIMIT := 60000

const MAX_BOXES := 6000
const MAX_PROPS := 2000
const MAX_TOYS := 96
const MAX_LIGHTS := 128
const MAX_WATER := 24
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
const ITEM_KINDS: Array[String] = ["weapon", "ammo", "medkit", "pills", "box", "throwable"]

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
		lights.append({
			"at": _floats(light["at"], 3),
			"range": clampf(float(light.get("range", 8.0)), 0.5, 80.0),
			"energy": clampf(float(light.get("energy", 1.0)), 0.0, 16.0),
			"colour": _floats(light.get("colour", [1.0, 0.95, 0.85]), 3),
		})

	if lights.size() > MAX_LIGHTS:
		return _refuse("%d lights; the most is %d" % [lights.size(), MAX_LIGHTS], source)

	doc["lights"] = lights

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

	var spawns: Variant = source.get("spawns", {})
	if not (spawns is Dictionary):
		return _refuse("'spawns' is not {survivors}", source)

	var out_spawns := {}
	var list: Array = []

	for raw: Variant in (spawns as Dictionary).get("survivors", []):
		if not (raw is Dictionary) or not (raw as Dictionary).has("at"):
			return _refuse("a survivor spawn has no 'at'", source)
		list.append({"at": _floats((raw as Dictionary)["at"], 3), "yaw": _r(float((raw as Dictionary).get("yaw", 0.0)))})

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

	if (nav["floors"] as Array).is_empty():
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


## A normalised document as bytes: JSON, deflated, behind both its lengths.
static func encode(doc: Dictionary) -> PackedByteArray:
	var raw := JSON.stringify(doc, "", false).to_utf8_buffer()
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
	return JSON.stringify(doc, "", true).sha256_text().substr(0, 12)


# --- Small readers ----------------------------------------------------------

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
