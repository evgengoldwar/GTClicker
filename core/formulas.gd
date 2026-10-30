class_name Formulas
extends RefCounted
## Формулы баланса (раздел 15). Коэффициенты — в data/balance.json.


## Кликов на блок: ceil(hardness / damage).
static func clicks_for(hardness: float, damage: float) -> int:
	return ceili(hardness / maxf(damage, 0.0001) - 1e-9)


## Множитель скорости крафта: 2^o, «идеальные» оверклоки EBF дают ×4 вместо ×2, плюс апгрейды (1 + s).
static func speed_multiplier(o: int, perfect: int, s: float) -> float:
	var p := mini(perfect, o)
	return pow(2.0, o - p) * pow(4.0, p) * (1.0 + s)


## Множитель EU/t: ×4 мощности за оверклок, (1 − e) энергоэффективность, скидка за нагрев EBF.
static func eut_multiplier(o: int, e: float, heat_discounts: int, discount: float) -> float:
	return pow(4.0, o) * (1.0 - e) * pow(1.0 - discount, heat_discounts)


## Стоимость глобального апгрейда: cost0 · growth^L, округление вверх.
static func upgrade_cost(cost0: int, growth: float, level: int) -> int:
	return ceili(cost0 * pow(growth, level) - 1e-9)
