extends Node3D

const ZzAudio := preload("zz_audio.gd")
const ZzBoxes := preload("zz_boxes.gd")
const ZzPaths := preload("zz_paths.gd")
const ZzDefibModel := preload("zz_defib_model.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzNpcs := preload("zz_npcs.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view.gd")
const ZzMutantView := preload("../npcs/zz_mutant_view.gd")
const ZzOilMonsterView := preload("../npcs/zz_oil_monster_view.gd")
const ZzZombieLimbs := preload("../npcs/zz_zombie_limbs.gd")
const ZzZombieLod := preload("../npcs/zz_zombie_lod.gd")

## Everything a client draws in the world that is not a survivor or a wall: the zombies and their
## bodies, what lies on the ground, pools of acid and fire, things thrown, explosions, and a
## strangler's tongue.
##
## [b]Told, never asking.[/b] Offline the world's own signals call these methods; connected, the
## bridge's do, with the same arguments, so the two can only differ in where a fact came from —
## the shape `ZzClient._hear_the_world` already has for the rest.
##
## [b]Sound is placed here, because this is what knows where things are.[/b] A common moans now
## and then while it idles, screams on the frame it turns to RAGE, and the special's own voice
## plays when it appears and when it uses what it has. The sleeper's crying is a loop that
## follows her, so it is louder the closer you are, which is the only warning she gives.

const CHANNEL := "zz.world_view"

## Seconds a killed zombie's body stays before it sinks away, when nothing gave the rules.
const CORPSE_SECONDS := 6.0

## Seconds a blast's flash lasts.
const BLAST_SECONDS := 0.6

## Gravity a thrown thing falls by on a client: the server's (`ZzHazards.GRAVITY`).
const GRAVITY := 18.0

var audio: ZzAudio = null
## The config the fade cvars live in, and the Hard Box stacks last heard of; a change of either redraws.
var fade_config: Object = null
var hard_stacks := 0
var _fade_seen := ""

## key -> {body, view, last_anim, next_moan, voice_handle}
var _zombies: Dictionary = {}

## [view, body, seconds left]
var _corpses: Array = []

## id -> node
var _loot: Dictionary = {}
var _hazards: Dictionary = {}

## id -> {node, head, gun, muzzle, yaw, pitch, want_yaw, want_pitch, idle, flash}
var _turrets: Dictionary = {}

## id -> {node, velocity}
var _flying: Dictionary = {}

## [node, seconds left, light]
var _blasts: Array = []

## victim player node -> {holder: Node3D, segments: [MeshInstance3D], knot: MeshInstance3D}
var _tongues: Dictionary = {}

## Pieces a tongue is drawn in, along its sag.
const TONGUE_SEGMENTS := 10

## The special holding the person whose eyes these are, drawn in front of them (see [method pin]).
var _lens_holder: Node3D = null
var _lens_victim: Node3D = null
var _lens_view: Node3D = null

var _rng := RandomNumberGenerator.new()
var _materials: Dictionary = {}

## Where killed zombies fall as skeletal ragdolls: dot-player-char's yard, the same bodies and
## reactions every player in the family falls with (a skinned body falls by its bones). Its
## cap is the machine's (four in a browser tab) and the server's `max_count`; a death past the
## cap, or with `sv_ragdoll 0`, is the view's animated fall instead (`ZzZombieView.die`), so a
## horde dying at once is a few ragdolls and the rest falling by the clip.
var ragdolls: DotPlayerRagdolls = null

## What a ragdoll lands on: the level's world and prop layers (`ZzGame.world_mask`).
var ragdoll_mask: int = 1

## The server's `sv_ragdoll*` rules (`ZzGame.ragdoll_rules`, followed through the link), set
## before this enters the tree. Null: the stock rules with [constant CORPSE_SECONDS].
var ragdoll_rules: DotPlayerRagdollRules = null
## How far each zombie is animated, shadowed and drawn; the client points it at `crowd_detail`.
var lod := ZzZombieLod.new()


func _ready() -> void:
	_rng.seed = Time.get_ticks_usec()
	ragdolls = DotPlayerRagdolls.new()
	ragdolls.name = "Ragdolls"
	if ragdoll_rules != null:
		ragdolls.rules = ragdoll_rules
	else:
		ragdolls.rules.lifetime = CORPSE_SECONDS
	ragdolls.sound_fn = _ragdoll_sound
	add_child(ragdolls)


## A dead body's landing (dot-player-char's stock death sounds), where it landed.
func _ragdoll_sound(id: StringName, at: Vector3, volume: float) -> void:
	if audio != null:
		var _played := audio.at(id, at, clampf(volume, 0.3, 1.0))


## Drops a survivor's [param figure] the way [param death] says: the same yard and rules as the
## zombies, so the cap counts both and the oldest body (a zombie, as a rule) makes room.
func drop_survivor(figure: Node3D, death: DotPlayerDeath, velocity: Vector3) -> DotPlayerRagdoll:
	if ragdolls == null or figure == null or not figure.is_inside_tree():
		return null
	ragdolls.rules.collision_mask = ragdoll_mask
	return ragdolls.spawn(figure, death if death != null else DotPlayerDeath.new(), velocity)


# --- Zombies -----------------------------------------------------------------

## The view class a kind draws with: the mutant and the oil monster have bodies of their own.
static func view_for(kind: StringName) -> ZzZombieView:
	match kind:
		&"mutant":
			return ZzMutantView.new()
		&"oil_monster":
			return ZzOilMonsterView.new()

	return ZzZombieView.new()


func add_zombie(key: int, kind: StringName, variant: int, body: Node3D) -> void:
	if body == null or _zombies.has(key):
		return

	var view: ZzZombieView = view_for(kind)
	view.name = "View"
	view.lod = lod
	body.add_child(view)
	view.build(kind, variant)
	# A mirror has no limbs yet (the server's body has them from its spawn); the view cuts them.
	var _limbs := ZzZombieLimbs.attach(body, kind, variant)
	ZzZombieLimbs.bind_view(body, view)

	view.set_fade(_alpha_of(kind))
	var entry := {"body": body, "view": view, "kind": kind, "last_anim": -1,
		"next_moan": _rng.randf_range(1.0, 9.0), "voice": 0}
	_zombies[key] = entry

	if kind != &"common" and audio != null:
		var handle := audio.special_voice(kind, body.global_position)

		# The sleeper's crying follows her for as long as she is there.
		if kind == &"sleeper":
			entry["voice"] = handle


## What the killcam records: [key, kind, variant, position, yaw, anim, flags] for each zombie
## within [param radius] of [param centre].
func snapshot(centre: Vector3, radius: float) -> Array:
	var rows: Array = []
	for key: int in _zombies:
		var entry: Dictionary = _zombies[key]
		var body: Node3D = entry["body"]
		var view: ZzZombieView = entry["view"]
		if body == null or not is_instance_valid(body) or view == null or not is_instance_valid(view):
			continue
		var at := body.global_position
		if at.distance_squared_to(centre) > radius * radius:
			continue
		rows.append([key, entry["kind"], view.variant, at, body.global_rotation.y, int(body.get(&"anim")), int(body.get(&"flags"))])
	return rows


## Hides the live zombies and their corpses while a replay draws its own, and shows them again.
func set_replaying(on: bool) -> void:
	for key: int in _zombies:
		var body: Node3D = _zombies[key]["body"]
		if body != null and is_instance_valid(body):
			body.visible = not on
	for corpse: Array in _corpses:
		var view: Node3D = corpse[0]
		if view != null and is_instance_valid(view):
			view.visible = not on
	# The dead lie where they fell, in the replay's frame too: a still, sprawled body at the camera.
	if ragdolls != null:
		ragdolls.visible = not on


## The kind of the zombie drawn under [param key], or empty.
func kind_of(key: int) -> StringName:
	var entry: Variant = _zombies.get(key)
	return (entry as Dictionary)["kind"] if entry != null else &""


## A zombie gone: a body to drop for a moment if it was killed.
func remove_zombie(key: int, killed: bool, body: Node3D = null) -> void:
	var entry: Variant = _zombies.get(key)
	_zombies.erase(key)

	if entry == null:
		if body != null and is_instance_valid(body):
			body.queue_free()
		return

	if audio != null and int((entry as Dictionary)["voice"]) != 0:
		audio.stop(int((entry as Dictionary)["voice"]))

	var view: ZzZombieView = (entry as Dictionary)["view"]
	var old_body: Node3D = body if body != null else (entry as Dictionary)["body"]

	if not killed or view == null or not is_instance_valid(view):
		if body != null and is_instance_valid(body):
			body.queue_free()
		# A holder drawn at the lens hangs off this node, not the body, and goes with it.
		if view != null and is_instance_valid(view) and view.get_parent() == self:
			view.queue_free()
		return

	if audio != null and old_body != null and is_instance_valid(old_body):
		var _died := audio.cue_at((entry as Dictionary)["kind"], &"die", old_body.global_position)

	# A skeletal ragdoll when there is room for one: copied from the view where it stands, so
	# the view and the server's body go now.
	var picked: Variant = old_body.get(&"death") if old_body != null and is_instance_valid(old_body) else null
	# `sv_ragdoll_style hide`: the body goes at once, ragdoll or not.
	if ragdolls != null and ragdolls.rules.effective_style() == DotPlayerRagdollRules.Style.HIDE:
		view.queue_free()
		if body != null and is_instance_valid(body):
			body.queue_free()
		return
	if picked is DotPlayerDeath and _ragdoll(view, picked as DotPlayerDeath):
		view.queue_free()
		if body != null and is_instance_valid(body):
			body.queue_free()
		return

	# The view outlives the body: offline the server's body is freed this frame, so the view is
	# moved out to here and left playing its death.
	var keep := view.global_transform
	var death: Variant = old_body.get(&"death") if old_body != null and is_instance_valid(old_body) else null
	view.get_parent().remove_child(view)
	add_child(view)
	view.global_transform = keep
	_corpses.append([view, maxf(ragdolls.rules.lifetime, 1.0) if ragdolls != null else CORPSE_SECONDS])

	# The server's pick of how it falls (dot-player-char's reactions); a body nobody was told
	# about drops where it stands.
	if death is DotPlayerDeath:
		var d := death as DotPlayerDeath
		view.die(d.reaction, d.direction * clampf(d.damage / 40.0, 0.6, 2.2), d.roll_seed)
	else:
		view.die(&"limp", Vector3.ZERO, 0)

	if body != null and is_instance_valid(body):
		body.queue_free()


## Drops [param view] as a ragdoll the way [param death] says, or false when this machine is
## at its cap or the server turned ragdolls off (the caller draws the animated fall instead).
func _ragdoll(view: ZzZombieView, death: DotPlayerDeath) -> bool:
	if ragdolls == null or not ragdolls.rules.enabled or ragdolls.standing_count() >= ragdolls.cap():
		return false
	if not view.is_inside_tree() or not view.visible:
		return false
	ragdolls.rules.collision_mask = ragdoll_mask
	return ragdolls.spawn(view, death) != null


func zombie_count() -> int:
	return _zombies.size()


# --- Loot ----------------------------------------------------------------------

func add_loot(id: int, kind: StringName, item: StringName, at: Vector3, box_colour: Color = Color(0.8, 0.6, 0.25)) -> void:
	remove_loot(id)
	var node := Node3D.new()
	node.name = "Loot_%d" % id
	add_child(node)
	node.global_position = at

	match kind:
		&"weapon", &"throwable":
			var art: Variant = ZeeWeaponArtTable.table().get(item)
			var model: Node3D = ZeeModelCache.instantiate((art as ZeeWeaponArt).model_path) \
				if art is ZeeWeaponArt and (art as ZeeWeaponArt).model_path != "" else null

			if model != null:
				node.add_child(model)
				model.basis = Basis(Vector3.FORWARD, PI * 0.5) * (art as ZeeWeaponArt).orientation()
				model.scale = Vector3.ONE * (art as ZeeWeaponArt).world_scale
				model.position.y = 0.08
			else:
				node.add_child(_box(Vector3(0.6, 0.12, 0.2), Color(0.3, 0.3, 0.32)))
		&"ammo":
			for i in 3:
				var crate := _box(Vector3(0.35, 0.22, 0.25), Color(0.32, 0.38, 0.22))
				crate.position = Vector3(float(i % 2) * 0.38 - 0.19, 0.11 + float(i / 2) * 0.22, 0.0)
				node.add_child(crate)
		&"medkit":
			node.add_child(_box(Vector3(0.42, 0.14, 0.3), Color(0.92, 0.92, 0.9)))
			var cross_a := _box(Vector3(0.22, 0.02, 0.06), Color(0.85, 0.08, 0.08))
			cross_a.position.y = 0.15
			node.add_child(cross_a)
			var cross_b := _box(Vector3(0.06, 0.02, 0.22), Color(0.85, 0.08, 0.08))
			cross_b.position.y = 0.15
			node.add_child(cross_b)
		&"defib":
			var unit := ZzDefibModel.instantiate()

			if unit != null:
				unit.name = "Defib"
				unit.rotation_degrees.y = 180.0
				unit.scale = Vector3.ONE * 1.5
				node.add_child(unit)
			else:
				node.add_child(_box(Vector3(0.3, 0.16, 0.4), Color(0.85, 0.85, 0.88)))
		&"pills":
			var bottle := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.045
			cylinder.bottom_radius = 0.045
			cylinder.height = 0.16
			bottle.mesh = cylinder
			bottle.position.y = 0.08
			bottle.material_override = _material(Color(0.95, 0.6, 0.15))
			node.add_child(bottle)
		&"backpack":
			var tier := clampf(float(String(item).to_int()), 1.0, 3.0)
			var pack := _box(Vector3(0.34 + 0.06 * tier, 0.42 + 0.06 * tier, 0.2 + 0.04 * tier), Color(0.28, 0.33 - 0.04 * tier, 0.2))
			pack.position.y = 0.25
			node.add_child(pack)
			var flap := _box(Vector3(0.3 + 0.06 * tier, 0.08, 0.24 + 0.04 * tier), Color(0.2, 0.22, 0.14))
			flap.position.y = 0.5 + 0.06 * tier
			node.add_child(flap)
		&"box":
			var crate := _box(Vector3(0.55, 0.45, 0.55), box_colour)
			crate.name = "Crate"
			crate.position.y = 0.4
			node.add_child(crate)
			var glow := OmniLight3D.new()
			glow.light_color = box_colour
			glow.omni_range = 3.0
			glow.light_energy = 0.8
			glow.position.y = 0.6
			node.add_child(glow)
			node.set_meta(&"bob", true)

	node.set_meta(&"label", _label(kind, item))
	_loot[id] = node


static func _label(kind: StringName, item: StringName) -> String:
	match kind:
		&"weapon", &"throwable":
			return "pick up %s" % ZzWeapons.title_of(item)
		&"ammo":
			return "take ammo"
		&"medkit":
			return "take the medkit"
		&"pills":
			return "take the pills"
		&"defib":
			return "take the defibrillator"
		&"backpack":
			return "wear backpack %s" % String(item)
		&"box":
			return "take the box" if item == &"unknown" else "take the %s box" % String(item).replace("_", " ")
	return "pick up"


## Marks loot [param id] as sold for [param price] points; the prompt says so.
func set_loot_price(id: int, price: int) -> void:
	var node: Node3D = _loot.get(id)

	if node != null and price > 0:
		node.set_meta(&"price", price)
		var tag := Label3D.new()
		tag.text = "%d" % price
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		# Seen through walls on purpose, so the map's occluders must not hide it either.
		tag.ignore_occlusion_culling = true
		tag.fixed_size = true
		tag.pixel_size = 0.0007
		tag.font_size = 40
		tag.outline_size = 12
		tag.modulate = Color(1.0, 0.85, 0.3)
		tag.position = Vector3(0.0, 0.7, 0.0)
		node.add_child(tag)


## Crates that moved on the server: `[id, at, rotation]` each. The pose is eased to in
## [method _present_loot], so ten updates a second are not ten steps; a bobbing box rests instead.
func move_loot_many(rows: Array) -> void:
	for row: Array in rows:
		var node: Node3D = _loot.get(int(row[0]))
		if node == null or not is_instance_valid(node):
			continue
		node.set_meta(&"aim_at", row[1])
		node.set_meta(&"aim_turn", row[2])
		if node.has_meta(&"bob"):
			node.remove_meta(&"bob")
			var crate := node.get_node_or_null(^"Crate") as Node3D
			if crate != null:
				crate.position.y = 0.225
				crate.rotation.y = 0.0


func remove_loot(id: int) -> void:
	var node: Node3D = _loot.get(id)
	_loot.erase(id)

	if node != null and is_instance_valid(node):
		node.queue_free()


# --- Hazards ---------------------------------------------------------------------

func add_hazard(id: int, kind: StringName, at: Vector3, radius: float, seconds: float) -> void:
	remove_hazard(id)
	var node := Node3D.new()
	node.name = "Hazard_%d" % id
	add_child(node)
	node.global_position = at + Vector3(0.0, 0.03, 0.0)
	node.set_meta(&"radius", radius)
	node.set_meta(&"age", 0.0)
	node.set_meta(&"life", seconds)

	var colour := Color(0.45, 0.85, 0.12, 0.55)

	match kind:
		&"fire":
			colour = Color(1.0, 0.45, 0.08, 0.35)
			var fire := _particles(Color(1.0, 0.55, 0.12), radius, 40)
			node.add_child(fire)
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.5, 0.15)
			light.omni_range = radius * 2.5
			light.light_energy = 1.6
			light.position.y = 1.0
			node.add_child(light)
		&"heal":
			colour = Color(0.3, 1.0, 0.45, 0.3)
		&"goo", &"goo_trail":
			colour = Color(0.02, 0.02, 0.04, 0.85)
			if kind == &"goo" and audio != null:
				var _glop := audio.at(ZzAudio.SPLAT, at)
		&"acid":
			if audio != null:
				var _splat := audio.at(ZzAudio.SPLAT, at)

	var disc := MeshInstance3D.new()
	disc.name = "Pool"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 0.02
	disc.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(colour.r, colour.g, colour.b) * 0.6
	disc.material_override = material
	disc.scale = Vector3(0.2, 1.0, 0.2) * radius
	node.add_child(disc)
	_hazards[id] = node


