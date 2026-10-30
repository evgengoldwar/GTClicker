extends TestCase
## Сохранение → загрузка → миграция, резервные копии, неизвестные id, экспорт base64.


func _sample_state() -> void:
	give({"log": 42, "cobblestone": 7, "tool_pickaxe_wood": 1, "wooden_collector": 1})
	install("furnace", 2)
	Miners.place("tree", "wooden_collector")
	give({"clay_ball": 3})
	Stations.enqueue("furnace_brick", 3)
	Power.install("coal_boiler")
	Progress.set_era(1)
	Quests.check_all()
	GameClock.advance(5.0)


func test_roundtrip() -> void:
	_sample_state()
	var a := Save.to_dict()
	Save.new_game()
	eq(Storage.count("log"), 0, "новая игра пуста")
	check(Save.from_dict(JSON.parse_string(JSON.stringify(a))), "загрузка из JSON")
	var b := Save.to_dict()
	a.erase("time")
	b.erase("time")
	eq(JSON.stringify(b), JSON.stringify(a), "состояние после загрузки совпадает")
	eq(Tools.equipped("pickaxe"), "tool_pickaxe_wood", "пояс инструментов")
	eq(Stations.queued_count("furnace"), 3, "очередь крафта")
	eq(Miners.cell_count("tree"), 1, "майнер в ячейке")


func test_file_save_load_and_backups() -> void:
	_sample_state()
	Save.delete_save()
	for i in 5:
		Storage.add("log", 1)
		check(Save.save_game(), "сохранение %d" % i)
	for i in 4:
		check(FileAccess.file_exists(Save.save_path(i)), "файл/копия %d существует" % i)
	check(not FileAccess.file_exists(Save.save_path(4)), "копий не больше трёх")
	check(not FileAccess.file_exists(Save.save_path() + ".tmp"), "временный файл убран")
	var logs := Storage.count("log")
	Save.new_game()
	check(Save.load_game(false), "загрузка с диска")
	eq(Storage.count("log"), logs, "количество совпадает")


func test_corrupted_main_falls_back_to_backup() -> void:
	_sample_state()
	Save.delete_save()
	Save.save_game()
	var logs := Storage.count("log")
	Storage.add("log", 100)
	Save.save_game()
	var f := FileAccess.open(Save.save_path(), FileAccess.WRITE)
	f.store_string("{битый json")
	f.close()
	Save.new_game()
	check(Save.load_game(false), "загрузилась резервная копия")
	eq(Storage.count("log"), logs, "состояние из .bak1")


func test_migration_v1_to_v2() -> void:
	var v1 := {"version": 1, "time": 0, "storage": {"log": "1.2e3", "copper_ingot": "7.8e15", "cobblestone": "1e40"}}
	check(Save.from_dict(v1), "сейв v1 загружается")
	eq(Storage.count("log"), 1200, "строка BigNum → int")
	eq(Storage.count("copper_ingot"), 7800000000000000, "7.8e15 точно")
	eq(Storage.count("cobblestone"), Qty.MAX, "1e40 насыщается до int64")
	check(Storage.is_discovered("copper_ingot"), "discovered восстановлен")
	eq(int(Save.migrate(v1)["version"]), Save.VERSION, "версия поднята до текущей")
	check(Save.migrate({"version": 99}).is_empty(), "сейв из будущего отклонён")


func test_unknown_ids_preserved() -> void:
	var data := Save.to_dict()
	data["storage"]["counts"]["removed_mod_item"] = 5
	data["storage"]["counts"]["log"] = 3
	check(Save.from_dict(data), "загрузка с неизвестным предметом")
	eq(Storage.count("log"), 3, "известное загружено")
	eq(int(Save.to_dict()["storage"]["counts"]["removed_mod_item"]), 5, "неизвестное сохранено обратно")


func test_export_import_string() -> void:
	_sample_state()
	var logs := Storage.count("log")
	var s := Save.export_string()
	check(s.begins_with(Save.EXPORT_PREFIX), "префикс")
	Save.new_game()
	check(Save.import_string(s), "импорт")
	eq(Storage.count("log"), logs, "состояние восстановлено")
	check(not Save.import_string("мусор"), "мусор отклонён")


func test_offline_on_load_capped() -> void:
	give({"wooden_collector": 1})
	Miners.place("tree", "wooden_collector")
	var data := Save.to_dict()
	data["time"] = Time.get_unix_time_from_system() - 20 * 3600
	Save.delete_save()
	DirAccess.make_dir_recursive_absolute(Save.save_dir())
	var f := FileAccess.open(Save.save_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	check(Save.load_game(true), "загрузка с офлайном")
	var r := Save.last_report
	near(float(r["seconds"]), 12 * 3600.0, 1.0, "офлайн обрезан до 12 ч")
	check(bool(r["capped"]), "отчёт знает про лимит")
	eq(int(r["gained"]["log"]), 8640, "0.2 бревна/с × 12 ч")
