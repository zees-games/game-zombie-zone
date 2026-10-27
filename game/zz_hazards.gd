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
## grenade   a thrown or fired explosive: off on its fuse (resting where it landed), or on contact
##           when it has none, which is a rocket.
## bile      a jar; every common near where it breaks comes to it, for a while.
## [/codeblock]

const ACID := &"acid"
const FIRE := &"fire"
const HEAL := &"heal"

const SPIT := &"spit"
const ROCK := &"rock"
const PIPE := &"pipe"
const SHELL := &"shell"
const MOLOTOV := &"molotov"
const GRENADE := &"grenade"
## A grenade that flies straight and goes off on contact: what a launcher fires.
const ROCKET := &"rocket"
const BILE := &"bile"
## A gravity gun's zap and its pull: drawn from the one announcement (a beam from [code]from[/code] to [code]from + velocity[/code]), never flown.
const BEAM_ZAP := &"beam_zap"
const BEAM_PULL := &"beam_pull"
## The mutant's dive landing: survivors only, unlike [method ZzGame.explode].
const SLAM := &"slam"

## A bile jar draws the horde this far, for this long.
const BILE_LURE := 35.0
const BILE_SECONDS := 15.0

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

## Zombie instance id -> burning until.
var _burning: Dictionary = {}

var _next_id: int = 1

## Ground hazards that hurt by standing in them (acid; the oil monster's goo): dot-effects' pool.
var pool := DotHazardPool.new()

## Hazard kind -> its [DotHazardProfile]; a kind not here is simulated by this file.
var profiles: Dictionary = {ACID: DotHazardProfile.acid()}


func _init(p_game: Object) -> void:
	game = p_game
	pool.id_source = _take_id
	pool.occupants = _occupants
	pool.damage_sink = _pay
	pool.victim_key = _victim_key
	pool.added.connect(_on_pool_added)
	pool.ended.connect(_on_pool_ended)


## Method callables, not lambdas: a lambda capturing self would make this RefCounted and its pool a cycle.
func _occupants(at: Vector3, radius: float, reach: float) -> Array:
	return game.survivors_within(at, radius, reach)


func _pay(player: Object, amount: float, owner: int, kind: StringName) -> void:
	game.hazard_damage(player, amount, owner, kind)


func _victim_key(player: Object) -> Variant:
	return player.player_id


func _on_pool_added(id: int, kind: StringName, at: Vector3, radius: float, seconds: float) -> void:
	var a: Dictionary = pool.areas[id]
	areas[id] = {"kind": kind, "at": at, "radius": radius, "until": a["until"], "since": a["since"],
		"amount": a["amount"], "owner": a["owner"]}
	area_added.emit(id, kind, at, radius, seconds)


func _on_pool_ended(id: int) -> void:
	if areas.erase(id):
		area_ended.emit(id)


func _take_id() -> int:
	_next_id += 1
	return _next_id - 1


## Sets profile keys for a hazard kind from a dot-profile's values or a cvar dump.
func configure(kind: StringName, values: Dictionary) -> void:
	profiles[kind] = DotHazardProfile.from_values(values, profiles.get(kind, DotHazardProfile.new()))


func add(kind: StringName, at: Vector3, radius: float, seconds: float, amount: float, owner: int = 0) -> int:
	if profiles.has(kind):
		return pool.add(profiles[kind], at, game.now(), owner, amount, radius, seconds)

	var id := _take_id()
	areas[id] = {"kind": kind, "at": at, "radius": radius, "until": game.now() + seconds,
		"since": game.now(), "amount": amount, "owner": owner}
	area_added.emit(id, kind, at, radius, seconds)
	return id


## [param fuse] seconds until a GRENADE goes off whatever it is doing (0 or less: on contact),
## [param radius] its blast, [param gravity] a multiple of [constant GRAVITY] (0 flies straight).
func launch(kind: StringName, from: Vector3, velocity: Vector3, owner: int, amount: float,
		fuse: float = -1.0, radius: float = 0.0, gravity: float = 1.0) -> int:
	var id := _next_id
	_next_id += 1
	flying[id] = {"kind": kind, "at": from, "velocity": velocity, "owner": owner, "amount": amount,
		"since": game.now(), "fuse": -1.0, "detonate_at": game.now() + fuse if fuse > 0.0 else -1.0,
		"radius": radius if radius > 0.0 else 4.0, "gravity": gravity, "rest": false}
	launched.emit(id, kind, from, velocity)
	return id


## A beam drawn from [param from] to [param to] for a quarter of a second on every machine.
func beam(kind: StringName, from: Vector3, to: Vector3) -> void:
	var id := _next_id
	_next_id += 1
	launched.emit(id, kind, from, to - from)


