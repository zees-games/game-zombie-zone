extends RefCounted

## The game module's workbench: the editable sets (settings, personas, waves, boxes, ambience) and the wiring that
## applies a change at once.

static func start(module: Variant, world: ZzGame) -> void:
	var rt := world.ensure_runtime()
	var admin_permit := Callable()
	if module.server != null and module.server.admins != null:
		admin_permit = module.server.admins.uid_has_permission
	rt.permit = func(actor: Variant, flag: String) -> bool:
		if typeof(actor) == TYPE_STRING_NAME and actor == ZzGame.LOCAL_ACTOR:
			return true
		return admin_permit.is_valid() and actor is String and bool(admin_permit.call(actor, flag))
	rt.actor_name = func(actor: Variant) -> String: return str(actor)
	var workbench := GSGameWorkbench.new()
	module.workbench = workbench
	workbench.name = "Workbench"
	workbench.dedicated = DisplayServer.get_name() == "headless"
	workbench.listen_host_fn = func() -> bool: return DisplayServer.get_name() != "headless"
	workbench.permit_fn = func(actor: Variant, flag: String) -> bool:
		return admin_permit.is_valid() and actor is String and bool(admin_permit.call(actor, flag))
	if world.config_binder != null:
		for set: GSProfileSet in world.config_binder.profile_sets():
			workbench.add_set(set, "Game settings: %s" % set.rel_path.trim_prefix("config_"))
	if world.flashlight_binder != null:
		for set: GSProfileSet in world.flashlight_binder.profile_sets():
			workbench.add_set(set, "Flashlight")
	workbench.add_set(world.bot_persona_set(), "Bot personas (add, edit, delete)")
	workbench.add_set(GSWaveSet.make_set("game-zombie-zone"), "Wave sets (sizes, pools, bosses, difficulty)")
	workbench.add_set(world.box_profile_set(), "Boxes (odds, effects, colours, sounds)")
	var ambient_set := GSGameWorkbench.cvar_set(module.console, world.ambient_rules.cvar_types(), module.AMBIENT_KIND)
	if ambient_set != null:
		workbench.add_set(ambient_set, "Ambience (zz_ambient*)")
	module.add_child(workbench)
	var started := workbench.start(rt)
	if not started.ok:
		module.log_warn("the workbench", {"why": started.error.message})
		return
	# Off until the owner sets sv_workbench_remote 1; then flagged admins edit from a client.
	if module.net != null:
		var _served := workbench.serve_remote(module.net)
	if world.config_binder != null:
		world.config_binder.attach(rt)
	if world.flashlight_binder != null:
		world.flashlight_binder.attach(rt)
	rt.profile_changed.connect(func(kind: String, _id: String, _rev: int) -> void:
		if kind == GSBotPersona.KIND:
			world.reload_personas()
		elif kind == GSBoxProfiles.KIND:
			world.reload_boxes())
	if ambient_set != null:
		var _applied := GSGameWorkbench.bind_cvar_set(ambient_set, rt, module.console)
