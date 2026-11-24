extends SceneTree

## Zombie Zone's visual QA capture (docs/visual-qa.md; the loop is gs-game's docs/visual-qa.md): every weapon's clips in the survivor's hands, the
## survivor's own locomotion, and every infected kind's walk, run, attack, flinch and death, each saved frame by frame in three
## views at --fps (60 by default) for tools/visual_qa_shot.sh (gs-game's shot tool) to turn into contact sheets and clips.
##   survivor: f = first person (the main viewport), t = behind-right of your own body, o = an opponent four metres in front.
##   infected: f = the victim's eye in front of it, t = behind-right, o = an opponent four metres in front.
## The outside views and frame saving are gs-game's GSGameVisualQaViews. The scene itself stays here, not a GSGameVisualQaCapture:
## the survivor is staged in the real offline client, which needs awaited setup (client start, world draw, weapon switch).
## Per clip it prints `VISUALQA {json}` (the shared verdict line) and `ANIMFRAMES {json}` (every frame's numbers) on stdout.
## User args: --out DIR --fps N [--only id,id|all|none] [--clips a,b] [--avatar] [--zombies kind,kind|all].
## --zombies runs the infected on a bare stage instead of the survivor in the offline client (one process cannot hold both).

const ZzWeapons := preload("../game/zz_weapons.gd")

## Your own body draws only in the outside views; the view model (ZeeViewModel's view_layer 20) only in the first-person one.
const BODY_LAYER := 1 << 18
const VIEW_LAYER := 1 << 19
const ALL_LAYERS := 0xFFFFF
## Where the survivor stands for every clip (tools/filmstrip_scenarios.json's defaults: open ground on the offline map).
const WEAPON_CLIPS: PackedStringArray = ["idle", "draw", "sprint", "ads", "fire", "reload", "inspect"]
## A clip that needs a magazine or a sight: melee and thrown weapons have neither.
const NEEDS_GUN: PackedStringArray = ["ads", "reload"]
const NO_GUN_TIERS: Array[StringName] = [&"melee", &"thrown"]
const AVATAR_KEYS := {"walk": [&"gs_fps_forward"], "strafe": [&"gs_fps_left"], "run": [&"gs_fps_forward", &"gs_fps_sprint"],
	"crouch": [&"gs_fps_crouch"], "jump": [&"gs_fps_jump"]}
const MOVE_KEYS: Array[StringName] = [&"gs_fps_forward", &"gs_fps_back", &"gs_fps_left", &"gs_fps_right",
	&"gs_fps_sprint", &"gs_fps_crouch", &"gs_fps_jump", &"gs_fps_walk"]
const SPRINT_KEYS: Array[StringName] = [&"gs_fps_forward", &"gs_fps_sprint"]
const ZOMBIE_CLIPS: PackedStringArray = ["walk", "run", "attack", "flinch", "die"]
const ZOMBIE_KINDS: Array[StringName] = [&"common", &"leaper", &"strangler", &"bloater", &"ram", &"spitter", &"rider", &"brute",
	&"sleeper", &"screamer", &"crawler", &"riot", &"mutant", &"oil_monster"]
## The zombie body's Anim each infected clip plays (npcs/zz_zombie_body.gd); flinch and die are events over an idle.
const ZOMBIE_ANIM := {"walk": "WALK", "run": "RUN", "attack": "ATTACK", "flinch": "IDLE", "die": "IDLE"}
## Seconds per clip (frames = seconds * fps).
const SECONDS := {"idle": 1.0, "draw": 1.4, "sprint": 1.8, "ads": 1.6, "fire": 1.6, "reload": 3.2, "inspect": 3.2,
	"walk": 2.4, "strafe": 2.4, "run": 2.4, "crouch": 2.0, "jump": 1.6,
	"z_walk": 3.0, "z_run": 2.0, "z_attack": 2.4, "z_flinch": 2.0, "z_die": 3.0}
