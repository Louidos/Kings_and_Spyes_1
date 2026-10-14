## HeroBar
##
## Heldenleiste unten links (direkt über dem Infobereich, unter der Armeeleiste):
## ein Porträtknopf je Held des Spielers – Porträt (Platzhalter aus Assets) mit
## Stufe, Name, Lebensbalken bzw. bei gefallenen Helden grau mit Restzeit oder
## "Wiederbeleben". Goldene Markierung bei offener Stufenwahl.
## - Klick: Held auswählen (zweiter Klick innerhalb von 0.35 s: Kamera hin)
## - gefallener Held: Klick belebt wieder, wenn es geht (Burg, Kosten), sonst
##   kommt der Grund als Meldung
## - Rechtsklick: Heldenfenster bei diesem Helden
## Die Lage hängt nicht von der Höhe des Auswahlfensters ab (der Infobereich
## darunter ist gleich hoch), Doppelklicks treffen also denselben Knopf.
## Ohne Helden ist die Leiste aus. Aktualisiert wird gedrosselt (0.25 s) – bei
## Änderungen sofort, sonst für Leben und Restzeit alle 0.5 s.
class_name HeroBar
extends PanelContainer

const REFRESH_INTERVAL := 0.25
## Leben und Restzeit ändern sich laufend: so oft ohne Signal nachführen
const IDLE_REFRESH := 0.5
const DOUBLE_CLICK_MS := 350
const BUTTON_WIDTH := 128.0
const BUTTON_HEIGHT := 50.0
const PORTRAIT_SIZE := 40.0


## Knopf eines Helden: Tooltip entsteht erst beim Zeigen
class HeroButton:
	extends Button
	var bar: HeroBar
	var hero_id := 0
	var portrait: HeroPortrait
	var name_label: Label
	var info_label: Label
	var hp_bar: HpBar

	func _get_tooltip(_at_position: Vector2) -> String:
		return bar.tooltip_for(hero_id) if is_instance_valid(bar) else ""


var game: Node

var _flow: HFlowContainer
## hero_id -> HeroButton
var _buttons: Dictionary = {}
var _ids: Array = []
var _dirty := true
var _since_refresh := 0.0
var _last_click_id := 0
var _last_click_ms := -100000


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var base := get_theme_stylebox("panel", "PanelContainer")
	if base != null:
		var style := base.duplicate() as StyleBox
		style.content_margin_top = 5.0
		style.content_margin_bottom = 5.0
		style.content_margin_left = 8.0
		style.content_margin_right = 8.0
		add_theme_stylebox_override("panel", style)
	_flow = HFlowContainer.new()
	_flow.add_theme_constant_override("h_separation", 5)
	_flow.add_theme_constant_override("v_separation", 5)
	_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flow)


func setup(p_game: Node) -> void:
	game = p_game
	game.hero_system.heroes_changed.connect(_on_heroes_changed)
	game.hero_system.xp_gained.connect(_on_xp_gained)
	game.selection.selection_changed.connect(_on_selection_changed)
	_refresh()


func _process(delta: float) -> void:
	if game == null:
		return
	_since_refresh += delta
	if (_dirty and _since_refresh >= REFRESH_INTERVAL) or (visible and _since_refresh >= IDLE_REFRESH):
		_refresh()


func _on_heroes_changed(k: Kingdom) -> void:
	if k == game.player:
		_dirty = true


func _on_xp_gained(k: Kingdom, _hero_id: int, _amount: int, _reason: String) -> void:
	if k == game.player:
		_dirty = true


func _on_selection_changed(_objs: Array) -> void:
	_update_pressed()


func _refresh() -> void:
	_dirty = false
	_since_refresh = 0.0
	var k: Kingdom = game.player
	if k == null:
		return
	var hs: HeroSystem = game.hero_system
	var ids: Array = []
	for rec in hs.get_heroes(k):
		ids.append(int(rec["id"]))
	if ids != _ids:
		_rebuild(ids)
	visible = not ids.is_empty()
	for hid in ids:
		_refresh_button(k, _buttons[hid] as HeroButton)
	_update_pressed()


func _rebuild(ids: Array) -> void:
	_ids = ids.duplicate()
	for child in _flow.get_children():
		_flow.remove_child(child)
		child.queue_free()
	_buttons.clear()
	for hid in ids:
		_buttons[hid] = _make_button(int(hid))


