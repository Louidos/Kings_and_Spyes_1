## ResearchPanel
##
## Forschungsfenster (Taste R, Button "Forschung (R)" oben; R, Esc oder × schliesst).
## Das Spiel läuft weiter; Klicks in die Welt sperrt das Fenster nur dort, wo
## es liegt.
## - Kopf: laufende Forschung mit Fortschritt, Warteschlange als Chips
##   (Klick = abbrechen, zweiter Klick bestätigt), Hinweis ohne Forschungsstätte
## - Reiter "Forschung": Baum – Spalten = Zweige, Zeilen = Stufen, Linien von
##   der Voraussetzung zur Forschung
## - Reiter "Kampfpunkte": Manakristall/Manaherz gegen Kampfpunkte
## Zeigt nur an und ruft ResearchSystem auf. Aktualisiert wird bei Signalen
## und alle 0.25 s, solange das Fenster offen ist.
class_name ResearchPanel
extends PanelContainer

## Fenster wurde geöffnet oder geschlossen
signal toggled(open: bool)

const TAB_TREE := "tree"
const TAB_POINTS := "points"

## Breite bei 1920×1080: passt zwischen Auswahlfenster (links) und Meldungen
## (rechts). Kleinere Fenster: verkleinert, nie ausserhalb.
const DESIGN_WIDTH := 1048.0
const TOP := 92.0
const MARGIN_X := 16.0
const MARGIN_Y := 12.0
const REFRESH_INTERVAL := 0.25
## Zweiter Klick innerhalb dieser Zeit bricht ab
const CONFIRM_MS := 2000
const CARD_HEIGHT := 102.0
const ROW_GAP := 22.0
const COL_GAP := 16.0
const SLOT_GAP := 8.0
const HEADER_HEIGHT := 30.0
const MIN_CARD_WIDTH := 150.0
const MAX_CARD_WIDTH := 230.0

const GOOD_ACCENT := Color("#f3d36b")
const GOOD_LIGHT := Color("#fff3c4")
const EVIL_ACCENT := Color("#8e44ad")
const EVIL_DARK := Color("#5b2a86")
const EVIL_MID := Color("#6c3483")
const EVIL_LIGHT := Color("#d9bdf2")
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.74, 0.71, 0.66)
const COLOR_WARN := Color(1.0, 0.82, 0.35)
const COLOR_BAD := Color(1.0, 0.45, 0.38)
const COLOR_GOOD := Color(0.55, 0.88, 0.5)
const COLOR_MANA := Color("#c9a8ff")


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
			draw_rect(r, Color(1, 1, 1, 0.03))
			draw_rect(r, Color(accent, 0.18), false, 1.0)
			# Kopfleiste der Spalte
			draw_rect(Rect2(r.position, Vector2(r.size.x, 28.0)), Color(accent, 0.1))
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
				return Color(ResearchCard.COLOR_DONE, 0.9)
			"active", "queued":
				return Color(ResearchCard.COLOR_ACTIVE, 0.9)
		return Color(0.6, 0.58, 0.55, 0.55)

	## Gerade oder mit Knick in der Lücke zwischen den Zeilen, unten ein Pfeil
	func _draw_link(a: Vector2, b: Vector2, color: Color) -> void:
		var end := b - Vector2(0, 6)
		if absf(a.x - b.x) < 1.0:
			draw_line(a, end, color, 2.0, true)
		else:
			var mid := floorf((a.y + b.y) * 0.5)
			draw_polyline(PackedVector2Array([a, Vector2(a.x, mid), Vector2(b.x, mid), end]), color, 2.0, true)
		draw_colored_polygon(PackedVector2Array([b, b + Vector2(-5, -7), b + Vector2(5, -7)]), color)


## Kleines Wappen vor dem Titel: Sonne (GUT) bzw. Mondsichel (BÖSE)
class Emblem:
	extends Control
	var evil := false
	var color := Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		if evil:
			draw_circle(c, r, color)
			draw_circle(c + Vector2(r * 0.42, -r * 0.18), r * 0.86, Color(0.075, 0.05, 0.105))
			draw_circle(c + Vector2(-r * 0.15, r * 0.55), 1.6, Color(color, 0.8))
		else:
			for i in 8:
				var dir := Vector2.from_angle(TAU * i / 8.0)
				draw_line(c + dir * r * 0.55, c + dir * r, color, 2.0, true)
			draw_circle(c, r * 0.42, color)


## Stufen einer Verbesserung als kleine Kästchen
class Pips:
	extends Control
	var level := 0
	var max_level := 0
	var color := Color.WHITE

	func _draw() -> void:
		if max_level <= 0:
			return
		var w := 20.0
		var gap := 5.0
		var total := max_level * w + (max_level - 1) * gap
		var x0 := floorf((size.x - total) * 0.5)
		for i in max_level:
			var r := Rect2(x0 + i * (w + gap), 2.0, w, 8.0)
			draw_rect(r, color if i < level else Color(1, 1, 1, 0.08))
			draw_rect(r, Color(color, 0.6), false, 1.0)


var game: Node

var _accent := GOOD_ACCENT
var _light := GOOD_LIGHT
var _evil := false
var _tab := TAB_TREE
var _timer := 0.0
## Laufender Abbruch-Wunsch: Forschung und Zeitpunkt des ersten Klicks
var _confirm_id := ""
var _confirm_ms := 0

