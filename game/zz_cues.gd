extends RefCounted

## Which sound a kind makes for which event: the shipped cue list, written into each kind's profile
## (`cue_<key>:` under `extra:`; tools/export_npc_profiles.gd) and read back by ZzAudio.
## A cue is a catalogue id: `real_*` are the recorded sets, the bare ids (`moan`, `scream`, `claw`,
## `zombie_die`, the specials' own) are the first generation, kept to compare and fall back to.

const KEYS: Array[String] = ["idle", "rage", "attack", "die", "hurt", "voice", "zap", "grab", "throw", "jet"]

const COMMON := {"idle": "real_moan", "rage": "real_rage", "attack": "real_claw", "die": "real_die", "hurt": "real_hurt"}


## The cues of one kind; empty for an unknown one.
static func of(kind: StringName) -> Dictionary:
	if kind == &"common":
		return COMMON
	var c := {"voice": "real_" + String(kind), "die": "real_die", "hurt": "real_hurt", "attack": "real_claw"}
	match kind:
		&"sleeper":
			return {"voice": "sleeper", "die": "real_die", "hurt": "real_hurt"}
		&"mutant":
			c["zap"] = "real_mutant_zap"
			c["grab"] = "real_mutant_grab"
			c["throw"] = "real_mutant_throw"
			c["jet"] = "real_mutant_jet"
		&"brute", &"leaper", &"strangler", &"bloater", &"ram", &"spitter", &"rider", &"screamer", &"crawler", &"riot":
			pass
		_:
			return {}
	return c
