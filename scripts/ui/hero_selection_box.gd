## HeroSelectionBox
##
## Helden-Abschnitt im Auswahlfenster (SelectionPanel), steht über den Befehlen:
## - Held ausgewählt (allein oder in einer gemischten Auswahl/Armee – dann der
##   aktive Held, Tab wechselt): Typ bzw. Name und Stufe, Erfahrungsbalken,
##   Knopf "Stufenwahl" bei offener Wahl und die drei Fähigkeitsknöpfe (C / V / B)
##   mit Abklingzeit, Rang und goldenem Rahmen für "selbst auslösen"
##   (Rechtsklick schaltet um). Fähigkeiten mit Ziel starten den Zielmodus.
## - Burg: je gefallenem Helden "Wiederbeleben: <Name>" (Restzeit, Kosten im Tooltip)
## - Heldenhalle: je lebendem Helden "Ausbilden: <Name>" und "Heldenfenster öffnen (G)"
##   (Anwerben läuft über die Beschwören-Knöpfe darüber).
## Wird vom Auswahlfenster bei jeder Aktualisierung (alle 0.25 s) gefüllt; die
## Knöpfe werden nur neu gebaut, wenn sich Heldentyp bzw. Heldenliste ändern.
class_name HeroSelectionBox
extends VBoxContainer

const FONT_SIZE := 16
const SMALL_FONT_SIZE := 15
const ABILITY_BUTTON_SIZE := 50.0

var game: Node

## "hero", "castle", "hall" oder ""
var _mode := ""
var _hero_uid := 0
var _hero_id := 0
var _building: Object = null

var _hero_part: VBoxContainer
var _level_label: Label
var _xp_bar: HpBar
var _choice_button: Button
var _ability_row: HBoxContainer
var _ability_buttons: Array[AbilityButton] = []
var _hint: Label
## Heldentyp, für den die Fähigkeitsknöpfe gebaut sind
var _shown_type := ""

var _building_part: VBoxContainer
var _building_title: Label
var _rows: VBoxContainer
## Je Zeile: {"hero_id", "button": ResearchTipButton, "info": Label}
var _row_entries: Array = []
var _rows_key := ""
var _window_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_hero_part = VBoxContainer.new()
	_hero_part.add_theme_constant_override("separation", 4)
	_hero_part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero_part)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_part.add_child(top)
	_level_label = _label(top, FONT_SIZE, SelectionPanel.COLOR_TITLE)
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_bar = HpBar.new()
	_xp_bar.fill_color = HeroUI.COLOR_XP
	_xp_bar.custom_minimum_size = Vector2(0, 20)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_xp_bar)
	_choice_button = Button.new()
	_choice_button.text = "Stufenwahl!"
	_choice_button.focus_mode = Control.FOCUS_NONE
	_choice_button.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_choice_button.add_theme_color_override("font_color", HeroUI.COLOR_PENDING)
	_choice_button.add_theme_color_override("font_hover_color", HeroUI.COLOR_PENDING.lightened(0.3))
	_choice_button.tooltip_text = "Eine Verbesserung wählen (Heldenfenster, G)"
	_choice_button.pressed.connect(_on_choice_pressed)
	top.add_child(_choice_button)

	_ability_row = HBoxContainer.new()
	_ability_row.add_theme_constant_override("separation", 6)
	_ability_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_part.add_child(_ability_row)
	_hint = _label(_ability_row, SMALL_FONT_SIZE - 1, SelectionPanel.COLOR_GREY)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_building_part = VBoxContainer.new()
	_building_part.add_theme_constant_override("separation", 4)
	_building_part.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_building_part)
	_building_title = _label(_building_part, SMALL_FONT_SIZE, SelectionPanel.COLOR_TITLE)
	_building_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_building_part.add_child(_rows)
	_window_button = Button.new()
	_window_button.text = "Heldenfenster öffnen (G)"
	_window_button.focus_mode = Control.FOCUS_NONE
	_window_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_window_button.tooltip_text = "Alle Helden: Stufenwahl, Ausbildung, Wiederbelebung, Anwerben"
	_window_button.pressed.connect(_on_window_pressed)
	_building_part.add_child(_window_button)


