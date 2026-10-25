extends RefCounted
## Which of a map's lamps are lit at once. The document keeps every lamp (the bake lights with all
## of them); a frame lights only the `limit` nearest the camera, each eased in and out so none pops.

const INTERVAL := 0.2
const FADE_PER_SECOND := 3.0
## Metres a lit lamp is favoured by, so two lamps at the same distance do not swap every pass.
const KEEP_BONUS := 4.0
const META := &"zz_base_energy"

var limit := 128
var _clock := 0.0
var _snap := true
var _lit := PackedByteArray()
var _level := PackedFloat32Array()


## Starts the lamps in [param lamps] (an order the document gave): the brightest [member limit] lit, the rest dark.
func setup(lamps: Array[Light3D]) -> void:
	_lit.resize(lamps.size())
	_level.resize(lamps.size())
	_clock = 0.0
	_snap = true

	var order := range(lamps.size())
	order.sort_custom(func(a: int, b: int) -> bool: return _strength(lamps[a]) > _strength(lamps[b]))

	for rank in order.size():
		var i: int = order[rank]
		lamps[i].set_meta(META, lamps[i].light_energy)
		_lit[i] = 1 if rank < limit else 0
		_apply(lamps[i], 1.0 if _lit[i] == 1 else 0.0)
		_level[i] = float(_lit[i])


## Lights every lamp at full strength (a bake scene wants them all).
static func restore(lamps: Array[Light3D]) -> void:
	for lamp in lamps:
		lamp.visible = true
		lamp.light_energy = float(lamp.get_meta(META, lamp.light_energy))


## Moves toward the [member limit] lamps nearest [param focus]; call it every frame.
func update(lamps: Array[Light3D], focus: Vector3, delta: float) -> void:
	_clock -= delta

	if _clock <= 0.0:
		_clock = INTERVAL
		_choose(lamps, focus)

	var step := 1.0 if _snap else FADE_PER_SECOND * delta
	_snap = false

	for i in lamps.size():
		var want := float(_lit[i])

		if _level[i] != want:
			_level[i] = move_toward(_level[i], want, step)
			_apply(lamps[i], _level[i])


func lit_count() -> int:
	var n := 0

	for flag in _lit:
		n += flag

	return n


func _choose(lamps: Array[Light3D], focus: Vector3) -> void:
	if lamps.size() <= limit:
		_lit.fill(1)
		return

	var scored: Array = []

	for i in lamps.size():
		var lamp := lamps[i]
		var reach := focus.distance_to(lamp.position) - _range(lamp) * 0.5 - (KEEP_BONUS if _lit[i] == 1 and not _snap else 0.0)
		scored.append([reach, i])

	scored.sort()
	_lit.fill(0)

	for rank in limit:
		_lit[(scored[rank] as Array)[1]] = 1


static func _apply(lamp: Light3D, level: float) -> void:
	lamp.visible = level > 0.0
	lamp.light_energy = float(lamp.get_meta(META, 1.0)) * level


static func _range(lamp: Light3D) -> float:
	return (lamp as OmniLight3D).omni_range if lamp is OmniLight3D else (lamp as SpotLight3D).spot_range


static func _strength(lamp: Light3D) -> float:
	return float(lamp.get_meta(META, lamp.light_energy)) * _range(lamp)
