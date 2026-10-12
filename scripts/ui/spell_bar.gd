## SpellBar
##
## Zauberleiste unten rechts über der Minikarte: ein Knopf je Zauber des
## Reichs (auch noch nicht erforschte – so sieht man, was es gibt), darunter
## die tatsächlichen Manakosten, oben der Titel und das Mana des Reichs.
## Zustand und Tooltip kommen aus MagicSystem.can_cast_now und get_cast_params
## (echte Werte nach Forschung, z. B. Manafokus).
## Klick auf einen bereiten Zauber startet den Zielmodus (SpellTargeting),
## ein zweiter Klick (oder Rechtsklick) bricht ihn ab.
## Wird von SpellTargeting angelegt (eigene CanvasLayer wie das HUD), damit
## das HUD-Skript nicht angefasst werden muss.
## Aktualisiert alle 0.25 s sowie bei Mana-, Forschungs- und Zielmodus-Änderungen.
class_name SpellBar
extends PanelContainer

const REFRESH_INTERVAL := 0.25
const DIRTY_INTERVAL := 0.1
## Abstand über der Minikarte
const GAP := 8.0
## Lage, falls die Minikarte nicht gefunden wird (Abstand rechts, unten)
const FALLBACK_MARGIN := Vector2(12.0, 292.0)
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.72, 0.7, 0.66)
const COLOR_BAD := Color(1.0, 0.45, 0.38)
const COLOR_MANA := Color(0.78, 0.7, 1.0)
const COLOR_EFFECT := Color(0.82, 0.9, 1.0)
const ACCENT_GOOD := Color("#f3d36b")
const ACCENT_EVIL := Color("#8e44ad")
const SCHOOL_NAMES := {"combat": "Kampf", "healing": "Heilung", "stealth": "Tarnung",
	"weather": "Wetter", "summon": "Beschwörung"}
const STAT_NAMES := {"attack": "Angriff", "armor": "Rüstung", "speed": "Tempo",
	"aggro_range": "Sichtweite", "regen": "Erholung", "range": "Reichweite", "hp": "Leben"}

var game: Node

var _accent := ACCENT_GOOD
var _row: HBoxContainer
var _buttons: Array[SpellButton] = []
var _cost_labels: Array[Label] = []
var _ids: PackedStringArray = []
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
	k.resources_changed.connect(_on_changed)
	# Forschung ändert Kosten und Abklingzeiten (Manafokus, Zauberfluss)
	k.modifiers_changed.connect(_on_changed)
	game.research_system.research_completed.connect(_on_research_completed)
	game.spell_targeting.targeting_changed.connect(_on_targeting_changed)
	get_viewport().size_changed.connect(_place)
	visible = game.hud.visible
	_refresh()
	_place()
	# Die Minikarte steht erst nach dem ersten Layout sicher an ihrem Platz
	_place.call_deferred()


func _build(k: Kingdom) -> void:
	var style := get_theme_stylebox("panel", "PanelContainer")
	if style is StyleBoxFlat:
		var own := (style as StyleBoxFlat).duplicate() as StyleBoxFlat
		own.border_color = Color(_accent, 0.85)
		own.set_border_width_all(maxi(own.border_width_top, 1))
		own.border_width_top = 2
		own.content_margin_left = 10.0
		own.content_margin_right = 10.0
		own.content_margin_top = 6.0
		own.content_margin_bottom = 4.0
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
	var title := _make_label(head, 14, _accent.lightened(0.35) if k.faction_id == "evil" else _accent)
	title.text = "Zauber des Königs"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mana_icon := ResourceIcon.new()
	mana_icon.setup("mana", 16.0)
	mana_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mana_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(mana_icon)
	_mana_label = _make_label(head, 15, COLOR_MANA)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_row)
	_build_buttons(k)


## Ein Knopf je Zauber (neu, wenn sich die Liste ändert – z. B. Bündnisse ab Phase 6)
func _build_buttons(k: Kingdom) -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_cost_labels.clear()
	_ids = _spell_ids(k)
	for id in _ids:
		var def := DataDB.get_spell(id)
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_child(slot)
		var button := SpellButton.new()
		button.setup(def)
		button.tip_source = _tooltip.bind(id)
		button.pressed.connect(_on_spell_pressed.bind(id))
		button.gui_input.connect(_on_button_gui_input)
		slot.add_child(button)
		var cost := _make_label(slot, 14, COLOR_MANA)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_buttons.append(button)
		_cost_labels.append(cost)


