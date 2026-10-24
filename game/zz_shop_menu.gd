extends PanelContainer

## The trader's menu: tabs by category, a list of what is for sale with its price, a side panel with what the item does, and the money you hold. Mouse, keyboard and gamepad (every row is a focusable button). It only shows and asks; the server prices and sells ([ZzShop]).

signal buy_requested(item_id: String)
signal close_requested()

const CATEGORY_TITLES := {"weapons": "Weapons", "grenades": "Grenades", "ammo": "Ammo", "supplies": "Supplies", "entities": "Deployables"}
const CATEGORY_ORDER: Array = ["weapons", "grenades", "ammo", "supplies", "entities"]

## items: the server's list. money: points held. state_fn(item) returns "" or why it is not buyable ("Owned", "Full").
var items: Array = []
var money: int = 0
var state_fn: Callable = Callable()
var category: String = "weapons"
var selected: String = ""

var _money_label: Label = null
var _tabs: HBoxContainer = null
var _list: VBoxContainer = null
var _title: Label = null
var _body: Label = null
var _price: Label = null
var _buy: Button = null
var _rows: Dictionary = {}


func _init() -> void:
	name = "ShopMenu"
	var theme_source := DotUiTheme.dark()
	theme = theme_source.build(1.0)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(860.0, 500.0)
	offset_left = -430.0
	offset_right = 430.0
	offset_top = -250.0
	offset_bottom = 250.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var head := HBoxContainer.new()
	column.add_child(head)
	var heading := Label.new()
	heading.text = "TRADER"
	heading.add_theme_font_size_override("font_size", 26)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 26)
	_money_label.add_theme_color_override("font_color", Color(0.98, 0.82, 0.3))
	head.add_child(_money_label)

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	column.add_child(_tabs)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	column.add_child(split)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(300.0, 0.0)
	detail.add_theme_constant_override("separation", 8)
	split.add_child(detail)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(_body)
	_price = Label.new()
	_price.add_theme_font_size_override("font_size", 22)
	detail.add_child(_price)
	_buy = Button.new()
	_buy.text = "Buy"
	_buy.custom_minimum_size = Vector2(0.0, 44.0)
	_buy.pressed.connect(func() -> void:
		if selected != "":
			buy_requested.emit(selected))
	detail.add_child(_buy)

	var foot := Label.new()
	foot.text = "Esc closes. Walk away and it closes itself."
	foot.add_theme_font_size_override("font_size", 13)
	foot.modulate = Color(1, 1, 1, 0.6)
	column.add_child(foot)


## Opens on [param p_items] with [param p_money] held.
func open(p_items: Array, p_money: int, p_state_fn: Callable) -> void:
	items = p_items
	money = p_money
	state_fn = p_state_fn
	visible = true
	_build_tabs()
	_show_category(category if _categories().has(category) else _first_category())
	grab_focus_on_first()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## Redraws prices and states without losing the selection (a purchase, a new balance).
func refresh(p_items: Array, p_money: int) -> void:
	items = p_items
	money = p_money
	if visible:
		_build_tabs()
		_show_category(category if _categories().has(category) else _first_category())


func grab_focus_on_first() -> void:
	if _list.get_child_count() > 0 and _list.get_child(0) is Control:
		(_list.get_child(0) as Control).grab_focus()


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


func _build_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	for c: String in _categories():
		var tab := Button.new()
		tab.text = str(CATEGORY_TITLES.get(c, c.capitalize()))
		tab.toggle_mode = true
		tab.button_pressed = c == category
		tab.pressed.connect(_show_category.bind(c))
		_tabs.add_child(tab)


func _show_category(c: String) -> void:
	category = c
	_money_label.text = "%d points" % money
	var i := 0
	for tab in _tabs.get_children():
		(tab as Button).button_pressed = i < _categories().size() and _categories()[i] == c
		i += 1
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	var first := ""
	for it: Dictionary in items:
		if str(it.get("cat", "")) != c:
			continue
		var id := str(it["id"])
		var why: String = str(state_fn.call(it)) if state_fn.is_valid() else ""
		var row := Button.new()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(0.0, 38.0)
		var price := int(it.get("price", 0))
		row.text = "%s    %s" % [str(it.get("name", id)), why if why != "" else "%d" % price]
		if why == "" and price > money:
			row.modulate = Color(1.0, 0.55, 0.5)
		elif why != "":
			row.modulate = Color(1, 1, 1, 0.5)
		row.pressed.connect(_select.bind(id))
		_list.add_child(row)
		_rows[id] = row
		if first == "":
			first = id
	if selected == "" or not _rows.has(selected):
		selected = first
	_select(selected)


func _select(id: String) -> void:
	selected = id
	for rid: String in _rows:
		(_rows[rid] as Button).flat = rid != id
	for it: Dictionary in items:
		if str(it["id"]) == id:
			var why: String = str(state_fn.call(it)) if state_fn.is_valid() else ""
			var price := int(it.get("price", 0))
			_title.text = str(it.get("name", id))
			_body.text = str(it.get("desc", ""))
			_price.text = "%d points" % price
			_price.add_theme_color_override("font_color", Color(0.98, 0.82, 0.3) if price <= money else Color(1.0, 0.45, 0.4))
			_buy.disabled = why != "" or price > money
			_buy.text = why if why != "" else ("Buy" if price <= money else "Not enough points")
			return
	_title.text = ""
	_body.text = ""
	_price.text = ""
	_buy.disabled = true
