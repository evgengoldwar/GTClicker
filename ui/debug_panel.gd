class_name DebugPanel
extends RefCounted
## Debug-панель (F12, раздел 14): выдать предмет, ускорить время, открыть эпоху,
## симулировать N часов офлайна, пропустить сутки.

static func open(parent: Control, on_report: Callable) -> void:
	var v := UIKit.modal(parent, "Debug (F12)", Vector2(560, 520))
	var tr_ := func(k: String) -> String: return TranslationServer.translate(k)

	v.add_child(UIKit.label(tr_.call("DBG_GIVE"), 15, UITheme.ACCENT))
	var search := LineEdit.new()
	search.placeholder_text = tr_.call("UI_SEARCH")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(520, 160)
	var ids: Array[String] = []
	var fill := func(q: String) -> void:
		list.clear()
		ids.clear()
		for id: String in Registry.item_order:
			if q.is_empty() or Registry.item_name(id).to_lower().contains(q.to_lower()) or id.contains(q):
				ids.append(id)
				list.add_item(Registry.item_name(id) + "  [" + id + "]")
	fill.call("")
	search.text_changed.connect(func(t: String) -> void: fill.call(t))
	v.add_child(search)
	v.add_child(list)
	var give := UIKit.hbox()
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = 1000000
	amount.value = 64
	give.add_child(amount)
	give.add_child(UIKit.button(tr_.call("DBG_GIVE_BTN"), func() -> void:
		for i in list.get_selected_items():
			Storage.add(ids[i], int(amount.value), false)))
	v.add_child(give)

	v.add_child(UIKit.label(tr_.call("DBG_SPEED"), 15, UITheme.ACCENT))
	var speed := UIKit.hbox()
	for s in [1, 10, 100, 1000]:
		speed.add_child(UIKit.button("×%d" % s, func() -> void: GameClock.time_scale = s))
	speed.add_child(UIKit.button(tr_.call("DBG_SKIP_DAY"), func() -> void: GameClock.advance(GameClock.day_length())))
	v.add_child(speed)

	v.add_child(UIKit.label(tr_.call("DBG_ERA"), 15, UITheme.ACCENT))
	var era := UIKit.hbox()
	for e in [1, 2]:
		era.add_child(UIKit.button(tr_.call("ERA_%d" % e), func() -> void:
			Progress.set_era(e)
			Progress.unlock("zone_ore_hills")
			for f: Dictionary in Registry.features:
				Progress.unlock(f["id"])))
	v.add_child(era)

	v.add_child(UIKit.label(tr_.call("DBG_OFFLINE"), 15, UITheme.ACCENT))
	var off := UIKit.hbox()
	var hours := SpinBox.new()
	hours.min_value = 0.1
	hours.max_value = 24
	hours.step = 0.1
	hours.value = 8
	off.add_child(hours)
	off.add_child(UIKit.button(tr_.call("DBG_OFFLINE_BTN"), func() -> void:
		UIKit.close_modal(v)
		on_report.call(Save.run_offline(hours.value * 3600.0))))
	v.add_child(off)
