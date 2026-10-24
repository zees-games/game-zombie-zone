extends DotMapEntity

## logic_winlose: the map's own ending. The Win and Lose inputs ask the game to decide the round (survivors win or the infected do);
## OnWin and OnLose fire when the round is decided, by this entity or by anything else. Music, slow motion and the end camera
## the keys name are not played.


func _input(io: DotMapIO, name: String, _param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"win", "humanswin":
			io.event("round_decide", {"entity": index, "won": true, "why": "the map ended it"})
		"lose", "zombieswin", "humanslose":
			io.event("round_decide", {"entity": index, "won": false, "why": "the map ended it"})
		_:
			return false
	return true


func decided(io: DotMapIO, won: bool) -> void:
	fire(io, "OnWin" if won else "OnLose", null)