## Failure limits. Metres per frame at 30 fps for a step (_limit scales it to --fps), frames at 30 fps for a duration.
## view_pop_m: a hand or weapon part jumping between frames in the eye's frame; view_kick_m: the same while firing (a recoil
## kick is one impulse at any fps); hidden_frames: the weapon gone from the view outside a draw.
const LIMITS := {"view_pop_m": 0.04, "view_kick_m": 0.09, "hidden_frames": 3}
## A move is a pop only when it is this many times both neighbouring frames' moves: a draw, an aim or a reload moves a part
## fast but smoothly, a pop is one frame's jump out of a still or slow pose.
const POP_SPIKE := 2.5
const PER_STEP: PackedStringArray = ["view_pop_m"]
const PER_COUNT: PackedStringArray = ["hidden_frames"]
## The infected's pace on the stage: zz_npcs.gd's common walk and run. A special's own pace differs, so only the common one's
## foot slide is judged; the others' slide row is printed as a note.
const ZOMBIE_SPEED := {"walk": 1.1, "run": 6.3, "attack": 0.0, "flinch": 0.0, "die": 0.0}

var fps := 60
## Seconds to wait for the map's delivered world before capturing anyway (it fails loudly).
const WORLD_WAIT_S := 400.0
var _out := "res://screenshots/visual_qa"
var _only := "all"
var _anims: PackedStringArray = []
var _avatar := false
var _zombies: Array[StringName] = []
var _client: Node = null
var _game: Object = null
var _local: Object = null
var _started := false
## Where you stand for every clip: the map's first survivor seat, once its world is drawn.
var _stand := Vector3.ZERO
var _stand_yaw := 0.0
var _done := false
var _views := GSGameVisualQaViews.new()
var _eye: Camera3D = null
var _frames: Array[Dictionary] = []
var _body := GSClipMetrics.new()
## The floor's height under the survivor for this clip, from the first frame it stood on it (NAN until then).
var _floor_y := NAN
var _skeleton: Skeleton3D = null
var _parts: Array[Node3D] = []
var _last_places: Array[Vector3] = []
var _last_wall := 0.0
var _was_scoped := false
var _subject := ""
var _clip := ""
## What the client is told this frame (it reads its own input members every frame, so they are written every frame).
var _fire := false
var _reload := false
var _aim := false
var _zombie: Node3D = null
var _zpos := Vector3.ZERO
var _zanim := 0
var _zspeed := 0.0
var _zkind: StringName = &""
## Set once the infected dies: a body lying down is not judged on its feet touching the floor.
var _zdead := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var key := args[i]
		var value := args[i + 1] if i + 1 < args.size() else ""
		match key:
			"--out":
				_out = value
			"--fps":
				fps = int(value)
			"--only":
				_only = value
			"--anims", "--clips":
				_anims = value.split(",", false)
			"--zombies":
				if value == "all":
					_zombies = ZOMBIE_KINDS.duplicate()
				else:
					for kind in value.split(",", false):
						_zombies.append(StringName(kind))
			"--avatar":
				_avatar = true
				i += 1
				continue
			_:
				i += 1
				continue
		i += 2
	if fps < 15:
		printerr("visual_qa: --fps must be at least 15, not %d" % fps)
		quit(2)
		return
	if not _zombies.is_empty():
		return
	var client_script: GDScript = load("res://game/zz_client.gd")
	_client = client_script.new()
	_client.name = "Client"
	_client.set("force_offline", true)
	_client.set("standalone_content", false)
	_client.set("offline_bots", 3)
	root.add_child(_client)


func _process(_delta: float) -> bool:
	if _started:
		return _done
	if not _zombies.is_empty():
		_started = true
		# One-shot start of the QA coroutine, not per-frame work: deferred so it runs once, outside the frame path.
		_run_zombies.call_deferred()
		return false
	_game = _client.get("game")
	_local = _client.get("player")
	if _game == null or _local == null or int(_game.get("phase")) == 0:
		return false
	_started = true
	_run_survivor.call_deferred()
	return false


func _limit(key: String) -> float:
	var v := float(LIMITS[key])
	if key in PER_STEP:
		return v * 30.0 / float(fps)
	if key in PER_COUNT:
		return v * float(fps) / 30.0
	return v


func _count(seconds: float) -> int:
	return maxi(1, roundi(seconds * float(fps)))


func _wait(seconds: float) -> void:
	for _i in _count(seconds):
		_apply_buttons()
		await process_frame


# --- the survivor ---------------------------------------------------------------------------------------------------------


