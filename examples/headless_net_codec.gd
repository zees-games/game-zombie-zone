extends "headless_net_late.gd"


static func _r(bytes: PackedByteArray) -> GSNetReader:
	return GSNetReader.new(bytes)


## Every encoder against its decoder. Nothing checks that two ends of a serialisation are
## inverses for you: gs-moderation once wrote "voice muted" and read back a warning.
func _test_the_codec() -> void:
	_section("every event decodes to what was encoded")

	var hello := ZzEvents.read_hello(_r(ZzEvents.write_hello(SESSION, 64, 1234, 2, 3)))
	_check(bool(hello["ok"]) and int(hello["player_id"]) == SESSION and int(hello["tick_rate"]) == 64
		and int(hello["server_tick"]) == 1234 and int(hello["difficulty"]) == 2 and int(hello["max_incaps"]) == 3,
		"HELLO", str(hello))

	var hello_caps := ZzEvents.read_hello(_r(ZzEvents.write_hello(SESSION, 64, 1234, 2, 3, "zz_map_objectives=0,zz_tick_rate=480")))
	_check(bool(hello_caps["ok"]) and str(hello_caps["caps"]) == "zz_map_objectives=0,zz_tick_rate=480" and int(hello_caps["max_incaps"]) == 3, "HELLO carries the server's advertised limits", str(hello_caps))
	_check(str(hello["caps"]).is_empty(), "a HELLO without limits reads as none")

	var wide_hello := ZzEvents.read_hello(_r(ZzEvents.write_hello(SESSION, 600, 1234, 2, 3, "zz_tick_rate=0")))
	_check(bool(wide_hello["ok"]) and int(wide_hello["tick_rate"]) == 600 and str(wide_hello["caps"]) == "zz_tick_rate=0" and int(wide_hello["max_incaps"]) == 3, "HELLO carries a tick rate above 511 whole", str(wide_hello))
	var edge_hello := ZzEvents.read_hello(_r(ZzEvents.write_hello(SESSION, 511, 1234, 2, 3)))
	_check(bool(edge_hello["ok"]) and int(edge_hello["tick_rate"]) == 511, "HELLO 511 stays in the 9 bits", str(edge_hello))
	_check(ZzEvents.write_hello(SESSION, 511, 1, 2, 3, "x").size() < ZzEvents.write_hello(SESSION, 512, 1, 2, 3, "x").size(), "HELLO at or under 511 has no extra field")
	# An older client reads the 9 bits and stops: it must see 0 (refused by its rate check), never a truncated rate.
	var old_r := _r(ZzEvents.write_hello(SESSION, 600, 1234, 2, 3, "zz_tick_rate=0"))
	old_r.read_varint()
	_check(old_r.read_uint(9) == 0, "an older reader sees 0 for a rate over 511, not 600 & 511")
	var cut := ZzEvents.write_hello(SESSION, 600, 1234, 2, 3, "x")
	_check(not bool(ZzEvents.read_hello(_r(cut.slice(0, cut.size() - 2)))["ok"]), "a cut-off wide HELLO is refused")

	var doc := ZzCatalogue.practice()
	var sent := ZzEvents.read_map(_r(ZzEvents.write_map(ZzMapDoc.encode(doc))))
	var decoded := ZzMapDoc.decode(sent["encoded"]) if bool(sent["ok"]) else GSResult.fail(GSError.CODE_PARSE, "no map")
	_check(decoded.ok and ZzMapDoc.digest(decoded.value) == ZzMapDoc.digest(doc), "MAP carries the document whole")

	var join := ZzEvents.read_join(_r(ZzEvents.write_join(SESSION, 9, "Ada", ZzGame.SURVIVORS, null)))
	_check(bool(join["ok"]) and int(join["team"]) == ZzGame.SURVIVORS and str(join["name"]) == "Ada", "JOIN", str(join))

	var round_info := ZzEvents.read_round(_r(ZzEvents.write_round(3, false, false, "everybody is down")))
	_check(bool(round_info["ok"]) and not bool(round_info["won"]) and str(round_info["why"]) == "everybody is down",
		"ROUND carries the result and the sentence")

	var clock := ZzEvents.read_clock(_r(ZzEvents.write_clock(3, 2, 40.25, 12.5, 60.0, 4, true, 0, 1, 20.0, 17.5)))
	_check(bool(clock["ok"]) and int(clock["round"]) == 3 and absf(float(clock["elapsed"]) - 40.25) < 0.1
		and absf(float(clock["held"]) - 12.5) < 0.1 and int(clock["alive"]) == 4 and int(clock["objective"]) == 0
		and int(clock["objective_state"]) == 1 and absf(float(clock["grace_left"]) - 17.5) < 0.2, "CLOCK", str(clock))

	var big_hello := ZzEvents.read_hello(_r(ZzEvents.write_hello(SESSION, 64, 1234, 2, 300)))
	_check(bool(big_hello["ok"]) and int(big_hello["max_incaps"]) == 300, "HELLO carries max_incaps above the old 15", str(big_hello))
	var big_clock := ZzEvents.read_clock(_r(ZzEvents.write_clock(3, 2, 9000.5, 9000.0, 20000.0, 400, true, 0, 1, 20.0, 9500.0)))
	_check(bool(big_clock["ok"]) and int(big_clock["alive"]) == 400 and absf(float(big_clock["elapsed"]) - 9000.5) < 0.1
		and absf(float(big_clock["held"]) - 9000.0) < 0.1, "CLOCK carries alive above 255 and seconds above 7200", str(big_clock))

	var npc := ZzEvents.read_npc(_r(ZzEvents.write_npc(77, ZzNpcs.STRANGLER, 513, Vector3(3.5, 0.0, -12.25))))
	_check(bool(npc["ok"]) and int(npc["net_id"]) == 77 and npc["kind"] == ZzNpcs.STRANGLER and int(npc["variant"]) == 513
		and (npc["at"] as Vector3).distance_to(Vector3(3.5, 0.0, -12.25)) < 0.05, "NPC", str(npc))

	_check_codec_map_fx()
	var held := ZzEvents.read_possess(_r(ZzEvents.write_possess(4097)))
	_check(bool(held["ok"]) and int(held["net_id"]) == 4097, "POSSESS names the body", str(held))
	var let_go := ZzEvents.read_possess(_r(ZzEvents.write_possess(0)))
	_check(bool(let_go["ok"]) and int(let_go["net_id"]) == 0, "POSSESS 0 lets go", str(let_go))
	var negative := ZzEvents.read_possess(_r(ZzEvents.write_possess(-5)))
	_check(bool(negative["ok"]) and int(negative["net_id"]) == 0, "POSSESS clamps a negative id to none", str(negative))
	_check(not bool(ZzEvents.read_possess(_r(PackedByteArray()))["ok"]), "POSSESS: an empty body reads as not ok")

	var gone := ZzEvents.read_npc_gone(_r(ZzEvents.write_npc_gone(77, true)))
	_check(bool(gone["ok"]) and int(gone["net_id"]) == 77 and bool(gone["killed"]) and gone["death"] == null, "NPC_GONE")
	var fall := GSPlayerDeath.decide(GSPlayerDeathReactions.stock(), true, 120.0, Vector3(0, 0, -1), 4242)
	var fell := ZzEvents.read_npc_gone(_r(ZzEvents.write_npc_gone(78, true, fall)))
	var told: GSPlayerDeath = fell["death"]
	_check(bool(fell["ok"]) and told != null and told.reaction == fall.reaction and told.roll_seed == 4242
		and told.direction.distance_to(Vector3(0, 0, -1)) < 0.05 and told.headshot,
		"NPC_GONE with how it fell", String(told.reaction) if told != null else "-")

	_check_codec_world()
	_finished()


