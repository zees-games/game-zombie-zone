extends Node3D

const ZzPaths := preload("../game/zz_paths.gd")
const ZzZombieBody := preload("zz_zombie_body.gd")

## What a zombie looks like: one of seven animated bodies from Quaternius' CC0 Zombie Apocalypse
## Kit, dressed by a palette shader, reshaped by its bones, and carrying whatever its kind wears
## (pustules, a helmet and shield, a tongue), playing the clip its body's [member ZzZombieBody.anim]
## asks for. The bodies are built by `tools/build_zombie_models.py`; the README credits the kit.
##
## [b]Client only.[/b] A server never builds one; it draws nothing. The body this hangs off is a
## client's mirror of the server's zombie, or (offline) the zombie itself.
##
## [b]A crowd is not one person.[/b] A common's 16-bit variant picks its body (five: the kit's
## zombie and its four survivors, turned), its skin from [constant SKINS], its clothes from
## [constant CLOTHES], its height, and where its blood and dirt are (the vertex-colour noise the
## build painted, cut at a threshold each zombie picks). That is 5 x 8 x 12 combinations before
## height, and a horde of forty has no two alike side by side. The previous model was one Kenney
## body in three shirts, and a play test called it out at once.
##
## [b]A special is read by its outline before its colour.[/b] Each kind is a different body or a
## different shape of one (bone scales: the brute's arms, the strangler's neck, the crawler's
## missing legs), stands differently (the leaper on all fours), and wears something nobody else
## does. The old ones were the same body in a tint, and a leaper that drew as two black polygons
## at the lens was a pin nobody could see coming.
##
## [b]The pose is written after the clip, every frame.[/b] The AnimationPlayer is advanced by
## hand ([method present]) and the bone shapes and the flinch applied after it, because left to
## the engine the clip and the override run in an order nothing controls and the clip wins.
##
## [b]Far zombies animate less often.[/b] [method present] advances a zombie past
## [constant LOD_NEAR] metres every second frame and past [constant LOD_FAR] every fourth, with
## the time it skipped, so its feet stay where its walk puts them. Skinning forty bodies is most
## of what a horde costs a browser; nobody can see a step at sixty metres.

const CHANNEL := "zz.zombie_view"

const LOD_NEAR := 22.0
const LOD_FAR := 45.0

## Below 1, the mesh switches to its simpler levels sooner. A crowd is small on screen.
const LOD_BIAS := 0.4

static var BODIES := {
	&"basic": ZzPaths.rebase("res://assets/zombies/zombie_basic.glb"),
	&"chubby": ZzPaths.rebase("res://assets/zombies/zombie_chubby.glb"),
	&"arm": ZzPaths.rebase("res://assets/zombies/zombie_arm.glb"),
	&"matt": ZzPaths.rebase("res://assets/zombies/zombie_matt.glb"),
	&"lis": ZzPaths.rebase("res://assets/zombies/zombie_lis.glb"),
	&"sam": ZzPaths.rebase("res://assets/zombies/zombie_sam.glb"),
	&"shaun": ZzPaths.rebase("res://assets/zombies/zombie_shaun.glb"),
	&"worker": ZzPaths.rebase("res://assets/zombies/zombie_worker.glb"),
}

## The kit's atlas, in the three versions its bodies were painted against: they differ in a few
## swatches, and a body drawn with another's atlas wears the wrong colours there.
static var ATLASES := {
	&"basic": ZzPaths.rebase("res://assets/zombies/atlas_basic.png"),
	&"heavy": ZzPaths.rebase("res://assets/zombies/atlas_heavy.png"),
	&"people": ZzPaths.rebase("res://assets/zombies/atlas_people.png"),
	## Ours, not the kit's: the worker's gear and dirt are baked in (`art-src/zombie_worker.py`).
	&"worker": ZzPaths.rebase("res://assets/zombies/atlas_worker.png"),
}

const ATLAS_OF := {&"basic": &"basic", &"chubby": &"heavy", &"arm": &"heavy", &"matt": &"people",
	&"lis": &"people", &"sam": &"people", &"shaun": &"people", &"worker": &"worker"}

## Bodies that carry no clips of their own and are driven by another's (same rig, same bone names).
const CLIPS_FROM := {&"matt": &"basic", &"lis": &"basic", &"sam": &"basic", &"shaun": &"basic"}

## The atlas colours each body wears, by role, measured from the kit (`tools/build_zombie_models.py`
## run with a probe: the colour under each face, by the bone that face follows). The shader swaps
## these for the look's colours.
const WEARS := {
	&"basic": {"skin": ["769751"], "bottom": ["3f5363"], "belt": ["664531"]},
	&"chubby": {"skin": ["5f6397"], "bottom": ["63503f"]},
	&"arm": {"skin": ["977525"], "bottom": ["3f5363"]},
	&"matt": {"skin": ["7c4e26"], "top": ["af6c1c"], "bottom": ["4e694b"]},
	&"lis": {"skin": ["c09264"], "top": ["bd8e30"], "bottom": ["466469"], "hair": ["225385"]},
	&"sam": {"skin": ["7c4e26"], "top": ["504c43"], "bottom": ["2a2927"], "hat": ["ac741d"]},
	&"shaun": {"skin": ["c09264"], "top": ["5f4009"], "bottom": ["466469"]},
	&"worker": {},  # painted in the atlas: nothing to swap
}

## The commons' bodies, in variant order.
const COMMON_BODIES: Array[StringName] = [&"basic", &"matt", &"lis", &"sam", &"shaun", &"worker"]

## Dead skin: grey-greens, ash, a bruised blue, jaundice, rot.
const SKINS: Array[String] = ["7d8f6a", "8f9a84", "8c98a0", "a39f6c", "66734f", "8a7a86", "9aa58a", "75806e"]

## Clothes: top, bottom. Faded, filthy, and nothing bright, so a special's colour is still news.
const CLOTHES: Array = [
	["6b4a3a", "3c4250"], ["4d5a6b", "2f3238"], ["7a6f55", "43483a"], ["5b2e2e", "3a3f4a"],
	["8a8a80", "4a4036"], ["3e5546", "5a5040"], ["6e5a7a", "36383c"], ["8f7a4e", "3d4a5a"],
	["a3a39a", "2c2e33"], ["455066", "6b5e48"], ["704c2a", "2f3a30"], ["5a5f63", "57442f"],
]

