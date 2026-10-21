extends Node3D

const ZzBoxes := preload("zz_boxes.gd")
const ZzBots := preload("zz_bots.gd")
const ZzCatalogue := preload("zz_catalogue.gd")
const ZzConfig := preload("zz_config.gd")
const ZzController := preload("zz_controller.gd")
const ZzHazards := preload("zz_hazards.gd")
const ZzTurrets := preload("zz_turrets.gd")
const ZzHorde := preload("zz_horde.gd")
const ZzLoot := preload("zz_loot.gd")
const ZzMap := preload("zz_map.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzNetCommand := preload("net/zz_net_command.gd")
const ZzNpcs := preload("zz_npcs.gd")
const ZzPaths := preload("zz_paths.gd")
const ZzPins := preload("zz_pins.gd")
const ZzPlayer := preload("zz_player.gd")
const ZzProgress := preload("zz_progress.gd")
const ZzProps := preload("zz_props.gd")
const ZzCrawlRules := preload("zz_crawl_rules.gd")
const ZzWaterRules := preload("zz_water_rules.gd")
const ZzPassRules := preload("zz_pass_rules.gd")
const ZzRules := preload("zz_rules.gd")
const ZzSpectate := preload("zz_spectate.gd")
const ZzSurvival := preload("zz_survival.gd")
const ZzTeamDamage := preload("zz_team_damage.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzWorkshop := preload("zz_workshop.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")

## The simulation. Headless, authoritative, and the only thing that decides anything.
##
## [b]A round is a map.[/b] Everybody starts in the start area, where nothing comes for them
## until somebody leaves it (or [member ZzConfig.start_grace_seconds] pass). Then the horde
## runs: an exodus map is won when every survivor still standing is inside the end shelter, a
## survival map when its hold is over ([ZzSurvival]: the last wave cleared, the last night
## lived through, or the clock run out) with anybody alive. It is lost when nobody is left on
## their feet and free. A won exodus map moves on to the map it names as `next`; a lost one is
## played again, [member ZzConfig.retries] times.
##
## [b]What it owns and what it borrows.[/b] The round and the scoreboard are dot-match's
## (decided through [ZzRules]); health and shots are dot-combat's; the weapons are
## zee-dot-weapons'; the zombies are [ZzHorde], which is dot-npc, dot-npc-ai and
## dot-npc-ai-director; the movement is dot-player-controller's, with this game's modifiers
## ([ZzController]). Downs, revives, medkits, the shove, pins, hazards, boxes and objectives are
## this game's own.
##
## [b]The order of a tick is the design.[/b] Bots decide; pins set their victims' velocities;
## every survivor moves; every gun fires (at zombies where they were when the survivor aimed);
## the horde perceives, thinks and moves; pins sit their specials on their victims and do their
## damage; hazards, loot and the round are judged last, on a world that has finished moving.

const CHANNEL := "zz.game"

## Where this world publishes itself, so a module can find it. A registry name and not an
## autoload: a server and a client in one process are two of these.
const SERVICE := &"zz_game"

## Where a host that runs this game with no server (the client shell's Solo play) publishes
## the map packs it mounted for it. See [method solo_map_dirs].
const SOLO_SERVICE := &"dot_solo"

## Snapshots a second. A crowd running at you is what a client is reading.
const NET_SNAPSHOT_RATE := 30

## How far a position may be from the origin, in metres, on the wire. Both ends read it here.
const NET_WORLD_EXTENT := 1024.0

## The two sides, as dot-combat and dot-match see them. Only one has players.
const SURVIVORS := 1
const INFECTED := 2

const TEAM_COLOURS: Array[Color] = [Color(0.36, 0.62, 0.95), Color(0.75, 0.2, 0.18)]
const TEAM_NAMES: Array[String] = ["Survivors", "Infected"]

## Which part of a map it is.
enum Phase {
	## Between maps, or waiting for somebody to play.
	IDLE,
	## In the start area: nothing comes yet.
	READY,
	## The horde is running.
	PLAY,
}

## Why somebody went down or died.
## Seconds a dead body lies before it fades, unless the owner sets `sv_ragdoll_time`.
const CORPSE_SECONDS := 6.0

const BY_ZOMBIE := &"zombie"
const BY_SPECIAL := &"special"
const BY_FRIEND := &"friend"
const BY_FELL := &"fell"
const BY_HAZARD := &"hazard"

## Damage type and weapon id of a survivor out of breath under water.
const DROWN := &"drown"
const BY_BLED := &"bled"
const BY_BOX := &"box"
const BY_REFLECT := &"reflected"

signal player_added(player_id: StringName)
signal player_removed(player_id: StringName)
signal round_began(number: int, map_id: StringName)
signal world_clearing()
signal world_rebuilt()
signal round_over(number: int, won: bool, why: String)
signal phase_changed(phase: int)
signal player_downed(player_id: StringName, by: StringName, why: StringName)
signal player_died(player_id: StringName, by: StringName, why: StringName)
signal player_revived(player_id: StringName, by: StringName)
signal player_rescued(player_id: StringName)
signal player_healed(player_id: StringName, by: StringName, amount: float)
signal player_biled(player_id: StringName, seconds: float)
signal player_hurt(player_id: StringName, amount: float, from: Vector3)
signal zombie_killed(npc_kind: StringName, by: StringName, headshot: bool)
signal objective_changed(index: int, state: StringName)
signal gate_opened(gate: String)
signal notice(text: String)
signal refused(player_id: StringName, why: String)
signal achievement_earned(player_id: StringName, title: String, points: int)
signal player_armed(player_id: StringName, weapon_id: StringName)

## Everything [param player_id] held was taken away (a new map, a rescue): an empty ARMED on the
## wire, so a client's own rig and everybody's drawn hands start again.
signal player_disarmed(player_id: StringName)
signal exploded(at: Vector3, radius: float, kind: StringName)

## A survivor's ammunition was filled by the server: a pile, a box. A predicting client's own
## rig has to be told, or it predicts an empty magazine the server has refilled.
signal ammo_given(player_id: StringName)

## A survivor's shot (or blast, or fire) took health off a zombie: the confirmation the
## shooter's hit marker and damage numbers are drawn from. The authority's decision, never a
## client's prediction; the bridge sends it to the shooter alone. [param victim] is the
## zombie's entity id, which only groups hits on one body; [param point] is where it landed.
signal hit_landed(player_id: StringName, victim: int, amount: float, point: Vector3, killed: bool, headshot: bool)

## A barricade took damage, broke, or was mended: its strength as a share, and whether it stands.
signal barricade_changed(id: String, fraction: float, intact: bool)

## The survival hold moved on (a wave began or was cleared, a night fell): the bridge tells
## every client at once rather than at the next clock.
signal survival_changed()

@export var config: ZzConfig = null
@export var authoritative: bool = true
@export_range(1, 240, 1) var tick_rate: int = 64
@export var external_tick: bool = false
@export var register_service: bool = true

## Whether this machine draws the world: a client does, a server does not.
@export var draw_world: bool = false

var map: ZzMap = null
var catalogue: ZzCatalogue = null

## Where subscribed Workshop maps are read from; null is dot-core's shared index. A test gives its own.
var content_index: DotContentIndex = null
var props_catalogue: ZzProps = null
var combat: DotCombatManager = null

## `func(player_id: StringName) -> bool`: whether a survivor may be hurt now, assigned by the
## module from dot-game's `can_peer_be_harmed`. Unset offline, and a stand-in is never loading.
var harm_gate: Callable = Callable()
var match_node: DotMatch = null
var random: DotRandomManager = null
var physics: DotPhysicsLayout = null
var effects: DotFxManager = null
var spectate: ZzSpectate = null
var progress: ZzProgress = null

## Server only. A client is told about zombies, pins, hazards and loot by the bridge.
var horde: ZzHorde = null
var pins: ZzPins = null
var hazards: ZzHazards = null
## Server only. The sentry turrets a box deployed.
var turrets: ZzTurrets = null
var loot: ZzLoot = null
var boxes: ZzBoxes = null
var bots: ZzBots = null

## player id -> [ZzPlayer].
var players: Dictionary = {}

## dot-player-controller's `mp_forceview` (may a player switch to third person) and
## `mp_solidplayers` (do survivors and stand-ins block each other). Bound by the module
## (REPLICATED) and followed by a client through its link.
var view_rules: DotPlayerViewRules = DotPlayerViewRules.new()
var body_rules: DotPlayerBodyRules = DotPlayerBodyRules.new()

## `zz_pass_barricades`: whether survivors walk through barricades. Bound by the module
## (REPLICATED) and followed by a client, which predicts its own player under it.
var pass_rules: ZzPassRules = ZzPassRules.new()

## `zz_down_crawl_speed`: how fast a downed survivor crawls (0: not at all). Bound by the module
## (REPLICATED) and followed by a client, which predicts its own player under it.
var crawl_rules: ZzCrawlRules = ZzCrawlRules.new()

## The `zz_water*` settings: how survivors wade, swim and drown, and how the horde wades. The
## movement ones are REPLICATED and a client follows them (see [ZzWaterRules]).
var water_rules: ZzWaterRules = ZzWaterRules.new()

## Server: team damage, added up per player over a window ([ZzTeamDamage]); the module wires
## what a voteban and a ban do.
var team_damage: ZzTeamDamage = ZzTeamDamage.new()

## What a dead body does, survivor or zombie, and which death reactions the server allows:
## dot-player-char's `sv_ragdoll*` cvars, bound by the module (REPLICATED) and followed by a
## client through its link, because the client draws the bodies. One set for both: an owner who
## turns ragdolls off means every body. A body lies [constant CORPSE_SECONDS] by default.
var ragdoll_rules: DotPlayerRagdollRules = _corpse_rules()

## dot-props' `sv_toys*` (whether a map's toys are there, how many simulate at once, how hard a
## walk pushes one). Bound by the module (REPLICATED) and followed by a client, which draws them.
var toy_rules: DotPropToyRules = DotPropToyRules.new()

## player id -> side. Everybody is a survivor today.
var sides: Dictionary = {}

## The map to play next, chosen by a vote or an admin. Empty: the rotation decides.
var next_map_id: StringName = &""

var round_number: int = 0
var phase: int = Phase.IDLE
var phase_elapsed: float = 0.0
var map_doc: Dictionary = {}
var entities := DotEntityTable.new()

## Survival: seconds held, and the clock style's goal. An exodus map leaves them at zero.
var survival_elapsed: float = 0.0
var survival_goal: float = 0.0

## Server: the survival map's hold, while one is being held. See [ZzSurvival].
var survival: ZzSurvival = null

## What a client was told of the hold, the shape of [method ZzSurvival.state]; empty for none.
var remote_survival: Dictionary = {}

## Every barricade of the map in play: id -> {health, max, intact, label}. Both ends keep it:
## the server decides, a client is told (BARRICADE) and draws it.
var barricades: Dictionary = {}

## Each objective's state: `waiting`, `holding` (the holdout is running), `done`.
var objective_states: Array[StringName] = []
var objective_progress: Array[float] = []

## Seconds the standing survivors have all been in the end area.
var end_hold: float = 0.0

## What a client is told rather than works out.
var remote_alive: int = -1
var remote_seconds_left: float = -1.0

## A client's copy of how long until the next map begins after a decided one, and which map
## (from ROUND); -1 while a map is being played. See [method next_round_seconds].
var remote_next_round: float = -1.0
var remote_next_map: StringName = &""
var remote_playable: bool = false

## How many times this map has been lost in a row.
var losses_on_map: int = 0

var _tick: int = 0
var _round_seed: int = 0
var _decided: bool = false
var _won: bool = false
var _why: String = ""
var _lost_since: float = -1.0
var _hurt_backlog: Dictionary = {}


func _ready() -> void:
	if config == null:
		config = ZzConfig.new()

	var valid := config.validate()

	if not valid.ok:
		DotLog.error(CHANNEL, "the configuration is not usable", {"why": valid.error.message})
		return

	_round_seed = config.seed_value
	ZzWeapons.use_packs(config.second_weapon_pack)

	_build_physics()
	pass_rules.humans_pass = config.humans_pass_barricades
	crawl_rules.speed = config.downed_crawl_speed
	if not crawl_rules.changed.is_connected(_on_crawl_rules_changed):
		crawl_rules.changed.connect(_on_crawl_rules_changed)
	if not water_rules.changed.is_connected(_push_water):
		water_rules.changed.connect(_push_water)
	if not body_rules.changed.is_connected(_on_body_rules_changed):
		body_rules.changed.connect(_on_body_rules_changed)
	if not pass_rules.changed.is_connected(_on_body_rules_changed):
		pass_rules.changed.connect(_on_body_rules_changed)
	team_damage.config = config
	team_damage.playtime_fn = _playtime_of
	_apply_gravity()
	_build_random()
	_build_props()
	_build_map()
	_build_combat()
	_build_effects()
	_build_match()
	_build_spectate()
	_build_progress()

	if authoritative:
		pins = ZzPins.new(self)
		hazards = ZzHazards.new(self)
		turrets = ZzTurrets.new(self)
		hazards.exploded.connect(func(at: Vector3, radius: float, kind: StringName) -> void:
			exploded.emit(at, radius, kind))
		# A pipe bomb, a propane tank, a molotov's burst: the map's toys thrown from it.
		var _toys := exploded.connect(_on_exploded_near_toys)
		loot = ZzLoot.new(self)
		boxes = ZzBoxes.new(self)
		var _loaded_boxes := boxes.load_file(config.box_file)
		bots = ZzBots.new(self)
		_build_horde()
		catalogue = ZzCatalogue.new()
		# Subscribed (solo) pack maps are map documents and join the catalogue; online none.
		catalogue.follow_content(content_index if content_index != null else DotContentIndex.shared(),
			ZzWorkshop.accepted_map_kinds())
		var _loaded := catalogue.load_from(config.map_directory)
		# Solo in the client shell: the map packs it mounted for this game, which a server
		# would have named. See [method solo_map_dirs].
		for root in solo_map_dirs("maps"):
			var _added := catalogue.add_directory(root)
		var _rotation := load_rotation()
		# Laid out now, not on the first round: a warmup on an empty world is indistinguishable
		# from a map that failed to load.
		_lay_out_map()

	if register_service:
		DotRegistry.register(SERVICE, self)

	DotLog.info(CHANNEL, "world ready", config.describe())


## The `<pack>/<subdir>` directories of the map packs a host running this game with no server
## has mounted for it: the client shell's Solo play, which fetches the packs a server owner
## would name (dot-server-deploy's `client/solo.json`) because a tab has no server to name
## them. Read the way the module reads its server's ([DotGameContent]). Empty everywhere else:
## a server, a suite, a run from the repository. Looked up by name and duck-typed, because a
## delivered game may not name a host's class.
static func solo_map_dirs(subdir: String) -> PackedStringArray:
	var host: Object = DotRegistry.get_service(SOLO_SERVICE)
	if host == null or not host.has_method(&"map_dirs"):
		return PackedStringArray()
	return host.call(&"map_dirs", subdir)


func _exit_tree() -> void:
	if register_service:
		DotRegistry.unregister_instance(SERVICE, self)


# --- Building -------------------------------------------------------------------------------

## Four layers: the world, the survivors, the furniture and the zombies.
##
## [b]Survivors do not collide with zombies, and that is the netcode's call, not the
## design's.[/b] A survivor's movement is predicted and a zombie is drawn a few ticks in the
## past; a capsule the client cannot see where the server has it is a survivor stopped by
## nothing on their screen and corrected every tick. The crowd still blocks you — by hitting
## you: every common's hit slows you (`ZzController.TAGGED`), which is the genre's own answer.
## Zombies collide with the world and the furniture, and not with each other: a crowd is kept
## apart by steering, which is smooth, rather than by bodies, which jam in doorways.
func _build_physics() -> void:
	physics = DotPhysicsLayout.custom(&"zombiezone", [&"world", &"player", &"prop", &"zombie", &"toy", &"footprint", &"barricade"])

	for layer in physics.layers:
		match layer.id:
			&"player":
				layer.collides_with = [&"world", &"prop", &"barricade"]
			&"zombie":
				layer.collides_with = [&"world", &"prop", &"barricade"]
			# A map's loose toy (dot-props'): the world, the furniture and the other toys, never
			# a survivor or a zombie, who walk through it (a survivor pushes it, `_advance_toys`).
			&"toy":
				layer.collides_with = [&"world", &"prop", &"toy", &"barricade"]
			# A toy's footprint, for a walkable mesh's bake only: nothing collides with it.
			&"footprint":
				layer.collides_with = []
			_:
				layer.collides_with = [&"player", &"zombie"]

	var built := physics.build()

	if not built.ok:
		DotLog.error(CHANNEL, "the collision layout would not build", {"why": built.error.message})
		physics = null


## The mask of everything a sight line stops on: the world and the furniture.
## The player's motor mask under `mp_solidplayers`, and the standing hull the others stop at
## (a player's body has no shape of its own). With the rule on, a stand-in survivor stops at
## your shoulder instead of filling the screen with its face (the first play test).
func _apply_body_mask(player: ZzPlayer) -> void:
	if physics == null or player == null or player.controller == null:
		return
	# A barricade is on its own layer so a survivor's mask can leave it out: the horde is held by
	# it and a shot stops on it either way, only the people walk through (`zz_pass_barricades`).
	var mask := physics.collision_mask(&"player")

	if pass_rules.humans_pass:
		mask &= ~physics.layer_mask(&"barricade")

	body_rules.apply_to(player.controller, mask, physics.layer_mask(&"player"))
	var tunables := player.controller.tunables
	body_rules.apply_hull(player, tunables.stand_height, tunables.radius)


## The DOWN modifier's pace on every survivor, on this end; the server and each client run the same.
func _on_crawl_rules_changed() -> void:
	for id in players:
		(players[id] as ZzPlayer).controller.set_crawl_speed(crawl_rules.speed)


## The water survivors move through: the map's volumes, or none when `zz_water` is off.
func _water_boxes() -> Array[AABB]:
	var none: Array[AABB] = []
	return map.water_boxes if map != null and water_rules.is_on() else none


## Hands every survivor the map's water and the rules, on this end: a map just built, a setting
## changed, a player just added. The server and each client run the same.
func _push_water() -> void:
	var boxes := _water_boxes()

	for id in players:
		(players[id] as ZzPlayer).set_water(boxes, water_rules)


## How deep a zombie standing at [param feet] is in water, as the factor on its pace: 1 dry,
## `zz_water_zombie_scale` with the feet wet, `zz_water_zombie_deep_scale` with the waist. The
## ground they walk is the bed (the nav is the map's floor plan), so wading is all they do.
func water_pace_at(feet: Vector3) -> float:
	if map == null or map.water_boxes.is_empty() or not water_rules.is_on():
		return 1.0

	var pace := 1.0

	for box in map.water_boxes:
		if box.has_point(feet + Vector3.UP * 1.0):
			return water_rules.zombie_deep
		if box.has_point(feet + Vector3.UP * 0.1):
			pace = water_rules.zombie_wade

	return pace


## A survivor's breath for one tick; on the server, drowning too. Every end counts its own air
## from its own copy of the water (the client's is the HUD's bar), only the server hurts.
func _advance_water(player: ZzPlayer, delta: float) -> void:
	var owed := player.breathe(delta, water_rules)

	if owed > 0.0 and authoritative and player.is_up():
		hazard_damage(player, owed, 0, DROWN)


func _on_body_rules_changed() -> void:
	for id in players:
		_apply_body_mask(players[id] as ZzPlayer)


func world_mask() -> int:
	if physics == null:
		return 1

	return physics.layer_mask(&"world") | physics.layer_mask(&"prop") | physics.layer_mask(&"barricade")


## The gravity the movement is tuned against, on this world's own physics SPACE: a project
## setting does not travel with a delivered pack.
func _apply_gravity() -> void:
	var world := get_world_3d()

	if world == null:
		return

	PhysicsServer3D.area_set_param(world.space, PhysicsServer3D.AREA_PARAM_GRAVITY, config.gravity)


func _build_random() -> void:
	random = DotRandomManager.new()
	random.name = "Random"
	random.register_as_service = false
	add_child(random)
	var _started := random.setup()
	random.reseed(_round_seed)


func _build_props() -> void:
	props_catalogue = ZzProps.new()
	var count := props_catalogue.load_file()

	if count == 0:
		DotLog.warn(CHANNEL, "no props: maps will be bare streets", {})


func _build_map() -> void:
	map = ZzMap.new()
	map.name = "Map"
	map.physics = physics
	map.catalogue = props_catalogue
	map.draw_world = draw_world
	map.authoritative = authoritative
	map.toy_rules = toy_rules
	map.gravity = config.gravity
	add_child(map)


func _build_combat() -> void:
	combat = DotCombatManager.new()
	combat.name = "Combat"
	combat.is_authority = authoritative
	combat.register_service = false

	var damage_rules := DotDamageRules.new()
	damage_rules.friendly_fire = config.friendly_fire_scale() > 0.0
	damage_rules.friendly_scale = clampf(config.friendly_fire_scale(), 0.0, 2.0)
	damage_rules.self_damage = true
	damage_rules.hit_groups = true
	combat.rules = damage_rules

	var settings := DotCombatConfig.new()
	settings.lag_compensation = true
	combat.config = settings

	# A shot stops on a wall and on the furniture. A shot that starts inside a team-mate is not
	# aimed at them: dot-combat's pass_through_sets does that (API level 2), under the rules.
	var trace := DotTracePhysics.new()
	trace.bind(get_world_3d())
	trace.collision_mask = world_mask()

	combat.trace = trace
	combat.resolver = DotDamageResolver.with_rules(damage_rules)
	combat.resolver.hit_groups = DotHitGroup.defaults()
	combat.resolver.team_of = func(entity_id: int) -> int:
		return INFECTED if DotEntity.is_kind(entity_id, DotEntity.KIND_NPC) else SURVIVORS
	combat.resolver.adjust = _adjust_damage

	for type in [_type(&"bite", 0.0), _type(&"fire", 0.0), _type(&"acid", 0.0), _type(&"blast", 0.0),
			_type(&"strike", 0.0), _type(&"fall", 0.0), _type(&"drown", 0.0)]:
		combat.register_damage_type(type)

	add_child(combat)
	combat.damage_applied.connect(_on_hit_landed)


static func _type(id: StringName, armour_share: float) -> DotDamageType:
	var t := DotDamageType.new()
	t.id = id
	t.armour_share = armour_share
	return t


## What a box's damage boost does, and nothing else: the difficulty is applied where a zombie's
## hit is made (see [method zombie_hit]), because it scales what zombies do, not what anybody
## does to them.
## Turns dot-combat's applied damage into [signal hit_landed] for a survivor hitting a zombie.
## Friendly fire is not a confirmation anybody wants a marker for, and a hit that took nothing
## (a dead body, an immune zombie) did not land.
func _on_hit_landed(damage: DotDamage) -> void:
	if not authoritative or damage.refused or damage.health_lost <= 0.0 \
			or not DotEntity.is_kind(damage.victim, DotEntity.KIND_NPC):
		return

	var by := key_for_entity(damage.attacker)

	if by == &"":
		return

	hit_landed.emit(by, damage.victim, damage.health_lost, damage.point, damage.lethal,
		damage.hit_group == DotHitGroup.HEAD)


func _adjust_damage(damage: DotDamage) -> void:
	# dot-game's "still loading": the one place every hurt on a survivor passes (a bite, a pin's
	# damage, acid, fire, a blast, a friend's bullet), so a seat behind its client's cover is
	# neither hurt, downed nor killed. An admin's slay or slap is the operator's word and passes.
	if DotEntity.is_kind(damage.victim, DotEntity.KIND_PLAYER) and not damage.context.get("admin", false):
		var covered := player_for_entity(damage.victim)

		if covered != null and not can_be_harmed(covered.player_id):
			damage.refuse("still loading")
			return

	if authoritative and damage.attacker != damage.victim and damage.attacker != 0 \
			and DotEntity.is_kind(damage.victim, DotEntity.KIND_PLAYER):
		_team_damage_hit(damage)
		return

	if not DotEntity.is_kind(damage.victim, DotEntity.KIND_NPC):
		return

	var attacker := player_for_entity(damage.attacker)

	if attacker != null and boxes != null:
		damage.amount *= boxes.damage_scale_for(attacker.player_id)

		var npc := horde.npc_for_entity(damage.victim) if horde != null else null
		if npc != null:
			damage.amount = boxes.zombie_damage(npc.def.id, npc.def.max_health, damage.amount)


## Whether [param player_id] may be hurt, downed, pinned or hunted now: false while their client
## is behind its loading cover. True for anybody the gate does not know (a stand-in is never
## loading; offline there is no gate).
func can_be_harmed(player_id: StringName) -> bool:
	return not harm_gate.is_valid() or bool(harm_gate.call(player_id))


## A survivor's bullet or blast reached another survivor, at [param damage]'s amount (the
## friendly-fire scale already applied). It is added to the shooter's window first, so a new
## player being reflected still runs up the total that earns a voteban or a ban, and then, when
## the shooter's damage is reflected, it lands on the shooter instead: the one who was hit takes
## nothing. Server only.
func _team_damage_hit(damage: DotDamage) -> void:
	var by := player_for_entity(damage.attacker)
	var victim := player_for_entity(damage.victim)

	if by == null or victim == null or damage.amount <= 0.0:
		return

	team_damage.record(by, damage.amount, now())

	if team_damage.reflects(by):
		damage.victim = damage.attacker
		damage.context["why"] = BY_REFLECT
		damage.context["reflected_from"] = victim.entity_id


## Seconds [param player_id] has played, for deciding who is new: lifetime where progress is
## kept, otherwise this session's.
func _playtime_of(player: ZzPlayer) -> float:
	var held := progress.playtime_of(player.player_id) if progress != null else 0.0
	return maxf(held, player.session_seconds)


func _build_effects() -> void:
	if authoritative and not draw_world:
		return

	var fx := DotFxCatalogue.new()

	for spec in [["go", 0.18, Color(0.98, 0.86, 0.35)], ["hurt", 0.32, Color(0.85, 0.08, 0.06)],
			["bile", 0.5, Color(0.42, 0.55, 0.12)], ["heal", 0.2, Color(0.3, 0.95, 0.4)]]:
		var def := DotFxDef.new()
		def.id = StringName(spec[0])
		def.kind = DotFxDef.Kind.SCREEN
		def.flash_peak = float(spec[1])
		def.flash_colour = spec[2]
		def.flash_decay_ms = 380
		fx.add(def)

	effects = DotFxManager.new()
	effects.name = "Effects"
	effects.catalogue = fx
	effects.config = DotFxConfig.new()
	effects.register_as_service = false
	add_child(effects)
	DotLog.result(CHANNEL, "the effects layer", effects.setup())


func _build_match() -> void:
	match_node = DotMatch.new()
	match_node.name = "Match"
	match_node.register_service = false

	var match_config := DotMatchConfig.new()
	match_config.tick_rate = tick_rate
	match_config.auto_start = false
	match_config.log_transitions = false
	match_config.balance_between_rounds = false
	match_node.config = match_config

	var match_rules: DotMatchRules = ZzRules.make()
	match_rules.intermission_sec = config.intermission_seconds
	match_rules.warmup_sec = config.warmup_seconds
	match_rules.countdown_sec = 0.0
	match_rules.team_based = true
	match_rules.min_players = 1
	match_rules.set(&"decision_fn", _decision)
	# The backstop only. A map ends when the game decides; three hours is a map nobody finished.
	match_rules.time_limit_sec = 10800.0
	match_node.rules = match_rules

	# Scoped to the match node, which finds nothing: this game places its own players.
	match_node.spawns_ref = DotNodeRef.of_path(^".")
	add_child(match_node)

	match_node.round_started.connect(_on_round_started)
	match_node.round_ended.connect(_on_round_ended)

	var teams: Array[DotTeam] = [
		DotTeam.make(SURVIVORS, TEAM_NAMES[0], TEAM_COLOURS[0]),
		DotTeam.make(INFECTED, TEAM_NAMES[1], TEAM_COLOURS[1]),
	]
	match_node.teams.teams = teams
	match_node.teams.force_balance = false
	match_node.teams.allow_choice = false
	match_node.teams.max_difference = 0
	match_node.teams.reindex()


func _decision() -> Dictionary:
	return {"decided": _decided, "winner": SURVIVORS if _won else INFECTED}


func _build_spectate() -> void:
	spectate = ZzSpectate.new()
	spectate.name = "Spectate"
	spectate.players = players
	spectate.sides = sides
	spectate.phase_fn = func() -> int: return phase
	add_child(spectate)

	var ready_now := spectate.setup(authoritative, tick_rate, config.spectate_camera)

	if not ready_now.ok:
		DotLog.warn(CHANNEL, "spectating is off", {"why": ready_now.error.message})
		remove_child(spectate)
		spectate.queue_free()
		spectate = null


func _build_progress() -> void:
	if not authoritative or not config.keep_progress:
		return

	progress = ZzProgress.new()
	progress.name = "Progress"
	progress.players = players
	add_child(progress)

	var ready_now := progress.setup(config.progress_directory, config.report_progress)

	if not ready_now.ok:
		DotLog.warn(CHANNEL, "progress is off", {"why": ready_now.error.message})
		remove_child(progress)
		progress.queue_free()
		progress = null
		return

	progress.earned.connect(func(id: StringName, title: String, points: int) -> void:
		achievement_earned.emit(id, title, points)
	)


## The stock rules with the game's corpse time: a horde dies by the dozen, and a body lying ten
## seconds (dot-player-char's default) kept the floor of a survival wave covered.
static func _corpse_rules() -> DotPlayerRagdollRules:
	var rules := DotPlayerRagdollRules.new()
	rules.lifetime = CORPSE_SECONDS
	return rules


## The horde picks a zombie's fall from the server's `sv_ragdoll_reactions` weights, as a
## survivor's is picked; kept in step when an owner changes them.
func _follow_ragdoll_reactions() -> void:
	if horde != null:
		horde.death_reactions = ragdoll_rules.reactions()


func _build_horde() -> void:
	horde = ZzHorde.new()
	horde.name = "Horde"
	add_child(horde)
	var ready_now := horde.setup(self, config)

	if not ready_now.ok:
		DotLog.error(CHANNEL, "the horde would not set up", {"why": ready_now.error.message})
		horde.queue_free()
		horde = null
		return

	horde.zombie_died.connect(_on_zombie_died)
	_follow_ragdoll_reactions()
	if not ragdoll_rules.changed.is_connected(_follow_ragdoll_reactions):
		ragdoll_rules.changed.connect(_follow_ragdoll_reactions)


# --- Players --------------------------------------------------------------------------------

func add_player(player_id: StringName, display_name: String, _wanted_side: int = 0,
		samples_input: bool = false) -> ZzPlayer:
	if players.has(player_id):
		return players[player_id]

	var player := ZzPlayer.new()
	player.name = "Player_%s" % String(player_id)
	player.player_id = player_id
	player.display_name = display_name
	player.samples_input = samples_input
	player.tick_rate = tick_rate
	player.config = config
	player.team = SURVIVORS
	add_child(player)

	if physics != null:
		var applied := physics.apply_to(player, &"player")

		if not applied.ok:
			DotLog.warn(CHANNEL, "a player could not be put on its collision layer", {"why": applied.error.message})

		_apply_body_mask(player)

	player.controller.set_crawl_speed(crawl_rules.speed)
	player.set_water(_water_boxes(), water_rules)

	var opened := entities.open(DotEntity.KIND_PLAYER, player, &"", player_id, now())
	player.entity_id = (opened.value as DotEntityHandle).id if opened.ok else 0

	var health := DotHealth.new()
	health.name = "Health"
	health.max_health = config.max_health
	health.health = health.max_health
	player.add_child(health)
	player.health = health

	if combat != null:
		combat.register_health(player.entity_id, health)
		player.build_hitboxes(combat)

	health.died.connect(func(damage: DotDamage) -> void: _on_health_zero(player, damage))
	health.damaged.connect(func(damage: DotDamage) -> void: _on_player_damaged(player, damage))

	players[player_id] = player
	sides[player_id] = SURVIVORS

	if match_node != null:
		var seated := match_node.add_player(String(player_id), display_name, _tick, SURVIVORS)

		if not seated.ok:
			DotLog.error(CHANNEL, "dot-match refused a player", {"id": String(player_id), "why": seated.error.message})

	place_one(player)
	DotLog.debug(CHANNEL, "player joined", {"id": String(player_id)})
	player_added.emit(player_id)
	return player


## Puts one player in the map. Joining during play is joining the team where it is, with a
## sidearm, rather than at a start area the team left ten minutes ago.
func place_one(player: ZzPlayer) -> void:
	if map == null or map.doc.is_empty():
		return

	if authoritative and phase == Phase.PLAY:
		var buddy := _furthest_survivor(player.player_id)

		if buddy != null:
			player.place_at(buddy.feet() + Vector3(0.6, 0.1, 0.6), buddy.controller.state.yaw)
		else:
			var spot := map.spawn("survivors", players.size() - 1)
			player.place_at(spot[0], spot[1])
	else:
		var spot := map.spawn("survivors", players.size() - 1)
		player.place_at(spot[0], spot[1])

	if authoritative:
		_equip(player, false)

	if spectate != null:
		spectate.on_spawned(player.player_id)


func remove_player(player_id: StringName) -> void:
	if not players.has(player_id):
		return

	var player: ZzPlayer = players[player_id]

	if pins != null:
		pins.release(player_id, &"left")

	if combat != null and is_instance_valid(combat) and player.entity_id != 0:
		combat.forget(player.entity_id)
		var _closed := entities.close(player.entity_id, DotEntityTable.REASON_OWNER_LEFT)

	if match_node != null:
		match_node.remove_player(String(player_id))

	players.erase(player_id)
	sides.erase(player_id)

	if bots != null:
		bots.forget(player_id)

	player.queue_free()

	if spectate != null:
		spectate.on_left(player_id)

	if progress != null:
		progress.leave(player_id)

	team_damage.forget(player_id)
	player_removed.emit(player_id)


func team_of(player_id: StringName) -> int:
	return int(sides.get(player_id, 0))


func side_name(side: int) -> String:
	return TEAM_NAMES[side - 1] if side == SURVIVORS or side == INFECTED else "nobody"


func side_colour(side: int) -> Color:
	return TEAM_COLOURS[side - 1] if side == SURVIVORS or side == INFECTED else Color(0.7, 0.7, 0.7)


func players_on(side: int) -> Array[ZzPlayer]:
	var out: Array[ZzPlayer] = []

	for id: StringName in players:
		if int(sides.get(id, 0)) == side:
			out.append(players[id])

	return out


## Every survivor, alive or not.
func survivors() -> Array[ZzPlayer]:
	return players_on(SURVIVORS)


func player_by_id(id: StringName) -> ZzPlayer:
	return players.get(id)


func player_for_entity(entity: int) -> ZzPlayer:
	if not DotEntity.is_kind(entity, DotEntity.KIND_PLAYER):
		return null

	return players.get(entities.key_for_id(entity))


## The candidate id a brain knows a survivor by, for an entity; empty for anything else.
func key_for_entity(entity: int) -> StringName:
	var player := player_for_entity(entity)
	return player.player_id if player != null else &""


## How many survivors are alive (up or down) and in the map.
func alive_on(side: int) -> int:
	if not authoritative and remote_alive >= 0:
		return remote_alive

	var total := 0

	for player in players_on(side):
		if player.is_alive() and not player.watching:
			total += 1

	return total


func sides_are_playable() -> bool:
	if not authoritative:
		return remote_playable

	return players.size() >= 1


## Survivors within [param radius] (horizontal) of [param at], and [param vertical] up or down.
func survivors_within(at: Vector3, radius: float, vertical: float = 1.5) -> Array[ZzPlayer]:
	var out: Array[ZzPlayer] = []

	for player in survivors():
		if not player.is_alive() or player.watching:
			continue

		var p := player.feet()

		if absf(p.y - at.y) <= vertical and Vector2(p.x - at.x, p.z - at.z).length() <= radius:
			out.append(player)

	return out


## The first survivor whose middle is within [param radius] of the segment, or empty.
func survivor_near_segment(from: Vector3, to: Vector3, radius: float) -> StringName:
	for player in survivors():
		if not player.is_alive() or player.watching:
			continue

		var middle := player.feet() + Vector3(0.0, 0.9, 0.0)
		var closest := Geometry3D.get_closest_point_to_segment(middle, from, to)

		if closest.distance_to(middle) <= radius:
			return player.player_id

	return &""


func _furthest_survivor(except: StringName = &"") -> ZzPlayer:
	var best: ZzPlayer = null
	var best_flow := -INF
	var flow: DotNpcDirectorFlow = horde.director.flow if horde != null and horde.director != null else null

	for player in survivors():
		if player.player_id == except or not player.is_up() or player.watching:
			continue

		var f := flow.flow_of(player.feet()) if flow != null and flow.has_route() else 0.0

		if best == null or f > best_flow:
			best = player
			best_flow = f

	return best


# --- The round --------------------------------------------------------------------------------

func start() -> void:
	if not authoritative:
		return

	# A map laid out when the world opened, before the module added the delivered maps, is the
	# practice street; if the server now has maps it would rather play, the first map is one of
	# those. Found by dot-server-deploy's zombiezone_client: a delivered server read six maps and
	# played the one built in.
	if not map_doc.is_empty() and catalogue != null and next_map_id == &"" \
			and not catalogue.playable(config.map_ids).has(StringName(str(map_doc.get("id", "")))):
		map_doc = {}

	# Built again here: on a server nothing was listening when the world opened (the module
	# builds the bridge after), and a map built before it is a map no client is ever sent.
	if not map_doc.is_empty():
		var _rebuilt := build_map(map_doc)
		_place_everybody()
	else:
		_lay_out_map()

	match_node.start(_tick)


func _on_round_started(number: int) -> void:
	round_number = number
	_round_seed = config.seed_value + number * 7919
	random.reseed(_round_seed)

	if next_map_id != &"":
		_lay_out_map()

	_decided = false
	_won = false
	_why = ""
	_lost_since = -1.0
	end_hold = 0.0
	survival_elapsed = 0.0
	survival_goal = _survival_goal()
	_stop_survival()
	_reset_barricades()

	if pins != null:
		pins.clear()
	if hazards != null:
		hazards.clear()
	if turrets != null:
		turrets.clear()
	if loot != null:
		loot.clear()
		loot.place_from_map(map_doc)
	if boxes != null:
		boxes.reset()

	_reset_objectives()

	if horde != null:
		var built := horde.build_for_map(map_doc)
		if not built.ok:
			DotLog.error(CHANNEL, "the horde has nowhere to walk on this map", {"why": built.error.message})

	_place_everybody()

	if progress != null:
		progress.on_round_began()

	_set_phase(Phase.READY)
	round_began.emit(number, map.id())

	DotLog.info(CHANNEL, "map began", {
		"number": number, "map": String(map.id()), "mode": str(map_doc.get("mode", "")),
		"seed": _round_seed, "survivors": players.size(), "difficulty": config.difficulty_name(),
	})


func _on_round_ended(number: int, _winner: int, _outcome: int) -> void:
	if boxes != null:
		boxes.end_round()

	_set_phase(Phase.IDLE)
	_stop_survival()

	if horde != null:
		horde.stop_pacing()

	if not _decided:
		_why = "the map ran out of time"

	if progress != null:
		progress.on_round_over(_won)

	# What plays next: a won campaign map's next, or the rotation; a lost one again, a few times.
	if next_map_id == &"":
		if _won:
			losses_on_map = 0
			var after := StringName(str(map_doc.get("next", "")))

			if after != &"" and catalogue != null and catalogue.maps.has(after):
				next_map_id = after
			else:
				next_map_id = _rotation_next()
		else:
			losses_on_map += 1

			if config.map_on_loss == 1 or losses_on_map > config.retries:
				losses_on_map = 0
				next_map_id = _rotation_next()
			else:
				next_map_id = map.id()

	round_over.emit(number, _won, _why)
	DotLog.info(CHANNEL, "map over", {"number": number, "won": _won, "why": _why, "next": String(next_map_id)})


## Every map this server plays, as the map menu (M) lists them: `{id, name, mode, detail,
## current}`, exodus or survival as the mode and the blurb under it, with the team it is built
## for. Solo the client's list, online the server's (the module hands it to dot-vote's map
## menu), so both say the same.
func map_rows() -> Array:
	var out: Array = []
	if catalogue == null:
		return out
	var now := map.id() if map != null else &""
	for id in catalogue.playable(config.map_ids):
		var doc: Dictionary = catalogue.maps.get(id, {})
		var rotates := catalogue.in_rotation(id)
		var row := {"id": String(id),
			"name": catalogue.display_name(id) + ("" if rotates else " (not in rotation)"),
			"in_rotation": rotates, "current": id == now,
			"mode": str(doc.get("mode", "")).capitalize(),
			"detail": str(doc.get("blurb", "")) if int(doc.get("survivors", 0)) <= 0 \
				else "%s (%d survivors)" % [str(doc.get("blurb", "")), int(doc["survivors"])]}
		if doc.has("thumbnail"):
			row["thumbnail"] = str(doc["thumbnail"])
		out.append(row)
	return out


## The map menu's change: [param id] now, not after this map. The next map is set and a fresh
## round begins on it (dot-match's `begin_round_now`: the map called off is neither won nor
## lost, and its retries are forgotten); with no match running it is simply built. Authority
## only.
func change_map_now(id: StringName) -> DotResult:
	if not authoritative:
		return DotResult.fail(DotError.CODE_STATE, "Only the server changes the map.")
	if catalogue == null or not catalogue.playable(config.map_ids).has(id):
		return DotResult.fail(DotError.CODE_INVALID, "There is no map called '%s' here." % id)
	next_map_id = id
	losses_on_map = 0
	if match_node == null or not match_node.begin_round_now(_tick):
		_lay_out_map()
	DotLog.info(CHANNEL, "map changed from the map menu", {"map": String(id)})
	return DotResult.success(id)


## Reads maps.yml (the `--config` directory first) and applies it. Called at boot and by
## `sv_map_rotation_file`. A file that is present and unreadable is an ERROR and changes nothing:
## rotating every map is a better failure than rotating none.
func load_rotation() -> DotResult:
	if catalogue == null:
		return DotResult.fail(DotError.CODE_STATE, "There is no catalogue to rotate.")

	var stem := config.map_rotation_file
	var dir := DotMapRotationFile.config_dir_arg()
	var found := DotMapRotationFile.find(stem, dir)

	if found == "" and stem != "" and (dir != "" or stem != ZzConfig.new().map_rotation_file):
		# The default name being absent is an install with no maps.yml; a name or a directory
		# somebody chose that finds nothing is a typo they would otherwise never hear about.
		DotLog.warn(CHANNEL, "the map rotation file was not found; every map rotates", {
			"file": stem, "config_dir": dir,
		})

	var paths := PackedStringArray()

	if found != "":
		paths.append(found)

	var read := DotMapRotationFile.load_files(paths, "game-zombie-zone")

	if not read.ok:
		DotLog.error(CHANNEL, "the map rotation file could not be read; every map rotates", {
			"why": read.error.message,
		})
		catalogue.rotation_file = null
		catalogue.apply_rotation(config.map_ids)
		return read

	catalogue.rotation_file = read.value
	catalogue.apply_rotation(config.map_ids)

	if catalogue.has_rotation_file():
		DotLog.info(CHANNEL, "the map rotation file", {
			"paths": ", ".join(catalogue.rotation_file.sources),
			"active": catalogue.rotation_file.active_name(),
		})

	return read


## maps.yml's `commands:` block (prefix and names), or empty with no file.
func rotation_commands() -> Dictionary:
	if catalogue == null or catalogue.rotation_file == null:
		return {}

	return catalogue.rotation_file.commands()


## Every name a role of this game's own answers to (the first is the one help shows), from
## maps.yml's `commands:` block; the role's own name with no file. Lets `zz_map` and its siblings
## be renamed the way dot-vote's roles are.
func command_names(role: String) -> PackedStringArray:
	var spec := rotation_commands()
	var names: Dictionary = spec.get("names", {})

	if not names.has(role):
		return PackedStringArray([role])

	return DotCommandNames.all_of("", names, {}, role)


func _rotation_next() -> StringName:
	if catalogue == null:
		return map.id()

	var doc := catalogue.next_map(config.map_ids, config.shuffle_maps, random.stream(&"map"), map.id())
	return StringName(str(doc.get("id", map.id())))


## The next map, built.
func _lay_out_map() -> void:
	if catalogue == null:
		return

	var doc: Dictionary = {}

	if next_map_id != &"" and catalogue.maps.has(next_map_id):
		doc = catalogue.maps[next_map_id]

	next_map_id = &""

	if doc.is_empty():
		doc = catalogue.next_map(config.map_ids, config.shuffle_maps, random.stream(&"map"),
			StringName(str(map_doc.get("id", ""))))

	catalogue.note_played(StringName(str(doc.get("id", ""))))
	var _built := build_map(doc)
	_place_everybody()


## Builds [param doc] as the map. What the server does between maps, and what a client does
## when it is sent one.
func build_map(doc: Dictionary) -> DotResult:
	world_clearing.emit()

	for id: StringName in players:
		(players[id] as ZzPlayer).reset_map()

	var built := map.build(doc)

	if not built.ok:
		DotLog.error(CHANNEL, "a map would not build", {"id": str(doc.get("id", "?")), "why": built.error.message})
		return built

	map_doc = map.doc
	_push_water()
	_reset_barricades()
	# The states are the map's: a map laid out between rounds (the map menu's change, a vote's)
	# otherwise keeps the last map's, and a shorter objective list is read past its end.
	_reset_objectives()

	if spectate != null:
		spectate.set_overviews(map.overview(), map.overview())

	world_rebuilt.emit()
	return built


## Everybody to the start, up, unhurt, holding what a map starts with.
func _place_everybody() -> void:
	var ids := players.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var seat := 0

	for id: StringName in ids:
		var player: ZzPlayer = players[id]
		player.reset_map()

		if player.health != null:
			player.health.max_health = config.max_health
			player.health.health = config.max_health
			player.health.alive = true
			player.health.invulnerable = false

		player.fit_hitboxes()
		var spot := map.spawn("survivors", seat)
		seat += 1
		player.place_at(spot[0], spot[1])

		if authoritative:
			_equip(player, true)

		if spectate != null:
			spectate.on_spawned(player.player_id)


## What a survivor holds at the start of a map ([param fresh]) or after a rescue.
func _equip(player: ZzPlayer, fresh: bool) -> void:
	_disarm(player)

	var kit := config.start_weapons if fresh else PackedStringArray([config.start_weapons[0]])

	for weapon_id in kit:
		var _armed := arm(player, StringName(weapon_id))

	if fresh:
		player.medkits = config.start_medkits
		player.pills = config.start_pills

	_draw(player, StringName(kit[0]))


func _draw(player: ZzPlayer, weapon_id: StringName) -> void:
	if player.weapons == null:
		return

	var def := player.weapons.arsenal.catalogue.get_def(weapon_id)

	if def != null:
		var _selected := player.weapons.arsenal.select(def.slot, _tick)
		player.wanted_slot = def.slot


func _set_phase(to: int) -> void:
	if phase == to:
		return

	phase = to
	phase_elapsed = 0.0
	phase_changed.emit(to)
	DotLog.debug(CHANNEL, "the map changed phase", {"phase": Phase.keys()[to]})


func is_survival() -> bool:
	return str(map_doc.get("mode", ZzMapDoc.EXODUS)) == ZzMapDoc.SURVIVAL


## The team the map in play is built for, or the configured minimum: what stand-ins fill to.
func team_size() -> int:
	var wanted := config.minimum_players

	if config.team_from_map and not map_doc.is_empty() and not is_survival():
		wanted = maxi(wanted, config.exodus_team)

	if config.team_from_map and not map_doc.is_empty():
		wanted = maxi(wanted, int(map_doc.get("survivors", 0)))

	return wanted


func _survival_goal() -> float:
	if not is_survival():
		return 0.0

	var asked := float(map_doc.get("survive_seconds", 0.0))
	return asked if asked > 0.0 else config.survive_seconds


func _advance_phase(delta: float) -> void:
	if phase == Phase.IDLE:
		return

	phase_elapsed += delta

	match phase:
		Phase.READY:
			if _anybody_left_start() or phase_elapsed >= config.start_grace_seconds:
				_begin_play()
			else:
				_check_round()
		Phase.PLAY:
			# A survival map's hold starts with its first objective, when it has one.
			if is_survival() and authoritative and (objective_states.is_empty() or objective_states[0] == &"done"):
				if survival == null:
					_start_survival()
				if survival != null:
					survival.tick(delta)
					survival_elapsed = survival.waves.elapsed if survival.waves != null else survival_elapsed + delta

			_advance_objectives(delta)
			_check_round()


func _anybody_left_start() -> bool:
	var starts: Array = (map_doc.get("areas", {}) as Dictionary).get("start", [])

	if starts.is_empty():
		return phase_elapsed >= 3.0

	for player in survivors():
		if player.is_up() and not player.watching and not map.in_area("start", player.feet()):
			return true

	return false


func _begin_play() -> void:
	_set_phase(Phase.PLAY)

	# A survival map's horde is the hold's (it starts on the next tick); an exodus map's is the
	# director's, from now.
	if horde != null and not is_survival():
		horde.start_pacing(false)

	if not is_survival():
		notice.emit("Make for the shelter.")


## Server: the hold begins. Its schedule's first stage sets the horde going.
func _start_survival() -> void:
	if not authoritative or horde == null:
		return

	survival = ZzSurvival.new(self)
	var begun := survival.begin()

	if not begun.ok:
		survival = null
		horde.start_pacing(true)
		return

	survival_changed.emit()
	if not survival.waves.stage_changed.is_connected(_on_survival_stage):
		survival.waves.stage_changed.connect(_on_survival_stage)


func _on_survival_stage(_stage: int, _index: int) -> void:
	survival_changed.emit()


func _stop_survival() -> void:
	if survival != null:
		survival.stop()
		survival = null

	remote_survival = {}


## The hold is over and held: the last wave, the last night, the clock.
func survival_finished(why: String) -> void:
	_decide(true, why)


## The hold as the HUD and the bridge read it (see [method ZzSurvival.state]): the server's own,
## or what a client was told. Empty on an exodus map or before the hold begins.
func survival_state() -> Dictionary:
	if authoritative:
		return survival.state() if survival != null else {}

	return remote_survival


## Lost, won, or neither yet.
func _check_round() -> void:
	if _decided:
		return

	var standing := 0
	var alive := 0

	for player in survivors():
		if player.watching or not player.is_alive():
			continue

		alive += 1

		if player.is_up() and not player.is_pinned():
			standing += 1

	if players.is_empty():
		return

	# Nobody on their feet and free is the end: nobody is left to pick anybody up. Two seconds
	# of grace, so the last survivor's final shove can still land.
	if standing == 0:
		if _lost_since < 0.0:
			_lost_since = now()
		elif now() - _lost_since >= 2.0:
			_decide(false, "everybody is down" if alive > 0 else "everybody is dead")
		return

	_lost_since = -1.0

	if phase != Phase.PLAY:
		return

	if is_survival():
		# Decided by the hold itself (survival_finished), whichever style it is held by.
		return

	# An exodus map: every survivor on their feet inside the end shelter, for a moment.
	var everyone_in := true
	var anybody := false

	for player in survivors():
		player.in_end_area = player.is_alive() and map.in_area("end", player.feet())

		if not player.is_up() or player.watching:
			continue

		anybody = true

		if not player.in_end_area:
			everyone_in = false

	if anybody and everyone_in:
		end_hold += delta_for_tick()

		if end_hold >= config.end_hold_seconds:
			_decide(true, "made it to the shelter")
	else:
		end_hold = 0.0


func _decide(won: bool, why: String) -> void:
	if _decided:
		return

	_decided = true
	_won = won
	_why = why

	if horde != null:
		horde.stop_pacing()

	if won:
		for player in survivors():
			if player.is_alive() and not player.watching:
				player.points += 10 + (5 if player.is_up() else 0)

				if progress != null:
					progress.on_survived(player.player_id, is_survival())

	DotLog.info(CHANNEL, "the map is decided", {"won": won, "why": why})


static func _clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


## Seconds until the next map begins, between a decided map and the next; -1 otherwise. The
## first play test ended on "YOU DIED", then ten seconds of "nobody left to watch" with nothing
## saying a new round was coming, and he quit at four: the HUD counts this down.
func next_round_seconds() -> float:
	if not authoritative:
		return remote_next_round
	if match_node == null or match_node.state != DotMatch.State.INTERMISSION:
		return -1.0
	return match_node.seconds_remaining(_tick)


## The map that [method next_round_seconds] counts down to (this one again after a loss, a
## campaign's next after a win, or the rotation's).
func next_round_map() -> StringName:
	return next_map_id if authoritative else remote_next_map


## Seconds left on a survival map's clock; -1 on an exodus map or an endless hold.
func seconds_left() -> float:
	if not authoritative:
		return remote_seconds_left

	if not is_survival() or survival_goal <= 0.0:
		return -1.0

	return maxf(survival_goal - survival_elapsed, 0.0)


# --- Objectives --------------------------------------------------------------------------------

func _reset_objectives() -> void:
	objective_states.clear()
	objective_progress.clear()

	for _o in map_doc.get("objectives", []):
		objective_states.append(&"waiting")
		objective_progress.append(0.0)


## The first objective not yet done, or -1.
func current_objective() -> int:
	for i in objective_states.size():
		if objective_states[i] != &"done":
			return i

	return -1


func _advance_objectives(_delta: float) -> void:
	var index := current_objective()

	if index < 0:
		return

	var o: Dictionary = (map_doc["objectives"] as Array)[index]

	match objective_states[index]:
		&"waiting":
			if o["kind"] == "reach":
				for player in survivors():
					if player.is_up() and player.feet().distance_to(ZzMapDoc.v3(o["at"])) <= float(o["radius"]):
						_objective_used(index)
						break
		&"holding":
			if now() >= objective_progress[index]:
				_finish_objective(index)


## A survivor finished holding E on objective [param index] (or reached it).
func _objective_used(index: int) -> void:
	var o: Dictionary = (map_doc["objectives"] as Array)[index]
	var holdout := float(o.get("holdout", 0.0))

	if holdout > 0.0:
		objective_states[index] = &"holding"
		objective_progress[index] = now() + holdout
		objective_changed.emit(index, &"holding")

		if bool(o.get("panic", true)) and horde != null:
			horde.panic(holdout)

			# Halfway through a long holdout, the brute: the genre's finale.
			if holdout >= 90.0:
				horde.call_deferred(&"spawn_brute")

		notice.emit(str(o.get("message", "")) if str(o.get("message", "")) != "" \
			else "Hold out for %s!" % _clock(holdout))
	else:
		_finish_objective(index)


func _finish_objective(index: int) -> void:
	var o: Dictionary = (map_doc["objectives"] as Array)[index]
	objective_states[index] = &"done"
	objective_changed.emit(index, &"done")

	for gate in (o.get("opens", PackedStringArray()) as PackedStringArray):
		open_gate(gate)

	if float(o.get("holdout", 0.0)) <= 0.0 and str(o.get("message", "")) != "":
		notice.emit(str(o["message"]))
	elif float(o.get("holdout", 0.0)) > 0.0:
		notice.emit("Done. Move!")


func open_gate(gate: String) -> void:
	map.open_gate(gate)

	if horde != null:
		horde.open_gate(gate)

	gate_opened.emit(gate)


# --- Barricades --------------------------------------------------------------------------------

## Every barricade back to full, from the map document: at a round's start on the server, and
## whenever a client builds a map (it is told any that are not full straight after).
func _reset_barricades() -> void:
	barricades.clear()

	if map == null:
		return

	for entry: Dictionary in map_doc.get("barricades", []):
		var id := str(entry["id"])
		var strength := float(entry.get("health", config.barricade_health))
		barricades[id] = {"health": strength, "max": strength, "intact": true, "label": str(entry.get("label", "a barricade"))}
		map.set_barricade(id, true, 1.0)

		# A map played again keeps its document, so nothing tells a client it is new: every
		# barricade it saw broken last round is told it stands.
		if authoritative:
			barricade_changed.emit(id, 1.0, true)

	_tell_horde_barricades()


func _tell_horde_barricades() -> void:
	if horde == null:
		return

	var standing := {}

	for id: String in barricades:
		if bool((barricades[id] as Dictionary)["intact"]):
			standing[id] = map.barricade_bounds(id)

	horde.set_barricades(standing)


## The horde tore [param amount] off barricade [param id]. Server only. At nothing it breaks:
## gone, and the way in is open until somebody mends it.
func bash_barricade(id: String, amount: float) -> void:
	var entry: Variant = barricades.get(id)

	if entry == null or not bool((entry as Dictionary)["intact"]) or amount <= 0.0:
		return

	var e := entry as Dictionary
	e["torn_at"] = now()
	var before := float(e["health"]) / float(e["max"])
	e["health"] = maxf(float(e["health"]) - amount, 0.0)
	var after := float(e["health"]) / float(e["max"])

	if float(e["health"]) <= 0.0:
		e["intact"] = false
		map.set_barricade(id, false, 0.0)
		_tell_horde_barricades()
		barricade_changed.emit(id, 0.0, false)
		notice.emit("They are through %s!" % str(e["label"]))
		DotLog.info(CHANNEL, "a barricade broke", {"id": id})
		return

	# Told in steps of a sixteenth: a crowd at a window is a hit every tick, and a message per
	# hit to every client is the whole wire.
	if floori(before * 16.0) != floori(after * 16.0):
		map.set_barricade(id, true, after)
		barricade_changed.emit(id, after, true)


## Seconds after the last blow on a barricade before it can be mended. A mend under attack
## outran any crowd at a window (120 every two seconds against 6 a second a zombie), so a team
## behind boards it could not see through mended forever and no wave was ever cleared, only
## timed out (zz-survival-long-run-1). The boards are held by killing what tears at them;
## mending is the breather's job, or a lull's.
const MEND_LOCKOUT := 1.5


## Whether something has torn at barricade [param id] in the last [constant MEND_LOCKOUT] s.
func barricade_torn(id: String) -> bool:
	var e: Dictionary = barricades.get(id, {})
	return not e.is_empty() and now() - float(e.get("torn_at", -INF)) < MEND_LOCKOUT


## The barricade [param player] is close enough to mend, as its index in the map's list, or -1:
## one within reach of their eyes that is not at full strength.
func barricade_to_mend(player: ZzPlayer) -> int:
	var list: Array = map_doc.get("barricades", [])
	var best := -1
	var best_gap := config.use_reach + 0.6
	var eye := player.eye_position()

	for i in list.size():
		var id := str((list[i] as Dictionary)["id"])
		var entry: Variant = barricades.get(id)

		if entry == null or float((entry as Dictionary)["health"]) >= float((entry as Dictionary)["max"]):
			continue

		var box := map.barricade_bounds(id)
		var nearest := Vector3(clampf(eye.x, box.position.x, box.end.x), clampf(eye.y, box.position.y, box.end.y),
			clampf(eye.z, box.position.z, box.end.z))
		var gap := nearest.distance_to(eye)

		if gap < best_gap:
			best = i
			best_gap = gap

	return best


## One mend done on the barricade at [param index]: its strength back by
## [member ZzConfig.barricade_repair], and a broken one standing again unless a zombie is in the
## gap, which is where it would stand.
func mend_barricade(index: int, by: ZzPlayer) -> bool:
	var list: Array = map_doc.get("barricades", [])

	if index < 0 or index >= list.size():
		return false

	var id := str((list[index] as Dictionary)["id"])
	var e: Dictionary = barricades.get(id, {})

	if e.is_empty():
		return false

	if barricade_torn(id):
		if by != null:
			refused.emit(by.player_id, "They are tearing at it. Clear them off first.")
		return false

	if not bool(e["intact"]) and horde != null:
		var box := map.barricade_bounds(id).grow(0.4)

		for npc in horde.spawner.npcs_near(box.get_center(), box.size.length() * 0.5 + 0.5):
			var p := npc.position()
			if npc.is_alive() and p.x >= box.position.x and p.x <= box.end.x and p.z >= box.position.z and p.z <= box.end.z:
				if by != null:
					refused.emit(by.player_id, "Something is in the gap.")
				return false

	e["health"] = minf(float(e["health"]) + config.barricade_repair, float(e["max"]))
	var was_broken := not bool(e["intact"])
	e["intact"] = true
	var fraction := float(e["health"]) / float(e["max"])
	map.set_barricade(id, true, fraction)

	if was_broken:
		_tell_horde_barricades()

	barricade_changed.emit(id, fraction, true)

	if by != null:
		by.points += 1

	return true


## A client was told barricade [param id] is at [param fraction] and standing or not.
func apply_barricade(id: String, fraction: float, intact: bool) -> void:
	var e: Dictionary = barricades.get(id, {})

	if e.is_empty():
		return

	e["health"] = float(e["max"]) * fraction
	e["intact"] = intact
	map.set_barricade(id, intact, fraction)


# --- Hands: use, heal, pills, shove ------------------------------------------------------------

## Everything a survivor does with their hands this tick. Server side.
func _advance_hands(player: ZzPlayer, delta: float) -> void:
	var held := player.actions
	var pressed := held & ~player.previous_actions
	player.previous_actions = held

	var shove_pressed := player.shove_held and not player.previous_shove
	player.previous_shove = player.shove_held

	_sync_carry(player)

	if player.is_down() or not player.is_alive() or player.watching or player.is_pinned():
		cancel_use(player)
		return

	if shove_pressed:
		_shove(player)

	if (pressed & ZzNetCommand.ACT_PILLS) != 0:
		_take_pills(player)

	# Holding: E, or the medkit. Whatever was started keeps going while its key is held.
	if player.using != &"":
		var key := ZzNetCommand.ACT_USE

		if player.using == &"heal":
			key = ZzNetCommand.ACT_HEAL
		elif player.using == &"deploy":
			key = ZzNetCommand.ACT_DEPLOY

		if (held & key) == 0 or not _use_still_valid(player):
			cancel_use(player)
		else:
			_advance_use(player, delta)
		return

	if (held & ZzNetCommand.ACT_DEPLOY) != 0 and (pressed & ZzNetCommand.ACT_DEPLOY) != 0 and boxes != null:
		_begin_deploy(player)
	elif (held & ZzNetCommand.ACT_HEAL) != 0 and player.medkits > 0:
		_begin_heal(player)
	elif (held & ZzNetCommand.ACT_USE) != 0 and (pressed & ZzNetCommand.ACT_USE) != 0:
		_begin_use(player)


func _begin_use(player: ZzPlayer) -> void:
	# Somebody down in front of you comes first: it is the one thing that cannot wait.
	var downed := _looked_at_survivor(player, config.revive_range + 0.4, true)

	if downed != null:
		_start(player, &"revive", downed.entity_id, config.revive_seconds)
		return

	var thing := loot.looked_at(player.eye_position(), player.aim_direction(), config.use_reach) if loot != null else -1

	if thing >= 0:
		var needs := loot.use_seconds(thing)

		if needs <= 0.0:
			loot.use(thing, player)
		else:
			_start(player, &"loot", thing, needs)
		return

	var index := current_objective()

	if index >= 0 and phase == Phase.PLAY:
		var o: Dictionary = (map_doc["objectives"] as Array)[index]

		if o["kind"] == "use" and objective_states[index] == &"waiting" \
				and player.eye_position().distance_to(ZzMapDoc.v3(o["at"])) <= float(o["radius"]) + 0.6:
			_start(player, &"objective", index, float(o["seconds"]))
			return

	var mend := barricade_to_mend(player)

	if mend >= 0:
		_start(player, &"repair", mend, config.barricade_repair_seconds)


## What everybody is told about the boxes in [param player]'s hands: how many, and which (not
## which when `box_labels` is off: the type does not leave the server).
func _sync_carry(player: ZzPlayer) -> void:
	player.carried_count = player.carried.size()
	player.carried_index = 0

	if not player.carried.is_empty() and boxes != null and config.box_labels:
		player.carried_index = boxes.order.find(player.carried.back()) + 1


## Deploying takes [member ZzConfig.box_deploy_seconds] with the key held, and the survivor may
## shuffle about only within [member ZzConfig.box_deploy_radius] of where they began. Not BUSY: they
## may turn and shoot, which is what makes it a risk worth taking.
func _begin_deploy(player: ZzPlayer) -> void:
	if player.carried.is_empty():
		refused.emit(player.player_id, "You are not carrying a box.")
		return

	player.using = &"deploy"
	player.use_target = 0
	player.use_started = now()
	player.use_needs = maxf(config.box_deploy_seconds, 0.01)
	player.use_fraction = 0.0
	player.use_origin = player.feet()


func _begin_heal(player: ZzPlayer) -> void:
	var friend := _looked_at_survivor(player, config.use_reach, false)
	var who := friend if friend != null and friend.real_health() < friend.health.max_health * 0.95 else player

	if who == player and player.real_health() >= player.health.max_health * 0.95:
		refused.emit(player.player_id, "You are not hurt.")
		player.previous_actions &= ~ZzNetCommand.ACT_HEAL
		return

	_start(player, &"heal", who.entity_id, config.medkit_seconds)


func _start(player: ZzPlayer, what: StringName, target: int, seconds: float) -> void:
	player.using = what
	player.use_target = target
	player.use_started = now()
	player.use_needs = maxf(seconds, 0.01)
	player.use_fraction = 0.0
	var _busy := player.controller.add_modifier(ZzController.BUSY)

	if what == &"revive":
		var downed := player_for_entity(target)
		if downed != null:
			downed.helped_fraction = 0.0


func _use_still_valid(player: ZzPlayer) -> bool:
	match player.using:
		&"revive":
			var downed := player_for_entity(player.use_target)
			return downed != null and downed.is_down() and not downed.is_pinned() \
				and downed.feet().distance_to(player.feet()) <= config.revive_range + 0.6
		&"heal":
			var who := player_for_entity(player.use_target)
			return player.medkits > 0 and who != null and who.is_up() \
				and (who == player or who.feet().distance_to(player.feet()) <= config.use_reach + 0.6)
		&"loot":
			return loot != null and loot.exists(player.use_target) \
				and loot.position_of(player.use_target).distance_to(player.eye_position()) <= config.use_reach + 0.8
		&"objective":
			return current_objective() == player.use_target and objective_states[player.use_target] == &"waiting"
		&"repair":
			return barricade_to_mend(player) == player.use_target
		&"deploy":
			var drift := (player.feet() - player.use_origin) * Vector3(1.0, 0.0, 1.0)
			return not player.carried.is_empty() and drift.length() <= config.box_deploy_radius

	return false


func _advance_use(player: ZzPlayer, _delta: float) -> void:
	player.use_fraction = clampf((now() - player.use_started) / player.use_needs, 0.0, 1.0)

	var other := player_for_entity(player.use_target) if player.using == &"revive" or player.using == &"heal" else null

	if other != null and other != player:
		other.helped_fraction = player.use_fraction

	if player.use_fraction < 1.0:
		return

	var what := player.using
	var target := player.use_target
	cancel_use(player)

	match what:
		&"revive":
			_revive(player_for_entity(target), player)
		&"heal":
			_heal_with_kit(player_for_entity(target), player)
		&"loot":
			loot.use(target, player)
		&"objective":
			_objective_used(target)
		&"repair":
			var _mended := mend_barricade(target, player)
		&"deploy":
			if boxes != null:
				boxes.deploy(player)


func cancel_use(player: ZzPlayer) -> void:
	if player.using == &"":
		return

	var other := player_for_entity(player.use_target) if player.using == &"revive" or player.using == &"heal" else null

	if other != null:
		other.helped_fraction = 0.0

	var what_was := player.using
	player.using = &""
	player.use_target = -1
	player.use_fraction = 0.0
	if what_was != &"deploy":
		var _free := player.controller.remove_modifier(ZzController.BUSY)


## The survivor [param player] is looking at within [param reach]: one who is down when
## [param down] is true, one who is up otherwise.
func _looked_at_survivor(player: ZzPlayer, reach: float, down: bool) -> ZzPlayer:
	var eye := player.eye_position()
	var aim := player.aim_direction()
	var best: ZzPlayer = null
	var best_dot := 0.82

	for other in survivors():
		if other == player or other.watching or not other.is_alive():
			continue

		if other.is_down() != down:
			continue

		var middle := other.feet() + Vector3(0.0, 0.3 if down else 1.0, 0.0)

		if eye.distance_to(middle) > reach + 0.8:
			continue

		var to := (middle - eye).normalized()
		var d := aim.dot(to)

		# A downed survivor on the floor at your feet is "looked at" from a wider angle: nobody
		# aims a revive.
		if down:
			d += 0.15

		if d > best_dot and clear_between(eye, middle):
			best_dot = d
			best = other

	return best


func _take_pills(player: ZzPlayer) -> void:
	if player.pills <= 0:
		return

	if player.health.health >= player.health.max_health - 1.0:
		refused.emit(player.player_id, "You are not hurt.")
		return

	player.pills -= 1
	var landed := player.grant_temp(config.pills_health)
	player_healed.emit(player.player_id, player.player_id, landed)


func _heal_with_kit(who: ZzPlayer, healer: ZzPlayer) -> void:
	if who == null or healer.medkits <= 0:
		return

	healer.medkits -= 1
	var missing := who.health.max_health - who.real_health()
	who.temp_health = 0.0
	who.health.health = who.real_health()
	var landed := who.heal_real(missing * config.medkit_heal_fraction)
	# A medkit is the genre's reset of the black-and-white: the next down is not death.
	who.incaps = 0

	if who != healer:
		healer.points += 2

	player_healed.emit(who.player_id, healer.player_id, landed)

	if progress != null:
		progress.on_healed(healer.player_id, who.player_id)


## A shove: staggers every zombie in front of [param player], and knocks a special off a friend.
func _shove(player: ZzPlayer) -> void:
	if now() < player.shove_ready_at:
		return

	var origin := player.feet()
	var facing := player.aim_direction()

	if horde != null:
		var _moved := horde.shove(origin, facing, config.shove_range, config.shove_half_angle,
			player.entity_id, config.shove_damage)

	# A friend in reach with something on them, or their something in reach: off it comes.
	if pins != null:
		for victim: StringName in pins.pins.keys():
			var friend := player_by_id(victim)
			var holder := pins.holder_of(victim)

			if friend == null or friend == player:
				continue

			var near_friend := friend.feet().distance_to(origin) <= config.shove_range + 0.5
			var near_holder := holder != null and holder.position().distance_to(origin) <= config.shove_range + 0.5

			if near_friend or near_holder:
				if pins.shoved(victim):
					player.points += 2

					if progress != null:
						progress.on_saved(player.player_id)

	# Fatigue: shoving four times in a row tires you.
	player.shove_streak = player.shove_streak + 1 if now() - player.shove_ready_at < 1.0 else 1
	var tired := maxf(float(player.shove_streak - 4), 0.0) * config.shove_fatigue
	player.shove_ready_at = now() + config.shove_cooldown + tired


# --- Hurting survivors --------------------------------------------------------------------------

## A zombie's swing landed. The difficulty is applied here, once.
func zombie_hit(npc: DotNpcInstance, entity: int, victim: StringName, amount: float) -> void:
	var player := player_by_id(victim)

	if player == null or not player.is_alive() or combat == null:
		return

	var scaled := amount * config.damage_scale()

	# A special's own ability is not scaled as hard as the crowd: on expert a common's hit is
	# five times normal, and a brute's punch five times its normal is two downs in one swing.
	if npc != null and ZzNpcs.is_special(npc.def.id):
		scaled = amount * lerpf(1.0, config.damage_scale(), 0.35)

	var hit := DotDamage.make(entity, player.entity_id, scaled, combat.damage_type(&"bite"))
	hit.point = player.feet() + Vector3(0.0, 1.0, 0.0)
	hit.direction = (player.feet() - (npc.position() if npc != null else player.feet())).normalized()
	hit.tick = _tick
	hit.weapon_id = npc.def.id if npc != null else &"zombie"
	hit.context = {"why": BY_SPECIAL if npc != null and ZzNpcs.is_special(npc.def.id) else BY_ZOMBIE}
	var _applied := combat.apply_damage(hit)

	if player.is_up() and npc != null and npc.def.id == ZzNpcs.COMMON:
		var _tagged := player.controller.add_modifier(ZzController.TAGGED)

	player_hurt.emit(victim, scaled, npc.position() if npc != null else player.feet())


## A pin's damage over time.
func pin_damage(npc: DotNpcInstance, entity: int, victim: StringName, amount: float, _kind: StringName) -> void:
	var player := player_by_id(victim)

	if player == null or not player.is_alive():
		return

	var hit := DotDamage.make(entity, player.entity_id, amount * lerpf(1.0, config.damage_scale(), 0.35), combat.damage_type(&"bite"))
	hit.tick = _tick
	hit.weapon_id = npc.def.id if npc != null else &"special"
	hit.context = {"why": BY_SPECIAL}
	var _applied := combat.apply_damage(hit)
	player_hurt.emit(victim, amount, npc.position() if npc != null else player.feet())


## Damage from standing somewhere: acid, fire. Gathered and paid in whole points.
func hazard_damage(player: ZzPlayer, amount: float, owner: int, kind: StringName) -> void:
	var owed := float(_hurt_backlog.get(player.player_id, 0.0)) + amount

	if owed < 1.0:
		_hurt_backlog[player.player_id] = owed
		return

	_hurt_backlog[player.player_id] = owed - floorf(owed)
	var hit := DotDamage.make(owner, player.entity_id, floorf(owed), combat.damage_type(kind))
	hit.tick = _tick
	hit.weapon_id = kind
	hit.context = {"why": BY_HAZARD}
	var _applied := combat.apply_damage(hit)
	player_hurt.emit(player.player_id, floorf(owed), player.feet())


## Thrown sideways by something big: damage, and a knock away from [param from].
func knock_survivor(victim: StringName, from: Vector3, amount: float, owner: int) -> void:
	var player := player_by_id(victim)

	if player == null or not player.is_alive():
		return

	if amount > 0.0:
		var npc: DotNpcInstance = horde.npc_for_entity(owner) if horde != null else null
		zombie_hit(npc, owner, victim, amount)

	if player.is_up() and not player.is_pinned():
		var _knocked := player.controller.add_modifier(ZzController.knock_toward(player.feet() - from))


func rock_hit(victim: StringName, at: Vector3, amount: float, owner: int) -> void:
	knock_survivor(victim, at, amount, owner)


## Covered in bile: blinded for a while, and every common in earshot is coming.
func bile_survivor(victim: StringName, seconds: float, _owner: int) -> void:
	var player := player_by_id(victim)

	if player == null or not player.is_alive():
		return

	player.biled_until = maxf(player.biled_until, now() + seconds)
	player.biled = true

	if horde != null:
		horde.bile_on(victim, seconds)

	player_biled.emit(victim, seconds)


## A zombie burning: fire damage, credited to nobody.
func burn_zombie(npc: DotNpcInstance, amount: float) -> void:
	if horde == null or combat == null:
		return

	var entity := horde.entity_id_for(npc)

	if entity == 0:
		return

	var hit := DotDamage.make(0, entity, amount, combat.damage_type(&"fire"))
	hit.tick = _tick
	hit.weapon_id = &"fire"
	var _applied := combat.apply_damage(hit)


## An explosion: zombies take all of it and stagger, survivors take [param survivor_scale] of it.
func explode(at: Vector3, radius: float, amount: float, owner: int, kind: StringName, survivor_scale: float) -> void:
	if combat == null:
		return

	if horde != null:
		for npc in horde.spawner.npcs_near(at, radius):
			var entity := horde.entity_id_for(npc)
			var falloff := 1.0 - clampf(npc.position().distance_to(at) / radius, 0.0, 0.9)
			var hit := DotDamage.make(owner, entity, amount * falloff, combat.damage_type(&"blast"))
			hit.point = npc.position()
			hit.direction = (npc.position() - at).normalized()
			hit.tick = _tick
			hit.weapon_id = kind
			var _a := combat.apply_damage(hit)

		horde.blast(at, radius * 1.2)
		horde.sounds.emit(DotNpcAiSounds.Kind.COMBAT, at, 50.0, horde.now(), 0.5)

	if survivor_scale > 0.0:
		for player in survivors_within(at, radius, 3.0):
			var falloff := 1.0 - clampf(player.feet().distance_to(at) / radius, 0.0, 0.9)
			var hurt := DotDamage.make(0, player.entity_id, amount * survivor_scale * falloff, combat.damage_type(&"blast"))
			hurt.tick = _tick
			hurt.weapon_id = kind
			hurt.context = {"why": BY_HAZARD}
			var _b := combat.apply_damage(hurt)

			if player.is_up() and not player.is_pinned():
				var _knocked := player.controller.add_modifier(ZzController.knock_toward(player.feet() - at))

	exploded.emit(at, radius, kind)


# --- Health ------------------------------------------------------------------------------------

func _on_player_damaged(player: ZzPlayer, damage: DotDamage) -> void:
	if damage.health_lost <= 0.0:
		return

	player.absorb_temp(damage.health_lost)
	player.damage_taken_map += damage.health_lost

	var attacker := player_for_entity(damage.attacker)

	if attacker != null and attacker != player:
		attacker.friendly_damage += damage.health_lost

	# Hurt while holding E: a revive or a heal is interrupted by a hit, as the genre has it,
	# only when the hit is a real one.
	if damage.health_lost >= 5.0 and player.using == &"heal":
		cancel_use(player)


## Health reached zero: down, unless this is the one too many.
func _on_health_zero(player: ZzPlayer, damage: DotDamage) -> void:
	var why: StringName = damage.context.get("why", BY_ZOMBIE)
	var by := _blame(damage)

	if player.life == ZzPlayer.Life.UP and player.incaps < config.max_incaps and why != BY_FELL:
		_go_down(player, by, why)
	else:
		_die(player, by, why, damage)


func _blame(damage: DotDamage) -> StringName:
	var attacker := player_for_entity(damage.attacker)

	if attacker != null:
		return attacker.player_id

	if horde != null:
		var npc := horde.npc_for_entity(damage.attacker)
		if npc != null:
			return StringName("%s" % npc.def.id)

	return &""


func _go_down(player: ZzPlayer, by: StringName, why: StringName) -> void:
	player.life = ZzPlayer.Life.DOWN
	player.incaps += 1
	player.temp_health = 0.0
	player.health.max_health = config.downed_health
	player.health.revive(1.0)
	cancel_use(player)

	if boxes != null:
		boxes.drop_carried(player)
		_sync_carry(player)

	var _down := player.controller.add_modifier(ZzController.DOWN)
	var _unlimp := player.controller.remove_modifier(ZzController.LIMP)
	player.fit_hitboxes()

	# The sidearm comes out: a downed survivor can still shoot, with what is in their hand.
	if player.weapons != null and player.weapons.arsenal != null:
		var sidearm := player.weapons.arsenal.catalogue.get_def(StringName(config.start_weapons[0]))
		if sidearm != null and player.weapons.arsenal.carries(sidearm.id):
			var _drawn := player.weapons.arsenal.select(sidearm.slot, _tick)
			player.wanted_slot = sidearm.slot

	if progress != null:
		progress.on_downed(player.player_id)

	player_downed.emit(player.player_id, by, why)
	DotLog.debug(CHANNEL, "survivor down", {"id": String(player.player_id), "by": String(by), "incaps": player.incaps})


func _revive(player: ZzPlayer, by: ZzPlayer) -> void:
	if player == null or not player.is_down():
		return

	player.life = ZzPlayer.Life.UP
	player.health.max_health = config.max_health
	player.health.health = config.revive_health
	player.temp_health = maxf(config.revive_health - 1.0, 0.0)
	player.helped_fraction = 0.0
	var _up := player.controller.remove_modifier(ZzController.DOWN)
	player.fit_hitboxes()

	if by != null:
		by.revives_done += 1
		by.points += 3

		if progress != null:
			progress.on_revived(by.player_id)

	player_revived.emit(player.player_id, by.player_id if by != null else &"")


## Stands a downed survivor up without anybody holding E: a box's doing.
func stand_up(player: ZzPlayer) -> void:
	_revive(player, null)


func _die(player: ZzPlayer, by: StringName, why: StringName, damage: DotDamage = null) -> void:
	if player.life == ZzPlayer.Life.DEAD:
		return

	player.life = ZzPlayer.Life.DEAD
	player.health.health = 0.0
	player.health.alive = false
	player.died_at = now()
	player.temp_health = 0.0
	cancel_use(player)

	if boxes != null:
		boxes.drop_carried(player)
		_sync_carry(player)

	if pins != null:
		pins.release(player.player_id, &"died")

	for id in [ZzController.DOWN, ZzController.PINNED, ZzController.LIMP, ZzController.BUSY]:
		var _off := player.controller.remove_modifier(id)

	if spectate != null and authoritative:
		spectate.on_died(player.player_id, by, why == BY_FELL, player.feet(), map.kill_height() + 8.0, _tick)

	if progress != null:
		progress.on_died(player.player_id)

	if match_node != null:
		match_node.report_kill(String(by), String(player.player_id), why, _tick)

	# How the body falls, picked once, here, and carried on DEATH to every client.
	player.death = decide_death(player, damage)

	player_died.emit(player.player_id, by, why)
	DotLog.debug(CHANNEL, "survivor dead", {"id": String(player.player_id), "by": String(by), "why": String(why)})


## The fall a survivor's death gets: dot-player-char's reaction rule over the server's weights,
## seeded from the player and the tick. The killing hit's direction when it had one, else away
## from whoever did it (a zombie's claw carries none); bleeding out and falling push nothing.
## A friend's gun is a weapon def, so a heavy one may launch the body as it would a zombie.
func decide_death(player: ZzPlayer, damage: DotDamage) -> DotPlayerDeath:
	var direction := Vector3.ZERO
	var headshot := false
	var amount := 0.0
	var weapon: Object = null

	if damage != null:
		direction = damage.direction
		headshot = damage.is_headshot()
		amount = damage.amount
		weapon = ZzWeapons.def_of(damage.weapon_id) if damage.weapon_id != &"" else null

		if direction.length_squared() < 0.0001 and damage.attacker != 0:
			var from := Vector3.INF
			var attacker := player_for_entity(damage.attacker)
			if attacker != null and attacker != player:
				from = attacker.feet()
			elif horde != null:
				var npc := horde.npc_for_entity(damage.attacker)
				if npc != null:
					from = npc.position()
			if from != Vector3.INF:
				direction = (player.feet() - from) * Vector3(1, 0, 1)

	return DotPlayerDeath.decide(
		ragdoll_rules.reactions(), headshot, amount, direction,
		DotPlayerDeath.seed_of(player.entity_id, _tick), weapon
	)


## A dead survivor back in, beside whoever is furthest along. A box's, or the rescue clock's.
func rescue(player: ZzPlayer) -> bool:
	if player == null or player.life != ZzPlayer.Life.DEAD or phase == Phase.IDLE:
		return false

	var buddy := _furthest_survivor(player.player_id)

	if buddy == null:
		return false

	player.life = ZzPlayer.Life.UP
	player.watching = false
	player.incaps = 0
	player.died_at = -1.0
	player.health.max_health = config.max_health
	player.health.revive(0.5)
	player.temp_health = 0.0
	player.fit_hitboxes()
	player.place_at(buddy.feet() + Vector3(0.5, 0.2, 0.5), buddy.controller.state.yaw)
	_equip(player, false)

	if spectate != null:
		spectate.on_spawned(player.player_id)

	player_rescued.emit(player.player_id)
	notice.emit("%s was rescued." % player.display_name)
	return true


## Every tick on the authority: bleeding, limping, borrowed health, bile, burning, the rescue.
func _advance_bodies(delta: float) -> void:
	var now_s := now()

	for player in survivors():
		if player.watching:
			continue

		if player.is_down():
			player.health.health -= config.downed_bleed_per_second * delta

			if player.health.health <= 0.0:
				_die(player, &"", BY_BLED)
				continue

		if player.is_up():
			player.decay_temp(config.temp_decay_per_second * delta)
			var limping := player.real_health() + player.temp_health < config.limp_health

			if limping != player.controller.has_modifier(ZzController.LIMP):
				if limping:
					var _l := player.controller.add_modifier(ZzController.LIMP)
				else:
					var _u := player.controller.remove_modifier(ZzController.LIMP)

		player.biled = player.biled_until > now_s
		player.burning = player.burning_until > now_s
		player.box_blind = boxes != null and boxes.is_blind(player.player_id)

		if player.life == ZzPlayer.Life.DEAD and config.rescue_seconds > 0.0 and phase == Phase.PLAY \
				and player.died_at >= 0.0 and now_s - player.died_at >= config.rescue_seconds:
			var _back := rescue(player)

		# Below the map is death, not a down.
		if player.is_alive() and player.feet().y < map.kill_height():
			if can_be_harmed(player.player_id):
				_die(player, &"", BY_FELL)
			else:
				# Under the cover nothing may kill it, but it cannot be left falling either.
				var spot := map.spawn("survivors", 0)
				player.place_at(spot[0], spot[1])


# --- Zombies dying ------------------------------------------------------------------------------

func _on_zombie_died(npc: DotNpcInstance, killer: StringName, damage: DotDamage) -> void:
	var kind := npc.def.id
	var at := npc.position()
	var headshot := damage != null and damage.hit_group == DotHitGroup.HEAD
	var player := player_by_id(killer)

	if player != null:
		if kind == ZzNpcs.COMMON:
			player.commons_killed += 1
			player.points += 1
		else:
			player.specials_killed += 1
			player.points += 5 if kind != ZzNpcs.BRUTE else 25

		if progress != null:
			progress.on_zombie_killed(player.player_id, kind, headshot)

	# The bloater bursts whatever killed it: bile on everybody close, and a shove.
	if kind == ZzNpcs.BLOATER:
		var reach := float(npc.def.meta.get("burst_radius", 3.6))

		for victim in survivors_within(at, reach, 2.0):
			bile_survivor(victim.player_id, float(npc.def.meta.get("bile_seconds", 15.0)), 0)

		if horde != null:
			horde.blast(at, reach)

		exploded.emit(at, reach, &"bile")

	# A spitter leaves a little of itself.
	if kind == ZzNpcs.SPITTER and hazards != null:
		var _pool := hazards.add(ZzHazards.ACID, at, 1.6, 4.0, 3.0, 0)

	if boxes != null and config.boxes_enabled:
		boxes.maybe_drop(kind, at)

	zombie_killed.emit(kind, killer, headshot)


# --- Weapons ------------------------------------------------------------------------------------

## Hands [param player] a weapon, building their rig the first time.
func arm(player: ZzPlayer, weapon_id: StringName) -> bool:
	if player.weapons == null:
		var rig := ZeeWeaponRig.new()
		rig.name = "Weapons"
		rig.role = ZeeWeaponRig.Role.SERVER
		rig.authority = authoritative
		rig.tick_rate = tick_rate
		rig.player_ref = DotNodeRef.of_path(player.get_path())
		player.add_child(rig)

		var ready_now := rig.setup()

		if not ready_now.ok:
			DotLog.warn(CHANNEL, "a weapon rig would not set up", {"player": String(player.player_id), "why": ready_now.error.message})
			player.remove_child(rig)
			rig.queue_free()
			return false

		player.weapons = rig

	if not player.weapons.give(weapon_id).ok:
		return false

	player_armed.emit(player.player_id, weapon_id)
	return true


func _disarm(player: ZzPlayer) -> void:
	if player.weapons == null:
		return

	player.remove_child(player.weapons)
	player.weapons.queue_free()
	player.weapons = null
	player_disarmed.emit(player.player_id)


## Everybody's guns. Down, you still shoot; pinned or busy, you do not.
func _advance_weapons() -> void:
	if combat == null:
		return

	for id: StringName in players:
		var player: ZzPlayer = players[id]

		if player.weapons == null or not player.is_alive() or player.watching:
			continue

		var command := weapon_command_for(player)
		command.yaw = player.controller.state.yaw
		command.pitch = player.controller.state.pitch
		var outcome := player.weapons.simulate_tick(command, _tick)

		for shot in outcome.shots:
			shot.attacker = player.entity_id
			shot.tick = _tick
			_shoot_toys(shot)
			var _resolved := combat.resolve_shot(shot)

			if horde != null:
				var def := player.weapons.current_def()
				var quiet := def != null and def.tags.has(&"silenced")
				horde.sounds.emit(DotNpcAiSounds.Kind.COMBAT, shot.origin,
					config.gunfire_radius * (0.35 if quiet else 1.0), horde.now(), 0.5, id)

		if authoritative and hazards != null:
			for spawn in outcome.spawns:
				_throw(player, spawn)


## What a weapon put into the world, as one of [ZzHazards]' projectiles.
##
## [b]dot-weapon spawns nothing; it says what should exist.[/b] Until this was here every
## grenade, sticky charge and rocket in the game was a use that cost ammunition and did
## nothing at all: `_advance_weapons` resolved `outcome.shots` and dropped `outcome.spawns`.
## A pack says what a throwable is by its tags (`molotov`, `pipe_bomb`, `bile`, as
## zed-dot-weapons' are), so a pack the game has never heard of still throws the right thing;
## anything else explosive is a grenade on its fuse, or on contact without one.
func _throw(player: ZzPlayer, spawn: DotWeaponSpawn) -> void:
	var def := ZzWeapons.def_of(spawn.id)
	var tags: Array = def.tags if def != null else []
	var amount := spawn.splash_damage if spawn.splash_damage > 0.0 else spawn.damage
	var kind := ZzHazards.GRENADE

	if tags.has(&"molotov"):
		kind = ZzHazards.MOLOTOV
		amount = maxf(amount, 8.0)
	elif tags.has(&"pipe_bomb"):
		kind = ZzHazards.PIPE
		amount = maxf(amount, 300.0)
	elif tags.has(&"bile"):
		kind = ZzHazards.BILE

	# A launcher's shell that barely drops is drawn and flown as a rocket: straight, on both
	# ends (a client is told only the start and the velocity, and falls by full gravity).
	var gravity := spawn.gravity_scale

	if kind == ZzHazards.GRENADE and spawn.gravity_scale < 0.5:
		kind = ZzHazards.ROCKET
		gravity = 0.0

	var fuse := float(spawn.fuse_ticks) / float(maxi(tick_rate, 1)) if kind == ZzHazards.GRENADE else -1.0
	var _id: int = hazards.launch(kind, spawn.origin, spawn.velocity, player.entity_id, amount,
		fuse, spawn.splash_radius, gravity)


## The command [param player]'s gun simulates this tick, from the buttons on their movement
## command. `ZzWeapons.command_for` is the rule, shared with the gun a client draws.
func weapon_command_for(player: ZzPlayer) -> DotWeaponCommand:
	var pending := player.controller.current_command
	var arsenal := player.weapons.arsenal if player.weapons != null else null

	if pending == null:
		return ZzWeapons.command_for(false, false, player.is_held(), 0.0, 0.0, player.wanted_slot, arsenal)

	return ZzWeapons.command_for(pending.is_pressed(ZzNetCommand.BUTTON_FIRE),
		pending.is_pressed(ZzNetCommand.BUTTON_RELOAD), player.is_held(), pending.yaw, pending.pitch,
		player.wanted_slot, arsenal)


# --- The tick ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not authoritative or match_node == null or external_tick:
		return

	simulate(delta)


## Asked every tick of a world that ticks itself: true while a cover is up (the client's load
## gate). Only the bodies are stepped then, so the director, waves, hazards, clocks and damage
## do not act on anybody in front of a picture. Unset, never held.
var hold_clock: Callable = Callable()


## One tick, counted by this world. What an offline client and the suite use.
func simulate(delta: float) -> void:
	_tick += 1

	if hold_clock.is_valid() and bool(hold_clock.call()):
		_step_bodies_only(delta)
		return

	_step(delta)


## A tick under a cover: the bodies move and settle, nothing else happens. A body the gate has
## frozen skips itself (see [method ZzPlayer.simulate]).
func _step_bodies_only(delta: float) -> void:
	for id: StringName in players:
		var player: ZzPlayer = players[id]

		if player.is_alive() and not player.watching:
			player.simulate(_tick, delta)


## One tick, numbered by the netcode. What the bridge uses.
func tick_once(tick: int) -> void:
	if match_node == null:
		return

	_tick = tick
	_step(delta_for_tick())


func current_tick() -> int:
	return _tick


## Simulated seconds, from the tick. What every timer in the game counts.
func now() -> float:
	return float(_tick) / float(maxi(tick_rate, 1))


func _step(delta: float) -> void:
	_advance_phase(delta)

	if authoritative and bots != null:
		bots.drive(delta)

	if pins != null:
		pins.steer(delta)

	for id: StringName in players:
		var player: ZzPlayer = players[id]

		if player.is_alive() and not player.watching:
			player.simulate(_tick, delta)
			_advance_water(player, delta)

			if authoritative:
				_advance_hands(player, delta)

		if authoritative and not player.is_bot:
			player.session_seconds += delta

			if progress != null:
				progress.add_playtime(id, delta)

	_advance_weapons()

	if authoritative:
		_advance_toys(delta)
		if horde != null:
			horde.tick(delta)
		if pins != null:
			pins.advance(delta)
		if hazards != null:
			hazards.tick(delta)
		if turrets != null:
			turrets.tick(delta)
		if boxes != null:
			boxes.tick(delta)
		if loot != null:
			loot.tick(delta)
		_advance_bodies(delta)

	if combat != null:
		combat.tick(_tick, delta)

	if spectate != null:
		spectate.advance(_tick)

	if not sides_are_playable() and phase == Phase.IDLE:
		return

	match_node.tick(_tick)


# --- Toys ----------------------------------------------------------------------

## A blast's speed at its centre, m/s to a toy (dot-props' `blast`).
const TOY_BLAST_SPEED := 12.0


## Every survivor against the map's toys, after they moved: a walk into a barrel or a ball
## sends it on; then the box's own tick (the awake cap, the lost sent home). Server side.
## Zombies walk through them: a crowd that shoved barrels about would be a crowd steering
## round its own debris.
func _advance_toys(delta: float) -> void:
	if map == null or map.toys == null or map.toys.count() == 0:
		return
	for id: StringName in players:
		var player: ZzPlayer = players[id]
		if not player.is_alive() or player.watching:
			continue
		var state := player.controller.state
		var tunables := player.controller.tunables
		var radius := tunables.radius if tunables != null else 0.35
		var height := lerpf(tunables.stand_height, tunables.crouch_height, state.crouch_fraction) if tunables != null else 1.8
		var _pushed := map.toys.push_from(state.position, state.velocity, radius, height)
	map.toys.advance(delta)


## A survivor's shot against the toys: the first one on its ray, nearer than a wall, is pushed
## (dot-props' `shot_along`). The shot goes on to the combat, whose trace never sees a toy, so
## a barrel is never cover between a survivor and a zombie. Server side.
func _shoot_toys(shot: DotShot) -> void:
	if not authoritative or map == null or map.toys == null or map.toys.count() == 0:
		return
	var directions: Array = shot.pellets if not shot.pellets.is_empty() else [shot.direction]
	for raw: Variant in directions:
		var _pushed := map.toys.shot_along(shot.origin, raw as Vector3, maxf(shot.max_range, 1.0), shot.damage, world_mask())


func _on_exploded_near_toys(at: Vector3, radius: float, _kind: StringName) -> void:
	if authoritative and map != null and map.toys != null:
		var _thrown := map.toys.blast(at, maxf(radius, 2.0), TOY_BLAST_SPEED)


func delta_for_tick() -> float:
	return 1.0 / float(maxi(tick_rate, 1))


func set_tick_rate(rate: int) -> bool:
	if rate <= 0 or rate == tick_rate:
		return false

	tick_rate = rate

	for id: StringName in players:
		(players[id] as ZzPlayer).tick_rate = rate

	if match_node != null and match_node.config != null:
		match_node.config.tick_rate = rate

	return true


# --- Asking the world ------------------------------------------------------------------------

## Whether nothing solid is between two points: the walls and the furniture.
func clear_between(from: Vector3, to: Vector3) -> bool:
	var world := get_world_3d()

	if world == null:
		return true

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = world_mask()
	return world.direct_space_state.intersect_ray(query).is_empty()


## Where a segment first hits the world, or INF.
func ray_hit(from: Vector3, to: Vector3) -> Vector3:
	var world := get_world_3d()

	if world == null:
		return Vector3.INF

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = world_mask()
	var hit := world.direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else Vector3.INF


## The nearest acid or fire within [param radius], or INF. For a rider steering its victim.
func nearest_hazard(at: Vector3, radius: float) -> Vector3:
	if hazards == null:
		return Vector3.INF

	var best := Vector3.INF

	for id: int in hazards.areas:
		var a: Dictionary = hazards.areas[id]

		if a["kind"] == ZzHazards.HEAL:
			continue

		var p: Vector3 = a["at"]

		if p.distance_to(at) <= radius and (best == Vector3.INF or p.distance_to(at) < best.distance_to(at)):
			best = p

	return best


# --- Reporting -----------------------------------------------------------------------------------

func describe() -> Dictionary:
	var out := {
		"round": round_number,
		"phase": Phase.keys()[phase],
		"map": str(map_doc.get("id", "-")),
		"mode": str(map_doc.get("mode", "-")),
		"players": players.size(),
		"alive": alive_on(SURVIVORS),
		"decided": _why if _decided else "-",
		"maps": catalogue.maps.size() if catalogue != null else 0,
		"phase_id": phase,
	}

	if is_survival():
		out["held"] = "%s of %s" % [_clock(survival_elapsed), _clock(survival_goal) if survival_goal > 0.0 else "endless"]
		if survival != null:
			out["survival"] = survival.describe()

	var index := current_objective()
	if index >= 0:
		out["objective"] = "%s (%s)" % [str(((map_doc["objectives"] as Array)[index] as Dictionary)["label"]), objective_states[index]]

	return out


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray(["zombiezone, map %d" % round_number])
	var facts := describe()

	for key: String in facts:
		lines.append("  %-10s %s" % [key, facts[key]])

	for id: StringName in players:
		var player: ZzPlayer = players[id]
		var d := player.describe()
		lines.append("  %-18s %-5s %s %s" % [player.display_name, d["life"], d["health"], d["pinned"]])

	if horde != null:
		lines.append("horde")
		lines.append_array(horde.describe_lines())

	if pins != null and not pins.pins.is_empty():
		lines.append("pins")
		lines.append_array(pins.describe_lines())

	if map != null:
		lines.append_array(map.describe_lines())

	return lines
