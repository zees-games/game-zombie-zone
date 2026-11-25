extends GSGameCheckSuite

const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzBlood := preload("../game/zz_blood.gd")
const ZzBreakFx := preload("../game/zz_break_fx.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view.gd")
const ZzTouch := preload("../game/zz_touch.gd")

## Blood behind a hit body (zz_blood.gd over gs-fx's GSFxDecals) and which end of a hold's day a map's own light becomes
## (ZzMapDoc.take_derived_light). `godot --headless --path . res://examples/headless_look.tscn`

const CHECKS := 43



func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-zombie-zone: blood and the hold's day")
	await _blood()
	_splinters()
	_light()
	_fade()
	_touch_fit()
	_special_looks()
	_report(CHECKS)


func _blood() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 10, 0.5)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = Vector3(0, 2, -4)
	var blood := ZzBlood.new()
	add_child(blood)
	blood.mask = 0xFFFFFFFF
	blood.apply_settings(null)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var npc := GSEntity.make_id(GSEntity.KIND_NPC, 1)
	var from := Vector3(0, 1.7, 8)
	_check(blood.on_body_hit(npc, Vector3(0, 1.2, -1), from, 8.0) != null, "a hit NPC splatters the wall behind it")
	_check(blood.decals.blood_count() == 1, "one splatter is counted (%d)" % blood.decals.blood_count())
	_check(blood.on_body_hit(GSEntity.make_id(GSEntity.KIND_PLAYER, 2), Vector3(1, 1.2, -1), from, 8.0) != null, "a hit player splatters it too")
	_check(blood.on_body_hit(GSEntity.make_id(GSEntity.KIND_PROP, 3), Vector3(1, 1.2, -1), from, 8.0) == null, "a prop bleeds nothing")
	_check(blood.on_body_hit(npc, Vector3(0, 1.2, -1), from, 1.0) == null, "no surface in reach, no splatter")
	for i in 300:
		var _s := blood.on_body_hit(npc, Vector3(-5 + (i % 10), 1.0 + (i % 4) * 0.5, -1), from, 8.0)
	var cap: int = blood.decals.config.effective_blood_cap()
	_check(blood.decals.blood_count() <= cap, "the cap holds (%d of %d)" % [blood.decals.blood_count(), cap])
	blood.clear()
	_check(blood.decals.blood_count() == 0, "a map change clears the blood")

	var surf := Vector3(0, 1.5, -3.7)
	_check(blood.splat_at(surf, Vector3.BACK) == null, "a server splat with no camera is dropped, not drawn without the distance gate")
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 1.7, 8)
	var drawn := 0
	for i in 40:
		if blood.splat_at(surf + Vector3(i * 0.01, 0, 0), Vector3.BACK) != null:
			drawn += 1
	_check(drawn == ZzBlood.SPLATS_PER_SECOND, "server splats are capped per second (%d drawn of 40, cap %d)" % [drawn, ZzBlood.SPLATS_PER_SECOND])
	_check(blood.splat_at(Vector3(0, 1.5, -300), Vector3.BACK) == null, "a splat beyond 60 m of the camera is dropped")
	blood.clear()

	var off := GSFxDecalConfig.new()
	off.gore = false
	blood.decals.apply_config(off)
	_check(blood.on_body_hit(npc, Vector3(0, 1.2, -1), from, 8.0) == null or blood.decals.blood_count() == 0, "gore off draws none")
	var low := GSFxDecalConfig.new()
	low.quality = 0
	blood.decals.apply_config(low)
	var _q := blood.on_body_hit(npc, Vector3(0, 1.2, -1), from, 8.0)
	_check(blood.decals.blood_count() == 0, "effects quality 0 draws none")


