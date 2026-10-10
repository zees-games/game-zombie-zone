extends Node3D

const ZzPaths := preload("../game/zz_paths.gd")
const ZzZombieBody := preload("zz_zombie_body.gd")

## What a zombie looks like: a Kenney animated character, skinned as one of the dead, scaled and
## tinted for its kind, playing the clip its body's [member ZzZombieBody.anim] asks for.
##
## [b]Client only.[/b] A server never builds one; it draws nothing. The body this hangs off is a
## client's mirror of the server's zombie, or — offline — the zombie itself.
##
## [b]One rig, nine monsters.[/b] Every kind is the same skeleton and the same thirteen clips
## (`tools/convert_bodies.gd` put them in one file per body), told apart by which body, which
## skin, how big, what colour, and how it stands: the crowd's arms come up and forward over the
## walk, the leaper crouches, the brute is half again as tall and twice as wide, the bloater is
## wide everywhere. That is what Kenney's CC0 bundle gives, and it is enough to read at a glance
## which thing is coming at you, which is the only thing a picture of a zombie has to do.
##
## [b]The pose is written after the clip, every frame.[/b] The AnimationPlayer is advanced by
## hand ([method _process]) and the arm and spine overrides applied after it, for the reason
## `ZzFigure` gives: left to the engine, the clip and the override run in an order nothing
## controls and the clip puts the arms back down.

const CHANNEL := "zz.zombie_view"

static var BODIES := {
	&"male": ZzPaths.rebase("res://assets/zombies/body_male.glb"),
	&"female": ZzPaths.rebase("res://assets/zombies/body_female.glb"),
	&"small": ZzPaths.rebase("res://assets/zombies/body_small.glb"),
}

static var SKINS: Array[String] = [
	ZzPaths.rebase("res://assets/zombies/skin_a.png"),
	ZzPaths.rebase("res://assets/zombies/skin_b.png"),
	ZzPaths.rebase("res://assets/zombies/skin_c.png"),
]

## Per kind: body, height in metres, girth (x/z scale against height), tint, skin index (-1 by
## variant), and how it stands (`arms`: forward reach of the arms, `hunch`: spine bend).
const LOOKS := {
	&"common": {"body": &"", "height": 1.75, "girth": 1.0, "tint": Color(0.86, 0.9, 0.84), "skin": -1, "arms": 0.9, "hunch": 0.15},
	&"leaper": {"body": &"male", "height": 1.7, "girth": 0.85, "tint": Color(0.55, 0.6, 0.72), "skin": 2, "arms": 0.4, "hunch": 0.5},
	&"strangler": {"body": &"male", "height": 2.05, "girth": 0.8, "tint": Color(0.68, 0.78, 0.55), "skin": 1, "arms": 0.2, "hunch": 0.3},
	&"bloater": {"body": &"male", "height": 1.85, "girth": 1.75, "tint": Color(0.86, 0.8, 0.5), "skin": 0, "arms": 0.5, "hunch": 0.05},
	&"ram": {"body": &"male", "height": 2.05, "girth": 1.35, "tint": Color(0.82, 0.6, 0.52), "skin": 1, "arms": 0.1, "hunch": 0.35},
	&"spitter": {"body": &"female", "height": 1.95, "girth": 0.85, "tint": Color(0.78, 0.9, 0.42), "skin": 2, "arms": 0.3, "hunch": 0.25},
	&"rider": {"body": &"small", "height": 1.2, "girth": 1.0, "tint": Color(0.75, 0.68, 0.6), "skin": 0, "arms": 0.7, "hunch": 0.6},
	&"brute": {"body": &"male", "height": 2.95, "girth": 1.75, "tint": Color(0.72, 0.62, 0.66), "skin": 1, "arms": 0.25, "hunch": 0.3},
	&"sleeper": {"body": &"female", "height": 1.65, "girth": 0.85, "tint": Color(0.95, 0.95, 0.98), "skin": 0, "arms": 0.0, "hunch": 0.0},
}

