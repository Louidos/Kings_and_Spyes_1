## SpellBar
##
## Zauberleiste unten rechts über der Minikarte: ein Knopf je Zauber der
## eigenen Fraktion (auch noch nicht erforschte – so sieht man, was es gibt),
## darunter die Manakosten, oben das Mana des Reichs.
## Klick auf einen bekannten, bereiten Zauber startet den Zielmodus
## (SpellTargeting), ein zweiter Klick bricht ihn ab.
## Wird von SpellTargeting angelegt (eigene CanvasLayer wie das HUD), damit
## das HUD-Skript nicht angefasst werden muss.
## Aktualisiert alle 0.25 s sowie bei Mana-, Forschungs- und Zielmodus-Änderungen.
class_name SpellBar
extends PanelContainer

const REFRESH_INTERVAL := 0.25
const DIRTY_INTERVAL := 0.1
## Abstand über der Minikarte
const GAP := 8.0
## Lage, falls die Minikarte nicht gefunden wird (rechts, unten)
const FALLBACK_MARGIN := Vector2(12.0, 292.0)
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.74, 0.71, 0.66)
const COLOR_BAD := Color(1.0, 0.45, 0.38)
const COLOR_MANA := Color(0.78, 0.7, 1.0)
const ACCENT_GOOD := Color("#f3d36b")
const ACCENT_EVIL := Color("#8e44ad")
const SCHOOL_NAMES := {"combat": "Kampf", "healing": "Heilung", "stealth": "Tarnung",
	"weather": "Wetter", "summon": "Beschwörung"}
const STAT_NAMES := {"attack": "Angriff", "armor": "Rüstung", "speed": "Tempo",
	"aggro_range": "Wahrnehmung", "regen": "Erholung", "range": "Reichweite"}
## Grund von can_cast, der nur vom Ort abhängt (in der Leiste ohne Bedeutung)
const RANGE_REASON_PREFIX := "Nur im eigenen Gebiet"

var game: Node

var _accent := ACCENT_GOOD
var _buttons: Array[SpellButton] = []
var _cost_labels: Array[Label] = []
var _mana_label: Label
var _timer := 0.0
var _dirty := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func setup(p_game: Node) -> void:
	game = p_game
	var k: Kingdom = game.player
	_accent = ACCENT_EVIL if k.faction_id == "evil" else ACCENT_GOOD
	_build(k)
	k.resources_changed.connect(_on_resources_changed)
	game.research_system.research_completed.connect(_on_research_completed)
	game.spell_targeting.targeting_changed.connect(_on_targeting_changed)
	get_viewport().size_changed.connect(_place)
	visible = true
	_refresh()
	_place()
	# Die Minikarte steht erst nach dem ersten Layout sicher an ihrem Platz
	_place.call_deferred()


func _build(k: Kingdom) -> void:
	var style := get_theme_stylebox("panel", "PanelContainer")
	if style is StyleBoxFlat:
		var own := (style as StyleBoxFlat).duplicate() as StyleBoxFlat
		own.border_color = Color(_accent, 0.8)
		own.content_margin_left = 10.0
		own.content_margin_right = 10.0
		own.content_margin_top = 6.0
		own.content_margin_bottom = 6.0
		add_theme_stylebox_override("panel", own)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	# Kopfzeile: Titel links, Mana rechts
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(head)
	var title := _make_label(head, 15, _accent.lightened(0.3) if k.faction_id == "evil" else _accent)
	title.text = "Zauber des Königs"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mana_icon := ResourceIcon.new()
	mana_icon.setup("mana", 16.0)
	head.add_child(mana_icon)
	_mana_label = _make_label(head, 15, COLOR_MANA)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row)
	for s in game.magic_system.get_spells(k):
		var def: Dictionary = s
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(slot)
		var button := SpellButton.new()
		button.setup(def)
		var id := str(def.get("id", ""))
		button.tip_source = _tooltip.bind(id)
		button.pressed.connect(_on_spell_pressed.bind(id))
		button.gui_input.connect(_on_button_gui_input)
		slot.add_child(button)
		var cost := _make_label(slot, 15, COLOR_MANA)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost.text = str(ceili(float(def.get("mana_cost", 0.0))))
		_buttons.append(button)
		_cost_labels.append(cost)


func _process(delta: float) -> void:
	if game == null:
		return
	# Mit dem HUD ein- und ausblenden (Ladebildschirm)
	var hud_visible: bool = game.hud.visible
	if visible != hud_visible:
		visible = hud_visible
	if not visible:
		return
	_timer += delta
	if (_dirty and _timer >= DIRTY_INTERVAL) or _timer >= REFRESH_INTERVAL:
		_refresh()