func _run_survivor() -> void:
	_local.set("is_bot", false)
	_local.get("health").set("invulnerable", true)
	# Your own legs in first person (cl_legs) pose the one figure with no head or arms, and the client sets that again
	# every frame, after which the outside views' THIRD comes a frame late: off for the capture, put back after.
	var store: Object = (_client.get("settings") as Object).get("settings")
	var legs: Variant = store.call("chosen_value", GSOwnBodySetting.KEY)
	var _off: GSResult = store.call("set_value", GSOwnBodySetting.KEY, false, &"visual_qa")
	# The delivered world draws after the round starts (bench.gd waits the same way): stood on before it, you fall.
	var map: Object = _game.get("map")
	var waited := 0
	while not bool(map.get("world_drawn")) and str((map.get("doc") as Dictionary).get("world", "")) != "":
		waited += 1
		if waited > _count(WORLD_WAIT_S):
			push_error("visual_qa: the map's world was not drawn after %.0f s" % WORLD_WAIT_S)
			break
		await process_frame
	var seat: Array = map.call("spawn", "survivors", 0)
	_stand = (seat[0] as Vector3) + Vector3(0.0, 0.05, 0.0)
	_stand_yaw = float(seat[1])
	_local.call("place_at", _stand, _stand_yaw)
	for other: Object in _game.call("survivors"):
		if other != _local:
			other.get("health").set("invulnerable", true)
			other.call("place_at", _stand + Vector3(0.0, 0.0, 400.0), 0.0)
	var cam := _client.get("camera") as Camera3D
	_views.setup(root, root.world_3d, cam.environment if cam != null else null)
	await _wait(1.0)
	var ids: Array[StringName] = []
	if _only == "all":
		for def in ZzWeapons.offered_defs():
			ids.append(def.id)
	elif _only != "none":
		for id in _only.split(",", false):
			ids.append(StringName(id))
	var clips: PackedStringArray = _anims if not _anims.is_empty() else WEAPON_CLIPS
	for id in ids:
		_subject = String(id)
		if not await _hold(id):
			_missing("all", "could not bring %s into hand" % id)
			continue
		var gun := not (ZzWeapons.tier_of(id) in NO_GUN_TIERS)
		for clip in clips:
			# --clips is shared with the infected (walk, die): a weapon takes only its own clips.
			if not WEAPON_CLIPS.has(clip) or (clip in NEEDS_GUN and not gun):
				continue
			await _weapon_clip(id, clip)
	if _avatar:
		_subject = "avatar"
		var held := &"zz_m4"
		if await _hold(held):
			for clip: String in AVATAR_KEYS:
				await _avatar_clip(clip)
		else:
			_missing("all", "could not bring %s into hand" % held)
	_release_all()
	var _back: GSResult = store.call("set_value", GSOwnBodySetting.KEY, legs, &"visual_qa")
	_done = true


## shot_base.gd's _hold_exact: armed, its slot picked, then cycled until it is the one in hand.
func _hold(id: StringName) -> bool:
	# The capture holds every weapon in turn: the carry weight limit (the rig's, once armed) would refuse the heavy ones.
	var rig: Object = _local.get("weapons")
	if rig != null and (rig.get("arsenal") as Object).get("carry") != null:
		(rig.get("arsenal") as Object).get("carry").set("enabled", false)
	if not _game.call("arm", _local, id):
		var why := String(_game.get("arm_failure"))
		if not why.is_empty():
			printerr("visual_qa: %s not armed: %s" % [id, why])
		return false
	var def := ZzWeapons.def_of(id)
	_client.set("_slot", def.slot)
	var arsenal: GSWeaponArsenal = (_client.get("weapons") as Object).get("arsenal")
	await _wait(0.8)
	for _i in 6:
		var now := arsenal.current()
		if now != null and now.def.id == id:
			return true
		var _cycled := arsenal.cycle_slot(Engine.get_physics_frames())
		await _wait(0.8)
	return false