## Which clip an animation state plays, and how fast.
const CLIPS := {
	ZzZombieBody.Anim.IDLE: [&"idle", 1.0],
	ZzZombieBody.Anim.WALK: [&"walk", 1.0],
	ZzZombieBody.Anim.SHAMBLE: [&"walk", 0.6],
	ZzZombieBody.Anim.RUN: [&"run", 1.0],
	ZzZombieBody.Anim.ATTACK: [&"punch", 1.3],
	ZzZombieBody.Anim.STAGGER: [&"crouch", 0.6],
	ZzZombieBody.Anim.SIT: [&"crouchIdle", 0.5],
	ZzZombieBody.Anim.FEED: [&"interactGround", 0.8],
	ZzZombieBody.Anim.CROUCH: [&"crouchWalk", 1.4],
	ZzZombieBody.Anim.LEAP: [&"jump", 0.8],
	ZzZombieBody.Anim.PIN: [&"punch", 2.0],
	ZzZombieBody.Anim.VOMIT: [&"interactStanding", 1.2],
	ZzZombieBody.Anim.SPIT: [&"attack", 1.0],
	ZzZombieBody.Anim.CHARGE: [&"run", 1.5],
	ZzZombieBody.Anim.CARRY: [&"run", 1.4],
	ZzZombieBody.Anim.THROW: [&"attack", 0.6],
	ZzZombieBody.Anim.CRY: [&"crouchIdle", 0.35],
	ZzZombieBody.Anim.RAGE: [&"kick", 0.7],
	ZzZombieBody.Anim.TONGUE: [&"interactStanding", 0.8],
	ZzZombieBody.Anim.DEAD: [&"death", 1.0],
}

var kind: StringName = &""
var variant: int = -1

var _model: Node3D = null
var _anim: AnimationPlayer = null
var _skeleton: Skeleton3D = null
var _bones: Dictionary = {}
var _clip: StringName = &""
var _look: Dictionary = {}
var _material: StandardMaterial3D = null
var _fire: CPUParticles3D = null
var _eyes: OmniLight3D = null
var _last_at: Vector3 = Vector3.INF
var _speed: float = 0.0
var _dead_for: float = -1.0

static var _scenes: Dictionary = {}
static var _textures: Dictionary = {}


## Builds the picture for [param p_kind], with [param p_variant] picking among the commons.
func build(p_kind: StringName, p_variant: int) -> void:
	if p_kind == kind and p_variant == variant and _model != null:
		return

	kind = p_kind
	variant = p_variant

	if _model != null:
		_model.queue_free()
		_model = null

	_look = LOOKS.get(kind, LOOKS[&"common"])
	var body_id: StringName = _look["body"]

	if body_id == &"":
		body_id = &"male" if (variant & 1) == 0 else &"female"

	var scene := _scene(BODIES[body_id])

	if scene == null:
		DotLog.warn(CHANNEL, "no zombie model; drawing a capsule", {"kind": String(kind)})
		_model = _capsule()
		add_child(_model)
		return

	_model = scene.instantiate() as Node3D
	add_child(_model)

	# The kit faces +Z; this family's forward is -Z.
	var height := float(_look["height"])

	if kind == &"common":
		height *= lerpf(0.9, 1.08, float((variant >> 2) & 15) / 15.0)

	var raw := _measure(_model)
	var by := height / maxf(raw.y, 0.01)
	var girth := float(_look["girth"])
	_model.basis = Basis(Vector3.UP, PI).scaled(Vector3(by * girth, by, by * girth))

	_skeleton = _model.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer

	if _anim != null:
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	if _skeleton != null:
		for bone in [&"LeftArm", &"RightArm", &"LeftForeArm", &"RightForeArm", &"Spine", &"Neck", &"Head"]:
			_bones[bone] = _skeleton.find_bone(String(bone))

	_paint()
	_clip = &""


