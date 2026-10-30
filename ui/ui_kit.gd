class_name UIKit
extends RefCounted
## Мелкие помощники для построения интерфейса кодом. UI только читает состояние автолоадов
## и вызывает их команды — сам ничего не считает.


static func label(text: String, size: int = 15, color: Color = UITheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, on_press: Callable, min_width: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.x = min_width
	b.pressed.connect(func() -> void:
		Sfx.play("click", 0.02)
		on_press.call())
	return b


static func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func bar(fraction: float, color: Color = UITheme.ACCENT, height: int = 10) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.value = fraction
	p.show_percentage = false
	p.custom_minimum_size.y = height
	p.add_theme_stylebox_override("fill", UITheme.box(color, color.darkened(0.3), 1, 2))
	return p


## Количество предмета с единицей: «144 L» для жидкостей.
static func amount(item_id: String, n: float) -> String:
	var it := Registry.item(item_id)
	var unit := " L" if it != null and it.is_liquid() else ""
	return NumFormat.format(n) + unit


## Строка «иконка · имя · нужно / есть», красным — если не хватает.
static func item_line(item_id: String, need: int, have: int = -1) -> HBoxContainer:
	var h := hbox()
	h.add_child(Icons.item_rect(item_id, 32))
	var text := "%s × %s" % [Registry.item_name(item_id), amount(item_id, need)]
	var color := UITheme.TEXT
	if have >= 0:
		text += "   /   " + TranslationServer.translate("UI_HAVE") + " " + amount(item_id, have)
		color = UITheme.GOOD if have >= need else UITheme.BAD
	var l := label(text, 14, color)
	if have >= 0 and have < need:
		l.text = "✗ " + l.text  # не только цветом (правка 10)
	h.add_child(l)
	h.tooltip_text = item_tooltip(item_id)
	return h


## Тултип предмета: точное количество и откуда приходит (раздел 3).
static func item_tooltip(item_id: String) -> String:
	var lines: Array[String] = [Registry.item_name(item_id)]
	var desc_key := "DESC_" + item_id.to_upper()
	if TranslationServer.translate(desc_key) != desc_key:
		lines.append(TranslationServer.translate(desc_key))
	lines.append("%s: %s" % [TranslationServer.translate("UI_IN_STORAGE"), NumFormat.full(Storage.count(item_id))])
	var inc := Storage.income(item_id)
	if inc > 0.0:
		lines.append("%s: %s" % [TranslationServer.translate("UI_INCOME"), NumFormat.rate(inc)])
	var miners := Miners.item_rate(item_id)
	if miners > 0.0:
		lines.append("%s: %s" % [TranslationServer.translate("UI_FROM_MINERS"), NumFormat.rate(miners)])
	lines.append(TranslationServer.translate("UI_RMB_LOOKUP"))
	return "\n".join(lines)


## Значок статуса: цвет + форма, чтобы статус читался без различения цветов (правка 10).
static func status_icon(status: String, px: int = 16) -> TextureRect:
	var shapes := {"ok": ["check", UITheme.GOOD], "warn": ["warning", UITheme.WARN],
		"bad": ["cross", UITheme.BAD], "idle": ["moon", UITheme.TEXT_DIM], "lock": ["lock", UITheme.TEXT_DIM]}
	var s: Array = shapes.get(status, shapes["idle"])
	return Icons.rect(s[0], s[1], px)


## Затемнённый фон + центрированная панель для модальных окон.
static func modal(parent: Control, title: String, min_size: Vector2) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := UITheme.riveted_panel()
	panel.custom_minimum_size = min_size
	center.add_child(panel)
	var v := vbox(8)
	panel.add_child(v)
	var head := hbox()
	head.add_child(label(title, 20, UITheme.ACCENT))
	head.add_child(spacer())
	head.add_child(button("✕", func() -> void: dim.queue_free()))
	v.add_child(head)
	v.set_meta("dim", dim)
	return v


static func close_modal(content: VBoxContainer) -> void:
	(content.get_meta("dim") as Node).queue_free()
