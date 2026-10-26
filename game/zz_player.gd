extends CharacterBody3D

const ZzWeapons := preload("zz_weapons.gd")
const ZzConfig := preload("zz_config.gd")
const ZzController := preload("zz_controller.gd")
const ZzWaterRules := preload("zz_water_rules.gd")
const ZzFigure := preload("zz_figure.gd")
const ZzAvatars := preload("zz_avatars.gd")

## One survivor: how they move, how hurt they are, whether they are up, down, held or dead, and
## what they are carrying.
##
## [b]Down is not dead, and the third time is.[/b] At zero health a survivor goes down instead of
## dying: the same [DotHealth] is revived at once with a bleed-out pool for a maximum, the DOWN
## modifier holds them where they fell, and they can still shoot what they hold. Damage while
## down comes off the pool; the pool running out is death. Somebody holding E over them for
## [member ZzConfig.revive_seconds] stands them up with a little temporary health. After
## [member ZzConfig.max_incaps] downs the next zero is death, and the screen has been saying so
## since the last one.
##
## [b]Temporary health is part of the health, and comes off first.[/b] What a bottle of pills or
## a revive gives is added to [member DotHealth.health] and remembered in [member temp_health];
## it drains by itself, and any damage taken comes off it before the real thing. One number for
## dot-combat to subtract from, and one for this file to know how much of it is borrowed.
##
## [b]Pinned is a person, not a flag.[/b] [member pinned_by] is the entity id of the special
## holding them and [member pin_kind] what it is doing (pounce, choke, carry, ride). The PINNED
## modifier holds them on both ends; what frees them is the special dying, a teammate's shove,
## or — for the ones that let go — the special deciding to.

const EYE_HEIGHT := 1.6
const EYE_DOWN := 0.45

const BODY_RADIUS := 0.35
const BODY_HEIGHT := 1.8
const BODY_CROUCH := 0.95
## Above the 0.42 m rise of a converted map's stairs, so walking up one does not wait on a hop.
const BODY_STEP := 0.45

## Where a survivor is in their life this map.
enum Life { UP, DOWN, DEAD }

@export var player_id: StringName = &"local"
@export var display_name: String = "Player"
@export var samples_input: bool = false
@export var is_bot: bool = false

## What this player looks like, as a dot-user-avatar document; null is the stock person.
var avatar: DotAvatar = null

var config: ZzConfig = null

var controller: ZzController = null
var sampler: DotFpsSampler = null
var health: DotHealth = null
var hitboxes: DotHitboxSet = null
var weapons: ZeeWeaponRig = null

## Always the survivors, today; kept so the scoreboard and the chat's team channel have a side.
var team: int = 1

var points: int = 0
var ping_ms: int = -1
var entity_id: int = 0

## How many times the server has PUT this player somewhere. Replicated, so a watcher's
## interpolator draws a teleport as one rather than as a flight across the map.
var warps: int = 0

## Sitting this map out, having joined after it started or died without a rescue.
var watching: bool = false

var life: int = Life.UP

## Times down this map. At [member ZzConfig.max_incaps] the next one is death.
var incaps: int = 0

## Borrowed health, already inside [member DotHealth.health]. See the class notes.
var temp_health: float = 0.0

## The special holding them, as an entity id, and what it is doing. 0 / empty when free.
var pinned_by: int = 0
var pin_kind: StringName = &""

## What they carry besides weapons.
var medkits: int = 0
var pills: int = 0
## Charges left in the defibrillator they carry (0: none), the time it is next ready (server), and
## the time until which they cannot be hurt after being shocked back (server).
var defibs: int = 0
var defib_ready_at: float = 0.0
var shield_until: float = -1.0

## The boxes in their hands, by type (server), and what everybody sees of them: how many, and
## which as an index into the box file's order plus one (0: none, or unknown because
## `box_labels` is off). See [ZzBoxes].
var carried: Array[StringName] = []
var carried_count: int = 0
var carried_index: int = 0
## Whether the box is in the hands (the gun is put away, primary fire deploys), replicated; the
## slot the player had asked for when it came out, server side: asking for another puts it away.
var box_out: bool = false
var box_slot: int = 0
var previous_fire: bool = false

## Where they stood when they began deploying a box, which they may drift from by only so far.
var use_origin: Vector3 = Vector3.ZERO

