## EspionagePanel
##
## Spionagefenster (Taste K, Button "Spionage" oben; K, Esc oder × schliesst).
## Gleiche Bauart wie Forschungs-, Helden- und Diplomatiefenster (eigene Ebene,
## Mitte oben); das Spiel läuft weiter. Es ist immer nur eines dieser Fenster offen.
## - Reiter "Übersicht": eigener Entdeckungswert mit Stufe und Balken, Ursachen
##   (Gebäude, Bevölkerung, Armee, Helden, Aggression, Reichstarnung), Reichstarnung
##   ein/aus mit Kosten (gesperrt mit Grund), "Was die anderen wissen" (Aufmerksamkeit
##   der KI-Reiche auf dich – ab Kundschaft 2 als Wort, ab 3 genau) und ein Hinweis.
## - Reiter "Reiche & Dörfer": links KI-Reiche (gefallene grau) und selbstständige
##   Dörfer mit Kundschaft (drei Punkte), Alter und Beziehung; rechts die
##   Zusammenfassung je nach Kundschaft und Knöpfe "Spion schicken", "Dorf
##   aufhetzen" bzw. "Rivalen aufhetzen" und "Hinspringen".
## - Reiter "Spione": eigene Spione mit Stufe, Erfahrung, Auftrag, Zustand und
##   Fortschritt (enttarnte rot), "Spion beschwören" (gesperrt mit Grund); rechts
##   Auftrag, Ziel und Zweitziel, Vorschau der Entdeckungsgefahr am Ziel, "Auftrag
##   erteilen", "Zurückrufen", "Hinspringen".
## - F3-Modus: "Aufmerksamkeit +30", "Volle Kundschaft", "KI greift jetzt an",
##   "KI-Reich besiegen" (gewähltes bzw. erstes), "Rivalen: Krieg".
## Zeigt nur an und ruft EspionageSystem, SpySystem, AISystem und VictorySystem mit
## dem Spieler-Reich auf (dieselben Funktionen nutzt die KI). Aktualisiert wird alle
## 0.25 s, solange das Fenster offen ist; Listen und Auswahllisten werden nur neu
## gebaut, wenn sich ihr Inhalt ändert.
class_name EspionagePanel
extends PanelContainer

## Fenster wurde geöffnet oder geschlossen
signal toggled(open: bool)

const TAB_OVERVIEW := "overview"
const TAB_REALMS := "realms"
const TAB_SPIES := "spies"
const DESIGN_WIDTH := 1048.0
const TOP := 92.0
const MARGIN_X := 16.0
const MARGIN_Y := 12.0
const REFRESH_INTERVAL := 0.25
const LIST_WIDTH := 384.0
const ENTRY_HEIGHT := 62.0
const PAGE_HEIGHT := 520.0
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.74, 0.71, 0.66)
const COLOR_GREY := Color(0.55, 0.53, 0.5)
const COLOR_BAD := Color(1.0, 0.45, 0.38)
const COLOR_GOOD := Color(0.55, 0.88, 0.5)
const COLOR_WARN := Color(1.0, 0.82, 0.35)
const COLOR_WAR := Color(1.0, 0.5, 0.42)
const COLOR_INTEL := Color(0.45, 0.72, 1.0)
const CAUSE_NAMES := {"buildings": "Gebäude", "population": "Bevölkerung", "army": "Armee", "heroes": "Helden",
		"aggression": "Aggression", "cloak": "Reichstarnung"}
const FALLEN_REASONS := {"castle": "die Burg wurde zerstört", "king": "der König ist tot"}
const CAUSE_ORDER := ["buildings", "population", "army", "heroes", "aggression", "cloak"]


## Kundschaft als drei Punkte (gefüllt bis zur Stufe)
class IntelDots:
	extends Control

	var level := 0:
		set(value):
			if level != value:
				level = value
				queue_redraw()
	var color := Color(0.45, 0.72, 1.0)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(40, 14)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		for i in 3:
			var c := Vector2(6.0 + i * 13.0, size.y * 0.5)
			draw_circle(c, 5.2, Color(0, 0, 0, 0.65))
			draw_circle(c, 4.0, color if i < level else Color(1, 1, 1, 0.14))


var game: Node

var _accent := ResearchPanel.GOOD_ACCENT
var _light := ResearchPanel.GOOD_LIGHT
var _evil := false
var _tab := TAB_OVERVIEW
var _timer := 0.0
var _refresh_queued := false
## Gewähltes Reich bzw. Dorf im Reiter "Reiche & Dörfer" (Kingdom.id, 0 = keins)
var _realm_id := 0
## Gewählter Spion (uid, 0 = keiner) und die Auftragswahl
var _spy_uid := 0
var _mission := "scout"
var _target_id := 0
var _target2_id := 0

## Reiter: id -> {"button": ResearchTipButton, "page": Control}
var _tabs: Dictionary = {}
var _count_label: Label
var _footer: Label
var _debug_row: HBoxContainer

# Übersicht
var _disc_label: Label
var _disc_bar: HpBar
var _causes_label: Label
var _cloak_label: Label
var _cloak_button: ResearchTipButton
var _aware_label: Label

# Reiche und Dörfer
var _realm_list: VBoxContainer
var _realm_key: Array = []
## id -> {"button", "swatch", "name", "tag", "dots", "sub"}
var _realm_entries: Dictionary = {}
var _realm_detail: VBoxContainer
var _realm_swatch: ColorRect
var _realm_name: Label
var _realm_people: Label
var _realm_summary: Label
var _realm_scout_button: ResearchTipButton
var _realm_incite_button: ResearchTipButton
var _realm_jump_button: Button

# Spione
var _spy_count: Label
var _recruit_button: ResearchTipButton
var _spy_list: VBoxContainer
var _spy_key: Array = []
## uid -> {"button", "name", "tag", "sub", "bar"}
var _spy_entries: Dictionary = {}
var _spy_empty: Label
var _spy_detail: VBoxContainer
var _spy_name: Label
var _spy_text: Label
var _mission_option: OptionButton
var _target_option: OptionButton
var _target2_label: Label
var _target2_option: OptionButton
var _target_ids: Array = []
var _target2_ids: Array = []
var _preview_label: Label
var _assign_button: ResearchTipButton
var _recall_button: Button
var _spy_jump_button: Button
var _spy_info: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


