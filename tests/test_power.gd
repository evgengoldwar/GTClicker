extends TestCase
## Энергия: пар, турбины, батареи и пропорциональное замедление при дефиците.


func _setup_ebf_job(n: int) -> void:
	Stations.install("ebf")
	give({"iron_dust": n, "coal_dust": n})
	check(Stations.enqueue("ebf_steel", n), "сталь в очереди EBF")


func test_no_power_no_progress() -> void:
	_setup_ebf_job(1)
	GameClock.advance(60.0)
	eq(Storage.count("steel_ingot"), 0, "без генерации крафт стоит")
	near(Stations.progress_fraction("ebf"), 0.0, 1e-9, "прогресс не идёт")


func test_proportional_slowdown_on_deficit() -> void:
	# Генератор на креозоте даёт 20 EU/t, EBF просит 30 EU/t, батарей нет → 2/3 скорости.
	Power.install("combustion_gen_lv")
	give({"creosote": 100000})
	_setup_ebf_job(1)
	Power.solve()
	near(Power.r_eu, 20.0 / 30.0, 1e-6, "коэффициент = генерация / потребление")
	GameClock.advance(30.0)
	near(Stations.progress_fraction("ebf"), 2.0 / 3.0, 1e-4, "за 30 с сделано 2/3 крафта")
	GameClock.advance(15.0 + 0.01)
	eq(Storage.count("steel_ingot"), 1, "крафт завершился, прогресс не потерян")


func test_battery_covers_deficit_then_drains() -> void:
	Power.install("combustion_gen_lv")
	Power.install("battery_buffer_lv")
	give({"creosote": 100000})
	Power.battery_charge = 6000.0
	_setup_ebf_job(1)
	Power.solve()
	near(Power.r_eu, 1.0, 1e-9, "пока есть заряд — полная скорость")
	near(Power.eu_net, -10.0, 1e-6, "батарея отдаёт 10 EU/t")
	# 6000 EU / (10 EU/t · 20 т/с) = 30 с полной скорости.
	GameClock.advance(30.0)
	near(Power.battery_charge, 0.0, 1e-3, "батарея опустела ровно за 30 с")
	eq(Storage.count("steel_ingot"), 1, "крафт шёл в полную силу и завершился за 30 с")


func test_boiler_warmup_and_fuel() -> void:
	Power.install("coal_boiler")
	Stations.install("steam_macerator")
	give({"coal": 11})
	check(Stations.enqueue("sm_coal_dust", 1), "дробим уголь")
	GameClock.advance(29.0)
	near(Stations.progress_fraction("steam_macerator"), 0.0, 1e-9, "котёл ещё разогревается")
	GameClock.advance(1.0 + 5.0 + 0.01)
	eq(Storage.count("coal_dust"), 1, "после разогрева машина отработала 5 с")
	check(Power.steam_gen > 0.0, "котёл даёт пар")


func test_boiler_stops_without_fuel() -> void:
	Power.install("coal_boiler")
	Storage.add("coal", 1, false)
	GameClock.advance(31.0)
	Power.solve()
	near(Power.steam_cap, 12.0, 1e-9, "котёл работает")
	# Буфер 2000 L, потребителей нет: котёл дросселируется и не тратит топливо зря.
	GameClock.advance(600.0)
	Power.solve()
	check(Power.steam_buffer >= 1999.0, "буфер пара полон")
	check(float(Power.groups["coal_boiler"]["fuel_left"]) > 0.0, "при полном буфере уголь не сгорает")


func test_steam_turbine_converts_two_to_one() -> void:
	Power.install("coal_boiler", 4)
	Power.install("steam_turbine_lv")
	Storage.add("coal", 100, false)
	_setup_ebf_job(1)
	GameClock.advance(31.0)
	Power.solve()
	near(Power.turbine_out, 24.0, 1e-6, "турбина выдаёт максимум 24 EU/t")
	near(Power.steam_use, 48.0, 1e-6, "2 L пара = 1 EU")
	near(Power.r_eu, 0.8, 1e-6, "24 из 30 EU/t")