var _tab_tree: Button
var _tab_points: ResearchTipButton
var _status: Label
var _queue_title: Label
var _chips: HBoxContainer
var _progress: ProgressBar
var _hint: Label
var _hint_row: HBoxContainer
var _build_button: Button
var _tree_page: Control
var _points_page: VBoxContainer
var _canvas: TreeCanvas
var _footer: Label
var _speed: Label
## Forschungs-ID -> ResearchCard
var _cards: Dictionary = {}
## Zweig-ID -> Überschrift (Label)
var _branch_labels: Dictionary = {}
## Zweig-ID -> Name
var _branch_names: Dictionary = {}
## Zweig-ID -> Forschungs-IDs (für "2/4")
var _branch_ids: Dictionary = {}
## Warteschlange, für die die Chips gebaut sind
var _chip_queue: Array = []
## Kampfpunkte-Seite
var _kp_label: Label
var _kp_total: Label
var _mana_label: Label
var _mana_rate: Label
var _info_cap: Label
var _info_income: Label
var _info_sources: Label
## Verbesserungs-ID -> {"level", "now", "pips", "next_title", "next", "cost", "button"}
var _upgrade_rows: Dictionary = {}
var _card_styles: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


## Aufbauen (das Fenster muss schon im Baum hängen)
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
	rs.queue_changed.connect(_on_queue_changed)
	rs.research_completed.connect(_on_research_completed)
	rs.upgrade_bought.connect(_on_upgrade_bought)
	get_viewport().size_changed.connect(_place)
	_show_tab(TAB_TREE)


func is_open() -> bool:
	return visible


## Öffnen, optional auf einem Reiter (TAB_TREE / TAB_POINTS)
func open(tab: String = "") -> void:
	if not tab.is_empty():
		_show_tab(tab)
	if visible:
		return
	visible = true
	set_process(true)
	_timer = 0.0
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


func get_tab() -> String:
	return _tab


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH_INTERVAL:
		return
	_timer = 0.0
	# Abbruch-Wunsch verfällt nach 2 s
	if not _confirm_id.is_empty() and Time.get_ticks_msec() - _confirm_ms > CONFIRM_MS:
		_confirm_id = ""
	_refresh()


func _on_queue_changed(k: Kingdom) -> void:
	_on_player_changed(k)


func _on_research_completed(k: Kingdom, _id: String) -> void:
	_on_player_changed(k)


func _on_upgrade_bought(k: Kingdom, _id: String, _level: int) -> void:
	_on_player_changed(k)


## Signale gelten für alle Reiche – nur der Spieler zählt
func _on_player_changed(k: Kingdom) -> void:
	if visible and k == game.player:
		_refresh.call_deferred()


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Titelzeile: Wappen, Titel, Reiter, Schliessen
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_row)
	var emblem := Emblem.new()
	emblem.evil = _evil
	emblem.color = _evil_or(EVIL_LIGHT, GOOD_ACCENT)
	emblem.custom_minimum_size = Vector2(26, 26)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(emblem)
	var title := _label(25, _evil_or(EVIL_LIGHT, GOOD_ACCENT))
	title.text = "Forschung · %s" % ("Schatten" if _evil else "Licht")
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	title.add_theme_constant_override("outline_size", 4)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var group := ButtonGroup.new()
	_tab_tree = _make_tab("Forschung", group)
	_tab_tree.tooltip_text = "Forschungsbaum"
	_tab_tree.pressed.connect(_show_tab.bind(TAB_TREE))
	title_row.add_child(_tab_tree)
	_tab_points = _make_tab("Kampfpunkte", group)
	_tab_points.badge_color = _evil_or(Color("#e07bff"), Color(1.0, 0.62, 0.18))
	_tab_points.tip_source = _points_tab_tip
	_tab_points.pressed.connect(_show_tab.bind(TAB_POINTS))
	title_row.add_child(_tab_points)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(6, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "Schliessen (R oder Esc)"
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.custom_minimum_size = Vector2(40, 36)
	close_button.pressed.connect(close)
	title_row.add_child(close_button)

	var title_line := ColorRect.new()
	title_line.color = Color(_accent, 0.55)
	title_line.custom_minimum_size = Vector2(0, 1)
	title_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_line)

	# Kopf: laufende Forschung und Warteschlange
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	status_row.custom_minimum_size = Vector2(0, 30)
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status_row)
	_status = _label(18, COLOR_TEXT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_row.add_child(_status)
	_queue_title = _label(15, COLOR_DIM)
	_queue_title.text = "Warteschlange:"
	status_row.add_child(_queue_title)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 5)
	status_row.add_child(_chips)

	# Fortschritt bzw. Hinweis ohne Forschungsstätte (gleicher Platz, gleiche Höhe)
	var bar_row := MarginContainer.new()
	bar_row.custom_minimum_size = Vector2(0, 32)
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_row)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.custom_minimum_size = Vector2(0, 12)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.add_theme_stylebox_override("background", _flat(Color(0.04, 0.05, 0.08, 0.9), Color(1, 1, 1, 0.14), 1, 3))
	_progress.add_theme_stylebox_override("fill", _flat(ResearchCard.COLOR_ACTIVE, ResearchCard.COLOR_ACTIVE.lightened(0.3), 0, 3))
	bar_row.add_child(_progress)
	_hint_row = HBoxContainer.new()
	_hint_row.add_theme_constant_override("separation", 14)
	_hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_row.visible = false
	bar_row.add_child(_hint_row)
	_hint = _label(18, COLOR_WARN)
	_hint_row.add_child(_hint)
	_build_button = Button.new()
	_build_button.focus_mode = Control.FOCUS_NONE
	_build_button.add_theme_font_size_override("font_size", 16)
	_build_button.custom_minimum_size = Vector2(0, 30)
	_build_button.tooltip_text = "Bauvorschau starten (Fenster schliesst sich)"
	_build_button.pressed.connect(_on_build_research_building)
	_hint_row.add_child(_build_button)

	# Seiten
	var pages := MarginContainer.new()
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pages)
	_tree_page = Control.new()
	_tree_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.add_child(_tree_page)
	_build_tree()
	_tree_page.custom_minimum_size = _canvas.custom_minimum_size
	# Beide Seiten gleich hoch – das Fenster springt beim Reiterwechsel nicht
	pages.custom_minimum_size = Vector2(0, _canvas.custom_minimum_size.y)
	_points_page = VBoxContainer.new()
	_points_page.add_theme_constant_override("separation", 10)
	_points_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.add_child(_points_page)
	_build_points_page()

	# Fusszeile: Bedienung, Forschungstempo
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 12)
	footer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(footer_row)
	_footer = _label(15, COLOR_DIM)
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer_row.add_child(_footer)
	_speed = _label(15, COLOR_DIM)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer_row.add_child(_speed)


