extends RefCounted

const ZzGame := preload("../zz_game.gd")

## The wire format for everything that is not a snapshot or an input.
##
## Encoders and decoders in pairs, and nothing checks that they are inverses for you —
## `headless_net` round-trips every one of them, because this family has already shipped a
## serialisation whose two ends never met: dot-moderation wrote `"voice muted"` and read
## back a warning, and the one thing that addon existed for silently did nothing.
##
## [b]The map is a document, and it travels whole.[/b] `MAP` carries the normalised document
## a server built (see [ZzMapDoc]), deflated: a client builds the identical map from it and
## needs no map files of its own.
##
## [b]A snapshot carries what moves; an event carries what happens.[/b] Survivors and zombies
## are entities in the snapshot. Everything else is said once, here: a zombie appearing (its
## kind and variant, which never change) and going; a survivor down, picked up, held, freed;
## something lying on the ground and picked up; a box's outcome; a pool of acid, a thrown
## rock and where it landed; an explosion; an objective; a gate. A pool and a rock are pure
## functions of how they began, so one event each draws all of their lives.

enum Kind {
	## Who you are and how fast the server ticks.
	HELLO,
	## The map, as a document. Build it from this.
	MAP,
	## A player is in the world: net id, name, side, face.
	JOIN,
	LEAVE,
	## A player changed sides.
	TEAM,
	## The clock and the numbers a client cannot count for itself.
	CLOCK,
	## A map began or ended, and how.
	ROUND,
	## The map moved on: in the start area, playing.
	PHASE,
	## Somebody is dead, and what did it.
	DEATH,
	## Somebody was handed a weapon.
	ARMED,
	## Text for one player, or for everybody.
	NOTICE,
	## One routed chat line.
	CHAT,
	## What this one player's camera is on now that they are out. To its owner only.
	SPECTATE,
	## A zombie appeared: its net id, kind, variant and where.
	NPC,
	## A zombie went: killed, or tidied away.
	NPC_GONE,
	## A survivor went down, and what did it.
	DOWN,
	## A survivor was picked up, and by whom (0: a box).
	REVIVE,
	## A dead survivor is back.
	RESCUE,
	## A survivor is held by a special: which zombie, and how.
	PIN,
	## Let go, and why.
	UNPIN,
	## Something is on the ground: an id, a kind, an item, a place.
	LOOT,
	## It is not any more, and who took it.
	LOOT_GONE,
	## A box was opened: by whom, which, what came out.
	BOX,
	## A pool of acid, a fire, a healing glow: an id, a kind, a place, a radius, a lifetime.
	HAZARD,
	HAZARD_GONE,
	## Something thrown or falling: an id, a kind, where from, how fast.
	THROW,
	## It landed, or hit somebody.
	LANDED,
	## An explosion: where, how big, what kind.
	BLAST,
	## A survivor was covered in bile, for so long.
	BILE,
	## An objective changed: which, and to what (`holding`, `done`).
	OBJECTIVE,
	## A gate opened.
	GATE,
	## What the boxes are doing to the game: one line per kind of effect.
	EFFECTS,
	## To one survivor: you were hurt, this much, from there.
	HURT,
	## To one survivor: your ammunition was filled.
	AMMO,
	## To one survivor: your hit landed on a zombie, this much, there, and whether it killed.
	HIT,
	## A survival map's hold: the style, the stage, which wave or night of how many, the
	## stage's seconds, the wave's zombies left, its twist, and the daylight.
	SURVIVAL,
	## A barricade's strength and whether it stands.
	BARRICADE,
	## The map's toys: the map's id, then their net ids in toy order (both ends build the toys
	## in the same order from the map). After MAP, and to a joiner after theirs.
	TOYS,
	## A sentry turret was set up: id, place, which way it faces, seconds it lasts.
	TURRET,
	## It fired at this point.
	TURRET_FIRE,
	## It ran out, or was taken down.
	TURRET_GONE,
	## A lift, door or other moving part of a converted map changed state: index, start tick,
	## fraction then, direction, locked.
	MOVER,
	## Blood on a surface: a point and the surface's normal, to everybody but the shooter, who
	## splatters it from their own HIT. An older client ignores a kind it does not know.
	SPLAT,
	## A dead survivor was shocked back by a defibrillator: who, and by whom (a pair).
	DEFIB,
	## The trader menu: whether it is open, where, how far it reaches, and the items with their prices (JSON).
	SHOP,
	## The map's navigation graph is being built: percent done, or none when it is not.
	NAV,
	## A brush the map's point_template copied, or removed: id, model, offset, alive.
	COPY,
	## A map's logic told its ears something: a sound fade or spin, or a beat (`MapFx`).
	MAP_FX,
	## Physics crates that moved: for each, the loot id, the place and the turn.
	LOOT_MOVED,
	## What this one player carries: weight, limit, backpack, speed scale and the weapons by slot (JSON). To its owner only.
	CARRY,
	## One piece of a map document too big for one message: which map, which piece of how many.
	MAP_PART,
	## A shootable support broke (its index in the map's list); what stood on it is the toys' own.
	SUPPORT,
}

## What a MAP_FX says.
enum MapFx { FADE, SPIN, BEAT, END }
## Most entities a map names by index on the wire, and the longest fade or spin it may ask for.
const MAP_FX_ENTITIES := 65535
const MAP_FX_SECONDS := 600.0
## A map's ending (`MapFx.END`): the slow motion's scale and length, and the camera point, as far as a client believes them.
const END_SCALE_MIN := 0.05
const END_SECONDS_MAX := 15.0

enum Ask {
	## I have built my world and can receive. Tell me everything in it.
	READY,
	## I typed a line. The server decides what channel it lands on and who hears it.
	SAY,
	## I am out: show me the next person, the previous one, or the other camera.
	SPECTATE,
	## I want to buy this item from the trader. The server checks reach, window, stock and points.
	BUY,
}

## Every decoder returns an `ok` beside its fields, and every caller checks it.
##
## [b]A reader past its end returns plausible zeros rather than failing.[/b] dot-net shipped
## with exhaustion that was not sticky, so a decoder that skipped this check got a
## believable value for the field AFTER the overrun — and a truncated packet decodes as a
## valid message about nothing.
const NAME_BYTES := 64
const ID_BYTES := 64
const TEXT_BYTES := 256

