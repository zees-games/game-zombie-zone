extends "res://npcs/zz_zombie_brain.gd"

## headless_native_brains: a zombie brain whose think is a seeded stand-in, so the spawner's think pacing can be
## checked against the zombie's own tick counting ([method _npc_think], [method think_paced], [method _pace_take],
## [method _pace_give]) with staggers, possessions, removals and spawns mid-tick. Every thought and driven tick goes
## to the spawner's `pace_log` meta.

var thoughts: int = 0


func _npc_ready() -> void:
	pass


func _npc_unbound() -> void:
	pass


func _npc_driven(delta: float) -> void:
	_log(["driven", npc.seed, director.now(), delta])


func _think_every() -> int:
	return 1 + absi(hash([npc.seed, thoughts])) % 6


## What [method stagger] does to the pacing, without a body to shove.
func probe_stagger() -> void:
	_every = 1

	if has_method(&"pace_every"):
		call(&"pace_every", 1)


func _think_now(delta: float) -> void:
	thoughts += 1
	_log(["think", npc.seed, director.now(), delta])
	var others: Array = director.call(&"all_npcs")
	var other: DotNpcInstance = others[absi(hash([npc.seed, thoughts, 3])) % others.size()]

	if other == npc or other.brain == null:
		return

	match absi(hash([npc.seed, thoughts, 7])) % 40:
		0, 1, 2:
			other.brain.probe_stagger()
			_log(["stagger", npc.seed, other.seed])
		3:
			if other.brain.drive == null:
				var held := DotNpcDrive.new()
				held.grab(&"p")
				other.brain.drive = held
				_log(["drive", npc.seed, other.seed])
		4, 5:
			if other.brain.drive != null:
				other.brain.drive = null
				_log(["free", npc.seed, other.seed])
		6:
			if int(director.call(&"world_count")) > 8:
				_log(["remove", npc.seed, other.seed])
				director.call(&"remove", other.instance_id)
		7:
			var made: Variant = director.call(&"spawn", npc.def.id, npc.position() + Vector3(0.5, 0, 0.5))
			if made != null:
				_log(["spawn", npc.seed, (made as DotNpcInstance).seed])
		8:
			if drive == null:
				var mine := DotNpcDrive.new()
				mine.grab(&"q")
				drive = mine
				_log(["self-drive", npc.seed])


func _log(entry: Array) -> void:
	var into: Array = director.get_meta(&"pace_log", [])
	into.append(entry)
	director.set_meta(&"pace_log", into)
