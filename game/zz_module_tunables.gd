extends "zz_module_base.gd"

## The game module's cvars: every tunable of the config, its range check and its friendly-fire hook.

## The numbers an operator will want to change, as cvars: live, each writing through to the
## configuration the world already reads. Pacing changes the next clock, not the one running;
## `zz_difficulty` is live for every hit.
func _add_tunables(world: ZzGame) -> void:
	var config := world.config

	_tunable("zz_difficulty", float(config.difficulty),
		"0 easy, 1 normal, 2 advanced, 3 expert: what a hit does, what a special takes, friendly fire",
		func(value: float) -> void:
			config.difficulty = clampi(int(value), 0, 3)
			_apply_friendly_fire(world))
	_tunable("zz_trader", float(config.trader_enabled),
		"The trader: 0 none on any map, 1 one; -1 reads game.shop.enabled in spawner.yml",
		func(value: float) -> void: config.trader_enabled = clampi(int(value), -1, 1))
	_tunable("zz_trader_when", float(config.trader_when),
		"When the trader sells: 0 the setup period only, 1 also a survival map's breathers, 2 always; -1 reads the file",
		func(value: float) -> void: config.trader_when = clampi(int(value), -1, 2))
	_tunable("zz_trader_despawn", float(config.trader_despawn),
		"1 the shelf is gone while closed, 0 it stays standing and will not sell; -1 reads the file",
		func(value: float) -> void: config.trader_despawn = clampi(int(value), -1, 1))
	_tunable("zz_start_points", float(config.start_points),
		"Points every survivor starts a map with (a prior balance above it is kept); -1 reads the file's per-difficulty values",
		func(value: float) -> void: config.start_points = clampi(int(value), -1, 1000000))
	_tunable("zz_friendly_fire", config.friendly_fire,
		"A teammate's bullet as a share of what it does to a zombie, before difficulty",
		func(value: float) -> void:
			config.friendly_fire = clampf(value, 0.0, 1.0)
			_apply_friendly_fire(world))
	_tunable("zz_friendly_fire_mode", float(config.friendly_fire_mode),
		"What a teammate's bullet does: 0 nothing, 1 hurts, 2 hurts but a new player's is reflected onto them, 3 everybody's is reflected",
		func(value: float) -> void:
			config.friendly_fire_mode = clampi(int(value), 0, 3)
			_apply_friendly_fire(world))
	_tunable("zz_rookie_minutes", config.rookie_minutes,
		"Minutes played under which a player is new and (mode 2) has their team damage reflected; 0 nobody is new",
		func(value: float) -> void: config.rookie_minutes = value)
	_tunable("zz_team_damage_window", config.team_damage_window,
		"Seconds team damage is added up over for the voteban and the ban",
		func(value: float) -> void: config.team_damage_window = value)
	_tunable("zz_team_damage_vote", config.team_damage_vote,
		"Team damage inside the window that starts a voteban against the player; 0 never",
		func(value: float) -> void: config.team_damage_vote = maxf(value, 0.0))
	_tunable("zz_team_damage_ban", config.team_damage_ban,
		"Team damage inside the window that bans the player outright; 0 never",
		func(value: float) -> void: config.team_damage_ban = maxf(value, 0.0))
	_tunable("zz_team_damage_ban_minutes", config.team_damage_ban_minutes,
		"Minutes the automatic ban lasts",
		func(value: float) -> void: config.team_damage_ban_minutes = maxf(value, 1.0))
	_tunable("zz_exodus_team", float(config.exodus_team),
		"Survivors (stand-ins fill) on an exodus map at least",
		func(value: float) -> void: config.exodus_team = clampi(int(value), 0, 24))
	_tunable("zz_nav_notes", 1.0 if config.nav_notes else 0.0,
		"Annotate each map (drops, chokepoints, cover) after its bake and let bots and zombies use it; 0 off",
		func(value: float) -> void: config.nav_notes = value > 0.5)
	_add_tunables_bots(world)
	_add_tunables_zombies(world)
	_add_tunables_survivors(world)
	_add_tunables_specials(world)
	_add_tunables_specials_2(world)
	_add_tunables_survival(world)
	_add_tunables_survival_2(world)