## Forschungsbaum: Spalten = Zweige (research_branches), Zeilen = Stufen.
## Zweige mit zwei Forschungen auf einer Stufe bekommen zwei Plätze.
func _build_tree() -> void:
	var k: Kingdom = game.player
	var rs: ResearchSystem = game.research_system
	var width := DESIGN_WIDTH - MARGIN_X * 2.0
	_canvas = TreeCanvas.new()
	_canvas.accent = _evil_or(EVIL_LIGHT, GOOD_ACCENT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree_page.add_child(_canvas)

	# Zweig -> Stufe -> Forschungen (Datenreihenfolge)
	var branch_ids: Array[String] = []
	for b in DataDB.research_branches:
		var bid := str(b.get("id", ""))
		branch_ids.append(bid)
		_branch_names[bid] = str(b.get("name", bid))
	var by_branch: Dictionary = {}
	var max_tier := 1
	for r in rs.get_tree_for(k):
		var def: Dictionary = r
		var bid := str(def.get("branch", ""))
		if not _branch_names.has(bid):
			# Unbekannter Zweig: eigene Spalte statt verschwinden
			branch_ids.append(bid)
			_branch_names[bid] = bid
		if not by_branch.has(bid):
			by_branch[bid] = {}
		var tiers: Dictionary = by_branch[bid]
		var tier := maxi(int(def.get("tier", 1)), 1)
		max_tier = maxi(max_tier, tier)
		if not tiers.has(tier):
			tiers[tier] = []
		(tiers[tier] as Array).append(def)
	# Leere Zweige (andere Fraktion) weglassen
	var used_branches: Array[String] = []
	for bid in branch_ids:
		if by_branch.has(bid):
			used_branches.append(bid)

	# Kartenbreite: alle Plätze teilen sich die Breite
	var slots: Array[int] = []
	var total_slots := 0
	var inner_gaps := 0.0
	for bid in used_branches:
		var n := 1
		var tiers: Dictionary = by_branch[bid]
		for t in tiers:
			n = maxi(n, (tiers[t] as Array).size())
		slots.append(n)
		total_slots += n
		inner_gaps += (n - 1) * SLOT_GAP
	var free := width - (used_branches.size() - 1) * COL_GAP - inner_gaps - 12.0 * used_branches.size()
	var card_w := clampf(floorf(free / float(maxi(total_slots, 1))), MIN_CARD_WIDTH, MAX_CARD_WIDTH)
	var used := total_slots * card_w + inner_gaps + (used_branches.size() - 1) * COL_GAP + 12.0 * used_branches.size()
	var x := floorf((width - used) * 0.5) + 6.0
	var height := HEADER_HEIGHT + 8.0 + max_tier * CARD_HEIGHT + (max_tier - 1) * ROW_GAP + 8.0
	_canvas.custom_minimum_size = Vector2(width, height)
	_canvas.size = Vector2(width, height)

	for i in used_branches.size():
		var bid := used_branches[i]
		var col_w := slots[i] * card_w + (slots[i] - 1) * SLOT_GAP
		_canvas.columns.append(Rect2(x - 6.0, 0.0, col_w + 12.0, height))
		var head := _label(17, _light)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.position = Vector2(x, 1.0)
		head.size = Vector2(col_w, 26.0)
		_canvas.add_child(head)
		_branch_labels[bid] = head
		var ids: Array[String] = []
		var tiers: Dictionary = by_branch[bid]
		for tier in range(1, max_tier + 1):
			var list: Array = tiers.get(tier, [])
			if list.is_empty():
				continue
			var y := HEADER_HEIGHT + 8.0 + (tier - 1) * (CARD_HEIGHT + ROW_GAP)
			var total := list.size() * card_w + (list.size() - 1) * SLOT_GAP
			var start := x + (col_w - total) * 0.5
			for j in list.size():
				var def: Dictionary = list[j]
				var cx := start + j * (card_w + SLOT_GAP)
				# Einzelne Forschung direkt unter ihrer einzigen Voraussetzung (gleicher Zweig)
				var reqs: Array = def.get("requires", [])
				if list.size() == 1 and reqs.size() == 1 and _cards.has(str(reqs[0])) \
						and str(DataDB.get_research(str(reqs[0])).get("branch", "")) == bid:
					var parent: ResearchCard = _cards[str(reqs[0])]
					cx = parent.position.x
				var card := ResearchCard.new()
				_canvas.add_child(card)
				card.position = Vector2(cx, y)
				card.setup(def, _card_effect_text(k, def), Vector2(card_w, CARD_HEIGHT), _card_styles)
				var rid := str(def.get("id", ""))
				card.tip_source = _card_tip.bind(rid)
				card.activated.connect(_on_card_activated)
				_cards[rid] = card
				ids.append(rid)
		_branch_ids[bid] = ids
		x += col_w + COL_GAP + 12.0

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
				_canvas.cross.append([card, "nach " + str(DataDB.get_research(str(req)).get("name", req))])


func _build_points_page() -> void:
	var rs: ResearchSystem = game.research_system
	# Kopf: Kampfpunkte links, Mana rechts
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_points_page.add_child(top)
	var swords := ResourceBar.SwordsIcon.new()
	swords.color = _evil_or(EVIL_LIGHT, GOOD_ACCENT)
	swords.custom_minimum_size = Vector2(30, 30)
	swords.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(swords)
	_kp_label = _label(24, _evil_or(EVIL_LIGHT, GOOD_ACCENT))
	top.add_child(_kp_label)
	_kp_total = _label(17, COLOR_DIM)
	_kp_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_kp_total)
	var mana_icon := ResourceIcon.new()
	mana_icon.setup("mana", 24.0)
	top.add_child(mana_icon)
	_mana_label = _label(20, COLOR_MANA)
	top.add_child(_mana_label)
	_mana_rate = _label(17, COLOR_DIM)
	top.add_child(_mana_rate)

	var hint := _label(16, COLOR_DIM)
	hint.text = "Kampfpunkte bekommst du für besiegte Monster und zerstörte Höhlen (auch für feindliche Truppen). Ausgeben hier – die Wirkung gilt sofort und dauerhaft."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_points_page.add_child(hint)

	for up in rs.get_upgrades():
		_build_upgrade_row(up)

	# Woher kommt Mana? (Zusammenfassung, ändert sich mit dem Spielstand)
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", _info_style())
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_points_page.add_child(info)
	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 4)
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(info_box)
	var info_title := _label(17, _light)
	info_title.text = "Mana im Überblick"
	info_box.add_child(info_title)
	_info_cap = _label(16, COLOR_TEXT)
	info_box.add_child(_info_cap)
	_info_income = _label(16, COLOR_TEXT)
	info_box.add_child(_info_income)
	_info_sources = _label(15, COLOR_DIM)
	_info_sources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_box.add_child(_info_sources)


