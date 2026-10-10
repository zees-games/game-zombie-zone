extends DotNetInput

const ZzNetCommand := preload("zz_net_command.gd")

## One tick of a player's intent, on the wire: a movement command, a weapon slot, and the hands.
##
## [b]The three game buttons ride in [member DotFpsCommand.buttons] for the reason a jump
## does:[/b] they are per-tick, they are held rather than pressed once, and they have to be
## ordered against the movement they were aimed with. A shot sent as a reliable request
## would arrive a round trip later and be resolved against a position the player has
## already left.
##
## The slot is the exception and is a field of its own, because [DotFpsCommand] has eight
## buttons and no room for a number — see [member ZzPlayer.wanted_slot].

## Fire. `BUTTON_USER_0`, which dot-player-controller reserves.
const BUTTON_FIRE := DotFpsCommand.BUTTON_USER_0

## The shove. On the alt button, as the genre puts it, and NOT handed to the weapon: zee's
## alt-fire is a bash with the gun, and a shove is the game's — it staggers a crowd and knocks a
## special off a friend, which no weapon's bash knows how to do.
const BUTTON_SHOVE := DotFpsCommand.BUTTON_USER_1

const BUTTON_RELOAD := DotFpsCommand.BUTTON_USER_2

## How many bits the slot takes. Eight slots is one more than the pack uses.
const SLOT_BITS := 3

## What the hands are doing, held: E (revive, open, pick up, press), the medkit, the pills.
## Bits of [member actions]. Held rather than pressed for the same reason fire is: a revive is
## five seconds of holding E, and it stops the tick the key comes up.
const ACT_USE := 1
const ACT_HEAL := 2
const ACT_PILLS := 4
const ACT_BITS := 4

var move: DotFpsCommand = DotFpsCommand.new()

## Which weapon the player has asked for, or zero for "leave it alone".
var slot: int = 0

var actions: int = 0

func _write(writer: DotNetWriter) -> void:
	move.write(writer)
	writer.write_uint(clampi(slot, 0, (1 << SLOT_BITS) - 1), SLOT_BITS)
	writer.write_uint(actions & ((1 << ACT_BITS) - 1), ACT_BITS)


func _read(reader: DotNetReader) -> void:
	move = DotFpsCommand.new()
	move.read(reader)
	slot = reader.read_uint(SLOT_BITS)
	actions = reader.read_uint(ACT_BITS)


## Not optional. Quantisation bounds each field; it cannot bound the relationship between
## them, and a move vector of (1, 1) is 41% more speed than anybody else — a survivor who outruns
## a crowd that should have caught them.
func _sanitise() -> void:
	move.sanitise()
	slot = clampi(slot, 0, (1 << SLOT_BITS) - 1)
	actions &= (1 << ACT_BITS) - 1


func _equals(other: DotNetInput) -> bool:
	var them := other as ZzNetCommand
	return them != null and slot == them.slot and actions == them.actions and move.equals(them.move)
