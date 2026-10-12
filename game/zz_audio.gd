extends Node

const ZzPaths := preload("zz_paths.gd")

## What this game makes a noise about, and the noise, on the client.
##
## [b]In a horror game the sounds are half the fear.[/b] A crowd is heard before it is seen: idle
## commons moan where they stand, a common that spots you screams and the ones round it scream
## back, a mob arriving is a rising wall of it with music under it. Each special has a voice of
## its own a player learns to dread — the leaper's screech before the jump, the strangler's
## cough, the sleeper's crying, which gets louder the closer you are — and the brute has its own
## music, because the moment it appears is the moment the fight changes.
##
## [b]Recordings where there are recordings, stand-ins where there are not.[/b] The zombies'
## voices, the explosions, the slime, the punches and the music are CC0 files in `sounds/`
## (see its CREDITS.md); the interface and the guns are dot-audio's synthesised stand-ins until
## somebody drops a file at the path. [DotAudioSinkGodot] consults the file before the stand-in.
##
## [b]Never on a server, and never deciding anything.[/b]

const CHANNEL := "zz.audio"

static var SOUND_DIR := ZzPaths.rebase("res://sounds")

# Flat, to this player.
const MAP_START := &"map_start"
const HORDE := &"horde"
const OBJECTIVE := &"objective"
const YOU_ARE_DOWN := &"you_are_down"
const YOU_ARE_UP := &"you_are_up"
const YOU_ARE_DEAD := &"you_are_dead"
const MAP_WON := &"map_won"
const MAP_LOST := &"map_lost"
const BOX_OPEN := &"box_open"
const PICKUP := &"pickup"
const HEALED := &"healed"
const UI_CLICK := &"ui_click"
const UI_DENY := &"ui_deny"
const HURT := &"hurt"

# Placed in the world.
const MOAN := &"moan"
const SCREAM := &"scream"
const CLAW := &"claw"
const ZOMBIE_DIE := &"zombie_die"
const LEAPER := &"leaper"
const STRANGLER := &"strangler"
const BLOATER := &"bloater"
const RAM := &"ram"
const SPITTER := &"spitter"
const RIDER := &"rider"
const BRUTE := &"brute"
const SLEEPER := &"sleeper"
const SCREAMER := &"screamer"
const CRAWLER := &"crawler"
const RIOT := &"riot"
const EXPLOSION := &"explosion"
const SPLAT := &"splat"
const ROCK := &"rock"
const WOOSH := &"woosh"
const CALL_MEDIC := &"call_medic"
const CALL_HELP := &"call_help"
const WEAPON_SHOT := &"weapon_shot"
const WEAPON_SWING := &"weapon_swing"
const WEAPON_LAUNCH := &"weapon_launch"
const WEAPON_BEAM := &"weapon_beam"
const WEAPON_THROW := &"weapon_throw"

# Music.
const MUSIC_HORDE := &"music_horde"
const MUSIC_BRUTE := &"music_brute"

## Which special's voice is which id.
const SPECIAL_VOICES := {
	&"leaper": LEAPER, &"strangler": STRANGLER, &"bloater": BLOATER, &"ram": RAM,
	&"spitter": SPITTER, &"rider": RIDER, &"brute": BRUTE, &"sleeper": SLEEPER,
	&"screamer": SCREAMER, &"crawler": CRAWLER, &"riot": RIOT,
}

var manager: DotAudioManager = null

## Everybody's footsteps by what they stand on, and the bed under the whole game: dot-audio's
## stock (Kenney's footsteps, generated beds, all CC0; the addon's stock/CREDITS.md).
var steps: DotAudioFootsteps = null
var ambience: DotAudioAmbience = null


static func ids() -> Array[StringName]:
	return sound_catalogue().ids()


static func _file(name: String) -> String:
	return "%s/%s.ogg" % [SOUND_DIR, name]