## Eine Zeile je Verbesserung: Name/Beschreibung, Stufe, nächste Wirkung, Kosten + Button
func _build_upgrade_row(up: Dictionary) -> void:
	var uid := str(up.get("id", ""))
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _card_styles.get("available"))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	_points_page.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(text_box)
	var name_label := _label(20, COLOR_TEXT)
	name_label.text = str(up.get("name", uid))
	text_box.add_child(name_label)
	var desc := _label(15, COLOR_DIM)
	desc.text = str(up.get("description", ""))
	text_box.add_child(desc)

	var level_box := VBoxContainer.new()
	level_box.custom_minimum_size = Vector2(150, 0)
	level_box.alignment = BoxContainer.ALIGNMENT_CENTER
	level_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(level_box)
	var level := _label(17, COLOR_TEXT)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_box.add_child(level)
	var pips := Pips.new()
	pips.color = _evil_or(EVIL_LIGHT, GOOD_ACCENT)
	pips.custom_minimum_size = Vector2(150, 12)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.max_level = (up.get("cost_kill_points", []) as Array).size()
	level_box.add_child(pips)
	var now := _label(14, COLOR_DIM)
	now.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_box.add_child(now)

	var next_box := VBoxContainer.new()
	next_box.custom_minimum_size = Vector2(250, 0)
	next_box.alignment = BoxContainer.ALIGNMENT_CENTER
	next_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(next_box)
	var next_title := _label(14, COLOR_DIM)
	next_title.text = "Nächste Stufe"
	next_box.add_child(next_title)
	var next := _label(17, _light)
	next_box.add_child(next)

	var buy_box := VBoxContainer.new()
	buy_box.custom_minimum_size = Vector2(160, 0)
	buy_box.alignment = BoxContainer.ALIGNMENT_CENTER
	buy_box.add_theme_constant_override("separation", 4)
	buy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(buy_box)
	var cost := _label(16, COLOR_TEXT)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buy_box.add_child(cost)
	var button := ResearchTipButton.new()
	button.text = "Verbessern"
	button.custom_minimum_size = Vector2(160, 40)
	button.add_theme_font_size_override("font_size", 17)
	button.tip_source = _upgrade_tip.bind(uid)
	button.pressed.connect(_on_upgrade_pressed.bind(uid))
	buy_box.add_child(button)
	_upgrade_rows[uid] = {"level": level, "now": now, "pips": pips, "next_title": next_title,
			"next": next, "cost": cost, "button": button}


func _make_tab(text: String, group: ButtonGroup) -> ResearchTipButton:
	var b := ResearchTipButton.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(136, 36)
	var pressed := _flat(_evil_or(EVIL_MID, Color(0.62, 0.47, 0.2)), _evil_or(EVIL_LIGHT, GOOD_LIGHT), 1, 4)
	pressed.content_margin_left = 14
	pressed.content_margin_right = 14
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	return b


