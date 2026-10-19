extends RefCounted

## What a map's surfaces are made of: a wood floor, a tiled corridor, a carpet, a painted
## wall, brick, grass, asphalt, glass. Generated here, once per process, as small tiling
## textures; never a file.
##
## [b]Generated, not vendored, and the reason is the delivered pack.[/b] A texture a game
## ships is a file inside a mount whose path the imported material recorded at the AUTHORED
## location, which is the family's delivery bug in its sixth form; a texture made in code has
## no path to be wrong. They are also tiny: twenty-odd 128-pixel images, generated in about a
## third of a second on a client and never on a server, which draws nothing.
##
## [b]Mapped in world space (triplanar), so a box needs no UVs.[/b] A map is hundreds of boxes
## of every size, and per-box UVs would stretch a plank across a two-metre wall and a
## twenty-metre one alike. In world space a plank is the same width on every wall, which is
## what makes a room read as a room rather than as a box with a picture on it.
##
## [b]A surface has a tint.[/b] A map document names a surface and may tint it, so one carpet
## is a blue classroom and a red library without a second texture.
##
## [b]The building is drawn in the family's look, dusted for the night[/b] (game-arena's
## built-in maps, then mg-prop-hunt's rooms): every surface a street or a room is built of
## (floors, walls, ceilings, roofs, the ground) is Kenney's light prototype grid, or his tiles
## on a floor, under a pastel that says what it is ([constant PASTELS]), moved
## [constant DUST] of the way to its own grey so a night street is not a sweet shop. The map's
## tint still multiplies it, paled halfway to white. [b]Light walls are what make a zombie
## read[/b]: the bodies are dark greys and greens, and against the old dark brick a crowd was
## one dark mass; against a pale wall, even at night, each one is a silhouette. Metal, glass,
## water, lines, lockers and the rest keep their generated look.
##
## [b]The two textures are files, and the reason the rest are not does not bite them[/b]:
## they are loaded by a path through [code]ZzPaths.rebase[/code] (as the props are), never
## referenced by an imported material, and a checkout without them falls back to the
## generated look rather than failing. Kenney's Prototype Textures 1.0, CC0;
## `assets/kenney/prototype/License.txt` is his, unchanged.

const ZzPaths := preload("zz_paths.gd")

const SIZE := 128

## Where the grid and the tiles are; rebased, for a delivered pack.
const GRID_PATH := "res://assets/kenney/prototype/grid.png"
const TILES_PATH := "res://assets/kenney/prototype/tiles.png"

## How much world one copy of either texture covers: 4 m, so a major line is 2 m and a faint
## one 0.5 m, as on game-arena's maps.
const GRID_METRES := 4.0

## How far each pastel is moved toward its own grey. mg-prop-hunt's pastels at full
## saturation under a blue moon read as candy; at a third of the way they still say
## "the peach floor", "the coral brick", and the street stays a street at night.
const DUST := 0.4

## surface id -> `[pastel, floor]`: mg-prop-hunt's table (the same hues name the same
## surfaces across the family), dusted by [constant DUST]. A surface not here keeps its
## generated pattern.
const PASTELS := {
	"wood_floor": [Color(0.98, 0.84, 0.70), true],
	"parquet": [Color(0.98, 0.86, 0.72), true],
	"gym": [Color(1.00, 0.92, 0.66), true],
	"tile": [Color(0.92, 0.96, 0.98), true],
	"tile_check": [Color(0.84, 0.94, 0.96), true],
	"tile_small": [Color(0.88, 0.96, 1.00), true],
	"carpet": [Color(0.76, 0.82, 1.00), true],
	"concrete": [Color(0.90, 0.90, 0.95), true],
	"sidewalk": [Color(0.92, 0.92, 0.94), true],
	"asphalt": [Color(0.62, 0.64, 0.74), true],
	"grass": [Color(0.70, 0.94, 0.68), true],
	"dirt": [Color(0.92, 0.80, 0.66), true],
	"sand": [Color(1.00, 0.93, 0.72), true],
	"rubber": [Color(1.00, 0.70, 0.66), true],
	"paint": [Color(0.98, 0.97, 0.94), false],
	"plaster": [Color(0.97, 0.96, 1.00), false],
	"ceiling": [Color(0.93, 0.93, 0.95), false],
	"brick": [Color(1.00, 0.80, 0.74), false],
	"stone": [Color(0.86, 0.86, 0.90), false],
	"roof": [Color(0.74, 0.70, 0.88), false],
	"wood": [Color(0.94, 0.80, 0.64), false],
	"hedge": [Color(0.56, 0.84, 0.58), false],
}

