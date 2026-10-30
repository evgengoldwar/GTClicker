class_name Qty
extends RefCounted
## Количества предметов — int64 с насыщением на максимуме (правка 3).

const MAX := 9223372036854775807


static func add(a: int, b: int) -> int:
	if b > 0 and a > MAX - b:
		return MAX
	if b < 0 and a < -MAX - b:
		return -MAX
	return a + b


static func mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	if absf(float(a) * float(b)) >= 9.2e18:
		return MAX if (a > 0) == (b > 0) else -MAX
	return a * b


## Безопасное приведение float → int с насыщением.
static func from_float(v: float) -> int:
	if v >= 9.2e18:
		return MAX
	if v <= -9.2e18:
		return -MAX
	return int(v)