func _weapon_clip(id: StringName, clip: String) -> void:
	var def := ZzWeapons.def_of(id)
	var count := _count(float(SECONDS[clip]))
	match clip:
		"draw":
			# Away to another weapon's slot first; the clip is the swap back.
			var other := &"zz_pistol" if ZzWeapons.tier_of(id) == &"melee" else &"zz_knife"
			if not _game.call("arm", _local, other):
				_missing(clip, "could not arm %s to draw from" % other)
				return
			_client.set("_slot", ZzWeapons.def_of(other).slot)
			await _wait(1.0)
			var back := _count(0.1)
			await _capture(clip, count, func(i: int) -> void:
				if i == back:
					_client.set("_slot", def.slot))
			if not await _hold(id):
				_missing(clip, "%s did not come back into hand" % id)
		"sprint":
			await _capture(clip, count, func(i: int) -> void:
				_press(SPRINT_KEYS, i >= _count(0.1) and i < _count(1.3)))
			_local.call("place_at", _stand, _stand_yaw)
		"ads":
			await _capture(clip, count, func(i: int) -> void:
				_aim = i >= _count(0.1) and i < _count(1.1))
		"fire":
			await _capture(clip, count, func(i: int) -> void:
				_fire = i >= _count(0.1) and i < _count(0.9))
		"reload":
			# A full magazine refuses the reload and the clip filmed a still gun: spend two rounds first, off camera, so the
			# clip is a partial reload whatever ran before it (a by-the-round reload of two shells, a magazine swap).
			var arsenal: GSWeaponArsenal = (_client.get("weapons") as Object).get("arsenal")
			for _shot in 6:
				var now := arsenal.current()
				if now == null or now.magazine_space() >= 2 or now.magazine <= 1:
					break
				_fire = true
				await _wait(0.1)
				_fire = false
				await _wait(0.7)
			await _wait(0.6)
			await _capture(clip, count, func(i: int) -> void:
				_reload = i >= _count(0.1) and i < _count(0.2))
		"inspect":
			# The look-over starts only at rest: no key is bound to it yet, so the capture asks the view model as a key would.
			var model: Object = _client.get("view_model")
			if model == null or not model.has_method("inspect"):
				_missing(clip, "the view model has no inspect")
				return
			await _capture(clip, count, func(i: int) -> void:
				if i == _count(0.1):
					model.call("inspect"))
		_:
			await _capture(clip, count, func(_i: int) -> void: pass)
	_release_all()
	await _wait(0.4)


## A locomotion clip with the rifle held: the keys from 0.15 s to 1.5 s (jump: one press); put back where it stood after.
func _avatar_clip(clip: String) -> void:
	var keys: Array[StringName] = []
	keys.assign(AVATAR_KEYS[clip])
	var until := _count(0.25) if clip == "jump" else _count(1.5)
	await _capture(clip, _count(float(SECONDS[clip])), func(i: int) -> void:
		_press(keys, i >= _count(0.15) and i < until))
	_release_all()
	await _wait(0.5)
	_local.call("place_at", _stand, _stand_yaw)
	await _wait(0.3)


func _press(keys: Array[StringName], on: bool) -> void:
	for k in keys:
		if on:
			Input.action_press(k)
		else:
			Input.action_release(k)


func _release_all() -> void:
	_fire = false
	_reload = false
	_aim = false
	_press(MOVE_KEYS, false)
	_apply_buttons()


func _apply_buttons() -> void:
	if _client == null:
		return
	_client.set("_firing", _fire)
	_client.set("_reloading", _reload)
	_client.set("_aiming", _aim)


func _missing(clip: String, why: String) -> void:
	print("VISUALQA " + JSON.stringify({"item": _subject, "clip": clip, "status": "skip", "why": why}))


# --- capture --------------------------------------------------------------------------------------------------------------


## Plays [param count] frames: [param step] runs before each frame's process, the views are staged just before it draws, and
## the three images are saved after it has drawn.
func _capture(clip: String, count: int, step: Callable) -> void:
	_clip = clip
	var dir := "%s/%s/_frames/%s" % [ProjectSettings.globalize_path(_out), _subject, clip]
	DirAccess.make_dir_recursive_absolute(dir)
	_frames.clear()
	if _zombie == null:
		_body = GSClipMetrics.new()
		_floor_y = NAN
		_skeleton = null
	_parts.clear()
	_last_places.clear()
	# The outside views draw one frame behind their first staging (the last clip's place): one staged draw first.
	await RenderingServer.frame_pre_draw
	_stage()
	await RenderingServer.frame_post_draw
	for i in count:
		step.call(i)
		_apply_buttons()
		await RenderingServer.frame_pre_draw
		_stage()
		_frames.append(_sample(i))
		await RenderingServer.frame_post_draw
		var saved := _views.save(dir, i, root.get_viewport())
		if not saved.ok:
			printerr("visual_qa: %s" % str(saved.error))
	_finish(count)


