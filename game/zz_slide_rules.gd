extends RefCounted

## The slide cvars (`zz_slide`, `zz_slide_boost`, `zz_slide_min_speed`, `zz_slide_duration`,
## `zz_slide_friction`, `zz_slide_cooldown`): their names, members and words are
## [method DotFpsSlidePreset.cvar_table], written once in dot-player-controller. A slide is part
## of the predicted motor, so every one is REPLICATED and a client follows it
## ([method follow_cvars]), the way [ZzCrawlRules] does for the crawl; a client that held other
## numbers would predict a slide the server does not make.
##
## ZZ's slide is the sprint one (only a sprinter holding C slides). `zz_slide_min_speed` 0 means
## the preset's own floor, just over a plain run ([constant DotFpsSlidePreset.SPRINT_MIN_FACTOR]).
## The slide's top speed is not in the shared table and stays a [ZzConfig] number.

signal changed

const PREFIX := "zz_slide"

## Members and their bounds; the cvar names and help come from the addon's table.
const LIMITS := {
	"slide_enabled": [0.0, 1.0],
	"slide_boost": [0.0, 20.0],
	"slide_min_speed": [0.0, 30.0],
	"slide_duration": [0.1, 5.0],
	"slide_friction": [0.0, 10.0],
	"slide_cooldown": [0.0, 10.0],
}

var slide_enabled: float = 1.0
var slide_boost: float = 1.5
var slide_min_speed: float = 0.0
var slide_duration: float = 0.9
var slide_friction: float = 0.0
var slide_cooldown: float = 1.0


func _init() -> void:
	slide_friction = DotFpsTunables.new().slide_friction


## cvar name -> [member, help].
static func table() -> Dictionary:
	return DotFpsSlidePreset.cvar_table(PREFIX)


## Registers the cvars ([param add] is the module's `add_cvar`, taking flags as a fourth
## argument). [param flags] should carry REPLICATED.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var out: Array = []
	var rows := table()

	for cvar_name: String in rows:
		var row: Array = rows[cvar_name]
		var made: Variant = add.call(cvar_name, str(get(row[0])), str(row[1]) + ". Players follow it.", flags)

		if not (made is Object):
			continue

		var cv := made as Object

		if cv.has_signal(&"changed"):
			cv.connect(&"changed", func(_old: Variant, new_value: Variant) -> void: set_cvar(cvar_name, str(new_value)))

		if cv.has_method(&"get_string"):
			set_cvar(cvar_name, String(cv.call(&"get_string")))

		out.append(cv)

	return out


## Follows a server's values through its link; false for an older shell's link.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false

	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false

	for cvar_name: String in table():
		var held := String(source.call(&"replicated_cvar", cvar_name, ""))

		if held != "":
			set_cvar(cvar_name, held)

	if not source.is_connected(&"replicated_cvar_changed", _on_replicated):
		source.connect(&"replicated_cvar_changed", _on_replicated)

	return true


## Sets the member a cvar names; false for a name or a value that is not one.
func set_cvar(cvar_name: String, value: String) -> bool:
	var text := value.strip_edges()
	var rows := table()

	if not text.is_valid_float() or not rows.has(cvar_name):
		return false

	var member: String = (rows[cvar_name] as Array)[0]
	var limits: Array = LIMITS[member]
	var clamped := clampf(text.to_float(), float(limits[0]), float(limits[1]))

	if not is_equal_approx(clamped, float(get(member))):
		set(member, clamped)
		changed.emit()

	return true


func _on_replicated(cvar_name: String, value: String) -> void:
	var _set := set_cvar(cvar_name, value)


## Puts the slide on [param t], ZZ's way. [param p_max_speed] is the slide's top speed
## ([member ZzConfig.slide_max_speed]); [param p_sprint] whether sprinting is on at all.
func apply(t: DotFpsTunables, p_max_speed: float, p_sprint: bool) -> void:
	DotFpsSlidePreset.apply_sprint(t, slide_enabled >= 0.5 and p_sprint, slide_boost, p_max_speed, slide_duration, slide_cooldown)
	t.slide_friction = slide_friction

	if slide_min_speed > 0.0:
		t.slide_min_speed = slide_min_speed


func describe() -> Dictionary:
	var out := {}

	for row: Array in table().values():
		out[row[0]] = get(row[0])

	return out
