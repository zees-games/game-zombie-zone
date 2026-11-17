extends "zz_world_view_base.gd"

## The world view's small makers (boxes, shared materials) and the sentries it draws: the first layer under zz_world_view.gd.

## id -> {node, head, gun, muzzle, yaw, pitch, want_yaw, want_pitch, idle, flash}
var _turrets: Dictionary = {}

var _materials: Dictionary = {}

# Turrets

const TURRET_MODEL := "res://assets/turret/turret.glb"

## Barrel turn on a client, radians a second: a little faster than the server's own, so the
## drawn gun is on its target when the shot is told.
const TURRET_TURN := 9.0

func add_turret(id: int, at: Vector3, yaw: float, _seconds: float) -> void:
	remove_turret(id)
	var scene := load(ZzPaths.rebase(TURRET_MODEL)) as PackedScene
	var node: Node3D = scene.instantiate() if scene != null else _box(Vector3(0.5, 1.0, 0.5), Color(0.3, 0.4, 0.45))
	node.name = "Turret_%d" % id
	add_child(node)
	node.global_position = at
	var head := node.find_child("Head", true, false) as Node3D
	var gun := node.find_child("Gun", true, false) as Node3D
	var muzzle := node.find_child("Muzzle", true, false) as Node3D
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.45)
	flash.omni_range = 5.0
	flash.light_energy = 0.0
	(muzzle if muzzle != null else node).add_child(flash)

	if head != null:
		head.rotation.y = yaw

	_turrets[id] = {"node": node, "head": head, "gun": gun, "muzzle": muzzle, "yaw": yaw, "pitch": 0.0,
		"want_yaw": yaw, "want_pitch": 0.0, "idle": 0.0, "flash": flash, "flash_left": 0.0, "age": 0.0}

## The server told it fired at [param target]: turn the barrel there, flash, and draw the line.
func fire_turret(id: int, target: Vector3) -> void:
	var t: Dictionary = _turrets.get(id, {})

	if t.is_empty():
		return

	var head := t["head"] as Node3D
	var from: Vector3 = (t["muzzle"] as Node3D).global_position if t["muzzle"] != null else (t["node"] as Node3D).global_position
	var pivot: Vector3 = head.global_position if head != null else from
	var to := target - pivot
	t["want_yaw"] = atan2(-to.x, -to.z)
	t["want_pitch"] = atan2(to.y - 0.3, Vector2(to.x, to.z).length())
	t["idle"] = 0.0
	t["flash_left"] = 0.06
	(t["flash"] as OmniLight3D).light_energy = 3.0
	_tracer(from, target)

func remove_turret(id: int) -> void:
	var t: Dictionary = _turrets.get(id, {})
	_turrets.erase(id)

	if not t.is_empty() and is_instance_valid(t["node"]):
		(t["node"] as Node).queue_free()

func _tracer(from: Vector3, to: Vector3) -> void:
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var length := from.distance_to(to)
	mesh.size = Vector3(0.025, 0.025, length)
	line.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.55, 0.95, 1.0)
	line.material_override = material
	add_child(line)
	line.global_position = (from + to) * 0.5
	line.look_at(to)
	var tween := line.create_tween()
	tween.tween_callback(line.queue_free).set_delay(0.05)

func _present_turrets(delta: float) -> void:
	for id: int in _turrets:
		var t: Dictionary = _turrets[id]
		t["idle"] = float(t["idle"]) + delta
		t["age"] = float(t["age"]) + delta

		# Not fired for a moment: scan side to side, so a standing turret looks switched on.
		if float(t["idle"]) > 1.0:
			t["want_yaw"] = float(t["want_yaw"]) + delta * 0.6
			t["want_pitch"] = 0.0

		var step := TURRET_TURN * delta
		t["yaw"] = float(t["yaw"]) + clampf(angle_difference(float(t["yaw"]), float(t["want_yaw"])), -step, step)
		t["pitch"] = float(t["pitch"]) + clampf(float(t["want_pitch"]) - float(t["pitch"]), -step, step)

		if t["head"] != null:
			(t["head"] as Node3D).rotation.y = float(t["yaw"])
		if t["gun"] != null:
			(t["gun"] as Node3D).rotation.x = float(t["pitch"])

		if float(t["flash_left"]) > 0.0:
			t["flash_left"] = float(t["flash_left"]) - delta

			if float(t["flash_left"]) <= 0.0:
				(t["flash"] as OmniLight3D).light_energy = 0.0


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
