extends DotMapEntity

## logic_waves: OnWaveStart fires when the survival hold begins the wave named by `wave`, OnWaveEnd when that wave is cleared.
## The game says which wave (`wave_started`, `wave_ended`); the entity holds no clock of its own.


func wave_started(p_io: RefCounted, number: int) -> void:
	var io: DotMapIO = p_io
	if enabled and int(key_float("wave", 0.0)) == number:
		fire(io, "OnWaveStart", null)


func wave_ended(p_io: RefCounted, number: int) -> void:
	var io: DotMapIO = p_io
	if enabled and int(key_float("wave", 0.0)) == number:
		fire(io, "OnWaveEnd", null)
