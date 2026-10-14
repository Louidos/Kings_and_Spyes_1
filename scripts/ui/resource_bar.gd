## ResourceBar
##
## Ressourcenleiste in der oberen Leiste: je Ressource Symbol und Menge
## (Tooltip: Ertrag pro Minute, bei Nahrung auch Verbrauch und Hungersnot,
## bei Mana Bestand/Maximum mit allen Anteilen), daneben die Kampfpunkte,
## danach Bewohner/Wohnraum mit dem Wachstumszustand im Tooltip, die Truppen
## (beschworene Einheiten) und das Leben des Königs. Ab Phase 8 nach den Bewohnern
## die Zufriedenheit (Gesicht mit Durchschnitt, Tooltip mit Ursachen; Klick öffnet
## die Reichsübersicht).
## Zeigt nur an – wird viermal pro Sekunde aktualisiert, nicht in jedem Bild.
class_name ResourceBar
extends HBoxContainer

## Klick auf die Kampfpunkte: Forschungsfenster auf dem Reiter "Kampfpunkte"
signal kill_points_clicked
## Klick auf die Zufriedenheit: Reichsübersicht (Phase 8)
signal satisfaction_clicked

const REFRESH_INTERVAL := 0.25
const ICON_SIZE := 24.0
const COLOR_NORMAL := Color(0.95, 0.92, 0.85)
const COLOR_BAD := Color(1.0, 0.42, 0.36)
const COLOR_FULL := Color(1.0, 0.85, 0.3)
const COLOR_GOOD := Color(0.55, 0.88, 0.5)
const COLOR_DIM := Color(0.74, 0.71, 0.66)
## Hinweis "Mana-Speicher voll" höchstens so oft (Spielsekunden)
const MANA_FULL_NOTIFY_INTERVAL := 120.0


## Eintrag der Leiste. Teure Tooltips (Verbrauch, Statistik) entstehen erst,
## wenn sie gezeigt werden (source), nicht bei jeder Aktualisierung.
## rich = true: der Tooltip ist BBCode (farbige Zeilen).
class TipBox:
	extends HBoxContainer
	var source := Callable()
	var rich := false
	var tip_max_width := 400.0

	func _get_tooltip(_at_position: Vector2) -> String:
		return str(source.call()) if source.is_valid() else tooltip_text

	func _make_custom_tooltip(for_text: String) -> Object:
		if not rich:
			return null
		return ResearchTipButton.make_rich_tooltip(for_text, tip_max_width)


## Zwei gekreuzte Schwerter (im Code gezeichnet – die Schrift hat kein ⚔)
class SwordsIcon:
	extends Control
	var color := Color(0.95, 0.83, 0.42)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := (size - Vector2(s, s)) * 0.5
		var outline := Color(0.05, 0.04, 0.03, 0.9)
		for flip in [false, true]:
			var a := o + Vector2(s * 0.14, s * 0.14)
			var b := o + Vector2(s * 0.8, s * 0.8)
			if flip:
				a = o + Vector2(s * 0.86, s * 0.14)
				b = o + Vector2(s * 0.2, s * 0.8)
			var dir := (b - a).normalized()
			var side := Vector2(-dir.y, dir.x)
			# Klinge (mit dunklem Rand), Parierstange, Griff
			draw_line(a, b - dir * s * 0.12, outline, s * 0.17, true)
			draw_line(a, b - dir * s * 0.12, color, s * 0.09, true)
			var guard := b - dir * s * 0.14
			draw_line(guard - side * s * 0.16, guard + side * s * 0.16, outline, s * 0.13, true)
			draw_line(guard - side * s * 0.15, guard + side * s * 0.15, color.darkened(0.25), s * 0.07, true)
			draw_line(guard, b + dir * s * 0.04, color.darkened(0.45), s * 0.08, true)


var game: Node

