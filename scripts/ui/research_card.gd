## ResearchCard
##
## Eine Forschung im Forschungsbaum: Name, Wirkung, Kosten (fehlende Mengen
## rot) und Dauer. Der Zustand bestimmt Rahmen und Zeichen: erforscht = grün
## mit Haken, läuft = blau mit Fortschritt, eingereiht = Nummer, gesperrt =
## grau. Zeigt nur an – Klicks wertet das ResearchPanel aus (Signal activated).
class_name ResearchCard
extends ResearchTipButton

signal activated(research_id: String)

## Namensschrift: so gross wie möglich, bis der Name passt
const NAME_FONT_SIZES: Array[int] = [16, 15, 14, 13]
const SMALL_FONT_SIZE := 14
const PAD := 9.0
const ICON_SIZE := 14.0
## Platz rechts oben für Haken bzw. Nummer
const BADGE_SLOT := 22.0

const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.74, 0.71, 0.66)
const COLOR_LOCKED := Color(0.5, 0.49, 0.48)
const COLOR_MISSING := Color(1.0, 0.45, 0.38)
const COLOR_DONE := Color(0.45, 0.82, 0.45)
const COLOR_ACTIVE := Color(0.4, 0.68, 0.98)
const COLOR_QUEUED := Color(0.42, 0.6, 0.86)
const COLOR_CONFIRM := Color(1.0, 0.4, 0.33)

var research_id := ""
## "done", "active", "queued", "available", "locked"
var state := ""
## Platz in der Warteschlange (1 = läuft)
var queue_pos := 0
var progress := 0.0
var confirming := false

var _name_label: Label
var _corner_label: Label
var _effect_label: Label
var _cost_box: HBoxContainer
## Ressource -> Label der Kostenzahl (für die rote Färbung)
var _cost_labels: Dictionary = {}
var _cost: Dictionary = {}
var _time := 0.0
var _effect_text := ""
## Zustand -> StyleBoxFlat (für alle Karten gleich, daher gemeinsam genutzt)
var _styles: Dictionary = {}