## Per kind: the body, how tall (m), how wide against that, its colours, which bones are reshaped
## (bone -> scale), how hunched, its clips where they differ, and what it wears (see [method _wear]).
const LOOKS := {
	&"common": {"body": &"", "height": 1.75, "girth": 1.0, "hunch": 0.1},
	&"leaper": {"body": &"sam", "height": 1.7, "girth": 0.9, "skin": "9ea39a", "top": "262d3d", "bottom": "202226", "hat": "1d2230",
		"bones": {"UpperArm.L*": 1.12, "UpperArm.R*": 1.12, "Head": 0.95}, "hunch": 0.35,
		"clips": {"walk": &"crawl", "idle": &"crawl", "run_arms": &"crawl", "run": &"crawl"}, "wear": [], "blood": 0.6},
	&"strangler": {"body": &"basic", "height": 2.05, "girth": 0.78, "skin": "8e9a5c", "bottom": "3b3a33", "belt": "2b2a26",
		"bones": {"Neck": Vector3(0.9, 2.2, 0.9), "Head": 0.85, "Tongue1*": Vector3(1.5, 2.6, 1.5)}, "hunch": 0.3, "wear": [&"neck_growth"], "blood": 0.62},
	&"bloater": {"body": &"chubby", "height": 1.85, "girth": 1.4, "skin": "a8a45a", "bottom": "4a3f30",
		"bones": {"Abdomen": Vector3(1.45, 1.0, 1.45), "Torso": Vector3(1.25, 1.0, 1.3), "Head": 0.9}, "hunch": 0.0, "wear": [&"boils"], "blood": 0.7},
	&"ram": {"body": &"arm", "height": 2.05, "girth": 1.1, "skin": "6e6152", "bottom": "2e3440",
		"bones": {}, "hunch": 0.2, "wear": [], "blood": 0.64},
	&"spitter": {"body": &"lis", "height": 1.95, "girth": 0.8, "skin": "9fb35a", "top": "3d4a2e", "bottom": "2c2e26", "hair": "1c1d18",
		"bones": {"Neck": Vector3(0.9, 2.4, 0.9), "Head": 0.9}, "hunch": 0.15, "wear": [&"acid_mouth"], "blood": 0.65, "glow": "4f8a12"},
	&"rider": {"body": &"basic", "height": 1.2, "girth": 1.0, "skin": "8a7a66", "bottom": "4a3a2a", "belt": "2a221a",
		"bones": {"UpperArm.L*": 1.35, "UpperArm.R*": 1.35, "Head": 1.15, "UpperLeg.L*": 0.8, "UpperLeg.R*": 0.8}, "hunch": 0.55, "wear": [], "blood": 0.64,
		"clips": {"run": &"run_arms", "walk": &"run_arms"}},
	&"brute": {"body": &"chubby", "height": 2.95, "girth": 1.55, "skin": "5e5263", "bottom": "2e2a2a",
		"bones": {"UpperArm.L*": 1.4, "UpperArm.R*": 1.4, "Shoulder.L": 1.3, "Shoulder.R": 1.3, "Head": 0.6, "Torso": Vector3(1.2, 1.0, 1.15)}, "hunch": 0.35,
		"wear": [&"spikes"], "blood": 0.62},
	&"sleeper": {"body": &"lis", "height": 1.65, "girth": 0.85, "skin": "e4e4e8", "top": "d6d2c8", "bottom": "c8c2b8", "hair": "16161a",
		"bones": {"Index1.L*": Vector3(0.8, 1.9, 0.8), "Index1.R*": Vector3(0.8, 1.9, 0.8), "Middle1.L*": Vector3(0.8, 1.9, 0.8), "Middle1.R*": Vector3(0.8, 1.9, 0.8), "Pinky1.L*": Vector3(0.8, 1.9, 0.8), "Pinky1.R*": Vector3(0.8, 1.9, 0.8)},
		"hunch": 0.0, "wear": [&"red_eyes"], "blood": 0.62},
	&"screamer": {"body": &"chubby", "height": 2.0, "girth": 0.72, "skin": "b6bfc6", "bottom": "3a1e22",
		"bones": {"Abdomen": Vector3(0.62, 1.15, 0.62), "Torso": Vector3(0.68, 1.1, 0.7), "Neck": Vector3(0.8, 1.6, 0.8), "BottomMouth": 1.4}, "hunch": 0.2,
		"wear": [], "blood": 0.62},
	&"crawler": {"body": &"basic", "height": 1.75, "girth": 1.0, "skin": "6f7a55", "bottom": "3a3a30", "belt": "4a2020",
		"bones": {"UpperLeg.L*": 0.04, "UpperLeg.R*": 0.04}, "hunch": 0.0,
		"clips": {"idle": &"crawl", "walk": &"crawl", "run": &"crawl", "run_arms": &"crawl", "attack": &"crawl", "attack_idle": &"crawl", "attack_run": &"crawl", "hit": &"crawl", "jump_idle": &"crawl"}, "wear": [&"gore"], "blood": 0.55},
	&"riot": {"body": &"sam", "height": 1.85, "girth": 1.1, "skin": "7f8b6e", "top": "1e2430", "bottom": "1b1f28", "hat": "1c2230",
		"bones": {}, "hunch": 0.05, "wear": [&"helmet", &"shield"], "blood": 0.6},
}

## Which clip an animation state plays, and how fast.
const CLIPS := {
	ZzZombieBody.Anim.IDLE: [&"idle", 1.0],
	ZzZombieBody.Anim.WALK: [&"walk", 1.0],
	ZzZombieBody.Anim.SHAMBLE: [&"walk", 0.7],
	ZzZombieBody.Anim.RUN: [&"run_arms", 1.0],
	ZzZombieBody.Anim.ATTACK: [&"attack", 1.25],
	ZzZombieBody.Anim.STAGGER: [&"hit", 0.9],
	ZzZombieBody.Anim.SIT: [&"crawl", 0.0],
	ZzZombieBody.Anim.FEED: [&"crawl", 0.25],
	ZzZombieBody.Anim.CROUCH: [&"crawl", 1.2],
	ZzZombieBody.Anim.LEAP: [&"jump_idle", 1.0],
	ZzZombieBody.Anim.PIN: [&"attack", 2.0],
	ZzZombieBody.Anim.VOMIT: [&"attack_idle", 1.3],
	ZzZombieBody.Anim.SPIT: [&"attack", 1.0],
	ZzZombieBody.Anim.CHARGE: [&"run", 1.5],
	ZzZombieBody.Anim.CARRY: [&"run", 1.3],
	ZzZombieBody.Anim.THROW: [&"attack_idle", 0.8],
	ZzZombieBody.Anim.CRY: [&"crawl", 0.0],
	ZzZombieBody.Anim.RAGE: [&"attack_idle", 1.0],
	ZzZombieBody.Anim.TONGUE: [&"idle", 0.6],
	ZzZombieBody.Anim.DEAD: [&"death", 1.0],
	ZzZombieBody.Anim.CRAWL: [&"crawl", 1.0],
	ZzZombieBody.Anim.SCREAM: [&"attack_idle", 0.6],
	ZzZombieBody.Anim.GRAB: [&"crawl", 2.2],
	ZzZombieBody.Anim.BLOCK: [&"walk", 0.8],
}

