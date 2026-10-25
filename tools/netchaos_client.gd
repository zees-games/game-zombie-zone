extends DotGameNetchaosClient

## Zombie Zone's side of `tools/netchaos.sh` (dot-game's DotGameNetchaosClient).


func _configure() -> void:
	client_scene = "res://game/zz.tscn"
	fire_action = &"zz_fire"


func _roster() -> Array:
	return _client.get("game").survivors()
