## The night sky's cover: stars and a moon painted on an image. Split from ZzMap.
extends RefCounted

## How many stars, and the cover's size (equirectangular: the top half is the sky).
const STARS := 1400

const STAR_MAP := Vector2i(2048, 1024)

static var _star_maps: Dictionary = {}

## The stars (seeded, so every machine draws the same sky; brighter ones rarer, a few two
## pixels wide) and a moon towards [param moon_from] (none when zero), built once per moon
## direction per process.
static func star_map(moon_from: Vector3 = Vector3.ZERO) -> ImageTexture:
	var key := "%.2f,%.2f,%.2f" % [moon_from.x, moon_from.y, moon_from.z]
	if _star_maps.has(key):
		return _star_maps[key]

	var image := Image.create(STAR_MAP.x, STAR_MAP.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011

	for i in STARS:
		var x := rng.randi_range(0, STAR_MAP.x - 2)
		# The top 44 % of the map, which is above the horizon, thinning towards it.
		var y := int(pow(rng.randf(), 1.4) * float(STAR_MAP.y) * 0.44)
		var bright := pow(rng.randf(), 3.0) * 0.85 + 0.15
		var tint := Color(0.85, 0.9, 1.0).lerp(Color(1.0, 0.92, 0.8), rng.randf())
		var star := Color(tint.r, tint.g, tint.b, bright)
		image.set_pixel(x, y, star)
		if bright > 0.7:
			image.set_pixel(x + 1, y, Color(star, bright * 0.6))
			image.set_pixel(x, mini(y + 1, STAR_MAP.y - 1), Color(star, bright * 0.6))

	if moon_from.y > 0.05:
		_paint_moon(image, moon_from.normalized())

	var texture := ImageTexture.create_from_image(image)
	_star_maps[key] = texture
	return texture

## Where a direction lands on the equirectangular cover, in pixels. Measured from frames (a
## disc painted by the textbook `atan2(x, -z)` came out on the opposite side of the sky).
static func sky_pixel(direction: Vector3) -> Vector2:
	var u := atan2(-direction.x, direction.z) / TAU + 0.5
	var v := acos(clampf(direction.y, -1.0, 1.0)) / PI
	return Vector2(u * float(STAR_MAP.x), v * float(STAR_MAP.y))

## A pale disc a degree and a half across, a little shading on one side, in a wide faint halo.
static func _paint_moon(image: Image, direction: Vector3) -> void:
	var centre := sky_pixel(direction)
	var per_degree := float(STAR_MAP.x) / 360.0
	# A row of the map is a circle of latitude: shorter towards the top, so the disc is
	# drawn wider in pixels by 1 / cos(latitude) to stay round.
	var widen := 1.0 / maxf(cos(asin(clampf(direction.y, -1.0, 1.0))), 0.2)
	var disc := 1.6 * per_degree
	var halo := 9.0 * per_degree

	for dy in range(-int(halo), int(halo) + 1):
		for dx in range(-int(halo * widen), int(halo * widen) + 1):
			var px := int(centre.x) + dx
			var py := int(centre.y) + dy
			if py < 0 or py >= STAR_MAP.y:
				continue
			px = posmod(px, STAR_MAP.x)
			var r := Vector2(float(dx) / widen, float(dy)).length()
			var colour := Color(0.0, 0.0, 0.0, 0.0)
			if r <= disc:
				var shade := 1.0 - 0.18 * clampf((float(dx) / widen + float(dy) * 0.4) / disc, 0.0, 1.0)
				colour = Color(0.93 * shade, 0.95 * shade, 1.0 * shade, 1.0)
			elif r <= halo:
				var t := 1.0 - (r - disc) / (halo - disc)
				colour = Color(0.7, 0.78, 1.0, 0.22 * t * t)
			else:
				continue
			image.set_pixel(px, py, colour)