# --- Turrets ---------------------------------------------------------------------

const TURRET_MODEL := "res://assets/turret/turret.glb"

## Barrel turn on a client, radians a second: a little faster than the server's own, so the
## drawn gun is on its target when the shot is told.
const TURRET_TURN := 9.0


func add_turret(id: int, at: Vector3, yaw: float, _seconds: float) -> void:
	remove_turret(id)
	var scene := load(ZzPaths.rebase(TURRET_MODEL)) as PackedScene
	var node: Node3D = scene.instantiate() if scene != null else _box(Vector3(0.5, 1.0, 0.5), Color(0.3, 0.4, 0.45))
	node.name = "Turret_%d" % id
	add_child(node)
	node.global_position = at
	var head := node.find_child("Head", true, false) as Node3D
	var gun := node.find_child("Gun", true, false) as Node3D
	var muzzle := node.find_child("Muzzle", true, false) as Node3D
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.45)
	flash.omni_range = 5.0
	flash.light_energy = 0.0
	(muzzle if muzzle != null else node).add_child(flash)

	if head != null:
		head.rotation.y = yaw

	_turrets[id] = {"node": node, "head": head, "gun": gun, "muzzle": muzzle, "yaw": yaw, "pitch": 0.0,
		"want_yaw": yaw, "want_pitch": 0.0, "idle": 0.0, "flash": flash, "flash_left": 0.0, "age": 0.0}


