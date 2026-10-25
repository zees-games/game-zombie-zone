extends DotNetBehaviour

const ZzZombieBody := preload("../../npcs/zz_zombie_body.gd")

## A zombie over the wire: where it is, which way it faces, how hurt it is, what it is doing.
##
## dot-npc's [DotNpcNetSync] fields, plus the two this game needs to draw one: the animation
## state ([member ZzZombieBody.anim]) and the flags (burning, enraged, startled). Server
## authoritative and never predicted, for dot-npc's reason: a zombie's position comes out of a
## graph, a brain and a crowd, none of which a client could reproduce, so the client draws it
## a few ticks in the past and is never corrected.
##
## [b]Its kind and its variant are not here.[/b] They never change, so they travel once, in the
## NPC event that announces it; a per-tick field would send the same sixteen bits forty times a
## second per zombie for ever.

var npc: DotNpcInstance = null

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


func _register_net_vars() -> void:
	for spec in DotNpcNetSync.specs():
		var field := replicate(spec["property"], DotNetVar.Type[spec["type"]])

		if int(spec["bits"]) > 0:
			field.bits(int(spec["bits"]))

		if bool(spec["interpolated"]):
			field.interpolated()

	for spec in DotNpcNetSync.limb_specs():
		replicate(spec["property"], DotNetVar.Type[spec["type"]]).bits(int(spec["bits"]))

	replicate(&"net_anim", DotNetVar.Type.UINT).bits(5)
	replicate(&"net_flags", DotNetVar.Type.UINT).bits(5)


func pull() -> void:
	if npc == null or not npc.is_alive() or body == null:
		return

	DotNpcNetSync.pull(npc, self, DotNpcNetSync.State.ATTACKING if npc.has_target() else DotNpcNetSync.State.IDLE)
	net_anim = clampi(body.anim, 0, 31)
	net_flags = body.flags & 31
	net_limbs = body.limb_mask & ((1 << DotNpcNetSync.LIMB_BITS) - 1)


func _net_simulate(_tick: int, _delta: float) -> void:
	if identity != null and identity.is_authoritative:
		pull()


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

	DotNpcNetSync.apply(body, self)