func _paint() -> void:
	var skin_index := int(_look["skin"])

	if skin_index < 0:
		skin_index = (variant >> 1) % SKINS.size()

	var texture := _texture(SKINS[skin_index])
	var tint: Color = _look["tint"]

	if kind == &"common":
		# A crowd is not one colour: a little lighter or darker, warmer or colder, each.
		var shade := lerpf(0.82, 1.08, float((variant >> 6) & 15) / 15.0)
		tint = Color(tint.r * shade, tint.g * shade * lerpf(0.95, 1.05, float((variant >> 10) & 7) / 7.0), tint.b * shade)

	_material = StandardMaterial3D.new()
	_material.albedo_texture = texture
	_material.albedo_color = tint
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_material.roughness = 0.9

	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = _material


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null

	return _scenes[path]


static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null

	return _textures[path]


## The model's height at rest, from its skeleton's bones: a skinned mesh's own bounds are the
## unposed mesh in the rig's units, which for this kit is a tenth of a millimetre tall.
static func _measure(model: Node3D) -> Vector3:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)

	if skeletons.is_empty():
		return Vector3(0.6, 1.8, 0.4)

	var skeleton := skeletons.front() as Skeleton3D
	var low := INF
	var high := -INF

	# The skeleton's transform up to the model: the kit puts a scale on the node above it.
	var chain := Transform3D.IDENTITY
	var node: Node = skeleton

	while node != null and node != model:
		if node is Node3D:
			chain = (node as Node3D).transform * chain
		node = node.get_parent()

	for i in skeleton.get_bone_count():
		var at := (chain * skeleton.get_bone_global_rest(i)).origin
		low = minf(low, at.y)
		high = maxf(high, at.y)

	# The head bone is at the base of the skull; the top of the head is about a sixth higher.
	return Vector3(0.6, (high - low) * 1.12, 0.4)


func _capsule() -> Node3D:
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.32
	capsule.height = float(_look.get("height", 1.75))
	mesh.mesh = capsule
	mesh.position.y = capsule.height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = _look.get("tint", Color(0.5, 0.6, 0.5))
	mesh.material_override = material
	return mesh


## One frame: the clip for [param anim], the pose over it, and the flags drawn.
func present(delta: float, anim: int, flags: int) -> void:
	if _model == null:
		return

	var at := global_position
	if _last_at != Vector3.INF and delta > 0.0:
		var moved := Vector2(at.x - _last_at.x, at.z - _last_at.z).length() / delta
		_speed = lerpf(_speed, moved, clampf(delta * 8.0, 0.0, 1.0))
	_last_at = at

	var wanted: Array = CLIPS.get(anim, CLIPS[ZzZombieBody.Anim.IDLE])
	var clip: StringName = wanted[0]
	var rate := float(wanted[1])

	# A moving zombie whose state says idle (a mirror between states) walks rather than slides.
	if (anim == ZzZombieBody.Anim.IDLE or anim == ZzZombieBody.Anim.RAGE) and _speed > 0.6:
		clip = &"walk" if _speed < 3.0 else &"run"

	if clip == &"walk" or clip == &"run":
		var natural := 1.4 if clip == &"walk" else 5.5
		rate *= clampf(_speed / natural, 0.5, 1.8) if _speed > 0.2 else 1.0

	if kind == &"common" and (variant & 8) != 0 and anim == ZzZombieBody.Anim.ATTACK:
		clip = &"attack"

	_play(clip, rate)

	if _anim != null:
		_anim.advance(delta * rate)

	_pose(anim)
	_draw_flags(flags)

	if anim == ZzZombieBody.Anim.DEAD:
		_dead_for = maxf(_dead_for, 0.0) + delta


func _play(clip: StringName, _rate: float) -> void:
	if _anim == null or clip == _clip:
		return

	if not _anim.has_animation(clip):
		return

	_clip = clip
	_anim.play(clip, 0.15)


