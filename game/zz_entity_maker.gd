extends GSMapEntity

## env_entity_maker: ForceSpawn runs the named point_template; the game places what the copies are.


func _input(p_io: RefCounted, name: String, _param: String, activator: Variant, _caller: Variant) -> bool:
	var io: GSMapIO = p_io
	if name != "forcespawn" and name != "forcespawnatentityorigin":
		return false
	if not enabled:
		return true
	var made := 0
	for template: GSMapEntity in io.find(key("entitytemplate")):
		if template is GSMapTemplate and template.accept(io, "ForceSpawn", "", activator, self):
			made += 1
	io.event("maker_spawn", {"maker": index, "at": origin(io), "templates": made})
	fire(io, "OnEntitySpawned", activator)
	return true
