class_name SettingsPanel
extends VBoxContainer
## Настройки: формат чисел, язык, звук, «уменьшить анимации», автосохранение,
## экспорт/импорт сейва строкой base64, новая игра.

signal language_changed()

## Слой модальных окон главного экрана.
var modal_host: Control
var _export := TextEdit.new()
var _status := UIKit.label("", 13, UITheme.TEXT_DIM)


func _ready() -> void:
	add_child(UIKit.label(tr("TAB_SETTINGS"), 20, UITheme.ACCENT))
	var fmt := OptionButton.new()
	for k in ["NUMFMT_SI", "NUMFMT_SHORT", "NUMFMT_SCI", "NUMFMT_FULL"]:
		fmt.add_item(tr(k))
	fmt.selected = Settings.number_format
	fmt.item_selected.connect(func(i: int) -> void: Settings.set_value("number_format", i))
	add_child(_row(tr("SET_NUMBER_FORMAT"), fmt))
	var lang := OptionButton.new()
	lang.add_item("Русский")
	lang.add_item("English")
	lang.selected = 0 if Settings.language == "ru" else 1
	lang.item_selected.connect(func(i: int) -> void:
		Settings.set_value("language", "ru" if i == 0 else "en")
		language_changed.emit())
	add_child(_row(tr("SET_LANGUAGE"), lang))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Settings.volume
	vol.custom_minimum_size.x = 200
	vol.value_changed.connect(func(v: float) -> void: Settings.set_value("volume", v))
	add_child(_row(tr("SET_VOLUME"), vol))
	add_child(_check(tr("SET_REDUCE_ANIM"), "reduce_animations"))
	add_child(_check(tr("SET_AUTOSAVE"), "autosave"))
	var buttons := UIKit.hbox()
	buttons.add_child(UIKit.button(tr("SET_SAVE_NOW"), func() -> void:
		_status.text = tr("SET_SAVED") if Save.save_game() else tr("SET_SAVE_FAILED")))
	buttons.add_child(UIKit.button(tr("SET_EXPORT"), func() -> void:
		_export.text = Save.export_string()
		DisplayServer.clipboard_set(_export.text)
		_status.text = tr("SET_EXPORTED")))
	buttons.add_child(UIKit.button(tr("SET_IMPORT"), func() -> void:
		_status.text = tr("SET_IMPORTED") if Save.import_string(_export.text) else tr("SET_IMPORT_FAILED")))
	add_child(buttons)
	_export.custom_minimum_size = Vector2(400, 110)
	_export.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_export.placeholder_text = tr("SET_EXPORT_HINT")
	add_child(_export)
	add_child(_status)
	var reset := UIKit.button(tr("SET_NEW_GAME"), func() -> void: _confirm_new_game())
	reset.add_theme_color_override("font_color", UITheme.BAD)
	add_child(reset)
	add_child(UIKit.label(tr("SET_HOTKEYS"), 12, UITheme.TEXT_DIM))


func _row(text: String, control: Control) -> HBoxContainer:
	var h := UIKit.hbox()
	var l := UIKit.label(text, 14)
	l.custom_minimum_size.x = 220
	h.add_child(l)
	h.add_child(control)
	return h


func _check(text: String, key: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = bool(Settings.get(key))
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	return c


func _confirm_new_game() -> void:
	var v := UIKit.modal(modal_host, tr("SET_NEW_GAME"), Vector2(420, 160))
	v.add_child(UIKit.label(tr("SET_NEW_GAME_CONFIRM"), 14))
	v.add_child(UIKit.button(tr("SET_NEW_GAME_YES"), func() -> void:
		Save.delete_save()
		Save.new_game()
		UIKit.close_modal(v)))