func _splinters() -> void:
	var fx := ZzBreakFx.new()
	add_child(fx)
	fx.break_fx.config.headless = true
	fx.splinter(Vector3(0, 1, -3), 1.5)
	_check(fx.break_fx.spawned == 1, "a broken barricade or support throws one burst of splinters", str(fx.break_fx.spawned))
	fx.break_fx.config.enabled = false
	fx.splinter(Vector3(0, 1, -3))
	_check(fx.break_fx.spawned == 1, "fx_quality 0 draws nothing", fx.break_fx.last_refusal)
	fx.break_fx.config.enabled = true
	fx.splinter(Vector3(0, 1, -3), 99.0)
	_check(fx.break_fx.spawned == 2, "a huge size still draws one burst", fx.break_fx.last_refusal)
	fx.free()


func _light() -> void:
	var day := ZzMapDoc.DEFAULT_ENV.duplicate(true)
	day["sun_energy"] = 0.8
	var hold := {"mode": ZzMapDoc.SURVIVAL, "environment": ZzMapDoc.IMPORTER_ENV.duplicate(true)}
	ZzMapDoc.take_derived_light(hold, day)
	_check(hold["day_environment"] == day and ZzMapDoc.is_importer_env(hold["environment"]), "a hold's derived day is its day and the night stays")
	var night := ZzMapDoc.IMPORTER_ENV.duplicate(true)
	night["sun_energy"] = 0.2
	var dark_hold := {"mode": ZzMapDoc.SURVIVAL, "environment": ZzMapDoc.IMPORTER_ENV.duplicate(true)}
	ZzMapDoc.take_derived_light(dark_hold, night)
	_check(not dark_hold.has("day_environment") and dark_hold["environment"] == night, "a derived night replaces the night and leaves no day")
	var exodus := {"mode": ZzMapDoc.EXODUS, "environment": ZzMapDoc.IMPORTER_ENV.duplicate(true)}
	ZzMapDoc.take_derived_light(exodus, day)
	_check(exodus["environment"] == day and not exodus.has("day_environment"), "an exodus map takes the derived day as its light")


