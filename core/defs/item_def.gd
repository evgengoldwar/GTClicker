class_name ItemDef
extends RefCounted
## Описание предмета или жидкости (раздел 3). Поле tier переименовано в era (правка 5).

var id: String
var name_key: String
var icon: String
var color: Color = Color.WHITE
var unit: String = "piece"
var era: int = 0
var tags: Array[String] = []
var material: String = ""
var form: String = ""
## item / station / generator / miner / part / tool
var kind: String = "item"
## Твёрдое топливо — литры пара на штуку; жидкое — EU на литр.
var fuel: float = 0.0
## Для катушек: температура, которую она даёт мультиблоку.
var heat: int = 0
## Для инструментов: type, tool_tier, damage, durability, head_item, head_cost, material.
var tool: Dictionary = {}


func is_liquid() -> bool:
	return unit == "liter"


func has_tag(tag: String) -> bool:
	return tags.has(tag)
