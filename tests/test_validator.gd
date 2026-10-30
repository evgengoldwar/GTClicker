extends TestCase
## Валидатор данных: битые ссылки, недостижимые предметы, циклы квестов.

const RegistryScript := preload("res://core/registry.gd")


func _broken_registry() -> Node:
	var data := RegistryScript.load_data_dir(RegistryScript.DATA_DIR)
	(data["recipes"] as Array).append({"id": "bad_ref", "station": "furnace",
		"inputs": [{"item": "no_such_item", "n": 1}], "outputs": [{"item": "log", "n": 1}]})
	(data["items"] as Array).append({"id": "orphan", "icon": "block"})
	(data["chapters"] as Array).append({"chapter": {"id": "loop", "order": 9}, "quests": [
		{"id": "qa", "requires": ["qb"], "goals": [{"type": "checkbox"}]},
		{"id": "qb", "requires": ["qa"], "goals": [{"type": "checkbox"}]}]})
	var r: Node = RegistryScript.new()
	r.build(data)
	r.validate()
	return r


func test_real_data_is_clean() -> void:
	eq(Registry.errors.size(), 0, "ошибки в данных: %s" % str(Registry.errors))
	eq(Registry.warnings.size(), 0, "предупреждения в данных: %s" % str(Registry.warnings))


func test_detects_problems() -> void:
	var r := _broken_registry()
	var text := "\n".join(r.errors)
	check(text.contains("no_such_item"), "битая ссылка")
	check(text.contains("'orphan' нельзя получить"), "недостижимый предмет")
	check(text.contains("цикл в цепочке квестов"), "цикл квестов")
	r.free()


func test_generated_items_and_recipes() -> void:
	check(Registry.has_item("copper_ingot"), "слиток меди сгенерирован из материала")
	check(Registry.has_item("tool_pickaxe_steel"), "стальная кирка сгенерирована")
	check(Registry.recipe("smelt_ore_iron") != null, "переплавка руды по шаблону")
	check(Registry.recipe("steam_macerate_ore_iron").outputs.size() == 2, "побочный продукт руды")
	var up := Registry.recipe("craft_tool_pickaxe_steel")
	eq(up.inputs[0]["item"], "tool_pickaxe_wrought_iron", "апгрейд = старый инструмент + материал")
	check(Registry.used_in["coal"].has("bbf_wrought_iron"), "индекс «где используется» раскрывает теги")
	check(Registry.dropped_by["tin_ore"].has("vein_tin_iron"), "индекс «где добыть»")


func test_translations_cover_content() -> void:
	for locale in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		for id: String in Registry.item_order:
			check(Registry.item_name(id) != id and not Registry.item_name(id).contains("ITEM_"), "%s: нет имени для %s" % [locale, id])
		for qid: String in Registry.quest_order:
			var q := Registry.quest(qid)
			check(TranslationServer.translate(q.title_key()) != q.title_key(), "%s: нет заголовка квеста %s" % [locale, qid])
			check(TranslationServer.translate(q.desc_key()) != q.desc_key(), "%s: нет описания квеста %s" % [locale, qid])
		for nid: String in Registry.node_order:
			check(Registry.node_name(nid) != "NODE_" + nid.to_upper(), "%s: нет имени блока %s" % [locale, nid])
		for vid: String in Registry.vein_order:
			check(TranslationServer.translate("VEIN_" + vid.to_upper()) != "VEIN_" + vid.to_upper(), "%s: нет имени жилы %s" % [locale, vid])
		for f: Dictionary in Registry.features:
			if f.has("hint"):
				check(TranslationServer.translate(f["hint"]) != f["hint"], "%s: нет подсказки %s" % [locale, f["hint"]])
	TranslationServer.set_locale(Settings.language)
