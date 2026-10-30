extends TestCase
## Форматирование чисел (таблица раздела 3) и арифметика количеств int64 с насыщением.


func test_si_table() -> void:
	eq(NumFormat.format(1234, NumFormat.Mode.SI), "1.23k", "1234")
	eq(NumFormat.format(5600000, NumFormat.Mode.SI), "5.60M", "5.6M")
	eq(NumFormat.format(7.8e15, NumFormat.Mode.SI), "7.80P", "7.8e15")
	eq(NumFormat.format(1e40, NumFormat.Mode.SI), "1.00e40", "1e40")


func test_short_scale_table() -> void:
	eq(NumFormat.format(1234, NumFormat.Mode.SHORT), "1.23K", "1234")
	eq(NumFormat.format(5600000, NumFormat.Mode.SHORT), "5.60M", "5.6M")
	eq(NumFormat.format(7.8e15, NumFormat.Mode.SHORT), "7.80Qa", "7.8e15")
	eq(NumFormat.format(1e40, NumFormat.Mode.SHORT), "10.0Dd", "1e40")


func test_scientific_table() -> void:
	eq(NumFormat.format(1234, NumFormat.Mode.SCIENTIFIC), "1.23e3", "1234")
	eq(NumFormat.format(5600000, NumFormat.Mode.SCIENTIFIC), "5.60e6", "5.6M")
	eq(NumFormat.format(7.8e15, NumFormat.Mode.SCIENTIFIC), "7.80e15", "7.8e15")
	eq(NumFormat.format(1e40, NumFormat.Mode.SCIENTIFIC), "1.00e40", "1e40")


func test_full_table() -> void:
	eq(NumFormat.format(1234, NumFormat.Mode.FULL), "1 234", "1234")
	eq(NumFormat.format(5600000, NumFormat.Mode.FULL), "5 600 000", "5.6M")
	eq(NumFormat.format(7.8e15, NumFormat.Mode.FULL), "7 800 000 000 000 000", "7.8e15")
	eq(NumFormat.format(1e40, NumFormat.Mode.FULL), "1.00e40", "1e40 сокращается до научной")


func test_three_significant_digits_and_rounding() -> void:
	eq(NumFormat.format(999, NumFormat.Mode.SI), "999", "999 без суффикса")
	eq(NumFormat.format(999600, NumFormat.Mode.SI), "1.00M", "999.6k округляется до 1.00M")
	eq(NumFormat.format(12345, NumFormat.Mode.SI), "12.3k", "12.3k")
	eq(NumFormat.format(123456, NumFormat.Mode.SI), "123k", "123k")
	eq(NumFormat.format(-1234, NumFormat.Mode.SI), "-1.23k", "отрицательное")
	eq(NumFormat.format(0.2, NumFormat.Mode.SI), "0.200", "дробное")
	eq(NumFormat.format(2.5, NumFormat.Mode.SI), "2.50", "дробное 2.5")
	eq(NumFormat.format(1e30, NumFormat.Mode.SI), "1.00Q", "последний суффикс СИ")
	eq(NumFormat.format(1e33, NumFormat.Mode.SI), "1.00e33", "за суффиксами — научная")
	eq(NumFormat.full(9223372036854775807), "9 223 372 036 854 775 807", "полное число в тултипе")


func test_qty_saturation() -> void:
	eq(Qty.add(Qty.MAX - 5, 10), Qty.MAX, "сложение насыщается")
	eq(Qty.add(100, 23), 123, "обычное сложение")
	eq(Qty.mul(4000000000, 4000000000), Qty.MAX, "умножение насыщается")
	eq(Qty.mul(-3, 7), -21, "умножение со знаком")
	eq(Qty.from_float(1e30), Qty.MAX, "float за пределами int64")


func test_storage_saturates() -> void:
	Storage.add("log", Qty.MAX - 1)
	Storage.add("log", 1000)
	eq(Storage.count("log"), Qty.MAX, "хранилище насыщается на максимуме")