## The stand-ins' and the nav's tunables.
func _add_tunables_bots(world: ZzGame) -> void:
	var config := world.config

	_tunable("zz_bot_open_boxes", 1.0 if config.bot_open_boxes else 0.0,
		"Stand-ins pick up and open the boxes zombies drop; 0 leaves them to the humans",
		func(value: float) -> void: config.bot_open_boxes = value > 0.5)
	_tunable("zz_bot_repress_use", 1.0 if config.bot_repress_use else 0.0,
		"Stand-ins release E every few ticks while going for a box so a missed press is repeated; 0 holds it",
		func(value: float) -> void: config.bot_repress_use = value > 0.5)
	_tunable("zz_bot_defib", 1.0 if config.bot_defib else 0.0,
		"Stand-ins pick up a defibrillator and shock a dead friend back; 0 leaves it to the humans",
		func(value: float) -> void: config.bot_defib = value > 0.5)
	_tunable("zz_bot_defib_reach", config.bot_defib_reach,
		"Metres a stand-in with a defibrillator walks to a dead friend's body (1 to 200)",
		func(value: float) -> void: config.bot_defib_reach = value)
	_tunable("zz_bot_idle_seconds", config.bot_idle_seconds,
		"Seconds a stand-in that wants to move or take something may stand still before it gets another goal; 0 off",
		func(value: float) -> void: config.bot_idle_seconds = value)
	_tunable("zz_nav_cache", 1.0 if config.nav_cache else 0.0,
		"Keep each built navigation graph on disk and load it next time; 0 builds every time",
		func(value: float) -> void: config.nav_cache = value > 0.5)
	_tunable("zz_nav_threads", float(config.nav_threads),
		"Worker tasks a navigation build uses off the main thread; 0 builds on the main thread in slices",
		func(value: float) -> void: config.nav_threads = int(value))
	_tunable("zz_nav_prune_thread", 1.0 if config.nav_prune_thread else 0.0,
		"Ask the world's collision about a graph built off the main thread on a worker too; 0 asks on the main thread",
		func(value: float) -> void: config.nav_prune_thread = value > 0.5)
	_tunable("zz_nav_budget_ms", config.nav_budget_ms,
		"Milliseconds a tick a main-thread navigation build may take (zz_nav_threads 0, or no threads)",
		func(value: float) -> void: config.nav_budget_ms = value)
	_tunable("zz_unstick_seconds", config.unstick_seconds,
		"Seconds a zombie may push without progress before it is nudged free; 0 turns it off",
		func(value: float) -> void: config.unstick_seconds = value)
	_tunable("zz_nav_drop", config.nav_drop_max, "The longest drop, in metres, a zombie takes off a ledge",
		func(value: float) -> void: config.nav_drop_max = value)
	_tunable("zz_zombie_drops", 1.0 if config.zombie_drops else 0.0,
		"Zombies step down ledges the annotations found; 0 off",
		func(value: float) -> void: config.zombie_drops = value > 0.5)
	_tunable("zz_zombie_climb", 1.0 if config.zombie_climb else 0.0,
		"Zombies climb the jump ups as well (a held tower is no longer safe); 0 off",
		func(value: float) -> void: config.zombie_climb = value > 0.5)
	_tunable("zz_zombie_ladder_speed", config.zombie_ladder_speed,
		"Metres a second a zombie climbs a ladder, which lets the horde up the map's ladders; 0 keeps them off ladders (takes effect on the next graph)",
		func(value: float) -> void: config.zombie_ladder_speed = value)
	_tunable("zz_zombie_detail", 1.0,
		"Bruises and sores on the specials' skin (client look only); 0 draws the plain colour",
		func(value: float) -> void: ZzZombieView.detail = value > 0.5)
	_tunable("zz_zombie_spread", 1.0 if config.zombie_spread else 0.0,
		"Send each zombie through the least used choke on its way, not all down one route; 0 off",
		func(value: float) -> void: config.zombie_spread = value > 0.5)
	_tunable("zz_zombie_think_range", config.think_range,
		"Scales the distances past which far zombies think and move less often; below 1 is cheaper",
		func(value: float) -> void: config.think_range = value)


## The zombies' pace, thinking and native-crowd tunables.
func _add_tunables_zombies(world: ZzGame) -> void:
	var config := world.config

	_tunable("zz_body_stride_near", config.body_stride_near,
		"Metres past which a zombie's body moves every second tick; lower is cheaper",
		func(value: float) -> void: config.body_stride_near = value)
	_tunable("zz_body_stride_far", config.body_stride_far,
		"Metres past which a zombie's body moves every fourth tick; lower is cheaper",
		func(value: float) -> void: config.body_stride_far = value)
	_tunable("zz_dormant_from", config.dormant_from,
		"Metres to the nearest survivor past which a zombie thinks every zz_dormant_think_every ticks and moves every eighth; 0 off",
		func(value: float) -> void: config.dormant_from = value)
	_tunable("zz_dormant_think_every", float(config.dormant_think_every),
		"Ticks a dormant zombie's thought spans (8 to 64)",
		func(value: float) -> void: config.dormant_think_every = int(value))
	_tunable("zz_path_reuse_thoughts", float(config.path_reuse_thoughts),
		"Thoughts a zombie keeps its waypoint while its goal drifts under 3 m; 0 asks the graph every thought",
		func(value: float) -> void: config.path_reuse_thoughts = maxi(int(value), 0))
	_tunable("zz_native_crowd", 1.0 if config.native_crowd else 0.0,
		"The horde's crowd grid runs in gs-sim's native library when loaded (the same answers); 0 keeps the script",
		func(value: float) -> void: config.native_crowd = value > 0.5)
	_tunable("zz_native_threat", 1.0 if config.native_threat else 0.0,
		"The stand-in survivors rank the crowd in gs-sim's native library when loaded; 0 keeps the script",
		func(value: float) -> void: config.native_threat = value > 0.5)
	_tunable("zz_native_senses", 1.0 if config.native_senses else 0.0,
		"Zombie senses run in gs-sim's native library when loaded (the same targets); 0 keeps the script",
		func(value: float) -> void: config.native_senses = value > 0.5)
	_tunable("zz_native_brains", 1.0 if config.native_brains else 0.0,
		"Zombie chase plans and spaced headings run in gs-sim's native library when loaded (the same decisions); 0 keeps the script",
		func(value: float) -> void: config.native_brains = value > 0.5)
	_tunable("zz_native_pacing", 1.0 if config.native_pacing else 0.0,
		"Which zombies think each tick is counted in gs-sim's native library when loaded (the same thoughts); 0 keeps each brain counting",
		func(value: float) -> void: config.native_pacing = value > 0.5)
	_tunable("zz_bot_hold_chokes", 1.0 if config.bot_hold_chokes else 0.0,
		"Survival stand-ins hold behind the chokes on the horde's routes and fall back when one is overrun; 0 posts only",
		func(value: float) -> void: config.bot_hold_chokes = value > 0.5)
	_tunable("zz_bot_hold_overrun", float(config.bot_hold_overrun),
		"Zombies within 4.5 m of a choke that make it overrun",
		func(value: float) -> void: config.bot_hold_overrun = int(value))
	_tunable("zz_bot_helpers", float(config.bot_helpers),
		"Survival stand-ins that answer a pinned or downed friend (the nearest standing ones); 0 all",
		func(value: float) -> void: config.bot_helpers = int(value))
	_tunable("zz_bot_helper_radius", config.bot_helper_radius,
		"Metres within which any survival stand-in answers a pinned or downed friend",
		func(value: float) -> void: config.bot_helper_radius = value)


