extends Node

## `tools/shot.sh --aim=DEG`: keeps these players' view pitch at `pitch` before anything else
## runs, each frame and each physics tick.

var players: Array = []
var pitch := INF
## `--sprint`: the stand-ins' state says they are sprinting.
var sprint := false


func _ready() -> void:
	process_physics_priority = -1000000


func _process(_delta: float) -> void:
	_hold()


func _physics_process(_delta: float) -> void:
	_hold()


func _hold() -> void:
	for player in players:
		if is_instance_valid(player) and player.controller != null:
			if pitch != INF:
				player.controller.state.pitch = pitch
			if sprint:
				player.controller.state.sprinting = true
