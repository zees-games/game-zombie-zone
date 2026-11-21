extends RefCounted
## The built-in practice street, split out of zz_catalogue.gd (which keeps `practice()` and `practice_toys`).

const ZzMapDoc := preload("zz_map_doc.gd")


## One street at night, from a safe room to a safe room, written here so a server with no map
## directory (a fresh clone, a suite) has a map whose every number is in front of the suites:
## start room x -5..5, z -14..-6; street x -9..9, z -6..80, y 0, alleys at z 14..18 and 54..58;
## the gate `barrier` closes it at z 40 until the switch at (6.5, 1, 36) is held; end room z 80..90.
static func build(toys: Array, id: StringName, channel: String) -> Dictionary:
	var source := {
		"format": ZzMapDoc.FORMAT,
		"kind": ZzMapDoc.KIND,
		"id": String(id),
		"name": "Practice Street",
		"author": "game-zombie-zone",
		"blurb": "One street at night. Get from one shelter to the other.",
		"mode": ZzMapDoc.EXODUS,
		"kill_y": -20.0,
		"environment": {
			"sky_top": [0.02, 0.025, 0.05], "sky_horizon": [0.08, 0.08, 0.11], "ground": [0.03, 0.03, 0.03],
			"sun_pitch": -40.0, "sun_yaw": 140.0, "sun_energy": 0.12, "sun_colour": [0.6, 0.7, 1.0],
			"ambient": [0.35, 0.38, 0.5], "ambient_energy": 0.22, "fog": 0.025,
		},
		"boxes": _practice_boxes(),
		"props": _practice_props(),
		# No physics props (toys) of its own: only prop hunt, murder mystery, hide n seek and
		# Playlot keep them. Tests set practice_toys of ZzCatalogue.
		"toys": toys.duplicate(true),
		"lights": _practice_lights(),
	}
	source.merge(_practice_layout())

	var normalised := ZzMapDoc.validate(source)

	if not normalised.ok:
		GSLog.error(channel, "the built-in practice street is refused", {"why": normalised.error.message})
		return {}

	return normalised.value


