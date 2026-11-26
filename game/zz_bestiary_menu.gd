extends PanelContainer

## The list of every infected the installed packs offer, as cards: the pack's icon (a tile with the first letter where the
## row has none or it will not load), the name and the role. Clicking a card asks for it by id ([signal picked]); the
## client sends an admin's `zz_spawn <id>`, so a player the server does not trust is refused there, not here.

signal picked(kind: String)
signal close_requested()

const ZzBestiary := preload("zz_bestiary.gd")

const PANEL := Color(0.06, 0.07, 0.1, 0.96)
const CARD := Color(0.12, 0.14, 0.19)
const CARD_HOVER := Color(0.17, 0.2, 0.27)
const ROLE_COLOR := {"boss": Color(1.0, 0.6, 0.3), "monster": Color(0.6, 0.9, 0.5)}
const CARD_SIZE := Vector2(150.0, 170.0)
const ICON_SIZE := 112.0

var _grid: GridContainer = null
var _empty: Label = null
## The card's id to whether its icon drew; a test reads it.
var drawn: Dictionary = {}


func _init() -> void:
	name = "BestiaryMenu"
	theme = GSUiTheme.dark().build(1.0)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(900.0, 560.0)
	offset_left = -450.0
	offset_right = 450.0
	offset_top = -280.0
	offset_bottom = 280.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_theme_stylebox_override("panel", _box(PANEL, 16, 18))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	var heading := Label.new()
	heading.text = "INFECTED"
	heading.add_theme_font_size_override("font_size", 28)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	_empty = Label.new()
	_empty.text = "No pack offers any infected."
	_empty.modulate = Color(1, 1, 1, 0.6)
	column.add_child(_empty)

	var foot := Label.new()
	foot.text = "Click to spawn near you (admins). Esc closes."
	foot.add_theme_font_size_override("font_size", 13)
	foot.modulate = Color(1, 1, 1, 0.5)
	column.add_child(foot)


## Shows [param entries] (default: what the packs list, [method ZzBestiary.entries]).
func open(entries: Array = []) -> void:
	_fill(entries if not entries.is_empty() else ZzBestiary.entries())
	visible = true
	move_to_front()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func card_count() -> int:
	return _grid.get_child_count()


func _fill(entries: Array) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	drawn.clear()
	_empty.visible = entries.is_empty()

	for entry: Dictionary in entries:
		_grid.add_child(_card(entry))


func _card(entry: Dictionary) -> Button:
	var id := str(entry["id"])
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_ALL
	card.tooltip_text = "%s (%s)" % [str(entry.get("name", id)), id]
	card.add_theme_stylebox_override("normal", _box(CARD, 10, 8))
	card.add_theme_stylebox_override("hover", _box(CARD_HOVER, 10, 8))
	card.add_theme_stylebox_override("pressed", _box(CARD_HOVER, 10, 8))
	card.add_theme_stylebox_override("focus", _box(CARD_HOVER, 10, 8))
	card.pressed.connect(func() -> void: picked.emit(id))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(column)

	var texture := ZzBestiary.texture(str(entry.get("icon", "")))
	drawn[id] = texture != null
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0.0, ICON_SIZE)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(holder)

	if texture != null:
		var picture := TextureRect.new()
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(picture)
	else:
		holder.add_child(_stand_in(str(entry.get("name", id))))

	var title := Label.new()
	title.text = str(entry.get("name", id))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var role := str(entry.get("role", ""))
	var tag := Label.new()
	tag.text = role.to_upper()
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", ROLE_COLOR.get(role, Color(0.55, 0.75, 1.0)))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tag)
	return card


## A tile with the name's first letter, in a colour taken from the name, for a row without a usable icon.
func _stand_in(label: String) -> Control:
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile.add_theme_stylebox_override("panel", _box(Color.from_hsv(float(hash(label) % 360) / 360.0, 0.4, 0.35), 10, 4))
	var letter := Label.new()
	letter.text = label.left(1).to_upper()
	letter.add_theme_font_size_override("font_size", 56)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(letter)
	return tile


func _box(color: Color, radius: int, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(pad)
	return box
