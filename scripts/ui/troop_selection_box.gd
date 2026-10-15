## TroopSelectionBox
##
## Truppen-Abschnitt im Auswahlfenster (SelectionPanel), steht über den Befehlen:
## - eine eigene Truppe: Rang mit Winkeln und Erfahrungsbalken, freie Wertepunkte und je
##   ein Knopf für Angriff, Leben, Rüstung und Tempo, der Reichsschalter "automatisch
##   verteilen" und das Aussehen (für alle dieses Typs und für diese Einheit).
##   Helden: nur die Wertepunkte (einer je Stufe). Im Debug-Modus (F3) "+50 EP (Test)".
## - eine fremde Truppe: nur der Rang.
## - mehrere eigene Einheiten: freie Punkte, "Punkte automatisch verteilen", der
##   Reichsschalter und – bei nur einem Einheitentyp – das Aussehen dieses Typs.
## - eigene, fertige Schmiede: je Truppenklasse die Knöpfe "Waffen" und "Rüstung"
##   (Stufe x/3, Kosten und Wirkung im Tooltip, Klick kauft die nächste Stufe).
## Alles ruft nur die Schnittstelle des TroopSystem auf. Wird vom Auswahlfenster bei
## jeder Aktualisierung (alle 0.25 s) gefüllt; Listen werden nur bei Änderungen neu gebaut.
class_name TroopSelectionBox
extends VBoxContainer

const FONT_SIZE := 15
const SMALL_FONT_SIZE := 14
const DEBUG_XP := 50.0
const KIND_NAMES := {"weapon": "Waffen", "armor": "Rüstung"}

var game: Node

## "unit", "foreign", "units", "forge" oder ""
var _mode := ""
var _unit: Unit = null
var _units: Array = []

var _unit_part: VBoxContainer
var _rank_row: HBoxContainer
var _rank_label: Label
var _xp_bar: HpBar
var _debug_button: Button
var _points_row: HBoxContainer
var _points_label: Label
var _auto_button: Button
var _auto_check: CheckBox
var _stat_row: HBoxContainer
## Wert-ID -> Button
var _stat_buttons: Dictionary = {}
var _skin_row: HBoxContainer
var _type_skin: OptionButton
var _unit_skin: OptionButton
var _type_skin_ids: Array = []
var _unit_skin_ids: Array = []
## Typ bzw. Einheit, für die die Listen gebaut sind
var _skin_key := ""