func setup(p_game: Node) -> void:
	game = p_game


## Nichts anzeigen
func hide_box() -> void:
	_mode = ""
	_hero_uid = 0
	_building = null
	visible = false


## Held u (eigener, lebender) – multi: Teil einer grösseren Auswahl
func show_hero(u: Unit, multi: bool) -> void:
	var hs: HeroSystem = game.hero_system
	var rec := hs.find_record(u) if u != null else {}
	if rec.is_empty():
		hide_box()
		return
	_mode = "hero"
	_hero_uid = u.uid
	_hero_id = int(rec["id"])
	_building = null
	visible = true
	_hero_part.visible = true
	_building_part.visible = false
	var htype := hs.get_type(rec)
	var who := str(rec["name"]) if multi else str(htype.get("name", ""))
	_set_text(_level_label, "%s · Stufe %d" % [who, int(rec["level"])])
	var need := hs.xp_for_next(rec)
	if need > 0:
		_xp_bar.set_value(float(rec["xp"]), float(need), HeroUI.xp_text(hs, rec))
	else:
		_xp_bar.set_value(1.0, 1.0, HeroUI.xp_text(hs, rec))
	var pending := int(rec["pending"])
	_choice_button.visible = pending > 0
	if pending > 1:
		_set_button_text(_choice_button, "Stufenwahl (%d)!" % pending)
	else:
		_set_button_text(_choice_button, "Stufenwahl!")
	_ensure_ability_buttons(str(rec["type_id"]))
	var st: SpellTargeting = game.spell_targeting
	for b in _ability_buttons:
		var aid := b.ability_id
		var rank := hs.get_rank(rec, aid)
		var passive := HeroUI.is_passive(aid)
		var cd := hs.cooldown_left(rec, aid)
		var total := maxf(float(hs.get_ability_values(rec, aid).get("cooldown", 0.0)), 0.01)
		var castable := rank > 0 and not passive and HeroUI.is_ready_reason(hs.can_use(u, aid))
		b.set_state(rank > 0, cd / total, ceili(cd), false, st.is_ability_targeting(u.uid, aid), castable)
		b.set_extra(rank, hs.is_autocast(rec, aid))
	var heroes: Array = game.selection.get_selected_heroes()
	var hint := "C V B: wirken\nRechtsklick: selbst auslösen"
	if heroes.size() > 1:
		hint = "C V B: wirken · Tab: anderer\nHeld (%d von %d)" % [heroes.find(u) + 1, heroes.size()]
	_set_text(_hint, hint)


## Burg (gefallene Helden wiederbeleben) bzw. Heldenhalle (Ausbildung); sonst aus
func show_building(b: Building) -> void:
	var k: Kingdom = game.player
	if b == null or b.kingdom != k or not b.constructed:
		hide_box()
		return
	var hs: HeroSystem = game.hero_system
	var ids: Array = []
	var mode := ""
	if b == k.castle:
		mode = "castle"
		for rec in hs.get_heroes(k):
			if bool(rec["dead"]):
				ids.append(int(rec["id"]))
		if ids.is_empty():
			hide_box()
			return
	elif bool(b.def.get("hero_hall", false)):
		mode = "hall"
		for rec in hs.get_heroes(k):
			if not bool(rec["dead"]):
				ids.append(int(rec["id"]))
	else:
		hide_box()
		return
	_mode = mode
	_building = b
	_hero_uid = 0
	visible = true
	_hero_part.visible = false
	_building_part.visible = true
	var key := "%s:%s" % [mode, str(ids)]
	if key != _rows_key:
		_rows_key = key
		_build_rows(ids)
	if mode == "castle":
		_set_text(_building_title, "Gefallene Helden")
	elif ids.is_empty():
		_set_text(_building_title, "Ausbildung: noch keine Helden – oben anwerben")
	else:
		_set_text(_building_title, "Ausbildung: +%d EP für %s" % [int(DataDB.hero_cfg("training.xp", 80)),
				DataDB.cost_to_text(DataDB.hero_cfg("training.cost", {}))])
	for e in _row_entries:
		_refresh_row(e as Dictionary)


