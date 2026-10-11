extends DotTracePhysics

## The shot trace, with one rule the stock trace cannot know: [b]a shot that starts inside a
## friend is not aimed at them.[/b]
##
## dot-combat counts a ray that starts inside a hitbox as a hit at distance zero, which is right
## for a shotgun pressed against a zombie's chest. Survivors here do not collide with each other
## (the netcode's call, see [method ZzGame._build_physics]), so two of them can stand in the same
## place, and then the muzzle sits inside the other's head: every shot, aimed anywhere, hit the
## friend at zero metres and nothing else. Four stand-ins following one path bunched like that,
## downed each other with friendly fire inside a minute and lost the practice street, and the
## stand-in's own "friend in the line" check could not help, because the friend was not in the
## line. A person standing inside a team-mate's capsule had the same gun.
##
## So a survivor's hitboxes that contain the shot's origin are left out of that shot, and it
## carries on to whatever it was aimed at. Anything else containing the origin (a zombie) is
## still a point-blank hit. A friend merely close, with the muzzle outside them, is still in the
## line and still hit: friendly fire is a rule, and only the stacked case was never aimed.

const ZzPlayer := preload("zz_player.gd")

## The rules the combat manager judges with. With
## [member DotDamageRules.pass_through_team_mate_at_muzzle] off (the server's
## `mp_teammate_passthrough 0`) this trace drops nothing, so the operator's setting is not
## undone here. Null keeps the rule on. dot-combat now applies the same rule itself in
## `DotCombatManager.pass_through_sets`; this file stays until every host has that.
var rules: DotDamageRules = null


func ray(
	from: Vector3,
	direction: Vector3,
	max_distance: float,
	sets: Array[DotHitboxSet] = []
) -> DotHitbox.Hit:
	if rules != null and not rules.pass_through_team_mate_at_muzzle:
		return super.ray(from, direction, max_distance, sets)

	var kept: Array[DotHitboxSet] = []

	for set_node in sets:
		if set_node == null or not is_instance_valid(set_node) or not survivor_around(set_node, from):
			kept.append(set_node)

	return super.ray(from, direction, max_distance, kept)


## Whether [param set_node] is a survivor's and one of its hitboxes contains [param point].
static func survivor_around(set_node: DotHitboxSet, point: Vector3) -> bool:
	if not (set_node.entity_owner() is ZzPlayer):
		return false

	for box in set_node.hitboxes():
		if box.enabled and box.overlaps_sphere(point, 0.0):
			return true

	return false
