extends SceneTree

## Plays one scripted clip of tools/filmstrip_scenarios.json for `--write-movie`: a survivor
## through the real offline client (first or third person) or a common infected on a stage.
## Run by tools/filmstrip_run.sh with user args `<clip> <fp|tp>`.

const BUTTON_ACTIONS := {"sprint": &"dot_fps_sprint", "walk": &"dot_fps_walk", "crouch": &"dot_fps_crouch"}

var _clip: DotScenario = null
var _view := "tp"
var _client: Node = null
var _game: Object = null
var _local: Object = null
var _zombie: Node3D = null
var _camera: Camera3D = null
var _metrics := DotClipMetrics.new()
var _time := -1.0
var _prev := -1.0
var _frames := 0
var _all := 0
var _start_frame := 0
var _anim := 0
var _speed := 0.0
var _pos := Vector3.ZERO
var _skeleton: Skeleton3D = null
var _parts: Array[Node3D] = []
## Where each part was when last visible: a part that reappears is measured against that.
var _last_places: Array[Vector3] = []
var _worst_hop := 0.0
var _worst_at := 0.0
var _worst_part := ""
var _log: Array[String] = []
var _zombie_script: GDScript = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var clips := DotScenario.load_file("res://tools/filmstrip_scenarios.json")
	if args.is_empty() or not clips.has(args[0]):
		printerr("filmstrip: clip %s not in %s" % [str(args), str(clips.keys())])
		quit(2)
		return
	_clip = clips[args[0]]
	_view = args[1] if args.size() > 1 else "tp"
	if _clip.fields.get("subject", "survivor") == "zombie":
		_stage()
	else:
		var client_script: GDScript = load("res://game/zz_client.gd")
		_client = client_script.new()
		_client.name = "Client"
		_client.set("force_offline", true)
		_client.set("standalone_content", false)
		_client.set("offline_bots", 3)
		root.add_child(_client)


func _stage() -> void:
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
	root.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	floor_mesh.mesh = plane
	root.add_child(floor_mesh)
	var views: GDScript = load("res://game/zz_world_view.gd")
	_zombie = views.view_for(&"common")
	root.add_child(_zombie)
	_zombie.rotation.y = deg_to_rad(-90.0)
	_zombie.call("build", &"common", 1)
	_pos = Vector3(-4.0, 0.0, 0.0)
	_zombie.position = _pos
	_camera = Camera3D.new()
	root.add_child(_camera)
	_camera.current = true
	_camera.fov = 50.0


func _process(delta: float) -> bool:
	_all += 1
	if _clip == null:
		return false
	if _zombie != null:
		return _zombie_frame(delta)
	if _game == null:
		_game = _client.get("game")
	_local = _client.get("player")
	if _game == null or _local == null or int(_game.get("phase")) == 0:
		return false
	if _frames == 0:
		_frames = 1
		_set_up()
		return false
	_time += delta
	_survivor_frame()
	if _time >= _clip.duration:
		return _finish()
	return false


func _set_up() -> void:
	_local.set("is_bot", false)
	_local.health.invulnerable = true
	var at: Array = _clip.fields["spawn"]
	var stand := Vector3(float(at[0]), float(at[1]), float(at[2]))
	_local.call("place_at", stand, float(_clip.fields["spawn_yaw"]))
	for other in _game.call("survivors"):
		if other != _local:
			other.health.invulnerable = true
			other.call("place_at", stand + Vector3(0.0, 0.0, 400.0), 0.0)
	if _view == "tp":
		_client.call("toggle_view")
		_camera = Camera3D.new()
		_camera.fov = 50.0
		root.add_child(_camera)
		_camera.make_current()
	_time = -0.3
	_start_frame = _all


## Everything the client draws on a canvas, hidden every frame (a banner or cover can reappear).
func _hide_overlays() -> void:
	for layer in _client.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var hud: Object = _client.get("hud")
	if hud != null:
		hud.visible = false


