extends RefCounted

const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")

## Things that hurt by being somewhere: pools of acid, fire, and the things thrown to make them.
##
## [b]Areas and projectiles, simulated on the server and announced once.[/b] An area is a place,
## a radius and an end time; a projectile is a start, a velocity and gravity. A client is told
## each one ONCE (the bridge relays [signal area_added], [signal launched], [signal exploded])
## and draws it from that, because both are pure functions of their start: an arc is the same
## arc on every machine, and a pool grows the same way. Nothing about them is sent per tick.
##
## [codeblock]
## acid      a spitter's. Hurts survivors more the longer they stand in it; zombies wade through.
## fire      a fire box, a burning car. Hurts everybody; sets zombies alight as they cross it.
## heal      a box's. Survivors inside get health back.
## spit      a glob in flight; an acid pool where it lands.
## rock      a brute's throw. Hits the first survivor near its path; breaks where it lands.
## pipe      a beeping charge. Every common near it goes to it; then it goes off.
## shell     falls out of the sky where it was called, a second later, and goes off.
## molotov   a bottle; fire where it lands.
## [/codeblock]

const ACID := &"acid"
const FIRE := &"fire"
const HEAL := &"heal"

const SPIT := &"spit"
const ROCK := &"rock"
const PIPE := &"pipe"
const SHELL := &"shell"
const MOLOTOV := &"molotov"

const GRAVITY := 18.0

## A rock hits a survivor whose middle passes this close to it.
const ROCK_HIT_RADIUS := 1.3

## A pipe charge beeps this long, and lures this far, before it goes off.
const PIPE_FUSE := 6.0
const PIPE_LURE := 40.0

## Seconds a zombie keeps burning once it has left the fire.
const AFTERBURN := 4.0
const BURN_DPS := 18.0

signal area_added(id: int, kind: StringName, at: Vector3, radius: float, seconds: float)
signal area_ended(id: int)
signal launched(id: int, kind: StringName, from: Vector3, velocity: Vector3)
signal landed(id: int, kind: StringName, at: Vector3)
signal exploded(at: Vector3, radius: float, kind: StringName)

## The game (`zz_game.gd`), untyped: it preloads this file.
var game = null

## id -> {kind, at, radius, until, since, amount, owner}
var areas: Dictionary = {}

## id -> {kind, at, velocity, owner, amount, since, fuse}
var flying: Dictionary = {}

## Survivor id -> seconds stood in acid without leaving, for the ramp.
var _in_acid: Dictionary = {}

## Zombie instance id -> burning until.
var _burning: Dictionary = {}

var _next_id: int = 1


func _init(p_game: Object) -> void:
	game = p_game


func add(kind: StringName, at: Vector3, radius: float, seconds: float, amount: float, owner: int = 0) -> int:
	var id := _next_id
	_next_id += 1
	areas[id] = {"kind": kind, "at": at, "radius": radius, "until": game.now() + seconds,
		"since": game.now(), "amount": amount, "owner": owner}
	area_added.emit(id, kind, at, radius, seconds)
	return id


func launch(kind: StringName, from: Vector3, velocity: Vector3, owner: int, amount: float) -> int:
	var id := _next_id
	_next_id += 1
	flying[id] = {"kind": kind, "at": from, "velocity": velocity, "owner": owner, "amount": amount,
		"since": game.now(), "fuse": -1.0}
	launched.emit(id, kind, from, velocity)
	return id


## A shell called down on [param at]: it falls for [param delay] seconds and goes off.
func strike(at: Vector3, delay: float, amount: float, owner: int = 0) -> int:
	var from := at + Vector3(0.0, GRAVITY * delay * delay * 0.5, 0.0)
	return launch(SHELL, from, Vector3.ZERO, owner, amount)


func tick(delta: float) -> void:
	_advance_flying(delta)
	_advance_areas(delta)
	_advance_burning(delta)


func _advance_flying(delta: float) -> void:
	for id: int in flying.keys():
		var p: Dictionary = flying[id]

		# A pipe on the ground: beeping, then a bang.
		if float(p["fuse"]) >= 0.0:
			p["fuse"] = float(p["fuse"]) - delta

			if float(p["fuse"]) <= 0.0:
				flying.erase(id)
				game.explode(p["at"], 6.0, float(p["amount"]), int(p["owner"]), PIPE, 0.0)
			continue

		var from: Vector3 = p["at"]
		var velocity: Vector3 = p["velocity"]
		velocity.y -= GRAVITY * delta
		var to := from + velocity * delta
		p["velocity"] = velocity

		if p["kind"] == ROCK:
			var victim: StringName = game.survivor_near_segment(from, to, ROCK_HIT_RADIUS)

			if victim != &"":
				flying.erase(id)
				game.rock_hit(victim, to, float(p["amount"]), int(p["owner"]))
				landed.emit(id, ROCK, to)
				continue

		var hit: Vector3 = game.ray_hit(from, to)

		if hit == Vector3.INF and float(p["since"]) + 8.0 > game.now():
			p["at"] = to
			continue

		var at := hit if hit != Vector3.INF else to
		_land(id, p, at)