func _show_tab(tab: String) -> void:
	_tab = TAB_POINTS if tab == TAB_POINTS else TAB_TREE
	var points := _tab == TAB_POINTS
	_tab_tree.set_pressed_no_signal(not points)
	_tab_points.set_pressed_no_signal(points)
	_tree_page.visible = not points
	_points_page.visible = points
	_footer.text = ("Verbesserungen wirken sofort und dauerhaft  ·  R / Esc: schliessen" if points else
			"Klick: erforschen bzw. abbrechen (Kosten zurück)  ·  R / Esc: schliessen")
	_confirm_id = ""
	if visible:
		_refresh()


## Mitte oben; bei kleinem Fenster verkleinert, aber nie ausserhalb
func _place() -> void:
	var vp := get_viewport_rect().size
	var want := Vector2(DESIGN_WIDTH, get_combined_minimum_size().y)
	size = want
	var s := minf(1.0, minf((vp.x - 16.0) / want.x, (vp.y - TOP - 8.0) / want.y))
	s = maxf(s, 0.4)
	scale = Vector2(s, s)
	var top := clampf(TOP, 8.0, maxf(vp.y - want.y * s - 8.0, 8.0))
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
	_tab_points.badge_visible = has_affordable_upgrade(game.research_system, k)
	if _tab == TAB_TREE:
		_refresh_tree(k)
	else:
		_refresh_points(k)


func _refresh_header(k: Kingdom) -> void:
	var rs: ResearchSystem = game.research_system
	var active := rs.get_active(k)
	var buildings := rs.count_research_buildings(k)
	var bname := rs.get_research_building_name(k)
	var ratio := rs.get_progress_ratio(k)
	var text := ""
	var color := COLOR_TEXT
	if not active.is_empty():
		var aname := str(DataDB.get_research(active).get("name", active))
		var remaining := rs.get_remaining_seconds(k)
		if remaining == INF:
			text = "Erforscht: %s – %d %% – angehalten" % [aname, floori(ratio * 100.0)]
			color = COLOR_WARN
		else:
			text = "Erforscht: %s – %d %% – noch %d s" % [aname, floori(ratio * 100.0), ceili(remaining)]
	elif buildings > 0:
		text = "Forschung ruht – wähle unten eine Forschung."
		color = COLOR_WARN
	else:
		text = "Keine Forschungsstätte"
		color = COLOR_DIM
	# Eine Forschungsstätte im Bau: nicht zum Bau einer zweiten auffordern
	var site: Building = rs.get_research_site(k) if buildings == 0 else null
	if site != null and active.is_empty():
		text = "%s wird gebaut – %d %%" % [site.get_display_name(), floori(site.get_progress_ratio() * 100.0)]
		color = COLOR_WARN
	_set_text(_status, text, color)
	var no_building := buildings == 0
	_hint_row.visible = no_building
	_progress.visible = not no_building
	if no_building:
		if site != null:
			_set_text(_hint, "Sobald %s fertig ist, kannst du forschen." % site.get_display_name(), COLOR_WARN)
		else:
			_set_text(_hint, "Baue %s %s (Baumenü), um zu forschen." % [_article(bname), bname], COLOR_WARN)
		_build_button.visible = site == null
		var label := "%s bauen" % bname
		if _build_button.text != label:
			_build_button.text = label
	_progress.value = ratio if not active.is_empty() else 0.0
	var speed_text := "%d × %s  ·  Tempo %d %%" % [buildings, bname, roundi(rs.get_speed(k) * 100.0)]
	if buildings == 0:
		speed_text = "%s im Bau" % bname if site != null else "Keine Forschungsstätte – %s im Baumenü" % bname
	_set_text(_speed, speed_text, COLOR_DIM)
	_refresh_chips(k)


## Chips der Warteschlange: neu gebaut nur, wenn sie sich geändert hat
func _refresh_chips(k: Kingdom) -> void:
	var queue: Array = k.research_queue.duplicate()
	if queue != _chip_queue:
		_chip_queue = queue
		for c in _chips.get_children():
			_chips.remove_child(c)
			c.queue_free()
		for i in queue.size():
			var rid := str(queue[i])
			var chip := ResearchTipButton.new()
			chip.add_theme_font_size_override("font_size", 15)
			chip.custom_minimum_size = Vector2(0, 28)
			chip.tip_source = _chip_tip.bind(rid)
			chip.pressed.connect(_ask_cancel.bind(rid))
			var color := ResearchCard.COLOR_ACTIVE if i == 0 else ResearchCard.COLOR_QUEUED
			var st := _flat(Color(color.darkened(0.72), 0.95), color, 1, 4)
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
		if chip == null:
			continue
		var rid := str(chip.get_meta("research_id", ""))
		var rname := str(DataDB.get_research(rid).get("name", rid))
		var confirming := rid == _confirm_id
		var nr := int(chip.get_meta("index", 0)) + 1
		var t := ("%d. %s – abbrechen?" % [nr, rname]) if confirming else "%d. %s  ×" % [nr, rname]
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
		var confirming := str(rid) == _confirm_id
		if confirming:
			var also := _dependant_names(k, str(rid))
			card.confirm_text = "Nochmal klicken: abbrechen (Kosten zurück)" if also.is_empty() \
					else "Nochmal klicken: abbrechen, auch %s" % also
		card.apply(st, pos, ratio if st == "active" else 0.0, confirming, k)
	for bid in _branch_labels:
		var ids: Array = _branch_ids.get(bid, [])
		var done := 0
		for rid in ids:
			if k.researched.has(rid):
				done += 1
		_set_text(_branch_labels[bid], "%s  ·  %d/%d" % [str(_branch_names.get(bid, bid)), done, ids.size()], _light)
	if links_changed:
		_canvas.queue_redraw()