## Ressource -> Label der Menge
var _amount_labels: Dictionary = {}
## Ressource -> Eintrag (trägt den Tooltip)
var _entries: Dictionary = {}
var _kp_label: Label
var _kp_icon: SwordsIcon
var _pop_label: Label
var _mood_icon: MoodIcon
var _mood_label: Label
var _troops_label: Label
var _king_label: Label
var _timer := 0.0
## Spielzeit des letzten "Mana voll"-Hinweises (-INF = noch nie)
var _mana_full_notified_at := -INF


func setup(p_game: Node) -> void:
	game = p_game
	for child in get_children():
		child.queue_free()
	_amount_labels.clear()
	_entries.clear()
	for r in DataDB.resources:
		var res_id := str(r["id"])
		var entry := _make_entry()
		entry.source = _resource_tip.bind(r)
		entry.rich = true
		var icon := ResourceIcon.new()
		icon.setup(res_id, ICON_SIZE)
		entry.add_child(icon)
		# Mana zeigt "Bestand/Maximum" und braucht mehr Platz
		var label := _make_label(74 if res_id == "mana" else 48)
		entry.add_child(label)
		_amount_labels[res_id] = label
		_entries[res_id] = entry
		if res_id == "mana":
			_add_kill_points_entry()
	if _kp_label == null:
		_add_kill_points_entry()
	var pop_entry := _make_entry()
	_pop_label = _make_label(0)
	pop_entry.add_child(_pop_label)
	_entries["_population"] = pop_entry
	_add_satisfaction_entry()
	# Phase 8: etwas engere Abstände, damit die obere Leiste mit der Zufriedenheit in 1920 passt
	add_theme_constant_override("separation", 5)
	var troops_entry := _make_entry()
	troops_entry.source = _troops_tip
	_troops_label = _make_label(0)
	troops_entry.add_child(_troops_label)
	_entries["_troops"] = troops_entry
	var king_entry := _make_entry()
	_king_label = _make_label(0)
	king_entry.add_child(_king_label)
	king_entry.tooltip_text = "Leben des Königs – fällt er, ist das Spiel verloren"
	_entries["_king"] = king_entry
	_refresh()


## Kampfpunkte: gekreuzte Schwerter + Zahl, Klick öffnet die Verbesserungen
func _add_kill_points_entry() -> void:
	var entry := _make_entry()
	entry.source = _kill_points_tip
	entry.rich = true
	entry.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	entry.gui_input.connect(_on_kill_points_input)
	_kp_icon = SwordsIcon.new()
	_kp_icon.color = Color("#d9bdf2") if game.player.faction_id == "evil" else Color("#f3d36b")
	_kp_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	entry.add_child(_kp_icon)
	_kp_label = _make_label(28)
	entry.add_child(_kp_label)
	_entries["_kill_points"] = entry


func _on_kill_points_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		kill_points_clicked.emit()
		accept_event()


func _process(delta: float) -> void:
	if game == null or not is_visible_in_tree():
		return
	_timer += delta
	if _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		_refresh()


func _refresh() -> void:
	var k: Kingdom = game.player
	if k == null:
		return
	for r in DataDB.resources:
		var res_id := str(r["id"])
		var label: Label = _amount_labels.get(res_id)
		if label == null:
			continue
		var amount := k.get_amount(res_id)
		if res_id == "mana":
			_refresh_mana(k, label, amount)
			continue
		var bad := res_id == "food" and k.starving
		_set_label(label, str(floori(amount)), COLOR_BAD if bad else COLOR_NORMAL)
	_set_label(_kp_label, str(k.kill_points), COLOR_NORMAL)
	_refresh_population(k)
	_refresh_satisfaction(k)
	_refresh_troops(k)
	_refresh_king(k)


## Mana "80/100"; voll = gelb. Läuft der volle Speicher weiter über, kommt
## höchstens alle 2 Spielminuten ein Hinweis.
func _refresh_mana(k: Kingdom, label: Label, amount: float) -> void:
	var cap := k.get_capacity("mana")
	var full := is_mana_full(k)
	# Über dem Maximum (nach Erstattung) wird nicht gekürzt angezeigt: "160/100"
	_set_label(label, "%d/%d" % [floori(amount), roundi(cap)], COLOR_FULL if full else COLOR_NORMAL)
	if full and is_mana_produced(k) \
			and GameClock.game_time - _mana_full_notified_at >= MANA_FULL_NOTIFY_INTERVAL:
		_mana_full_notified_at = GameClock.game_time
		Notify.info("Mana-Speicher voll – Überschuss geht verloren. Mehr Maximum: Forschung (R) → Kampfpunkte.")