## The server told it fired at [param target]: turn the barrel there, flash, and draw the line.
func fire_turret(id: int, target: Vector3) -> void:
	var t: Dictionary = _turrets.get(id, {})

	if t.is_empty():
		return

	var head := t["head"] as Node3D
	var from: Vector3 = (t["muzzle"] as Node3D).global_position if t["muzzle"] != null else (t["node"] as Node3D).global_position
	var pivot: Vector3 = head.global_position if head != null else from
	var to := target - pivot
	t["want_yaw"] = atan2(-to.x, -to.z)
	t["want_pitch"] = atan2(to.y - 0.3, Vector2(to.x, to.z).length())
	t["idle"] = 0.0
	t["flash_left"] = 0.06
	(t["flash"] as OmniLight3D).light_energy = 3.0
	_tracer(from, target)



func remove_turret(id: int) -> void:
	var t: Dictionary = _turrets.get(id, {})
	_turrets.erase(id)

	if not t.is_empty() and is_instance_valid(t["node"]):
		(t["node"] as Node).queue_free()


func _tracer(from: Vector3, to: Vector3) -> void:
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var length := from.distance_to(to)
	mesh.size = Vector3(0.025, 0.025, length)
	line.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.55, 0.95, 1.0)
	line.material_override = material
	add_child(line)
	line.global_position = (from + to) * 0.5
	line.look_at(to)
	var tween := line.create_tween()
	tween.tween_callback(line.queue_free).set_delay(0.05)


