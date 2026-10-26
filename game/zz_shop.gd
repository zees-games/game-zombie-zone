extends RefCounted

const ZzWeapons := preload("zz_weapons.gd")

## The trader's menu: what is for sale, at what price, and the purchase. Server side.
##
## The catalogue is built from the weapons the game has (every pack), the supplies and the box types, then bent by the `game: shop:` block of `dot_weapon/spawner.yml` (docs/operators.md): `menu`, `radius`, `price_multiplier`, `categories`, `disabled`, `items`, `supplies`, `boxes`, `ammo`. A client is sent the list as JSON and asks to buy by id; the price and the reach are decided here, never on the client.

const CHANNEL := "zz.shop"
const DEFAULT_CATEGORIES: Array = ["weapons", "grenades", "ammo", "supplies", "entities"]
const MAX_ITEMS := 400

var game = null


func _init(p_game: Object) -> void:
	game = p_game


func _block() -> Dictionary:
	return game.spawners.shop_block() if game.spawners != null else {}


func menu_enabled() -> bool:
	return bool(_block().get("menu", true)) and game.spawners != null and game.spawners.trader_enabled()


func radius() -> float:
	return clampf(float(_block().get("radius", 3.5)), 1.0, 30.0)


func multiplier() -> float:
	return clampf(float(_block().get("price_multiplier", 1.0)), 0.0, 100.0)


func _categories() -> Array:
	var raw: Variant = _block().get("categories", DEFAULT_CATEGORIES)
	return raw as Array if raw is Array else DEFAULT_CATEGORIES


## Every item for sale now: {id, name, cat, price, desc, w?}.
func items() -> Array:
	var out: Array = []
	var block := _block()
	var overrides: Dictionary = block.get("items", {}) as Dictionary if block.get("items") is Dictionary else {}
	var disabled: Array = block.get("disabled", []) as Array if block.get("disabled") is Array else []
	var cats := _categories()
	var prices: Dictionary = block.get("prices", {}) as Dictionary if block.get("prices") is Dictionary else {}
	var supplies: Dictionary = block.get("supplies", {}) as Dictionary if block.get("supplies") is Dictionary else {}
	var ammo: Dictionary = block.get("ammo", {}) as Dictionary if block.get("ammo") is Dictionary else {}
	var boxes: Dictionary = block.get("boxes", {}) as Dictionary if block.get("boxes") is Dictionary else {}
	var mag_share := float(ammo.get("magazine_share", 0.08))
	var refill_share := float(ammo.get("refill_share", 0.2))

	for def in ZzWeapons.all_defs():
		if def.id == &"fists":
			continue
		var tier := ZzWeapons.tier_of(def.id)
		var base: Variant = prices.get(String(tier), null)
		if base == null and not overrides.has(String(def.id)):
			continue
		var cost := _price(base if base != null else 0)
		var cat := "grenades" if tier == &"thrown" else "weapons"
		out.append({"id": String(def.id), "name": ZzWeapons.title_of(def.id), "cat": cat, "price": cost, "w": String(def.id), "tier": String(tier),
			"desc": _describe(def, tier)})

		if cat == "weapons" and def.ammo_type != &"" and not def.infinite_reserve and tier != &"melee":
			out.append({"id": "mag:%s" % def.id, "name": "%s: magazine" % ZzWeapons.title_of(def.id), "cat": "ammo", "w": String(def.id),
				"price": maxi(int(round(cost * mag_share)), 5), "desc": "Adds %d rounds." % maxi(def.magazine, 1)})
			out.append({"id": "refill:%s" % def.id, "name": "%s: refill" % ZzWeapons.title_of(def.id), "cat": "ammo", "w": String(def.id),
				"price": maxi(int(round(cost * refill_share)), 10), "desc": "Fills the reserve to its cap of %d." % def.reserve_cap()})

	out.append({"id": "refill_all", "name": "Refill every gun", "cat": "ammo", "price": _price(ammo.get("refill_all", 150)), "desc": "Tops up the ammunition of every weapon you carry."})
	out.append({"id": "medkit", "name": "Medkit", "cat": "supplies", "price": _price(supplies.get("medkit", 150)), "desc": "A medkit for you or a friend (one at a time)."})
	out.append({"id": "pills", "name": "Pills", "cat": "supplies", "price": _price(supplies.get("pills", 50)), "desc": "Borrowed health, quickly."})
	out.append({"id": "heal", "name": "Patch up", "cat": "supplies", "price": _price(supplies.get("heal", 100)), "desc": "Back to full health."})
	out.append({"id": "armour", "name": "Armour", "cat": "supplies", "price": _price(supplies.get("armour", 200)), "desc": "+%d armour." % int(supplies.get("armour_amount", 50))})

	if game.boxes != null:
		for type_id: Variant in boxes:
			if game.boxes.types.has(StringName(str(type_id))):
				var title := str((game.boxes.types[StringName(str(type_id))] as Variant).get("title", type_id)) if game.boxes.types[StringName(str(type_id))] is Dictionary else str(type_id).capitalize()
				out.append({"id": "box:%s" % type_id, "name": "%s box" % title, "cat": "entities", "price": _price(boxes[type_id]), "desc": "A box you carry and deploy where you stand."})

	var kept: Array = []
	for it: Dictionary in out:
		var id := str(it["id"])
		var over: Variant = overrides.get(id)
		if over is Dictionary:
			if (over as Dictionary).has("price"):
				it["price"] = _price((over as Dictionary)["price"])
			if not bool((over as Dictionary).get("enabled", true)):
				continue
		elif over != null:
			it["price"] = _price(over)
		if disabled.has(id) or not cats.has(str(it["cat"])):
			continue
		it["price"] = int(round(float(it["price"]) * multiplier()))
		kept.append(it)
		if kept.size() >= MAX_ITEMS:
			break
	return kept


