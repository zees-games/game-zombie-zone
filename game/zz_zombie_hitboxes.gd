extends RefCounted

const ZzZombieLimbs := preload("../npcs/zz_zombie_limbs.gd")
## A zombie's hitbox set, sized to its kind, for `ZzHorde._register_combat`.


## A zombie's hitboxes: head, body, stomach and, on a riot zombie, its shield.
static func build(def: GSNpcDef, height: float, radius: float) -> GSHitboxSet:
	var set_node := GSHitboxSet.new()
	set_node.name = "Hitboxes"
	set_node.bounds_offset = Vector3(0.0, height * 0.5, 0.0)
	set_node.bounds_radius = height

	var head := GSHitbox.new()
	head.name = "Head"
	head.group = GSHitGroup.HEAD
	head.shape = GSHitbox.Shape.SPHERE
	head.radius = clampf(radius * 0.7, 0.18, 0.4)
	head.position = Vector3(0.0, height - head.radius * 1.1, 0.0)
	head.precedence = 10
	set_node.add_child(head)

	var chest := GSHitbox.new()
	chest.name = "Body"
	chest.group = GSHitGroup.CHEST
	chest.shape = GSHitbox.Shape.CAPSULE
	chest.radius = radius + 0.06
	chest.height = height * 0.82
	chest.position = Vector3(0.0, height * 0.41, 0.0)
	set_node.add_child(chest)

	# The belly is a zone of its own (dot-combat's stomach), a band of the body that wins over the
	# capsule; with mp_hitzones 0 the resolver folds it into chest, so damage is unchanged.
	var stomach := GSHitbox.new()
	stomach.name = "Stomach"
	stomach.group = GSHitGroup.STOMACH
	stomach.shape = GSHitbox.Shape.BOX
	stomach.half_extents = Vector3(radius + 0.06, height * (ZzZombieLimbs.STOMACH_TOP - ZzZombieLimbs.STOMACH_BOTTOM) * 0.5, radius + 0.06)
	stomach.position = Vector3(0.0, height * (ZzZombieLimbs.STOMACH_TOP + ZzZombieLimbs.STOMACH_BOTTOM) * 0.5, 0.0)
	stomach.precedence = 5
	set_node.add_child(stomach)

	# A riot zombie's shield: a hitbox of its own in front of it, nearer the gun than its body,
	# so a frontal shot stops there (nearest entry wins in dot-combat) and does `shield` of its
	# damage. From the side or behind, the body is nearer and takes it all.
	if def.meta.has("shield"):
		var shield := GSHitbox.new()
		shield.name = "Shield"
		shield.group = GSHitGroup.CHEST
		shield.shape = GSHitbox.Shape.BOX
		shield.half_extents = Vector3(0.36, height * 0.3, 0.05)
		shield.position = Vector3(0.0, height * 0.5, -(radius + 0.16))
		shield.damage_scale = clampf(float(def.meta["shield"]), 0.0, 1.0)
		shield.precedence = 20
		set_node.add_child(shield)

	return set_node
