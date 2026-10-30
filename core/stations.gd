extends Node
## Stations: экземпляры станций, сгруппированные по типу (группа из N одинаковых станций
## считается одним объектом с множителем), очереди крафта, оверклок, нагрев EBF,
## глобальные апгрейды «скорость» и «энергоэффективность», сборка мультиблоков (раздел 5).

signal queue_changed(station_id: String)
signal recipes_seen_changed()

const EPS := 1e-6

## station id -> {count, queue: [{recipe, n}], slots: [{recipe, progress, total, eut}]}
var groups: Dictionary = {}
## station id -> {speed: int, efficiency: int}
var upgrades: Dictionary = {}
## Сборка мультиблока: station id -> {part item -> установлено}
var builds: Dictionary = {}
## Рецепты, которые игрок уже видел (для жёлтой точки «новое»).
var seen: Dictionary = {}
## Дробные остатки шансовых выходов: "recipe:item" -> float (детерминированно, без рандома).
var chance_acc: Dictionary = {}

var _emptied_offline: Dictionary = {}


func _ready() -> void:
	Events.item_obtained.connect(_on_item_obtained)


func reset() -> void:
	groups.clear()
	upgrades.clear()
	builds.clear()
	seen.clear()
	chance_acc.clear()
	_emptied_offline.clear()


func _group(sid: String) -> Dictionary:
	if not groups.has(sid):
		groups[sid] = {"count": 0, "queue": [], "slots": []}
	return groups[sid]


func instance_count(sid: String) -> int:
	var s := Registry.station(sid)
	if s != null and s.builtin:
		return 1
	return int(groups[sid]["count"]) if groups.has(sid) else 0


func is_available(sid: String) -> bool:
	return instance_count(sid) > 0


func install(sid: String, n: int = 1) -> void:
	_group(sid)["count"] = int(_group(sid)["count"]) + n
	Events.station_installed.emit(sid)
	_fill(sid)


func _on_item_obtained(item_id: String, _amount: int) -> void:
	var it := Registry.item(item_id)
	if it == null or it.kind != "station":
		return
	var sid: String = Registry.station_by_item.get(item_id, "")
	if not sid.is_empty() and Storage.try_remove(item_id, 1):
		install(sid)


# --- Формулы (раздел 15) --------------------------------------------------------------------

func max_eu(sid: String) -> float:
	var s := Registry.station(sid)
	match s.energy:
		"steam":
			return float(Registry.balance.get("steam_machine_max_eu", 8))
		"eu":
			return Registry.voltage_eu(s.voltage)
	return 0.0


## Число оверклоков: на сколько тиров напряжение станции выше тира рецепта.
func overclocks(sid: String, r: RecipeDef) -> int:
	var s := Registry.station(sid)
	if s.energy != "eu" or r.eu <= 0.0:
		return 0
	return maxi(0, Registry.voltage_tier_index(s.voltage) - Registry.voltage_tier_for(r.eu))


func heat(sid: String) -> int:
	var s := Registry.station(sid)
	if not s.is_multiblock():
		return 0
	var coil := Registry.item(s.multiblock.get("heat_from", ""))
	return coil.heat if coil != null else 0


func speed_bonus(sid: String) -> float:
	return upgrade_level(sid, "speed") * float(Registry.station_balance().get("speed_per_level", 0.1))


func efficiency_bonus(sid: String) -> float:
	return upgrade_level(sid, "efficiency") * float(Registry.station_balance().get("efficiency_per_level", 0.05))


func _heat_terms(sid: String, r: RecipeDef) -> Vector2i:
	if r.heat <= 0:
		return Vector2i.ZERO
	var ebf: Dictionary = Registry.balance.get("ebf", {})
	var over := maxi(0, heat(sid) - r.heat)
	return Vector2i(floori(over / float(ebf.get("heat_discount_step", 900))),
		floori(over / float(ebf.get("perfect_overclock_step", 1800))))


func craft_ticks(sid: String, r: RecipeDef) -> float:
	var h := _heat_terms(sid, r)
	return r.ticks / Formulas.speed_multiplier(overclocks(sid, r), h.y, speed_bonus(sid))


func craft_eut(sid: String, r: RecipeDef) -> float:
	var h := _heat_terms(sid, r)
	var discount := float((Registry.balance.get("ebf", {}) as Dictionary).get("heat_discount", 0.05))
	return r.eu * Formulas.eut_multiplier(overclocks(sid, r), efficiency_bonus(sid), h.x, discount)


