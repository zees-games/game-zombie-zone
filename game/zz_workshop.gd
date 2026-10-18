extends RefCounted

## What subscribed Workshop packs add to this game's lists, read from dot-core's content index.
##
## [b]Playable, as documents.[/b] A pack's `map` entry has `scene` pointing at a [ZzMapDoc]
## document (JSON) whose `id` equals the entry's; [ZzCatalogue] follows the index and builds it
## like its own maps (validation, nav graph, safe rooms, waves), shown as "Name [Pack]".
## This file only says which `map_kind`s are accepted.
##
## [b]Solo only, by the index and not by this file.[/b] [method DotContentIndex.entries] answers
## for the index's current session, so a server (online) lists none; nothing here checks which it is.
## No `class_name`: a mounted pack cannot register one.

## The file a game pack states what it takes from subscriptions in. Read from there because the
## site offers a pack by this same file and a second list here would drift from it.
const PROVIDES_PATH := "res://provides.json"

const ACCEPTED_FALLBACK := ["survival", "exodus"]

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
