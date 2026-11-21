extends RefCounted

## Zombie Zone's own copy (2026-11-16) of the grenade code first written for fc-weapons: the game depends on no FC addon.

const ZzUtilityZones := preload("zz_utility_zones.gd")

## Client visuals of the utility grenades through gs-fx: smoke and fire clouds, and the blind flash the player's flash settings cap.
## The cloud scenes ship in `fx/` beside this script; [method add_defs] takes another folder only to override them.

const SMOKE_ID := &"smoke_cloud"
const FIRE_ID := &"fire_cloud"
const BLIND_ID := &"blind_flash"
const BLIND_MIN_MS := 250
const BLIND_MAX_MS := 10000
## The cloud scenes beside this script, preloaded so their paths follow the game wherever its pack is mounted.
const SCENES := {&"smoke_cloud": preload("fx/smoke_cloud.tscn"), &"fire_cloud": preload("fx/fire_cloud.tscn")}


## The three defs; [param fx_dir] holds `smoke_cloud.tscn` and `fire_cloud.tscn` (empty: the game's own in `fx/`).
static func defs(fx_dir: String = "") -> Array[GSFxDef]:
	var out: Array[GSFxDef] = []
	for id: StringName in [SMOKE_ID, FIRE_ID]:
		var cloud := GSFxDef.new()
		cloud.id = id
		cloud.scene_path = (SCENES[id] as PackedScene).resource_path if fx_dir.is_empty() else "%s/%s.tscn" % [fx_dir, id]
		cloud.lifetime_ms = 30000
		cloud.cost = 10
		cloud.priority = 80
		cloud.max_distance = 120.0
		out.append(cloud)

	var blind := GSFxDef.new()
	blind.id = BLIND_ID
	blind.kind = GSFxDef.Kind.SCREEN
	blind.flash_peak = 1.0
	blind.flash_decay_ms = 2500
	out.append(blind)
	return out


## The game's own `fx/` folder, wherever the pack is mounted.
static func own_dir() -> String:
	return (SCENES[SMOKE_ID] as PackedScene).resource_path.get_base_dir()


static func add_defs(catalogue: GSFxCatalogue, fx_dir: String = "") -> void:
	for def in defs(fx_dir):
		catalogue.add(def)


## How long the white takes to fade for a blind of [param seconds].
static func flash_decay_ms(seconds: float) -> int:
	return clampi(int(seconds * 1000.0), BLIND_MIN_MS, BLIND_MAX_MS)


## Shows an [signal ZzUtilityZones.effect] on [param fx]; a blind only for [param own_id]. Returns the cloud, or null.
static func show(fx: GSFxManager, tree: SceneTree, info: Dictionary, own_id: int) -> Node:
	if fx == null or fx.catalogue == null:
		return null

	var seconds := float(info["seconds"])
	var strength := clampf(float(info.get("strength", 1.0)), 0.0, 1.0)
	match int(info["fx"]):
		ZzUtilityZones.Fx.BLIND:
			var def := fx.catalogue.find(BLIND_ID)
			if int(info["victim"]) == own_id and def != null:
				# The decay is set per flash: it is how long this blind lasts.
				def.flash_decay_ms = flash_decay_ms(seconds)
				def.flash_peak = maxf(strength, 0.05)
				var _shown := fx.flash(BLIND_ID)
		ZzUtilityZones.Fx.SMOKE, ZzUtilityZones.Fx.FIRE:
			var id := SMOKE_ID if int(info["fx"]) == ZzUtilityZones.Fx.SMOKE else FIRE_ID
			var scale := Vector3.ONE * float(info["radius"]) * 0.5
			var cloud := fx.spawn(id, Transform3D(Basis.IDENTITY.scaled(scale), info["position"]))
			if cloud != null and tree != null:
				tree.create_timer(seconds).timeout.connect(func() -> void:
					if is_instance_valid(cloud):
						cloud.queue_free())
			return cloud
	return null
