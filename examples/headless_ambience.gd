extends Node

## The creepy ambience in zz: cvars, the shipped sound set, the map to mood choice and the settings.
##
## [codeblock]
## ./game.sh --no-parse test headless_ambience
## [/codeblock]

const ZzAudio := preload("../game/zz_audio.gd")
const ZzAmbientRules := preload("../game/zz_ambient_rules.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const CHECKS := 44

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _check(ok: bool, what: String, _detail := "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


func _run() -> void:
	print("game-zombie-zone: ambience")

	var rules := ZzAmbientRules.new()
	var fired := [0]
	rules.changed.connect(func() -> void: fired[0] += 1)
	_check(rules.is_on() and rules.volume == 0.5 and rules.frequency == 1.0 and rules.mood == "", "rules default to on, quiet and free")
	_check(rules.set_cvar("zz_ambient_volume", "0.3") and is_equal_approx(rules.volume, 0.3), "a level cvar sets the level")
	_check(rules.set_cvar("zz_ambient_volume", "9") and rules.volume == 1.0, "and is clamped")
	_check(rules.set_cvar("zz_ambient_frequency", "2") and rules.frequency == 2.0, "the one-shot rate sets")
	_check(not rules.set_cvar("zz_ambient_volume", "loud"), "a word is not a level")
	_check(not rules.set_cvar("zz_nothing", "1"), "an unknown name is refused")
	_check(rules.set_cvar("zz_ambient_mood", "swamp") and rules.mood == "swamp", "the mood cvar holds text")
	_check(rules.set_cvar("zz_ambient", "0") and not rules.is_on(), "zz_ambient 0 turns it off")
	_check(fired[0] == 5, "every change was announced once", str(fired[0]))
	_check(rules.describe().has("allowed") and rules.describe()["mood"] == "swamp", "describe lists the values")

	var doc := JSON.new()
	var file := FileAccess.get_file_as_string("res://sounds/ambience/moods.json")
	_check(doc.parse(file) == OK, "moods.json parses")
	var moods: Dictionary = (doc.data as Dictionary).get("moods", {})
	_check(moods.size() == 8, "eight moods ship", str(moods.size()))
	var missing := PackedStringArray()
	var used := {}
	for mood_name: String in moods:
		var m: Dictionary = moods[mood_name]
		var files: Array = []
		for b: Dictionary in m.get("beds", []):
			files.append(b["file"])
		for s: Dictionary in m.get("oneshots", []):
			files.append_array(s["files"])
		for f: String in files:
			used[f] = true
			if not FileAccess.file_exists("res://sounds/ambience/" + f) and not FileAccess.file_exists("res://sounds/ambience/" + f + ".import"):
				missing.append(f)
		_check(not (m.get("beds", []) as Array).is_empty() and not (m.get("oneshots", []) as Array).is_empty(), "%s has beds and one-shots" % mood_name)
	_check(missing.is_empty(), "every file moods.json names exists", ", ".join(missing))
	var credits := FileAccess.get_file_as_string("res://sounds/ambience/CREDITS.md")
	var uncredited := PackedStringArray()
	for f: String in used:
		if not credits.contains("`" + f + "`"):
			uncredited.append(f)
	_check(uncredited.is_empty(), "every file is credited", ", ".join(uncredited))

	var chapel := JSON.new()
	var read_ok := chapel.parse(FileAccess.get_file_as_string("res://maps/zz_chapel.json")) == OK
	_check(read_ok, "a map document reads")
	var src: Dictionary = (chapel.data as Dictionary).duplicate(true) if read_ok else {}
	src["ambient"] = "swamp"
	var validated := ZzMapDoc.validate(src)
	_check(validated.ok and (validated.value as Dictionary).get("ambient", "") == "swamp", "validation keeps a map's ambient field",
		"" if validated.ok else validated.error.message)

	var audio := ZzAudio.new()
	add_child(audio)
	_check(audio.setup().ok, "the audio sets up")
	_check(audio.ambient != null and audio.ambient.mood_names().size() == 8, "the ambience loaded all eight moods")
	_check(audio.ambient.config.enabled, "and it is on by default")

	var cases := {
		&"zz_chapel": &"interior_horror", &"zz_mall": &"indoor_hall", &"zz_blackout_3": &"snow_wind",
		&"zz_blackout_2": &"industrial", &"zz_lot": &"city_ruins", &"zz_blackout_1": &"outdoor_night",
	}
	for id: StringName in cases:
		audio.on_map_doc(id, {})
		_check(audio.ambient.effective_mood() == cases[id], "%s sounds %s" % [id, cases[id]], str(audio.ambient.effective_mood()))
	audio.on_map_doc(&"zz_mall", {"ambient": "cave_tunnel"})
	_check(audio.ambient.effective_mood() == &"cave_tunnel", "a map document's ambient wins over the table")
	audio.on_map_doc(&"zz_new_map", {})
	_check(audio.ambient.effective_mood() == ZzAudio.DEFAULT_MOOD and audio.mood_for_map()["why"] == "default", "an unknown map gets the default")
	audio.on_world_sounds({"soundscapes": [{"soundscape": "swamp.frogs"}, {"soundscape": "swamp.night"}]})
	_check(audio.ambient.effective_mood() == &"swamp" and audio.mood_for_map()["why"] == "sound names", "a converted map's sound names vote")
	audio.on_map_doc(&"zz_new_map", {"ambient": "indoor_hall"})
	audio.on_world_sounds({"soundscapes": [{"soundscape": "swamp.frogs"}]})
	_check(audio.ambient.effective_mood() == &"indoor_hall", "and the document still beats the vote")

	var live := ZzAmbientRules.new()
	audio.follow_settings(null, live)
	live.set_cvar("zz_ambient_volume", "0.4")
	_check(is_equal_approx(audio.ambient.config.volume, 0.4), "the server's level reaches the ambience")
	live.set_cvar("zz_ambient_mood", "cave_tunnel")
	_check(audio.ambient.effective_mood() == &"cave_tunnel", "a forced mood beats the map")
	live.set_cvar("zz_ambient_mood", "")
	live.set_cvar("zz_ambient", "0")
	_check(not audio.ambient.config.enabled, "the server can switch it off")
	live.set_cvar("zz_ambient", "1")
	_check(audio.ambient.config.enabled, "and on again")
	_check(audio.describe().has("ambient"), "describe carries the ambience")

	audio.on_map_doc(&"zz_chapel", {})
	for _i in 600:
		audio.ambient.advance(1.0)
	var d: Dictionary = audio.ambient.describe()
	print("  ambience after 10 simulated minutes in zz_chapel: ", JSON.stringify(d))
	_check(d["mood"] == "interior_horror" and int(d["beds"]) == 3, "the chapel plays its three beds", str(d["beds"]))
	_check(int(d["oneshots_played"]) >= 2 and is_equal_approx(float(d["level"]), 0.4), "and some one-shots, faded in to the server level", str(d["oneshots_played"]))

	audio.free()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
