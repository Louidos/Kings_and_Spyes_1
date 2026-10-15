## UiStyle
##
## Gemeinsame Hilfen der Oberfläche (Phase 10):
## - UI-Grösse (Einstellung "Grösse der Oberfläche"): registrierte Ebenen werden
##   skaliert, ihre Wurzel bekommt die Grösse Viewport / Faktor (Klicks stimmen so).
## - Fenster im gleichen Stil: Rahmen und Hintergrund in den Farben der Fraktion
##   (window_style), Titelzeile mit Wappen, Titel, Reitern und Schliessen-Knopf
##   (window_header), Reiter (tab_button), Abschnittstitel (section_label), Fusszeile
##   (footer_label). Benutzt von Forschung, Helden, Diplomatie, Spionage, Reich, Armee,
##   Hilfe, Protokoll und Spielmenü (Speichern/Laden/Einstellungen).
## - Tooltips mit BBCode.
class_name UiStyle
extends RefCounted

const TITLE_FONT_SIZE := 22
const GROUP := "ui_scale"

## Farben der Fenster (GUT: Gold, BÖSE: Violett)
const GOOD_ACCENT := Color("#f3d36b")
const GOOD_LIGHT := Color("#fff3c4")
const GOOD_MID := Color(0.62, 0.47, 0.2)
const EVIL_ACCENT := Color("#8e44ad")
const EVIL_MID := Color("#6c3483")
const EVIL_LIGHT := Color("#d9bdf2")
const GOOD_BG := Color(0.1, 0.085, 0.065, 0.97)
const EVIL_BG := Color(0.07, 0.045, 0.1, 0.97)
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.74, 0.71, 0.66)
## Grösse des Fenstertitels und Innenabstand aller Fenster
const WINDOW_TITLE_SIZE := 25
const WINDOW_MARGIN_X := 16.0
const WINDOW_MARGIN_Y := 12.0
const TAB_FONT_SIZE := 17
const TAB_MIN_WIDTH := 136.0
const SECTION_FONT_SIZE := 18
const FOOTER_FONT_SIZE := 15


## Fraktion des Spielers (BÖSE: violett; ohne Partie GUT)
static func is_evil() -> bool:
	return GameSession.faction_id == "evil"


static func accent(evil: bool) -> Color:
	return EVIL_ACCENT if evil else GOOD_ACCENT


static func light(evil: bool) -> Color:
	return EVIL_LIGHT if evil else GOOD_LIGHT


## Farbe von Titeln und Abschnittsüberschriften
static func title_color(evil: bool) -> Color:
	return EVIL_LIGHT if evil else GOOD_ACCENT


