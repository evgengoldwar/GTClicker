class_name StationWindow
extends RefCounted
## Окно станции (раздел 5): слева список рецептов с поиском («???» для неоткрытых),
## справа — входы «нужно / есть», выход, время, энергия, количество 1 / 10 / макс и «Крафт»
## (Shift = ×10, Ctrl = максимум). Ниже — очередь, апгрейды и сборка мультиблока.

var station_id := ""
var root: VBoxContainer
var _list := UIKit.vbox(2)
var _details := UIKit.vbox(6)
var _search := LineEdit.new()
var _selected := ""
var _qty := 1
var _timer: Timer


static func open(parent: Control, sid: String) -> StationWindow:
	var w := StationWindow.new()
	w.station_id = sid
	w._build(parent)
	w.root.set_meta("window", w)  # окно живёт, пока жив его узел
	return w


func _build(parent: Control) -> void:
	root = UIKit.modal(parent, Registry.station_name(station_id), Vector2(940, 600))
	var body := UIKit.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var left := UIKit.vbox(4)
	left.custom_minimum_size = Vector2(330, 520)
	_search.placeholder_text = tr_("UI_SEARCH")
	_search.text_changed.connect(func(_t: String) -> void: _rebuild_list())
	left.add_child(_search)
	left.add_child(UIKit.scroll(_list))
	body.add_child(left)
	var right_scroll := UIKit.scroll(_details)
	right_scroll.custom_minimum_size = Vector2(560, 520)
	body.add_child(right_scroll)
	_timer = Timer.new()
	_timer.wait_time = 0.25
	_timer.autostart = true
	_timer.timeout.connect(_refresh_live)
	root.add_child(_timer)
	Stations.mark_seen(station_id)
	_rebuild_list()
	var known := _known_recipes()
	_select(known[0] if not known.is_empty() else "")


static func tr_(key: String) -> String:
	return TranslationServer.translate(key)


func _known_recipes() -> Array[String]:
	var out: Array[String] = []
	for rid in Registry.recipes_for_station(station_id):
		if Stations.is_recipe_known(rid):
			out.append(rid)
	return out


func _rebuild_list() -> void:
	UIKit.clear(_list)
	var q := _search.text.strip_edges().to_lower()
	var unknown := 0
	for rid in Registry.recipes_for_station(station_id):
		if not Stations.is_recipe_known(rid):
			unknown += 1
			continue
		var out := Registry.recipe(rid).main_output()
		if not q.is_empty() and not Registry.item_name(out).to_lower().contains(q):
			continue
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = Registry.item_name(out)
		b.icon = Icons.shape(Registry.item(out).icon)
		b.expand_icon = false
		b.add_theme_color_override("icon_normal_color", Registry.item(out).color)
		b.add_theme_color_override("icon_hover_color", Registry.item(out).color)
		b.add_theme_color_override("icon_pressed_color", Registry.item(out).color)
		if rid == _selected:
			b.add_theme_stylebox_override("normal", UITheme.box(UITheme.PANEL_LIGHT, UITheme.ACCENT))
		if Stations.max_craftable(rid) <= 0:
			b.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		b.pressed.connect(func() -> void: _select(rid))
		_list.add_child(b)
	# Неоткрытые рецепты: «???» с подсказкой — это манит исследовать.
	for rid in Registry.recipes_for_station(station_id):
		if Stations.is_recipe_known(rid):
			continue
		var l := UIKit.label("???  " + tr_("UI_UNKNOWN_INPUTS") % Stations.unknown_inputs(rid), 13, UITheme.TEXT_DIM)
		l.tooltip_text = tr_("UI_UNKNOWN_HINT")
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_list.add_child(l)
	if unknown == 0 and _list.get_child_count() == 0:
		_list.add_child(UIKit.label(tr_("UI_NOTHING"), 13, UITheme.TEXT_DIM))


func _select(rid: String) -> void:
	_selected = rid
	_rebuild_list()
	_rebuild_details()


func _rebuild_details() -> void:
	UIKit.clear(_details)
	var s := Registry.station(station_id)
	if s.is_multiblock() and not Stations.is_available(station_id):
		_build_multiblock()
		return
	if not _selected.is_empty():
		_build_recipe(Registry.recipe(_selected))
	_build_queue()
	_build_upgrades()
	if s.is_multiblock():
		_details.add_child(UIKit.label(tr_("UI_HEAT") % Stations.heat(station_id), 13, UITheme.TEXT_DIM))


