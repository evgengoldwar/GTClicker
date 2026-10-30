class_name MiningPanel
extends PanelContainer
## Панель добычи (раздел 8): крупный блок для кликов с трещинами, тряской, частицами и
## крит-искрой, полоса прочности блока, дроп с шансами, ячейка майнера.
## Зажатая кнопка мыши = автоклик 5/с.

signal floating_text(text: String, at: Vector2, color: Color)

const BLOCK_PX := 128

var node_id := ""
var _block := Control.new()
var _cracks := Control.new()
var _icon: TextureRect
var _spark := TextureRect.new()
var _particles := CPUParticles2D.new()
var _title := UIKit.label("", 18, UITheme.ACCENT)
var _info := UIKit.label("", 13, UITheme.TEXT_DIM)
var _hp := UIKit.bar(1.0, UITheme.GOOD, 12)
var _drops := UIKit.vbox(2)
var _miner_box := UIKit.vbox(4)
var _hold := 0.0
var _holding := false
var _refresh := 0.0


func _ready() -> void:
	theme_type_variation = "PanelContainer"
	var h := UIKit.hbox(16)
	add_child(h)
	_block.custom_minimum_size = Vector2(BLOCK_PX, BLOCK_PX)
	_block.mouse_filter = Control.MOUSE_FILTER_STOP
	_block.gui_input.connect(_on_block_input)
	_block.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_icon = Icons.rect("tree", Color.WHITE, BLOCK_PX)
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_block.add_child(_icon)
	_cracks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cracks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cracks.draw.connect(_draw_cracks)
	_block.add_child(_cracks)
	_spark.texture = Icons.shape("spark")
	_spark.material = Icons.tint_material(Color("#fff27a"))
	_spark.size = Vector2(32, 32)
	_spark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spark.visible = false
	_block.add_child(_spark)
	_particles.emitting = false
	_particles.one_shot = true
	_particles.amount = 12
	_particles.lifetime = 0.5
	_particles.explosiveness = 1.0
	_particles.direction = Vector2(0, -1)
	_particles.spread = 80.0
	_particles.initial_velocity_min = 60.0
	_particles.initial_velocity_max = 140.0
	_particles.gravity = Vector2(0, 300)
	_particles.scale_amount_min = 3.0
	_particles.scale_amount_max = 5.0
	_particles.position = Vector2(BLOCK_PX / 2.0, BLOCK_PX / 2.0)
	_block.add_child(_particles)
	h.add_child(_block)

	var mid := UIKit.vbox(4)
	mid.custom_minimum_size.x = 300
	mid.add_child(_title)
	mid.add_child(_info)
	mid.add_child(UIKit.label(tr("UI_BLOCK_HP"), 12, UITheme.TEXT_DIM))
	mid.add_child(_hp)
	mid.add_child(UIKit.label(tr("UI_DROPS"), 13, UITheme.TEXT_DIM))
	mid.add_child(_drops)
	h.add_child(mid)
	_miner_box.custom_minimum_size.x = 280
	h.add_child(_miner_box)
	World.node_hit.connect(_on_hit)
	World.node_broken.connect(_on_broken)
	World.spark_changed.connect(func(_n: String) -> void: _update_spark())
	Miners.cells_changed.connect(func(_n: String) -> void: _rebuild())
	Events.tool_equipped.connect(func(_t: String) -> void: _rebuild())
	Events.feature_unlocked.connect(func(_f: String) -> void: _rebuild())
	Events.veins_changed.connect(_rebuild)


func show_node(nid: String) -> void:
	node_id = nid
	visible = not nid.is_empty()
	World.focus(nid)
	if visible:
		_rebuild()


func _rebuild() -> void:
	if node_id.is_empty():
		return
	var n := World.node_def(node_id)
	var locked := World.is_locked(node_id)
	_icon.texture = Icons.shape(n.icon)
	_icon.material = Icons.tint_material(Color(0.2, 0.2, 0.24) if locked else n.color)
	_title.text = Registry.node_name(node_id)
	if n.vein_slot >= 0:
		_title.text += " · " + tr("VEIN_" + World.current_vein(node_id).to_upper())
	var hit := Tools.hit_for(n)
	if locked:
		_info.text = tr("UI_NEED_TOOL") % [tr("TOOL_" + n.tool_type.to_upper()), _tier_name(n.min_tool_tier)]
		_info.add_theme_color_override("font_color", UITheme.BAD)
	else:
		var tool_name := tr("UI_HANDS") if str(hit["type"]).is_empty() else Registry.item_name(Tools.equipped(hit["type"]))
		_info.text = tr("UI_MINING_WITH") % [tool_name, World.clicks_needed(node_id)]
		_info.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	UIKit.clear(_drops)
	for d in n.drops:
		var line := UIKit.hbox(4)
		line.add_child(Icons.item_rect(d["item"], 16))
		var amount := str(d["min"]) if d["min"] == d["max"] else "%d–%d" % [d["min"], d["max"]]
		var item_label := "%s ×%s" % [Registry.item_name(d["item"]), amount]
		line.add_child(UIKit.label("%s  (%d%%)" % [item_label, roundi(float(d["chance"]) * 100.0)], 13))
		_drops.add_child(line)
	_rebuild_miners()
	_update_spark()
	_cracks.queue_redraw()


