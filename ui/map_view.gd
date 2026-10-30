class_name MapView
extends Control
## Карта острова: TileMapLayer с процедурным тайлсетом, кликабельные блоки, туман над закрытыми
## зонами, силуэты с замком, майнеры на тайлах, база в центре растёт по эпохам, день/ночь.

signal node_selected(node_id: String)

const TILE := 16
const TILE_KINDS: Array[String] = ["water", "grass", "forest", "sand", "dirt", "hills", "fog"]

var island := Node2D.new()
var ground := TileMapLayer.new()
var fog := TileMapLayer.new()
var _objects: Dictionary = {}   # node id -> Node2D
var _base := Sprite2D.new()
var _highlight := Sprite2D.new()
var _selected := ""
var _scale := 3
var _refresh := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(island)
	var ts := _tileset()
	ground.tile_set = ts
	fog.tile_set = ts
	island.add_child(ground)
	_build_ground()
	_base.texture = Icons.shape("base_0")
	_base.material = Icons.tint_material(Color("#e0c090"))
	var bp: Array = Registry.dimension.get("base", {}).get("pos", [6, 4])
	_base.position = Vector2(int(bp[0]) * TILE + TILE / 2.0, int(bp[1]) * TILE + TILE / 2.0)
	island.add_child(_base)
	for nid: String in Registry.node_order:
		var obj := _make_object(nid)
		_objects[nid] = obj
		island.add_child(obj)
	island.add_child(fog)
	_highlight.texture = Icons.shape("select")
	_highlight.modulate = Color(1, 0.85, 0.3)
	_highlight.visible = false
	island.add_child(_highlight)
	resized.connect(func() -> void:
		_scale = _wanted_scale()
		_layout())
	Events.state_reset.connect(refresh)
	Events.feature_unlocked.connect(func(_f: String) -> void: refresh())
	Events.item_discovered.connect(func(_i: String) -> void: refresh())
	Events.era_changed.connect(func(_e: int) -> void: refresh())
	Events.veins_changed.connect(refresh)
	Events.tool_equipped.connect(func(_t: String) -> void: refresh())
	Miners.cells_changed.connect(func(_n: String) -> void: refresh())
	refresh()
	_layout()


func _tileset() -> TileSet:
	var atlas_img := Image.create(TILE * TILE_KINDS.size(), TILE, false, Image.FORMAT_RGBA8)
	for i in TILE_KINDS.size():
		atlas_img.blit_rect(Icons.tile(TILE_KINDS[i]), Rect2i(0, 0, TILE, TILE), Vector2i(i * TILE, 0))
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(atlas_img)
	src.texture_region_size = Vector2i(TILE, TILE)
	for i in TILE_KINDS.size():
		src.create_tile(Vector2i(i, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	return ts


func _tile_index(kind: String) -> int:
	return maxi(0, TILE_KINDS.find(kind))


func _build_ground() -> void:
	var rows: Array = Registry.dimension.get("tiles", [])
	var types: Dictionary = Registry.dimension.get("tile_types", {})
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var t: Dictionary = types.get(row[x], {"id": "water"})
			ground.set_cell(Vector2i(x, y), 0, Vector2i(_tile_index(t["id"]), 0))


func _make_object(nid: String) -> Node2D:
	var n := Registry.node(nid)
	var root := Node2D.new()
	root.position = Vector2(n.pos.x * TILE + TILE / 2.0, n.pos.y * TILE + TILE / 2.0)
	var spr := Sprite2D.new()
	spr.name = "Icon"
	root.add_child(spr)
	var lock := Sprite2D.new()
	lock.name = "Lock"
	lock.texture = Icons.shape("lock")
	lock.scale = Vector2(0.5, 0.5)
	lock.position = Vector2(5, -5)
	root.add_child(lock)
	var miner := Sprite2D.new()
	miner.name = "Miner"
	miner.texture = Icons.shape("drill")
	miner.scale = Vector2(0.5, 0.5)
	miner.position = Vector2(-5, 5)
	root.add_child(miner)
	return root


func refresh() -> void:
	var types: Dictionary = Registry.dimension.get("tile_types", {})
	var rows: Array = Registry.dimension.get("tiles", [])
	fog.clear()
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var t: Dictionary = types.get(row[x], {})
			if t.has("zone") and not World.zone_unlocked(t["zone"]):
				fog.set_cell(Vector2i(x, y), 0, Vector2i(_tile_index("fog"), 0))
	for nid: String in _objects:
		var obj: Node2D = _objects[nid]
		var shown := World.is_revealed(nid)
		obj.visible = shown
		if not shown:
			continue
		var n := World.node_def(nid)
		var spr: Sprite2D = obj.get_node("Icon")
		spr.texture = Icons.shape(n.icon)
		var locked := World.is_locked(nid)
		spr.material = Icons.tint_material(Color(0.15, 0.15, 0.18) if locked else n.color)
		(obj.get_node("Lock") as Sprite2D).visible = locked
		var miner: Sprite2D = obj.get_node("Miner")
		miner.visible = Miners.cell_count(nid) > 0
		if miner.visible:
			miner.material = Icons.tint_material(Registry.item(Miners.cell_miner(nid)).color)
	_base.texture = Icons.shape("base_%d" % clampi(Progress.era, 0, 2))


func select(nid: String) -> void:
	_selected = nid
	_highlight.visible = not nid.is_empty()
	if _highlight.visible:
		_highlight.position = (_objects[nid] as Node2D).position
	_zoom(_wanted_scale())


## Целый масштаб: максимальный, при котором остров влезает; при выбранном блоке — на 1 крупнее.
func _wanted_scale() -> int:
	var fit := floori(minf(size.x / _map_size().x, size.y / _map_size().y))
	return clampi(fit, 2, 5) + (1 if not _selected.is_empty() else 0)


func _zoom(target: int) -> void:
	if target == _scale or size.x <= 0.0 or Settings.reduce_animations:
		_scale = target
		_layout()
		return
	_scale = target
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(island, "scale", Vector2(_scale, _scale), 0.25)
	tw.parallel().tween_property(island, "position", _target_position(), 0.25)


func _map_size() -> Vector2:
	var rows: Array = Registry.dimension.get("tiles", [])
	return Vector2(((rows[0] as String).length() if not rows.is_empty() else 1) * TILE, rows.size() * TILE)


func _target_position() -> Vector2:
	var focus := _map_size() / 2.0
	if not _selected.is_empty():
		focus = focus.lerp((_objects[_selected] as Node2D).position, 0.6)
	return (size / 2.0 - focus * _scale).round()


func _layout() -> void:
	island.scale = Vector2(_scale, _scale)
	island.position = _target_position()


func _process(delta: float) -> void:
	_refresh += delta
	if _refresh < 0.25:
		return
	_refresh = 0.0
	# Ночь: остров затеняется (визуальная смена дня и ночи).
	var night := 0.0 if GameClock.is_day() else 1.0
	island.modulate = Color(1, 1, 1).lerp(Color(0.55, 0.6, 0.85), night)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := island.get_local_mouse_position()
		var cell := Vector2i(floori(local.x / TILE), floori(local.y / TILE))
		for nid: String in _objects:
			if (_objects[nid] as Node2D).visible and Registry.node(nid).pos == cell:
				node_selected.emit(nid)
				accept_event()
				return
		node_selected.emit("")


## Позиция блока на экране (для подсказки онбординга).
func node_screen_position(nid: String) -> Vector2:
	return island.get_global_transform() * (_objects[nid] as Node2D).position