func _present_turrets(delta: float) -> void:
	for id: int in _turrets:
		var t: Dictionary = _turrets[id]
		t["idle"] = float(t["idle"]) + delta
		t["age"] = float(t["age"]) + delta

		# Not fired for a moment: scan side to side, so a standing turret looks switched on.
		if float(t["idle"]) > 1.0:
			t["want_yaw"] = float(t["want_yaw"]) + delta * 0.6
			t["want_pitch"] = 0.0

		var step := TURRET_TURN * delta
		t["yaw"] = float(t["yaw"]) + clampf(angle_difference(float(t["yaw"]), float(t["want_yaw"])), -step, step)
		t["pitch"] = float(t["pitch"]) + clampf(float(t["want_pitch"]) - float(t["pitch"]), -step, step)

		if t["head"] != null:
			(t["head"] as Node3D).rotation.y = float(t["yaw"])
		if t["gun"] != null:
			(t["gun"] as Node3D).rotation.x = float(t["pitch"])

		if float(t["flash_left"]) > 0.0:
			t["flash_left"] = float(t["flash_left"]) - delta

			if float(t["flash_left"]) <= 0.0:
				(t["flash"] as OmniLight3D).light_energy = 0.0


func remove_hazard(id: int) -> void:
	var node: Node3D = _hazards.get(id)
	_hazards.erase(id)

	if node != null and is_instance_valid(node):
		node.queue_free()


