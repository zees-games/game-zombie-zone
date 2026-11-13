extends RefCounted

const ZzMapDoc := preload("zz_map_doc.gd")
const ZzPaths := preload("zz_paths.gd")

## Every map this server can play, and which one is next.
##
## [b]Two sources, and the built-in one is a floor rather than a feature.[/b] The maps are
## documents read from [member ZzConfig.map_directory] — `maps/`, a link to zombie-zone-maps,
## in a checkout; a directory in a delivered pack. A server whose directory is missing or empty
## still has [method practice], so it plays rather than refusing to start.
##
## [b]A server reads documents; a client never does.[/b] The map travels in its own event (see
## [ZzMapDoc]), so nothing here runs on a connected client.

const CHANNEL := "zz.catalogue"

const PRACTICE := &"zz_practice"

## Internal-use-only originals (`*_orig` ids) unzipped into the user folder; never shipped.
const USER_MAPS := "user://maps"

## id -> normalised document.
var maps: Dictionary = {}

## Where a parsed document is kept between runs ("" keeps none). Reading and normalising the ~40
## documents was 1.5 s at start; a binary copy keyed on the file's size and time and on the
## normaliser's own source loads in a fraction of it, and a changed file or a changed [ZzMapDoc]
## parses again by itself.
var doc_cache_dir: String = "user://map_docs"
var _validator_key: String = ""

## Files that were refused, with why. What `zz_maps` prints, so a mapper can see it.
var refused: Dictionary = {}

var _order: Array[StringName] = []

## Whether a directory's documents are read as a name and a mode only, and a map's whole
## document only when it is needed ([method doc]). The browser's memory cannot hold 47 parsed
## documents (zombie-zone-maps 0.1.16 is 53 MiB of JSON and ran the wasm heap out), and a
## round plays one map. Off natively, where every document is read up front as it always was.
var lazy: bool = OS.has_feature("web")

## id -> the file a stub was peeked from, and the stubs themselves (what [member maps] holds
## for a map whose document is not read), so a map that was read can be put back.
var _files: Dictionary = {}
var _stubs: Dictionary = {}
const PEEK_BYTES := 4096

## The server's maps.yml, or null when there is none (every map rotates, as it always did).
## dot-map's rotation file speaks DotMapDef; this catalogue holds map documents, so [member _defs]
## mirrors the ids and the file marks `in_rotation` on the mirror. See [method rotating].
var rotation_file: DotMapRotationFile = null
var _defs: DotMapCatalogue = DotMapCatalogue.new()
var _rotation: DotMapRotation = DotMapRotation.of(_defs)
var _next: int = 0

# --- Workshop maps ----------------------------------------------------------
# A pack's `map` entry names a ZzMapDoc DOCUMENT in `scene` (the same JSON as maps/), so a
# subscribed map goes through exactly the validation, nav graph, safe rooms and waves of the
# game's own. Online the index answers for its session and lists none.
## id -> the directory its document was read from (its maps pack's `hulls/` is beside it).
var roots: Dictionary = {}
var _index: DotContentIndex = null
var _kinds: PackedStringArray = PackedStringArray()
var _content_ids: Dictionary = {}    # id -> the document this follower added
var _content_titles: Dictionary = {} # id -> pack title
var _content_docs: Dictionary = {}   # entry key -> document ({} when refused), read once
var _content_keys: Dictionary = {}   # id -> the entry key of a subscribed map held as a stand-in


## Reads every document under [param directory] (relative to this game's root), and adds the
## one built in. Forgets anything read before.
func load_from(directory: String) -> int:
	maps.clear()
	roots.clear()
	refused.clear()
	_files.clear()
	_stubs.clear()
	_content_ids.clear()
	_content_docs.clear()
	_content_keys.clear()

	_add(practice(), "built-in")

	var root := ZzPaths.rebase("res://" + directory.trim_prefix("res://").trim_prefix("/"))
	var loaded := _read_directory(root)
	# The game's own maps win an id; the user folder only adds.
	loaded += _read_directory(USER_MAPS)
	_rebuild_order()
	sync_content()

	DotLog.info(CHANNEL, "maps loaded", {"maps": maps.size(), "refused": refused.size()})
	return loaded


## Adds every document under [param root], an absolute `res://` path: a maps pack mounted
## beside the game, at its OWN prefix, which this game's rebasing would put somewhere else.
func add_directory(root: String) -> int:
	var loaded := _read_directory(root)
	_rebuild_order()
	DotLog.info(CHANNEL, "maps added", {"from": root, "read": loaded, "maps": maps.size()})
	return loaded


