extends TestCase
## Ручной крафт с очередью, открытие рецептов по discovered, группы экземпляров, мультиблок.


func test_recipe_discovery_by_inputs() -> void:
	install("furnace")
	check(not Stations.is_recipe_known("furnace_firebrick"), "без глины и песка рецепт скрыт")
	eq(Stations.unknown_inputs("furnace_firebrick"), 2, "не хватает 2 неизвестных ресурсов")
	Storage.add("clay_ball", 1)
	eq(Stations.unknown_inputs("furnace_firebrick"), 1, "осталась 1 неизвестная")
	Storage.add("sand", 1)
	check(Stations.is_recipe_known("furnace_firebrick"), "все входы в discovered — рецепт открыт")
	Storage.try_remove("sand", 1)
	check(Stations.is_recipe_known("furnace_firebrick"), "рецепт не закрывается, когда ресурс кончился")
	check(Stations.new_recipes("furnace").has("furnace_firebrick"), "новый рецепт помечен")
	Stations.mark_seen("furnace")
	check(not Stations.new_recipes("furnace").has("furnace_firebrick"), "после просмотра — не новый")


func test_tag_inputs_accept_any_item() -> void:
	install("brick_blast_furnace")
	give({"iron_ingot": 2, "charcoal": 1, "coke": 1})
	check(Stations.is_recipe_known("bbf_wrought_iron"), "вход #carbon открыт любым углём")
	eq(Stations.max_craftable("bbf_wrought_iron"), 2, "уголь и кокс суммируются по тегу")
	check(Stations.enqueue("bbf_wrought_iron", 2), "крафт по тегу")
	eq(Storage.count("charcoal") + Storage.count("coke"), 0, "оба предмета тега списаны")


func test_queue_deducts_immediately_and_completes() -> void:
	give({"log": 3})
	eq(Stations.max_craftable("hand_planks"), 3, "максимум по ресурсам")
	check(Stations.enqueue("hand_planks", 3), "в очередь 3 крафта")
	eq(Storage.count("log"), 0, "ресурсы списаны сразу")
	check(not Stations.enqueue("hand_planks", 1), "нечем крафтить")
	GameClock.advance(1.6)
	eq(Storage.count("planks"), 2, "за 1.6 с готов один крафт (1.5 с на штуку)")
	GameClock.advance(3.0)
	eq(Storage.count("planks"), 6, "очередь доделана")
	eq(int(Progress.crafted["planks"]), 6, "статистика крафта")


func test_instances_work_in_parallel() -> void:
	install("furnace", 3)
	give({"clay_ball": 6})
	Stations.enqueue("furnace_brick", 6)
	GameClock.advance(8.0 + 0.01)
	eq(Storage.count("brick"), 3, "3 печи делают 3 крафта параллельно")
	GameClock.advance(8.0)
	eq(Storage.count("brick"), 6, "вторая волна")


func test_station_item_installs_itself() -> void:
	give({"planks": 4})
	Stations.enqueue("hand_workbench", 1)
	GameClock.advance(3.0)
	eq(Stations.instance_count("workbench"), 1, "скрафченная станция появилась")
	eq(Storage.count("workbench"), 0, "предмет станции ушёл в установку")
	check(Progress.has_feature("tab_stations"), "открылась вкладка «Станции»")


func test_click_boost() -> void:
	give({"log": 1})
	Stations.enqueue("hand_planks", 1)
	for i in 8:
		Stations.click_boost("hand")
	eq(Storage.count("planks"), 2, "клики по станции ускоряют крафт на 0.2 с")


func test_cancel_returns_resources() -> void:
	give({"log": 5})
	Stations.enqueue("hand_planks", 5)
	Stations.cancel_queue("hand")
	eq(Storage.count("log"), 4, "4 не начатых крафта вернулись, 1 уже в работе")


func test_voltage_and_heat_requirements() -> void:
	install("steam_macerator")
	eq(Stations.block_reason("ebf_steel"), "REASON_NO_STATION", "EBF ещё не собран")
	check(Stations.max_eu("steam_macerator") <= 8.0, "паровые машины ограничены 8 EU/t")


func test_ebf_multiblock_build() -> void:
	var parts := {"ebf_controller": 1, "heatproof_casing": 8, "cupronickel_coil": 16,
		"lv_input_bus": 1, "lv_output_bus": 1, "lv_energy_hatch": 1}
	give({"ebf_controller": 1, "heatproof_casing": 5, "cupronickel_coil": 16})
	Stations.install_part("ebf", "ebf_controller")
	Stations.install_part("ebf", "heatproof_casing")
	Stations.install_part("ebf", "cupronickel_coil")
	near(Stations.build_progress("ebf"), 22.0 / 28.0, 1e-6, "прогресс по деталям")
	eq(Stations.instance_count("ebf"), 0, "ещё не собран")
	give({"heatproof_casing": 5, "lv_input_bus": 1, "lv_output_bus": 1, "lv_energy_hatch": 1})
	for p: String in parts:
		Stations.install_part("ebf", p)
	eq(Stations.instance_count("ebf"), 1, "EBF собран")
	eq(Storage.count("heatproof_casing"), 2, "лишние корпуса остались в хранилище")
	eq(Stations.heat("ebf"), 1801, "нагрев от купроникелевых катушек")
	give({"iron_dust": 1, "coal_dust": 1})
	eq(Stations.block_reason("ebf_steel"), "", "сталь доступна в EBF на LV")