var _forge_part: VBoxContainer
var _forge_title: Label
var _forge_rows: VBoxContainer
## Verbesserungs-ID -> Button
var _forge_buttons: Dictionary = {}
var _forge_built := false


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_unit_part = VBoxContainer.new()
	_unit_part.add_theme_constant_override("separation", 4)
	_unit_part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_unit_part)

	_rank_row = HBoxContainer.new()
	_rank_row.add_theme_constant_override("separation", 8)
	_rank_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unit_part.add_child(_rank_row)
	_rank_label = _label(_rank_row, FONT_SIZE, SelectionPanel.COLOR_TITLE)
	_rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_bar = HpBar.new()
	_xp_bar.fill_color = Color(0.85, 0.7, 0.3)
	_xp_bar.custom_minimum_size = Vector2(0, 18)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rank_row.add_child(_xp_bar)
	_debug_button = _button(_rank_row, "+%d EP (Test)" % roundi(DEBUG_XP), SMALL_FONT_SIZE - 1)
	_debug_button.tooltip_text = "Debug (F3): dieser Einheit %d Erfahrung geben" % roundi(DEBUG_XP)
	_debug_button.pressed.connect(_on_debug_pressed)

	_points_row = HBoxContainer.new()
	_points_row.add_theme_constant_override("separation", 6)
	_points_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unit_part.add_child(_points_row)
	_points_label = _label(_points_row, SMALL_FONT_SIZE, SelectionPanel.COLOR_DIM)
	_points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_auto_button = _button(_points_row, "Punkte automatisch verteilen", SMALL_FONT_SIZE)
	_auto_button.tooltip_text = "Alle freien Wertepunkte der ausgewählten Einheiten nach ihrer Klasse verteilen"
	_auto_button.pressed.connect(press_auto)
	_auto_check = CheckBox.new()
	_auto_check.text = "automatisch"
	_auto_check.focus_mode = Control.FOCUS_NONE
	_auto_check.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_auto_check.tooltip_text = "Für das ganze Reich: neue Wertepunkte beim Aufstieg sofort automatisch verteilen\n(Reihenfolge je Klasse, z. B. Fusstruppen zuerst Leben und Rüstung)"
	_auto_check.toggled.connect(_on_auto_toggled)
	_points_row.add_child(_auto_check)

	_stat_row = HBoxContainer.new()
	_stat_row.add_theme_constant_override("separation", 4)
	_stat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unit_part.add_child(_stat_row)
	for stat_id in TroopRules.STAT_IDS:
		var b := _button(_stat_row, TroopRules.stat_name(stat_id), SMALL_FONT_SIZE)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(press_stat.bind(stat_id))
		_stat_buttons[stat_id] = b

	_skin_row = HBoxContainer.new()
	_skin_row.add_theme_constant_override("separation", 6)
	_skin_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unit_part.add_child(_skin_row)
	var skin_label := _label(_skin_row, SMALL_FONT_SIZE, SelectionPanel.COLOR_DIM)
	skin_label.text = "Aussehen:"
	skin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_type_skin = _option(_skin_row)
	_type_skin.item_selected.connect(_on_type_skin_selected)
	_unit_skin = _option(_skin_row)
	_unit_skin.item_selected.connect(_on_unit_skin_selected)

	_forge_part = VBoxContainer.new()
	_forge_part.add_theme_constant_override("separation", 4)
	_forge_part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_forge_part)
	_forge_title = _label(_forge_part, FONT_SIZE, SelectionPanel.COLOR_TITLE)
	_forge_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forge_rows = VBoxContainer.new()
	_forge_rows.add_theme_constant_override("separation", 3)
	_forge_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forge_part.add_child(_forge_rows)


func setup(p_game: Node) -> void:
	game = p_game


## Nichts anzeigen
func hide_box() -> void:
	_mode = ""
	_unit = null
	_units = []
	visible = false


## Was gerade gezeigt wird ("unit", "foreign", "units", "forge" oder "")
func get_mode() -> String:
	return _mode


# ---------------------------------------------------------------------------
# Einheiten
# ---------------------------------------------------------------------------