## Aufbauen (das Fenster muss schon im Baum hängen)
func setup(p_game: Node) -> void:
	game = p_game
	var k: Kingdom = game.player
	_evil = k.faction_id == "evil"
	_accent = ResearchPanel.EVIL_ACCENT if _evil else ResearchPanel.GOOD_ACCENT
	_light = ResearchPanel.EVIL_LIGHT if _evil else ResearchPanel.GOOD_LIGHT
	add_theme_stylebox_override("panel", _panel_style())
	custom_minimum_size = Vector2(DESIGN_WIDTH, 0)
	_build()
	var esp: EspionageSystem = game.espionage_system
	var spies: SpySystem = game.spy_system
	spies.spies_changed.connect(_on_changed.unbind(1))
	esp.intel_changed.connect(_on_changed.unbind(3))
	esp.cloak_changed.connect(_on_changed.unbind(2))
	game.victory_system.kingdom_fallen.connect(_on_changed.unbind(3))
	get_viewport().size_changed.connect(_place)
	Settings.changed.connect(_place)
	minimum_size_changed.connect(_queue_place)
	_show_tab(TAB_OVERVIEW)


func is_open() -> bool:
	return visible


## Öffnen, optional auf einem Reiter, bei einem Reich/Dorf (Kingdom.id) und einem Spion (uid).
## Mit Reiter "spies" ist target_id das vorgewählte Ziel des Auftrags.
func open(tab: String = "", target_id: int = 0, spy_uid: int = 0) -> void:
	if spy_uid != 0:
		select_spy(spy_uid)
		if tab.is_empty():
			tab = TAB_SPIES
	if target_id != 0:
		if tab == TAB_SPIES:
			_target_id = target_id
			_choose_mission_for(game.get_kingdom(target_id))
		else:
			_realm_id = target_id
			if tab.is_empty():
				tab = TAB_REALMS
	if not tab.is_empty():
		_show_tab(tab)
	if visible:
		_refresh()
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
	toggled.emit(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func get_tab() -> String:
	return _tab


## Spion im Reiter "Spione" wählen (uid)
func select_spy(uid: int) -> void:
	_spy_uid = uid
	if visible:
		_refresh()


func get_spy_uid() -> int:
	return _spy_uid


## Auftragswahl setzen (Rauchtest, Knöpfe im Reiter "Reiche & Dörfer")
func set_mission_choice(mission: String, target_id: int, target2_id: int = 0) -> void:
	_mission = mission if SpySystem.MISSIONS.has(mission) else "scout"
	_target_id = target_id
	_target2_id = target2_id
	if visible:
		_refresh()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH_INTERVAL:
		return
	_timer = 0.0
	_refresh()


## Spione, Kundschaft, Tarnung oder Reiche geändert: höchstens einmal pro Bild neu zeichnen
func _on_changed() -> void:
	if visible and not _refresh_queued:
		_refresh_queued = true
		_deferred_refresh.call_deferred()


func _deferred_refresh() -> void:
	_refresh_queued = false
	_refresh()


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Titelzeile: Wappen, Titel, Kurzstand, Reiter, Schliessen (gleicher Aufbau in allen Fenstern)
	var title_row := UiStyle.window_header(root, "Spionage", _evil, "Schliessen (K oder Esc)", close)
	_count_label = _label(16, COLOR_DIM)
	_count_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiStyle.header_add(title_row, _count_label, true)
	var group := ButtonGroup.new()
	var tab_overview := _make_tab("Übersicht", group)
	tab_overview.tooltip_text = "Dein Entdeckungswert, seine Ursachen und die Reichstarnung"
	tab_overview.pressed.connect(_show_tab.bind(TAB_OVERVIEW))
	UiStyle.header_add(title_row, tab_overview)
	var tab_realms := _make_tab("Reiche & Dörfer", group)
	tab_realms.tooltip_text = "Was du über fremde Reiche und Dörfer weisst (Kundschaft)"
	tab_realms.pressed.connect(_show_tab.bind(TAB_REALMS))
	UiStyle.header_add(title_row, tab_realms)
	var tab_spies := _make_tab("Spione", group)
	tab_spies.tooltip_text = "Eigene Spione: beschwören, Aufträge erteilen, zurückrufen"
	tab_spies.pressed.connect(_show_tab.bind(TAB_SPIES))
	UiStyle.header_add(title_row, tab_spies)

	# Seiten (gleich hoch: das Fenster springt beim Reiterwechsel nicht)
	var pages := MarginContainer.new()
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.custom_minimum_size = Vector2(0, PAGE_HEIGHT)
	root.add_child(pages)
	var overview := VBoxContainer.new()
	overview.add_theme_constant_override("separation", 8)
	overview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.add_child(overview)
	_tabs[TAB_OVERVIEW] = {"button": tab_overview, "page": overview}
	_build_overview(overview)
	var realms := HBoxContainer.new()
	realms.add_theme_constant_override("separation", 14)
	realms.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.add_child(realms)
	_tabs[TAB_REALMS] = {"button": tab_realms, "page": realms}
	_build_realms(realms)
	var spies_page := HBoxContainer.new()
	spies_page.add_theme_constant_override("separation", 14)
	spies_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.add_child(spies_page)
	_tabs[TAB_SPIES] = {"button": tab_spies, "page": spies_page}
	_build_spies(spies_page)

	# Debug (F3)
	_debug_row = _row(root)
	var debug_label := _label(15, COLOR_WARN)
	debug_label.text = "Debug:"
	_debug_row.add_child(debug_label)
	for entry in [["aware", "Aufmerksamkeit +30"], ["intel", "Volle Kundschaft"], ["attack", "KI greift jetzt an"],
			["defeat", "KI-Reich besiegen"], ["rivals", "Rivalen: Krieg"]]:
		var b := _plain_button(str(entry[1]))
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size = Vector2(0, 30)
		b.pressed.connect(debug_action.bind(str(entry[0])))
		_debug_row.add_child(b)

	_footer = _label(15, COLOR_DIM)
	_footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(_footer)


func _build_overview(page: VBoxContainer) -> void:
	var head := _row(page)
	_disc_label = _label(22, COLOR_TEXT)
	_disc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_disc_label)
	_disc_bar = HpBar.new()
	_disc_bar.custom_minimum_size = Vector2(0, 22)
	page.add_child(_disc_bar)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(300, 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left)
	left.add_child(_section_label("Ursachen"))
	_causes_label = _label(16, COLOR_TEXT)
	_causes_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	left.add_child(_causes_label)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(right)
	right.add_child(_section_label("Reichstarnung"))
	_cloak_label = _wrap_label(16, COLOR_TEXT)
	right.add_child(_cloak_label)
	var cloak_row := _row(right)
	_cloak_button = _tip_button("Tarnung einschalten")
	_cloak_button.custom_minimum_size = Vector2(240, 36)
	_cloak_button.tip_source = _cloak_tip
	_cloak_button.pressed.connect(_on_cloak_pressed)
	cloak_row.add_child(_cloak_button)
	right.add_child(_section_label("Was die anderen wissen"))
	_aware_label = _wrap_label(16, COLOR_TEXT)
	right.add_child(_aware_label)

	var hint := _wrap_label(15, COLOR_DIM)
	hint.text = ("Je grösser, mächtiger und angriffslustiger dein Reich ist, desto eher hören die anderen Reiche "
			+ "davon – nahe Nachbarn schneller als ferne. Bei Gerüchten schicken sie Spione, ist dein Reich entdeckt, "
			+ "planen sie Angriffe. Aggression (Angriffe, Zerstörung, getötete Boten) klingt mit der Zeit ab; "
			+ "die Reichstarnung senkt den Wert, kostet aber laufend Mana. Späher, eigene Spione und das "
			+ "Kundschafterhaus entdecken fremde Spione.")
	page.add_child(hint)