func setup(def: Dictionary, effect_text: String, card_size: Vector2, styles: Dictionary) -> void:
	research_id = str(def.get("id", ""))
	_styles = styles
	_effect_text = effect_text
	_cost = def.get("cost", {})
	_time = float(def.get("time", 0.0))
	custom_minimum_size = card_size
	size = card_size
	pressed.connect(func() -> void: activated.emit(research_id))

	_name_label = _make_label(NAME_FONT_SIZES[0], COLOR_TEXT)
	_name_label.text = str(def.get("name", research_id))
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.position = Vector2(PAD, PAD - 3.0)

	_corner_label = _make_label(SMALL_FONT_SIZE, COLOR_DIM)
	_corner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_effect_label = _make_label(SMALL_FONT_SIZE, COLOR_DIM)
	_effect_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effect_label.max_lines_visible = 2
	_effect_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_effect_label.add_theme_constant_override("line_spacing", -3)
	_effect_label.position = Vector2(PAD, PAD + 20.0)
	_effect_label.size = Vector2(card_size.x - PAD * 2.0, 36.0)
	_effect_label.text = effect_text

	_cost_box = HBoxContainer.new()
	_cost_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost_box.add_theme_constant_override("separation", 2)
	_cost_box.position = Vector2(PAD, card_size.y - PAD - 21.0)
	_cost_box.size = Vector2(card_size.x - PAD * 2.0, 20.0)
	add_child(_cost_box)
	var first := true
	for r in DataDB.resources:
		var res_id := str(r["id"])
		var amount := float(_cost.get(res_id, 0.0))
		if amount <= 0.0:
			continue
		if not first:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(6, 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_cost_box.add_child(gap)
		first = false
		var icon := ResourceIcon.new()
		icon.setup(res_id, ICON_SIZE)
		_cost_box.add_child(icon)
		var label := _make_label(SMALL_FONT_SIZE, COLOR_TEXT, false)
		label.text = str(ceili(amount))
		_cost_box.add_child(label)
		_cost_labels[res_id] = label
	if first:
		var free := _make_label(SMALL_FONT_SIZE, COLOR_DIM, false)
		free.text = "kostenlos"
		_cost_box.add_child(free)
	_layout_top_row()


## Zustand übernehmen (Stil und Zeichen nur bei Änderung neu)
func apply(p_state: String, p_queue_pos: int, p_progress: float, p_confirming: bool, k: Kingdom) -> void:
	var changed := p_state != state or p_queue_pos != queue_pos or p_confirming != confirming
	var progress_changed := not is_equal_approx(p_progress, progress)
	state = p_state
	queue_pos = p_queue_pos
	progress = p_progress
	confirming = p_confirming
	var locked := state == "locked"
	if changed:
		var key := "confirm" if confirming else state
		var style: StyleBox = _styles.get(key)
		var hover: StyleBox = _styles.get(key + "_hover", style)
		if style != null:
			add_theme_stylebox_override("normal", style)
			add_theme_stylebox_override("disabled", style)
			add_theme_stylebox_override("hover", hover)
			add_theme_stylebox_override("pressed", hover)
			add_theme_stylebox_override("hover_pressed", hover)
		var name_color := COLOR_TEXT
		if locked:
			name_color = COLOR_LOCKED
		elif state == "done":
			name_color = COLOR_DONE.lightened(0.35)
		_set_color(_name_label, name_color)
		queue_redraw()
	# Rechts oben: Dauer; bei der laufenden Forschung der Fortschritt
	var corner := "%d s" % roundi(_time)
	if state == "active":
		corner = "%d %%" % floori(progress * 100.0)
	elif state == "done" or state == "queued":
		corner = ""  # Haken bzw. Nummer wird gezeichnet
	if _corner_label.text != corner or changed:
		_corner_label.text = corner
		_layout_top_row()
	_set_color(_corner_label, COLOR_ACTIVE.lightened(0.3) if state == "active" else (COLOR_LOCKED if locked else COLOR_DIM))
	# Wirkungszeile: beim Bestätigen der Hinweis zum Abbrechen
	var effect := "Nochmal klicken: abbrechen (Kosten zurück)" if confirming else _effect_text
	if _effect_label.text != effect:
		_effect_label.text = effect
	_set_color(_effect_label, COLOR_CONFIRM if confirming else (COLOR_LOCKED if locked else COLOR_DIM))
	# Kosten: fehlende Mengen rot (nur solange man sie noch bezahlen muss)
	var pay := state == "available" or locked
	for res_id in _cost_labels:
		var label: Label = _cost_labels[res_id]
		var lack := pay and k.get_amount(str(res_id)) + 0.0001 < float(_cost[res_id])
		var c := COLOR_TEXT
		if lack:
			c = COLOR_MISSING
		elif locked:
			c = COLOR_LOCKED
		elif state == "done":
			c = COLOR_DIM
		_set_color(label, c)
	var cost_alpha := 0.5 if state == "done" else (0.7 if locked else 1.0)
	if not is_equal_approx(_cost_box.modulate.a, cost_alpha):
		_cost_box.modulate.a = cost_alpha
	if progress_changed and state == "active":
		queue_redraw()


func _draw() -> void:
	var corner := Vector2(size.x - PAD - 8.0, PAD + 7.0)
	match state:
		"done":
			draw_circle(corner, 9.0, COLOR_DONE)
			draw_polyline(PackedVector2Array([corner + Vector2(-4.5, 0.2), corner + Vector2(-1.3, 3.5),
					corner + Vector2(4.6, -3.4)]), Color(0.05, 0.12, 0.05), 2.4, true)
		"queued":
			draw_circle(corner, 9.5, COLOR_QUEUED.darkened(0.25))
			draw_arc(corner, 9.5, 0.0, TAU, 24, COLOR_QUEUED.lightened(0.45), 1.3, true)
			var font := get_theme_default_font()
			var t := str(queue_pos)
			var fs := 13
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var base := corner.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
			draw_string(font, Vector2(corner.x - tw * 0.5, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		"active":
			# Fortschritt als Balken am unteren Rand (innerhalb des Rahmens)
			var bar := Rect2(4.0, size.y - 7.0, size.x - 8.0, 4.0)
			draw_rect(bar, Color(0.03, 0.06, 0.12, 0.95))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), bar.size.y)), COLOR_ACTIVE)


## Mittelpunkt oben/unten (für die Verbindungslinien im Baum)
func get_top_anchor() -> Vector2:
	return position + Vector2(size.x * 0.5, 0.0)


func get_bottom_anchor() -> Vector2:
	return position + Vector2(size.x * 0.5, size.y)


## Name links, Dauer bzw. Zeichen rechts; die Namensschrift wird kleiner,
## bis der Name in den verbleibenden Platz passt.
func _layout_top_row() -> void:
	var font := get_theme_default_font()
	var corner_w := BADGE_SLOT
	if not _corner_label.text.is_empty():
		corner_w = font.get_string_size(_corner_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_FONT_SIZE).x + 2.0
	_corner_label.size = Vector2(corner_w + 2.0, 22.0)
	_corner_label.position = Vector2(size.x - PAD - corner_w - 2.0, PAD - 3.0)
	var avail := size.x - PAD * 2.0 - corner_w - 6.0
	var chosen := NAME_FONT_SIZES[NAME_FONT_SIZES.size() - 1]
	for fs in NAME_FONT_SIZES:
		if font.get_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= avail:
			chosen = fs
			break
	_name_label.add_theme_font_size_override("font_size", chosen)
	_name_label.size = Vector2(avail, 22.0)


func _make_label(font_size: int, color: Color, add := true) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if add:
		add_child(label)
	return label


func _set_color(label: Label, color: Color) -> void:
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)
