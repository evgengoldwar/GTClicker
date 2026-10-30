extends TestCase
## Формулы оверклока, энергии, апгрейдов и баланса добычи (раздел 15, правка 7).


func test_overclock_formulas() -> void:
	near(Formulas.speed_multiplier(0, 0, 0.0), 1.0, 1e-9, "без оверклока")
	near(Formulas.speed_multiplier(1, 0, 0.0), 2.0, 1e-9, "1 оверклок = ×2 скорость")
	near(Formulas.speed_multiplier(2, 0, 0.5), 6.0, 1e-9, "2 оверклока и +50% апгрейдов")
	near(Formulas.speed_multiplier(1, 1, 0.0), 4.0, 1e-9, "идеальный оверклок = ×4")
	near(Formulas.speed_multiplier(1, 3, 0.0), 4.0, 1e-9, "идеальных не больше, чем оверклоков")
	near(Formulas.eut_multiplier(1, 0.0, 0, 0.05), 4.0, 1e-9, "1 оверклок = ×4 мощность")
	near(Formulas.eut_multiplier(0, 0.25, 0, 0.05), 0.75, 1e-9, "энергоэффективность 25%")
	near(Formulas.eut_multiplier(0, 0.0, 2, 0.05), 0.9025, 1e-9, "две скидки за нагрев по 5%")


func test_energy_per_craft_doubles_per_overclock() -> void:
	# EU на крафт = EU/t · время: ×4 мощности и ×2 скорости дают ×2 энергии на крафт.
	var base := 8.0 * 100.0
	var oc := 8.0 * Formulas.eut_multiplier(1, 0.0, 0, 0.05) * 100.0 / Formulas.speed_multiplier(1, 0, 0.0)
	near(oc / base, 2.0, 1e-9, "энергия на крафт ×2")


func test_station_overclock_ulv_recipe_in_lv_machine() -> void:
	install("lv_wiremill")
	var r := Registry.recipe("lv_wiremill_copper")  # 8 EU/t = ULV, станция LV
	eq(Stations.overclocks("lv_wiremill", r), 1, "ULV-рецепт в LV-станции разгоняется")
	near(Stations.craft_ticks("lv_wiremill", r), 50.0, 1e-6, "100 тиков / 2")
	near(Stations.craft_eut("lv_wiremill", r), 32.0, 1e-6, "8 EU/t × 4")
	var steel := Registry.recipe("ebf_steel")
	eq(Stations.overclocks("ebf", steel), 0, "сталь — рецепт LV, без оверклока")
	check(steel.eu <= 32.0, "сталь в EBF укладывается в LV (правка 1)")


func test_upgrades_cost_and_effect() -> void:
	install("furnace")
	eq(Formulas.upgrade_cost(48, 1.6, 0), 48, "уровень 0")
	eq(Formulas.upgrade_cost(48, 1.6, 2), 123, "48·1.6² = 122.88 → 123")
	give({"cobblestone": 48})
	check(Stations.buy_upgrade("furnace", "speed"), "покупка апгрейда скорости")
	eq(Stations.upgrade_level("furnace", "speed"), 1, "уровень 1")
	near(Stations.craft_ticks("furnace", Registry.recipe("furnace_brick")), 160.0 / 1.1, 1e-6, "+10% скорости")
	check(not Stations.can_upgrade("furnace", "efficiency"), "у печи без энергии нет энергоэффективности")
	eq(int(Stations.upgrade_cost("furnace", "speed")["cobblestone"]), 77, "дорожает ×1.6")


func _damage_for_tier(tier: int) -> float:
	if tier < 0:
		return float(Registry.mining_balance()["hand_damage"])
	for id: String in Registry.materials:
		var m: Dictionary = Registry.materials[id]
		if m.has("tool") and int(m["tool"]["tool_tier"]) == tier:
			return float(m["tool"]["damage"])
	return -1.0


func test_mining_balance_new_resources_8_to_12_clicks() -> void:
	for id: String in Registry.node_order + Registry.vein_order:
		var n: NodeDef = Registry.nodes[id] if Registry.nodes.has(id) else Registry.veins[id]
		if n.vein_slot >= 0:
			continue
		var clicks := Formulas.clicks_for(n.hardness, _damage_for_tier(n.era_tool_tier))
		check(clicks >= 8 and clicks <= 12, "%s: %d кликов инструментом своего тира" % [id, clicks])


func test_mining_balance_old_resources_1_to_2_clicks() -> void:
	for id: String in Registry.node_order:
		var n: NodeDef = Registry.nodes[id]
		if n.vein_slot >= 0 or n.era_tool_tier > 1:
			continue
		var tier := 2 if n.era_tool_tier <= 0 else 4
		var clicks := Formulas.clicks_for(n.hardness, _damage_for_tier(tier))
		check(clicks <= 2, "%s: %d кликов инструментом тира %d" % [id, clicks, tier])
