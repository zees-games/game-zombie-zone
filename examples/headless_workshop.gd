extends Node

const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzVote := preload("../game/zz_vote.gd")
const ZzWorkshop := preload("../game/zz_workshop.gd")

## What a subscribed map pack does to this game's lists, against a fixture [DotContentIndex]
## and never the process's shared one: a solo map is listed on the map menu and the ballot with
## its pack's name, an online session lists none, a map kind the game does not accept is left
## out, and the game's own ids win. Choosing one builds it: a pack's map entry names a map DOCUMENT in `scene`, read like the
## game's own. A malformed document is refused with its reason and listed nowhere.
##
## [codeblock]
## godot --headless --path . res://examples/headless_workshop.tscn
## [/codeblock]

const SECTIONS := 6
const MAP := "fixture_ruin"
const OTHER_KIND := "fixture_run"
const BAD := "fixture_bad"
const DIR := "user://ws_fixture/"

var _passed := 0
var _failed := 0
var _entered := 0
var _completed := 0
var _failures: Array[String] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-zombie-zone — Workshop maps")
	_test_accepts()
	_test_solo()
	_test_online()
	_test_ids()
	_test_refused()
	await _test_play()

	print("")
	_check(_completed == _entered and _entered == SECTIONS,
		"every section ran to its last line (%d of %d, %d expected)" % [_completed, _entered, SECTIONS])
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	get_tree().quit(1 if _failed > 0 or _completed != SECTIONS else 0)


## A pack with a survival map, a race map the game does not accept, and a map that claims the
## id of the built-in practice street.
func _index(session: StringName) -> DotContentIndex:
	_write_fixtures()
	var index := DotContentIndex.new()
	index.set_session(session)
	var added := index.add_pack({
		"content_id": "fixture/ruins", "version": "1.0.0", "prefix": DIR,
		"session": session, "source": &"subscription",
		"provides": {"schema": 1, "title": "Ruins Pack", "kinds": ["map"], "entries": [
			{"kind": "map", "id": MAP, "name": "Fixture Ruin", "scene": "ruin.json", "map_kind": "survival"},
			{"kind": "map", "id": OTHER_KIND, "name": "Fixture Run", "scene": "run.tscn", "map_kind": "race"},
			{"kind": "map", "id": BAD, "name": "Fixture Bad", "scene": "bad.json", "map_kind": "survival"},
			{"kind": "map", "id": "zz_practice", "name": "Not The Street", "scene": "p.tscn", "map_kind": "exodus"},
		]},
	})
	_check(added.ok, "the fixture pack registers for %s" % session)
	return index


## The pack's files: a map document of the practice street under the entry's id, and a broken one.
func _write_fixtures() -> void:
	var made := DirAccess.make_dir_recursive_absolute(DIR)
	_check(made == OK, "the fixture directory exists")
	var doc := ZzCatalogue.practice().duplicate(true)
	doc["id"] = MAP
	doc["name"] = "Fixture Ruin"
	doc["mode"] = ZzMapDoc.SURVIVAL
	doc["objectives"] = []
	doc["caches"] = [[-2.0, 0.0, 10.0], [2.0, 0.0, 10.0]]
	_put("ruin.json", JSON.stringify(doc))
	_put("bad.json", '{"format": 1, "kind": "zz_map", "id": "fixture_bad", "boxes": "not a list"')


func _put(file: String, text: String) -> void:
	var f := FileAccess.open(DIR + file, FileAccess.WRITE)
	if f != null:
		f.store_string(text)


func _game(index: DotContentIndex) -> ZzGame:
	var game := ZzGame.new()
	game.config = ZzConfig.new()
	game.catalogue = ZzCatalogue.new()
	game.catalogue.maps[ZzCatalogue.PRACTICE] = {"id": "zz_practice", "name": "Practice Street"}
	game.catalogue._order.append(ZzCatalogue.PRACTICE)
	game.catalogue.follow_content(index, ZzWorkshop.accepted_map_kinds())
	game.content_index = index
	return game


