class_name PowerPanel
extends VBoxContainer
## Экран «Энергосеть» (раздел 6): слева генераторы с выдачей и топливом, справа потребители,
## в центре график заряда батарей и буфера пара за последние 10 минут.

var _gens := UIKit.vbox(6)
var _cons := UIKit.vbox(4)
var _summary := UIKit.label("", 14)
var _chart := Control.new()
var _timer := 0.0
var _rows: Dictionary = {}   # generator id -> {line: HBoxContainer, fuel: Label}
var _signature := ""


func _ready() -> void:
	add_child(UIKit.label(tr("TAB_POWER"), 20, UITheme.ACCENT))
	add_child(_summary)
	var body := UIKit.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := UIKit.vbox()
	left.custom_minimum_size.x = 300
	left.add_child(UIKit.label(tr("UI_GENERATORS"), 16, UITheme.ACCENT))
	left.add_child(UIKit.scroll(_gens))
	body.add_child(left)
	var mid := UIKit.vbox()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(UIKit.label(tr("UI_CHART"), 16, UITheme.ACCENT))
	_chart.custom_minimum_size = Vector2(260, 220)
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chart.draw.connect(_draw_chart)
	mid.add_child(_chart)
	var legend := UIKit.hbox()
	legend.add_child(UIKit.label("■ " + tr("UI_CHART_BATTERY"), 12, UITheme.ACCENT))
	legend.add_child(UIKit.label("▲ " + tr("UI_CHART_STEAM"), 12, Color("#9ad0ff")))
	mid.add_child(legend)
	body.add_child(mid)
	var right := UIKit.vbox()
	right.custom_minimum_size.x = 260
	right.add_child(UIKit.label(tr("UI_CONSUMERS"), 16, UITheme.ACCENT))
	right.add_child(UIKit.scroll(_cons))
	body.add_child(right)
	add_child(body)
	Power.history_updated.connect(_chart.queue_redraw)
	Events.generator_installed.connect(func(_g: String) -> void: rebuild())
	Events.state_reset.connect(rebuild)
	visibility_changed.connect(func() -> void: if is_visible_in_tree(): rebuild())
	rebuild()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_timer += delta
	if _timer >= 0.5:
		_timer = 0.0
		rebuild()


func rebuild() -> void:
	var worst := minf(Power.r_steam, Power.r_eu)
	_summary.text = tr("UI_POWER_SUMMARY") % [NumFormat.format(Power.steam_gen), NumFormat.format(Power.steam_use),
		NumFormat.format(Power.eu_gen), NumFormat.format(Power.eu_use), roundi(worst * 100.0)]
	_summary.add_theme_color_override("font_color", UITheme.TEXT if worst >= 0.999 else UITheme.WARN)
	var sig := ""
	for id: String in Power.groups:
		sig += "%s:%d;" % [id, Power.count(id)]
	if sig != _signature:
		_signature = sig
		UIKit.clear(_gens)
		_rows.clear()
		for id: String in Power.groups:
			_gens.add_child(_gen_row(id))
		if Power.groups.is_empty():
			_gens.add_child(UIKit.label(tr("UI_NOTHING"), 13, UITheme.TEXT_DIM))
	for id: String in _rows:
		_update_row(id)
	UIKit.clear(_cons)
	for c in Power.top_consumers():
		var unit := tr("UNIT_STEAM") if c["energy"] == "steam" else "EU/t"
		var eu := float(c["eu"]) * (Power.steam_per_eu() if c["energy"] == "steam" else 1.0)
		_cons.add_child(UIKit.label("%s — %s %s" % [c["name"], NumFormat.format(eu), unit], 13))


