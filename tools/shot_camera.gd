extends Camera3D

## The shot tool's free camera. The client writes its own camera and HUD every frame (and puts
## its camera back as current after a view change), so this one takes over after it, last in
## each frame, rather than once when it is made.

var client: Node = null
## Optional: returns the world point to keep in frame; the camera sits `track_offset` from it.
var track: Callable
var track_offset := Vector3(5.0, 2.0, 5.0)


func _ready() -> void:
	process_priority = 1000000


func _process(_delta: float) -> void:
	if not current:
		make_current()

	if track.is_valid():
		var target: Variant = track.call()
		if target is Vector3:
			look_at_from_position(target + track_offset, target)

	var hud = client.get("hud") if client != null else null

	if hud is CanvasItem or hud is CanvasLayer:
		hud.visible = false
