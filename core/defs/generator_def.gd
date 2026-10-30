class_name GeneratorDef
extends RefCounted
## Генератор/накопитель: boiler, solar, turbine, fuel_gen, battery.

var id: String
var type: String
var era: int = 0
var steam_per_tick: float = 0.0
var buffer: float = 0.0
var warmup_sec: float = 0.0
var fuel_tag: String = ""
## Автовыбор топлива берёт только предметы с этим тегом (котёл не жжёт брёвна без спроса).
var auto_tag: String = ""
var eu_per_tick: float = 0.0
var pull: int = 1
var capacity: float = 0.0
