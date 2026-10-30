class_name StationsPanel
extends VBoxContainer
## Экран «Станции»: карточки типов станций с группой экземпляров («EBF ×1 · 1801 K · LV»),
## прогрессом, очередью и статусом. Клик по полосе прогресса работающей станции ускоряет крафт.

signal station_opened(station_id: String)

var _grid := GridContainer.new()
var _cards: Dictionary = {}
var _timer := 0.0


func _ready() -> void:
	add_child(UIKit.label(tr("TAB_STATIONS"), 20, UITheme.ACCENT))
	add_child(UIKit.label(tr("UI_STATIONS_HINT"), 13, UITheme.TEXT_DIM))
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	add_child(UIKit.scroll(_grid))
	resized.connect(func() -> void: _grid.columns = maxi(1, floori(size.x / 270.0)))
	Events.station_installed.connect(func(_s: String) -> void: rebuild())
	Events.state_reset.connect(rebuild)
	Events.item_discovered.connect(func(_i: String) -> void: rebuild())
	visibility_changed.connect(func() -> void: if is_visible_in_tree(): _update())
	rebuild()


func visible_stations() -> Array[String]:
	var out: Array[String] = []
	for sid in Registry.station_order:
		var s := Registry.station(sid)
		if s.builtin:
			if Progress.has_feature("hand_craft"):
				out.append(sid)
		elif Stations.is_available(sid):
			out.append(sid)
		elif s.is_multiblock() and Storage.is_discovered(s.multiblock["parts"][0]["item"]):
			out.append(sid)
	return out


func rebuild() -> void:
	UIKit.clear(_grid)
	_cards.clear()
	for sid in visible_stations():
		var card := _make_card(sid)
		_cards[sid] = card
		_grid.add_child(card)
	_update()


func _make_card(sid: String) -> PanelContainer:
	var s := Registry.station(sid)
	var card := UITheme.riveted_panel()
	card.custom_minimum_size = Vector2(250, 120)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var v := UIKit.vbox(4)
	card.add_child(v)
	var h := UIKit.hbox()
	h.add_child(Icons.rect(s.icon, s.color, 48))
	var info := UIKit.vbox(2)
	var name_line := UIKit.hbox(4)
	name_line.add_child(UIKit.label(Registry.station_name(sid), 15))
	var dot := Icons.rect("star", UITheme.WARN, 16)
	dot.name = "NewDot"
	dot.tooltip_text = tr("UI_NEW_RECIPES")
	name_line.add_child(dot)
	info.add_child(name_line)
	var group := UIKit.label("", 12, UITheme.TEXT_DIM)
	group.name = "Group"
	info.add_child(group)
	var status := UIKit.hbox(4)
	status.name = "Status"
	info.add_child(status)
	h.add_child(info)
	v.add_child(h)
	var bar := UIKit.bar(0.0, UITheme.ACCENT, 14)
	bar.name = "Bar"
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.tooltip_text = tr("UI_CLICK_BOOST")
	bar.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if Stations.click_boost(sid):
				Sfx.play("click")
			bar.accept_event())
	v.add_child(bar)
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			station_opened.emit(sid))
	return card


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_timer += delta
	if _timer >= 0.1:
		_timer = 0.0
		_update()


func _update() -> void:
	for sid: String in _cards:
		var card: PanelContainer = _cards[sid]
		var s := Registry.station(sid)
		var group: Label = card.find_child("Group", true, false)
		var parts: Array[String] = ["×%d" % Stations.instance_count(sid)]
		if s.is_multiblock():
			parts.append("%d K" % Stations.heat(sid))
			if not Stations.is_available(sid):
				parts = [tr("UI_BUILD_PROGRESS") % roundi(Stations.build_progress(sid) * 100)]
		if s.energy == "eu":
			parts.append(s.voltage)
		elif s.energy == "steam":
			parts.append(tr("ENERGY_STEAM"))
		var queued := Stations.queued_count(sid)
		if queued > 0:
			parts.append(tr("UI_QUEUE") % queued)
		group.text = " · ".join(parts)
		(card.find_child("Bar", true, false) as ProgressBar).value = Stations.progress_fraction(sid)
		(card.find_child("NewDot", true, false) as Control).visible = not Stations.new_recipes(sid).is_empty()
		var status: HBoxContainer = card.find_child("Status", true, false)
		var key := _status(sid)
		if status.get_meta("key", "") != key:
			status.set_meta("key", key)
			UIKit.clear(status)
			status.add_child(UIKit.status_icon(key.get_slice(":", 0), 14))
			status.add_child(UIKit.label(tr(key.get_slice(":", 1)), 12, UITheme.TEXT_DIM))


func _status(sid: String) -> String:
	var s := Registry.station(sid)
	if not Stations.is_available(sid):
		return "lock:STATUS_NOT_BUILT"
	if not Stations.is_busy(sid):
		return "idle:STATUS_IDLE"
	if Power.ratio(s.energy) <= 0.0:
		return "bad:STATUS_NO_POWER"
	if Power.ratio(s.energy) < 0.999:
		return "warn:STATUS_SLOW"
	return "ok:STATUS_WORKING"
