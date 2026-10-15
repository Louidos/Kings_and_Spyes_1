## HelpPanel
##
## Hilfefenster (F1, Knopf im Spielmenü): Reiter Steuerung (alle Tasten aus
## data/help.json, die Tasten selbst aus der aktuellen Eingabe-Zuordnung),
## Spielablauf (Kurztexte) und Schwierigkeit (alle Werte je Grad).
## Liegt über dem Spielmenü, damit es auch von dort aus lesbar ist; Esc schliesst.
class_name HelpPanel
extends CanvasLayer

signal toggled(open: bool)

const LAYER := 41

## Fenstergrösse (logische Punkte bei UI-Grösse 100 %)
const WIDTH := 1000.0
const HEIGHT := 700.0
## Breite der Tasten-Spalte im Reiter "Steuerung"
const KEYS_WIDTH := 330.0
const FONT_SIZE := 16

var _root: Control
var _pages: Array[Control] = []
var _tab_buttons: Array[Button] = []


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(WIDTH, HEIGHT)
	var evil := UiStyle.is_evil()
	panel.add_theme_stylebox_override("panel", UiStyle.window_style(evil))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	var header := UiStyle.window_header(box, "Hilfe", evil, "Schliessen (F1 oder Esc)", close)
	var group := ButtonGroup.new()
	var pages := MarginContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(pages)
	for entry in [["Steuerung", "Alle Tasten nach Thema (aus der aktuellen Tastenbelegung)", _build_controls()],
			["Spielablauf", "Kurztexte zu Wirtschaft, Kampf, Helden, Diplomatie und mehr", _build_topics()],
			["Schwierigkeit", "Alle Werte der Schwierigkeitsgrade", _build_difficulty()]]:
		var tab := UiStyle.tab_button(str(entry[0]), group, evil)
		tab.tooltip_text = str(entry[1])
		var index := _pages.size()
		tab.pressed.connect(_show_page.bind(index))
		UiStyle.header_add(header, tab)
		_tab_buttons.append(tab)
		var page := _scroll(str(entry[0]), entry[2] as Control)
		pages.add_child(page)
		_pages.append(page)
	box.add_child(UiStyle.footer_label("Die Tasten stehen auch in den Tooltips der Knöpfe  ·  F1 / Esc: schliessen"))
	_show_page(0)
	UiStyle.register_scaled_layer(self, _root)


func is_open() -> bool:
	return visible


func _show_page(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index
		_tab_buttons[i].set_pressed_no_signal(i == index)


func open() -> void:
	visible = true
	toggled.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	toggled.emit(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Esc schliesst die Hilfe vor allem anderen (auch über dem Spielmenü)
func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("game_menu") or event.is_action_pressed("toggle_help")):
		close()
		get_viewport().set_input_as_handled()


## Alle Aktionen, die die Hilfe nennt (Rauchtest vergleicht mit der Eingabe-Zuordnung)
static func listed_actions() -> Array:
	var out: Array = []
	for section in DataDB.help_cfg.get("sections", []):
		for row in section.get("rows", []):
			if row.has("action"):
				out.append(str(row["action"]))
	return out


## Deutsche Namen der Tasten, die Godot englisch nennt
const KEY_NAMES := {"Space": "Leertaste", "Escape": "Esc", "Equal": "=", "Plus": "+", "Minus": "−",
		"Kp Add": "Num +", "Kp Subtract": "Num −", "Home": "Pos1", "End": "Ende", "Pageup": "Bild↑",
		"Pagedown": "Bild↓", "Delete": "Entf", "Enter": "Eingabe", "Shift": "Umschalt", "Ctrl": "Strg",
		"Up": "↑", "Down": "↓", "Left": "←", "Right": "→"}


## Tasten einer Aktion als Text ("F1", "Leertaste, P")
static func keys_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var parts: PackedStringArray = []
	for ev in InputMap.action_get_events(action):
		var key := ev as InputEventKey
		if key == null:
			continue
		var text := ""
		if key.physical_keycode != 0:
			# Ohne Fenster (Rauchtest) kennt der Bildschirmdienst die Tastaturbelegung nicht
			var code := key.physical_keycode if DisplayServer.get_name() == "headless" \
					else DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
			text = OS.get_keycode_string(code)
		else:
			text = OS.get_keycode_string(key.keycode)
		if text.is_empty():
			text = key.as_text().replace("Ctrl+", "Strg+").replace("Shift+", "Umschalt+")
		text = str(KEY_NAMES.get(text, text))
		if key.ctrl_pressed and not text.begins_with("Strg"):
			text = "Strg+" + text
		if not parts.has(text):
			parts.append(text)
	return ", ".join(parts)


func _scroll(title: String, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


func _build_controls() -> Control:
	var box := VBoxContainer.new()
	for section in DataDB.help_cfg.get("sections", []):
		box.add_child(_heading(str(section.get("title", ""))))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 3)
		for row in section.get("rows", []):
			var keys := keys_text(str(row["action"])) if row.has("action") else str(row.get("keys", ""))
			var k := Label.new()
			k.text = keys
			k.custom_minimum_size.x = KEYS_WIDTH
			k.add_theme_font_size_override("font_size", FONT_SIZE)
			k.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
			k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			grid.add_child(k)
			var t := Label.new()
			t.text = str(row.get("text", ""))
			t.add_theme_font_size_override("font_size", FONT_SIZE)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			grid.add_child(t)
		box.add_child(grid)
	return box


func _build_topics() -> Control:
	var box := VBoxContainer.new()
	for topic in DataDB.help_cfg.get("topics", []):
		box.add_child(_heading(str(topic.get("title", ""))))
		box.add_child(_text(str(topic.get("text", ""))))
	return box


func _build_difficulty() -> Control:
	var box := VBoxContainer.new()
	for d in DataDB.difficulties:
		var id := str(d.get("id", ""))
		var title := str(d.get("name", id))
		if id == GameSession.difficulty_id:
			title += " (diese Partie)"
		box.add_child(_heading(title))
		box.add_child(_text(Difficulty.describe(id)))
	return box


static func _heading(text: String) -> Label:
	var l := UiStyle.section_label(text, UiStyle.is_evil())
	l.custom_minimum_size.y = 34
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


static func _text(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
