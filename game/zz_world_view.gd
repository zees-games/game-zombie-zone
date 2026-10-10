extends Node3D

const ZzAudio := preload("zz_audio.gd")
const ZzBoxes := preload("zz_boxes.gd")
const ZzPaths := preload("zz_paths.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view.gd")

## Everything a client draws in the world that is not a survivor or a wall: the zombies and their
## bodies, what lies on the ground, pools of acid and fire, things thrown, explosions, and a
## strangler's tongue.
##
## [b]Told, never asking.[/b] Offline the world's own signals call these methods; connected, the
## bridge's do, with the same arguments, so the two can only differ in where a fact came from —
## the shape `ZzClient._hear_the_world` already has for the rest.
##
## [b]Sound is placed here, because this is what knows where things are.[/b] A common moans now
## and then while it idles, screams on the frame it turns to RAGE, and the special's own voice
## plays when it appears and when it uses what it has. The sleeper's crying is a loop that
## follows her, so it is louder the closer you are, which is the only warning she gives.

const CHANNEL := "zz.world_view"

## Seconds a killed zombie's body stays before it sinks away.
const CORPSE_SECONDS := 6.0

## Seconds a blast's flash lasts.
const BLAST_SECONDS := 0.6

## Gravity a thrown thing falls by on a client: the server's (`ZzHazards.GRAVITY`).
const GRAVITY := 18.0

var audio: ZzAudio = null

## key -> {body, view, last_anim, next_moan, voice_handle}
var _zombies: Dictionary = {}

## [view, body, seconds left]
var _corpses: Array = []

## id -> node
var _loot: Dictionary = {}
var _hazards: Dictionary = {}

## id -> {node, velocity}
var _flying: Dictionary = {}

## [node, seconds left, light]
var _blasts: Array = []

## victim player node -> {holder: Node3D, line: MeshInstance3D}
var _tongues: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _materials: Dictionary = {}


func _ready() -> void:
	_rng.seed = Time.get_ticks_usec()


# --- Zombies -----------------------------------------------------------------

func add_zombie(key: int, kind: StringName, variant: int, body: Node3D) -> void:
	if body == null or _zombies.has(key):
		return

	var view := ZzZombieView.new()
	view.name = "View"
	body.add_child(view)
	view.build(kind, variant)

	var entry := {"body": body, "view": view, "kind": kind, "last_anim": -1,
		"next_moan": _rng.randf_range(1.0, 9.0), "voice": 0}
	_zombies[key] = entry

	if kind != &"common" and audio != null:
		var handle := audio.special_voice(kind, body.global_position)

		# The sleeper's crying follows her for as long as she is there.
		if kind == &"sleeper":
			entry["voice"] = handle


## A zombie gone: a body to drop for a moment if it was killed.
func remove_zombie(key: int, killed: bool, body: Node3D = null) -> void:
	var entry: Variant = _zombies.get(key)
	_zombies.erase(key)

	if entry == null:
		if body != null and is_instance_valid(body):
			body.queue_free()
		return

	if audio != null and int((entry as Dictionary)["voice"]) != 0:
		audio.stop(int((entry as Dictionary)["voice"]))

	var view: ZzZombieView = (entry as Dictionary)["view"]
	var old_body: Node3D = body if body != null else (entry as Dictionary)["body"]

	if not killed or view == null or not is_instance_valid(view):
		if body != null and is_instance_valid(body):
			body.queue_free()
		return

	if audio != null and old_body != null and is_instance_valid(old_body):
		var _died := audio.at(ZzAudio.ZOMBIE_DIE, old_body.global_position)

	# The view outlives the body: offline the server's body is freed this frame, so the view is
	# moved out to here and left playing its death.
	var keep := view.global_transform
	view.get_parent().remove_child(view)
	add_child(view)
	view.global_transform = keep
	_corpses.append([view, CORPSE_SECONDS])

	if body != null and is_instance_valid(body):
		body.queue_free()


func zombie_count() -> int:
	return _zombies.size()


# --- Loot ----------------------------------------------------------------------

