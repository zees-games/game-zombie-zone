extends "zz_npcs_base.gd"

static func is_special(kind: StringName) -> bool:
	return kind != COMMON and kind != &""

## The built-in kinds (twelve) with their `npc` profiles laid over them; [param roots] replaces the config roots (tests).
static func catalogue(config: ZzConfig = null, roots: PackedStringArray = PackedStringArray()) -> GSNpcCatalogue:
	var c := config if config != null else ZzConfig.new()
	var out := GSNpcCatalogue.new()
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
			GSLog.warn(CHANNEL, "a zombie could not be catalogued", {
				"npc": String(def.id), "why": added.error.message
			})

	return out

## The common from code and [param c] alone, and the kinds an installed pack carries as `core` rows (the thirteen
## specials of zz-mutants), no profile; the floor the shipped ymls are written from.
static func builtin(c: ZzConfig) -> Array:
	var out: Array = [_eyes(_common(c))]

	for core in ZzPackList.cores:
		out.append(_eyes(_core_def(core, c)))

	return out

## The kinds the director chooses between (the `special` core rows): empty without the pack. Not the brute (its own
## clock) or the sleeper (placed by the map).
static func specials() -> Array[StringName]:
	var out: Array[StringName] = []

	for core in ZzPackList.cores:
		if core["role"] == "special":
			out.append(core["id"])

	return out

## A core kind's def, built from a pack's row, or null where no pack carries it. [param c] is a ZzConfig.
static func core_def(id: StringName, c: ZzConfig) -> GSNpcDef:
	for core in ZzPackList.cores:
		if core["id"] == id:
			return _eyes(_core_def(core, c))

	return null

## One core row as a def. Its health is a number (`fixed`), the special scale over one (`special`) or the brute's own
## rule (`brute`); a meta value `"cfg:<field>"` is that field of [param c].
static func _core_def(core: Dictionary, c: ZzConfig) -> GSNpcDef:
	var d: Dictionary = core["data"]
	var health := float(d.get("health", 200.0))
	var hp := str(d.get("hp", "special"))

	if hp == "special":
		health *= c.special_health_scale()
	elif hp == "brute":
		health = brute_health(c, 1)

	var weight: GSNpcDef.Weight = {"light": GSNpcDef.Weight.LIGHT, "heavy": GSNpcDef.Weight.HEAVY}.get(str(d.get("weight", "normal")), GSNpcDef.Weight.NORMAL)
	var def := _def(core["id"], str(d.get("name", core["id"])), core["brain"], health, float(d.get("speed", 4.4)), int(d.get("cost", 3)), weight)
	def.sight_range = float(d.get("sight", 40.0))
	def.sight_half_angle_deg = float(d.get("sight_angle", 90.0))
	def.hearing_range = float(d.get("hearing", 18.0))
	def.require_line_of_sight = bool(d.get("los", true))

	if bool(d.get("narrow", false)):
		def.nav_exclude_flags = ZzNavGraph.NARROW

	var meta: Dictionary = (d.get("meta", {}) as Dictionary).duplicate(true)

	for key: String in meta:
		var v: Variant = meta[key]

		if v is String and (v as String).begins_with("cfg:"):
			meta[key] = c.get((v as String).substr(4))

	def.meta = meta
	return def

## An installed pack's monsters (see zz_packs.gd), each the common's numbers with the pack's
## `spawn` on top. A special's health scale applies, as it does to every special.
static func _pack_defs(c: ZzConfig) -> Array:
	var out: Array = []

	for m in ZzPackList.monsters:
		var s: Dictionary = m.spawn
		var health := float(s.get("health", 200.0)) * (c.special_health_scale() if not m.boss else 1.0)
		var brain := str(s.get("brain", "")) if s.has("brain") else COMMON_BRAIN
		var def := _def(m.id, m.title, brain, health, float(s.get("speed", 4.4)), 3 if not m.boss else 8,
			GSNpcDef.Weight.NORMAL if not m.boss else GSNpcDef.Weight.HEAVY)
		def.sight_range = 40.0
		def.sight_half_angle_deg = 90.0
		def.hearing_range = 18.0
		def.meta = {
			"damage": float(s.get("damage", 8.0)), "reach": float(s.get("reach", 1.6)),
			"attack_interval": float(s.get("attack_interval", 1.0)), "attackers": c.attackers_per_survivor,
			"body": str(s.get("body", "common")), "radius": 0.34, "height": 1.8, "pack": m.pack,
		}
		def.meta.merge(s.get("meta", {}), true)
		_fit_collider(def.meta)
		out.append(def)

	return out