func _price(v: Variant) -> int:
	return game.spawners._clean_price(v)


func _describe(def: DotWeaponDef, tier: StringName) -> String:
	var parts: PackedStringArray = []
	parts.append(String(tier).capitalize())
	if def.params.has("damage"):
		parts.append("%s damage" % str(def.params["damage"]))
	if def.magazine > 0:
		parts.append("magazine %d" % def.magazine)
	if def.reserve_cap() > 0:
		parts.append("reserve %d" % def.reserve_cap())
	return " · ".join(parts) if def.description == "" else "%s\n%s" % [def.description, " · ".join(parts)]


## The JSON a client is told: whether the trader is open, where, how far it reaches, and the list.
func state_json() -> String:
	var at: Array = []
	if game.spawners != null:
		for pos: Vector3 in game.spawners.trader_sites():
			at.append([snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)])
	return JSON.stringify({"menu": menu_enabled(), "open": game.spawners != null and game.spawners.trader_open(),
		"radius": radius(), "at": at, "closed_message": game.spawners.closed_message() if game.spawners != null else "", "items": items() if menu_enabled() else []})


## Whether [param player] stands within reach of an open trader.
func in_reach(player) -> bool:
	if game.spawners == null or not game.spawners.trader_open():
		return false
	var feet: Vector3 = player.feet()
	for pos: Vector3 in game.spawners.trader_positions():
		if feet.distance_to(pos) <= radius():
			return true
	return false


## Sells [param item_id] to [param player]. False, with the reason sent to them, when it cannot.
func buy(player, item_id: String) -> bool:
	if not menu_enabled() or player == null or not player.is_up():
		return false
	if not in_reach(player):
		game.refused.emit(player.player_id, "The trader is not here.")
		return false
	var found: Dictionary = {}
	for it: Dictionary in items():
		if str(it["id"]) == item_id:
			found = it
			break
	if found.is_empty():
		game.refused.emit(player.player_id, "That is not for sale.")
		return false
	var price := int(found["price"])
	if player.points < price:
		game.refused.emit(player.player_id, "That costs %d points." % price)
		return false
	var why := _give(player, item_id, found)
	if why != "":
		game.refused.emit(player.player_id, why)
		return false
	player.points = maxi(int(player.points) - price, 0)
	game.told.emit(player.player_id, "Bought %s." % str(found["name"]))
	return true


## Hands the item over; "" when done, else why not.
func _give(player, item_id: String, found: Dictionary) -> String:
	var block := _block()
	var supplies: Dictionary = block.get("supplies", {}) as Dictionary if block.get("supplies") is Dictionary else {}
	var arsenal: DotWeaponArsenal = player.weapons.arsenal if player.weapons != null else null

	if item_id == "medkit":
		if player.medkits >= 1:
			return "You already have a medkit."
		player.medkits = 1
		return ""
	if item_id == "pills":
		if player.pills >= 1:
			return "You already have pills."
		player.pills = 1
		return ""
	if item_id == "heal":
		if player.health == null or player.health.health >= player.health.max_health:
			return "You are at full health."
		player.health.health = player.health.max_health
		return ""
	if item_id == "armour":
		if player.health == null or player.health.armour >= player.health.max_armour:
			return "Your armour is full."
		player.health.armour = minf(player.health.armour + float(supplies.get("armour_amount", 50)), player.health.max_armour)
		player.health.armour_changed.emit(player.health.armour)
		return ""
	if item_id == "refill_all":
		var added: int = 0 if arsenal == null else int(game.loot.give_ammo(player, 1.0))
		return "" if added > 0 else "Your ammunition is full."
	if item_id.begins_with("box:"):
		if game.boxes == null or not game.boxes.carry(player, StringName(item_id.substr(4))):
			return "Your hands are full."
		return ""

	var weapon := StringName(str(found.get("w", "")))
	var def := ZzWeapons.def_of(weapon)
	if def == null:
		return "That is not for sale."

	if item_id.begins_with("mag:") or item_id.begins_with("refill:"):
		if arsenal == null or not arsenal.carries(weapon):
			return "You do not carry that gun."
		var room: int = def.reserve_cap() - arsenal.ammo().count(def.ammo_type)
		var want: int = room if item_id.begins_with("refill:") else mini(maxi(def.magazine, 1), room)
		return "" if want > 0 and arsenal.add_ammo(def.ammo_type, want) > 0 else "That gun's ammunition is full."

	if arsenal != null and arsenal.carries(weapon):
		if str(found.get("cat", "")) == "grenades" and def.ammo_type != &"":
			return "" if arsenal.add_ammo(def.ammo_type, 1) > 0 else "You cannot carry more."
		return "You already carry it."
	if not game.arm(player, weapon):
		return "You cannot carry that."
	if str(found.get("cat", "")) == "weapons":
		game._draw(player, weapon)
	return ""