# --- Thrown things -------------------------------------------------------------------

func throw(id: int, kind: StringName, from: Vector3, velocity: Vector3) -> void:
	if kind == &"beam_zap" or kind == &"beam_pull":
		var zap := kind == &"beam_zap"
		var _beam := DotFxBeam.zap(self, from, from + velocity,
			Color(0.5, 0.85, 1.0) if zap else Color(0.9, 0.5, 1.0), 0.25, 0.12 if zap else 0.07)
		if audio != null and zap:
			var _zzt := audio.at(ZzAudio.WOOSH, from)
		return

	var node := MeshInstance3D.new()
	node.name = "Thrown_%d" % id
	var sphere := SphereMesh.new()
	var colour := Color(0.5, 0.85, 0.15)
	var size := 0.25

	match kind:
		&"rock":
			colour = Color(0.45, 0.42, 0.4)
			size = 0.9
		&"pipe":
			colour = Color(0.2, 0.2, 0.22)
			size = 0.18
		&"shell":
			colour = Color(0.15, 0.15, 0.15)
			size = 0.3
		&"molotov":
			colour = Color(0.9, 0.5, 0.1)
			size = 0.15
		&"grenade":
			colour = Color(0.22, 0.3, 0.16)
			size = 0.16
		&"rocket":
			colour = Color(0.75, 0.75, 0.7)
			size = 0.2
		&"bile":
			colour = Color(0.45, 0.65, 0.1)
			size = 0.16
		&"goo_spit":
			colour = Color(0.02, 0.02, 0.04)
			size = 0.45

	sphere.radius = size * 0.5
	sphere.height = size
	node.mesh = sphere
	node.material_override = _material(colour)
	add_child(node)
	node.global_position = from
	_flying[id] = {"node": node, "velocity": velocity, "kind": kind, "beep": 0.0}

	if audio != null and kind != &"shell":
		var _woosh := audio.at(ZzAudio.WOOSH, from)


func land(id: int, kind: StringName, at: Vector3) -> void:
	var entry: Variant = _flying.get(id)

	if entry == null:
		return

	# A pipe (or a grenade on its fuse) lies where it landed, and a pipe beeps; everything else
	# is gone.
	if kind == &"pipe" or kind == &"grenade":
		var node: Node3D = (entry as Dictionary)["node"]
		node.global_position = at
		(entry as Dictionary)["velocity"] = Vector3.ZERO
		(entry as Dictionary)["landed"] = true
		return

	_flying.erase(id)
	var node: Node3D = (entry as Dictionary)["node"]

	if node != null and is_instance_valid(node):
		node.queue_free()

	if kind == &"rock" and audio != null:
		var _crack := audio.at(ZzAudio.ROCK, at)


## An explosion's flash, its fire and its noise.
func blast(at: Vector3, radius: float, kind: StringName) -> void:
	# A pipe that went off is no longer beeping.
	for id: int in _flying.keys():
		var entry: Dictionary = _flying[id]
		if (entry["kind"] == &"pipe" or entry["kind"] == &"grenade") and (entry["node"] as Node3D).global_position.distance_to(at) < 1.5:
			(entry["node"] as Node3D).queue_free()
			_flying.erase(id)

	var node := Node3D.new()
	node.name = "Blast"
	add_child(node)
	node.global_position = at

	var bile := kind == &"bile"
	var colour := Color(0.55, 0.75, 0.1) if bile else (Color(0.6, 0.55, 0.5) if kind == &"slam" else Color(1.0, 0.6, 0.2))
	var puff := _particles(colour, radius * 0.5, 60)
	puff.one_shot = true
	puff.explosiveness = 0.95
	puff.initial_velocity_min = radius * 1.2
	puff.initial_velocity_max = radius * 2.4
	puff.direction = Vector3.UP
	puff.spread = 80.0
	node.add_child(puff)

	var light := OmniLight3D.new()
	light.light_color = colour
	light.omni_range = radius * 3.0
	light.light_energy = 0.0 if bile else 6.0
	light.position.y = 1.0
	node.add_child(light)
	_blasts.append([node, BLAST_SECONDS * (2.0 if not bile else 1.5), light])

	if audio != null:
		var _boom := audio.at(ZzAudio.SPLAT if bile else ZzAudio.EXPLOSION, at)


