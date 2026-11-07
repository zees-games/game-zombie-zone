extends Node3D

const ZzPaths := preload("../game/zz_paths.gd")
const ZzZombieBody := preload("zz_zombie_body.gd")

## What a zombie looks like: one of seven animated bodies (Quaternius' CC0 Zombie Apocalypse Kit, built by `tools/build_zombie_models.py`) dressed by a palette shader, reshaped by its bones, wearing what its kind wears. Client only.
## A common's variant picks body, skin ([constant SKINS]), clothes ([constant CLOTHES]), height and blood/dirt, so a horde has no two alike; a special reads by outline (bone scales, stance, wear) before colour.
## The pose is written after the clip every frame ([method present]), or the clip wins; far and unseen zombies animate less often ([member lod], `zz_zombie_lod.gd`).

const CHANNEL := "zz.zombie_view"
const ZzZombieLod := preload("zz_zombie_lod.gd")

## The world view's shared level-of-detail rules; a view without one makes its own.
var lod: ZzZombieLod = null
var _shadowed := true
var _own_lod := false

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
	&"city": ZzPaths.rebase("res://assets/zombies/zombie_city.glb"),
	&"gent": ZzPaths.rebase("res://assets/zombies/zombie_gent.glb"),
	&"cop": ZzPaths.rebase("res://assets/zombies/zombie_cop.glb"),
	&"punk": ZzPaths.rebase("res://assets/zombies/zombie_punk.glb"),
	&"convict": ZzPaths.rebase("res://assets/zombies/zombie_convict.glb"),
	&"hazmat": ZzPaths.rebase("res://assets/zombies/zombie_hazmat.glb"),
	&"walker": ZzPaths.rebase("res://assets/zombies/zombie_walker.glb"),
}

## The kit's atlas, in the three versions its bodies were painted against: they differ in a few
## swatches, and a body drawn with another's atlas wears the wrong colours there.
static var ATLASES := {
	&"basic": ZzPaths.rebase("res://assets/zombies/atlas_basic.png"),
	&"heavy": ZzPaths.rebase("res://assets/zombies/atlas_heavy.png"),
	&"people": ZzPaths.rebase("res://assets/zombies/atlas_people.png"),
	## Ours, not the kit's: the worker's gear and dirt are baked in (`art-src/zombie_worker.py`).
	&"worker": ZzPaths.rebase("res://assets/zombies/atlas_worker.png"),
	## A realistic body's baked colour (`art-src/zombie_city.py`); its tangent normal map is [constant CITY_NORMAL].
	&"city": ZzPaths.rebase("res://assets/zombies/city_albedo_0.png"),
	&"gent": ZzPaths.rebase("res://assets/zombies/gent_albedo.png"),
	&"cop": ZzPaths.rebase("res://assets/zombies/cop_albedo.png"),
	&"punk": ZzPaths.rebase("res://assets/zombies/punk_albedo.png"),
	&"convict": ZzPaths.rebase("res://assets/zombies/convict_albedo.png"),
	&"hazmat": ZzPaths.rebase("res://assets/zombies/hazmat_albedo.png"),
	&"walker": ZzPaths.rebase("res://assets/zombies/walker_albedo.png"),
}

## The city body's painted people (`art-src/zombie_city_paint.py`): skin, outfit and hair differ per texture.
const CITY_LOOKS := 6

## Shown in the scoreboard header: the CC-BY zombie bodies (README.md has the URLs).
const CREDITS := "Walking Dead zombies by LasquetiSpice, Zombie Hazmat by LxNazarov, Zombie Walk Test by OSCAR CREATIVO (all CC-BY 4.0), modified"

const CITY_NORMAL := "res://assets/zombies/city_normal.png"

## Bodies baked with a tangent normal map (the city's and the Sketchfab characters', `art-src/zombie_sketchfab.py`):
## colour, blood and dirt are in the texture, so the shader's splashes are off and only these sample a normal map.
static var NORMALS := {&"city": CITY_NORMAL, &"gent": "res://assets/zombies/gent_normal.png", &"cop": "res://assets/zombies/cop_normal.png",
	&"punk": "res://assets/zombies/punk_normal.png", &"convict": "res://assets/zombies/convict_normal.png", &"hazmat": "res://assets/zombies/hazmat_normal.png",
	&"walker": "res://assets/zombies/walker_normal.png"}

