extends SceneTree

const CLIPS := ["idle", "walk", "run", "attack", "punch", "kick", "death", "crouch", "crouchIdle", "crouchWalk", "jump", "interactGround", "interactStanding"]

func _initialize() -> void:
	for model in ["characterMedium", "characterLargeMale", "characterLargeFemale", "characterSmall"]:
		var root := (load("res://src/%s.fbx" % model) as PackedScene).instantiate()
		var player := AnimationPlayer.new()
		player.name = "AnimationPlayer"
		root.add_child(player)
		player.owner = root
		var lib := AnimationLibrary.new()
		for clip in CLIPS:
			var src := (load("res://src/%s.fbx" % clip) as PackedScene).instantiate()
			var ap := src.get_node("AnimationPlayer") as AnimationPlayer
			var picked: Animation = null
			for name in ap.get_animation_list():
				if not String(name).contains("Targeting"):
					picked = ap.get_animation(name).duplicate(true)
			if picked != null:
				picked.loop_mode = Animation.LOOP_LINEAR if clip in ["idle", "walk", "run", "crouchIdle", "crouchWalk", "interactGround"] else Animation.LOOP_NONE
				lib.add_animation(clip, picked)
			src.free()
		player.add_animation_library("", lib)
		for c in root.get_children():
			_own(c, root)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_scene(root, state)
		if err != OK:
			printerr("append failed ", model, " ", err)
			continue
		err = doc.write_to_filesystem(state, "res://out/%s.glb" % model)
		print(model, " -> ", err, " anims=", lib.get_animation_list())
		root.free()
	quit()

func _own(n: Node, owner: Node) -> void:
	if n != owner:
		n.owner = owner
	for c in n.get_children():
		_own(c, owner)
