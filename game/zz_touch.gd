extends RefCounted

## The phone's controls: dot-mobile's stick, drag-look and buttons over the HUD, driving the client's own
## [DotFpsTouchSampler]. Fire is read through [method is_held], so a thumb and auto-fire take the Fire key's path.
## The server's `sv_mobile_*`, `sv_aim_assist*` and `sv_autofire*` cvars ([member ZzGameState.mobile_rules]) govern it.

const SelfScript := preload("zz_touch.gd")

## Offsets are from the bottom-right corner (see [DotTouchButtons]). Every radius is at least 24 so a
## button is 48 px across, thumb size, and the cluster still sits above the ammunition plate.
const LAYOUT: Array[Dictionary] = [
	{"id": &"fire", "label": "FIRE", "offset": Vector2(86, 150), "radius": 52.0},
	{"id": &"jump", "label": "JUMP", "offset": Vector2(200, 130), "radius": 42.0, "hold": DotFpsCommand.BUTTON_JUMP},
	{"id": &"crouch", "label": "DUCK", "offset": Vector2(60, 272), "radius": 36.0, "hold": DotFpsCommand.BUTTON_CROUCH},
	{"id": &"reload", "label": "R", "offset": Vector2(170, 244), "radius": 36.0},
	{"id": &"next", "label": "NEXT", "offset": Vector2(268, 200), "radius": 36.0},
	{"id": &"use", "label": "USE", "offset": Vector2(290, 90), "radius": 36.0},
	{"id": &"heal", "label": "HEAL", "offset": Vector2(280, 300), "radius": 30.0},
]

## A portrait phone: the same buttons in a tighter arc above the weight readout and the ammunition plate, so none
## sits on the health panel or the readout.
const LAYOUT_PORTRAIT: Array[Dictionary] = [
	{"id": &"fire", "label": "FIRE", "offset": Vector2(70, 340), "radius": 44.0},
	{"id": &"jump", "label": "JUMP", "offset": Vector2(175, 310), "radius": 36.0, "hold": DotFpsCommand.BUTTON_JUMP},
	{"id": &"crouch", "label": "DUCK", "offset": Vector2(50, 450), "radius": 30.0, "hold": DotFpsCommand.BUTTON_CROUCH},
	{"id": &"reload", "label": "R", "offset": Vector2(135, 435), "radius": 30.0},
	{"id": &"next", "label": "NEXT", "offset": Vector2(225, 385), "radius": 30.0},
	{"id": &"use", "label": "USE", "offset": Vector2(225, 490), "radius": 30.0},
	{"id": &"heal", "label": "HEAL", "offset": Vector2(60, 550), "radius": 26.0},
]

## How far left of the right edge the HUD's weight readout moves, in HUD units, to clear the cluster.
const WEIGHT_SHIFT := 410.0

## How far the health plate lifts, in HUD units, to clear the thumbstick (none in portrait, where the stick sits lower).
const PLATE_LIFT := 100.0

## The button layout for a screen of [param size]: portrait gets the compact arc.
static func layout_for(size: Vector2) -> Array[Dictionary]:
	return LAYOUT_PORTRAIT if size.y > size.x else LAYOUT


## How far the weight readout moves left on a screen of [param size]; none in portrait, where the cluster sits above it.
static func weight_shift_for(size: Vector2) -> float:
	return 0.0 if size.y > size.x else WEIGHT_SHIFT


## How far the health plate lifts on a screen of [param size].
static func plate_lift_for(size: Vector2) -> float:
	return 0.0 if size.y > size.x else PLATE_LIFT


## The health plate's lift for the host's current screen.
func plate_lift() -> float:
	return plate_lift_for(_host.get_viewport_rect().size) if _host != null and _host.is_inside_tree() else PLATE_LIFT


