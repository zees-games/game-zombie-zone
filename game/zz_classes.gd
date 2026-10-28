extends RefCounted

## Survivor and stand-in classes as dot-player-class profiles (`cfg/game/game-zombie-zone/class/<id>.yml`).
##
## An installed pack (zz-ply-class-pack, found through [ZzPacks]) is the weakest config root, so the
## game's `cfg/` and a server's own files still win. Without any class profile the game's own numbers
## apply (a class number at -1 keeps them). Health is relative: a class's 100 is the game's `max_health`.
## The extra keys a class may carry: `models` (skin ids from [ZzAvatars]), `model_mode` (`random` per
## spawn, `select` the player picks, `first`), `persona` (a bot persona id) and `bot_weight`.

const ZzAvatars := preload("zz_avatars.gd")

const CHANNEL := "zz.classes"
const GAME := "game-zombie-zone"
const SURVIVOR := "survivor"
const MODES: Array[String] = ["random", "select", "first"]

## Process-wide state lives in Engine metadata, not static vars: a script reached by two paths
## (a suite's "../game/x.gd") is two script objects with two copies of every static.
const META_ALL := &"zz_classes_all"
const META_ROOTS := &"zz_class_roots"
const META_DEFAULT := &"zz_class_default"
const META_PACK_ROOTS := &"zz_class_pack_roots"
const META_ERRORS := &"zz_classes_errors"


## Config roots for the profile set; empty uses the defaults. Tests point it at a temp folder.
static func set_roots(roots: PackedStringArray) -> void:
	Engine.set_meta(META_ROOTS, roots)
	forget()


## Roots an installed pack contributes (weakest); [ZzPacks] sets them after its scan.
static func set_pack_roots(roots: PackedStringArray) -> void:
	Engine.set_meta(META_PACK_ROOTS, roots)
	forget()


static func _roots() -> PackedStringArray:
	var given: PackedStringArray = Engine.get_meta(META_ROOTS, PackedStringArray())
	if not given.is_empty():
		return given

	var out: PackedStringArray = Engine.get_meta(META_PACK_ROOTS, PackedStringArray()).duplicate()
	out.append_array(DotProfileSet.default_roots())
	return out


## The id every survivor starts as (`zz_class_default`); an unknown id falls back to [constant SURVIVOR].
static func set_default(id: String) -> void:
	var clean := id.strip_edges() if id.strip_edges() != "" else SURVIVOR
	if str(Engine.get_meta(META_DEFAULT, SURVIVOR)) != clean:
		Engine.set_meta(META_DEFAULT, clean)


static func default_id() -> String:
	var id := str(Engine.get_meta(META_DEFAULT, SURVIVOR))
	return id if all().has(id) else SURVIVOR


## Every class that loads, id to [DotPlayerClassDef]. A profile the schema or `validate` refuses is
## left out and named in [method rejected]; the rest still load.
static func all() -> Dictionary:
	var host := _def_host()
	if not host.has_meta(META_ALL):
		var loaded := {}
		var errors := PackedStringArray()
		var set := DotPlayerClassProfiles.make_set(GAME, _roots())
		for id in set.list_ids():
			var res := DotPlayerClassProfiles.load_def(set, id)
			var bad := ""
			if res.ok:
				bad = _check_extras(res.value)
			else:
				bad = res.error.message
			if bad == "":
				loaded[id] = res.value
			else:
				errors.append("%s: %s" % [id, bad])
				DotLog.error(CHANNEL, "class refused", {"class": id, "why": bad})
		host.set_meta(META_ALL, loaded)
		host.set_meta(META_ERRORS, errors)
	return host.get_meta(META_ALL)


## Classes that were refused on load, as `id: why`.
static func rejected() -> PackedStringArray:
	var _all := all()
	return _def_host().get_meta(META_ERRORS, PackedStringArray())


static func _check_extras(def: DotPlayerClassDef) -> String:
	var mode := model_mode(def)
	if not MODES.has(mode):
		return "model_mode '%s' is not one of %s" % [mode, ", ".join(MODES)]
	var models: Variant = def.attributes.get("models", [])
	if not models is Array:
		return "models must be a list of skin ids"
	for m: Variant in models:
		if not ZzAvatars.SKINS.has(StringName(str(m))):
			return "model '%s' is not one of this game's skins" % str(m)
	if mode == "select" and (models as Array).is_empty():
		return "model_mode select needs models"
	if float(def.attributes.get("bot_weight", 0.0)) < 0.0:
		return "bot_weight is negative"
	return ""


