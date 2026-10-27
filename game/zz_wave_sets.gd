extends RefCounted
## Wave sets as config (dot-npc-ai-director's DotWaveSet): which set a map plays and the
## game's own keys in `extra.zz`.

const GAME := "game-zombie-zone"
const ZZ_KEYS := ["twists", "wave_scale_by_map"]


## The sets to try, best first: the `sv_waves` value, the rotation entry's, the map document's.
static func candidates(sv_waves: String, play: Dictionary, doc_waves: String) -> Array:
	var out: Array = []
	for v: Variant in [sv_waves, play.get("waves", ""), doc_waves]:
		if str(v) != "" and not out.has(str(v)):
			out.append(str(v))
	return out


## `extra.zz` may hold only the keys this game reads, so a typo fails at load.
static func validate_extra(extra: Dictionary) -> DotResult:
	var zz: Variant = extra.get("zz", {})
	if not (zz is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "extra.zz must be a mapping")
	for k: Variant in zz:
		if not ZZ_KEYS.has(str(k)):
			return DotResult.fail(DotError.CODE_INVALID, "extra.zz.%s is not a key this game reads (%s)" % [k, ", ".join(ZZ_KEYS)])
	return DotResult.success(extra)


## Applies `extra.zz.wave_scale_by_map` for [param map_id] to the set's head counts.
static func scale_for_map(set: DotWaveSet, map_id: String) -> void:
	var zz: Variant = set.extra.get("zz", {})
	var table: Variant = (zz as Dictionary).get("wave_scale_by_map", {}) if zz is Dictionary else {}
	if not (table is Dictionary) or not (table as Dictionary).has(map_id):
		return
	var scale := float((table as Dictionary)[map_id])
	set.size_base = int(round(float(set.size_base) * scale))
	set.size_per_player = int(round(float(set.size_per_player) * scale))
