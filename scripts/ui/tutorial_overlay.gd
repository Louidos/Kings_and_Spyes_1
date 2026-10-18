## TutorialOverlay
##
## Oberfläche des Tutorials (TutorialSystem): rechts ein Fenster mit Kapitel, "Schritt 5/35",
## Titel, Text, Aufgabe bzw. "Geschafft!" und den Knöpfen "Zeigen", "Überspringen",
## "Beenden" und "Weiter" (einklappbar). Dazu ein pulsierender Rahmen um das Bedienelement
## des Schritts (Baumenü-Knopf, Knopf oben, Minikarte …) bzw. ein Pfeil zu einer Stelle in
## der Welt (am Bildschirmrand, wenn sie ausserhalb liegt).
## Rahmen und Pfeil liegen in einer eigenen, nicht skalierten Ebene über dem HUD und den
## Fenstern und lassen alle Klicks durch – das Ziel bleibt bedienbar. Das Fenster skaliert
## mit der UI-Grösse (UiStyle). Es zeigt nur an und ruft advance/skip/abort des Systems auf.
class_name TutorialOverlay
extends CanvasLayer

## Über HUD (10), Fenstern (11), Flüchtlingsdialog (12); unter Spielmenü (40), Hilfe (41), Spielende (45)
const LAYER := 30
const PANEL_WIDTH := 400.0
## Rechts über der Zauberleiste (bzw. der Minikarte): Abstand darüber, Platz für beide ohne Leiste
const PANEL_GAP := 10.0
const PANEL_BOTTOM_FALLBACK := 380.0
## Nie höher als unter die obere Leiste und das Protokoll-Knöpfchen
const PANEL_MIN_TOP := 100.0
const REFRESH_INTERVAL := 0.25
const CONFIRM_MS := 3000
const COLOR_FRAME := Color(1.0, 0.84, 0.3)
const COLOR_DONE := Color(0.55, 0.95, 0.5)
const COLOR_HINT := Color(0.78, 0.75, 0.68)
const COLOR_CHAPTER := Color(0.95, 0.8, 0.45)

var game: Node
var system: TutorialSystem

var _root: Control
var _panel: PanelContainer
var _body: VBoxContainer
var _chapter: Label
var _progress_label: Label
var _min_button: Button
var _title: Label
var _text: RichTextLabel
var _status: Label
var _bar: ProgressBar
var _show_button: Button
var _skip_button: Button
var _end_button: Button
var _next_button: Button
## Zweite Ebene (nicht skaliert) für Rahmen und Pfeil
var _frame_layer: CanvasLayer
var _frame: Control
var _timer := 0.0
var _time := 0.0
var _end_confirm_ms := -100000
var _shown_step := ""


func _ready() -> void:
	layer = LAYER
	visible = false
	_frame_layer = CanvasLayer.new()
	_frame_layer.name = "TutorialFrameLayer"
	_frame_layer.layer = LAYER
	add_child(_frame_layer)
	_frame = Control.new()
	_frame.name = "TutorialFrame"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.draw.connect(_draw_frame)
	_frame_layer.add_child(_frame)
	_frame_layer.visible = false
	_root = Control.new()
	_root.name = "TutorialRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()
	UiStyle.register_scaled_layer(self, _root)


