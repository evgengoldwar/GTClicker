extends TestCase
## Ручная добыча, крит-искра, появление блоков, майнеры и рудные жилы.


func test_click_breaks_and_drops() -> void:
	for i in 7:
		World.click("tree")
	eq(Storage.count("log"), 0, "7 кликов из 8 — ещё не разбито")
	World.click("tree")
	eq(Storage.count("log"), 1, "8-й клик даёт бревно")
	eq(int(Progress.broken["tree"]), 1, "статистика разбитых блоков")
	eq(Progress.clicks, 8, "клики считаются")


func test_crit_spark_multiplies_damage() -> void:
	World.focus("tree")
	World.spark_time = 1.0
	eq(World.click("tree", true), 5.0, "клик по искре = ×5")
	eq(World.click("tree", true), 1.0, "искра одноразовая")


func test_onboarding_reveals() -> void:
	check(World.is_revealed("tree"), "дерево видно сразу")
	check(not World.is_revealed("stone"), "камень скрыт до деревянной кирки")
	for i in 5 * 8:
		World.click("tree")
	check(Progress.has_feature("tab_storage"), "5 брёвен открывают хранилище")
	check(not Progress.has_feature("tab_stations"), "станции ещё скрыты")
	Storage.add("tool_pickaxe_wood", 1)
	check(World.is_revealed("stone"), "кирка открывает камень")
	check(not World.is_revealed("hills_a"), "рудные холмы закрыты")


func test_locked_node() -> void:
	Storage.add("brick", 1)
	Storage.add("tool_pickaxe_wood", 1)
	check(World.is_revealed("coal_outcrop"), "уголь виден")
	check(World.is_locked("coal_outcrop"), "но деревянной киркой не добывается")
	eq(World.click("coal_outcrop"), 0.0, "клик по закрытому блоку ничего не делает")


func test_miner_limit_replace_and_rate() -> void:
	give({"wooden_collector": 6, "steam_drill": 1})
	for i in 5:
		Miners.place("tree", "wooden_collector")
	eq(Miners.cell_count("tree"), 4, "лимит по размеру жилы (4)")
	eq(Miners.place_reason("tree", "wooden_collector"), "REASON_VEIN_FULL", "причина отказа")
	near(Miners.blocks_per_sec("tree"), 4 * 1.6 / 8.0, 1e-9, "4 сборщика по 1.6 урона/с по твёрдости 8")
	GameClock.advance(10.0)
	eq(Storage.count("log"), 8, "0.8 бревна/с за 10 с")
	Miners.place("tree", "steam_drill")
	eq(Miners.cell_miner("tree"), "steam_drill", "новый тип заменил старый")
	eq(Storage.count("wooden_collector"), 6, "старые майнеры вернулись в хранилище")


func test_collector_rate_matches_doc() -> void:
	give({"wooden_collector": 1})
	Miners.place("tree", "wooden_collector")
	near(Miners.item_rate("log"), 0.2, 1e-9, "один сборщик — 0.2 бревна/с, как в документе")


func test_veins_rotate_daily_online_only() -> void:
	Progress.unlock("zone_ore_hills")
	var before := World.current_vein("hills_a")
	GameClock.offline = true
	GameClock.advance(GameClock.day_length() * 2.5)
	GameClock.offline = false
	eq(World.current_vein("hills_a"), before, "офлайн жилы не меняются")
	var day := GameClock.vein_day
	GameClock.advance(GameClock.day_length())
	eq(GameClock.vein_day, day + 1, "онлайн — раз в игровые сутки")
	check(World.current_vein("hills_a") != before, "жила сменилась")
	var seen: Dictionary = {}
	for id in ["hills_a", "hills_b", "hills_c"]:
		seen[World.current_vein(id)] = true
	eq(seen.size(), 3, "в любой день три разные жилы")


func test_steam_miner_needs_steam() -> void:
	Progress.unlock("zone_ore_hills")
	give({"steam_drill": 2})
	Miners.place("hills_a", "steam_drill")
	GameClock.advance(60.0)
	eq(Storage.count(World.node_def("hills_a").drops[0]["item"]), 0, "без пара бур стоит")
	Power.install("solar_boiler", 2)
	GameClock.advance(60.0)
	check(Storage.count(World.node_def("hills_a").drops[0]["item"]) > 0, "солнечный котёл днём даёт пар")
