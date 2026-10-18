## SettingsForm
##
## Formular der Einstellungen (Hauptmenü und Spielmenü) in fünf Reitern (UiStyle.tab_button):
## Grafik (Vollbild, VSync, Bildrate, Tag-Nacht-Abdunklung) · Ton (Lautstärken) · Steuerung
## (Rand-Scrollen, Kamera-, Rand- und Zoomtempo) · Oberfläche (Grösse, Lebensbalken, Meldungsdauer,
## Minikarte, kompaktes HUD) · Spiel (automatisch speichern, komprimieren, Starttempo, Rückfrage vor einer
## Kriegserklärung, Tooltip-Verzögerung). Änderungen wirken sofort (Settings.apply);
## "Speichern und zurück" schreibt die Datei, "Standard" setzt alle Standardwerte.
class_name SettingsForm
extends VBoxContainer

## "Speichern und zurück" wurde gedrückt (Datei ist schon geschrieben)
signal closed

const BUS_NAMES := {"Master": "Gesamt", "Music": "Musik", "SFX": "Effekte", "UI": "Oberfläche"}
## Reiter: [id, Name, Tooltip]
const TABS := [["graphics", "Grafik", "Vollbild, VSync, Bildrate und Tag-Nacht-Abdunklung"],
		["audio", "Ton", "Lautstärken"],
		["controls", "Steuerung", "Kamera: Tasten, Bildschirmrand und Zoom"],
		["interface", "Oberfläche", "Grösse der Oberfläche, Lebensbalken, Meldungen und Minikarte"],
		["game", "Spiel", "Speichern, Tempo zu Beginn, Rückfragen und Tooltips"]]
## Breite der Beschriftung links neben einem Regler
const LABEL_WIDTH := 215
## Tooltip-Verzögerungen zur Auswahl (Sekunden)
const TOOLTIP_STEPS := [0.1, 0.3, 0.5, 0.8, 1.2]