## Clips that loop; the rest play once and hold their last frame.
const LOOPING: Array[StringName] = [&"idle", &"walk", &"run", &"run_arms", &"crawl", &"attack_idle", &"jump_idle", &"attack_run"]

## The palette shader. Up to [constant SWAPS] atlas colours swapped for others (matched within a
## tolerance, so the gradient swatches keep their shading), then dirt and blood from the
## vertex-colour noise, then the kind's glow. Written for the compatibility renderer: no
## per-instance uniforms (a material per look instead), no arrays with hints.
const SWAPS := 6
const SHADER := """
shader_type spatial;
render_mode cull_back, specular_disabled;
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform vec4 from_colour[6];
uniform vec4 to_colour[6];
uniform vec4 from_linear[6];
uniform vec4 to_linear[6];
uniform int swaps = 0;
uniform float tolerance = 0.004;
uniform float dirt = 0.5;
uniform float blood_cut = 0.6;
uniform vec3 blood_colour : source_color = vec3(0.45, 0.06, 0.05);
uniform vec3 glow = vec3(0.0);
uniform float flash = 0.0;

void fragment() {
	// Sampled exactly as a StandardMaterial3D samples its albedo (source_color), so a zombie is
	// lit like everything else on the street. Which space that hands back differs by renderer
	// (the compatibility one gave the stored sRGB values here), so a swap is matched in both and
	// answered in the space it matched: a shader that converted by hand drew every zombie a
	// shade from black at night.
	vec3 c = texture(atlas, UV).rgb;
	for (int i = 0; i < swaps; i++) {
		vec3 d = c - from_colour[i].rgb;
		if (dot(d, d) < tolerance) {
			c = to_colour[i].rgb;
			break;
		}
		vec3 e = c - from_linear[i].rgb;
		if (dot(e, e) < tolerance * 0.25) {
			c = to_linear[i].rgb;
			break;
		}
	}
	c *= mix(1.0, 0.6, smoothstep(0.45, 0.85, COLOR.r) * dirt);
	c *= mix(0.88, 1.05, COLOR.b);
	// Blood where two noises agree: splashes rather than a coat.
	float blood = smoothstep(blood_cut, blood_cut + 0.05, COLOR.g) * smoothstep(0.52, 0.6, COLOR.r);
	c = mix(c, blood_colour, blood * 0.85);
	ALBEDO = c;
	ROUGHNESS = mix(0.9, 0.3, blood);
	EMISSION = glow + vec3(flash * 0.35, flash * 0.05, flash * 0.03);
}
"""

var kind: StringName = &""
var variant: int = -1

## The body this look was built on, for a suite to read.
var body_id: StringName = &""

var _model: Node3D = null
var _anim: AnimationPlayer = null
var _skeleton: Skeleton3D = null
var _mesh: MeshInstance3D = null
var _bones: Dictionary = {}
var _shape_bones: Dictionary = {}
var _dead_bones: Dictionary = {}
var _clip: StringName = &""
var _look: Dictionary = {}
var _material: ShaderMaterial = null
var _fire: CPUParticles3D = null
var _eyes: OmniLight3D = null
var _drip: CPUParticles3D = null
var _last_at: Vector3 = Vector3.INF
var _last_y: float = 0.0
var _speed: float = 0.0
var _climb: float = 0.0
var _dead_for: float = -1.0
var _owed: float = 0.0
var _frame: int = 0
var _flinch: float = 0.0
var _flinch_side: float = 1.0
var _hunch: float = 0.0
var _scale: float = 1.0

## A death being drawn: the reaction's id, which way the hit pushed, how hard, and the seed.
var _death: Dictionary = {}
var _death_from: Transform3D = Transform3D.IDENTITY

static var _scenes: Dictionary = {}
static var _libraries: Dictionary = {}
static var _materials: Dictionary = {}
static var _shader: Shader = null
static var _atlases: Dictionary = {}


## Builds the picture for [param p_kind], with [param p_variant] picking among the commons.
func build(p_kind: StringName, p_variant: int) -> void:
	if p_kind == kind and p_variant == variant and _model != null:
		return

	kind = p_kind
	variant = p_variant

	if _model != null:
		_model.queue_free()
		_model = null

	_look = look_for(kind, variant)
	body_id = _look["body"]
	var scene := _scene(BODIES.get(body_id, ""))

	if scene == null:
		DotLog.warn(CHANNEL, "no zombie model; drawing a capsule", {"kind": String(kind), "body": String(body_id)})
		_model = _capsule()
		add_child(_model)
		return

	_model = scene.instantiate() as Node3D
	add_child(_model)

	_skeleton = _model.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	_mesh = _model.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer

	if _anim == null:
		_anim = AnimationPlayer.new()
		_anim.name = "AnimationPlayer"
		_model.add_child(_anim)

	var library := _library_for(body_id, _skeleton)

	if library != null and not _anim.has_animation_library(&"zz"):
		var _added := _anim.add_animation_library(&"zz", library)

	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	# The kit faces +Z; this family's forward is -Z.
	var raw := _measure(_skeleton, _model)
	_scale = float(_look["height"]) / maxf(raw, 0.01)
	var girth := float(_look["girth"])
	_model.basis = Basis(Vector3.UP, PI).scaled(Vector3(_scale * girth, _scale, _scale * girth))
	_hunch = float(_look.get("hunch", 0.0))

	_bones.clear()
	for bone in [&"Abdomen", &"Torso", &"Neck", &"Head", &"Hips", &"Tongue1", &"Tongue2", &"Tongue3", &"BottomMouth"]:
		_bones[bone] = _skeleton.find_bone(String(bone))

	_shape_bones = shape_scales(_skeleton, _look.get("bones", {}))
	# Dead, a tongue is not held out: the strangler's otherwise stands straight up off the corpse.
	var limp: Dictionary = (_look.get("bones", {}) as Dictionary).duplicate()
	for key: String in limp.keys():
		if key.begins_with("Tongue"):
			limp.erase(key)
	_dead_bones = shape_scales(_skeleton, limp)

	_mesh.material_override = _material_for(_look)
	_material = _mesh.material_override as ShaderMaterial
	# A zombie a long way off is not drawn at all: the far end of a street is where a horde
	# is thickest and where nobody can make one out.
	_mesh.visibility_range_end = 120.0
	_mesh.lod_bias = LOD_BIAS
	_mesh.visibility_range_end_margin = 10.0

	for item: StringName in _look.get("wear", []):
		_wear(item)

	_clip = &""
	_play(&"idle", 1.0)


