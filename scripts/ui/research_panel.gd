## ResearchPanel
##
## Forschungsfenster (Taste R, Button "Forschung (R)" oben, Esc/R schliesst).
## Das Spiel läuft weiter; Klicks in die Welt sperrt das Fenster nur dort, wo
## es liegt.
## - Kopf: laufende Forschung mit Fortschritt, Warteschlange als Chips
##   (Klick = abbrechen, zweiter Klick bestätigt), Hinweis ohne Forschungsstätte
## - Reiter "Forschung": Baum – Spalten = Zweige, Zeilen = Stufen, Linien von
##   der Voraussetzung zur Forschung
## - Reiter "Mana (Kampfpunkte)": Mana-Verbesserungen gegen Kampfpunkte
## Zeigt nur an und ruft ResearchSystem auf. Aktualisiert wird bei Signalen
## und alle 0.25 s, solange das Fenster offen ist.
class_name ResearchPanel
extends PanelContainer

## Fenster wurde geöffnet oder geschlossen
signal toggled(open: bool)

## Grösse bei 1920×1080 (kleinere Fenster: verkleinert, nie ausserhalb)
const DESIGN_WIDTH := 1100.0
const TOP := 112.0
const MARGIN_X := 18.0
const MARGIN_Y := 14.0
const REFRESH_INTERVAL := 0.25
## Zweiter Klick innerhalb dieser Zeit bricht ab
const CONFIRM_MS := 2000
const CARD_HEIGHT := 90.0
const ROW_GAP := 26.0
const COL_GAP := 22.0
const SLOT_GAP := 10.0
const HEADER_HEIGHT := 30.0
const MIN_CARD_WIDTH := 150.0
const MAX_CARD_WIDTH := 240.0

const GOOD_ACCENT := Color("#f3d36b")
const GOOD_LIGHT := Color("#fff3c4")
const EVIL_ACCENT := Color("#8e44ad")
const EVIL_DARK := Color("#5b2a86")
const EVIL_MID := Color("#6c3483")
const EVIL_LIGHT := Color("#d9bdf2")
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.72, 0.69, 0.64)
const COLOR_WARN := Color(1.0, 0.74, 0.36)
const COLOR_BAD := Color(1.0, 0.45, 0.38)


