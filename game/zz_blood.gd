extends Node
## Blood on the surface behind a body the local shooter hit. Visual only: the HIT event carries
## a point and no normal, so no other client is told and the wire is unchanged.

var decals := DotFxDecals.new()
## Layers the splatter may land on; the game's world, props and barricades.
var mask := 0xFFFFFFFF


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


func advance(delta: float) -> void:
	decals.advance(delta)


func clear() -> void:
	decals.clear_blood()