func _resource_tip(r: Dictionary) -> String:
	var k: Kingdom = game.player
	if k == null:
		return ""
	if str(r["id"]) == "mana":
		return mana_tooltip(k)
	return _resource_tooltip(k, r, k.get_amount(str(r["id"])))


func _resource_tooltip(k: Kingdom, r: Dictionary, amount: float) -> String:
	var res_id := str(r["id"])
	var lines: PackedStringArray = []
	lines.append("[b]%s: %d[/b]" % [ResearchTipButton.esc(str(r.get("name", res_id))), floori(amount)])
	lines.append("%s pro Minute" % format_signed(float(k.income_rate.get(res_id, 0.0))))
	var cap := k.get_capacity(res_id)
	if cap < INF:
		lines.append("Lager: höchstens %d" % floori(cap))
	if res_id == "food":
		var use: float = game.economy_system.get_food_consumption_per_minute(k)
		lines.append("Verbrauch: %s pro Minute" % format_number(use))
		if k.starving:
			lines.append(ResearchTipButton.colored("Hungersnot – Arbeit halb so schnell", COLOR_BAD))
	return "\n".join(lines)


## Mana-Tooltip (BBCode): Bestand, Ertrag, Burg, laufende Kosten, Maximum mit
## allen Anteilen und wie man mehr bekommt.
func mana_tooltip(k: Kingdom) -> String:
	var tip := ResearchTipButton
	var amount := k.get_amount("mana")
	var cap := k.get_capacity("mana")
	var lines: PackedStringArray = []
	lines.append("[b]Mana: %d/%d[/b]" % [floori(amount), roundi(cap)])
	if is_mana_full(k):
		lines.append(tip.colored("Mana-Speicher voll – Überschuss geht verloren", COLOR_FULL))
	lines.append("Ertrag: %s pro Minute" % format_signed(float(k.income_rate.get("mana", 0.0))))
	var regen := k.mana_regen * 60.0
	if regen > 0.0:
		lines.append("  davon Burg (Manaherz): %s pro Minute" % format_signed(regen))
	else:
		lines.append(tip.colored("  Burg: kein eigenes Mana (Manaherz, Kampfpunkte)", COLOR_DIM))
	var upkeep := k.get_upkeep("mana") * 60.0
	if upkeep > 0.0:
		lines.append(tip.colored("  laufende Zauber (Tarnung): −%s pro Minute" % format_number(upkeep), COLOR_BAD))
	var parts: PackedStringArray = []
	for p in mana_cap_parts(k):
		parts.append("%s %d" % [str(p[0]), roundi(float(p[1]))])
	lines.append("Maximum %d = %s" % [roundi(cap), tip.esc(" + ".join(parts))])
	lines.append(tip.colored(mana_raise_hint(k), COLOR_DIM))
	return "\n".join(lines)


## Mana-Maximum in Anteilen: [[Name, Wert], …] – Grundwert (resources.json),
## dann jede Zuschlagsquelle ("Manakristall" …)
static func mana_cap_parts(k: Kingdom) -> Array:
	var parts: Array = []
	var base := float(DataDB.get_resource("mana").get("cap", 0.0)) * k.mod("cap.mana")
	parts.append(["Grundwert", base])
	for src in k.bonus_sources:
		var entry: Dictionary = k.bonus_sources[src]
		var v := float(entry.get("cap.mana", 0.0))
		if not is_zero_approx(v):
			parts.append([DataDB.describe_effect_source(str(src)), v])
	return parts