## Where the head bone sits against the body's height, for the bodies that are not the kit's big-headed
## proportions (the kit's is 1.22, [method _measure]).
const HEAD_TOP := {&"city": 1.137, &"gent": 1.077, &"cop": 1.107, &"punk": 1.124, &"convict": 1.087, &"hazmat": 1.138, &"walker": 1.136}

const ATLAS_OF := {&"basic": &"basic", &"chubby": &"heavy", &"arm": &"heavy", &"matt": &"people",
	&"lis": &"people", &"sam": &"people", &"shaun": &"people", &"worker": &"worker", &"city": &"city",
	&"gent": &"gent", &"cop": &"cop", &"punk": &"punk", &"convict": &"convict", &"hazmat": &"hazmat", &"walker": &"walker"}

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
	&"city": {},  # baked likewise
	&"gent": {},
	&"cop": {},
	&"punk": {},
	&"convict": {},
	&"hazmat": {},
	&"walker": {},
}

## The commons' bodies, in variant order: the realistic ones only; the kit's cartoon bodies stay for other roles.
const COMMON_BODIES: Array[StringName] = [&"city", &"gent", &"cop", &"punk", &"convict", &"hazmat", &"walker"]

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
		"bones": {"Neck": Vector3(0.9, 2.2, 0.9), "Head": 0.85, "Tongue1*": Vector3(1.5, 2.6, 1.5)}, "hunch": 0.3, "shamble": {"stoop": 0.3, "head": 0.45, "arms": -0.2, "swing": 0.5, "drag": 0.25, "sway": 0.18}, "wear": [&"neck_growth"], "mark": "4a2a3a", "blood": 0.62},
	&"bloater": {"body": &"chubby", "height": 1.85, "girth": 1.4, "skin": "a8a45a", "bottom": "4a3f30",
		"bones": {"Abdomen": Vector3(1.45, 1.0, 1.45), "Torso": Vector3(1.25, 1.0, 1.3), "Head": 0.9}, "hunch": 0.0, "shamble": {"stoop": 0.1, "swing": 0.45, "drag": 0.5, "trail": 0.2, "sway": 0.25, "hip": 0.25, "cadence": 0.8}, "wear": [&"boils"], "mark": "6b7a2a", "blood": 0.7},
	&"ram": {"body": &"arm", "height": 2.05, "girth": 1.1, "skin": "6e6152", "bottom": "2e3440",
		"bones": {}, "hunch": 0.2, "shamble": {"stoop": 0.4, "head": -0.1, "arms": -0.35, "swing": 0.65, "drag": 0.5, "sway": 0.2, "hip": 0.2}, "wear": [], "mark": "3a2a24", "blood": 0.64,
		"clips": {"attack_idle": &"attack", "crawl": &"walk"}},
	&"spitter": {"body": &"lis", "height": 1.95, "girth": 0.8, "skin": "9fb35a", "top": "3d4a2e", "bottom": "2c2e26", "hair": "1c1d18",
		"bones": {"Neck": Vector3(0.9, 2.4, 0.9), "Head": 0.9}, "hunch": 0.15, "shamble": {"stoop": 0.3, "head": 0.55, "hang": -0.9, "swing": 0.5, "drag": 0.2}, "wear": [&"acid_mouth"], "mark": "2e4a12", "blood": 0.65, "glow": "4f8a12"},
	&"rider": {"body": &"basic", "height": 1.2, "girth": 1.0, "skin": "8a7a66", "bottom": "4a3a2a", "belt": "2a221a",
		"bones": {"UpperArm.L*": 1.35, "UpperArm.R*": 1.35, "Head": 1.15, "UpperLeg.L*": 0.8, "UpperLeg.R*": 0.8}, "hunch": 0.55, "wear": [], "blood": 0.64,
		"clips": {"run": &"run_arms", "walk": &"run_arms"}},
	&"brute": {"body": &"chubby", "height": 2.95, "girth": 1.55, "skin": "5e5263", "bottom": "2e2a2a",
		"bones": {"UpperArm.L*": 1.4, "UpperArm.R*": 1.4, "Shoulder.L": 1.3, "Shoulder.R": 1.3, "Head": 0.6, "Torso": Vector3(1.2, 1.0, 1.15)}, "hunch": 0.35, "shamble": {"stoop": 0.35, "head": 0.1, "arms": -0.5, "hang": -0.9, "swing": 0.6, "drag": 0.6, "trail": 0.1, "sway": 0.22, "hip": 0.2, "cadence": 0.8, "lurch": 0.0},
		"wear": [&"spikes"], "mark": "2a1d3a", "blood": 0.62},
	&"sleeper": {"body": &"lis", "height": 1.65, "girth": 0.85, "skin": "e4e4e8", "top": "d6d2c8", "bottom": "c8c2b8", "hair": "16161a",
		"bones": {"Index1.L*": Vector3(0.8, 1.9, 0.8), "Index1.R*": Vector3(0.8, 1.9, 0.8), "Middle1.L*": Vector3(0.8, 1.9, 0.8), "Middle1.R*": Vector3(0.8, 1.9, 0.8), "Pinky1.L*": Vector3(0.8, 1.9, 0.8), "Pinky1.R*": Vector3(0.8, 1.9, 0.8)},
		"hunch": 0.0, "shamble": {"stoop": 0.12, "head": 0.1, "arms": -0.5, "hang": -0.8, "swing": 0.8, "drag": 0.8, "trail": 0.0, "sway": 0.05, "hip": 0.04, "cadence": 0.7, "lurch": 0.0}, "wear": [&"red_eyes"], "mark": "7a8a9a", "blood": 0.62},
	&"screamer": {"body": &"chubby", "height": 2.0, "girth": 0.72, "skin": "b6bfc6", "bottom": "3a1e22",
		"bones": {"Abdomen": Vector3(0.62, 1.15, 0.62), "Torso": Vector3(0.68, 1.1, 0.7), "Neck": Vector3(0.8, 1.6, 0.8), "BottomMouth": 1.4}, "hunch": 0.2, "shamble": {"stoop": 0.1, "head": -0.1, "arms": -0.5, "hang": -0.7, "swing": 0.7, "drag": 0.7, "trail": 0.0, "sway": 0.08, "hip": 0.06, "cadence": 1.1, "lurch": 0.0},
		"wear": [], "mark": "5a6a8a", "blood": 0.62},
	&"crawler": {"body": &"basic", "height": 1.75, "girth": 1.0, "skin": "6f7a55", "bottom": "3a3a30", "belt": "4a2020",
		"bones": {"UpperLeg.L*": 0.04, "UpperLeg.R*": 0.04}, "hunch": 0.0,
		"clips": {"idle": &"crawl", "walk": &"crawl", "run": &"crawl", "run_arms": &"crawl", "attack": &"crawl", "attack_idle": &"crawl", "attack_run": &"crawl", "hit": &"crawl", "jump_idle": &"crawl"}, "wear": [&"gore"], "blood": 0.55},
	&"riot": {"body": &"sam", "height": 1.85, "girth": 1.1, "skin": "7f8b6e", "top": "1e2430", "bottom": "1b1f28", "hat": "1c2230",
		"bones": {}, "hunch": 0.05, "shamble": {"stoop": 0.05, "head": 0.05, "arms": -0.5, "hang": -0.8, "swing": 0.55, "drag": 0.4, "trail": 0.25, "sway": 0.1}, "wear": [&"helmet", &"shield"], "blood": 0.6},
}