func setup(p_game: Node, p_system: TutorialSystem) -> void:
	game = p_game
	system = p_system
	system.changed.connect(_refresh)
	if game.hud != null:
		game.hud.visibility_changed.connect(_refresh)
	_refresh()


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "TutorialPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -PANEL_WIDTH - 12.0
	_panel.offset_right = -12.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	var style := _panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var s := (style as StyleBoxFlat).duplicate() as StyleBoxFlat
		s.border_color = COLOR_FRAME
		s.set_border_width_all(2)
		s.bg_color = Color(s.bg_color, 0.97)
		_panel.add_theme_stylebox_override("panel", s)
	_root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	_chapter = _label(15, COLOR_CHAPTER)
	_chapter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chapter.clip_text = true
	head.add_child(_chapter)
	_progress_label = _label(15, COLOR_HINT)
	_progress_label.mouse_filter = Control.MOUSE_FILTER_STOP
	head.add_child(_progress_label)
	_min_button = _button("–", "Tutorial einklappen")
	_min_button.custom_minimum_size = Vector2(30, 0)
	_min_button.pressed.connect(func() -> void: system.set_minimized(not system.minimized))
	head.add_child(_min_button)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	box.add_child(_body)
	_title = _label(21, Color(1.0, 0.92, 0.7))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(PANEL_WIDTH - 28.0, 0)
	_text.add_theme_font_size_override("normal_font_size", 16)
	_text.add_theme_font_size_override("bold_font_size", 16)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_text)
	_status = _label(16, COLOR_HINT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_bar)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	_body.add_child(buttons)
	_show_button = _button("Zeigen", "Kamera zur Stelle des Pfeils")
	_show_button.pressed.connect(_on_show_pressed)
	buttons.add_child(_show_button)
	_skip_button = _button("Überspringen", "Diesen Schritt auslassen (dauert sonst eine Weile)")
	_skip_button.pressed.connect(func() -> void: system.skip())
	buttons.add_child(_skip_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_child(spacer)
	_end_button = _button("Beenden", "Tutorial beenden (zweimal klicken) – im Spielmenü (Esc) fortsetzbar")
	_end_button.pressed.connect(_on_end_pressed)
	buttons.add_child(_end_button)
	_next_button = _button("Weiter", "Zum nächsten Schritt")
	_next_button.pressed.connect(func() -> void: system.advance())
	buttons.add_child(_next_button)
	_panel.minimum_size_changed.connect(_place_panel, CONNECT_DEFERRED)


## Fenster rechts unten über die Zauberleiste stellen (wächst nach oben, damit lange Texte
## die Meldungen oben rechts möglichst wenig verdecken)
func _place_panel() -> void:
	if _panel == null or not is_inside_tree():
		return
	var s := maxf(scale.y, 0.01)
	var bottom := _root.size.y - PANEL_BOTTOM_FALLBACK
	var st: Variant = game.get("spell_targeting") if game != null else null
	var bar: Variant = st.get("bar") if st is Object else null
	if bar is Control and (bar as Control).is_visible_in_tree():
		bottom = (bar as Control).get_global_transform_with_canvas().origin.y / s - PANEL_GAP
	elif game != null and game.hud != null and game.hud.get("minimap") is Control:
		var mm: Control = game.hud.minimap
		bottom = mm.get_global_transform_with_canvas().origin.y / s - PANEL_GAP - 30.0
	var h := _panel.get_combined_minimum_size().y
	var top := clampf(bottom - h, PANEL_MIN_TOP, maxf(_root.size.y - h - 8.0, PANEL_MIN_TOP))
	if not is_equal_approx(_panel.offset_top, top):
		_panel.offset_top = top
		_panel.offset_bottom = top + h


func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	return b


# ---------------------------------------------------------------------------
# Aktualisieren
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_frame.queue_redraw()
	_timer += delta
	if _timer >= REFRESH_INTERVAL:
		_timer = 0.0
		_refresh_status()


## Ganzes Fenster neu (Schrittwechsel, Zustand)
func _refresh() -> void:
	if system == null:
		return
	var want: bool = system.is_running() and game.hud != null and game.hud.visible
	if visible != want:
		visible = want
	_frame_layer.visible = want and not system.minimized
	if not want:
		return
	var s := system.get_step()
	var id := str(s.get("id", ""))
	if id != _shown_step:
		_shown_step = id
		_end_confirm_ms = -100000
	_chapter.text = str(s.get("chapter", "Tutorial"))
	_progress_label.text = "Schritt %d/%d" % [system.get_step_number(), system.get_step_count()]
	_progress_label.tooltip_text = "Tutorial – %s" % ("Gegner und Ereignisse verschonen dich, solange es läuft" if system.is_protecting() else "ohne Schutz vor Gegnern")
	_title.text = str(s.get("title", ""))
	_text.text = system.format_text(str(s.get("text", "")))
	_bar.max_value = maxf(float(system.get_step_count()), 1.0)
	_bar.value = float(system.get_step_number() - 1)
	_body.visible = not system.minimized
	_min_button.text = "+" if system.minimized else "–"
	_min_button.tooltip_text = "Tutorial aufklappen" if system.minimized else "Tutorial einklappen"
	_skip_button.visible = bool(s.get("skippable", false))
	_show_button.visible = _world_pos() is Vector2
	_refresh_status()
	_place_panel()


## Aufgabe/erledigt, Zustand der Knöpfe (alle REFRESH_INTERVAL)
func _refresh_status() -> void:
	if system == null or not system.is_running():
		return
	var s := system.get_step()
	var has_cond := not str(s.get("condition", "")).is_empty()
	var text := ""
	var color := COLOR_HINT
	if has_cond and system.is_step_done():
		text = "✓ Geschafft!"
		color = COLOR_DONE
	elif has_cond:
		text = "Aufgabe läuft …" if not bool(s.get("skippable", false)) else "Aufgabe läuft … (oder überspringen)"
	if _status.text != text:
		_status.text = text
	_status.add_theme_color_override("font_color", color)
	_status.visible = not text.is_empty()
	var can_next := not has_cond or system.is_step_done()
	_next_button.disabled = not can_next
	var next_text := "Abschliessen" if system.is_last_step() else "Weiter"
	if _next_button.text != next_text:
		_next_button.text = next_text
	_next_button.tooltip_text = ("Tutorial abschliessen" if system.is_last_step() else "Zum nächsten Schritt") if can_next \
			else "Erst die Aufgabe erledigen – oder „Überspringen“, wenn es den Knopf gibt"
	if _end_button.text != "Beenden" and Time.get_ticks_msec() - _end_confirm_ms > CONFIRM_MS:
		_end_button.text = "Beenden"
	_place_panel()


func _on_end_pressed() -> void:
	var now := Time.get_ticks_msec()
	if now - _end_confirm_ms <= CONFIRM_MS:
		_end_confirm_ms = -100000
		_end_button.text = "Beenden"
		system.abort()
		return
	_end_confirm_ms = now
	_end_button.text = "Wirklich?"


func _on_show_pressed() -> void:
	var pos: Variant = _world_pos()
	if pos is Vector2:
		game.camera.focus_on(pos)


## Stelle des Pfeils (world:… in highlight oder world), sonst null
func _world_pos() -> Variant:
	var s := system.get_step()
	for key in ["world", "highlight"]:
		var spec := str(s.get(key, ""))
		if spec.begins_with("world:"):
			return system.world_target(spec)
	return null


# ---------------------------------------------------------------------------
# Ziele im HUD
# ---------------------------------------------------------------------------

## Bedienelemente des Schritts (leer, wenn keins sichtbar ist); mehrere = gemeinsamer Rahmen
func get_target_controls() -> Array:
	var spec := str(system.get_step().get("highlight", ""))
	if spec.is_empty() or spec.begins_with("world:"):
		return []
	var hud: Node = game.hud
	if hud == null:
		return []
	var list: Array = []
	var kind := spec.get_slice(":", 0)
	var arg := spec.get_slice(":", 1) if spec.contains(":") else ""
	match kind:
		"build":
			var menu: Variant = hud.get("build_menu")
			if menu is Object:
				var b: Variant = (menu.get("_buttons") as Dictionary).get(arg, null)
				if b is Control and (b as Control).is_visible_in_tree():
					list.append(b)
				else:
					# Knopf liegt in einem anderen Reiter: den Reiter zeigen
					var def: Dictionary = DataDB.get_building(arg)
					var tab: Variant = (menu.get("_tab_buttons") as Dictionary).get(BuildMenu.category_of(def), null)
					if tab is Control:
						list.append(tab)
		"top":
			var names := {"research": "_research_button", "heroes": "_hero_button", "army": "_troop_button",
					"diplomacy": "_diplomacy_button", "espionage": "_espionage_button", "kingdom": "_kingdom_button"}
			list.append(hud.get(str(names.get(arg, ""))) if names.has(arg) else null)
		"job":
			var panel: Variant = hud.get("job_panel")
			if panel is Object:
				for row in panel.get("_rows"):
					if str(row.get("id", "")) == arg:
						list.append(row.get("name_box"))
						list.append(row.get("plus"))
		"summon":
			var sp: Variant = hud.get("selection_panel")
			if sp is Object:
				list.append(sp.get("_summon_box"))
		"spell_bar":
			var st: Variant = game.get("spell_targeting")
			if st is Object:
				list.append(st.get("bar"))
		"selection":
			list.append(hud.get("selection_panel"))
		"stance":
			# Haltung: Zeile im Auswahlfenster, bei offenem Armeefenster auch dessen Knöpfe
			var sel: Variant = hud.get("selection_panel")
			if sel is Object:
				list.append(sel.get("_stance_row"))
			var army: Variant = hud.get("troop_panel")
			if army is Object and army.call("is_open"):
				for b in (army.get("_stance_buttons") as Dictionary).values():
					list.append(b)
		"army_select_all":
			var army_panel: Variant = hud.get("troop_panel")
			if army_panel is Object and army_panel.call("is_open"):
				list.append((army_panel.get("buttons") as Dictionary).get("all"))
		"jobs":
			list.append(hud.get("job_panel"))
		"log":
			list.append(hud.get("_log_button"))
		"speed":
			list.append(hud.get("speed_bar"))
		"resources":
			list.append(hud.get("resource_bar"))
		_:
			list.append(hud.get(kind))
	var out: Array = []
	for c in list:
		if c is Control and is_instance_valid(c) and (c as Control).is_visible_in_tree():
			out.append(c)
	return out


## Rahmen um die Ziele in Koordinaten des Bildschirms (leer = keins)
func get_target_rect() -> Rect2:
	var r := Rect2()
	var first := true
	for c in get_target_controls():
		var ctrl: Control = c
		var xf := ctrl.get_global_transform_with_canvas()
		var cr := Rect2(xf.origin, xf.basis_xform(ctrl.size)).abs()
		r = cr if first else r.merge(cr)
		first = false
	return r


# ---------------------------------------------------------------------------
# Zeichnen (Rahmen, Pfeil)
# ---------------------------------------------------------------------------

func _draw_frame() -> void:
	if system == null or not system.is_running() or system.minimized:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	var rect := get_target_rect()
	if rect.size.x > 0.0:
		var grow := 4.0 + 4.0 * pulse
		var outer := rect.grow(grow + 4.0)
		_frame.draw_rect(outer, Color(COLOR_FRAME, 0.18 + 0.12 * pulse), false, 6.0)
		_frame.draw_rect(rect.grow(grow), Color(COLOR_FRAME, 0.65 + 0.35 * pulse), false, 3.0)
	var pos: Variant = _world_pos()
	if pos is Vector2:
		_draw_world_arrow(pos, pulse)


func _draw_world_arrow(world_pos: Vector2, pulse: float) -> void:
	var vp := _frame.get_viewport_rect().size
	var screen: Vector2 = game.get_viewport().get_canvas_transform() * world_pos
	var margin := 70.0
	var inner := Rect2(Vector2(margin, margin + 40.0), vp - Vector2(margin * 2.0, margin * 2.0 + 40.0))
	var color := Color(COLOR_FRAME, 0.75 + 0.25 * pulse)
	if inner.has_point(screen):
		# Auf dem Bildschirm: Ring und ein wippender Pfeil von oben
		var radius := 34.0 + 6.0 * pulse
		_frame.draw_arc(screen, radius, 0.0, TAU, 40, color, 3.0, true)
		var tip := screen - Vector2(0.0, radius + 6.0 + 8.0 * pulse)
		_draw_arrow(tip, Vector2.DOWN, color)
		return
	# Ausserhalb: Pfeil am Rand in Richtung der Stelle
	var center := vp * 0.5
	var dir := (screen - center).normalized()
	if dir == Vector2.ZERO:
		return
	var t := INF
	if absf(dir.x) > 0.0001:
		t = minf(t, (inner.size.x * 0.5) / absf(dir.x))
	if absf(dir.y) > 0.0001:
		t = minf(t, (inner.size.y * 0.5) / absf(dir.y))
	var edge := inner.get_center() + dir * t
	_draw_arrow(edge + dir * (6.0 * pulse), dir, color)


## Pfeil mit Spitze bei tip in Richtung dir
func _draw_arrow(tip: Vector2, dir: Vector2, color: Color) -> void:
	var side := dir.orthogonal()
	var head := PackedVector2Array([tip, tip - dir * 26.0 + side * 16.0, tip - dir * 26.0 - side * 16.0])
	_frame.draw_colored_polygon(head, color)
	_frame.draw_line(tip - dir * 22.0, tip - dir * 58.0, color, 8.0, true)
	var outline := PackedVector2Array([head[0], head[1], head[2], head[0]])
	_frame.draw_polyline(outline, Color(0.1, 0.06, 0.02, 0.8), 2.0, true)