func _refresh_points(k: Kingdom) -> void:
	var rs: ResearchSystem = game.research_system
	_set_text(_kp_label, "Kampfpunkte: %d" % k.kill_points, _evil_or(EVIL_LIGHT, GOOD_ACCENT))
	_set_text(_kp_total, "(gesamt %d)" % k.kill_points_total, COLOR_DIM)
	var amount := k.get_amount("mana")
	var cap := k.get_capacity("mana")
	var full := amount >= cap - 0.5
	_set_text(_mana_label, "Mana %d/%d" % [floori(amount), roundi(cap)], COLOR_WARN if full else COLOR_MANA)
	var regen := k.mana_regen * 60.0
	_set_text(_mana_rate, "  ·  Burg %s/min" % ResourceBar.format_signed(regen) if regen > 0.0 else "  ·  Burg: kein eigenes Mana",
			COLOR_DIM)
	var pip_color := _evil_or(EVIL_LIGHT, GOOD_ACCENT)
	for up in rs.get_upgrades():
		var uid := str(up.get("id", ""))
		var row: Dictionary = _upgrade_rows.get(uid, {})
		if row.is_empty():
			continue
		var level := rs.get_upgrade_level(k, uid)
		var max_level := (up.get("cost_kill_points", []) as Array).size()
		_set_text(row["level"], "Stufe %d/%d" % [level, max_level], COLOR_TEXT)
		var pips: Pips = row["pips"]
		if pips.level != level:
			pips.level = level
			pips.color = pip_color
			pips.queue_redraw()
		_set_text(row["now"], upgrade_current_text(up, level), COLOR_DIM)
		var cost := rs.get_upgrade_cost(k, uid)
		var maxed := cost < 0
		_set_text(row["next_title"], "Höchste Stufe erreicht" if maxed else "Nächste Stufe", COLOR_DIM)
		_set_text(row["next"], "" if maxed else upgrade_next_text(k, up), _light)
		var affordable := not maxed and k.kill_points >= cost
		_set_text(row["cost"], "Höchste Stufe" if maxed else "%d Kampfpunkte" % cost,
				COLOR_DIM if maxed else (COLOR_GOOD if affordable else COLOR_BAD))
		var button: ResearchTipButton = row["button"]
		button.disabled = not rs.can_buy_upgrade(k, uid).is_empty()
		button.badge_visible = affordable
	# Überblick
	var parts := ResourceBar.mana_cap_parts(k)
	var texts: PackedStringArray = []
	for p in parts:
		texts.append("%s %d" % [str(p[0]), roundi(float(p[1]))])
	_set_text(_info_cap, "Maximum %d = %s" % [roundi(cap), " + ".join(texts)], COLOR_TEXT)
	var income := float(k.income_rate.get("mana", 0.0))
	var upkeep := k.get_upkeep("mana") * 60.0
	var line := "Ertrag %s pro Minute" % ResourceBar.format_signed(income)
	if regen > 0.0:
		line += "  ·  davon Burg %s" % ResourceBar.format_signed(regen)
	if upkeep > 0.0:
		line += "  ·  laufende Zauber −%s" % ResourceBar.format_number(upkeep)
	if full:
		line += "  ·  Speicher voll – Überschuss geht verloren"
	_set_text(_info_income, line, COLOR_WARN if full else COLOR_TEXT)
	_set_text(_info_sources, ResourceBar.mana_raise_hint(k), COLOR_DIM)


## Mindestens eine Verbesserung ist jetzt bezahlbar?
static func has_affordable_upgrade(rs: ResearchSystem, k: Kingdom) -> bool:
	for up in rs.get_upgrades():
		if rs.can_buy_upgrade(k, str(up.get("id", ""))).is_empty():
			return true
	return false


## Wirkung der nächsten Stufe: "Maximum 100 → 140" bzw. "Mana +3,0/min (jetzt 11,4 → 14,4)"
static func upgrade_next_text(k: Kingdom, up: Dictionary) -> String:
	var per: Dictionary = up.get("per_level", {})
	var parts: PackedStringArray = []
	for key in per:
		var add := float(per[key])
		match str(key):
			"mana_cap":
				var cap := k.get_capacity("mana")
				parts.append("Maximum %d → %d" % [roundi(cap), roundi(cap + add)])
			"mana_regen":
				var per_min := add * 60.0 * k.mod("mana_regen")
				var now := float(k.income_rate.get("mana", 0.0))
				parts.append("Mana +%s/min (jetzt %s → %s)" % [ResearchTipButton.num1(per_min),
						ResearchTipButton.num1(now), ResearchTipButton.num1(now + per_min)])
			_:
				parts.append(str(up.get("description", "")))
	return ", ".join(parts)


