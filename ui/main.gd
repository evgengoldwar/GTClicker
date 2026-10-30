extends Control
## Главный экран (раздел 13): карта острова в центре, все системы — панели поверх неё.
## Вкладки скрыты, пока не открыты (онбординг, раздел 2); горячие клавиши 1–7, F12 — debug.

const TABS: Array[Dictionary] = [
	{"id": "map", "icon": "map", "feature": ""},
	{"id": "storage", "icon": "storage", "feature": "tab_storage"},
	{"id": "stations", "icon": "stations", "feature": "tab_stations"},
	{"id": "quests", "icon": "quest", "feature": "tab_quests"},
	{"id": "anvil", "icon": "anvil", "feature": "tab_anvil"},
	{"id": "power", "icon": "power", "feature": "tab_power"},
	{"id": "settings", "icon": "settings", "feature": ""},
]

var map_view := MapView.new()
var mining := MiningPanel.new()
var _panel_host := PanelContainer.new()
var _panels: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _badges: Dictionary = {}
var _current := "map"
var _modal_layer := Control.new()
var _toasts := UIKit.vbox(6)
var _float_layer := Control.new()
var _hint := UIKit.label("", 16, UITheme.WARN)
# Верхняя панель
var _era_label := UIKit.label("", 16)
var _clock_icon: TextureRect
var _clock_label := UIKit.label("", 14)
var _steam_bar := UIKit.bar(0.0, Color("#9ad0ff"), 12)
var _steam_label := UIKit.label("", 13)
var _eu_bar := UIKit.bar(0.0, UITheme.ACCENT, 12)
var _eu_label := UIKit.label("", 13)
var _deficit_icon: TextureRect
var _top_timer := 0.0
var _last_new_recipes := 0


func _ready() -> void:
	theme = UITheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := UIKit.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_build_top_bar())
	var body := UIKit.hbox(0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_build_rail())
	var center := Control.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(map_view)
	map_view.node_selected.connect(_on_node_selected)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_hint)
	mining.visible = false
	mining.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	mining.offset_top = -190
	mining.offset_left = 10
	mining.offset_right = -10
	mining.offset_bottom = -10
	mining.floating_text.connect(spawn_float)
	center.add_child(mining)
	_panel_host.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_panel_host.anchor_left = 0.36
	_panel_host.offset_left = 0
	_panel_host.offset_top = 8
	_panel_host.offset_bottom = -8
	_panel_host.offset_right = -8
	_panel_host.visible = false
	center.add_child(_panel_host)
	_build_panels()
	_float_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float_layer)
	# Уведомления — слева над картой, чтобы не закрывать панели справа.
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_toasts.offset_left = 172
	_toasts.offset_top = 56
	_toasts.offset_right = 540
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_layer)
	_connect_events()
	_start_game()


func _start_game() -> void:
	if Save.has_save() and Save.load_game(true):
		ReportWindows.offline(_modal_layer, Save.last_report)
	else:
		Save.new_game()
	_refresh_tabs()
	if Progress.demo_finished:
		toast(tr("DEMO_ALREADY"), "info")


# --- Построение -----------------------------------------------------------------------------

func _build_top_bar() -> Control:
	var bar := UITheme.riveted_panel()
	var h := UIKit.hbox(14)
	bar.add_child(h)
	h.add_child(UIKit.label("GregClicker", 18, UITheme.ACCENT))
	h.add_child(_era_label)
	_clock_icon = Icons.rect("sun", UITheme.WARN, 16)
	h.add_child(_clock_icon)
	h.add_child(_clock_label)
	h.add_child(UIKit.spacer())
	h.add_child(Icons.rect("steam", Color("#9ad0ff"), 16))
	_steam_bar.custom_minimum_size.x = 120
	h.add_child(_steam_bar)
	h.add_child(_steam_label)
	h.add_child(Icons.rect("bolt", UITheme.ACCENT, 16))
	_eu_bar.custom_minimum_size.x = 120
	h.add_child(_eu_bar)
	h.add_child(_eu_label)
	_deficit_icon = Icons.rect("warning", UITheme.BAD, 16)
	_deficit_icon.tooltip_text = tr("UI_DEFICIT_ICON")
	_deficit_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(_deficit_icon)
	return bar


