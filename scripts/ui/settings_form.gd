## SettingsForm
##
## Formular der Einstellungen (Hauptmenü und Spielmenü): Ton, Kamera, Anzeige, Spiel.
## Änderungen wirken sofort (Settings.apply); "Speichern und zurück" schreibt die
## Datei, "Standard" setzt die Standardwerte.
class_name SettingsForm
extends VBoxContainer

## "Speichern und zurück" wurde gedrückt (Datei ist schon geschrieben)
signal closed

const BUS_NAMES := {"Master": "Gesamt", "Music": "Musik", "SFX": "Effekte", "UI": "Oberfläche"}

var _volume_sliders := {}
var _volume_labels := {}
var _edge_check: CheckBox
var _speed_slider: HSlider
var _fullscreen_check: CheckBox
var _ui_scale_slider: HSlider
var _ui_scale_label: Label
var _tint_check: CheckBox
var _autosave_option: OptionButton
var _compress_check: CheckBox
var _back_button: Button
## Während refresh() die Werte setzt, nichts übernehmen
var _updating := false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Einstellungen"
	title.add_theme_font_size_override("font_size", UiStyle.WINDOW_TITLE_SIZE)
	title.add_theme_color_override("font_color", UiStyle.title_color(UiStyle.is_evil()))
	add_child(title)
	_group("Ton")
	for bus in Settings.BUSES:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(BUS_NAMES.get(bus, bus))
		label.custom_minimum_size.x = 150
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.x = 180
		slider.tooltip_text = "Lautstärke %s (0 = stumm)" % str(BUS_NAMES.get(bus, bus))
		slider.value_changed.connect(_on_volume.bind(str(bus)))
		row.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size.x = 56
		row.add_child(value)
		add_child(row)
		_volume_sliders[bus] = slider
		_volume_labels[bus] = value
	_group("Kamera")
	_edge_check = _check("Kamera am Bildschirmrand verschieben", "Maus an den Bildschirmrand bewegt die Karte")
	_speed_slider = _slider_row("Kamera-Tempo", 0.5, 2.0, 0.1, "Wie schnell die Kamera mit Tasten und am Rand fährt")
	_group("Anzeige")
	_fullscreen_check = _check("Vollbild", "Spiel im Vollbild anzeigen")
	_ui_scale_slider = _slider_row("Grösse der Oberfläche", 0.75, 1.5, 0.05,
			"Leisten, Menüs und Fenster grösser oder kleiner darstellen")
	_ui_scale_label = Label.new()
	(_ui_scale_slider.get_parent() as HBoxContainer).add_child(_ui_scale_label)
	_tint_check = _check("Tag-Nacht-Abdunklung", "Die Karte wird nachts dunkler (ab Phase 8)")
	_group("Spiel")
	var row2 := HBoxContainer.new()
	var label2 := Label.new()
	label2.text = "Automatisch speichern"
	label2.custom_minimum_size.x = 150
	row2.add_child(label2)
	_autosave_option = OptionButton.new()
	_autosave_option.tooltip_text = "Abstand der automatischen Spielstände (echte Spielzeit, reihum %d Plätze)" % \
			int(DataDB.cfg("save.autosave_slots", 3))
	for m in Settings.AUTOSAVE_STEPS:
		_autosave_option.add_item("aus" if int(m) == 0 else "alle %d Minuten" % int(m))
		_autosave_option.set_item_metadata(_autosave_option.item_count - 1, int(m))
	_autosave_option.item_selected.connect(func(_i: int) -> void: _take())
	row2.add_child(_autosave_option)
	add_child(row2)
	_compress_check = _check("Spielstände komprimieren", "Spielstände kleiner speichern (zstd)")
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var defaults := Button.new()
	defaults.text = "Standard"
	defaults.tooltip_text = "Alle Einstellungen auf die Standardwerte setzen"
	defaults.pressed.connect(func() -> void:
		Settings.reset_defaults()
		Settings.apply()
		refresh())
	buttons.add_child(defaults)
	_back_button = Button.new()
	_back_button.text = "Speichern und zurück"
	_back_button.tooltip_text = "Einstellungen speichern"
	_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_button.pressed.connect(save_and_close)
	buttons.add_child(_back_button)
	add_child(buttons)
	refresh()


## Werte aus Settings übernehmen
func refresh() -> void:
	_updating = true
	for bus in _volume_sliders:
		(_volume_sliders[bus] as HSlider).value = Settings.get_volume(str(bus))
		(_volume_labels[bus] as Label).text = "%d %%" % roundi(Settings.get_volume(str(bus)) * 100.0)
	_edge_check.button_pressed = Settings.edge_scroll
	_speed_slider.value = Settings.camera_speed
	_fullscreen_check.button_pressed = Settings.fullscreen
	_ui_scale_slider.value = Settings.ui_scale
	_ui_scale_label.text = "%d %%" % roundi(Settings.ui_scale * 100.0)
	_tint_check.button_pressed = Settings.day_night_tint
	for i in _autosave_option.item_count:
		if int(_autosave_option.get_item_metadata(i)) == Settings.autosave_minutes:
			_autosave_option.select(i)
	_compress_check.button_pressed = Settings.compress_saves
	_updating = false


## Rauchtest und Knopf: speichern, schliessen
func save_and_close() -> void:
	_take()
	Settings.save_settings()
	closed.emit()


## Rauchtest: Werte direkt setzen (wie über die Elemente)
func set_values(ui_scale: float, autosave_minutes: int, master_volume: float) -> void:
	_ui_scale_slider.value = ui_scale
	for i in _autosave_option.item_count:
		if int(_autosave_option.get_item_metadata(i)) == autosave_minutes:
			_autosave_option.select(i)
	(_volume_sliders["Master"] as HSlider).value = master_volume
	_take()


func _take() -> void:
	if _updating:
		return
	for bus in _volume_sliders:
		Settings.set_volume(str(bus), (_volume_sliders[bus] as HSlider).value)
	Settings.edge_scroll = _edge_check.button_pressed
	Settings.camera_speed = _speed_slider.value
	Settings.fullscreen = _fullscreen_check.button_pressed
	Settings.ui_scale = _ui_scale_slider.value
	Settings.day_night_tint = _tint_check.button_pressed
	if _autosave_option.selected >= 0:
		Settings.autosave_minutes = int(_autosave_option.get_item_metadata(_autosave_option.selected))
	Settings.compress_saves = _compress_check.button_pressed
	Settings.apply()
	_updating = true
	for bus in _volume_labels:
		(_volume_labels[bus] as Label).text = "%d %%" % roundi(Settings.get_volume(str(bus)) * 100.0)
	_ui_scale_label.text = "%d %%" % roundi(Settings.ui_scale * 100.0)
	_updating = false


func _on_volume(_v: float, _bus: String) -> void:
	_take()


func _group(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	add_child(label)


func _check(text: String, tip: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.toggled.connect(func(_on: bool) -> void: _take())
	add_child(c)
	return c


func _slider_row(text: String, from: float, to: float, step: float, tip: String) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 150
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = from
	slider.max_value = to
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 180
	slider.tooltip_text = tip
	slider.value_changed.connect(func(_v: float) -> void: _take())
	row.add_child(slider)
	add_child(row)
	return slider