func _read_directory(root: String) -> int:
	var dir := DirAccess.open(root)

	if dir == null:
		DotLog.info(CHANNEL, "no map directory here", {"looked_at": root})
		return 0

	var files := PackedStringArray()

	for file in dir.get_files():
		if file.ends_with(".json"):
			files.append(file)

	files.sort()
	var loaded := 0

	for file in files:
		if lazy:
			var stub := _peek(root.path_join(file))

			if not stub.is_empty() and _add(stub, file):
				var stub_id := StringName(str(stub["id"]))
				roots[stub_id] = root
				_files[stub_id] = root.path_join(file)
				_stubs[stub_id] = stub
				loaded += 1
				continue

		var cached := _cache_read(root, file)

		if not cached.is_empty() and _add(cached, file):
			roots[StringName(str(cached["id"]))] = root
			loaded += 1
			continue

		var text := FileAccess.get_file_as_string(root.path_join(file))

		if text.is_empty():
			refused[file] = "empty or unreadable"
			continue

		var parsed := ZzMapDoc.parse_json(text, file)

		if not parsed.ok:
			refused[file] = parsed.error.message
			DotLog.warn(CHANNEL, "a map was refused", {
				"file": file, "why": parsed.error.message, "detail": parsed.error.detail,
			})
			continue

		if _add(parsed.value, file):
			roots[StringName(str(parsed.value["id"]))] = root
			loaded += 1
			_cache_write(root, file, parsed.value)

	return loaded


## What the cache holds for [param file] under [param root], or {} when it holds nothing current.
func _cache_read(root: String, file: String) -> Dictionary:
	var path := _cache_path(root, file)

	if path == "" or not FileAccess.file_exists(path):
		return {}

	var f := FileAccess.open(path, FileAccess.READ)

	if f == null:
		return {}

	var head: Variant = f.get_var()

	if typeof(head) != TYPE_STRING or head != _cache_key(root, file):
		return {}

	var doc: Variant = f.get_var()
	return doc if typeof(doc) == TYPE_DICTIONARY else {}


func _cache_write(root: String, file: String, doc: Dictionary) -> void:
	var path := _cache_path(root, file)

	if path == "":
		return

	DirAccess.make_dir_recursive_absolute(doc_cache_dir)
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)

	if f == null:
		return

	f.store_var(_cache_key(root, file))
	f.store_var(doc)
	f.close()
	var _renamed := DirAccess.rename_absolute(path + ".tmp", path)


func _cache_path(root: String, file: String) -> String:
	if doc_cache_dir == "":
		return ""

	return doc_cache_dir.path_join("%s_%s.bin" % [root.md5_text().substr(0, 8), file])


## The file's size and time, with the normaliser's source: either changing makes the copy stale.
func _cache_key(root: String, file: String) -> String:
	if _validator_key == "":
		_validator_key = FileAccess.get_md5((ZzMapDoc as Script).resource_path) + FileAccess.get_md5(get_script().resource_path)

	var src := root.path_join(file)
	var f := FileAccess.open(src, FileAccess.READ)
	var size := f.get_length() if f != null else -1
	return "%d:%d:%s" % [size, FileAccess.get_modified_time(src), _validator_key]