## id -> `{pattern, colours, metres, roughness, alpha, metallic}`. `metres` is how much world
## one tile of the texture covers.
const SURFACES := {
	"wood_floor": {"pattern": "planks", "a": Color(0.62, 0.43, 0.26), "b": Color(0.47, 0.31, 0.18), "metres": 2.0, "rough": 0.7},
	"parquet": {"pattern": "parquet", "a": Color(0.66, 0.48, 0.30), "b": Color(0.52, 0.36, 0.21), "metres": 1.2, "rough": 0.6},
	"gym": {"pattern": "planks", "a": Color(0.86, 0.69, 0.45), "b": Color(0.76, 0.58, 0.36), "metres": 2.4, "rough": 0.45},
	"tile": {"pattern": "tiles", "a": Color(0.88, 0.87, 0.82), "b": Color(0.62, 0.62, 0.60), "metres": 1.2, "rough": 0.35, "n": 2},
	"tile_check": {"pattern": "checker", "a": Color(0.90, 0.89, 0.84), "b": Color(0.32, 0.46, 0.52), "metres": 1.2, "rough": 0.35},
	"tile_small": {"pattern": "tiles", "a": Color(0.93, 0.94, 0.95), "b": Color(0.70, 0.72, 0.74), "metres": 0.8, "rough": 0.3, "n": 4},
	"carpet": {"pattern": "speckle", "a": Color(0.36, 0.42, 0.55), "b": Color(0.28, 0.33, 0.45), "metres": 1.5, "rough": 0.95},
	"paint": {"pattern": "plaster", "a": Color(0.92, 0.91, 0.88), "b": Color(0.86, 0.85, 0.82), "metres": 3.0, "rough": 0.9},
	"plaster": {"pattern": "plaster", "a": Color(0.95, 0.94, 0.92), "b": Color(0.90, 0.89, 0.87), "metres": 3.0, "rough": 0.9},
	"ceiling": {"pattern": "grid", "a": Color(0.95, 0.95, 0.93), "b": Color(0.78, 0.78, 0.76), "metres": 1.2, "rough": 0.9},
	"brick": {"pattern": "bricks", "a": Color(0.62, 0.30, 0.22), "b": Color(0.80, 0.76, 0.70), "metres": 1.6, "rough": 0.85},
	"stone": {"pattern": "stones", "a": Color(0.60, 0.59, 0.56), "b": Color(0.42, 0.41, 0.40), "metres": 2.0, "rough": 0.85},
	"concrete": {"pattern": "speckle", "a": Color(0.66, 0.66, 0.64), "b": Color(0.56, 0.56, 0.55), "metres": 3.0, "rough": 0.9},
	"sidewalk": {"pattern": "slabs", "a": Color(0.62, 0.61, 0.58), "b": Color(0.48, 0.48, 0.46), "metres": 2.0, "rough": 0.9},
	"asphalt": {"pattern": "speckle", "a": Color(0.20, 0.21, 0.22), "b": Color(0.28, 0.28, 0.29), "metres": 3.0, "rough": 0.95},
	"grass": {"pattern": "grass", "a": Color(0.25, 0.42, 0.16), "b": Color(0.19, 0.33, 0.12), "metres": 2.5, "rough": 1.0},
	"dirt": {"pattern": "speckle", "a": Color(0.47, 0.36, 0.24), "b": Color(0.38, 0.28, 0.18), "metres": 2.5, "rough": 1.0},
	"sand": {"pattern": "speckle", "a": Color(0.86, 0.78, 0.58), "b": Color(0.78, 0.70, 0.50), "metres": 2.0, "rough": 1.0},
	"rubber": {"pattern": "speckle", "a": Color(0.46, 0.20, 0.17), "b": Color(0.38, 0.15, 0.12), "metres": 1.5, "rough": 0.95},
	"roof": {"pattern": "shingles", "a": Color(0.30, 0.28, 0.30), "b": Color(0.20, 0.19, 0.21), "metres": 2.0, "rough": 0.9},
	"wood": {"pattern": "grain", "a": Color(0.58, 0.40, 0.24), "b": Color(0.46, 0.31, 0.18), "metres": 1.5, "rough": 0.6},
	"metal": {"pattern": "brushed", "a": Color(0.70, 0.72, 0.74), "b": Color(0.60, 0.62, 0.65), "metres": 1.0, "rough": 0.35, "metallic": 0.6},
	"locker": {"pattern": "lockers", "a": Color(0.25, 0.45, 0.68), "b": Color(0.14, 0.26, 0.42), "metres": 1.2, "rough": 0.4, "metallic": 0.4},
	"chalkboard": {"pattern": "speckle", "a": Color(0.16, 0.27, 0.21), "b": Color(0.20, 0.31, 0.25), "metres": 2.0, "rough": 0.9},
	"whiteboard": {"pattern": "flat", "a": Color(0.96, 0.97, 0.98), "b": Color(0.96, 0.97, 0.98), "metres": 2.0, "rough": 0.15},
	"glass": {"pattern": "flat", "a": Color(0.72, 0.86, 0.95), "b": Color(0.72, 0.86, 0.95), "metres": 2.0, "rough": 0.05, "alpha": 0.22},
	"water": {"pattern": "speckle", "a": Color(0.20, 0.55, 0.78), "b": Color(0.26, 0.62, 0.85), "metres": 3.0, "rough": 0.1, "alpha": 0.6},
	"line": {"pattern": "flat", "a": Color(0.95, 0.95, 0.92), "b": Color(0.95, 0.95, 0.92), "metres": 1.0, "rough": 0.8},
	"hedge": {"pattern": "grass", "a": Color(0.20, 0.42, 0.16), "b": Color(0.15, 0.33, 0.12), "metres": 1.2, "rough": 1.0},
	"fabric": {"pattern": "speckle", "a": Color(0.70, 0.20, 0.20), "b": Color(0.60, 0.15, 0.15), "metres": 1.0, "rough": 0.95},
	"flat": {"pattern": "flat", "a": Color(0.8, 0.8, 0.8), "b": Color(0.8, 0.8, 0.8), "metres": 2.0, "rough": 0.8},
}