static func sound_catalogue() -> DotAudioCatalogue:
	var c := DotAudioCatalogue.new()

	# Footsteps and ambience beds, the family's stock.
	DotAudioStock.add_to(c)

	c.add(_flat(MAP_START, &"UI", 1, 85, ""))
	c.add(_flat(HORDE, &"SFX", 1, 90, "horde_distant"))
	c.add(_flat(OBJECTIVE, &"UI", 1, 85, ""))
	c.add(_flat(YOU_ARE_DOWN, &"SFX", 1, 100, ""))
	c.add(_flat(YOU_ARE_UP, &"UI", 1, 90, ""))
	c.add(_flat(YOU_ARE_DEAD, &"SFX", 1, 100, ""))
	c.add(_flat(MAP_WON, &"UI", 1, 80, ""))
	c.add(_flat(MAP_LOST, &"UI", 1, 80, ""))
	c.add(_flat(BOX_OPEN, &"SFX", 2, 85, "box_open"))
	c.add(_flat(PICKUP, &"UI", 2, 70, ""))
	c.add(_flat(HEALED, &"UI", 1, 70, ""))
	var hurt := _flat(HURT, &"SFX", 2, 75, "punch_1")
	hurt.variants = PackedStringArray([_file("punch_1"), _file("punch_2")])
	hurt.cooldown_ms = 150
	c.add(hurt)
	var click := _flat(UI_CLICK, &"UI", 2, 60, "")
	click.cooldown_ms = 60
	c.add(click)
	var deny := _flat(UI_DENY, &"UI", 1, 60, "")
	deny.cooldown_ms = 250
	c.add(deny)

	# The crowd: many at once, but not every one of forty, and the nearest win.
	var moan := _placed(MOAN, 30.0, 4.0, 5, 30, 0.85, 1.15, "moan_1")
	moan.variants = PackedStringArray([_file("moan_1"), _file("moan_2"), _file("moan_3"),
		_file("moan_4"), _file("moan_5"), _file("zombienoise1"), _file("zombienoise2")])
	moan.cooldown_ms = 250
	c.add(moan)
	var scream := _placed(SCREAM, 45.0, 6.0, 4, 60, 0.9, 1.2, "fastzombie1")
	scream.variants = PackedStringArray([_file("fastzombie1"), _file("zombienoise3")])
	scream.cooldown_ms = 120
	c.add(scream)
	var claw := _placed(CLAW, 20.0, 4.0, 4, 50, 0.9, 1.1, "punch_2")
	claw.variants = PackedStringArray([_file("punch_1"), _file("punch_2")])
	c.add(claw)
	var die := _placed(ZOMBIE_DIE, 25.0, 4.0, 4, 40, 0.8, 1.1, "zombienoise2")
	die.cooldown_ms = 90
	c.add(die)

	c.add(_placed(LEAPER, 60.0, 8.0, 2, 85, 0.95, 1.05, "leaper_screech"))
	c.add(_placed(STRANGLER, 50.0, 7.0, 2, 80, 0.95, 1.05, "strangler_cough"))
	c.add(_placed(BLOATER, 40.0, 6.0, 2, 80, 0.9, 1.1, "slime_1"))
	c.add(_placed(RAM, 60.0, 8.0, 2, 85, 0.9, 1.0, "ram_bellow"))
	c.add(_placed(SPITTER, 45.0, 6.0, 2, 80, 1.0, 1.2, "slime_2"))
	c.add(_placed(RIDER, 45.0, 6.0, 2, 80, 1.0, 1.1, "rider_laugh"))
	c.add(_placed(BRUTE, 120.0, 14.0, 1, 95, 0.95, 1.0, "brute_roar"))
	# The screamer is heard further than anything but the brute: its scream is the warning.
	c.add(_placed(SCREAMER, 90.0, 10.0, 1, 90, 0.95, 1.05, "screamer_shriek"))
	c.add(_placed(CRAWLER, 22.0, 3.0, 2, 75, 0.9, 1.1, "crawler_gurgle"))
	c.add(_placed(RIOT, 45.0, 6.0, 2, 80, 0.9, 1.05, "riot_clank"))
	var cry := _placed(SLEEPER, 28.0, 3.0, 1, 90, 0.95, 1.05, "sleeper_cry")
	cry.looping = true
	c.add(cry)

	var boom := _placed(EXPLOSION, 160.0, 18.0, 3, 95, 0.9, 1.05, "explosion_1")
	boom.variants = PackedStringArray([_file("explosion_1"), _file("explosion_2")])
	c.add(boom)
	c.add(_placed(SPLAT, 40.0, 6.0, 2, 70, 0.9, 1.1, "slime_1"))
	c.add(_placed(ROCK, 60.0, 10.0, 2, 80, 0.9, 1.0, "rock_hit"))
	c.add(_placed(WOOSH, 30.0, 6.0, 3, 50, 0.9, 1.1, "woosh"))
	c.add(_placed(CALL_MEDIC, 45.0, 8.0, 1, 75, 1.0, 1.0, "call_medic"))
	c.add(_placed(CALL_HELP, 45.0, 8.0, 1, 75, 1.0, 1.0, "call_look_out"))

	var shot := _placed(WEAPON_SHOT, 110.0, 14.0, 4, 80, 0.94, 1.06, "")
	shot.tags = [&"weapon"]
	c.add(shot)
	var swing := _placed(WEAPON_SWING, 30.0, 6.0, 2, 55, 0.9, 1.1, "")
	swing.tags = [&"weapon"]
	c.add(swing)
	var launch := _placed(WEAPON_LAUNCH, 140.0, 16.0, 2, 82, 0.95, 1.05, "")
	launch.tags = [&"weapon"]
	c.add(launch)
	var beam := _placed(WEAPON_BEAM, 90.0, 12.0, 1, 75, 1.0, 1.0, "")
	beam.cooldown_ms = 180
	beam.tags = [&"weapon"]
	c.add(beam)
	var throw := _placed(WEAPON_THROW, 40.0, 8.0, 2, 55, 0.95, 1.05, "")
	throw.tags = [&"weapon"]
	c.add(throw)

	var horde_music := _flat(MUSIC_HORDE, &"Music", 1, 50, "music_horde")
	horde_music.looping = true
	c.add(horde_music)
	var brute_music := _flat(MUSIC_BRUTE, &"Music", 1, 60, "music_brute")
	brute_music.looping = true
	c.add(brute_music)
	return c