## Holding E on something: what (`revive`, `heal`, `box`, `objective`, `item`), whom or which,
## since when (simulated seconds) and for how long it takes. Server side; the fraction is
## replicated to the owner and to whoever is being revived.
var using: StringName = &""
var use_target: int = -1
var use_started: float = 0.0
var use_needs: float = 0.0

## 0..1 of the way through whatever they are holding E for, as the wire carries it.
var use_fraction: float = 0.0

## Being revived or healed by somebody, 0..1. For the downed person's own screen.
var helped_fraction: float = 0.0

## Simulated seconds when they may next shove, and how many they have shoved in a row.
var shove_ready_at: float = 0.0
var shove_streak: int = 0

## Covered in bile until, and burning until, in simulated seconds. Server side; replicated as
## two flags.
var biled_until: float = -1.0
var burning_until: float = -1.0

## Replicated flags for the two above, on a client.
var biled: bool = false
var burning: bool = false

## A box's flash: their screen white. Set from the box effects on the server, replicated.
var box_blind: bool = false

## When they died, for the rescue clock. Simulated seconds.
var died_at: float = -1.0

## When a timed respawn returns them (server, simulated seconds); -1 for none. And until when
## they cannot be hurt after one.
var respawn_at: float = -1.0
var protected_until: float = -1.0

## What they did this map, for the scoreboard and the end-of-map card.
var commons_killed: int = 0
var specials_killed: int = 0
var revives_done: int = 0
var damage_taken_map: float = 0.0
var friendly_damage: float = 0.0

## Seconds this player has been in the game this session (server): the floor under their
## playtime when progress is not kept.
var session_seconds: float = 0.0

## Which weapon slot they have asked for, from this game's input message.
var wanted_slot: int = 0

## What their hands are doing this tick and did last tick: `ZzNetCommand.ACT_*` bits, and the
## shove button. Server side; a press is the difference between the two.
var actions: int = 0
var previous_actions: int = 0
var shove_held: bool = false
var previous_shove: bool = false

## An administrator's `blind` and `beacon`, as dot-moderation's tools set them.
var blinded: bool = false
var beacon: bool = false
var beacon_marker: DotFxBeacon = null

## Whether the end-of-map logic has them inside the end area right now.
var in_end_area: bool = false

## What other people see this player as. Client side.
var figure: ZzFigure = null

## How this survivor's body falls on their death: the server's pick ([method ZzGame.decide_death]),
## carried on DEATH and set here before anybody hears of it. Null before a first death.
var death: DotPlayerDeath = null

## Remote weapon state, for drawing a gun in a watched survivor's hand. See mg-deathrun.
var mirrored: bool = false
var dealt: Array[StringName] = []
var dealt_round: int = -1
var mirror_slot: int = 0
var mirror_switching: bool = false
var mirror_fired: int = 0
var mirror_fire_kind: int = 0
var _seen_fire_seq: int = -1
static var _slots: Dictionary = {}

## The rig the client playing this survivor draws their gun with (`ZzClient.weapons`); null on
## every other machine and for everybody else. Its magazine is what the HUD counts, so it is
## corrected from the server's (see [method correct_view_rig]).
var view_rig: ZeeWeaponRig = null

## Simulated seconds [member view_rig] has gone without a trigger, a reload or a switch.
var _view_rig_quiet: float = 0.0

## How long the drawn gun must be quiet before the server's count may overwrite it: longer than
## a shot takes to reach the server and its snapshot to come back, so a correction never undoes
## a shot the server has not heard of yet.
const VIEW_RIG_SETTLE_SEC := 0.6

## Offline only: puts the client's buttons on the command [member sampler] has just made.
##
## [b]Stamped after sampling, inside [method simulate], never on the command before it.[/b] The
## client used to stamp `controller.current_command` from its own physics frame, and then this
## file's [method simulate] replaced that command with a fresh sample: fire and reload never
## reached the world's rig, so offline the HUD's 15 / 60 never moved and nothing you shot was hit.
var command_stamp: Callable = Callable()

# --- Water --------------------------------------------------------------------

## How deep in water: none, the feet (below the waist: wading), the waist (swimming) or the eyes
## (under: the breath runs out). Source's four levels, and the same names here.
enum WaterLevel { NONE, FEET, WAIST, EYES }

