extends "zz_client_fitting.gd"
## How a map's ending shows on the client: the slow clock and the ending camera.


## A map's own ending slows the client's time for a moment and, with a camera point, takes the view there;
## the game's clock is the server's, so only what is drawn and heard slows.
func _on_map_ending(_won: bool, raw_scale: float, raw_seconds: float, raw_point: Variant) -> void:
	var sane := ZzEventsMapFx.sane_end(raw_scale, raw_seconds, raw_point)
	var time_scale: float = sane["time_scale"]
	var seconds: float = sane["seconds"]
	var camera_point: Variant = sane["camera"]
	var slow := time_scale < 1.0 and seconds > 0.0
	var real_seconds := minf(seconds * time_scale if slow else seconds, END_HOLD_MAX)
	if camera_point is Vector3 and game != null and game.end_camera_rules.is_on():
		begin_end_camera(camera_point, real_seconds if real_seconds > 0.0 else game.end_camera_rules.window)
	if not slow or (DisplayServer.get_name() == "headless" and not slowmo_in_headless):
		return
	reset_slowmo()
	_slowed = true
	Engine.time_scale = time_scale
	# Only the newest ending's timer may restore the clock: an older one would end this one early.
	var gen := _slow_gen
	var t := get_tree().create_timer(real_seconds, true, false, true)
	t.timeout.connect(func() -> void:
		if gen == _slow_gen:
			reset_slowmo())


## Gives the clock back to normal speed and drops any pending slow-motion timer.
func reset_slowmo() -> void:
	_slow_gen += 1
	if _slowed:
		Engine.time_scale = 1.0
		_slowed = false


## Starts the ending camera at [param point] for [param real_seconds] of unscaled time.
func begin_end_camera(point: Vector3, real_seconds: float) -> void:
	_end_point = point
	_end_left = maxf(real_seconds, 0.1)
	_end_elapsed = 0.0
	_end_active = true


## 0 on the survivor's own eyes, 1 on the map's ending camera.
func end_camera_weight() -> float:
	return _end_weight


## Where the ending camera stands and looks: [param point] seen from [param focus], circling it [param orbit_deg] degrees.
static func end_camera_pose(point: Vector3, focus: Vector3, orbit_deg: float) -> Transform3D:
	var offset := point - focus
	if offset.length() < 1.5:
		offset = Vector3(0.0, 1.0, 3.0)
	var at := focus + offset.rotated(Vector3.UP, deg_to_rad(orbit_deg))
	var pose := Transform3D(Basis.IDENTITY, at)
	return pose.looking_at(focus, Vector3.UP)


## Glides the view to the ending camera and back; a map without a point never gets here.
func _present_end_camera(delta: float, focus: Vector3) -> void:
	if not _end_active and _end_weight <= 0.0:
		return
	var real := delta / maxf(Engine.time_scale, 0.01)
	var rules := game.end_camera_rules
	var glide := maxf(rules.blend, 0.05)
	_end_elapsed += real
	_end_left -= real
	var goal := 1.0 if (_end_active and _end_left > 0.0 and rules.is_on()) else 0.0
	_end_weight = move_toward(_end_weight, goal, real / glide)
	if goal == 0.0:
		_end_active = false
	if _end_weight <= 0.0:
		return
	var smooth := smoothstep(0.0, 1.0, _end_weight)
	var target := end_camera_pose(_end_point, focus, rules.orbit * _end_elapsed)
	camera.global_transform = camera.global_transform.interpolate_with(target, smooth)
