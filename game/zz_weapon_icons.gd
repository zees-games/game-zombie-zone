extends RefCounted

## Zombie Zone's weapon pictures: weapon id to sprite tag; the rest is dot-ui's [DotWeaponIconStyle].

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

## The one instance the HUD, the trader and the console share.
static var shared: DotWeaponIconStyle = _make()


static func _make() -> DotWeaponIconStyle:
	var s := DotWeaponIconStyle.new()
	s.tags = TAGS
	return s