## Where the photographic kinds are (dot-map's DotMapSurfaces), in this game's own tree: the
## client shell bundles dot-map without its textures, so the ones used ship in this pack
## (assets/surfaces, [code]tools/sync-surfaces.sh[/code] in dot-map writes it). Rebased, for a
## delivered pack.
const SURFACES_ROOT := "res://assets/surfaces"
const SURFACES_SCRIPT := "res://addons/dot_map/surfaces/dot_map_surfaces.gd"

## Which surface kind draws a map surface, by what the box is: a [b]wall[/b] (anything
## upright or small) or a [b]floor[/b] (a slab lying down, 0.6 m or thinner and wider than
## 1.5 m: floors, ceilings, roofs, roads). Most surfaces are one kind either way; a painted
## surface is plaster on a wall and bare clean concrete underfoot. A surface not here (lockers,
## carpet, glass, water, lines, fabric, hedges) keeps its generated look.
const KIND_OF := {
	"concrete": ["concrete", "concrete"], "stone": ["concrete", "concrete"],
	"sidewalk": ["concrete_clean", "concrete_clean"], "ceiling": ["concrete_clean", "concrete_clean"],
	"asphalt": ["asphalt", "asphalt"],
	"tile": ["tile_white", "tile_white"], "tile_small": ["tile_white", "tile_white"],
	"tile_check": ["tile_checker", "tile_checker"],
	"paint": ["plaster", "concrete_clean"], "plaster": ["plaster", "concrete_clean"],
	"brick": ["brick", "brick"], "roof": ["corrugated", "corrugated"],
	"wood_floor": ["wood_floor", "wood_floor"], "parquet": ["wood_floor", "wood_floor"],
	"gym": ["wood_floor", "wood_floor"], "wood": ["wood_planks", "wood_planks"],
	"metal": ["metal", "metal"], "grass": ["grass", "grass"], "dirt": ["ground", "ground"],
}

