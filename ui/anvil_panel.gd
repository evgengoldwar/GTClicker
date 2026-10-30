class_name AnvilPanel
extends VBoxContainer
## Наковальня (раздел 4): инструменты пояса с полосой прочности, ремонт «+25%» и «до полного».
## Стоимость = утраченная доля × стоимость головки × 0.6.

var _list := UIKit.vbox(8)
var _timer := 0.0


func _ready() -> void:
	add_child(UIKit.label(tr("TAB_ANVIL"), 20, UITheme.ACCENT))
	var hint := UIKit.label(tr("UI_ANVIL_HINT"), 13, UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	add_child(UIKit.scroll(_list))
	Events.tool_equipped.connect(func(_t: String) -> void: rebuild())
	Events.tool_broken.connect(func(_t: String, _i: String) -> void: rebuild())
	Events.state_reset.connect(rebuild)
	visibility_changed.connect(func() -> void: if is_visible_in_tree(): rebuild())
	rebuild()


func _process(delta: float) -> void:
	_timer += delta
	if is_visible_in_tree() and _timer > 0.5:
		_timer = 0.0
		rebuild()


func rebuild() -> void:
	UIKit.clear(_list)
	for type: String in Registry.tool_balance().get("types", []):
		var row := UITheme.riveted_panel()
		var h := UIKit.hbox(10)
		row.add_child(h)
		var id := Tools.equipped(type)
		if id.is_empty():
			h.add_child(Icons.rect(type, UITheme.TEXT_DIM, 48))
			h.add_child(UIKit.label(tr("UI_NO_TOOL") % tr("TOOL_" + type.to_upper()), 14, UITheme.TEXT_DIM))
			_list.add_child(row)
			continue
		h.add_child(Icons.item_rect(id, 48))
		var info := UIKit.vbox(2)
		info.custom_minimum_size.x = 260
		info.add_child(UIKit.label(Registry.item_name(id), 15))
		var frac := Tools.durability_fraction(type)
		var color := UITheme.GOOD if frac > 0.2 else (UITheme.WARN if frac > 0.05 else UITheme.BAD)
		info.add_child(UIKit.bar(frac, color, 12))
		var status := UIKit.hbox(4)
		status.add_child(UIKit.status_icon("ok" if frac > 0.2 else ("warn" if frac > 0.05 else "bad"), 14))
		status.add_child(UIKit.label("%d / %d" % [Tools.durability(type), Tools.max_durability(type)], 12, UITheme.TEXT_DIM))
		info.add_child(status)
		h.add_child(info)
		for f: float in [0.25, 1.0]:
			var cost := Tools.repair_cost(type, f)
			var label := tr("UI_REPAIR_25") if f < 1.0 else tr("UI_REPAIR_FULL")
			for item: String in cost:
				label += "\n%s ×%d" % [Registry.item_name(item), int(cost[item])]
			var b := UIKit.button(label, func() -> void:
				Sfx.play("hit_metal" if Tools.repair(type, f) else "error")
				rebuild())
			b.disabled = cost.is_empty() or not Storage.has_all(cost) or not Tools.can_repair()
			if not Tools.can_repair():
				b.tooltip_text = tr("REASON_NO_ANVIL")
			h.add_child(b)
		_list.add_child(row)
