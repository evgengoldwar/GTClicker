class_name TestCase
extends RefCounted
## Базовый класс тестов для собственного раннера (tests/test_runner.gd).
## Методы test_* вызываются по очереди, перед каждым — чистая новая игра.

var failures: Array[String] = []


func check(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append(msg if not msg.is_empty() else "условие ложно")


func eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: ожидалось <%s>, получено <%s>" % [msg, str(expected), str(actual)])


func near(actual: float, expected: float, eps: float = 1e-6, msg: String = "") -> void:
	if absf(actual - expected) > eps:
		failures.append("%s: ожидалось %f ± %f, получено %f" % [msg, expected, eps, actual])


## Выдаёт предметы без статистики дохода.
func give(items: Dictionary) -> void:
	for id: String in items:
		Storage.add(id, int(items[id]), false)


## Ставит станцию напрямую (как будто её скрафтили).
func install(station_id: String, n: int = 1) -> void:
	Stations.install(station_id, n)