## A kind's own tint, multiplied under the map's. The photographs are mid-tone to bright
## (white tile is 0.97 on average, plaster 0.75): scaled so a map reads at the brightness the
## pale prototype grid had, which the zombies are read against, and so tile, grass, ground and
## planks are not neon under a night's light.
const KIND_TINT := {
	"concrete": Color(0.95, 0.95, 0.95), "concrete_clean": Color(0.85, 0.85, 0.85),
	"plaster": Color(0.9, 0.9, 0.9), "brick": Color(1.15, 1.1, 1.1),
	"tile_white": Color(0.8, 0.8, 0.82), "tile_checker": Color(1.3, 1.3, 1.3),
	"wood_floor": Color(1.35, 1.3, 1.3), "wood_planks": Color(0.8, 0.78, 0.75),
	"asphalt": Color(1.2, 1.2, 1.2), "metal": Color(1.2, 1.2, 1.2),
	"corrugated": Color(0.9, 0.9, 0.9), "grass": Color(0.6, 0.64, 0.5),
	"ground": Color(0.8, 0.75, 0.65),
}

static var _textures: Dictionary = {}
static var _materials: Dictionary = {}
## DotMapSurfaces for baked surfaces (no metallic: a lightmap holds diffuse light only) and for
## the one live-lit metal; null until asked, and false when the addon or the textures are not
## in this build (then every surface keeps its generated look).
static var _baked_surfaces: Variant = null
static var _live_surfaces: Variant = null


static func ids() -> Array:
	return SURFACES.keys()


static func has(id: String) -> bool:
	return SURFACES.has(id)


## Whether [param id] is drawn see-through. A see-through surface is still solid unless the
## map says otherwise; glass stops a player and does not stop a look.
static func is_transparent(id: String) -> bool:
	return float((SURFACES.get(id, {}) as Dictionary).get("alpha", 1.0)) < 1.0


## A surface whose look is a highlight a lamp throws on it (brushed metal): a lightmap holds
## diffuse light only, so baked, a lamp's bright pool on a metal wall is gone. Such a surface is
## left out of the bake and lit live by the lamps, which still light what has no lightmap.
static func is_shiny(id: String, role: String = "", surface: String = "") -> bool:
	var kind := kind_for(id, role, surface)
	if kind != "":
		return kind == "metal"
	return float((SURFACES.get(id, {}) as Dictionary).get("metallic", 0.0)) >= 0.5


## "floor" for a slab lying down (0.6 m or thinner, wider than 1.5 m), "wall" for the rest.
static func role_of(size: Vector3) -> String:
	return "floor" if size.y <= 0.6 and maxf(size.x, size.z) >= 1.5 else "wall"


## The photographic kind that draws [param id] for a box of [param role], or empty when it keeps
## its generated look (or this build has no textures). [param surface] is a map's own word for
## the box ("surface": "brick") and wins; it may be a kind or one of DotMapSurfaces' aliases.
static func kind_for(id: String, role: String = "wall", surface: String = "") -> String:
	# A barricade's damage is its tint stepping down (zz_map.set_barricade); a photograph under
	# the paled tint would barely show it, so the boards keep their generated look.
	if role == "barricade":
		return ""
	var surfaces: Variant = _surfaces(false)
	if surfaces == null:
		return ""
	var kind := ""
	if surface != "":
		kind = String(surfaces.resolve(StringName(surface)))
	if kind == "" and KIND_OF.has(id):
		kind = (KIND_OF[id] as Array)[1 if role == "floor" else 0]
	return kind if kind != "" and _kind_present(surfaces, kind) else ""


## Whether a kind's textures are in this build's tree (the vendored copy is the one a pack ships).
static func _kind_present(surfaces: Object, kind: String) -> bool:
	return ResourceLoader.exists("%s/%s/albedo.jpg" % [surfaces.root, kind])


## The surfaces library, or null. [param live] is the one with its metallic values; the other has
## them off, for surfaces a lightmap covers.
static func _surfaces(live: bool) -> Variant:
	var held: Variant = _live_surfaces if live else _baked_surfaces
	if held != null:
		return held if held is Object else null
	if not ResourceLoader.exists(SURFACES_SCRIPT):
		_live_surfaces = false
		_baked_surfaces = false
		return null
	var script := load(SURFACES_SCRIPT) as GDScript
	var made: Object = script.new(ZzPaths.rebase(SURFACES_ROOT))
	if not live:
		made.set("metallic_scale", 0.0)
	if live:
		_live_surfaces = made
	else:
		_baked_surfaces = made
	return made