# ---------------------------------------------------------------------------
# Fähigkeiten
# ---------------------------------------------------------------------------

func _ensure_ability_buttons(type_id: String) -> void:
	if type_id == _shown_type:
		return
	_shown_type = type_id
	for b in _ability_buttons:
		_ability_row.remove_child(b)
		b.queue_free()
	_ability_buttons.clear()
	var abilities: Array = DataDB.get_hero_type(type_id).get("abilities", [])
	for i in abilities.size():
		var aid := str(abilities[i])
		var b := AbilityButton.new()
		b.custom_minimum_size = Vector2(ABILITY_BUTTON_SIZE, ABILITY_BUTTON_SIZE)
		b.setup_ability(DataDB.get_ability(aid), str(HeroUI.ABILITY_KEYS[i]) if i < HeroUI.ABILITY_KEYS.size() else "")
		b.tip_source = _ability_tip.bind(aid, i)
		b.pressed.connect(_on_ability_pressed.bind(aid))
		b.autocast_requested.connect(_on_autocast_requested)
		_ability_row.add_child(b)
		_ability_row.move_child(b, i)
		_ability_buttons.append(b)


func _hero_unit() -> Unit:
	var u: Variant = game.find_by_uid(_hero_uid)
	if is_instance_valid(u) and u is Unit and (u as Unit).is_alive():
		return u
	return null


func _ability_tip(ability_id: String, index: int) -> String:
	var u := _hero_unit()
	if u == null:
		return ""
	var key := str(HeroUI.ABILITY_KEYS[index]) if index < HeroUI.ABILITY_KEYS.size() else ""
	return HeroUI.ability_tip(game.hero_system, game.hero_system.find_record(u), ability_id, u, key)


func _on_ability_pressed(ability_id: String) -> void:
	var u := _hero_unit()
	if u == null:
		return
	if HeroUI.is_passive(ability_id):
		Notify.info("%s wirkt von selbst (passiv)" % str(DataDB.get_ability(ability_id).get("name", "")))
		return
	game.spell_targeting.start_ability(u, ability_id)


## Rechtsklick: "selbst auslösen" umschalten
func _on_autocast_requested(ability_id: String) -> void:
	var u := _hero_unit()
	if u == null:
		return
	toggle_autocast(game, u, ability_id)
	show_hero(u, game.selection.get_selected_heroes().size() > 1 or game.selection.selected.size() > 1)


## "Selbst auslösen" einer Fähigkeit umschalten (mit Meldung, wenn es nicht geht)
static func toggle_autocast(p_game: Node, u: Unit, ability_id: String) -> void:
	var hs: HeroSystem = p_game.hero_system
	var rec := hs.find_record(u)
	if rec.is_empty():
		return
	var ability_name := str(DataDB.get_ability(ability_id).get("name", ability_id))
	if not HeroUI.can_autocast(ability_id):
		Notify.info("%s kann nicht selbst auslösen" % ability_name)
		return
	if hs.get_rank(rec, ability_id) <= 0:
		Notify.info("%s: noch nicht gelernt" % ability_name)
		return
	var on := not hs.is_autocast(rec, ability_id)
	hs.set_autocast(u.kingdom, int(rec["id"]), ability_id, on)
	Notify.info("%s: selbst auslösen %s" % [ability_name, "an" if on else "aus"])


func _on_choice_pressed() -> void:
	_open_window(_hero_id)


# ---------------------------------------------------------------------------
# Burg und Heldenhalle
# ---------------------------------------------------------------------------

func _build_rows(ids: Array) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_row_entries.clear()
	for hid in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(row)
		var button := ResearchTipButton.new()
		button.add_theme_font_size_override("font_size", FONT_SIZE)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.tip_source = _row_tip.bind(int(hid))
		button.pressed.connect(_on_row_pressed.bind(int(hid)))
		row.add_child(button)
		var info := _label(row, SMALL_FONT_SIZE, SelectionPanel.COLOR_DIM)
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		info.custom_minimum_size = Vector2(86, 0)
		_row_entries.append({"hero_id": int(hid), "button": button, "info": info})
	_window_button.visible = true


