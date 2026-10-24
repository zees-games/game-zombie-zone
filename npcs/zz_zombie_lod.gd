extends RefCounted

## How much each zombie's look costs by where it is from the camera: how often its clip is
## advanced, whether it casts a shadow and how far it is drawn. One per world view, shared by
## every zombie view; [method refresh] once a frame. The setting `crowd_detail` picks a preset.

const CHANNEL := "zz.zombie_lod"

## Low, normal, high: [near, far, shadow_until, draw_until, offscreen_every].
const PRESETS := [
	[12.0, 25.0, 15.0, 70.0, 8],
	[22.0, 45.0, 30.0, 120.0, 8],
	[40.0, 80.0, 60.0, 160.0, 4],
]

## Metres past which the clip is advanced every second frame, and every fourth.
var near := 22.0
var far := 45.0
## Metres past which it casts no shadow, and past which it is not drawn.
var shadow_until := 30.0
var draw_until := 120.0
## Frames between advances of a zombie outside the view (its pose is not seen, only a shadow).
var offscreen_every := 8
var detail := 1

var camera_at := Vector3.INF
var _planes: Array[Plane] = []


## Picks preset [param level] (0 low, 1 normal, 2 high).
func apply_detail(level: int) -> void:
	detail = clampi(level, 0, PRESETS.size() - 1)
	var p: Array = PRESETS[detail]
	near = p[0]
	far = p[1]
	shadow_until = p[2]
	draw_until = p[3]
	offscreen_every = p[4]
	DotLog.debug(CHANNEL, "crowd detail", {"level": detail})


## Follows `crowd_detail` in [param store] now and whenever it changes.
func follow(store: Object) -> void:
	if store == null:
		return
	apply_detail(store.get_int(&"crowd_detail", 1))
	if not store.changed.is_connected(_on_changed):
		store.changed.connect(_on_changed.bind(store))


func _on_changed(key: StringName, _value: Variant, _why: StringName, store: Object) -> void:
	if key == &"crowd_detail":
		apply_detail(store.get_int(&"crowd_detail", 1))


## Where the camera is and what it sees this frame. Null keeps every zombie in view.
func refresh(camera: Camera3D) -> void:
	if camera == null or not camera.is_inside_tree():
		camera_at = Vector3.INF
		_planes.clear()
		return
	camera_at = camera.global_position
	_planes.assign(camera.get_frustum())


## Whether a sphere of [param radius] at [param at] is at least partly in view.
func in_view(at: Vector3, radius: float = 1.5) -> bool:
	for plane in _planes:
		if plane.distance_to(at) > radius:
			return false
	return true


## Frames between clip advances for a zombie at [param at].
func every(at: Vector3) -> int:
	if camera_at == Vector3.INF:
		return 1
	if not in_view(at + Vector3(0.0, 1.0, 0.0)):
		return offscreen_every
	var d := camera_at.distance_to(at)
	return 4 if d > far else (2 if d > near else 1)


func describe() -> Dictionary:
	return {"detail": detail, "near": near, "far": far, "shadow_until": shadow_until,
		"draw_until": draw_until, "offscreen_every": offscreen_every}
