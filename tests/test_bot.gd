extends TestCase
## Сквозной тест «бот проходит MVP»: от пустого сейва до стали из EBF и MV-схемы.
## Бот пользуется только командами симуляции; время идёт ускоренно через GameClock.advance.


func _step(bot: Bot, item_id: String, n: int = 1) -> bool:
	var ok := bot.obtain(item_id, n)
	bot.claim_quests()
	if ok:
		bot.note("есть %s ×%d" % [item_id, n])
	return ok


func test_bot_completes_mvp() -> void:
	var bot := Bot.new()
	var plan: Array = [
		# Эпоха 0: руки → дерево → камень → печь.
		["log", 5], ["workbench", 1], ["tool_pickaxe_wood", 1], ["tool_axe_wood", 1],
		["cobblestone", 24], ["furnace", 1], ["tool_shovel_wood", 1], ["charcoal", 4],
		["brick", 4], ["tool_pickaxe_stone", 1], ["tool_axe_stone", 1], ["tool_shovel_stone", 1],
		["log", 32], ["coal", 12], ["copper_ingot", 6], ["coke_oven", 1], ["anvil", 1],
	]
	for p: Array in plan:
		if not _step(bot, p[0], p[1]):
			break
	check(Storage.count("wooden_collector") + Miners.total_count() > 0 or not bot.failed.is_empty(),
		"«Стажёр» выдал деревянный сборщик")
	bot.place_miners("wooden_collector", ["tree"])
	eq(Progress.era, 1, "ворота эпохи 0 → 1 пройдены")
	check(World.zone_unlocked("ore_hills"), "Рудные холмы открыты")

	plan = [
		# Эпоха 1: бронза, пар, майнеры, кованое железо, резина, первая схема.
		["tin_ore", 4], ["bronze_ingot", 8], ["tool_pickaxe_bronze", 1], ["coal_boiler", 2],
		["steam_macerator", 1], ["steam_drill", 4],
	]
	for p: Array in plan:
		if not _step(bot, p[0], p[1]):
			break
	bot.place_miners("steam_drill", ["coal_outcrop", "hills_a", "hills_b", "hills_c"])
	plan = [
		["brick_blast_furnace", 1], ["wrought_iron_ingot", 16], ["tool_pickaxe_wrought_iron", 1],
		["rubber_plate", 4], ["lv_circuit", 1], ["steam_turbine_lv", 1],
	]
	for p: Array in plan:
		if not _step(bot, p[0], p[1]):
			break
	eq(Progress.era, 2, "ворота эпохи 1 → 2: первая LV-машина")

	plan = [
		# Эпоха 2: энергосеть, никель, купроникель, EBF, сталь, MV-схема.
		["coal_boiler", 4], ["battery_buffer_lv", 1], ["lv_wiremill", 1], ["lv_alloy_smelter", 1],
		["nickel_ingot", 8], ["cupronickel_coil", 16],
	]
	for p: Array in plan:
		if not _step(bot, p[0], p[1]):
			break
	if bot.failed.is_empty():
		bot.ensure_station("ebf")
	plan = [["steel_ingot", 2], ["lv_assembler", 1], ["mv_circuit", 1]]
	for p: Array in plan:
		if not _step(bot, p[0], p[1]):
			break
	bot.tick(1.0)

	var summary := "игровое время %s, активное %s, «держал кнопку» %s, кликов %d" % [
		NumFormat.duration(GameClock.game_time), NumFormat.duration(Progress.play_time),
		NumFormat.duration(bot.manual_seconds), Progress.clicks]
	print("    бот: " + summary)
	var verbose := OS.get_cmdline_user_args().has("--verbose")
	if verbose or not bot.failed.is_empty() or not Progress.demo_finished:
		for line in bot.log_lines.slice(0 if verbose else maxi(0, bot.log_lines.size() - 25)):
			print("      " + line)
	eq(bot.failed, "", "бот не застрял")
	check(int(Progress.crafted_at.get("ebf:steel_ingot", 0)) > 0, "сталь скрафчена в EBF")
	check(Storage.total_obtained.has("mv_circuit"), "MV-схема получена")
	check(Progress.demo_finished, "экран «Конец демо»")
	var done := 0
	for qid in Registry.quest_order:
		done += 1 if Quests.is_done(qid) else 0
	print("    квестов выполнено: %d из %d" % [done, Registry.quest_order.size()])
	check(done == Registry.quest_order.size(), "все квесты выполнимы по ходу игры")
