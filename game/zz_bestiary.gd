extends RefCounted

## What the installed packs list as spawnable infected, for any screen that shows them: the special infected a pack carries
## (`core` rows) and its other monsters, each with the `icon` the pack's row names. Nothing here names a kind; a pack without
## icons, or an icon that is missing or will not load, gives a null texture and the screen draws a tile of its own.

const ZzPackList := preload("zz_packs.gd")

static var _cache: Dictionary = {}


## Each `{id, name, icon (path), pack, role}` in the pack's order: cores first, then monsters.
static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	for core: Dictionary in ZzPackList.cores:
		out.append({"id": core["id"], "name": str(core.get("name", core["id"])), "icon": str(core.get("icon", "")),
			"pack": core["pack"], "role": str(core.get("role", "special"))})

	for m in ZzPackList.monsters:
		out.append({"id": m.id, "name": m.title, "icon": m.icon, "pack": m.pack, "role": "boss" if m.boss else "monster"})

	return out


## The picture at [param path], or null when the row has none, the file is not there or it is not an image.
## A texture the editor imported loads as a resource; one in a freshly delivered pack that was never imported is read as an image.
static func texture(path: String) -> Texture2D:
	if path == "":
		return null

	if _cache.has(path):
		return _cache[path]

	var found: Texture2D = null

	if ResourceLoader.exists(path):
		found = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		found = ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null

	_cache[path] = found
	return found


static func clear() -> void:
	_cache.clear()