func _build_realms(page: HBoxContainer) -> void:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_realm_list = VBoxContainer.new()
	_realm_list.add_theme_constant_override("separation", 6)
	_realm_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_realm_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_realm_list)

	page.add_child(_separator())

	_realm_detail = VBoxContainer.new()
	_realm_detail.add_theme_constant_override("separation", 8)
	_realm_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_realm_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_realm_detail)
	var head := _row(_realm_detail)
	_realm_swatch = ColorRect.new()
	_realm_swatch.custom_minimum_size = Vector2(18, 18)
	_realm_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_realm_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_realm_swatch)
	_realm_name = _label(22, _light)
	_realm_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_realm_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_realm_name)
	_realm_people = _wrap_label(16, _accent.lightened(0.2))
	_realm_detail.add_child(_realm_people)
	var scroll2 := ScrollContainer.new()
	scroll2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_realm_detail.add_child(scroll2)
	_realm_summary = _wrap_label(16, COLOR_TEXT)
	_realm_summary.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	scroll2.add_child(_realm_summary)
	var actions := _row(_realm_detail)
	_realm_scout_button = _tip_button("Spion schicken: Auskundschaften")
	_realm_scout_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_realm_scout_button.tip_source = _realm_scout_tip
	_realm_scout_button.pressed.connect(_on_realm_mission_pressed.bind("scout"))
	actions.add_child(_realm_scout_button)
	_realm_incite_button = _tip_button("Aufhetzen …")
	_realm_incite_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_realm_incite_button.tip_source = _realm_incite_tip
	_realm_incite_button.pressed.connect(_on_realm_mission_pressed.bind("incite"))
	actions.add_child(_realm_incite_button)
	_realm_jump_button = _plain_button("Hinspringen")
	_realm_jump_button.tooltip_text = "Kamera zur Burg bzw. zum Dorf (Fenster schliesst)"
	_realm_jump_button.pressed.connect(_on_realm_jump_pressed)
	actions.add_child(_realm_jump_button)


