extends DotBotNav

## [DotBotNav] that bakes a map too big for one Recast grid in tiles and joins them into one mesh. Godot's baker refuses a bake whose cell grid is over 30 million cells ("suspiciously big") while `navigation/baking/use_crash_prevention_checks` is on, and one Recast poly mesh holds under 65535 vertices. At ZZ's 0.1016 m cell (the survivors' radius in exactly 4 cells) rp_southside, rp_asheville, gm_boreas, gm_vyten,
## gm_bigisland and gm_valley are over the first, and a wider cell still baked nothing on rp_southside (the second). So such a map is baked at the same cell in square tiles, each with a border of cells around it the way Recast's tiled meshes are (its regions end exactly on the tile line), and the tiles are joined: the vertices two tiles share on a line are welded, and a tile's edge along the line is split at the other
## side's vertices, so every seam is a shared edge, the navigation server connects it, and the annotator sees one floor. A map within the budget bakes exactly as before (one grid, same mesh, same cache file). Nothing is clamped: a tile size the engine would refuse, or a negative one, fails the bake saying so. A tiled bake in dot-bot itself would let this override go (nightly dotbot-nav-max-cells-1).

const LOG := "zz.nav"

## The engine's refusal line (nav_mesh_generator_3d.cpp, `use_crash_prevention_checks`).
const ENGINE_MAX_CELLS := 30000000

## The tile side, metres, when the map is over the budget and [member tile_size] is 0 (auto).
const AUTO_TILE := 128.0

## Metres within which a seam vertex counts as an edge's own end, not a point inside it to split at.
const SPLIT_EPSILON := 0.0001

## Cells of border past the agent's radius around each tile (Recast's own advice is 3).
const BORDER_PAD := 3

## Tile side, metres (rounded up to whole cells): 0 = auto (one grid while the map is within the
## engine's limit, else [constant AUTO_TILE] tiles), above 0 always tiles.
var tile_size: float = 0.0

## The tiles the last bake used (0 for one grid) and their side.
var tiles_cut: int = 0
var tile_cut: float = 0.0

## The tile boxes of the current bake (no border) and the grid they sit on.
var _tiles: Array[AABB] = []
var _origin := Vector3.ZERO
var _counts := Vector2i.ZERO


## [method DotBotNav.bake], tiled when the map needs it.
func bake(root: Node3D, agent: Dictionary = {}, mask: int = 0, bodies: Array = []) -> DotResult:
	var parsed := _parse(root, agent, mask, bodies)

	if not parsed.ok:
		return parsed

	if _cache_load(parsed.value):
		return _take_in()

	return bake_now(parsed.value)


## [method DotBotNav.bake_in_background], the tiles baked side by side on the server's workers.
func bake_in_background(root: Node3D, agent: Dictionary = {}, mask: int = 0, bodies: Array = [], done: Callable = Callable()) -> DotResult:
	var parsed := _parse(root, agent, mask, bodies)

	if not parsed.ok:
		return parsed

	var source: NavigationMeshSourceGeometryData3D = parsed.value

	if _cache_load(source) or not DotPlatform.has_threads():
		var res := _take_in() if last_bake_cached else bake_now(source)
		if done.is_valid():
			done.call(res)
		return res

	_baking = true

	if _tiles.is_empty():
		NavigationServer3D.bake_from_source_geometry_data_async(mesh, source, _on_baked.bind(_generation, mesh, done))
		return DotResult.success(0)

	var parts: Array[NavigationMesh] = []
	var landed := [0]

	for box in _tiles:
		parts.append(_tile_mesh(box))

	for part in parts:
		NavigationServer3D.bake_from_source_geometry_data_async(part, source, _on_tile.bind(_generation, mesh, parts, landed, done))

	return DotResult.success(0)


## The sync bake of an already parsed [param source], one grid or tiled.
func bake_now(source: NavigationMeshSourceGeometryData3D) -> DotResult:
	if _tiles.is_empty():
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
		return _take_in()

	var parts: Array[NavigationMesh] = []

	for box in _tiles:
		var part := _tile_mesh(box)
		NavigationServer3D.bake_from_source_geometry_data(part, source)
		parts.append(part)

	return _joined(parts)


func _on_tile(generation: int, base: NavigationMesh, parts: Array[NavigationMesh], landed: Array, done: Callable) -> void:
	if generation != _generation or base != mesh:
		return

	landed[0] += 1

	if landed[0] < parts.size():
		return

	_baking = false
	var res := _joined(parts)

	if done.is_valid():
		done.call(res)