## Aim assist's candidates: within this many degrees of the crosshair and metres, each checked for a wall.
const ASSIST_CONE_DEG := 10.0
const ASSIST_RANGE := 80.0
## The crosshair test looks no further than this, and takes a survivor to stand this tall and this wide.
const SIGHT_RANGE := 120.0
const PLAYER_HEIGHT := 1.8
const PLAYER_RADIUS := 0.4

var controls: DotMobileControls = null
## dot-ui's buttons inside the overlay, for the shell's DPI fit.
var buttons: DotTouchButtons:
	get:
		return controls.buttons if controls != null else null

var _client: Node = null
var _host: Control = null


## The layout for the host's current screen.
func layout() -> Array[Dictionary]:
	return layout_for(_host.get_viewport_rect().size) if _host != null and _host.is_inside_tree() else LAYOUT


## The weight readout's shift for the host's current screen.
func weight_shift() -> float:
	return weight_shift_for(_host.get_viewport_rect().size) if _host != null and _host.is_inside_tree() else WEIGHT_SHIFT


## Builds the overlay under [param host] (the HUD), following [param rules] (the server's). Never null.
static func build(client: Node, host: Control, sampler: DotFpsSampler, rules: DotMobileRules, menu_button: Control = null) -> RefCounted:
	var made: RefCounted = (SelfScript as GDScript).new()
	made.call(&"_setup", client, host, sampler, rules, menu_button)
	return made


func _setup(client: Node, host: Control, sampler: DotFpsSampler, rules: DotMobileRules, menu_button: Control) -> void:
	_client = client
	_host = host
	controls = DotMobileControls.new()
	controls.name = "TouchControls"
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rules != null:
		controls.rules = rules
	if menu_button != null:
		controls.ignore_fn = func(at: Vector2) -> bool:
			return menu_button.visible and menu_button.get_global_rect().has_point(at)
	controls.setup(sampler, layout())
	controls.crosshair_fn = _crosshair
	controls.targets_fn = _assist_targets
	controls.eye_fn = _eye
	host.add_child(controls)


## Hands the overlay the sampler now in use (offline, the player's own; online, the client's), sized to [param width].
func attach(sampler: DotFpsSampler, _width: float = 0.0) -> void:
	if controls != null and sampler != null:
		controls.setup(sampler, layout())


## A declared button held by a thumb, or Fire held by auto-fire.
func is_held(id: StringName) -> bool:
	return controls != null and controls.is_held(id)


## True when the overlay is up and forwards [param event] itself, or [param event] is the mouse Godot emulates
## from a touch, which would turn the view a second time.
func takes(event: InputEvent) -> bool:
	if controls == null or not controls.touch:
		return false
	return controls.takes(event) or (event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION)


func active() -> bool:
	return controls != null and controls.touch


## Called every frame by the client: pauses under a menu, the shop or a spectate, and matches auto-fire to the gun in hand.
func sync(busy: bool, gun: DotWeaponDef) -> void:
	if controls == null:
		return
	controls.paused = busy
	controls.autofire.automatic = gun == null or gun.is_continuous()


func describe() -> Dictionary:
	return controls.describe() if controls != null else {"built": false}


func _camera() -> Camera3D:
	return _client.get_viewport().get_camera_3d() if is_instance_valid(_client) and _client.is_inside_tree() else null


func _me() -> Node:
	return _client.get(&"player") if is_instance_valid(_client) else null


func _game() -> Object:
	return _client.get(&"game") if is_instance_valid(_client) else null


func _eye() -> Vector3:
	var cam := _camera()
	return cam.global_position if cam != null else Vector3.ZERO


func _crosshair() -> int:
	var cam := _camera()
	var game := _game()
	if cam == null or game == null:
		return DotMobileAutoFire.TARGET_NONE
	return crosshair_kind(cam.global_position, -cam.global_basis.z, _me(), _others(game), _zombies(), _space(cam),
		int(game.call(&"world_mask")))


func _assist_targets() -> PackedVector3Array:
	var cam := _camera()
	var game := _game()
	if cam == null or game == null:
		return PackedVector3Array()
	return assist_targets(cam.global_position, -cam.global_basis.z, _zombies(), _space(cam), int(game.call(&"world_mask")))


