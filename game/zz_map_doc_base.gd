extends RefCounted

const ZzMaterials := preload("zz_materials.gd")

const ZzFixtures := preload("zz_fixtures.gd")

## What a map IS: a JSON document, checked here before anything is built. [b]A map is a document, not a scene[/b], for mg-wipeout's reason, which every map-driven game in this family has taken since: a scene per map is content to import, to rebase inside a mounted pack and to keep in step across a server and every client; a document is a few tens of kilobytes the server reads off disk and SENDS to each client when the map changes. A client needs no map files, a server gets a new map by having a file dropped in a directory, and the two ends cannot disagree about where a wall or a chair is, because there is one copy and it travelled. [b]What is in one:[/b] boxes (the streets, the buildings, the barricades), props (cars, crates, furniture, by catalogue id), lights, where the survivors start, and how the sky looks. Then what makes it a zombie map rather than a room: [codeblock] mode "exodus" (get from the start shelter to the end one) or "survival" (hold out) survivors the team the map is built for;
## stand-ins fill to it (ZzConfig.team_from_map); unsaid (0), the server's own number areas {start: [area], end: [area]}: the safe rooms, each {min, max} route the critical path the director spawns AHEAD along, start to end nav {spacing, floors: [[x0, z0, x1, z1, y]], links: [[from xyz, to xyz]]} terrain a converted map's displacement ground (dot-map's DotMapTerrain), with the walk mask items weapons, ammo, medkits, pills and boxes lying where a mapper left them mechanics true when the document's boxes leave out the world's movers, so a global pack's lifts and doors run traders shelves of priced stock: {at, yaw?, pool?, slots?, spacing?, restock?}, the stock from the spawner config's pool spawners weapon and supply spawners (dot-weapon docs/spawners.md): {at, pool?, tags_any?, respawn?, max?...} objectives things to do on the way: press a button, hold out while the horde comes gates a box with a "gate" id is a door an objective opens sleepers where the crying one sits, waiting for somebody to come
## too close posts survival: where a team holds; stand-ins spread over them caches survival: where supplies are restocked in every breather, better each wave barricades survival: [{id, label, health}]; a box with a "barricade" id is part of one: solid, but on the zombies' ground, so they come to it and break it down day_environment survival by nights: the sky by day (the map's `environment` is its night) [/codeblock] Every length is metres, every angle degrees. A box's `at` is its CENTRE; a prop's `at` is the middle of its footprint ON the floor, so a mapper places a car by where it stands. [b]Normalised into plain arrays, never vectors.[/b] What a server encodes is what this returned, and a vector's float32 components come back out of JSON as `0.300000011920929`: twice the bytes for a map of a thousand boxes and a document whose digest moves when nothing did. Rounded to the millimetre here, once. `maps/README.md` in zombie-zone-maps is the mapper's copy of this.


## The numbers of a list as ints; anything else in it is dropped.
static func _ints(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for v: Variant in value:
			if v is int or v is float:
				out.append(int(v))
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


static func _is_id(id: String) -> bool:
	if id.is_empty() or id.length() > 48:
		return false

	for character in id:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") \
				and character != "_":
			return false

	return true