func add_loot(id: int, kind: StringName, item: StringName, at: Vector3, box_colour: Color = Color(0.8, 0.6, 0.25)) -> void:
	remove_loot(id)
	var node := Node3D.new()
	node.name = "Loot_%d" % id
	add_child(node)
	node.global_position = at

	match kind:
		&"weapon", &"throwable":
			var art: Variant = ZeeWeaponArtTable.table().get(item)
			var model: Node3D = ZeeModelCache.instantiate((art as ZeeWeaponArt).model_path) \
				if art is ZeeWeaponArt and (art as ZeeWeaponArt).model_path != "" else null

			if model != null:
				node.add_child(model)
				model.basis = Basis(Vector3.FORWARD, PI * 0.5) * (art as ZeeWeaponArt).orientation()
				model.scale = Vector3.ONE * (art as ZeeWeaponArt).world_scale
				model.position.y = 0.08
			else:
				node.add_child(_box(Vector3(0.6, 0.12, 0.2), Color(0.3, 0.3, 0.32)))
		&"ammo":
			for i in 3:
				var crate := _box(Vector3(0.35, 0.22, 0.25), Color(0.32, 0.38, 0.22))
				crate.position = Vector3(float(i % 2) * 0.38 - 0.19, 0.11 + float(i / 2) * 0.22, 0.0)
				node.add_child(crate)
		&"medkit":
			node.add_child(_box(Vector3(0.42, 0.14, 0.3), Color(0.92, 0.92, 0.9)))
			var cross_a := _box(Vector3(0.22, 0.02, 0.06), Color(0.85, 0.08, 0.08))
			cross_a.position.y = 0.15
			node.add_child(cross_a)
			var cross_b := _box(Vector3(0.06, 0.02, 0.22), Color(0.85, 0.08, 0.08))
			cross_b.position.y = 0.15
			node.add_child(cross_b)
		&"pills":
			var bottle := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.045
			cylinder.bottom_radius = 0.045
			cylinder.height = 0.16
			bottle.mesh = cylinder
			bottle.position.y = 0.08
			bottle.material_override = _material(Color(0.95, 0.6, 0.15))
			node.add_child(bottle)
		&"box":
			var crate := _box(Vector3(0.55, 0.45, 0.55), box_colour)
			crate.name = "Crate"
			crate.position.y = 0.4
			node.add_child(crate)
			var glow := OmniLight3D.new()
			glow.light_color = box_colour
			glow.omni_range = 3.0
			glow.light_energy = 0.8
			glow.position.y = 0.6
			node.add_child(glow)
			node.set_meta(&"bob", true)

	node.set_meta(&"label", _label(kind, item))
	_loot[id] = node


static func _label(kind: StringName, item: StringName) -> String:
	match kind:
		&"weapon", &"throwable":
			return "pick up %s" % ZzWeapons.title_of(item)
		&"ammo":
			return "take ammo"
		&"medkit":
			return "take the medkit"
		&"pills":
			return "take the pills"
		&"box":
			return "open the %s box" % String(item).replace("_", " ")
	return "pick up"


func remove_loot(id: int) -> void:
	var node: Node3D = _loot.get(id)
	_loot.erase(id)

	if node != null and is_instance_valid(node):
		node.queue_free()


# --- Hazards ---------------------------------------------------------------------

func add_hazard(id: int, kind: StringName, at: Vector3, radius: float, seconds: float) -> void:
	remove_hazard(id)
	var node := Node3D.new()
	node.name = "Hazard_%d" % id
	add_child(node)
	node.global_position = at + Vector3(0.0, 0.03, 0.0)
	node.set_meta(&"radius", radius)
	node.set_meta(&"age", 0.0)
	node.set_meta(&"life", seconds)

	var colour := Color(0.45, 0.85, 0.12, 0.55)

	match kind:
		&"fire":
			colour = Color(1.0, 0.45, 0.08, 0.35)
			var fire := _particles(Color(1.0, 0.55, 0.12), radius, 40)
			node.add_child(fire)
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.5, 0.15)
			light.omni_range = radius * 2.5
			light.light_energy = 1.6
			light.position.y = 1.0
			node.add_child(light)
		&"heal":
			colour = Color(0.3, 1.0, 0.45, 0.3)
		&"acid":
			if audio != null:
				var _splat := audio.at(ZzAudio.SPLAT, at)

	var disc := MeshInstance3D.new()
	disc.name = "Pool"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 0.02
	disc.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(colour.r, colour.g, colour.b) * 0.6
	disc.material_override = material
	disc.scale = Vector3(0.2, 1.0, 0.2) * radius
	node.add_child(disc)
	_hazards[id] = node


