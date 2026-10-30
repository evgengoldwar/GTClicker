class_name LookupWindow
extends RefCounted
## «Где добыть / где используется» (аналог R/U из NEI) для любого предмета.

static func open(parent: Control, item_id: String) -> void:
	var v := UIKit.modal(parent, Registry.item_name(item_id), Vector2(720, 520))
	var body := UIKit.vbox(6)
	v.add_child(UIKit.scroll(body))
	(body.get_parent() as ScrollContainer).custom_minimum_size.y = 440
	var head := UIKit.hbox()
	head.add_child(Icons.item_rect(item_id, 48))
	head.add_child(UIKit.label(UIKit.item_tooltip(item_id).replace(TranslationServer.translate("UI_RMB_LOOKUP"), ""), 13))
	body.add_child(head)

	body.add_child(UIKit.label(TranslationServer.translate("UI_WHERE_GET"), 17, UITheme.ACCENT))
	var any := false
	for nid: String in Registry.dropped_by.get(item_id, []):
		any = true
		body.add_child(_drop_line(nid, item_id))
	for rid: String in Registry.produced_by.get(item_id, []):
		any = true
		body.add_child(recipe_line(rid, parent, v))
	if not any:
		body.add_child(UIKit.label(TranslationServer.translate("UI_NOTHING"), 13, UITheme.TEXT_DIM))

	body.add_child(UIKit.label(TranslationServer.translate("UI_WHERE_USED"), 17, UITheme.ACCENT))
	var used: Array = Registry.used_in.get(item_id, [])
	for rid: String in used:
		body.add_child(recipe_line(rid, parent, v))
	if used.is_empty():
		body.add_child(UIKit.label(TranslationServer.translate("UI_NOTHING"), 13, UITheme.TEXT_DIM))


static func _drop_line(nid: String, item_id: String) -> Control:
	var n: NodeDef = Registry.nodes[nid] if Registry.nodes.has(nid) else Registry.veins[nid]
	var where := Registry.node_name(nid) if Registry.nodes.has(nid) \
		else TranslationServer.translate("VEIN_" + nid.to_upper()) + " · " + TranslationServer.translate("NODE_ZONE_ORE_HILLS")
	var chance := 0.0
	for d in n.drops:
		if d["item"] == item_id:
			chance = float(d["chance"])
	var h := UIKit.hbox()
	h.add_child(Icons.rect(n.icon, n.color, 32))
	h.add_child(UIKit.label("%s — %s (%d%%), %s" % [TranslationServer.translate("UI_MINE"), where, roundi(chance * 100),
		TranslationServer.translate("TOOL_" + n.tool_type.to_upper())], 14))
	return h


## Строка рецепта «входы → выходы · станция · время · энергия». Неоткрытый рецепт — «???».
static func recipe_line(rid: String, parent: Control, window: VBoxContainer) -> Control:
	var r := Registry.recipe(rid)
	var h := UIKit.hbox(4)
	h.add_child(UIKit.label(Registry.station_name(r.station) + ":", 13, UITheme.TEXT_DIM))
	if not Stations.is_recipe_known(rid):
		h.add_child(UIKit.label("???  " + TranslationServer.translate("UI_UNKNOWN_INPUTS") % Stations.unknown_inputs(rid),
			13, UITheme.TEXT_DIM))
		return h
	for inp in r.inputs:
		h.add_child(_item_button(Registry.input_candidates(inp)[0], int(inp["n"]), inp.has("tag"), parent, window))
	h.add_child(UIKit.label("→", 16))
	for o in r.outputs:
		h.add_child(_item_button(o["item"], int(o["n"]), false, parent, window))
		if float(o["chance"]) < 1.0:
			h.add_child(UIKit.label("%d%%" % roundi(float(o["chance"]) * 100), 12, UITheme.TEXT_DIM))
	var info := NumFormat.duration(r.ticks / Registry.ticks_per_second()) if r.ticks >= 20 \
		else "%.2f %s" % [r.ticks / Registry.ticks_per_second(), TranslationServer.translate("UNIT_SECONDS")]
	if r.eu > 0.0:
		info += " · %s EU/t" % NumFormat.format(r.eu)
	if r.heat > 0:
		info += " · %d K" % r.heat
	h.add_child(UIKit.label("  " + info, 12, UITheme.TEXT_DIM))
	return h


static func _item_button(item_id: String, n: int, is_tag: bool, parent: Control, window: VBoxContainer) -> Control:
	var b := Button.new()
	b.icon = Icons.shape(Registry.item(item_id).icon)
	b.expand_icon = true
	b.custom_minimum_size = Vector2(44, 36)
	b.material = null
	b.text = "×" + UIKit.amount(item_id, n)
	b.add_theme_font_size_override("font_size", 11)
	b.tooltip_text = ("#" if is_tag else "") + Registry.item_name(item_id)
	b.add_theme_color_override("icon_normal_color", Registry.item(item_id).color)
	b.add_theme_color_override("icon_hover_color", Registry.item(item_id).color.lightened(0.2))
	b.pressed.connect(func() -> void:
		UIKit.close_modal(window)
		open(parent, item_id))
	return b