func craft_seconds(sid: String, r: RecipeDef) -> float:
	return craft_ticks(sid, r) / Registry.ticks_per_second()


# --- Открытие рецептов ----------------------------------------------------------------------

func _input_discovered(inp: Dictionary) -> bool:
	for c in Registry.input_candidates(inp):
		if Storage.is_discovered(c):
			return true
	return false


## Рецепт виден, когда все его входы есть в discovered (иначе в списке «???»).
func is_recipe_known(rid: String) -> bool:
	return unknown_inputs(rid) == 0


func unknown_inputs(rid: String) -> int:
	var n := 0
	for inp in Registry.recipe(rid).inputs:
		if not _input_discovered(inp):
			n += 1
	return n


func new_recipes(sid: String) -> Array[String]:
	var out: Array[String] = []
	if not is_available(sid):
		return out
	for rid in Registry.recipes_for_station(sid):
		if not seen.has(rid) and is_recipe_known(rid):
			out.append(rid)
	return out


func mark_seen(sid: String) -> void:
	for rid in new_recipes(sid):
		seen[rid] = true
	recipes_seen_changed.emit()


# --- Крафт ----------------------------------------------------------------------------------

## Причина, по которой рецепт нельзя запустить, или пустая строка.
func block_reason(rid: String) -> String:
	var r := Registry.recipe(rid)
	if not is_available(r.station):
		return "REASON_NO_STATION"
	if r.eu > max_eu(r.station) + EPS:
		return "REASON_VOLTAGE"
	if r.heat > heat(r.station):
		return "REASON_HEAT"
	if not is_recipe_known(rid):
		return "REASON_UNKNOWN"
	return ""


func _available(item_id: String) -> int:
	return Tools.available(item_id)


## Конкретные предметы для n крафтов (теги раскрываются по наличию) или {} если не хватает.
func resolve_inputs(rid: String, n: int) -> Dictionary:
	var out: Dictionary = {}
	for inp in Registry.recipe(rid).inputs:
		var need := Qty.mul(int(inp["n"]), n)
		var cands := Registry.input_candidates(inp)
		cands.sort_custom(func(a: String, b: String) -> bool: return _available(a) > _available(b))
		for c in cands:
			var free := _available(c) - int(out.get(c, 0))
			var take := mini(free, need)
			if take > 0:
				out[c] = int(out.get(c, 0)) + take
				need -= take
			if need <= 0:
				break
		if need > 0:
			return {}
	return out


func max_craftable(rid: String) -> int:
	var r := Registry.recipe(rid)
	var best := -1
	for inp in r.inputs:
		var total := 0
		for c in Registry.input_candidates(inp):
			total += _available(c)
		var k := floori(total / float(inp["n"]))
		best = k if best < 0 else mini(best, k)
	return maxi(best, 0)


## Ставит n крафтов в очередь, ресурсы списываются сразу и атомарно.
func enqueue(rid: String, n: int) -> bool:
	if n <= 0 or not block_reason(rid).is_empty():
		return false
	var cost := resolve_inputs(rid, n)
	if cost.is_empty():
		return false
	for id: String in cost:
		var it := Registry.item(id)
		if it.kind == "tool" and Storage.count(id) < int(cost[id]):
			Tools.unequip_to_storage(it.tool["type"])
	if not Storage.try_remove_all(cost):
		return false
	var r := Registry.recipe(rid)
	var queue: Array = _group(r.station)["queue"]
	if not queue.is_empty() and (queue.back() as Dictionary)["recipe"] == rid:
		queue.back()["n"] = int(queue.back()["n"]) + n
		queue.back()["cost"] = _merge(queue.back().get("cost", {}), cost)
	else:
		queue.append({"recipe": rid, "n": n, "cost": cost})
	_fill(r.station)
	queue_changed.emit(r.station)
	return true


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k: String in b:
		out[k] = int(out.get(k, 0)) + int(b[k])
	return out


## Отменяет ещё не начатые крафты и возвращает их ресурсы.
func cancel_queue(sid: String) -> void:
	if not groups.has(sid):
		return
	for job: Dictionary in groups[sid]["queue"]:
		var cost: Dictionary = job.get("cost", {})
		for id: String in cost:
			Storage.put_back(id, int(cost[id]))
	(groups[sid]["queue"] as Array).clear()
	queue_changed.emit(sid)


func queued_count(sid: String) -> int:
	var total := 0
	if groups.has(sid):
		for job: Dictionary in groups[sid]["queue"]:
			total += int(job["n"])
		total += (groups[sid]["slots"] as Array).size()
	return total


