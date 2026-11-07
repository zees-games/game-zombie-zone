extends "zz_zombie_view_base.gd"

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

	var library := _with_ual(body_id, _skeleton, _library_for(body_id, _skeleton))

	if library != null and not _anim.has_animation_library(&"zz"):
		var _added := _anim.add_animation_library(&"zz", library)

	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	# The kit faces +Z; this family's forward is -Z.
	var raw := _measure(_skeleton, _model, float(HEAD_TOP.get(body_id, 1.22)))
	_scale = float(_look["height"]) / maxf(raw, 0.01)
	var girth := float(_look["girth"])
	_model.basis = Basis(Vector3.UP, PI).scaled(Vector3(_scale * girth, _scale, _scale * girth))
	_hunch = float(_look.get("hunch", 0.0))

	_bones.clear()
	for bone in [&"Abdomen", &"Torso", &"Neck", &"Head", &"Hips", &"Tongue1", &"Tongue2", &"Tongue3", &"BottomMouth"]:
		_bones[bone] = _skeleton.find_bone(String(bone))

	_limbs.clear()
	_legs.clear()
	_plant.reset()
	for bone in ["UpperArm", "LowerArm", "UpperLeg", "LowerLeg", "Foot"]:
		for side in [".L", ".R"]:
			_limbs[bone + side] = _skeleton.find_bone(bone + side)

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
	_mesh.visibility_range_end = lod.draw_until if lod != null else 120.0
	_mesh.lod_bias = LOD_BIAS
	_mesh.visibility_range_end_margin = 10.0

	for item: StringName in _look.get("wear", []):
		_wear(item)

	_clip = &""
	_play(&"idle", 1.0)


## [DotNpcLimbs]' view seam: takes a limb off the drawn body, and returns where it was cut.
func sever_limb(limb: StringName, d: Dictionary, impulse: Vector3) -> Vector3:
	if _skeleton == null or _model == null:
		return Vector3.INF

	_note_limb(limb)
	var joint := DotNpcGibs.sever(_skeleton, _model, "%s/%s" % [body_id, limb], limb, d, impulse)
	_fade_new_parts(limb, joint)
	return joint


## A limb that was gone before this machine saw the zombie: the stump alone.
func stump_limb(limb: StringName, d: Dictionary) -> Vector3:
	if _skeleton == null or _model == null:
		return Vector3.INF

	_note_limb(limb)
	var joint := DotNpcGibs.sever(_skeleton, _model, "%s/%s" % [body_id, limb], limb, d, Vector3.ZERO, true)
	_fade_new_parts(limb, joint)
	return joint


## Draws the zombie at [param alpha] (1 solid). Every mesh gets its own copy of its material, so
## the look shared by the whole crowd is never written; a copy only exists while a zombie fades.
## The shadow stays solid: a body that is there still blocks the light.
func set_fade(alpha: float) -> void:
	alpha = clampf(alpha, 0.0, 1.0)

	if is_equal_approx(alpha, _fade):
		return

	_fade = alpha
	_fade_meshes(find_children("*", "MeshInstance3D", true, false))


func fade() -> float:
	return _fade


func _fade_meshes(meshes: Array) -> void:
	for node: Node in meshes:
		var m := node as MeshInstance3D
		var kept: Variant = m.get_meta(&"zz_solid") if m.has_meta(&"zz_solid") else null

		if _fade >= 0.999:
			if kept != null:
				m.material_override = kept as Material
				m.remove_meta(&"zz_solid")
			continue

		var mat := m.get_meta(&"zz_faded") as Material if m.has_meta(&"zz_faded") else null

		if mat == null:
			var source := m.material_override

			if source == null:
				continue

			mat = _faded_copy(source)
			m.set_meta(&"zz_faded", mat)

		if kept == null:
			m.set_meta(&"zz_solid", m.material_override)

		m.material_override = mat

		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter(&"fade", _fade)
		elif mat is BaseMaterial3D:
			var c := (mat as BaseMaterial3D).albedo_color
			c.a = _fade
			(mat as BaseMaterial3D).albedo_color = c


