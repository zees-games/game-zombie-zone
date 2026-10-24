extends PanelContainer

## The trader's menu: category tabs, a list of cards (a picture of the weapon, its name, its price), a detail pane with a large picture and the buy button, and the money you hold. Mouse, keyboard and gamepad (every card is a focusable button; a second click on the selected card buys). It only shows and asks; the server prices and sells ([ZzShop]).

signal buy_requested(item_id: String)
signal close_requested()

const ZzShopIcons := preload("zz_shop_icons.gd")

const CATEGORY_TITLES := {"weapons": "Weapons", "grenades": "Grenades", "ammo": "Ammo", "supplies": "Supplies", "entities": "Deployables"}
const CATEGORY_ORDER: Array = ["weapons", "grenades", "ammo", "supplies", "entities"]

const PANEL := Color(0.06, 0.07, 0.1, 0.96)
const CARD := Color(0.12, 0.14, 0.19)
const CARD_HOVER := Color(0.17, 0.2, 0.27)
const CARD_SELECTED := Color(0.16, 0.26, 0.4)
const ACCENT := Color(0.38, 0.65, 1.0)
const GOLD := Color(1.0, 0.83, 0.32)
const BAD := Color(1.0, 0.45, 0.4)
const GOOD := Color(0.25, 0.74, 0.45)

## items: the server's list. money: points held. state_fn(item) returns "" or why it is not buyable ("Owned", "Full").
var items: Array = []
var money: int = 0
var state_fn: Callable = Callable()
var category: String = "weapons"
var selected: String = ""

var _money_label: Label = null
var _tabs: HBoxContainer = null
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _picture: TextureRect = null
var _title: Label = null
var _kind: Label = null
var _body: Label = null
var _price: Label = null
var _buy: Button = null
var _icons: Node = null
var _rows: Dictionary = {}
var _signature: int = 0


func _init() -> void:
	name = "ShopMenu"
	var theme_source := DotUiTheme.dark()
	theme = theme_source.build(1.0)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(940.0, 540.0)
	offset_left = -470.0
	offset_right = 470.0
	offset_top = -270.0
	offset_bottom = 270.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_theme_stylebox_override("panel", _box(PANEL, 16, 18, 2, Color(1, 1, 1, 0.08)))

	_icons = ZzShopIcons.new()
	add_child(_icons)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	var heading := Label.new()
	heading.text = "TRADER"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", _box(Color(0.2, 0.17, 0.06), 20, 14, 1, GOLD.darkened(0.4), 6))
	head.add_child(pill)
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 22)
	_money_label.add_theme_color_override("font_color", GOLD)
	pill.add_child(_money_label)

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	column.add_child(_tabs)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 16)
	column.add_child(split)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)

	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size = Vector2(340.0, 0.0)
	detail_panel.add_theme_stylebox_override("panel", _box(CARD, 12, 14))
	split.add_child(detail_panel)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 8)
	detail_panel.add_child(detail)

	_picture = TextureRect.new()
	_picture.custom_minimum_size = Vector2(0.0, 150.0)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail.add_child(_picture)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_title)
	_kind = Label.new()
	_kind.add_theme_font_size_override("font_size", 14)
	_kind.add_theme_color_override("font_color", ACCENT)
	detail.add_child(_kind)
	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 15)
	_body.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(_body)
	_price = Label.new()
	_price.add_theme_font_size_override("font_size", 24)
	detail.add_child(_price)
	_buy = Button.new()
	_buy.text = "Buy"
	_buy.custom_minimum_size = Vector2(0.0, 48.0)
	_buy.add_theme_font_size_override("font_size", 18)
	_buy.add_theme_stylebox_override("normal", _box(GOOD, 10, 0))
	_buy.add_theme_stylebox_override("hover", _box(GOOD.lightened(0.15), 10, 0))
	_buy.add_theme_stylebox_override("pressed", _box(GOOD.darkened(0.2), 10, 0))
	_buy.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), 10, 0, 2, Color(1, 1, 1, 0.8)))
	_buy.add_theme_stylebox_override("disabled", _box(Color(0.2, 0.22, 0.27), 10, 0))
	_buy.pressed.connect(_ask_to_buy)
	detail.add_child(_buy)

	var foot := Label.new()
	foot.text = "Click a card, then Buy (or click it again). Esc closes. Walk away and it closes itself."
	foot.add_theme_font_size_override("font_size", 13)
	foot.modulate = Color(1, 1, 1, 0.5)
	column.add_child(foot)


