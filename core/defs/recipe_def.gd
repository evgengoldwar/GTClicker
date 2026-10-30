class_name RecipeDef
extends RefCounted
## Рецепт станции. Время в тиках GT (20/с), энергия в EU/t (правка 4).

var id: String
var station: String
## [{item: String} или {tag: String}, n: int]
var inputs: Array[Dictionary] = []
## [{item: String, n: int, chance: float}]
var outputs: Array[Dictionary] = []
var ticks: int = 20
var eu: float = 0.0
var heat: int = 0
var generated: bool = false


func main_output() -> String:
	return outputs[0]["item"] if not outputs.is_empty() else ""
