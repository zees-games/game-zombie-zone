extends RefCounted

## A stand-in for an installed content pack (zz-modern-weapons and its kin), for headless_packs.
## It follows the contract in game/zz_packs.gd and names nothing the real packs own.


static func spawn_entries() -> Array[Dictionary]:
	return [
		{"category": "Weapons", "id": "fx_rifle", "name": "Fixture Rifle", "icon": "", "kind": "weapon",
			"spawn": {"weapon": "fx_rifle"}, "cfg_hint": "cfg/addons/zz_fixture_pack/*.yml"},
		{"category": "Weapons", "id": "fx_unbacked", "name": "No definition", "icon": "", "kind": "weapon",
			"spawn": {"weapon": "fx_unbacked"}, "cfg_hint": ""},
		{"category": "Monsters", "id": "fx_ghoul", "name": "Fixture Ghoul", "icon": "", "kind": "npc",
			"spawn": {"health": 150.0, "speed": 5.0, "damage": 7.0}, "cfg_hint": ""},
		{"category": "Monsters", "id": "fx_titan", "name": "Fixture Titan", "icon": "", "kind": "npc",
			"spawn": {"health": 3000.0, "speed": 3.0, "damage": 30.0, "boss": true}, "cfg_hint": ""},
		{"category": "Monsters", "id": "brute", "name": "Impostor", "icon": "", "kind": "npc",
			"spawn": {}, "cfg_hint": ""},
	]


static func weapon_defs(types: Dictionary = {}) -> Array[DotWeaponDef]:
	var def := ZeeWeaponPack.rifle(types)
	def.id = &"fx_rifle"
	def.display_name = "Fixture Rifle"
	var out: Array[DotWeaponDef] = [def]
	return out