## The largest map a reader accepts: [ZzMapDoc.WIRE_LIMIT] and its header.
const MAP_BYTES := 65536 + 16

## A map larger than this is sent as MAP_PART pieces of this size (a browser's outbound buffer is 64 KiB).
const MAP_PART_BYTES := 32768
## The most pieces a reader accepts for one map: a hostile server cannot make a client hold more than 64 MiB.
const MAP_PARTS_MAX := 2048

## The most an avatar document may take in a JOIN.
const AVATAR_BYTES := 1024

## The box effects list, as JSON.
const EFFECTS_BYTES := 2048

## Where a body may be, in metres, on the wire. Read from [ZzGame], not written here: a
## quantised position is decoded against this range, and two files holding two numbers put
## the thing somewhere else (game-arena: 256 against 128).
const WORLD_EXTENT := ZzGame.NET_WORLD_EXTENT
const POS_BITS := 24

## Velocities of thrown things, m/s.
const SPEED_MAX := 80.0
const SPEED_BITS := 14

## Clocks, in seconds: well past any map.
const CLOCK_MAX := 7200.0
const CLOCK_BITS := 18

const TEAM_BITS := 3
const PHASE_BITS := 3


static func kind_name(kind: int) -> String:
	var names := Kind.keys()
	return String(names[kind]) if kind >= 0 and kind < names.size() else "?"


static func ask_name(ask: int) -> String:
	var names := Ask.keys()
	return String(names[ask]) if ask >= 0 and ask < names.size() else "?"


static func _w() -> DotNetWriter:
	return DotNetWriter.new()


static func _pos(w: DotNetWriter, at: Vector3) -> void:
	w.write_vector3_range(at, -WORLD_EXTENT, WORLD_EXTENT, POS_BITS)


static func _read_pos(r: DotNetReader) -> Vector3:
	return r.read_vector3_range(-WORLD_EXTENT, WORLD_EXTENT, POS_BITS)


# --- Hello -----------------------------------------------------------------