# --- Tongues ------------------------------------------------------------------

## [param victim] is held by [param holder]: a choke draws a tongue between them, and a holder
## on the person whose eyes these are ([param at_lens]) is drawn in front of them.
##
## [b]A leaper or a rider on you is drawn where you can see it.[/b] The server puts it on top of
## you, which is right for everybody else and puts its body round your camera: the first play
## test saw "two black polygons" (the inside of its mesh) and never knew what had it. So for the
## victim alone its picture stands just in front of the lens, facing them, clawing.
func pin(victim: Node3D, holder: Node3D, kind: StringName, at_lens: bool = false) -> void:
	unpin(victim)

	if victim == null or holder == null:
		return

	if audio != null:
		var _call := audio.at(ZzAudio.CALL_HELP, victim.global_position)

	if at_lens and (kind == &"pounce" or kind == &"ride"):
		_lens_holder = holder
		_lens_victim = victim
		# Out from under the body: the camera fade hides whatever hangs off a collider at the
		# lens, and the body is exactly there.
		_lens_view = holder.get_node_or_null(^"View") as Node3D
		if _lens_view != null:
			_lens_view.reparent(self, true)

	if kind != &"choke":
		return

	var segments: Array[MeshInstance3D] = []
	var flesh := _material(Color(0.86, 0.36, 0.44))

	for i in TONGUE_SEGMENTS:
		var piece := MeshInstance3D.new()
		piece.name = "Tongue%d" % i
		var cylinder := CylinderMesh.new()
		var f := float(i) / float(TONGUE_SEGMENTS)
		cylinder.top_radius = lerpf(0.08, 0.045, f)
		cylinder.bottom_radius = lerpf(0.085, 0.05, f)
		cylinder.height = 1.0
		cylinder.radial_segments = 6
		cylinder.rings = 1
		piece.mesh = cylinder
		piece.material_override = flesh
		add_child(piece)
		segments.append(piece)

	# The tip wrapped round them: a knot of tongue at their chest.
	var knot := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.28
	torus.rings = 10
	torus.ring_segments = 6
	knot.mesh = torus
	knot.material_override = flesh
	add_child(knot)
	_tongues[victim] = {"holder": holder, "segments": segments, "knot": knot}


func unpin(victim: Node3D) -> void:
	var entry: Variant = _tongues.get(victim)
	_tongues.erase(victim)

	if entry != null:
		for piece: Node in (entry as Dictionary)["segments"]:
			if is_instance_valid(piece):
				piece.queue_free()
		if is_instance_valid((entry as Dictionary)["knot"]):
			((entry as Dictionary)["knot"] as Node).queue_free()

	if victim != _lens_victim:
		return

	if _lens_view != null and is_instance_valid(_lens_view) and _lens_view.get_parent() == self:
		if _lens_holder != null and is_instance_valid(_lens_holder):
			_lens_view.reparent(_lens_holder, false)
			_lens_view.transform = Transform3D.IDENTITY

	_lens_holder = null
	_lens_victim = null
	_lens_view = null


# --- The frame ---------------------------------------------------------------------

## The effects the HUD lists; the Hard Box's stacks are what fade the zombies.
func set_effects(rows: Array) -> void:
	var stacks := 0

	for row: Variant in rows:
		if row is Dictionary and str((row as Dictionary).get("id", "")) == "hard":
			stacks += int((row as Dictionary).get("stacks", 0))

	hard_stacks = stacks


func _alpha_of(kind: StringName) -> float:
	return ZzNpcs.fade_alpha(fade_config, kind, hard_stacks) if fade_config != null else 1.0


## Redraws every zombie when a stack or a cvar moved, so a change mid-life shows at once.
func _refresh_fade() -> void:
	if fade_config == null:
		return

	var sig := "%d|%s|%s|%s|%s" % [hard_stacks, fade_config.get(&"mutant_fade"), fade_config.get(&"mutant_min_alpha"),
		fade_config.get(&"mutant_fade_per_stack"), fade_config.get(&"common_fade")]

	if sig == _fade_seen:
		return

	_fade_seen = sig

	for key: Variant in _zombies:
		var entry: Dictionary = _zombies[key]
		var view: ZzZombieView = entry["view"]

		if is_instance_valid(view):
			view.set_fade(_alpha_of(entry["kind"]))


func present(delta: float, listener: Vector3) -> void:
	_refresh_fade()
	_present_zombies(delta, listener)
	_present_corpses(delta)
	_present_loot(delta)
	_present_hazards(delta)
	_present_turrets(delta)
	_present_flying(delta)
	_present_blasts(delta)
	_present_tongues()
	_present_lens_holder()