func remove_hazard(id: int) -> void:
	var node: Node3D = _hazards.get(id)
	_hazards.erase(id)

	if node != null and is_instance_valid(node):
		node.queue_free()


# --- Thrown things -------------------------------------------------------------------

func throw(id: int, kind: StringName, from: Vector3, velocity: Vector3) -> void:
	var node := MeshInstance3D.new()
	node.name = "Thrown_%d" % id
	var sphere := SphereMesh.new()
	var colour := Color(0.5, 0.85, 0.15)
	var size := 0.25

	match kind:
		&"rock":
			colour = Color(0.45, 0.42, 0.4)
			size = 0.9
		&"pipe":
			colour = Color(0.2, 0.2, 0.22)
			size = 0.18
		&"shell":
			colour = Color(0.15, 0.15, 0.15)
			size = 0.3
		&"molotov":
			colour = Color(0.9, 0.5, 0.1)
			size = 0.15
		&"grenade":
			colour = Color(0.22, 0.3, 0.16)
			size = 0.16
		&"rocket":
			colour = Color(0.75, 0.75, 0.7)
			size = 0.2
		&"bile":
			colour = Color(0.45, 0.65, 0.1)
			size = 0.16

	sphere.radius = size * 0.5
	sphere.height = size
	node.mesh = sphere
	node.material_override = _material(colour)
	add_child(node)
	node.global_position = from
	_flying[id] = {"node": node, "velocity": velocity, "kind": kind, "beep": 0.0}

	if audio != null and kind != &"shell":
		var _woosh := audio.at(ZzAudio.WOOSH, from)


func land(id: int, kind: StringName, at: Vector3) -> void:
	var entry: Variant = _flying.get(id)

	if entry == null:
		return

	# A pipe (or a grenade on its fuse) lies where it landed, and a pipe beeps; everything else
	# is gone.
	if kind == &"pipe" or kind == &"grenade":
		var node: Node3D = (entry as Dictionary)["node"]
		node.global_position = at
		(entry as Dictionary)["velocity"] = Vector3.ZERO
		(entry as Dictionary)["landed"] = true
		return

	_flying.erase(id)
	var node: Node3D = (entry as Dictionary)["node"]

	if node != null and is_instance_valid(node):
		node.queue_free()

	if kind == &"rock" and audio != null:
		var _crack := audio.at(ZzAudio.ROCK, at)


## An explosion's flash, its fire and its noise.
func blast(at: Vector3, radius: float, kind: StringName) -> void:
	# A pipe that went off is no longer beeping.
	for id: int in _flying.keys():
		var entry: Dictionary = _flying[id]
		if (entry["kind"] == &"pipe" or entry["kind"] == &"grenade") and (entry["node"] as Node3D).global_position.distance_to(at) < 1.5:
			(entry["node"] as Node3D).queue_free()
			_flying.erase(id)

	var node := Node3D.new()
	node.name = "Blast"
	add_child(node)
	node.global_position = at

	var bile := kind == &"bile"
	var colour := Color(0.55, 0.75, 0.1) if bile else Color(1.0, 0.6, 0.2)
	var puff := _particles(colour, radius * 0.5, 60)
	puff.one_shot = true
	puff.explosiveness = 0.95
	puff.initial_velocity_min = radius * 1.2
	puff.initial_velocity_max = radius * 2.4
	puff.direction = Vector3.UP
	puff.spread = 80.0
	node.add_child(puff)

	var light := OmniLight3D.new()
	light.light_color = colour
	light.omni_range = radius * 3.0
	light.light_energy = 0.0 if bile else 6.0
	light.position.y = 1.0
	node.add_child(light)
	_blasts.append([node, BLAST_SECONDS * (2.0 if not bile else 1.5), light])

	if audio != null:
		var _boom := audio.at(ZzAudio.SPLAT if bile else ZzAudio.EXPLOSION, at)


