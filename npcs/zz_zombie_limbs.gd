extends RefCounted

## The wiring of a zombie's shootable limbs (dot-npc's DotNpcLimbs): which limbs a kind has, where
## they sit on the body as drawn, and the view that cuts them off. No class_name (a mounted pack
## cannot register one); callers preload it.

const ZzZombieView := preload("zz_zombie_view.gd")

## The kind every other kind's limbs are read from, with its own keys laid over.
const BASE := &"zombie"


## The limbs of [param kind]: the base set with the kind's own keys over it. A limb's `share` of
## [param max_health] becomes its `health` (0 leaves `health` as written, or 100).
static func defs_for(kind: StringName, max_health: float) -> Dictionary:
	var base := DotNpcLimbs.defs_from_config(BASE)

	if base.is_empty():
		return {}

	var defs := base.duplicate(true)

	if kind != BASE:
		var own := DotNpcLimbs.defs_from_config(kind)

		for limb: String in own:
			if defs.has(limb) and own[limb] is Dictionary:
				(defs[limb] as Dictionary).merge(own[limb], true)
			else:
				defs[limb] = own[limb]

	for limb: String in defs:
		var d := defs[limb] as Dictionary

		if d.has("share") and max_health > 0.0:
			d["health"] = float(d["share"]) * max_health

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