var _volume_sliders := {}
var _volume_labels := {}
var _edge_check: CheckBox
var _speed_slider: HSlider
var _edge_speed_slider: HSlider
var _zoom_slider: HSlider
var _fullscreen_check: CheckBox
var _vsync_check: CheckBox
var _fps_option: OptionButton
var _ui_scale_slider: HSlider
var _tint_check: CheckBox
var _hp_option: OptionButton
var _notify_option: OptionButton
var _minimap_slider: HSlider
var _compact_check: CheckBox
var _autosave_option: OptionButton
var _compress_check: CheckBox
var _start_speed_option: OptionButton
var _war_check: CheckBox
var _tooltip_option: OptionButton
var _back_button: Button
## Prozentanzeige je Regler (HSlider -> Label)
var _value_labels := {}
## Reiter-id -> Seite (VBoxContainer) bzw. Knopf
var _pages := {}
var _tab_buttons := {}
var _tab := "graphics"
## Seite, in die _check/_slider_row/_option_row gerade einfügen
var _page: VBoxContainer
## Während refresh() die Werte setzt, nichts übernehmen
var _updating := false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var evil := UiStyle.is_evil()
	var title := Label.new()
	title.text = "Einstellungen"
	title.add_theme_font_size_override("font_size", UiStyle.WINDOW_TITLE_SIZE)
	title.add_theme_color_override("font_color", UiStyle.title_color(evil))
	add_child(title)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	add_child(tabs)
	var group := ButtonGroup.new()
	for entry in TABS:
		var b := UiStyle.tab_button(str(entry[1]), group, evil, 96.0)
		b.tooltip_text = str(entry[2])
		b.pressed.connect(select_tab.bind(str(entry[0])))
		tabs.add_child(b)
		_tab_buttons[str(entry[0])] = b
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 6)
		page.custom_minimum_size = Vector2(0, 250)
		add_child(page)
		_pages[str(entry[0])] = page
	# Grafik
	_page = _pages["graphics"]
	_fullscreen_check = _check("Vollbild", "Spiel im Vollbild anzeigen")
	_vsync_check = _check("VSync", "Bild mit der Bildwiederholrate des Bildschirms abgleichen (verhindert Bildrisse)")
	_fps_option = _option_row("Bildrate-Grenze", "Höchstens so viele Bilder pro Sekunde (spart Strom und Wärme)")
	for f in Settings.FPS_STEPS:
		_add_item(_fps_option, "unbegrenzt" if int(f) == 0 else "%d Bilder/s" % int(f), int(f))
	_tint_check = _check("Tag-Nacht-Abdunklung", "Die Karte wird nachts dunkler")
	# Ton
	_page = _pages["audio"]
	for bus in Settings.BUSES:
		var slider := _slider_row(str(BUS_NAMES.get(bus, bus)), 0.0, 1.0, 0.05,
				"Lautstärke %s (0 = stumm)" % str(BUS_NAMES.get(bus, bus)))
		_volume_sliders[bus] = slider
		_volume_labels[bus] = _value_labels[slider]
	# Steuerung
	_page = _pages["controls"]
	_edge_check = _check("Kamera am Bildschirmrand verschieben", "Maus an den Bildschirmrand bewegt die Karte")
	_speed_slider = _slider_row("Kamera-Tempo (Tasten)", 0.5, 2.0, 0.1, "Wie schnell die Kamera mit WASD und den Pfeiltasten fährt")
	_edge_speed_slider = _slider_row("Tempo am Bildschirmrand", 0.5, 2.0, 0.1, "Wie schnell die Kamera fährt, wenn die Maus am Rand steht")
	_zoom_slider = _slider_row("Zoom-Tempo", 0.5, 2.0, 0.1, "Wie stark eine Raste am Mausrad bzw. Q/E zoomt")
	# Oberfläche
	_page = _pages["interface"]
	_ui_scale_slider = _slider_row("Grösse der Oberfläche", 0.75, 1.5, 0.05,
			"Leisten, Menüs und Fenster grösser oder kleiner darstellen")
	_hp_option = _option_row("Lebensbalken", "Wann über Einheiten und Gebäuden ein Lebensbalken erscheint")
	for mode in Settings.HP_BAR_MODES:
		_add_item(_hp_option, str(Settings.HP_BAR_NAMES.get(mode, mode)), str(mode))
	_notify_option = _option_row("Meldungen sichtbar", "Wie lange eine Meldung oben rechts stehen bleibt (alle stehen im Protokoll, M)")
	for sec in Settings.NOTIFY_STEPS:
		_add_item(_notify_option, "%d Sekunden" % roundi(float(sec)), float(sec))
	_minimap_slider = _slider_row("Grösse der Minikarte", 0.75, 1.5, 0.05, "Minikarte rechts unten grösser oder kleiner")
	_compact_check = _check("Kompaktes HUD", "Weniger Text: Fenster-Knöpfe oben nur als Symbol, Kurznamen im Baumenü, ohne Hinweiszeile")
	# Spiel
	_page = _pages["game"]
	_autosave_option = _option_row("Automatisch speichern",
			"Abstand der automatischen Spielstände (echte Spielzeit, reihum %d Plätze)" % int(DataDB.cfg("save.autosave_slots", 3)))
	for m in Settings.AUTOSAVE_STEPS:
		_add_item(_autosave_option, "aus" if int(m) == 0 else "alle %d Minuten" % int(m), int(m))
	_compress_check = _check("Spielstände komprimieren", "Spielstände kleiner speichern (zstd)")
	_start_speed_option = _option_row("Tempo zu Beginn", "Spieltempo, mit dem eine neue Partie startet")
	_add_item(_start_speed_option, "Standard", -1)
	var steps: Array = DataDB.cfg("time.speed_steps", [0.5, 1.0, 2.0, 3.0])
	for i in steps.size():
		_add_item(_start_speed_option, "%sx" % String.num(float(steps[i]), 1).trim_suffix(".0").replace(".", ","), i)
	_war_check = _check("Rückfrage vor einer Kriegserklärung",
			"An: Krieg erst mit einem zweiten Klick erklären (Rechtsklick auf ein friedliches Dorf, Diplomatiefenster). Aus: sofort")
	_tooltip_option = _option_row("Tooltip-Verzögerung", "Wie lange die Maus stillstehen muss, bis ein Tooltip erscheint (gilt ab dem nächsten Start)")
	for t in TOOLTIP_STEPS:
		_add_item(_tooltip_option, "%s s" % String.num(float(t), 1).replace(".", ","), float(t))
	var note := Label.new()
	note.text = "Die Tooltip-Verzögerung gilt ab dem nächsten Start."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	_page.add_child(note)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var defaults := Button.new()
	defaults.text = "Standard"
	defaults.tooltip_text = "Alle Einstellungen (alle Reiter) auf die Standardwerte setzen"
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
	select_tab(_tab)
	refresh()


