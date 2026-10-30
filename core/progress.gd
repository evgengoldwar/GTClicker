extends Node
## Progress: текущая эпоха, открытые вкладки/системы (онбординг, раздел 2), статистика игры
## и общий вычислитель условий для unlocks.json и появления блоков на карте.

var era := 0
var features: Dictionary = {}     # id -> true
var clicks := 0
var play_time := 0.0              # активное время онлайн, сек
var broken: Dictionary = {}       # node id -> int (ручная добыча)
var crafted: Dictionary = {}      # item id -> int
var crafted_at: Dictionary = {}   # "station:item" -> int
var repairs := 0
var tools_broken := 0
var demo_finished := false


func _ready() -> void:
	Events.item_obtained.connect(func(_id: String, _n: int) -> void: check_features())
	Events.quest_completed.connect(func(_id: String) -> void: check_features())
	Events.crafted.connect(_on_crafted)
	Events.block_broken.connect(_on_block_broken)
	GameClock.ticked.connect(func(dt: float) -> void: play_time += dt)


func reset() -> void:
	era = 0
	features.clear()
	clicks = 0
	play_time = 0.0
	broken.clear()
	crafted.clear()
	crafted_at.clear()
	repairs = 0
	tools_broken = 0
	demo_finished = false


func has_feature(id: String) -> bool:
	return features.has(id)


func unlock(id: String) -> void:
	if features.has(id):
		return
	features[id] = true
	Events.feature_unlocked.emit(id)


func set_era(value: int) -> void:
	if value <= era:
		return
	era = value
	Events.era_changed.emit(era)
	check_features()


func finish_demo() -> void:
	if demo_finished:
		return
	demo_finished = true
	Events.demo_finished.emit()


func check_features() -> void:
	for f: Dictionary in Registry.features:
		if not features.has(f["id"]) and check(f.get("when", {})):
			unlock(f["id"])


## Условие из данных: obtained / discovered / quest / era / feature / any / all.
func check(cond: Dictionary) -> bool:
	if cond.is_empty():
		return true
	for key: String in cond:
		var v: Variant = cond[key]
		var ok := false
		match key:
			"obtained":
				ok = true
				for id: String in v:
					ok = ok and int(Storage.total_obtained.get(id, 0)) >= int(v[id])
			"discovered":
				ok = Storage.is_discovered(v)
			"quest":
				ok = Quests.is_done(v)
			"era":
				ok = era >= int(v)
			"feature":
				ok = has_feature(v)
			"any":
				for sub: Dictionary in v:
					ok = ok or check(sub)
			"all":
				ok = true
				for sub: Dictionary in v:
					ok = ok and check(sub)
			_:
				push_error("[Progress] неизвестное условие '%s'" % key)
		if not ok:
			return false
	return true


## Показатели для квестов типа stat.
func stat(stat_name: String) -> float:
	match stat_name:
		"steam_gen":
			return Power.steam_gen
		"eu_gen":
			return Power.eu_gen
		"miners":
			return Miners.total_count()
		"ebf_built":
			return Stations.instance_count("ebf")
		"era":
			return era
		"repairs":
			return repairs
		"clicks":
			return clicks
	push_error("[Progress] неизвестный показатель '%s'" % stat_name)
	return 0.0


func _on_crafted(item_id: String, amount: int, station_id: String, _recipe_id: String) -> void:
	crafted[item_id] = int(crafted.get(item_id, 0)) + amount
	var key := station_id + ":" + item_id
	crafted_at[key] = int(crafted_at.get(key, 0)) + amount


func _on_block_broken(node_id: String, manual: bool) -> void:
	if manual:
		broken[node_id] = int(broken.get(node_id, 0)) + 1


func serialize() -> Dictionary:
	return {"era": era, "features": features.keys(), "clicks": clicks, "play_time": play_time,
		"broken": broken.duplicate(), "crafted": crafted.duplicate(), "crafted_at": crafted_at.duplicate(),
		"repairs": repairs, "tools_broken": tools_broken, "demo_finished": demo_finished}


func deserialize(data: Dictionary) -> void:
	reset()
	era = int(data.get("era", 0))
	for f: String in data.get("features", []):
		features[f] = true
	clicks = int(data.get("clicks", 0))
	play_time = float(data.get("play_time", 0.0))
	for k: String in data.get("broken", {}):
		broken[k] = int(data["broken"][k])
	for k: String in data.get("crafted", {}):
		crafted[k] = int(data["crafted"][k])
	for k: String in data.get("crafted_at", {}):
		crafted_at[k] = int(data["crafted_at"][k])
	repairs = int(data.get("repairs", 0))
	tools_broken = int(data.get("tools_broken", 0))
	demo_finished = bool(data.get("demo_finished", false))