## The material for [param id], tinted. Cached per (surface, tint).
static func material(id: String, tint: Color = Color.WHITE, role: String = "wall", surface: String = "") -> StandardMaterial3D:
	if not SURFACES.has(id):
		id = "flat"

	var key := "%s|%s|%s|%s" % [id, tint.to_html(), role, surface]

	if _materials.has(key):
		return _materials[key]

	var kind := kind_for(id, role, surface)
	if kind != "":
		var photo := _photo(kind, tint)
		if photo != null:
			_materials[key] = photo
			return photo

	if PASTELS.has(id):
		var grid := _pastel(id, tint)
		if grid != null:
			_materials[key] = grid
			return grid

	var spec: Dictionary = SURFACES[id]
	var m := StandardMaterial3D.new()
	var alpha := float(spec.get("alpha", 1.0))
	m.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	m.roughness = float(spec.get("rough", 0.8))
	m.metallic = float(spec.get("metallic", 0.0))

	if str(spec["pattern"]) != "flat":
		m.albedo_texture = texture(id)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / maxf(float(spec.get("metres", 2.0)), 0.1)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		m.albedo_color = Color(
			(spec["a"] as Color).r * tint.r, (spec["a"] as Color).g * tint.g, (spec["a"] as Color).b * tint.b, alpha)

	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX

	_materials[key] = m
	return m


## A photographic kind under the map's tint, or null when it did not load. The map's tint was
## chosen against the old darker base colours, so it is paled halfway to white before it
## multiplies (as for the grid below); the kind's own tint scales the photograph's brightness.
static func _photo(kind: String, tint: Color) -> StandardMaterial3D:
	var surfaces: Variant = _surfaces(kind == "metal")
	if surfaces == null:
		return null
	var pale := Color(minf(tint.r, 1.1), minf(tint.g, 1.1), minf(tint.b, 1.1)).lerp(Color.WHITE, 0.5)
	var base: Color = KIND_TINT.get(kind, Color.WHITE)
	var res: DotResult = surfaces.try_material(StringName(kind), Color(base.r * pale.r, base.g * pale.g, base.b * pale.b))
	return res.value if res.ok else null


## A building surface on Kenney's grid (or tiles), or null when the textures are not there.
static func _pastel(id: String, tint: Color) -> StandardMaterial3D:
	var entry: Array = PASTELS[id]
	var texture := _kenney(TILES_PATH if bool(entry[1]) else GRID_PATH)
	if texture == null:
		return null

	# The tint was chosen against the old, darker base colour, so it is paled halfway to
	# white before it multiplies: at full strength a brick tint over a pastel was mud.
	var pale := Color(minf(tint.r, 1.1), minf(tint.g, 1.1), minf(tint.b, 1.1)).lerp(Color.WHITE, 0.5)
	var pastel: Color = entry[0]
	var grey := pastel.get_luminance()
	pastel = pastel.lerp(Color(grey, grey, grey), DUST)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(pastel.r * pale.r, pastel.g * pale.g, pastel.b * pale.b)
	m.albedo_texture = texture
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / GRID_METRES
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 0.85
	m.metallic = 0.0
	return m


