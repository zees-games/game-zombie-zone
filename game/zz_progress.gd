extends Node

const ZzPlayer := preload("zz_player.gd")

## What a player keeps from a map: the numbers this game produces, and what they earn.
##
## [b]The numbers are the ones only this game has.[/b] What a co-operative survival game is
## judged by is not kills alone: it is the friends you picked up, the ones you shoved a leaper off,
## the medkits you spent on somebody else, the maps you finished, the holds you survived. Each is
## declared once, in [method schema], counted as it happens and reported by dot-stats as a DELTA —
## "add one", never "now has forty" — so two servers reporting one player add up rather than
## overwrite.
##
## [b]Achievements are rules over those numbers and nothing else.[/b] dot-achievements never
## hears about a revive; it hears that a number moved, through [DotAchievementStatsLink].
##
## [b]Stand-ins are never counted.[/b] An achievement a bot can earn is noise in every log an
## operator reads, and a stand-in's numbers are no player's numbers.
##
## [b]Server side, and on an offline client — wherever the world is authoritative.[/b]
##
## [b]A player's numbers are filed under their scoped profile key when they have one[/b] — see
## mg-wipeout's note, which this is, unchanged: [member durable_key_fn] supplies it, and
## without one the key is the world's id and lasts a connection.

const CHANNEL := "zz.progress"

# --- The numbers -------------------------------------------------------------

const MAPS_PLAYED := &"zz.maps_played"
## A campaign map finished alive, and a survival hold survived.
const MAPS_WON := &"zz.maps_won"
const HOLDS_SURVIVED := &"zz.holds_survived"
const COMMONS_KILLED := &"zz.commons_killed"
const SPECIALS_KILLED := &"zz.specials_killed"
const BRUTES_KILLED := &"zz.brutes_killed"
const SLEEPERS_KILLED := &"zz.sleepers_killed"
const HEADSHOTS := &"zz.headshots"
## The most commons killed in one map.
const BEST_MAP_KILLS := &"zz.best_map_kills"
## A teammate picked up, freed from a special, and healed with your own medkit.
const REVIVES := &"zz.revives"
const SAVES := &"zz.saves"
const TEAM_HEALS := &"zz.team_heals"
const BOXES_OPENED := &"zz.boxes_opened"
const DOWNS := &"zz.downs"
const DEATHS := &"zz.deaths"

signal earned(player_id: StringName, title: String, points: int)

var stats: DotStatsTracker = null
var achievements: DotAchievementTracker = null
var link: DotAchievementStatsLink = null

## The world's own dictionary of players, shared. See [ZzSpectate] for why not a reference to it.
var players: Dictionary = {}

## Players present when this map began. Only they have played it.
var _in_round: Dictionary = {}

## player id -> commons killed this map, for [constant BEST_MAP_KILLS].
var _map_kills: Dictionary = {}

## `func(player_id: StringName) -> String`: the durable key to file this player under, or
## "" for none. Set by the module from dot-platform; see the class note.
var durable_key_fn: Callable = Callable()

## World id -> the key their numbers are filed under, and back. Fixed at [method record]'s
## first reading for them.
var _keys: Dictionary = {}
var _ids: Dictionary = {}


# --- The documents -----------------------------------------------------------

static func ids() -> Array[StringName]:
	return [
		MAPS_PLAYED, MAPS_WON, HOLDS_SURVIVED, COMMONS_KILLED, SPECIALS_KILLED, BRUTES_KILLED,
		SLEEPERS_KILLED, HEADSHOTS, BEST_MAP_KILLS, REVIVES, SAVES, TEAM_HEALS, BOXES_OPENED,
		DOWNS, DEATHS,
	]


