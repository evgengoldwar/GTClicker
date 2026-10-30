class_name UITheme
extends RefCounted
## Единая тёмная «металлическая» тема интерфейса (раздел 13) и цвета статусов/эпох.

const BG := Color("#1b1d21")
const PANEL := Color("#2a2d33")
const PANEL_LIGHT := Color("#383c44")
const EDGE := Color("#5a606b")
const RIVET := Color("#8a909b")
const TEXT := Color("#e4e6ea")
const TEXT_DIM := Color("#9aa0aa")
const ACCENT := Color("#e0a040")
const GOOD := Color("#5fc06a")
const BAD := Color("#e05a4a")
const WARN := Color("#e0c040")
## Цвет эпохи: каменный век, пар (бронза), LV (серый, как в GT).
const ERA_COLORS: Array[Color] = [Color("#9a7a55"), Color("#d99a3a"), Color("#b8bcc4")]


static func era_color(era: int) -> Color:
	return ERA_COLORS[clampi(era, 0, ERA_COLORS.size() - 1)]


static func box(color: Color, border: Color = EDGE, width: int = 2, radius: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(6)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 2
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.6))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_color", "RichTextLabel", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL))
	t.set_stylebox("panel", "Panel", box(PANEL))
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT))
	t.set_stylebox("hover", "Button", box(PANEL_LIGHT.lightened(0.12), RIVET))
	t.set_stylebox("pressed", "Button", box(PANEL.darkened(0.2), ACCENT))
	t.set_stylebox("disabled", "Button", box(PANEL.darkened(0.1), PANEL_LIGHT))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT, 1))
	t.set_stylebox("normal", "LineEdit", box(BG, EDGE, 1))
	t.set_stylebox("focus", "LineEdit", box(BG, ACCENT, 1))
	t.set_stylebox("background", "ProgressBar", box(BG, EDGE, 1, 2))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, ACCENT.darkened(0.3), 1, 2))
	t.set_stylebox("panel", "PopupMenu", box(PANEL))
	t.set_stylebox("panel", "TooltipPanel", box(BG, ACCENT, 1))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("normal", "OptionButton", box(PANEL_LIGHT))
	t.set_stylebox("hover", "OptionButton", box(PANEL_LIGHT.lightened(0.12), RIVET))
	t.set_stylebox("pressed", "OptionButton", box(PANEL.darkened(0.2), ACCENT))
	t.set_stylebox("panel", "TabContainer", box(PANEL))
	t.set_stylebox("embedded_border", "Window", box(PANEL, ACCENT))
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_constant("separation", "VBoxContainer", 6)
	return t


## Панель с «заклёпками» по углам.
static func riveted_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.draw.connect(func() -> void:
		for c: Vector2 in [Vector2(5, 5), Vector2(p.size.x - 5, 5), Vector2(5, p.size.y - 5), p.size - Vector2(5, 5)]:
			p.draw_circle(c, 2.0, RIVET))
	return p