## Which clip an animation state plays, and how fast.
const GAIT_SHAMBLE := &"shamble"
const GAIT_RUN := &"run"
## A look's `gait` key overrides these: below `shamble_below` m/s the body shambles (the walk clip
## at its real speed, stiff and dragging), from `run_from` it runs; between, it keeps what it did.
const GAIT := {"shamble_below": 2.7, "run_from": 3.1}
## The shamble's numbers, radians unless said; a look's `shamble` key overrides any (stoop, head, arms/hang,
## swing, drag, trail, sway/hip, cadence, lurch).
## The anims played on both feet, whose ankles [method _ground_feet] keeps out of the floor.
const STANDING_ANIMS: Array[int] = [ZzZombieBody.Anim.IDLE, ZzZombieBody.Anim.WALK, ZzZombieBody.Anim.RUN,
	ZzZombieBody.Anim.ATTACK, ZzZombieBody.Anim.STAGGER, ZzZombieBody.Anim.VOMIT, ZzZombieBody.Anim.SPIT,
	ZzZombieBody.Anim.CHARGE, ZzZombieBody.Anim.CARRY, ZzZombieBody.Anim.THROW, ZzZombieBody.Anim.CRY,
	ZzZombieBody.Anim.RAGE, ZzZombieBody.Anim.SHAMBLE, ZzZombieBody.Anim.SCREAM, ZzZombieBody.Anim.GRAB,
	ZzZombieBody.Anim.BLOCK, ZzZombieBody.Anim.CHARGE_UP, ZzZombieBody.Anim.ZAP]