func _fade() -> void:
	var c := ZzConfig.new()
	_check(is_equal_approx(ZzNpcs.fade_alpha(c, &"spitter", 0), 1.0), "no Hard Box stack: a mutant is solid")
	_check(is_equal_approx(ZzNpcs.fade_alpha(c, &"spitter", 3), 1.0 - 3.0 * c.mutant_fade_per_stack), "three stacks: alpha is 1 - 3 * step")
	_check(is_equal_approx(ZzNpcs.fade_alpha(c, &"brute", 40), c.mutant_min_alpha), "any number of stacks stops at the minimum alpha")
	c.mutant_min_alpha = 0.0
	_check(ZzNpcs.fade_alpha(c, &"ram", 99) >= GSStackScale.ALPHA_FLOOR, "a minimum of 0 still leaves the mutant visible")
	c.mutant_min_alpha = 0.25
	_check(is_equal_approx(ZzNpcs.fade_alpha(c, &"common", 5), 1.0), "commons are untouched by default")
	c.common_fade = 1
	_check(ZzNpcs.fade_alpha(c, &"common", 5) < 1.0, "zz_common_fade 1 fades commons too")
	c.mutant_fade = 0
	_check(is_equal_approx(ZzNpcs.fade_alpha(c, &"spitter", 8), 1.0) and is_equal_approx(ZzNpcs.fade_alpha(c, &"common", 8), 1.0), "zz_mutant_fade 0 gives 1.0 for everyone")

	var a := ZzZombieView.new()
	var b := ZzZombieView.new()
	add_child(a)
	add_child(b)
	a.build(&"spitter", 0)
	b.build(&"spitter", 0)
	var meshes_a := a.find_children("*", "MeshInstance3D", true, false)
	var solid: Material = (meshes_a[0] as MeshInstance3D).material_override
	_check(meshes_a.size() >= 1 and solid == (b.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_override,
		"two spitters share one look before any fade (%d parts)" % meshes_a.size())
	a.set_fade(0.5)
	var every := true
	for node: Node in a.find_children("*", "MeshInstance3D", true, false):
		var m := node as MeshInstance3D
		var mat := m.material_override
		var half := false
		if mat is ShaderMaterial:
			half = is_equal_approx(float((mat as ShaderMaterial).get_shader_parameter(&"fade")), 0.5)
		elif mat is BaseMaterial3D:
			half = is_equal_approx((mat as BaseMaterial3D).albedo_color.a, 0.5)
		every = every and half
	_check(every, "every part of the body, its worn parts included, is drawn at 0.5")
	var other: Material = (b.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_override
	_check(other == solid and (solid as ShaderMaterial).get_shader_parameter(&"fade") == null, "the shared look was not written")
	b.set_fade(0.8)
	var first := (a.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_override as ShaderMaterial
	var second := (b.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_override as ShaderMaterial
	_check(is_equal_approx(float(first.get_shader_parameter(&"fade")), 0.5) and is_equal_approx(float(second.get_shader_parameter(&"fade")), 0.8),
		"two zombies of one kind keep independent alpha")
	a.set_fade(0.3)
	_check(is_equal_approx(float(first.get_shader_parameter(&"fade")), 0.3), "a stack change mid-life updates the same zombie")
	a.set_fade(1.0)
	_check((a.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_override == solid, "back to solid: the shared look returns")
	a.queue_free()
	b.queue_free()


## The phone's buttons through gs-game's GSGameScreenFit (what ZzClient._build_touch hands to fit_touch_buttons):
## every one at least 44 real px across on a landscape phone.
func _touch_fit() -> void:
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(667, 375)]:
		var fit := GSGameScreenFit.new()
		fit.size_override = phone
		fit.dpi_override = 160.0
		fit.attach(get_tree().root)
		var host := Control.new()
		add_child(host)
		var buttons := GSTouchButtons.new()
		buttons.set_buttons(ZzTouch.LAYOUT.duplicate())
		host.add_child(buttons)
		var k := fit.fit_buttons(buttons, ZzTouch.LAYOUT)
		var stretch := float(fit.plan.get("stretch", 0.0))
		var smallest := INF
		for b: Dictionary in ZzTouch.LAYOUT:
			smallest = minf(smallest, buttons.radius_of(b["id"]) * 2.0 * stretch)
		_check(buttons.button_scale == k and fit.describe()["buttons"] == 1, "the fit holds the touch buttons at %dx%d" % [phone.x, phone.y])
		_check(smallest >= 43.99, "every touch button is at least 44 real px across at %dx%d (smallest %.1f)" % [phone.x, phone.y, smallest])
		fit.detach()
		host.free()


## The six specials' bodies carry gear skinned to the same bones, so a bone scale reshapes the gear too: keep every scale
## in a band where a body stays a body (a bloater a stout man, not a toad; a screamer slim, not a cone).
func _special_looks() -> void:
	var worst := 1.0
	var widest := 1.0
	for kind: StringName in [&"brute", &"bloater", &"screamer", &"strangler", &"spitter", &"sleeper"]:
		var look := ZzZombieView.look_for(kind, 0)
		_check(look["body"] != &"" and float(look["girth"]) > 0.5 and float(look["girth"]) < 1.8, "%s has its own body and a sane girth (%.2f)" % [kind, float(look["girth"])])

		for bone: Variant in (look["bones"] as Dictionary).values():
			var s: Vector3 = bone if bone is Vector3 else Vector3.ONE * float(bone)
			worst = minf(worst, minf(s.x, minf(s.y, s.z)))
			widest = maxf(widest, maxf(s.x, maxf(s.y, s.z)))

	_check(worst >= 0.6, "no special squashes a bone below 0.6 (%.2f)" % worst)
	_check(widest <= 2.7, "no special stretches a bone past 2.7 (%.2f)" % widest)