## Where the cache lives; a tiled bake keeps its own file, so changing the tile never reads the other's mesh.
func cache_path() -> String:
	var path := super()

	if path.is_empty() or _tiles.is_empty():
		return path

	return path.trim_suffix(".nav.res") + ".tile%d.nav.res" % roundi(tile_cut * 1000.0)


func _parse(root: Node3D, agent: Dictionary, mask: int, bodies: Array) -> DotResult:
	_tiles.clear()
	tiles_cut = 0
	tile_cut = 0.0
	var parsed: DotResult = super(root, agent, mask, bodies)

	if not parsed.ok:
		return parsed

	var planned := _plan(parsed.value)
	return parsed if planned.ok else planned


## Recast's grid (rcCalcGridSize) for [param size] at [param cell].
static func grid_cells(size: Vector3, cell: float) -> int:
	return int(size.x / cell + 0.5) * int(size.z / cell + 0.5)


## The border around a tile, metres: the radius in whole cells plus [constant BORDER_PAD].
func border() -> float:
	return (ceilf(mesh.agent_radius / mesh.cell_size - 0.001) + BORDER_PAD) * mesh.cell_size


## Splits the map into tiles when [member tile_size] or the engine's limit asks for it.
func _plan(source: NavigationMeshSourceGeometryData3D) -> DotResult:
	var engine_checks := bool(ProjectSettings.get_setting("navigation/baking/use_crash_prevention_checks", true))
	var bounds := source.get_bounds()
	var cell := mesh.cell_size

	if tile_size < 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "zz_nav_notes_bake_tile is %.1f; it is metres, 0 for auto" % tile_size)

	var side := tile_size

	if side == 0.0:
		if not engine_checks or grid_cells(bounds.size, cell) <= ENGINE_MAX_CELLS:
			return DotResult.success(0)
		side = AUTO_TILE

	side = ceilf(side / cell - 0.001) * cell
	var pad := border()

	if side < 4.0 * pad:
		return DotResult.fail(DotError.CODE_INVALID,
			"zz_nav_notes_bake_tile %.2f m is under four times the %.2f m border each tile bakes around it; raise it or set 0 for auto" % [side, pad])

	var with_border := Vector3(side + 2.0 * pad, 0.0, side + 2.0 * pad)

	if engine_checks and grid_cells(with_border, cell) > ENGINE_MAX_CELLS:
		return DotResult.fail(DotError.CODE_INVALID,
			"zz_nav_notes_bake_tile %.0f m needs %d cells a tile, over the engine's %d while navigation/baking/use_crash_prevention_checks is on; lower it or set 0 for auto" % [
				side, grid_cells(with_border, cell), ENGINE_MAX_CELLS])

	# The tiles sit on the cell grid, so the two sides of a seam put their vertices on the same line.
	_origin = Vector3(floorf(bounds.position.x / cell) * cell, bounds.position.y - 1.0, floorf(bounds.position.z / cell) * cell)
	_counts = Vector2i(maxi(int(ceilf((bounds.end.x - _origin.x) / side)), 1), maxi(int(ceilf((bounds.end.z - _origin.z) / side)), 1))
	var height := bounds.size.y + 2.0

	for tz in _counts.y:
		for tx in _counts.x:
			_tiles.append(AABB(_origin + Vector3(tx * side, 0.0, tz * side), Vector3(side, height, side)))

	tile_cut = side
	tiles_cut = _tiles.size()
	DotLog.info(LOG, "navigation bake: the map is baked in tiles", {
		"extent": "%.0fx%.0f m" % [bounds.size.x, bounds.size.z], "cells": grid_cells(bounds.size, cell),
		"tile": snappedf(side, 0.001), "tiles": "%dx%d" % [_counts.x, _counts.y], "border": snappedf(pad, 0.001)})
	return DotResult.success(_tiles.size())


## A copy of [member mesh]'s settings that bakes [param box] and a border round it.
func _tile_mesh(box: AABB) -> NavigationMesh:
	var part: NavigationMesh = mesh.duplicate()
	var pad := border()
	part.border_size = pad
	part.filter_baking_aabb = AABB(box.position - Vector3(pad, 0.0, pad), box.size + Vector3(2.0 * pad, 0.0, 2.0 * pad))
	return part


