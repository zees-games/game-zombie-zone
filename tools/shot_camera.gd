extends Camera3D

## The shot tool's free camera. The client writes its own camera and HUD every frame (and puts
## its camera back as current after a view change), so this one takes over after it, last in
## each frame, rather than once when it is made.

var client: Node = null


func _ready() -> void:
	process_priority = 1000000


func _process(_delta: float) -> void:
	if not current:
		make_current()

	var hud = client.get("hud") if client != null else null

	if hud is CanvasItem or hud is CanvasLayer:
		hud.visible = false
