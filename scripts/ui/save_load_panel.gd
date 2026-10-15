## SaveLoadPanel
##
## Liste der Spielstände für das Hauptmenü (Laden) und das Spielmenü (Speichern und
## Laden). Jede Zeile zeigt Name, Art, Spielzeit, Fraktion/Volk/Schwierigkeit/Karte,
## Datum und Grösse. Nicht ladbare Spielstände sind grau mit Grund; ist eine Datei
## defekt, aber eine Sicherung (.bak) da, kann diese geladen werden.
## Rückfragen (Überschreiben, Löschen, ungespeicherter Fortschritt) über einen
## ConfirmationDialog.
class_name SaveLoadPanel
extends PanelContainer

## "Zurück" gedrückt
signal closed
## Ein Spielstand soll geladen werden (Speicherplatz oder Pfad einer Sicherung)
signal load_requested(slot: String)

const KIND_NAMES := {"manual": "", "quick": "Schnellspeicherung", "auto": "Autospeicherung"}
const COLOR_REASON := Color(1.0, 0.45, 0.4)
const COLOR_HINT := Color(1.0, 0.85, 0.35)
const COLOR_INFO := Color(0.8, 0.77, 0.7)

## Spielszene (nur im Spielmenü; nötig zum Speichern)
var game: Node = null
var mode := "load"
## Im Hintergrund speichern (der Rauchtest speichert synchron)
var async_save := true

var _title: Label
var _name_row: HBoxContainer
var _name_edit: LineEdit
var _save_button: Button
var _name_reason: Label
var _list: VBoxContainer
var _status: Label
var _confirm: ConfirmationDialog
var _pending_action: Callable = Callable()
var _rows: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(640, 520)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", UiStyle.WINDOW_TITLE_SIZE)
	_title.add_theme_color_override("font_color", UiStyle.title_color(UiStyle.is_evil()))
	box.add_child(_title)
	var line := ColorRect.new()
	line.color = Color(UiStyle.accent(UiStyle.is_evil()), 0.55)
	line.custom_minimum_size = Vector2(0, 1)
	box.add_child(line)
	_name_row = HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Name"
	_name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.max_length = 60
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.tooltip_text = "Name des Spielstands (höchstens %d Zeichen)" % SaveManager.MAX_NAME_LENGTH
	_name_edit.text_submitted.connect(func(_t: String) -> void: press_save())
	_name_row.add_child(_name_edit)
	_save_button = Button.new()
	_save_button.text = "Speichern"
	_save_button.tooltip_text = "Partie unter diesem Namen speichern"
	_save_button.pressed.connect(press_save)
	_name_row.add_child(_save_button)
	box.add_child(_name_row)
	_name_reason = Label.new()
	_name_reason.add_theme_color_override("font_color", COLOR_REASON)
	box.add_child(_name_reason)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var back := Button.new()
	back.text = "Zurück"
	back.tooltip_text = "Zurück zum Menü"
	back.pressed.connect(func() -> void: closed.emit())
	box.add_child(back)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Rückfrage"
	_confirm.cancel_button_text = "Abbrechen"
	_confirm.confirmed.connect(confirm_pending)
	add_child(_confirm)
	SaveManager.saves_changed.connect(_on_saves_changed)
	SaveManager.save_finished.connect(_on_save_finished)


## "save" oder "load"
func open_mode(p_mode: String) -> void:
	mode = p_mode
	_title.text = "Spiel speichern" if mode == "save" else "Spiel laden"
	_name_row.visible = mode == "save"
	_name_reason.text = ""
	_status.text = ""
	if mode == "save":
		_name_edit.text = _suggest_name()
	refresh()


func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	_rows.clear()
	var saves := SaveManager.list_saves()
	if saves.is_empty():
		var empty := Label.new()
		empty.text = "Noch keine Spielstände."
		empty.add_theme_color_override("font_color", COLOR_INFO)
		_list.add_child(empty)
	for entry in saves:
		_add_row(entry)