func _build_rail() -> Control:
	var rail := PanelContainer.new()
	var v := UIKit.vbox(4)
	rail.add_child(v)
	for i in TABS.size():
		var t: Dictionary = TABS[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = Icons.shape(t["icon"])
		b.text = "%d  %s" % [i + 1, tr("TAB_" + str(t["id"]).to_upper())]
		var id: String = t["id"]
		b.pressed.connect(func() -> void: open_tab(id))
		var badge := Icons.rect("star", UITheme.WARN, 16)
		badge.position = Vector2(130, 4)
		badge.visible = false
		b.add_child(badge)
		_badges[id] = badge
		_tab_buttons[id] = b
		v.add_child(b)
	return rail


func _build_panels() -> void:
	var storage := StoragePanel.new()
	storage.lookup_requested.connect(func(id: String) -> void: LookupWindow.open(_modal_layer, id))
	storage.hand_craft_requested.connect(func() -> void: StationWindow.open(_modal_layer, "hand"))
	var stations := StationsPanel.new()
	stations.station_opened.connect(func(sid: String) -> void: StationWindow.open(_modal_layer, sid))
	var quests := QuestsPanel.new()
	quests.reward_claimed.connect(_on_reward_claimed)
	var settings := SettingsPanel.new()
	settings.modal_host = _modal_layer
	settings.language_changed.connect(func() -> void: get_tree().reload_current_scene())
	_panels = {"storage": storage, "stations": stations, "quests": quests, "anvil": AnvilPanel.new(),
		"power": PowerPanel.new(), "settings": settings}
	for id: String in _panels:
		var p: Control = _panels[id]
		p.visible = false
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_panel_host.add_child(p)


func _connect_events() -> void:
	Events.feature_unlocked.connect(_on_feature_unlocked)
	Events.state_reset.connect(_refresh_tabs)
	Events.notify.connect(toast)
	Events.quest_completed.connect(func(qid: String) -> void:
		toast(tr("TOAST_QUEST_DONE") % tr(Registry.quest(qid).title_key()), "good"))
	Events.era_changed.connect(func(era: int) -> void:
		Sfx.play("unlock")
		toast(tr("TOAST_ERA") % tr("ERA_%d" % era), "good"))
	Events.tool_broken.connect(func(_t: String, item: String) -> void:
		Sfx.play("tool_break")
		toast(tr("TOAST_TOOL_BROKEN") % Registry.item_name(item), "bad"))
	Events.tool_durability_warning.connect(func(type: String, frac: float) -> void:
		toast(tr("TOAST_TOOL_WORN") % [Registry.item_name(Tools.equipped(type)), roundi(frac * 100)], "warn"))
	Events.power_deficit.connect(_on_deficit)
	Events.demo_finished.connect(func() -> void: ReportWindows.demo_end(_modal_layer))
	Events.item_discovered.connect(func(_id: String) -> void: _check_new_recipes())


# --- Вкладки --------------------------------------------------------------------------------

func open_tab(id: String) -> void:
	var tab := _tab_def(id)
	if tab.is_empty() or (not str(tab["feature"]).is_empty() and not Progress.has_feature(tab["feature"])):
		return
	_current = id if _current != id or id == "map" else "map"
	for pid: String in _panels:
		(_panels[pid] as Control).visible = pid == _current
	_panel_host.visible = _current != "map"
	for tid: String in _tab_buttons:
		var b: Button = _tab_buttons[tid]
		b.add_theme_stylebox_override("normal", UITheme.box(UITheme.PANEL_LIGHT, UITheme.ACCENT if tid == _current else UITheme.EDGE))


func _tab_def(id: String) -> Dictionary:
	for t in TABS:
		if t["id"] == id:
			return t
	return {}


func _refresh_tabs() -> void:
	for t in TABS:
		var f: String = t["feature"]
		(_tab_buttons[t["id"]] as Button).visible = f.is_empty() or Progress.has_feature(f)
	open_tab("map")
	map_view.select("")
	mining.show_node("")
	_update_hint()


func _on_feature_unlocked(feature: String) -> void:
	Sfx.play("unlock")
	var hint_key := ""
	for f: Dictionary in Registry.features:
		if f["id"] == feature:
			hint_key = f.get("hint", "")
	if not hint_key.is_empty():
		toast(tr(hint_key), "good")
	for t in TABS:
		if t["feature"] == feature:
			var b: Button = _tab_buttons[t["id"]]
			b.visible = true
			if not Settings.reduce_animations:
				var tw := b.create_tween().set_loops(3)
				tw.tween_property(b, "modulate", Color(1.8, 1.5, 0.6), 0.25)
				tw.tween_property(b, "modulate", Color.WHITE, 0.25)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		DebugPanel.open(_modal_layer, func(r: Dictionary) -> void: ReportWindows.offline(_modal_layer, r))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_7 and _modal_layer.get_child_count() == 0:
			open_tab(TABS[k - KEY_1]["id"])
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE:
			if _modal_layer.get_child_count() > 0:
				_modal_layer.get_child(_modal_layer.get_child_count() - 1).queue_free()
			elif _current != "map":
				open_tab("map")
			else:
				_on_node_selected("")
			get_viewport().set_input_as_handled()


# --- Карта и добыча ---------------------------------------------------------------------------

func _on_node_selected(nid: String) -> void:
	if nid == mining.node_id:
		nid = ""
	map_view.select(nid)
	mining.show_node(nid)
	if not nid.is_empty() and _current != "map":
		open_tab("map")
	_update_hint()


func _update_hint() -> void:
	_hint.visible = false
	if Storage.total_obtained.has("log") and int(Storage.total_obtained["log"]) >= 3:
		return
	_hint.visible = true
	if mining.node_id.is_empty():
		_hint.text = tr("HINT_CLICK_TREE")
		_hint.position = map_view.node_screen_position("tree") - map_view.get_global_rect().position + Vector2(-70, -72)
	else:
		_hint.text = tr("HINT_CLICK_BLOCK")
		_hint.position = Vector2(160, map_view.size.y - 230)


# --- Уведомления и анимации ---------------------------------------------------------------------

func toast(text: String, kind: String = "info") -> void:
	for t in _toasts.get_children():
		if t.has_meta("text") and t.get_meta("text") == text:
			return
	var colors := {"good": UITheme.GOOD, "bad": UITheme.BAD, "warn": UITheme.WARN, "info": UITheme.EDGE}
	var icons := {"good": "check", "bad": "cross", "warn": "warning", "info": "star"}
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL, colors.get(kind, UITheme.EDGE)))
	var h := UIKit.hbox()
	h.add_child(Icons.rect(icons.get(kind, "star"), colors.get(kind, UITheme.TEXT), 16))
	var l := UIKit.label(text, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 320
	h.add_child(l)
	p.add_child(h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_meta("text", text)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 5:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func spawn_float(text: String, at: Vector2, color: Color) -> void:
	var l := UIKit.label(text, 16, color)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.position = at - Vector2(40, 0)
	_float_layer.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", at.y - 60, 0.9 if not Settings.reduce_animations else 0.3)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9)
	tw.tween_callback(l.queue_free)


func _on_reward_claimed(qid: String, from: Vector2) -> void:
	var rw := Registry.quest(qid).rewards
	var target := (_tab_buttons["storage"] as Button).get_global_rect().get_center()
	var items: Array = rw.get("items", [])
	var i := 0
	for e: Dictionary in items:
		var icon := Icons.item_rect(e["item"], 32)
		icon.position = from + Vector2(i * 36, 0)
		_float_layer.add_child(icon)
		var tw := icon.create_tween()
		tw.tween_property(icon, "scale", Vector2(1.6, 1.6), 0.15)
		tw.tween_property(icon, "scale", Vector2.ONE, 0.15)
		tw.tween_property(icon, "position", target, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(icon.queue_free)
		spawn_float("+%s %s" % [UIKit.amount(e["item"], int(e["n"])), Registry.item_name(e["item"])],
			from + Vector2(0, -20 - i * 18), UITheme.GOOD)
		i += 1
	toast(tr("TOAST_REWARD") % tr(Registry.quest(qid).title_key()), "good")


func _on_deficit(ratio: float) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL, UITheme.BAD))
	var h := UIKit.hbox()
	h.add_child(UIKit.status_icon("warn", 16))
	h.add_child(UIKit.label(tr("TOAST_DEFICIT") % roundi(ratio * 100), 13))
	h.add_child(UIKit.button(tr("UI_SHOW_CONSUMERS"), func() -> void:
		open_tab("power")
		p.queue_free()))
	p.add_child(h)
	_toasts.add_child(p)
	var tw := p.create_tween()
	tw.tween_interval(7.0)
	tw.tween_callback(p.queue_free)


func _check_new_recipes() -> void:
	var n := 0
	for sid in Registry.station_order:
		n += Stations.new_recipes(sid).size()
	if n > _last_new_recipes and Progress.has_feature("tab_stations"):
		toast(tr("TOAST_NEW_RECIPES"), "info")
	_last_new_recipes = n


func _process(delta: float) -> void:
	_top_timer += delta
	if _top_timer < 0.2:
		return
	_top_timer = 0.0
	_era_label.text = tr("ERA_%d" % Progress.era)
	_era_label.add_theme_color_override("font_color", UITheme.era_color(Progress.era))
	var day := GameClock.is_day()
	_clock_icon.texture = Icons.shape("sun" if day else "moon")
	var phase := GameClock.day_phase()
	var minutes := floori(phase * 24.0 * 60.0)
	_clock_label.text = tr("UI_CLOCK") % [GameClock.day_index() + 1, floori(minutes / 60.0), minutes % 60]
	var sc := Power.steam_capacity()
	_steam_bar.value = Power.steam_buffer / sc if sc > 0.0 else 0.0
	_steam_label.text = "+%s / −%s %s" % [NumFormat.format(Power.steam_gen), NumFormat.format(Power.steam_use), tr("UNIT_STEAM")]
	var bc := Power.battery_capacity()
	_eu_bar.value = Power.battery_charge / bc if bc > 0.0 else 0.0
	_eu_label.text = "+%s / −%s EU/t" % [NumFormat.format(Power.eu_gen), NumFormat.format(Power.eu_use)]
	_deficit_icon.visible = minf(Power.r_steam, Power.r_eu) < 0.999
	var claim := Quests.claimable().size()
	(_badges["quests"] as Control).visible = claim > 0
	var fresh := false
	for sid in Registry.station_order:
		fresh = fresh or not Stations.new_recipes(sid).is_empty()
	(_badges["stations"] as Control).visible = fresh
	if _hint.visible:
		_update_hint()
