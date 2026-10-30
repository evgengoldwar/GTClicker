class_name Bot
extends RefCounted
## Бот-игрок для сквозного теста: пользуется только командами автолоадов (как UI) и ускоренным
## временем. Цель «получить N предметов» решается рекурсивно по индексам Registry:
## добыча руками → майнеры → рецепт на доступной станции → постройка нужной станции.

const CLICK_SEC := 0.2          # зажатая кнопка = 5 кликов/с
const WAIT_STEP := 5.0
const MAX_WAIT := 4 * 3600.0
const MAX_DEPTH := 40

var log_lines: Array[String] = []
var failed := ""
var manual_seconds := 0.0       # время, которое бот «держал кнопку»
var _stack: Dictionary = {}
var _fueling := false


func fail(msg: String) -> bool:
	if failed.is_empty():
		failed = msg
		log_lines.append("FAIL: " + msg)
	return false


func note(msg: String) -> void:
	log_lines.append("[%s] %s" % [NumFormat.duration(GameClock.game_time), msg])


# --- Состояние -------------------------------------------------------------------------------

func have(item_id: String) -> int:
	var it := Registry.item(item_id)
	match it.kind:
		"station":
			return Stations.instance_count(Registry.station_by_item[item_id])
		"generator":
			return Power.count(item_id)
		"tool":
			return Tools.available(item_id)
	return Storage.count(item_id)


func tick(seconds: float) -> void:
	GameClock.advance(seconds)
	claim_quests()


func claim_quests() -> void:
	for qid: String in Registry.quest_order:
		if Quests.state(qid) == Quests.State.AVAILABLE:
			for g in Registry.quest(qid).goals:
				if g["type"] == "checkbox":
					Quests.set_checked(qid)
	for qid in Quests.claimable():
		Quests.claim(qid, 0)


# --- Главная цель -----------------------------------------------------------------------------

func obtain(item_id: String, n: int, depth: int = 0) -> bool:
	if not failed.is_empty():
		return false
	if have(item_id) >= n:
		return true
	if depth > MAX_DEPTH:
		return fail("слишком глубокая рекурсия на " + item_id)
	var key := "%s" % item_id
	if _stack.has(key):
		return false
	_stack[key] = true
	var ok := _obtain_inner(item_id, n, depth)
	_stack.erase(key)
	return ok


func _obtain_inner(item_id: String, n: int, depth: int) -> bool:
	for attempt in 6:
		if have(item_id) >= n:
			return true
		var node := best_node_for(item_id)
		if not node.is_empty():
			mine(node, item_id, n, depth)
			continue
		var rid := choose_recipe(item_id, depth)
		if not rid.is_empty():
			if not craft(rid, item_id, n, depth):
				return false
			continue
		# Источник появится позже: жилы меняются раз в сутки, майнеры копят.
		if Registry.dropped_by.has(item_id) and wait_for_source(item_id, n):
			continue
		return fail("не знаю, как получить %s ×%d (есть %d)" % [item_id, n, have(item_id)])
	if have(item_id) >= n:
		return true
	return fail("не удалось набрать %s ×%d (есть %d)" % [item_id, n, have(item_id)])


# --- Добыча -----------------------------------------------------------------------------------

## Лучший открытый блок с этим дропом; если он закрыт тиром инструмента — готовит инструмент.
func best_node_for(item_id: String) -> String:
	var best := ""
	var best_score := 0.0
	for nid: String in Registry.node_order:
		if not World.is_revealed(nid):
			continue
		var n := World.node_def(nid)
		for d in n.drops:
			if d["item"] != item_id:
				continue
			if World.is_locked(nid) and not ensure_tool(n.tool_type, n.min_tool_tier):
				continue
			var score := n.expected_drop(d) / maxf(1.0, World.clicks_needed(nid))
			if score > best_score:
				best = nid
				best_score = score
	return best


func ensure_tool(type: String, min_tier: int) -> bool:
	if type == "any" or Tools.tool_tier(type) >= min_tier:
		return true
	var best := ""
	for id: String in Registry.item_order:
		var it := Registry.item(id)
		if it.kind == "tool" and it.tool["type"] == type and int(it.tool["tool_tier"]) >= min_tier:
			if best.is_empty() or int(it.tool["tool_tier"]) < int(Registry.item(best).tool["tool_tier"]):
				best = id
	if best.is_empty() or _stack.has(best):
		return false
	note("инструмент: " + best)
	return obtain(best, 1, 0) and Tools.tool_tier(type) >= min_tier


func mine(node_id: String, item_id: String, n: int, depth: int) -> void:
	var guard := 0
	while have(item_id) < n and failed.is_empty():
		var nd := World.node_def(node_id)
		if World.is_locked(node_id) and not ensure_tool(nd.tool_type, nd.min_tool_tier):
			fail("нечем добывать " + node_id)
			return
		maintain_tool(nd.tool_type, depth)
		World.click(node_id)
		manual_seconds += CLICK_SEC
		tick(CLICK_SEC)
		guard += 1
		if guard > 200000:
			fail("бесконечная добыча " + item_id)
			return


## Ремонт на наковальне, когда прочности осталось мало; иначе — новый инструмент после поломки.
func maintain_tool(type: String, _depth: int) -> void:
	if type == "any" or Tools.equipped(type).is_empty():
		return
	if Tools.durability_fraction(type) < 0.1 and Tools.can_repair():
		var cost := Tools.repair_cost(type, 1.0)
		if not cost.is_empty() and Storage.has_all(cost):
			Tools.repair(type, 1.0)


