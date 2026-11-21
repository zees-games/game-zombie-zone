extends RefCounted

const ZzEvents := preload("zz_events.gd")

## The chat, carry, class, shop, buy, fit and notice messages of [ZzEvents]' wire (the text-bodied ones), same pairing rules.

## A chat line's own field widths. Wider than the rules allow, so a rule can be raised
## without the wire silently truncating what it lets through.
const CHAT_BYTES := 200
const CHAT_CHANNEL_BYTES := 24
const CHAT_KEY_BYTES := 48
const CHAT_KIND_BITS := 4


## Whether every [enum GSChatMessage.Kind] fits in [constant CHAT_KIND_BITS]. gs-chat owns
## that enum, so it can grow under this game; headless_net reads this.
static func chat_kinds_fit() -> bool:
	return GSChatMessage.KIND_NAMES.size() <= (1 << CHAT_KIND_BITS)


## One routed line, in [GSChatMessage]'s own wire shape.
## Field by field rather than `var_to_bytes`: the widths below are the validation. `x.p` is the
## one meta field carried, the speaker's session id, so a client can colour a line by whose it is.
static func write_chat(wire: Dictionary) -> PackedByteArray:
	var w := GSNetWriter.new()
	w.write_varint(int(wire.get("n", 0)))
	w.write_uint(int(wire.get("t", 0)), 32)
	w.write_string(str(wire.get("c", "")), CHAT_CHANNEL_BYTES)
	w.write_uint(
		maxi(0, GSChatMessage.kind_from_name(str(wire.get("k", "say")))), CHAT_KIND_BITS
	)
	w.write_string(str(wire.get("s", "")), CHAT_KEY_BYTES)
	w.write_string(str(wire.get("d", "")), ZzEvents.NAME_BYTES)
	w.write_string(str(wire.get("w", "")), CHAT_KEY_BYTES)
	w.write_string(str(wire.get("m", "")), CHAT_BYTES)

	var meta: Variant = wire.get("x")
	var player_id := 0

	if typeof(meta) == TYPE_DICTIONARY:
		player_id = int((meta as Dictionary).get("p", 0))

	w.write_varint(maxi(player_id, 0))
	return w.to_bytes()


static func read_chat(r: GSNetReader) -> Dictionary:
	var out := {
		"n": r.read_varint(),
		"t": r.read_uint(32),
		"c": r.read_string(CHAT_CHANNEL_BYTES),
	}

	var kind := r.read_uint(CHAT_KIND_BITS)
	out["k"] = (
		GSChatMessage.KIND_NAMES[kind] if kind >= 0 and kind < GSChatMessage.KIND_NAMES.size()
		else "say"
	)

	out["s"] = r.read_string(CHAT_KEY_BYTES)
	out["d"] = r.read_string(ZzEvents.NAME_BYTES)
	out["w"] = r.read_string(CHAT_KEY_BYTES)
	out["m"] = r.read_string(CHAT_BYTES)

	var player_id := r.read_varint()

	if player_id > 0:
		out["x"] = {"p": player_id}

	out["ok"] = r.ok()
	return out


## What a client sends when somebody presses Enter: a channel and a line, and nothing else.
## No speaker, no time, no colour: the server decides who said it, whether they are gagged or
## too fast, which channel they may use and who hears it.
static func write_say(channel_id: StringName, text: String) -> PackedByteArray:
	var w := GSNetWriter.new()
	w.write_string(String(channel_id), CHAT_CHANNEL_BYTES)
	w.write_string(text, CHAT_BYTES)
	return w.to_bytes()


static func read_say(r: GSNetReader) -> Dictionary:
	var out := {
		"channel": r.read_string(CHAT_CHANNEL_BYTES),
		"text": r.read_string(CHAT_BYTES),
	}
	out["ok"] = r.ok()
	return out


const SHOP_BYTES := 32768
const CARRY_BYTES := 2048


static func write_carry(json: String) -> PackedByteArray:
	var w := GSNetWriter.new()
	w.write_bytes(json.to_utf8_buffer().slice(0, CARRY_BYTES))
	return w.to_bytes()


static func read_carry(r: GSNetReader) -> Dictionary:
	var raw := r.read_bytes(CARRY_BYTES)
	return {"json": raw.get_string_from_utf8(), "ok": r.ok()}



static func write_classed(player_id: int, class_id: StringName, skin: StringName) -> PackedByteArray:
	var w := GSNetWriter.new()
	w.write_varint(player_id)
	w.write_string(String(class_id), ZzEvents.ID_BYTES)
	w.write_string(String(skin), ZzEvents.ID_BYTES)
	return w.to_bytes()


static func read_classed(r: GSNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var class_id := r.read_string(ZzEvents.ID_BYTES)
	var skin := r.read_string(ZzEvents.ID_BYTES)
	return {"player_id": player_id, "class_id": StringName(class_id), "skin": StringName(skin), "ok": r.ok()}


static func write_shop(json: String) -> PackedByteArray:
	var w := GSNetWriter.new()
	w.write_bytes(json.to_utf8_buffer().slice(0, SHOP_BYTES))
	return w.to_bytes()


static func read_shop(r: GSNetReader) -> Dictionary:
	var raw := r.read_bytes(SHOP_BYTES)
	return {"json": raw.get_string_from_utf8(), "ok": r.ok()}


static func write_buy(item_id: String) -> PackedByteArray:
	var w := GSNetWriter.new()
	w.write_string(item_id, ZzEvents.ID_BYTES)
	return w.to_bytes()


static func read_buy(r: GSNetReader) -> Dictionary:
	var id := r.read_string(ZzEvents.ID_BYTES)
	return {"id": id, "ok": r.ok()}


## A fitting asked for: the weapon and its [method GSWeaponAttachments.encode] code, which both
## sides compute from the same catalogue (the build's packs). Ids would not fit [ZzRequest]'s body.
static func write_fit(weapon_id: StringName, code: int) -> PackedByteArray:
	var w := GSNetWriter.new()
	w.write_string(String(weapon_id), ZzEvents.ID_BYTES)
	w.write_varint(maxi(code, 0))
	return w.to_bytes()


static func read_fit(r: GSNetReader) -> Dictionary:
	var id := r.read_string(ZzEvents.ID_BYTES)
	var code := r.read_varint()
	return {"id": StringName(id), "code": code, "ok": r.ok() and code >= 0}


static func write_notice(text: String) -> PackedByteArray:
	var w := GSNetWriter.new()
	w.write_string(text, ZzEvents.TEXT_BYTES)
	return w.to_bytes()


static func read_notice(r: GSNetReader) -> Dictionary:
	var text := r.read_string(ZzEvents.TEXT_BYTES)
	return {"text": text, "ok": r.ok()}