## Rauchtest: Name eintragen
func set_name_text(t: String) -> void:
	_name_edit.text = t


## Rauchtest: [{slot, name, compatible}] in Anzeigereihenfolge
func get_rows() -> Array:
	var out: Array = []
	for entry in _rows:
		out.append({"slot": entry["slot"], "name": str((entry["header"] as Dictionary).get("name", entry["slot"])),
				"compatible": str(entry["reason"]).is_empty()})
	return out


## Ist gerade eine Rückfrage offen?
func has_pending() -> bool:
	return _pending_action.is_valid()


func press_save() -> void:
	if game == null:
		return
	var text := _name_edit.text.strip_edges()
	if text.is_empty():
		_name_reason.text = "Bitte einen Namen eingeben."
		return
	if text.length() > SaveManager.MAX_NAME_LENGTH:
		_name_reason.text = "Der Name ist zu lang (höchstens %d Zeichen)." % SaveManager.MAX_NAME_LENGTH
		return
	var reason: String = game.can_save()
	if not reason.is_empty():
		_name_reason.text = reason
		return
	_name_reason.text = ""
	var slot := SaveManager.slot_for_name(text)
	if SaveManager.exists(slot):
		_ask("Spielstand „%s“ überschreiben?" % text, "Überschreiben", _do_save.bind(slot, text))
	else:
		_do_save(slot, text)


func press_load(slot: String) -> void:
	var entry := _find(slot)
	var target := slot
	if not entry.is_empty() and not str(entry["reason"]).is_empty():
		if str(entry["backup_path"]).is_empty() or str(entry["error"]).is_empty():
			return
		target = str(entry["backup_path"])
	if game != null and game.has_method("seconds_since_save") \
			and float(game.seconds_since_save()) > float(DataDB.cfg("save.unsaved_warning_seconds", 60)):
		_ask("Nicht gespeicherter Fortschritt geht verloren. Laden?", "Laden", _emit_load.bind(target))
	else:
		_emit_load(target)


func press_delete(slot: String) -> void:
	var entry := _find(slot)
	var shown := str((entry.get("header", {}) as Dictionary).get("name", slot)) if not entry.is_empty() else slot
	_ask("Spielstand „%s“ wirklich löschen?" % shown, "Löschen", _do_delete.bind(slot))


## Bestätigt eine offene Rückfrage (Knopf und Rauchtest)
func confirm_pending() -> void:
	var action := _pending_action
	_pending_action = Callable()
	if _confirm.visible:
		_confirm.hide()
	if action.is_valid():
		action.call()


func _ask(text: String, ok_text: String, action: Callable) -> void:
	_pending_action = action
	_confirm.dialog_text = text
	_confirm.ok_button_text = ok_text
	_confirm.popup_centered()


func _emit_load(slot: String) -> void:
	load_requested.emit(slot)


func _do_save(slot: String, text: String) -> void:
	_status.text = "Speichere …"
	_status.add_theme_color_override("font_color", COLOR_INFO)
	var err: String = game.save_game(slot, text, "manual", async_save)
	if not err.is_empty():
		_status.text = "Speichern fehlgeschlagen: " + err
		_status.add_theme_color_override("font_color", COLOR_REASON)


func _do_delete(slot: String) -> void:
	SaveManager.delete_save(slot)
	refresh()


func _on_saves_changed() -> void:
	if is_visible_in_tree():
		refresh()


func _on_save_finished(_slot: String, ok: bool, message: String) -> void:
	if not is_visible_in_tree():
		return
	_status.text = "Gespeichert." if ok else "Speichern fehlgeschlagen: " + message
	_status.add_theme_color_override("font_color", COLOR_INFO if ok else COLOR_REASON)
	if not ok:
		Notify.danger("Speichern fehlgeschlagen: " + message)


func _find(slot: String) -> Dictionary:
	for entry in _rows:
		if entry["slot"] == slot:
			return entry
	return {}


