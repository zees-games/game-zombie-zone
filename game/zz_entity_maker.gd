extends DotMapEntity

## env_entity_maker: ForceSpawn runs the named point_template; the game places what the copies are.


func _input(io: DotMapIO, name: String, _param: String, activator: Variant, _caller: Variant) -> bool:
	if name != "forcespawn" and name != "forcespawnatentityorigin":
		return false
	if not enabled:
		return true
	var made := 0
	for template: DotMapEntity in io.find(key("entitytemplate")):
		if template is DotMapTemplate and template.accept(io, "ForceSpawn", "", activator, self):
			made += 1
	io.event("maker_spawn", {"maker": index, "at": origin(io), "templates": made})
	fire(io, "OnEntitySpawned", activator)
	return true
