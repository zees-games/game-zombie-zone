extends RefCounted

## The survivor class as a dot-player-class profile (`cfg/game/game-zombie-zone/class/survivor.yml`).
##
## ZzConfig holds the defaults; a class number left at -1 keeps them, so there is one source per
## number. Health stays in config_survivors: only movement, sprint, stamina and carry come from here.

const CHANNEL := "zz.classes"
const GAME := "game-zombie-zone"
const SURVIVOR := "survivor"

## Process-wide state lives in Engine metadata, not static vars: a script reached by two paths
## (a suite's "../game/x.gd") is two script objects with two copies of every static.
const META_DEF := &"zz_survivor_class"
const META_ROOTS := &"zz_class_roots"


## Config roots for the profile set; empty uses the defaults. Tests point it at a temp folder.
static func set_roots(roots: PackedStringArray) -> void:
	Engine.set_meta(META_ROOTS, roots)
	forget()


## The survivor class, or null when no profile loads (then config alone applies).
static func survivor() -> DotPlayerClassDef:
	var host := _def_host()
	if not host.has_meta(META_DEF):
		var def: DotPlayerClassDef = null
		var set := DotPlayerClassProfiles.make_set(GAME, Engine.get_meta(META_ROOTS, PackedStringArray()))
		if set.has_id(SURVIVOR):
			var res := DotPlayerClassProfiles.load_def(set, SURVIVOR)
			if res.ok:
				def = res.value
			else:
				DotLog.error(CHANNEL, "survivor class refused, using config", {"why": res.error.message})
		host.set_meta(META_DEF, def if def != null else false)
	var held: Variant = host.get_meta(META_DEF)
	return held if held is DotPlayerClassDef else null


## Forgets the loaded class so the next spawn reads the files again.
static func forget() -> void:
	var host := _def_host()
	if host.has_meta(META_DEF):
		host.remove_meta(META_DEF)


## The main loop holds the def: it is freed before the script languages shut down, while a
## script object left in Engine metadata is freed after them and aborts the process at exit.
static func _def_host() -> Object:
	var loop := Engine.get_main_loop()
	return loop if loop != null else Engine


## The carry limit for a survivor: the class's, else [param fallback].
static func carry_limit(fallback: float) -> float:
	return DotPlayerClassApply.carry_limit(survivor(), fallback)