## The map's water volumes this player moves through, world space (see [method set_water]).
var water: Array[AABB] = []

## This player's swimming mode (dot-player-controller's DotFpsSwimMode), one per player in
## `controller.extra_modes` so a style's rebuilt motor keeps it under the same id on every machine.
var swim: DotFpsSwimMode = DotFpsSwimMode.new()

## Breath left, in seconds under water; refilled with the head out. Each end counts its own
## from its own copy of the water: the server's decides the damage, the client's is the HUD's
## bar, and neither is on the wire.
var air: float = 12.0

## Whether the eyes are under water now, as of the last tick.
var submerged: bool = false

## The level as of the last simulated tick.
var water_level: int = WaterLevel.NONE

var tick_rate: int = 64:
	set(value):
		tick_rate = value
		if controller != null:
			controller.tick_rate = value

## The key dot-weapon's player bridge identifies this carrier by.
var player_key: String:
	get:
		return String(player_id)


func _ready() -> void:
	controller = ZzController.new()
	controller.name = "Controller"
	controller.tick_rate = tick_rate
	# EXTERNAL even offline: the world owns the tick, which is the shape a dedicated server
	# needs and the one a predicting client replays.
	controller.drive = DotFpsController.Drive.EXTERNAL
	controller.tunables = tunables_for(config)
	controller.admin_abilities = true
	controller.extra_modes = [swim]
	add_child(controller)
	controller.simulated.connect(_on_simulated)
	controller.before_fn = _before_tick

	if samples_input:
		sampler = DotFpsSampler.new(controller.tunables)
		register_actions(sampler)


## Hands over the map's water, [param boxes] (empty: none), and the rules that tune it.
func set_water(boxes: Array[AABB], rules: ZzWaterRules) -> void:
	water = boxes
	swim.volumes = boxes
	swim.swim_speed = rules.swim_speed if rules != null else 4.4

	if controller != null:
		controller.set_wade_scale(rules.wade_scale if rules != null else 0.8)

		if boxes.is_empty() and controller.motor != null and controller.state != null \
				and controller.state.mode == swim.mode_id:
			controller.motor.set_mode(controller.state, DotFpsState.Mode.AIR)

	air = rules.drown_seconds if rules != null else 12.0


## The level of [param feet] in this player's water: the feet a hand's breadth up, the waist where
## the swim mode puts it, the eyes where [param eye] is. A question of the box list alone, so a
## replayed tick and a server tick give one answer.
func level_at(feet: Vector3, eye: Vector3) -> int:
	var boxes := water

	if boxes.is_empty():
		return WaterLevel.NONE

	var out := WaterLevel.NONE

	for box in boxes:
		if box.has_point(eye):
			return WaterLevel.EYES

		if box.has_point(feet + Vector3.UP * swim.waist):
			out = maxi(out, WaterLevel.WAIST)
		elif box.has_point(feet + Vector3.UP * 0.1):
			out = maxi(out, WaterLevel.FEET)

	return out


## Returns the map's mechanics (lifts, doors), or null. Set by the game.
var mechanics_fn: Callable = Callable()


func _before_tick(tick: int) -> void:
	var mech: Variant = mechanics_fn.call() if mechanics_fn.is_valid() else null

	if mech != null:
		mech.pose_at(tick)


## What the ground does to somebody standing on it: a lift or a swinging door carries them, in
## the state, because the next tick starts from `state.position`.
func _ride(tick: int, state: DotFpsState) -> void:
	if state.mode != DotFpsState.Mode.GROUND or state.ground_id == 0 or not mechanics_fn.is_valid():
		return

	var mech: Variant = mechanics_fn.call()

	if mech == null:
		return

	var moved: Vector3 = mech.carry(state.ground_id, state.position, tick)

	if moved != Vector3.ZERO:
		state.position += moved
		global_position = state.position


