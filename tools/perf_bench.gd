extends DotGamePerfBench

## Solo-client benchmark (dot-game's DotGamePerfBench: see it for the flags and the report). Runs the offline client's own map
## with `--bots N` stand-ins; windowed on a GPU box through tools/perf_bench.sh, not headless.


func _configure() -> void:
	client_scene = "res://game/zz.tscn"
	bots = 3
	warmup = 10.0