func _survivor_frame() -> void:
	_hide_overlays()
	var live := _time >= 0.0
	var state := _clip.state_at(maxf(_time, 0.0))
	var want: Array = state["buttons"] if live else []
	var move: Array = state["move"] if live else [0.0, 0.0]
	_actions(move, want)
	_client.set("_firing", want.has("fire"))
	_client.set("_reloading", want.has("reload"))
	if live:
		for step: Dictionary in _clip.events_between(_prev, _time):
			_event(String(step["event"]))
	_prev = _time
	if not live:
		return
	var feet: Vector3 = _local.call("feet")
	if _view == "fp":
		_first_person_sample(feet)
		return
	# Own camera: the game's chase view crops the legs and the death cuts to the spectate view.
	_camera.look_at_from_position(feet + Vector3(3.2, 1.4, 2.0), feet + Vector3(0.0, 0.85, 0.0))
	_camera.make_current()
	var sample := _metrics.pose_sample(_time, _find_skeleton(_local.get("figure")), feet, true)
	var points: Array[Vector2] = []
	for spot: Vector3 in [feet, feet + Vector3(0.0, 1.6, 0.0)]:
		points.append(_unit(_camera, spot))
	sample["points"] = points
	_metrics.add(sample)
	_log.append("%.2f pos=(%.1f,%.1f,%.1f) %s" % [_time, feet.x, feet.y, feet.z, str(sample.get("points", ""))])


## The hands and weapon in the eye's frame: their rotations feed the bone-pop check and the
## largest hop of any part's position is the "view_pop" row (the body is hidden in first person).
func _first_person_sample(feet: Vector3) -> void:
	var cam: Camera3D = _client.get("camera")
	var model: Node = _client.get("view_model")
	if cam == null or model == null:
		return
	if _parts.is_empty() or _parts.any(func(n: Node3D) -> bool: return not is_instance_valid(n)):
		_parts.assign(model.find_children("*", "Node3D", true, false))
		_last_places.clear()
	var inverse := cam.global_transform.affine_inverse()
	var rotations: Array = []
	var places: Array[Vector3] = []
	var shown: Array[bool] = []
	for part: Node3D in _parts:
		var local := inverse * part.global_transform
		rotations.append(local.basis.get_rotation_quaternion())
		places.append(local.origin)
		shown.append(part.is_visible_in_tree())
	_metrics.add({"t": _time, "root": feet, "ground_y": feet.y, "grounded": true, "rotations": rotations})
	if _last_places.size() != places.size():
		_last_places = places.duplicate()
	for i in places.size():
		# Hidden pairs and a part going hidden are never seen; a reappearing part is judged from where it vanished.
		if not shown[i]:
			continue
		var hop := places[i].distance_to(_last_places[i])
		if hop > _worst_hop:
			_worst_hop = hop
			_worst_at = _time
			_worst_part = "%s (%s)" % [_parts[i].get_path(), _parts[i].get_class()]
		_last_places[i] = places[i]
	_log.append("%.2f pos=(%.1f,%.1f,%.1f)" % [_time, feet.x, feet.y, feet.z])


func _actions(move: Array, want: Array) -> void:
	var wanted := {&"dot_fps_forward": float(move[1]) < -0.1, &"dot_fps_back": float(move[1]) > 0.1,
		&"dot_fps_left": float(move[0]) < -0.1, &"dot_fps_right": float(move[0]) > 0.1}
	for button: String in BUTTON_ACTIONS:
		wanted[BUTTON_ACTIONS[button]] = want.has(button)
	for action: StringName in wanted:
		if wanted[action]:
			Input.action_press(action)
		else:
			Input.action_release(action)