## A map's push and gravity volumes, in the state so a replayed tick gives the server's answer. A push lifts the velocity along
## its direction to its speed (standing in it adds no more), a gravity volume scales the fall that tick's gravity took.
func _volume_forces(state: DotFpsState) -> void:
	var mech: Variant = mechanics_fn.call() if mechanics_fn.is_valid() else null

	if mech == null or state.mode == DotFpsState.Mode.NOCLIP:
		return

	var tunables := controller.tunables
	var push: Vector3 = mech.push_at(state.position, tunables.stand_height)

	if push != Vector3.ZERO:
		var dir := push.normalized()
		var along := state.velocity.dot(dir)

		if along < push.length():
			state.velocity += dir * (push.length() - along)

			if state.velocity.y > 0.0 and state.mode == DotFpsState.Mode.GROUND:
				controller.motor.set_mode(state, DotFpsState.Mode.AIR)

	var scale: float = mech.gravity_at(state.position, tunables.stand_height)

	if scale != 1.0 and state.mode == DotFpsState.Mode.AIR:
		state.velocity.y += tunables.gravity * (1.0 - scale) / float(maxi(tick_rate, 1))


## Once per simulated tick, after the move, a replay's included: into the water at the waist,
## and the wading slowdown while the feet are wet and the waist is not.
func _on_simulated(tick: int, state: DotFpsState) -> void:
	if controller.motor == null:
		return

	_ride(tick, state)
	_volume_forces(state)

	swim.update(controller.motor, state)
	water_level = level_at(state.position, eye_position())
	submerged = water_level == WaterLevel.EYES
	# Waist-deep water too shallow to float in is waded too (DotFpsSwimMode.has_room_to_float).
	var wading := water_level != WaterLevel.NONE and state.mode != swim.mode_id
	var has := controller.motor.has_modifier(state, ZzController.WADING)

	if wading and not has:
		var _on := controller.motor.add_modifier(state, ZzController.WADING)
	elif not wading and has:
		var _off := controller.motor.remove_modifier(state, ZzController.WADING)


## One tick of breath, from the level the last tick ended at. Returns the damage owed, in health
## per second times [param delta]: 0 while there is air. [param rules] says how long a breath is.
func breathe(delta: float, rules: ZzWaterRules) -> float:
	var full := maxf(rules.drown_seconds, 0.001)

	if not submerged or rules.drown_seconds <= 0.0:
		air = minf(full, air + delta * rules.air_refill)
		return 0.0

	air = maxf(air - delta, 0.0)
	return rules.drown_damage * delta if air <= 0.0 else 0.0


## How a survivor moves. Static: a connected client builds a sampler before it has a player, and
## the two must agree.
static func tunables_for(p_config: ZzConfig) -> DotFpsTunables:
	var t := DotFpsTunables.new()
	t.max_speed = p_config.run_speed if p_config != null else 6.2
	t.gravity = p_config.gravity if p_config != null else 20.0
	t.jump_height = p_config.jump_height if p_config != null else 1.1
	t.auto_hop = false
	t.walk_speed_scale = p_config.walk_speed_scale if p_config != null else 0.45
	t.can_walk = true
	t.can_sprint = false
	t.can_crouch = true
	t.crouch_speed_scale = 0.45
	t.accelerate = 10.0
	t.friction = 6.0
	t.stop_speed = 2.5
	t.air_accelerate = p_config.air_accelerate if p_config != null else 12.0
	t.max_air_wish_speed = 1.2
	t.coyote_time = 0.1
	t.jump_buffer_time = 0.12
	t.max_slope_angle = 46.0
	t.radius = BODY_RADIUS
	t.stand_height = BODY_HEIGHT
	t.crouch_height = BODY_CROUCH
	t.step_height = BODY_STEP
	return t


## The movement actions, and the slow walk on shift.
static func register_actions(p_sampler: DotFpsSampler = null) -> void:
	var _added := DotFpsSampler.register_default_actions(p_sampler)
	var crouch := &"dot_fps_crouch"

	# C beside Ctrl: Ctrl is a browser shortcut and a window manager's on some desktops.
	if InputMap.has_action(crouch) and not _has_key(crouch, KEY_C):
		var c := InputEventKey.new()
		c.physical_keycode = KEY_C
		InputMap.action_add_event(crouch, c)

	var walk := &"dot_fps_walk"

	if not InputMap.has_action(walk):
		return

	for event in InputMap.action_get_events(walk):
		var key := event as InputEventKey
		if key != null and key.physical_keycode == KEY_SHIFT:
			return

	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	InputMap.action_add_event(walk, shift)