## Every number, once. [b]`publish` on the ones a player page would show[/b].
static func schema() -> DotStatsSchema:
	var out := DotStatsSchema.new()
	_add(out, MAPS_PLAYED, DotStatsDef.Kind.COUNTER, "Maps played", "maps", false)
	_add(out, MAPS_WON, DotStatsDef.Kind.COUNTER, "Maps finished", "maps", true)
	_add(out, HOLDS_SURVIVED, DotStatsDef.Kind.COUNTER, "Holds survived", "maps", true)
	_add(out, COMMONS_KILLED, DotStatsDef.Kind.COUNTER, "Infected killed", "kills", true)
	_add(out, SPECIALS_KILLED, DotStatsDef.Kind.COUNTER, "Specials killed", "kills", true)
	_add(out, BRUTES_KILLED, DotStatsDef.Kind.COUNTER, "Brutes killed", "kills", true)
	_add(out, SLEEPERS_KILLED, DotStatsDef.Kind.COUNTER, "Sleepers killed", "kills", true)
	_add(out, HEADSHOTS, DotStatsDef.Kind.COUNTER, "Headshot kills", "kills", true)
	_add(out, BEST_MAP_KILLS, DotStatsDef.Kind.BEST, "Most infected killed in a map", "kills", true)
	_add(out, REVIVES, DotStatsDef.Kind.COUNTER, "Teammates picked up", "revives", true)
	_add(out, SAVES, DotStatsDef.Kind.COUNTER, "Teammates freed", "saves", true)
	_add(out, TEAM_HEALS, DotStatsDef.Kind.COUNTER, "Teammates healed", "heals", true)
	_add(out, BOXES_OPENED, DotStatsDef.Kind.COUNTER, "Boxes opened", "boxes", true)
	_add(out, DOWNS, DotStatsDef.Kind.COUNTER, "Times down", "downs", false)
	_add(out, DEATHS, DotStatsDef.Kind.COUNTER, "Deaths", "deaths", false)
	return out


static func _add(
	out: DotStatsSchema, id: StringName, kind: DotStatsDef.Kind, display: String,
	unit: String, publish: bool
) -> void:
	var def := DotStatsDef.make(id, kind, display)
	def.unit = unit
	def.publish = publish
	out.stats.append(def)


## What a player can earn, as rules over [method schema]'s numbers.
##
## [b]Every stat read here is one [method schema] declares and this file records[/b] — an
## achievement over a stat nothing reports never unlocks and nothing errors.
static func catalogue() -> DotAchievementCatalogue:
	var made: Array[DotAchievement] = []

	made.append(_sum(&"zz.first_blood", "Still Breathing", COMMONS_KILLED, 1.0, 5,
		"Kill an infected.", &"zz.killer", 1))
	made.append(_sum(&"zz.exterminator", "Exterminator", COMMONS_KILLED, 1000.0, 30,
		"Kill a thousand infected.", &"zz.killer", 2))
	made.append(_sum(&"zz.special_ops", "Special Ops", SPECIALS_KILLED, 50.0, 20,
		"Kill fifty special infected."))
	made.append(_sum(&"zz.giant_slayer", "Giant Slayer", BRUTES_KILLED, 1.0, 25,
		"Be there when a brute goes down."))
	made.append(_sum(&"zz.marksman", "Dead Eye", HEADSHOTS, 250.0, 20,
		"Kill 250 infected with a headshot."))
	made.append(_sum(&"zz.medic", "Field Medic", TEAM_HEALS, 10.0, 15,
		"Heal ten teammates with your own medkit."))
	made.append(_sum(&"zz.lifeline", "Lifeline", REVIVES, 25.0, 20,
		"Pick up twenty-five downed teammates."))
	made.append(_sum(&"zz.bodyguard", "Bodyguard", SAVES, 25.0, 20,
		"Free twenty-five teammates from specials."))
	made.append(_sum(&"zz.gambler", "Gambler", BOXES_OPENED, 50.0, 15,
		"Open fifty boxes."))
	made.append(_sum(&"zz.survivor", "Survivor", MAPS_WON, 10.0, 25,
		"Finish ten maps."))
	made.append(_sum(&"zz.holdout", "Holdout", HOLDS_SURVIVED, 1.0, 20,
		"Survive a hold to the end."))

	# A BEST: a hundred in one map, not a hundred over a career.
	var rampage := DotAchievement.make(&"zz.rampage", "Rampage", [
		DotAchievementRule.make(
			BEST_MAP_KILLS, 100.0, DotAchievementRule.Op.AT_LEAST,
			DotAchievementRule.Merge.HIGHEST
		),
	])
	rampage.description = "Kill a hundred infected in one map."
	rampage.points = 25
	made.append(rampage)

	# Secret: for leaving her alone, and failing to.
	var crying := _sum(&"zz.should_have_left_her", "Should Have Left Her Alone", SLEEPERS_KILLED, 1.0, 10,
		"Kill a sleeper.")
	crying.secret = true
	made.append(crying)

	var out := DotAchievementCatalogue.new()
	out.achievements = made
	return out