func _build_spies(page: HBoxContainer) -> void:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(left)
	var head := _row(left)
	_spy_count = _label(17, _light)
	_spy_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_spy_count)
	_recruit_button = _tip_button("Spion beschwören")
	_recruit_button.tip_source = _recruit_tip
	_recruit_button.pressed.connect(_on_recruit_pressed)
	head.add_child(_recruit_button)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_spy_list = VBoxContainer.new()
	_spy_list.add_theme_constant_override("separation", 6)
	_spy_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spy_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_spy_list)
	_spy_empty = _wrap_label(16, COLOR_DIM)
	left.add_child(_spy_empty)

	page.add_child(_separator())

	_spy_detail = VBoxContainer.new()
	_spy_detail.add_theme_constant_override("separation", 8)
	_spy_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spy_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_spy_detail)
	_spy_name = _label(22, _light)
	_spy_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_spy_detail.add_child(_spy_name)
	_spy_text = _wrap_label(16, COLOR_TEXT)
	_spy_detail.add_child(_spy_text)
	_spy_detail.add_child(_section_label("Neuer Auftrag"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spy_detail.add_child(grid)
	var l1 := _label(16, COLOR_DIM)
	l1.text = "Auftrag"
	grid.add_child(l1)
	_mission_option = _option()
	_mission_option.tooltip_text = "Auftrag des Spions: auskundschaften, Dorf aufhetzen, Rivalen aufhetzen …"
	for m in SpySystem.MISSIONS:
		_mission_option.add_item(SpySystem.mission_name(str(m)))
	_mission_option.item_selected.connect(_on_mission_selected)
	grid.add_child(_mission_option)
	var l2 := _label(16, COLOR_DIM)
	l2.text = "Ziel"
	grid.add_child(l2)
	_target_option = _option()
	_target_option.tooltip_text = "Ziel des Auftrags (Reich bzw. Dorf)"
	_target_option.item_selected.connect(_on_target_selected)
	grid.add_child(_target_option)
	_target2_label = _label(16, COLOR_DIM)
	grid.add_child(_target2_label)
	_target2_option = _option()
	_target2_option.tooltip_text = "Zweites Ziel (z. B. gegen wen aufgehetzt wird)"
	_target2_option.item_selected.connect(_on_target2_selected)
	grid.add_child(_target2_option)
	_preview_label = _wrap_label(15, COLOR_DIM)
	_spy_detail.add_child(_preview_label)

	var actions := _row(_spy_detail)
	_assign_button = _tip_button("Auftrag erteilen")
	_assign_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_assign_button.tip_source = _assign_tip
	_assign_button.pressed.connect(_on_assign_pressed)
	actions.add_child(_assign_button)
	_recall_button = _plain_button("Zurückrufen")
	_recall_button.tooltip_text = "Auftrag beenden – der Spion kehrt zur Burg zurück"
	_recall_button.pressed.connect(_on_recall_pressed)
	actions.add_child(_recall_button)
	_spy_jump_button = _plain_button("Hinspringen")
	_spy_jump_button.tooltip_text = "Spion auswählen und hinspringen (Fenster schliesst)"
	_spy_jump_button.pressed.connect(_on_spy_jump_pressed)
	actions.add_child(_spy_jump_button)
	_spy_info = _wrap_label(15, COLOR_WARN)
	_spy_detail.add_child(_spy_info)


func _make_tab(text: String, group: ButtonGroup) -> ResearchTipButton:
	return UiStyle.tab_button(text, group, _evil)


func _show_tab(tab: String) -> void:
	_tab = tab if _tabs.has(tab) else TAB_OVERVIEW
	for id in _tabs:
		var entry: Dictionary = _tabs[id]
		(entry["button"] as Button).set_pressed_no_signal(id == _tab)
		(entry["page"] as Control).visible = id == _tab
	match _tab:
		TAB_REALMS:
			_footer.text = "Kundschaft (Punkte): 1 Gerüchte · 2 Bericht (Schätzung) · 3 genau – sie veraltet mit der Zeit  ·  K / Esc: schliessen"
		TAB_SPIES:
			_footer.text = "Spione sind getarnt; entdeckt werden sie kurz sichtbar und fliehen heim  ·  K / Esc: schliessen"
		_:
			_footer.text = "Entdeckungswert: wie bekannt dein Reich ist  ·  Balken oben in der Leiste  ·  K / Esc: schliessen"
	if visible:
		_refresh()


func _queue_place() -> void:
	if visible:
		_place.call_deferred()


## Mitte oben; bei kleinem Fenster verkleinert, aber nie ausserhalb
func _place() -> void:
	UiStyle.place_window(self, DESIGN_WIDTH, TOP)


# ---------------------------------------------------------------------------
# Aktualisieren
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if game == null or not visible:
		return
	var k: Kingdom = game.player
	var esp: EspionageSystem = game.espionage_system
	var spies: SpySystem = game.spy_system
	var value := esp.get_discovery(k)
	_set_text(_count_label, "Entdeckungswert %d · Spione %d/%d" % [roundi(value), spies.get_spies(k).size(),
			spies.max_spies(k)], COLOR_DIM)
	match _tab:
		TAB_REALMS:
			_refresh_realms(k)
		TAB_SPIES:
			_refresh_spies(k)
		_:
			_refresh_overview(k)
	var hud: Node = game.hud
	_debug_row.visible = hud != null and hud.has_method("is_debug_visible") and bool(hud.call("is_debug_visible"))


# --- Übersicht

func _refresh_overview(k: Kingdom) -> void:
	var esp: EspionageSystem = game.espionage_system
	var value := esp.get_discovery(k)
	var tier := EspionageSystem.discovery_tier(value)
	var color: Color = tier["color"]
	_set_text(_disc_label, "Dein Entdeckungswert: %d – %s" % [roundi(value), str(tier["name"])], color)
	_disc_bar.fill_color = color
	var max_display := float(DataDB.esp("discovery.max_display", 150))
	_disc_bar.set_value(minf(value, max_display), max_display, "%d" % roundi(value))
	_set_text(_causes_label, causes_text(esp.get_discovery_parts(k), esp.get_aggression(k) > 0.5), COLOR_TEXT)
	# Reichstarnung
	var cloaked := esp.is_cloaked(k)
	var spell_id := esp.get_cloak_spell(k)
	var spell_name := str(DataDB.get_spell(spell_id).get("name", "Reichstarnung")) if not spell_id.is_empty() else "Reichstarnung"
	var reason := esp.can_toggle_cloak(k)
	var cost := esp.cloak_upkeep(k) * 60.0
	var cloak_text := ""
	if cloaked:
		cloak_text = "%s ist aktiv: Entdeckungswert −%d %%, kostet laufend %s Mana/min." % [spell_name,
				roundi(float(DataDB.esp("cloak.reduction", 0.4)) * 100.0), _num(cost)]
	else:
		cloak_text = "%s (Zauber): senkt den Entdeckungswert um %d %% und kostet laufend Mana (jetzt etwa %s Mana/min); endet bei Manamangel." % [
				spell_name, roundi(float(DataDB.esp("cloak.reduction", 0.4)) * 100.0), _num(cost)]
		if not reason.is_empty():
			cloak_text += "\n" + reason
	_set_text(_cloak_label, cloak_text, COLOR_GOOD if cloaked else (COLOR_TEXT if reason.is_empty() else COLOR_DIM))
	_set_button_text(_cloak_button, "Tarnung ausschalten" if cloaked else "Tarnung einschalten")
	_set_disabled(_cloak_button, not cloaked and not reason.is_empty())
	_set_text(_aware_label, awareness_text(k), COLOR_TEXT)


## Ursachen des Entdeckungswerts, je eine Zeile ("Gebäude +18", "Reichstarnung −17")
static func causes_text(parts: Dictionary, aggression_active: bool = false) -> String:
	var lines: PackedStringArray = []
	for key in CAUSE_ORDER:
		var v := float(parts.get(key, 0.0))
		if key == "cloak" and v >= -0.05:
			continue
		var line := "%s %s" % [str(CAUSE_NAMES[key]), ResourceBar.format_signed(roundf(v))]
		if key == "aggression" and aggression_active:
			line += " (klingt ab)"
		lines.append(line)
	return "\n".join(lines)


## Aufmerksamkeit der KI-Reiche auf den Spieler: ab Kundschaft 2 als Wort, ab 3 genau, sonst "?"
func awareness_text(k: Kingdom) -> String:
	var esp: EspionageSystem = game.espionage_system
	var lines: PackedStringArray = []
	for o in game.ai_system.get_ai_kingdoms():
		var ai: Kingdom = o
		var level := esp.get_intel_level(k, ai)
		var tier := esp.get_awareness_tier(ai, k)
		var text := "?"
		if level >= 3:
			text = "%s (%d %%)" % [EspionageSystem.awareness_tier_name(tier), roundi(esp.get_awareness(ai, k))]
		elif level >= 2:
			text = EspionageSystem.awareness_tier_name(tier)
		lines.append("%s: %s" % [ai.display_name, text])
	if lines.is_empty():
		return "Keine feindlichen Reiche mehr."
	lines.append("(„?“ = Kundschaft nötig: Späher oder Spione schicken)")
	return "\n".join(lines)


# --- Reiche und Dörfer

## KI-Reiche (auch gefallene, am Ende) und selbstständige Dörfer (nach Entfernung)
func realm_list() -> Array:
	var list: Array = []
	var fallen: Array = []
	for o in game.ai_system.get_ai_kingdoms(true):
		var k: Kingdom = o
		if k.defeated:
			fallen.append(k)
		else:
			list.append(k)
	var vs: VillageSystem = game.village_system
	var villages: Array = vs.get_villages()
	var from := _home_pos()
	villages.sort_custom(func(a: Kingdom, b: Kingdom) -> bool:
		return from.distance_squared_to(vs.get_center(a)) < from.distance_squared_to(vs.get_center(b)))
	list.append_array(villages)
	list.append_array(fallen)
	return list


func _refresh_realms(k: Kingdom) -> void:
	var list := realm_list()
	var key: Array = []
	for o in list:
		key.append([(o as Kingdom).id, (o as Kingdom).defeated])
	if key != _realm_key:
		_rebuild_realm_list(list, key)
	var found := false
	for o in list:
		if (o as Kingdom).id == _realm_id:
			found = true
	if not found:
		_realm_id = (list[0] as Kingdom).id if not list.is_empty() else 0
	for o in list:
		_refresh_realm_entry(k, o)
	_realm_detail.visible = _realm_id != 0
	if _realm_id != 0:
		_refresh_realm_detail(k, game.get_kingdom(_realm_id))


func _rebuild_realm_list(list: Array, key: Array) -> void:
	_realm_key = key
	for child in _realm_list.get_children():
		_realm_list.remove_child(child)
		child.queue_free()
	_realm_entries.clear()
	for o in list:
		var r: Kingdom = o
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, ENTRY_HEIGHT)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "%s – Klick: Kundschaft und Aufträge" % r.display_name
		b.pressed.connect(_on_realm_pressed.bind(r.id))
		_realm_list.add_child(b)
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 8.0
		box.offset_top = 5.0
		box.offset_right = -8.0
		box.offset_bottom = -6.0
		box.add_theme_constant_override("separation", 2)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(box)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(top)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.color = r.color
		top.add_child(swatch)
		var name_label := _label(17, _light)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.text = r.display_name
		top.add_child(name_label)
		var tag := _label(14, COLOR_TEXT)
		top.add_child(tag)
		var bottom := HBoxContainer.new()
		bottom.add_theme_constant_override("separation", 8)
		bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(bottom)
		var dots := IntelDots.new()
		bottom.add_child(dots)
		var sub := _label(14, COLOR_DIM)
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		bottom.add_child(sub)
		_realm_entries[r.id] = {"button": b, "swatch": swatch, "name": name_label, "tag": tag, "dots": dots, "sub": sub}


func _refresh_realm_entry(k: Kingdom, r: Kingdom) -> void:
	var e: Dictionary = _realm_entries.get(r.id, {})
	if e.is_empty():
		return
	var esp: EspionageSystem = game.espionage_system
	var dots: IntelDots = e["dots"]
	if r.defeated:
		_set_text(e["name"], r.display_name, COLOR_GREY)
		_set_text(e["tag"], "gefallen", COLOR_GREY)
		_set_text(e["sub"], "Ruinen – das Reich ist besiegt", COLOR_GREY)
		dots.level = 0
	else:
		_set_text(e["name"], r.display_name, _light)
		var tag := _relation_tag(k, r)
		_set_text(e["tag"], str(tag[0]), tag[1])
		var level := esp.get_intel_level(k, r)
		dots.level = level
		dots.color = COLOR_INTEL if level >= 2 else COLOR_DIM
		_set_text(e["sub"], "%s · %s" % [_kind_text(r), _intel_age_text(k, r)], COLOR_DIM)
	var b: Button = e["button"]
	if b.button_pressed != (r.id == _realm_id):
		b.set_pressed_no_signal(r.id == _realm_id)


## Beziehung zum Spieler als [Text, Farbe]
func _relation_tag(k: Kingdom, r: Kingdom) -> Array:
	if game.are_hostile(k, r):
		return ["Krieg", COLOR_WAR]
	var vs: VillageSystem = game.village_system
	if vs.is_village(r):
		var tier := DiplomacySystem.tier_for(game.diplomacy_system.get_reputation(r, k))
		return [DiplomacySystem.tier_name(tier), DiplomacySystem.tier_color(tier)]
	if game.are_allied(k, r):
		return ["Bündnis", COLOR_GOOD]
	return ["Frieden", COLOR_DIM]


## "Reich der Orks" / "Dorf (Zwerge)"
func _kind_text(r: Kingdom) -> String:
	var vs: VillageSystem = game.village_system
	if vs.is_village_kingdom(r):
		return "Dorf (%s)" % str(vs.get_people(r).get("name", "?"))
	return "Reich (%s)" % str(DataDB.get_people(r.people_id).get("name", "?"))


## "Bericht, vor 4 min" / "keine Kundschaft"
func _intel_age_text(k: Kingdom, r: Kingdom) -> String:
	var esp: EspionageSystem = game.espionage_system
	var level := esp.get_intel_level(k, r)
	var names: Array = DataDB.esp("intel.names", ["Unbekannt", "Gerüchte", "Bericht", "Genau"])
	var text := str(names[clampi(level, 0, names.size() - 1)])
	var age := esp.get_intel_age(k, r)
	if age == INF:
		return text if level > 0 else "keine Kundschaft"
	if age < 60.0:
		return text + ", gerade eben"
	return text + ", vor %d min" % floori(age / 60.0)


func _refresh_realm_detail(k: Kingdom, r: Kingdom) -> void:
	if r == null:
		return
	var esp: EspionageSystem = game.espionage_system
	_realm_swatch.color = r.color
	_set_text(_realm_name, r.display_name, COLOR_GREY if r.defeated else _light)
	var people_text := _kind_text(r)
	if not r.defeated:
		people_text += "  ·  %d Kacheln von deiner Burg  ·  %s" % [_distance_tiles(r), str(_relation_tag(k, r)[0])]
	_set_text(_realm_people, people_text, _accent.lightened(0.2))
	var summary := ""
	if r.defeated:
		summary = "Dieses Reich ist gefallen."
		for f in game.victory_system.fallen:
			if int(f.get("id", 0)) == r.id:
				var why := str(f.get("reason", ""))
				summary = "Dieses Reich ist gefallen: %s." % str(FALLEN_REASONS.get(why, why))
	else:
		summary = esp.get_kingdom_summary(r, k)
	_set_text(_realm_summary, summary, COLOR_TEXT)
	var vs: VillageSystem = game.village_system
	var village := vs.is_village(r)
	_realm_scout_button.disabled = r.defeated
	_realm_incite_button.visible = not r.defeated and (village or game.ai_system.get_ai_kingdoms().size() >= 2)
	_set_button_text(_realm_incite_button, "Dorf aufhetzen …" if village else "Rivalen aufhetzen …")
	_realm_jump_button.disabled = r.defeated


# --- Spione

func _refresh_spies(k: Kingdom) -> void:
	var spies: SpySystem = game.spy_system
	var list := spies.get_spies(k)
	var key: Array = []
	for o in list:
		key.append((o as Unit).uid)
	if key != _spy_key:
		_rebuild_spy_list(list, key)
	var found := false
	for o in list:
		if (o as Unit).uid == _spy_uid:
			found = true
	if not found:
		_spy_uid = (list[0] as Unit).uid if not list.is_empty() else 0
	var queued := spies.count_queued(k)
	var count_text := "Spione: %d/%d" % [list.size(), spies.max_spies(k)]
	if queued > 0:
		count_text += " (+%d in Arbeit)" % queued
	_set_text(_spy_count, count_text, _light)
	var reason := spies.can_recruit(k)
	_set_disabled(_recruit_button, not reason.is_empty())
	# Ohne Spione: Hinweis; sonst nur der Grund, warum kein weiterer geht
	_spy_empty.visible = list.is_empty() or not reason.is_empty()
	if list.is_empty():
		var text := "Noch keine Spione."
		text += "\n" + (reason if not reason.is_empty() else "„Spion beschwören“ – in der Burg oder im Kundschafterhaus.")
		_set_text(_spy_empty, text, COLOR_DIM)
	elif not reason.is_empty():
		_set_text(_spy_empty, "Kein weiterer Spion: " + reason, COLOR_DIM)
	for o in list:
		_refresh_spy_entry(o)
	_spy_detail.visible = _spy_uid != 0
	if _spy_uid != 0:
		var u: Variant = game.find_by_uid(_spy_uid)
		if u is Unit:
			_refresh_spy_detail(k, u)


func _rebuild_spy_list(list: Array, key: Array) -> void:
	_spy_key = key
	for child in _spy_list.get_children():
		_spy_list.remove_child(child)
		child.queue_free()
	_spy_entries.clear()
	for o in list:
		var u: Unit = o
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, ENTRY_HEIGHT + 14.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "Spion – Klick: Auftrag wählen"
		b.pressed.connect(select_spy.bind(u.uid))
		_spy_list.add_child(b)
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 8.0
		box.offset_top = 5.0
		box.offset_right = -8.0
		box.offset_bottom = -6.0
		box.add_theme_constant_override("separation", 2)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(box)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(top)
		var name_label := _label(17, _light)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		top.add_child(name_label)
		var tag := _label(14, COLOR_TEXT)
		top.add_child(tag)
		var sub := _label(14, COLOR_DIM)
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(sub)
		var bar := HpBar.new()
		bar.font_size = 13
		bar.custom_minimum_size = Vector2(0, 17)
		box.add_child(bar)
		_spy_entries[u.uid] = {"button": b, "name": name_label, "tag": tag, "sub": sub, "bar": bar}


func _refresh_spy_entry(u: Unit) -> void:
	var e: Dictionary = _spy_entries.get(u.uid, {})
	if e.is_empty():
		return
	var spies: SpySystem = game.spy_system
	var rec := spies.get_record(u)
	var revealed := bool(rec.get("revealed", false)) and not u.stealthed
	var next := spies.xp_for_next(u)
	var xp_text := "EP %s/%s" % [_num(float(rec.get("xp", 0.0))), _num(next)] if next >= 0.0 else "höchste Stufe"
	_set_text(e["name"], "%s · Stufe %d · %s" % [u.get_display_name(), spies.get_level(u), xp_text],
			COLOR_BAD if revealed else _light)
	var state := str(rec.get("state", "idle"))
	_set_text(e["tag"], "enttarnt" if revealed else SpySystem.state_name(state), COLOR_BAD if revealed else COLOR_DIM)
	var mission := str(rec.get("mission", ""))
	var bar: HpBar = e["bar"]
	if mission.is_empty():
		_set_text(e["sub"], "Kein Auftrag", COLOR_DIM)
		bar.fill_color = COLOR_GREY
		bar.set_value(0.0, 1.0, "–")
	else:
		_set_text(e["sub"], _mission_line(rec), COLOR_TEXT)
		var p := spies.get_progress(u)
		bar.fill_color = COLOR_INTEL
		bar.set_value(p, 1.0, "%d %%" % roundi(p * 100.0))
	var b: Button = e["button"]
	if b.button_pressed != (u.uid == _spy_uid):
		b.set_pressed_no_signal(u.uid == _spy_uid)


## "Auskundschaften → Reich der Orks" / "Dorf aufhetzen → Dorf gegen Reich"
func _mission_line(rec: Dictionary) -> String:
	var mission := str(rec.get("mission", ""))
	var target: Kingdom = game.get_kingdom(int(rec.get("target_id", 0)))
	var text := "%s → %s" % [SpySystem.mission_name(mission), target.display_name if target != null else "?"]
	var other: Kingdom = game.get_kingdom(int(rec.get("target2_id", 0)))
	if other != null:
		text += (" gegen %s" if mission == "incite_village" else " und %s") % other.display_name
	return text


func _refresh_spy_detail(k: Kingdom, u: Unit) -> void:
	var spies: SpySystem = game.spy_system
	_set_text(_spy_name, u.get_display_name(), _light)
	_set_text(_spy_text, spies.get_spy_text(u), COLOR_TEXT)
	var mi := SpySystem.MISSIONS.find(_mission)
	if _mission_option.selected != mi:
		_mission_option.select(mi)
	# Ziele (nur neu bauen, wenn sich die Liste ändert)
	var targets := spies.get_valid_targets(k, _mission)
	_target_ids = _fill_option(_target_option, targets, _target_ids)
	if not _target_ids.has(_target_id):
		_target_id = int(_target_ids[0]) if not _target_ids.is_empty() else 0
	_select_option(_target_option, _target_ids, _target_id)
	var target: Kingdom = game.get_kingdom(_target_id) if _target_id != 0 else null
	var needs2 := _mission != "scout"
	_target2_label.visible = needs2
	_target2_option.visible = needs2
	var target2: Kingdom = null
	if needs2:
		_set_text(_target2_label, "gegen" if _mission == "incite_village" else "und", COLOR_DIM)
		var targets2 := spies.get_valid_targets2(k, _mission, target)
		_target2_ids = _fill_option(_target2_option, targets2, _target2_ids)
		if not _target2_ids.has(_target2_id):
			_target2_id = int(_target2_ids[0]) if not _target2_ids.is_empty() else 0
		_select_option(_target2_option, _target2_ids, _target2_id)
		target2 = game.get_kingdom(_target2_id) if _target2_id != 0 else null
	# Vorschau der Entdeckungsgefahr am Ziel
	var preview := ""
	if target != null:
		var chance := spies.preview_detection(u, target)
		var interval := int(DataDB.esp("spies.detect_interval", 10))
		preview = "Entdeckungsgefahr dort: ~%d %% je %d s" % [roundi(chance * 100.0), interval]
		if chance > 0.0:
			preview += " (im Mittel nach etwa %d s)" % roundi(float(interval) / chance)
		preview += "  ·  " + _mission_hint(_mission)
	_set_text(_preview_label, preview, COLOR_DIM)
	var reason := spies.can_assign(u, _mission, target, target2)
	_set_disabled(_assign_button, not reason.is_empty())
	var rec := spies.get_record(u)
	var busy := not str(rec.get("mission", "")).is_empty() or str(rec.get("state", "idle")) == "travel"
	_set_disabled(_recall_button, not busy)
	_set_text(_spy_info, reason, COLOR_WARN)


static func _mission_hint(mission: String) -> String:
	match mission:
		"incite_village":
			return "senkt den Ruf des Dorfs gegenüber dem Reich"
		"incite_rival":
			return "treibt zwei Reiche in den Krieg gegeneinander"
	return "liefert genaue Kundschaft, solange der Spion bleibt"


## Auswahlliste mit Reichen füllen (nur wenn sich die ids ändern); gibt die ids zurück
func _fill_option(option: OptionButton, kingdoms: Array, old_ids: Array) -> Array:
	var ids: Array = []
	for o in kingdoms:
		ids.append((o as Kingdom).id)
	if ids == old_ids:
		return old_ids
	option.clear()
	for o in kingdoms:
		option.add_item((o as Kingdom).display_name)
	return ids


static func _select_option(option: OptionButton, ids: Array, id: int) -> void:
	var index := ids.find(id)
	if option.selected != index:
		option.select(index)


## Passender Auftrag für ein Ziel (Dorf aufhetzen geht nur bei Dörfern, sonst Auskundschaften)
func _choose_mission_for(target: Kingdom) -> void:
	if target == null:
		return
	var spies: SpySystem = game.spy_system
	if not spies.get_valid_targets(game.player, _mission).has(target):
		_mission = "scout"


# ---------------------------------------------------------------------------
# Tooltips
# ---------------------------------------------------------------------------

func _cloak_tip() -> String:
	var esp: EspionageSystem = game.espionage_system
	var k: Kingdom = game.player
	var tip := ResearchTipButton
	var lines: PackedStringArray = ["[b]Reichstarnung[/b]"]
	if esp.is_cloaked(k):
		lines.append("Aktiv – Klick schaltet sie aus.")
		lines.append("Kosten: %s Mana/min" % _num(esp.cloak_upkeep(k) * 60.0))
		return "\n".join(lines)
	lines.append("Senkt den Entdeckungswert um %d %%." % roundi(float(DataDB.esp("cloak.reduction", 0.4)) * 100.0))
	lines.append("Kosten: Zauber an der Burg, danach etwa %s Mana/min" % _num(esp.cloak_upkeep(k) * 60.0))
	var reason := esp.can_toggle_cloak(k)
	if not reason.is_empty():
		lines.append(tip.colored(reason, COLOR_BAD))
	return "\n".join(lines)


func _recruit_tip() -> String:
	var spies: SpySystem = game.spy_system
	var k: Kingdom = game.player
	var tip := ResearchTipButton
	var def := SpySystem.spy_type(k.faction_id)
	var lines: PackedStringArray = ["[b]%s beschwören[/b]" % tip.esc(str(def.get("name", "Spion")))]
	var b := spies.get_recruit_building(k)
	lines.append("Kosten: %s" % tip.esc(DataDB.cost_to_text(game.summon_system.get_cost(k, str(def.get("id", ""))))))
	lines.append("Ort: %s" % (b.get_display_name() if b != null else "Burg oder Kundschafterhaus"))
	lines.append("Im Kundschafterhaus beginnen Spione eine Stufe höher.")
	var reason := spies.can_recruit(k)
	if not reason.is_empty():
		lines.append(tip.colored(reason, COLOR_BAD))
	return "\n".join(lines)


func _assign_tip() -> String:
	var u := _selected_spy()
	if u == null:
		return ""
	var reason: String = game.spy_system.can_assign(u, _mission, _kingdom(_target_id), _kingdom(_target2_id))
	var tip := ResearchTipButton
	var lines: PackedStringArray = ["[b]%s[/b]" % SpySystem.mission_name(_mission), tip.esc(_mission_hint(_mission))]
	if not reason.is_empty():
		lines.append(tip.colored(reason, COLOR_BAD))
	return "\n".join(lines)


func _realm_scout_tip() -> String:
	var tip := ResearchTipButton
	var lines: PackedStringArray = ["[b]Spion schicken[/b]", "Wählt einen freien Spion und öffnet den Reiter „Spione“ mit diesem Ziel."]
	if game.spy_system.get_spies(game.player).is_empty():
		lines.append(tip.colored("Noch keine Spione – erst einen beschwören", COLOR_WARN))
	return "\n".join(lines)


func _realm_incite_tip() -> String:
	var r := _kingdom(_realm_id)
	if r == null:
		return ""
	if game.village_system.is_village(r):
		return "[b]Dorf aufhetzen[/b]\nEin Spion senkt im Dorf den Ruf eines feindlichen Reichs."
	return "[b]Rivalen aufhetzen[/b]\nEin Spion schürt in diesem Reich die Spannung zu einem anderen Reich – bis zum Krieg."


# ---------------------------------------------------------------------------
# Aktionen
# ---------------------------------------------------------------------------

func _on_cloak_pressed() -> void:
	var reason: String = game.espionage_system.toggle_cloak(game.player)
	if not reason.is_empty():
		Notify.warning(reason.get_slice("\n", 0))
	_refresh()


func _on_recruit_pressed() -> void:
	var spies: SpySystem = game.spy_system
	var reason := spies.can_recruit(game.player)
	if not reason.is_empty() or not spies.recruit(game.player):
		Notify.warning(reason.get_slice("\n", 0) if not reason.is_empty() else "Beschwören nicht möglich")
	_refresh()


func _on_realm_pressed(id: int) -> void:
	_realm_id = id
	_refresh()


## Knöpfe im Reiter "Reiche & Dörfer": Auftrag vorwählen, freien Spion wählen, Reiter "Spione"
func _on_realm_mission_pressed(kind: String) -> void:
	var r := _kingdom(_realm_id)
	if r == null:
		return
	if kind == "scout":
		set_mission_choice("scout", r.id)
	elif game.village_system.is_village(r):
		set_mission_choice("incite_village", r.id, 0)
	else:
		set_mission_choice("incite_rival", r.id, 0)
	var free := _free_spy()
	if free != null:
		_spy_uid = free.uid
	_show_tab(TAB_SPIES)


## Erster Spion ohne Auftrag (sonst der erste überhaupt, null wenn keiner)
func _free_spy() -> Unit:
	var spies: SpySystem = game.spy_system
	var list := spies.get_spies(game.player)
	for o in list:
		var u: Unit = o
		if str(spies.get_record(u).get("mission", "")).is_empty() and str(spies.get_record(u).get("state", "")) != "return":
			return u
	return list[0] as Unit if not list.is_empty() else null


func _on_realm_jump_pressed() -> void:
	var r := _kingdom(_realm_id)
	if r == null:
		return
	var vs: VillageSystem = game.village_system
	if vs.is_village_kingdom(r):
		var hall := vs.get_hall(r)
		if hall != null:
			game.selection.select([hall])
		game.camera.focus_on(vs.get_center(r))
	elif is_instance_valid(r.castle):
		game.selection.select([r.castle])
		game.camera.focus_on(r.castle.get_center())
	close()


func _on_mission_selected(index: int) -> void:
	if index >= 0 and index < SpySystem.MISSIONS.size():
		_mission = str(SpySystem.MISSIONS[index])
	_refresh()


func _on_target_selected(index: int) -> void:
	if index >= 0 and index < _target_ids.size():
		_target_id = int(_target_ids[index])
	_refresh()


func _on_target2_selected(index: int) -> void:
	if index >= 0 and index < _target2_ids.size():
		_target2_id = int(_target2_ids[index])
	_refresh()


## Auftrag mit der aktuellen Wahl erteilen (Knopf und Rauchtest). "" = ok, sonst der Grund.
func assign_selected() -> String:
	var u := _selected_spy()
	if u == null:
		return "Kein Spion gewählt"
	var target := _kingdom(_target_id)
	var target2: Kingdom = _kingdom(_target2_id) if _mission != "scout" else null
	var reason: String = game.spy_system.assign_mission(u, _mission, target, target2)
	if reason.is_empty():
		Notify.info("%s: %s" % [u.get_display_name(), _mission_line(game.spy_system.get_record(u))], u.position)
	return reason


func _on_assign_pressed() -> void:
	var reason := assign_selected()
	if not reason.is_empty():
		Notify.warning(reason)
	_refresh()


func _on_recall_pressed() -> void:
	var u := _selected_spy()
	if u != null:
		game.spy_system.recall(u)
	_refresh()


func _on_spy_jump_pressed() -> void:
	var u := _selected_spy()
	if u == null:
		return
	game.selection.select([u])
	game.camera.focus_on(u.position)
	close()


## Debug-Knöpfe (F3): "aware", "intel", "attack", "defeat", "rivals"
func debug_action(action: String) -> void:
	var k: Kingdom = game.player
	var esp: EspionageSystem = game.espionage_system
	var ai: AISystem = game.ai_system
	var list := ai.get_ai_kingdoms()
	match action:
		"aware":
			for o in list:
				esp.debug_set_awareness(o, k, esp.get_awareness(o, k) + 30.0)
			Notify.info("Debug: Aufmerksamkeit aller KI-Reiche +30")
		"intel":
			esp.debug_full_intel(k)
			Notify.info("Debug: volle Kundschaft")
		"attack":
			var near := _nearest_ai(list)
			if near == null or not ai.debug_force_attack(near, k):
				Notify.warning("Debug: keine KI kann jetzt angreifen")
			else:
				Notify.info("Debug: %s greift an" % near.display_name)
		"defeat":
			var target := _kingdom(_realm_id)
			if target == null or not list.has(target):
				target = list[0] as Kingdom if not list.is_empty() else null
			if target != null:
				game.victory_system.debug_defeat(target, "castle")
		"rivals":
			if list.size() >= 2:
				ai.debug_set_tension(list[0], list[1], 95.0)
				Notify.info("Debug: Spannung %s – %s auf 95 (Krieg zur vollen Stunde)" % [(list[0] as Kingdom).display_name,
						(list[1] as Kingdom).display_name])
			else:
				Notify.warning("Debug: dafür braucht es zwei KI-Reiche")
	_refresh()


func _nearest_ai(list: Array) -> Kingdom:
	var from := _home_pos()
	var best: Kingdom = null
	var best_d := INF
	for o in list:
		var k: Kingdom = o
		if not is_instance_valid(k.castle):
			continue
		var d := from.distance_squared_to(k.castle.get_center())
		if d < best_d:
			best_d = d
			best = k
	return best


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

func _selected_spy() -> Unit:
	if game == null or _spy_uid == 0:
		return null
	var u: Variant = game.find_by_uid(_spy_uid)
	return u as Unit if u is Unit and (u as Unit).is_alive() else null


func _kingdom(id: int) -> Kingdom:
	if game == null or id == 0:
		return null
	return game.get_kingdom(id)


func _home_pos() -> Vector2:
	var k: Kingdom = game.player
	if is_instance_valid(k.castle):
		return k.castle.get_center()
	return game.world.cell_to_world(game.world.start_cell)


## Entfernung Burg – Burg bzw. Dorf in Kacheln
func _distance_tiles(r: Kingdom) -> int:
	var vs: VillageSystem = game.village_system
	var center := Vector2.ZERO
	if vs.is_village_kingdom(r):
		center = vs.get_center(r)
	elif is_instance_valid(r.castle):
		center = r.castle.get_center()
	else:
		return 0
	return roundi(_home_pos().distance_to(center) / float(game.world.tile_size))


static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return str(roundi(v))
	return ("%.1f" % v).replace(".", ",")


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	return row


func _separator() -> ColorRect:
	var sep := ColorRect.new()
	sep.color = Color(_accent, 0.3)
	sep.custom_minimum_size = Vector2(1, 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


func _section_label(text: String) -> Label:
	var label := _label(17, _accent.lightened(0.2))
	label.text = text
	return label


func _option() -> OptionButton:
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.add_theme_font_size_override("font_size", 16)
	option.custom_minimum_size = Vector2(320, 34)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return option


func _panel_style() -> StyleBoxFlat:
	return UiStyle.window_style(_evil)


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


func _wrap_label(font_size: int, color: Color) -> Label:
	var label := _label(font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _tip_button(text: String) -> ResearchTipButton:
	var b := ResearchTipButton.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 36)
	return b


func _plain_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 36)
	return b


func _set_text(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _set_button_text(b: Button, text: String) -> void:
	if b.text != text:
		b.text = text


func _set_disabled(b: Button, disabled: bool) -> void:
	if b.disabled != disabled:
		b.disabled = disabled


func _evil_or(evil_color: Color, good_color: Color) -> Color:
	return evil_color if _evil else good_color