## The widest a pack monster's collider is made, whatever its data says: the nav graph and the maps' doorways are
## laid for a brute (0.7), and a T-Rex of 1.1 would jam in every one.
const PACK_MAX_RADIUS := 0.9

## The tallest a pack monster's collider stands (a brute stoops under a 2.4 m lintel the same way); its hitboxes and
## eyes keep the full height.
const PACK_FIT_HEIGHT := 2.1

## A pack monster's collider from the body the pack declares (`meta.cfg.body`: radius and height), if it declares one;
## otherwise the common's 0.34 by 1.8 stays.
static func _fit_collider(meta: Dictionary) -> void:
	var cfg: Variant = meta.get("cfg", null)
	var declared: Variant = (cfg as Dictionary).get("body", null) if cfg is Dictionary else null

	if not declared is Dictionary:
		return

	var d: Dictionary = declared
	var r := float(d.get("radius", 0.0))
	var h := float(d.get("height", 0.0))

	if r > 0.0:
		meta["radius"] = minf(r, PACK_MAX_RADIUS)

	if h > 0.0:
		meta["height"] = h
		meta["fit_height"] = minf(h, PACK_FIT_HEIGHT) if h > PACK_FIT_HEIGHT else 0.0

## The population a map runs under. Commons are cheap; a special costs what it is worth, so the
## world budget is a real ceiling on how bad things can get at once.
static func limits(config: ZzConfig, survivors: int) -> GSNpcLimits:
	var out := GSNpcLimits.new()
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
		cost: int, weight: GSNpcDef.Weight) -> GSNpcDef:
	var def := GSNpcDef.make(id, SCENE)
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
static func _eyes(def: GSNpcDef) -> GSNpcDef:
	def.eye_height = float(def.meta.get("height", 1.75)) * 0.9
	return def

## A common's chase speed in m/s: the slow base plus [param hard_stacks] steps, capped; a runner (or
## scaling off) keeps the old full run speed.
static func common_chase_speed(c: ZzConfig, hard_stacks: int, runner: bool) -> float:
	if not c.common_speed_scaling or runner:
		return c.common_run_speed

	return GSStackScale.ramp(c.common_speed_base, c.common_speed_per_hard_stack, c.common_speed_max, hard_stacks)

## How see-through a zombie is drawn at the Hard Box stacks now on (`zz_mutant_fade*`, `zz_common_fade`).
## [param c] is a ZzConfig; commons stay solid unless `zz_common_fade` is on.
static func fade_alpha(c: Object, kind: StringName, stacks: int) -> float:
	if int(c.get(&"mutant_fade")) != 1:
		return 1.0

	if kind == &"common" and int(c.get(&"common_fade")) != 1:
		return 1.0

	return GSStackScale.fade_alpha(stacks, float(c.get(&"mutant_fade_per_stack")), float(c.get(&"mutant_min_alpha")))

## The crowd.
##
## [b]Short sight and good ears while it idles, which is what makes sneaking past one a thing a
## player can do.[/b] Its brain widens both once it is alert; the senses read the instance's
## `sight_scale`, which the brain sets.
static func _common(c: ZzConfig) -> GSNpcDef:
	var def := _def(COMMON, "Infected", COMMON_BRAIN, c.common_health, c.common_run_speed, 1, GSNpcDef.Weight.NORMAL)
	def.sight_range = 30.0
	def.sight_half_angle_deg = 75.0
	def.hearing_range = 10.0
	def.meta = {
		"damage": c.common_damage, "reach": 1.55, "attack_interval": c.common_attack_interval,
		"walk_speed": c.common_walk_speed, "squad": "horde", "attackers": c.attackers_per_survivor,
		"body": "common", "radius": 0.32, "height": 1.75,
	}
	return def

static func brute_health(c: ZzConfig, survivors: int, def: GSNpcDef = null) -> float:
	var base: float = float(def.meta.get("brute_health", c.brute_health)) if def != null else c.brute_health
	return (base + c.brute_health_per_survivor * float(maxi(survivors - 1, 0))) * c.special_health_scale()


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