func _names(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in rows:
		out.append(str(row["name"]))
	return out


func _vote(index: DotContentIndex) -> ZzVote:
	var vote := ZzVote.new()
	vote.content_index = index
	vote.config_path = ""
	vote.maps_fn = func() -> Array: return [[&"zz_practice", "Practice Street"]]
	var built := vote.setup()
	_check(built.ok, "the vote builds")
	return vote


func _labels(vote: ZzVote) -> PackedStringArray:
	var out := PackedStringArray()
	for choice in vote.source.choices():
		out.append(choice.label())
	return out


func _test_accepts() -> void:
	_entered += 1
	var kinds := ZzWorkshop.accepted_map_kinds()
	_check(kinds.has("survival") and kinds.has("exodus") and not kinds.has("race"),
		"provides.json accepts survival and exodus maps (%s)" % ",".join(kinds))
	_completed += 1


func _test_solo() -> void:
	_entered += 1
	var index := _index(DotContentIndex.SESSION_SOLO)
	var names := _names(_game(index).map_rows())
	_check(names.has("Fixture Ruin [Ruins Pack]"), "solo: the map menu lists the pack's map with its pack (%s)" % ",".join(names))
	_check(not names.has("Fixture Run [Ruins Pack]"), "solo: a kind the game does not accept is left out")
	var vote := _vote(index)
	var labels := _labels(vote)
	_check(labels.has("Fixture Ruin [Ruins Pack]"), "solo: the ballot lists the pack's map (%s)" % ",".join(labels))
	_check(not labels.has("Fixture Run [Ruins Pack]"), "solo: the ballot leaves the unaccepted kind out")
	vote.free()
	_completed += 1


func _test_online() -> void:
	_entered += 1
	# A subscribed pack is tagged solo; the session then goes online, as it does on joining a server.
	var index := _index(DotContentIndex.SESSION_SOLO)
	index.set_session(DotContentIndex.SESSION_ONLINE)
	var names := _names(_game(index).map_rows())
	_check(not names.has("Fixture Ruin [Ruins Pack]") and names.size() == 1,
		"online: the map menu lists only the game's own (%s)" % ",".join(names))
	var vote := _vote(index)
	var labels := _labels(vote)
	_check(labels.size() == 1 and labels[0] == "Practice Street", "online: the ballot lists only the game's own (%s)" % ",".join(labels))
	vote.free()
	_completed += 1


func _test_ids() -> void:
	_entered += 1
	var index := _index(DotContentIndex.SESSION_SOLO)
	var game := _game(index)
	var names := _names(game.map_rows())
	_check(not names.has("Not The Street [Ruins Pack]") and str(game.catalogue.maps[ZzCatalogue.PRACTICE]["name"]) == "Practice Street"
			and not game.catalogue.is_content(ZzCatalogue.PRACTICE),
		"the game's own id wins over a pack's (%s)" % ",".join(names))
	game.free()
	_completed += 1


func _test_refused() -> void:
	_entered += 1
	var game := _game(_index(DotContentIndex.SESSION_SOLO))
	var names := _names(game.map_rows())
	_check(not names.has("Fixture Bad [Ruins Pack]"), "a malformed document is not listed")
	var why := ""
	for key: String in game.catalogue.refused:
		if key.find(BAD) >= 0:
			why = str(game.catalogue.refused[key])
	_check(why != "" and why.find("JSON") >= 0, "it is refused with a reason that says what is wrong (%s)" % why)
	game.authoritative = true
	var res := game.change_map_now(StringName(BAD))
	_check(not res.ok and res.error.message.find(BAD) >= 0, "choosing it answers that there is no such map (%s)" % (res.error.message if not res.ok else ""))
	game.free()
	_completed += 1


## A real world in solo: the pack's map is chosen and the round starts on it.
func _test_play() -> void:
	_entered += 1
	var solo := ZzGame.new()
	solo.config = ZzConfig.new()
	solo.config.minimum_players = 0
	solo.authoritative = true
	solo.register_service = false
	solo.tick_rate = 30
	solo.content_index = _index(DotContentIndex.SESSION_SOLO)
	add_child(solo)
	solo.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var res := solo.change_map_now(StringName(MAP))
	_check(res.ok, "solo: choosing the pack's map succeeds (%s)" % (res.error.message if not res.ok else ""))
	_check(solo.map_doc.get("id", "") == MAP, "solo: the round is on the pack's map (%s)" % str(solo.map_doc.get("id", "")))
	_check(solo.map != null and solo.map.id() == StringName(MAP), "solo: the map is built")
	_check(not (solo.map_doc.get("spawns", {}) as Dictionary).get("survivors", []).is_empty(), "solo: the pack map has survivor spawns")
	var spawn: Array = solo.map.spawn("survivors", 0) if solo.map != null else []
	_check(spawn.size() == 2 and spawn[0] is Vector3, "solo: a spawn is placed on it")
	var rows := solo.map_rows()
	var mine := rows.filter(func(r: Dictionary) -> bool: return r["id"] == MAP)
	_check(mine.size() == 1 and mine[0]["name"] == "Fixture Ruin [Ruins Pack]", "solo: listed once, with its pack")
	solo.queue_free()

	# Online the same pack is not even a catalogue entry.
	var index := _index(DotContentIndex.SESSION_SOLO)
	index.set_session(DotContentIndex.SESSION_ONLINE)
	var online := _game(index)
	online.authoritative = true
	var denied := online.change_map_now(StringName(MAP))
	_check(not denied.ok and not online.catalogue.maps.has(StringName(MAP)), "online: the pack's map is not playable")
	online.free()
	_completed += 1


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what)
		print("  FAIL  %s" % what)