static func _practice_boxes() -> Array:
	var boxes: Array = []
	var h := 6.0
	# The start room: brick, a doorway onto the street at x -1.2..1.2.
	boxes.append({"at": [0.0, -0.1, -10.0], "size": [10.4, 0.2, 8.4], "mat": "tile"})
	boxes.append({"at": [0.0, 3.1, -10.0], "size": [10.4, 0.2, 8.4], "mat": "ceiling"})
	boxes.append({"at": [0.0, 1.5, -14.2], "size": [10.4, 3.0, 0.2], "mat": "brick"})
	boxes.append({"at": [-5.2, 1.5, -10.0], "size": [0.2, 3.0, 8.4], "mat": "brick"})
	boxes.append({"at": [5.2, 1.5, -10.0], "size": [0.2, 3.0, 8.4], "mat": "brick"})
	boxes.append({"at": [-3.2, 1.5, -5.9], "size": [4.0, 3.0, 0.2], "mat": "brick"})
	boxes.append({"at": [3.2, 1.5, -5.9], "size": [4.0, 3.0, 0.2], "mat": "brick"})
	boxes.append({"at": [0.0, 2.6, -5.9], "size": [2.4, 0.8, 0.2], "mat": "brick"})
	# The start room's frontage closed off either side, out to the street's buildings: the
	# first smoke run had a stand-in walk round the room's corner and fall out of the map.
	boxes.append({"at": [-7.15, h * 0.5, -6.1], "size": [3.9, h, 0.2], "mat": "brick"})
	boxes.append({"at": [7.15, h * 0.5, -6.1], "size": [3.9, h, 0.2], "mat": "brick"})
	boxes.append({"at": [0.0, h * 0.5 + 1.5, -6.1], "size": [10.4, h - 3.0, 0.2], "mat": "brick"})
	# The street and its pavements.
	boxes.append({"at": [0.0, -0.1, 37.0], "size": [12.0, 0.2, 86.0], "mat": "asphalt"})
	boxes.append({"at": [-7.5, -0.1, 37.0], "size": [3.0, 0.2, 86.0], "mat": "sidewalk"})
	boxes.append({"at": [7.5, -0.1, 37.0], "size": [3.0, 0.2, 86.0], "mat": "sidewalk"})
	# The buildings either side, broken by an alley each side at z 14..18 and 54..58.
	for side in [-1.0, 1.0]:
		for span in [[-6.0, 14.0], [18.0, 54.0], [58.0, 80.0]]:
			var length: float = span[1] - span[0]
			boxes.append({"at": [side * 9.1, h * 0.5, (span[0] + span[1]) * 0.5], "size": [0.2, h, length], "mat": "brick",
				"tint": [0.85, 0.8, 0.78] if side < 0.0 else [0.75, 0.75, 0.8]})
		for alley in [16.0, 56.0]:
			boxes.append({"at": [side * 12.5, -0.1, alley], "size": [7.0, 0.2, 4.0], "mat": "concrete"})
			boxes.append({"at": [side * 12.5, h * 0.5, alley - 2.1], "size": [7.0, h, 0.2], "mat": "concrete"})
			boxes.append({"at": [side * 12.5, h * 0.5, alley + 2.1], "size": [7.0, h, 0.2], "mat": "concrete"})
			boxes.append({"at": [side * 16.1, h * 0.5, alley], "size": [0.2, h, 4.4], "mat": "concrete"})
	# The far end: a wall across the street, with the end room's door in it.
	boxes.append({"at": [-5.2, h * 0.5, 80.0], "size": [7.8, h, 0.2], "mat": "brick"})
	boxes.append({"at": [5.2, h * 0.5, 80.0], "size": [7.8, h, 0.2], "mat": "brick"})
	boxes.append({"at": [0.0, 4.0, 80.0], "size": [2.6, 4.0, 0.2], "mat": "brick"})
	# The end room.
	boxes.append({"at": [0.0, -0.1, 85.0], "size": [10.4, 0.2, 10.4], "mat": "tile"})
	boxes.append({"at": [0.0, 3.1, 85.0], "size": [10.4, 0.2, 10.4], "mat": "ceiling"})
	boxes.append({"at": [0.0, 1.5, 90.2], "size": [10.4, 3.0, 0.2], "mat": "brick"})
	boxes.append({"at": [-5.2, 1.5, 85.0], "size": [0.2, 3.0, 10.4], "mat": "brick"})
	boxes.append({"at": [5.2, 1.5, 85.0], "size": [0.2, 3.0, 10.4], "mat": "brick"})
	# The barrier across the street at z 40: a gate the switch opens.
	boxes.append({"at": [0.0, 1.6, 40.0], "size": [18.0, 3.2, 0.4], "mat": "metal", "tint": [0.85, 0.6, 0.2], "gate": "barrier"})
	return boxes


static func _practice_props() -> Array:
	return [
		{"id": "cars_sedan", "at": [-3.5, 0.0, 6.0], "yaw": 10.0},
		{"id": "cars_taxi", "at": [3.8, 0.0, 22.0], "yaw": 175.0},
		{"id": "cars_police", "at": [-2.0, 0.0, 31.0], "yaw": 60.0},
		{"id": "cars_ambulance", "at": [4.0, 0.0, 48.0], "yaw": 190.0},
		{"id": "cars_van", "at": [-3.8, 0.0, 64.0], "yaw": -8.0},
		{"id": "urban_detail-dumpster-closed", "at": [-7.6, 0.0, 10.0], "yaw": 90.0},
		{"id": "urban_detail-dumpster-open", "at": [7.6, 0.0, 44.0], "yaw": -90.0},
		{"id": "roads_construction-barrier", "at": [2.0, 0.0, 38.4]},
		{"id": "roads_construction-cone", "at": [-1.5, 0.0, 37.8]},
		{"id": "survival_barrel", "at": [7.6, 0.0, 26.0]},
		{"id": "survival_barrel", "at": [7.2, 0.0, 26.9]},
		{"id": "urban_detail-light-single", "at": [-8.3, 0.0, 2.0], "yaw": 90.0},
		{"id": "urban_detail-light-single", "at": [8.3, 0.0, 20.0], "yaw": -90.0},
		{"id": "urban_detail-light-single", "at": [-8.3, 0.0, 38.0], "yaw": 90.0},
		{"id": "urban_detail-light-single", "at": [8.3, 0.0, 58.0], "yaw": -90.0},
		{"id": "urban_detail-light-single", "at": [-8.3, 0.0, 74.0], "yaw": 90.0},
		{"id": "furniture_table", "at": [-3.0, 0.0, -12.5]},
		{"id": "furniture_table", "at": [3.0, 0.0, -12.5]},
		{"id": "furniture_table", "at": [0.0, 0.0, 88.5]},
		{"id": "graveyard_debris", "at": [1.0, 0.0, 15.0]},
		{"id": "graveyard_debris-wood", "at": [-5.0, 0.0, 52.0]},
	]