## Pins, loot, boxes, the event field and the request and chat kinds.
func _check_codec_world() -> void:
	var pin := ZzEvents.read_pin(_r(ZzEvents.write_pin(SESSION, 77, &"choke")))
	_check(bool(pin["ok"]) and int(pin["player_id"]) == SESSION and int(pin["npc"]) == 77 and pin["kind"] == &"choke", "PIN")

	var loot := ZzEvents.read_loot(_r(ZzEvents.write_loot(5, ZzLoot.WEAPON, &"shotgun", Vector3(1.0, 0.5, 2.0))))
	_check(bool(loot["ok"]) and int(loot["id"]) == 5 and loot["kind"] == ZzLoot.WEAPON and loot["item"] == &"shotgun"
		and (loot["at"] as Vector3).distance_to(Vector3(1.0, 0.5, 2.0)) < 0.05, "LOOT", str(loot))

	var box := ZzEvents.read_box(_r(ZzEvents.write_box(SESSION, &"explosive", "Short fuse", "Ada opened it")))
	_check(bool(box["ok"]) and box["type"] == &"explosive" and str(box["title"]) == "Short fuse"
		and str(box["message"]) == "Ada opened it", "BOX")

	# Every kind fits the event's kind field: at 5 bits HURT and AMMO wrapped to HELLO and MAP.
	# The largest MAP a reader accepts survives the event's own body cap. At 4096 a 4100-byte map
	# went out whole and was read back as no bytes, silently (hs_park with its toys).
	var biggest := PackedByteArray()
	biggest.resize(ZzEvents.MAP_BYTES)
	var outgoing := ZzEvent.new(ZzEvents.Kind.MAP, ZzEvents.write_map(biggest))
	var wire := GSNetWriter.new()
	outgoing._write(wire)
	var incoming := ZzEvent.new()
	incoming._read(GSNetReader.new(wire.to_bytes()))
	var carried := ZzEvents.read_map(incoming.reader())
	_check(bool(carried["ok"]) and (carried["encoded"] as PackedByteArray).size() == ZzEvents.MAP_BYTES,
		"a MAP as large as a reader accepts fits in an event", "%d of %d bytes" % [(carried["encoded"] as PackedByteArray).size(), ZzEvents.MAP_BYTES])

	_check(ZzEvent.fits(), "every event kind fits the kind field",
		"%d kinds in %d bits" % [ZzEvents.Kind.size(), ZzEvent.KIND_BITS])

	_check_codec_effects()
	# A kind goes out in a fixed field the writer masks without a word, so one past it aliases a
	# smaller kind: game-zombie-zone sent HURT and AMMO as HELLO and MAP that way.
	_check(ZzRequest.fits(), "every request kind fits the request's kind field",
		"%d kinds in %d bits" % [ZzEvents.Ask.size(), ZzRequest.KIND_BITS])
	_check(ZzEventsText.chat_kinds_fit(), "every chat kind fits the chat line's kind field",
		"%d kinds in %d bits" % [GSChatMessage.KIND_NAMES.size(), ZzEventsText.CHAT_KIND_BITS])


