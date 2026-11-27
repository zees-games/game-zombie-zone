extends RefCounted

## The box outcomes that put zombies on the map.

const ZzNpcs := preload("zz_npcs.gd")

## [param a]'s `count` specials of its `kind` (or any), near the opener; [param rng] picks the kind.
static func special(game: Object, rng: RandomNumberGenerator, a: Dictionary) -> void:
	if game.horde == null:
		return

	for i in int(a.get("count", 1)):
		var kind := StringName(str(a.get("kind", "any")))
		var specials := ZzNpcs.specials()

		if specials.is_empty():
			return

		if kind == &"any" or not specials.has(kind):
			kind = specials[rng.randi_range(0, specials.size() - 1)]
		var _s = game.horde.spawn_special(kind)
