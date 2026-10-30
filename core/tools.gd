extends Node
## Tools: пояс инструментов (по одному активному на тип), прочность за разбитый блок,
## поломка с возвратом 50% головки, ремонт на наковальне (раздел 4).

## type -> {item: String, durability: int}
var belt: Dictionary = {}


func _ready() -> void:
	Events.item_obtained.connect(_on_item_obtained)


func reset() -> void:
	belt.clear()


func equipped(type: String) -> String:
	return (belt[type] as Dictionary)["item"] if belt.has(type) else ""


func durability(type: String) -> int:
	return int((belt[type] as Dictionary)["durability"]) if belt.has(type) else 0


func max_durability(type: String) -> int:
	var id := equipped(type)
	return int(Registry.item(id).tool["durability"]) if not id.is_empty() else 0


func durability_fraction(type: String) -> float:
	var m := max_durability(type)
	return float(durability(type)) / m if m > 0 else 0.0


func tool_tier(type: String) -> int:
	var id := equipped(type)
	return int(Registry.item(id).tool["tool_tier"]) if not id.is_empty() else -1


func tool_damage(type: String) -> float:
	var id := equipped(type)
	return float(Registry.item(id).tool["damage"]) if not id.is_empty() else 0.0


## Сколько экземпляров инструмента доступно рецепту: в хранилище плюс надетый.
func available(item_id: String) -> int:
	var it := Registry.item(item_id)
	var n := Storage.count(item_id)
	if it != null and it.kind == "tool" and equipped(it.tool["type"]) == item_id:
		n += 1
	return n


## Снимает инструмент в хранилище (перед списанием в рецепт апгрейда).
func unequip_to_storage(type: String) -> void:
	var id := equipped(type)
	if id.is_empty():
		return
	belt.erase(type)
	Storage.put_back(id, 1)
	Events.tool_equipped.emit(type)


## Урон и тир, которыми игрок бьёт блок: свой тип инструмента, чужой (×0.25) или руки.
func hit_for(node: NodeDef) -> Dictionary:
	var mining := Registry.mining_balance()
	var hand := {"damage": float(mining.get("hand_damage", 1)), "tier": -1, "type": ""}
	if node.tool_type == "any":
		var best := hand
		for type: String in belt:
			if tool_damage(type) > float(best["damage"]):
				best = {"damage": tool_damage(type), "tier": tool_tier(type), "type": type}
		return best
	if belt.has(node.tool_type):
		return {"damage": tool_damage(node.tool_type), "tier": tool_tier(node.tool_type), "type": node.tool_type}
	# Своего инструмента нет: руки или чужой инструмент с множителем; берём сильнейший из подходящих.
	var mult := float(mining.get("wrong_tool_mult", 0.25))
	var best := hand if node.min_tool_tier <= -1 else {}
	for type: String in belt:
		if tool_tier(type) >= node.min_tool_tier and (best.is_empty() or tool_damage(type) * mult > float(best["damage"])):
			best = {"damage": tool_damage(type) * mult, "tier": tool_tier(type), "type": type}
	return hand if best.is_empty() else best


## Блок разбит инструментом типа type: −1 прочности, поломка с возвратом материала.
func on_block_broken(type: String) -> void:
	if type.is_empty() or not belt.has(type):
		return
	var slot: Dictionary = belt[type]
	slot["durability"] = int(slot["durability"]) - 1
	var frac := durability_fraction(type)
	var bal := Registry.tool_balance()
	var max_d := max_durability(type)
	if int(slot["durability"]) == ceili(max_d * float(bal.get("warn_fraction", 0.2))) \
			or int(slot["durability"]) == ceili(max_d * float(bal.get("alert_fraction", 0.05))):
		Events.tool_durability_warning.emit(type, frac)
	if int(slot["durability"]) <= 0:
		_break_tool(type)


func _break_tool(type: String) -> void:
	var id := equipped(type)
	var t: Dictionary = Registry.item(id).tool
	belt.erase(type)
	var back := roundi(int(t["head_cost"]) * float(Registry.tool_balance().get("break_return", 0.5)))
	Storage.add(t["head_item"], back, false)
	Progress.tools_broken += 1
	Events.tool_broken.emit(type, id)
	# Если в хранилище есть запасной инструмент этого типа — надеваем лучший.
	_equip_best_from_storage(type)


func _on_item_obtained(item_id: String, _amount: int) -> void:
	var it := Registry.item(item_id)
	if it == null or it.kind != "tool":
		return
	var type: String = it.tool["type"]
	if int(it.tool["tool_tier"]) > tool_tier(type):
		equip(item_id)


## Надевает инструмент из хранилища; предыдущий возвращается в хранилище.
func equip(item_id: String) -> bool:
	var it := Registry.item(item_id)
	if it == null or it.kind != "tool" or not Storage.try_remove(item_id, 1):
		return false
	var type: String = it.tool["type"]
	var old := equipped(type)
	if not old.is_empty():
		Storage.put_back(old, 1)
	belt[type] = {"item": item_id, "durability": int(it.tool["durability"])}
	Events.tool_equipped.emit(type)
	return true


func _equip_best_from_storage(type: String) -> void:
	var best := ""
	var best_tier := -1
	for id: String in Storage.counts:
		var it := Registry.item(id)
		if it != null and it.kind == "tool" and it.tool["type"] == type and Storage.count(id) > 0 \
				and int(it.tool["tool_tier"]) > best_tier:
			best = id
			best_tier = int(it.tool["tool_tier"])
	if not best.is_empty():
		equip(best)


# --- Ремонт ---------------------------------------------------------------------------------

## Стоимость восстановления доли fraction (0..1) прочности: доля × стоимость головки × 0.6.
func repair_cost(type: String, fraction: float) -> Dictionary:
	var id := equipped(type)
	if id.is_empty():
		return {}
	var t: Dictionary = Registry.item(id).tool
	var lost := 1.0 - durability_fraction(type)
	var f := clampf(fraction, 0.0, lost)
	if f <= 0.0:
		return {}
	var n := ceili(f * int(t["head_cost"]) * float(Registry.tool_balance().get("repair_cost_mult", 0.6)) - 1e-9)
	return {t["head_item"]: maxi(1, n)}


func can_repair() -> bool:
	return Stations.instance_count("anvil") > 0


func repair(type: String, fraction: float) -> bool:
	if not can_repair():
		return false
	var cost := repair_cost(type, fraction)
	if cost.is_empty() or not Storage.try_remove_all(cost):
		return false
	var slot: Dictionary = belt[type]
	var m := max_durability(type)
	slot["durability"] = mini(m, int(slot["durability"]) + ceili(clampf(fraction, 0.0, 1.0) * m))
	Progress.repairs += 1
	Events.tool_equipped.emit(type)
	return true


func serialize() -> Dictionary:
	return {"belt": belt.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	reset()
	var b: Dictionary = data.get("belt", {})
	for type: String in b:
		var id: String = (b[type] as Dictionary).get("item", "")
		if Registry.has_item(id):
			belt[type] = {"item": id, "durability": int(b[type].get("durability", 1))}