## The look of [param p_kind] (and, for a common, of [param p_variant]): a dictionary in the
## shape of [constant LOOKS], with the common's body and colours filled in.
static func look_for(p_kind: StringName, p_variant: int) -> Dictionary:
	var look: Dictionary = (LOOKS.get(p_kind, LOOKS[&"common"]) as Dictionary).duplicate()

	if look["body"] != &"":
		return look

	var v := p_variant & 0xFFFF
	look["body"] = COMMON_BODIES[v % COMMON_BODIES.size()]
	look["skin"] = SKINS[(v >> 3) % SKINS.size()]
	var clothes: Array = CLOTHES[(v >> 6) % CLOTHES.size()]
	look["top"] = clothes[0]
	look["bottom"] = clothes[1]
	look["belt"] = clothes[1]
	look["hair"] = ["1e1a16", "4a3626", "6e5a3e", "2a2a2a"][(v >> 10) & 3]
	look["height"] = float(look["height"]) * lerpf(0.9, 1.07, float((v >> 12) & 15) / 15.0)
	look["girth"] = lerpf(0.92, 1.12, float((v >> 4) & 3) / 3.0)
	look["blood"] = lerpf(0.5, 0.72, float((v >> 2) & 7) / 7.0)
	look["dirt"] = lerpf(0.3, 0.8, float((v >> 9) & 7) / 7.0)
	return look


## The pose scale each bone needs for [param shapes], a look's `bones`: bone name -> the size that
## bone's own stretch of the body should be drawn at (a number, or a Vector3 in the bone's axes, Y
## along the bone, for thicker without longer). A name ending in `*` sizes the bone and everything
## below it (a whole arm).
##
## [b]Sizes are the bone's own, not inherited.[/b] A pose scale carries down to every child, so
## the strangler's long neck would give it a giant head and the screamer's thin waist a doll's
## arms. Each bone is drawn at its wanted size divided by its parent's, so a neck can be long and
## the head on it ordinary.
static func shape_scales(skeleton: Skeleton3D, shapes: Dictionary) -> Dictionary:
	var out := {}

	if skeleton == null or shapes.is_empty():
		return out

	var wanted := {}

	for key: String in shapes:
		var value: Variant = shapes[key]
		var size: Vector3 = value if value is Vector3 else Vector3.ONE * float(value)
		var whole := key.ends_with("*")
		var index := skeleton.find_bone(key.trim_suffix("*"))

		if index < 0:
			continue

		wanted[index] = size

		if whole:
			for child in _descendants(skeleton, index):
				wanted[child] = size

	for i in skeleton.get_bone_count():
		var own: Vector3 = wanted.get(i, Vector3.ONE)
		var parent := skeleton.get_bone_parent(i)
		var above: Vector3 = wanted.get(parent, Vector3.ONE) if parent >= 0 else Vector3.ONE
		var pose := own / above

		if not pose.is_equal_approx(Vector3.ONE):
			out[i] = pose

	return out


static func _descendants(skeleton: Skeleton3D, index: int) -> PackedInt32Array:
	var out := PackedInt32Array()

	for child in skeleton.get_bone_children(index):
		out.append(child)
		out.append_array(_descendants(skeleton, child))

	return out


## How many distinct commons [method look_for] can give, before height: bodies x skins x clothes.
static func common_variety() -> int:
	return COMMON_BODIES.size() * SKINS.size() * CLOTHES.size()


static func _scene(path: String) -> PackedScene:
	if path == "":
		return null

	if not _scenes.has(path):
		# Imported or not: a pull that brought new zombies and no editor run left them all capsules.
		_scenes[path] = DotHumanoidFigure.load_model(path)

	return _scenes[path]


## The clips of [param id]'s body, shared by every zombie drawn with them, with the loop modes set.
static func _library(id: StringName) -> AnimationLibrary:
	if _libraries.has(id):
		return _libraries[id]

	var library: AnimationLibrary = null
	var scene := _scene(BODIES.get(id, ""))

	if scene != null:
		var probe := scene.instantiate()
		var player := probe.find_child("AnimationPlayer", true, false) as AnimationPlayer

		if player != null:
			library = AnimationLibrary.new()

			for clip in player.get_animation_list():
				var animation := player.get_animation(clip)
				animation.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(StringName(clip)) else Animation.LOOP_NONE
				var _added := library.add_animation(StringName(clip), animation)

		probe.free()

	_libraries[id] = library
	return library


## The clips [param id] plays: its own, or (a survivor body) zombie_basic's carried over onto its
## skeleton by [method _retarget], once per body and shared.
static func _library_for(id: StringName, skeleton: Skeleton3D) -> AnimationLibrary:
	if not CLIPS_FROM.has(id):
		return _library(id)

	var key := StringName("%s<-%s" % [id, CLIPS_FROM[id]])

	if not _libraries.has(key):
		_libraries[key] = _retarget(_library(CLIPS_FROM[id]), _rests(CLIPS_FROM[id]), skeleton)

	return _libraries[key]


## The rest pose of [param id]'s skeleton, bone name -> local rest transform.
static func _rests(id: StringName) -> Dictionary:
	var key := StringName("rests:" + String(id))

	if _libraries.has(key):
		return _libraries[key]

	var out := {}
	var scene := _scene(BODIES.get(id, ""))

	if scene != null:
		var probe := scene.instantiate()
		var skeleton := probe.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
		for i in skeleton.get_bone_count():
			out[skeleton.get_bone_name(i)] = skeleton.get_bone_rest(i)
		probe.free()

	_libraries[key] = out
	return out


