extends Control

## Old against new, per event: `./game.sh` is not needed, open it with
## `godot --path . res://tools/sound_compare.tscn`. Each row has the first-generation files (OLD)
## and every recorded variant (NEW); nothing plays on its own. `--` `--list` prints the table and quits.

const ZzAudio := preload("../game/zz_audio.gd")

## event: old files in sounds/
const OLD := {
	"moan": ["moan_1", "moan_2", "moan_3", "zombienoise1"], "rage": ["fastzombie1", "zombienoise3"],
	"claw": ["punch_1", "punch_2"], "die": ["zombienoise2"], "hurt": ["zombienoise1"],
	"leaper": ["leaper_screech"], "strangler": ["strangler_cough"], "bloater": ["slime_1"], "ram": ["ram_bellow"],
	"spitter": ["slime_2"], "rider": ["rider_laugh"], "brute": ["brute_roar"], "screamer": ["screamer_shriek"],
	"crawler": ["crawler_gurgle"], "riot": ["riot_clank"], "mutant": ["brute_roar"], "mutant_zap": ["explosion_1"],
	"mutant_grab": ["woosh"], "mutant_throw": ["woosh"], "mutant_jet": [], "gore_bone": ["punch_heavy"],
	"gore_rip": ["slime_1"], "gore_splat": ["slime_2"], "horde": ["horde_distant"],
}

var _player := AudioStreamPlayer.new()


func _ready() -> void:
	add_child(_player)
	if "--list" in OS.get_cmdline_user_args():
		for event: String in OLD:
			print("%s: old %d, new %d" % [event, (OLD[event] as Array).size(), int(ZzAudio.REAL_COUNTS[StringName(event)])])
		get_tree().quit()
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	for event: String in OLD:
		var row := HFlowContainer.new()
		var label := Label.new()
		label.text = event
		label.custom_minimum_size.x = 130
		row.add_child(label)
		for f: String in OLD[event]:
			row.add_child(_button("OLD " + f, "res://sounds/%s.ogg" % f))
		for i in int(ZzAudio.REAL_COUNTS[StringName(event)]):
			row.add_child(_button("new %d" % (i + 1), "res://sounds/real/%s_%d.ogg" % [event, i + 1]))
		box.add_child(row)


func _button(text: String, path: String) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void:
		var stream := load(path) as AudioStream
		if stream != null:
			_player.stream = stream
			_player.play())
	return b
