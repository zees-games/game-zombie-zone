extends RefCounted

## Every key this game reads, as one [DotMenuBindings] table: the action, the setting that
## stores it, the words a player sees, the default, and the card it goes on.
##
## [b]A table, because four things read it:[/b] the client matches events against the actions,
## the settings document stores one binding per row, the menu's Controls page draws a key per
## row, and the help screen lists them with the key each is on now.
##
## [b]The genre's keys.[/b] E does everything with the hands (pick up, open, revive, press), the
## right mouse button shoves (F as well, for a trackpad), G holds a medkit on yourself or on the
## friend you are looking at, Q takes pills, and the number keys pick a slot.
##
## [b]H is help, in every game of the family[/b] (dot-menu adds the row). The medkit was on H
## until 2026-10-11, the first play test's "[H] medkit"; it is on G, beside the other hand
## keys.
##
## [b]The slots are rows[/b], read through their actions, so the Controls page can move them
## and the help screen lists them; they were keycodes in the client, which no page could show.

const USE := &"zz_use"
const HEAL := &"zz_heal"
const PILLS := &"zz_pills"
const SHOVE := &"zz_shove"
const RELOAD := &"zz_reload"
const VIEW := &"zz_view"
const SCOREBOARD := &"zz_scoreboard"
## Slots 1 to 5, the weapon pack's: melee, sidearm, primary, heavy, thrown.
const SLOTS: Array[StringName] = [&"zz_slot_1", &"zz_slot_2", &"zz_slot_3", &"zz_slot_4", &"zz_slot_5"]
const SLOT_NAMES: Array[String] = ["melee", "sidearm", "primary", "heavy", "thrown"]


static func make() -> DotMenuBindings:
	var keys := DotMenuBindings.new()
	keys.add_movement()
	keys.add(USE, &"bind_use", "Use, pick up, revive (hold)", "E", "Hands")
	keys.add(HEAL, &"bind_heal", "Medkit on yourself or a friend (hold)", "G", "Hands")
	keys.add(PILLS, &"bind_pills", "Take pills", "Q", "Hands")
	keys.add(SHOVE, &"bind_shove", "Shove (also right mouse)", "F", "Hands")
	keys.add(RELOAD, &"bind_reload", "Reload", "R", "Weapons")
	for i in range(SLOTS.size()):
		keys.add(SLOTS[i], StringName("bind_slot_%d" % (i + 1)), "Slot %d: %s" % [i + 1, SLOT_NAMES[i]], str(i + 1), "Weapons")
	keys.add(VIEW, &"bind_view", "First or third person", "F5", "General")
	keys.add(SCOREBOARD, &"bind_scoreboard", "Scoreboard (hold)", "Tab", "General")
	return keys