const SHAMBLE := {"stoop": 0.2, "head": 0.3, "arms": -0.4, "hang": -1.2, "swing": 0.4, "drag": 0.15,
	"trail": 0.5, "sway": 0.14, "hip": 0.12, "cadence": 1.0, "lurch": 0.3}

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
	ZzZombieBody.Anim.STRIKE_DOWN: [&"attack", 1.25],
}

## A swing's length in seconds (the brain's windup plus recover) and the fraction of it at which the
## blow lands, so the overlay's strike frame is the brain's damage frame.
const SWING_PERIOD := 0.87
const HIT_AT := 0.37


## Clips that loop; the rest play once and hold their last frame.
const LOOPING: Array[StringName] = [&"idle", &"walk", &"run", &"run_arms", &"crawl", &"attack_idle", &"jump_idle", &"attack_run", &"ual_zombie_idle", &"ual_zombie_walk", &"ual_sprint", &"ual_jog", &"ual_crouch_walk"]

## Real clips (Universal Animation Library, CC0, baked by dot-player-char) a body plays in place
## of the made one when they are in the library; absent, the made clip plays as before.
const UAL_FOR := {&"idle": &"ual_zombie_idle", &"walk": &"ual_zombie_walk", &"run_arms": &"ual_sprint",
	&"attack": &"ual_zombie_scratch", &"hit": &"ual_hit_chest"}
## Under this ground speed (m/s) a run is the jog; the clips' own ground speeds, for the playback rate.
const JOG_BELOW := 4.2
const JOG_NATURAL := 3.6
const CROUCH_NATURAL := 1.4
const UAL_LIBRARY := "res://addons/dot_player_char/people/people_ual.res"
const UAL_FROM := "res://addons/dot_player_char/people/people_matt.glb"

