extends Node

## Prints what the annotations find on each survival map, and how long it takes. A probe, not a
## suite: `godot --headless --path . res://tools/nav_probe.tscn -- --map=zz_high_school`.

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")

const TICK := 1.0 / 64.0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	var ids := ["zz_chapel", "zz_high_school", "zz_lot", "zz_mall", "zz_relief_camp", "zz_stadium"]

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			ids = [arg.substr(6)]

	for id: String in ids:
		var config := ZzConfig.new()
		config.map_ids = PackedStringArray([id])
		config.warmup_seconds = 0.0
		config.minimum_players = 0
		config.keep_progress = false
		var game := ZzGame.new()
		game.config = config
		game.tick_rate = 64
		game.authoritative = true
		game.register_service = false
		add_child(game)
		game.set_physics_process(false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		for i in maxi(game.team_size(), 4):
			var p := game.add_player(StringName("u%d" % i), "B%d" % i)
			p.is_bot = true
		game.start()
		var ticks := 0
		while not game.horde.notes.is_ready() and ticks < 4000 and game.horde.notes.state != 4:
			game.simulate(TICK)
			ticks += 1
			if ticks % 8 == 0:
				await get_tree().physics_frame
		print("phase ", game.phase, " players ", game.players.size(), " team ", game.team_size())
		print("%s: %d ticks  %s map=%s nav=%s" % [id, ticks, game.horde.notes.describe(), game.map.id() if game.map else "none", game.horde.nav.point_count() if game.horde.nav else -1])
		var n: Object = game.horde.notes
		if n.annotations != null:
			for l in n.annotations.describe_lines():
				print("   ", l)
			print("   stats ", n.annotations.stats.get("routes"), " ", n.annotations.stats.get("islands_kept"))
		if n.annotations != null:
			var shown := 0
			var data = game.horde.nav
			for l in n.annotations.links_of(0):
				if shown >= 4: break
				shown += 1
				var a: int = data.nearest_point(l["from"], 1.6)
				var b: int = data.nearest_point(l["to"], 1.6)
				print("   drop ", l["from"], " -> ", l["to"], " pts ", a, " ", b, " ys ", data.points[a].y if a >= 0 else -1.0, " ", data.points[b].y if b >= 0 else -1.0)
		for c in n.chokes:
			print("   choke at %s w=%.1f order=%.2f hold=%s fallback=%d" % [c["at"], c["width"], c["order"], c["hold"], c["fallback"]])
		game.queue_free()
		await get_tree().physics_frame
	get_tree().quit()