## Downs, rescue, the clock and the horde's pace.
func _add_tunables_survivors(world: ZzGame) -> void:
	var config := world.config

	_tunable("zz_max_incaps", float(config.max_incaps), "Downs before the next one is death",
		func(value: float) -> void: config.max_incaps = int(value))
	_tunable("zz_rescue_seconds", config.rescue_seconds,
		"Seconds before a dead survivor is rescued beside the team (0 never)",
		func(value: float) -> void: config.rescue_seconds = value)
	_tunable("zz_fall_rescue", 1.0 if config.fall_rescue else 0.0,
		"1: a survivor below the map's floor or outside its walls is put back on the last ground they stood on; 0: they die at the kill height",
		func(value: float) -> void: config.fall_rescue = value != 0.0)
	_tunable("zz_stuck_rescue_seconds", config.stuck_rescue_seconds,
		"Seconds a survivor pushes on the world without moving before they are put back on the last ground (0 off)",
		func(value: float) -> void: config.stuck_rescue_seconds = value)
	_tunable("zz_start_grace", config.start_grace_seconds,
		"Seconds the start area holds the horde off unless somebody leaves it",
		func(value: float) -> void: config.start_grace_seconds = value)
	_tunable("zz_survive_seconds", config.survive_seconds,
		"Seconds a survival map is held for when the map does not say (0 endless)",
		func(value: float) -> void: config.survive_seconds = value)
	_tunable("zz_map_on_loss", float(config.map_on_loss), "After a lost map: 0 play it again, 1 move on",
		func(value: float) -> void: config.map_on_loss = clampi(int(value), 0, 1))
	_tunable("zz_retries", float(config.retries), "Times a lost map is played again before moving on",
		func(value: float) -> void: config.retries = int(value))
	_tunable("zz_commons", float(config.commons_base), "Commons alive at once for one survivor",
		func(value: float) -> void: config.commons_base = int(value))
	_tunable("zz_commons_far_divisor", float(config.commons_far_divisor), "Past sixteen survivors each adds 1 over this of the per-survivor share",
		func(value: float) -> void: config.commons_far_divisor = int(value))
	_tunable("zz_commons_per_survivor", float(config.commons_per_survivor), "And for each survivor more",
		func(value: float) -> void: config.commons_per_survivor = int(value))
	_tunable("zz_wanderers", config.wanderer_density, "Commons standing about a map, per 100 square metres",
		func(value: float) -> void: config.wanderer_density = value)
	_tunable("zz_mob_min", config.mob_interval_min, "Seconds between mobs, from",
		func(value: float) -> void: config.mob_interval_min = value)
	_tunable("zz_mob_max", config.mob_interval_max, "Seconds between mobs, to",
		func(value: float) -> void: config.mob_interval_max = value)
	_tunable("zz_mob_size", float(config.mob_size), "Commons in a mob, for one survivor",
		func(value: float) -> void: config.mob_size = int(value))
	_tunable("zz_specials", float(config.specials_base), "Specials alive at once for one survivor",
		func(value: float) -> void: config.specials_base = int(value))
	_tunable("zz_special_min", config.special_interval_min, "Seconds between specials, from",
		func(value: float) -> void: config.special_interval_min = value)
	_tunable("zz_special_max", config.special_interval_max, "Seconds between specials, to",
		func(value: float) -> void: config.special_interval_max = value)


