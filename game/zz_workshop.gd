extends RefCounted

## What subscribed Workshop packs add to this game's lists, read from dot-core's content index.
##
## [b]Listed, not playable.[/b] A pack's map is a scene; this game builds a map from a document
## (boxes, props, spawns: [ZzMapDoc]) and has no way to take a scene, so a Workshop map is shown
## in the solo map menu and on the solo ballot as "Name [Pack]" and answers [constant
## NOT_PLAYABLE] when chosen. docs/not-yet.md says what playing one needs.
##
## [b]Solo only, by the index and not by this file.[/b] [method DotContentIndex.entries] answers
## for the index's current session, so a server (online) lists none; nothing here checks which it is.
## No `class_name`: a mounted pack cannot register one.

## The file a game pack states what it takes from subscriptions in. Read from there because the
## site offers a pack by this same file and a second list here would drift from it.
const PROVIDES_PATH := "res://provides.json"

const ACCEPTED_FALLBACK := ["survival", "exodus"]

const NOT_PLAYABLE := "Zombie Zone cannot play Workshop maps yet."

const ZzPaths := preload("zz_paths.gd")


## The `map_kind`s of subscribed maps this game lists: `accepts.map_kinds` in `provides.json`.
static func accepted_map_kinds() -> PackedStringArray:
	var out := PackedStringArray()
	var path := ZzPaths.rebase(PROVIDES_PATH)
	var parsed: Variant = null
	if FileAccess.file_exists(path):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var accepts: Variant = (parsed as Dictionary).get("accepts") if parsed is Dictionary else null
	var kinds: Variant = (accepts as Dictionary).get("map_kinds") if accepts is Dictionary else null
	if not (kinds is Array):
		kinds = ACCEPTED_FALLBACK
	for kind: Variant in (kinds as Array):
		out.append(str(kind))
	return out


## The subscribed maps of an accepted kind whose id is not one of [param own_ids].
static func entries(index: DotContentIndex, own_ids: Array) -> Array[DotContentEntry]:
	var out: Array[DotContentEntry] = []
	if index == null:
		return out
	var kinds := accepted_map_kinds()
	for entry in index.entries(&"map"):
		var kind := str(entry.raw.get("map_kind", ""))
		if entry.id == "" or kind == "" or not (kinds.has("*") or kinds.has(kind)):
			continue
		if own_ids.has(entry.id) or own_ids.has(StringName(entry.id)):
			continue
		out.append(entry)
	return out


## Map-menu rows for [method entries], in the shape of [code]ZzGame.map_rows[/code].
static func rows(index: DotContentIndex, own_ids: Array) -> Array:
	var out: Array = []
	for entry in entries(index, own_ids):
		var title := entry.pack_title
		out.append({"id": entry.id, "name": "%s [%s]" % [entry.name, title] if title != "" else entry.name,
			"current": false, "mode": str(entry.raw.get("map_kind", "")).capitalize(),
			"detail": "Workshop map"})
	return out