func _land(id: int, p: Dictionary, at: Vector3) -> void:
	landed.emit(id, p["kind"], at)

	match p["kind"]:
		SPIT:
			flying.erase(id)
			var _a := add(ACID, at, 3.2, 7.0, float(p["amount"]), int(p["owner"]))
		MOLOTOV:
			flying.erase(id)
			var _f := add(FIRE, at, 4.0, 12.0, float(p["amount"]), int(p["owner"]))
		ROCK:
			flying.erase(id)
			game.explode(at, 2.5, 10.0, int(p["owner"]), ROCK, 1.0)
		SHELL:
			flying.erase(id)
			game.explode(at, 7.0, float(p["amount"]), int(p["owner"]), SHELL, 0.6)
		PIPE:
			p["at"] = at + Vector3(0.0, 0.1, 0.0)
			p["velocity"] = Vector3.ZERO
			p["fuse"] = PIPE_FUSE
			game.horde.lure(at, PIPE_FUSE, PIPE_LURE)
		_:
			flying.erase(id)


func _advance_areas(delta: float) -> void:
	var now: float = game.now()
	var in_acid_now := {}

	for id: int in areas.keys():
		var a: Dictionary = areas[id]

		if float(a["until"]) <= now:
			areas.erase(id)
			area_ended.emit(id)
			continue

		var at: Vector3 = a["at"]
		# A pool spreads over its first second rather than appearing whole.
		var radius: float = float(a["radius"]) * clampf((now - float(a["since"])) / 1.0, 0.2, 1.0)

		match a["kind"]:
			ACID:
				for player in game.survivors_within(at, radius, 1.2):
					var stood: float = float(_in_acid.get(player.player_id, 0.0)) + delta
					in_acid_now[player.player_id] = stood
					# Two a second at first, the full amount after two seconds of standing in it.
					var rate := lerpf(2.0, float(a["amount"]) * 4.0, clampf(stood / 2.0, 0.0, 1.0))
					game.hazard_damage(player, rate * delta, int(a["owner"]), ACID)
			FIRE:
				for player in game.survivors_within(at, radius, 1.0):
					game.hazard_damage(player, float(a["amount"]) * delta, int(a["owner"]), FIRE)
					player.burning_until = maxf(player.burning_until, now + 0.6)

				for npc in game.horde.spawner.npcs_near(at, radius + 0.4):
					_burning[npc.instance_id] = now + AFTERBURN
			HEAL:
				for player in game.survivors_within(at, radius, 1.0):
					var _healed: float = player.heal_real(float(a["amount"]) * delta)

	_in_acid = in_acid_now


func _advance_burning(delta: float) -> void:
	if _burning.is_empty():
		return

	var now: float = game.now()

	for instance_id: int in _burning.keys():
		var npc: DotNpcInstance = game.horde.spawner.get_npc(instance_id)

		if npc == null or not npc.is_alive():
			_burning.erase(instance_id)
			continue

		var body := npc.node as ZzZombieBody
		var on := float(_burning[instance_id]) > now
		body.set_flag(ZzZombieBody.FLAG_BURNING, on)

		if not on:
			_burning.erase(instance_id)
			continue

		# The brute burns slower: it is meant to be lit and then run from.
		var rate := BURN_DPS * (0.5 if npc.def.id == &"brute" else 1.0)
		game.burn_zombie(npc, rate * delta)


## Sets [param npc] alight for [param seconds].
func ignite(npc: DotNpcInstance, seconds: float = AFTERBURN) -> void:
	if npc != null and npc.is_alive():
		_burning[npc.instance_id] = maxf(float(_burning.get(npc.instance_id, 0.0)), game.now() + seconds)


func clear() -> void:
	for id: int in areas.keys():
		area_ended.emit(id)

	areas.clear()
	flying.clear()
	_in_acid.clear()
	_burning.clear()


## A pipe charge's position while it beeps, for the client's sound and the HUD.
func pipes() -> Array[Vector3]:
	var out: Array[Vector3] = []

	for id: int in flying:
		var p: Dictionary = flying[id]
		if p["kind"] == PIPE and float(p["fuse"]) >= 0.0:
			out.append(p["at"])

	return out


func describe() -> Dictionary:
	return {"areas": areas.size(), "flying": flying.size(), "burning": _burning.size()}