## The movement, body, toy, water, ambience and view rules' cvars, replicated where a client predicts or draws under them.
func _bind_rule_cvars(world: ZzGame) -> void:
	# gs-player-controller's mp_forceview (the player's choice, or one held) and mp_solidplayers
	# (survivors and stand-ins block each other, 1 by default). REPLICATED: the client places its camera
	# under the first and predicts its player under the second.
	var _views := world.view_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED
	)
	var _bodies := world.body_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED
	)
	# Dead bodies, survivors' and zombies' alike: gs-player-char's sv_ragdoll* set. The server
	# only picks each death's reaction from them; REPLICATED, because the clients draw the bodies.
	var _ragdolls := world.ragdoll_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED
	)
	# The map's toys: gs-props' sv_toys* set. REPLICATED, because a client hides the toys the
	# server took away.
	var _toys := world.toy_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED
	)
	# Whether survivors walk through barricades. REPLICATED, because a client predicts its own
	# player under it (see ZzPassRules).
	var _passing := world.pass_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED
	)

	# How fast a downed survivor crawls. REPLICATED: the DOWN modifier's speed is part of the
	# prediction (see ZzCrawlRules).
	world.crawl_rules.speed = world.config.downed_crawl_speed
	var _crawl := world.crawl_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED
	)

	# gs-mobile's touch, aim assist and auto-fire rules: REPLICATED, the overlay on a phone follows them.
	var _mobile := world.mobile_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED
	)

	# The slide's numbers (gs-player-controller's cvar table under `zz_slide`): REPLICATED, a client predicts its own slide.
	var _slide := world.slide_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED
	)

	# What a downed survivor holds and whether they crawl with it: part of the prediction (can_crawl).
	var _downed := world.downed_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED
	)

	# Aim down sights: spread and pace while aimed are part of the prediction, so the numbers the
	# simulation reads cross as one JSON cvar (see ZeeAdsRules.PREDICTED).
	var _ads := world.ads_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED
	)

	# mp_vm_* and cl_vm_kick: the view model's feel, drawn on each client, hence REPLICATED.
	var _feel := world.feel_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED
	)

	# zz_head_mult, zz_neck_mult, zz_stomach_mult, zz_leg_mult: what a hit on that zone does, for every attacker.
	if world.combat != null and world.combat.resolver.hit_groups != null:
		var _zones: Array = world.combat.resolver.hit_groups.bind_cvars(add_cvar, "zz", GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY)

	# Spread, recoil, sprint and stamina: the server's shot, and a client's prediction and view, read the same numbers.
	world.combat_feel.bind_cvars(add_cvar)

	# Water: how survivors wade, swim and drown, and how the horde wades (see ZzWaterRules). The
	# movement ones are REPLICATED, because a client predicts its own swim.
	var _water := world.water_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED,
		GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY
	)

	# The creepy ambience: on/off, level, one-shot rate and mood (see ZzAmbientRules).
	var _ambient := world.ambient_rules.bind_cvars(
		add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED,
		GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY
	)
	# The ending camera a map may ask for: the viewer's own, archived (see ZzEndCameraRules).
	var _end_camera := world.end_camera_rules.bind_cvars(add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY)