static func model_mode(def: DotPlayerClassDef) -> String:
	return str(def.attributes.get("model_mode", "random"))


## The skin ids a class may wear, as strings.
static func models_of(def: DotPlayerClassDef) -> PackedStringArray:
	var out := PackedStringArray()
	var list: Variant = def.attributes.get("models", [])
	if list is Array:
		for m: Variant in list:
			out.append(str(m))
	return out


## The skin for this spawn. [param wanted] is the player's own pick (used only in `select` mode and
## only if it is on the list); `random` draws from [param rng]; `first` is the head of the list.
## Empty means the class has no models: the player keeps their own avatar.
static func pick_model(def: DotPlayerClassDef, wanted: String, rng: RandomNumberGenerator) -> String:
	var models := models_of(def)
	if models.is_empty():
		return ""
	match model_mode(def):
		"select":
			return wanted if models.has(wanted) else models[0]
		"first":
			return models[0]
		_:
			return models[rng.randi() % models.size()]


## The class ids a survivor may ask for now: empty when selection is off.
static func offered(select_on: bool, allowed_csv: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not select_on:
		return out
	var wanted := PackedStringArray()
	for part in allowed_csv.split(",", false):
		wanted.append(part.strip_edges())
	var ids: Array = all().keys()
	ids.sort()
	for id: String in ids:
		var def: DotPlayerClassDef = all()[id]
		if (wanted.is_empty() and def.selectable) or wanted.has(id):
			out.append(id)
	return out


## Whether [param id] may be chosen; the refusal names why.
static func check_choice(id: String, select_on: bool, allowed_csv: String) -> DotResult:
	if not select_on:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Class selection is off on this server.")
	if not all().has(id):
		return DotResult.fail(DotError.CODE_INVALID, "No class '%s'." % id)
	if not offered(select_on, allowed_csv).has(id):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "'%s' is not offered here." % id)
	return DotResult.success(id)


## The class a stand-in is dealt, by `bot_weight` (0 never), or the default; deterministic in [param rng].
static func draw_for_bot(rng: RandomNumberGenerator) -> String:
	var ids: Array = all().keys()
	ids.sort()
	var total := 0.0
	for id: String in ids:
		total += float((all()[id] as DotPlayerClassDef).attributes.get("bot_weight", 0.0))
	if total <= 0.0:
		return default_id()
	var point := rng.randf() * total
	for id: String in ids:
		point -= float((all()[id] as DotPlayerClassDef).attributes.get("bot_weight", 0.0))
		if point < 0.0:
			return id
	return default_id()


## The default class, or null when no profile loads (then config alone applies).
static func survivor() -> DotPlayerClassDef:
	var found: Variant = all().get(default_id())
	return found as DotPlayerClassDef


## A class by id, or the default.
static func def_of(id: String) -> DotPlayerClassDef:
	var found: Variant = all().get(id)
	return found as DotPlayerClassDef if found != null else survivor()


## Forgets the loaded class so the next spawn reads the files again.
static func forget() -> void:
	var host := _def_host()
	if host.has_meta(META_ALL):
		host.remove_meta(META_ALL)
	if host.has_meta(META_ERRORS):
		host.remove_meta(META_ERRORS)


## The main loop holds the def: it is freed before the script languages shut down, while a
## script object left in Engine metadata is freed after them and aborts the process at exit.
static func _def_host() -> Object:
	var loop := Engine.get_main_loop()
	return loop if loop != null else Engine


## The carry limit for a survivor: the class's, else [param fallback].
static func carry_limit(fallback: float) -> float:
	return DotPlayerClassApply.carry_limit(survivor(), fallback)


## Writes the survivor class's `immune_to` onto [param combat] for [param entity]; no profile clears it.
## Called at every spawn, so a respawn never keeps what the last life had.
static func apply_immunity(combat: Object, entity: int) -> int:
	return DotGameClassImmunity.apply(combat, survivor(), entity)
