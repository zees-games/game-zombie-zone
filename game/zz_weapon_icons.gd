extends RefCounted

## Zombie Zone's weapon pictures: Jestan's CC0 sprites (dot-ui's DotWeaponIcons) mapped weapon by weapon.

## `pixel` is the sprites as drawn, `flat` one colour, `silhouette` the trader's rendered model.
const STYLES := [&"pixel", &"flat", &"silhouette"]

## Weapon id to the sprite's type tag. A weapon not here (a bow, a shield) keeps the rendered model or its name.
const TAGS := {
	&"zz_aa12": &"drum_shotgun", &"zz_ak": &"assault_rifle", &"zz_axe": &"axe", &"zz_bat": &"hammer",
	&"zz_bren": &"lmg", &"zz_crowbar": &"hammer", &"zz_deagle": &"revolver", &"zz_dmr": &"marksman",
	&"zz_frag": &"grenade", &"zz_glock": &"pistol", &"zz_hunting": &"rifle", &"zz_knife": &"knife",
	&"zz_lmg": &"lmg", &"zz_m4": &"carbine", &"zz_m79": &"launcher", &"zz_machete": &"sword",
	&"zz_mp5": &"smg", &"zz_p90": &"smg", &"zz_pistol": &"pistol", &"zz_revolver": &"revolver",
	&"zz_rpg": &"launcher", &"zz_scar": &"battle_rifle", &"zz_shotgun": &"shotgun", &"zz_sledge": &"hammer",
	&"zz_smg": &"smg", &"zz_sniper": &"sniper", &"zz_spas": &"shotgun", &"zz_vss": &"energy_rifle",
	&"battle_rifle": &"battle_rifle", &"beamer": &"energy_rifle", &"bullpup": &"bullpup",
	&"burst_rifle": &"assault_rifle", &"carbine": &"carbine", &"charge_rifle": &"charge_rifle",
	&"derringer": &"derringer", &"drum_shotgun": &"drum_shotgun", &"frag": &"grenade",
	&"hatchet": &"hatchet", &"knife": &"knife", &"launcher": &"launcher",
	&"machine_pistol": &"machine_pistol", &"mallet": &"hammer", &"marksman": &"marksman",
	&"minigun": &"lmg", &"pickaxe": &"pickaxe", &"pistol": &"pistol", &"revolver": &"revolver",
	&"rifle": &"rifle", &"shiv": &"dagger", &"shotgun": &"shotgun", &"smg": &"smg",
	&"sniper": &"sniper", &"spade": &"axe", &"sticky": &"sticky",
	&"battle_axe": &"axe", &"war_axe": &"axe", &"double_axe": &"axe", &"dagger": &"dagger",
	&"longsword": &"sword", &"mace": &"hammer",
}

static var style: StringName = &"pixel"
static var _set: DotIconSet = null


## The shared set: stock sheet, this game's aliases, and the player's overrides from `user://weapon_icons.json`.
static func icon_set() -> DotIconSet:
	if _set == null:
		_set = DotWeaponIcons.stock()
		for id in TAGS:
			_set.alias(id, TAGS[id])
		var path := "user://weapon_icons.json"
		if FileAccess.file_exists(path):
			var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if doc is Dictionary:
				_set.load_overrides(doc)
	_set.flat = style == &"flat"
	_set.flat_colour = Color.WHITE
	return _set


## The sprite for [param id], or null (use the rendered model or the name). Always null under `silhouette`.
static func texture(id: StringName) -> Texture2D:
	if style == &"silhouette" or id == &"":
		return null
	return icon_set().texture_for(id)


static func set_style(value: StringName) -> bool:
	if not STYLES.has(value):
		return false
	style = value
	return true


## Nearest filtering for pixel art on [param canvas]; the rendered models stay smooth.
static func filter(canvas: CanvasItem, sprite: bool) -> void:
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if sprite else CanvasItem.TEXTURE_FILTER_PARENT_NODE


## The cvar at the console's local source.
static func bind_console(local: DotConsoleLocal) -> void:
	local.add_var(&"cl_weapon_icons", "Weapon pictures: pixel (Jestan's sprites), flat (one colour) or silhouette (the rendered model).",
		func() -> Variant: return String(style),
		func(v: Variant) -> Variant:
			if not set_style(StringName(str(v).strip_edges())):
				return DotResult.fail(DotError.CODE_INVALID, "cl_weapon_icons is pixel, flat or silhouette")
			return DotResult.success(String(style))
	)