static func nav_for(doc: Dictionary, props_size: Callable, open_gates: PackedStringArray = PackedStringArray(), extra_solids: Array[AABB] = [], cache: bool = false) -> GSNpcNavData:
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
	job.make_builder = func(heights: Array, info: Dictionary) -> GSNpcNavBuilder:
		return _builder_for(source, sizes if known else {}, known, open_gates, extra_solids, heights, info)
	job.reach = func(nav: GSNpcNavData) -> Vector2i:
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
	out["hull_sha"] = str(extra.get("hull_sha", ""))

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
static func reachable_posts(nav: GSNpcNavData, doc: Dictionary) -> Array:
	var posts: Array = doc.get("posts", [])
	var spawns: Array = (doc.get("spawns", {}) as Dictionary).get("survivors", [])

	if spawns.is_empty() or posts.is_empty():
		return posts

	var graph := GSNpcNavGraph.new(nav)
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
static func _reach(nav: GSNpcNavData, doc: Dictionary) -> Vector2i:
	var graph := GSNpcNavGraph.new(nav)
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

static func _builder_for(doc: Dictionary, sizes: Dictionary, sizes_known: bool, open_gates: PackedStringArray, extra_solids: Array[AABB], heights: Array, info: Dictionary) -> GSNpcNavBuilder:
	var nav_doc: Dictionary = doc.get("nav", {})
	var builder := GSNpcNavBuilder.new()
	builder.spacing = float(nav_doc.get("spacing", 1.0))
	builder.point_radius = builder.spacing * 1.25
	builder.neighbour_reach = 1.6
	builder.centre_narrow_floors = true
	builder.obstacle_under_feet = float(nav_doc.get("under_feet", -1.0))
	builder.obstacle_overhead = float(nav_doc.get("overhead", NAV_OVERHEAD_BY_MAP.get(str(doc.get("id", "")), NAV_OVERHEAD)))
	builder.bridge_gap = float(nav_doc.get("bridge", NAV_BRIDGE_GAP))
	builder.clearance = float(nav_doc.get("clearance", 0.35))
	builder.links_check_obstacles = true
	builder.generate_cover = true
	builder.cover_range = NAV_COVER_RANGE

	var floors: Array = ZzNavLadderFloors.with_rows(doc, open_gates, _box_bounds)

	for f: Array in floors:
		var area := AABB(Vector3(float(f[0]), float(f[4]), float(f[1])),
			Vector3(float(f[2]) - float(f[0]), 0.0, float(f[3]) - float(f[1])))
		builder.add_floor(area, float(f[4]))

	if doc.has("terrain"):
		var ground := GSMapTerrain.from_dict(doc["terrain"])
		if ground.ok:
			builder.add_points((ground.value as GSMapTerrain).walk_points(builder.spacing), GSMapTerrain.WALK_RISE)

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
		GSLog.debug(CHANNEL, "nav links through solid geometry dropped", {"map": doc.get("id", ""), "dropped": rejected})

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

## A fingerprint of everything the graph was built from, and of what the physics pass then cut it on: the cache holds
## the PRUNED graph (ZzHorde._prune_blocked), so the document's choice of colliding world hulls and its solid props are
## part of the key. Without them a map whose `world_collision` changed kept its old cuts on every box that had run it.
static func digest_of(doc: Dictionary, open_gates: PackedStringArray = PackedStringArray(), extra_solids: Array[AABB] = []) -> String:
	return GSNpcNavData.digest_of([
		str(doc.get("id", "")), JSON.stringify(doc.get("nav", {})), str(doc.get("terrain", {}).get("data", "")).sha256_text(),
		JSON.stringify(doc.get("boxes", [])).sha256_text(), JSON.stringify(doc.get("props", [])).sha256_text(),
		JSON.stringify(doc.get("solid_props", [])).sha256_text(), JSON.stringify(doc.get("world_collision", {})),
		str(doc.get("world", "")), str(doc.get("world_key", "")), str(doc.get("hull_sha", "")),
		",".join(open_gates), str(extra_solids),
		NAV_OVERHEAD, str(NAV_OVERHEAD_BY_MAP), "link_obstacles_needed", SLAB_THICK, SLAB_TOP_CUT,
		float(doc.get("nav", {}).get("spacing", 1.0)), float(doc.get("nav", {}).get("clearance", 0.35)), NAV_COVER_RANGE,
	])
