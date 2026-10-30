extends TestCase
## Хранилище: атомарное списание, discovered, доход.


func test_add_remove() -> void:
	Storage.add("log", 10)
	check(Storage.try_remove("log", 4), "списание 4 из 10")
	eq(Storage.count("log"), 6, "остаток")
	check(not Storage.try_remove("log", 7), "нельзя списать больше, чем есть")
	eq(Storage.count("log"), 6, "неудачное списание ничего не меняет")


func test_try_remove_all_is_atomic() -> void:
	give({"log": 5, "planks": 2})
	check(not Storage.try_remove_all({"log": 3, "planks": 5}), "не хватает досок")
	eq(Storage.count("log"), 5, "бревна не тронуты при неудаче")
	eq(Storage.count("planks"), 2, "доски не тронуты при неудаче")
	check(Storage.try_remove_all({"log": 3, "planks": 2}), "хватает всего")
	eq(Storage.count("log"), 2, "бревна списаны")
	eq(Storage.count("planks"), 0, "доски списаны")


func test_discovered_and_totals() -> void:
	check(not Storage.is_discovered("cobblestone"), "сначала неизвестно")
	Storage.add("cobblestone", 3)
	Storage.try_remove("cobblestone", 3)
	check(Storage.is_discovered("cobblestone"), "discovered остаётся после траты")
	eq(int(Storage.total_obtained["cobblestone"]), 3, "всего получено")


func test_income_average() -> void:
	for i in 10:
		Storage.add("log", 5)
		Storage.sample_income(1.0)
	near(Storage.income("log"), 5.0, 1e-6, "среднее за 10 секунд")
	Storage.add("planks", 100, false)
	Storage.sample_income(1.0)
	near(Storage.income("planks"), 0.0, 1e-6, "награды не считаются доходом")