## A shot landed at [param point]: the nearest zombie within reach gets a wound mark there (client only).
func wound_near(point: Vector3) -> void:
	var best: ZzZombieView = null
	var best_d := 1.4
	for key: int in _zombies.keys():
		var view: ZzZombieView = (_zombies[key] as Dictionary).get("view")
		if view == null or not is_instance_valid(view) or not view.is_inside_tree():
			continue
		var d := (view.global_position + Vector3(0.0, 1.0, 0.0)).distance_to(point)
		if d < best_d:
			best_d = d
			best = view
	if best != null:
		best.wound_at(point)


func _present_zombies(delta: float, listener: Vector3) -> void:
	lod.refresh(get_viewport().get_camera_3d() if is_inside_tree() else null)
	for key: int in _zombies.keys():
		var entry: Dictionary = _zombies[key]
		var body: Node3D = entry["body"]
		var view: ZzZombieView = entry["view"]

		if body == null or not is_instance_valid(body) or view == null or not is_instance_valid(view):
			_zombies.erase(key)
			continue

		var anim := int(body.get(&"anim"))
		var flags := int(body.get(&"flags"))

		# Hit: a flinch over whatever it is doing, from the health the snapshot carries.
		var health := float(body.get(&"health"))
		var was := float(entry.get("health", health))
		entry["health"] = health
		if health < was - 0.5 and health > 0.0:
			view.flinch(-1.0 if (int(health) & 1) == 0 else 1.0)

		view.present(delta, anim, flags)

		if audio == null:
			continue

		var at := body.global_position
		var last := int(entry["last_anim"])
		entry["last_anim"] = anim

		if int(entry["voice"]) != 0:
			audio.move(int(entry["voice"]), at)

		# Further than this nobody is listening; the audio layer would cull it anyway, and
		# not asking saves forty calls a frame.
		if at.distance_to(listener) > 45.0:
			continue

		if anim != last:
			match anim:
				ZzZombieBody.Anim.RAGE:
					var kind: StringName = entry["kind"]
					var _s := audio.cue_at(&"common", &"rage", at) if kind == &"common" else audio.special_voice(kind, at)
				ZzZombieBody.Anim.ATTACK, ZzZombieBody.Anim.PIN:
					var _c := audio.cue_at(entry["kind"], &"attack", at)
				ZzZombieBody.Anim.LEAP, ZzZombieBody.Anim.CHARGE, ZzZombieBody.Anim.VOMIT, \
						ZzZombieBody.Anim.SPIT, ZzZombieBody.Anim.TONGUE, ZzZombieBody.Anim.THROW, \
						ZzZombieBody.Anim.SCREAM, ZzZombieBody.Anim.GRAB:
					var _v := audio.special_voice(entry["kind"], at)

		entry["next_moan"] = float(entry["next_moan"]) - delta

		if float(entry["next_moan"]) <= 0.0:
			entry["next_moan"] = _rng.randf_range(4.0, 14.0)

			if entry["kind"] == &"common":
				var _m := audio.cue_at(&"common", &"idle", at, 0.8)


func _present_corpses(delta: float) -> void:
	var kept: Array = []

	for corpse: Array in _corpses:
		var view: ZzZombieView = corpse[0]
		corpse[1] = float(corpse[1]) - delta

		if view == null or not is_instance_valid(view):
			continue

		view.present(delta, ZzZombieBody.Anim.DEAD, 0)

		if float(corpse[1]) < 1.0:
			view.position.y -= delta * 0.6

		if float(corpse[1]) <= 0.0:
			view.queue_free()
			continue

		kept.append(corpse)

	_corpses = kept


func _present_loot(delta: float) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001

	for id: int in _loot:
		var node: Node3D = _loot[id]
		if node.has_meta(&"aim_at"):
			var k := clampf(delta * 14.0, 0.0, 1.0)
			node.global_position = node.global_position.lerp(node.get_meta(&"aim_at"), k)
			node.quaternion = node.quaternion.slerp(node.get_meta(&"aim_turn"), k)
		if node.has_meta(&"bob"):
			var crate := node.get_node_or_null(^"Crate") as Node3D
			if crate != null:
				crate.position.y = 0.4 + sin(t * 2.0 + float(id)) * 0.08
				crate.rotation.y += delta * 0.8


func _present_hazards(delta: float) -> void:
	for id: int in _hazards:
		var node: Node3D = _hazards[id]
		var age := float(node.get_meta(&"age")) + delta
		node.set_meta(&"age", age)
		var pool := node.get_node_or_null(^"Pool") as Node3D

		if pool != null:
			var radius := float(node.get_meta(&"radius")) * clampf(age, 0.2, 1.0)
			pool.scale = Vector3(radius, 1.0, radius)


func _present_flying(delta: float) -> void:
	for id: int in _flying.keys():
		var entry: Dictionary = _flying[id]
		var node: Node3D = entry["node"]

		if node == null or not is_instance_valid(node):
			_flying.erase(id)
			continue

		if bool(entry.get("landed", false)):
			# A pipe on the ground: a blink and a beep, faster as it goes.
			if entry["kind"] == &"pipe":
				entry["beep"] = float(entry["beep"]) + delta
				node.visible = fmod(float(entry["beep"]) * 3.0, 1.0) < 0.6
			continue

		var velocity: Vector3 = entry["velocity"]
		# A rocket flies straight; everything else falls as the server's does.
		if entry["kind"] != &"rocket":
			velocity.y -= GRAVITY * delta
		entry["velocity"] = velocity
		node.global_position += velocity * delta


