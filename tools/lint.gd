extends Node
## Компилирует все скрипты проекта. Запускается из tools/check.sh вместе с override.cfg,
## где предупреждения GDScript подняты до уровня ошибки. Сцена, а не -s, чтобы были видны автолоады.

const SELF := "res://tools/lint.gd"


func _ready() -> void:
	var files: Array[String] = []
	_collect("res://", files)
	var failed := 0
	for path in files:
		if path == SELF:
			continue
		var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		if script == null or not script.can_instantiate():
			failed += 1
			printerr("LINT FAIL: ", path)
	print("lint: %d скриптов, ошибок: %d" % [files.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)


func _collect(dir: String, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_collect(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