## The tunables of the specials added with the animated models.
func _add_tunables_specials(world: ZzGame) -> void:
	var config := world.config

	# The specials added with the animated models. Each writes the configuration (the next map's
	# catalogue) and the live catalogue's definition (the next one spawned), because a brain
	# reads its numbers from its definition.
	_tunable("zz_screamer_mob", float(config.screamer_mob), "Commons a screamer's scream sends at whoever it saw",
		func(value: float) -> void:
			config.screamer_mob = int(value)
			_set_meta(world, ZzNpcs.SCREAMER, "scream_mob", float(config.screamer_mob)))
	_tunable("zz_screamer_cooldown", config.screamer_cooldown, "Seconds between one screamer's screams",
		func(value: float) -> void:
			config.screamer_cooldown = value
			_set_meta(world, ZzNpcs.SCREAMER, "scream_cooldown", config.screamer_cooldown))
	_tunable("zz_crawler_grab_dps", config.crawler_grab_dps, "What a crawler's hold on an ankle does a second, on normal",
		func(value: float) -> void:
			config.crawler_grab_dps = value
			_set_meta(world, ZzNpcs.CRAWLER, "pin_dps", config.crawler_grab_dps))
	_tunable("zz_riot_shield", config.riot_shield, "Share of a hit on a riot zombie's shield that gets through (0..1)",
		func(value: float) -> void:
			config.riot_shield = clampf(value, 0.0, 1.0)
			_set_meta(world, ZzNpcs.RIOT, "shield", config.riot_shield))
	var kinds := add_cvar("zz_special_kinds", ",".join(config.special_kinds),
		"Which specials the director sends, comma separated (empty: all of %s)" % ", ".join(ZzNpcs.specials()))
	if kinds != null:
		kinds.changed.connect(func(_old: String, now: String) -> void:
			var wanted := PackedStringArray()
			for part in now.split(",", false):
				if ZzNpcs.specials().has(StringName(part.strip_edges())):
					wanted.append(part.strip_edges())
			config.special_kinds = wanted
			log_info("a tunable changed", {"cvar": "zz_special_kinds", "now": ",".join(wanted)}))
	_tunable("zz_mutant_chance", config.mutant_chance, "Chance a special roll may pick the mutant (0 never)",
		func(value: float) -> void: config.mutant_chance = clampf(value, 0.0, 1.0))
	_tunable("zz_mutant_min_wave", float(config.mutant_min_wave), "First wave the mutant can appear on",
		func(value: float) -> void: config.mutant_min_wave = maxi(int(value), 0))
	var mutant := ZzNpcs.core_def(ZzNpcs.MUTANT, config)

	for row: Array in [] if mutant == null else [["zap_damage", "Damage of one gravity-gun zap", 0.0, 100.0], ["throw_damage", "Damage of a thrown prop", 0.0, 200.0],
			["slam_damage", "Damage at the centre of the angry dive's slam", 0.0, 500.0], ["slam_radius", "Radius of the slam in metres", 1.0, 30.0],
			["fuel", "Seconds of jetpack fuel", 1.0, 120.0], ["angry_health", "Health share below which the mutant gets angry", 0.0, 1.0]]:
		var key: String = row[0]
		_tunable("zz_mutant_" + key, float(mutant.meta[key]), String(row[1]),
			func(value: float) -> void: _set_meta(world, ZzNpcs.MUTANT, key, value),
			[float(row[2]), float(row[3])])
	_tunable("zz_oil_monster_chance", config.oil_monster_chance, "Chance a special roll may pick the oil monster (0 never)",
		func(value: float) -> void: config.oil_monster_chance = clampf(value, 0.0, 1.0))
	_tunable("zz_oil_monster_min_wave", float(config.oil_monster_min_wave), "First wave the oil monster can appear on",
		func(value: float) -> void: config.oil_monster_min_wave = maxi(int(value), 0))
	# Its profile keys as cvars (`zz_oil_<key>`): the spit, the screen impair, the puddle (`goo_*`) and the trail (`trail_*`, gs-effects' GSHazardProfile keys).
	var oil_def := ZzNpcs.core_def(ZzNpcs.OIL_MONSTER, config)
	var oil: Dictionary = oil_def.meta if oil_def != null else {}

	for row: Array in OIL_TUNABLES if oil_def != null else []:
		var key: String = row[0]
		_tunable("zz_oil_" + key, float(oil[key]), String(row[1]),
			func(value: float) -> void: _set_meta(world, ZzNpcs.OIL_MONSTER, key, value),
			[float(row[2]), float(row[3])])
	_tunable("zz_brute_min", config.brute_interval_min, "Seconds between brutes, from (0 with zz_brute_max 0: never)",
		func(value: float) -> void: config.brute_interval_min = value)
	_tunable("zz_brute_max", config.brute_interval_max, "Seconds between brutes, to",
		func(value: float) -> void: config.brute_interval_max = value)
	_tunable("zz_director", 1.0 if config.director_enabled else 0.0, "Whether the build-up / peak / relax pressure runs",
		func(value: float) -> void: config.director_enabled = value > 0.5)
	_tunable("zz_sleepers", 1.0 if config.sleepers_enabled else 0.0, "Whether the maps' sleepers are there (next map)",
		func(value: float) -> void: config.sleepers_enabled = value > 0.5)
	_tunable("zz_box_drops", 1.0 if config.boxes_enabled else 0.0, "Whether zombies drop boxes",
		func(value: float) -> void: config.boxes_enabled = value > 0.5)
	_tunable("zz_box_common", config.box_drop_common, "Chance a common drops a box",
		func(value: float) -> void: config.box_drop_common = clampf(value, 0.0, 1.0))
	_tunable("zz_box_special", config.box_drop_special, "Chance a special drops a box",
		func(value: float) -> void: config.box_drop_special = clampf(value, 0.0, 1.0))