## Zeichenfläche des Baums: Spaltenhintergründe und Verbindungslinien
## (die Karten sind Kinder und liegen darüber).
class TreeCanvas:
	extends Control
	## Spaltenrechtecke
	var columns: Array[Rect2] = []
	## [Voraussetzung (ResearchCard), Forschung (ResearchCard)]
	var links: Array = []
	## [Karte, Text] – Voraussetzung aus einer anderen Spalte
	var cross: Array = []
	var accent := Color.WHITE

	func _draw() -> void:
		for r in columns:
			draw_rect(r, Color(1, 1, 1, 0.035))
			draw_rect(r, Color(accent, 0.16), false, 1.0)
		for l in links:
			var from: ResearchCard = l[0]
			var to: ResearchCard = l[1]
			_draw_link(from.get_bottom_anchor(), to.get_top_anchor(), _link_color(from.state))
		var font := get_theme_default_font()
		for c in cross:
			var card: ResearchCard = c[0]
			draw_string(font, card.position + Vector2(2, -6), str(c[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(accent, 0.85))

	func _link_color(from_state: String) -> Color:
		match from_state:
			"done":
				return Color(ResearchCard.COLOR_DONE, 0.85)
			"active", "queued":
				return Color(ResearchCard.COLOR_ACTIVE, 0.85)
		return Color(0.55, 0.53, 0.5, 0.55)

	## Gerade oder mit Knick, unten ein kleiner Pfeil
	func _draw_link(a: Vector2, b: Vector2, color: Color) -> void:
		var end := b - Vector2(0, 5)
		if absf(a.x - b.x) < 1.0:
			draw_line(a, end, color, 2.0, true)
		else:
			var mid := (a.y + b.y) * 0.5
			draw_polyline(PackedVector2Array([a, Vector2(a.x, mid), Vector2(b.x, mid), end]), color, 2.0, true)
		draw_colored_polygon(PackedVector2Array([b, b + Vector2(-5, -7), b + Vector2(5, -7)]), color)


var game: Node

var _accent := GOOD_ACCENT
var _light := GOOD_LIGHT
var _evil := false
var _timer := 0.0
var _dirty := true
## Laufender Abbruch-Wunsch: Forschung und Zeitpunkt des ersten Klicks
var _confirm_id := ""
var _confirm_ms := 0

var _title: Label
var _tab_tree: Button
var _tab_mana: Button
var _status: Label
var _queue_title: Label
var _chips: HBoxContainer
var _progress: ProgressBar
var _hint: Label
var _pages: MarginContainer
var _tree_page: Control
var _mana_page: VBoxContainer
var _canvas: TreeCanvas
var _footer: Label
var _speed: Label
## Forschungs-ID -> ResearchCard
var _cards: Dictionary = {}
## Spalten-Überschriften: Zweig-ID -> Label
var _branch_labels: Dictionary = {}
## Zweig-ID -> Forschungs-IDs (für "2/4 erforscht")
var _branch_ids: Dictionary = {}
## Warteschlange, für die die Chips gebaut sind
var _chip_queue: Array = []
## Kampfpunkte-Seite
var _kp_label: Label
var _mana_label: Label
var _cap_label: Label
## Verbesserungs-ID -> {"level": Label, "pips": Control, "cost": Label, "button": Button}
var _upgrade_rows: Dictionary = {}
var _card_styles: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


func setup(p_game: Node) -> void:
	game = p_game
	var k: Kingdom = game.player
	_evil = k.faction_id == "evil"
	_accent = EVIL_ACCENT if _evil else GOOD_ACCENT
	_light = EVIL_LIGHT if _evil else GOOD_LIGHT
	add_theme_stylebox_override("panel", _panel_style())
	_card_styles = _make_card_styles()
	_build()
	var rs: ResearchSystem = game.research_system
	rs.queue_changed.connect(_on_research_signal.unbind(1))
	rs.research_completed.connect(_on_research_signal.unbind(2))
	rs.upgrade_bought.connect(_on_research_signal.unbind(3))
	k.resources_changed.connect(_on_resources_changed)
	get_viewport().size_changed.connect(_place)
	_show_page(false)


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	set_process(true)
	_dirty = true
	_refresh()
	_place()
	toggled.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	set_process(false)
	_confirm_id = ""
	toggled.emit(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH_INTERVAL:
		return
	_timer = 0.0
	# Abbruch-Wunsch verfällt nach 2 s
	if not _confirm_id.is_empty() and Time.get_ticks_msec() - _confirm_ms > CONFIRM_MS:
		_confirm_id = ""
	_refresh()


func _on_research_signal() -> void:
	_dirty = true
	if visible:
		_refresh.call_deferred()


## Ressourcen ändern sich sehr oft – nur vormerken, der Takt holt es nach
func _on_resources_changed() -> void:
	_dirty = true


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Titelzeile: Titel, Reiter, Schliessen
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	root.add_child(title_row)
	_title = Label.new()
	_title.text = "Forschung · %s" % ("Schatten" if _evil else "Licht")
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", _evil_or(EVIL_LIGHT, GOOD_ACCENT))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_title.add_theme_constant_override("outline_size", 4)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title)
	var group := ButtonGroup.new()
	_tab_tree = _make_tab("Forschung", group)
	_tab_tree.pressed.connect(_show_page.bind(false))
	title_row.add_child(_tab_tree)
	_tab_mana = _make_tab("Mana (Kampfpunkte)", group)
	_tab_mana.pressed.connect(_show_page.bind(true))
	title_row.add_child(_tab_mana)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, 0)
	title_row.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "Schliessen (R oder Esc)"
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.custom_minimum_size = Vector2(40, 0)
	close_button.pressed.connect(close)
	title_row.add_child(close_button)

	# Kopf: laufende Forschung und Warteschlange
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	status_row.custom_minimum_size = Vector2(0, 30)
	root.add_child(status_row)
	_status = _label(18, COLOR_TEXT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_row.add_child(_status)
	_queue_title = _label(15, COLOR_DIM)
	_queue_title.text = "Warteschlange:"
	status_row.add_child(_queue_title)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 4)
	status_row.add_child(_chips)

	# Fortschritt bzw. Hinweis ohne Forschungsstätte (gleiche Zeile)
	var bar_row := MarginContainer.new()
	bar_row.custom_minimum_size = Vector2(0, 14)
	root.add_child(bar_row)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.custom_minimum_size = Vector2(0, 12)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.add_theme_stylebox_override("background", _flat(Color(0.04, 0.05, 0.08, 0.9), Color(1, 1, 1, 0.12), 1, 3))
	_progress.add_theme_stylebox_override("fill", _flat(ResearchCard.COLOR_ACTIVE, ResearchCard.COLOR_ACTIVE.lightened(0.3), 0, 3))
	bar_row.add_child(_progress)
	_hint = _label(17, COLOR_WARN)
	_hint.visible = false
	bar_row.add_child(_hint)

	var sep := ColorRect.new()
	sep.color = Color(_accent, 0.45)
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sep)

	# Seiten
	_pages = MarginContainer.new()
	_pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_pages)
	_tree_page = Control.new()
	_tree_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pages.add_child(_tree_page)
	_build_tree()
	_pages.custom_minimum_size = Vector2(0, _canvas.custom_minimum_size.y)
	_mana_page = VBoxContainer.new()
	_mana_page.add_theme_constant_override("separation", 10)
	_mana_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pages.add_child(_mana_page)
	_build_mana_page()

	# Fusszeile: Bedienung, Forschungstempo
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 12)
	root.add_child(footer_row)
	_footer = _label(14, COLOR_DIM)
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(_footer)
	_speed = _label(14, COLOR_DIM)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer_row.add_child(_speed)


