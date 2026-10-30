extends Node
## Storage: единое хранилище без лимита (раздел 3). Количества — int64 с насыщением,
## discovered — всё когда-либо полученное, доход — скользящее среднее за окно.

## Изменилось количество предмета. Испускается пачками не чаще 10 раз в секунду.
signal changed(item_id: String)

const EMIT_INTERVAL := 0.1

var counts: Dictionary = {}          # id -> int
var discovered: Dictionary = {}      # id -> true
var total_obtained: Dictionary = {}  # id -> int, за всю игру

var _dirty: Dictionary = {}
var _emit_timer := 0.0
var _income_window: Array[Dictionary] = []
var _income_current: Dictionary = {}
var _income_timer := 0.0
var _income_cache: Dictionary = {}


func _process(delta: float) -> void:
	_emit_timer += delta
	if _emit_timer < EMIT_INTERVAL or _dirty.is_empty():
		return
	_emit_timer = 0.0
	var ids := _dirty.keys()
	_dirty.clear()
	for id: String in ids:
		changed.emit(id)


func reset() -> void:
	counts.clear()
	discovered.clear()
	total_obtained.clear()
	_dirty.clear()
	_income_window.clear()
	_income_current.clear()
	_income_cache.clear()
	_income_timer = 0.0


func count(id: String) -> int:
	return counts.get(id, 0)


func is_discovered(id: String) -> bool:
	return discovered.has(id)


## Добавляет предмет. counts_as_income=false для наград и выдачи из debug-панели.
func add(id: String, amount: int, counts_as_income: bool = true) -> void:
	if amount <= 0:
		return
	counts[id] = Qty.add(count(id), amount)
	total_obtained[id] = Qty.add(total_obtained.get(id, 0), amount)
	if counts_as_income:
		_income_current[id] = Qty.add(_income_current.get(id, 0), amount)
	_dirty[id] = true
	if not discovered.has(id):
		discovered[id] = true
		Events.item_discovered.emit(id)
	Events.item_obtained.emit(id, amount)


## Возврат ранее списанного (снятый инструмент, отменённый крафт) без статистики и событий.
func put_back(id: String, amount: int) -> void:
	counts[id] = Qty.add(count(id), amount)
	_dirty[id] = true


func try_remove(id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if count(id) < amount:
		return false
	counts[id] = count(id) - amount
	_dirty[id] = true
	return true


func has_all(cost: Dictionary) -> bool:
	for id: String in cost:
		if count(id) < int(cost[id]):
			return false
	return true


## Атомарное списание пачки: либо всё, либо ничего.
func try_remove_all(cost: Dictionary) -> bool:
	if not has_all(cost):
		return false
	for id: String in cost:
		try_remove(id, int(cost[id]))
	return true


## Средний доход в секунду за окно balance.income_window_sec.
func income(id: String) -> float:
	return _income_cache.get(id, 0.0)


## Вызывается GameClock после онлайн-тика.
func sample_income(dt: float) -> void:
	_income_timer += dt
	if _income_timer < 1.0:
		return
	_income_timer -= 1.0
	_income_window.append(_income_current)
	_income_current = {}
	var window := int(Registry.balance.get("income_window_sec", 10))
	while _income_window.size() > window:
		_income_window.pop_front()
	_income_cache.clear()
	for sample in _income_window:
		for id: String in sample:
			_income_cache[id] = float(_income_cache.get(id, 0.0)) + float(sample[id]) / window


func clear_income() -> void:
	_income_window.clear()
	_income_current.clear()
	_income_cache.clear()


func serialize() -> Dictionary:
	return {"counts": counts.duplicate(), "discovered": discovered.keys(), "total": total_obtained.duplicate()}


## Неизвестные id (удалённый предмет, отключённый мод) уходят в unknown и не теряются.
func deserialize(data: Dictionary, unknown: Dictionary) -> void:
	reset()
	var lost: Dictionary = unknown.get_or_add("storage", {})
	for id: String in data.get("counts", {}):
		var n := int(data["counts"][id])
		if Registry.has_item(id):
			counts[id] = n
		else:
			lost[id] = n
	for id: String in data.get("discovered", []):
		if Registry.has_item(id):
			discovered[id] = true
	for id: String in data.get("total", {}):
		if Registry.has_item(id):
			total_obtained[id] = int(data["total"][id])
	for id: String in counts:
		_dirty[id] = true