## Vorschlag: zuletzt benutzter Name, sonst "<Fraktion/Volk> Tag <n>"
func _suggest_name() -> String:
	if not GameSession.last_save_name.is_empty():
		return GameSession.last_save_name
	var who := DataDB.get_people_name(GameSession.people_id) if not GameSession.people_id.is_empty() \
			else str(GameSession.get_faction().get("name", "Spiel"))
	return "%s Tag %d" % [who, GameClock.get_day()]


func _add_row(entry: Dictionary) -> void:
	_rows.append(entry)
	var h: Dictionary = entry["header"]
	var slot := str(entry["slot"])
	var ok := str(entry["reason"]).is_empty()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = "Doppelklick: %s" % ("laden" if mode == "load" else "Namen übernehmen")
	panel.gui_input.connect(_on_row_input.bind(slot))
	var row := HBoxContainer.new()
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := _label(str(h.get("name", slot)), 18, Color.WHITE if ok else Color(0.6, 0.6, 0.6))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	top.add_child(_label(str(KIND_NAMES.get(str(h.get("kind", "manual")), "")), 14, COLOR_INFO))
	info.add_child(top)
	if not h.is_empty():
		var played := int(float(h.get("play_seconds", 0.0)))
		info.add_child(_label("%s · %s gespielt" % [str(h.get("time_text", "")).replace("  ", " "),
				_duration(played)], 14, COLOR_INFO))
		var parts: PackedStringArray = [str(h.get("faction_name", ""))]
		if not str(h.get("people_name", "")).is_empty():
			parts.append(str(h["people_name"]))
		parts.append(str(h.get("difficulty_name", "")))
		parts.append(str(h.get("map_size_name", "")).get_slice(" (", 0))
		parts.append("Seed %s" % str(h.get("seed_text", "")))
		info.add_child(_label(" · ".join(parts), 14, COLOR_INFO))
		info.add_child(_label("gespeichert %s · %d KB" % [SaveGame.format_date(int(h.get("saved_at", 0))),
				maxi(roundi(float(entry["bytes"]) / 1024.0), 1)], 13, COLOR_INFO))
	if not ok:
		info.add_child(_label(str(entry["reason"]), 14, COLOR_REASON))
	elif bool(entry["data_changed"]):
		var hint := _label("Spieldaten wurden seit dem Speichern geändert – Werte können abweichen", 13, COLOR_HINT)
		hint.tooltip_text = "Die Dateien in data/ sind anders als beim Speichern."
		info.add_child(hint)
	var buttons := VBoxContainer.new()
	row.add_child(buttons)
	if mode == "load":
		var load_button := Button.new()
		load_button.text = "Laden"
		load_button.tooltip_text = "Diesen Spielstand laden"
		load_button.disabled = not ok
		if not ok and not str(entry["error"]).is_empty() and not str(entry["backup_path"]).is_empty():
			load_button.text = "Sicherung laden"
			load_button.tooltip_text = "Die Datei ist defekt – die vorige Fassung (.bak) laden"
			load_button.disabled = false
		load_button.pressed.connect(press_load.bind(slot))
		buttons.add_child(load_button)
	var del := Button.new()
	del.text = "Löschen"
	del.tooltip_text = "Diesen Spielstand löschen (mit Rückfrage)"
	del.pressed.connect(press_delete.bind(slot))
	buttons.add_child(del)
	_list.add_child(panel)


func _on_row_input(event: InputEvent, slot: String) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mode == "save":
		var entry := _find(slot)
		if not entry.is_empty():
			_name_edit.text = str((entry["header"] as Dictionary).get("name", slot))
	elif mb.double_click:
		press_load(slot)


static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## "3 h 12 min" bzw. "12 min"
static func _duration(seconds: int) -> String:
	@warning_ignore("integer_division")
	var h := seconds / 3600
	@warning_ignore("integer_division")
	var m := (seconds % 3600) / 60
	return "%d h %d min" % [h, m] if h > 0 else "%d min" % m