# --- Tongues ------------------------------------------------------------------

## [param victim] is held by [param holder]: a choke draws a tongue between them.
func pin(victim: Node3D, holder: Node3D, kind: StringName) -> void:
	unpin(victim)

	if victim == null or holder == null:
		return

	if audio != null:
		var _call := audio.at(ZzAudio.CALL_HELP, victim.global_position)

	if kind != &"choke":
		return

	var line := MeshInstance3D.new()
	line.name = "Tongue"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.035
	cylinder.bottom_radius = 0.035
	cylinder.height = 1.0
	line.mesh = cylinder
	line.material_override = _material(Color(0.55, 0.12, 0.15))
	add_child(line)
	_tongues[victim] = {"holder": holder, "line": line}


func unpin(victim: Node3D) -> void:
	var entry: Variant = _tongues.get(victim)
	_tongues.erase(victim)

	if entry != null and is_instance_valid((entry as Dictionary)["line"]):
		((entry as Dictionary)["line"] as Node).queue_free()


# --- The frame ---------------------------------------------------------------------

func present(delta: float, listener: Vector3) -> void:
	_present_zombies(delta, listener)
	_present_corpses(delta)
	_present_loot(delta)
	_present_hazards(delta)
	_present_flying(delta)
	_present_blasts(delta)
	_present_tongues()


func _present_zombies(delta: float, listener: Vector3) -> void:
	for key: int in _zombies.keys():
		var entry: Dictionary = _zombies[key]
		var body: Node3D = entry["body"]
		var view: ZzZombieView = entry["view"]

		if body == null or not is_instance_valid(body) or view == null or not is_instance_valid(view):
			_zombies.erase(key)
			continue

		var anim := int(body.get(&"anim"))
		var flags := int(body.get(&"flags"))
		view.present(delta, anim, flags)

		if audio == null:
			continue

		var at := body.global_position
		var last := int(entry["last_anim"])
		entry["last_anim"] = anim

		if int(entry["voice"]) != 0:
			audio.move(int(entry["voice"]), at)

		# Further than this nobody is listening; the audio layer would cull it anyway, and
		# not asking saves forty calls a frame.
		if at.distance_to(listener) > 45.0:
			continue

		if anim != last:
			match anim:
				ZzZombieBody.Anim.RAGE:
					var kind: StringName = entry["kind"]
					var _s := audio.at(ZzAudio.SCREAM, at) if kind == &"common" else audio.special_voice(kind, at)
				ZzZombieBody.Anim.ATTACK, ZzZombieBody.Anim.PIN:
					var _c := audio.at(ZzAudio.CLAW, at)
				ZzZombieBody.Anim.LEAP, ZzZombieBody.Anim.CHARGE, ZzZombieBody.Anim.VOMIT, \
						ZzZombieBody.Anim.SPIT, ZzZombieBody.Anim.TONGUE, ZzZombieBody.Anim.THROW:
					var _v := audio.special_voice(entry["kind"], at)

		entry["next_moan"] = float(entry["next_moan"]) - delta

		if float(entry["next_moan"]) <= 0.0:
			entry["next_moan"] = _rng.randf_range(4.0, 14.0)

			if entry["kind"] == &"common":
				var _m := audio.at(ZzAudio.MOAN, at, 0.8)


func _present_corpses(delta: float) -> void:
	var kept: Array = []

	for corpse: Array in _corpses:
		var view: ZzZombieView = corpse[0]
		corpse[1] = float(corpse[1]) - delta

		if view == null or not is_instance_valid(view):
			continue

		view.present(delta, ZzZombieBody.Anim.DEAD, 0)

		if float(corpse[1]) < 1.0:
			view.position.y -= delta * 0.6

		if float(corpse[1]) <= 0.0:
			view.queue_free()
			continue

		kept.append(corpse)

	_corpses = kept


func _present_loot(delta: float) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001

	for id: int in _loot:
		var node: Node3D = _loot[id]
		if node.has_meta(&"bob"):
			var crate := node.get_node_or_null(^"Crate") as Node3D
			if crate != null:
				crate.position.y = 0.4 + sin(t * 2.0 + float(id)) * 0.08
				crate.rotation.y += delta * 0.8