## Joins the baked [param parts] into [member mesh] and takes it in.
func _joined(parts: Array[NavigationMesh]) -> DotResult:
	var began := Time.get_ticks_usec()
	var vertices := PackedVector3Array()
	var tris := PackedInt32Array()

	for part in parts:
		var base := vertices.size()
		vertices.append_array(part.get_vertices())

		for p in part.get_polygon_count():
			var polygon := part.get_polygon(p)
			for k in range(1, polygon.size() - 1):
				tris.append(base + polygon[0])
				tris.append(base + polygon[k])
				tris.append(base + polygon[k + 1])

	var seams := _stitch(vertices, tris)
	var used := PackedInt32Array()
	used.resize(vertices.size())
	used.fill(-1)
	var kept := PackedVector3Array()

	for i in tris.size():
		var v := tris[i]
		if used[v] < 0:
			used[v] = kept.size()
			kept.append(vertices[v])
		tris[i] = used[v]

	mesh.clear_polygons()
	mesh.vertices = kept

	for t in range(0, tris.size(), 3):
		mesh.add_polygon(PackedInt32Array([tris[t], tris[t + 1], tris[t + 2]]))

	DotLog.info(LOG, "navigation bake: tiles joined", {"tiles": parts.size(), "polygons": tris.size() / 3,
		"vertices": kept.size(), "seam_splits": seams, "join_ms": snappedf((Time.get_ticks_usec() - began) / 1000.0, 0.1)})
	return _take_in()


## Welds the vertices on the tile lines and splits each seam edge at the other side's vertices, so
## the tiles share their edges. Returns how many triangles were split.
func _stitch(vertices: PackedVector3Array, tris: PackedInt32Array) -> int:
	var side := tile_cut
	var near := mesh.cell_size * 0.25
	var rise := maxf(mesh.agent_max_climb, mesh.cell_height * 2.0)
	var count := vertices.size()
	var rep := PackedInt32Array()
	rep.resize(count)
	# Per vertex, the x line and z line it is on, -1 for none.
	var on_x := PackedInt32Array()
	var on_z := PackedInt32Array()
	on_x.resize(count)
	on_z.resize(count)
	var lines_x: Dictionary = {}
	var lines_z: Dictionary = {}

	for i in count:
		rep[i] = i
		var v := vertices[i]
		on_x[i] = _line_of(v.x - _origin.x, side, near, _counts.x)
		on_z[i] = _line_of(v.z - _origin.z, side, near, _counts.y)
		if on_x[i] >= 0:
			lines_x.get_or_add(on_x[i], []).append(i)
		if on_z[i] >= 0:
			lines_z.get_or_add(on_z[i], []).append(i)

	# Weld: along each line, the vertices in one cell and at one height become one (a corner is on two lines).
	for line: int in lines_x:
		_weld(lines_x[line], vertices, rep, 2, mesh.cell_size, rise)

	for line: int in lines_z:
		_weld(lines_z[line], vertices, rep, 0, mesh.cell_size, rise)

	var sorted_x: Dictionary = {}
	var sorted_z: Dictionary = {}

	for line: int in lines_x:
		sorted_x[line] = _line_list(lines_x[line], vertices, rep, 2)

	for line: int in lines_z:
		sorted_z[line] = _line_list(lines_z[line], vertices, rep, 0)

	for i in tris.size():
		tris[i] = _root_of(rep, tris[i])

	return _split_seams(vertices, tris, on_x, on_z, sorted_x, sorted_z, rise)