func _add_tunables_specials_2(world: ZzGame) -> void:
	var config := world.config

	_tunable("zz_box_carry", float(config.box_carry), "How many boxes a survivor carries (0: E opens them on the ground)",
		func(value: float) -> void: config.box_carry = int(value))
	_tunable("zz_box_deploy_seconds", config.box_deploy_seconds, "Seconds primary fire is held to open a carried box (0.5 to 15, default 1; the config file key is box_deploy_seconds)",
		func(value: float) -> void: config.box_deploy_seconds = value)
	_tunable("zz_revive_seconds", config.revive_seconds, "Seconds E is held to pick a downed teammate up (0.5 to 30)",
		func(value: float) -> void: config.revive_seconds = value)
	_tunable("zz_revive_range", config.revive_range, "Metres a reviver may stand from the downed (0.5 to 5)",
		func(value: float) -> void: config.revive_range = value)
	_tunable("zz_revive_health", config.revive_health, "Temporary health a revived survivor gets up with (1 to 100)",
		func(value: float) -> void: config.revive_health = value)
	_tunable("zz_revive_bleed_per_second", config.downed_bleed_per_second, "Health a downed survivor loses a second until revived (0 to 100; 0 never bleeds out)",
		func(value: float) -> void: config.downed_bleed_per_second = value)
	_tunable("zz_defib_start", float(config.start_defibs), "Whether each survivor starts a map holding a defibrillator (0 or 1)",
		func(value: float) -> void: config.start_defibs = clampi(int(value), 0, 1))
	_tunable("zz_defib_charge_seconds", config.defib_charge_seconds, "Seconds E is held at a dead teammate's body before the shock (0.5 to 30)",
		func(value: float) -> void: config.defib_charge_seconds = value)
	_tunable("zz_defib_range", config.defib_range, "Metres from the body a defibrillator works (0.5 to 5)",
		func(value: float) -> void: config.defib_range = value)
	_tunable("zz_defib_revive_fraction", config.defib_revive_fraction, "Share of maximum health the revived come back with (0.05 to 1)",
		func(value: float) -> void: config.defib_revive_fraction = clampf(value, 0.05, 1.0))
	_tunable("zz_defib_invulnerable_seconds", config.defib_invulnerable_seconds, "Seconds the revived cannot be hurt (0 to 15)",
		func(value: float) -> void: config.defib_invulnerable_seconds = value)
	_tunable("zz_defib_charges", float(config.defib_charges), "Revives one defibrillator holds (1 or more; applies to ones picked up from now)",
		func(value: float) -> void: config.defib_charges = maxi(int(value), 1))
	_tunable("zz_defib_cooldown_seconds", config.defib_cooldown_seconds, "Seconds after a shock before the item may be used again (0 to 120)",
		func(value: float) -> void: config.defib_cooldown_seconds = value)
	_tunable("zz_defib_max_body_age", config.defib_max_body_age, "Seconds after death beyond which the body is past saving (0: never)",
		func(value: float) -> void: config.defib_max_body_age = value)
	_tunable("zz_defib_move_tolerance", config.defib_move_tolerance, "Metres the user may drift while charging before it is interrupted (0.1 to 3)",
		func(value: float) -> void: config.defib_move_tolerance = value)
	_tunable("zz_defib_price", float(config.defib_price), "Points the trader asks for a defibrillator, also on trader shelves without a site price (0: not sold)",
		func(value: float) -> void: config.defib_price = int(value))
	_tunable("zz_defib_hear_range", config.defib_hear_range, "Metres from which other survivors hear a defibrillator charging (0: only its user)",
		func(value: float) -> void: config.defib_hear_range = value)
	_tunable("zz_common_speed_scaling", 1.0 if config.common_speed_scaling else 0.0, "Commons chase slowly and speed up with Hard Box stacks (1), or all run at zz_common_run_speed as before (0)",
		func(value: float) -> void: config.common_speed_scaling = value > 0.5)
	_tunable("zz_common_speed_base", config.common_speed_base, "A common's chase speed in m/s with no Hard Box stack (0.5 to 15)",
		func(value: float) -> void: config.common_speed_base = value)
	_tunable("zz_common_speed_per_hard_stack", config.common_speed_per_hard_stack, "m/s a common gains per Hard Box stack (0 to 5)",
		func(value: float) -> void: config.common_speed_per_hard_stack = value)
	_tunable("zz_common_speed_max", config.common_speed_max, "The fastest a scaled common gets, in m/s (0.5 to 15)",
		func(value: float) -> void: config.common_speed_max = value)
	_tunable("zz_angry_runner_fraction", config.angry_runner_fraction, "Share of commons that run at full speed while an Angry Box lasts (0 to 1)",
		func(value: float) -> void: config.angry_runner_fraction = clampf(value, 0.0, 1.0))
	_tunable("zz_box_labels", 1.0 if config.box_labels else 0.0, "Whether a box says its type before it is opened (default 0: the contents are a surprise, and the type is never sent)",
		func(value: float) -> void: config.box_labels = value > 0.5)
	_tunable("zz_box_instakill_min", config.box_instakill_min, "Instakill lasts at least this many seconds (negative: the box file's)",
		func(value: float) -> void: config.box_instakill_min = value)
	_tunable("zz_box_instakill_max", config.box_instakill_max, "Instakill lasts at most this many seconds (negative: the box file's)",
		func(value: float) -> void: config.box_instakill_max = value)
	_tunable("zz_box_instakill_special_scale", config.box_instakill_special_scale, "Instakill: what a special takes per hit, as a multiple",
		func(value: float) -> void: config.box_instakill_special_scale = value)
	_tunable("zz_limb_follow_health", float(config.limb_follow_health),
		"1: a limb holds as much as the zombie's real health and Instakill's boost skips limbs; 0: the old rule (later waves and Instakill strip limbs)",
		func(value: float) -> void: config.limb_follow_health = value > 0.5)
	_tunable("zz_gravity", config.gravity, "Metres per second squared, for everything",
		func(value: float) -> void: config.gravity = value)
	_tunable("zz_spectate_camera", float(config.spectate_camera),
		"Who somebody who is out may watch: 0 anybody, 1 their own side, 2 nobody",
		func(value: float) -> void:
			config.spectate_camera = clampi(int(value), 0, 2)
			if world.spectate != null:
				world.spectate.set_force_camera(config.spectate_camera))


