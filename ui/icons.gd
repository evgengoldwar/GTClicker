class_name Icons
extends RefCounted
## Процедурные плейсхолдер-иконки 16×16: одна серая форма на тип, перекраска шейдером
## в цвет материала (раздел 3). Если художник положит res://art/icons/<форма>.png —
## берётся файл. Тайлы карты рисуются сразу в цвете.

const SIZE := 16
const TINT_SHADER := preload("res://ui/tint.gdshader")

static var _cache: Dictionary = {}
static var _materials: Dictionary = {}


## Серая текстура формы.
static func shape(shape_name: String) -> Texture2D:
	if _cache.has(shape_name):
		return _cache[shape_name]
	var path := "res://art/icons/%s.png" % shape_name
	var tex: Texture2D
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		tex = ImageTexture.create_from_image(_paint(shape_name))
	_cache[shape_name] = tex
	return tex


## Материал-перекраска для цвета (общий на все иконки этого цвета).
static func tint_material(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = TINT_SHADER
		m.set_shader_parameter("tint", color)
		_materials[key] = m
	return _materials[key]


## Готовый TextureRect с иконкой формы и перекраской; px — кратно 16 (целый масштаб).
static func rect(shape_name: String, color: Color, px: int = 32) -> TextureRect:
	var r := TextureRect.new()
	r.texture = shape(shape_name)
	r.material = tint_material(color)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func item_rect(item_id: String, px: int = 32) -> TextureRect:
	var it := Registry.item(item_id)
	if it == null:
		return rect("unknown", Color.GRAY, px)
	return rect(it.icon, it.color, px)


static func set_item(r: TextureRect, item_id: String) -> void:
	var it := Registry.item(item_id)
	r.texture = shape(it.icon if it != null else "unknown")
	r.material = tint_material(it.color if it != null else Color.GRAY)


# --- Рисование ---------------------------------------------------------------------------------

class Painter:
	var img: Image

	func _init() -> void:
		img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))

	func px(x: int, y: int, v: float) -> void:
		if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
			img.set_pixel(x, y, Color(v, v, v, 1.0))

	func rect(x: int, y: int, w: int, h: int, v: float) -> void:
		for i in w:
			for j in h:
				px(x + i, y + j, v)

	func frame(x: int, y: int, w: int, h: int, v: float) -> void:
		for i in w:
			px(x + i, y, v)
			px(x + i, y + h - 1, v)
		for j in h:
			px(x, y + j, v)
			px(x + w - 1, y + j, v)

	func circle(cx: float, cy: float, r: float, v: float) -> void:
		for x in SIZE:
			for y in SIZE:
				if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= r:
					px(x, y, v)

	func line(x0: int, y0: int, x1: int, y1: int, v: float) -> void:
		var steps := maxi(absi(x1 - x0), absi(y1 - y0))
		for i in steps + 1:
			var t := float(i) / maxf(1.0, steps)
			px(roundi(lerpf(x0, x1, t)), roundi(lerpf(y0, y1, t)), v)

	func shade_vertical(top: float, bottom: float) -> void:
		for y in SIZE:
			var k := lerpf(top, bottom, float(y) / (SIZE - 1))
			for x in SIZE:
				var c := img.get_pixel(x, y)
				if c.a > 0.0:
					img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, c.a))

	## Тёмная обводка по контуру — пиксель-арт без художника.
	func outline() -> void:
		var src := img.duplicate() as Image
		for x in SIZE:
			for y in SIZE:
				if src.get_pixel(x, y).a > 0.0:
					continue
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx := x + d.x
					var ny := y + d.y
					if nx >= 0 and ny >= 0 and nx < SIZE and ny < SIZE and src.get_pixel(nx, ny).a > 0.0:
						img.set_pixel(x, y, Color(0.12, 0.12, 0.12, 1.0))
						break


