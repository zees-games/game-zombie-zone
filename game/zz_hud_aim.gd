extends "zz_hud_base.gd"

## The crosshair, the scope and how both follow the aim: the aiming part of [code]zz_hud.gd[/code], split
## off so the HUD stays a size the efficiency gate allows.

## dot-ui's spread crosshair where the host has it (API 10), else the old dot. Through Variants: named
## directly, an older dot-ui fails to compile this script.
func _make_crosshair() -> Control:
	if GSAddonApi.build_level("dot_ui") >= 10:
		var shape: Variant = GSCrosshair
		var cross := (shape as GDScript).new() as Control
		cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Dead or spectating: nothing in hand to aim (dot-ui API 14; older ones ignore the property).
		if GSAddonApi.build_level("dot_ui") >= 14:
			cross.set(&"alive_source", func() -> bool: return player != null and player.is_alive() and not player.watching)
		return cross

	var dot := ColorRect.new()
	dot.color = Color(1.0, 1.0, 1.0, 0.75)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dot.offset_left = -2.0
	dot.offset_top = -2.0
	dot.offset_right = 2.0
	dot.offset_bottom = 2.0
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot

## The crosshair control, for the feel's cl_crosshair_* binding.
func crosshair() -> Control:
	return _crosshair

## The weapon's spread cone in degrees, from the arsenal; the crosshair opens with it.
func set_spread(degrees: float, fov: float = 75.0, gap_scale: float = 1.0) -> void:
	if _crosshair != null and _crosshair.has_method(&"set_spread"):
		_crosshair.set(&"gap_scale", clampf(gap_scale, 0.1, 4.0))
		_crosshair.set(&"fov_degrees", clampf(fov, 10.0, 170.0))
		_crosshair.call(&"set_spread", degrees)

## The client's hands this frame: the scope follows their progressive fade-in and the crosshair gives way as it rises.
func follow_hands(hands: ZeeViewModel, camera: Camera3D = null) -> void:
	set_aim(hands.aim_fraction() if hands != null else 0.0, hands != null and hands.scope_fraction() > 0.0)
	if scope != null and hands != null:
		scope.follow(hands)
		# The lens view draws the zoom with a second camera that follows the player's and leaves the hands out.
		# Only for hands that keep the main camera at the hip in lens mode (`view_fov_scale`); an older
		# zee-weapons copy zooms the main camera, and a lens on top would zoom twice. By name, as the
		# overlay of such a copy has no `mode` either (ZzClient.scope_view_zoom has the story).
		var overlay: Object = scope
		if camera != null and hands.has_method(&"view_fov_scale") and "mode" in overlay and int(overlay.get(&"mode")) == 1 \
				and overlay.has_method(&"bind_camera"):
			overlay.call(&"bind_camera", camera, (1 << (hands.view_layer - 1)) if hands.view_layer > 0 else 0)

## The aim this frame: the dot fades as the gun comes up; [param scoped] hides it for the scope.
func set_aim(fraction: float, scoped: bool) -> void:
	aim_fraction = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 0.0
	_scoped = scoped
	if scope != null:
		scope.fraction = aim_fraction if scoped else 0.0
	if _crosshair != null and _crosshair.has_method(&"set_aim"):
		_crosshair.call(&"set_aim", aim_fraction)
		_crosshair.set(&"suppressed", scoped)
	elif _crosshair != null:
		_crosshair.modulate.a = 0.0 if scoped else crosshair_opacity(aim_fraction)

## How much of the dot [param fraction] leaves: dot-ui's curve where the host has it, else the
## dot stays (an older shell had no aim to fade for).
func crosshair_opacity(fraction: float) -> float:
	if not _fades:
		return 1.0
	# Through a Variant: named directly, an older dot-ui without it fails to compile this script.
	var crosshair: Variant = GSCrosshair
	return float((crosshair as Script).call(&"opacity_for_aim", fraction))