## Before the draw, after every _process: overlays off, your own body shown to the outside cameras only, cameras placed.
func _stage() -> void:
	if _zombie != null:
		_stage_zombie()
		return
	for layer in _client.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	# Loot price tags (a floating "250" over the lying guns) are overlays too: the judge reads them as a stray label.
	for tag in _client.find_children("*", "Label3D", true, false):
		(tag as Label3D).visible = false
	var hud: Variant = _client.get("hud")
	if hud is CanvasItem:
		(hud as CanvasItem).visible = false
	elif hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	var cam := _client.get("camera") as Camera3D
	if cam != null:
		cam.cull_mask = ALL_LAYERS & ~BODY_LAYER
	var feet: Vector3 = _local.call("feet")
	# The client hides your own body in first person and so stops posing it; this poses and shows it for the outside views.
	var _shown: bool = _local.call("present_body", false, feet, _game.call("side_colour", 1), false)
	var figure: Node = _local.get("figure")
	if figure != null:
		var _tagged := GSGameVisualQaViews.tag_layers(figure, BODY_LAYER)
	_views.place(feet, deg_to_rad(float(_local.get("controller").get("state").get("yaw"))))


## One frame's numbers: the largest hop of a hand or weapon part in the eye's frame, whether the weapon shows, where the
## weapon and the muzzle sit in camera space; and the body's bones for the outside views' pop and foot checks.
func _sample(i: int) -> Dictionary:
	var t := float(i) / float(fps)
	var out := {"t": snappedf(t, 0.001)}
	if _zombie != null:
		_body.add(_body.pose_sample(t, _zombie_skeleton(), _zpos, not _zdead))
		return out
	var feet: Vector3 = _local.call("feet")
	var figure: Node = _local.get("figure")
	if (_skeleton == null or not is_instance_valid(_skeleton)) and figure != null:
		var found := figure.find_children("*", "Skeleton3D", true, false)
		_skeleton = null if found.is_empty() else found.front() as Skeleton3D
	# The real state: on the floor only while the controller is in ground mode, and the floor is where the feet first
	# stood (the capture starts at rest, settled), not wherever the root is now: a jump's rise is not a foot skating on
	# a floor that rose with it.
	var on_floor := int(_local.get("controller").get("state").get("mode")) == GSFpsState.Mode.GROUND
	if is_nan(_floor_y) and on_floor:
		_floor_y = feet.y
	var sample: Dictionary = _body.pose_sample(t, _skeleton if is_instance_valid(_skeleton) else null, feet, on_floor)
	if not is_nan(_floor_y):
		sample["ground_y"] = _floor_y
	_body.add(sample)
	_carry_sample(figure, out)
	# Untyped on purpose: a typed local holding a freed node is itself the script error.
	var cam = _client.get("camera")
	var model = _client.get("view_model")
	if not is_instance_valid(cam) or not is_instance_valid(model):
		return out
	var inverse: Transform3D = (cam as Camera3D).global_transform.affine_inverse()
	var weapon = model.call("weapon_node")
	var shown: bool = is_instance_valid(weapon) and (weapon as Node3D).is_visible_in_tree()
	out["shown"] = shown
	# Through a scope the gun is not drawn on purpose (the scope picture is the view) and the zoom moves the camera: neither is a defect of the gun.
	var scoped: bool = (model.has_method("is_scoped") and bool(model.call("is_scoped"))) \
		or (model.has_method("scope_picture_up") and bool(model.call("scope_picture_up")))
	out["scoped"] = scoped
	if shown:
		out["weapon"] = _v((inverse * (weapon as Node3D).global_transform).origin)
		var muzzle: Transform3D = model.call("muzzle_transform")
		out["muzzle"] = _v(inverse * muzzle.origin)
	# The authored motions' clocks, so a hop can be laid against the draw or the reload phase that made it.
	var pose: Dictionary = (model.call("describe") as Dictionary).get("pose", {})
	out["deploy"] = snappedf(float(pose.get("deploy", 1.0)), 0.001)
	out["reload"] = snappedf(float(pose.get("reload", 0.0)), 0.001)
	var seq = model.call("reload_sequence") if model.has_method("reload_sequence") else null
	# Rounds in the drawn gun and in the world's: a by-the-round reload that stops early shows here, not in the pose.
	var player = _client.get("player")
	var rig = player.get("view_rig") if player != null else null
	if rig != null and rig.get("arsenal") != null and rig.arsenal.current() != null:
		out["mag"] = int(rig.arsenal.current().magazine)
	var truth = _client.get("weapons")
	if truth != null and truth.get("arsenal") != null and truth.arsenal.current() != null:
		out["truth_mag"] = int(truth.arsenal.current().magazine)
	if seq != null:
		out["phase"] = String(seq.call("phase_at", out["reload"]))
	var stale := _parts.is_empty()
	for part in _parts:
		if not is_instance_valid(part):
			stale = true
			break
	if stale:
		# The view model's own camera follows the eye on its own: not a hand or weapon part.
		_parts.assign((model as Node).find_children("*", "Node3D", true, false).filter(
			func(n: Node) -> bool: return not n is Camera3D))
		_last_places.clear()
	var places: Array[Vector3] = []
	for part in _parts:
		places.append((inverse * part.global_transform).origin)
	if _last_places.size() != places.size():
		_last_places = places.duplicate()
	var wall: float = model.call("wall_amount")
	var hop := 0.0
	var where := ""
	for n in places.size():
		var d := places[n].distance_to(_last_places[n])
		_last_places[n] = places[n]
		if _parts[n].is_visible_in_tree() and d > hop:
			hop = d
			where = String(_parts[n].name)
	# The wall retract is a timed swing, not a pop: a frame where it moved is not judged.
	out["wall"] = snappedf(wall, 0.001)
	if absf(wall - _last_wall) <= 0.0001 and not scoped and not _was_scoped:
		out["hop"] = snappedf(hop, 0.0001)
		out["part"] = where
	_last_wall = wall
	_was_scoped = scoped
	return out