static func flat(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(border_width)
	st.set_corner_radius_all(radius)
	st.anti_aliasing = true
	return st


## Hintergrund aller Fenster: dunkel, Rahmen in der Akzentfarbe, Schatten, gleicher Innenabstand
static func window_style(evil: bool) -> StyleBoxFlat:
	var st := flat(EVIL_BG if evil else GOOD_BG, accent(evil), 2, 8)
	st.content_margin_left = WINDOW_MARGIN_X
	st.content_margin_right = WINDOW_MARGIN_X
	st.content_margin_top = WINDOW_MARGIN_Y
	st.content_margin_bottom = WINDOW_MARGIN_Y
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 14
	if evil:
		st.border_blend = true
	return st


## Titelzeile eines Fensters: Wappen, Titel, (Platz für Zusatz und Reiter), Schliessen-Knopf;
## darunter eine Linie in der Akzentfarbe. Weitere Elemente mit header_add einfügen
## (stehen dann vor dem Schliessen-Knopf). Der Titel ist als Meta "title" abgelegt.
static func window_header(root: Control, title: String, evil: bool, close_tip: String, on_close: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(row)
	var emblem := ResearchPanel.Emblem.new()
	emblem.evil = evil
	emblem.color = title_color(evil)
	emblem.custom_minimum_size = Vector2(26, 26)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(emblem)
	var label := Label.new()
	label.text = title
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", WINDOW_TITLE_SIZE)
	label.add_theme_color_override("font_color", title_color(evil))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("outline_size", 4)
	row.add_child(label)
	row.set_meta("title", label)
	# Füller: Zusatz und Reiter stehen rechts, der Schliessen-Knopf ganz rechts
	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(filler)
	row.set_meta("filler", filler)
	if on_close.is_valid():
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(6, 0)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(spacer)
		row.add_child(close_button(close_tip, on_close))
	var line := ColorRect.new()
	line.color = Color(accent(evil), 0.55)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(line)
	return row


## Element in die Titelzeile einfügen: after_title = direkt hinter dem Titel (z. B. "3 von 5
## Helden", füllt dann die Breite), sonst rechts vor dem Schliessen-Knopf (Reiter, Schalter)
static func header_add(row: HBoxContainer, c: Control, after_title: bool = false) -> void:
	var filler: Control = row.get_meta("filler")
	row.add_child(c)
	if after_title:
		row.move_child(c, filler.get_index())
		# Der Zusatz nimmt den freien Platz ein
		filler.size_flags_horizontal = Control.SIZE_FILL
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		var close_idx := row.get_child_count() - 1
		for i in row.get_child_count():
			if row.get_child(i) is Button and row.get_child(i).has_meta("close"):
				close_idx = i - 1  # vor dem Abstand
				break
		row.move_child(c, maxi(close_idx, filler.get_index() + 1))


## Schliessen-Knopf "×" (alle Fenster gleich)
static func close_button(tip: String, on_close: Callable) -> Button:
	var b := Button.new()
	b.text = "×"
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(40, 36)
	b.set_meta("close", true)
	b.pressed.connect(on_close)
	return b


## Reiter in der Titelzeile (Umschalter einer Gruppe; gedrückt in der Akzentfarbe)
static func tab_button(text: String, group: ButtonGroup, evil: bool, min_width: float = TAB_MIN_WIDTH) -> ResearchTipButton:
	var b := ResearchTipButton.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", TAB_FONT_SIZE)
	b.custom_minimum_size = Vector2(min_width, 36)
	var pressed := flat(EVIL_MID if evil else GOOD_MID, light(evil), 1, 4)
	pressed.content_margin_left = 14
	pressed.content_margin_right = 14
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	return b


## Abschnittsüberschrift in einem Fenster
static func section_label(text: String, evil: bool, font_size: int = SECTION_FONT_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", title_color(evil))
	return l


## Fusszeile (Hinweise, Tasten) unten im Fenster
static func footer_label(text: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", FOOTER_FONT_SIZE)
	l.add_theme_color_override("font_color", COLOR_DIM)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


## Ebene für die UI-Grösse anmelden (root: Control, die die ganze Ebene füllt)
static func register_scaled_layer(layer: CanvasLayer, root: Control) -> void:
	layer.add_to_group(GROUP)
	layer.set_meta("ui_root", root)
	if layer.is_inside_tree():
		_apply_layer(layer, Settings.ui_scale)


## UI-Grösse auf alle angemeldeten Ebenen anwenden (nach Settings.changed und bei Fenstergrösse)
static func apply_ui_scale(tree: SceneTree) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		if node is CanvasLayer:
			_apply_layer(node as CanvasLayer, Settings.ui_scale)


static func _apply_layer(layer: CanvasLayer, s: float) -> void:
	var root: Variant = layer.get_meta("ui_root", null)
	if not (root is Control) or not is_instance_valid(root):
		return
	var c: Control = root
	if is_equal_approx(s, 1.0) and not layer.has_meta("ui_scaled"):
		return  # nie skaliert: nichts anfassen
	layer.set_meta("ui_scaled", true)
	layer.scale = Vector2(s, s)
	var vp := layer.get_viewport().get_visible_rect().size
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2.ZERO
	c.size = vp / s


## Zentriertes Fenster (Forschung, Helden, Diplomatie, Spionage, Reich) oben mittig platzieren:
## Grösse nach der UI-Grösse, bei kleinem Fenster verkleinert, aber nie ausserhalb.
## top ist der Abstand unter der Leiste oben bei UI-Grösse 100 %.
static func place_window(panel: Control, design_width: float, top: float) -> void:
	var vp := panel.get_viewport_rect().size
	var u := Settings.ui_scale
	var want := Vector2(design_width, panel.get_combined_minimum_size().y)
	panel.size = want
	var top_px := top * u
	var s := minf(u, minf((vp.x - 16.0) / want.x, (vp.y - top_px - 8.0) / want.y))
	s = maxf(s, 0.4)
	panel.scale = Vector2(s, s)
	var y := clampf(top_px, 8.0, maxf(vp.y - want.y * s - 8.0, 8.0))
	panel.position = Vector2(floorf((vp.x - want.x * s) * 0.5), floorf(y))


## Tooltip mit BBCode (für _make_custom_tooltip)
static func make_rich_tooltip(bbcode: String, max_width: float = 420.0) -> Control:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(max_width, 0)
	label.text = bbcode
	return label
