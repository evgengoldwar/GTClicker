extends Node
## Power: пар (котлы, солнечные котлы) и EU (паровая турбина, генераторы LV, батареи) — раздел 6.
## Всё в EU/t и L/t (правка 4). При дефиците и пустом буфере потребители замедляются
## пропорционально генерация / потребление; прогресс не теряется.
##
## solve() вычисляет «рабочую точку» сети при текущем состоянии: она постоянна до следующего
## события (буфер опустел/заполнился, кончилось топливо, закончился разогрев), что и позволяет
## GameClock перематывать время событиями.

signal history_updated()

const EPS := 1e-6

## id генератора -> {count, fuel_item, fuel_left, warm_left, fuel_choice}
var groups: Dictionary = {}
var battery_charge := 0.0
var steam_buffer := 0.0
## [{charge, steam, gen, use}] за последние 10 минут.
var history: Array[Dictionary] = []

# Результат solve(): коэффициенты для потребителей и текущие потоки.
var r_steam := 1.0
var r_eu := 1.0
var steam_cap := 0.0
var steam_gen := 0.0
var steam_use := 0.0
var steam_net := 0.0
var eu_cap := 0.0
var eu_gen := 0.0
var eu_use := 0.0
var eu_net := 0.0
var turbine_out := 0.0
var _burn: Dictionary = {}     # id группы -> расход топлива в единицах fuel_left за тик

var _history_timer := 0.0
var _last_ratio := 1.0
var _report: Array[Dictionary] = []
var _reporting := false


func _ready() -> void:
	GameClock.ticked.connect(_on_ticked)
	Events.item_obtained.connect(_on_item_obtained)


func reset() -> void:
	groups.clear()
	battery_charge = 0.0
	steam_buffer = 0.0
	history.clear()
	_burn.clear()
	_history_timer = 0.0
	_last_ratio = 1.0
	r_steam = 1.0
	r_eu = 1.0
	steam_cap = 0.0
	steam_gen = 0.0
	steam_use = 0.0
	steam_net = 0.0
	eu_cap = 0.0
	eu_gen = 0.0
	eu_use = 0.0
	eu_net = 0.0
	turbine_out = 0.0


func steam_per_eu() -> float:
	return float((Registry.balance.get("power", {}) as Dictionary).get("steam_per_eu", 2))


func count(gen_id: String) -> int:
	return int((groups[gen_id] as Dictionary)["count"]) if groups.has(gen_id) else 0


func gdef(gen_id: String) -> GeneratorDef:
	return Registry.generators[gen_id]


func install(gen_id: String, n: int = 1) -> void:
	if not groups.has(gen_id):
		groups[gen_id] = {"count": 0, "fuel_item": "", "fuel_left": 0.0,
			"warm_left": gdef(gen_id).warmup_sec, "fuel_choice": ""}
	groups[gen_id]["count"] = count(gen_id) + n
	Events.generator_installed.emit(gen_id)


func steam_capacity() -> float:
	var total := 0.0
	for id: String in groups:
		total += gdef(id).buffer * count(id)
	return total


func battery_capacity() -> float:
	var total := 0.0
	for id: String in groups:
		if gdef(id).type == "battery":
			total += gdef(id).capacity * count(id)
	return total


func is_producing(gen_id: String) -> bool:
	var g: Dictionary = groups[gen_id]
	return float(g["fuel_left"]) > EPS and float(g["warm_left"]) <= EPS


func is_warming(gen_id: String) -> bool:
	var g: Dictionary = groups[gen_id]
	return float(g["fuel_left"]) > EPS and float(g["warm_left"]) > EPS


## Выбор топлива: явный выбор игрока или самое калорийное из имеющегося.
func pick_fuel(gen_id: String) -> String:
	var g: Dictionary = groups[gen_id]
	var choice: String = g.get("fuel_choice", "")
	if not choice.is_empty():
		return choice if Storage.count(choice) > 0 else ""
	var best := ""
	for id: String in auto_fuels(gen_id):
		if Storage.count(id) <= 0:
			continue
		var it := Registry.item(id)
		if best.is_empty() or it.fuel > Registry.item(best).fuel \
				or (it.fuel == Registry.item(best).fuel and Storage.count(id) > Storage.count(best)):
			best = id
	return best


## Топливо, которое группа берёт сама при автовыборе.
func auto_fuels(gen_id: String) -> Array[String]:
	var out: Array[String] = []
	var def := gdef(gen_id)
	for id: String in Registry.tag_items.get(def.fuel_tag, []):
		if def.auto_tag.is_empty() or Registry.item(id).has_tag(def.auto_tag):
			out.append(id)
	return out


