extends Node
## Простой раннер тестов на чистом GDScript.
## Запуск: godot --headless --path . res://tests/test_runner.tscn [-- --filter=имя]

const DIR := "res://tests"


func _ready() -> void:
	GameClock.paused = true
	Settings.autosave = false
	Save.slot = "test"
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
	var total := 0
	var failed := 0
	var started := Time.get_ticks_msec()
	for file in DirAccess.get_files_at(DIR):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd" \
				or file == "test_runner.gd":
			continue
		var script: GDScript = load(DIR + "/" + file)
		for m in script.get_script_method_list():
			var method: String = m["name"]
			if not method.begins_with("test_") or (not filter.is_empty() and not (file + method).contains(filter)):
				continue
			total += 1
			Save.new_game()
			var t: TestCase = script.new()
			var t0 := Time.get_ticks_msec()
			t.call(method)
			var ms := Time.get_ticks_msec() - t0
			if t.failures.is_empty():
				print("  ok   %s::%s (%d мс)" % [file.get_basename(), method, ms])
			else:
				failed += 1
				print("  FAIL %s::%s" % [file.get_basename(), method])
				for f in t.failures:
					print("         - " + f)
	Save.delete_save()
	print("\nТестов: %d, упало: %d, время %.1f с" % [total, failed, (Time.get_ticks_msec() - started) / 1000.0])
	get_tree().quit(1 if failed > 0 or total == 0 else 0)
