class_name QuestsPanel
extends HBoxContainer
## Экран квестов (раздел 10): слева главы с прогрессом «x/y», в центре — панорамируемое полотно
## с иконками и линиями связей, справа — описание, цели с прогресс-барами, награды.
## Рамка по статусу дублируется значком (правка 10); главные — золотая, опциональные — серебряная.

signal reward_claimed(quest_id: String, from: Vector2)

const CELL := Vector2(104, 92)
const NODE := 56

var _chapters := UIKit.vbox(4)
var _canvas := Control.new()
var _content := Control.new()
var _details := UIKit.vbox(6)
var _chapter := ""
var _selected := ""
var _drag := false
var _timer := 0.0
var _hidden_label := UIKit.label("", 12, UITheme.TEXT_DIM)
var _rebuild_pending := false


func _ready() -> void:
	_chapters.custom_minimum_size.x = 170
	add_child(_chapters)
	_canvas.clip_contents = true
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_on_canvas_input)
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(bg)
	_content.draw.connect(_draw_links)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_content)
	_hidden_label.position = Vector2(8, 4)
	_canvas.add_child(_hidden_label)
	add_child(_canvas)
	var right := PanelContainer.new()
	right.custom_minimum_size.x = 320
	right.add_child(UIKit.scroll(_details))
	add_child(right)
	Quests.quest_state_changed.connect(func(_q: String) -> void: _queue_rebuild())
	Events.state_reset.connect(_queue_rebuild)
	_chapter = Registry.chapters[0]["id"] if not Registry.chapters.is_empty() else ""
	rebuild()


func _queue_rebuild() -> void:
	_rebuild_pending = true


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_timer += delta
	if _timer < 0.2:
		return
	_timer = 0.0
	if _rebuild_pending:
		_rebuild_pending = false
		rebuild()
	elif not _selected.is_empty():
		_refresh_goals()


func rebuild() -> void:
	UIKit.clear(_chapters)
	_chapters.add_child(UIKit.label(tr("UI_CHAPTERS"), 16, UITheme.ACCENT))
	for ch in Registry.chapters:
		var cid: String = ch["id"]
		var p := Quests.chapter_progress(cid)
		var b := UIKit.button("%s  %d/%d" % [tr("CHAPTER_" + cid.to_upper()), p.x, p.y], func() -> void:
			_chapter = cid
			_selected = ""
			rebuild())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var started := false
		for qid: String in ch["quests"]:
			started = started or Quests.state(qid) != Quests.State.LOCKED
		b.disabled = not started
		if cid == _chapter:
			b.add_theme_stylebox_override("normal", UITheme.box(UITheme.PANEL_LIGHT, UITheme.ACCENT))
		_chapters.add_child(b)
	for c in _content.get_children():
		c.queue_free()
	var hidden_count := 0
	for qid in _chapter_quests():
		if not Quests.is_visible_on_canvas(qid):
			hidden_count += 1
			continue
		_content.add_child(_quest_node(qid))
	_hidden_label.text = tr("UI_HIDDEN_QUESTS") % hidden_count if hidden_count > 0 else ""
	_content.queue_redraw()
	_show_details()


func _chapter_quests() -> Array[String]:
	for ch in Registry.chapters:
		if ch["id"] == _chapter:
			var out: Array[String] = []
			out.assign(ch["quests"])
			return out
	return []


func _quest_center(qid: String) -> Vector2:
	return Registry.quest(qid).pos * CELL + Vector2(40, 60) + Vector2(NODE, NODE) / 2.0


func _status(qid: String) -> Array:
	match Quests.state(qid):
		Quests.State.LOCKED:
			return ["lock", UITheme.TEXT_DIM]
		Quests.State.AVAILABLE:
			return ["quest", Color.WHITE]
		Quests.State.COMPLETED:
			return ["star", UITheme.GOOD]
	return ["check", UITheme.GOOD.darkened(0.4)]


func _quest_node(qid: String) -> Control:
	var q := Registry.quest(qid)
	var st := _status(qid)
	var b := Button.new()
	b.custom_minimum_size = Vector2(NODE, NODE)
	b.size = Vector2(NODE, NODE)
	b.position = _quest_center(qid) - Vector2(NODE, NODE) / 2.0
	var frame: Color = st[1]
	var border := Color("#e0b030") if q.main else Color("#c0c8d0")
	b.add_theme_stylebox_override("normal", UITheme.box(UITheme.PANEL, border if Quests.state(qid) != Quests.State.LOCKED else UITheme.EDGE, 3, 6))
	b.add_theme_stylebox_override("hover", UITheme.box(UITheme.PANEL_LIGHT, frame, 3, 6))
	b.tooltip_text = tr(q.title_key())
	var icon := Icons.item_rect(q.icon, 32) if not q.icon.is_empty() else Icons.rect("quest", Color.WHITE, 32)
	icon.position = Vector2(NODE - 32, NODE - 32) / 2.0
	if Quests.state(qid) == Quests.State.LOCKED:
		icon.modulate = Color(0.4, 0.4, 0.4)
	b.add_child(icon)
	var badge := Icons.rect(st[0], frame, 16)
	badge.position = Vector2(NODE - 14, -4)
	b.add_child(badge)
	if Quests.state(qid) == Quests.State.COMPLETED and not Settings.reduce_animations:
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "modulate", Color(1.3, 1.6, 1.3), 0.5)
		tw.tween_property(b, "modulate", Color.WHITE, 0.5)
	b.pressed.connect(func() -> void:
		_selected = qid
		_show_details())
	return b