func is_busy(sid: String) -> bool:
	return groups.has(sid) and not (groups[sid]["slots"] as Array).is_empty()


## Занимает свободные экземпляры задачами из очереди.
func _fill(sid: String) -> void:
	var g := _group(sid)
	var slots: Array = g["slots"]
	var queue: Array = g["queue"]
	while slots.size() < instance_count(sid) and not queue.is_empty():
		var job: Dictionary = queue.front()
		var r := Registry.recipe(job["recipe"])
		slots.append({"recipe": r.id, "progress": 0.0, "total": craft_ticks(sid, r), "eut": craft_eut(sid, r)})
		job["n"] = int(job["n"]) - 1
		var per_craft: Dictionary = {}
		var cost: Dictionary = job.get("cost", {})
		for id: String in cost:
			per_craft[id] = ceili(float(cost[id]) / (int(job["n"]) + 1))
			cost[id] = int(cost[id]) - int(per_craft[id])
		if int(job["n"]) <= 0:
			queue.pop_front()


func demand(energy: String) -> float:
	var total := 0.0
	for sid: String in groups:
		if Registry.station(sid).energy != energy:
			continue
		for slot: Dictionary in groups[sid]["slots"]:
			total += float(slot["eut"])
	return total


func consumers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sid: String in groups:
		var s := Registry.station(sid)
		if not s.uses_energy():
			continue
		var eu := 0.0
		for slot: Dictionary in groups[sid]["slots"]:
			eu += float(slot["eut"])
		if eu > 0.0:
			out.append({"name": Registry.station_name(sid), "eu": eu, "energy": s.energy})
	return out


func time_to_event() -> float:
	var tps := Registry.ticks_per_second()
	var t := INF
	for sid: String in groups:
		var rate := tps * Power.ratio(Registry.station(sid).energy)
		if rate <= EPS:
			continue
		for slot: Dictionary in groups[sid]["slots"]:
			t = minf(t, (float(slot["total"]) - float(slot["progress"])) / rate)
	return t


func advance(dt: float) -> void:
	var tps := Registry.ticks_per_second()
	for sid: String in groups:
		var rate := tps * Power.ratio(Registry.station(sid).energy)
		for slot: Dictionary in groups[sid]["slots"]:
			slot["progress"] = float(slot["progress"]) + dt * rate


func process_events() -> void:
	for sid: String in groups:
		var slots: Array = groups[sid]["slots"]
		var done: Array[Dictionary] = []
		for slot: Dictionary in slots:
			if float(slot["progress"]) >= float(slot["total"]) - EPS:
				done.append(slot)
		for slot in done:
			slots.erase(slot)
			_complete(sid, slot["recipe"])
		if not done.is_empty():
			_fill(sid)
			queue_changed.emit(sid)
			if GameClock.offline and queued_count(sid) == 0:
				_emptied_offline[sid] = true


func _complete(sid: String, rid: String) -> void:
	var r := Registry.recipe(rid)
	for o in r.outputs:
		var amount := int(o["n"])
		if float(o["chance"]) < 1.0:
			var key := rid + ":" + str(o["item"])
			var acc := float(chance_acc.get(key, 0.0)) + float(o["chance"]) * amount
			amount = floori(acc + 1e-9)
			chance_acc[key] = acc - amount
		if amount > 0:
			Storage.add(o["item"], amount)
			Events.crafted.emit(o["item"], amount, sid, rid)


## Клик по работающей станции ускоряет текущий крафт на 0.2 с.
func click_boost(sid: String) -> bool:
	if not is_busy(sid):
		return false
	var slot: Dictionary = (groups[sid]["slots"] as Array).front()
	var boost := float(Registry.station_balance().get("craft_click_boost_sec", 0.2)) * Registry.ticks_per_second()
	slot["progress"] = minf(float(slot["total"]), float(slot["progress"]) + boost)
	process_events()
	return true


## Доля прогресса первого крафта группы (для полосы на карточке).
func progress_fraction(sid: String) -> float:
	if not is_busy(sid):
		return 0.0
	var slot: Dictionary = (groups[sid]["slots"] as Array).front()
	return clampf(float(slot["progress"]) / maxf(float(slot["total"]), EPS), 0.0, 1.0)


func idle_groups() -> Array[String]:
	var out: Array[String] = []
	out.assign(_emptied_offline.keys())
	_emptied_offline.clear()
	return out


# --- Апгрейды -------------------------------------------------------------------------------

