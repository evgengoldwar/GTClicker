extends TestCase
## Квесты: цепочки, триггеры, награды, видимость.


func test_chain_and_obtain_trigger() -> void:
	Quests.check_all()
	eq(Quests.state("q0_first_log"), Quests.State.AVAILABLE, "первый квест доступен")
	eq(Quests.state("q0_workbench"), Quests.State.LOCKED, "следующий закрыт")
	Storage.add("log", 1)
	Quests.check_all()
	eq(Quests.state("q0_first_log"), Quests.State.COMPLETED, "obtain выполнен")
	eq(Quests.state("q0_workbench"), Quests.State.AVAILABLE, "открылся следующий")
	check(Quests.claim("q0_first_log"), "награда забрана")
	eq(Storage.count("log"), 5, "1 + 4 бревна награды")
	check(not Quests.claim("q0_first_log"), "дважды не забрать")


func test_have_vs_obtain() -> void:
	Quests.states["q0_intern"] = Quests.State.AVAILABLE
	Storage.add("log", 40)
	Storage.try_remove("log", 20)
	Quests.check_all()
	check(not Quests.is_done("q0_intern"), "have: нужно иметь 32 одновременно")
	Storage.add("log", 12)
	Quests.check_all()
	check(Quests.is_done("q0_intern"), "have выполнен")


func test_checkbox_break_craft_stat() -> void:
	Quests.states["q0_tools_book"] = Quests.State.AVAILABLE
	Quests.set_checked("q0_tools_book")
	check(Quests.is_done("q0_tools_book"), "checkbox")
	Quests.states["q0_break_stone"] = Quests.State.AVAILABLE
	Progress.broken["stone"] = 10
	Quests.check_all()
	check(Quests.is_done("q0_break_stone"), "break")
	Quests.states["q1_steam_machine"] = Quests.State.AVAILABLE
	Events.crafted.emit("steam_compressor", 1, "workbench", "x")
	Quests.check_all()
	check(Quests.is_done("q1_steam_machine"), "craft по тегу #steam_machine")
	Quests.states["q1_steam_gen"] = Quests.State.AVAILABLE
	Power.install("coal_boiler", 2)
	Storage.add("coal", 5, false)
	GameClock.advance(31.0)
	check(Quests.is_done("q1_steam_gen"), "stat steam_gen ≥ 24")


func test_rewards_choice_era_unlock_demo() -> void:
	Quests.states["q1_boiler"] = Quests.State.COMPLETED
	check(Quests.claim("q1_boiler", 1), "выбор второго варианта")
	eq(Storage.count("bronze_plate"), 5, "получен второй вариант")
	eq(Storage.count("coal"), 0, "первый вариант не выдан")
	Quests.states["q0_gate"] = Quests.State.COMPLETED
	Quests.claim("q0_gate")
	eq(Progress.era, 1, "ворота дают эпоху 1")
	check(World.is_revealed("rubber_tree"), "эпоха открывает каучуковое дерево")
	Quests.states["q1_ore_hills"] = Quests.State.COMPLETED
	Quests.claim("q1_ore_hills")
	check(World.zone_unlocked("ore_hills"), "квест открывает Рудные холмы")
	Quests.states["q2_demo_end"] = Quests.State.COMPLETED
	Quests.claim("q2_demo_end")
	check(Progress.demo_finished, "финал демо")


func test_visibility_hides_deep_locked_chain() -> void:
	Quests.check_all()
	check(Quests.is_visible_on_canvas("q0_first_log"), "доступный виден")
	check(Quests.is_visible_on_canvas("q0_workbench"), "закрытый на 1 уровень — виден")
	check(not Quests.is_visible_on_canvas("q0_wood_pick"), "глубже — скрыт")


func test_quest_count_in_range() -> void:
	var n := Registry.quest_order.size()
	check(n >= 25 and n <= 40, "квестов %d (нужно 25–40)" % n)