static func _sum(
	id: StringName, title: String, stat: StringName, target: float, points: int,
	description: String, series: StringName = &"", tier: int = 0
) -> DotAchievement:
	var out := DotAchievement.make(id, title, [
		DotAchievementRule.make(
			stat, target, DotAchievementRule.Op.AT_LEAST, DotAchievementRule.Merge.SUM
		),
	])
	out.description = description
	out.points = points
	out.series = series
	out.tier = tier
	return out


# --- Building ---------------------------------------------------------------

## [param directory] empty keeps achievement progress in memory; see
## [member ZzConfig.progress_directory]. [param report] is [member ZzConfig.report_progress].
func setup(directory: String, report: bool) -> DotResult:
	stats = DotStatsTracker.new()
	stats.name = "Stats"
	stats.schema = schema()
	stats.report_to_backbone = report
	stats.define_on_start = report
	add_child(stats)

	var counted := stats.start()

	if not counted.ok:
		return counted.wrap("zombiezone stats")

	achievements = DotAchievementTracker.new()
	achievements.name = "Achievements"
	achievements.catalogue = catalogue()
	achievements.report_to_backbone = report
	# Not published: a server and a client in one process — every suite here — would fight
	# over one registry name, and the link below is handed the tracker directly.
	achievements.register_as = &""

	if directory != "":
		var file_store := DotAchievementStoreFile.new()
		file_store.directory = directory
		achievements.store = file_store
	else:
		achievements.store = DotAchievementStoreMemory.new()

	add_child(achievements)

	var awarded := achievements.start()

	if not awarded.ok:
		return awarded.wrap("zombiezone achievements")

	achievements.unlocked.connect(_on_unlocked)

	link = DotAchievementStatsLink.new()
	link.name = "StatsLink"
	link.tracker = achievements
	link.stats = stats
	add_child(link)

	return link.start().wrap("zombiezone's stats-to-achievements link")


# --- Counting ---------------------------------------------------------------

## Files one reading for one person, and starts counting for them the first time.
##
## [b]Begun lazily, on the first number, and that is what keeps stand-ins out.[/b] A player
## is added to the world before a bridge or a client marks them a stand-in, so a check at
## join time would see every bot as a person; by the time anything is worth counting, the
## flag is set. The memory and file stores load synchronously, so the achievement tracker
## has them before the reading that follows.
func record(player_id: StringName, stat: StringName, value: float = 1.0) -> void:
	if stats == null:
		return

	var body: ZzPlayer = players.get(player_id)

	if body == null or body.is_bot:
		return

	var key := _key(player_id)

	if not stats.has_player(key):
		stats.begin(key, body.display_name)
		_begin(key)

	var filed := stats.record(key, stat, value)

	if not filed.ok:
		# WARN: a number a player earned that nobody will ever see. It is a schema or a key
		# that is wrong, and it only ever happens for a reason worth looking at.
		DotLog.warn(CHANNEL, "a reading was refused", {
			"player": String(player_id), "stat": String(stat), "why": filed.error.message,
		})


## The key a player's numbers are filed under. Asked of [member durable_key_fn] once, then
## remembered; see the class note.
func _key(player_id: StringName) -> StringName:
	if _keys.has(player_id):
		return _keys[player_id]

	var key := player_id

	if durable_key_fn.is_valid():
		var durable := str(durable_key_fn.call(player_id))

		if durable != "":
			key = StringName(durable)

	_keys[player_id] = key
	_ids[key] = player_id
	return key


