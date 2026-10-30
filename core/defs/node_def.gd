class_name NodeDef
extends RefCounted
## Добываемый блок на карте (раздел 4) или тип рудной жилы.

var id: String
var pos: Vector2i = Vector2i.ZERO
var zone: String = "start"
var icon: String = "rock"
var color: Color = Color.WHITE
## pickaxe / axe / shovel / any
var tool_type: String = "pickaxe"
var hardness: float = 10.0
var min_tool_tier: int = 0
## Тир инструмента, для которого блок «новый» (проверка баланса, правка 7).
var era_tool_tier: int = 0
var vein_size: int = 4
var reveal: Dictionary = {}
## [{item, min, max, chance}]
var drops: Array[Dictionary] = []
## Номер ячейки жилы в «Рудных холмах» или -1.
var vein_slot: int = -1


func expected_drop(drop: Dictionary) -> float:
	return float(drop["chance"]) * (float(drop["min"]) + float(drop["max"])) * 0.5
