extends RefCounted

## The wiring of a zombie's shootable limbs (dot-npc's DotNpcLimbs): which limbs a kind has, where
## they sit on the body as drawn, and the view that cuts them off. No class_name (a mounted pack
## cannot register one); callers preload it.

const ZzZombieView := preload("zz_zombie_view.gd")

## The kind every other kind's limbs are read from, with its own keys laid over.
const BASE := &"zombie"


## The zone a limb belongs to when a shot lands on it, as dot-combat's [DotHitGroup] ids. Under `mp_hitzones` 0
## dot-combat folds knee and foot into leg, hand into arm (DotHitzone.coarse), so these never change damage then.
const LIMB_ZONE := {&"head": DotHitGroup.HEAD, &"armL": DotHitGroup.ARM, &"armR": DotHitGroup.ARM,
	&"legL": DotHitGroup.LEG, &"legR": DotHitGroup.LEG}
## Fractions of body height (from the feet): below FOOT is foot, FOOT to KNEE_TOP a shin or knee band is knee.
const FOOT_TOP := 0.08
const KNEE_BOTTOM := 0.2
const KNEE_TOP := 0.34
## An arm hit below this height is the hand; the stomach box sits between STOMACH_BOTTOM and STOMACH_TOP.
const HAND_TOP := 0.42
const STOMACH_BOTTOM := 0.4
const STOMACH_TOP := 0.56


## The zone of a hit on [param limb] at [param rel] (0 at the feet, 1 at the top of the head): the limb's
## zone, refined to foot, knee or hand by height. An unknown limb (a mutant's gun) is the chest.
static func zone_of(limb: StringName, rel: float) -> StringName:
	var zone: StringName = LIMB_ZONE.get(limb, DotHitGroup.CHEST)

	if zone == DotHitGroup.LEG:
		if rel < FOOT_TOP:
			return DotHitGroup.FOOT
		if rel >= KNEE_BOTTOM and rel <= KNEE_TOP:
			return DotHitGroup.KNEE
	elif zone == DotHitGroup.ARM and rel < HAND_TOP:
		return DotHitGroup.HAND

	return zone


## The limbs of [param kind]: the base set with the kind's own keys over it. A limb's `share` of
## [param max_health] becomes its `health` (0 leaves `health` as written, or 100).
static func defs_for(kind: StringName, max_health: float) -> Dictionary:
	var defs := (_configured(kind) as Dictionary).duplicate(true)

	for limb: String in defs:
		var d := defs[limb] as Dictionary

		if d.has("share") and max_health > 0.0:
			d["health"] = float(d["share"]) * max_health

	return defs


## [param kind]'s limbs as configured, read from the config dir once per kind: a read is a walk
## over every config tier on disk, and every zombie spawned asked twice. Never handed out; a
## caller gets a deep copy from [method defs_for].
static var _configured_by_kind: Dictionary = {}


static func _configured(kind: StringName) -> Dictionary:
	if _configured_by_kind.has(kind):
		return _configured_by_kind[kind]

	# A kind with a body of its own lists every limb and takes none of the zombie's.
	var base := DotNpcLimbs.defs_from_config(BASE) if kind != &"mutant" and kind != &"oil_monster" else {}

	# Not kept: an unread config (a pack not mounted yet) is asked again next time.
	if base.is_empty() and kind != &"mutant" and kind != &"oil_monster":
		return {}

	var defs := base.duplicate(true)

	if kind != BASE:
		var own := DotNpcLimbs.defs_from_config(kind)

		for limb: String in own:
			if defs.has(limb) and own[limb] is Dictionary:
				(defs[limb] as Dictionary).merge(own[limb], true)
			else:
				defs[limb] = own[limb]

	_configured_by_kind[kind] = defs
	return defs


## Gives [param body] its limbs, once. [param max_health] is the kind's (0 on a client, which never
## hurts a limb). Null for a kind with none configured.
static func attach(body: Node3D, kind: StringName, variant: int, max_health: float = 0.0) -> DotNpcLimbs:
	if body.get(&"limbs") != null:
		return body.get(&"limbs")

	var defs := defs_for(kind, max_health)

	if defs.is_empty():
		return null

	var limbs := DotNpcLimbs.new()
	limbs.name = "Limbs"
	body.add_child(limbs)
	limbs.rest_model = ZzZombieView.limb_rest(kind, variant)
	limbs.setup(kind, defs)
	limbs.severed.connect(body.on_limbs_severed)
	body.set(&"limbs", limbs)

	var mask := int(body.get(&"limb_mask"))

	if mask != 0:
		limbs.apply_mask(mask)

	return limbs


## The drawn zombie takes over cutting its own limbs, and shows the ones already gone.
static func bind_view(body: Node3D, view: Node3D) -> void:
	var limbs: DotNpcLimbs = body.get(&"limbs")

	if limbs == null:
		return

	limbs.view = view
	limbs.skeleton = view.get(&"_skeleton")
	limbs.model = view.get(&"_model")
	var mask := limbs.mask()

	if mask != 0:
		# Gone before there was a body to draw: stumps only, as a late joiner sees them.
		var gone := limbs.limb_names().filter(func(k: StringName) -> bool: return limbs.is_severed(k))
		for k: StringName in gone:
			view.call(&"stump_limb", k, limbs.defs[k])