func _refresh_button(k: Kingdom, b: HeroButton) -> void:
	var hs: HeroSystem = game.hero_system
	var rec := hs.get_record(k, b.hero_id)
	if rec.is_empty():
		return
	var dead := bool(rec["dead"])
	var pending := int(rec["pending"]) > 0
	b.portrait.set_state(dead, int(rec["level"]), pending)
	_set_label(b.name_label, str(rec["name"]), HeroUI.COLOR_DEAD if dead else SelectionPanel.COLOR_TITLE)
	var u := hs.get_unit(k, b.hero_id)
	var info := ""
	var info_color := SelectionPanel.COLOR_DIM
	if dead:
		var wait := hs.revive_ready_in(rec)
		if wait > 0.0:
			info = "in %d s" % ceili(wait)
		else:
			info = "Wiederbeleben"
			info_color = HeroUI.COLOR_GOOD if hs.can_revive(k, b.hero_id).is_empty() else HeroUI.COLOR_WARN
	elif pending:
		info = "Stufenwahl!"
		info_color = HeroUI.COLOR_PENDING
	else:
		info = "Stufe %d" % int(rec["level"])
	_set_label(b.info_label, info, info_color)
	b.hp_bar.visible = u != null
	if u != null:
		b.hp_bar.set_value(u.hp, u.max_hp, " ")


## Eingedrückt: ausgewählte Helden
func _update_pressed() -> void:
	for hid in _buttons:
		var b: HeroButton = _buttons[hid]
		var u := HeroUI.hero_unit(game, int(hid))
		var on := u != null and u.selected
		if b.button_pressed != on:
			b.set_pressed_no_signal(on)


## Tooltip: Name, Typ, Stufe, Zustand und Bedienung
func tooltip_for(hero_id: int) -> String:
	if game == null:
		return ""
	var hs: HeroSystem = game.hero_system
	var k: Kingdom = game.player
	var rec := hs.get_record(k, hero_id)
	if rec.is_empty():
		return ""
	var lines: PackedStringArray = ["%s – Stufe %d" % [hs.get_title(rec), int(rec["level"])]]
	lines.append(HeroUI.xp_text(hs, rec))
	var state := HeroUI.state_text(hs, rec, hs.get_unit(k, hero_id))
	if not state.is_empty():
		lines.append(state)
	if int(rec["pending"]) > 0:
		lines.append("Stufenwahl offen – Rechtsklick oder G: Heldenfenster")
	lines.append("")
	if bool(rec["dead"]):
		lines.append("Wiederbeleben: %s" % DataDB.cost_to_text(hs.revive_cost(rec)))
		var reason := hs.can_revive(k, hero_id)
		lines.append("Klick: wiederbeleben" if reason.is_empty() else reason)
	else:
		lines.append("Klick: auswählen · zweimal: hinspringen")
	lines.append("Rechtsklick: Heldenfenster")
	return "\n".join(lines)


func _make_button(hero_id: int) -> HeroButton:
	var hs: HeroSystem = game.hero_system
	var rec := hs.get_record(game.player, hero_id)
	var b := HeroButton.new()
	b.bar = self
	b.hero_id = hero_id
	b.toggle_mode = true
	# Kein Tastaturfokus, sonst würde die Leertaste (Pause) den Button auslösen
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	for style_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var base := get_theme_stylebox(style_name, "Button")
		if base == null:
			continue
		var style := base.duplicate() as StyleBox
		style.content_margin_left = 4.0
		style.content_margin_right = 4.0
		style.content_margin_top = 2.0
		style.content_margin_bottom = 2.0
		b.add_theme_stylebox_override(style_name, style)
	b.pressed.connect(_on_hero_pressed.bind(hero_id))
	b.gui_input.connect(_on_button_gui_input.bind(hero_id))
	_flow.add_child(b)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 5.0
	row.offset_top = 5.0
	row.offset_right = -6.0
	row.offset_bottom = -5.0
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	b.portrait = HeroPortrait.new()
	b.portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	b.portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.portrait.setup(hs.get_type(rec))
	row.add_child(b.portrait)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	b.name_label = _make_label(texts, 14)
	b.info_label = _make_label(texts, 13)
	b.hp_bar = HpBar.new()
	b.hp_bar.custom_minimum_size = Vector2(0, 6)
	b.hp_bar.font_size = 1
	texts.add_child(b.hp_bar)
	return b


func _make_label(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _set_label(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _on_hero_pressed(hero_id: int) -> void:
	var hs: HeroSystem = game.hero_system
	var k: Kingdom = game.player
	var rec := hs.get_record(k, hero_id)
	if rec.is_empty():
		return
	if bool(rec["dead"]):
		var reason := hs.can_revive(k, hero_id)
		if reason.is_empty():
			hs.revive(k, hero_id)
		else:
			Notify.warning("%s: %s" % [str(rec["name"]), reason])
		_refresh()
		return
	var u := hs.get_unit(k, hero_id)
	if u == null:
		return
	var now := Time.get_ticks_msec()
	var again := hero_id == _last_click_id and now - _last_click_ms <= DOUBLE_CLICK_MS
	_last_click_id = hero_id
	_last_click_ms = now
	game.selection.select([u])
	if again:
		game.camera.focus_on(u.position)
	_update_pressed()


## Rechtsklick: Heldenfenster bei diesem Helden
func _on_button_gui_input(event: InputEvent, hero_id: int) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		var hud: Node = game.hud
		if hud.has_method("open_heroes"):
			hud.call("open_heroes", HeroPanel.TAB_HEROES, hero_id)