## [param library]'s clips, moved from a skeleton with rests [param from] onto [param to].
##
## [b]A clip stores where each bone is, not how far it moved.[/b] The survivor bodies share the
## zombie's bone names but not its rest pose (their chest bone points up, the zombie's leans
## forward), so the zombie's clips played as they are bent every survivor over at the waist and
## swung their gear about. What the animator made is the motion away from rest, so each key is
## taken off the zombie's rest and put on the survivor's: rotation `to * from^-1 * key`, a
## position by the same turn about the new rest.
static func _retarget(library: AnimationLibrary, from: Dictionary, to: Skeleton3D) -> AnimationLibrary:
	if library == null or to == null:
		return library

	var out := AnimationLibrary.new()

	for clip in library.get_animation_list():
		var animation := library.get_animation(clip).duplicate(true) as Animation

		for t in animation.get_track_count():
			var bone := String(animation.track_get_path(t).get_concatenated_subnames())
			var index := to.find_bone(bone)

			if index < 0 or not from.has(bone):
				continue

			var a: Transform3D = from[bone]
			var b := to.get_bone_rest(index)
			var turn := b.basis.get_rotation_quaternion() * a.basis.get_rotation_quaternion().inverse()

			match animation.track_get_type(t):
				Animation.TYPE_ROTATION_3D:
					for k in animation.track_get_key_count(t):
						var q: Quaternion = animation.track_get_key_value(t, k)
						animation.track_set_key_value(t, k, (turn * q).normalized())
				Animation.TYPE_POSITION_3D:
					for k in animation.track_get_key_count(t):
						var p: Vector3 = animation.track_get_key_value(t, k)
						animation.track_set_key_value(t, k, b.origin + turn * (p - a.origin))

		var _added := out.add_animation(clip, animation)

	return out


## One material per look: zombies with the same colours share it, and a crowd of forty is a
## handful of materials rather than forty.
static func _material_for(look: Dictionary) -> ShaderMaterial:
	var wears: Dictionary = WEARS.get(look["body"], {})
	# vec4, not vec3: a vec3 array's elements are padded to four floats on the GPU, and a
	# PackedVector3Array set into one is read skewed.
	var from := PackedVector4Array()
	var to := PackedVector4Array()
	var from_lin := PackedVector4Array()
	var to_lin := PackedVector4Array()

	for role: String in ["skin", "top", "bottom", "belt", "hair", "hat"]:
		if not look.has(role) or not wears.has(role):
			continue

		for hex: String in wears[role]:
			if from.size() >= SWAPS:
				break
			from.append(_raw(hex))
			to.append(_raw(str(look[role])))
			from_lin.append(_lin(hex))
			to_lin.append(_lin(str(look[role])))

	var glow := Color(str(look.get("glow", "000000")))
	var key := "%s|%s|%s|%.2f|%.2f|%s" % [look["body"], from, to, float(look.get("blood", 0.6)), float(look.get("dirt", 0.5)), glow.to_html()]

	if _materials.has(key):
		return _materials[key]

	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER

	var atlas_id: StringName = ATLAS_OF.get(look["body"], &"basic")

	if not _atlases.has(atlas_id):
		var path: String = ATLASES[atlas_id]
		_atlases[atlas_id] = DotHumanoidFigure.load_texture(path)

	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter(&"atlas", _atlases[atlas_id])

	while from.size() < SWAPS:
		from.append(Vector4(-9.0, -9.0, -9.0, 0.0))
		to.append(Vector4.ZERO)
		from_lin.append(Vector4(-9.0, -9.0, -9.0, 0.0))
		to_lin.append(Vector4.ZERO)

	material.set_shader_parameter(&"from_colour", from)
	material.set_shader_parameter(&"to_colour", to)
	material.set_shader_parameter(&"from_linear", from_lin)
	material.set_shader_parameter(&"to_linear", to_lin)
	material.set_shader_parameter(&"swaps", SWAPS)
	material.set_shader_parameter(&"blood_cut", float(look.get("blood", 0.6)))
	material.set_shader_parameter(&"dirt", float(look.get("dirt", 0.5)))
	var g := glow.srgb_to_linear()
	material.set_shader_parameter(&"glow", Vector3(g.r, g.g, g.b))
	_materials[key] = material
	return material


static func _lin(hex: String) -> Vector4:
	var c := Color(hex).srgb_to_linear()
	return Vector4(c.r, c.g, c.b, 1.0)


static func _raw(hex: String) -> Vector4:
	var c := Color(hex)
	return Vector4(c.r, c.g, c.b, 1.0)



## The model's height at rest, from its skeleton's bones: a skinned mesh's own bounds are the
## unposed mesh.
static func _measure(skeleton: Skeleton3D, model: Node3D) -> float:
	if skeleton == null:
		return 1.75

	var chain := Transform3D.IDENTITY
	var node: Node = skeleton

	while node != null and node != model:
		if node is Node3D:
			chain = (node as Node3D).transform * chain
		node = node.get_parent()

	var low := INF
	var high := -INF

	for i in skeleton.get_bone_count():
		var at := (chain * skeleton.get_bone_global_rest(i)).origin
		low = minf(low, at.y)
		high = maxf(high, at.y)

	var head := skeleton.find_bone("Head")
	# The head bone is at the base of the skull; this kit's heads are big, about a third more.
	var top := high

	if head >= 0:
		top = (chain * skeleton.get_bone_global_rest(head)).origin.y * 1.22

	return maxf(top, high) - minf(low, 0.0)


## The bone origins of [param p_kind]'s body in the body's own space as drawn (turned, scaled to
## its height and girth), filed under the returned key in [method DotNpcLimbs.rest_points]: the
## server draws nothing, and its limb regions must still sit where a client sees the limbs.
static func limb_rest(p_kind: StringName, p_variant: int) -> String:
	var look := look_for(p_kind, p_variant)
	var scene := _scene(BODIES.get(look["body"], ""))

	if scene == null:
		return ""

	var key := "zz-rest:%s:%.3f:%.3f" % [look["body"], float(look["height"]), float(look["girth"])]
	var filed := DotNpcLimbs.rest_points(key)

	if not filed.is_empty():
		return key

	var root := scene.instantiate() as Node3D
	var found := root.find_children("*", "Skeleton3D", true, false)

	if not found.is_empty():
		var skeleton := found[0] as Skeleton3D
		var chain := Transform3D.IDENTITY
		var node: Node = skeleton

		while node != null and node != root:
			if node is Node3D:
				chain = (node as Node3D).transform * chain
			node = node.get_parent()

		var fit := float(look["height"]) / maxf(_measure(skeleton, root), 0.01)
		var girth := float(look["girth"])
		var drawn := Basis(Vector3.UP, PI).scaled(Vector3(fit * girth, fit, fit * girth))

		for i in skeleton.get_bone_count():
			var bone := skeleton.get_bone_name(i)
			filed[StringName(bone)] = drawn * (chain * skeleton.get_bone_global_rest(i)).origin

			if skeleton.get_bone_parent(i) >= 0:
				filed["@" + bone] = StringName(skeleton.get_bone_name(skeleton.get_bone_parent(i)))

	root.free()
	return key


