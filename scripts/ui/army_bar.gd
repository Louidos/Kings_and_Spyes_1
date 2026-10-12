## ArmyBar
##
## Armeeleiste unten links (zwischen Auswahlfenster und Infobereich): ein
## kleiner Button je gespeicherter Armee des Spielers, "1 · 12" (Nummer ·
## lebende Einheiten). Klick wählt die Armee aus, ein zweiter Klick innerhalb
## von 0.35 s springt zusätzlich mit der Kamera hin. Die Armee, die genau der
## Auswahl entspricht, bleibt eingedrückt. Ohne Armeen ist die Leiste aus.
## Aktualisiert wird gedrosselt (höchstens alle 0.25 s) bei Änderungen der
## Armeen und wenn Einheiten verschwinden – nie in jedem Bild.
class_name ArmyBar
extends PanelContainer

const REFRESH_INTERVAL := 0.25
const DOUBLE_CLICK_MS := 350
const FONT_SIZE := 15
const MAX_ARMIES := 9

var game: Node

var _flow: HFlowContainer
## Armee-Nummer (1–9) -> Button
var _buttons: Dictionary = {}
## Armee-Nummer -> Array der uids beim letzten Aufbau (für die Hervorhebung)
var _army_uids: Dictionary = {}
var _dirty := true
var _since_refresh := 0.0
var _last_click_army := 0
var _last_click_ms := -100000


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# Schlanker als die anderen Fenster: weniger Innenabstand
	var base := get_theme_stylebox("panel", "PanelContainer")
	if base != null:
		var style := base.duplicate() as StyleBox
		style.content_margin_top = 5.0
		style.content_margin_bottom = 5.0
		style.content_margin_left = 10.0
		style.content_margin_right = 10.0
		add_theme_stylebox_override("panel", style)
	_flow = HFlowContainer.new()
	_flow.add_theme_constant_override("h_separation", 5)
	_flow.add_theme_constant_override("v_separation", 5)
	add_child(_flow)
	var title := Label.new()
	title.text = "Armeen"
	title.add_theme_font_size_override("font_size", FONT_SIZE)
	title.add_theme_color_override("font_color", SelectionPanel.COLOR_TITLE)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_vertical = Control.SIZE_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow.add_child(title)


func setup(p_game: Node) -> void:
	game = p_game
	game.command_system.armies_changed.connect(_on_armies_changed)
	game.unit_system.unit_removed.connect(_on_unit_removed)
	game.selection.selection_changed.connect(_on_selection_changed)
	_refresh()


func _process(delta: float) -> void:
	if game == null:
		return
	_since_refresh += delta
	if _dirty and _since_refresh >= REFRESH_INTERVAL:
		_refresh()


func _on_armies_changed(k: Kingdom) -> void:
	if k == game.player:
		_dirty = true


func _on_unit_removed(u: Unit) -> void:
	# Nur eigene Einheiten können in Armeen stehen
	if u.kingdom == game.player and not _buttons.is_empty():
		_dirty = true


func _on_selection_changed(_objs: Array) -> void:
	_update_pressed()


func _refresh() -> void:
	_dirty = false
	_since_refresh = 0.0
	var k: Kingdom = game.player
	if k == null:
		return
	_army_uids.clear()
	var any := false
	for n in range(1, MAX_ARMIES + 1):
		var units: Array = game.command_system.get_army(k, n) if k.armies.has(n) else []
		var button: Button = _buttons.get(n)
		if units.is_empty():
			if button != null:
				button.visible = false
			continue
		any = true
		if button == null:
			button = _make_button(n)
			_buttons[n] = button
		button.visible = true
		var text := "%d · %d" % [n, units.size()]
		if button.text != text:
			button.text = text
		var tip := _tooltip(n, units)
		if button.tooltip_text != tip:
			button.tooltip_text = tip
		var uids: Array = []
		for u in units:
			uids.append((u as Unit).uid)
		_army_uids[n] = uids
	visible = any
	_update_pressed()


## Eingedrückt: die Armee, deren Einheiten genau ausgewählt sind
func _update_pressed() -> void:
	if _buttons.is_empty():
		return
	var selected := {}
	for u in game.selection.get_own_units():
		selected[(u as Unit).uid] = true
	for n in _buttons:
		var button: Button = _buttons[n]
		var uids: Array = _army_uids.get(n, [])
		var match_all := not uids.is_empty() and uids.size() == selected.size()
		if match_all:
			for uid in uids:
				if not selected.has(uid):
					match_all = false
					break
		if button.button_pressed != match_all:
			button.set_pressed_no_signal(match_all)


func _tooltip(n: int, units: Array) -> String:
	var counts := {}
	for u in units:
		var unit_name: String = (u as Unit).get_display_name()
		counts[unit_name] = int(counts.get(unit_name, 0)) + 1
	var names: Array = counts.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool: return int(counts[a]) > int(counts[b]))
	var lines: PackedStringArray = ["Armee %d – %d Einheiten" % [n, units.size()]]
	for unit_name in names:
		lines.append("%d× %s" % [int(counts[unit_name]), str(unit_name)])
	lines.append("")
	lines.append("Klick oder Taste %d: auswählen · zweimal: hinspringen" % n)
	lines.append("Strg+%d: neu speichern · Umschalt+%d: hinzufügen" % [n, n])
	return "\n".join(lines)


func _make_button(n: int) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	# Kein Tastaturfokus, sonst würde die Leertaste (Pause) den Button auslösen
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.custom_minimum_size = Vector2(56, 0)
	for style_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var base := get_theme_stylebox(style_name, "Button")
		if base == null:
			continue
		var style := base.duplicate() as StyleBox
		style.content_margin_left = 8.0
		style.content_margin_right = 8.0
		style.content_margin_top = 2.0
		style.content_margin_bottom = 2.0
		b.add_theme_stylebox_override(style_name, style)
	b.pressed.connect(_on_army_pressed.bind(n))
	# Nach Nummer sortiert einfügen (der Titel steht an Stelle 0)
	var index := 1
	for other in _buttons:
		if int(other) < n:
			index += 1
	_flow.add_child(b)
	_flow.move_child(b, index)
	return b


func _on_army_pressed(n: int) -> void:
	var now := Time.get_ticks_msec()
	var again := n == _last_click_army and now - _last_click_ms <= DOUBLE_CLICK_MS
	_last_click_army = n
	_last_click_ms = now
	game.selection.select_army(n)
	if again:
		game.selection.center_on_selection()
	_update_pressed()
