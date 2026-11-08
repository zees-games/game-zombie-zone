extends RefCounted

## shot.sh's orbit camera: a free camera that circles a chosen subject at a distance, one frame per
## (time, yaw) pair, so a pose can be judged from several sides and at several moments in an animation.
##
##   --cam=orbit               turn it on (any view; the view's own free camera is replaced)
##   --target=holder|victim|pair|point|me   what to keep in frame (default pair: the midpoint of the pinned
##                             pair; holder / victim are the special and the survivor it holds; point is --at;
##                             me is the local survivor)
##   --dist=3.0                metres from the target
##   --yaw=0,90,180,270        degrees round the target, counter-clockwise seen from above. 0 is on the survivor's
##                             side of the pair looking back at the holder's front (its face and claws), 180 is
##                             behind the holder looking at the survivor, 90 / 270 the sides. One frame per value.
##   --pitch=12                degrees the camera is raised above the target
##   --lift=1.0                metres above the target's feet that the camera looks at
##   --times=0.2,0.5,0.9       seconds, after the view's own --seconds wait, at which to save a set of frames
##                             (default: one set at once). A view like pinned wants a short --seconds with these.
## Files: <out>_t<time>_y<yaw>.png beside --out.

var enabled := false
var target := "pair"
var dist := 3.0
var yaws: Array[float] = [0.0]
var pitch := 12.0
var lift := 1.0
var times: Array[float] = [0.0]
var point := Vector3.ZERO
## The pair in the frame, set by the view that makes one.
var holder: Variant = null
var victim: Variant = null
var me: Variant = null
var _yaw := 0.0


## True when [param arg] was one of this tool's flags and has been taken.
func take(arg: String) -> bool:
	if arg.begins_with("--cam="):
		enabled = arg.trim_prefix("--cam=") == "orbit"
	elif arg.begins_with("--target="):
		target = arg.trim_prefix("--target=")
	elif arg.begins_with("--dist="):
		dist = arg.trim_prefix("--dist=").to_float()
	elif arg.begins_with("--yaw="):
		yaws.clear()
		for part in arg.trim_prefix("--yaw=").split(",", false):
			yaws.append(part.to_float())
	elif arg.begins_with("--pitch="):
		pitch = arg.trim_prefix("--pitch=").to_float()
	elif arg.begins_with("--lift="):
		lift = arg.trim_prefix("--lift=").to_float()
	elif arg.begins_with("--times="):
		times.clear()
		for part in arg.trim_prefix("--times=").split(",", false):
			times.append(part.to_float())
	else:
		return false
	return true


func _holder_at() -> Vector3:
	return holder.position() if holder != null else Vector3.INF


func _victim_at() -> Vector3:
	return victim.feet() if victim != null else Vector3.INF


## The point the camera looks at.
func focus() -> Vector3:
	var h := _holder_at()
	var v := _victim_at()
	var up := Vector3.UP * lift
	match target:
		"holder":
			return (h if h != Vector3.INF else v) + up
		"victim":
			return (v if v != Vector3.INF else h) + up
		"point":
			return point
		"me":
			return (me.feet() if me != null else Vector3.ZERO) + up
	if h != Vector3.INF and v != Vector3.INF:
		return h.lerp(v, 0.5) + up
	return (h if h != Vector3.INF else v) + up


## Flat unit vector from the holder toward the survivor (the holder's facing when there is none).
func axis() -> Vector3:
	var h := _holder_at()
	var v := _victim_at()
	var flat := Vector3(v.x - h.x, 0.0, v.z - h.z) if h != Vector3.INF and v != Vector3.INF else Vector3.ZERO
	if flat.length() < 0.15 and holder != null and holder.node != null:
		flat = -holder.node.global_transform.basis.z
		flat.y = 0.0
	return flat.normalized() if flat.length() > 0.001 else Vector3(0.0, 0.0, -1.0)


func set_yaw(degrees: float) -> void:
	_yaw = degrees


## Camera offset from the focus for the current yaw.
func offset() -> Vector3:
	var flat := axis().rotated(Vector3.UP, deg_to_rad(_yaw)) * cos(deg_to_rad(pitch))
	return (flat + Vector3.UP * sin(deg_to_rad(pitch))) * dist