## Splits each triangle edge along a tile line at the line's other vertices inside it. Returns the splits.
func _split_seams(vertices: PackedVector3Array, tris: PackedInt32Array, on_x: PackedInt32Array, on_z: PackedInt32Array,
		sorted_x: Dictionary, sorted_z: Dictionary, rise: float) -> int:
	# Split: a triangle's edge along a line gains every vertex of the line strictly inside it at its height.
	var splits := 0
	var out := PackedInt32Array()
	var work: Array[PackedInt32Array] = []

	for t in range(0, tris.size(), 3):
		work.append(PackedInt32Array([tris[t], tris[t + 1], tris[t + 2]]))

	while not work.is_empty():
		var tri: PackedInt32Array = work.pop_back()
		var split := false

		# A sliver whose two corners were welded into one point has no floor left.
		if tri[0] == tri[1] or tri[1] == tri[2] or tri[0] == tri[2]:
			continue

		for e in 3:
			var a := tri[e]
			var b := tri[(e + 1) % 3]
			var c := tri[(e + 2) % 3]
			var inner := PackedInt32Array()

			if on_x[a] >= 0 and on_x[a] == on_x[b] and on_x[c] != on_x[a]:
				inner = _between(sorted_x.get(on_x[a], []), vertices, a, b, 2, rise)
			elif on_z[a] >= 0 and on_z[a] == on_z[b] and on_z[c] != on_z[a]:
				inner = _between(sorted_z.get(on_z[a], []), vertices, a, b, 0, rise)

			if inner.is_empty():
				continue

			var chain := PackedInt32Array([a])
			chain.append_array(inner)
			chain.append(b)
			for k in chain.size() - 1:
				work.append(PackedInt32Array([chain[k], chain[k + 1], c]))
			splits += 1
			split = true
			break

		if not split:
			out.append_array(tri)

	tris.resize(out.size())
	for i in out.size():
		tris[i] = out[i]

	return splits


## The tile line [param offset] (from the grid's origin) is on, -1 for none or the map's outer edge.
static func _line_of(offset: float, side: float, near: float, tiles: int) -> int:
	var line := roundi(offset / side)
	return line if line > 0 and line < tiles and absf(offset - line * side) <= near else -1


static func _root_of(rep: PackedInt32Array, i: int) -> int:
	while rep[i] != i:
		i = rep[i]
	return i


## Welds the [param members] of one line: those in one [param cell] along axis [param along] and within [param rise] of each other's height become one. The cell is the
## navigation map's own edge-merge cell (its cell size), so no two seam vertices are left for the map to read as one point: the detail mesh puts its edge samples at different
## places on the two sides of a seam, and two of them a few centimetres apart would otherwise be "more than 2 edges in one rasterization space".
static func _weld(members: Array, vertices: PackedVector3Array, rep: PackedInt32Array, along: int, cell: float, rise: float) -> void:
	members.sort_custom(func(p: int, q: int) -> bool:
		var cp := floori(vertices[p][along] / cell)
		var cq := floori(vertices[q][along] / cell)
		return cp < cq or (cp == cq and vertices[p].y < vertices[q].y))

	var at := 0

	while at < members.size():
		# The run of vertices in one cell of the line, low to high.
		var run_end := at + 1
		var run_cell := floori(vertices[members[at]][along] / cell)
		while run_end < members.size() and floori(vertices[members[run_end]][along] / cell) == run_cell:
			run_end += 1

		var first: int = members[at]

		for k in range(at + 1, run_end):
			var i: int = members[k]
			if absf(vertices[i].y - vertices[first].y) > rise:
				first = i
				continue
			var ri := _root_of(rep, i)
			var rf := _root_of(rep, first)
			if ri != rf:
				rep[ri] = rf

		at = run_end


## The welded vertices of a line, each once, sorted along axis [param along].
static func _line_list(members: Array, vertices: PackedVector3Array, rep: PackedInt32Array, along: int) -> Array:
	var seen: Dictionary = {}
	for i: int in members:
		seen[_root_of(rep, i)] = true
	var unique: Array = seen.keys()
	unique.sort_custom(func(p: int, q: int) -> bool: return vertices[p][along] < vertices[q][along])
	return unique


## The welded vertices of a line strictly between [param a] and [param b] at the edge's height, in order from a.
static func _between(line: Array, vertices: PackedVector3Array, a: int, b: int, along: int, rise: float) -> PackedInt32Array:
	var found := PackedInt32Array()
	var from: float = vertices[a][along]
	var to: float = vertices[b][along]
	var lo := minf(from, to)
	var hi := maxf(from, to)

	if hi - lo <= 2.0 * SPLIT_EPSILON:
		return found

	# First vertex past lo (binary search; the line is sorted along).
	var left := 0
	var right := line.size()
	while left < right:
		var mid := (left + right) >> 1
		if vertices[line[mid]][along] <= lo + SPLIT_EPSILON:
			left = mid + 1
		else:
			right = mid

	for k in range(left, line.size()):
		var m: int = line[k]
		var d: float = vertices[m][along]
		if d >= hi - SPLIT_EPSILON:
			break
		if m == a or m == b:
			continue
		var y := lerpf(vertices[a].y, vertices[b].y, (d - from) / (to - from))
		if absf(vertices[m].y - y) <= rise:
			found.append(m)

	if from > to:
		found.reverse()

	return found