func _space(cam: Camera3D) -> PhysicsDirectSpaceState3D:
	return cam.get_world_3d().direct_space_state


func _others(game: Object) -> Array:
	var all: Variant = game.get(&"players")
	return (all as Dictionary).values() if all is Dictionary else []


func _zombies() -> Array:
	var view: Object = _client.get(&"world_view") if is_instance_valid(_client) else null
	return view.call(&"live_bodies") if view != null else []


## What the crosshair is on: the nearest body the camera's ray passes through. ENEMY for a living zombie, FRIEND for
## another survivor or a dead one (never shot), NONE when nothing is or a wall is in front. A zombie a client sees is a
## mirror with no collision, so the test is analytic (a vertical capsule), plus at most one physics ray for walls.
static func crosshair_kind(eye: Vector3, forward: Vector3, me: Object, others: Array, zombies: Array,
		space: PhysicsDirectSpaceState3D, mask: int) -> int:
	var best_t := INF
	var best_enemy := false
	var best_aim := Vector3.ZERO
	for p: Node3D in others:
		if p == me or not _shown(p):
			continue
		var feet := p.global_position
		var t := _ray_hit(eye, forward, feet, PLAYER_HEIGHT, PLAYER_RADIUS)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_enemy = false
	for z: Node3D in zombies:
		if not _shown(z):
			continue
		var height := float(z.get(&"height"))
		var t := _ray_hit(eye, forward, z.global_position, height, float(z.get(&"radius")))
		if t >= 0.0 and t < best_t:
			best_t = t
			best_enemy = true
			best_aim = z.global_position + Vector3(0.0, height * 0.6, 0.0)
	if best_t == INF:
		return DotMobileAutoFire.TARGET_NONE
	if not best_enemy:
		return DotMobileAutoFire.TARGET_FRIEND
	if _blocked(space, mask, eye, best_aim):
		return DotMobileAutoFire.TARGET_NONE
	return DotMobileAutoFire.TARGET_ENEMY


## The chests of living zombies near the crosshair with no wall between, for aim assist.
static func assist_targets(eye: Vector3, forward: Vector3, zombies: Array, space: PhysicsDirectSpaceState3D,
		mask: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cos_cone := cos(deg_to_rad(ASSIST_CONE_DEG))
	for z: Node3D in zombies:
		if not _shown(z):
			continue
		var at := z.global_position + Vector3(0.0, float(z.get(&"height")) * 0.6, 0.0)
		var to := at - eye
		var dist := to.length()
		if dist < 0.01 or dist > ASSIST_RANGE or forward.dot(to / dist) < cos_cone:
			continue
		if not _blocked(space, mask, eye, at):
			out.append(at)
	return out


## Distance along the ray to the point nearest the upright capsule's axis when the ray passes within [param radius] of
## it, in front of the eye and within [constant SIGHT_RANGE]; -1 when it does not.
static func _ray_hit(from: Vector3, dir: Vector3, feet: Vector3, height: float, radius: float) -> float:
	var w := from - feet
	var denom := height * (dir.y * dir.y - 1.0)
	var s := 0.5 if absf(denom) < 0.0001 else (dir.y * dir.dot(w) - w.y) / denom
	s = clampf(s, 0.0, 1.0)
	var on_segment := feet + Vector3(0.0, height * s, 0.0)
	var t := dir.dot(on_segment - from)
	if t <= 0.0 or t > SIGHT_RANGE:
		return -1.0
	return t if (from + dir * t).distance_to(on_segment) <= radius else -1.0


static func _shown(p: Node3D) -> bool:
	return is_instance_valid(p) and p.is_inside_tree() and p.is_visible_in_tree()


static func _blocked(space: PhysicsDirectSpaceState3D, mask: int, from: Vector3, to: Vector3) -> bool:
	if space == null or mask == 0:
		return false
	return not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask)).is_empty()
