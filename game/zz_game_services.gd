extends "zz_game_state.gd"
## The authoritative game's services: what a round's server owns beside the world itself.


## Builds the services only a server runs: pins, hazards, turrets, loot, crates, spawners, shop, drops, boxes and bots.
func _build_services(box_profiles: DotProfileSet) -> void:
	pins = ZzPins.new(self)
	hazards = ZzHazards.new(self)
	turrets = ZzTurrets.new(self)
	hazards.exploded.connect(func(at: Vector3, radius: float, kind: StringName) -> void:
		exploded.emit(at, radius, kind))
	loot = ZzLoot.new(self)
	crates = ZzCrates.new(self)
	var _cm := crates.moved_many.connect(func(batch: Array) -> void: loot.moved_many.emit(batch))
	spawners = ZzSpawners.new(self)
	spawners.load_config()
	shop = ZzShop.new(self)
	loot.removed.connect(spawners.on_loot_removed)
	drops = ZzDrops.new(self)
	map_objects = ZzMapObjects.new(self)
	drops.load_config()
	boxes = ZzBoxes.new(self)
	var _loaded_boxes := boxes.load_file(config.box_file)
	var _box_profiles := boxes.overlay_profiles(box_profiles)
	bots = ZzBots.new(self)


## Builds the map catalogue: the content index's subscribed maps, the map directory, then [param solo_dirs].
func _load_catalogue(solo_dirs: PackedStringArray) -> void:
	catalogue = ZzCatalogue.new()
	# Subscribed (solo) pack maps are map documents and join the catalogue; online none.
	catalogue.follow_content(content_index if content_index != null else DotContentIndex.shared(),
		ZzWorkshop.accepted_map_kinds())
	var _loaded := catalogue.load_from(config.map_directory)
	# Solo in the client shell: the map packs it mounted for this game, which a server
	# would have named. See [method solo_map_dirs].
	for root in solo_dirs:
		var _added := catalogue.add_directory(root)