## Loads somebody's lifetime progress. A statement call, never assigned: the tracker's
## `begin` is a coroutine, and this is the family's pattern for starting one from code that
## is not — `await` inside, a bare call outside.
func _begin(player_id: StringName) -> void:
	var began: DotResult = await achievements.begin(String(player_id))

	if not began.ok:
		# WARN: this player will earn nothing this session, and they will not be told why.
		DotLog.warn(CHANNEL, "achievement progress could not be loaded", {
			"player": String(player_id), "why": began.error.message,
		})


## Saves somebody's progress as they go. See [method _begin].
func _end(player_id: StringName) -> void:
	var ended: DotResult = await achievements.end(String(player_id))

	if not ended.ok:
		DotLog.warn(CHANNEL, "achievement progress could not be saved", {
			"player": String(player_id), "why": ended.error.message,
		})


## Stops counting for somebody who left, and saves what they earned.
func leave(player_id: StringName) -> void:
	_in_round.erase(player_id)
	_map_kills.erase(player_id)

	var key: StringName = _keys.get(player_id, player_id)
	_keys.erase(player_id)
	_ids.erase(key)

	if stats == null or not stats.has_player(key):
		return

	var _values := stats.end(key)
	link.forget(String(key))
	_end(key)


func session_values(player_id: StringName) -> DotStatsValues:
	return stats.session_values(_keys.get(player_id, player_id)) \
		if stats != null else DotStatsValues.new()


## The key [param player_id]'s numbers are filed under. For a console command and a suite.
func filed_under(player_id: StringName) -> StringName:
	return _keys.get(player_id, player_id)


# --- What the world reports -------------------------------------------------

func on_round_began() -> void:
	_in_round.clear()
	_map_kills.clear()

	for id: StringName in players:
		_in_round[id] = true


## A map ended, won or lost.
func on_round_over(_won: bool) -> void:
	for id: StringName in _in_round.keys():
		if not players.has(id):
			continue

		record(id, MAPS_PLAYED)

		var kills := int(_map_kills.get(id, 0))

		if kills > 0:
			record(id, BEST_MAP_KILLS, float(kills))

	_in_round.clear()
	_map_kills.clear()


## Somebody alive at the end of a won map.
func on_survived(player_id: StringName, hold: bool) -> void:
	record(player_id, HOLDS_SURVIVED if hold else MAPS_WON)


func on_zombie_killed(player_id: StringName, kind: StringName, headshot: bool) -> void:
	match kind:
		&"common":
			record(player_id, COMMONS_KILLED)
			_map_kills[player_id] = int(_map_kills.get(player_id, 0)) + 1
		&"brute":
			record(player_id, BRUTES_KILLED)
			record(player_id, SPECIALS_KILLED)
		&"sleeper":
			record(player_id, SLEEPERS_KILLED)
		_:
			record(player_id, SPECIALS_KILLED)

	if headshot:
		record(player_id, HEADSHOTS)


func on_revived(by: StringName) -> void:
	record(by, REVIVES)


func on_saved(by: StringName) -> void:
	record(by, SAVES)


func on_healed(healer: StringName, who: StringName) -> void:
	if healer != who:
		record(healer, TEAM_HEALS)


func on_box(player_id: StringName) -> void:
	record(player_id, BOXES_OPENED)


func on_downed(player_id: StringName) -> void:
	record(player_id, DOWNS)


func on_died(player_id: StringName) -> void:
	record(player_id, DEATHS)


func _on_unlocked(player: String, achievement: DotAchievement) -> void:
	# INFO: what an admin keeps. "I did the thing and was not told" is answered here.
	DotLog.info(CHANNEL, "an achievement was unlocked", {
		"player": player, "achievement": String(achievement.id), "points": achievement.points,
	})
	# Back to the world's id: the world tells the player, and the world knows them by that.
	earned.emit(_ids.get(StringName(player), StringName(player)),
		achievement.display_name, achievement.points)


func describe() -> Dictionary:
	return {
		"tracking": stats.players().size() if stats != null else 0,
		"in_round": _in_round.size(),
		"achievements": achievements.catalogue.size() if achievements != null else 0,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	if stats != null:
		out.append_array(stats.describe_lines())

	if achievements != null:
		out.append_array(achievements.describe_lines())

	return out
