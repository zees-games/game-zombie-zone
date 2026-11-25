extends "zz_zombie_view_base.gd"

## A zombie drawn at an alpha (the spawn and despawn fade, its stumps and gibs too): the layer under zz_zombie_view_legs.gd.

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
			_fade_shader.code = ZzZombieShader.SHADER \
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

	for n: Node in get_tree().get_nodes_in_group(GSNpcGibs.GROUP):
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