## The head of a document, as a stand-in map: id, name, mode, author, blurb, survivors, flagged
## `_stub`. Empty when the head does not read as a map document, which is then read whole (and
## refused with its reason) as ever. The builder writes these keys first; the full document
## is what [method doc] reads.
func _peek(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return {}

	var head := file.get_buffer(PEEK_BYTES).get_string_from_utf8()
	var id := _peek_string(head, "id")
	var kind := _peek_string(head, "kind")

	if id == "" or kind != ZzMapDoc.KIND or not head.contains("\"format\": %d" % ZzMapDoc.FORMAT):
		return {}

	var survivors := RegEx.create_from_string("\"survivors\"\\s*:\\s*(\\d+)").search(head)
	var mode := _peek_string(head, "mode")
	return {
		"id": id, "name": _peek_string(head, "name", id), "mode": mode if mode != "" else ZzMapDoc.EXODUS,
		"author": _peek_string(head, "author"), "blurb": _peek_string(head, "blurb"),
		"survivors": int(survivors.get_string(1)) if survivors != null else 0,
		"props": [], "_stub": true,
	}


func _peek_string(head: String, key: String, fallback: String = "") -> String:
	var found := RegEx.create_from_string("\"%s\"\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\")" % key).search(head)

	if found == null:
		return fallback

	var value: Variant = JSON.parse_string(found.get_string(1))
	return str(value) if value != null else fallback


## The whole document of map [param id]: what [member maps] holds, or, for a stand-in, the file
## read now. Only one such document is kept: reading another puts the last back to its stand-in,
## so the catalogue's cost is a map's, not the pack's. Empty when there is no such map or its
## document has gone bad since it was peeked.
func doc(id: StringName) -> Dictionary:
	var held: Dictionary = maps.get(id, {})

	if not held.get("_stub", false):
		return held

	for other: StringName in _stubs:
		if other != id and maps.has(other) and not maps[other].get("_stub", false):
			_hold(other, _stubs[other])

	var parsed := ZzMapDoc.parse_json(FileAccess.get_file_as_string(str(_files[id])), str(_files[id]))

	if not parsed.ok:
		refused[str(_files[id]).get_file()] = parsed.error.message
		DotLog.warn(CHANNEL, "a map was refused", {"file": _files[id], "why": parsed.error.message})
		return {}

	_hold(id, parsed.value)
	return parsed.value


## Makes [param document] what the catalogue holds for [param id]; a subscribed map's entry
## follows, so [method sync_content] still finds the document it added.
func _hold(id: StringName, document: Dictionary) -> void:
	maps[id] = document

	if _content_keys.has(id):
		_content_docs[_content_keys[id]] = document

		if _content_ids.has(id):
			_content_ids[id] = document


## Follows [param index]: subscribed (solo) map entries of an accepted kind become maps here, for
## the index's CURRENT session only. The game's own ids always win.
func follow_content(index: DotContentIndex, accepted_kinds: PackedStringArray) -> void:
	_index = index
	_kinds = accepted_kinds
	sync_content()


## Re-reads the index into [member maps]. Called from [method playable] rather than on a signal,
## because a session change announces nothing and a stale list is worse than a loop over a
## handful of entries.
func sync_content() -> void:
	var wanted: Dictionary = {}

	if _index != null:
		for entry in _index.entries(&"map"):
			var kind := str(entry.raw.get("map_kind", ""))

			if entry.id == "" or kind == "" or not (_kinds.has("*") or _kinds.has(kind)):
				continue

			var doc := _content_doc(entry)

			if doc.is_empty():
				continue

			var id := StringName(str(doc["id"]))

			if not wanted.has(id):
				wanted[id] = doc
				_content_titles[id] = entry.pack_title

	var changed := false

	# Only a map this follower added is taken out: load_from may since have put the game's own
	# under the id.
	for id: StringName in _content_ids:
		if maps.has(id) and is_same(maps[id], _content_ids[id]) \
				and not (wanted.has(id) and is_same(wanted[id], _content_ids[id])):
			var _gone := maps.erase(id)
			changed = true

	_content_ids.clear()

	for id: StringName in wanted:
		if maps.has(id):
			if is_same(maps[id], wanted[id]):
				_content_ids[id] = wanted[id]
			continue

		maps[id] = wanted[id]
		_content_ids[id] = wanted[id]
		changed = true

	if changed:
		_rebuild_order()


## Whether [param id] is a subscribed pack map rather than one of the game's own.
func is_content(id: StringName) -> bool:
	return _content_ids.has(id)


## The name a menu shows: "Name [Pack]" for a pack's map, the document's name otherwise.
func display_name(id: StringName) -> String:
	var doc: Dictionary = maps.get(id, {})
	var shown := str(doc.get("name", id))
	var title := str(_content_titles.get(id, "")) if _content_ids.has(id) else ""
	return "%s [%s]" % [shown, title] if title != "" else shown


func _content_doc(entry: DotContentEntry) -> Dictionary:
	if _content_docs.has(entry.key):
		return _content_docs[entry.key]

	var file := entry.path("scene")

	if lazy and file != "":
		var stub := _peek(file)

		if not stub.is_empty() and str(stub["id"]) == entry.id:
			var stub_id := StringName(entry.id)

			if not _files.has(stub_id):  # the game's own map under this id wins, and keeps its file
				_files[stub_id] = file
				_stubs[stub_id] = stub
				_content_keys[stub_id] = entry.key

			_content_docs[entry.key] = stub
			return stub

	var text := FileAccess.get_file_as_string(file) if file != "" else ""
	var doc: Dictionary = {}

	if text.is_empty():
		refused[entry.key] = "The pack's map document is empty or unreadable: %s" % file
	else:
		var parsed := ZzMapDoc.parse_json(text, file)

		if parsed.ok and str(parsed.value["id"]) != entry.id:
			# The ballot names the entry's id and the map menu the document's: two names for one
			# map would offer a choice the catalogue cannot find.
			refused[entry.key] = "The pack's entry id is %s but its document's id is %s." % [entry.id, parsed.value["id"]]
		elif parsed.ok:
			doc = parsed.value
		else:
			refused[entry.key] = parsed.error.message
			DotLog.warn(CHANNEL, "a subscribed map was refused", {
				"key": entry.key, "why": parsed.error.message, "detail": parsed.error.detail,
			})

	_content_docs[entry.key] = doc
	return doc


func _add(doc: Dictionary, origin: String) -> bool:
	var id := StringName(str(doc["id"]))

	if maps.has(id) and origin != "built-in" and id != PRACTICE:
		refused[origin] = "a second map with id %s" % id
		return false

	maps[id] = doc
	return true


func _rebuild_order() -> void:
	_order.clear()

	for id: StringName in maps:
		_order.append(id)

	_order.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	_next = 0


## The ids a server may draw from, after [param allowed] (empty is all). The built-in practice
## map drops out once there is anything else.
func playable(allowed: PackedStringArray) -> Array[StringName]:
	sync_content()
	var out: Array[StringName] = []

	for id in _order:
		if allowed.is_empty() or allowed.has(String(id)):
			out.append(id)

	if allowed.is_empty() and out.size() > 1:
		out.erase(PRACTICE)

	return out


## Whether maps.yml names rotations, so that it (not [code]zz_shuffle[/code]) orders the maps.
func has_rotation_file() -> bool:
	return rotation_file != null and rotation_file.has_rotations()


## Brings the mirror up to date with [member maps] and lets the file mark who rotates.
## Without a file every map is in (the practice street only when it is all there is), which is
## what [method playable] always did.
func apply_rotation(allowed: PackedStringArray = PackedStringArray()) -> void:
	sync_content()
	var seen := {}

	for id: StringName in _order:
		seen[id] = true
		var def := _defs.get_map(id)

		if def == null:
			def = DotMapDef.new()
			def.id = id
			def.scene_path = "zz:%s" % id
			def.display_name = display_name(id)
			var _added := _defs.add(def)

		def.enabled = allowed.is_empty() or allowed.has(String(id))

	for def: DotMapDef in _defs.maps.duplicate():
		if not seen.has(def.id):
			var _gone := _defs.remove(def.id)

	if has_rotation_file():
		# Captures the mirror, never self: a lambda on self held by a member is a reference cycle,
		# and a RefCounted cycle leaks.
		var mirror := _defs
		rotation_file.fallback_in = func(def: DotMapDef) -> bool:
			return def.id != PRACTICE or mirror.size() == 1
		var _applied := rotation_file.apply(_rotation)
		return

	_rotation.order = []

	for def: DotMapDef in _defs.maps:
		def.in_rotation = true


## `zz_rotation <name>`: the live switch to another named rotation in the file.
func switch_rotation(rotation_name: String) -> DotResult:
	if not has_rotation_file():
		return DotResult.fail(DotError.CODE_STATE, "There is no maps.yml to switch rotations in.")

	apply_rotation()
	return rotation_file.switch(_rotation, rotation_name)


## Whether [param id] is in the active rotation. A map the catalogue does not hold is not.
func in_rotation(id: StringName) -> bool:
	if not maps.has(id):
		return false

	if not has_rotation_file():
		return true

	apply_rotation()
	var def := _defs.get_map(id)
	return def != null and def.in_rotation


## What the ballot, a nomination and the next-map draw may offer: [method playable] less the
## maps maps.yml leaves out. A map left out stays [i]playable[/i] (an admin's `zz_map` and the
## map menu load it). With no file, or a file that leaves nothing, it is [method playable].
func rotating(allowed: PackedStringArray) -> Array[StringName]:
	var every := playable(allowed)

	if not has_rotation_file():
		return every

	apply_rotation(allowed)
	var out: Array[StringName] = []

	for id in every:
		var def := _defs.get_map(id)

		if def != null and def.in_rotation:
			out.append(id)

	return out if not out.is_empty() else every


## What the rotation entry gives map [param id] (`{waves: "hard"}`), empty for a bare entry or no file.
func play_for(id: StringName) -> Dictionary:
	if not has_rotation_file():
		return {}

	apply_rotation()
	var def := _defs.get_map(id)
	return def.play if def != null else {}


## Records that [param id] was built, for the file's cooldown and cycle. Nothing without a file.
func note_played(id: StringName) -> void:
	if has_rotation_file() and maps.has(id):
		_rotation.note_played(id)


## The next map: drawn from [param stream] when shuffling, in order otherwise, and never the
## same one twice running when there is a choice. A maps.yml with rotations replaces both: its
## rotation's mode (`random` with a cooldown, or `cycle`) and written order decide.
func next_map(allowed: PackedStringArray, shuffle: bool, stream: DotRandomStream,
		previous: StringName) -> Dictionary:
	if has_rotation_file():
		apply_rotation(allowed)

		if _rotation.seed_value == 0 and stream != null:
			_rotation.seed_value = stream.next_range_i(1, 0x3fffffff)

		var chosen := _rotation.choose(0)

		if chosen != null and maps.has(chosen.id):
			return doc(chosen.id)

	var ids := rotating(allowed)

	if ids.is_empty():
		DotLog.warn(CHANNEL, "no map matches the allowed list; playing practice", {
			"allowed": ",".join(allowed),
		})
		return maps.get(PRACTICE, practice())

	var pick: StringName

	if shuffle and stream != null:
		pick = ids[stream.next_range_i(0, ids.size() - 1)]

		if pick == previous and ids.size() > 1:
			pick = ids[(ids.find(pick) + 1 + stream.next_range_i(0, ids.size() - 2)) % ids.size()]
	else:
		pick = ids[_next % ids.size()]
		_next += 1

	return doc(pick)


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray(["maps (%d)" % maps.size()])

	for id in _order:
		var doc: Dictionary = maps[id]
		lines.append("  %-22s %-28s %-8s %4d props  %s%s" % [
			id, str(doc["name"]), str(doc["mode"]), (doc["props"] as Array).size(), str(doc["author"]),
			"" if in_rotation(id) else "  (not in rotation)",
		])

	if not refused.is_empty():
		lines.append("refused (%d)" % refused.size())

		for file: String in refused:
			lines.append("  %-22s %s" % [file, refused[file]])

	return lines


# --- The one built in -------------------------------------------------------

## Tests only: loose physics props (dot-props' toys) to put on the practice street; empty in play.
static var practice_toys: Array = []


## One street at night, from a safe room to a safe room.
##
## [b]Written here rather than shipped as a file,[/b] so a server with no map directory at all
## — a fresh clone, a suite — has something to play, and the suites have a map whose every
## number is in front of them. They lean on these: the start room is x -5..5, z -14..-6; the
## street is x -9..9 from z -6 to 80 at y 0, with an alley off each side at z 14..18 and 54..58;
## a barrier (the gate `barrier`) closes the street at z 40 until the switch at (6.5, 1, 36) has
## been held out; the end room is x -5..5, z 80..90.
static func practice() -> Dictionary:
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

	var props: Array = [
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

	var lights: Array = [{"at": [0.0, 2.8, -10.0], "range": 9.0, "energy": 1.2, "colour": [1.0, 0.92, 0.75]},
		{"at": [0.0, 2.8, 85.0], "range": 9.0, "energy": 1.2, "colour": [1.0, 0.92, 0.75]}]

	for z in [2.0, 20.0, 38.0, 58.0, 74.0]:
		lights.append({"at": [-6.5 if int(z) % 4 == 2 else 6.5, 3.6, z], "range": 14.0, "energy": 1.4, "colour": [1.0, 0.78, 0.45]})

	var source := {
		"format": ZzMapDoc.FORMAT,
		"kind": ZzMapDoc.KIND,
		"id": String(PRACTICE),
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
		"boxes": boxes,
		"props": props,
		# No physics props (toys) of its own: only prop hunt, murder mystery, hide n seek and
		# the playground keep them. Tests set [member practice_toys].
		"toys": practice_toys.duplicate(true),
		"lights": lights,
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

	var normalised := ZzMapDoc.validate(source)

	if not normalised.ok:
		DotLog.error(CHANNEL, "the built-in practice street is refused", {"why": normalised.error.message})
		return {}

	return normalised.value