## Forschungsbaum: Spalten = Zweige (research_branches), Zeilen = Stufen.
## Zweige mit mehreren Forschungen auf einer Stufe werden breiter.
func _build_tree() -> void:
	var k: Kingdom = game.player
	var rs: ResearchSystem = game.research_system
	var width := DESIGN_WIDTH - MARGIN_X * 2.0
	_canvas = TreeCanvas.new()
	_canvas.accent = _accent if not _evil else EVIL_LIGHT
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree_page.add_child(_canvas)

	# Zweig -> Stufe -> Forschungen (Datenreihenfolge)
	var branch_ids: Array[String] = []
	var branch_names: Dictionary = {}
	for b in DataDB.research_branches:
		var bid := str(b.get("id", ""))
		branch_ids.append(bid)
		branch_names[bid] = str(b.get("name", bid))
	var by_branch: Dictionary = {}
	var max_tier := 1
	for r in rs.get_tree_for(k):
		var def: Dictionary = r
		var bid := str(def.get("branch", ""))
		if not branch_names.has(bid):
			# Unbekannter Zweig: eigene Spalte statt verschwinden
			branch_ids.append(bid)
			branch_names[bid] = bid
		if not by_branch.has(bid):
			by_branch[bid] = {}
		var tiers: Dictionary = by_branch[bid]
		var tier := maxi(int(def.get("tier", 1)), 1)
		max_tier = maxi(max_tier, tier)
		if not tiers.has(tier):
			tiers[tier] = []
		(tiers[tier] as Array).append(def)

	# Kartenbreite: alle Plätze teilen sich die Breite
	var slots: Array[int] = []
	var total_slots := 0
	var inner_gaps := 0.0
	for bid in branch_ids:
		var n := 1
		var tiers: Dictionary = by_branch.get(bid, {})
		for t in tiers:
			n = maxi(n, (tiers[t] as Array).size())
		slots.append(n)
		total_slots += n
		inner_gaps += (n - 1) * SLOT_GAP
	var free := width - (branch_ids.size() - 1) * COL_GAP - inner_gaps
	var card_w := clampf(floorf(free / float(maxi(total_slots, 1))), MIN_CARD_WIDTH, MAX_CARD_WIDTH)
	var used := total_slots * card_w + inner_gaps + (branch_ids.size() - 1) * COL_GAP
	var x := floorf((width - used) * 0.5)
	var height := HEADER_HEIGHT + max_tier * CARD_HEIGHT + (max_tier - 1) * ROW_GAP + 6.0
	_canvas.custom_minimum_size = Vector2(width, height)
	_canvas.size = Vector2(width, height)

	for i in branch_ids.size():
		var bid := branch_ids[i]
		var col_w := slots[i] * card_w + (slots[i] - 1) * SLOT_GAP
		_canvas.columns.append(Rect2(x - 6.0, 0.0, col_w + 12.0, height))
		var head := _label(17, _light if not _evil else EVIL_LIGHT)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.position = Vector2(x, 3.0)
		head.size = Vector2(col_w, HEADER_HEIGHT - 6.0)
		_canvas.add_child(head)
		_branch_labels[bid] = head
		var ids: Array[String] = []
		var tiers: Dictionary = by_branch.get(bid, {})
		for tier in range(1, max_tier + 1):
			var list: Array = tiers.get(tier, [])
			if list.is_empty():
				continue
			var y := HEADER_HEIGHT + (tier - 1) * (CARD_HEIGHT + ROW_GAP)
			var total := list.size() * card_w + (list.size() - 1) * SLOT_GAP
			var start := x + (col_w - total) * 0.5
			for j in list.size():
				var def: Dictionary = list[j]
				var cx := start + j * (card_w + SLOT_GAP)
				# Einzelne Forschung unter ihrer einzigen Voraussetzung (gleiche Spalte)
				var reqs: Array = def.get("requires", [])
				if list.size() == 1 and reqs.size() == 1 and _cards.has(str(reqs[0])):
					var parent: ResearchCard = _cards[str(reqs[0])]
					if str(DataDB.get_research(str(reqs[0])).get("branch", "")) == bid:
						cx = parent.position.x
				var card := ResearchCard.new()
				_canvas.add_child(card)
				card.setup(def, _card_effect_text(k, def), Vector2(card_w, CARD_HEIGHT), _accent, _card_styles)
				card.position = Vector2(cx, y)
				var rid := str(def.get("id", ""))
				card.tip_source = _card_tip.bind(rid)
				card.activated.connect(_on_card_activated)
				_cards[rid] = card
				ids.append(rid)
		_branch_ids[bid] = ids
		x += col_w + COL_GAP

	# Verbindungen (erst jetzt sind alle Karten da)
	for rid in _cards:
		var card: ResearchCard = _cards[rid]
		var def := DataDB.get_research(str(rid))
		for req in def.get("requires", []):
			var from: ResearchCard = _cards.get(str(req))
			if from == null:
				continue
			if str(DataDB.get_research(str(req)).get("branch", "")) == str(def.get("branch", "")):
				_canvas.links.append([from, card])
			else:
				_canvas.cross.append([card, "← " + str(DataDB.get_research(str(req)).get("name", req))])


