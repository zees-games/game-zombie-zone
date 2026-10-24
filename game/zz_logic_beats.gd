extends DotMapEntity

## logic_beats: the map's wave cues. This game has no wave music, so what it keeps is the announcer: `DisableAnnoucner` (the
## key's own spelling) silences the "Wave N of M" line while the entity is enabled.


func announcer_off() -> bool:
	return enabled and flag("disableannoucner")