## The palette shader: up to [constant SWAPS] atlas colours swapped within a tolerance, then dirt and blood
## from the vertex-colour noise, then the kind's glow. Compatibility renderer: no per-instance
## uniforms (a material per look) and no arrays with hints.
const SWAPS := 6
## How much of a kind's `glow` the whole body gives off (the throat is its own mesh): at full
## strength the spitter was a flat green silhouette with no face. And the share of its own
## colour every zombie emits, which keeps a dark body readable in the dark.
const GLOW_BODY := 0.25
const BODY_LIFT := 0.22
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
uniform vec3 mark_colour : source_color = vec3(0.0);
uniform float mark_amount = 0.0;
uniform float flash = 0.0;
uniform float lift = 0.0;

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
	// Bruises and sores: where the noises disagree with the blood, so the two never overlap.
	float mark = smoothstep(0.48, 0.56, COLOR.g) * (1.0 - smoothstep(0.45, 0.52, COLOR.r));
	c = mix(c, mark_colour, mark * mark_amount);
	ALBEDO = c;
	ROUGHNESS = mix(0.9, 0.3, blood);
	// A little self-light so a dark skin on a night map keeps its legs, head and face: lit by
	// the moon alone the specials' charcoal bodies drew as black cones.
	EMISSION = c * lift + glow + vec3(flash * 0.35, flash * 0.05, flash * 0.03);
}
"""

var kind: StringName = &""
var variant: int = -1

## The body this look was built on, for a suite to read.
var body_id: StringName = &""

var _model: Node3D = null
var _anim: AnimationPlayer = null
var _skeleton: Skeleton3D = null
var _legs_gone := 0
var _trail_from := Vector3.INF
var _mesh: MeshInstance3D = null
var _bones: Dictionary = {}
var _shape_bones: Dictionary = {}
var _dead_bones: Dictionary = {}
var _clip: StringName = &""
var _look: Dictionary = {}
var _material: ShaderMaterial = null
var _fade := 1.0
static var _fade_shader: Shader = null
var _fire: CPUParticles3D = null
var _eyes: OmniLight3D = null
var _drip: CPUParticles3D = null
var _last_at: Vector3 = Vector3.INF
var _last_y: float = 0.0
var _speed: float = 0.0
var _gait: StringName = GAIT_SHAMBLE
var _shamble: float = 0.0
var _limbs: Dictionary = {}
var _climb: float = 0.0
## The body's ground velocity, smoothed like [member _speed], and the rate the clip last played at.
var _velocity := Vector3.ZERO
var _rate := 1.0
var _want_clip: StringName = &"idle"
var _want_rate := 1.0
## Each foot planted on the floor through the shamble ([method _plant_feet]).
var _plant := DotFootPlant.new()
## Per side: [upper, lower, ankle in the lower bone's frame, rest ankle, leg length], skeleton space.
var _legs: Array = []
var _dead_for: float = -1.0
var _owed: float = 0.0
var _frame: int = 0
var _flinch: float = 0.0
var _flinch_side: float = 1.0
var _hunch: float = 0.0
## Seconds since the attack state began, and where in the swing that puts it (0 to 1).
var _strike_t: float = 0.0
var _strike_phase: float = 0.0
var _scale: float = 1.0

## A death being drawn: the reaction's id, which way the hit pushed, how hard, and the seed.
var _death: Dictionary = {}
var _death_from: Transform3D = Transform3D.IDENTITY

static var _scenes: Dictionary = {}
static var _libraries: Dictionary = {}
## Per-kind bruises and sores on the specials' flat skin (`zz_zombie_detail`; 0 draws the plain look).
static var detail := true
static var _materials: Dictionary = {}
static var _shader: Shader = null
static var _shader_normal: Shader = null
static var _atlases: Dictionary = {}


## The look of [param p_kind] (and, for a common, of [param p_variant]): a dictionary in the
## shape of [constant LOOKS], with the common's body and colours filled in.
## A pack monster's kind -> the built-in kind whose body it wears (`ZzPacks` fills it, both ends scan).
static var aliases: Dictionary = {}


static func look_for(p_kind: StringName, p_variant: int) -> Dictionary:
	var look: Dictionary = (LOOKS.get(aliases.get(p_kind, p_kind), LOOKS[&"common"]) as Dictionary).duplicate()

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

	if NORMALS.has(look["body"]):
		# Colour, blood and dirt are painted in the texture; the shader's splashes would land on the baked ones.
		if look["body"] == &"city":
			look["tex"] = (v >> 3) % CITY_LOOKS

		look["blood"] = 2.0
		look["dirt"] = 0.0

	return look


## The pose scale each bone needs for [param shapes], a look's `bones`: bone name -> drawn size (a number, or a Vector3 in the bone's axes). A name ending in `*` sizes the bone and everything below it.
## Sizes are the bone's own, not inherited: each is divided by its parent's, since a pose scale carries down
## to every child and a long neck would give a giant head.
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
## skeleton by [method DotHumanoidClips.retarget], once per body and shared.
static func _library_for(id: StringName, skeleton: Skeleton3D) -> AnimationLibrary:
	if not CLIPS_FROM.has(id):
		return _library(id)

	var key := StringName("%s<-%s" % [id, CLIPS_FROM[id]])

	if not _libraries.has(key):
		_libraries[key] = DotHumanoidClips.retarget(_library(CLIPS_FROM[id]), _rests(CLIPS_FROM[id]), skeleton)

	return _libraries[key]


## [param library] plus the real clips, carried from the people kit's rest onto [param skeleton]'s
## once per body; [param library] unchanged when the file or the kit is missing.
static func _with_ual(id: StringName, skeleton: Skeleton3D, library: AnimationLibrary) -> AnimationLibrary:
	if library == null or skeleton == null:
		return library

	var key := StringName("ual:" + String(id))

	if not _libraries.has(key):
		var merged := library
		var real := load(UAL_LIBRARY) as AnimationLibrary if ResourceLoader.exists(UAL_LIBRARY) else null
		var kit := _scene(UAL_FROM)

		if real != null and kit != null:
			var probe := kit.instantiate()
			var from := DotHumanoidClips.rests_of(probe.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D)
			probe.free()
			merged = AnimationLibrary.new()
			for clip in library.get_animation_list():
				var _kept := merged.add_animation(clip, library.get_animation(clip))
			var carried := DotHumanoidClips.retarget(real, from, skeleton)
			for clip in carried.get_animation_list():
				var animation := carried.get_animation(clip)
				animation.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(StringName(clip)) else Animation.LOOP_NONE
				if String(clip).begins_with("ual_hit"):
					_hold_legs(animation)
				var _added := merged.add_animation(clip, animation)
		_libraries[key] = merged

	return _libraries[key]


## A flinch is played where the body stands: its leg tracks are dropped so the legs keep the idle stance.
static func _hold_legs(animation: Animation) -> void:
	for t in range(animation.get_track_count() - 1, -1, -1):
		var bone := String(animation.track_get_path(t).get_concatenated_subnames())

		if bone.begins_with("UpperLeg") or bone.begins_with("LowerLeg") or bone.begins_with("Foot") or bone.begins_with("Toes"):
			animation.remove_track(t)


## The rest pose of [param id]'s skeleton, bone name -> local rest transform.
static func _rests(id: StringName) -> Dictionary:
	var key := StringName("rests:" + String(id))

	if not _libraries.has(key):
		var scene := _scene(BODIES.get(id, ""))
		var out := {}

		if scene != null:
			var probe := scene.instantiate()
			out = DotHumanoidClips.rests_of(probe.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D)
			probe.free()

		_libraries[key] = out

	return _libraries[key]


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
	var mark := Color(str(look.get("mark", "000000"))).srgb_to_linear() if detail else Color.BLACK
	var key := "%s%s|%s|%s|%.2f|%.2f|%s|%s" % [look["body"], look.get("tex", ""), from, to, float(look.get("blood", 0.6)), float(look.get("dirt", 0.5)), glow.to_html(), mark.to_html()]

	if _materials.has(key):
		return _materials[key]

	var normal_tex: bool = NORMALS.has(look["body"])

	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER

	if normal_tex and _shader_normal == null:
		# Only the body that has a normal map pays for sampling one.
		_shader_normal = Shader.new()
		_shader_normal.code = SHADER.replace("uniform float lift = 0.0;", "uniform float lift = 0.0;\nuniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;") \
			.replace("	ALBEDO = c;", "	ALBEDO = c;\n	NORMAL_MAP = texture(normal_tex, UV).rgb;")

	var atlas_id: StringName = ATLAS_OF.get(look["body"], &"basic")
	var path: String = ATLASES[atlas_id]

	if look["body"] == &"city":
		atlas_id = StringName("city_%d" % int(look.get("tex", 0)))
		path = path.replace("city_albedo_0", "city_albedo_%d" % int(look.get("tex", 0)))

	if not _atlases.has(atlas_id):
		_atlases[atlas_id] = DotHumanoidFigure.load_texture(path)

	var material := ShaderMaterial.new()
	material.shader = _shader_normal if normal_tex else _shader
	material.set_shader_parameter(&"atlas", _atlases[atlas_id])

	if normal_tex:
		var normal_id := StringName("%s_normal" % look["body"])

		if not _atlases.has(normal_id):
			_atlases[normal_id] = DotHumanoidFigure.load_texture(ZzPaths.rebase(NORMALS[look["body"]]))

		material.set_shader_parameter(&"normal_tex", _atlases[normal_id])

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
	material.set_shader_parameter(&"glow", Vector3(g.r, g.g, g.b) * GLOW_BODY)
	material.set_shader_parameter(&"lift", BODY_LIFT)
	material.set_shader_parameter(&"mark_colour", Color(mark.r, mark.g, mark.b))
	material.set_shader_parameter(&"mark_amount", 0.95 if mark != Color.BLACK else 0.0)
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
static func _measure(skeleton: Skeleton3D, model: Node3D, head_top := 1.22) -> float:
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
		top = (chain * skeleton.get_bone_global_rest(head)).origin.y * head_top

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

		var fit := float(look["height"]) / maxf(_measure(skeleton, root, float(HEAD_TOP.get(look["body"], 1.22))), 0.01)
		var girth := float(look["girth"])
		var drawn := Basis(Vector3.UP, PI).scaled(Vector3(fit * girth, fit, fit * girth))

		for i in skeleton.get_bone_count():
			var bone := skeleton.get_bone_name(i)
			filed[StringName(bone)] = drawn * (chain * skeleton.get_bone_global_rest(i)).origin

			if skeleton.get_bone_parent(i) >= 0:
				filed["@" + bone] = StringName(skeleton.get_bone_name(skeleton.get_bone_parent(i)))

	root.free()
	DotNpcLimbs.store_rest_points(key, filed)
	return key
