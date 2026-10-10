extends Node

## Under xvfb-run (never --headless, whose audio driver is Dummy): does the game make a noise?
## Bakes the bank as a client does and plays a cue of every kind beside the listener: one made
## in code (the map starting), one read from a file (a moan), a special's call, a blast, and
## the horde's music.
##   xvfb-run -a godot --path . res://tools/audio_probe.tscn

const ZzAudio := preload("res://game/zz_audio.gd")


func _ready() -> void:
	var audio := ZzAudio.new()
	add_child(audio)
	var ready_now := audio.setup()
	var sink := audio.manager.sink as DotAudioSinkGodot
	var ok := ready_now.ok and sink != null
	print("driver=%s sink=%s" % [AudioServer.get_driver_name(), sink != null])

	for id: StringName in [ZzAudio.MAP_START, ZzAudio.MOAN, ZzAudio.STRANGLER, ZzAudio.EXPLOSION, ZzAudio.BOX_OPEN, ZzAudio.MUSIC_HORDE]:
		# Made in code, it is in the bank; read from a file, the sink loads the path when played.
		var stream: Variant = sink.bank.get(id) if sink != null else null
		var def: DotAudioDef = audio.manager.catalogue.find(id)
		if stream == null and def != null and def.path != "":
			stream = load(def.path)
		var length := (stream as AudioStream).get_length() if stream is AudioStream else 0.0
		var voice := audio.manager.play_at(id, Vector3(0, 0, -3))
		await get_tree().process_frame
		print("%s baked=%.2f s voice=%d" % [id, length, voice])
		ok = ok and length > 0.05 and voice != 0

	# The catalogue names a file for every id; the ones made in code are in the bank instead.
	var missing := PackedStringArray()
	for path in audio.manager.catalogue.missing_files():
		if not sink.bank.has(StringName(path.get_file().get_basename())):
			missing.append(path)
	print("missing files: %s" % ", ".join(missing))
	ok = ok and missing.is_empty()

	get_tree().quit(0 if ok else 1)
