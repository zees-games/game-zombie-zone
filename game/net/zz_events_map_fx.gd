extends RefCounted

const ZzEvents := preload("zz_events.gd")

## The map-effect messages (fades, spins, beats, the ending) of [ZzEvents]' wire, same pairing rules.


## A sound fade ([param from] and [param to] are -1 when the map gave none), a spin (pitch, 1-255, -1 for none), or a beat.
static func write_map_fx(fx: int, entity: int, flag: bool, seconds: float, from: float, to: float) -> PackedByteArray:
	var w := ZzEvents._w()
	w.write_uint(fx, 2)
	w.write_varint(maxi(entity, 0))
	w.write_bool(flag)
	w.write_varint(0 if is_nan(seconds) or is_inf(seconds) or seconds <= 0.0 else int(round(seconds * 10.0)))
	w.write_uint(0 if from < 0.0 else clampi(int(round(from)) + 1, 1, 256), 9)
	w.write_uint(0 if to < 0.0 else clampi(int(round(to)) + 1, 1, 256), 9)
	return w.to_bytes()


## Volumes travel as 0-200 (the entity's tenths of full, clamped); pitches as 1-255.
static func write_map_fade(entity: int, fading_in: bool, seconds: float, from: float, to: float) -> PackedByteArray:
	return write_map_fx(ZzEvents.MapFx.FADE, entity, fading_in, seconds, -1.0 if from < 0.0 else clampf(from, 0.0, 1.0) * 200.0, -1.0 if to < 0.0 else clampf(to, 0.0, 1.0) * 200.0)


static func write_map_spin(entity: int, seconds: float, from: float, to: float) -> PackedByteArray:
	return write_map_fx(ZzEvents.MapFx.SPIN, entity, true, seconds, -1.0 if from < 0.0 else clampf(from, 1.0, 255.0), -1.0 if to < 0.0 else clampf(to, 1.0, 255.0))


static func write_map_beat(beat: int, downbeat: bool) -> PackedByteArray:
	return write_map_fx(ZzEvents.MapFx.BEAT, 0, downbeat, 0.0, float(clampi(beat, 0, 255)), -1.0)


## Whether a point is a finite place inside the world's wire range.
static func sane_point(p: Variant) -> bool:
	return p is Vector3 and is_finite((p as Vector3).x) and is_finite((p as Vector3).y) and is_finite((p as Vector3).z) \
		and absf((p as Vector3).x) <= ZzEvents.WORLD_EXTENT and absf((p as Vector3).y) <= ZzEvents.WORLD_EXTENT and absf((p as Vector3).z) <= ZzEvents.WORLD_EXTENT


## The one clamp both ends use: scale 0.05-1 (NaN is 1), seconds 0-15 (NaN is 0), the point or null when it is not finite and inside the world.
static func sane_end(time_scale: float, seconds: float, camera: Variant) -> Dictionary:
	return {"time_scale": 1.0 if is_nan(time_scale) else clampf(time_scale, ZzEvents.END_SCALE_MIN, 1.0),
		"seconds": 0.0 if is_nan(seconds) else clampf(seconds, 0.0, ZzEvents.END_SECONDS_MAX),
		"camera": camera if sane_point(camera) else null}


## A map's ending: who won, the slow motion and the camera point (none when absent or not sane).
static func write_map_end(won: bool, time_scale: float, seconds: float, camera: Variant) -> PackedByteArray:
	var e := sane_end(time_scale, seconds, camera)
	var w := ZzEvents._w()
	w.write_uint(ZzEvents.MapFx.END, 2)
	w.write_bool(won)
	w.write_uint(clampi(int(round(float(e["seconds"]) * 10.0)), 0, 150), 8)
	w.write_uint(clampi(int(round(float(e["time_scale"]) * 200.0)), 10, 200), 8)
	w.write_bool(e["camera"] != null)
	if e["camera"] != null:
		ZzEvents._pos(w, e["camera"])
	return w.to_bytes()


## Decoded and clamped again: a fade's volumes are 0-1, a spin's pitches 1-255, a beat's number 0-255, with -1 for none.
static func read_map_fx(r: GSNetReader) -> Dictionary:
	var fx := r.read_uint(2)
	if fx == ZzEvents.MapFx.END:
		var won := r.read_bool()
		var seconds := float(r.read_uint(8)) / 10.0
		var scale := float(r.read_uint(8)) / 200.0
		var camera: Variant = ZzEvents._read_pos(r) if r.read_bool() else null
		var e := sane_end(scale, seconds, camera)
		return {"fx": fx, "won": won, "time_scale": e["time_scale"], "seconds": e["seconds"], "camera": e["camera"], "ok": r.ok()}
	var entity := r.read_varint()
	var flag := r.read_bool()
	var seconds := float(r.read_varint()) / 10.0
	var from := float(r.read_uint(9)) - 1.0
	var to := float(r.read_uint(9)) - 1.0
	if fx == ZzEvents.MapFx.FADE:
		from = -1.0 if from < 0.0 else clampf(from / 200.0, 0.0, 1.0)
		to = -1.0 if to < 0.0 else clampf(to / 200.0, 0.0, 1.0)
	return {"fx": fx, "entity": entity, "flag": flag, "seconds": seconds, "from": from, "to": to,
		"ok": r.ok() and fx <= ZzEvents.MapFx.BEAT}
