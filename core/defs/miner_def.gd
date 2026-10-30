class_name MinerDef
extends RefCounted
## Тип майнера: урон в секунду по блоку ячейки, энергия в EU/t-эквиваленте.

var id: String
var era: int = 0
var tool_tier: int = 0
var damage_per_sec: float = 1.0
var tool_types: Array[String] = []
## none / steam / eu
var energy: String = "none"
var usage: float = 0.0


func can_mine(node: NodeDef) -> bool:
	return tool_tier >= node.min_tool_tier and tool_types.has(node.tool_type)