static func _paint(shape_name: String) -> Image:
	var p := Painter.new()
	match shape_name:
		"log":
			p.rect(3, 2, 10, 12, 0.7)
			for y in [4, 7, 10]:
				p.line(4, y, 11, y + 1, 0.5)
			p.circle(8, 3, 4, 0.9)
			p.circle(8, 3, 2, 0.75)
		"planks":
			for i in 3:
				p.rect(2, 3 + i * 4, 12, 3, 0.85 - i * 0.05)
				p.px(4 + i * 3, 4 + i * 4, 0.55)
		"stick":
			p.line(4, 13, 12, 2, 0.85)
			p.line(5, 13, 13, 2, 0.65)
		"block":
			p.rect(2, 2, 12, 12, 0.7)
			for c: Vector2i in [Vector2i(4, 4), Vector2i(9, 5), Vector2i(5, 10), Vector2i(10, 10)]:
				p.rect(c.x, c.y, 2, 2, 0.95)
		"gem":
			p.circle(8, 8, 5, 0.75)
			p.line(6, 5, 9, 4, 1.0)
			p.px(6, 6, 1.0)
		"ball":
			p.circle(8, 9, 5, 0.8)
			p.circle(6.5, 7, 1.5, 1.0)
		"pile", "dust":
			p.circle(8, 11, 5, 0.8)
			p.rect(3, 11, 10, 3, 0.8)
			p.px(6, 8, 1.0)
			p.px(9, 9, 1.0)
			p.px(7, 11, 0.6)
		"brick":
			p.rect(1, 5, 14, 7, 0.75)
			p.line(1, 8, 14, 8, 0.5)
			p.line(7, 5, 7, 7, 0.5)
			p.line(4, 9, 4, 11, 0.5)
			p.line(11, 9, 11, 11, 0.5)
		"glass":
			p.frame(2, 2, 12, 12, 0.9)
			p.line(5, 10, 10, 5, 1.0)
			p.line(4, 7, 7, 4, 1.0)
		"lump":
			p.circle(8, 9, 5, 0.6)
			p.circle(6, 7, 2, 0.85)
		"fluid":
			p.circle(8, 10, 4.5, 0.85)
			p.line(8, 2, 5, 8, 0.85)
			p.line(8, 2, 11, 8, 0.85)
			p.rect(6, 5, 5, 4, 0.85)
			p.px(6, 9, 1.0)
		"resin":
			p.circle(8, 10, 4, 0.9)
			p.circle(8, 6, 2.5, 0.9)
			p.px(7, 9, 1.0)
		"ore", "ore_rock":
			p.rect(2, 2, 12, 12, 0.45)
			for c: Vector2i in [Vector2i(4, 4), Vector2i(9, 4), Vector2i(6, 9), Vector2i(11, 10), Vector2i(3, 11)]:
				p.rect(c.x, c.y, 2, 2, 1.0)
		"ingot":
			p.rect(2, 7, 12, 5, 0.8)
			p.rect(4, 5, 8, 2, 1.0)
			p.line(3, 11, 13, 11, 0.6)
		"plate":
			p.rect(2, 3, 12, 10, 0.8)
			p.line(3, 4, 12, 4, 1.0)
			p.line(3, 4, 3, 11, 1.0)
		"rod":
			p.line(3, 13, 13, 3, 0.85)
			p.line(3, 12, 12, 3, 1.0)
			p.line(4, 13, 13, 4, 0.6)
		"wire":
			for i in 4:
				p.circle(8, 8, 6 - i * 1.5, 0.95 - i * 0.12)
			p.circle(8, 8, 1, 0.0)
		"cable":
			p.line(2, 12, 13, 3, 0.35)
			p.line(2, 13, 14, 3, 0.35)
			p.line(3, 13, 14, 4, 0.35)
			p.px(2, 13, 1.0)
			p.px(14, 3, 1.0)
		"casing", "hull":
			p.rect(2, 2, 12, 12, 0.7)
			p.frame(2, 2, 12, 12, 0.95)
			for c: Vector2i in [Vector2i(3, 3), Vector2i(12, 3), Vector2i(3, 12), Vector2i(12, 12)]:
				p.px(c.x, c.y, 0.4)
			if shape_name == "hull":
				p.rect(5, 5, 6, 6, 0.5)
		"machine":
			p.rect(1, 2, 14, 12, 0.7)
			p.frame(1, 2, 14, 12, 0.95)
			p.rect(4, 5, 8, 5, 0.35)
			p.rect(5, 6, 3, 3, 0.9)
			p.rect(3, 11, 2, 2, 1.0)
		"workbench":
			p.rect(1, 4, 14, 4, 0.85)
			p.rect(2, 8, 2, 6, 0.6)
			p.rect(12, 8, 2, 6, 0.6)
			p.line(4, 5, 12, 5, 1.0)
		"furnace", "blast":
			p.rect(2, 1 if shape_name == "blast" else 3, 12, 14 if shape_name == "blast" else 12, 0.65)
			p.rect(5, 8, 6, 5, 0.2)
			p.rect(6, 10, 4, 2, 1.0)
			p.line(2, 6, 13, 6, 0.85)
		"anvil":
			p.rect(2, 4, 12, 3, 0.85)
			p.rect(6, 7, 4, 4, 0.7)
			p.rect(3, 11, 10, 3, 0.75)
			p.rect(1, 4, 2, 2, 0.85)
		"boiler":
			p.rect(3, 3, 10, 11, 0.75)
			p.rect(6, 1, 3, 3, 0.6)
			p.rect(5, 9, 6, 3, 0.25)
			p.rect(6, 10, 4, 1, 1.0)
		"solar":
			p.rect(1, 6, 14, 3, 0.95)
			p.rect(2, 9, 12, 5, 0.65)
			for x in [4, 8, 12]:
				p.line(x, 6, x, 8, 0.6)
		"turbine", "generator":
			p.rect(2, 4, 12, 9, 0.7)
			p.circle(8, 8.5, 3.5, 0.95)
			p.circle(8, 8.5, 1.2, 0.4)
			if shape_name == "generator":
				p.rect(5, 1, 2, 3, 0.6)
		"battery", "battery_box":
			p.rect(4, 3, 8, 12, 0.75)
			p.rect(6, 1, 4, 2, 0.95)
			p.rect(5, 9, 6, 5, 1.0)
			if shape_name == "battery_box":
				p.frame(1, 3, 14, 12, 0.6)
		"drill":
			p.rect(3, 1, 10, 6, 0.75)
			p.line(5, 7, 8, 14, 0.95)
			p.line(11, 7, 8, 14, 0.95)
			p.line(6, 7, 10, 7, 0.95)
			p.line(7, 10, 9, 10, 0.6)
		"collector":
			p.rect(3, 6, 10, 8, 0.75)
			p.frame(3, 6, 10, 8, 0.95)
			p.line(4, 2, 12, 2, 0.85)
			p.line(4, 2, 4, 6, 0.85)
			p.line(12, 2, 12, 6, 0.85)
		"motor":
			p.rect(3, 4, 9, 8, 0.75)
			p.rect(12, 7, 3, 2, 1.0)
			p.line(4, 6, 10, 6, 0.95)
			p.line(4, 9, 10, 9, 0.95)
		"piston":
			p.rect(2, 9, 12, 5, 0.65)
			p.rect(6, 3, 4, 6, 0.9)
			p.rect(3, 2, 10, 2, 1.0)
		"tube":
			p.circle(8, 6, 4, 0.95)
			p.rect(5, 6, 6, 6, 0.95)
			p.rect(5, 12, 6, 2, 0.5)
			p.px(7, 5, 0.6)
		"resistor":
			p.line(1, 8, 14, 8, 0.6)
			p.rect(4, 6, 8, 5, 0.85)
			p.line(6, 6, 6, 10, 0.5)
			p.line(9, 6, 9, 10, 0.5)
		"board":
			p.rect(1, 3, 14, 10, 0.7)
			p.line(3, 5, 9, 5, 1.0)
			p.line(9, 5, 9, 10, 1.0)
			p.line(4, 10, 13, 10, 1.0)
		"circuit":
			p.rect(3, 3, 10, 10, 0.4)
			p.rect(5, 5, 6, 6, 0.95)
			for i in 4:
				p.px(4 + i * 2, 1, 0.8)
				p.px(4 + i * 2, 14, 0.8)
				p.px(1, 4 + i * 2, 0.8)
				p.px(14, 4 + i * 2, 0.8)
		"coil":
			p.rect(3, 2, 10, 12, 0.5)
			for y in range(3, 14, 2):
				p.line(3, y, 12, y, 0.95)
		"bus", "hatch":
			p.rect(2, 2, 12, 12, 0.7)
			p.frame(2, 2, 12, 12, 0.95)
			if shape_name == "bus":
				p.rect(5, 5, 6, 6, 0.3)
			else:
				p.line(9, 4, 6, 8, 1.0)
				p.line(6, 8, 10, 8, 1.0)
				p.line(10, 8, 7, 12, 1.0)
		"controller":
			p.rect(2, 2, 12, 12, 0.6)
			p.rect(4, 4, 8, 5, 0.25)
			p.line(5, 7, 7, 5, 1.0)
			p.line(7, 5, 10, 7, 1.0)
			p.rect(4, 11, 2, 2, 1.0)
			p.rect(8, 11, 2, 2, 0.8)
		"pickaxe":
			p.line(2, 4, 8, 2, 0.95)
			p.line(8, 2, 14, 4, 0.95)
			p.line(3, 5, 13, 5, 0.75)
			p.line(8, 4, 8, 14, 0.55)
		"axe":
			p.line(6, 3, 6, 14, 0.55)
			p.rect(7, 2, 5, 5, 0.95)
			p.line(12, 2, 12, 7, 0.8)
		"shovel":
			p.line(8, 1, 8, 9, 0.55)
			p.rect(5, 9, 6, 5, 0.95)
			p.px(8, 14, 0.95)
		"hand":
			p.rect(4, 6, 8, 8, 0.85)
			for i in 4:
				p.rect(4 + i * 2, 2 + (i % 2), 2, 4, 0.85)
			p.rect(2, 8, 2, 4, 0.85)
		"tree":
			p.rect(7, 10, 3, 5, 0.5)
			p.circle(8.5, 6, 5.5, 0.8)
			p.circle(6, 5, 2, 0.95)
		"rock":
			p.circle(8, 10, 6, 0.65)
			p.rect(2, 10, 12, 4, 0.65)
			p.circle(6, 8, 2, 0.85)
		"mound":
			p.circle(8, 12, 7, 0.8)
			p.px(6, 9, 1.0)
			p.px(10, 10, 1.0)
		"spring":
			p.circle(8, 10, 6, 0.85)
			p.circle(8, 10, 3, 1.0)
			p.line(8, 2, 8, 6, 0.9)
		"select":
			p.frame(0, 0, 16, 16, 1.0)
			p.frame(1, 1, 14, 14, 1.0)
			p.img.set_pixel(0, 0, Color(0, 0, 0, 0))
			return p.img
		"lock":
			p.rect(4, 7, 8, 7, 0.85)
			p.frame(5, 3, 6, 5, 0.85)
			p.rect(7, 9, 2, 3, 0.3)
		"check":
			p.line(3, 8, 6, 11, 1.0)
			p.line(6, 11, 13, 4, 1.0)
			p.line(3, 9, 6, 12, 1.0)
			p.line(6, 12, 13, 5, 1.0)
		"cross":
			p.line(3, 3, 12, 12, 1.0)
			p.line(12, 3, 3, 12, 1.0)
			p.line(4, 3, 13, 12, 1.0)
			p.line(13, 3, 4, 12, 1.0)
		"star", "spark":
			p.line(8, 1, 8, 14, 1.0)
			p.line(1, 8, 14, 8, 1.0)
			p.line(3, 3, 12, 12, 0.85)
			p.line(12, 3, 3, 12, 0.85)
			p.circle(8, 8, 2.5, 1.0)
		"warning":
			p.line(8, 2, 2, 13, 1.0)
			p.line(8, 2, 14, 13, 1.0)
			p.line(2, 13, 14, 13, 1.0)
			p.line(8, 6, 8, 9, 1.0)
			p.px(8, 11, 1.0)
		"bolt":
			p.line(10, 1, 5, 8, 1.0)
			p.line(5, 8, 11, 8, 1.0)
			p.line(11, 8, 6, 15, 1.0)
		"steam":
			for i in 3:
				p.circle(4 + i * 4, 9 - i, 2.5, 0.9)
		"sun":
			p.circle(8, 8, 4, 1.0)
			for d: Vector2i in [Vector2i(0, -7), Vector2i(0, 6), Vector2i(-7, 0), Vector2i(6, 0)]:
				p.px(8 + d.x, 8 + d.y, 1.0)
		"moon":
			p.circle(8, 8, 5, 0.9)
			p.circle(10, 6, 4, 0.0)
		"storage", "quest", "gear", "map", "power", "settings", "debug", "stations":
			_paint_tab(p, shape_name)
		"base_0":
			p.line(4, 14, 12, 10, 0.5)
			p.line(4, 10, 12, 14, 0.5)
			p.circle(8, 9, 3, 1.0)
			p.circle(8, 6, 1.5, 0.9)
		"base_1":
			p.rect(2, 7, 12, 7, 0.7)
			p.line(2, 7, 8, 2, 0.85)
			p.line(8, 2, 14, 7, 0.85)
			p.rect(11, 1, 2, 5, 0.5)
			p.rect(6, 10, 4, 4, 0.2)
		"base_2":
			p.rect(1, 6, 14, 8, 0.7)
			p.rect(3, 1, 2, 5, 0.55)
			p.rect(8, 2, 2, 4, 0.55)
			for x in [3, 7, 11]:
				p.rect(x, 9, 2, 2, 1.0)
		_:
			p.rect(3, 3, 10, 10, 0.6)
			p.line(6, 6, 10, 6, 1.0)
			p.line(10, 6, 8, 9, 1.0)
			p.px(8, 11, 1.0)
	p.outline()
	return p.img


