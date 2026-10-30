class_name StoragePanel
extends VBoxContainer
## Хранилище в стиле AE (раздел 3): сетка ячеек 48×48 с числом в правом нижнем углу,
## поиск (в т.ч. #тег и @измерение), сортировка, фильтр «предметы / жидкости»,
## тултип с точным числом и доходом, ПКМ — «где добыть / где используется».

signal lookup_requested(item_id: String)
signal hand_craft_requested()

const CELL := 48

var _search := LineEdit.new()
var _sort := OptionButton.new()
var _filter := OptionButton.new()
var _grid := GridContainer.new()
var _hand := Button.new()
var _cells: Dictionary = {}   # item id -> PanelContainer
var _dirty := true
var _timer := 0.0


func _ready() -> void:
	var head := UIKit.hbox()
	head.add_child(UIKit.label(tr("TAB_STORAGE"), 20, UITheme.ACCENT))
	head.add_child(UIKit.spacer())
	_hand.text = tr("UI_HAND_CRAFT")
	_hand.pressed.connect(func() -> void: hand_craft_requested.emit())
	head.add_child(_hand)
	add_child(head)
	var bar := UIKit.hbox()
	_search.placeholder_text = tr("UI_SEARCH_HINT")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _dirty = true)
	bar.add_child(_search)
	for k in ["SORT_NAME", "SORT_COUNT", "SORT_INCOME", "SORT_ERA"]:
		_sort.add_item(tr(k))
	_sort.item_selected.connect(func(_i: int) -> void: _dirty = true)
	bar.add_child(_sort)
	for k in ["FILTER_ALL", "FILTER_ITEMS", "FILTER_LIQUIDS"]:
		_filter.add_item(tr(k))
	_filter.item_selected.connect(func(_i: int) -> void: _dirty = true)
	bar.add_child(_filter)
	add_child(bar)
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	add_child(UIKit.scroll(_grid))
	resized.connect(func() -> void: _grid.columns = maxi(1, floori((size.x - 20) / (CELL + 4))))
	Storage.changed.connect(_on_changed)
	Events.state_reset.connect(func() -> void: _dirty = true)
	Events.feature_unlocked.connect(func(_f: String) -> void: _hand.visible = Progress.has_feature("hand_craft"))
	_hand.visible = Progress.has_feature("hand_craft")


func _on_changed(id: String) -> void:
	if not _cells.has(id) or Storage.count(id) <= 0:
		_dirty = true
	else:
		_update_cell(id)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_timer += delta
	if _timer < 0.1:
		return
	_timer = 0.0
	if _dirty:
		_rebuild()


func matches(id: String, query: String) -> bool:
	var it := Registry.item(id)
	var q := query.strip_edges().to_lower()
	if _filter.selected == 1 and it.is_liquid() or _filter.selected == 2 and not it.is_liquid():
		return false
	if q.is_empty():
		return true
	if q.begins_with("#"):
		for t in it.tags:
			if t.begins_with(q.substr(1)):
				return true
		return false
	if q.begins_with("@"):
		return Registry.dropped_by.has(id) and (tr("DIM_OVERWORLD").to_lower().begins_with(q.substr(1))
			or "overworld".begins_with(q.substr(1)))
	return Registry.item_name(id).to_lower().contains(q) or id.contains(q)


func _rebuild() -> void:
	_dirty = false
	var ids: Array[String] = []
	for id: String in Storage.counts:
		if Storage.count(id) > 0 and Registry.has_item(id) and matches(id, _search.text):
			ids.append(id)
	match _sort.selected:
		0:
			ids.sort_custom(func(a: String, b: String) -> bool: return Registry.item_name(a) < Registry.item_name(b))
		1:
			ids.sort_custom(func(a: String, b: String) -> bool: return Storage.count(a) > Storage.count(b))
		2:
			ids.sort_custom(func(a: String, b: String) -> bool: return Storage.income(a) > Storage.income(b))
		3:
			ids.sort_custom(func(a: String, b: String) -> bool:
				return Registry.item(a).era > Registry.item(b).era if Registry.item(a).era != Registry.item(b).era \
					else Registry.item_name(a) < Registry.item_name(b))
	UIKit.clear(_grid)
	_cells.clear()
	for id in ids:
		var cell := _make_cell(id)
		_cells[id] = cell
		_grid.add_child(cell)


func _make_cell(id: String) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(CELL, CELL)
	cell.add_theme_stylebox_override("panel", UITheme.box(UITheme.BG, UITheme.era_color(Registry.item(id).era).darkened(0.3), 1, 2))
	var icon := Icons.item_rect(id, 32)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_child(icon)
	var count := UIKit.label("", 12)
	count.name = "Count"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.add_theme_constant_override("outline_size", 4)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	cell.add_child(count)
	cell.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			lookup_requested.emit(id))
	cell.mouse_entered.connect(func() -> void: cell.tooltip_text = UIKit.item_tooltip(id))
	_set_count(cell, id)
	return cell


func _update_cell(id: String) -> void:
	_set_count(_cells[id], id)


func _set_count(cell: PanelContainer, id: String) -> void:
	var l: Label = cell.get_node("Count")
	l.text = NumFormat.format(Storage.count(id))
	cell.tooltip_text = UIKit.item_tooltip(id)
