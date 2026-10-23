extends RefCounted

## Per-map settings: dot-game's [DotGameMapConfig] over the server cvars a map may change.
##
## `cfg/game/game-zombie-zone/dot_map/map/<name>.yml` (a glob covers a class of maps), overridable from `cfg/server/...`. Only the keys in [constant KEYS] are accepted. All are server-side rules; none is a movement setting, because a client predicts those and `zz_gravity` is not replicated.

const GAME_ID := "game-zombie-zone"

## cvar -> its constraint.
const KEYS := {
	"zz_difficulty": {"type": "int", "min": 0, "max": 3},
	"zz_friendly_fire": {"type": "float", "min": 0.0, "max": 1.0},
	"zz_max_incaps": {"type": "int", "min": 0, "max": 10},
	"zz_survive_seconds": {"type": "float", "min": 0.0},
	"zz_commons": {"type": "int", "min": 0, "max": 200},
	"zz_waves": {"type": "int", "min": 1, "max": 100},
	"zz_nights": {"type": "int", "min": 1, "max": 100},
	"zz_day_seconds": {"type": "float", "min": 1.0},
	"zz_wave_size": {"type": "int", "min": 1, "max": 200},
	"zz_wave_twists": {"type": "int", "min": 0, "max": 1},
}
