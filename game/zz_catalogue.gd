extends RefCounted

const ZzMapDoc := preload("zz_map_doc.gd")
const ZzPaths := preload("zz_paths.gd")
const ZzPracticeStreet := preload("zz_practice_street.gd")

## Every map this server can play, and which one is next.
## [b]Two sources; the built-in one is a floor.[/b] Documents are read from [member ZzConfig.map_directory]
## (`maps/`, a link to zombie-zone-maps; a directory in a pack); with none, [method practice] plays.
## [b]A server reads documents; a client never does.[/b] The map travels in its own event ([ZzMapDoc]).

const CHANNEL := "zz.catalogue"

const PRACTICE := &"zz_practice"

## Internal-use-only originals (`*_orig` ids) unzipped into the user folder; never shipped.
const USER_MAPS := "user://maps"

## id -> normalised document.
var maps: Dictionary = {}

## Where a parsed document is kept between runs ("" keeps none). A binary copy keyed on the file's
## size and time and the normaliser's source loads in a fraction of the 1.5 s reading ~40 documents
## took; a changed file or [ZzMapDoc] parses again by itself.
var doc_cache_dir: String = "user://map_docs"
var _validator_key: String = ""

## Files that were refused, with why. What `zz_maps` prints, so a mapper can see it.
var refused: Dictionary = {}

var _order: Array[StringName] = []

## Whether documents are read as a name and a mode only, a map's whole document only when needed
## ([method doc]): the browser's memory cannot hold 47 parsed documents (53 MiB of JSON), and a
## round plays one map. Off natively, where every document is read up front.
var lazy: bool = OS.has_feature("web")

## Whether a document whose cached copy is current is held as a stand-in too (see [member lazy]):
## the copy proves it validated, so it is read whole only when played. Off: every document is
## loaded at start. Skipped when [member doc_cache_dir] is "".
var stub_from_cache: bool = true

## id -> the file a stub was peeked from, and the stubs themselves (what [member maps] holds
## for a map whose document is not read), so a map that was read can be put back.
var _files: Dictionary = {}
var _stubs: Dictionary = {}
const PEEK_BYTES := 4096

## Most JSON a cold start parses at once on the worker threads (0: every uncached document at once).
var parse_batch_bytes: int = 1 << 20

## The server's maps.yml, or null when there is none (every map rotates, as it always did).
## dot-map's rotation file speaks DotMapDef; this catalogue holds map documents, so [member _defs]
## mirrors the ids and the file marks `in_rotation` on the mirror. See [method rotating].
var rotation_file: DotMapRotationFile = null
var _defs: DotMapCatalogue = DotMapCatalogue.new()
var _rotation: DotMapRotation = DotMapRotation.of(_defs)
var _next: int = 0

# Workshop maps: a pack's `map` entry names a ZzMapDoc DOCUMENT in `scene`, so it gets the
# game's own validation, nav graph, safe rooms and waves. Online the index lists none.
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

	for batch in _batches(root, files):
		loaded += _read_batch(root, batch)

	return loaded


## [param files] in runs of at most [member parse_batch_bytes] of JSON (one file at least), so a cold
## start parses a run at a time instead of every document at once.
func _batches(root: String, files: PackedStringArray) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = [PackedStringArray()]
	var bytes := 0

	for file in files:
		var f := FileAccess.open(root.path_join(file), FileAccess.READ)
		var size := f.get_length() if f != null else 0

		if parse_batch_bytes > 0 and not out[-1].is_empty() and bytes + size > parse_batch_bytes:
			out.append(PackedStringArray())
			bytes = 0

		out[-1].append(file)
		bytes += size

	return out


func _read_batch(root: String, files: PackedStringArray) -> int:
	var loaded := 0
	var ahead := _parse_ahead(root, files)

	for file in files:
		# A cached current document was validated by this normaliser earlier, so its head stands in;
		# the whole (up to 21 MB) is read when a round needs it ([method doc]). One with no current
		# copy is read, validated and refused or cached as before.
		if lazy or (stub_from_cache and _cache_current(root, file)):
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

		var parsed: DotResult = null

		if ahead.has(file):
			parsed = ahead[file]
			var _released := ahead.erase(file)
		else:
			var text := FileAccess.get_file_as_string(root.path_join(file))
			parsed = ZzMapDoc.parse_json(text, file) if not text.is_empty() else null

		if parsed == null:
			refused[file] = "empty or unreadable"
			continue

		if not parsed.ok:
			refused[file] = parsed.error.message
			DotLog.warn(CHANNEL, "a map was refused", {
				"file": file, "why": parsed.error.message, "detail": parsed.error.detail,
			})
			continue

		if _add(parsed.value, file):
			roots[StringName(str(parsed.value["id"]))] = root
			loaded += 1

			# Every cold document held whole was 2.2 GB for 53 maps (OOM on a 2 GiB server); cached, its head will do.
			if _cache_write(root, file, parsed.value) and stub_from_cache:
				_stand_in(root, file, StringName(str(parsed.value["id"])))

	return loaded