func _build_recipe(r: RecipeDef) -> void:
	_details.add_child(UIKit.label(tr_("UI_INPUTS"), 15, UITheme.ACCENT))
	for inp in r.inputs:
		var cands := Registry.input_candidates(inp)
		var have := 0
		for c in cands:
			have += Tools.available(c)
		var line := UIKit.item_line(cands[0], int(inp["n"]) * _qty, have)
		if inp.has("tag"):
			line.add_child(UIKit.label("(#%s)" % inp["tag"], 12, UITheme.TEXT_DIM))
		_details.add_child(line)
	_details.add_child(UIKit.label(tr_("UI_OUTPUTS"), 15, UITheme.ACCENT))
	for o in r.outputs:
		var line := UIKit.item_line(o["item"], int(o["n"]) * _qty)
		if float(o["chance"]) < 1.0:
			line.add_child(UIKit.label("%d%%" % roundi(float(o["chance"]) * 100), 12, UITheme.TEXT_DIM))
		_details.add_child(line)
	var sec := Stations.craft_seconds(station_id, r)
	var info := tr_("UI_TIME") % ("%.1f" % sec)
	if r.eu > 0.0:
		info += "   " + tr_("UI_ENERGY") % [NumFormat.format(Stations.craft_eut(station_id, r)),
			tr_("UNIT_STEAM") if Registry.station(station_id).energy == "steam" else "EU/t"]
		var o := Stations.overclocks(station_id, r)
		if o > 0:
			info += "   " + tr_("UI_OVERCLOCK") % o
	if r.heat > 0:
		info += "   " + tr_("UI_NEEDS_HEAT") % r.heat
	_details.add_child(UIKit.label(info, 13, UITheme.TEXT_DIM))
	var qty := UIKit.hbox()
	for n in [1, 10]:
		var b := UIKit.button("×%d" % n, func() -> void:
			_qty = n
			_rebuild_details())
		if _qty == n:
			b.add_theme_stylebox_override("normal", UITheme.box(UITheme.PANEL_LIGHT, UITheme.ACCENT))
		qty.add_child(b)
	qty.add_child(UIKit.button(tr_("UI_MAX") + " (%d)" % Stations.max_craftable(r.id), func() -> void:
		_qty = maxi(1, Stations.max_craftable(r.id))
		_rebuild_details()))
	var craft := Button.new()
	craft.text = tr_("UI_CRAFT")
	craft.custom_minimum_size.x = 140
	var reason := Stations.block_reason(r.id)
	craft.disabled = not reason.is_empty() or Stations.max_craftable(r.id) <= 0
	craft.tooltip_text = tr_(reason) if not reason.is_empty() else tr_("UI_CRAFT_HINT")
	craft.pressed.connect(func() -> void:
		var n := _qty
		if Input.is_key_pressed(KEY_SHIFT):
			n = 10
		if Input.is_key_pressed(KEY_CTRL):
			n = Stations.max_craftable(r.id)
		n = mini(n, Stations.max_craftable(r.id))
		Sfx.play("click" if Stations.enqueue(r.id, n) else "error")
		_rebuild_details()
		_rebuild_list())
	qty.add_child(craft)
	_details.add_child(qty)


func _build_queue() -> void:
	var line := UIKit.hbox()
	var bar := UIKit.bar(Stations.progress_fraction(station_id), UITheme.ACCENT, 16)
	bar.name = "Progress"
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(bar)
	var q := UIKit.label(tr_("UI_QUEUE") % Stations.queued_count(station_id), 13)
	q.name = "QueueLabel"
	line.add_child(q)
	line.add_child(UIKit.button(tr_("UI_CANCEL_QUEUE"), func() -> void:
		Stations.cancel_queue(station_id)
		_rebuild_details()))
	_details.add_child(line)


func _build_upgrades() -> void:
	_details.add_child(UIKit.label(tr_("UI_UPGRADES"), 15, UITheme.ACCENT))
	for kind in ["speed", "efficiency"]:
		if kind == "efficiency" and not Registry.station(station_id).uses_energy():
			continue
		var h := UIKit.hbox()
		var lvl := Stations.upgrade_level(station_id, kind)
		h.add_child(UIKit.label(tr_("UPGRADE_" + kind.to_upper()) % [lvl, Stations.upgrade_max(kind)], 14))
		h.add_child(UIKit.spacer())
		var cost := Stations.upgrade_cost(station_id, kind)
		var cost_text: Array[String] = []
		for id: String in cost:
			cost_text.append("%s ×%s" % [Registry.item_name(id), NumFormat.format(cost[id])])
		var b := UIKit.button(tr_("UI_BUY") + ": " + ", ".join(cost_text), func() -> void:
			Sfx.play("unlock" if Stations.buy_upgrade(station_id, kind) else "error")
			_rebuild_details())
		b.disabled = not Stations.can_upgrade(station_id, kind) or not Storage.has_all(cost)
		h.add_child(b)
		_details.add_child(h)


## Экран сборки мультиблока: список деталей с прогрессом (упрощение силуэта из документа).
func _build_multiblock() -> void:
	var s := Registry.station(station_id)
	_details.add_child(UIKit.label(tr_("UI_MULTIBLOCK"), 16, UITheme.ACCENT))
	_details.add_child(UIKit.bar(Stations.build_progress(station_id), UITheme.GOOD, 18))
	for p: Dictionary in s.multiblock["parts"]:
		var installed := Stations.build_installed(station_id, p["item"])
		var h := UIKit.hbox()
		h.add_child(Icons.item_rect(p["item"], 32))
		h.add_child(UIKit.label("%s  %d / %d" % [Registry.item_name(p["item"]), installed, p["n"]], 14,
			UITheme.GOOD if installed >= int(p["n"]) else UITheme.TEXT))
		h.add_child(UIKit.spacer())
		var b := UIKit.button(tr_("UI_INSTALL") + " (%s)" % NumFormat.format(Storage.count(p["item"])), func() -> void:
			Sfx.play("click" if Stations.install_part(station_id, p["item"]) > 0 else "error")
			_rebuild_details())
		b.disabled = installed >= int(p["n"]) or Storage.count(p["item"]) <= 0
		h.add_child(b)
		_details.add_child(h)


func _refresh_live() -> void:
	if not is_instance_valid(root):
		return
	var bar := root.find_child("Progress", true, false) as ProgressBar
	if bar != null:
		bar.value = Stations.progress_fraction(station_id)
	var q := root.find_child("QueueLabel", true, false) as Label
	if q != null:
		q.text = tr_("UI_QUEUE") % Stations.queued_count(station_id)