## The synthesised stand-ins, for every id with no file.
static func sound_recipes() -> Dictionary:
	return {
		MAP_START: DotAudioSynth.Voice.SPAWN,
		OBJECTIVE: DotAudioSynth.Voice.BLIP,
		YOU_ARE_DOWN: DotAudioSynth.Voice.DIE,
		YOU_ARE_UP: DotAudioSynth.Voice.PICKUP,
		YOU_ARE_DEAD: DotAudioSynth.Voice.DIE,
		MAP_WON: DotAudioSynth.Voice.PICKUP,
		MAP_LOST: DotAudioSynth.Voice.DENY,
		PICKUP: DotAudioSynth.Voice.PICKUP,
		HEALED: DotAudioSynth.Voice.PICKUP,
		UI_CLICK: DotAudioSynth.Voice.CLICK,
		UI_DENY: DotAudioSynth.Voice.DENY,
		WEAPON_SHOT: DotAudioSynth.Voice.SHOT,
		WEAPON_SWING: DotAudioSynth.Voice.STEP,
		WEAPON_LAUNCH: DotAudioSynth.Voice.SHOT_HEAVY,
		WEAPON_BEAM: DotAudioSynth.Voice.SHOT_TIGHT,
		WEAPON_THROW: DotAudioSynth.Voice.CLICK,
	}


static func weapon_sound(kind: int) -> StringName:
	match kind:
		ZeeWeaponNet.KIND_SHOT:
			return WEAPON_SHOT
		ZeeWeaponNet.KIND_SWING:
			return WEAPON_SWING
		ZeeWeaponNet.KIND_SPAWN:
			return WEAPON_LAUNCH
		ZeeWeaponNet.KIND_BEAM:
			return WEAPON_BEAM
		ZeeWeaponNet.KIND_THROW:
			return WEAPON_THROW
		_:
			return &""


static func _placed(
	id: StringName, max_distance: float, unit_size: float, concurrent: int, priority: int,
	pitch_min: float, pitch_max: float, file: String
) -> DotAudioDef:
	var def := DotAudioDef.new()
	def.id = id
	def.path = _file(file if file != "" else String(id))
	def.kind = DotAudioDef.Kind.POSITIONAL_3D
	def.bus = &"SFX"
	def.max_distance = max_distance
	def.unit_size = unit_size
	def.max_concurrent = concurrent
	def.priority = priority
	def.pitch_min = pitch_min
	def.pitch_max = pitch_max
	return def


static func _flat(id: StringName, bus: StringName, concurrent: int, priority: int, file: String) -> DotAudioDef:
	var def := DotAudioDef.new()
	def.id = id
	def.path = _file(file if file != "" else String(id))
	def.bus = bus
	def.max_concurrent = concurrent
	def.priority = priority
	return def