func _draw_links() -> void:
	var ids := _chapter_quests()
	for qid in ids:
		if not Quests.is_visible_on_canvas(qid):
			continue
		for req in Registry.quest(qid).requires:
			if ids.has(req) and Quests.is_visible_on_canvas(req):
				var c := UITheme.GOOD if Quests.is_done(req) else UITheme.EDGE
				_content.draw_line(_quest_center(req), _quest_center(qid), c, 3.0)


func _on_canvas_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_MIDDLE):
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		_content.position += (e as InputEventMouseMotion).relative


func _show_details() -> void:
	UIKit.clear(_details)
	if _selected.is_empty():
		_details.add_child(UIKit.label(tr("UI_QUEST_SELECT"), 13, UITheme.TEXT_DIM))
		return
	var q := Registry.quest(_selected)
	var title := UIKit.label(tr(q.title_key()), 18, UITheme.ACCENT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_child(title)
	_details.add_child(UIKit.label(tr("UI_QUEST_MAIN") if q.main else tr("UI_QUEST_OPTIONAL"), 12, UITheme.TEXT_DIM))
	var desc := UIKit.label(tr(q.desc_key()), 14)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 290
	_details.add_child(desc)
	_details.add_child(UIKit.label(tr("UI_GOALS") + (" (" + tr("UI_ANY") + ")" if q.goals_mode == "any" else ""), 15, UITheme.ACCENT))
	for i in q.goals.size():
		var g: Dictionary = q.goals[i]
		var row := UIKit.vbox(2)
		row.name = "Goal%d" % i
		var text := UIKit.label(_goal_text(g), 13)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)
		if g["type"] == "checkbox":
			var b := UIKit.button(tr("UI_MARK_READ"), func() -> void: Quests.set_checked(_selected))
			b.disabled = Quests.state(_selected) != Quests.State.AVAILABLE
			row.add_child(b)
		else:
			var p := Quests.goal_progress(_selected, g)
			var bar := UIKit.bar(float(p.x) / maxf(1.0, p.y), UITheme.GOOD, 10)
			bar.name = "Bar"
			row.add_child(bar)
			var pl := UIKit.label("%s / %s" % [NumFormat.format(p.x), NumFormat.format(p.y)], 12, UITheme.TEXT_DIM)
			pl.name = "Count"
			row.add_child(pl)
		_details.add_child(row)
	_details.add_child(UIKit.label(tr("UI_REWARDS"), 15, UITheme.ACCENT))
	var rw := q.rewards
	for e: Dictionary in rw.get("items", []):
		_details.add_child(UIKit.item_line(e["item"], int(e["n"])))
	if rw.has("era"):
		_details.add_child(UIKit.label(tr("UI_REWARD_ERA") % tr("ERA_%d" % int(rw["era"])), 13, UITheme.WARN))
	for f: String in rw.get("unlock", []):
		_details.add_child(UIKit.label(tr("UI_REWARD_UNLOCK") % tr("FEATURE_" + f.to_upper()), 13, UITheme.WARN))
	if rw.get("demo_end", false):
		_details.add_child(UIKit.label(tr("UI_REWARD_DEMO_END"), 13, UITheme.WARN))
	var options: Array = rw.get("choice", [])
	var claimable := Quests.state(_selected) == Quests.State.COMPLETED
	if not options.is_empty():
		_details.add_child(UIKit.label(tr("UI_REWARD_CHOICE"), 13))
		for i in options.size():
			var parts: Array[String] = []
			for e: Dictionary in options[i]:
				parts.append("%s ×%d" % [Registry.item_name(e["item"]), int(e["n"])])
			var b := UIKit.button(", ".join(parts), func() -> void: _claim(i))
			b.disabled = not claimable
			_details.add_child(b)
	elif claimable:
		_details.add_child(UIKit.button(tr("UI_CLAIM"), func() -> void: _claim(0)))
	if Quests.state(_selected) == Quests.State.CLAIMED:
		_details.add_child(UIKit.label(tr("UI_CLAIMED"), 13, UITheme.GOOD))


func _claim(choice: int) -> void:
	var qid := _selected
	if Quests.claim(qid, choice):
		Sfx.play("claim")
		reward_claimed.emit(qid, get_global_mouse_position())
		rebuild()


func _refresh_goals() -> void:
	var q := Registry.quest(_selected)
	for i in q.goals.size():
		var row := _details.get_node_or_null("Goal%d" % i)
		if row == null or not row.has_node("Bar"):
			continue
		var p := Quests.goal_progress(_selected, q.goals[i])
		(row.get_node("Bar") as ProgressBar).value = float(p.x) / maxf(1.0, p.y)
		(row.get_node("Count") as Label).text = "%s / %s" % [NumFormat.format(p.x), NumFormat.format(p.y)]


func _goal_text(g: Dictionary) -> String:
	var target := ""
	if g.has("item"):
		target = Registry.item_name(g["item"])
	elif g.has("tag"):
		target = tr("TAG_" + str(g["tag"]).to_upper())
	elif g.has("node"):
		target = Registry.node_name(g["node"])
	match g["type"]:
		"obtain":
			return tr("GOAL_OBTAIN") % [target, int(g["n"])]
		"have":
			return tr("GOAL_HAVE") % [target, int(g["n"])]
		"craft":
			var t := tr("GOAL_CRAFT") % [target, int(g["n"])]
			if g.has("station"):
				t += " " + tr("GOAL_AT") % Registry.station_name(g["station"])
			return t
		"break":
			return tr("GOAL_BREAK") % [target, int(g["n"])]
		"stat":
			return tr("STAT_" + str(g["stat"]).to_upper()) % int(g["n"])
		"checkbox":
			return tr("GOAL_CHECKBOX")
	return str(g)
