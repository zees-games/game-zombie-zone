extends RefCounted

const ZzMapDoc := preload("zz_map_doc.gd")

## The light a map's `environment` describes, as gs-lighting documents and profiles (ZzMap applies it).

## The gs-lighting document a map's `environment` describes.
##
## [b]The sun is the map's, at the map's strength[/b]: 380 (game-fatal-contact's daylight) times the
## square of `sun_energy`, which for a night map's 0.12 is a faint moon (drawn below the rig's
## floor, see [method ZzMap._build_environment]) and leaves the lamps to light the street. [b]The fill is the map's
## ambient hue taken halfway to neutral and brought up to a pale value[/b]: a night map's
## ambient is a deep blue that, at the strength the dark needs to stay readable, tinted
## everything navy and lost every zombie against every wall; halfway keeps the moonlit cool
## (and the pier's dusk rose) without the cast. [b]The fog is the map's own darkness from
## 14 m[/b]: its horizon colour, reaching full at about 2 / `fog` metres further on and never
## quite opaque, so what comes out of the dark comes out of it at a distance a survivor can
## still shoot, and the map's `fog` (the chapel's 0.05 is twice the street's) still says how
## thick. Source units (metres / 0.01905), as the rig reads them.
static func light_document(env_doc: Dictionary) -> Dictionary:
	var sun := ZzMapDoc.colour(env_doc["sun_colour"])
	var horizon := ZzMapDoc.colour(env_doc["sky_horizon"])
	var ambient := ZzMapDoc.colour(env_doc["ambient"])
	var peak := maxf(maxf(ambient.r, ambient.g), maxf(ambient.b, 0.01))
	var fill := Color(ambient.r / peak, ambient.g / peak, ambient.b / peak).lerp(Color(1.0, 1.0, 1.0), 0.5) * 0.9
	var energy := float(env_doc["sun_energy"])
	var fog := maxf(float(env_doc["fog"]), 0.01)
	var start := 14.0
	var end := start + 2.0 / fog
	var thickest := clampf(fog * 20.0, 0.35, 0.85)
	if env_doc.has("fog_start"):
		# Clear air from a converted day map (ZzMapDoc.environment_from_world): a thin haze far off.
		start = float(env_doc["fog_start"])
		end = maxf(float(env_doc.get("fog_end", start * 10.0)), start + 1.0)
		thickest = 0.25
	return {
		"sun": {
			"colour": [sun.r, sun.g, sun.b],
			"brightness": 380.0 * energy * energy,
			"spread_degrees": 1.0,
			"ambient_colour": [fill.r, fill.g, fill.b],
		},
		"fog": {
			"enabled": true,
			"colour": [horizon.r, horizon.g, horizon.b],
			"start": start / 0.01905,
			"end": end / 0.01905,
			"max_density": thickest,
		},
	}

## What this machine draws of a map's light: gs-lighting's `painted()` (API level 3), the
## family's profile for hand-built worlds, with the map's ambient and fill.
##
## [b]Shadows stay on in the browser[/b], unlike gs-lighting's `web()`: a moonlit street
## without them is every face lit alike, and the boxes are batched into a few dozen meshes.
## `painted()` matches its light to the renderer (the Compatibility renderer this game and the
## client shell use has no headroom above white), lowers the exposure, grades, and trades
## ambient for a shadowless fill from the side the sun is not on, turned with the map's sun
## ([method ZzMap._aim_fill]) and blended between night and day with it ([method ZzMap.set_daylight]).
##
## [b]The ambient is the map's `ambient_energy` times [constant AMBIENT] of `painted()`'s, the
## fill times [constant FILL][/b], chosen from rendered frames under Compatibility (the
## family's 4 and 2.8 scaled by this game's old 1.2 against their 1.4): a night street stays
## dusky with the lamps pooling and a zombie a dark figure against a lighter wall, and the
## school by day loses the glare that washed its field white.
const AMBIENT := 3.4

const FILL := 2.4

static func light_profile(ambient_energy: float = 0.5) -> GSLightProfile:
	var p := GSLightProfile.painted()
	p.sun_shadows = true
	p.ambient_energy *= ambient_energy * AMBIENT
	p.fill_energy *= ambient_energy * FILL
	# Less contrast than painted()'s 1.12: the grade pivots at mid grey, and dark props and
	# zombies in shade went to black at 1.12.
	p.contrast = 1.04
	# Glow only from what is brighter than white (the lamps, the fires), not from every
	# pale wall.
	p.glow_threshold = 1.0
	return p