func setup() -> DotResult:
	manager = DotAudioManager.new()
	manager.name = "Audio"
	manager.catalogue = sound_catalogue()
	manager.mixer = DotAudioMixer.new()
	manager.register_as_service = false
	manager.voices = 32
	# Measured toward the family's -17 LUFS (dot-audio docs/loudness.md): at +6 two 40 s runs
	# read -19.4 LUFS; at +8 two runs whose camera went over 100 m read -16.1 and -16.9. A run
	# where the player is cornered or dead most of the time (camera under 40 m) reads about
	# 2 LU lower, so read the capture's camera line before believing a number.
	manager.loudness_trim_db = 8.0
	add_child(manager)

	var ready_now := manager.setup()

	if not ready_now.ok:
		return ready_now.wrap("zombiezone audio")

	steps = DotAudioFootsteps.new()
	steps.name = "Footsteps"
	steps.manager = manager
	steps.default_surface = &"concrete"
	add_child(steps)
	ambience = DotAudioAmbience.new()
	ambience.name = "Ambience"
	ambience.manager = manager
	ambience.fallback_bed = &"amb_night"
	add_child(ambience)
	ambience.set_map_bed(&"amb_night")

	var godot_sink := manager.sink as DotAudioSinkGodot

	if godot_sink != null:
		godot_sink.bank = DotAudioSynth.bank(manager.catalogue, sound_recipes())

	return DotResult.success(null)


## Each map's bed outdoors and the ground nobody named, for a document that says neither
## (`"ambience"` and `"surface"` in a map document win). Indoors is found, not listed: see
## [method on_map_doc].
const MAP_SOUND := {
	&"zz_blackout_1": [&"amb_night", &"concrete"],
	&"zz_blackout_2": [&"amb_industrial", &"concrete"],
	&"zz_blackout_3": [&"amb_wind", &"wood"],
	&"zz_chapel": [&"amb_eerie", &"grass"],
	&"zz_high_school": [&"amb_outdoor", &"concrete"],
	&"zz_lot": [&"amb_city", &"concrete"],
	&"zz_mall": [&"amb_city", &"concrete"],
	&"zz_relief_camp": [&"amb_night", &"grass"],
	&"zz_stadium": [&"amb_outdoor", &"concrete"],
}


## A map arrived. Its bed and ground, and an indoor zone under every ceiling or roof box: the
## room tone plays where there is something over your head, and no map lists its rooms twice.
func on_map_doc(id: StringName, doc: Dictionary) -> void:
	var row: Array = MAP_SOUND.get(id, [&"amb_night", &"concrete"])
	on_map(StringName(str(doc.get("ambience", row[0]))), StringName(str(doc.get("surface", row[1]))))
	if ambience == null:
		return
	ambience.clear_zones()
	for box: Variant in doc.get("boxes", []):
		if not (box is Dictionary) or not (str(box.get("mat", "")) in ["ceiling", "roof"]):
			continue
		var at: Array = box.get("at", [0, 0, 0])
		var size: Array = box.get("size", [0, 0, 0])
		var top := float(at[1]) + float(size[1]) * 0.5
		var low := top - 6.0
		ambience.add_zone(AABB(Vector3(float(at[0]) - float(size[0]) * 0.5, low, float(at[2]) - float(size[2]) * 0.5),
			Vector3(float(size[0]), top - low, float(size[2]))), &"amb_indoor")


## Everybody this client knows steps, once a frame: players and bots alike.
func keep_walkers(bodies: Array) -> void:
	if steps != null:
		steps.keep(bodies)


## A map arrived: its bed and its ground. Empty keeps what is playing.
func on_map(bed: StringName, surface: StringName = &"") -> void:
	if ambience != null and bed != &"":
		ambience.set_map_bed(bed)
	if steps != null and surface != &"":
		steps.default_surface = surface


func listen_from(at: Vector3) -> void:
	if manager != null:
		manager.listener_position = at


func play(id: StringName) -> bool:
	return manager != null and manager.play(id) != 0


func at(id: StringName, where: Vector3, volume: float = 1.0) -> int:
	return manager.play_at(id, where, volume) if manager != null else 0


func move(handle: int, where: Vector3) -> void:
	if manager != null and handle != 0:
		manager.move(handle, where)


func stop(handle: int) -> void:
	if manager != null and handle != 0:
		manager.stop(handle)


func on_weapon(where: Vector3, kind: int) -> bool:
	var id := weapon_sound(kind)
	return id != &"" and at(id, where) != 0


func special_voice(kind: StringName, where: Vector3) -> int:
	var id: StringName = SPECIAL_VOICES.get(kind, &"")
	return at(id, where) if id != &"" else 0


func music(id: StringName) -> void:
	if manager == null:
		return

	if id == &"":
		manager.stop_music(2.0)
	elif manager.music_id() != id:
		var _handle := manager.play_music(id, 1.5)


func click() -> bool:
	return play(UI_CLICK)


func deny() -> bool:
	return play(UI_DENY)


func describe() -> Dictionary:
	return {
		"ids": ids().size(),
		"device": manager != null and manager.sink is DotAudioSinkGodot,
		"music": String(manager.music_id()) if manager != null else "",
	}
