extends RefCounted

## Every key this game reads, as one [DotMenuBindings] table: the action, the setting that
## stores it, the words a player sees, the default, and the card it goes on.
##
## [b]A table, because four things read it:[/b] the client matches events against the actions,
## the settings document stores one binding per row, the menu's Controls page draws a key per
## row, and the help screen lists them with the key each is on now.
##
## [b]The genre's keys.[/b] E does everything with the hands (pick up, open, revive, press), F
## shoves, G holds a medkit on yourself or on the friend you are looking at, P takes pills, Q drops the weapon in hand, and
## the number keys pick a slot.
##
## [b]The right mouse button aims down the sights[/b] (zee's `ZeeViewModel.aim`, the family's
## Aim row, as in the arena). It shoved until 2026-10-12, when the family gained aiming; the
## shove kept F, which it always had.
##
## [b]H is help, in every game of the family[/b] (dot-menu adds the row). The medkit was on H
## until 2026-10-11, the first play test's "[H] medkit"; it is on G, beside the other hand
## keys.
##
## [b]The slots are rows[/b], read through their actions, so the Controls page can move them
## and the help screen lists them; they were keycodes in the client, which no page could show.
##
## [b]Chat is two rows[/b] on dot-ui's chat window's own actions (Y to all, U to your side), so
## the help screen lists them and the Controls page moves them; until 2026-10-12 they were the
## window's defaults, on no page.

const USE := &"zz_use"
const HEAL := &"zz_heal"
const PILLS := &"zz_pills"
## Hands one pill / one medkit to the friend you aim at (server cvars `zz_give_pills`, `zz_give_medkits`).
const GIVE_PILLS := &"zz_give_pills"
const GIVE_KIT := &"zz_give_medkit"
## Puts the weapon in hand down in front of you (server cvar `sv_weapon_drop_key`).
const DROP := &"zz_drop_weapon"
const SHOVE := &"zz_shove"
## Switches the flashlight (on F since 2026-10-27; the shove moved to T).
const FLASHLIGHT := &"zz_flashlight"
## Takes a carried box out of the pack into the hands, or puts it away; the box in the hands is
## deployed with primary fire, held.
const BOX := &"zz_box"
## Down the sights while held: the view model comes up and the lens zooms. Presentation only;
## nothing the server simulates reads it.
const AIM := &"zz_aim"
## Primary fire: shoots the gun in the hands, or deploys the box when that is what they hold.
const FIRE := &"zz_fire"
const RELOAD := &"zz_reload"
## Cycles the gun in hand through the fire modes it has (auto, semi, burst).
const FIRE_MODE := &"zz_fire_mode"
const VIEW := &"zz_view"
const SCOREBOARD := &"zz_scoreboard"
## dot-ui's chat window's actions, which dot-game's chat client leaves at their defaults.
const CHAT := &"chat_open"
const CHAT_TEAM := &"chat_open_team"
## Slots 1 to 5, the weapon pack's: melee, sidearm, primary, heavy, thrown.
const SLOTS: Array[StringName] = [&"zz_slot_1", &"zz_slot_2", &"zz_slot_3", &"zz_slot_4", &"zz_slot_5"]
const SLOT_NAMES: Array[String] = ["melee", "sidearm", "primary", "heavy", "thrown"]


static func make() -> DotMenuBindings:
	var keys := DotMenuBindings.new()
	keys.add_movement()
	keys.add(USE, &"bind_use", "Use, pick up, revive (hold)", "E", "Hands")
	keys.add(HEAL, &"bind_heal", "Medkit on yourself or a friend (hold)", "G", "Hands")
	keys.add(PILLS, &"bind_pills", "Take pills (hold)", "P", "Hands")
	keys.add(GIVE_PILLS, &"bind_give_pills", "Give a friend pills", "N", "Hands")
	keys.add(GIVE_KIT, &"bind_give_medkit", "Give a friend a medkit", "K", "Hands")
	keys.add(DROP, &"bind_drop_weapon", "Drop the weapon in hand", "Q", "Hands")
	keys.add(SHOVE, &"bind_shove", "Shove", "T", "Hands")
	keys.add(FLASHLIGHT, &"bind_flashlight", "Flashlight", "F", "Hands")
	keys.add(BOX, &"bind_box", "Take out or put away a carried box", "X", "Hands")
	keys.add(FIRE, &"bind_fire", "Primary fire (hold to deploy a box)", "Mouse 1", "Weapons")
	keys.add(AIM, &"bind_aim", "Aim down the sights (hold)", "Mouse 2", "Weapons")
	keys.add(RELOAD, &"bind_reload", "Reload", "R", "Weapons")
	keys.add(FIRE_MODE, &"bind_fire_mode", "Fire mode: auto, semi, burst", "B", "Weapons")
	for i in range(SLOTS.size()):
		keys.add(SLOTS[i], StringName("bind_slot_%d" % (i + 1)), "Slot %d: %s" % [i + 1, SLOT_NAMES[i]], str(i + 1), "Weapons")
	keys.add_wheel_weapons()
	keys.add(CHAT, &"bind_chat", "Chat", "Y", "Communication")
	keys.add(CHAT_TEAM, &"bind_chat_team", "Chat to your side", "U", "Communication")
	keys.add(VIEW, &"bind_view", "First or third person", "F5", "General")
	keys.add(SCOREBOARD, &"bind_scoreboard", "Scoreboard (hold)", "Tab", "General")
	# Defaults that moved under saved documents: the medkit left H for help, the shove left V
	# for push to talk. A player who never touched them follows; a key they chose stays.
	var _r := keys.renamed(&"bind_heal", ["H"]).renamed(&"bind_shove", ["V", "F"]).renamed(&"bind_flashlight", ["T"]).renamed(&"bind_pills", ["Q"])
	return keys