func upgrade_level(sid: String, kind: String) -> int:
	return int((upgrades.get(sid, {}) as Dictionary).get(kind, 0))


func upgrade_max(kind: String) -> int:
	return int(Registry.station_balance().get(kind + "_max_level", 10))


## cost(L) = cost0 · 1.6^L, округление вверх.
func upgrade_cost(sid: String, kind: String) -> Dictionary:
	var s := Registry.station(sid)
	var base: Array[Dictionary] = s.speed_cost if kind == "speed" else s.efficiency_cost
	var growth := float(Registry.station_balance().get("upgrade_cost_growth", 1.6))
	var out: Dictionary = {}
	for c in base:
		out[c["item"]] = Formulas.upgrade_cost(int(c["n"]), growth, upgrade_level(sid, kind))
	return out


func can_upgrade(sid: String, kind: String) -> bool:
	if kind == "efficiency" and not Registry.station(sid).uses_energy():
		return false
	return upgrade_level(sid, kind) < upgrade_max(kind) and not upgrade_cost(sid, kind).is_empty()


func buy_upgrade(sid: String, kind: String) -> bool:
	if not can_upgrade(sid, kind) or not Storage.try_remove_all(upgrade_cost(sid, kind)):
		return false
	var u: Dictionary = upgrades.get_or_add(sid, {})
	u[kind] = upgrade_level(sid, kind) + 1
	queue_changed.emit(sid)
	return true


# --- Мультиблоки ----------------------------------------------------------------------------

func build_installed(sid: String, part: String) -> int:
	return int((builds.get(sid, {}) as Dictionary).get(part, 0))


## Доля собранного мультиблока 0..1.
func build_progress(sid: String) -> float:
	var s := Registry.station(sid)
	var have := 0
	var need := 0
	for p: Dictionary in s.multiblock.get("parts", []):
		have += mini(build_installed(sid, p["item"]), int(p["n"]))
		need += int(p["n"])
	return float(have) / need if need > 0 else 0.0


## Устанавливает в мультиблок столько деталей part, сколько есть и сколько ещё нужно.
func install_part(sid: String, part: String) -> int:
	var s := Registry.station(sid)
	for p: Dictionary in s.multiblock.get("parts", []):
		if p["item"] != part:
			continue
		var n := mini(int(p["n"]) - build_installed(sid, part), Storage.count(part))
		if n <= 0 or not Storage.try_remove(part, n):
			return 0
		var b: Dictionary = builds.get_or_add(sid, {})
		b[part] = build_installed(sid, part) + n
		if build_progress(sid) >= 1.0:
			builds.erase(sid)
			install(sid)
		queue_changed.emit(sid)
		return n
	return 0


func serialize() -> Dictionary:
	return {"groups": groups.duplicate(true), "upgrades": upgrades.duplicate(true),
		"builds": builds.duplicate(true), "seen": seen.keys(), "chance_acc": chance_acc.duplicate()}


func deserialize(data: Dictionary) -> void:
	reset()
	var g: Dictionary = data.get("groups", {})
	for sid: String in g:
		if Registry.station(sid) == null:
			continue
		var src: Dictionary = g[sid]
		var grp := {"count": int(src.get("count", 0)), "queue": [], "slots": []}
		for job: Dictionary in src.get("queue", []):
			if Registry.recipe(job.get("recipe", "")) != null:
				var cost: Dictionary = {}
				for id: String in job.get("cost", {}):
					cost[id] = int(job["cost"][id])
				grp["queue"].append({"recipe": job["recipe"], "n": int(job["n"]), "cost": cost})
		for slot: Dictionary in src.get("slots", []):
			if Registry.recipe(slot.get("recipe", "")) != null:
				grp["slots"].append({"recipe": slot["recipe"], "progress": float(slot["progress"]),
					"total": float(slot["total"]), "eut": float(slot["eut"])})
		groups[sid] = grp
	for sid: String in data.get("upgrades", {}):
		upgrades[sid] = {"speed": int(data["upgrades"][sid].get("speed", 0)),
			"efficiency": int(data["upgrades"][sid].get("efficiency", 0))}
	for sid: String in data.get("builds", {}):
		var b: Dictionary = {}
		for part: String in data["builds"][sid]:
			b[part] = int(data["builds"][sid][part])
		builds[sid] = b
	for rid: String in data.get("seen", []):
		seen[rid] = true
	for k: String in data.get("chance_acc", {}):
		chance_acc[k] = float(data["chance_acc"][k])
