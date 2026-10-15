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

var _root: Control
var _tabs: TabContainer


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
	panel.custom_minimum_size = Vector2(900, 640)
	center.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(UiStyle.make_title_bar("Hilfe", close))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_tabs.add_child(_scroll("Steuerung", _build_controls()))
	_tabs.add_child(_scroll("Spielablauf", _build_topics()))
	_tabs.add_child(_scroll("Schwierigkeit", _build_difficulty()))
	UiStyle.register_scaled_layer(self, _root)


func is_open() -> bool:
	return visible


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
			text = key.as_text()
		elif key.ctrl_pressed:
			text = "Strg+" + text
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
		for row in section.get("rows", []):
			var keys := keys_text(str(row["action"])) if row.has("action") else str(row.get("keys", ""))
			var k := Label.new()
			k.text = keys
			k.custom_minimum_size.x = 300
			k.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
			k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			grid.add_child(k)
			var t := Label.new()
			t.text = str(row.get("text", ""))
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
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	return l


static func _text(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