## Wirkung der aktuellen Stufe: "jetzt +40 Maximum" / "jetzt +3,0 Mana/min"
static func upgrade_current_text(up: Dictionary, level: int) -> String:
	if level <= 0:
		return "noch nicht verbessert"
	var per: Dictionary = up.get("per_level", {})
	var parts: PackedStringArray = []
	for key in per:
		var total := float(per[key]) * level
		match str(key):
			"mana_cap":
				parts.append("jetzt +%d Maximum" % roundi(total))
			"mana_regen":
				parts.append("jetzt +%s Mana/min" % ResearchTipButton.num1(total * 60.0))
	return ", ".join(parts)


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
			# Alle nennen, die mit abgebrochen werden (Folgeforschungen in der Warteschlange)
			var names: PackedStringArray = []
			for cid in game.research_system.get_cancel_set(k, rid):
				names.append(str(DataDB.get_research(str(cid)).get("name", cid)))
			game.research_system.cancel(k, rid)
			Notify.info("Forschung abgebrochen: %s – Kosten erstattet" % ", ".join(names))
	else:
		_confirm_id = rid
		_confirm_ms = now
	_refresh()


## "Bibliothek bauen": Bauvorschau der Forschungsstätte starten, Fenster schliessen
func _on_build_research_building() -> void:
	for d in DataDB.buildings:
		var def: Dictionary = d
		if bool(def.get("research", false)) and bool(def.get("player_buildable", false)):
			close()
			game.placement.start(def)
			return


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
				Notify.good("%s: Stufe %d – %s" % [str(up.get("name", uid)), rs.get_upgrade_level(k, uid),
						upgrade_current_text(up, rs.get_upgrade_level(k, uid))])
	_refresh()


# ---------------------------------------------------------------------------
# Texte
# ---------------------------------------------------------------------------

## Kurze Wirkung für die Karte ("Neu: Ritter", "+10 % Angriff (Kämpfer)")
func _card_effect_text(k: Kingdom, def: Dictionary) -> String:
	var parts: PackedStringArray = []
	var unlocks: PackedStringArray = []
	for line in effect_lines(k, str(def.get("id", ""))):
		var s := str(line)
		if s.begins_with("Schaltet frei: "):
			unlocks.append(s.trim_prefix("Schaltet frei: "))
		else:
			parts.append(s.trim_suffix(" ausserhalb des Gebiets"))
	if not unlocks.is_empty():
		parts.insert(0, "Neu: " + ", ".join(unlocks))
	return ", ".join(parts)


## Wirkungen einer Forschung (describe_effects). Rollen-Modifikatoren wie
## "armor@combat" beschreibt DataDB.describe_modifier noch nicht lesbar
## ("+30 % armor@combat") – diese Zeilen hier selbst bilden: "Rüstung ×1,3 (alle Truppen)".
func effect_lines(k: Kingdom, rid: String) -> PackedStringArray:
	var lines: PackedStringArray = game.research_system.describe_effects(k, rid)
	var effects: Array = DataDB.get_research(rid).get("effects", [])
	if lines.size() != effects.size():
		return lines
	for i in effects.size():
		var e: Dictionary = effects[i]
		var key := str(e.get("key", ""))
		if str(e.get("type", "")) == "modifier" and key.contains("@") and lines[i].contains("@"):
			lines[i] = describe_role_modifier(key, float(e.get("factor", 1.0)))
	return lines


const _ROLE_NAMES := {"combat": "alle Truppen", "worker": "Bewohner", "support": "Heiler",
	"king": "König", "monster": "Monster"}


## "armor@combat" ×1.3 -> "Rüstung ×1,3 (alle Truppen)"
static func describe_role_modifier(key: String, factor: float) -> String:
	var parts := key.split("@", true, 1)
	var role := str(_ROLE_NAMES.get(parts[1], parts[1])) if parts.size() > 1 else ""
	var text := DataDB.describe_modifier(parts[0], factor)
	return text + (" (%s)" % role if not role.is_empty() else "")


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
	var branch := str(_branch_names.get(str(def.get("branch", "")), ""))
	lines.append("[b]%s[/b]   %s" % [tip.colored(str(def.get("name", rid)), _evil_or(EVIL_LIGHT, GOOD_ACCENT)),
			tip.colored("%s · Stufe %d" % [branch, int(def.get("tier", 1))], COLOR_DIM)])
	var desc := str(def.get("description", ""))
	if not desc.is_empty():
		lines.append(tip.esc(desc))
	for e in effect_lines(k, rid):
		lines.append("• " + tip.colored(str(e), Color(0.72, 0.9, 1.0)))
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
			if not _dependant_names(k, rid).is_empty():
				lines.append(tip.colored("Bricht auch ab: " + _dependant_names(k, rid), COLOR_WARN))
		"queued":
			lines.append(tip.colored("In der Warteschlange (Platz %d)" % (k.research_queue.find(rid) + 1), ResearchCard.COLOR_QUEUED))
			lines.append(tip.colored("Klick: abbrechen – Kosten werden erstattet", COLOR_DIM))
			if not _dependant_names(k, rid).is_empty():
				lines.append(tip.colored("Bricht auch ab: " + _dependant_names(k, rid), COLOR_WARN))
		_:
			var reason := rs.can_start(k, rid)
			if reason.is_empty():
				lines.append(tip.colored("Klick: erforschen (Kosten werden sofort bezahlt)", ResearchCard.COLOR_DONE))
			elif not reason.begins_with("Es fehlen") and not reason.begins_with("Benötigt zuerst"):
				# Fehlende Rohstoffe und Voraussetzungen stehen schon oben
				lines.append(tip.colored(reason, COLOR_BAD))
	return "\n".join(lines)