## Rechts über der Minikarte, rechte Kante bündig mit ihr
func _place() -> void:
	if game == null:
		return
	var vp := get_viewport_rect().size
	var margin := FALLBACK_MARGIN
	var mm: Variant = game.hud.get("minimap")
	if is_instance_valid(mm) and mm is Control:
		var panel := (mm as Control).get_parent() as Control
		if panel != null and panel.size.y > 0.0:
			var r := panel.get_global_rect()
			margin = Vector2(maxf(vp.x - r.end.x, 0.0), maxf(vp.y - r.position.y, 0.0) + GAP)
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -margin.x
	offset_bottom = -margin.y
	offset_left = offset_right
	offset_top = offset_bottom
	reset_size()


func _refresh() -> void:
	_timer = 0.0
	_dirty = false
	var k: Kingdom = game.player
	var ms: MagicSystem = game.magic_system
	var mana := k.get_amount("mana")
	# Nicht begrenzen: nach Erstattungen kann Mana über dem Maximum liegen
	_set_label(_mana_label, "%d/%d" % [floori(mana), roundi(k.get_capacity("mana"))], COLOR_MANA)
	var active_id: String = game.spell_targeting.spell_id
	for i in _buttons.size():
		var button := _buttons[i]
		var def := DataDB.get_spell(button.spell_id)
		var known := ms.is_known(k, button.spell_id)
		var cd := ms.cooldown_left(k, button.spell_id)
		var total := maxf(float(def.get("cooldown", 1.0)), 0.01)
		var cost := float(def.get("mana_cost", 0.0))
		var no_mana := mana + 0.0001 < cost
		button.set_state(known, cd / total, ceili(cd), no_mana, active_id == button.spell_id)
		var cost_color := COLOR_DIM
		if known:
			cost_color = COLOR_BAD if no_mana else COLOR_MANA
		_set_label(_cost_labels[i], str(ceili(cost)), cost_color)


## Grund, der nicht vom Ort abhängt ("" = bereit): unbekannt, Abklingzeit, Mana
func get_ready_reason(spell_id: String) -> String:
	var k: Kingdom = game.player
	var ms: MagicSystem = game.magic_system
	var def := DataDB.get_spell(spell_id)
	if not ms.is_known(k, spell_id):
		var r := DataDB.find_research_unlocking(k.faction_id, str(def.get("requires", "")))
		return "Noch nicht erforscht: %s (R)" % str(r.get("name", "?"))
	# Ein Ort, der sicher in Reichweite liegt: die Burg (sonst der König)
	var anchor := Vector2.ZERO
	if is_instance_valid(k.castle):
		anchor = k.castle.get_center()
	elif is_instance_valid(k.king):
		anchor = k.king.position
	var reason := ms.can_cast(k, spell_id, anchor)
	return "" if reason.begins_with(RANGE_REASON_PREFIX) else reason


func _on_spell_pressed(spell_id: String) -> void:
	var st: SpellTargeting = game.spell_targeting
	if st.spell_id == spell_id:
		st.cancel()
		return
	var reason := get_ready_reason(spell_id)
	if not reason.is_empty():
		Notify.warning("%s: %s" % [str(DataDB.get_spell(spell_id).get("name", "")), reason])
		_refresh()
		return
	st.start(spell_id)


## Rechtsklick auf die Leiste bricht den Zielmodus ab (wie in der Welt)
func _on_button_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and game.spell_targeting.is_active():
		game.spell_targeting.cancel()
		accept_event()


func _on_resources_changed() -> void:
	_dirty = true


func _on_research_completed(k: Kingdom, _id: String) -> void:
	if k == game.player:
		_dirty = true


func _on_targeting_changed(_spell_id: String) -> void:
	_refresh()


# ---------------------------------------------------------------------------
# Tooltip (BBCode, wird erst beim Zeigen gebaut)
# ---------------------------------------------------------------------------

