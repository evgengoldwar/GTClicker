extends Node
## Save: сохранение/загрузка (раздел 14). JSON с полем version и цепочкой миграций,
## автосейв раз в 60 с и при выходе, запись через временный файл + 3 резервные копии,
## экспорт/импорт строкой base64, офлайн-прогресс при загрузке (лимит 12 ч).

signal saved()
## Загрузка завершена; report — отчёт офлайна или {} если офлайна не было.
signal loaded(report: Dictionary)

const VERSION := 2
const EXPORT_PREFIX := "GC2:"
const MIN_OFFLINE_SEC := 60.0

var slot := "0"
## Неизвестные id из сейва (удалённые предметы, отключённые моды) — хранятся и пишутся обратно.
var unknown: Dictionary = {}
var last_report: Dictionary = {}

var _autosave_timer := 0.0
var _migrations: Dictionary = {1: _migrate_1_to_2}


func _ready() -> void:
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if Settings.autosave:
			save_game()
		get_tree().quit()


func _process(delta: float) -> void:
	if not Settings.autosave or GameClock.paused:
		return
	_autosave_timer += delta
	if _autosave_timer >= float((Registry.balance.get("save", {}) as Dictionary).get("autosave_sec", 60)):
		_autosave_timer = 0.0
		save_game()


func save_dir() -> String:
	return "user://saves"


func save_path(index: int = 0) -> String:
	var base := "%s/save_%s.json" % [save_dir(), slot]
	return base if index == 0 else "%s.bak%d" % [base, index]


# --- Состояние ------------------------------------------------------------------------------

func new_game() -> void:
	unknown = {}
	last_report = {}
	GameClock.reset()
	Storage.reset()
	Progress.reset()
	Tools.reset()
	World.reset()
	Power.reset()
	Stations.reset()
	Miners.reset()
	Quests.reset()
	Quests.check_all()
	Events.state_reset.emit()


func to_dict() -> Dictionary:
	var storage := Storage.serialize()
	var lost: Dictionary = unknown.get("storage", {})
	for id: String in lost:
		storage["counts"][id] = lost[id]
	return {
		"version": VERSION,
		"time": Time.get_unix_time_from_system(),
		"clock": GameClock.serialize(),
		"storage": storage,
		"progress": Progress.serialize(),
		"tools": Tools.serialize(),
		"world": World.serialize(),
		"power": Power.serialize(),
		"stations": Stations.serialize(),
		"miners": Miners.serialize(),
		"quests": Quests.serialize(),
	}


## Применяет словарь сейва (после миграций). Возвращает false, если формат не распознан.
func from_dict(raw: Dictionary) -> bool:
	var data := migrate(raw)
	if data.is_empty():
		return false
	unknown = {}
	GameClock.deserialize(data.get("clock", {}))
	Storage.deserialize(data.get("storage", {}), unknown)
	Progress.deserialize(data.get("progress", {}))
	Tools.deserialize(data.get("tools", {}))
	World.deserialize(data.get("world", {}))
	Power.deserialize(data.get("power", {}))
	Stations.deserialize(data.get("stations", {}))
	Miners.deserialize(data.get("miners", {}))
	Quests.deserialize(data.get("quests", {}))
	Quests.check_all()
	Progress.check_features()
	Events.state_reset.emit()
	return true


# --- Миграции -------------------------------------------------------------------------------

func migrate(raw: Dictionary) -> Dictionary:
	var data := raw.duplicate(true)
	var v := int(data.get("version", 0))
	if v <= 0 or v > VERSION:
		push_warning("[Save] неподдерживаемая версия сейва: %d" % v)
		return {}
	while v < VERSION:
		var step: Callable = _migrations[v]
		data = step.call(data)
		v += 1
		data["version"] = v
	return data


## v1 хранил количества строками BigNum ("7.8e15"); v2 — int64 с насыщением (правка 3).
func _migrate_1_to_2(data: Dictionary) -> Dictionary:
	var storage: Dictionary = data.get("storage", {})
	var counts: Dictionary = {}
	for id: String in storage:
		counts[id] = Qty.from_float(float(str(storage[id])))
	data["storage"] = {"counts": counts, "discovered": counts.keys(), "total": counts.duplicate()}
	return data


# --- Файлы ----------------------------------------------------------------------------------

## Запись через временный файл и переименование; предыдущие версии сдвигаются в .bak1–.bak3.
func save_game() -> bool:
	DirAccess.make_dir_recursive_absolute(save_dir())
	var tmp := save_path() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[Save] не удалось открыть %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	var backups := int((Registry.balance.get("save", {}) as Dictionary).get("backups", 3))
	for i in range(backups, 0, -1):
		var from := save_path(i - 1)
		if FileAccess.file_exists(from):
			if FileAccess.file_exists(save_path(i)):
				DirAccess.remove_absolute(save_path(i))
			if i == 1:
				DirAccess.copy_absolute(from, save_path(1))
			else:
				DirAccess.rename_absolute(from, save_path(i))
	if FileAccess.file_exists(save_path()):
		DirAccess.remove_absolute(save_path())
	var err := DirAccess.rename_absolute(tmp, save_path())
	if err != OK:
		push_error("[Save] не удалось переименовать сейв: %s" % error_string(err))
		return false
	saved.emit()
	return true


func has_save() -> bool:
	for i in 4:
		if FileAccess.file_exists(save_path(i)):
			return true
	return false


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return json.data if json.data is Dictionary else {}


## Загружает основной сейв (или первую целую резервную копию) и считает офлайн-прогресс.
func load_game(apply_offline: bool = true) -> bool:
	for i in 4:
		var data := _read(save_path(i))
		if data.is_empty():
			continue
		if i > 0:
			push_warning("[Save] основной сейв повреждён, загружена копия .bak%d" % i)
		if not from_dict(data):
			continue
		last_report = {}
		if apply_offline:
			var elapsed := Time.get_unix_time_from_system() - float(data.get("time", 0.0))
			last_report = run_offline(elapsed)
		loaded.emit(last_report)
		return true
	return false


## Офлайн-прогресс за seconds (обрезается до лимита). Возвращает отчёт или {} если мало времени.
func run_offline(seconds: float) -> Dictionary:
	if seconds < MIN_OFFLINE_SEC:
		return {}
	var max_sec := float((Registry.balance.get("offline", {}) as Dictionary).get("max_hours", 12)) * 3600.0
	var report := GameClock.simulate_offline(minf(seconds, max_sec))
	report["away"] = seconds
	report["capped"] = seconds > max_sec
	return report


func delete_save() -> void:
	for i in 4:
		if FileAccess.file_exists(save_path(i)):
			DirAccess.remove_absolute(save_path(i))


# --- Экспорт / импорт -----------------------------------------------------------------------

func export_string() -> String:
	var bytes := JSON.stringify(to_dict()).to_utf8_buffer()
	return EXPORT_PREFIX + Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_GZIP))


## Импорт строки из export_string(). Офлайн по импорту не считается.
func import_string(text: String) -> bool:
	var s := text.strip_edges()
	if not s.begins_with(EXPORT_PREFIX):
		return false
	var packed := Marshalls.base64_to_raw(s.substr(EXPORT_PREFIX.length()))
	if packed.is_empty():
		return false
	var bytes := packed.decompress_dynamic(64 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		return false
	return from_dict(json.data)
