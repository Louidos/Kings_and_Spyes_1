## ResourceBar
##
## Ressourcenleiste in der oberen Leiste: je Ressource Symbol und Menge
## (Tooltip: Ertrag pro Minute, bei Nahrung auch Verbrauch und Hungersnot),
## danach Bewohner/Wohnraum mit dem Wachstumszustand im Tooltip, die Truppen
## (beschworene Einheiten, Tooltip mit Kampfpunkten) und das Leben des Königs.
## Zeigt nur an – wird viermal pro Sekunde aktualisiert, nicht in jedem Bild.
class_name ResourceBar
extends HBoxContainer

const REFRESH_INTERVAL := 0.25
const ICON_SIZE := 24.0
const COLOR_NORMAL := Color(0.95, 0.92, 0.85)
const COLOR_BAD := Color(1.0, 0.42, 0.36)


## Eintrag der Leiste. Teure Tooltips (Verbrauch, Statistik) entstehen erst,
## wenn sie gezeigt werden (source), nicht bei jeder Aktualisierung.
class TipBox:
	extends HBoxContainer
	var source := Callable()

	func _get_tooltip(_at_position: Vector2) -> String:
		return str(source.call()) if source.is_valid() else tooltip_text


var game: Node

## Ressource -> Label der Menge
var _amount_labels: Dictionary = {}
## Ressource -> Eintrag (trägt den Tooltip)
var _entries: Dictionary = {}
var _pop_label: Label
var _troops_label: Label
var _king_label: Label
var _timer := 0.0


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
		var icon := ResourceIcon.new()
		icon.setup(res_id, ICON_SIZE)
		entry.add_child(icon)
		var label := _make_label(48)
		entry.add_child(label)
		_amount_labels[res_id] = label
		_entries[res_id] = entry
	var pop_entry := _make_entry()
	_pop_label = _make_label(0)
	pop_entry.add_child(_pop_label)
	_entries["_population"] = pop_entry
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
		var entry: Control = _entries.get(res_id)
		if label == null or entry == null:
			continue
		var amount := k.get_amount(res_id)
		var bad := res_id == "food" and k.starving
		_set_label(label, str(floori(amount)), COLOR_BAD if bad else COLOR_NORMAL)
	_refresh_population(k)
	_refresh_troops(k)
	_refresh_king(k)


func _resource_tip(r: Dictionary) -> String:
	var k: Kingdom = game.player
	if k == null:
		return ""
	return _resource_tooltip(k, r, k.get_amount(str(r["id"])))


func _resource_tooltip(k: Kingdom, r: Dictionary, amount: float) -> String:
	var res_id := str(r["id"])
	var lines: PackedStringArray = []
	lines.append("%s: %d" % [str(r.get("name", res_id)), floori(amount)])
	lines.append("%s pro Minute" % format_signed(float(k.income_rate.get(res_id, 0.0))))
	var cap := k.get_capacity(res_id)
	if cap < INF:
		lines.append("Lager: höchstens %d" % floori(cap))
	if res_id == "food":
		var use: float = game.economy_system.get_food_consumption_per_minute(k)
		lines.append("Verbrauch: %s pro Minute" % format_number(use))
		if k.starving:
			lines.append("Hungersnot – Arbeit halb so schnell")
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


## Zahl für die Anzeige: unter 10 mit einer Nachkommastelle, sonst ganz
static func format_number(v: float) -> String:
	if absf(v) >= 9.95:
		return str(roundi(v))
	var s := "%.1f" % v
	return s.trim_suffix(".0")


## Wie format_number, aber immer mit Vorzeichen ("+3.5", "−2", "0")
static func format_signed(v: float) -> String:
	var s := format_number(absf(v))
	if s == "0":
		return "±0"
	return ("+" if v > 0.0 else "−") + s
