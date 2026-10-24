extends PanelContainer

## "Navigation regenerating" with a bar and a percent, in the corner while the map's graph is built.
## The HUD calls [method show_percent] every frame; -1 hides it.

const WIDTH := 300.0
const BAR_HEIGHT := 8.0

var _title: Label = null
var _percent: Label = null
var _back: ColorRect = null
var _fill: ColorRect = null


func _init() -> void:
	name = "NavMeter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.05, 0.06, 0.78)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(12)
	add_theme_stylebox_override("panel", box)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)

	_title = Label.new()
	_title.text = "Navigation regenerating"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 15)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_title)

	_percent = Label.new()
	_percent.add_theme_font_size_override("font_size", 15)
	_percent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_percent)

	# The bar is a track and a fill laid in a fixed-size holder: a container would stretch the fill.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(WIDTH, BAR_HEIGHT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(holder)

	_back = ColorRect.new()
	_back.color = Color(1.0, 1.0, 1.0, 0.14)
	_back.size = Vector2(WIDTH, BAR_HEIGHT)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_back)

	_fill = ColorRect.new()
	_fill.color = Color(0.98, 0.84, 0.5)
	_fill.size = Vector2(0.0, BAR_HEIGHT)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_fill)

	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -WIDTH - 24.0 - 24.0
	offset_right = -24.0
	offset_top = -190.0
	offset_bottom = -112.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN


## Shows the panel at [param percent] (0 to 100), or hides it for -1.
func show_percent(percent: int) -> void:
	visible = percent >= 0

	if percent < 0:
		return

	_percent.text = "%d%%" % percent
	_fill.size.x = WIDTH * float(percent) / 100.0
