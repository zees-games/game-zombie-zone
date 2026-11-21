extends GSGameWorkbenchSuite

## game-zombie-zone: the workbench over the config binder, one edit per profile set, the export and its cfg round trip.
## Run: godot --headless --path . res://examples/headless_workbench.tscn

const ZzConfig := preload("../game/zz_config.gd")


func _make_config() -> GSConfig:
	return ZzConfig.new()


func _make_binder(config: GSConfig) -> GSGameConfigBinder:
	return ZzConfig.make_binder(config)
