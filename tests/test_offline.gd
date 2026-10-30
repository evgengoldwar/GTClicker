extends TestCase
## Офлайн по событиям (правка 8) против пошаговой симуляции тиками по 1/20 с.

const DURATION := 900.0


func _scenario() -> void:
	Progress.unlock("zone_ore_hills")
	Storage.add("brick", 1)
	give({"coal": 40, "wooden_collector": 4, "steam_drill": 3, "clay_ball": 30})
	Power.install("coal_boiler", 2)
	Power.install("solar_boiler", 1)
	install("steam_macerator", 2)
	install("furnace", 2)
	Miners.place("tree", "wooden_collector")
	Miners.place("tree", "wooden_collector")
	Miners.place("hills_a", "steam_drill")
	Miners.place("hills_a", "steam_drill")
	Miners.place("sand", "steam_drill")
	check(Stations.enqueue("sm_coal_dust", 20), "дробление угля")
	check(Stations.enqueue("furnace_brick", 30), "кирпичи")


func _snapshot() -> Dictionary:
	var out := Storage.counts.duplicate()
	out["_steam"] = snappedf(Power.steam_buffer, 0.01)
	out["_time"] = snappedf(GameClock.game_time, 0.001)
	return out


func test_event_jump_matches_stepwise() -> void:
	_scenario()
	var start := Save.to_dict()
	# Пошагово: 18 000 тиков.
	var tick := GameClock.tick_length()
	var steps := roundi(DURATION / tick)
	for i in steps:
		GameClock.advance(tick)
	var stepwise := _snapshot()
	# По событиям: одним вызовом.
	check(Save.from_dict(start), "восстановление стартового состояния")
	var segments := GameClock.advance(DURATION)
	var jumped := _snapshot()
	check(segments < steps / 10.0, "событий (%d) намного меньше, чем тиков (%d)" % [segments, steps])
	for id: String in stepwise:
		if id.begins_with("_"):
			near(float(jumped[id]), float(stepwise[id]), 0.5, id)
		else:
			check(absi(int(jumped.get(id, 0)) - int(stepwise[id])) <= 1,
				"%s: по событиям %d, пошагово %d" % [id, int(jumped.get(id, 0)), int(stepwise[id])])
	check(int(stepwise.get("coal_dust", 0)) > 0, "сценарий что-то произвёл")
	check(int(stepwise.get("brick", 0)) > 1, "печи работали")


func test_twelve_hours_is_fast() -> void:
	_scenario()
	var t0 := Time.get_ticks_msec()
	var report := GameClock.simulate_offline(12 * 3600.0)
	var ms := Time.get_ticks_msec() - t0
	check(ms < 3000, "12 ч офлайна считаются за %d мс" % ms)
	check(int(report["events"]) < 20000, "событий: %d" % int(report["events"]))
	check(int((report["gained"] as Dictionary).get("log", 0)) > 0, "бревна добыты")
	var stops: Array = report["stops"]
	var no_fuel := false
	for s: Dictionary in stops:
		no_fuel = no_fuel or s["reason"] == "STOP_NO_FUEL"
	check(no_fuel, "отчёт фиксирует, что котлы остались без топлива")