func set_fuel_choice(gen_id: String, item_id: String) -> void:
	if groups.has(gen_id):
		groups[gen_id]["fuel_choice"] = item_id


func fuel_candidates(gen_id: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(Registry.tag_items.get(gdef(gen_id).fuel_tag, []))
	return out


## Догружает топливо всем группам, у которых оно кончилось.
func _refuel() -> void:
	for id: String in groups:
		var def := gdef(id)
		if def.fuel_tag.is_empty():
			continue
		var g: Dictionary = groups[id]
		if float(g["fuel_left"]) > EPS:
			continue
		g["fuel_left"] = 0.0
		var fuel := pick_fuel(id)
		if fuel.is_empty():
			if def.warmup_sec > 0.0:
				g["warm_left"] = def.warmup_sec
			continue
		var want := count(id) * def.pull
		var take := mini(want, Storage.count(fuel))
		Storage.try_remove(fuel, take)
		g["fuel_item"] = fuel
		g["fuel_left"] = take * Registry.item(fuel).fuel


func solve() -> void:
	_refuel()
	var spe := steam_per_eu()
	var solar_cap := 0.0
	var boiler_cap := 0.0
	var turbine_cap := 0.0
	var fuel_cap := 0.0
	for id: String in groups:
		var def := gdef(id)
		var n := count(id)
		match def.type:
			"boiler":
				if is_producing(id):
					boiler_cap += def.steam_per_tick * n
			"solar":
				if GameClock.is_day():
					solar_cap += def.steam_per_tick * n
			"turbine":
				turbine_cap += def.eu_per_tick * n
			"fuel_gen":
				if float(groups[id]["fuel_left"]) > EPS:
					fuel_cap += def.eu_per_tick * n
	steam_cap = solar_cap + boiler_cap
	eu_cap = turbine_cap + fuel_cap
	var steam_need := (Stations.demand("steam") + Miners.demand("steam")) * spe
	eu_use = Stations.demand("eu") + Miners.demand("eu")
	var bat_cap := battery_capacity()
	var bat_full := bat_cap <= 0.0 or battery_charge >= bat_cap - EPS
	var steam_full := steam_buffer >= steam_capacity() - EPS

	# Пар: машины и турбины (в объёме текущего спроса на EU) делят пар поровну.
	var t_base := minf(turbine_cap, eu_use)
	var steam_demand := steam_need + t_base * spe
	var surplus := 0.0
	if steam_cap >= steam_demand:
		r_steam = 1.0
		surplus = steam_cap - steam_demand
	elif steam_buffer > EPS:
		r_steam = 1.0
		surplus = steam_cap - steam_demand
	else:
		r_steam = steam_cap / steam_demand
	turbine_out = t_base * r_steam
	# Излишек пара дозаряжает батареи через турбины.
	if not bat_full and surplus > 0.0:
		var extra := minf(turbine_cap - turbine_out, surplus / spe)
		turbine_out += extra
		surplus -= extra * spe
	if surplus > 0.0 and steam_full:
		steam_gen = steam_cap - surplus
		steam_net = 0.0
	else:
		steam_gen = steam_cap
		steam_net = surplus
	steam_use = steam_need * r_steam + turbine_out * spe

	# EU: генераторы на топливе добирают недостачу, а при неполной батарее работают в полную силу.
	var fuel_out := fuel_cap if not bat_full else clampf(eu_use - turbine_out, 0.0, fuel_cap)
	eu_gen = turbine_out + fuel_out
	if eu_gen >= eu_use - EPS:
		r_eu = 1.0
		eu_net = 0.0 if bat_full else eu_gen - eu_use
	elif battery_charge > EPS:
		r_eu = 1.0
		eu_net = eu_gen - eu_use
	else:
		r_eu = eu_gen / eu_use
		eu_net = 0.0

	# Расход топлива по группам.
	_burn.clear()
	var coal_steam := maxf(0.0, steam_gen - solar_cap)
	for id: String in groups:
		var def := gdef(id)
		if def.type == "boiler" and is_producing(id) and boiler_cap > 0.0:
			_burn[id] = coal_steam * (def.steam_per_tick * count(id) / boiler_cap)
		elif def.type == "fuel_gen" and float(groups[id]["fuel_left"]) > EPS and fuel_cap > 0.0:
			_burn[id] = fuel_out * (def.eu_per_tick * count(id) / fuel_cap)
	_check_deficit()


func ratio(energy: String) -> float:
	match energy:
		"steam":
			return r_steam
		"eu":
			return r_eu
	return 1.0


func time_to_event() -> float:
	var tps := Registry.ticks_per_second()
	var t := INF
	if steam_net < -EPS:
		t = minf(t, steam_buffer / (-steam_net * tps))
	elif steam_net > EPS:
		t = minf(t, (steam_capacity() - steam_buffer) / (steam_net * tps))
	if eu_net < -EPS:
		t = minf(t, battery_charge / (-eu_net * tps))
	elif eu_net > EPS:
		t = minf(t, (battery_capacity() - battery_charge) / (eu_net * tps))
	for id: String in groups:
		var g: Dictionary = groups[id]
		var burn := float(_burn.get(id, 0.0))
		if burn > EPS:
			t = minf(t, float(g["fuel_left"]) / (burn * tps))
		if is_warming(id):
			t = minf(t, float(g["warm_left"]))
		if not gdef(id).fuel_tag.is_empty() and float(g["fuel_left"]) <= EPS:
			var choice: String = g.get("fuel_choice", "")
			for fuel in ([choice] if not choice.is_empty() else auto_fuels(id)):
				t = minf(t, Miners.time_until_item(fuel))
	return t


func advance(dt: float) -> void:
	var ticks := dt * Registry.ticks_per_second()
	steam_buffer = clampf(steam_buffer + steam_net * ticks, 0.0, steam_capacity())
	battery_charge = clampf(battery_charge + eu_net * ticks, 0.0, battery_capacity())
	if steam_buffer < EPS:
		steam_buffer = 0.0
	if battery_charge < EPS:
		battery_charge = 0.0
	for id: String in groups:
		var g: Dictionary = groups[id]
		if is_warming(id):
			g["warm_left"] = maxf(0.0, float(g["warm_left"]) - dt)
		var burn := float(_burn.get(id, 0.0))
		if burn > 0.0:
			g["fuel_left"] = maxf(0.0, float(g["fuel_left"]) - burn * ticks)


func process_events() -> void:
	for id: String in groups:
		if float(groups[id]["warm_left"]) <= EPS:
			groups[id]["warm_left"] = 0.0
	_refuel()
	if not _reporting:
		return
	for id: String in groups:
		if not gdef(id).fuel_tag.is_empty() and float(groups[id]["fuel_left"]) <= EPS and count(id) > 0:
			_add_stop("STOP_NO_FUEL", id)


func _check_deficit() -> void:
	var worst := minf(r_steam, r_eu)
	if worst < 0.999 and _last_ratio >= 0.999:
		if _reporting:
			_add_stop("STOP_DEFICIT", "")
		elif not GameClock.offline:
			Events.power_deficit.emit(worst)
	_last_ratio = worst


func begin_report() -> void:
	_report.clear()
	_reporting = true


func end_report() -> Array[Dictionary]:
	_reporting = false
	var out: Array[Dictionary] = []
	out.assign(_report)
	return out


func _add_stop(reason: String, gen_id: String) -> void:
	for r in _report:
		if r["reason"] == reason and r["id"] == gen_id:
			return
	_report.append({"reason": reason, "id": gen_id, "at": GameClock.game_time})


func _on_item_obtained(item_id: String, _amount: int) -> void:
	var it := Registry.item(item_id)
	if it != null and it.kind == "generator" and Storage.try_remove(item_id, 1):
		install(item_id)


func _on_ticked(dt: float) -> void:
	var bal: Dictionary = Registry.balance.get("power", {})
	_history_timer += dt
	if _history_timer < float(bal.get("history_sample_sec", 5)):
		return
	_history_timer = 0.0
	var bc := battery_capacity()
	var sc := steam_capacity()
	history.append({"charge": battery_charge / bc if bc > 0.0 else 0.0,
		"steam": steam_buffer / sc if sc > 0.0 else 0.0, "gen": eu_gen, "use": eu_use,
		"steam_gen": steam_gen, "steam_use": steam_use})
	while history.size() > int(bal.get("history_points", 120)):
		history.pop_front()
	history_updated.emit()


## Крупнейшие потребители для уведомления о дефиците: [{name, eu}].
func top_consumers() -> Array[Dictionary]:
	var list := Stations.consumers() + Miners.consumers()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["eu"] > b["eu"])
	return list


func serialize() -> Dictionary:
	return {"groups": groups.duplicate(true), "battery": battery_charge, "steam": steam_buffer}


func deserialize(data: Dictionary) -> void:
	reset()
	var g: Dictionary = data.get("groups", {})
	for id: String in g:
		if Registry.generators.has(id):
			var src: Dictionary = g[id]
			groups[id] = {"count": int(src.get("count", 0)), "fuel_item": src.get("fuel_item", ""),
				"fuel_left": float(src.get("fuel_left", 0.0)), "warm_left": float(src.get("warm_left", 0.0)),
				"fuel_choice": src.get("fuel_choice", "")}
	battery_charge = float(data.get("battery", 0.0))
	steam_buffer = float(data.get("steam", 0.0))