## Eine Einheit (own: eigene – mit Knöpfen; fremde nur mit Rang)
func show_unit(u: Unit, own: bool) -> void:
	var ts: TroopSystem = game.troop_system
	if u == null or not is_instance_valid(u) or not ts.has_stat_points(u):
		hide_box()
		return
	if not own:
		if u.vet_rank <= 0:
			hide_box()
			return
		_mode = "foreign"
		_unit = u
		visible = true
		_unit_part.visible = true
		_forge_part.visible = false
		_rank_row.visible = true
		_set_text(_rank_label, "Rang: %s" % TroopRules.rank_name(u.vet_rank))
		_xp_bar.visible = false
		_debug_button.visible = false
		_points_row.visible = false
		_stat_row.visible = false
		_skin_row.visible = false
		return
	_mode = "unit"
	_unit = u
	_units = []
	visible = true
	_unit_part.visible = true
	_forge_part.visible = false
	var hero := u.hero_id != 0
	_rank_row.visible = not hero
	if not hero:
		_set_text(_rank_label, "%s (Rang %d/%d)" % [TroopRules.rank_name(u.vet_rank), u.vet_rank, TroopRules.max_rank()])
		_xp_bar.visible = true
		_xp_bar.set_value(ts.rank_progress(u), 1.0, ts.xp_text(u))
		_debug_button.visible = _debug_on()
	var free := ts.get_free_points(u)
	_points_row.visible = true
	_set_text(_points_label, "Wertepunkte: %d frei" % free if free > 0 else "Wertepunkte: keine frei")
	_auto_button.visible = false
	_sync_auto_check(u.kingdom)
	_stat_row.visible = true
	for stat_id in TroopRules.STAT_IDS:
		var b: Button = _stat_buttons[stat_id]
		var n := int(u.stat_alloc.get(stat_id, 0))
		_set_button_text(b, "%s +" % TroopRules.stat_name(stat_id) if n == 0 else "%s %d +" % [TroopRules.stat_name(stat_id), n])
		var reason := ts.can_spend_point(u, stat_id)
		b.disabled = not reason.is_empty()
		var tip := "Wertepunkt auf %s: %s je Punkt (verteilt: %d von höchstens %d)" % [TroopRules.stat_name(stat_id),
				TroopRules.stat_effect_text(stat_id), n, TroopRules.max_per_stat()]
		if not reason.is_empty():
			tip += "\n" + reason
		if b.tooltip_text != tip:
			b.tooltip_text = tip
	_show_skins(u.kingdom, u.type_def, u)


## Mehrere eigene Einheiten: freie Punkte, automatisch verteilen, Aussehen bei einem Typ
func show_units(units: Array) -> void:
	var ts: TroopSystem = game.troop_system
	var eligible: Array = []
	var type_id := ""
	var one_type := true
	for o in units:
		var u: Unit = o
		if not ts.has_stat_points(u):
			continue
		eligible.append(u)
		if type_id.is_empty():
			type_id = u.type_id
		elif type_id != u.type_id:
			one_type = false
	if eligible.is_empty():
		hide_box()
		return
	_mode = "units"
	_unit = null
	_units = eligible
	visible = true
	_unit_part.visible = true
	_forge_part.visible = false
	_rank_row.visible = false
	_stat_row.visible = false
	var free := ts.free_points_of(eligible)
	_points_row.visible = true
	_set_text(_points_label, "Wertepunkte: %d frei" % free)
	_auto_button.visible = true
	_auto_button.disabled = free <= 0
	_sync_auto_check((eligible[0] as Unit).kingdom)
	var def := DataDB.get_unit_type(type_id)
	if one_type and TroopRules.has_skins(def):
		_show_skins((eligible[0] as Unit).kingdom, def, null)
	else:
		_skin_row.visible = false


func _sync_auto_check(k: Kingdom) -> void:
	if _auto_check.button_pressed != k.auto_stat_points:
		_auto_check.set_pressed_no_signal(k.auto_stat_points)


## Auswahllisten des Aussehens: Typ (immer) und Einheit (nur bei einer Einheit)
func _show_skins(k: Kingdom, def: Dictionary, u: Unit) -> void:
	var type_ids := TroopRules.skins_for(k, def)
	if type_ids.size() <= 1:
		_skin_row.visible = false
		return
	_skin_row.visible = true
	var ts: TroopSystem = game.troop_system
	var type_id := str(def.get("id", ""))
	var unit_ids: Array = []
	if u != null:
		unit_ids = [""]
		unit_ids.append_array(TroopRules.skins_for(k, def, u.vet_rank))
	var key := "%s|%s|%s" % [type_id, str(type_ids), str(unit_ids)]
	if key != _skin_key and not _type_skin.get_popup().visible and not _unit_skin.get_popup().visible:
		_skin_key = key
		_type_skin_ids = type_ids
		_unit_skin_ids = unit_ids
		_type_skin.clear()
		for sid in type_ids:
			_type_skin.add_item("Alle: %s" % TroopRules.skin_name(str(sid)))
		_unit_skin.clear()
		for sid in unit_ids:
			_unit_skin.add_item("Diese: wie alle" if str(sid).is_empty() else "Diese: %s" % TroopRules.skin_name(str(sid)))
	var plural := str(def.get("name", type_id))
	_type_skin.tooltip_text = "Aussehen aller %s des Reichs (rein kosmetisch; eigene Grafik: %s)" % [plural,
			TroopRules.skin_sprite(type_id, "<skin>").get_file()]
	var current := _type_skin_ids.find(ts.get_type_skin(k, type_id))
	if current >= 0 and _type_skin.selected != current:
		_type_skin.select(current)
	_unit_skin.visible = u != null
	if u != null:
		_unit_skin.tooltip_text = "Eigenes Aussehen nur dieser Einheit („Heldenbanner“ ab dem Rang %s)" % TroopRules.rank_name(
				int(TroopRules.skin_def("hero_banner").get("min_rank", 3)))
		var own_idx := _unit_skin_ids.find(u.skin)
		if own_idx < 0:
			own_idx = 0
		if _unit_skin.selected != own_idx:
			_unit_skin.select(own_idx)


