extends RefCounted

## The box types as dot-profile `box` profiles (`cfg/game/game-zombie-zone/box/<id>.yml`).
##
## boxes/boxes.json is the floor and the source of the shipped files (tools/export_box_profiles.gd; the packs suite fails when they are
## stale). A profile of the same id replaces that type, so an operator edits one in the workbench or in cfg/server/game/game-zombie-zone/box.
## What the profile cannot say stays in code: the action vocabulary (ZzBoxes.ACTIONS) and the named handlers.

const GAME := "game-zombie-zone"
const DIR := "res://cfg/game/game-zombie-zone/box"
const KEYS: Array[String] = [
	"title", "colour", "polarity", "impact", "radius", "stacks", "max_stacks", "survives_round", "duration", "drop", "open_seconds",
	"lifetime", "params", "outcomes", "sounds", "enabled",
]


static func make_set(roots: PackedStringArray = PackedStringArray()) -> DotProfileSet:
	return DotBoxProfiles.make_set(GAME, roots)


## The profile as the document ZzBoxes.read_box reads.
static func doc_of(p: DotProfile) -> Dictionary:
	var doc := {}

	for k in KEYS:
		doc[k] = DotBoxProfiles.unwrap_lists(p.get_value(k))

	return doc


## yml of one box type from boxes.json's document.
static func yaml_of(box: Dictionary) -> String:
	var tree := {}

	for k in KEYS:
		if box.has(k):
			tree[k] = box[k]

	return DotBoxProfiles.to_yaml(tree)