## [DotNpcLimbs]' view seam: takes a limb off the drawn body, and returns where it was cut.
func sever_limb(limb: StringName, d: Dictionary, impulse: Vector3) -> Vector3:
	if _skeleton == null or _model == null:
		return Vector3.INF

	return DotNpcGibs.sever(_skeleton, _model, "%s/%s" % [body_id, limb], limb, d, impulse)


## A limb that was gone before this machine saw the zombie: the stump alone.
func stump_limb(limb: StringName, d: Dictionary) -> Vector3:
	if _skeleton == null or _model == null:
		return Vector3.INF

	return DotNpcGibs.sever(_skeleton, _model, "%s/%s" % [body_id, limb], limb, d, Vector3.ZERO, true)


func restore_limbs() -> void:
	if _skeleton != null:
		DotNpcGibs.restore(_skeleton, _model)


func _capsule() -> Node3D:
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.32
	capsule.height = float(_look.get("height", 1.75))
	mesh.mesh = capsule
	mesh.position.y = capsule.height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.6, 0.5)
	mesh.material_override = material
	return mesh


# --- What a kind wears ---------------------------------------------------------------------------

## Puts [param item] on the model, hung off the bone it moves with. Simple shapes in the atlas's
## flat-shaded style; each is one more draw call, which is why only specials wear anything.
func _wear(item: StringName) -> void:
	match item:
		&"boils":
			for spot: Array in [[&"Abdomen", Vector3(0.12, 0.05, 0.16), 0.11], [&"Abdomen", Vector3(-0.16, 0.1, 0.12), 0.09],
					[&"Torso", Vector3(0.05, 0.12, 0.18), 0.1], [&"Torso", Vector3(-0.12, 0.2, -0.14), 0.08],
					[&"Abdomen", Vector3(0.18, -0.05, -0.1), 0.1], [&"Torso", Vector3(0.18, 0.15, 0.02), 0.07]]:
				_attach(spot[0], _sphere(float(spot[2]), Color("c4bf5a"), Color("2a2a00")), spot[1])
		&"neck_growth":
			_attach(&"Neck", _sphere(0.09, Color("b9a55a"), Color.BLACK), Vector3(0.08, 0.05, 0.02))
			_attach(&"Neck", _sphere(0.07, Color("a3904a"), Color.BLACK), Vector3(0.1, 0.1, -0.04))
			_attach(&"Torso", _sphere(0.08, Color("b9a55a"), Color.BLACK), Vector3(0.14, 0.25, 0.0))
		&"acid_mouth":
			# A throat swollen with what it spits, lit from inside: the one green light on a street.
			var sac := _sphere(0.15, Color("8fdc3a"), Color("3f8a0c"))
			sac.scale = Vector3(1.1, 0.9, 1.0)
			_attach(&"Neck", sac, Vector3(0.0, 0.0, 0.1))
			var mouth := _sphere(0.06, Color("b6ff5a"), Color("6cd018"))
			_attach(&"Head", mouth, Vector3(0.0, 0.12, 0.3))
			_drip = _make_drip()
			mouth.add_child(_drip)
		&"spikes":
			for i in 5:
				var cone := _cone(0.06, 0.26, Color("d8cdb0"))
				_attach(&"Torso", cone, Vector3(lerpf(-0.22, 0.22, float(i) / 4.0), 0.2 + 0.06 * float(i % 2), -0.22),
					Vector3(deg_to_rad(-55.0), 0.0, deg_to_rad(lerpf(30.0, -30.0, float(i) / 4.0))))
		&"red_eyes":
			_attach(&"Head", _sphere(0.04, Color("ff2010"), Color("ff1008")), Vector3(0.09, 0.26, 0.3))
			_attach(&"Head", _sphere(0.04, Color("ff2010"), Color("ff1008")), Vector3(-0.09, 0.26, 0.3))
		&"hood":
			var hood := _sphere(0.2, Color("262d3d"), Color.BLACK)
			hood.scale = Vector3(1.05, 1.0, 1.1)
			_attach(&"Head", hood, Vector3(0.0, 0.14, -0.05))
		&"gore":
			_attach(&"Hips", _sphere(0.13, Color("5a1010"), Color("1a0000")), Vector3(0.0, -0.05, 0.0))
		&"helmet":
			var shell := _sphere(0.29, Color("1c2230"), Color.BLACK)
			shell.scale = Vector3(1.0, 0.85, 1.05)
			_attach(&"Head", shell, Vector3(0.0, 0.22, 0.0))
			var visor := _box(Vector3(0.42, 0.14, 0.04), Color("6f8aa0"))
			_attach(&"Head", visor, Vector3(0.0, 0.12, 0.27))
		&"shield":
			var shield := _box(Vector3(0.62, 0.95, 0.05), Color("2a3240"))
			var stripe := _box(Vector3(0.63, 0.07, 0.055), Color("d8d8d0"))
			stripe.position = Vector3(0.0, 0.25, 0.0)
			shield.add_child(stripe)
			var window := _box(Vector3(0.4, 0.16, 0.056), Color("8aa0b4"))
			window.position = Vector3(0.0, 0.36, 0.0)
			shield.add_child(window)
			_attach(&"Torso", shield, Vector3(0.0, 0.0, 0.42))


## Hangs [param item] off [param bone]: [param offset] is in metres from the bone's joint, in the
## body's own axes (+Y up, +Z the way it faces, at rest), and [param turn] likewise. The kit's
## bones point every which way (the torso bone leans forward along the chest), so an offset in
## the bone's own axes put the riot shield flat under its chin.
func _attach(bone: StringName, item: Node3D, offset: Vector3, turn: Vector3 = Vector3.ZERO) -> void:
	var index := _skeleton.find_bone(String(bone)) if _skeleton != null else -1

	if index < 0:
		item.free()
		return

	var mount := BoneAttachment3D.new()
	mount.bone_name = String(bone)
	_skeleton.add_child(mount)
	var unit := maxf(_scale, 0.01)
	var rest := _skeleton.get_bone_global_rest(index)
	var placed := Transform3D(Basis.from_euler(turn).scaled(item.scale / unit), rest.origin + offset / unit)
	item.transform = rest.affine_inverse() * placed
	mount.add_child(item)