## Map effects, objectives, endings and copies decode, and the wild ones are clamped.
func _check_codec_map_fx() -> void:
	var fade := ZzEventsMapFx.read_map_fx(_r(ZzEventsMapFx.write_map_fade(7, true, 2.5, 0.0, 0.8)))
	_check(bool(fade["ok"]) and int(fade["fx"]) == ZzEvents.MapFx.FADE and int(fade["entity"]) == 7 and bool(fade["flag"]) and absf(float(fade["seconds"]) - 2.5) < 0.01
		and absf(float(fade["to"]) - 0.8) < 0.01 and float(fade["from"]) == 0.0, "MAP_FX fade", str(fade))
	var spin := ZzEventsMapFx.read_map_fx(_r(ZzEventsMapFx.write_map_spin(9, 4.0, 40.0, 100.0)))
	_check(bool(spin["ok"]) and int(spin["fx"]) == ZzEvents.MapFx.SPIN and float(spin["from"]) == 40.0 and float(spin["to"]) == 100.0, "MAP_FX spin", str(spin))
	var beat := ZzEventsMapFx.read_map_fx(_r(ZzEventsMapFx.write_map_beat(5, true)))
	_check(bool(beat["ok"]) and int(beat["fx"]) == ZzEvents.MapFx.BEAT and int(beat["from"]) == 5 and bool(beat["flag"]), "MAP_FX beat", str(beat))
	var wild := ZzEventsMapFx.read_map_fx(_r(ZzEventsMapFx.write_map_fade(999999, true, 1.0e6, 7.0, -3.0)))
	_check(bool(wild["ok"]) and absf(float(wild["seconds"]) - 1.0e6) < 0.1 and float(wild["from"]) <= 1.0 and float(wild["to"]) == -1.0 and int(wild["entity"]) == 999999,
		"MAP_FX entity and seconds are varints (no 65535 or 600 s limit); volumes are still clamped", str(wild))
	var objective := ZzEvents.read_objective(_r(ZzEvents.write_objective(40, 2)))
	_check(bool(objective["ok"]) and int(objective["index"]) == 40 and int(objective["state"]) == 2, "OBJECTIVE index past 31 round-trips", str(objective))
	var big_obj := ZzEvents.read_clock(_r(ZzEvents.write_clock(1, 2, 1.0, 0.0, 0.0, 1, true, 99, 1, 0.0)))
	_check(bool(big_obj["ok"]) and int(big_obj["objective"]) == 99, "CLOCK carries an objective index past 30", str(big_obj))
	_check(not bool(ZzEventsMapFx.read_map_fx(_r(PackedByteArray([0xFF])))["ok"]), "MAP_FX: a truncated or unknown body reads as not ok")
	var ended := ZzEventsMapFx.read_map_fx(_r(ZzEventsMapFx.write_map_end(true, 0.25, 3.0, Vector3(10.0, 2.0, -5.0))))
	_check(bool(ended["ok"]) and int(ended["fx"]) == ZzEvents.MapFx.END and bool(ended["won"]) and absf(float(ended["time_scale"]) - 0.25) < 0.01
		and absf(float(ended["seconds"]) - 3.0) < 0.11 and (ended["camera"] as Vector3).distance_to(Vector3(10.0, 2.0, -5.0)) < 0.05, "MAP_FX end", str(ended))
	var wild_end := ZzEventsMapFx.read_map_fx(_r(ZzEventsMapFx.write_map_end(false, -4.0, 1.0e9, Vector3(1.0e12, 0.0, 0.0))))
	_check(bool(wild_end["ok"]) and float(wild_end["time_scale"]) == ZzEvents.END_SCALE_MIN and float(wild_end["seconds"]) == ZzEvents.END_SECONDS_MAX and wild_end["camera"] == null,
		"MAP_FX end: out-of-range scale, seconds and camera are clamped or dropped", str(wild_end))
	var nan_end := ZzEventsMapFx.read_map_fx(_r(ZzEventsMapFx.write_map_end(true, NAN, NAN, Vector3(NAN, 0.0, 0.0))))
	_check(bool(nan_end["ok"]) and float(nan_end["time_scale"]) == 1.0 and float(nan_end["seconds"]) == 0.0 and nan_end["camera"] == null, "MAP_FX end: NaN is rejected", str(nan_end))
	var copy := ZzEvents.read_copy(_r(ZzEvents.write_copy(412, 7, Vector3(12.5, 0.0, -3.0), true)))
	_check(bool(copy["ok"]) and int(copy["id"]) == 412 and int(copy["model"]) == 7 and bool(copy["alive"])
		and (copy["offset"] as Vector3).distance_to(Vector3(12.5, 0.0, -3.0)) < 0.05, "COPY", str(copy))


