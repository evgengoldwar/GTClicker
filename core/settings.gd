extends Node
## Settings: формат чисел, язык, громкость, «уменьшить анимации», автосохранение.
## Переводы RU/EN грузятся из res://i18n/strings.csv (ключ, en, ru) в TranslationServer.

signal changed()

const PATH := "user://settings.cfg"
const I18N := "res://i18n/strings.csv"

var number_format: int = NumFormat.Mode.SI
var language := "ru"
var volume := 0.8
var reduce_animations := false
var autosave := true


func _ready() -> void:
	load_translations()
	load_settings()
	apply()


func load_translations() -> void:
	var f := FileAccess.open(I18N, FileAccess.READ)
	if f == null:
		push_error("[Settings] нет файла переводов " + I18N)
		return
	var header := f.get_csv_line()
	var translations: Array[Translation] = []
	for i in range(1, header.size()):
		var t := Translation.new()
		t.locale = header[i]
		translations.append(t)
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0].is_empty() or row[0].begins_with("#"):
			continue
		for i in range(1, mini(row.size(), header.size())):
			translations[i - 1].add_message(row[0], row[i].replace("\\n", "\n"))
	for t in translations:
		TranslationServer.add_translation(t)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	number_format = int(cfg.get_value("ui", "number_format", number_format))
	language = str(cfg.get_value("ui", "language", language))
	volume = float(cfg.get_value("audio", "volume", volume))
	reduce_animations = bool(cfg.get_value("ui", "reduce_animations", reduce_animations))
	autosave = bool(cfg.get_value("game", "autosave", autosave))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "number_format", number_format)
	cfg.set_value("ui", "language", language)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("ui", "reduce_animations", reduce_animations)
	cfg.set_value("game", "autosave", autosave)
	cfg.save(PATH)


func apply() -> void:
	NumFormat.mode = number_format as NumFormat.Mode
	TranslationServer.set_locale(language)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	changed.emit()


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	apply()
	save_settings()
