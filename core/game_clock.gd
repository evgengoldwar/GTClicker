extends Node
## GameClock: единое игровое время, тики 20/с (правка 4), игровые сутки (правка 6),
## пауза и ускорение для отладки, событийная перемотка (правка 8).
##
## Модель: между «событиями» (готов крафт, опустел буфер, кончилось топливо, смена дня/ночи)
## все скорости постоянны, поэтому advance(dt) перематывает время сразу до ближайшего события.
## Онлайн-тик — это тот же advance() на кратное число тиков, так что офлайн и онлайн
## считаются одной формулой.

## Испускается после онлайн-продвижения времени (не во время офлайн-перемотки).
signal ticked(dt: float)
signal day_changed(day: int)
signal phase_changed(is_day: bool)

const EPS := 1e-9
## Минимальный шаг: гарантирует продвижение, если событие «вот-вот» (погрешность float).
const MIN_STEP := 1e-6

var game_time := 0.0
var time_scale := 1.0
var paused := false
## Во время офлайн-перемотки жилы не меняются (правка 9).
var offline := false
## Сколько суток прошло онлайн — от этого зависит набор жил.
var vein_day := 0
var last_events := 0

var _acc := 0.0
var _last_day := 0
var _last_is_day := true


func _process(delta: float) -> void:
	if paused:
		return
	_acc += delta * time_scale
	var tick := tick_length()
	var n := floori(_acc / tick)
	if n <= 0:
		return
	_acc -= n * tick
	var dt := n * tick
	advance(dt)
	ticked.emit(dt)


func reset() -> void:
	game_time = 0.0
	vein_day = 0
	_acc = 0.0
	_last_day = 0
	_last_is_day = true
	offline = false


func tick_length() -> float:
	return 1.0 / Registry.ticks_per_second()


func day_length() -> float:
	return float(Registry.balance.get("day_length_sec", 1200))


func day_index() -> int:
	return floori(game_time / day_length())


## Доля суток 0..1.
func day_phase() -> float:
	return fposmod(game_time, day_length()) / day_length()


func is_day() -> bool:
	return day_phase() < float(Registry.balance.get("day_fraction", 0.6))


func time_to_phase_change() -> float:
	var length := day_length()
	var t := fposmod(game_time, length)
	var day_end := length * float(Registry.balance.get("day_fraction", 0.6))
	return day_end - t if t < day_end else length - t


## Перематывает симуляцию на dt секунд, разбивая на отрезки между событиями.
## Возвращает число обработанных отрезков.
func advance(dt: float) -> int:
	var left := dt
	var segments := 0
	var limit := int((Registry.balance.get("offline", {}) as Dictionary).get("max_events", 200000))
	while left > EPS:
		Power.solve()
		var step := minf(left, maxf(_time_to_next_event(), MIN_STEP))
		Stations.advance(step)
		Miners.advance(step)
		Power.advance(step)
		game_time += step
		left -= step
		_process_boundaries()
		segments += 1
		if segments >= limit:
			push_warning("[GameClock] превышен лимит событий (%d), остаток %.1f с пропущен" % [limit, left])
			break
	last_events = segments
	Quests.check_all()
	return segments


func _time_to_next_event() -> float:
	var t := minf(Stations.time_to_event(), Power.time_to_event())
	t = minf(t, time_to_phase_change())
	if not offline:
		t = minf(t, day_length() * (day_index() + 1) - game_time)
	return t


func _process_boundaries() -> void:
	Stations.process_events()
	Power.process_events()
	var now_day := is_day()
	if now_day != _last_is_day:
		_last_is_day = now_day
		phase_changed.emit(now_day)
	var d := day_index()
	if d != _last_day:
		_last_day = d
		day_changed.emit(d)
		if not offline:
			vein_day += 1
			World.on_veins_rotated()


## Офлайн-прогресс: та же перемотка, но жилы заморожены. Возвращает отчёт.
func simulate_offline(seconds: float) -> Dictionary:
	var before := Storage.counts.duplicate()
	var crafted_before := Progress.crafted.duplicate()
	Power.begin_report()
	offline = true
	var segments := advance(seconds)
	offline = false
	_last_day = day_index()
	_last_is_day = is_day()
	var gained: Dictionary = {}
	for id: String in Storage.counts:
		var diff := int(Storage.counts[id]) - int(before.get(id, 0))
		if diff > 0:
			gained[id] = diff
	var crafted: Dictionary = {}
	for id: String in Progress.crafted:
		var diff := int(Progress.crafted[id]) - int(crafted_before.get(id, 0))
		if diff > 0:
			crafted[id] = diff
	Storage.clear_income()
	return {"seconds": seconds, "gained": gained, "crafted": crafted, "stops": Power.end_report(),
		"idle_stations": Stations.idle_groups(), "events": segments}


func serialize() -> Dictionary:
	return {"game_time": game_time, "vein_day": vein_day}


func deserialize(data: Dictionary) -> void:
	reset()
	game_time = float(data.get("game_time", 0.0))
	vein_day = int(data.get("vein_day", 0))
	_last_day = day_index()
	_last_is_day = is_day()
