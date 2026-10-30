class_name ReportWindows
extends RefCounted
## Окно «Пока вас не было…» (раздел 12) и экран «Конец демо» со статистикой.

static func tr_(k: String) -> String:
	return TranslationServer.translate(k)


static func _top(dict: Dictionary, n: int) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(dict.keys())
	ids.sort_custom(func(a: String, b: String) -> bool: return int(dict[a]) > int(dict[b]))
	return ids.slice(0, n)


static func offline(parent: Control, report: Dictionary) -> void:
	if report.is_empty():
		return
	var v := UIKit.modal(parent, tr_("OFFLINE_TITLE") % NumFormat.duration(float(report.get("away", report["seconds"]))),
		Vector2(560, 440))
	if bool(report.get("capped", false)):
		v.add_child(UIKit.label(tr_("OFFLINE_CAPPED") % NumFormat.duration(float(report["seconds"])), 13, UITheme.WARN))
	var body := UIKit.vbox(4)
	v.add_child(UIKit.scroll(body))
	(body.get_parent() as ScrollContainer).custom_minimum_size.y = 320
	var gained: Dictionary = report.get("gained", {})
	body.add_child(UIKit.label(tr_("OFFLINE_GAINED"), 15, UITheme.ACCENT))
	if gained.is_empty():
		body.add_child(UIKit.label(tr_("UI_NOTHING"), 13, UITheme.TEXT_DIM))
	for id in _top(gained, 16):
		body.add_child(UIKit.item_line(id, int(gained[id])))
	var crafted: Dictionary = report.get("crafted", {})
	if not crafted.is_empty():
		body.add_child(UIKit.label(tr_("OFFLINE_CRAFTED"), 15, UITheme.ACCENT))
		for id in _top(crafted, 8):
			body.add_child(UIKit.item_line(id, int(crafted[id])))
	var stops: Array = report.get("stops", [])
	var idle: Array = report.get("idle_stations", [])
	if not stops.is_empty() or not idle.is_empty():
		body.add_child(UIKit.label(tr_("OFFLINE_STOPS"), 15, UITheme.ACCENT))
		for s: Dictionary in stops:
			var line := UIKit.hbox(4)
			line.add_child(UIKit.status_icon("bad", 14))
			var who := Registry.item_name(s["id"]) if not str(s["id"]).is_empty() else ""
			line.add_child(UIKit.label(tr_(s["reason"]) % who if not who.is_empty() else tr_(s["reason"]), 13))
			body.add_child(line)
		for sid: String in idle:
			var line := UIKit.hbox(4)
			line.add_child(UIKit.status_icon("idle", 14))
			line.add_child(UIKit.label(tr_("STOP_QUEUE_DONE") % Registry.station_name(sid), 13))
			body.add_child(line)
	v.add_child(UIKit.button(tr_("UI_OK"), func() -> void: UIKit.close_modal(v)))


static func demo_end(parent: Control) -> void:
	var v := UIKit.modal(parent, tr_("DEMO_END_TITLE"), Vector2(600, 480))
	var text := UIKit.label(tr_("DEMO_END_TEXT"), 14)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 560
	v.add_child(text)
	var crafted_total := 0
	for id: String in Progress.crafted:
		crafted_total += int(Progress.crafted[id])
	var broken_total := 0
	for id: String in Progress.broken:
		broken_total += int(Progress.broken[id])
	for line: String in [
		tr_("DEMO_TIME_GAME") % NumFormat.duration(GameClock.game_time),
		tr_("DEMO_TIME_ACTIVE") % NumFormat.duration(Progress.play_time),
		tr_("DEMO_CLICKS") % NumFormat.format(Progress.clicks),
		tr_("DEMO_BROKEN") % NumFormat.format(broken_total),
		tr_("DEMO_CRAFTED") % NumFormat.format(crafted_total),
		tr_("DEMO_TOOLS") % [Progress.tools_broken, Progress.repairs]]:
		v.add_child(UIKit.label(line, 14))
	v.add_child(UIKit.label(tr_("DEMO_PRODUCED"), 15, UITheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	for id in _top(Storage.total_obtained, 10):
		grid.add_child(UIKit.item_line(id, int(Storage.total_obtained[id])))
	v.add_child(grid)
	var buttons := UIKit.hbox()
	buttons.add_child(UIKit.button(tr_("DEMO_CONTINUE"), func() -> void: UIKit.close_modal(v)))
	v.add_child(buttons)
