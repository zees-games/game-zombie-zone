extends RefCounted
## `headless_native_brains`' steer snapshot: what a steer leaves on a common's body, character, brain and path,
## read before and after so the script and native steers start from, and are compared on, the same state.

const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")


## What a steer leaves behind: the body's transform and wish, the character's turn, the brain's cruise and watch.
static func take(brain: Object) -> Array:
	var b: ZzZombieBody = brain.npc.node
	var c: DotNpcAiCharacter = brain.character
	var rough: float = brain.path.rough_until if brain.path != null else 0.0
	var index: int = brain.path.index if brain.path != null else -99
	var st := [b.global_transform, b.wish, c._peak_turn, c._over_amt, c._over_axis, c._turns, brain._cruise_to,
		brain._cruise_dest, brain._progress_at, brain._progress_since, rough, index, brain._waypoint]
	# The rest of the path: a stuck steer goes rough (its points dropped, its arrive radius cut), and a due one's
	# search reads is_rough, which puts the radius back.
	var p: DotNpcPath = brain.path
	if p != null:
		st.append_array([p.points.duplicate(), p.arrive_radius, p._arrive_before, p.computed_at, p.goal_at_compute,
			p.partial])
	return st


## Puts back what [method take] read, so the native steer starts where the script's did.
static func put(brain: Object, st: Array) -> void:
	var b: ZzZombieBody = brain.npc.node
	var c: DotNpcAiCharacter = brain.character
	b.global_transform = st[0]
	b.wish = st[1]
	c._peak_turn = st[2]
	c._over_amt = st[3]
	c._over_axis = st[4]
	c._turns = st[5]
	brain._cruise_to = st[6]
	brain._cruise_dest = st[7]
	brain._progress_at = st[8]
	brain._progress_since = st[9]
	if brain.path != null:
		brain.path.rough_until = st[10]
		brain.path.index = st[11]
		brain.path.points = (st[13] as PackedVector3Array).duplicate()
		brain.path.arrive_radius = st[14]
		brain.path._arrive_before = st[15]
		brain.path.computed_at = st[16]
		brain.path.goal_at_compute = st[17]
		brain.path.partial = st[18]
	brain._waypoint = st[12]
