extends GSLoadProbe

## The load probe: gs-game's [GSLoadProbe] on this game's offline solo client, with the tick
## column(s) before player/cam/hud. Needs xvfb-run, never --headless:
##   xvfb-run -a godot --path . res://tools/load_probe.tscn -- [--frames=90] [--shot=N]
const ZzClientScript := preload("../game/zz_client.gd")


func _make_client() -> Node:
	var c := ZzClientScript.new()
	c.set("force_offline", true)
	return c


func _columns(gate: Object) -> String:
	return "tick=%s %s" % [client.get("game").current_tick(), super(gate)]
