class_name StationDef
extends RefCounted
## Тип станции. Экземпляры и группы живут в автолоаде Stations.

var id: String
## Предмет, крафт которого добавляет экземпляр; пусто для встроенных и мультиблоков.
var item: String = ""
## none / steam / eu
var energy: String = "none"
var voltage: String = ""
var era: int = 0
var builtin: bool = false
var icon: String = "machine"
var color: Color = Color.WHITE
var speed_cost: Array[Dictionary] = []
var efficiency_cost: Array[Dictionary] = []
## {heat_from: item, parts: [{item, n}]} для мультиблоков.
var multiblock: Dictionary = {}


func is_multiblock() -> bool:
	return not multiblock.is_empty()


func uses_energy() -> bool:
	return energy != "none"