## Opens on [param p_items] with [param p_money] held.
func open(p_items: Array, p_money: int, p_state_fn: Callable) -> void:
	items = p_items
	money = p_money
	state_fn = p_state_fn
	visible = true
	# Above the HUD's notices, which are later siblings.
	move_to_front()
	_signature = 0
	_rebuild()
	grab_focus_on_first()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## Redraws prices and states without losing the selection (a purchase, a new balance). The client calls this every frame; nothing is rebuilt unless what is shown changed, because a card freed between a press and its release is a click that never lands.
func refresh(p_items: Array, p_money: int) -> void:
	items = p_items
	money = p_money
	if visible and _current_signature() != _signature:
		_rebuild()


func grab_focus_on_first() -> void:
	if _selected_row() != null:
		_selected_row().grab_focus()
	elif _list.get_child_count() > 0 and _list.get_child(0) is Control:
		(_list.get_child(0) as Control).grab_focus()


func _selected_row() -> Button:
	return _rows.get(selected) as Button


func _ask_to_buy() -> void:
	if selected != "":
		buy_requested.emit(selected)


func _current_signature() -> int:
	var states: Array = []
	if state_fn.is_valid():
		for it: Dictionary in items:
			if str(it.get("cat", "")) == category:
				states.append(str(state_fn.call(it)))
	return hash([items.hash(), money, category, states])


func _categories() -> Array:
	var have := {}
	for it: Dictionary in items:
		have[str(it.get("cat", ""))] = true
	var out: Array = []
	for c: String in CATEGORY_ORDER:
		if have.has(c):
			out.append(c)
	for c: Variant in have:
		if not out.has(c):
			out.append(c)
	return out


func _first_category() -> String:
	var all := _categories()
	return str(all[0]) if not all.is_empty() else ""


func _rebuild() -> void:
	if not _categories().has(category):
		category = _first_category()
	_build_tabs()
	_show_category(category)
	_signature = _current_signature()


func _build_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	for c: String in _categories():
		var tab := Button.new()
		tab.text = str(CATEGORY_TITLES.get(c, c.capitalize()))
		tab.toggle_mode = true
		tab.button_pressed = c == category
		tab.add_theme_font_size_override("font_size", 16)
		var active := c == category
		tab.add_theme_stylebox_override("normal", _box(ACCENT.darkened(0.45) if active else CARD, 18, 16, 0, Color.TRANSPARENT, 6))
		tab.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.45), 18, 16, 0, Color.TRANSPARENT, 6))
		tab.add_theme_stylebox_override("hover", _box(CARD_HOVER, 18, 16, 0, Color.TRANSPARENT, 6))
		tab.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, 18, 16, 2, ACCENT, 6))
		tab.pressed.connect(_pick_category.bind(c))
		_tabs.add_child(tab)


func _pick_category(c: String) -> void:
	category = c
	selected = ""
	_scroll.scroll_vertical = 0
	_rebuild()


func _show_category(c: String) -> void:
	category = c
	_money_label.text = "%d points" % money
	var kept_scroll := _scroll.scroll_vertical

	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()

	var first := ""
	for it: Dictionary in items:
		if str(it.get("cat", "")) != c:
			continue
		var id := str(it["id"])
		_list.add_child(_card(it))
		if first == "":
			first = id

	if selected == "" or not _rows.has(selected):
		selected = first
	_select(selected)
	_scroll.set_deferred("scroll_vertical", kept_scroll)