func _present_blasts(delta: float) -> void:
	var kept: Array = []

	for b: Array in _blasts:
		b[1] = float(b[1]) - delta
		var light: OmniLight3D = b[2]

		if is_instance_valid(light):
			light.light_energy = maxf(light.light_energy - delta * 12.0, 0.0)

		if float(b[1]) <= 0.0:
			if is_instance_valid(b[0]):
				(b[0] as Node).queue_free()
			continue

		kept.append(b)

	_blasts = kept


func _present_tongues() -> void:
	for victim: Node3D in _tongues.keys():
		var entry: Dictionary = _tongues[victim]
		var holder: Node3D = entry["holder"]

		if not is_instance_valid(victim) or not is_instance_valid(holder):
			unpin(victim)
			continue

		var view := holder.get_node_or_null(^"View")
		var from: Vector3 = view.call(&"mouth") if view != null and view.has_method(&"mouth") else holder.global_position + Vector3(0.0, 1.7, 0.0)
		var to := victim.global_position + Vector3(0.0, 1.15, 0.0)
		var length := from.distance_to(to)

		if length < 0.05:
			continue

		# A tongue sags between the two, more the slacker it is (a short one is pulled tight).
		var sag := clampf(length * 0.06, 0.05, 0.9)
		var points: Array[Vector3] = []
		var count: int = (entry["segments"] as Array).size()

		for i in count + 1:
			var f := float(i) / float(count)
			points.append(from.lerp(to, f) + Vector3.DOWN * sag * 4.0 * f * (1.0 - f))

		for i in count:
			var piece: MeshInstance3D = entry["segments"][i]
			_stretch(piece, points[i], points[i + 1])

		var knot: MeshInstance3D = entry["knot"]
		knot.global_position = to + Vector3.DOWN * 0.1


## Lays a unit-tall cylinder from [param a] to [param b].
static func _stretch(piece: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)

	if length < 0.001:
		return

	var up := (b - a) / length
	var side := up.cross(Vector3.FORWARD) if absf(up.dot(Vector3.FORWARD)) < 0.95 else up.cross(Vector3.RIGHT)
	piece.global_transform = Transform3D(Basis(side.normalized(), up, side.normalized().cross(up)).scaled(Vector3(1.0, length * 1.08, 1.0)), (a + b) * 0.5)


## The holder at the lens, put where the victim can see it: a step in front, facing them.
func _present_lens_holder() -> void:
	if _lens_holder == null:
		return

	if not is_instance_valid(_lens_holder) or _lens_view == null or not is_instance_valid(_lens_view) \
			or _lens_view.get_parent() != self:
		_lens_holder = null
		return

	var view := _lens_view
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null

	if view == null or camera == null:
		return

	var forward := -camera.global_basis.z
	forward.y = 0.0

	if forward.length() < 0.01:
		return

	forward = forward.normalized()
	var tall := float((view.call(&"describe") as Dictionary).get("height", 1.6)) if view.has_method(&"describe") else 1.6
	var at := camera.global_position + forward * 1.15 + Vector3.DOWN * tall * 0.82
	view.global_position = at
	view.look_at(Vector3(camera.global_position.x, at.y, camera.global_position.z), Vector3.UP)


# --- Making things ----------------------------------------------------------------

func _box(size: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position.y = size.y * 0.5
	mesh.material_override = _material(colour)
	return mesh


func _material(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html()

	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.roughness = 0.6
		_materials[key] = m

	return _materials[key]


func _particles(colour: Color, radius: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(radius * 0.6, 0.2)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0.0, 1.5, 0.0)
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.5
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	# dot-fx's soft sprite: an untextured quad was a hard square, the "big pixels" of the fire.
	var material := DotFxSoftSprite.material(Color(colour.r, colour.g, colour.b, 1.0))
	quad.material = material
	p.mesh = quad
	var gradient := Gradient.new()
	gradient.set_color(0, Color(colour.r, colour.g, colour.b, 1.0))
	gradient.set_color(1, Color(colour.r * 0.5, colour.g * 0.3, colour.b * 0.2, 0.0))
	p.color_ramp = gradient
	return p


func clear() -> void:
	if ragdolls != null:
		ragdolls.clear()
	for id: int in _loot.keys():
		remove_loot(id)
	for id: int in _hazards.keys():
		remove_hazard(id)
	for id: int in _turrets.keys():
		remove_turret(id)
	for id: int in _flying.keys():
		var node: Node = (_flying[id] as Dictionary)["node"]
		if is_instance_valid(node):
			node.queue_free()
	_flying.clear()
	for victim: Node3D in _tongues.keys():
		unpin(victim)
	if _lens_victim != null:
		unpin(_lens_victim)


func describe() -> Dictionary:
	return {
		"zombies": _zombies.size(), "corpses": _corpses.size(), "loot": _loot.size(),
		"hazards": _hazards.size(), "turrets": _turrets.size(), "flying": _flying.size(), "tongues": _tongues.size(),
	}
