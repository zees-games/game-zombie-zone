extends GSNetBehaviour

const ZzZombieBody := preload("../../npcs/zz_zombie_body.gd")

## A zombie over the wire: where it is, which way it faces, how hurt it is, what it is doing.
##
## gs-npc's [GSNpcNetSync] fields, plus the two this game needs to draw one: the animation
## state ([member ZzZombieBody.anim]) and the flags (burning, enraged, startled). Server
## authoritative and never predicted, for gs-npc's reason: a zombie's position comes out of a
## graph, a brain and a crowd, none of which a client could reproduce, so the client draws it
## a few ticks in the past and is never corrected.
##
## [b]Its kind and its variant are not here.[/b] They never change, so they travel once, in the
## NPC event that announces it; a per-tick field would send the same sixteen bits forty times a
## second per zombie for ever.

var npc: GSNpcInstance = null

## The body this moves: the server's zombie, or a client's mirror of it.
var body: ZzZombieBody = null

var net_x: float = 0.0
var net_y: float = 0.0
var net_z: float = 0.0
var net_yaw: int = 0
var net_health: int = 0
var net_state: int = 0
var net_anim: int = 0
var net_flags: int = 0
var net_limbs: int = 0
## Client: wall-clock msec of the last snapshot that carried or listed this zombie.
var state_msec: int = 0
## Client: the newest interpolator tick seen for this zombie (see [method is_stale]).
var seen_tick: int = -1


func _register_net_vars() -> void:
	for spec in GSNpcNetSync.specs():
		var field := replicate(spec["property"], GSNetVar.Type[spec["type"]])

		if int(spec["bits"]) > 0:
			field.bits(int(spec["bits"]))

		if bool(spec["interpolated"]):
			field.interpolated()

	for spec in GSNpcNetSync.limb_specs():
		replicate(spec["property"], GSNetVar.Type[spec["type"]]).bits(int(spec["bits"]))

	replicate(&"net_anim", GSNetVar.Type.UINT).bits(5)
	replicate(&"net_flags", GSNetVar.Type.UINT).bits(5)


func pull() -> void:
	if npc == null or not npc.is_alive() or body == null:
		return

	GSNpcNetSync.pull(npc, self, GSNpcNetSync.State.ATTACKING if npc.has_target() else GSNpcNetSync.State.IDLE)
	net_anim = clampi(body.anim, 0, 31)
	net_flags = body.flags & 31
	net_limbs = body.limb_mask & ((1 << GSNpcNetSync.LIMB_BITS) - 1)


func _net_simulate(_tick: int, _delta: float) -> void:
	if identity != null and identity.is_authoritative:
		pull()


## Client: whether no snapshot has carried or listed this zombie for [param after_msec]. A snapshot
## that lists it with no changed value skips [method _net_state_applied] (gs-net API 26) but still
## adds an interpolator sample, so a new newest tick counts as heard from too.
func is_stale(now: int, after_msec: int, interpolator: GSNetInterpolator, net_id: int) -> bool:
	if interpolator != null:
		var tick := interpolator.newest_tick(net_id)
		if tick != seen_tick:
			seen_tick = tick
			state_msec = now
	return now - state_msec > after_msec


func _net_state_applied(_tick: int) -> void:
	state_msec = Time.get_ticks_msec()
	_draw()

	if body != null and identity != null and not identity.is_authoritative:
		body.anim = net_anim
		body.flags = net_flags
		body.limb_mask = net_limbs
		body.health = float(net_health)


func _net_interpolated(_tick: int) -> void:
	_draw()


func _draw() -> void:
	if body == null or not is_instance_valid(body):
		return

	if identity != null and identity.is_authoritative:
		return

	GSNpcNetSync.apply(body, self)
