extends Node

## Weapon pictures for the trader's menu, drawn from the weapon's own model the first time one is asked for (one still frame each, side-on, on a clear background), so every pack's weapons have a picture with no art to ship. Owned by the menu: the textures live as long as this node.

const SIZE := Vector2i(320, 180)

var _cache: Dictionary = {}


## The picture of weapon [param id], or null where nothing can be drawn (a headless run, a weapon with no model).
func icon_for(id: StringName) -> Texture2D:
	if id == &"" or DisplayServer.get_name() == "headless":
		return null
	if _cache.has(id):
		return _cache[id]

	var picture: Texture2D = _draw(id)
	_cache[id] = picture
	return picture


func _draw(id: StringName) -> Texture2D:
	var art := ZeeWeaponArtTable.get_art(id)
	if art == null or not art.has_model():
		return null
	var model := ZeeModelCache.instantiate(art.model_path)
	if model == null:
		return null

	var basis := art.orientation()
	var box: AABB = ZeeModelCache.bounds(art.model_path)
	var turned := Transform3D(basis, Vector3.ZERO) * box
	model.transform = Transform3D(basis, -turned.get_center())

	var view := SubViewport.new()
	view.size = SIZE
	view.transparent_bg = true
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	view.add_child(model)
	# In the tree before the camera is aimed: look_at refuses a node outside it and leaves the camera facing -Z.
	add_child(view)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	environment.ambient_light_energy = 0.7

	# From +X, a weapon pointing along -Z has its muzzle on the right of the picture.
	var camera := Camera3D.new()
	camera.environment = environment
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(maxf(turned.size.y, turned.size.z * float(SIZE.y) / float(SIZE.x)) * 1.2, 0.05)
	camera.near = 0.01
	camera.far = maxf(turned.size.length() * 4.0, 10.0)
	view.add_child(camera)
	camera.position = Vector3(maxf(turned.size.length() * 2.0, 2.0), 0.0, 0.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	view.add_child(key)
	key.rotation_degrees = Vector3(-35.0, 40.0, 0.0)

	return view.get_texture()
