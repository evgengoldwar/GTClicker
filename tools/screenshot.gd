extends Node
## Скриншоты главного экрана в разных состояниях (для проверки вёрстки без редактора).
## Запуск: xvfb-run godot --path . res://tools/screenshot.tscn -- --out=/путь/к/папке

var out_dir := "user://screenshots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	Save.slot = "screenshot"
	Settings.autosave = false
	Save.delete_save()
	var main: Control = (load("res://ui/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _shot("01_start")
	for i in 6 * 8:
		World.click("tree")
	main.call("_on_node_selected", "tree")
	await _shot("02_mining")
	# Середина эпохи 1: выдаём ресурсы, как debug-панель.
	for id in ["workbench", "furnace", "coke_oven", "anvil", "steam_macerator", "brick_blast_furnace", "coal_boiler"]:
		Storage.add(id, 1, false)
	for id in ["tool_pickaxe_bronze", "tool_axe_stone", "tool_shovel_stone", "wooden_collector", "steam_drill"]:
		Storage.add(id, 1, false)
	for id in ["log", "planks", "cobblestone", "coal", "copper_ingot", "tin_ingot", "bronze_ingot", "clay_ball", "sand",
			"brick", "iron_ore", "copper_ore", "creosote", "sticky_resin", "firebrick"]:
		Storage.add(id, 137, false)
	Progress.set_era(1)
	Quests.check_all()
	for qid in Quests.claimable():
		Quests.claim(qid)
	Progress.unlock("zone_ore_hills")
	Miners.place("tree", "wooden_collector")
	GameClock.advance(40.0)
	main.call("_on_node_selected", "hills_a")
	await _shot("03_hills")
	main.call("open_tab", "storage")
	await _shot("04_storage")
	main.call("open_tab", "stations")
	await _shot("05_stations")
	StationWindow.open(main.get("_modal_layer"), "furnace")
	await _shot("06_station_window")
	(main.get("_modal_layer") as Control).get_child(0).free()
	main.call("open_tab", "quests")
	await _shot("07_quests")
	main.call("open_tab", "power")
	await _shot("08_power")
	main.call("open_tab", "anvil")
	await _shot("09_anvil")
	LookupWindow.open(main.get("_modal_layer"), "bronze_ingot")
	await _shot("10_lookup")
	(main.get("_modal_layer") as Control).get_child(0).free()
	ReportWindows.offline(main.get("_modal_layer"), Save.run_offline(3 * 3600.0))
	await _shot("11_offline")
	(main.get("_modal_layer") as Control).get_child(0).free()
	main.call("open_tab", "settings")
	await _shot("12_settings")
	ReportWindows.demo_end(main.get("_modal_layer"))
	await _shot("13_demo_end")
	Save.delete_save()
	get_tree().quit()


func _shot(file_name: String) -> void:
	for i in 8:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(file_name + ".png"))
	print("screenshot: ", file_name)