## The mutant's dive landing at [param at]: every survivor within [param radius] takes
## [param amount] (less with distance) and is thrown clear.
func slam(at: Vector3, radius: float, amount: float, owner: int) -> int:
	var hit := 0

	for player in game.survivors_within(at, radius, 3.0):
		var falloff := 1.0 - clampf(player.feet().distance_to(at) / radius, 0.0, 0.7)
		game.knock_survivor(player.player_id, at, amount * falloff, owner)
		hit += 1

	game.exploded.emit(at, radius, SLAM)
	return hit


## A shell called down on [param at]: it falls for [param delay] seconds and goes off.
func strike(at: Vector3, delay: float, amount: float, owner: int = 0) -> int:
	var from := at + Vector3(0.0, GRAVITY * delay * delay * 0.5, 0.0)
	return launch(SHELL, from, Vector3.ZERO, owner, amount)


func tick(delta: float) -> void:
	pool.tick(game.now(), delta)
	_advance_flying(delta)
	_advance_areas(delta)
	_advance_burning(delta)


func _advance_flying(delta: float) -> void:
	for id: int in flying.keys():
		var p: Dictionary = flying[id]

		# A fused grenade goes off on time, in the air or on the ground.
		if float(p.get("detonate_at", -1.0)) >= 0.0 and game.now() >= float(p["detonate_at"]):
			flying.erase(id)
			game.explode(p["at"], float(p["radius"]), float(p["amount"]), int(p["owner"]), p["kind"], 0.5)
			continue

		if bool(p.get("rest", false)):
			continue

		# A pipe on the ground: beeping, then a bang.
		if float(p["fuse"]) >= 0.0:
			p["fuse"] = float(p["fuse"]) - delta

			if float(p["fuse"]) <= 0.0:
				flying.erase(id)
				game.explode(p["at"], 6.0, float(p["amount"]), int(p["owner"]), PIPE, 0.0)
			continue

		var from: Vector3 = p["at"]
		var velocity: Vector3 = p["velocity"]
		velocity.y -= GRAVITY * float(p.get("gravity", 1.0)) * delta
		var to := from + velocity * delta
		p["velocity"] = velocity

		if p["kind"] == ROCK:
			var victim: StringName = game.survivor_near_segment(from, to, ROCK_HIT_RADIUS)

			if victim != &"":
				flying.erase(id)
				game.rock_hit(victim, to, float(p["amount"]), int(p["owner"]))
				landed.emit(id, ROCK, to)
				continue

		# A rocket goes off on the first zombie it meets, not on the wall behind the crowd: the
		# world ray does not see zombies.
		if p["kind"] == ROCKET and game.horde != null and not game.horde.spawner.npcs_near(to + Vector3(0.0, -1.0, 0.0), 1.1).is_empty():
			_land(id, p, to)
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
		GRENADE, ROCKET:
			if float(p["detonate_at"]) >= 0.0:
				p["at"] = at + Vector3(0.0, 0.1, 0.0)
				p["velocity"] = Vector3.ZERO
				p["rest"] = true
			else:
				flying.erase(id)
				game.explode(at, float(p["radius"]), float(p["amount"]), int(p["owner"]), p["kind"], 0.5)
		BILE:
			flying.erase(id)
			game.horde.bile_at(at, BILE_SECONDS, BILE_LURE)
		PIPE:
			p["at"] = at + Vector3(0.0, 0.1, 0.0)
			p["velocity"] = Vector3.ZERO
			p["fuse"] = PIPE_FUSE
			game.horde.lure(at, PIPE_FUSE, PIPE_LURE)
		_:
			flying.erase(id)


func _advance_areas(delta: float) -> void:
	var now: float = game.now()

	for id: int in areas.keys():
		var a: Dictionary = areas[id]

		if profiles.has(a["kind"]):
			continue

		if float(a["until"]) <= now:
			areas.erase(id)
			area_ended.emit(id)
			continue

		var at: Vector3 = a["at"]
		# A pool spreads over its first second rather than appearing whole.
		var radius: float = float(a["radius"]) * clampf((now - float(a["since"])) / 1.0, 0.2, 1.0)

		match a["kind"]:
			FIRE:
				for player in game.survivors_within(at, radius, 1.0):
					game.hazard_damage(player, float(a["amount"]) * delta, int(a["owner"]), FIRE)
					player.burning_until = maxf(player.burning_until, now + 0.6)

				for npc in game.horde.spawner.npcs_near(at, radius + 0.4):
					_burning[npc.instance_id] = now + AFTERBURN
			HEAL:
				for player in game.survivors_within(at, radius, 1.0):
					var _healed: float = player.heal_real(float(a["amount"]) * delta)



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
	pool.clear()

	for id: int in areas.keys():
		area_ended.emit(id)

	areas.clear()
	flying.clear()
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