static func _has_key(action: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null and key.physical_keycode == keycode:
			return true

	return false


## One simulated tick. On the server and offline; a client predicts through its behaviour.
func simulate(tick: int, delta: float) -> void:
	# The world calls this by name, so a body the load gate froze is skipped here.
	if is_inside_tree() and not can_process():
		return

	if sampler != null:
		# Settling under the cover runs the body with its input off (falls, lands, no keys).
		var gate := DotLoadGate.of(self) if is_inside_tree() else null
		var sampled := sampler.sample(delta) if gate == null or gate.is_open() else DotFpsCommand.new()

		if command_stamp.is_valid():
			command_stamp.call(sampled)

		controller.apply_command(sampled)

	step_controller(tick, delta)
	global_position = controller.state.position


## The motor's tick at the weapon's ADS pace while the rig says it is aimed. Server, offline and a
## predicting client all come through here and read the same rig rule, so the prediction agrees.
## The top speed is scaled for the one tick and put back (the tunables are shared, and every
## motor modifier slot is taken: dot-player-controller's admin set fills the 32).
func step_controller(tick: int, delta: float) -> void:
	var rig := weapons if weapons != null else view_rig
	var tunables := controller.tunables
	var scale := rig.ads_move_scale() if rig != null else 1.0

	if tunables == null or scale >= 1.0:
		controller.simulate_tick(tick, delta)
		return

	var kept := tunables.max_speed
	tunables.max_speed = kept * clampf(scale, 0.05, 1.0)
	controller.simulate_tick(tick, delta)
	tunables.max_speed = kept


func delta_for_tick() -> float:
	return 1.0 / float(maxi(tick_rate, 1))


# --- Life -------------------------------------------------------------------

## Not dead. Down counts as alive: they are still in the map, and still a target.
func is_alive() -> bool:
	return life != Life.DEAD and (health == null or health.alive)


func is_up() -> bool:
	return life == Life.UP and is_alive()


func is_down() -> bool:
	return life == Life.DOWN


func is_pinned() -> bool:
	return pinned_by != 0


## Pinned, using something with both hands, or a box in them: the gun does nothing (down, you
## still shoot; and grabbed by the ankle, too, which is the one pin you fight your own way out of).
func is_held() -> bool:
	return (is_pinned() and pin_kind != &"grab") or using != &"" or (box_out and carried_count > 0)


## One tick of [member view_rig] from the client's own buttons, by the same rule the server's rig
## follows (`ZzWeapons.command_for`). [param delta] is the tick's simulated length.
func drive_view_rig(fire: bool, reload: bool, slot: int, tick: int, delta: float, aim: bool = false) -> DotWeaponOutcome:
	if view_rig == null or view_rig.arsenal == null:
		return DotWeaponOutcome.nothing("No drawn rig.")

	var state := controller.state if controller != null else null
	var command := ZzWeapons.command_for(fire, reload, is_held(), state.yaw if state != null else 0.0,
		state.pitch if state != null else 0.0, slot, view_rig.arsenal, aim)
	var outcome := view_rig.simulate_tick(command, tick)
	var arsenal := view_rig.arsenal

	if command.is_pressed(DotWeaponCommand.BUTTON_ATTACK) or command.is_pressed(DotWeaponCommand.BUTTON_RELOAD) \
			or arsenal.is_reloading() or arsenal.is_switching():
		_view_rig_quiet = 0.0
	else:
		_view_rig_quiet += maxf(delta, 0.0)

	return outcome


## Brings [member view_rig]'s count to the server's, once the drawn gun has been quiet long
## enough that the server has heard every shot it fired. True when it changed anything.
##
## [b]The drawn gun predicts, so it can be wrong, and nothing used to put it right.[/b] Shots
## the server refused, an ammo pile, a box, a map's fresh rig: each left the counter on the drawn
## gun's own sum for the rest of the map. Correcting on every snapshot instead would undo the
## shots still in flight and make the counter flicker up while you fire.
func correct_view_rig(magazine: int, reserve: int, slot: int, server_busy: bool) -> bool:
	if view_rig == null or view_rig.arsenal == null or server_busy:
		return false

	var arsenal := view_rig.arsenal
	var held := arsenal.current()

	if held == null or slot != arsenal.current_slot() or _view_rig_quiet < VIEW_RIG_SETTLE_SEC:
		return false

	var changed := false

	if held.def.uses_magazine() and held.magazine != magazine:
		held.magazine = clampi(magazine, 0, held.def.magazine)
		changed = true

	if held.def.ammo_type != &"" and not held.def.infinite_reserve and arsenal.ammo().count(held.def.ammo_type) != reserve:
		arsenal.ammo().set_count(held.def.ammo_type, reserve)
		changed = true

	return changed


## Up, free, and not holding E on anything: able to do things with their hands.
func can_act() -> bool:
	return is_up() and not is_pinned() and not watching


## Whether the next down is death: what the black-and-white screen says.
func on_last_life() -> bool:
	return config != null and incaps >= config.max_incaps


## Real health: what is left once the borrowed part is taken out.
func real_health() -> float:
	return maxf((health.health if health != null else 0.0) - temp_health, 0.0)


## Health as the HUD shows it, 0..1 of the maximum, real and borrowed together.
func health_fraction() -> float:
	if health == null:
		return 0.0

	return clampf(health.health / maxf(health.max_health, 1.0), 0.0, 1.0)


## Adds borrowed health, up to the maximum. Returns what landed.
func grant_temp(amount: float) -> float:
	if health == null or not is_up() or amount <= 0.0:
		return 0.0

	var landed := minf(amount, maxf(health.max_health - health.health, 0.0))

	if landed <= 0.0:
		return 0.0

	health.health += landed
	temp_health += landed
	return landed


## Heals real health: borrowed health it would push past the maximum is given back.
func heal_real(amount: float) -> float:
	if health == null or not is_up() or amount <= 0.0:
		return 0.0

	var room := health.max_health - real_health()
	var landed := minf(amount, maxf(room, 0.0))
	var total := real_health() + landed
	temp_health = minf(temp_health, maxf(health.max_health - total, 0.0))
	health.health = total + temp_health
	return landed


## A hit landed: the borrowed health goes first.
func absorb_temp(lost: float) -> void:
	temp_health = maxf(temp_health - lost, 0.0)

	if health != null:
		temp_health = minf(temp_health, health.health)


## Borrowed health drains with time. Every tick on the authority.
func decay_temp(amount: float) -> void:
	if temp_health <= 0.0 or health == null or not is_up():
		return

	var drained := minf(amount, temp_health)
	temp_health -= drained
	health.health = maxf(health.health - drained, 1.0)


# --- Bodies ----------------------------------------------------------------

## Where this player's eyes are: standing, crouched, or on the floor.
func eye_position() -> Vector3:
	if is_down():
		return controller.state.position + Vector3(0.0, EYE_DOWN, 0.0)

	var crouch := controller.state.crouch_fraction if controller != null else 0.0
	var height := lerpf(EYE_HEIGHT, BODY_CROUCH - 0.15, crouch)
	return controller.state.position + Vector3(0.0, height, 0.0)


## Which way they are looking, as a unit vector. From yaw and pitch, never a camera.
func aim_direction() -> Vector3:
	var view := Basis.from_euler(Vector3(
		deg_to_rad(controller.state.pitch), deg_to_rad(controller.state.yaw), 0.0
	))
	return -view.z


## Where they stand.
func feet() -> Vector3:
	return controller.state.position if controller != null else global_position


## The hitboxes: a capsule and a head. A survivor on the floor is the same boxes, lowered.
func build_hitboxes(combat: DotCombatManager) -> void:
	hitboxes = DotHitboxSet.new()
	hitboxes.name = "Hitboxes"
	hitboxes.owner_ref = DotNodeRef.of_path(^"..")
	hitboxes.bounds_offset = Vector3(0.0, 0.9, 0.0)
	hitboxes.bounds_radius = 1.5
	add_child(hitboxes)

	var chest := DotHitbox.new()
	chest.name = "Chest"
	chest.group = DotHitGroup.CHEST
	chest.shape = DotHitbox.Shape.CAPSULE
	chest.radius = 0.34
	chest.height = 1.25
	chest.position = Vector3(0.0, 0.78, 0.0)
	hitboxes.add_child(chest)

	var head := DotHitbox.new()
	head.name = "Head"
	head.group = DotHitGroup.HEAD
	head.shape = DotHitbox.Shape.SPHERE
	head.radius = 0.19
	head.position = Vector3(0.0, EYE_HEIGHT + 0.06, 0.0)
	head.damage_scale = 2.0
	head.precedence = 10
	hitboxes.add_child(head)

	hitboxes.refresh()
	hitboxes.register_with(combat, entity_id)


## Lowers the hitboxes onto the floor for a downed survivor and back up again.
func fit_hitboxes() -> void:
	if hitboxes == null or not is_instance_valid(hitboxes):
		return

	var down := is_down()
	var chest := hitboxes.get_node_or_null(^"Chest") as DotHitbox
	var head := hitboxes.get_node_or_null(^"Head") as DotHitbox

	if chest != null:
		chest.position = Vector3(0.0, 0.3 if down else 0.78, 0.0)
		chest.height = 0.7 if down else 1.25
	if head != null:
		head.position = Vector3(0.0, 0.4 if down else EYE_HEIGHT + 0.06, 0.0)


## The duck-typed lookup dot-weapon's player bridge asks a carrier for.
func component(type_name: StringName) -> Object:
	match String(type_name):
		"DotPlayerController", "DotFpsController":
			return controller
		"DotHealth":
			return health
		"ZeeWeaponRig":
			return weapons
		_:
			return null


## Puts a player somewhere, facing somewhere, with nothing carried over.
func place_at(at: Vector3, yaw_degrees: float) -> void:
	warps += 1
	global_position = at
	controller.teleport(at, yaw_degrees, 0.0)

	if sampler != null:
		sampler.look_at_angles(yaw_degrees, 0.0)

	var facing := DotFpsCommand.new()
	facing.yaw = yaw_degrees
	controller.apply_command(facing)


## Back to the start of a map: up, unhurt, nothing borrowed, nothing holding them.
func reset_map() -> void:
	watching = false
	life = Life.UP
	incaps = 0
	temp_health = 0.0
	pinned_by = 0
	pin_kind = &""
	using = &""
	use_target = -1
	use_fraction = 0.0
	helped_fraction = 0.0
	shove_streak = 0
	shove_ready_at = 0.0
	biled_until = -1.0
	burning_until = -1.0
	biled = false
	burning = false
	died_at = -1.0
	respawn_at = -1.0
	protected_until = -1.0
	in_end_area = false
	commons_killed = 0
	specials_killed = 0
	revives_done = 0
	defib_ready_at = 0.0
	shield_until = -1.0
	damage_taken_map = 0.0
	friendly_damage = 0.0
	air = 12.0
	submerged = false
	water_level = WaterLevel.NONE

	if controller != null:
		for id in [ZzController.PINNED, ZzController.DOWN, ZzController.LIMP, ZzController.BUSY,
				ZzController.HASTE, ZzController.LOW_GRAVITY, ZzController.HEAVY,
				ZzController.MOVE_BOOST, ZzController.CRAWL_BOOST, ZzController.WADING]:
			var _off := controller.remove_modifier(id)

	fit_hitboxes()


func retune() -> void:
	if controller == null:
		return

	controller.tunables = tunables_for(config)

	if sampler != null:
		sampler.tunables = controller.tunables


# --- Drawing (client side) --------------------------------------------------

## Draws the beacon at [param at], from an admin's flag. Returns whether it pinged.
func present_beacon(delta: float, at: Vector3, local_view: bool, period: float) -> bool:
	if not beacon or not is_alive():
		if beacon_marker != null:
			beacon_marker.queue_free()
			beacon_marker = null
		return false

	if beacon_marker == null:
		beacon_marker = DotFxBeacon.new()
		beacon_marker.name = "Beacon"
		beacon_marker.period = period
		beacon_marker.colour = Color(0.98, 0.22, 0.86)
		beacon_marker.column_base = BODY_HEIGHT + 0.4
		add_child(beacon_marker)

	beacon_marker.local_view = local_view
	beacon_marker.global_position = at
	return beacon_marker.advance(delta)


## Draws this player for one frame at [param at]: standing, crouched, or on the floor. Returns
## whether anything was shown.
func present_body(hidden: bool, at: Vector3, team_colour: Color) -> bool:
	var shown := not hidden and is_alive() and not watching

	if figure == null:
		if not shown:
			return false
		figure = ZzFigure.new()
		figure.name = "Figure"
		add_child(figure)

	var atlas := _atlas()

	if figure.atlas != atlas or not figure.team_colour.is_equal_approx(team_colour):
		figure.build(BODY_HEIGHT, atlas, team_colour)

	figure.visible = shown

	if shown:
		_present_held()
		var velocity := controller.state.velocity
		# Down is on the floor, crawling: the person's crawl clip (the zombies' own, same rig),
		# slowed to the crawling pace. It used to be the standing figure tipped onto its back,
		# which slid along the ground lying flat (the first play test, 1:44).
		figure.set_motion({
			"on_floor": controller.state.mode == DotFpsState.Mode.GROUND,
			"vertical": velocity.y,
			"crouched": controller.state.crouch_fraction > 0.5,
			"downed": is_down(),
			# The view's pitch bends the figure's spine and gun arm (dot-player-char people.md).
			"aim": deg_to_rad(controller.state.pitch),
		})
		figure.pose(at, deg_to_rad(controller.state.yaw), Vector2(velocity.x, velocity.z).length())
		figure.show_defib(using == &"defib")
		figure.show_box(carried_count, use_fraction if using == &"deploy" else 0.0, box_out)

	return shown


## Breaks this player's body apart: torn up by a brute. Client side.
func break_body(break_rules: DotPlayerBreakRules, direction: Vector3, seed_value: int) -> DotPlayerBodyBreak:
	if figure == null or not figure.visible or break_rules == null:
		return null

	var model := figure.body_node()

	if model == null:
		return null

	return DotPlayerBodyBreak.break_apart(
		model, get_parent(), break_rules, figure.global_position, direction, seed_value, true, true
	)


func note_dealt(weapon_id: StringName, round_number: int) -> void:
	if round_number != dealt_round:
		dealt.clear()
		dealt_round = round_number

	if not dealt.has(weapon_id):
		dealt.append(weapon_id)


func _present_held() -> void:
	var rig := _rig()
	var id := &""
	var switching := false
	var fired := 0
	var kind := 0

	if rig != null and rig.arsenal != null:
		var def := rig.arsenal.current_def()
		id = def.id if def != null else &""
		switching = rig.arsenal.is_switching()
		var seq := rig.fire_seq % ZeeWeaponNet.FIRE_SEQ_WRAP
		fired = ZeeWeaponNet.uses_between(_seen_fire_seq, seq) if _seen_fire_seq >= 0 else 0
		_seen_fire_seq = seq
		kind = rig.fire_kind
	elif mirrored:
		id = held_by_slot(dealt, mirror_slot)
		switching = mirror_switching
		fired = mirror_fired
		kind = mirror_fire_kind

	mirror_fired = 0
	figure.hold(id, switching)
	figure.fired(fired, kind)


static func held_by_slot(ids: Array[StringName], slot: int) -> StringName:
	if slot <= 0 or ids.is_empty():
		return &""

	if _slots.is_empty():
		for def in ZzWeapons.all_defs():
			_slots[def.id] = def.slot

	for id in ids:
		if int(_slots.get(id, -1)) == slot:
			return id

	return &""


func _rig() -> ZeeWeaponRig:
	if weapons != null:
		return weapons

	return get_node_or_null(^"Weapons") as ZeeWeaponRig


func _atlas() -> String:
	var index := ZzAvatars.skin_index(avatar)

	if index < 0 or index >= ZzFigure.ATLASES.size():
		index = ZzAvatars.stock_index(player_id)

	return str(ZzFigure.ATLASES[index])


func describe() -> Dictionary:
	return {
		"id": String(player_id),
		"life": Life.keys()[life],
		"health": "%.0f (+%.0f temp)" % [real_health(), temp_health],
		"incaps": incaps,
		"pinned": "%s by %d" % [pin_kind, pinned_by] if is_pinned() else "-",
		"using": "%s %.0f%%" % [using, use_fraction * 100.0] if using != &"" else "-",
		"kits": "%d medkit, %d pills" % [medkits, pills],
		"watching": watching,
		"armed": weapons != null,
		"points": points,
		"kills": "%d commons, %d specials" % [commons_killed, specials_killed],
	}