static func _kenney(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var at := ZzPaths.rebase(path)
	var loaded: Texture2D = null
	if ResourceLoader.exists(at, "Texture2D"):
		loaded = ResourceLoader.load(at, "Texture2D") as Texture2D
	_textures[path] = loaded
	return loaded


## The tiling texture for [param id].
static func texture(id: String) -> ImageTexture:
	if _textures.has(id):
		return _textures[id]

	var spec: Dictionary = SURFACES.get(id, SURFACES["flat"])
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = hash(id)
	noise.frequency = 0.08
	var a: Color = spec["a"]
	var b: Color = spec["b"]

	match str(spec["pattern"]):
		"planks":
			_planks(image, a, b, noise, 8)
		"parquet":
			_parquet(image, a, b, noise)
		"tiles":
			_tiles(image, a, b, noise, int(spec.get("n", 2)))
		"checker":
			_checker(image, a, b, noise)
		"grid":
			_tiles(image, a, b, noise, 2, 1)
		"bricks":
			_bricks(image, a, b, noise)
		"stones":
			_stones(image, a, b, noise)
		"slabs":
			_tiles(image, a, b, noise, 2, 2)
		"shingles":
			_shingles(image, a, b, noise)
		"grain":
			_grain(image, a, b, noise)
		"brushed":
			_brushed(image, a, b, noise)
		"lockers":
			_lockers(image, a, b, noise)
		"grass":
			_grass(image, a, b, noise)
		"plaster":
			_speckle(image, a, b, noise, 0.5)
		_:
			_speckle(image, a, b, noise, 1.0)

	image.generate_mipmaps()
	var made := ImageTexture.create_from_image(image)
	_textures[id] = made
	return made


static func _n(noise: FastNoiseLite, x: float, y: float) -> float:
	# Tiling noise: the same field sampled on a torus, so the edges meet.
	var u := x / float(SIZE) * TAU
	var v := y / float(SIZE) * TAU
	return noise.get_noise_3d(cos(u) * 8.0, sin(u) * 8.0 + cos(v) * 8.0, sin(v) * 8.0)


static func _speckle(image: Image, a: Color, b: Color, noise: FastNoiseLite, amount: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise.seed
	for y in range(SIZE):
		for x in range(SIZE):
			var t := clampf(0.5 + _n(noise, x, y) * 0.8 * amount + rng.randf_range(-0.15, 0.15) * amount, 0.0, 1.0)
			image.set_pixel(x, y, a.lerp(b, t))


static func _planks(image: Image, a: Color, b: Color, noise: FastNoiseLite, rows: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise.seed
	var height := SIZE / rows
	var offsets: Array[int] = []
	var shades: Array[float] = []
	for r in range(rows):
		offsets.append(rng.randi_range(0, SIZE - 1))
		shades.append(rng.randf_range(-0.25, 0.25))
	for y in range(SIZE):
		var row := y / height
		for x in range(SIZE):
			var along := float((x + offsets[row]) % SIZE)
			var grain := sin(along * 0.18 + _n(noise, x, y) * 6.0) * 0.18
			var t := clampf(0.45 + shades[row] + grain, 0.0, 1.0)
			var c := a.lerp(b, t)
			if y % height == 0 or int(along) % (SIZE / 2) == 0:
				c = c.darkened(0.35)
			image.set_pixel(x, y, c)


static func _parquet(image: Image, a: Color, b: Color, noise: FastNoiseLite) -> void:
	var cell := SIZE / 4
	for y in range(SIZE):
		for x in range(SIZE):
			var cx := x / cell
			var cy := y / cell
			var flip := (cx + cy) % 2 == 0
			var local := (x % cell) if flip else (y % cell)
			var strip := local / (cell / 4)
			var t := clampf(0.4 + (0.25 if strip % 2 == 0 else -0.1) + _n(noise, x, y) * 0.3, 0.0, 1.0)
			var c := a.lerp(b, t)
			if x % cell == 0 or y % cell == 0 or local % (cell / 4) == 0:
				c = c.darkened(0.3)
			image.set_pixel(x, y, c)


static func _tiles(image: Image, a: Color, b: Color, noise: FastNoiseLite, n: int, grout: int = 2) -> void:
	var cell := SIZE / n
	var rng := RandomNumberGenerator.new()
	rng.seed = noise.seed
	var shades := []
	for i in range(n * n):
		shades.append(rng.randf_range(-0.04, 0.04))
	for y in range(SIZE):
		for x in range(SIZE):
			var c := a
			if x % cell < grout or y % cell < grout:
				c = b
			else:
				var s: float = shades[(y / cell) * n + (x / cell)]
				c = a.lightened(s) if s > 0.0 else a.darkened(-s)
				c = c.darkened(maxf(_n(noise, x, y), 0.0) * 0.06)
			image.set_pixel(x, y, c)


static func _checker(image: Image, a: Color, b: Color, noise: FastNoiseLite) -> void:
	var cell := SIZE / 2
	for y in range(SIZE):
		for x in range(SIZE):
			var c := a if ((x / cell) + (y / cell)) % 2 == 0 else b
			c = c.darkened(maxf(_n(noise, x, y), 0.0) * 0.05)
			if x % cell == 0 or y % cell == 0:
				c = c.darkened(0.2)
			image.set_pixel(x, y, c)


static func _bricks(image: Image, a: Color, b: Color, noise: FastNoiseLite) -> void:
	var rows := 8
	var height := SIZE / rows
	var width := SIZE / 4
	var rng := RandomNumberGenerator.new()
	rng.seed = noise.seed
	var shades := []
	for i in range(rows * 5):
		shades.append(rng.randf_range(-0.12, 0.12))
	for y in range(SIZE):
		var row := y / height
		var shift := (width / 2) if row % 2 == 1 else 0
		for x in range(SIZE):
			var xs := (x + shift) % SIZE
			var c := b
			if y % height >= 2 and xs % width >= 2:
				var s: float = shades[row * 5 + xs / width]
				c = a.lightened(s) if s > 0.0 else a.darkened(-s)
				c = c.darkened(maxf(_n(noise, x, y), 0.0) * 0.18)
			image.set_pixel(x, y, c)


static func _stones(image: Image, a: Color, b: Color, noise: FastNoiseLite) -> void:
	var cells := Voronoi.new(noise.seed, 14)
	for y in range(SIZE):
		for x in range(SIZE):
			var near := cells._near(x, y)
			var d := float(near[1]) - float(near[0])
			var c := a.lerp(b, clampf(0.4 + _n(noise, x, y) * 0.5 + cells.shades[int(near[2])], 0.0, 1.0))
			if d < 1.6:
				c = b.darkened(0.3)
			image.set_pixel(x, y, c)


static func _shingles(image: Image, a: Color, b: Color, noise: FastNoiseLite) -> void:
	var rows := 8
	var height := SIZE / rows
	for y in range(SIZE):
		var row := y / height
		var shift := (SIZE / 16) if row % 2 == 1 else 0
		for x in range(SIZE):
			var t := float(y % height) / float(height)
			var c := a.lerp(b, t * 0.8 + _n(noise, x, y) * 0.2)
			if (x + shift) % (SIZE / 8) == 0:
				c = b.darkened(0.25)
			image.set_pixel(x, y, c)


static func _grain(image: Image, a: Color, b: Color, noise: FastNoiseLite) -> void:
	for y in range(SIZE):
		for x in range(SIZE):
			var t := clampf(0.5 + sin(float(y) * 0.35 + _n(noise, x, y) * 8.0) * 0.35, 0.0, 1.0)
			image.set_pixel(x, y, a.lerp(b, t))


static func _brushed(image: Image, a: Color, b: Color, noise: FastNoiseLite) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise.seed
	var rows := []
	for y in range(SIZE):
		rows.append(rng.randf_range(0.0, 1.0))
	for y in range(SIZE):
		for x in range(SIZE):
			image.set_pixel(x, y, a.lerp(b, clampf(float(rows[y]) * 0.7 + _n(noise, x, y) * 0.3, 0.0, 1.0)))


static func _lockers(image: Image, a: Color, b: Color, noise: FastNoiseLite) -> void:
	var door := SIZE / 2
	for y in range(SIZE):
		for x in range(SIZE):
			var c := a.darkened(maxf(_n(noise, x, y), 0.0) * 0.1)
			var lx := x % door
			if lx < 2 or y < 2:
				c = b
			# Vents near the top, a handle half way down.
			elif y > 10 and y < 26 and lx > 12 and lx < door - 12 and y % 4 < 2:
				c = b.lightened(0.1)
			elif lx > door - 12 and lx < door - 7 and y > 58 and y < 72:
				c = Color(0.82, 0.82, 0.84)
			image.set_pixel(x, y, c)


static func _grass(image: Image, a: Color, b: Color, noise: FastNoiseLite) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise.seed
	for y in range(SIZE):
		for x in range(SIZE):
			var t := clampf(0.5 + _n(noise, x, y) * 0.9, 0.0, 1.0)
			var c := a.lerp(b, t)
			if rng.randf() < 0.12:
				c = c.lightened(rng.randf_range(0.05, 0.18))
			image.set_pixel(x, y, c)


## A few points on a torus, for stones: how far a pixel is from the nearest edge between two
## cells, and a shade per cell.
class Voronoi:
	extends RefCounted
	var points: Array[Vector2] = []
	var shades: Array[float] = []

	func _init(seed_value: int, count: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for i in range(count):
			points.append(Vector2(rng.randf() * SIZE, rng.randf() * SIZE))
			shades.append(rng.randf_range(-0.2, 0.2))

	func _near(x: int, y: int) -> Array:
		var best := INF
		var second := INF
		var which := 0
		for i in range(points.size()):
			var d := INF
			for ox in [-SIZE, 0, SIZE]:
				for oy in [-SIZE, 0, SIZE]:
					d = minf(d, Vector2(x, y).distance_to(points[i] + Vector2(ox, oy)))
			if d < best:
				second = best
				best = d
				which = i
			elif d < second:
				second = d
		return [best, second, which]