func _build_mana_page() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 40)
	_mana_page.add_child(top)
	_kp_label = _label(22, _evil_or(EVIL_LIGHT, GOOD_ACCENT))
	top.add_child(_kp_label)
	_mana_label = _label(20, Color("#c9a8ff"))
	top.add_child(_mana_label)
	_cap_label = _label(16, COLOR_DIM)
	_mana_page.add_child(_cap_label)
	var space := Control.new()
	space.custom_minimum_size = Vector2(0, 4)
	_mana_page.add_child(space)

	var rs: ResearchSystem = game.research_system
	for up in rs.get_upgrades():
		var uid := str(up.get("id", ""))
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _card_styles.get("available"))
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		_mana_page.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 24)
		row.add_child(h)
		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_box.add_theme_constant_override("separation", 2)
		h.add_child(text_box)
		var name_label := _label(19, COLOR_TEXT)
		name_label.text = str(up.get("name", uid))
		text_box.add_child(name_label)
		var desc := _label(15, COLOR_DIM)
		desc.text = str(up.get("description", ""))
		text_box.add_child(desc)
		var level_box := VBoxContainer.new()
		level_box.custom_minimum_size = Vector2(150, 0)
		level_box.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(level_box)
		var level := _label(17, COLOR_TEXT)
		level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_box.add_child(level)
		var pips := Control.new()
		pips.custom_minimum_size = Vector2(150, 12)
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.draw.connect(_draw_pips.bind(pips, uid))
		level_box.add_child(pips)
		var cost := _label(17, COLOR_TEXT)
		cost.custom_minimum_size = Vector2(190, 0)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(cost)
		var button := ResearchTipButton.new()
		button.text = "Verbessern"
		button.custom_minimum_size = Vector2(150, 44)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.tip_source = _upgrade_tip.bind(uid)
		button.pressed.connect(_on_upgrade_pressed.bind(uid))
		h.add_child(button)
		_upgrade_rows[uid] = {"level": level, "pips": pips, "cost": cost, "button": button}

	var hint := _label(16, COLOR_DIM)
	hint.text = "Kampfpunkte bekommst du für besiegte Monster und zerstörte Höhlen."
	_mana_page.add_child(hint)
	var hint2 := _label(15, COLOR_DIM)
	hint2.text = "Das Mana-Maximum steigt ausserdem durch Forschung im Zweig „Mana“."
	_mana_page.add_child(hint2)