## Wertepunkt auf einen Wert (einzelne Einheit)
func press_stat(stat_id: String) -> bool:
	if _mode != "unit" or not is_instance_valid(_unit):
		return false
	var ts: TroopSystem = game.troop_system
	if not ts.spend_point(_unit, stat_id):
		var reason := ts.can_spend_point(_unit, stat_id)
		if not reason.is_empty():
			Notify.warning(reason)
		return false
	show_unit(_unit, true)
	return true


## Mehrfachauswahl: alle freien Punkte verteilen
func press_auto() -> int:
	var n := 0
	if _mode == "units":
		n = game.troop_system.auto_distribute_units(_units)
	elif _mode == "unit" and is_instance_valid(_unit):
		n = game.troop_system.auto_distribute(_unit)
	if n > 0:
		Notify.good("%d Wertepunkte verteilt" % n)
	return n


func _on_auto_toggled(on: bool) -> void:
	var k: Kingdom = game.player
	game.troop_system.set_auto_points(k, on)


## Aussehen des Typs wählen (Skin-ID)
func select_type_skin(skin_id: String) -> bool:
	var u: Unit = null
	if _mode == "unit":
		u = _unit
	elif _mode == "units" and not _units.is_empty():
		u = _units[0]
	if u == null or not is_instance_valid(u):
		return false
	return game.troop_system.set_type_skin(u.kingdom, u.type_id, skin_id)


## Eigenes Aussehen der angezeigten Einheit wählen ("" = wie alle)
func select_unit_skin(skin_id: String) -> bool:
	if _mode != "unit" or not is_instance_valid(_unit):
		return false
	return game.troop_system.set_unit_skin(_unit, skin_id)


func _on_type_skin_selected(index: int) -> void:
	if index >= 0 and index < _type_skin_ids.size():
		select_type_skin(str(_type_skin_ids[index]))


func _on_unit_skin_selected(index: int) -> void:
	if index >= 0 and index < _unit_skin_ids.size():
		select_unit_skin(str(_unit_skin_ids[index]))


func _on_debug_pressed() -> void:
	if _mode == "unit" and is_instance_valid(_unit):
		game.troop_system.debug_add_xp(_unit, DEBUG_XP)


func _debug_on() -> bool:
	var hud: Node = game.get("hud")
	return hud != null and hud.has_method("is_debug_visible") and bool(hud.call("is_debug_visible"))


# ---------------------------------------------------------------------------
# Schmiede
# ---------------------------------------------------------------------------

