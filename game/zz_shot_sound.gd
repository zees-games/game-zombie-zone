class_name ZzShotSound
extends Node

## A gun's report: gs-audio's recorded, layered shot (attack, body, the room's tail and a far report, delayed by the speed
## of sound; [GSShotPlayer]) in the game's own mixer, picked by the weapon's sound class. This replaces the one synthesised
## `weapon_shot` voice every gun used to share. The class of a weapon id is the weapon pack's (`ZzWeaponSound.CLASSES`,
## found by global-class name since the pack is optional); a kind with no class falls back to the kind's own default.
##
## Presentation only: it reads nothing back, and a build without the stock files plays nothing here and the caller falls
## back to its synthesised voice ([method fire] returns false).

const CHANNEL := "zz.shot_sound"
const PACK_CLASS := &"ZzWeaponSound"

## Weapon classes with a stock shot, from [GSAudioShotStock.COUNTS].
## The class a weapon outcome kind plays when its weapon id names none.
const KIND_DEFAULT := {
	ZeeWeaponNet.KIND_SHOT: &"rifle", ZeeWeaponNet.KIND_SWING: &"swing", ZeeWeaponNet.KIND_SPAWN: &"launcher",
	ZeeWeaponNet.KIND_BEAM: &"beam", ZeeWeaponNet.KIND_THROW: &"throw",
}
## A pack's class names that the stock set spells differently.
const ALIAS := {&"bash": &"swing"}

var player: GSShotPlayer = null
var enclosure: GSAudioEnclosure = null

static var _classes: Dictionary = {}
static var _classes_read := false


func setup(manager: GSAudioManager, send_bus: StringName = &"SFX") -> bool:
	if manager == null or manager.catalogue == null:
		return false
	enclosure = GSAudioEnclosure.new()
	enclosure.send_bus = send_bus
	add_child(enclosure)
	player = GSShotPlayer.new()
	player.manager = manager
	player.enclosure = enclosure
	add_child(player)
	for shot in GSAudioShotStock.shots():
		var made := player.register(shot)
		if not made.ok:
			GSLog.warn(CHANNEL, "a stock shot did not register; guns keep the synthesised report", {"cause": str(made)})
			return false
	return true


func is_ready() -> bool:
	return player != null


## The stock shot class for [param weapon_id] (or the [param kind]'s default); empty for none.
static func class_of(weapon_id: StringName, kind: int) -> StringName:
	var named: StringName = _pack_classes().get(weapon_id, &"")
	named = ALIAS.get(named, named)
	if named != &"" and GSAudioShotStock.COUNTS.has(named):
		return named
	return KIND_DEFAULT.get(kind, &"")


## Plays the report at [param at]; false when no stock shot covers it (the caller plays its own).
func fire(weapon_id: StringName, kind: int, at: Vector3) -> bool:
	if player == null:
		return false
	var weapon_class := class_of(weapon_id, kind)
	if weapon_class == &"":
		return false
	var suppressed := weapon_id == &"zz_vss"
	var played := player.fire(GSAudioShotStock.id_of(weapon_class), at, suppressed)
	return played.ok and int(played.value_or(0)) > 0


## Measures the room round the listener for the tail; once a frame.
func probe(delta: float, eye: Vector3, space: PhysicsDirectSpaceState3D) -> void:
	if enclosure != null and space != null:
		enclosure.step(delta, eye, space)


static func _pack_classes() -> Dictionary:
	if _classes_read:
		return _classes
	_classes_read = true
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry.get("class", &"") == PACK_CLASS:
			var script := load(str(entry.get("path", ""))) as GDScript
			if script != null:
				var table: Variant = script.get_script_constant_map().get("CLASSES", {})
				if table is Dictionary:
					_classes = table
			break
	return _classes