## The tunables of how a survival map is held, the stand-ins and the zombies' skill.
func _add_tunables_survival(world: ZzGame) -> void:
	var config := world.config

	# How a survival map is held: `zz_survival waves|nights|clock` (by name or 0/1/2), and its
	# numbers. Read when a hold begins, so a change takes from the next survival map.
	var style := add_cvar("zz_survival", config.survival_style_name(),
		"How survival maps are held: waves (the default: waves to clear), nights (days to get ready, nights to live through) or clock")
	if style != null:
		style.changed.connect(func(_old: String, now: String) -> void:
			var picked := GSNpcDirectorWaves.style_from(now)
			if picked >= 0:
				config.survival_style = picked
			log_info("survival style", {"now": config.survival_style_name()}))
	var wave_set_cvar := add_cvar("sv_waves", config.waves_set,
		"Wave set survival maps play (cfg/game/game-zombie-zone/waves/<id>.yml), over a rotation entry's and the map's; empty leaves them to decide")
	if wave_set_cvar != null:
		wave_set_cvar.changed.connect(func(_old: String, now: String) -> void:
			config.waves_set = now.strip_edges()
			log_info("wave set", {"now": config.waves_set}))
	var force_cvar := add_cvar("zz_prop_force", "",
		"JSON over props/forces.json: {\"weapon id\": {\"barrel\": 2.0}} sets that weapon's push on a kind of loose prop; empty keeps the file")
	if force_cvar != null:
		force_cvar.changed.connect(func(_old: String, now: String) -> void:
			if not world.set_prop_force_override(now):
				log_info("zz_prop_force is not a JSON object, ignored", {"value": now}))
	_tunable("zz_prop_carry_mass", world.prop_carry.max_mass, "Heaviest loose prop (kg) a survivor can pick up with the use key",
		func(value: float) -> void: world.prop_carry.max_mass = value)
	_tunable("zz_waves", float(config.waves), "Waves a survival map is held for (zz_survival waves)",
		func(value: float) -> void: config.waves = int(value))
	_tunable("zz_nights", float(config.nights), "Nights a survival map is held for (zz_survival nights)",
		func(value: float) -> void: config.nights = int(value))
	_tunable("zz_breather", config.breather_seconds, "Seconds of breather between waves",
		func(value: float) -> void: config.breather_seconds = value)
	_tunable("zz_prestart_time", config.prestart_seconds, "Setup seconds before a survival map's first wave: no zombies until it ends (0 skips)",
		func(value: float) -> void: config.prestart_seconds = value)
	_tunable("zz_infect_after", config.infect_after_seconds, "Seconds into a round after which survivors turn into zombies (0 off)",
		func(value: float) -> void: config.infect_after_seconds = value)
	_tunable("zz_infect_count", float(config.infect_count), "How many survivors turn (the last never does)",
		func(value: float) -> void: config.infect_count = int(value))
	_tunable("zz_survival_warmup", config.survival_warmup_seconds, "Overrides zz_prestart_time when 0 or more (-1 follows it)",
		func(value: float) -> void: config.survival_warmup_seconds = value)
	_tunable("zz_respawn_on_wave_end", 1.0 if config.respawn_on_wave_end else 0.0, "1: the dead return as each breather begins",
		func(value: float) -> void: config.respawn_on_wave_end = value >= 0.5)
	_tunable("zz_timed_respawn", 1.0 if config.timed_respawn else 0.0, "1: a dead survivor returns after a delay (zz_respawn_* )",
		func(value: float) -> void: config.timed_respawn = value >= 0.5)
	_tunable("zz_respawn_base", config.respawn_base_seconds, "Timed respawn: base seconds",
		func(value: float) -> void: config.respawn_base_seconds = value)
	_tunable("zz_respawn_min", config.respawn_min_seconds, "Timed respawn: shortest delay",
		func(value: float) -> void: config.respawn_min_seconds = value)
	_tunable("zz_respawn_max", config.respawn_max_seconds, "Timed respawn: longest delay",
		func(value: float) -> void: config.respawn_max_seconds = value)
	_tunable("zz_respawn_healthy_scale", config.respawn_healthy_scale, "Timed respawn: multiplier with the team all up",
		func(value: float) -> void: config.respawn_healthy_scale = value)
	_tunable("zz_respawn_scarce_scale", config.respawn_scarce_scale, "Timed respawn: multiplier with few survivors up",
		func(value: float) -> void: config.respawn_scarce_scale = value)


