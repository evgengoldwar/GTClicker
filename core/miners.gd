extends Node
## Miners: ячейки майнеров на блоках карты (раздел 7). В ячейке один тип майнера, количество
## ограничено размером жилы. Дроп начисляется по ожидаемому значению через дробные накопители —
## детерминированно, поэтому офлайн-перемотка совпадает с пошаговой симуляцией.

signal cells_changed(node_id: String)

const EPS := 1e-9

## node id -> {miner: String, count: int, acc: {item: float}}
var cells: Dictionary = {}


func reset() -> void:
	cells.clear()


func cell_count(node_id: String) -> int:
	return int((cells[node_id] as Dictionary)["count"]) if cells.has(node_id) else 0


func cell_miner(node_id: String) -> String:
	return (cells[node_id] as Dictionary)["miner"] if cells.has(node_id) else ""


func total_count() -> int:
	var n := 0
	for id: String in cells:
		n += cell_count(id)
	return n


func limit(node_id: String) -> int:
	return Registry.node(node_id).vein_size


## Причина, по которой майнер нельзя поставить, или пустая строка.
func place_reason(node_id: String, miner_id: String) -> String:
	var m: MinerDef = Registry.miners.get(miner_id)
	var n := World.node_def(node_id)
	if m == null or n == null or not World.is_revealed(node_id):
		return "REASON_UNKNOWN"
	if not m.can_mine(n):
		return "REASON_MINER_TIER"
	if cell_miner(node_id) == miner_id and cell_count(node_id) >= limit(node_id):
		return "REASON_VEIN_FULL"
	if Storage.count(miner_id) <= 0:
		return "REASON_NO_ITEM"
	return ""


## Ставит один майнер. Другой тип в ячейке заменяется, старые возвращаются в хранилище.
func place(node_id: String, miner_id: String) -> bool:
	if not place_reason(node_id, miner_id).is_empty():
		return false
	var current := cell_miner(node_id)
	if not current.is_empty() and current != miner_id:
		Storage.put_back(current, cell_count(node_id))
		cells.erase(node_id)
	Storage.try_remove(miner_id, 1)
	if not cells.has(node_id):
		cells[node_id] = {"miner": miner_id, "count": 0, "acc": {}}
	cells[node_id]["count"] = cell_count(node_id) + 1
	cells_changed.emit(node_id)
	return true


func remove(node_id: String, n: int = 1) -> void:
	if not cells.has(node_id):
		return
	var k := mini(n, cell_count(node_id))
	Storage.put_back(cell_miner(node_id), k)
	cells[node_id]["count"] = cell_count(node_id) - k
	if cell_count(node_id) <= 0:
		cells.erase(node_id)
	cells_changed.emit(node_id)


func _mdef(node_id: String) -> MinerDef:
	return Registry.miners[cell_miner(node_id)]


## Блоков в секунду без учёта энергии.
func blocks_per_sec(node_id: String) -> float:
	if not cells.has(node_id):
		return 0.0
	return cell_count(node_id) * _mdef(node_id).damage_per_sec / World.node_def(node_id).hardness


func effective_blocks_per_sec(node_id: String) -> float:
	if not cells.has(node_id):
		return 0.0
	return blocks_per_sec(node_id) * Power.ratio(_mdef(node_id).energy)


## Поступление предмета в секунду от всех майнеров.
func item_rate(item_id: String) -> float:
	var total := 0.0
	for id: String in cells:
		var n := World.node_def(id)
		for d in n.drops:
			if d["item"] == item_id:
				total += effective_blocks_per_sec(id) * n.expected_drop(d)
	return total


func demand(energy: String) -> float:
	var total := 0.0
	for id: String in cells:
		var m := _mdef(id)
		if m.energy == energy:
			total += m.usage * cell_count(id)
	return total


func consumers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in cells:
		var m := _mdef(id)
		if m.energy != "none":
			out.append({"name": "%s ×%d · %s" % [Registry.item_name(m.id), cell_count(id), Registry.node_name(id)],
				"eu": m.usage * cell_count(id), "energy": m.energy})
	return out


## Через сколько секунд в хранилище появится ещё одна штука предмета (для котлов без топлива).
func time_until_item(item_id: String) -> float:
	var t := INF
	for id: String in cells:
		var n := World.node_def(id)
		var bps := effective_blocks_per_sec(id)
		if bps <= EPS:
			continue
		for d in n.drops:
			if d["item"] == item_id:
				var acc := float((cells[id]["acc"] as Dictionary).get(item_id, 0.0))
				t = minf(t, (1.0 - acc) / (bps * n.expected_drop(d)))
	return maxf(t, 0.0)


func advance(dt: float) -> void:
	for id: String in cells:
		var n := World.node_def(id)
		var blocks := effective_blocks_per_sec(id) * dt
		if blocks <= 0.0:
			continue
		var acc: Dictionary = cells[id]["acc"]
		for d in n.drops:
			var item_id: String = d["item"]
			var v := float(acc.get(item_id, 0.0)) + blocks * n.expected_drop(d)
			var whole := floori(v + EPS)
			acc[item_id] = maxf(0.0, v - whole)
			if whole > 0:
				Storage.add(item_id, whole)


## Жила сменилась: накопители предметов, которых больше нет в дропе, обнуляются.
func on_veins_rotated() -> void:
	for id: String in cells:
		var keep: Dictionary = {}
		var acc: Dictionary = cells[id]["acc"]
		for d in World.node_def(id).drops:
			keep[d["item"]] = acc.get(d["item"], 0.0)
		cells[id]["acc"] = keep
		cells_changed.emit(id)


func serialize() -> Dictionary:
	return {"cells": cells.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	reset()
	var c: Dictionary = data.get("cells", {})
	for id: String in c:
		var src: Dictionary = c[id]
		if Registry.nodes.has(id) and Registry.miners.has(src.get("miner", "")):
			var acc: Dictionary = {}
			for k: String in src.get("acc", {}):
				acc[k] = float(src["acc"][k])
			cells[id] = {"miner": src["miner"], "count": int(src.get("count", 1)), "acc": acc}