## Wie man mehr Mana bekommt (Forschungsname der eigenen Fraktion)
static func mana_raise_hint(k: Kingdom) -> String:
	var lore := ""
	for r in DataDB.get_research_for_faction(k.faction_id):
		for e in r.get("effects", []):
			if str(e.get("type", "")) == "modifier" and str(e.get("key", "")) == "production.mana":
				lore = str(r.get("name", ""))
	var text := "Mehr Mana: Manabrunnen + Manawirker (J)"
	if not lore.is_empty():
		text += ", Forschung „%s“" % lore
	return text + "\nMehr Maximum und Burg-Mana: Kampfpunkte (Forschung, R)"


## Mana am (oder über dem) Maximum?
static func is_mana_full(k: Kingdom) -> bool:
	return k.get_amount("mana") >= k.get_capacity("mana") - 0.5


## Kommt laufend Mana dazu (Burg oder fertige Gebäude mit Mana-Ertrag)?
static func is_mana_produced(k: Kingdom) -> bool:
	if k.mana_regen > 0.0:
		return true
	for b in k.buildings:
		if not is_instance_valid(b) or not b.constructed:
			continue
		var per_worker: Dictionary = b.def.get("production", {})
		var base: Dictionary = b.def.get("base_production", {})
		if float(base.get("mana", 0.0)) > 0.0 or (float(per_worker.get("mana", 0.0)) > 0.0 and not b.workers.is_empty()):
			return true
	return false


func _kill_points_tip() -> String:
	var k: Kingdom = game.player
	if k == null:
		return ""
	var lines: PackedStringArray = []
	lines.append("[b]Kampfpunkte: %d[/b] (gesamt %d)" % [k.kill_points, k.kill_points_total])
	lines.append("Kampfpunkte – für besiegte Monster und Feinde.")
	lines.append("Ausgeben: Forschung (R) → Kampfpunkte")
	if ResearchPanel.has_affordable_upgrade(game.research_system, k):
		lines.append(ResearchTipButton.colored("Eine Verbesserung ist bezahlbar – klicken!", COLOR_GOOD))
	return "\n".join(lines)


func _refresh_population(k: Kingdom) -> void:
	var pop := k.get_population()
	var housing := k.get_housing()
	var state: int = game.economy_system.get_growth_state(k)
	var blocked := state != EconomySystem.Growth.GROWING
	_set_label(_pop_label, "Bewohner %d/%d" % [pop, housing], COLOR_BAD if blocked else COLOR_NORMAL)
	var lines: PackedStringArray = ["Bewohner: %d  ·  Wohnraum: %d" % [pop, housing]]
	match state:
		EconomySystem.Growth.GROWING:
			var secs: float = game.economy_system.get_seconds_to_growth(k)
			lines.append("Nächster Bewohner in %d s" % ceili(secs))
		EconomySystem.Growth.HOUSING_FULL:
			lines.append("Wachstum gestoppt: Wohnraum voll – baue Wohnhäuser")
		EconomySystem.Growth.LOW_FOOD:
			lines.append("Wachstum gestoppt: weniger als %d Nahrung" % int(DataDB.eco("population.growth_food_min", 30)))
		EconomySystem.Growth.STARVING:
			lines.append("Wachstum gestoppt: Hungersnot")
	var entry: Control = _entries.get("_population")
	if entry != null:
		entry.tooltip_text = "\n".join(lines)


## Zufriedenheit: Gesicht (24 px) und Durchschnitt; Klick öffnet die Reichsübersicht
func _add_satisfaction_entry() -> void:
	var entry := _make_entry()
	entry.source = _satisfaction_tip
	entry.rich = true
	entry.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	entry.gui_input.connect(_on_satisfaction_input)
	_mood_icon = MoodIcon.new()
	_mood_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	entry.add_child(_mood_icon)
	_mood_label = _make_label(0)
	entry.add_child(_mood_label)
	_entries["_satisfaction"] = entry


func _on_satisfaction_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		satisfaction_clicked.emit()
		accept_event()


func _refresh_satisfaction(k: Kingdom) -> void:
	var ss: Variant = game.get("satisfaction_system")
	if _mood_label == null or ss == null:
		return
	var avg := float(ss.get_average(k))
	_mood_icon.set_value(avg)
	if avg < 0.0:
		_set_label(_mood_label, "–", COLOR_DIM)
	else:
		_set_label(_mood_label, str(roundi(avg)), SatisfactionSystem.tier_for(avg)["color"])