## Reiter zeigen ("graphics", "audio", "controls", "interface", "game")
func select_tab(tab_id: String) -> void:
	_tab = tab_id if _pages.has(tab_id) else "graphics"
	for id in _pages:
		(_pages[id] as Control).visible = id == _tab
		(_tab_buttons[id] as Button).set_pressed_no_signal(id == _tab)


func get_tab() -> String:
	return _tab


## Seite eines Reiters (Rauchtest)
func get_page(tab_id: String) -> VBoxContainer:
	return _pages.get(tab_id)


## Werte aus Settings übernehmen
func refresh() -> void:
	_updating = true
	for bus in _volume_sliders:
		(_volume_sliders[bus] as HSlider).value = Settings.get_volume(str(bus))
	_edge_check.button_pressed = Settings.edge_scroll
	_speed_slider.value = Settings.camera_speed
	_edge_speed_slider.value = Settings.edge_scroll_speed
	_zoom_slider.value = Settings.zoom_speed
	_fullscreen_check.button_pressed = Settings.fullscreen
	_vsync_check.button_pressed = Settings.vsync
	_select(_fps_option, Settings.max_fps)
	_ui_scale_slider.value = Settings.ui_scale
	_tint_check.button_pressed = Settings.day_night_tint
	_select(_hp_option, Settings.hp_bars)
	_select(_notify_option, Settings.notify_seconds)
	_minimap_slider.value = Settings.minimap_scale
	_compact_check.button_pressed = Settings.compact_hud
	_select(_autosave_option, Settings.autosave_minutes)
	_compress_check.button_pressed = Settings.compress_saves
	_select(_start_speed_option, Settings.start_speed_index)
	_war_check.button_pressed = Settings.confirm_war
	_select(_tooltip_option, Settings.tooltip_delay)
	_update_value_labels()
	_updating = false


## Rauchtest und Knopf: speichern, schliessen
func save_and_close() -> void:
	_take()
	Settings.save_settings()
	closed.emit()


## Rauchtest: Werte direkt setzen (wie über die Elemente)
func set_values(ui_scale: float, autosave_minutes: int, master_volume: float) -> void:
	_ui_scale_slider.value = ui_scale
	_select(_autosave_option, autosave_minutes)
	(_volume_sliders["Master"] as HSlider).value = master_volume
	_take()


## Rauchtest: die neuen Einstellungen über die Elemente setzen
func set_more_values(values: Dictionary) -> void:
	if values.has("vsync"):
		_vsync_check.button_pressed = bool(values["vsync"])
	if values.has("max_fps"):
		_select(_fps_option, int(values["max_fps"]))
	if values.has("zoom_speed"):
		_zoom_slider.value = float(values["zoom_speed"])
	if values.has("edge_scroll_speed"):
		_edge_speed_slider.value = float(values["edge_scroll_speed"])
	if values.has("hp_bars"):
		_select(_hp_option, str(values["hp_bars"]))
	if values.has("notify_seconds"):
		_select(_notify_option, float(values["notify_seconds"]))
	if values.has("minimap_scale"):
		_minimap_slider.value = float(values["minimap_scale"])
	if values.has("compact_hud"):
		_compact_check.button_pressed = bool(values["compact_hud"])
	if values.has("start_speed_index"):
		_select(_start_speed_option, int(values["start_speed_index"]))
	if values.has("confirm_war"):
		_war_check.button_pressed = bool(values["confirm_war"])
	if values.has("tooltip_delay"):
		_select(_tooltip_option, float(values["tooltip_delay"]))
	_take()