## Eigene, fertige Schmiede: Stufen je Klasse; sonst aus
func show_building(b: Building) -> void:
	if b == null or not is_instance_valid(b) or b.kingdom != game.player or not b.constructed \
			or not bool(b.def.get("forge", false)):
		hide_box()
		return
	_mode = "forge"
	_unit = null
	_units = []
	visible = true
	_unit_part.visible = false
	_forge_part.visible = true
	_ensure_forge_rows()
	_set_text(_forge_title, "Waffen und Rüstung je Truppenklasse – Klick kauft die nächste Stufe")
	var k: Kingdom = b.kingdom
	var ts: TroopSystem = game.troop_system
	for id in _forge_buttons:
		var button: Button = _forge_buttons[id]
		var up := DataDB.get_forge_upgrade(str(id))
		var level := ts.get_forge_level(k, str(id))
		var max_level := int(up.get("max_level", 0))
		_set_button_text(button, "%s %d/%d" % [str(KIND_NAMES.get(str(up.get("kind", "")), "Stufe")), level, max_level])
		var reason := ts.can_buy_forge(k, str(id))
		var ok := reason.is_empty()
		if button.disabled == ok:
			button.disabled = not ok
		var tip := forge_tip(k, str(id))
		if button.tooltip_text != tip:
			button.tooltip_text = tip


## Tooltip einer Schmiede-Verbesserung: Name, jetzige Wirkung, nächste Stufe, Kosten, Grund
func forge_tip(k: Kingdom, upgrade_id: String) -> String:
	var ts: TroopSystem = game.troop_system
	var up := DataDB.get_forge_upgrade(upgrade_id)
	var level := ts.get_forge_level(k, upgrade_id)
	var max_level := int(up.get("max_level", 0))
	var lines: PackedStringArray = []
	lines.append("%s – %s" % [ts.upgrade_name(k, up), str(up.get("name", ""))])
	lines.append("Stufe %d von %d%s" % [level, max_level, (": " + ts.forge_effect_text(up, level)) if level > 0 else ""])
	if level < max_level:
		lines.append("Nächste Stufe: %s" % ts.forge_effect_text(up, level + 1))
		lines.append("Kosten: %s" % DataDB.cost_to_text(ts.get_forge_cost(k, upgrade_id)))
	var reason := ts.can_buy_forge(k, upgrade_id)
	if not reason.is_empty() and level < max_level:
		lines.append(reason)
	return "\n".join(lines)


## Eine Stufe kaufen (Klick)
func press_forge(upgrade_id: String) -> bool:
	var k: Kingdom = game.player
	var ts: TroopSystem = game.troop_system
	if ts.buy_forge(k, upgrade_id):
		return true
	var reason := ts.can_buy_forge(k, upgrade_id)
	if not reason.is_empty():
		Notify.warning(reason.get_slice("\n", 0))
	return false


## Eine Zeile je Truppenklasse (Reihenfolge der Daten), darin Waffen- und Rüstungsknopf
func _ensure_forge_rows() -> void:
	if _forge_built:
		return
	_forge_built = true
	var rows := {}
	for up in game.troop_system.get_forge_upgrades():
		var cid := str(up.get("class", ""))
		if not rows.has(cid):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_forge_rows.add_child(row)
			var name_label := _label(row, SMALL_FONT_SIZE, SelectionPanel.COLOR_TEXT)
			name_label.text = DataDB.get_class_name(cid)
			name_label.custom_minimum_size = Vector2(120, 0)
			name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			rows[cid] = row
		var b := _button(rows[cid] as HBoxContainer, "", SMALL_FONT_SIZE)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(press_forge.bind(str(up.get("id", ""))))
		_forge_buttons[str(up.get("id", ""))] = b


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

func _label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	parent.add_child(b)
	return b


func _option(parent: Control) -> OptionButton:
	var o := OptionButton.new()
	# Kein Tastaturfokus, sonst würde die Leertaste (Pause) die Liste öffnen
	o.focus_mode = Control.FOCUS_NONE
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	o.fit_to_longest_item = false
	o.clip_text = true
	parent.add_child(o)
	return o


func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
	label.visible = not text.is_empty()


func _set_button_text(b: Button, text: String) -> void:
	if b.text != text:
		b.text = text