func _gen_row(id: String) -> Control:
	var def := Power.gdef(id)
	var g: Dictionary = Power.groups[id]
	var row := UITheme.riveted_panel()
	var v := UIKit.vbox(2)
	row.add_child(v)
	var head := UIKit.hbox()
	head.add_child(Icons.item_rect(id, 32))
	head.add_child(UIKit.label("%s ×%d" % [Registry.item_name(id), Power.count(id)], 14))
	v.add_child(head)
	var line := UIKit.hbox(4)
	v.add_child(line)
	var fuel := UIKit.label("", 12, UITheme.TEXT_DIM)
	v.add_child(fuel)
	_rows[id] = {"line": line, "fuel": fuel}
	if not def.fuel_tag.is_empty():
		var pick := OptionButton.new()
		pick.add_item(tr("UI_FUEL_AUTO"))
		var cands := Power.fuel_candidates(id)
		for c in cands:
			pick.add_item(Registry.item_name(c))
		var choice: String = g.get("fuel_choice", "")
		pick.selected = cands.find(choice) + 1 if not choice.is_empty() else 0
		pick.item_selected.connect(func(i: int) -> void:
			Power.set_fuel_choice(id, "" if i == 0 else cands[i - 1]))
		v.add_child(pick)
	return row


func _update_row(id: String) -> void:
	var def := Power.gdef(id)
	var g: Dictionary = Power.groups[id]
	var status := "ok"
	var text := ""
	match def.type:
		"boiler":
			if Power.is_producing(id):
				text = tr("GEN_BOILER_ON") % NumFormat.format(def.steam_per_tick * Power.count(id))
			elif Power.is_warming(id):
				status = "warn"
				text = tr("GEN_WARMING") % ceili(float(g["warm_left"]))
			else:
				status = "bad"
				text = tr("GEN_NO_FUEL")
		"solar":
			status = "ok" if GameClock.is_day() else "idle"
			text = tr("GEN_SOLAR_DAY") % NumFormat.format(def.steam_per_tick * Power.count(id)) if GameClock.is_day() \
				else tr("GEN_SOLAR_NIGHT")
		"turbine":
			text = tr("GEN_TURBINE") % [NumFormat.format(Power.turbine_out), NumFormat.format(def.eu_per_tick * Power.count(id))]
		"fuel_gen":
			status = "ok" if float(g["fuel_left"]) > 0.0 else "bad"
			text = tr("GEN_FUEL_GEN") % NumFormat.format(def.eu_per_tick * Power.count(id)) if status == "ok" \
				else tr("GEN_NO_FUEL")
		"battery":
			text = tr("GEN_BATTERY") % [NumFormat.format(Power.battery_charge), NumFormat.format(Power.battery_capacity())]
	var line: HBoxContainer = _rows[id]["line"]
	UIKit.clear(line)
	line.add_child(UIKit.status_icon(status, 14))
	line.add_child(UIKit.label(text, 12, UITheme.TEXT_DIM))
	var fuel: Label = _rows[id]["fuel"]
	fuel.visible = not def.fuel_tag.is_empty() and float(g["fuel_left"]) > 0.0
	if fuel.visible:
		fuel.text = tr("GEN_FUEL_LEFT") % [Registry.item_name(g["fuel_item"]), NumFormat.format(g["fuel_left"])]


func _draw_chart() -> void:
	var r := Rect2(Vector2.ZERO, _chart.size)
	_chart.draw_rect(r, UITheme.BG)
	_chart.draw_rect(r, UITheme.EDGE, false, 1.0)
	for i in 5:
		var y := r.size.y * i / 4.0
		_chart.draw_line(Vector2(0, y), Vector2(r.size.x, y), Color(1, 1, 1, 0.06))
	var h := Power.history
	if h.size() < 2:
		_chart.draw_string(get_theme_default_font(), Vector2(10, 24), tr("UI_CHART_EMPTY"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
		return
	var pts := int(Registry.balance["power"].get("history_points", 120))
	for key: String in ["charge", "steam"]:
		var line := PackedVector2Array()
		for i in h.size():
			var x := r.size.x * float(i + pts - h.size()) / (pts - 1)
			line.append(Vector2(x, r.size.y * (1.0 - float(h[i][key]))))
		var color := UITheme.ACCENT if key == "charge" else Color("#9ad0ff")
		_chart.draw_polyline(line, color, 2.0)
		# Форма маркеров дублирует цвет (правка 10): квадраты — батарея, треугольники — пар.
		for i in range(0, line.size(), 10):
			if key == "charge":
				_chart.draw_rect(Rect2(line[i] - Vector2(3, 3), Vector2(6, 6)), color)
			else:
				_chart.draw_colored_polygon(PackedVector2Array([line[i] + Vector2(0, -4), line[i] + Vector2(4, 3),
					line[i] + Vector2(-4, 3)]), color)
