extends RefCounted

## The survivor's flashlight config and the server's rules for it (the beam is dot-flashlight's).

const ZzMapDocScript := preload("zz_map_doc.gd")
const ZzAudio := preload("zz_audio.gd")
const GAME_ID := "game-zombie-zone"


## A config with this game's defaults: the key is F; the shove moved to T.
static func make_config() -> DotFlashlightConfig:
	var cfg := DotFlashlightConfig.new()
	cfg.key = "F"
	return cfg


## The binder for the config: `zz_flashlight_<field>` cvars, `cfg/game/game-zombie-zone/flashlight/game.yml`, a workbench set.
static func flashlight_binder(cfg: DotFlashlightConfig) -> DotGameConfigBinder:
	var b := DotGameConfigBinder.create(cfg, GAME_ID, "zz_flashlight")
	b.profile_kind = "flashlight"
	return b


## Whether a survivor starts the map with the light on: the map's mood or its ambient against the floor.
static func starts_on(cfg: DotFlashlightConfig, map_id: String, doc: Dictionary) -> bool:
	var env: Dictionary = doc.get("environment", {})
	var ambient := float(env.get("ambient_energy", ZzMapDocScript.DEFAULT_ENV["ambient_energy"]))
	return DotFlashlightRules.start_on(cfg, map_id, ambient, mood_of(map_id, doc))


## The mood a map document names. Converted maps write "ambient" as a dictionary
## ({"mood": ..., "indoor": ...}) and hand-made ones may write a string; with neither, the
## hand-made table decides. Reading the dictionary with str() gave a string no dark mood matched,
## so ze_biohazard_manor (ambient 0.3, over the floor) started with the light off.
static func mood_of(map_id: String, doc: Dictionary) -> String:
	var a: Variant = doc.get("ambient", null)
	if a is Dictionary:
		var m := str((a as Dictionary).get("mood", ""))
		if m != "":
			return m
	elif a != null and str(a) != "":
		return str(a)
	return str(ZzAudio.MAP_MOOD.get(StringName(map_id), ""))