func _chip_tip(rid: String) -> String:
	var rname := str(DataDB.get_research(rid).get("name", rid))
	var text := "[b]%s[/b]\nAbbrechen – Kosten werden erstattet" % ResearchTipButton.esc(rname)
	var also := _dependant_names(game.player, rid)
	if not also.is_empty():
		text += "\n" + ResearchTipButton.colored("Bricht auch ab: " + also, COLOR_WARN)
	return text + "\n" + ResearchTipButton.colored("Zum Bestätigen zweimal klicken", COLOR_DIM)


## Namen der eingereihten Forschungen, die beim Abbrechen von rid mit abgebrochen würden
func _dependant_names(k: Kingdom, rid: String) -> String:
	var names: PackedStringArray = []
	for cid in game.research_system.get_cancel_set(k, rid):
		if str(cid) != rid:
			names.append(str(DataDB.get_research(str(cid)).get("name", cid)))
	return ", ".join(names)


func _upgrade_tip(uid: String) -> String:
	if game == null:
		return ""
	var k: Kingdom = game.player
	var rs: ResearchSystem = game.research_system
	var reason := rs.can_buy_upgrade(k, uid)
	if reason.is_empty():
		return "Für %d Kampfpunkte verbessern" % rs.get_upgrade_cost(k, uid)
	return ResearchTipButton.colored(reason, COLOR_BAD)


func _points_tab_tip() -> String:
	if game == null:
		return ""
	var text := "Kampfpunkte ausgeben: Mana-Maximum (Manakristall) und Mana der Burg (Manaherz)"
	if has_affordable_upgrade(game.research_system, game.player):
		text += "\n" + ResearchTipButton.colored("Eine Verbesserung ist bezahlbar!", COLOR_GOOD)
	return text


## "eine Bibliothek" / "ein Dunkles Archiv" (Artikel nach der Wortendung)
static func _article(noun: String) -> String:
	var last := noun.get_slice(" ", noun.get_slice_count(" ") - 1).to_lower()
	for ending in ["ek", "e", "ei", "ung", "heit", "keit", "schaft", "ion", "statt", "stätte", "halle", "hütte", "mine"]:
		if last.ends_with(ending):
			return "eine"
	return "ein"


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

func _make_card_styles() -> Dictionary:
	var avail_bg := Color(0.16, 0.1, 0.22, 0.98) if _evil else Color(0.2, 0.165, 0.11, 0.98)
	var avail_border := EVIL_ACCENT.lightened(0.12) if _evil else GOOD_ACCENT.darkened(0.3)
	var hover_border := EVIL_LIGHT if _evil else GOOD_LIGHT
	var styles := {}
	styles["available"] = _flat(avail_bg, avail_border, 1, 6)
	styles["available_hover"] = _flat(avail_bg.lightened(0.08), hover_border, 2, 6)
	styles["locked"] = _flat(Color(0.1, 0.095, 0.11, 0.95), Color(0.3, 0.29, 0.31), 1, 6)
	styles["locked_hover"] = _flat(Color(0.13, 0.125, 0.14, 0.95), Color(0.45, 0.44, 0.46), 1, 6)
	styles["done"] = _flat(Color(0.08, 0.16, 0.09, 0.98), ResearchCard.COLOR_DONE, 2, 6)
	styles["done_hover"] = _flat(Color(0.1, 0.2, 0.11, 0.98), ResearchCard.COLOR_DONE.lightened(0.3), 2, 6)
	styles["active"] = _flat(Color(0.07, 0.13, 0.24, 0.98), ResearchCard.COLOR_ACTIVE, 2, 6)
	styles["active_hover"] = _flat(Color(0.09, 0.16, 0.29, 0.98), ResearchCard.COLOR_ACTIVE.lightened(0.3), 2, 6)
	styles["queued"] = _flat(Color(0.09, 0.12, 0.2, 0.98), ResearchCard.COLOR_QUEUED, 1, 6)
	styles["queued_hover"] = _flat(Color(0.11, 0.15, 0.24, 0.98), ResearchCard.COLOR_QUEUED.lightened(0.3), 2, 6)
	styles["confirm"] = _flat(Color(0.22, 0.07, 0.06, 0.98), ResearchCard.COLOR_CONFIRM, 2, 6)
	styles["confirm_hover"] = _flat(Color(0.28, 0.09, 0.08, 0.98), ResearchCard.COLOR_CONFIRM.lightened(0.2), 2, 6)
	for key in styles:
		var st: StyleBoxFlat = styles[key]
		st.content_margin_left = 12
		st.content_margin_right = 12
		st.content_margin_top = 8
		st.content_margin_bottom = 8
	return styles


func _panel_style() -> StyleBoxFlat:
	var bg := Color(0.07, 0.045, 0.1, 0.97) if _evil else Color(0.1, 0.085, 0.065, 0.97)
	var st := _flat(bg, _accent, 2, 8)
	st.content_margin_left = MARGIN_X
	st.content_margin_right = MARGIN_X
	st.content_margin_top = MARGIN_Y
	st.content_margin_bottom = MARGIN_Y
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 14
	if _evil:
		# Dunkles Violett: Rahmen geht weich in den Hintergrund über
		st.border_blend = true
	return st


func _info_style() -> StyleBoxFlat:
	var st := _flat(Color(1, 1, 1, 0.03), Color(_accent, 0.3), 1, 6)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 8
	st.content_margin_bottom = 8
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


func _set_text(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _evil_or(evil_color: Color, good_color: Color) -> Color:
	return evil_color if _evil else good_color
