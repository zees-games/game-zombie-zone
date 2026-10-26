extends RefCounted

## The survivor's flashlight config and the server's rules for it (the beam is dot-flashlight's).

const ZzMapDocScript := preload("zz_map_doc.gd")
const ZzAudio := preload("zz_audio.gd")
const GAME_ID := "game-zombie-zone"


## A config with this game's defaults: the key is T because F is the shove.
static func make_config() -> DotFlashlightConfig:
	var cfg := DotFlashlightConfig.new()
	cfg.key = "T"
	return cfg


## The binder for the config: `zz_flashlight_<field>` cvars, `cfg/game/game-zombie-zone/flashlight/game.yml`, a workbench set.
static func make_binder(cfg: DotFlashlightConfig) -> DotGameConfigBinder:
	var b := DotGameConfigBinder.create(cfg, GAME_ID, "zz_flashlight")
	b.profile_kind = "flashlight"
	return b


## Whether a survivor starts the map with the light on: the map's mood or its ambient against the floor.
static func starts_on(cfg: DotFlashlightConfig, map_id: String, doc: Dictionary) -> bool:
	var env: Dictionary = doc.get("environment", {})
	var ambient := float(env.get("ambient_energy", ZzMapDocScript.DEFAULT_ENV["ambient_energy"]))
	var mood := str(doc.get("ambient", ZzAudio.MAP_MOOD.get(StringName(map_id), "")))
	return DotFlashlightRules.start_on(cfg, map_id, ambient, mood)
