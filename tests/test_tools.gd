extends TestCase
## Инструменты: тип и тир, прочность за блок, поломка с возвратом 50%, ремонт, апгрейд.


func test_hand_and_wrong_tool() -> void:
	var tree := Registry.node("tree")
	eq(float(Tools.hit_for(tree)["damage"]), 1.0, "руки бьют дерево с уроном 1")
	var stone := Registry.node("stone")
	eq(int(Tools.hit_for(stone)["tier"]), -1, "камень руками не добыть")
	Storage.add("tool_axe_wood", 1)
	eq(Tools.equipped("axe"), "tool_axe_wood", "инструмент надевается сам")
	near(float(Tools.hit_for(stone)["damage"]), 0.5, 1e-9, "чужой инструмент ×0.25")
	Storage.add("tool_pickaxe_wood", 1)
	near(float(Tools.hit_for(stone)["damage"]), 2.0, 1e-9, "своя кирка")
	eq(World.clicks_needed("stone"), 8, "камень деревянной киркой — 8 кликов")


func test_durability_per_block_and_break_returns_half() -> void:
	Storage.add("tool_axe_wood", 1)
	eq(World.clicks_needed("tree"), 4, "деревянный топор — 4 клика")
	for i in 4 * 59:
		World.click("tree")
	eq(Tools.durability("axe"), 1, "−1 прочности за блок, а не за клик (59 блоков)")
	var planks := Storage.count("planks")
	for i in 4:
		World.click("tree")
	eq(Tools.equipped("axe"), "", "топор сломался")
	eq(Storage.count("planks") - planks, 2, "вернулось 50% головки (3 доски → 2)")
	eq(Progress.tools_broken, 1, "статистика поломок")


func test_repair_cost_and_anvil() -> void:
	Storage.add("tool_pickaxe_bronze", 1)
	Tools.belt["pickaxe"]["durability"] = 100  # потеряно 75%
	eq(int(Tools.repair_cost("pickaxe", 1.0)["bronze_ingot"]), 2, "0.75 × 3 × 0.6 = 1.35 → 2")
	eq(int(Tools.repair_cost("pickaxe", 0.25)["bronze_ingot"]), 1, "+25%")
	give({"bronze_ingot": 5})
	check(not Tools.repair("pickaxe", 1.0), "без наковальни ремонта нет")
	install("anvil")
	check(Tools.repair("pickaxe", 0.25), "ремонт +25%")
	eq(Tools.durability("pickaxe"), 200, "100 + 25% от 400")
	check(Tools.repair("pickaxe", 1.0), "до полного")
	eq(Tools.durability("pickaxe"), 400, "полная прочность")


func test_upgrade_consumes_equipped_tool() -> void:
	install("workbench")
	Storage.add("tool_pickaxe_wood", 1)
	give({"cobblestone": 3})
	check(Stations.enqueue("craft_tool_pickaxe_stone", 1), "апгрейд кирки")
	eq(Tools.equipped("pickaxe"), "", "старая кирка снята и ушла в рецепт")
	GameClock.advance(10.0)
	eq(Tools.equipped("pickaxe"), "tool_pickaxe_stone", "новая кирка надета")
	eq(Storage.count("tool_pickaxe_wood"), 0, "старой кирки нет")
