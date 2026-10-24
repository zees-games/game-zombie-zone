extends DotMapEntity

## logic_gamerules: a bag of rule keys the map sets at start. The ones that map onto this game's tunables (ZzMapCommands.GAMERULES)
## are told to the game as `game_rule` events, which applies them through the same ranges as a map's server commands; the rest are
## logged once and left alone.


func on_map_spawn(io: DotMapIO) -> void:
	if not enabled:
		return
	for k: String in keys:
		if k == "spawnflags" or k == "origin" or k == "angles" or k == "targetname" or k == "hammerid" or k == "classname":
			continue
		io.event("game_rule", {"entity": index, "key": k, "value": key(k)})