func _tier_name(tier: int) -> String:
	for id: String in Registry.materials:
		var m: Dictionary = Registry.materials[id]
		if m.has("tool") and int(m["tool"]["tool_tier"]) == tier:
			return tr("MAT_" + id.to_upper())
	return str(tier)


func _rebuild_miners() -> void:
	UIKit.clear(_miner_box)
	if not Progress.has_feature("miner_cells"):
		return
	_miner_box.add_child(UIKit.label(tr("UI_MINER_CELL"), 15, UITheme.ACCENT))
	var current := Miners.cell_miner(node_id)
	if current.is_empty():
		_miner_box.add_child(UIKit.label(tr("UI_MINER_EMPTY"), 13, UITheme.TEXT_DIM))
	else:
		var line := UIKit.hbox()
		line.add_child(Icons.item_rect(current, 32))
		line.add_child(UIKit.label("%s ×%d / %d" % [Registry.item_name(current), Miners.cell_count(node_id),
			Miners.limit(node_id)], 14))
		_miner_box.add_child(line)
		var rate := Miners.effective_blocks_per_sec(node_id)
		_miner_box.add_child(UIKit.label(tr("UI_MINER_RATE") % NumFormat.format(rate), 13, UITheme.TEXT_DIM))
		_miner_box.add_child(UIKit.button(tr("UI_MINER_REMOVE"), func() -> void: Miners.remove(node_id, 1)))
	for mid: String in Registry.miners:
		if Storage.count(mid) <= 0:
			continue
		var m: MinerDef = Registry.miners[mid]
		var reason := Miners.place_reason(node_id, mid)
		var b := UIKit.button(tr("UI_MINER_PLACE") % [Registry.item_name(mid), Storage.count(mid)],
			func() -> void: Miners.place(node_id, mid))
		b.disabled = not reason.is_empty()
		b.tooltip_text = tr(reason) if not reason.is_empty() else tr("UI_MINER_HINT") % [
			NumFormat.format(m.damage_per_sec), tr("ENERGY_" + m.energy.to_upper())]
		_miner_box.add_child(b)


func _process(delta: float) -> void:
	if node_id.is_empty():
		return
	if _holding:
		_hold += delta
		var interval := 1.0 / float(Registry.mining_balance().get("autoclick_per_sec", 5))
		while _hold >= interval:
			_hold -= interval
			_click(_block.get_local_mouse_position())
	_refresh += delta
	if _refresh >= 0.1:
		_refresh = 0.0
		_hp.value = World.health_fraction(node_id)


func _on_block_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_holding = event.pressed
		_hold = 0.0
		if event.pressed:
			_click((event as InputEventMouseButton).position)


func _click(at: Vector2) -> void:
	var on_spark := _spark.visible and at.distance_to(_spark.position + _spark.size / 2.0) <= 24.0
	if World.is_locked(node_id):
		Sfx.play("error")
		_holding = false
		return
	World.click(node_id, on_spark)


func _on_hit(nid: String, _damage: float, crit: bool) -> void:
	if nid != node_id:
		return
	var n := World.node_def(nid)
	Sfx.play("crit" if crit else _hit_sound(n.tool_type))
	_cracks.queue_redraw()
	if Settings.reduce_animations:
		return
	_particles.color = n.color.lightened(0.2)
	_particles.restart()
	var tw := create_tween()
	tw.tween_property(_icon, "position", Vector2(randf_range(-4, 4), randf_range(-3, 3)), 0.04)
	tw.tween_property(_icon, "position", Vector2.ZERO, 0.05)
	if crit:
		floating_text.emit("×5!", _block.global_position + Vector2(BLOCK_PX / 2.0, 10), Color("#fff27a"))


func _hit_sound(tool_type: String) -> String:
	match tool_type:
		"axe":
			return "hit_wood"
		"shovel":
			return "hit_soft"
	return "hit_stone"


func _on_broken(nid: String, drops: Dictionary) -> void:
	if nid != node_id:
		return
	Sfx.play("break")
	var y := 0.0
	for id: String in drops:
		floating_text.emit("+%s %s" % [UIKit.amount(id, drops[id]), Registry.item_name(id)],
			_block.global_position + Vector2(BLOCK_PX / 2.0, y), UITheme.GOOD)
		y -= 18.0
	_cracks.queue_redraw()


func _update_spark() -> void:
	_spark.visible = not node_id.is_empty() and World.spark_time > 0.0 and World.focused == node_id \
		and not World.is_locked(node_id)
	if _spark.visible:
		_spark.position = World.spark_pos * BLOCK_PX - _spark.size / 2.0


## Трещины на блоке: 5 стадий по накопленному урону.
func _draw_cracks() -> void:
	if node_id.is_empty():
		return
	var stage := ceili((1.0 - World.health_fraction(node_id)) * 5.0)
	var c := Vector2(BLOCK_PX / 2.0, BLOCK_PX / 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(node_id)
	for i in stage * 3:
		var a := rng.randf() * TAU
		var p0 := c + Vector2.from_angle(a) * rng.randf_range(4, 20)
		var p1 := p0 + Vector2.from_angle(a + rng.randf_range(-0.6, 0.6)) * rng.randf_range(16, 40)
		_cracks.draw_line(p0, p1, Color(0, 0, 0, 0.75), 3.0)