## The third-person carry as drawn (style, blends, the closed grip), so a capture shows whether it ran at all.
func _carry_sample(figure: Node, out: Dictionary) -> void:
	var person = figure.get("person") if figure != null else null
	if is_instance_valid(person) and person.get("carry") != null:
		out["carry"] = (person.get("carry") as Object).call("describe")
		out["hold"] = person.get("hold")


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]


func _finish(count: int) -> void:
	var fail: Array[String] = []
	var notes: Array[String] = []
	var worst := {}
	if _zombie == null:
		var cap := _limit("view_kick_m") if _clip == "fire" else _limit("view_pop_m")
		var top := 0.0
		var top_at := -1
		for n in range(1, _frames.size()):
			var h := float(_frames[n].get("hop", 0.0))
			var before := float(_frames[n - 1].get("hop", -1.0))
			var after := float(_frames[n + 1].get("hop", -1.0)) if n + 1 < _frames.size() else 0.0
			# A neighbour the wall retract left unjudged (no hop) has no known move: a steady swing that happens to sit
			# beside such frames is not a spike against them.
			if before < 0.0 or after < 0.0 or h < POP_SPIKE * maxf(before, after):
				continue
			if h > top:
				top = h
				top_at = n
		worst["view_hop_m"] = snappedf(top, 0.001)
		if top > cap:
			fail.append("view pop %.3f m > %.3f at #%d (%s)" % [top, cap, top_at, _frames[top_at].get("part", "")])
		# Fists are bare hands: there is no weapon to hide.
		if _clip != "draw" and _subject != "avatar" and _subject != "fists":
			var run := 0
			var longest := 0
			var at := -1
			for n in _frames.size():
				run = 0 if (_frames[n].get("shown", true) or _frames[n].get("scoped", false)) else run + 1
				if run > longest:
					longest = run
					at = n
			if longest > _limit("hidden_frames"):
				fail.append("weapon hidden %d frames to #%d" % [longest, at])
	var limits := GSClipMetrics.limits_for("res://tools/filmstrip_thresholds.json", "")
	for row in _body.evaluate(limits):
		if row.get("skip", false) or String(row.get("check", "")) == "framing":
			continue
		var check := String(row["check"])
		worst[check] = row.get("value")
		if row.get("pass", true):
			continue
		var line := "%s %s > %s %s" % [check, str(row.get("value")), str(row.get("limit")), String(row.get("note", ""))]
		# Foot slide is judged where the stage pace is the body's own: the survivor's, and the common infected's.
		if check == "foot_slide" and _zombie != null and _zkind != &"common":
			notes.append(line)
		else:
			fail.append(line)
	var verdict := {"item": _subject, "clip": _clip, "frames": count, "fps": fps, "pass": fail.is_empty(), "fail": fail,
		"notes": notes, "worst": worst}
	print("VISUALQA " + JSON.stringify(verdict))
	print("ANIMFRAMES " + JSON.stringify({"item": _subject, "clip": _clip, "frames": _frames}))


