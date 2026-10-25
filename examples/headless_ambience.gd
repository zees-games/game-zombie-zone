extends Node

## The creepy ambience in zz: cvars, the shipped sound set, the map to mood choice and the settings.
##
## [codeblock]
## ./game.sh --no-parse test headless_ambience
## [/codeblock]

const ZzAudio := preload("../game/zz_audio.gd")
const ZzAmbientRules := preload("../game/zz_ambient_rules.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const CHECKS := 65

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
	var file := FileAccess.get_file_as_string(DotAudioStock.moods_directory() + "/moods.json")
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
			if not FileAccess.file_exists(DotAudioStock.moods_directory() + "/" + f) and not FileAccess.file_exists(DotAudioStock.moods_directory() + "/" + f + ".import"):
				missing.append(f)
		_check(not (m.get("beds", []) as Array).is_empty() and not (m.get("oneshots", []) as Array).is_empty(), "%s has beds and one-shots" % mood_name)
	_check(missing.is_empty(), "every file moods.json names exists", ", ".join(missing))
	var credits := FileAccess.get_file_as_string(DotAudioStock.moods_directory() + "/CREDITS.md")
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

	# Every shipped map document carries a valid ambient field that validation keeps.
	var shipped := 0
	var lacking := PackedStringArray()
	var changed_by_validate := PackedStringArray()
	var scaled := 0
	for fname in DirAccess.get_files_at("res://maps"):
		if not fname.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://maps/" + fname))
		if not (parsed is Dictionary):
			continue
		shipped += 1
		var field: Variant = (parsed as Dictionary).get("ambient")
		var v := ZzMapDoc.validate(parsed)
		if field == null:
			lacking.append(fname)
		elif not v.ok or (v.value as Dictionary).get("ambient") != field:
			changed_by_validate.append(fname)
		if field is Dictionary and ((field as Dictionary).has("volume") or (field as Dictionary).has("frequency") or (field as Dictionary).has("extra")):
			scaled += 1
		var named: String = str((field as Dictionary).get("mood", "")) if field is Dictionary else str(field)
		if field != null and not (named in audio.ambient.mood_names()):
			lacking.append(fname + " (unknown mood)")
			lacking.append(fname + " (unknown mood)")
	_check(shipped >= 41 and lacking.is_empty(), "all %d shipped maps name a known mood" % shipped, ", ".join(lacking))
	_check(changed_by_validate.is_empty(), "and validation keeps every field as written", ", ".join(changed_by_validate))
	_check(scaled >= 10, "some maps scale or extend it (%d)" % scaled)
	for pair: Array in [["zm_4way_tunnel", &"cave_tunnel"], ["zs_goth_house", &"interior_horror"], ["ze_jurassicpark", &"swamp"], ["zm_antarctic_hospital", &"snow_wind"], ["zz_mall", &"indoor_hall"]]:
		var one: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://maps/%s.json" % pair[0]))
		audio.on_map_doc(StringName(pair[0]), (ZzMapDoc.validate(one).value as Dictionary))
		_check(audio.ambient.effective_mood() == pair[1] or audio.ambient.effective_mood() == StringName("%s+%s" % [pair[1], (ZzMapDoc.validate(one).value as Dictionary)["ambient"].get("extra", "")]), "%s sounds %s from its document" % [pair[0], pair[1]], str(audio.ambient.effective_mood()))

	# The object form: indoor mood, extra one-shots, scales.
	var dict_doc := {"ambient": {"mood": "swamp", "indoor": "cave_tunnel", "volume": 0.5, "frequency": 2.0, "extra": "industrial"}}
	audio.on_map_doc(&"zz_new_map", dict_doc)
	_check(audio.ambient.effective_mood() == &"swamp+industrial", "an extra set joins the mood's one-shots", str(audio.ambient.effective_mood()))
	var base_shots := audio.ambient.mood_def(&"swamp").oneshots.size()
	_check(audio.ambient.mood_def(&"swamp+industrial").oneshots.size() == base_shots + audio.ambient.mood_def(&"industrial").oneshots.size(), "and the beds are the base's")
	_check(is_equal_approx(audio.ambient.config.frequency, 2.0 * 1.0), "the map's frequency scales the setting", str(audio.ambient.config.frequency))
	audio.ambient.set_indoors(true)
	audio.ambient.advance(0.1)
	_check(audio.ambient.effective_mood() == &"cave_tunnel+industrial", "under a roof the document's indoor mood plays, with the extra", str(audio.ambient.effective_mood()))
	audio.ambient.set_indoors(false)
	audio.on_map_doc(&"zz_new_map", {"ambient": "swamp"})
	_check(audio.indoor_mood_for_map() == &"indoor_hall" and audio.ambient.config.frequency == 1.0, "a bare mood gets the default room tone and no scales")
	src["ambient"] = {"mood": "swamp", "volume": 99, "frequency": -3, "indoor": "Bad Id", "junk": 1}
	var v2 := ZzMapDoc.validate(src)
	var kept: Variant = (v2.value as Dictionary).get("ambient") if v2.ok else null
	_check(kept is Dictionary and kept["volume"] == 2.0 and kept["frequency"] == 0.0 and not kept.has("indoor") and not kept.has("junk"), "validation clamps scales and drops what is not an id", str(kept) + (" " + v2.error.message if not v2.ok else ""))

	# The switch: a rule off keeps the outdoor mood; the probe flips on agreeing rays only.
	var gate := ZzAmbientRules.new()
	audio.follow_settings(null, gate)
	_check(gate.follows_indoors() and gate.set_cvar("zz_ambient_indoor", "0") and not gate.follows_indoors(), "zz_ambient_indoor gates the switch")
	audio.on_map_doc(&"zz_new_map", dict_doc)
	var probe := DotAmbienceRoof.new()
	_check(not probe.feed(true) and probe.feed(true) and probe.roofed, "the roof probe flips on a second agreeing ray")
	gate.set_cvar("zz_ambient_indoor", "1")

	# A real ray: a slab overhead is a roof, open sky is not (needs a physics frame to exist).
	var slab := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 0.2, 10)
	shape.shape = box
	slab.add_child(shape)
	slab.position = Vector3(0, 4, 0)
	add_child(slab)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	audio.on_map_doc(&"zz_new_map", dict_doc)
	for _i in 12:
		audio.follow_roof(0.25, Vector3(0, 1.5, 0), space, 1)
	_check(audio.ambient.indoors(), "standing under a slab the ambience is indoors")
	for _i in 12:
		audio.follow_roof(0.25, Vector3(30, 1.5, 0), space, 1)
	_check(not audio.ambient.indoors(), "walking out into the open it is not")
	gate.set_cvar("zz_ambient_indoor", "0")
	for _i in 12:
		audio.follow_roof(0.25, Vector3(0, 1.5, 0), space, 1)
	_check(not audio.ambient.indoors(), "with the cvar off the slab changes nothing")
	slab.free()

	var unlisted: Array[String] = []
	for dir in DirAccess.get_directories_at(DotAudioStock.moods_directory()):
		for f in DirAccess.get_files_at(DotAudioStock.moods_directory() + "/" + dir):
			if f.ends_with(".ogg") and not credits.contains(dir + "/" + f):
				unlisted.append(dir + "/" + f)
	_check(unlisted.is_empty(), "every shipped ambience file is credited: %s" % ", ".join(unlisted))
	_check(FileAccess.file_exists("res://docs/ambience-audit.md"), "the loudness audit table is kept")

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