## Tooltip: Durchschnitt mit Stufe, Ursachen (grün/rot), Arbeitsleistung, Gefahr
func _satisfaction_tip() -> String:
	var k: Kingdom = game.player
	var ss: SatisfactionSystem = game.satisfaction_system
	var tip := ResearchTipButton
	var avg := ss.get_average(k)
	if avg < 0.0:
		return "[b]Zufriedenheit[/b]\nKeine Bewohner"
	var lines: PackedStringArray = ["[b]Zufriedenheit Ø %d – %s[/b]" % [roundi(avg), str(SatisfactionSystem.tier_for(avg)["name"])]]
	var parts := ss.get_breakdown(k)
	for i in mini(parts.size(), 8):
		var p: Dictionary = parts[i]
		var v := float(p["value"])
		lines.append(tip.colored(("%+d %s" % [roundi(v), str(p["cause"])]).replace("-", "−"), COLOR_GOOD if v > 0.0 else (COLOR_BAD if v < 0.0 else COLOR_NORMAL)))
	lines.append("Arbeitsleistung ×%s" % String.num(SatisfactionSystem.work_mult_for(avg), 2).replace(".", ","))
	var risk := ss.get_risk(k)
	if int(risk["defect"]) > 0:
		lines.append(tip.colored("%d Bewohner kurz vor dem Überlaufen" % int(risk["defect"]), COLOR_BAD))
	if int(risk["defecting"]) > 0:
		lines.append(tip.colored("%d läuft gerade über" % int(risk["defecting"]), COLOR_BAD))
	lines.append(tip.colored("Klick: Reichsübersicht (L)", COLOR_DIM))
	return "\n".join(lines)


## Truppen = eigene Einheiten ausser Bewohnern und König
func _refresh_troops(k: Kingdom) -> void:
	var troops := 0
	for u in k.units:
		var role: String = u.role
		if role != "worker" and role != "king":
			troops += 1
	_set_label(_troops_label, "Truppen %d" % troops, COLOR_NORMAL)


func _troops_tip() -> String:
	var k: Kingdom = game.player
	if k == null:
		return ""
	return "Beschworene Einheiten: %d\nKampfpunkte: %d (gesamt %d)\nBesiegte Feinde: %d  ·  Verluste: %d" % [
		int(k.stats.get("summoned", 0)), k.kill_points, k.kill_points_total,
		int(k.stats.get("kills", 0)), int(k.stats.get("losses", 0))]


## "König 600/600", rot unter halbem Leben; ohne König ausgeblendet
func _refresh_king(k: Kingdom) -> void:
	var entry: Control = _entries.get("_king")
	if entry == null:
		return
	var king: Variant = k.king
	var alive := is_instance_valid(king) and (king as Unit).is_alive()
	entry.visible = alive
	if not alive:
		return
	var u := king as Unit
	var low := u.hp < u.max_hp * 0.5
	_set_label(_king_label, "König %d/%d" % [ceili(u.hp), roundi(u.max_hp)], COLOR_BAD if low else COLOR_NORMAL)


func _make_entry() -> TipBox:
	var entry := TipBox.new()
	entry.add_theme_constant_override("separation", 6)
	# STOP, damit der Tooltip über Symbol und Zahl erscheint
	entry.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(entry)
	return entry


func _make_label(min_width: float) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(min_width, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _set_label(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


## Zahl für die Anzeige: unter 10 mit einer Nachkommastelle (Komma), sonst ganz
static func format_number(v: float) -> String:
	if absf(v) >= 9.95:
		return str(roundi(v))
	var s := "%.1f" % v
	return s.trim_suffix(".0").replace(".", ",")


## Wie format_number, aber immer mit Vorzeichen ("+3,5", "−2", "±0")
static func format_signed(v: float) -> String:
	var s := format_number(absf(v))
	if s == "0":
		return "±0"
	return ("+" if v > 0.0 else "−") + s