static func _practice_lights() -> Array:
	var lights: Array = [{"at": [0.0, 2.8, -10.0], "range": 9.0, "energy": 1.2, "colour": [1.0, 0.92, 0.75]},
		{"at": [0.0, 2.8, 85.0], "range": 9.0, "energy": 1.2, "colour": [1.0, 0.92, 0.75]}]

	for z in [2.0, 20.0, 38.0, 58.0, 74.0]:
		lights.append({"at": [-6.5 if int(z) % 4 == 2 else 6.5, 3.6, z], "range": 14.0, "energy": 1.4, "colour": [1.0, 0.78, 0.45]})
	return lights


## The map's spawns, areas, route, nav, items, spawners, objectives: the part of the document with no loops in it.
static func _practice_layout() -> Dictionary:
	return {
		"spawns": {"survivors": [
			{"at": [-2.0, 0.1, -10.5], "yaw": 180.0}, {"at": [2.0, 0.1, -10.5], "yaw": 180.0},
			{"at": [-2.0, 0.1, -8.5], "yaw": 180.0}, {"at": [2.0, 0.1, -8.5], "yaw": 180.0},
		]},
		"areas": {
			"start": [{"min": [-5.0, -0.5, -14.0], "max": [5.0, 3.0, -6.0]}],
			"end": [{"min": [-5.0, -0.5, 80.2], "max": [5.0, 3.0, 90.0]}],
		},
		"route": [[0.0, 0.0, -10.0], [0.0, 0.0, -4.0], [0.0, 0.0, 40.0], [0.0, 0.0, 85.0]],
		"nav": {
			"spacing": 1.0, "clearance": 0.35,
			"floors": [[-4.9, -13.9, 4.9, -6.1, 0.0], [-1.1, -6.3, 1.1, -5.5, 0.0], [-8.9, -6.0, 8.9, 79.9, 0.0],
				[-1.2, 79.7, 1.2, 80.4, 0.0], [-4.9, 80.2, 4.9, 89.9, 0.0],
				[-16.0, 14.1, -9.0, 17.9, 0.0], [9.0, 14.1, 16.0, 17.9, 0.0],
				[-16.0, 54.1, -9.0, 57.9, 0.0], [9.0, 54.1, 16.0, 57.9, 0.0]],
			"links": [],
		},
		"items": [
			{"kind": "weapon", "id": "zz_smg", "at": [-3.0, 0.82, -12.5]},
			{"kind": "weapon", "id": "zz_shotgun", "at": [-2.4, 0.82, -12.5]},
			{"kind": "weapon", "id": "zz_m4", "at": [3.0, 0.82, -12.5]},
			{"kind": "ammo", "at": [3.6, 0.82, -12.5]},
			{"kind": "pills", "at": [-3.6, 0.82, -12.5]},
			{"kind": "box", "id": "mystery", "at": [-6.8, 0.0, 20.0]},
			{"kind": "ammo", "at": [7.0, 0.0, 34.0]},
			{"kind": "throwable", "id": "zz_frag", "at": [6.8, 0.0, 33.0]},
			{"kind": "medkit", "at": [0.6, 0.82, 88.5]},
			{"kind": "ammo", "at": [-0.6, 0.82, 88.5]},
		],
		"spawners": [
			{"id": "wall", "at": [-1.8, 0.82, -12.5], "pool": "wall_guns", "respawn": 45, "max": 1},
			{"id": "supplies", "at": [0.0, 0.82, 88.5]},
			{"id": "wallbuy", "at": [2.4, 0.82, -12.5], "pool": "wall_guns", "respawn": 0, "data": {"tier_price": true}},
		],
		"traders": [{"id": "trader", "at": [-3.0, 0.82, -12.5], "slots": 3, "restock": 90.0}],
		"objectives": [
			{"id": "barrier", "kind": "use", "at": [6.5, 1.0, 36.0], "label": "Lower the barrier", "seconds": 2.0,
				"holdout": 40.0, "opens": ["barrier"], "message": "The barrier is coming down. Hold them off!",
				"prop": "lever", "yaw": -90.0},
		],
		"sleepers": [[-7.4, 0.0, 26.0, 90.0]],
		"zombie_spawns": [[-14.0, 0.0, 16.0], [14.0, 0.0, 16.0], [-14.0, 0.0, 56.0], [14.0, 0.0, 56.0]],
	}