## The crowd's stance over whatever the legs are doing: arms up and forward, a hunch, a head
## that lolls. Written straight onto the bones after the clip.
func _pose(anim: int) -> void:
	if _skeleton == null:
		return

	var arms := float(_look["arms"])
	var hunch := float(_look["hunch"])

	# Arms come down to swing, to vomit, to throw, and in death.
	if anim in [ZzZombieBody.Anim.ATTACK, ZzZombieBody.Anim.PIN, ZzZombieBody.Anim.THROW,
			ZzZombieBody.Anim.VOMIT, ZzZombieBody.Anim.DEAD, ZzZombieBody.Anim.SPIT, ZzZombieBody.Anim.FEED]:
		arms = 0.0

	if arms > 0.0:
		for side in [[&"LeftArm", 1.0], [&"RightArm", -1.0]]:
			var bone: int = _bones.get(side[0], -1)
			if bone < 0:
				continue
			var reach := arms * (1.15 + 0.15 * sin(float(Time.get_ticks_msec()) * 0.003 + float(variant) + float(side[1])))
			var lift := Quaternion(Vector3.RIGHT, -reach * 1.1) * Quaternion(Vector3.FORWARD, float(side[1]) * reach * 0.25)
			_skeleton.set_bone_pose_rotation(bone, lift * _skeleton.get_bone_pose_rotation(bone))

	if hunch > 0.0:
		var spine: int = _bones.get(&"Spine", -1)
		if spine >= 0:
			_skeleton.set_bone_pose_rotation(spine, Quaternion(Vector3.RIGHT, hunch * 0.5) * _skeleton.get_bone_pose_rotation(spine))
		var head: int = _bones.get(&"Head", -1)
		if head >= 0:
			var loll := 0.25 * sin(float(Time.get_ticks_msec()) * 0.0011 + float(variant))
			_skeleton.set_bone_pose_rotation(head, Quaternion(Vector3.FORWARD, loll * hunch) * _skeleton.get_bone_pose_rotation(head))


func _draw_flags(flags: int) -> void:
	var burning := (flags & ZzZombieBody.FLAG_BURNING) != 0

	if burning and _fire == null:
		_fire = _make_fire()
		add_child(_fire)
	if _fire != null:
		_fire.emitting = burning

	var startled := (flags & ZzZombieBody.FLAG_STARTLED) != 0 or (flags & ZzZombieBody.FLAG_ENRAGED) != 0

	if startled and _eyes == null:
		_eyes = OmniLight3D.new()
		_eyes.light_color = Color(1.0, 0.15, 0.1)
		_eyes.omni_range = 2.5
		_eyes.light_energy = 1.2
		_eyes.position = Vector3(0.0, float(_look["height"]) * 0.92, -0.2)
		add_child(_eyes)
	if _eyes != null:
		_eyes.visible = startled

	if _material != null and kind == &"brute":
		var enraged := (flags & ZzZombieBody.FLAG_ENRAGED) != 0
		_material.emission_enabled = enraged
		_material.emission = Color(0.5, 0.05, 0.02)


func _make_fire() -> CPUParticles3D:
	var fire := CPUParticles3D.new()
	fire.name = "Fire"
	fire.amount = 24
	fire.lifetime = 0.6
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fire.emission_box_extents = Vector3(0.25, float(_look["height"]) * 0.4, 0.25)
	fire.position = Vector3(0.0, float(_look["height"]) * 0.5, 0.0)
	fire.direction = Vector3.UP
	fire.spread = 15.0
	fire.initial_velocity_min = 1.0
	fire.initial_velocity_max = 2.5
	fire.gravity = Vector3(0.0, 2.0, 0.0)
	fire.scale_amount_min = 0.15
	fire.scale_amount_max = 0.35
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(1.0, 0.55, 0.12, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = material
	fire.mesh = quad
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.8, 0.3, 1.0))
	gradient.set_color(1, Color(0.6, 0.1, 0.0, 0.0))
	fire.color_ramp = gradient
	return fire


## Seconds this one has been dead, or -1.
func dead_for() -> float:
	return _dead_for