## Hits, splats, effects, hazards, turrets and blasts decode to what was written.
func _check_codec_effects() -> void:
	var hit := ZzEvents.read_hit(_r(ZzEvents.write_hit(GSEntity.make_id(GSEntity.KIND_NPC, 4321), 17.5, Vector3(1.0, 1.4, -6.0), true, true)))
	_check(bool(hit["ok"]) and int(hit["victim"]) == 4321 and absf(float(hit["amount"]) - 17.5) < 0.1
		and bool(hit["killed"]) and bool(hit["headshot"]) and (hit["point"] as Vector3).distance_to(Vector3(1.0, 1.4, -6.0)) < 0.01,
		"HIT (the victim's entity serial, so a whole entity id never overflows the field)", str(hit))

	var splat_bytes := ZzEvents.write_splat(Vector3(1.0, 1.4, -6.0), Vector3(0.6, -0.64, -0.48).normalized())
	var splat := ZzEvents.read_splat(_r(splat_bytes))
	_check(bool(splat["ok"]) and (splat["normal"] as Vector3).dot(Vector3(0.6, -0.64, -0.48).normalized()) > 0.98
		and (splat["point"] as Vector3).distance_to(Vector3(1.0, 1.4, -6.0)) < 0.01,
		"SPLAT (a point and a 12-bit octahedral normal, both hemispheres)", "%d bytes, %s" % [splat_bytes.size(), str(splat)])
	var up_splat := ZzEvents.read_splat(_r(ZzEvents.write_splat(Vector3.ZERO, Vector3.UP)))
	_check((up_splat["normal"] as Vector3).dot(Vector3.UP) > 0.99, "SPLAT keeps a floor facing up")
	var exact := true
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		var back: Vector3 = ZzEvents.read_splat(_r(ZzEvents.write_splat(Vector3.ZERO, axis)))["normal"]
		exact = exact and back.is_equal_approx(axis)
	_check(exact, "SPLAT round-trips an axis normal exactly (0 is a quantisation level)")
	var effects := ZzEvents.read_effects(_r(ZzEvents.write_effects([
		{"title": "Glass cannon", "stacks": 2, "seconds": 14.25, "who": "everybody", "scale": 1.5},
	])))
	var rows: Array = effects["effects"]
	_check(bool(effects["ok"]) and rows.size() == 1 and int(rows[0]["stacks"]) == 2 and str(rows[0]["title"]) == "Glass cannon",
		"EFFECTS", str(rows))

	var hazard := ZzEvents.read_hazard(_r(ZzEvents.write_hazard(9, &"acid", Vector3(2.0, 0.0, 3.0), 3.5, 7.0)))
	_check(bool(hazard["ok"]) and hazard["kind"] == &"acid" and absf(float(hazard["radius"]) - 3.5) < 0.05
		and absf(float(hazard["seconds"]) - 7.0) < 0.1, "HAZARD", str(hazard))

	var turret := ZzEvents.read_turret(_r(ZzEvents.write_turret(4, Vector3(1.0, 0.0, -2.0), 1.5, 45.0)))
	_check(bool(turret["ok"]) and int(turret["id"]) == 4 and absf(float(turret["yaw"]) - 1.5) < 0.02
		and absf(float(turret["seconds"]) - 45.0) < 0.1, "TURRET", str(turret))
	var turret_fire := ZzEvents.read_turret_fire(_r(ZzEvents.write_turret_fire(4, Vector3(3.0, 1.0, -9.0))))
	_check(bool(turret_fire["ok"]) and int(turret_fire["id"]) == 4
		and (turret_fire["target"] as Vector3).distance_to(Vector3(3.0, 1.0, -9.0)) < 0.1, "TURRET_FIRE", str(turret_fire))

	var blast := ZzEvents.read_blast(_r(ZzEvents.write_blast(Vector3(0.0, 1.0, 5.0), 6.0, &"pipe")))
	_check(bool(blast["ok"]) and blast["kind"] == &"pipe" and absf(float(blast["radius"]) - 6.0) < 0.05, "BLAST")


# Bringing both halves up