func _take() -> void:
	if _updating:
		return
	for bus in _volume_sliders:
		Settings.set_volume(str(bus), (_volume_sliders[bus] as HSlider).value)
	Settings.edge_scroll = _edge_check.button_pressed
	Settings.camera_speed = _speed_slider.value
	Settings.edge_scroll_speed = _edge_speed_slider.value
	Settings.zoom_speed = _zoom_slider.value
	Settings.fullscreen = _fullscreen_check.button_pressed
	Settings.vsync = _vsync_check.button_pressed
	Settings.max_fps = int(_selected(_fps_option, Settings.max_fps))
	Settings.ui_scale = _ui_scale_slider.value
	Settings.day_night_tint = _tint_check.button_pressed
	Settings.hp_bars = str(_selected(_hp_option, Settings.hp_bars))
	Settings.notify_seconds = float(_selected(_notify_option, Settings.notify_seconds))
	Settings.minimap_scale = _minimap_slider.value
	Settings.compact_hud = _compact_check.button_pressed
	Settings.autosave_minutes = int(_selected(_autosave_option, Settings.autosave_minutes))
	Settings.compress_saves = _compress_check.button_pressed
	Settings.start_speed_index = int(_selected(_start_speed_option, Settings.start_speed_index))
	Settings.confirm_war = _war_check.button_pressed
	Settings.tooltip_delay = float(_selected(_tooltip_option, Settings.tooltip_delay))
	Settings.apply()
	_updating = true
	_update_value_labels()
	_updating = false


## Prozentwerte neben den Reglern
func _update_value_labels() -> void:
	for slider in _value_labels:
		(_value_labels[slider] as Label).text = "%d %%" % roundi((slider as HSlider).value * 100.0)


func _add_item(option: OptionButton, text: String, meta: Variant) -> void:
	option.add_item(text)
	option.set_item_metadata(option.item_count - 1, meta)


## Eintrag mit diesem Wert wählen (Zahlen ungefähr gleich); sonst bleibt die Auswahl
func _select(option: OptionButton, value: Variant) -> void:
	for i in option.item_count:
		var meta: Variant = option.get_item_metadata(i)
		var same := false
		if (meta is float or meta is int) and (value is float or value is int):
			same = is_equal_approx(float(meta), float(value))
		else:
			same = str(meta) == str(value)
		if same:
			option.select(i)
			return


func _selected(option: OptionButton, fallback: Variant) -> Variant:
	if option.selected < 0:
		return fallback
	return option.get_item_metadata(option.selected)


func _check(text: String, tip: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.toggled.connect(func(_on: bool) -> void: _take())
	_page.add_child(c)
	return c


func _row(text: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.tooltip_text = tip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(label)
	_page.add_child(row)
	return row


func _option_row(text: String, tip: String) -> OptionButton:
	var row := _row(text, tip)
	var option := OptionButton.new()
	option.tooltip_text = tip
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(func(_i: int) -> void: _take())
	row.add_child(option)
	return option


func _slider_row(text: String, from: float, to: float, step: float, tip: String) -> HSlider:
	var row := _row(text, tip)
	var slider := HSlider.new()
	slider.min_value = from
	slider.max_value = to
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 180
	slider.tooltip_text = tip
	slider.value_changed.connect(func(_v: float) -> void: _take())
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 56
	row.add_child(value)
	_value_labels[slider] = value
	return slider
