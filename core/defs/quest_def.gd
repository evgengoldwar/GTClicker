class_name QuestDef
extends RefCounted
## Квест (раздел 10). Тексты — ключи перевода QUEST_<ID> и QUEST_<ID>_DESC.

var id: String
var chapter: String
var pos: Vector2 = Vector2.ZERO
var requires: Array[String] = []
## all / any
var requires_mode: String = "all"
var main: bool = true
## visible / locked / hidden
var visibility: String = "visible"
var goals_mode: String = "all"
var goals: Array[Dictionary] = []
## {items: [...], choice: [[...], [...]], unlock: [...], era: int, demo_end: bool}
var rewards: Dictionary = {}
var icon: String = ""


func title_key() -> String:
	return "QUEST_" + id.to_upper()


func desc_key() -> String:
	return "QUEST_" + id.to_upper() + "_DESC"