static func write_hello(player_id: int, tick_rate: int, server_tick: int, difficulty: int, max_incaps: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_uint(tick_rate, 9)
	w.write_varint(server_tick)
	w.write_uint(clampi(difficulty, 0, 3), 2)
	w.write_uint(clampi(max_incaps, 0, 15), 4)
	return w.to_bytes()


static func read_hello(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var tick_rate := r.read_uint(9)
	var server_tick := r.read_varint()
	var difficulty := r.read_uint(2)
	var max_incaps := r.read_uint(4)
	return {
		"player_id": player_id, "tick_rate": tick_rate, "server_tick": server_tick,
		"difficulty": difficulty, "max_incaps": max_incaps, "ok": r.ok(),
	}


# --- The map -----------------------------------------------------------------

## The map: [ZzMapDoc.encode]'s bytes, as they are. Opaque here, and checked at the other end.
static func write_toys(map_id: StringName, net_ids: PackedInt64Array) -> PackedByteArray:
	var w := _w()
	w.write_string(String(map_id), ID_BYTES)
	w.write_varint(net_ids.size())
	for id in net_ids:
		w.write_varint(maxi(int(id), 0))
	return w.to_bytes()


static func read_toys(r: DotNetReader) -> Dictionary:
	var map_id := StringName(r.read_string(ID_BYTES))
	var count := r.read_varint()
	var ids := PackedInt64Array()
	if count < 0 or count > 256:
		return {"map_id": map_id, "ids": ids, "ok": false}
	for i in count:
		ids.append(r.read_varint())
	return {"map_id": map_id, "ids": ids, "ok": r.ok()}


static func write_map(encoded: PackedByteArray) -> PackedByteArray:
	var w := _w()
	w.write_bytes(encoded)
	return w.to_bytes()


static func read_map(r: DotNetReader) -> Dictionary:
	var encoded := r.read_bytes(MAP_BYTES)
	return {"encoded": encoded, "ok": r.ok() and not encoded.is_empty()}


## The pieces of an encoded map, each a MAP_PART body; [] when it fits one MAP message.
static func write_map_parts(encoded: PackedByteArray, seq: int) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if encoded.size() <= MAP_PART_BYTES:
		return out
	var count := (encoded.size() + MAP_PART_BYTES - 1) / MAP_PART_BYTES
	for i in count:
		var w := _w()
		w.write_varint(seq)
		w.write_varint(i)
		w.write_varint(count)
		w.write_bytes(encoded.slice(i * MAP_PART_BYTES, mini((i + 1) * MAP_PART_BYTES, encoded.size())))
		out.append(w.to_bytes())
	return out


static func read_map_part(r: DotNetReader) -> Dictionary:
	var seq := r.read_varint()
	var index := r.read_varint()
	var count := r.read_varint()
	var piece := r.read_bytes(MAP_PART_BYTES)
	return {"seq": seq, "index": index, "count": count, "piece": piece,
		"ok": r.ok() and count > 0 and count <= MAP_PARTS_MAX and index < count and not piece.is_empty()}


# --- Players ---------------------------------------------------------------

## A join, or a change to who somebody is. Appended, never inserted.
static func write_join(
	player_id: int, net_id: int, display_name: String, team: int,
	avatar: DotAvatar = null
) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_varint(net_id)
	w.write_string(display_name, NAME_BYTES)
	w.write_varint(maxi(team, 0))
	w.write_string(JSON.stringify(avatar.to_dict()) if avatar != null else "", AVATAR_BYTES)
	return w.to_bytes()


static func read_join(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var net_id := r.read_varint()
	var display_name := r.read_string(NAME_BYTES)
	var team := r.read_varint()
	var text := r.read_string(AVATAR_BYTES)
	var avatar: DotAvatar = null

	# A document that does not parse is the stock person, not a refused join.
	if text != "":
		var parsed: Variant = JSON.parse_string(text)

		if parsed is Dictionary:
			var built := DotAvatar.from_dict(parsed)

			if built.ok:
				avatar = built.value

	return {
		"player_id": player_id, "net_id": net_id, "name": display_name, "team": team,
		"avatar": avatar, "ok": r.ok(),
	}


static func write_player(player_id: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	return w.to_bytes()


static func read_player(r: DotNetReader) -> int:
	return r.read_varint()


static func write_team(player_id: int, team: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_varint(maxi(team, 0))
	return w.to_bytes()


static func read_team(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var team := r.read_varint()
	return {"player_id": player_id, "team": team, "ok": r.ok()}


## A death or a down: who, by whom (a session, or 0), by what (a zombie kind, or empty), why.
## [param death] is how the body falls (dot-player-char's [DotPlayerDeath], the server's pick),
## last and optional, so every client draws the same fall and an older one reads the rest.
## [param weapon_id] is what landed the hit (empty for a claw), for the killcam's icon.
static func write_death(player_id: int, by: int, why: StringName, by_kind: StringName = &"",
		death: DotPlayerDeath = null, weapon_id: StringName = &"") -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_varint(by)
	w.write_string(String(why), ID_BYTES)
	w.write_string(String(by_kind), ID_BYTES)
	w.write_string(String(weapon_id), ID_BYTES)
	if death != null:
		death.write_to(w)
	return w.to_bytes()


static func read_death(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var by := r.read_varint()
	var why := r.read_string(ID_BYTES)
	var by_kind := r.read_string(ID_BYTES)
	var weapon_id := r.read_string(ID_BYTES)
	var out := {"player_id": player_id, "by": by, "why": StringName(why), "by_kind": StringName(by_kind),
		"weapon_id": StringName(weapon_id)}
	# A byte or more left is the fall; less is the padding to the last byte.
	if r.bits_remaining() >= 8:
		out["death"] = DotPlayerDeath.read_from(r)
	out["ok"] = r.ok()
	return out


## Somebody, and somebody else (a reviver, 0 for nobody).
static func write_pair(player_id: int, other: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_varint(maxi(other, 0))
	return w.to_bytes()


static func read_pair(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var other := r.read_varint()
	return {"player_id": player_id, "other": other, "ok": r.ok()}


static func write_armed(player_id: int, weapon_id: StringName) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_string(String(weapon_id), ID_BYTES)
	return w.to_bytes()


static func read_armed(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var weapon_id := r.read_string(ID_BYTES)
	return {"player_id": player_id, "weapon_id": StringName(weapon_id), "ok": r.ok()}


# --- The map's clock -----------------------------------------------------------

## The clock: the map number, its phase and how long it has been in it, a survival hold's time
## and goal (0 for none), who is left, the objective in play and its state.
static func write_clock(
	round_number: int, phase: int, elapsed: float, held: float, goal: float,
	alive: int, playable: bool, objective: int, objective_state: int, objective_ends: float,
	grace_left: float = 0.0
) -> PackedByteArray:
	var w := _w()
	w.write_varint(round_number)
	w.write_uint(clampi(phase, 0, 7), PHASE_BITS)
	w.write_float_range(clampf(elapsed, 0.0, CLOCK_MAX), 0.0, CLOCK_MAX, CLOCK_BITS)
	w.write_float_range(clampf(held, 0.0, CLOCK_MAX), 0.0, CLOCK_MAX, CLOCK_BITS)
	w.write_float_range(clampf(goal, 0.0, CLOCK_MAX), 0.0, CLOCK_MAX, CLOCK_BITS)
	w.write_uint(clampi(alive, 0, 255), 8)
	w.write_bool(playable)
	w.write_uint(clampi(objective + 1, 0, 31), 5)
	w.write_uint(clampi(objective_state, 0, 3), 2)
	w.write_float_range(clampf(objective_ends, 0.0, CLOCK_MAX), 0.0, CLOCK_MAX, CLOCK_BITS)
	w.write_float_range(clampf(grace_left, 0.0, CLOCK_MAX), 0.0, CLOCK_MAX, CLOCK_BITS)
	return w.to_bytes()


static func read_clock(r: DotNetReader) -> Dictionary:
	var round_number := r.read_varint()
	var phase := r.read_uint(PHASE_BITS)
	var elapsed := r.read_float_range(0.0, CLOCK_MAX, CLOCK_BITS)
	var held := r.read_float_range(0.0, CLOCK_MAX, CLOCK_BITS)
	var goal := r.read_float_range(0.0, CLOCK_MAX, CLOCK_BITS)
	var alive := r.read_uint(8)
	var playable := r.read_bool()
	var objective := r.read_uint(5) - 1
	var objective_state := r.read_uint(2)
	var objective_ends := r.read_float_range(0.0, CLOCK_MAX, CLOCK_BITS)
	var grace_left := r.read_float_range(0.0, CLOCK_MAX, CLOCK_BITS)
	return {
		"round": round_number, "phase": phase, "elapsed": elapsed, "held": held, "goal": goal,
		"alive": alive, "playable": playable, "objective": objective,
		"objective_state": objective_state, "objective_ends": objective_ends, "grace_left": grace_left, "ok": r.ok(),
	}


## A map began or ended. [param won] whether the survivors made it, and [param why] the
## server's sentence, which is what the HUD prints.
## A map began or was decided. A decided one also says how long until the next begins (tenths
## of a second) and which map that is, so a client can count it down.
static func write_round(number: int, began: bool, won: bool, why: String = "", next_in: float = -1.0,
		next_map: String = "") -> PackedByteArray:
	var w := _w()
	w.write_varint(number)
	w.write_bool(began)
	w.write_bool(won)
	w.write_string(why, TEXT_BYTES)
	w.write_varint(clampi(int(round(next_in * 10.0)) + 1, 0, 36000))
	w.write_string(next_map, TEXT_BYTES)
	return w.to_bytes()


static func read_round(r: DotNetReader) -> Dictionary:
	var number := r.read_varint()
	var began := r.read_bool()
	var won := r.read_bool()
	var why := r.read_string(TEXT_BYTES)
	var next_in := float(r.read_varint() - 1) / 10.0
	var next_map := r.read_string(TEXT_BYTES)
	return {"round": number, "began": began, "won": won, "why": why, "next_in": maxf(next_in, -1.0),
		"next_map": next_map, "ok": r.ok()}


static func write_phase(phase: int) -> PackedByteArray:
	var w := _w()
	w.write_uint(clampi(phase, 0, 7), PHASE_BITS)
	return w.to_bytes()


static func read_phase(r: DotNetReader) -> Dictionary:
	var phase := r.read_uint(PHASE_BITS)
	return {"phase": phase, "ok": r.ok()}


## 127 on the wire: no navigation build is running.
const NAV_NONE := 127


static func write_nav(percent: int) -> PackedByteArray:
	var w := _w()
	w.write_uint(NAV_NONE if percent < 0 else clampi(percent, 0, 100), 7)
	return w.to_bytes()


## `percent` is -1 when no build is running.
static func read_nav(r: DotNetReader) -> Dictionary:
	var value := r.read_uint(7)
	return {"percent": -1 if value > 100 else value, "ok": r.ok()}


# --- Watching --------------------------------------------------------------

## A view dot-spectate decided, for the one player it belongs to. Sessions, 0 is nobody.
static func write_spectate(
	viewer: int, mode: int, target: int, killer: int, death_at: Vector3
) -> PackedByteArray:
	var w := _w()
	w.write_varint(viewer)
	w.write_uint(clampi(mode, 0, 7), 3)
	w.write_varint(maxi(target, 0))
	w.write_varint(maxi(killer, 0))
	_pos(w, death_at)
	return w.to_bytes()


static func read_spectate(r: DotNetReader) -> Dictionary:
	var viewer := r.read_varint()
	var mode := r.read_uint(3)
	var target := r.read_varint()
	var killer := r.read_varint()
	var death_at := _read_pos(r)
	return {
		"viewer": viewer, "mode": mode, "target": target, "killer": killer,
		"death_at": death_at, "ok": r.ok(),
	}


## Next (+1), previous (-1), or the other camera (0).
static func write_ask_spectate(direction: int) -> PackedByteArray:
	var w := _w()
	w.write_uint(clampi(direction, -1, 1) + 1, 2)
	return w.to_bytes()


static func read_ask_spectate(r: DotNetReader) -> Dictionary:
	var raw := r.read_uint(2)
	return {"direction": clampi(raw, 0, 2) - 1, "ok": r.ok()}


# --- Zombies -----------------------------------------------------------------

static func write_npc(net_id: int, kind: StringName, variant: int, at: Vector3) -> PackedByteArray:
	var w := _w()
	w.write_varint(net_id)
	w.write_string(String(kind), ID_BYTES)
	w.write_uint(variant & 0xFFFF, 16)
	_pos(w, at)
	return w.to_bytes()


static func read_npc(r: DotNetReader) -> Dictionary:
	var net_id := r.read_varint()
	var kind := r.read_string(ID_BYTES)
	var variant := r.read_uint(16)
	var at := _read_pos(r)
	return {"net_id": net_id, "kind": StringName(kind), "variant": variant, "at": at, "ok": r.ok()}


## A zombie gone: [param killed] says it died rather than being tidied away, so a client can
## leave a body, and [param death] (dot-player-char's, the server's pick) how that body falls.
## The death is last and behind a flag, so a client that predates it reads the rest.
static func write_npc_gone(net_id: int, killed: bool, death: DotPlayerDeath = null) -> PackedByteArray:
	var w := _w()
	w.write_varint(net_id)
	w.write_bool(killed)
	w.write_bool(death != null)

	if death != null:
		death.write_to(w)

	return w.to_bytes()


static func read_npc_gone(r: DotNetReader) -> Dictionary:
	var net_id := r.read_varint()
	var killed := r.read_bool()
	var death: DotPlayerDeath = null

	# The flag reads false off a message's zero padding, so an older server's NPC_GONE is a death
	# with no reaction rather than a misread.
	if r.bits_remaining() > 0 and r.read_bool():
		death = DotPlayerDeath.read_from(r)

	return {"net_id": net_id, "killed": killed, "death": death, "ok": r.ok()}


## A survivor held: who, by which zombie (its net id), how.
static func write_pin(player_id: int, npc_net_id: int, kind: StringName) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_varint(npc_net_id)
	w.write_string(String(kind), ID_BYTES)
	return w.to_bytes()


static func read_pin(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var npc_net_id := r.read_varint()
	var kind := r.read_string(ID_BYTES)
	return {"player_id": player_id, "npc": npc_net_id, "kind": StringName(kind), "ok": r.ok()}


# --- Things on the ground ------------------------------------------------------

static func write_loot(id: int, kind: StringName, item: StringName, at: Vector3, price: int = 0) -> PackedByteArray:
	var w := _w()
	w.write_varint(id)
	w.write_string(String(kind), ID_BYTES)
	w.write_string(String(item), ID_BYTES)
	_pos(w, at)
	w.write_varint(maxi(price, 0))
	return w.to_bytes()


static func read_loot(r: DotNetReader) -> Dictionary:
	var id := r.read_varint()
	var kind := r.read_string(ID_BYTES)
	var item := r.read_string(ID_BYTES)
	var at := _read_pos(r)
	var price := r.read_varint()
	return {"id": id, "kind": StringName(kind), "item": StringName(item), "at": at, "price": price, "ok": r.ok()}


## The most crates one LOOT_MOVED carries (the cap on awake crates is 256).
const MOVED_MAX := 256


static func write_loot_moved(batch: Array) -> PackedByteArray:
	var w := _w()
	var n := mini(batch.size(), MOVED_MAX)
	w.write_varint(n)
	for i in n:
		var row: Array = batch[i]
		w.write_varint(int(row[0]))
		_pos(w, row[1])
		w.write_quaternion(row[2], 9)
	return w.to_bytes()


static func read_loot_moved(r: DotNetReader) -> Dictionary:
	var n := mini(r.read_varint(), MOVED_MAX)
	var rows: Array = []
	for i in n:
		var id := r.read_varint()
		var at := _read_pos(r)
		var turn := r.read_quaternion(9)
		rows.append([id, at, turn])
	return {"rows": rows, "ok": r.ok()}


static func write_loot_gone(id: int, by: int) -> PackedByteArray:
	return write_pair(id, by)


static func read_loot_gone(r: DotNetReader) -> Dictionary:
	var pair := read_pair(r)
	return {"id": pair["player_id"], "by": pair["other"], "ok": pair["ok"]}


## A box opened: by whom, which type, the outcome's title and the message.
static func write_box(player_id: int, type_id: StringName, title: String, message: String) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_string(String(type_id), ID_BYTES)
	w.write_string(title, NAME_BYTES)
	w.write_string(message, TEXT_BYTES)
	return w.to_bytes()


static func read_box(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var type_id := r.read_string(ID_BYTES)
	var title := r.read_string(NAME_BYTES)
	var message := r.read_string(TEXT_BYTES)
	return {"player_id": player_id, "type": StringName(type_id), "title": title, "message": message, "ok": r.ok()}


## The effects the boxes have running, as the HUD lists them.
static func write_effects(summary: Array) -> PackedByteArray:
	var w := _w()
	var rows: Array = []

	for e: Dictionary in summary:
		rows.append([str(e["title"]), int(e["stacks"]), snappedf(float(e["seconds"]), 0.1), str(e["who"]), snappedf(float(e["scale"]), 0.01), str(e.get("id", ""))])

	w.write_string(JSON.stringify(rows), EFFECTS_BYTES)
	return w.to_bytes()


static func read_effects(r: DotNetReader) -> Dictionary:
	var text := r.read_string(EFFECTS_BYTES)
	var rows: Array = []
	var parsed: Variant = JSON.parse_string(text) if text != "" else []

	if parsed is Array:
		for row: Variant in parsed:
			if row is Array and (row as Array).size() >= 5:
				rows.append({"title": str(row[0]), "stacks": int(row[1]), "seconds": float(row[2]), "who": str(row[3]), "scale": float(row[4]), "id": str(row[5]) if (row as Array).size() > 5 else ""})

	return {"effects": rows, "ok": r.ok()}


# --- Hazards and thrown things ---------------------------------------------------

static func write_hazard(id: int, kind: StringName, at: Vector3, radius: float, seconds: float) -> PackedByteArray:
	var w := _w()
	w.write_varint(id)
	w.write_string(String(kind), ID_BYTES)
	_pos(w, at)
	w.write_float_range(clampf(radius, 0.0, 64.0), 0.0, 64.0, 12)
	w.write_float_range(clampf(seconds, 0.0, 600.0), 0.0, 600.0, 14)
	return w.to_bytes()


static func read_hazard(r: DotNetReader) -> Dictionary:
	var id := r.read_varint()
	var kind := r.read_string(ID_BYTES)
	var at := _read_pos(r)
	var radius := r.read_float_range(0.0, 64.0, 12)
	var seconds := r.read_float_range(0.0, 600.0, 14)
	return {"id": id, "kind": StringName(kind), "at": at, "radius": radius, "seconds": seconds, "ok": r.ok()}


static func write_turret(id: int, at: Vector3, yaw: float, seconds: float) -> PackedByteArray:
	var w := _w()
	w.write_varint(id)
	_pos(w, at)
	w.write_float_range(wrapf(yaw, -PI, PI), -PI, PI, 10)
	w.write_float_range(clampf(seconds, 0.0, 600.0), 0.0, 600.0, 14)
	return w.to_bytes()


static func read_turret(r: DotNetReader) -> Dictionary:
	var id := r.read_varint()
	var at := _read_pos(r)
	var yaw := r.read_float_range(-PI, PI, 10)
	var seconds := r.read_float_range(0.0, 600.0, 14)
	return {"id": id, "at": at, "yaw": yaw, "seconds": seconds, "ok": r.ok()}


static func write_turret_fire(id: int, target: Vector3) -> PackedByteArray:
	var w := _w()
	w.write_varint(id)
	_pos(w, target)
	return w.to_bytes()


static func read_turret_fire(r: DotNetReader) -> Dictionary:
	var id := r.read_varint()
	var target := _read_pos(r)
	return {"id": id, "target": target, "ok": r.ok()}


static func write_id(id: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(id)
	return w.to_bytes()


static func read_id(r: DotNetReader) -> Dictionary:
	var id := r.read_varint()
	return {"id": id, "ok": r.ok()}


static func write_throw(id: int, kind: StringName, from: Vector3, velocity: Vector3) -> PackedByteArray:
	var w := _w()
	w.write_varint(id)
	w.write_string(String(kind), ID_BYTES)
	_pos(w, from)
	w.write_vector3_range(velocity, -SPEED_MAX, SPEED_MAX, SPEED_BITS)
	return w.to_bytes()


static func read_throw(r: DotNetReader) -> Dictionary:
	var id := r.read_varint()
	var kind := r.read_string(ID_BYTES)
	var from := _read_pos(r)
	var velocity := r.read_vector3_range(-SPEED_MAX, SPEED_MAX, SPEED_BITS)
	return {"id": id, "kind": StringName(kind), "from": from, "velocity": velocity, "ok": r.ok()}


static func write_landed(id: int, kind: StringName, at: Vector3) -> PackedByteArray:
	var w := _w()
	w.write_varint(id)
	w.write_string(String(kind), ID_BYTES)
	_pos(w, at)
	return w.to_bytes()


static func read_landed(r: DotNetReader) -> Dictionary:
	var id := r.read_varint()
	var kind := r.read_string(ID_BYTES)
	var at := _read_pos(r)
	return {"id": id, "kind": StringName(kind), "at": at, "ok": r.ok()}


static func write_blast(at: Vector3, radius: float, kind: StringName) -> PackedByteArray:
	var w := _w()
	_pos(w, at)
	w.write_float_range(clampf(radius, 0.0, 64.0), 0.0, 64.0, 12)
	w.write_string(String(kind), ID_BYTES)
	return w.to_bytes()


static func read_blast(r: DotNetReader) -> Dictionary:
	var at := _read_pos(r)
	var radius := r.read_float_range(0.0, 64.0, 12)
	var kind := r.read_string(ID_BYTES)
	return {"at": at, "radius": radius, "kind": StringName(kind), "ok": r.ok()}


static func write_bile(player_id: int, seconds: float) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_float_range(clampf(seconds, 0.0, 120.0), 0.0, 120.0, 12)
	return w.to_bytes()


static func read_bile(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var seconds := r.read_float_range(0.0, 120.0, 12)
	return {"player_id": player_id, "seconds": seconds, "ok": r.ok()}


# --- Objectives ----------------------------------------------------------------

## An objective changed: its index and state (1 holding, 2 done).
static func write_objective(index: int, state: int) -> PackedByteArray:
	var w := _w()
	w.write_uint(clampi(index, 0, 31), 5)
	w.write_uint(clampi(state, 0, 3), 2)
	return w.to_bytes()


static func read_objective(r: DotNetReader) -> Dictionary:
	var index := r.read_uint(5)
	var state := r.read_uint(2)
	return {"index": index, "state": state, "ok": r.ok()}


static func write_mover(state: Array, index: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(index)
	w.write_varint(int(state[0]))
	w.write_uint(clampi(int(state[1]), 0, 1000), 10)
	w.write_uint(clampi(int(state[2]) + 1, 0, 2), 2)
	w.write_uint(int(state[3]), 1)
	w.write_uint(int(state[4]), 1)
	return w.to_bytes()


static func read_mover(r: DotNetReader) -> Dictionary:
	var index := r.read_varint()
	var start := r.read_varint()
	var from := r.read_uint(10)
	var dir := r.read_uint(2) - 1
	var locked := r.read_uint(1)
	var side := r.read_uint(1)
	return {"index": index, "start": start, "from": from, "dir": dir, "locked": locked != 0, "side": 1.0 if side != 0 else -1.0, "ok": r.ok()}


## [param mover] is the copy's mover index in the MOVER stream, -1 for a copy that does not move.
static func write_copy(id: int, model: int, offset: Vector3, alive: bool, mover: int = -1) -> PackedByteArray:
	var w := _w()
	w.write_varint(id)
	w.write_varint(model)
	_pos(w, offset)
	w.write_uint(1 if alive else 0, 1)
	w.write_varint(maxi(mover + 1, 0))
	return w.to_bytes()


static func read_copy(r: DotNetReader) -> Dictionary:
	var id := r.read_varint()
	var model := r.read_varint()
	var offset := _read_pos(r)
	var alive := r.read_uint(1)
	var mover := r.read_varint() - 1
	return {"id": id, "model": model, "offset": offset, "alive": alive != 0, "mover": mover, "ok": r.ok()}


## A sound fade ([param from] and [param to] are -1 when the map gave none), a spin (pitch, 1-255, -1 for none), or a beat.
static func write_map_fx(fx: int, entity: int, flag: bool, seconds: float, from: float, to: float) -> PackedByteArray:
	var w := _w()
	w.write_uint(fx, 2)
	w.write_uint(clampi(entity, 0, MAP_FX_ENTITIES), 16)
	w.write_bool(flag)
	w.write_uint(clampi(int(round(clampf(seconds, 0.0, MAP_FX_SECONDS) * 10.0)), 0, 6000), 13)
	w.write_uint(0 if from < 0.0 else clampi(int(round(from)) + 1, 1, 256), 9)
	w.write_uint(0 if to < 0.0 else clampi(int(round(to)) + 1, 1, 256), 9)
	return w.to_bytes()


## Volumes travel as 0-200 (the entity's tenths of full, clamped); pitches as 1-255.
static func write_map_fade(entity: int, fading_in: bool, seconds: float, from: float, to: float) -> PackedByteArray:
	return write_map_fx(MapFx.FADE, entity, fading_in, seconds, -1.0 if from < 0.0 else clampf(from, 0.0, 1.0) * 200.0, -1.0 if to < 0.0 else clampf(to, 0.0, 1.0) * 200.0)


static func write_map_spin(entity: int, seconds: float, from: float, to: float) -> PackedByteArray:
	return write_map_fx(MapFx.SPIN, entity, true, seconds, -1.0 if from < 0.0 else clampf(from, 1.0, 255.0), -1.0 if to < 0.0 else clampf(to, 1.0, 255.0))


static func write_map_beat(beat: int, downbeat: bool) -> PackedByteArray:
	return write_map_fx(MapFx.BEAT, 0, downbeat, 0.0, float(clampi(beat, 0, 255)), -1.0)


## Whether a point is a finite place inside the world's wire range.
static func sane_point(p: Variant) -> bool:
	return p is Vector3 and is_finite((p as Vector3).x) and is_finite((p as Vector3).y) and is_finite((p as Vector3).z) \
		and absf((p as Vector3).x) <= WORLD_EXTENT and absf((p as Vector3).y) <= WORLD_EXTENT and absf((p as Vector3).z) <= WORLD_EXTENT


## The one clamp both ends use: scale 0.05-1 (NaN is 1), seconds 0-15 (NaN is 0), the point or null when it is not finite and inside the world.
static func sane_end(time_scale: float, seconds: float, camera: Variant) -> Dictionary:
	return {"time_scale": 1.0 if is_nan(time_scale) else clampf(time_scale, END_SCALE_MIN, 1.0),
		"seconds": 0.0 if is_nan(seconds) else clampf(seconds, 0.0, END_SECONDS_MAX),
		"camera": camera if sane_point(camera) else null}


## A map's ending: who won, the slow motion and the camera point (none when absent or not sane).
static func write_map_end(won: bool, time_scale: float, seconds: float, camera: Variant) -> PackedByteArray:
	var e := sane_end(time_scale, seconds, camera)
	var w := _w()
	w.write_uint(MapFx.END, 2)
	w.write_bool(won)
	w.write_uint(clampi(int(round(float(e["seconds"]) * 10.0)), 0, 150), 8)
	w.write_uint(clampi(int(round(float(e["time_scale"]) * 200.0)), 10, 200), 8)
	w.write_bool(e["camera"] != null)
	if e["camera"] != null:
		_pos(w, e["camera"])
	return w.to_bytes()


## Decoded and clamped again: a fade's volumes are 0-1, a spin's pitches 1-255, a beat's number 0-255, with -1 for none.
static func read_map_fx(r: DotNetReader) -> Dictionary:
	var fx := r.read_uint(2)
	if fx == MapFx.END:
		var won := r.read_bool()
		var seconds := float(r.read_uint(8)) / 10.0
		var scale := float(r.read_uint(8)) / 200.0
		var camera: Variant = _read_pos(r) if r.read_bool() else null
		var e := sane_end(scale, seconds, camera)
		return {"fx": fx, "won": won, "time_scale": e["time_scale"], "seconds": e["seconds"], "camera": e["camera"], "ok": r.ok()}
	var entity := r.read_uint(16)
	var flag := r.read_bool()
	var seconds := float(r.read_uint(13)) / 10.0
	var from := float(r.read_uint(9)) - 1.0
	var to := float(r.read_uint(9)) - 1.0
	if fx == MapFx.FADE:
		from = -1.0 if from < 0.0 else clampf(from / 200.0, 0.0, 1.0)
		to = -1.0 if to < 0.0 else clampf(to / 200.0, 0.0, 1.0)
	return {"fx": fx, "entity": entity, "flag": flag, "seconds": clampf(seconds, 0.0, MAP_FX_SECONDS), "from": from, "to": to,
		"ok": r.ok() and fx <= MapFx.BEAT}


static func write_gate(gate: String) -> PackedByteArray:
	var w := _w()
	w.write_string(gate, ID_BYTES)
	return w.to_bytes()


static func read_gate(r: DotNetReader) -> Dictionary:
	var gate := r.read_string(ID_BYTES)
	return {"gate": gate, "ok": r.ok()}


## A survival map's hold, as [method ZzGame.survival_state] says it. `left` and `remaining` are
## -1 for none, sent one up; the twist is its index in [constant TWIST_NAMES] (0 none).
const TWIST_NAMES := ["", "sprinters", "swarm", "heavies", "hunters"]

static func write_survival(state: Dictionary) -> PackedByteArray:
	var w := _w()
	w.write_uint(clampi(int(state.get("style", 0)), 0, 3), 2)
	w.write_uint(clampi(int(state.get("stage", 0)), 0, 3), 2)
	w.write_uint(clampi(int(state.get("index", 0)), 0, 255), 8)
	w.write_uint(clampi(int(state.get("count", 0)), 0, 255), 8)
	w.write_float_range(clampf(float(state.get("left", -1.0)) + 1.0, 0.0, CLOCK_MAX), 0.0, CLOCK_MAX, CLOCK_BITS)
	w.write_varint(maxi(int(state.get("remaining", -1)) + 1, 0))
	w.write_uint(maxi(TWIST_NAMES.find(str(state.get("twist", ""))), 0), 3)
	w.write_float_range(clampf(float(state.get("daylight", -1.0)) + 1.0, 0.0, 2.0), 0.0, 2.0, 8)
	return w.to_bytes()


static func read_survival(r: DotNetReader) -> Dictionary:
	var style := r.read_uint(2)
	var stage := r.read_uint(2)
	var index := r.read_uint(8)
	var count := r.read_uint(8)
	var left := r.read_float_range(0.0, CLOCK_MAX, CLOCK_BITS) - 1.0
	var remaining := r.read_varint() - 1
	var twist := r.read_uint(3)
	var daylight := r.read_float_range(0.0, 2.0, 8) - 1.0
	return {
		"style": style, "stage": stage, "index": index, "count": count, "left": left if left > -0.5 else -1.0,
		"remaining": remaining, "twist": TWIST_NAMES[twist] if twist < TWIST_NAMES.size() else "",
		"daylight": daylight if daylight > -0.5 else -1.0, "ok": r.ok(),
	}


static func write_barricade(id: String, fraction: float, intact: bool) -> PackedByteArray:
	var w := _w()
	w.write_string(id, ID_BYTES)
	w.write_uint(clampi(int(round(clampf(fraction, 0.0, 1.0) * 255.0)), 0, 255), 8)
	w.write_bool(intact)
	return w.to_bytes()


static func read_barricade(r: DotNetReader) -> Dictionary:
	var id := r.read_string(ID_BYTES)
	var fraction := float(r.read_uint(8)) / 255.0
	var intact := r.read_bool()
	return {"id": id, "fraction": fraction, "intact": intact, "ok": r.ok()}


## You were hurt: how much, from where. For the red edge of the screen that says which way.
static func write_hurt(amount: float, from: Vector3) -> PackedByteArray:
	var w := _w()
	w.write_float_range(clampf(amount, 0.0, 500.0), 0.0, 500.0, 12)
	_pos(w, from)
	return w.to_bytes()


static func read_hurt(r: DotNetReader) -> Dictionary:
	var amount := r.read_float_range(0.0, 500.0, 12)
	var from := _read_pos(r)
	return {"amount": amount, "from": from, "ok": r.ok()}


## Your hit landed: on which zombie (its entity serial, which only groups hits on one body: a
## whole entity id is a kind times 10^12 and does not fit the field), how
## much, where, and whether it was a kill or a head. For the shooter's hit marker and damage
## numbers, which are drawn from this and never from the local prediction.
static func write_hit(victim: int, amount: float, point: Vector3, killed: bool, headshot: bool) -> PackedByteArray:
	var w := _w()
	w.write_uint(clampi(victim % DotEntity.STRIDE, 0, 0xFFFFFFFF), 32)
	w.write_float_range(clampf(amount, 0.0, 1000.0), 0.0, 1000.0, 14)
	_pos(w, point)
	w.write_uint((1 if killed else 0) | (2 if headshot else 0), 2)
	return w.to_bytes()


static func read_hit(r: DotNetReader) -> Dictionary:
	var victim := r.read_uint(32)
	var amount := r.read_float_range(0.0, 1000.0, 14)
	var point := _read_pos(r)
	var flags := r.read_uint(2)
	return {"victim": victim, "amount": amount, "point": point, "killed": flags & 1 != 0,
		"headshot": flags & 2 != 0, "ok": r.ok()}


## The octahedral normal's bits per axis: 6 gives about 2 degrees, plenty for a blood decal.
## 63 levels (not 64), so 0 sits on a level and an axis normal round-trips exactly.
const NORMAL_BITS := 6
const NORMAL_TOP := (1 << NORMAL_BITS) - 2


static func write_splat(point: Vector3, normal: Vector3) -> PackedByteArray:
	var w := _w()
	_pos(w, point)
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var o := Vector2(n.x, n.z) / (absf(n.x) + absf(n.y) + absf(n.z))
	if n.y < 0.0:
		o = Vector2((1.0 - absf(o.y)) * _sign(o.x), (1.0 - absf(o.x)) * _sign(o.y))
	w.write_uint(clampi(roundi((o.x * 0.5 + 0.5) * NORMAL_TOP), 0, NORMAL_TOP), NORMAL_BITS)
	w.write_uint(clampi(roundi((o.y * 0.5 + 0.5) * NORMAL_TOP), 0, NORMAL_TOP), NORMAL_BITS)
	return w.to_bytes()


static func _sign(v: float) -> float:
	return -1.0 if v < 0.0 else 1.0


static func read_splat(r: DotNetReader) -> Dictionary:
	var point := _read_pos(r)
	var x := float(r.read_uint(NORMAL_BITS)) / NORMAL_TOP * 2.0 - 1.0
	var z := float(r.read_uint(NORMAL_BITS)) / NORMAL_TOP * 2.0 - 1.0
	var y := 1.0 - absf(x) - absf(z)
	if y < 0.0:
		var ox := x
		x = (1.0 - absf(z)) * _sign(ox)
		z = (1.0 - absf(ox)) * _sign(z)
	var n := Vector3(x, y, z)
	return {"point": point, "normal": n.normalized() if n.length_squared() > 0.0001 else Vector3.UP, "ok": r.ok()}


# --- Chat ------------------------------------------------------------------

## A chat line's own field widths. Wider than the rules allow, so a rule can be raised
## without the wire silently truncating what it lets through.
const CHAT_BYTES := 200
const CHAT_CHANNEL_BYTES := 24
const CHAT_KEY_BYTES := 48
const CHAT_KIND_BITS := 4


## Whether every [enum DotChatMessage.Kind] fits in [constant CHAT_KIND_BITS]. dot-chat owns
## that enum, so it can grow under this game; headless_net reads this.
static func chat_kinds_fit() -> bool:
	return DotChatMessage.KIND_NAMES.size() <= (1 << CHAT_KIND_BITS)


## One routed line, in [DotChatMessage]'s own wire shape.
##
## [b]Field by field rather than `var_to_bytes`, like every other message here.[/b] A
## dictionary serialised whole is a dictionary whose contents are whatever the sender put
## in it — including keys a client will happily read — and the widths below are the
## validation. `x.p` is the one meta field this game carries: the speaker's session id, so
## a client can colour a line by whose it is.
static func write_chat(wire: Dictionary) -> PackedByteArray:
	var w := _w()
	w.write_varint(int(wire.get("n", 0)))
	w.write_uint(int(wire.get("t", 0)), 32)
	w.write_string(str(wire.get("c", "")), CHAT_CHANNEL_BYTES)
	w.write_uint(
		maxi(0, DotChatMessage.kind_from_name(str(wire.get("k", "say")))), CHAT_KIND_BITS
	)
	w.write_string(str(wire.get("s", "")), CHAT_KEY_BYTES)
	w.write_string(str(wire.get("d", "")), NAME_BYTES)
	w.write_string(str(wire.get("w", "")), CHAT_KEY_BYTES)
	w.write_string(str(wire.get("m", "")), CHAT_BYTES)

	var meta: Variant = wire.get("x")
	var player_id := 0

	if typeof(meta) == TYPE_DICTIONARY:
		player_id = int((meta as Dictionary).get("p", 0))

	w.write_varint(maxi(player_id, 0))
	return w.to_bytes()


static func read_chat(r: DotNetReader) -> Dictionary:
	var out := {
		"n": r.read_varint(),
		"t": r.read_uint(32),
		"c": r.read_string(CHAT_CHANNEL_BYTES),
	}

	var kind := r.read_uint(CHAT_KIND_BITS)
	out["k"] = (
		DotChatMessage.KIND_NAMES[kind] if kind >= 0 and kind < DotChatMessage.KIND_NAMES.size()
		else "say"
	)

	out["s"] = r.read_string(CHAT_KEY_BYTES)
	out["d"] = r.read_string(NAME_BYTES)
	out["w"] = r.read_string(CHAT_KEY_BYTES)
	out["m"] = r.read_string(CHAT_BYTES)

	var player_id := r.read_varint()

	if player_id > 0:
		out["x"] = {"p": player_id}

	out["ok"] = r.ok()
	return out


## What a client sends when somebody presses Enter: a channel and a line, and nothing else.
##
## [b]No speaker, no time, no colour.[/b] Everything about what a line MEANS is decided on
## the server — who said it, whether they are gagged, whether they are talking too fast,
## which channel they may use and who can hear it. A client that sent any of that would be
## a client that could claim it.
static func write_say(channel_id: StringName, text: String) -> PackedByteArray:
	var w := _w()
	w.write_string(String(channel_id), CHAT_CHANNEL_BYTES)
	w.write_string(text, CHAT_BYTES)
	return w.to_bytes()


static func read_say(r: DotNetReader) -> Dictionary:
	var out := {
		"channel": r.read_string(CHAT_CHANNEL_BYTES),
		"text": r.read_string(CHAT_BYTES),
	}
	out["ok"] = r.ok()
	return out


const SHOP_BYTES := 32768
const CARRY_BYTES := 2048


static func write_carry(json: String) -> PackedByteArray:
	var w := _w()
	w.write_bytes(json.to_utf8_buffer().slice(0, CARRY_BYTES))
	return w.to_bytes()


static func read_carry(r: DotNetReader) -> Dictionary:
	var raw := r.read_bytes(CARRY_BYTES)
	return {"json": raw.get_string_from_utf8(), "ok": r.ok()}



static func write_shop(json: String) -> PackedByteArray:
	var w := _w()
	w.write_bytes(json.to_utf8_buffer().slice(0, SHOP_BYTES))
	return w.to_bytes()


static func read_shop(r: DotNetReader) -> Dictionary:
	var raw := r.read_bytes(SHOP_BYTES)
	return {"json": raw.get_string_from_utf8(), "ok": r.ok()}


static func write_buy(item_id: String) -> PackedByteArray:
	var w := _w()
	w.write_string(item_id, ID_BYTES)
	return w.to_bytes()


static func read_buy(r: DotNetReader) -> Dictionary:
	var id := r.read_string(ID_BYTES)
	return {"id": id, "ok": r.ok()}


static func write_notice(text: String) -> PackedByteArray:
	var w := _w()
	w.write_string(text, TEXT_BYTES)
	return w.to_bytes()


static func read_notice(r: DotNetReader) -> Dictionary:
	var text := r.read_string(TEXT_BYTES)
	return {"text": text, "ok": r.ok()}