func _tooltip(spell_id: String) -> String:
	var k: Kingdom = game.player
	var def := DataDB.get_spell(spell_id)
	var lines: PackedStringArray = []
	lines.append("[b][color=%s]%s[/color][/b]" % [SpellButton.text_color_html(def.get("color", Color.WHITE)),
			str(def.get("name", spell_id))])
	lines.append("[color=#%s]%s[/color]" % [COLOR_DIM.to_html(false),
			str(SCHOOL_NAMES.get(str(def.get("school", "")), "Zauber"))])
	lines.append(SpellButton.wrap_text(str(def.get("description", ""))))
	var effect := _effect_text(def)
	if not effect.is_empty():
		lines.append("[color=#%s]%s[/color]" % [COLOR_MANA.lightened(0.2).to_html(false), SpellButton.wrap_text(effect)])
	lines.append("")
	var cost := float(def.get("mana_cost", 0.0))
	var mana_text := "Mana: %d" % ceili(cost)
	if k.get_amount("mana") + 0.0001 < cost:
		mana_text = "Mana: [color=#%s]%d[/color] (du hast %d)" % [COLOR_BAD.to_html(false), ceili(cost), floori(k.get_amount("mana"))]
	var upkeep := float(def.get("upkeep", 0.0))
	if upkeep > 0.0:
		mana_text += ", laufend %s/s" % ResourceBar.format_number(upkeep)
	lines.append(mana_text)
	lines.append("Abklingzeit: %d s" % ceili(float(def.get("cooldown", 0.0))))
	var radius := float(def.get("radius", 0.0))
	lines.append("Wirkungskreis: %s %s" % [ResourceBar.format_number(radius), "Feld" if is_equal_approx(radius, 1.0) else "Felder"])
	var duration := float(def.get("duration", 0.0))
	if duration > 0.0:
		lines.append("Dauer: %s%d s" % ["höchstens " if bool(def.get("stealth", false)) else "", ceili(duration)])
	var reason := get_ready_reason(spell_id)
	lines.append("")
	if reason.is_empty():
		var hint := "Abbrechen: Rechtsklick oder Esc" if game.spell_targeting.spell_id == spell_id \
				else "Klick: Ziel wählen (im eigenen Gebiet oder bis %d Felder davor)" % int(DataDB.mag("settings.cast_range_outside", 8))
		lines.append("[color=#%s]%s[/color]" % [COLOR_DIM.to_html(false), SpellButton.wrap_text(hint)])
	else:
		lines.append("[color=#%s]%s[/color]" % [COLOR_BAD.to_html(false), SpellButton.wrap_text(reason)])
	return "\n".join(lines)


## Wirkung in Zahlen: "+25 % Angriff, +15 % Rüstung" usw.
func _effect_text(def: Dictionary) -> String:
	var own: PackedStringArray = []
	var enemy: PackedStringArray = []
	var parts: PackedStringArray = []
	var heal := float(def.get("heal_instant", 0.0))
	if heal > 0.0:
		parts.append("heilt sofort %d Leben" % roundi(heal))
	var effect_list: Array = def.get("effects", [])
	var zone: Dictionary = def.get("zone", {})
	effect_list = effect_list + (zone.get("effects", []) as Array)
	for e in effect_list:
		var eff: Dictionary = e
		var key := str(eff.get("key", ""))
		var text := ""
		if key == "heal_over_time":
			text = "danach %s Leben/s" % ResourceBar.format_number(float(eff.get("add", 0.0)))
			parts.append(text)
			continue
		var stat := str(STAT_NAMES.get(key, key))
		if eff.has("mult"):
			text = "%s %s" % [_percent(float(eff["mult"]) - 1.0), stat]
		elif eff.has("add"):
			text = "%s %s" % [_percent(float(eff["add"])), stat]
		if text.is_empty():
			continue
		if str(eff.get("side", "own")) == "enemy":
			enemy.append(text)
		else:
			own.append(text)
	if not own.is_empty():
		parts.append("Eigene: " + ", ".join(own))
	if not enemy.is_empty():
		parts.append("Feinde: " + ", ".join(enemy))
	var production := float(zone.get("production", 1.0))
	if production != 1.0:
		var names: PackedStringArray = []
		for r in zone.get("resources", []):
			names.append(str(DataDB.get_resource(str(r)).get("name", r)))
		parts.append("%s Ertrag (%s)" % [_percent(production - 1.0), ", ".join(names)])
	var summon: Dictionary = def.get("summon", {})
	if not summon.is_empty():
		var unit_def := DataDB.get_unit_type(str(summon.get("unit", "")))
		parts.append("%d× %s" % [int(summon.get("count", 1)), str(unit_def.get("name", "?"))])
	if bool(def.get("stealth", false)):
		parts.append("unsichtbar bis zum ersten Angriff")
	if parts.is_empty():
		return ""
	# Erster Buchstabe gross
	var text := ", ".join(parts)
	return text.left(1).to_upper() + text.substr(1)


## "+25 %" bzw. "−40 %"
static func _percent(v: float) -> String:
	var p := roundi(v * 100.0)
	return ("+%d %%" % p) if p >= 0 else ("−%d %%" % -p)


func _make_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _set_label(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)