static func _faded_copy(source: Material) -> Material:
	var copy := source.duplicate() as Material

	if copy is ShaderMaterial:
		if _fade_shader == null:
			_fade_shader = Shader.new()
			_fade_shader.code = SHADER \
				.replace("specular_disabled;", "specular_disabled, depth_draw_always;") \
				.replace("uniform float lift = 0.0;", "uniform float lift = 0.0;\nuniform float fade = 1.0;") \
				.replace("EMISSION = ", "ALPHA = fade;\n\tEMISSION = ")

		(copy as ShaderMaterial).shader = _fade_shader
	elif copy is BaseMaterial3D:
		(copy as BaseMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	return copy


## A cut makes a stump on the body and a flying limb in the world; both follow the zombie's alpha.
func _fade_new_parts(limb: StringName, joint: Vector3) -> void:
	if _fade >= 0.999 or _model == null:
		return

	_fade_meshes(find_children("*", "MeshInstance3D", true, false))

	if joint == Vector3.INF or _material == null or not is_inside_tree():
		return

	var best: Node3D = null

	for n: Node in get_tree().get_nodes_in_group(DotNpcGibs.GROUP):
		var gib := n as Node3D

		if gib != null and gib.name == "Gib_%s" % limb and not gib.is_queued_for_deletion():
			if best == null or gib.global_position.distance_to(joint) < best.global_position.distance_to(joint):
				best = gib

	if best == null:
		return

	for mi: Node in best.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.material_override = _faded_copy(m.material_override if m.material_override != null else _mesh.get_meta(&"zz_solid") if _mesh.has_meta(&"zz_solid") else _mesh.material_override)
		(m.material_override as ShaderMaterial).set_shader_parameter(&"fade", _fade)


func _trail(at: Vector3) -> void:
	if _speed < 0.25 or not is_inside_tree():
		return
	if _trail_from == Vector3.INF or at.distance_to(_trail_from) > 0.8:
		_trail_from = at
		var _pool := DotNpcGibs.add_pool(get_tree(), at, 0.2)


func _note_limb(limb: StringName) -> void:
	if String(limb).begins_with("leg"):
		_legs_gone += 1


## A wet mark on the body where a shot landed (client only, pooled and capped by DotNpcGore.max_wounds).
func wound_at(world_point: Vector3, size := 0.09) -> void:
	if _skeleton != null and kind != &"":
		var _mark := DotNpcGibs.add_wound(_skeleton, world_point, size)


func restore_limbs() -> void:
	_legs_gone = 0
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

## The locomotion style for a body moving at [param speed] m/s that was last in [param prior]; a
## look's [param gait] overrides [constant GAIT]. Hysteresis keeps a body at the edge from flickering.
static func gait_for(speed: float, prior: StringName, gait: Dictionary = {}) -> StringName:
	var below := float(gait.get("shamble_below", GAIT["shamble_below"]))
	var from := float(gait.get("run_from", GAIT["run_from"]))

	if speed < below:
		return GAIT_SHAMBLE
	if speed >= from:
		return GAIT_RUN

	return prior


## One frame: the clip for [param anim], the pose over it, and the flags drawn.
func present(delta: float, anim: int, flags: int) -> void:
	if _model == null:
		return

	_frame += 1
	var at := global_position
	_track_motion(at, delta)

	if anim == ZzZombieBody.Anim.DEAD and _death.is_empty():
		die(&"limp", Vector3.ZERO, variant)

	var striking := anim == ZzZombieBody.Anim.ATTACK or anim == ZzZombieBody.Anim.STRIKE_DOWN
	var prior := _strike_phase
	_pick_base_clip(anim)
	_advance_strike(striking, delta)

	var overrides: Dictionary = _look.get("clips", {})
	_want_clip = overrides.get(_want_clip, _want_clip)

	# No legs: it drags itself on its arms and leaves a trail.
	if _legs_gone >= 2 and anim != ZzZombieBody.Anim.DEAD and (_want_clip == &"walk" or _want_clip == &"run" or _want_clip == &"run_arms" or _want_clip == &"idle"):
		_want_clip = &"crawl"
		_trail(at)

	# A new swing starts its clip over, so the swing's frames follow the brain's swing.
	if striking and _strike_phase < prior and _anim != null and _anim.has_animation(_qualified(_want_clip)):
		_clip = &""

	_pace_to_ground()
	_shamble = move_toward(_shamble, 1.0 if _want_clip == &"walk" and _gait == GAIT_SHAMBLE and anim != ZzZombieBody.Anim.IDLE else 0.0, delta * 3.0)
	_swap_for_real_clip(anim, striking, overrides)
	_pick_reaction_clip(delta, anim, striking)
	_prior_anim = anim

	var clip := _want_clip
	var rate := _want_rate
	_rate = rate
	_play(clip, rate)

	var every := _lod_every(at)
	_owed += delta
	_flinch = maxf(_flinch - delta * 4.0, 0.0)

	# The bones are written only on a frame the clip was evaluated: the overrides go on top of
	# the clip's pose, so writing them again over last frame's result would stack them.
	if (_frame + (variant & 3)) % every == 0:
		_advance_clip(clip, rate)
		_owed = 0.0
		_pose(anim)

	_draw_flags(flags)

	if anim == ZzZombieBody.Anim.DEAD:
		_dead_for = maxf(_dead_for, 0.0) + delta
		_present_death(delta)


## Speed, velocity and climb rate of the body, smoothed, from where it stood last frame.
func _track_motion(at: Vector3, delta: float) -> void:
	if _last_at != Vector3.INF and delta > 0.0:
		var moved := Vector2(at.x - _last_at.x, at.z - _last_at.z).length() / delta
		_speed = lerpf(_speed, moved, clampf(delta * 8.0, 0.0, 1.0))
		_velocity = _velocity.lerp(Vector3(at.x - _last_at.x, 0.0, at.z - _last_at.z) / delta, clampf(delta * 8.0, 0.0, 1.0))
		_climb = lerpf(_climb, (at.y - _last_y) / delta, clampf(delta * 10.0, 0.0, 1.0))
	_last_at = at
	_last_y = at.y


## The clip and rate the brain's state asks for, adjusted by how the body really moves.
func _pick_base_clip(anim: int) -> void:
	var wanted: Array = CLIPS.get(anim, CLIPS[ZzZombieBody.Anim.IDLE])
	_want_clip = wanted[0]
	_want_rate = float(wanted[1])
	var moving := false

	# A moving zombie whose state says idle (a mirror between states) walks rather than slides.
	if (anim == ZzZombieBody.Anim.IDLE or anim == ZzZombieBody.Anim.RAGE) and _speed > 0.6:
		_want_clip = &"walk"
		_want_rate = 1.0
		moving = true

	# Walking, shambling and running are told apart by how fast the body really moves, not by the
	# brain's state: a chase at 2 m/s is still a shamble, and a run cycle slowed to fit is the
	# "weird running" the players saw.
	if moving or anim == ZzZombieBody.Anim.WALK or anim == ZzZombieBody.Anim.RUN or anim == ZzZombieBody.Anim.SHAMBLE:
		if _speed > 0.2:
			_gait = gait_for(_speed, _gait, _look.get("gait", {}))
			_want_clip = &"walk" if _gait == GAIT_SHAMBLE else &"run_arms"
		elif anim == ZzZombieBody.Anim.RUN:
			_want_clip = &"walk"
			_gait = GAIT_SHAMBLE

	# Off the ground and going up or falling fast: a climb, a leap, a drop from a ledge.
	if anim != ZzZombieBody.Anim.DEAD and anim != ZzZombieBody.Anim.LEAP and absf(_climb) > 2.5:
		_want_clip = &"jump_idle"

	# A common lunging while it runs swings on the move.
	if anim == ZzZombieBody.Anim.ATTACK and _speed > 1.5:
		_want_clip = &"attack_run"
	elif anim == ZzZombieBody.Anim.ATTACK and kind == &"common" and (attack_anim == 2 or (attack_anim == 0 and (variant & 8) != 0)):
		_want_clip = &"attack_idle"


## Runs the swing's clock while striking and gives each body its own tempo.
func _advance_strike(striking: bool, delta: float) -> void:
	if striking:
		_strike_t += delta
		_strike_phase = fposmod(_strike_t / SWING_PERIOD, 1.0)
		# Attack variety: a body's own tempo, so a crowd does not swing in step.
		_want_rate *= 0.9 + 0.1 * float(variant & 7) / 3.5
	else:
		_strike_t = 0.0
		_strike_phase = 0.0


## Sets the playback rate of a walk or run from the ground speed, so a planted foot stands still.
func _pace_to_ground() -> void:
	var clip := _want_clip
	if clip == &"walk" or clip == &"run" or clip == &"run_arms" or clip == &"crawl":
		var natural := {&"walk": 1.3, &"run": 5.0, &"run_arms": 5.0, &"crawl": 1.2}[clip] as float
		natural *= float(_look["height"]) / 1.75
		if _speed > 0.2 and _want_rate > 0.0:
			if clip == &"walk" and _gait == GAIT_SHAMBLE:
				var sh := shamble_numbers(_look)
				# A planted foot must stand still on the ground, so stride times rate equals the ground speed:
				# short steps are taken quicker, and the stride lengthens where the rate would pass its cap.
				natural = 1.8 * float(_look["height"]) / 1.75 if _ual else natural
				var real := _anim != null and _anim.has_animation(_qualified(&"ual_zombie_walk"))
				# The real walk reads small below a 0.6 stride, so it takes a lower floor and a lower rate cap.
				var cap := float(sh["cadence"]) * (1.3 if real else (1.6 if kind == &"common" else 1.0))
				_stride = 1.0 if real else clampf(_speed / (natural * cap), float(sh["swing"]), 1.0)
				_want_rate = clampf(_speed / (natural * _stride), 0.35, cap)
			else:
				_want_rate = clampf(_speed / natural, 0.7, 1.8)


## Swaps a generic clip for the real animation-library one when the body has it.
func _swap_for_real_clip(anim: int, striking: bool, overrides: Dictionary) -> void:
	# Each common keeps its own tempo (plus or minus 15%) so a crowd does not step together.
	_ual = false

	if UAL_FOR.has(_want_clip) and _has(UAL_FOR[_want_clip]):
		_want_clip = UAL_FOR[_want_clip]
		_want_rate *= 0.85 + 0.3 * float((variant >> 3) & 15) / 15.0
		_ual = true

		if striking and _want_clip == &"ual_zombie_scratch":
			# The free scratch clip is 1.8 s: played at this rate one swing is one whole windup, strike and recovery.
			_want_rate = 1.8 / SWING_PERIOD

		# A slow run is the jog: the sprint clip's stride at 3 m/s is a skid.
		if _want_clip == &"ual_sprint" and _speed > 0.2 and _speed < JOG_BELOW and _has(&"ual_jog"):
			_want_clip = &"ual_jog"
			_want_rate = clampf(_speed / (JOG_NATURAL * float(_look["height"]) / 1.75), 0.7, 1.5)

	# A stalking crouch (not a crawler's or a leaper's, which crawl all the time) is the real squat walk.
	if anim == ZzZombieBody.Anim.CROUCH and _want_clip == &"crawl" and overrides.get(&"walk", &"") != &"crawl" and _has(&"ual_crouch_walk"):
		_want_clip = &"ual_crouch_walk"
		_want_rate = clampf(_speed / (CROUCH_NATURAL * float(_look["height"]) / 1.75), 0.5, 1.6) if _speed > 0.2 else 1.0


## A bullet's flinch and a rise from the ground take over the clip for a moment.
func _pick_reaction_clip(delta: float, anim: int, striking: bool) -> void:
	_hit_left = maxf(_hit_left - delta, 0.0)
	_rise_left = maxf(_rise_left - delta, 0.0)

	# A bullet's flinch on a standing body is a short hit clip.
	if _hit_left > 0.0 and _speed < 0.6 and anim != ZzZombieBody.Anim.DEAD and not striking \
			and _has(&"ual_hit_head") and _has(&"ual_hit_chest"):
		_want_clip = &"ual_hit_head" if _hit_head else &"ual_hit_chest"
		_want_rate = 1.0

	# Getting up from sitting, feeding or lying: the lay-to-idle clip, if it stands still while it plays.
	if _rise_left > 0.0 and _speed < 0.6 and _has(&"ual_lay_to_idle") and not striking and anim != ZzZombieBody.Anim.DEAD:
		_want_clip = &"ual_lay_to_idle"
		_want_rate = 1.0

	if (_prior_anim == ZzZombieBody.Anim.SIT or _prior_anim == ZzZombieBody.Anim.FEED or _prior_anim == ZzZombieBody.Anim.CRY) \
			and anim != _prior_anim and _has(&"ual_lay_to_idle"):
		_rise_left = _anim.get_animation(_qualified(&"ual_lay_to_idle")).length


## Level of detail: how often this one is advanced, by where it is from the camera.
func _lod_every(at: Vector3) -> int:
	var every := 1

	if _death.is_empty():
		if lod == null or _own_lod:
			_own_lod = true
			lod = lod if lod != null else ZzZombieLod.new()
			lod.refresh(get_viewport().get_camera_3d() if is_inside_tree() else null)
		every = lod.every(at)
		if _mesh != null and lod.camera_at != Vector3.INF:
			var shadowed := lod.camera_at.distance_to(at) < lod.shadow_until
			if shadowed != _shadowed:
				_shadowed = shadowed
				_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadowed \
						else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return every


## Steps the clip by the time owed, holding a one-shot clip's last frame.
func _advance_clip(clip: StringName, rate: float) -> void:
	if _anim == null or not _anim.has_animation(_qualified(clip)):
		return

	var length := _anim.current_animation_length
	var looping := LOOPING.has(clip)

	if not looping and _anim.current_animation_position + _owed * rate >= length - 0.01:
		# A one-shot clip holds its last frame; evaluated there rather than stepped past
		# the end, where the player stops and nothing writes the pose again.
		_anim.seek(maxf(length - 0.01, 0.0), true)
	else:
		_anim.advance(_owed * rate)


## True when this body has the real clip [param clip] (the file is missing or the body is a capsule otherwise).
func _has(clip: StringName) -> bool:
	return _anim != null and _anim.has_animation(_qualified(clip))


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

	# play() leaves the position where the last clip ended until the next evaluation, so a repeated swing was read as already over and held its last frame.
	if not LOOPING.has(clip):
		_anim.seek(0.0, true)

	# A looping real clip starts at this body's own phase, not at frame zero with its neighbours.
	if LOOPING.has(clip) and String(clip).begins_with("ual_"):
		_anim.seek(fposmod(float(variant) * 0.618034, 1.0) * _anim.current_animation_length, true)


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

	if _shamble > 0.01 and anim != ZzZombieBody.Anim.DEAD:
		_pose_shamble()
		_plant_feet()
	else:
		_plant.reset()
		if anim in STANDING_ANIMS and _clip != &"crawl":
			_ground_feet()

	if anim == ZzZombieBody.Anim.STRIKE_DOWN:
		_pose_ground_strike()
	elif anim == ZzZombieBody.Anim.ATTACK and _look.get("clips", {}).get(&"attack", &"") == &"crawl":
		_pose_lunge()
	elif anim == ZzZombieBody.Anim.PIN:
		_pose_hold()
	elif anim == ZzZombieBody.Anim.LEAP:
		_pose_leap()
	elif anim == ZzZombieBody.Anim.TONGUE:
		_pose_reel()
	elif anim == ZzZombieBody.Anim.GRAB:
		_pose_reach()

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


## The leg chains of [member _legs], found once per body; empty when a bone is missing.
func _leg_chains() -> Array:
	if _legs.is_empty() and _skeleton != null:
		for side in [".L", ".R"]:
			var upper: int = _limbs.get("UpperLeg" + side, -1)
			var lower: int = _limbs.get("LowerLeg" + side, -1)
			var foot: int = _limbs.get("Foot" + side, -1)
			if upper < 0 or lower < 0 or foot < 0:
				_legs.clear()
				break
			var rest := _skeleton.get_bone_global_rest(foot).origin
			var ankle := _skeleton.get_bone_global_rest(lower).affine_inverse() * rest
			_legs.append([upper, lower, ankle, rest, _skeleton.get_bone_rest(lower).origin.length() + ankle.length()])
	return _legs


## Moves the bone the thighs hang from by [param up] (skeleton space) from the clip's key of it, or
## its rest when the clip keys none: an earlier clip's key otherwise stays and sinks the legs.
func _lift_pelvis(up: Vector3) -> void:
	var pelvis := _skeleton.get_bone_parent(int(_legs[0][0]))
	var above := _skeleton.get_bone_parent(pelvis)
	var base := _skeleton.get_bone_rest(pelvis).origin
	var playing := _anim.get_animation(_qualified(_clip)) if _anim != null and _anim.has_animation(_qualified(_clip)) else null
	var suffix := ":" + _skeleton.get_bone_name(pelvis)
	for t in (playing.get_track_count() if playing != null else 0):
		if playing.track_get_type(t) == Animation.TYPE_POSITION_3D and String(playing.track_get_path(t)).ends_with(suffix):
			base = playing.position_track_interpolate(t, _anim.current_animation_position)
			break
	if above >= 0:
		up = DotHumanoidIk.global_pose(_skeleton, above).basis.inverse() * up
	_skeleton.set_bone_pose_position(pelvis, base + up)


## A standing clip's legs: the bone the thighs hang from back on the clip's key (or rest), then
## each ankle the clip puts under the floor bent up onto it, the hips left where the clip has them.
func _ground_feet() -> void:
	if _leg_chains().is_empty():
		return
	_lift_pelvis(Vector3.ZERO)
	for leg: Array in _legs:
		var ankle := DotHumanoidIk.global_pose(_skeleton, leg[1]) * (leg[2] as Vector3)
		var floor_y := (leg[3] as Vector3).y
		if ankle.y < floor_y:
			DotHumanoidIk.two_bone_to(_skeleton, leg[0], leg[1], leg[2], Vector3(ankle.x, floor_y, ankle.z), Vector3(0.0, 0.0, 1.0), 1.0)


## The shamble's legs: each foot stands still on the floor for its stance and swings to its next
## step (dot-player-char's DotFootPlant over the clip's own phase), the hips lowered where a leg
## would not reach and both legs bent to their feet. Weighted by [member _shamble].
func _plant_feet() -> void:
	var legs := _leg_chains()
	if legs.is_empty() or _anim == null:
		return
	_lift_pelvis(Vector3.ZERO)
	var length := maxf(_anim.current_animation_length, 0.01)
	var to_world := _skeleton.global_transform
	var to_skeleton := to_world.affine_inverse()
	var homes: Array[Vector3] = []
	for leg: Array in legs:
		homes.append(to_world * (leg[3] as Vector3))
	var feet := _plant.step(_anim.current_animation_position / length, homes, _velocity, length / maxf(_rate, 0.05))
	var drop := 0.0
	for i in legs.size():
		var hip := DotHumanoidIk.global_pose(_skeleton, legs[i][0]).origin
		var gap := to_skeleton * feet[i] - hip
		var flat := Vector2(gap.x, gap.z).length()
		var longest := float(legs[i][4]) * 0.97
		if gap.length() > longest and flat < longest:
			drop = maxf(drop, -gap.y - sqrt(longest * longest - flat * flat))
	if drop > 0.0:
		_lift_pelvis(Vector3(0.0, -drop * _shamble, 0.0))
	for i in legs.size():
		var _reached := DotHumanoidIk.two_bone_to(_skeleton, legs[i][0], legs[i][1], legs[i][2], to_skeleton * feet[i], Vector3(0.0, 0.0, 1.0), _shamble)


## A look's shamble numbers: [constant SHAMBLE] with the look's own `shamble` keys over it.
static func shamble_numbers(look: Dictionary) -> Dictionary:
	var out := SHAMBLE.duplicate()
	out.merge(look.get("shamble", {}), true)
	return out


## Pulls a limb bone's pose back toward its rest by [param keep] (1 leaves the clip's swing alone).
func _damp(bone: String, keep: float) -> void:
	var index: int = _limbs.get(bone, -1)

	if index >= 0:
		var rest := _skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		_skeleton.set_bone_pose_rotation(index, rest.slerp(_skeleton.get_bone_pose_rotation(index), keep))


func _pitch_limb(bone: String, angle: float) -> void:
	var index: int = _limbs.get(bone, -1)

	if index >= 0:
		_pitch_index(index, angle)


## The shamble over the walk clip: stooped, head hung and lolling, short uneven steps with one foot
## dragged, the torso and hips rolling with each step. Numbers are per look ([constant SHAMBLE]).
var _ual := false
var _hit_left := 0.0
var _hit_head := false
var _rise_left := 0.0
var _prior_anim := -1
## The stride [method present] matched to the ground speed: the share of the clip's leg swing kept.
var _stride := 0.4


func _pose_shamble() -> void:
	var k := _shamble
	var n := shamble_numbers(_look)
	var length := maxf(_anim.current_animation_length, 0.01) if _anim != null else 1.0
	var phase := (_anim.current_animation_position / length) if _anim != null else 0.0
	var roll := sin(phase * TAU)
	var drag := ".L" if (variant & 2) != 0 else ".R"
	var reach := (variant & 1) != 0
	var swing := lerpf(1.0, _stride, k)

	# Legs first: the stride matched to the ground speed, so a planted foot holds still.
	for side in [".L", ".R"]:
		_damp("UpperLeg" + side, swing)
		_damp("LowerLeg" + side, 1.6)

	_pitch(&"Abdomen", 0.8 * float(n["stoop"]) * k)
	_pitch(&"Torso", float(n["stoop"]) * k)
	_pitch(&"Head", float(n["head"]) * k)

	var torso: int = _bones.get(&"Torso", -1)

	if torso >= 0:
		_roll_index(torso, roll * float(n["sway"]) * k)

	var hips: int = _bones.get(&"Hips", -1)

	if hips >= 0:
		# Weight drops onto the good leg: a roll twice as fast as the stride's, off-centre toward it.
		var dip := float(n["hip"]) * (sin(phase * TAU + float(n["lurch"])) * 0.7 + 0.5 * (1.0 if drag == ".R" else -1.0)) * k
		# The clip does not key the hips, so a roll on the current pose would pile up every frame.
		_skeleton.set_bone_pose_rotation(hips, _skeleton.get_bone_rest(hips).basis.get_rotation_quaternion())
		_roll_index(hips, dip)

	var head: int = _bones.get(&"Head", -1)

	if head >= 0:
		_skeleton.set_bone_pose_rotation(head, Quaternion(Vector3.FORWARD, (0.3 * k) * sin(phase * TAU * 0.5 + float(variant))) * _skeleton.get_bone_pose_rotation(head))

	for side in [".L", ".R"]:
		_pitch_limb("UpperArm" + side, float(n["arms"] if reach else n["hang"]) * k)
		_pitch_limb("LowerArm" + side, (0.3 if reach else 0.1) * k)

	# The dragged leg: thigh trailing behind the body, shin hanging, toe scuffing.
	_pitch_limb("UpperLeg" + drag, -0.2 * k)
	_pitch_limb("LowerLeg" + drag, float(n["trail"]) * k * (0.75 + 0.25 * roll))
	_pitch_limb("Foot" + drag, 0.3 * k)


## How far into the blow it is: 0 at rest, rising to 1 on the swing's landing frame.
func _strike_curve() -> float:
	var p := _strike_phase

	if p < HIT_AT:
		return -0.35 * sin(p / HIT_AT * PI * 0.5)

	var q := (p - HIT_AT) / (1.0 - HIT_AT)
	return lerpf(1.0, 0.0, clampf(q * 1.6, 0.0, 1.0)) if q < 0.625 else 0.0


## Swings [param bone]'s tip forward by [param angle] (negative backward) about the body's own side
## axis, whatever the bone's own axes are. The kit faces +Z in skeleton space.
func _pitch(bone: StringName, angle: float) -> void:
	var index: int = _bones.get(bone, _limbs.get(String(bone), -1))

	if index >= 0:
		_pitch_index(index, angle)


## Rolls a bone about the body's own forward axis, whatever the bone's own axes are.
func _roll_index(index: int, angle: float) -> void:
	var parent := _skeleton.get_bone_parent(index)
	var parent_basis := _skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var global := _skeleton.get_bone_global_pose(index).basis.orthonormalized()
	var local := parent_basis.inverse() * Basis(Vector3.BACK, angle) * global
	_skeleton.set_bone_pose_rotation(index, local.orthonormalized().get_rotation_quaternion())


func _pitch_index(index: int, angle: float) -> void:
	var parent := _skeleton.get_bone_parent(index)
	var parent_basis := _skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var global := _skeleton.get_bone_global_pose(index).basis.orthonormalized()
	var local := parent_basis.inverse() * Basis(Vector3.RIGHT, -angle) * global
	_skeleton.set_bone_pose_rotation(index, local.orthonormalized().get_rotation_quaternion())


## Kneeling over a downed survivor: knees bent, chest folded over, both arms raised on the windup
## and driven down on the landing frame.
func _pose_ground_strike() -> void:
	var hit := _strike_curve()
	var hips: int = _bones.get(&"Hips", -1)

	if hips >= 0:
		# From the rest origin, not the current pose: no clip writes the hips' position, so adding
		# to it sank the body 0.3 per frame until only the feet were left.
		_skeleton.set_bone_pose_position(hips, _skeleton.get_bone_rest(hips).origin + Vector3(0.0, -0.32 * float(_look["height"]) / 1.75, 0.0))

	_pitch(&"Abdomen", 0.5 + 0.5 * hit)
	_pitch(&"Torso", 0.4 + 0.4 * hit)
	_pitch(&"Head", 0.3)

	for side in [&".L", &".R"]:
		_pitch(StringName("UpperLeg" + side), 0.9)
		_pitch(StringName("LowerLeg" + side), -1.3)
		_pitch(StringName("UpperArm" + side), 1.7 - 0.7 * hit)


## A crawler's swing: a lunge of the chest and both arms onto the landing frame.
func _pose_lunge() -> void:
	var hit := _strike_curve()
	_pitch(&"Torso", 0.35 * hit)

	for side in [&".L", &".R"]:
		_pitch(StringName("UpperArm" + side), 0.9 * hit)


## A special holding a survivor: the rider grips the head with its legs wrapped and rocks, the ram
## slams both fists down, the strangler squeezes, every other (the leaper's pounce) claws.
func _pose_hold() -> void:
	var t := float(Time.get_ticks_msec()) * 0.001 + float(variant)

	if kind == &"rider":
		_pitch(&"Torso", 0.25 + 0.12 * sin(t * 5.0))

		for side in [&".L", &".R"]:
			_pitch(StringName("UpperLeg" + side), 1.2)
			_pitch(StringName("LowerLeg" + side), -1.0)
			_pitch(StringName("UpperArm" + side), 2.5 + 0.25 * sin(t * 9.0))
	elif kind == &"strangler":
		_pitch(&"Torso", 0.2)

		for side in [&".L", &".R"]:
			_pitch(StringName("UpperArm" + side), 1.5 + 0.1 * sin(t * 7.0))
	elif kind == &"ram":
		var slam := maxf(sin(t * 6.0), 0.0)
		_pitch(&"Torso", 0.5 * slam)

		for side in [&".L", &".R"]:
			_pitch(StringName("UpperArm" + side), 2.6 - 2.2 * slam)
	else:
		_pitch(&"Torso", 0.45)

		for i in 2:
			var swipe := maxf(sin(t * 11.0 + float(i) * PI), 0.0)
			_pitch(StringName("UpperArm" + (&".L" if i == 0 else &".R")), 1.9 - 1.3 * swipe)


## The strangler's tongue out: hands over hands hauling the line in.
func _pose_reel() -> void:
	var t := float(Time.get_ticks_msec()) * 0.001 + float(variant)
	_pitch(&"Torso", -0.12)

	for i in 2:
		var pull := 0.5 + 0.5 * sin(t * 6.0 + float(i) * PI)
		_pitch(StringName("UpperArm" + (&".L" if i == 0 else &".R")), 0.8 + 0.8 * pull)


## Airborne: arms thrown forward, knees tucked, chest leaning in.
func _pose_leap() -> void:
	_pitch(&"Torso", 0.3)

	for side in [&".L", &".R"]:
		_pitch(StringName("UpperArm" + side), 2.0)
		_pitch(StringName("UpperLeg" + side), 0.7)
		_pitch(StringName("LowerLeg" + side), -1.0)


## A crawler holding an ankle: the near arm hooked out and pulling, the other clawing.
func _pose_reach() -> void:
	var t := float(Time.get_ticks_msec()) * 0.001 + float(variant)
	_pitch(&"Torso", 0.25)
	_pitch(&"UpperArm.L", 1.6 + 0.4 * sin(t * 4.0))
	_pitch(&"UpperArm.R", 1.0 + 0.5 * sin(t * 4.0 + PI))


## Hit: a flinch over whatever it is doing. [param from_side] is -1 or 1 for which side the hit
## came from; a flinch already running is not restarted, so a shotgun's pellets are one flinch.
func flinch(from_side: float = 1.0, head := false) -> void:
	if _death.is_empty() and _flinch < 0.5:
		_flinch = 1.0
		_hit_left = 0.6
		_hit_head = head
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

	var worn := _mesh.material_override as ShaderMaterial if _mesh != null else null

	if worn != null and kind == &"brute":
		var enraged := (flags & ZzZombieBody.FLAG_ENRAGED) != 0
		worn.set_shader_parameter(&"flash", 0.6 if enraged else 0.0)


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