## Holds the head of [param file] for [param id] in place of the whole document [method doc] reads back.
func _stand_in(root: String, file: String, id: StringName) -> void:
	var stub := _peek(root.path_join(file))

	if stub.is_empty() or StringName(str(stub["id"])) != id:
		return

	_hold(id, stub)
	_files[id] = root.path_join(file)
	_stubs[id] = stub


## Reads and validates, on the worker threads, every document that has no current cached copy: a cold
## start parses them all, and one after another that is tens of seconds. file -> DotResult (null: empty or unreadable).
func _parse_ahead(root: String, files: PackedStringArray) -> Dictionary:
	var todo := PackedStringArray()

	for file in files:
		if not lazy and not _cache_current(root, file):
			todo.append(file)

	if todo.size() < 2 or not DotPlatform.has_threads():
		return {}

	var results: Array = []
	results.resize(todo.size())
	var read := func(i: int) -> void:
		var text := FileAccess.get_file_as_string(root.path_join(todo[i]))
		results[i] = ZzMapDoc.parse_json(text, todo[i]) if not text.is_empty() else null

	var group := WorkerThreadPool.add_group_task(read, todo.size(), -1, true, "zz map documents")
	WorkerThreadPool.wait_for_group_task_completion(group)
	var out := {}

	for i in todo.size():
		out[todo[i]] = results[i]

	return out


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


## Whether the cache holds a copy of [param file] that is current, without loading it.
func _cache_current(root: String, file: String) -> bool:
	var path := _cache_path(root, file)

	if path == "" or not FileAccess.file_exists(path):
		return false

	var f := FileAccess.open(path, FileAccess.READ)

	if f == null:
		return false

	var head: Variant = f.get_var()
	return typeof(head) == TYPE_STRING and head == _cache_key(root, file)


## Whether a current copy of [param doc] is now cached.
func _cache_write(root: String, file: String, doc: Dictionary) -> bool:
	var path := _cache_path(root, file)

	if path == "":
		return false

	var _made := DirAccess.make_dir_recursive_absolute(doc_cache_dir)
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)

	if f == null:
		return false

	f.store_var(_cache_key(root, file))
	f.store_var(doc)
	f.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK


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


## The head of a document as a stand-in map (id, name, mode, author, blurb, survivors, flagged
## `_stub`). Empty when it does not read as a map document, which is then read whole and refused
## with its reason. The full document is what [method doc] reads.
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


## The whole document of map [param id]: what [member maps] holds, or for a stand-in the file read
## now. Only one is kept (reading another restores the last to its stand-in). Empty when there is
## no such map or its document has gone bad since it was peeked.
func doc(id: StringName) -> Dictionary:
	var held: Dictionary = maps.get(id, {})

	if not held.get("_stub", false):
		return held

	for other: StringName in _stubs:
		if other != id and maps.has(other) and not maps[other].get("_stub", false):
			_hold(other, _stubs[other])

	var file := str(_files[id])
	var cached := _cache_read(str(roots[id]), file.get_file()) if not lazy and roots.has(id) else {}

	if not cached.is_empty() and str(cached.get("id", "")) == String(id):
		_hold(id, cached)
		return cached

	var parsed := ZzMapDoc.parse_json(FileAccess.get_file_as_string(file), file)

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
	if roots.get(id, "") == USER_MAPS:
		shown += DotMapDocDrop.TAG
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


## id -> the user://maps file of each map dropped this run (ZzMapDrop), which a later drop may replace.
var dropped: Dictionary = {}


## A map dropped on the game (ZzMapDrop): [param document], already checked by [method ZzMapDoc.parse_json] and
## copied to [param path] in [constant USER_MAPS], joins at once, whole (never a stand-in), replacing an earlier drop.
func add_dropped(document: Dictionary, path: String) -> void:
	dropped[StringName(str(document["id"]))] = path
	var id := StringName(str(document["id"]))
	maps[id] = document
	roots[id] = USER_MAPS
	var _was_file := _files.erase(id)
	var _was_stub := _stubs.erase(id)
	var _was_refused := refused.erase(path.get_file())
	_rebuild_order()


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


# The one built in

## Tests only: loose physics props (dot-props' toys) to put on the practice street; empty in play.
static var practice_toys: Array = []


## One street at night, from a safe room to a safe room (see zz_practice_street.gd for the layout).
static func practice() -> Dictionary:
	return ZzPracticeStreet.build(practice_toys, PRACTICE, CHANNEL)