func wait_for_source(item_id: String, n: int) -> bool:
	note("жду источник " + item_id)
	var waited := 0.0
	while waited < GameClock.day_length() * 1.5:
		tick(60.0)
		waited += 60.0
		if have(item_id) >= n or not best_node_for(item_id).is_empty():
			return true
	return false


# --- Крафт ------------------------------------------------------------------------------------

func powered(sid: String) -> bool:
	match Registry.station(sid).energy:
		"steam":
			return Power.count("coal_boiler") + Power.count("solar_boiler") > 0
		"eu":
			return Power.count("steam_turbine_lv") + Power.count("combustion_gen_lv") > 0
	return true


func _station_obtainable(sid: String) -> bool:
	var s := Registry.station(sid)
	if s.builtin or Stations.is_available(sid):
		return true
	if s.is_multiblock():
		for p: Dictionary in s.multiblock["parts"]:
			if _stack.has(p["item"]):
				return false
		return true
	return not _stack.has(s.item)


## Выбор рецепта: работающая станция с энергией, затем — та, которую проще построить.
func choose_recipe(item_id: String, _depth: int) -> String:
	var best := ""
	var best_score := -INF
	for rid: String in Registry.produced_by.get(item_id, []):
		var r := Registry.recipe(rid)
		var self_input := false
		for inp in r.inputs:
			for c in Registry.input_candidates(inp):
				self_input = self_input or c == item_id or _stack.has(c)
		if self_input or not _station_obtainable(r.station):
			continue
		var reason := Stations.block_reason(rid)
		if reason == "REASON_VOLTAGE" or reason == "REASON_HEAT":
			continue
		var s := Registry.station(r.station)
		var score := 0.0
		if Stations.is_available(r.station) and powered(r.station):
			score = 100.0 + s.era * 10.0 + (0.0 if s.builtin else 1.0)
		else:
			score = -s.era * 10.0 - (5.0 if s.is_multiblock() else 0.0)
		if score > best_score:
			best = rid
			best_score = score
	return best


func ensure_station(sid: String) -> bool:
	if Stations.is_available(sid):
		return ensure_power(Registry.station(sid).energy)
	var s := Registry.station(sid)
	if s.is_multiblock():
		note("собираю мультиблок " + sid)
		for p: Dictionary in s.multiblock["parts"]:
			var need := int(p["n"]) - Stations.build_installed(sid, p["item"])
			if need > 0 and not obtain(p["item"], need, 1):
				return false
			Stations.install_part(sid, p["item"])
	elif not obtain(s.item, 1, 1):
		return false
	note("станция готова: " + sid)
	return Stations.is_available(sid) and ensure_power(s.energy)


func ensure_power(energy: String) -> bool:
	match energy:
		"steam":
			if Power.count("coal_boiler") == 0 and not obtain("coal_boiler", 2, 1):
				return false
		"eu":
			if Power.count("steam_turbine_lv") == 0 and not obtain("steam_turbine_lv", 1, 1):
				return false
			if Power.count("coal_boiler") < 4 and not obtain("coal_boiler", 4, 1):
				return false
	return true


func craft(rid: String, item_id: String, n: int, depth: int) -> bool:
	var r := Registry.recipe(rid)
	if not ensure_station(r.station):
		return fail("не построить станцию %s для %s" % [r.station, rid])
	var per := 0.0
	for o in r.outputs:
		if o["item"] == item_id:
			per += float(o["n"]) * float(o["chance"])
	var crafts := ceili((n - have(item_id)) / per - 1e-9)
	if crafts <= 0:
		return true
	for attempt in 5:
		if not Stations.resolve_inputs(rid, crafts).is_empty():
			break
		for inp in r.inputs:
			var need := int(inp["n"]) * crafts
			var cands := Registry.input_candidates(inp)
			var target := cands[0]
			var total := 0
			for c in cands:
				total += have(c)
				if have(c) > have(target):
					target = c
			if total < need and not obtain(target, have(target) + need - total, depth + 1):
				return false
	if not Stations.enqueue(rid, crafts):
		return fail("не удалось поставить %s ×%d: %s" % [rid, crafts, Stations.block_reason(rid)])
	return wait_station(r.station)


func wait_station(sid: String) -> bool:
	var waited := 0.0
	while Stations.queued_count(sid) > 0:
		keep_fuel()
		while Stations.click_boost(sid) and Registry.station(sid).builtin:
			manual_seconds += CLICK_SEC
			tick(CLICK_SEC)
		tick(WAIT_STEP)
		waited += WAIT_STEP
		if waited > MAX_WAIT:
			return fail("станция %s не доделала очередь (энергия %.2f/%.2f)" % [sid, Power.r_steam, Power.r_eu])
	return true


## Котлам нужен уголь: если запас мал — добываем (руками или ждём майнеры).
func keep_fuel() -> void:
	if _fueling or Power.count("coal_boiler") == 0:
		return
	var carbon := 0
	for id: String in Registry.tag_items["carbon"]:
		carbon += Storage.count(id)
	var fueled := false
	for id: String in Power.groups:
		fueled = fueled or float(Power.groups[id]["fuel_left"]) > 0.0
	if carbon >= 4 or fueled:
		return
	_fueling = true
	obtain("coal", 16, 1)
	_fueling = false


# --- Майнеры ----------------------------------------------------------------------------------

## Ставит все свободные майнеры на открытые блоки с нужными дропами.
func place_miners(miner_id: String, nodes: Array[String]) -> void:
	for nid in nodes:
		while Storage.count(miner_id) > 0 and Miners.place_reason(nid, miner_id).is_empty():
			Miners.place(nid, miner_id)
