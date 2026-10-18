extends Node

const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzVote := preload("../game/zz_vote.gd")
const ZzWorkshop := preload("../game/zz_workshop.gd")

## What a subscribed map pack does to this game's lists, against a fixture [DotContentIndex]
## and never the process's shared one: a solo map is listed on the map menu and the ballot with
## its pack's name, an online session lists none, a map kind the game does not accept is left
## out, and the game's own ids win. Choosing one answers that it cannot be played yet.
##
## [codeblock]
## godot --headless --path . res://examples/headless_workshop.tscn
## [/codeblock]

const SECTIONS := 5
const MAP := "fixture_ruin"
const OTHER_KIND := "fixture_run"

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
	var index := DotContentIndex.new()
	index.set_session(session)
	var added := index.add_pack({
		"content_id": "fixture/ruins", "version": "1.0.0", "prefix": "res://fixture/",
		"session": session, "source": &"subscription",
		"provides": {"schema": 1, "title": "Ruins Pack", "kinds": ["map"], "entries": [
			{"kind": "map", "id": MAP, "name": "Fixture Ruin", "scene": "ruin.tscn", "map_kind": "survival"},
			{"kind": "map", "id": OTHER_KIND, "name": "Fixture Run", "scene": "run.tscn", "map_kind": "race"},
			{"kind": "map", "id": "zz_practice", "name": "Not The Street", "scene": "p.tscn", "map_kind": "exodus"},
		]},
	})
	_check(added.ok, "the fixture pack registers for %s" % session)
	return index


func _game(index: DotContentIndex) -> ZzGame:
	var game := ZzGame.new()
	game.config = ZzConfig.new()
	game.catalogue = ZzCatalogue.new()
	game.catalogue.maps[ZzCatalogue.PRACTICE] = {"id": "zz_practice", "name": "Practice Street"}
	game.catalogue._order.append(ZzCatalogue.PRACTICE)
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
	var names := _names(_game(index).map_rows())
	_check(not names.has("Not The Street [Ruins Pack]") and names.has("Practice Street"),
		"the game's own id wins over a pack's (%s)" % ",".join(names))
	_completed += 1


func _test_refused() -> void:
	_entered += 1
	var game := _game(_index(DotContentIndex.SESSION_SOLO))
	var res := game.change_map_now(StringName(MAP))
	# Not authoritative here, so that answer comes first; the workshop answer is on a server.
	game.authoritative = true
	res = game.change_map_now(StringName(MAP))
	_check(not res.ok and res.error.message == ZzWorkshop.NOT_PLAYABLE, "choosing a Workshop map says it cannot be played yet")
	_completed += 1


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what)
		print("  FAIL  %s" % what)