func _event(event: String) -> void:
	var combat: Object = _game.get("combat")
	match event:
		"hit", "down":
			_local.health.invulnerable = false
			var amount := 20.0 if event == "hit" else 500.0
			combat.call("apply_damage", DotDamage.make(0, _local.get("entity_id"), amount, combat.call("damage_type", &"strike")))
			_local.health.invulnerable = true
		"die":
			_game.call("_die", _local, &"strike", &"filmstrip")
		"revive":
			# A stand-in kneels beside the downed survivor and holds the real revive (config seconds).
			for other in _game.call("survivors"):
				if other != _local:
					other.call("place_at", _local.call("feet") + Vector3(0.6, 0.0, 0.0), 0.0)
					_game.call("_start", other, &"revive", _local.get("entity_id"), float(_game.get("config").revive_seconds))
					return


func _zombie_frame(delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		# Soles from the body standing at rest: a run's first live frame can be both feet in the air.
		_metrics.pose_sample(0.0, _find_skeleton(_zombie), _pos, true)
	if _frames > 2:
		_time += delta
	var live := _time >= 0.0
	var state := _clip.state_at(maxf(_time, 0.0))
	if state.has("speed"):
		_speed = float(state["speed"])
	if state.has("anim"):
		var body: GDScript = load("res://npcs/zz_zombie_body.gd")
		_anim = int(body.Anim[String(state["anim"])])
	if live:
		for step: Dictionary in _clip.events_between(_prev, _time):
			match String(step["event"]):
				"flinch":
					_zombie.call("flinch")
				"die":
					_zombie.call("die", &"limp", Vector3(0.0, 0.0, 1.0), 1)
	_prev = _time
	_pos.x += _speed * delta
	_zombie.position = _pos
	_zombie.call("present", delta, _anim, 0)
	_camera.look_at_from_position(_pos + Vector3(2.4, 1.2, 3.4), _pos + Vector3(0.6, 0.9, 0.0))
	if live:
		var sample := _metrics.pose_sample(_time, _find_skeleton(_zombie), _pos, true)
		var points: Array[Vector2] = []
		for spot: Vector3 in [_pos, _pos + Vector3(0.0, 1.7, 0.0)]:
			points.append(_unit(_camera, spot))
		sample["points"] = points
		_metrics.add(sample)
		var feet: Array = sample.get("feet", [])
		_log.append("%.2f x=%.2f speed=%.2f feet=%s" % [_time, _pos.x, _speed, str(feet.map(func(f: Vector3) -> String: return "%.3f,%.3f" % [f.x - _pos.x, f.y - _pos.y]))])
	if _time >= _clip.duration:
		return _finish()
	return false


func _find_skeleton(node: Node) -> Skeleton3D:
	if _skeleton == null and node != null:
		var found := node.find_children("*", "Skeleton3D", true, false)
		if not found.is_empty():
			_skeleton = found.front() as Skeleton3D
	return _skeleton


func _unit(cam: Camera3D, spot: Vector3) -> Vector2:
	if cam.is_position_behind(spot):
		return Vector2(-1.0, -1.0)
	return cam.unproject_position(spot) / cam.get_viewport().get_visible_rect().size


func _finish() -> bool:
	var label: String = _clip.name if _zombie != null else "%s_%s" % [_clip.name, _view]
	var limits := DotClipMetrics.limits_for("res://tools/filmstrip_thresholds.json", _clip.name)
	print("FILMSTRIP_CLIP start_frame=%d frames=%d" % [_start_frame, _all - _start_frame])
	var rows := _metrics.evaluate(limits)
	if _view == "fp" and _zombie == null:
		var cap := float(limits.get("view_hop_m", 0.15))
		rows.append({"check": "view_pop", "pass": _worst_hop <= cap, "value": "%.3f" % _worst_hop, "limit": "%.3f" % cap,
			"note": "m, largest hop of a hand or weapon part between frames (eye frame), at %.2f s, %s; %d parts" % [_worst_at, _worst_part, _parts.size()]})
	var text := DotClipMetrics.table(label, rows)
	print(text)
	DotClipMetrics.write_report("res://screenshots/filmstrip/%s_report.txt" % label, text, _log)
	return true