static func _paint_tab(p: Painter, shape_name: String) -> void:
	match shape_name:
		"storage":
			for i in 2:
				for j in 2:
					p.rect(2 + i * 7, 2 + j * 7, 5, 5, 0.85)
		"quest":
			p.rect(3, 1, 10, 14, 0.85)
			for y in [4, 7, 10]:
				p.line(5, y, 11, y, 0.4)
		"gear", "settings", "stations":
			p.circle(8, 8, 6, 0.85)
			p.circle(8, 8, 2.5, 0.0)
			for d: Vector2i in [Vector2i(0, -7), Vector2i(0, 6), Vector2i(-7, 0), Vector2i(6, 0)]:
				p.rect(7 + d.x, 7 + d.y, 2, 2, 0.85)
		"map":
			p.rect(1, 3, 14, 10, 0.75)
			p.line(5, 3, 5, 12, 0.5)
			p.line(10, 3, 10, 12, 0.5)
			p.circle(7.5, 8, 1.5, 1.0)
		"power":
			p.line(10, 1, 5, 8, 1.0)
			p.line(5, 8, 11, 8, 1.0)
			p.line(11, 8, 6, 15, 1.0)
			p.line(9, 1, 4, 8, 0.8)
		"debug":
			p.circle(8, 9, 4.5, 0.85)
			p.line(3, 4, 6, 6, 0.85)
			p.line(13, 4, 10, 6, 0.85)
			p.line(8, 5, 8, 13, 0.3)


## Тайл карты 16×16 в цвете с шумом.
static func tile(kind: String) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var base := {"water": Color("#2b4f8a"), "grass": Color("#4f7f3a"), "forest": Color("#3c6a30"),
		"sand": Color("#c9b47a"), "dirt": Color("#7a5a3c"), "hills": Color("#7d7468"),
		"fog": Color("#c8ccd4")}
	var c: Color = base.get(kind, Color.MAGENTA)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for x in SIZE:
		for y in SIZE:
			var k := rng.randf_range(0.9, 1.08)
			if kind == "water" and (x + y * 3) % 7 == 0:
				k = 1.25
			img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, 1.0 if kind != "fog" else 0.9))
	return img