func _sphere(radius: float, colour: Color, emit: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mesh.mesh = sphere
	mesh.material_override = _flat(colour, emit)
	return mesh


func _cone(radius: float, length: float, colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = length
	cone.radial_segments = 6
	mesh.mesh = cone
	mesh.material_override = _flat(colour, Color.BLACK)
	return mesh


func _box(size: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _flat(colour, Color.BLACK)
	return mesh


static func _flat(colour: Color, emit: Color) -> StandardMaterial3D:
	var key := "flat|%s|%s" % [colour.to_html(), emit.to_html()]

	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.6
		if emit != Color.BLACK:
			material.emission_enabled = true
			material.emission = emit
		_materials[key] = material

	return _materials[key]


func _make_drip() -> CPUParticles3D:
	var drip := CPUParticles3D.new()
	drip.name = "Drip"
	drip.amount = 8
	drip.lifetime = 0.8
	drip.direction = Vector3.DOWN
	drip.spread = 10.0
	drip.initial_velocity_min = 0.2
	drip.initial_velocity_max = 0.5
	drip.gravity = Vector3(0.0, -6.0, 0.0)
	drip.scale_amount_min = 0.03
	drip.scale_amount_max = 0.06
	drip.local_coords = false
	var quad := SphereMesh.new()
	quad.radius = 0.5
	quad.height = 1.0
	quad.radial_segments = 4
	quad.rings = 2
	quad.material = _flat(Color("9cff3a"), Color("5cc010"))
	drip.mesh = quad
	return drip


# --- The frame -----------------------------------------------------------------------------------

## One frame: the clip for [param anim], the pose over it, and the flags drawn.
func present(delta: float, anim: int, flags: int) -> void:
	if _model == null:
		return

	_frame += 1
	var at := global_position

	if _last_at != Vector3.INF and delta > 0.0:
		var moved := Vector2(at.x - _last_at.x, at.z - _last_at.z).length() / delta
		_speed = lerpf(_speed, moved, clampf(delta * 8.0, 0.0, 1.0))
		_climb = lerpf(_climb, (at.y - _last_y) / delta, clampf(delta * 10.0, 0.0, 1.0))
	_last_at = at
	_last_y = at.y

	if anim == ZzZombieBody.Anim.DEAD and _death.is_empty():
		die(&"limp", Vector3.ZERO, variant)

	var wanted: Array = CLIPS.get(anim, CLIPS[ZzZombieBody.Anim.IDLE])
	var clip: StringName = wanted[0]
	var rate := float(wanted[1])

	# A moving zombie whose state says idle (a mirror between states) walks rather than slides.
	if (anim == ZzZombieBody.Anim.IDLE or anim == ZzZombieBody.Anim.RAGE) and _speed > 0.6:
		clip = &"walk" if _speed < 3.0 else &"run_arms"
		rate = 1.0

	# Off the ground and going up or falling fast: a climb, a leap, a drop from a ledge.
	if anim != ZzZombieBody.Anim.DEAD and anim != ZzZombieBody.Anim.LEAP and absf(_climb) > 2.5:
		clip = &"jump_idle"

	# A common lunging while it runs swings on the move.
	if anim == ZzZombieBody.Anim.ATTACK and _speed > 1.5:
		clip = &"attack_run"
	elif anim == ZzZombieBody.Anim.ATTACK and kind == &"common" and (variant & 8) != 0:
		clip = &"attack_idle"

	var overrides: Dictionary = _look.get("clips", {})
	clip = overrides.get(clip, clip)

	if clip == &"walk" or clip == &"run" or clip == &"run_arms" or clip == &"crawl":
		var natural := {&"walk": 1.3, &"run": 5.0, &"run_arms": 5.0, &"crawl": 1.2}[clip] as float
		natural *= float(_look["height"]) / 1.75
		if _speed > 0.2 and rate > 0.0:
			rate = clampf(_speed / natural, 0.5, 1.8)

	_play(clip, rate)

	# Level of detail: how often this one is advanced, by how far it is from the camera.
	var every := 1
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null

	if camera != null and _death.is_empty():
		var far := camera.global_position.distance_to(at)
		every = 4 if far > LOD_FAR else (2 if far > LOD_NEAR else 1)

	_owed += delta
	_flinch = maxf(_flinch - delta * 4.0, 0.0)

	# The bones are written only on a frame the clip was evaluated: the overrides go on top of
	# the clip's pose, so writing them again over last frame's result would stack them.
	if (_frame + (variant & 3)) % every == 0:
		if _anim != null and _anim.has_animation(_qualified(clip)):
			var length := _anim.current_animation_length
			var looping := LOOPING.has(clip)

			if not looping and _anim.current_animation_position + _owed * rate >= length - 0.01:
				# A one-shot clip holds its last frame; evaluated there rather than stepped past
				# the end, where the player stops and nothing writes the pose again.
				_anim.seek(maxf(length - 0.01, 0.0), true)
			else:
				_anim.advance(_owed * rate)

		_owed = 0.0
		_pose(anim)

	_draw_flags(flags)

	if anim == ZzZombieBody.Anim.DEAD:
		_dead_for = maxf(_dead_for, 0.0) + delta
		_present_death(delta)


func _qualified(clip: StringName) -> StringName:
	return StringName("zz/" + String(clip))


func _play(clip: StringName, _rate: float) -> void:
	if _anim == null or clip == _clip:
		return

	var name := _qualified(clip)

	if not _anim.has_animation(name):
		return

	_clip = clip
	_anim.play(name, 0.15)


## The kind's shape and stance over whatever the clip is doing: its bones' scales, a hunch, the
## tongue, a scream's open jaw, and a flinch when it is hit. Written straight onto the bones.
func _pose(anim: int) -> void:
	if _skeleton == null:
		return

	var shapes := _dead_bones if anim == ZzZombieBody.Anim.DEAD else _shape_bones

	for index: int in shapes:
		_skeleton.set_bone_pose_scale(index, shapes[index])

	var hunch := _hunch

	if anim == ZzZombieBody.Anim.DEAD:
		hunch = 0.0

	# A severed limb's collapsed bone: the clip wrote its scale back this frame.
	for gone: int in _skeleton.get_meta(DotNpcGibs.COLLAPSED, []):
		_skeleton.set_bone_pose_scale(gone, Vector3.ONE * 0.001)

	var spine: int = _bones.get(&"Torso", -1)

	if hunch > 0.0 and spine >= 0:
		_skeleton.set_bone_pose_rotation(spine, Quaternion(Vector3.RIGHT, hunch * 0.6) * _skeleton.get_bone_pose_rotation(spine))

	var head: int = _bones.get(&"Head", -1)

	if head >= 0 and anim != ZzZombieBody.Anim.DEAD:
		var loll := 0.18 * sin(float(Time.get_ticks_msec()) * 0.0013 + float(variant))
		_skeleton.set_bone_pose_rotation(head, Quaternion(Vector3.FORWARD, loll) * _skeleton.get_bone_pose_rotation(head))

	# A scream opens the jaw as far as it goes.
	var jaw: int = _bones.get(&"BottomMouth", -1)

	if jaw >= 0 and anim in [ZzZombieBody.Anim.SCREAM, ZzZombieBody.Anim.RAGE, ZzZombieBody.Anim.VOMIT, ZzZombieBody.Anim.SPIT]:
		_skeleton.set_bone_pose_rotation(jaw, Quaternion(Vector3.RIGHT, 0.7) * _skeleton.get_bone_pose_rotation(jaw))

	# A flinch: the chest snaps back from the hit and comes back over a quarter of a second.
	if _flinch > 0.0:
		var snap := sin(_flinch * PI) * 0.45

		if spine >= 0:
			_skeleton.set_bone_pose_rotation(spine, Quaternion(Vector3(-1.0, 0.0, _flinch_side * 0.4).normalized(), snap) * _skeleton.get_bone_pose_rotation(spine))
		if head >= 0:
			_skeleton.set_bone_pose_rotation(head, Quaternion(Vector3.RIGHT, -snap * 0.8) * _skeleton.get_bone_pose_rotation(head))


## Hit: a flinch over whatever it is doing. [param from_side] is -1 or 1 for which side the hit
## came from; a flinch already running is not restarted, so a shotgun's pellets are one flinch.
func flinch(from_side: float = 1.0) -> void:
	if _death.is_empty() and _flinch < 0.5:
		_flinch = 1.0
		_flinch_side = signf(from_side) if from_side != 0.0 else 1.0


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
		_material.set_shader_parameter(&"flash", 0.6 if enraged else 0.0)


# --- Dying ---------------------------------------------------------------------------------------

## Starts the fall: [param reaction] is a dot-player-char reaction id the server picked
## (`DotPlayerDeath`), [param push] the shot's direction scaled by its strength, [param seed] the
## death's own number. Animated, not physical: see [method _present_death].
func die(reaction: StringName, push: Vector3, seed: int) -> void:
	if not _death.is_empty():
		return

	_death = {"reaction": reaction, "push": push, "seed": seed, "t": 0.0}
	_death_from = transform
	var flat := Vector3(push.x, 0.0, push.z)

	# The kit's death clip falls backwards, so it is turned to have its back to where the shot
	# was going: every reaction falls away from the gun. They differ in how: thrown, stepped
	# back, slid, folded (see [method _present_death]). The kit has no fall onto the face, so
	# a face plant is the backward fall, quick and short.
	if flat.length() > 0.05:
		var away := flat.normalized()
		_death["yaw_to"] = atan2(away.x, away.z)
	else:
		_death["yaw_to"] = rotation.y

	if _drip != null:
		_drip.emitting = false

	_flinch = 0.0


## The death's motion over the clip: a launch is an arc, a headshot a step back, a crumple a
## slow fold, and every one ends lying where the clip leaves it.
func _present_death(delta: float) -> void:
	var t := float(_death.get("t", 0.0)) + delta
	_death["t"] = t
	var reaction: StringName = _death.get("reaction", &"limp")
	var push: Vector3 = _death.get("push", Vector3.ZERO)
	var flat := Vector3(push.x, 0.0, push.z)
	var strength := clampf(flat.length(), 0.0, 3.0)
	var dir := flat.normalized() if flat.length() > 0.01 else Vector3.ZERO

	# Turn to fall the right way over the first fifth of a second.
	var turn := clampf(t / 0.2, 0.0, 1.0)
	var from_yaw := _death_from.basis.get_euler().y
	rotation.y = lerp_angle(from_yaw, float(_death["yaw_to"]), turn)

	match reaction:
		&"power_launch", &"headshot_launch":
			var air := 0.55 if reaction == &"power_launch" else 0.3
			var reach := (2.6 if reaction == &"power_launch" else 1.1) * maxf(strength, 0.6)
			var f := clampf(t / air, 0.0, 1.0)
			position = _death_from.origin + dir * reach * (1.0 - (1.0 - f) * (1.0 - f)) \
				+ Vector3(0.0, 4.0 * (0.9 if reaction == &"power_launch" else 0.35) * f * (1.0 - f), 0.0)
		&"crumple":
			position = _death_from.origin + dir * 0.15 * clampf(t / 0.4, 0.0, 1.0)
			if _anim != null:
				_anim.speed_scale = 0.55
		&"face_plant":
			position = _death_from.origin + dir * 0.5 * clampf(t / 0.35, 0.0, 1.0)
			if _anim != null:
				_anim.speed_scale = 1.5
		_:
			position = _death_from.origin + dir * 0.35 * clampf(t / 0.3, 0.0, 1.0)


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


## Where the mouth is in the world (a tongue starts here), or the top of the body without a skeleton.
func mouth() -> Vector3:
	var head: int = _bones.get(&"Head", -1)

	if _skeleton != null and head >= 0:
		return _skeleton.global_transform * _skeleton.get_bone_global_pose(head) * (Vector3(0.0, 0.1, 0.16) / maxf(_scale, 0.01))

	return global_position + Vector3(0.0, float(_look.get("height", 1.75)) * 0.88, 0.0)


## Hides or shows the model: a holder at the lens of the person it holds is drawn from its arms only.
func set_drawn(on: bool) -> void:
	if _model != null:
		_model.visible = on


## Seconds this one has been dead, or -1.
func dead_for() -> float:
	return _dead_for


## The clip playing now, without the library's prefix; for a suite and a contact sheet.
func clip() -> StringName:
	return _clip


func describe() -> Dictionary:
	return {
		"kind": String(kind), "body": String(body_id), "variant": variant, "clip": String(_clip),
		"height": float(_look.get("height", 0.0)), "dead": _dead_for,
		"death": String(_death.get("reaction", "")),
	}