func _add_tunables_survival_2(world: ZzGame) -> void:
	var config := world.config
	_tunable("zz_nav_notes_bake_tile", config.nav_notes_bake_tile,
		"Metres a side of the tiles a navigation bake is cut into; 0 auto (tiles only past the engine's cell limit)",
		func(value: float) -> void: config.nav_notes_bake_tile = value, [0, 0])

	_tunable("zz_respawn_per_wave", config.respawn_per_wave_seconds, "Timed respawn: seconds added per wave after the first",
		func(value: float) -> void: config.respawn_per_wave_seconds = value)
	_tunable("zz_respawn_difficulty_step", config.respawn_difficulty_step, "Timed respawn: delay fraction per difficulty step above normal",
		func(value: float) -> void: config.respawn_difficulty_step = clampf(value, 0.0, 1.0))
	_tunable("zz_respawn_protect", config.respawn_protect_seconds, "Timed respawn: seconds of invulnerability after returning",
		func(value: float) -> void: config.respawn_protect_seconds = value)
	_tunable("zz_day_seconds", config.day_seconds, "Seconds of day between nights",
		func(value: float) -> void: config.day_seconds = value)
	_tunable("zz_night_seconds", config.night_seconds, "Seconds a night lasts",
		func(value: float) -> void: config.night_seconds = value)
	_tunable("zz_wave_size", float(config.wave_size), "The first wave's commons for one survivor",
		func(value: float) -> void: config.wave_size = int(value))
	_tunable("zz_wave_size_per_survivor", float(config.wave_size_per_survivor), "And for each survivor more",
		func(value: float) -> void: config.wave_size_per_survivor = int(value))
	_tunable("zz_wave_growth", config.wave_growth, "How much bigger each wave is than the first, as a share of it",
		func(value: float) -> void: config.wave_growth = value)
	_tunable("zz_wave_twists", 1.0 if config.wave_twists else 0.0, "1: waves from the third draw a twist (sprinters, swarm, heavies, hunters)",
		func(value: float) -> void: config.wave_twists = value >= 0.5)
	_tunable("zz_brute_every", float(config.brute_every_waves), "Every this many waves a brute comes (and two with the last); 0 never",
		func(value: float) -> void: config.brute_every_waves = int(value))
	_tunable("zz_barricade_health", config.barricade_health, "A barricade's strength when the map does not say",
		func(value: float) -> void: config.barricade_health = value)
	_tunable("zz_barricade_bash", config.barricade_bash, "What one zombie's bashing takes off a barricade a second",
		func(value: float) -> void: config.barricade_bash = value)
	_tunable("zz_team_from_map", 1.0 if config.team_from_map else 0.0,
		"1: stand-ins fill to the team a map is built for (its survivors) when that is more than bot_quota",
		func(value: float) -> void: config.team_from_map = value >= 0.5)
	# [b]Deprecated: the count is `bot_quota` now[/b], and this forwards to it. Kept rather than
	# removed because every shipped server config sets it; left as its own number it would be
	# a second cvar deciding the same count, and whichever was read last would win.
	_tunable("zz_min_players", float(config.minimum_players),
		"Deprecated, sets bot_quota. How many survivors the server keeps in the game with stand-ins",
		func(value: float) -> void:
			config.minimum_players = int(value)
			if _quota != null and _quota.quota_cvar != null:
				var _set := _quota.quota_cvar.set_value(str(config.minimum_players)))
	# How the stand-ins aim and shoot is gs-bot's: `bot_difficulty` and the `bot_*` settings it bundles.
	# Kept as game metadata, where ZzBots reads it, never the registry (two servers in one process).
	# `zz_bot_reaction` stays as the old name for `bot_reaction`.
	var bot_settings := GSBotSettings.of(game)
	var _bot_cvars := bot_settings.bind_cvars(add_cvar, GSConVar.FLAG_NOTIFY, add_command)
	_tunable("zz_bot_reaction", bot_settings.profile.reaction, "Deprecated, sets bot_reaction. Seconds a stand-in takes to react to a zombie",
		func(value: float) -> void:
			var _set := bot_settings.set_value("reaction", str(value)))

	# How clever and how quick the zombies are, as gs-npc-ai's server skill: `npc_skill`
	# (-1..1 or a level), `npc_reaction_scale`, `npc_reaction_min`.
	if world.horde != null:
		var _bound := world.horde.skill.bind_cvars(add_cvar)


## Writes [param key] into the live catalogue's definition of [param kind], if there is one yet.
func _set_meta(world: ZzGame, kind: StringName, key: String, value: float) -> void:
	if world.horde == null or world.horde.catalogue == null:
		return

	var def := world.horde.catalogue.get_npc(kind)

	if def != null:
		def.meta[key] = value

func _apply_friendly_fire(world: ZzGame) -> void:
	world.apply_friendly_fire()

## A number as an operator would type it: `34`, not `34.000000`. Not `%g`: GDScript's format strings
## parse it and fail at RUNTIME inside `_game_load`, which unwinds the module sequence (a server that
## logged ready, then reported the game would not load).
static func _number(value: float) -> String:
	return "%d" % int(round(value)) if is_equal_approx(value, round(value)) else "%.3f" % value

## Empty when [param value] is inside what the cvar takes, else why not (see [ZzCaps]). The highest
## is the old hard cap, now the `cap_overrides` setting's default; 0 there is unlimited.
func _cap_refusal(cvar_name: String, value: float, range_of: Array) -> String:
	if not (game is ZzGame):
		return ""
	var errors := PackedStringArray()
	var overrides := ZzCaps.parse_overrides((game as ZzGame).config.cap_overrides, errors)
	if not errors.is_empty():
		return "; ".join(errors)
	var refused := ZzCaps.refusal(cvar_name, value, overrides, range_of)
	if not refused.is_empty():
		return refused
	if ZzCaps.PAIRS.has(cvar_name):
		return ZzCaps.pair_refusal(cvar_name, value, float((game as ZzGame).config.get(ZzCaps.PAIRS[cvar_name][0])))
	return ""

## One cvar, its default taken from the configuration rather than written twice: a literal default
## would be a second copy of what `defaults < JSON < environment < argv` decided, so `ZZ_ROUND_SECONDS=240`
## would report 300 and reset itself when written back.
func _tunable(
	cvar_name: String, current: float, description: String, apply: Callable, range_of: Array = []
) -> void:
	var cvar := add_cvar(cvar_name, _number(current), description)

	if cvar == null:
		return

	# A value outside the cvar's range is refused here, loudly (the console reports it, the log
	# carries it); nothing is clamped silently. See [ZzCaps].
	var _checked := cvar.with_validator(func(text: String) -> GSResult:
		var refused := _cap_refusal(cvar_name, text.to_float(), range_of)
		if refused.is_empty():
			return GSResult.success(text)
		log_warn(refused, {"cvar": cvar_name})
		return GSResult.fail(GSError.CODE_INVALID, refused))

	# The handler must not capture `cvar`: it would be a reference cycle the engine never frees.
	cvar.changed.connect(func(_old: String, new_value: String) -> void:
		apply.call(new_value.to_float())
		log_info("a tunable changed", {"cvar": cvar_name, "now": new_value})
	)
