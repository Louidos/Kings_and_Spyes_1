## MessageLogPanel
##
## Meldungsprotokoll (Taste M, Knopf über den Meldungen): alle Meldungen der Partie,
## neueste zuerst, mit Spielzeit und in der Farbe ihrer Art. Filter Alle/Gefahr/
## Warnung/Info/Gut. Ein Klick verhält sich wie bei den Meldungen oben rechts
## (Stelle anspringen bzw. Fenster öffnen). Das Protokoll wird gespeichert (Notify.history).
class_name MessageLogPanel
extends CanvasLayer

signal toggled(open: bool)

const LAYER := 12
const FILTERS := [["", "Alle"], ["danger", "Gefahr"], ["warning", "Warnung"], ["info", "Info"], ["good", "Gut"]]

var game: Node
var _root: Control
var _list: VBoxContainer
var _filter := ""
var _count_label: Label


func setup(p_game: Node) -> void:
	game = p_game


func _ready() -> void:
	layer = LAYER
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
	panel.custom_minimum_size = Vector2(760, 620)
	center.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(UiStyle.make_title_bar("Meldungsprotokoll", close))
	var filters := HBoxContainer.new()
	var group := ButtonGroup.new()
	for f in FILTERS:
		var b := Button.new()
		b.text = str(f[1])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = str(f[0]) == _filter
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Nur Meldungen dieser Art zeigen" if not str(f[0]).is_empty() else "Alle Meldungen zeigen"
		b.pressed.connect(set_filter.bind(str(f[0])))
		filters.add_child(b)
	_count_label = Label.new()
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	filters.add_child(_count_label)
	box.add_child(filters)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	Notify.history_changed.connect(_on_history_changed)
	UiStyle.register_scaled_layer(self, _root)


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	refresh()
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


## Filter setzen ("" = alle; sonst eine Art)
func set_filter(kind: String) -> void:
	_filter = kind
	refresh()


## Anzahl der angezeigten Einträge (Rauchtest)
func get_shown_count() -> int:
	return _list.get_child_count()


func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var shown := 0
	for i in range(Notify.history.size() - 1, -1, -1):
		var e: Dictionary = Notify.history[i]
		if not _filter.is_empty() and str(e.get("kind", "info")) != _filter:
			continue
		var color: Color = NotificationPanel.KIND_COLORS.get(str(e.get("kind", "info")), Color.WHITE)
		var b := Button.new()
		b.text = "%s   %s" % [str(e.get("time_text", "")).replace("  ", " "), str(e.get("text", ""))]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(state, color)
		var pos: Variant = e.get("pos", null)
		b.tooltip_text = "Klicken: zur Stelle springen" if pos is Vector2 else ("Klicken: Fenster öffnen" if pos is Dictionary else "Meldung")
		b.pressed.connect(_on_entry_pressed.bind(pos))
		_list.add_child(b)
		shown += 1
	_count_label.text = "%d Meldungen" % shown


func _on_entry_pressed(pos: Variant) -> void:
	if pos == null:
		return
	NotificationPanel.open_target(game, pos)


func _on_history_changed() -> void:
	if visible:
		refresh()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("game_menu"):
		close()
		get_viewport().set_input_as_handled()