func _refresh_row(e: Dictionary) -> void:
	var hs: HeroSystem = game.hero_system
	var k: Kingdom = game.player
	var hid := int(e["hero_id"])
	var rec := hs.get_record(k, hid)
	if rec.is_empty():
		return
	var button: ResearchTipButton = e["button"]
	var info: Label = e["info"]
	var reason := ""
	var info_text := ""
	if _mode == "castle":
		_set_button_text(button, "Wiederbeleben: %s" % str(rec["name"]))
		reason = hs.can_revive(k, hid)
		var wait := hs.revive_ready_in(rec)
		info_text = "noch %d s" % ceili(wait) if wait > 0.0 else ("bereit" if reason.is_empty() else "fehlt etwas")
	else:
		_set_button_text(button, "Ausbilden: %s (Stufe %d)" % [str(rec["name"]), int(rec["level"])])
		reason = hs.can_train(k, hid)
		var wait := float(rec["train_ready_at"]) - GameClock.game_time
		if int(rec["level"]) >= hs.train_cap(k):
			info_text = "nur im Kampf"
		elif wait > 0.0:
			info_text = "noch %d s" % ceili(wait)
		else:
			info_text = "bereit" if reason.is_empty() else "fehlt etwas"
	var ok := reason.is_empty()
	if button.disabled == ok:
		button.disabled = not ok
	_set_text(info, info_text)
	_set_color(info, SelectionPanel.COLOR_DIM if not ok else HeroUI.COLOR_GOOD)


func _row_tip(hero_id: int) -> String:
	var hs: HeroSystem = game.hero_system
	var k: Kingdom = game.player
	var rec := hs.get_record(k, hero_id)
	if rec.is_empty():
		return ""
	var tip := ResearchTipButton
	var lines: PackedStringArray = []
	if _mode == "castle":
		lines.append("[b]%s[/b] wiederbeleben (Stufe %d)" % [tip.esc(hs.get_title(rec)), int(rec["level"])])
		lines.append("Kosten: " + HeroUI.cost_bbcode(k, hs.revive_cost(rec)))
		lines.append("Erscheint an der Burg mit vollem Leben und kehrt in seine Armee zurück.")
		var reason := hs.can_revive(k, hero_id)
		if not reason.is_empty():
			lines.append(tip.colored(reason, HeroUI.COLOR_BAD))
	else:
		lines.append("[b]%s[/b] ausbilden: +%d EP" % [tip.esc(hs.get_title(rec)), int(DataDB.hero_cfg("training.xp", 80))])
		lines.append("Kosten: " + HeroUI.cost_bbcode(k, DataDB.hero_cfg("training.cost", {})))
		lines.append("Ausbildung bis Stufe %d, danach nur noch im Kampf (Heldenlehre: höher)." % hs.train_cap(k))
		var reason := hs.can_train(k, hero_id)
		if not reason.is_empty():
			lines.append(tip.colored(reason, HeroUI.COLOR_BAD))
	return "\n".join(lines)


func _on_row_pressed(hero_id: int) -> void:
	var hs: HeroSystem = game.hero_system
	var k: Kingdom = game.player
	if _mode == "castle":
		if not hs.revive(k, hero_id):
			Notify.warning(hs.can_revive(k, hero_id))
	elif _mode == "hall":
		var rec := hs.get_record(k, hero_id)
		if hs.train(k, hero_id):
			Notify.good("Ausbildung: %s erhält Erfahrung" % str(rec.get("name", "")))
		else:
			Notify.warning(hs.can_train(k, hero_id))
	_rows_key = ""
	if is_instance_valid(_building) and _building is Building:
		show_building(_building as Building)


func _on_window_pressed() -> void:
	_open_window(0)


func _open_window(hero_id: int) -> void:
	var hud: Node = game.hud
	if hud.has_method("open_heroes"):
		hud.call("open_heroes", HeroPanel.TAB_HEROES, hero_id)


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


func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
	label.visible = not text.is_empty()


func _set_color(label: Label, color: Color) -> void:
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _set_button_text(b: Button, text: String) -> void:
	if b.text != text:
		b.text = text