func _present_hazards(delta: float) -> void:
	for id: int in _hazards:
		var node: Node3D = _hazards[id]
		var age := float(node.get_meta(&"age")) + delta
		node.set_meta(&"age", age)
		var pool := node.get_node_or_null(^"Pool") as Node3D

		if pool != null:
			var radius := float(node.get_meta(&"radius")) * clampf(age, 0.2, 1.0)
			pool.scale = Vector3(radius, 1.0, radius)


func _present_flying(delta: float) -> void:
	for id: int in _flying.keys():
		var entry: Dictionary = _flying[id]
		var node: Node3D = entry["node"]

		if node == null or not is_instance_valid(node):
			_flying.erase(id)
			continue

		if bool(entry.get("landed", false)):
			# A pipe on the ground: a blink and a beep, faster as it goes.
			if entry["kind"] == &"pipe":
				entry["beep"] = float(entry["beep"]) + delta
				node.visible = fmod(float(entry["beep"]) * 3.0, 1.0) < 0.6
			continue

		var velocity: Vector3 = entry["velocity"]
		# A rocket flies straight; everything else falls as the server's does.
		if entry["kind"] != &"rocket":
			velocity.y -= GRAVITY * delta
		entry["velocity"] = velocity
		node.global_position += velocity * delta


func _present_blasts(delta: float) -> void:
	var kept: Array = []

	for b: Array in _blasts:
		b[1] = float(b[1]) - delta
		var light: OmniLight3D = b[2]

		if is_instance_valid(light):
			light.light_energy = maxf(light.light_energy - delta * 12.0, 0.0)

		if float(b[1]) <= 0.0:
			if is_instance_valid(b[0]):
				(b[0] as Node).queue_free()
			continue

		kept.append(b)

	_blasts = kept


func _present_tongues() -> void:
	for victim: Node3D in _tongues.keys():
		var entry: Dictionary = _tongues[victim]
		var holder: Node3D = entry["holder"]
		var line: MeshInstance3D = entry["line"]

		if not is_instance_valid(victim) or not is_instance_valid(holder) or not is_instance_valid(line):
			unpin(victim)
			continue

		var from := holder.global_position + Vector3(0.0, 1.7, 0.0)
		var to := victim.global_position + Vector3(0.0, 1.2, 0.0)
		var length := from.distance_to(to)

		if length < 0.05:
			continue

		line.global_position = (from + to) * 0.5
		var up := (to - from) / length
		var side := up.cross(Vector3.FORWARD) if absf(up.dot(Vector3.FORWARD)) < 0.95 else up.cross(Vector3.RIGHT)
		line.global_basis = Basis(side.normalized(), up, side.normalized().cross(up)).scaled(Vector3(1.0, length, 1.0))


# --- Making things ----------------------------------------------------------------

func _box(size: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position.y = size.y * 0.5
	mesh.material_override = _material(colour)
	return mesh


func _material(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html()

	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = 0.6
		_materials[key] = m

	return _materials[key]


func _particles(colour: Color, radius: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(radius * 0.6, 0.2)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0.0, 1.5, 0.0)
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.5
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(colour.r, colour.g, colour.b, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = material
	p.mesh = quad
	var gradient := Gradient.new()
	gradient.set_color(0, Color(colour.r, colour.g, colour.b, 1.0))
	gradient.set_color(1, Color(colour.r * 0.5, colour.g * 0.3, colour.b * 0.2, 0.0))
	p.color_ramp = gradient
	return p


func clear() -> void:
	for id: int in _loot.keys():
		remove_loot(id)
	for id: int in _hazards.keys():
		remove_hazard(id)
	for id: int in _flying.keys():
		var node: Node = (_flying[id] as Dictionary)["node"]
		if is_instance_valid(node):
			node.queue_free()
	_flying.clear()
	for victim: Node3D in _tongues.keys():
		unpin(victim)


func describe() -> Dictionary:
	return {
		"zombies": _zombies.size(), "corpses": _corpses.size(), "loot": _loot.size(),
		"hazards": _hazards.size(), "flying": _flying.size(), "tongues": _tongues.size(),
	}