func _card(it: Dictionary) -> Button:
	var id := str(it["id"])
	var why: String = str(state_fn.call(it)) if state_fn.is_valid() else ""
	var price := int(it.get("price", 0))
	var poor := why == "" and price > money

	var row := Button.new()
	row.custom_minimum_size = Vector2(0.0, 72.0)
	row.focus_mode = Control.FOCUS_ALL
	row.add_theme_stylebox_override("normal", _box(CARD, 10, 0))
	row.add_theme_stylebox_override("hover", _box(CARD_HOVER, 10, 0))
	row.add_theme_stylebox_override("pressed", _box(CARD_SELECTED, 10, 0))
	row.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, 10, 0, 2, ACCENT))
	row.pressed.connect(_clicked.bind(id))

	var inside := HBoxContainer.new()
	inside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inside.offset_left = 10.0
	inside.offset_right = -14.0
	inside.add_theme_constant_override("separation", 12)
	inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(inside)

	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(112.0, 0.0)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = _picture_of(it)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.add_child(picture)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.add_child(words)
	var name_label := Label.new()
	name_label.text = str(it.get("name", id))
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(name_label)
	if why != "":
		var state := Label.new()
		state.text = why
		state.add_theme_font_size_override("font_size", 13)
		state.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		state.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(state)

	var cost := Label.new()
	cost.text = "%d" % price
	cost.add_theme_font_size_override("font_size", 20)
	cost.add_theme_color_override("font_color", BAD if poor else GOLD)
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inside.add_child(cost)

	if why != "":
		row.modulate = Color(1, 1, 1, 0.55)
	_rows[id] = row
	return row


func _picture_of(it: Dictionary) -> Texture2D:
	var weapon := str(it.get("w", ""))
	return _icons.icon_for(StringName(weapon)) if weapon != "" else null


func _clicked(id: String) -> void:
	if id == selected and visible:
		var item := _item(id)
		var why: String = str(state_fn.call(item)) if state_fn.is_valid() and not item.is_empty() else ""
		if why == "" and int(item.get("price", 0)) <= money:
			buy_requested.emit(id)
			return
	_select(id)


func _item(id: String) -> Dictionary:
	for it: Dictionary in items:
		if str(it["id"]) == id:
			return it
	return {}


func _select(id: String) -> void:
	selected = id
	for rid: String in _rows:
		var row := _rows[rid] as Button
		row.add_theme_stylebox_override("normal", _box(CARD_SELECTED if rid == id else CARD, 10, 0, 2 if rid == id else 0, ACCENT))

	var it := _item(id)
	if it.is_empty():
		_picture.texture = null
		_title.text = ""
		_kind.text = ""
		_body.text = ""
		_price.text = ""
		_buy.disabled = true
		return

	var why: String = str(state_fn.call(it)) if state_fn.is_valid() else ""
	var price := int(it.get("price", 0))
	_picture.texture = _picture_of(it)
	_title.text = str(it.get("name", id))
	_kind.text = str(CATEGORY_TITLES.get(str(it.get("cat", "")), "")).to_upper()
	_body.text = str(it.get("desc", ""))
	_price.text = "%d points" % price
	_price.add_theme_color_override("font_color", GOLD if price <= money else BAD)
	_buy.disabled = why != "" or price > money
	_buy.text = why if why != "" else ("Buy" if price <= money else "Not enough points")


func _box(color: Color, radius: int, pad: int, border: int = 0, border_color: Color = Color.TRANSPARENT, pad_v: int = -1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(pad)
	if pad_v >= 0:
		box.content_margin_top = pad_v
		box.content_margin_bottom = pad_v
	if border > 0:
		box.set_border_width_all(border)
		box.border_color = border_color
	return box