# --- the infected ---------------------------------------------------------------------------------------------------------


func _run_zombies() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.32, 0.36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.55
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 155, 0)
	sun.shadow_enabled = true
	# A short shadow range keeps the shadow's bias small: a foot on the floor touches its own shadow, so one that does not is
	# floating, not the light's fault.
	sun.directional_shadow_max_distance = 25.0
	root.add_child(sun)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	floor_mesh.mesh = plane
	ground.add_child(floor_mesh)
	root.add_child(ground)
	_eye = Camera3D.new()
	_eye.fov = 70.0
	root.add_child(_eye)
	_eye.make_current()
	_views.setup(root, root.world_3d)
	var body: GDScript = load("res://npcs/zz_zombie_body.gd")
	var anim_enum: Dictionary = body.get_script_constant_map()["Anim"]
	var clips: PackedStringArray = _anims if not _anims.is_empty() else ZOMBIE_CLIPS
	for kind in _zombies:
		_zkind = kind
		_subject = "zombie_%s" % kind
		for clip in clips:
			if not ZOMBIE_ANIM.has(clip):
				continue
			_build_zombie(kind)
			if _zombie == null:
				_missing(clip, "no view for %s" % kind)
				break
			_zanim = int(anim_enum[ZOMBIE_ANIM[clip]])
			_zspeed = float(ZOMBIE_SPEED[clip])
			for _i in 6:
				_zombie.call("present", 1.0 / float(fps), _zanim, 0)
				await process_frame
			var flinch_at: Array[int] = [_count(0.4), _count(1.1)]
			var die_at := _count(0.4)
			_zdead = false
			await _capture(clip, _count(float(SECONDS["z_" + clip])), func(i: int) -> void:
				if clip == "flinch" and i in flinch_at:
					_zombie.call("flinch")
				elif clip == "die" and i == die_at:
					_zombie.call("die", &"limp", Vector3(-1.0, 0.0, 0.0), 1)
					_zdead = true
					# The view plays its death only while the body says DEAD, as the server's does from then on.
					_zanim = int(anim_enum["DEAD"])
				_zpos.x += _zspeed / float(fps)
				_zombie.position = _zpos
				_zombie.call("present", 1.0 / float(fps), _zanim, 0))
	if _zombie != null:
		_zombie.queue_free()
	_done = true


func _build_zombie(kind: StringName) -> void:
	if _zombie != null:
		_zombie.queue_free()
		_zombie = null
	var views: GDScript = load("res://game/zz_world_view.gd")
	_zombie = views.call("view_for", kind)
	if _zombie == null:
		return
	root.add_child(_zombie)
	_zombie.rotation.y = deg_to_rad(-90.0)
	_zombie.call("build", kind, 1)
	_zpos = Vector3.ZERO
	_zombie.position = _zpos
	_body = GSClipMetrics.new()
	_skeleton = null


func _zombie_skeleton() -> Skeleton3D:
	if (_skeleton == null or not is_instance_valid(_skeleton)) and _zombie != null:
		var found := _zombie.find_children("*", "Skeleton3D", true, false)
		_skeleton = null if found.is_empty() else found.front() as Skeleton3D
	return _skeleton


## The infected faces +x (yaw -90 degrees): the victim stands 1.8 m ahead of it at eye height; the outside views are the shared ones.
func _stage_zombie() -> void:
	_eye.look_at_from_position(_zpos + Vector3(1.8, 1.6, 0.0), _zpos + Vector3(0.0, 1.3, 0.0))
	_views.place(_zpos, deg_to_rad(-90.0))
