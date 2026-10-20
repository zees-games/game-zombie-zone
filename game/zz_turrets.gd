extends RefCounted

## Sentry turrets a box deploys: the server's, announced once and fired from there.
##
## [b]The decision is dot-combat's [DotSentry]; this file is the rules.[/b] Where a turret may
## stand ([method deploy] asks [method DotSentry.find_spot]), how many a survivor may have out,
## what it shoots (the horde, never a survivor: it has no friendly fire to be wrong about), and
## how a shot becomes damage (the same dot-combat path as a survivor's, credited to its owner, so
## the score, the drop and the body falling are not a second implementation).
##
## A client is told three things and draws from them: [signal placed] (where, which way, for how
## long), [signal fired] (at what point, for the muzzle flash and the barrel's yaw) and
## [signal ended]. Nothing is sent per tick.

const CHANNEL := "zz.turrets"

## What a turret does when the box's action leaves a number out.
const DEFAULTS := {"seconds": 40.0, "ammo": 220, "damage": 14.0, "reach": 20.0, "interval": 0.14}

## Per survivor; a third turns the oldest one off rather than refusing the box.
const MAX_PER_OWNER := 2

## Muzzle-to-chest, so a shot lands on the body and not the feet.
const CHEST := Vector3(0.0, 1.1, 0.0)

signal placed(id: int, at: Vector3, yaw: float, seconds: float)
signal fired(id: int, target: Vector3)
signal ended(id: int)

## The game (`zz_game.gd`), untyped: it preloads this file.
var game = null

## id -> {sentry: DotSentry, owner: int (entity), owner_key: StringName, damage: float}
var turrets: Dictionary = {}

var _next_id: int = 1


func _init(p_game: Object) -> void:
	game = p_game


## Puts a turret where [param player] is looking, or at their feet when that spot is no good.
## Returns the id, or 0 with [param why] saying what was wrong (a [DotResult] failure's detail).
func deploy(player, params: Dictionary) -> DotResult:
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state if game.get_world_3d() != null else null

	if space == null:
		return DotResult.fail(DotError.CODE_STATE, "No world to stand it in.")

	var eye: Vector3 = player.feet() + Vector3(0.0, 1.5, 0.0)
	var facing := Vector3(-sin(deg_to_rad(player.controller.state.yaw)), 0.0, -cos(deg_to_rad(player.controller.state.yaw)))
	var mask: int = game.world_mask()
	var spot := DotSentry.find_spot(space, eye, facing, mask, 2.2)

	if not spot.ok:
		spot = DotSentry.find_spot(space, eye, Vector3.DOWN + facing * 0.01, mask, 0.4)

	if not spot.ok:
		return spot.wrap("A turret cannot stand there.")

	var at: Vector3 = spot.value["position"]
	var seconds := float(params.get("seconds", DEFAULTS["seconds"]))
	var sentry := DotSentry.new(at, game.now(), deg_to_rad(player.controller.state.yaw))
	sentry.lifetime = seconds
	sentry.ammo = int(params.get("ammo", DEFAULTS["ammo"]))
	sentry.reach = float(params.get("reach", DEFAULTS["reach"]))
	sentry.interval = float(params.get("interval", DEFAULTS["interval"]))
	sentry.muzzle_height = 0.85
	_make_room(player.entity_id)

	var id := _next_id
	_next_id += 1
	turrets[id] = {"sentry": sentry, "owner": player.entity_id, "owner_key": player.player_id,
		"damage": float(params.get("damage", DEFAULTS["damage"]))}
	placed.emit(id, at, sentry.yaw, seconds)
	DotLog.info(CHANNEL, "a turret was deployed", {"by": String(player.player_id), "at": at})
	return DotResult.success(id)


func tick(delta: float) -> void:
	if turrets.is_empty():
		return

	var now: float = game.now()

	for id: int in turrets.keys():
		var t: Dictionary = turrets[id]
		var sentry: DotSentry = t["sentry"]

		if sentry.expired(now):
			remove(id)
			continue

		var candidates := _candidates(sentry)
		var shot := sentry.step(delta, now, candidates, game.clear_between)

		if shot.is_empty():
			continue

		_hit(t, shot["fire"], shot["to"])
		fired.emit(id, shot["to"])


func remove(id: int) -> void:
	if turrets.erase(id):
		ended.emit(id)


func clear() -> void:
	for id: int in turrets.keys():
		ended.emit(id)

	turrets.clear()


func count_for(owner: int) -> int:
	var n := 0

	for id: int in turrets:
		if int(turrets[id]["owner"]) == owner:
			n += 1

	return n


func _make_room(owner: int) -> void:
	while count_for(owner) >= MAX_PER_OWNER:
		var oldest := 0

		for id: int in turrets:
			if int(turrets[id]["owner"]) == owner and (oldest == 0 or id < oldest):
				oldest = id

		remove(oldest)


func _candidates(sentry: DotSentry) -> Array:
	var out: Array = []

	if game.horde == null:
		return out

	for npc in game.horde.zombies_near(sentry.position, sentry.reach):
		var entity: int = game.horde.entity_id_for(npc)

		if entity != 0:
			out.append({"id": entity, "at": npc.position() + CHEST})

	return out


func _hit(t: Dictionary, target: Dictionary, point: Vector3) -> void:
	var victim := int(target["id"])
	var hit := DotDamage.make(int(t["owner"]), victim, float(t["damage"]), game.combat.damage_type(&"strike"))
	hit.point = point
	hit.direction = (point - (t["sentry"] as DotSentry).muzzle()).normalized()
	hit.tick = int(float(game.now()) * float(game.tick_rate))
	hit.weapon_id = &"turret"
	var _applied: Variant = game.combat.apply_damage(hit)


func describe() -> Dictionary:
	var rows: Array = []

	for id: int in turrets:
		rows.append({"id": id, "owner": String(turrets[id]["owner_key"]), "sentry": (turrets[id]["sentry"] as DotSentry).describe()})

	return {"turrets": rows}