func _make_tab(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(130, 36)
	if _evil:
		# Eingedrückter Reiter violett statt gold
		var pressed := _flat(EVIL_MID, EVIL_LIGHT, 1, 4)
		pressed.content_margin_left = 14
		pressed.content_margin_right = 14
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("hover_pressed", pressed)
	return b


func _show_page(mana: bool) -> void:
	_tab_tree.set_pressed_no_signal(not mana)
	_tab_mana.set_pressed_no_signal(mana)
	_tree_page.visible = not mana
	_mana_page.visible = mana
	_footer.text = ("Verbesserungen wirken sofort und dauerhaft  ·  R / Esc: schliessen" if mana else
			"Klick: erforschen (Kosten sofort)  ·  Klick auf laufende/eingereihte: abbrechen, alles zurück  ·  R / Esc: schliessen")
	_dirty = true
	if visible:
		_refresh()


## Mitte oben; bei kleinem Fenster verkleinert, aber nie ausserhalb
func _place() -> void:
	var vp := get_viewport_rect().size
	var want := Vector2(DESIGN_WIDTH, get_combined_minimum_size().y)
	size = want
	var s := minf(1.0, minf((vp.x - 24.0) / want.x, (vp.y - 60.0) / want.y))
	scale = Vector2(s, s)
	var top := clampf(TOP, 52.0, maxf(vp.y - want.y * s - 8.0, 52.0))
	position = Vector2(floorf((vp.x - want.x * s) * 0.5), floorf(top))


# ---------------------------------------------------------------------------
# Aktualisieren
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if game == null or not visible:
		return
	var k: Kingdom = game.player
	if k == null:
		return
	_refresh_header(k)
	if _tree_page.visible:
		_refresh_tree(k)
	else:
		_refresh_mana(k)
	_dirty = false


func _refresh_header(k: Kingdom) -> void:
	var rs: ResearchSystem = game.research_system
	var active := rs.get_active(k)
	var buildings := rs.count_research_buildings(k)
	var bname := rs.get_research_building_name(k)
	var ratio := rs.get_progress_ratio(k)
	var text := ""
	if not active.is_empty():
		var aname := str(DataDB.get_research(active).get("name", active))
		var remaining := rs.get_remaining_seconds(k)
		if remaining == INF:
			text = "Erforscht: %s – %d %% – angehalten" % [aname, floori(ratio * 100.0)]
		else:
			text = "Erforscht: %s – %d %% – noch %d s" % [aname, floori(ratio * 100.0), ceili(remaining)]
	elif buildings > 0:
		text = "Keine laufende Forschung – klicke unten auf eine Forschung."
	else:
		text = "Keine laufende Forschung"
	_set_text(_status, text)
	var no_building := buildings == 0
	_hint.visible = no_building
	_progress.visible = not no_building
	if no_building:
		_set_text(_hint, "Baue „%s“ (Baumenü), um zu forschen." % bname)
	_progress.value = ratio
	_set_text(_speed, "%d × %s  ·  Tempo %d %%" % [buildings, bname, roundi(rs.get_speed(k) * 100.0)]
			if buildings > 0 else "Keine Forschungsstätte")
	_refresh_chips(k)


## Chips der Warteschlange: neu gebaut nur, wenn sie sich geändert hat
func _refresh_chips(k: Kingdom) -> void:
	var queue: Array = k.research_queue.duplicate()
	if queue != _chip_queue:
		_chip_queue = queue
		for c in _chips.get_children():
			c.queue_free()
		for i in queue.size():
			var rid := str(queue[i])
			var chip := Button.new()
			chip.focus_mode = Control.FOCUS_NONE
			chip.add_theme_font_size_override("font_size", 15)
			chip.custom_minimum_size = Vector2(0, 28)
			chip.tooltip_text = "Abbrechen – Kosten werden erstattet\n(zum Bestätigen zweimal klicken)"
			chip.pressed.connect(_ask_cancel.bind(rid))
			var color := ResearchCard.COLOR_ACTIVE if i == 0 else ResearchCard.COLOR_QUEUED
			var st := _flat(Color(color.darkened(0.7), 0.95), color, 1, 4)
			st.content_margin_left = 9
			st.content_margin_right = 9
			st.content_margin_top = 2
			st.content_margin_bottom = 2
			chip.add_theme_stylebox_override("normal", st)
			var hover := st.duplicate() as StyleBoxFlat
			hover.bg_color = Color(color.darkened(0.5), 0.95)
			chip.add_theme_stylebox_override("hover", hover)
			chip.add_theme_stylebox_override("pressed", hover)
			chip.set_meta("research_id", rid)
			chip.set_meta("index", i)
			_chips.add_child(chip)
	_queue_title.visible = not queue.is_empty()
	for c in _chips.get_children():
		var chip := c as Button
		if chip == null or chip.is_queued_for_deletion():
			continue
		var rid := str(chip.get_meta("research_id", ""))
		var name := str(DataDB.get_research(rid).get("name", rid))
		var confirming := rid == _confirm_id
		var t := ("%d. %s – abbrechen?" % [int(chip.get_meta("index", 0)) + 1, name]) if confirming else \
				"%d. %s  ×" % [int(chip.get_meta("index", 0)) + 1, name]
		if chip.text != t:
			chip.text = t
		var fc := ResearchCard.COLOR_CONFIRM if confirming else COLOR_TEXT
		if chip.get_theme_color("font_color") != fc:
			chip.add_theme_color_override("font_color", fc)
			chip.add_theme_color_override("font_hover_color", fc)


func _refresh_tree(k: Kingdom) -> void:
	var rs: ResearchSystem = game.research_system
	var ratio := rs.get_progress_ratio(k)
	var links_changed := false
	for rid in _cards:
		var card: ResearchCard = _cards[rid]
		var st := rs.get_state(k, str(rid))
		if st != card.state:
			links_changed = true
		var pos := k.research_queue.find(rid) + 1
		card.apply(st, pos, ratio if st == "active" else 0.0, str(rid) == _confirm_id, k)
	for bid in _branch_labels:
		var ids: Array = _branch_ids.get(bid, [])
		var done := 0
		for rid in ids:
			if k.researched.has(rid):
				done += 1
		var name := ""
		for b in DataDB.research_branches:
			if str(b.get("id", "")) == str(bid):
				name = str(b.get("name", bid))
		if name.is_empty():
			name = str(bid)
		_set_text(_branch_labels[bid], "%s  %d/%d" % [name, done, ids.size()])
	if links_changed:
		_canvas.queue_redraw()


func _refresh_mana(k: Kingdom) -> void:
	var rs: ResearchSystem = game.research_system
	_set_text(_kp_label, "Kampfpunkte: %d (gesamt %d)" % [k.kill_points, k.kill_points_total])
	var regen := "  ·  Burg: +%s pro Sekunde" % _num(k.mana_regen) if k.mana_regen > 0.0 else "  ·  Burg: kein eigenes Mana"
	_set_text(_mana_label, "Mana: %d/%d%s" % [floori(k.get_amount("mana")), floori(k.get_capacity("mana")), regen])
	var parts := mana_cap_parts(k)
	_set_text(_cap_label, "Mana-Maximum %d = Grundwert %d + Forschung %d + Kampfpunkte %d" % [
			floori(k.get_capacity("mana")), roundi(float(parts["base"])), roundi(float(parts["research"])),
			roundi(float(parts["upgrades"]))])
	for up in rs.get_upgrades():
		var uid := str(up.get("id", ""))
		var row: Dictionary = _upgrade_rows.get(uid, {})
		if row.is_empty():
			continue
		var level := rs.get_upgrade_level(k, uid)
		var max_level := (up.get("cost_kill_points", []) as Array).size()
		_set_text(row["level"], "Stufe %d/%d" % [level, max_level])
		var cost := rs.get_upgrade_cost(k, uid)
		var cost_label: Label = row["cost"]
		_set_text(cost_label, "Höchste Stufe" if cost < 0 else "%d Kampfpunkte" % cost)
		var c := COLOR_DIM if cost < 0 else (COLOR_BAD if k.kill_points < cost else COLOR_TEXT)
		if cost_label.get_theme_color("font_color") != c:
			cost_label.add_theme_color_override("font_color", c)
		var button: Button = row["button"]
		var reason := rs.can_buy_upgrade(k, uid)
		button.disabled = not reason.is_empty()
		button.tooltip_text = reason
		(row["pips"] as Control).queue_redraw()


## Mana-Maximum aufgeteilt: Grundwert, Forschung, Kampfpunkte
static func mana_cap_parts(k: Kingdom) -> Dictionary:
	var research := 0.0
	for rid in k.researched:
		for e in DataDB.get_research(str(rid)).get("effects", []):
			if str(e.get("type", "")) == "mana_cap":
				research += float(e.get("add", 0.0))
	var upgrades := 0.0
	for up in DataDB.mag("upgrades", []):
		var level := int(k.mana_upgrades.get(str(up.get("id", "")), 0))
		upgrades += float((up.get("per_level", {}) as Dictionary).get("mana_cap", 0.0)) * level
	var total := k.get_capacity("mana")
	return {"base": total - research - upgrades, "research": research, "upgrades": upgrades}


func _draw_pips(pips: Control, uid: String) -> void:
	if game == null:
		return
	var rs: ResearchSystem = game.research_system
	var k: Kingdom = game.player
	var max_level := 0
	for up in rs.get_upgrades():
		if str(up.get("id", "")) == uid:
			max_level = (up.get("cost_kill_points", []) as Array).size()
	if max_level <= 0:
		return
	var level := rs.get_upgrade_level(k, uid)
	var w := 20.0
	var gap := 5.0
	var total := max_level * w + (max_level - 1) * gap
	var x0 := (pips.size.x - total) * 0.5
	var fill := _evil_or(EVIL_LIGHT, GOOD_ACCENT)
	for i in max_level:
		var r := Rect2(x0 + i * (w + gap), 2.0, w, 8.0)
		pips.draw_rect(r, fill if i < level else Color(1, 1, 1, 0.1))
		pips.draw_rect(r, Color(fill, 0.6), false, 1.0)


# ---------------------------------------------------------------------------
# Klicks
# ---------------------------------------------------------------------------

func _on_card_activated(rid: String) -> void:
	var k: Kingdom = game.player
	var rs: ResearchSystem = game.research_system
	match rs.get_state(k, rid):
		"done":
			pass
		"active", "queued":
			_ask_cancel(rid)
			return
		_:
			var reason := rs.can_start(k, rid)
			if reason.is_empty():
				rs.start(k, rid)
			else:
				Notify.warning(reason)
	_confirm_id = ""
	_refresh()


## Erster Klick: nachfragen (Karte/Chip rot), zweiter Klick innerhalb 2 s: abbrechen
func _ask_cancel(rid: String) -> void:
	var k: Kingdom = game.player
	var now := Time.get_ticks_msec()
	if _confirm_id == rid and now - _confirm_ms <= CONFIRM_MS:
		_confirm_id = ""
		if k.research_queue.has(rid):
			game.research_system.cancel(k, rid)
			Notify.info("Forschung abgebrochen: %s – Kosten erstattet" % str(DataDB.get_research(rid).get("name", rid)))
	else:
		_confirm_id = rid
		_confirm_ms = now
	_refresh()


func _on_upgrade_pressed(uid: String) -> void:
	var k: Kingdom = game.player
	var rs: ResearchSystem = game.research_system
	var reason := rs.can_buy_upgrade(k, uid)
	if not reason.is_empty():
		Notify.warning(reason)
		return
	if rs.buy_upgrade(k, uid):
		for up in rs.get_upgrades():
			if str(up.get("id", "")) == uid:
				Notify.good("%s: Stufe %d" % [str(up.get("name", uid)), rs.get_upgrade_level(k, uid)])
	_refresh()


# ---------------------------------------------------------------------------
# Texte
# ---------------------------------------------------------------------------

## Kurze Wirkung für die Karte ("Neu: Ritter", "+10 % Angriff (Kämpfer)")
func _card_effect_text(k: Kingdom, def: Dictionary) -> String:
	var parts: PackedStringArray = []
	var unlocks: PackedStringArray = []
	for line in game.research_system.describe_effects(k, str(def.get("id", ""))):
		var s := str(line)
		if s.begins_with("Schaltet frei: "):
			unlocks.append(s.trim_prefix("Schaltet frei: "))
		else:
			parts.append(s)
	if not unlocks.is_empty():
		parts.insert(0, "Neu: " + ", ".join(unlocks))
	return ", ".join(parts)


## Tooltip einer Forschung (BBCode): Beschreibung, alle Wirkungen, Kosten,
## Dauer, Voraussetzungen (fehlende rot) und warum sie gerade nicht startet.
func _card_tip(rid: String) -> String:
	if game == null:
		return ""
	var k: Kingdom = game.player
	var rs: ResearchSystem = game.research_system
	var def := DataDB.get_research(rid)
	var st := rs.get_state(k, rid)
	var tip := ResearchTipButton
	var lines: PackedStringArray = []
	var branch := ""
	for b in DataDB.research_branches:
		if str(b.get("id", "")) == str(def.get("branch", "")):
			branch = str(b.get("name", ""))
	lines.append("[b]%s[/b]  %s" % [tip.colored(str(def.get("name", rid)), _evil_or(EVIL_LIGHT, GOOD_ACCENT)),
			tip.colored("%s · Stufe %d" % [branch, int(def.get("tier", 1))], COLOR_DIM)])
	var desc := str(def.get("description", ""))
	if not desc.is_empty():
		lines.append(tip.esc(desc))
	for e in rs.describe_effects(k, rid):
		lines.append("• " + tip.colored(str(e), Color(0.7, 0.9, 1.0)))
	var cost: Dictionary = def.get("cost", {})
	lines.append("Kosten: " + tip.esc(DataDB.cost_to_text(cost)))
	if st == "available" or st == "locked":
		var missing := k.missing_text(cost)
		if not missing.is_empty():
			lines.append(tip.colored(missing, COLOR_BAD))
	var time := float(def.get("time", 0.0))
	var speed := rs.get_speed(k)
	var time_text := "Dauer: %d s" % roundi(time)
	if speed > 0.0 and not is_equal_approx(speed, 1.0):
		time_text += " (bei Tempo %d %%: %d s)" % [roundi(speed * 100.0), ceili(time / speed)]
	lines.append(time_text)
	var reqs: Array = def.get("requires", [])
	if not reqs.is_empty():
		var parts: PackedStringArray = []
		for req in reqs:
			var rname := str(DataDB.get_research(str(req)).get("name", req))
			if k.researched.has(req):
				parts.append(tip.colored(rname + " (erforscht)", ResearchCard.COLOR_DONE))
			elif k.research_queue.has(req):
				parts.append(tip.colored(rname + " (in der Warteschlange)", ResearchCard.COLOR_ACTIVE))
			else:
				parts.append(tip.colored(rname + " – fehlt", COLOR_BAD))
		lines.append("Voraussetzung: " + ", ".join(parts))
	match st:
		"done":
			lines.append(tip.colored("Erforscht", ResearchCard.COLOR_DONE))
		"active":
			var remaining := rs.get_remaining_seconds(k)
			var rest := "angehalten – keine Forschungsstätte" if remaining == INF else "noch %d s" % ceili(remaining)
			lines.append(tip.colored("Wird erforscht: %d %% – %s" % [floori(rs.get_progress_ratio(k) * 100.0), rest], ResearchCard.COLOR_ACTIVE))
			lines.append(tip.colored("Klick: abbrechen – Kosten werden erstattet", COLOR_DIM))
		"queued":
			lines.append(tip.colored("In der Warteschlange (Platz %d)" % (k.research_queue.find(rid) + 1), ResearchCard.COLOR_QUEUED))
			lines.append(tip.colored("Klick: abbrechen – Kosten werden erstattet", COLOR_DIM))
		_:
			var reason := rs.can_start(k, rid)
			if reason.is_empty():
				lines.append(tip.colored("Klick: erforschen (Kosten werden sofort bezahlt)", ResearchCard.COLOR_DONE))
			elif not reason.begins_with("Es fehlen"):
				# Fehlende Rohstoffe stehen schon oben
				lines.append(tip.colored(reason, COLOR_BAD))
	return "\n".join(lines)


func _upgrade_tip(uid: String) -> String:
	if game == null:
		return ""
	var k: Kingdom = game.player
	var rs: ResearchSystem = game.research_system
	var reason := rs.can_buy_upgrade(k, uid)
	if reason.is_empty():
		return "Für %d Kampfpunkte verbessern" % rs.get_upgrade_cost(k, uid)
	return ResearchTipButton.colored(reason, COLOR_BAD)


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

func _make_card_styles() -> Dictionary:
	var avail_bg := Color(0.15, 0.11, 0.2, 0.97) if _evil else Color(0.19, 0.165, 0.12, 0.97)
	var avail_border := EVIL_ACCENT.lightened(0.15) if _evil else GOOD_ACCENT.darkened(0.25)
	var hover_border := EVIL_LIGHT if _evil else GOOD_LIGHT
	var styles := {}
	styles["available"] = _flat(avail_bg, avail_border, 1, 6)
	styles["available_hover"] = _flat(avail_bg.lightened(0.08), hover_border, 2, 6)
	styles["locked"] = _flat(Color(0.1, 0.1, 0.11, 0.95), Color(0.3, 0.29, 0.31), 1, 6)
	styles["locked_hover"] = _flat(Color(0.13, 0.13, 0.14, 0.95), Color(0.45, 0.44, 0.46), 1, 6)
	styles["done"] = _flat(Color(0.09, 0.17, 0.1, 0.97), ResearchCard.COLOR_DONE, 2, 6)
	styles["done_hover"] = _flat(Color(0.11, 0.21, 0.12, 0.97), ResearchCard.COLOR_DONE.lightened(0.3), 2, 6)
	styles["active"] = _flat(Color(0.08, 0.14, 0.24, 0.97), ResearchCard.COLOR_ACTIVE, 2, 6)
	styles["active_hover"] = _flat(Color(0.1, 0.17, 0.29, 0.97), ResearchCard.COLOR_ACTIVE.lightened(0.3), 2, 6)
	styles["queued"] = _flat(Color(0.1, 0.13, 0.2, 0.97), ResearchCard.COLOR_QUEUED, 1, 6)
	styles["queued_hover"] = _flat(Color(0.12, 0.16, 0.24, 0.97), ResearchCard.COLOR_QUEUED.lightened(0.3), 2, 6)
	styles["confirm"] = _flat(Color(0.22, 0.08, 0.07, 0.97), ResearchCard.COLOR_CONFIRM, 2, 6)
	styles["confirm_hover"] = _flat(Color(0.28, 0.1, 0.09, 0.97), ResearchCard.COLOR_CONFIRM.lightened(0.2), 2, 6)
	for key in styles:
		var st: StyleBoxFlat = styles[key]
		st.content_margin_left = 12
		st.content_margin_right = 12
		st.content_margin_top = 8
		st.content_margin_bottom = 8
	return styles


func _panel_style() -> StyleBoxFlat:
	var bg := Color(0.075, 0.05, 0.105, 0.97) if _evil else Color(0.1, 0.088, 0.07, 0.97)
	var st := _flat(bg, _accent, 2, 8)
	st.content_margin_left = MARGIN_X
	st.content_margin_right = MARGIN_X
	st.content_margin_top = MARGIN_Y
	st.content_margin_bottom = MARGIN_Y
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 14
	if _evil:
		# Dunkles Violett leuchtet von innen ein wenig
		st.border_blend = true
	return st


static func _flat(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(border_width)
	st.set_corner_radius_all(radius)
	st.anti_aliasing = true
	return st


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


func _evil_or(evil_color: Color, good_color: Color) -> Color:
	return evil_color if _evil else good_color


static func _num(v: float) -> String:
	var s := "%.2f" % v
	return s.trim_suffix("0").trim_suffix(".0") if s.ends_with("0") else s
