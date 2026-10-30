extends Node
## World: блоки на карте острова, рудные жилы «Рудных холмов» (меняются раз в игровые сутки,
## только онлайн), ручная добыча кликами с крит-искрой (раздел 4).

## Блок получил урон: UI рисует трещины, частицы и всплывающие числа.
signal node_hit(node_id: String, damage: float, crit: bool)
## Блок разбит руками; drops: {item: amount}.
signal node_broken(node_id: String, drops: Dictionary)
signal spark_changed(node_id: String)

var damage: Dictionary = {}   # node id -> накопленный урон
var focused := ""
## Крит-искра на блоке в фокусе: позиция в долях 0..1 и оставшееся время.
var spark_pos := Vector2.ZERO
var spark_time := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	GameClock.ticked.connect(_on_ticked)


func reset() -> void:
	damage.clear()
	focused = ""
	spark_time = 0.0
	rng.seed = 1


## Определение блока с учётом текущей жилы (для ячеек «Рудных холмов»).
func node_def(node_id: String) -> NodeDef:
	var base := Registry.node(node_id)
	if base == null or base.vein_slot < 0:
		return base
	var vein: NodeDef = Registry.veins[current_vein(node_id)]
	var n := NodeDef.new()
	n.id = base.id
	n.pos = base.pos
	n.zone = base.zone
	n.vein_size = base.vein_size
	n.vein_slot = base.vein_slot
	n.icon = vein.icon
	n.color = vein.color
	n.tool_type = vein.tool_type
	n.hardness = vein.hardness
	n.min_tool_tier = vein.min_tool_tier
	n.era_tool_tier = vein.era_tool_tier
	n.drops = vein.drops
	return n


## Ячейка i в сутки d показывает жилу pool[(d + i) % N] — в любой день видно 3 из 4.
func current_vein(node_id: String) -> String:
	var base := Registry.node(node_id)
	var pool := Registry.vein_order
	return pool[(GameClock.vein_day + base.vein_slot) % pool.size()]


func on_veins_rotated() -> void:
	for id: String in Registry.node_order:
		if Registry.node(id).vein_slot >= 0:
			damage.erase(id)
	Miners.on_veins_rotated()
	Events.veins_changed.emit()
	Events.notify.emit(TranslationServer.translate("NOTIFY_VEINS_CHANGED"), "info")


func zone_unlocked(zone_id: String) -> bool:
	for z: Dictionary in Registry.dimension.get("zones", []):
		if z["id"] == zone_id:
			return bool(z.get("unlocked", false)) or Progress.has_feature(z.get("feature", ""))
	return false


## Блок виден на карте (условие reveal выполнено и зона открыта).
func is_revealed(node_id: String) -> bool:
	var n := Registry.node(node_id)
	return n != null and zone_unlocked(n.zone) and Progress.check(n.reveal)


## Блок виден, но текущим инструментом не добывается (силуэт с замком).
func is_locked(node_id: String) -> bool:
	var n := node_def(node_id)
	return int(Tools.hit_for(n)["tier"]) < n.min_tool_tier


func clicks_needed(node_id: String) -> int:
	var n := node_def(node_id)
	return Formulas.clicks_for(n.hardness, float(Tools.hit_for(n)["damage"]))


func health_fraction(node_id: String) -> float:
	var n := node_def(node_id)
	return clampf(1.0 - float(damage.get(node_id, 0.0)) / n.hardness, 0.0, 1.0)


func focus(node_id: String) -> void:
	focused = node_id
	spark_time = 0.0
	spark_changed.emit(node_id)


## Один клик по блоку. on_spark — игрок попал по искре (урон ×5). Возвращает урон.
func click(node_id: String, on_spark: bool = false) -> float:
	if not is_revealed(node_id) or is_locked(node_id):
		return 0.0
	var n := node_def(node_id)
	var hit := Tools.hit_for(n)
	var dmg := float(hit["damage"])
	var crit := on_spark and spark_time > 0.0 and node_id == focused
	if crit:
		dmg *= float(Registry.mining_balance().get("crit_mult", 5))
		spark_time = 0.0
		spark_changed.emit(node_id)
	Progress.clicks += 1
	var total := float(damage.get(node_id, 0.0)) + dmg
	node_hit.emit(node_id, dmg, crit)
	if total + 1e-9 < n.hardness:
		damage[node_id] = total
		return dmg
	damage[node_id] = 0.0
	var drops := roll_drops(n)
	for id: String in drops:
		Storage.add(id, drops[id])
	Tools.on_block_broken(hit["type"])
	node_broken.emit(node_id, drops)
	Events.block_broken.emit(node_id, true)
	return dmg


func roll_drops(n: NodeDef) -> Dictionary:
	var out: Dictionary = {}
	for d in n.drops:
		if rng.randf() < float(d["chance"]):
			var amount := rng.randi_range(int(d["min"]), int(d["max"]))
			out[d["item"]] = int(out.get(d["item"], 0)) + amount
	return out


func _on_ticked(dt: float) -> void:
	if focused.is_empty():
		return
	var mining := Registry.mining_balance()
	if spark_time > 0.0:
		spark_time -= dt
		if spark_time <= 0.0:
			spark_changed.emit(focused)
	elif rng.randf() < float(mining.get("crit_spawn_per_sec", 0.2)) * dt:
		spark_time = float(mining.get("crit_lifetime_sec", 1.6))
		spark_pos = Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8))
		spark_changed.emit(focused)


func serialize() -> Dictionary:
	return {"damage": damage.duplicate()}


func deserialize(data: Dictionary) -> void:
	reset()
	for id: String in data.get("damage", {}):
		if Registry.nodes.has(id):
			damage[id] = float(data["damage"][id])