func _spell_ids(k: Kingdom) -> PackedStringArray:
	var ids := PackedStringArray()
	for s in game.magic_system.get_spells(k):
		var def: Dictionary = s
		ids.append(str(def.get("id", "")))
	return ids


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
		var id := button.spell_id
		var known := ms.is_known(k, id)
		var params := ms.get_cast_params(k, id)
		var cost := float(params["mana_cost"])
		var cd := ms.cooldown_left(k, id)
		var total := maxf(float(params["cooldown"]), 0.01)
		var no_mana := mana + 0.0001 < cost
		var ready := ms.can_cast_now(k, id).is_empty()
		button.set_state(known, cd / total, ceili(cd), no_mana, active_id == id, ready)
		var cost_color := COLOR_DIM
		if known:
			cost_color = COLOR_BAD if no_mana else COLOR_MANA
		_set_label(_cost_labels[i], str(ceili(cost - 0.001)), cost_color)


func _on_spell_pressed(spell_id: String) -> void:
	var st: SpellTargeting = game.spell_targeting
	if st.spell_id == spell_id:
		st.cancel()
		_refresh()
		return
	var k: Kingdom = game.player
	var spell_name := str(DataDB.get_spell(spell_id).get("name", ""))
	var reason: String = game.magic_system.can_cast_now(k, spell_id)
	if not reason.is_empty():
		if not game.magic_system.is_known(k, spell_id):
			reason = "Noch nicht erforscht – %s" % _research_hint(k, spell_id)
		Notify.warning("%s: %s" % [spell_name, reason])
		_refresh()
		return
	st.start(spell_id)


## Rechtsklick auf die Leiste bricht den Zielmodus ab (wie in der Welt)
func _on_button_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and game.spell_targeting.is_active():
		game.spell_targeting.cancel()
		accept_event()


func _on_changed() -> void:
	_dirty = true


func _on_research_completed(k: Kingdom, _id: String) -> void:
	if k != game.player:
		return
	if _spell_ids(k) != _ids:
		_build_buttons(k)
		reset_size()
		_place()
	_dirty = true


func _on_targeting_changed(_spell_id: String) -> void:
	_refresh()


# ---------------------------------------------------------------------------
# Tooltip (BBCode, wird erst beim Zeigen gebaut)
# ---------------------------------------------------------------------------

func _tooltip(spell_id: String) -> String:
	var k: Kingdom = game.player
	var ms: MagicSystem = game.magic_system
	var def := DataDB.get_spell(spell_id)
	var p := ms.get_cast_params(k, spell_id)
	var known := ms.is_known(k, spell_id)
	var lines: PackedStringArray = []
	lines.append("[b][color=%s]%s[/color][/b]   [color=#%s]%s[/color]" % [
			SpellButton.text_color_html(def.get("color", Color.WHITE)), str(def.get("name", spell_id)),
			COLOR_DIM.to_html(false), str(SCHOOL_NAMES.get(str(def.get("school", "")), "Zauber"))])
	lines.append(SpellButton.wrap_text(str(def.get("description", ""))))
	var effect := _effect_text(def, float(p["power"]))
	if not effect.is_empty():
		lines.append("[color=#%s]%s[/color]" % [COLOR_EFFECT.to_html(false), SpellButton.wrap_text(effect)])
	lines.append("")

	# Werte nach Forschung (Grundwert in Klammern, wenn er abweicht)
	var cost := float(p["mana_cost"])
	var mana := k.get_amount("mana")
	var mana_text := "Mana: %s" % _num(cost)
	if known and mana + 0.0001 < cost:
		mana_text = "Mana: [color=#%s]%s[/color] (du hast %d)" % [COLOR_BAD.to_html(false), _num(cost), floori(mana)]
	mana_text += _base_note(cost, float(def.get("mana_cost", 0.0)), "")
	var upkeep := float(p["upkeep"])
	if upkeep > 0.0:
		mana_text += ", laufend %s Mana/s je Zauber" % _num(upkeep)
	lines.append(mana_text)
	var cooldown := float(p["cooldown"])
	lines.append("Abklingzeit: %s s%s" % [_num(cooldown), _base_note(cooldown, float(def.get("cooldown", 0.0)), " s")])
	var radius := float(p["radius"])
	lines.append("Wirkungskreis: %s %s" % [_num(radius), "Feld" if is_equal_approx(radius, 1.0) else "Felder"])
	var duration := float(p["duration"])
	if duration < 0.0:
		lines.append("Dauer: bis zum Ende")
	elif duration > 0.0:
		var prefix := "höchstens " if bool(def.get("stealth", false)) else ""
		lines.append("Dauer: %s%s s" % [prefix, _num(duration)])
	lines.append("Reichweite: eigenes Gebiet und %d Felder davor" % int(p["range"]))

	# Zustand (unabhängig vom Zielort)
	lines.append("")
	var bad := "[color=#%s]%s[/color]"
	if not known:
		lines.append(bad % [COLOR_BAD.to_html(false), "Noch nicht erforscht"])
		lines.append(SpellButton.wrap_text(_research_hint(k, spell_id)))
	else:
		var reason := ms.can_cast_now(k, spell_id)
		if not reason.is_empty():
			lines.append(bad % [COLOR_BAD.to_html(false), SpellButton.wrap_text(reason)])
		elif game.spell_targeting.spell_id == spell_id:
			lines.append("[color=#%s]Zielort wählen · Rechtsklick oder Esc: abbrechen[/color]" % COLOR_DIM.to_html(false))
		else:
			lines.append("[color=#%s]Klick: Zielort wählen[/color]" % COLOR_DIM.to_html(false))
	return "\n".join(lines)


