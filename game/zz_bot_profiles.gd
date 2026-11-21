extends RefCounted

## The stand-ins' characters as dot-bot persona profiles (`cfg/game/game-zombie-zone/bot/<id>.yml`):
## what a survivor does when nothing is in front of it, how likely the server is to give it that
## character, and how well it shoots. Added, edited and deleted live in the workbench.

const GAME := "game-zombie-zone"


static func make_set(roots: PackedStringArray = PackedStringArray()) -> GSProfileSet:
	var s := GSProfileSet.create("dot-bot", GAME, GSBotPersona.KIND, GSBotPersona.schema())
	s.roots = roots
	return s
