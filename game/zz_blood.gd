extends Node
## Blood on the surface behind a body somebody hit. The shooter casts it from their own HIT; everybody
## else gets the server's SPLAT (point and normal), so a client without that event just sees fewer decals.

var decals := DotFxDecals.new()
## Layers the splatter may land on; the game's world, props and barricades.
var mask := 0xFFFFFFFF
## Server splats drawn per second at most.
const SPLATS_PER_SECOND := 20

var _window_start := 0
var _window_count := 0


func _init() -> void:
	name = "Blood"
	decals.name = "Decals"
	add_child(decals)


## Takes the player's `gore` and `fx_quality`; env and command line layer under them in the config's own loader.
func apply_settings(store: DotSettingsManager) -> void:
	var cfg := DotFxDecalConfig.new()
	if store != null:
		cfg.gore = store.get_bool(&"gore", true)
		cfg.quality = store.get_int(&"fx_quality", 3)
	decals.apply_config(cfg)


func follow(store: DotSettingsManager) -> void:
	apply_settings(store)
	if store != null and not store.changed.is_connected(_on_changed):
		store.changed.connect(_on_changed.bind(store))


func _on_changed(key: StringName, _value: Variant, _why: StringName, store: DotSettingsManager) -> void:
	if key == &"gore" or key == &"fx_quality":
		apply_settings(store)


## A player or NPC took a hit at [param point], seen from [param from]: blood on the first surface
## behind it within [param reach] metres. Returns the splatter, or null (no victim of that kind, no surface, gore off).
func on_body_hit(victim: int, point: Vector3, from: Vector3, reach: float = 4.0) -> Node3D:
	var kind := DotEntity.kind_of(victim)
	if kind != DotEntity.KIND_PLAYER and kind != DotEntity.KIND_NPC:
		return null
	var world := get_viewport().find_world_3d() if get_viewport() != null else null
	var along := point - from
	if world == null or along.length() < 0.01:
		return null
	var query := PhysicsRayQueryParameters3D.create(point, point + along.normalized() * reach, mask)
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return decals.splatter(hit["position"], hit["normal"])


## The server's word that blood landed at [param point] on a surface facing [param normal]; only near the
## camera (no camera, no decal) and at most [constant SPLATS_PER_SECOND] a second, so a flood of events cannot flood the decals.
func on_splat(point: Vector3, normal: Vector3, within: float = 60.0) -> Node3D:
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null or camera.global_position.distance_to(point) > within:
		return null
	var now := Time.get_ticks_msec()
	if now - _window_start >= 1000:
		_window_start = now
		_window_count = 0
	if _window_count >= SPLATS_PER_SECOND:
		return null
	_window_count += 1
	return decals.splatter(point, normal)


func advance(delta: float) -> void:
	decals.advance(delta)


func clear() -> void:
	decals.clear_blood()
