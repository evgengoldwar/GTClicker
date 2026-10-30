extends TestCase
## Дымовой тест интерфейса: главный экран, онбординг вкладок, все панели и окна открываются
## без ошибок скриптов (headless, без отрисовки).


func test_main_screen_and_panels() -> void:
	Save.delete_save()
	var tree := Engine.get_main_loop() as SceneTree
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	var tabs: Dictionary = main.get("_tab_buttons")
	check(not (tabs["storage"] as Button).visible, "хранилище скрыто до 5 брёвен")
	for i in 5 * 8:
		World.click("tree")
	check((tabs["storage"] as Button).visible, "5 брёвен открыли вкладку «Хранилище»")
	check(not (tabs["stations"] as Button).visible, "станции ещё скрыты")
	main.call("_on_node_selected", "tree")
	eq((main.get("mining") as MiningPanel).node_id, "tree", "панель добычи открыта")
	_unlock_all()
	for id in ["storage", "stations", "quests", "anvil", "power", "settings", "map"]:
		main.call("open_tab", id)
		main.call("_process", 1.0)
	var modal: Control = main.get("_modal_layer")
	for sid in ["hand", "furnace", "ebf"]:
		StationWindow.open(modal, sid)
	LookupWindow.open(modal, "bronze_ingot")
	DebugPanel.open(modal, func(_r: Dictionary) -> void: pass)
	ReportWindows.offline(modal, Save.run_offline(600.0))
	ReportWindows.demo_end(modal)
	check(modal.get_child_count() >= 7, "все окна открылись")
	main.call("toast", "тест", "info")
	main.call("_on_deficit", 0.5)
	main.queue_free()
	Save.delete_save()


## То же, что кнопка «Открыть эпоху» в debug-панели.
func _unlock_all() -> void:
	Progress.set_era(2)
	for f: Dictionary in Registry.features:
		Progress.unlock(f["id"])
	for id in ["workbench", "furnace", "anvil", "coal_boiler", "steam_turbine_lv", "ebf_controller"]:
		Storage.add(id, 1, false)
	Quests.check_all()