## "Forschung: Lichtsegen (Bibliothek, R)"
func _research_hint(k: Kingdom, spell_id: String) -> String:
	var def := DataDB.get_spell(spell_id)
	var requires: Array = def.get("requires", [])
	var building: String = game.research_system.get_research_building_name(k)
	return "Forschung: %s (%s, R)" % [DataDB.describe_requirement(requires, k.faction_id), building]


## " (statt 30)" – nur wenn Forschung den Wert verändert hat
func _base_note(value: float, base: float, unit: String) -> String:
	if absf(value - base) < 0.05:
		return ""
	return " [color=#%s](statt %s%s)[/color]" % [COLOR_DIM.to_html(false), _num(base), unit]


## Wirkung in Zahlen (mit Zauberstärke): "Eigene: +25 % Angriff, +15 % Rüstung" usw.
func _effect_text(def: Dictionary, power: float) -> String:
	var own: PackedStringArray = []
	var enemy: PackedStringArray = []
	var parts: PackedStringArray = []
	var heal := float(def.get("heal_instant", 0.0)) * power
	if heal > 0.0:
		parts.append("Heilt sofort %s Leben" % _num(heal))
	var zone: Dictionary = def.get("zone", {})
	var effect_list: Array = (def.get("effects", []) as Array) + (zone.get("effects", []) as Array)
	for e in effect_list:
		var eff: Dictionary = e
		var key := str(eff.get("key", ""))
		var text := ""
		if key == "hp_per_sec":
			var rate := float(eff.get("add", 0.0)) * power
			text = "%s Leben/s" % _signed(rate)
		else:
			var stat := str(STAT_NAMES.get(key, key))
			if eff.has("mult"):
				text = "%s %s" % [_percent((float(eff["mult"]) - 1.0) * power), stat]
			elif eff.has("add"):
				text = "%s %s" % [_percent(float(eff["add"]) * power), stat]
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
		parts.append("%s Ertrag (%s)" % [_percent((production - 1.0) * power), ", ".join(names)])
	var drop := float(zone.get("drop_targets_beyond", 0.0))
	if drop > 0.0:
		parts.append("Feinde verlieren Ziele über %s Felder" % _num(drop))
	var summon: Dictionary = def.get("summon", {})
	if not summon.is_empty():
		var unit_def := DataDB.get_unit_type(str(summon.get("unit", "")))
		parts.append("%d× %s (Leben %d, Angriff %d)" % [int(summon.get("count", 1)), str(unit_def.get("name", "?")),
				roundi(float(unit_def.get("hp", 0.0))), roundi(float(unit_def.get("attack", 0.0)))])
	if bool(def.get("stealth", false)):
		parts.append("Eigene Truppen unsichtbar bis zum ersten Angriff")
	return " · ".join(parts)


## "+25 %" bzw. "−40 %"
static func _percent(v: float) -> String:
	var p := roundi(v * 100.0)
	return ("+%d %%" % p) if p >= 0 else ("−%d %%" % -p)


## Zahl mit Komma: "0,5", "24", "13,2"
static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return str(roundi(v))
	return ("%.1f" % v).replace(".", ",")


static func _signed(v: float) -> String:
	return ("+" if v >= 0.0 else "−") + _num(absf(v))


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
