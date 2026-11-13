extends RefCounted

## A survivor's attachment fittings, one per weapon: what the fitting screen saves in the
## profile's settings, what a client asks the server for, and putting them on an arsenal.
##
## [b]Per weapon id, not per slot.[/b] The rifle wears the same red dot whichever slot or
## shelf it is picked up into, and the fitting outlives the rifle being dropped: the next one
## found wears it too.
##
## [b]Nothing here trusts what it is given.[/b] [method apply_to] puts on only what
## [method DotWeaponAttachments.conform] keeps, so a fitting saved by another version, or
## typed into the settings file, degrades rather than refuses; the server validates a fitting
## outright before it stores one (`ZzGame.fit_weapon`).
##
## The text form, the [constant SETTING] value: `m4:optic=zz_red_dot,underbarrel=zz_grip;ak:...`.

const SETTING := &"weapon_fittings"
## The setting's length cap, and so how much [method parse] reads.
const MAX_TEXT := 2048
const MAX_WEAPONS := 64
const MAX_MOUNTS := 8


## Weapon id -> [DotWeaponFitting] from [param text]; malformed parts are skipped.
static func parse(text: String) -> Dictionary:
	var out: Dictionary = {}

	for part in text.substr(0, MAX_TEXT).split(";", false):
		if out.size() >= MAX_WEAPONS:
			break

		var head := part.split(":", true, 1)
		var weapon := head[0].strip_edges() if head.size() == 2 else ""

		if weapon == "":
			continue

		var fitting := DotWeaponFitting.make(StringName(weapon))

		for pair in head[1].split(",", false):
			if fitting.mounts().size() >= MAX_MOUNTS:
				break

			var kv := pair.split("=")

			if kv.size() == 2 and kv[0].strip_edges() != "" and kv[1].strip_edges() != "":
				fitting.fit(StringName(kv[0].strip_edges()), StringName(kv[1].strip_edges()))

		out[fitting.weapon_id] = fitting

	return out


## The inverse of [method parse], in id order; an empty fitting is left out.
static func format(fittings: Dictionary) -> String:
	var ids: Array = fittings.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var parts := PackedStringArray()

	for id: Variant in ids:
		var fitting := fittings[id] as DotWeaponFitting

		if fitting == null or fitting.is_empty():
			continue

		var pairs := PackedStringArray()

		for mount in fitting.mounts():
			pairs.append("%s=%s" % [mount, fitting.attachment_on(mount)])

		parts.append("%s:%s" % [id, ",".join(pairs)])

	return ";".join(parts)


## Fits every weapon in hand in [param arsenal] that [param fittings] names and does not
## already wear it. Returns how many changed. Idempotent: fitting emits `carried_changed`,
## and the second pass finds nothing to do.
static func apply_to(arsenal: DotWeaponArsenal, fittings: Dictionary) -> int:
	if arsenal == null or arsenal.attachments == null or fittings.is_empty():
		return 0

	var changed := 0

	for slot in arsenal.slots():
		var now := arsenal.fitting_at(slot)
		var wanted := fittings.get(now.weapon_id) as DotWeaponFitting
		var base := arsenal.catalogue.get_def(now.weapon_id) if wanted != null else null

		if base == null:
			continue

		var legal := arsenal.attachments.conform(base, wanted)

		if legal.key() != now.key() and arsenal.fit(slot, legal).ok:
			changed += 1

	return changed


## Keeps [param arsenal] wearing [param fittings] (held by reference: change the dictionary,
## not the variable) as weapons are given, picked up and swapped off the shelf.
static func watch(arsenal: DotWeaponArsenal, fittings: Dictionary) -> void:
	var follow := func() -> void:
		var _changed := apply_to(arsenal, fittings)

	arsenal.carried_changed.connect(follow)
	arsenal.switched.connect(func(_from: int, _to: int) -> void: follow.call())
