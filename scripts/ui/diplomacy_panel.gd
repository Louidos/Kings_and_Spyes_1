## DiplomacyPanel
##
## Diplomatiefenster (Taste N, Button "Diplomatie (N)" oben; N, Esc oder ×
## schliesst). Gleiche Bauart wie Forschungs- und Heldenfenster (eigene Ebene,
## Mitte oben); das Spiel läuft weiter. Es ist immer nur eines der drei offen.
## - Reiter "Dörfer": links die Liste aller Dörfer (Volksfarbe, Name, Volk,
##   Entfernung zur Burg, grobe Stärke, Ruf als Balken mit Stufe, Vertrag bzw.
##   Krieg; aufgenommene, eroberte und zerstörte grau), selbstständige zuerst,
##   nach Entfernung sortiert.
## - Rechts das gewählte Dorf: Volk mit Beschreibung, Stärken und Schwächen,
##   Produktion, Miliz und Vorrat, Ruf mit Verlauf, Vertrag mit Pflichten
##   (Tribut, Lieferungen, Hilfe nötig), Beziehungen zu anderen Reichen.
##   Darunter die Aktionen: Geschenk (Ware und Menge, Vorschau des Rufgewinns),
##   Verträge (Annahme-Chance auf dem Knopf, Bedingungen im Tooltip; Kündigen
##   mit zweitem Klick), Tauschhandel (Kurs, Tageslimit), Aufnahme ins Reich,
##   Drohung, Krieg erklären (zweiter Klick) bzw. Frieden anbieten und
##   Hinspringen. Gesperrte Knöpfe nennen den Grund (Tooltip und Infozeile).
##   Im F3-Modus: "Ruf +20", "Ruf −20", "Bote senden (Test)".
##   Was das Dorf mit anderen Reichen verbindet, sein Vorrat und die genaue
##   Milizzahl stehen erst mit Kundschaft (Stufe 2) bzw. einem eigenen Vertrag da.
## - Reiter "Reiche" (Phase 7): links die feindlichen KI-Reiche (Farbe, Name, Volk,
##   Krieg, Stärke nach Kundschaft: "?" / "etwa 20–30" / genau; gefallene grau),
##   rechts Volk mit Stärken und Schwächen, Beziehung (immer Krieg), bekannte Kriege,
##   Verträge mit Dörfern und Aufmerksamkeit auf dich (nur mit Kundschaft), Knöpfe
##   "Spion schicken (K)", "Hinspringen" und im F3-Modus "Besiegen (Test)".
## - Reiter "Handelswege" (Phase 9; dieselbe Liste steht auch in der Reichsübersicht,
##   Reiter "Handel"): TradeRouteList mit eigenen und gesichteten Handelswegen und der Versorgung.
## Zeigt nur an und ruft das DiplomacySystem mit dem Spieler-Reich auf (dieselben
## Funktionen nutzt ab Phase 7 die KI). Aktualisiert wird alle 0.25 s, solange
## das Fenster offen ist, und bei Signalen; die Liste wird nur neu gebaut, wenn
## sich Dörfer, Reihenfolge oder Status ändern.
class_name DiplomacyPanel
extends PanelContainer

## Fenster wurde geöffnet oder geschlossen
signal toggled(open: bool)

const TAB_VILLAGES := "villages"
const TAB_REALMS := "realms"
## Handelswege (Phase 9)
const TAB_TRADE := "trade"
const DESIGN_WIDTH := 1048.0
const TOP := 92.0
const MARGIN_X := 16.0
const MARGIN_Y := 12.0
const REFRESH_INTERVAL := 0.25
## So lange (ms) gilt der erste Klick auf Kündigen, Aufnehmen oder Krieg
const CONFIRM_MS := 3000
const LIST_WIDTH := 384.0
const ENTRY_HEIGHT := 78.0
const PAGE_HEIGHT := 700.0
## Mengen für Geschenk und Tausch (Knöpfe)
const GIFT_AMOUNTS := [25, 50, 100, 250]
const TRADE_AMOUNTS := [10, 50, 100]
## So viele Einträge des Ruf-Verlaufs
const HISTORY_LINES := 5
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.74, 0.71, 0.66)
const COLOR_GREY := Color(0.55, 0.53, 0.5)
const COLOR_BAD := Color(1.0, 0.45, 0.38)
const COLOR_GOOD := Color(0.55, 0.88, 0.5)
const COLOR_WARN := Color(1.0, 0.82, 0.35)
const COLOR_ALLY := Color(1.0, 0.84, 0.4)
const COLOR_WAR := Color(1.0, 0.5, 0.42)
## Kurzname der Verträge in der Liste
const TREATY_SHORT := {"protection": "Schutz", "trade": "Handel", "alliance": "Bündnis"}

var game: Node

var _accent := ResearchPanel.GOOD_ACCENT
var _light := ResearchPanel.GOOD_LIGHT
var _evil := false
var _tab := TAB_VILLAGES
var _timer := 0.0
var _refresh_queued := false
## Gewähltes Dorf (Kingdom.id, 0 = keins)
var _village_id := 0
## Zweiter Klick: Aktion ("cancel", "annex", "war"), Dorf und Zeitpunkt des ersten Klicks
var _confirm_action := ""
var _confirm_village := 0
var _confirm_ms := 0
## Ressourcen-ids in der Reihenfolge der Auswahllisten
var _res_ids: PackedStringArray = []
var _gift_amount := 50
var _trade_amount := 50

## Reiter: id -> {"button": ResearchTipButton, "page": Control}
var _tabs: Dictionary = {}
var _count_label: Label
var _footer: Label
## Handelsliste im Reiter "Handelswege"
var trade_list: TradeRouteList

# Liste links
var _list: VBoxContainer
## Dorf-ids und Status der zuletzt gebauten Liste (Neuaufbau nur bei Änderung)
var _list_key: Array = []
## Dorf-id -> {"button", "swatch", "name", "tag", "sub", "bar"}
var _list_entries: Dictionary = {}
var _empty_label: Label

# Einzelheiten rechts
var _detail: VBoxContainer
var _swatch: ColorRect
var _name_label: Label
var _people_label: Label
var _desc_label: Label
var _strengths_label: Label
var _weaknesses_label: Label
var _economy_label: Label
var _stock_label: Label
var _rep_bar: HpBar
var _base_label: Label
var _history_label: Label
var _treaty_info: RichTextLabel
var _relations_label: Label

# Aktionen
var _actions: VBoxContainer
var _inactive_label: Label
var _gift_option: OptionButton
var _gift_amount_buttons: Array[Button] = []
var _gift_button: ResearchTipButton
var _gift_preview: RichTextLabel
## Vertragsart -> ResearchTipButton
var _treaty_buttons: Dictionary = {}
var _cancel_button: Button
var _treaty_hint: RichTextLabel
var _trade_give_option: OptionButton
var _trade_get_option: OptionButton
var _trade_amount_buttons: Array[Button] = []
var _trade_button: ResearchTipButton
var _trade_preview: RichTextLabel
var _annex_button: ResearchTipButton
var _threat_button: ResearchTipButton
var _war_button: ResearchTipButton
var _jump_button: Button
var _action_info: RichTextLabel
var _debug_row: HBoxContainer

# Reiter "Reiche"
var _realm_id := 0
var _realm_list: VBoxContainer
var _realm_key: Array = []
## Reich-id -> {"button", "name", "tag", "sub"}
var _realm_entries: Dictionary = {}
var _realm_empty: Label
var _realm_detail: VBoxContainer
var _realm_swatch: ColorRect
var _realm_name: Label
var _realm_people: Label
var _realm_desc: Label
var _realm_strengths: Label
var _realm_weaknesses: Label
var _realm_info: Label
var _realm_spy_button: Button
var _realm_jump_button: Button
var _realm_defeat_button: Button


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
	for r in DataDB.resources:
		_res_ids.append(str(r["id"]))
	add_theme_stylebox_override("panel", _panel_style())
	# Feste Breite: umbrechende Texte kennen so ihre Breite
	custom_minimum_size = Vector2(DESIGN_WIDTH, 0)
	_build()
	var vs: VillageSystem = game.village_system
	var ds: DiplomacySystem = game.diplomacy_system
	vs.village_founded.connect(_on_changed.unbind(1))
	vs.settlement_transferred.connect(_on_changed.unbind(3))
	vs.village_destroyed.connect(_on_changed.unbind(2))
	ds.treaty_changed.connect(_on_changed.unbind(3))
	ds.reputation_tier_changed.connect(_on_changed.unbind(4))
	ds.side_switched.connect(_on_changed.unbind(3))
	game.relation_changed.connect(_on_changed.unbind(3))
	get_viewport().size_changed.connect(_place)
	Settings.changed.connect(_place)
	minimum_size_changed.connect(_queue_place)
	_show_tab(TAB_VILLAGES)


func is_open() -> bool:
	return visible


## Öffnen, optional bei einem Dorf (Kingdom.id)
func open(village_id: int = 0) -> void:
	if village_id != 0:
		select_village(village_id)
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
	_confirm_action = ""
	toggled.emit(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func get_tab() -> String:
	return _tab


## Dorf im Fenster wählen (Kingdom.id)
func select_village(id: int) -> void:
	if id != _village_id:
		_confirm_action = ""
	_village_id = id
	if visible:
		_refresh()


## Gewähltes Dorf (Kingdom.id, 0 = keins)
func get_village_id() -> int:
	return _village_id


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH_INTERVAL:
		return
	_timer = 0.0
	if not _confirm_action.is_empty() and Time.get_ticks_msec() - _confirm_ms > CONFIRM_MS:
		_confirm_action = ""
	_refresh()


## Dörfer, Verträge oder Beziehungen geändert: höchstens einmal pro Bild neu zeichnen
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

	# Titelzeile: Wappen, Titel, Anzahl, Reiter, Schliessen (gleicher Aufbau in allen Fenstern)
	var title_row := UiStyle.window_header(root, "Diplomatie", _evil, "Schliessen (N oder Esc)", close)
	_count_label = _label(16, COLOR_DIM)
	_count_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiStyle.header_add(title_row, _count_label, true)
	var group := ButtonGroup.new()
	var tab_villages := _make_tab("Dörfer", group)
	tab_villages.tooltip_text = "Neutrale Dörfer: Ruf, Geschenke, Handel, Verträge, Aufnahme"
	tab_villages.pressed.connect(_show_tab.bind(TAB_VILLAGES))
	UiStyle.header_add(title_row, tab_villages)
	var tab_realms := _make_tab("Reiche", group)
	tab_realms.tooltip_text = "Feindliche Königreiche: Volk, Kriege, geschätzte Stärke (Kundschaft nötig)"
	tab_realms.pressed.connect(_show_tab.bind(TAB_REALMS))
	UiStyle.header_add(title_row, tab_realms)
	var tab_trade := _make_tab("Handelswege", group)
	tab_trade.tooltip_text = "Handelswege, Karawanen, gesichtete fremde Wege und Versorgung"
	tab_trade.pressed.connect(_show_tab.bind(TAB_TRADE))
	UiStyle.header_add(title_row, tab_trade)

	# Seiten (gleich hoch: das Fenster springt beim Reiterwechsel nicht)
	var pages := MarginContainer.new()
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.custom_minimum_size = Vector2(0, PAGE_HEIGHT)
	root.add_child(pages)
	var villages_page := HBoxContainer.new()
	villages_page.add_theme_constant_override("separation", 14)
	villages_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.add_child(villages_page)
	_tabs[TAB_VILLAGES] = {"button": tab_villages, "page": villages_page}
	_build_villages_page(villages_page)
	var realms_page := HBoxContainer.new()
	realms_page.add_theme_constant_override("separation", 14)
	realms_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.add_child(realms_page)
	_tabs[TAB_REALMS] = {"button": tab_realms, "page": realms_page}
	_build_realms_page(realms_page)
	var trade_page := ScrollContainer.new()
	trade_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages.add_child(trade_page)
	trade_list = TradeRouteList.new()
	trade_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_page.add_child(trade_list)
	trade_list.setup(game)
	trade_list.jump_requested.connect(func(pos: Vector2) -> void: game.camera.focus_on(pos))
	_tabs[TAB_TRADE] = {"button": tab_trade, "page": trade_page}

	_footer = _label(15, COLOR_DIM)
	_footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(_footer)


func _build_villages_page(page: HBoxContainer) -> void:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_list)
	_empty_label = _wrap_label(16, COLOR_DIM)
	_empty_label.text = "Keine Dörfer in dieser Welt."
	left.add_child(_empty_label)

	var sep := ColorRect.new()
	sep.color = Color(_accent, 0.3)
	sep.custom_minimum_size = Vector2(1, 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(sep)

	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_detail)
	_build_info(_detail)
	_build_actions(_detail)


## Reiter "Reiche": links die KI-Reiche, rechts Volk, Beziehung und Kundschaft
func _build_realms_page(page: HBoxContainer) -> void:
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
	_realm_empty = _wrap_label(16, COLOR_DIM)
	_realm_empty.text = "Keine feindlichen Königreiche in dieser Welt."
	left.add_child(_realm_empty)

	var sep := ColorRect.new()
	sep.color = Color(_accent, 0.3)
	sep.custom_minimum_size = Vector2(1, 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(sep)

	_realm_detail = VBoxContainer.new()
	_realm_detail.add_theme_constant_override("separation", 6)
	_realm_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_realm_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_realm_detail)
	var head := _row(_realm_detail)
	_realm_swatch = ColorRect.new()
	_realm_swatch.custom_minimum_size = Vector2(20, 20)
	_realm_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_realm_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_realm_swatch)
	_realm_name = _label(23, _light)
	_realm_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_realm_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_realm_name)
	_realm_people = _label(16, _accent.lightened(0.2))
	_realm_detail.add_child(_realm_people)
	_realm_desc = _wrap_label(15, COLOR_DIM)
	_realm_detail.add_child(_realm_desc)
	var traits := HBoxContainer.new()
	traits.add_theme_constant_override("separation", 12)
	traits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_realm_detail.add_child(traits)
	_realm_strengths = _wrap_label(14, COLOR_GOOD)
	_realm_strengths.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	traits.add_child(_realm_strengths)
	_realm_weaknesses = _wrap_label(14, COLOR_BAD)
	_realm_weaknesses.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	traits.add_child(_realm_weaknesses)
	var line := ColorRect.new()
	line.color = Color(_accent, 0.3)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_realm_detail.add_child(line)
	var info_scroll := ScrollContainer.new()
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_realm_detail.add_child(info_scroll)
	_realm_info = _wrap_label(16, COLOR_TEXT)
	_realm_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	info_scroll.add_child(_realm_info)
	var actions := _row(_realm_detail)
	_realm_spy_button = _plain_button("Spion schicken (K)")
	_realm_spy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_realm_spy_button.tooltip_text = "Spionagefenster öffnen: einen Spion zu diesem Reich schicken (Auskundschaften)"
	_realm_spy_button.pressed.connect(_on_realm_spy_pressed)
	actions.add_child(_realm_spy_button)
	_realm_jump_button = _plain_button("Hinspringen")
	_realm_jump_button.tooltip_text = "Kamera zur Burg des Reichs (Fenster schliesst)"
	_realm_jump_button.pressed.connect(_on_realm_jump_pressed)
	actions.add_child(_realm_jump_button)
	_realm_defeat_button = _plain_button("Besiegen (Test)")
	_realm_defeat_button.add_theme_color_override("font_color", COLOR_WARN)
	_realm_defeat_button.tooltip_text = "Debug: dieses Reich fällt sofort (wie eine zerstörte Burg)"
	_realm_defeat_button.pressed.connect(_on_realm_defeat_pressed)
	actions.add_child(_realm_defeat_button)


## Oberer Teil der Einzelheiten (scrollt, wenn er zu lang wird – die Aktionen
## darunter behalten ihre Lage)
func _build_info(parent: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(info)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(head)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(20, 20)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_swatch)
	_name_label = _label(23, _light)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_name_label)
	_people_label = _label(16, _accent.lightened(0.2))
	info.add_child(_people_label)
	_desc_label = _wrap_label(15, COLOR_DIM)
	info.add_child(_desc_label)

	# Stärken und Schwächen nebeneinander
	var traits := HBoxContainer.new()
	traits.add_theme_constant_override("separation", 12)
	traits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(traits)
	_strengths_label = _wrap_label(14, COLOR_GOOD)
	_strengths_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	traits.add_child(_strengths_label)
	_weaknesses_label = _wrap_label(14, COLOR_BAD)
	_weaknesses_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	traits.add_child(_weaknesses_label)
	_economy_label = _wrap_label(15, COLOR_TEXT)
	info.add_child(_economy_label)
	_stock_label = _wrap_label(14, COLOR_DIM)
	info.add_child(_stock_label)

	# Ruf mit Stufe und Verlauf
	var rep_row := HBoxContainer.new()
	rep_row.add_theme_constant_override("separation", 10)
	rep_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(rep_row)
	var rep_title := _label(16, _light)
	rep_title.text = "Ruf"
	rep_row.add_child(rep_title)
	_rep_bar = HpBar.new()
	_rep_bar.font_size = 15
	_rep_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rep_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rep_bar.custom_minimum_size = Vector2(0, 22)
	rep_row.add_child(_rep_bar)
	_base_label = _label(14, COLOR_DIM)
	rep_row.add_child(_base_label)
	_history_label = _wrap_label(14, COLOR_DIM)
	info.add_child(_history_label)
	_treaty_info = _rich(15)
	info.add_child(_treaty_info)
	_relations_label = _wrap_label(14, COLOR_DIM)
	info.add_child(_relations_label)


## Aktionsblöcke (feste Höhe, unten im Fenster)
func _build_actions(parent: Control) -> void:
	var line := ColorRect.new()
	line.color = Color(_accent, 0.3)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	_inactive_label = _wrap_label(16, COLOR_DIM)
	parent.add_child(_inactive_label)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 5)
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_actions)

	# 1. Geschenk
	var gift_row := _row(_actions)
	gift_row.add_child(_section_label("Geschenk"))
	_gift_option = _res_option()
	_gift_option.tooltip_text = "Ware des Geschenks"
	_gift_option.select(maxi(_res_ids.find("food"), 0))
	_gift_option.item_selected.connect(_on_option_changed.unbind(1))
	gift_row.add_child(_gift_option)
	var gift_group := ButtonGroup.new()
	for amount in GIFT_AMOUNTS:
		var b := _amount_button(str(amount), gift_group)
		b.tooltip_text = "Geschenk: %d Einheiten" % int(amount)
		b.set_pressed_no_signal(int(amount) == _gift_amount)
		b.pressed.connect(_on_gift_amount_pressed.bind(int(amount)))
		gift_row.add_child(b)
		_gift_amount_buttons.append(b)
	_gift_button = _tip_button("Schenken")
	_gift_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gift_button.tip_source = _gift_tip
	_gift_button.pressed.connect(_on_gift_pressed)
	gift_row.add_child(_gift_button)
	_gift_preview = _rich(14)
	_actions.add_child(_gift_preview)

	# 2. Verträge
	var treaty_row := _row(_actions)
	treaty_row.add_child(_section_label("Verträge"))
	for treaty_type in DiplomacySystem.TREATY_TYPES:
		var b := _tip_button(DiplomacySystem.treaty_name(str(treaty_type)))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tip_source = _treaty_tip.bind(str(treaty_type))
		b.pressed.connect(_on_treaty_pressed.bind(str(treaty_type)))
		treaty_row.add_child(b)
		_treaty_buttons[str(treaty_type)] = b
	# Darunter: Grund der Sperre bzw. Hinweis und "Kündigen" (feste Höhe)
	var hint_row := _row(_actions)
	hint_row.custom_minimum_size = Vector2(0, 36)
	_treaty_hint = _rich(14)
	_treaty_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_treaty_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_row.add_child(_treaty_hint)
	_cancel_button = _plain_button("Kündigen")
	_cancel_button.pressed.connect(_on_cancel_pressed)
	hint_row.add_child(_cancel_button)

	# 3. Handel
	var trade_row := _row(_actions)
	trade_row.add_child(_section_label("Handel"))
	var trade_group := ButtonGroup.new()
	for amount in TRADE_AMOUNTS:
		var b := _amount_button(str(amount), trade_group)
		b.tooltip_text = "Handel: %d Einheiten geben" % int(amount)
		b.set_pressed_no_signal(int(amount) == _trade_amount)
		b.pressed.connect(_on_trade_amount_pressed.bind(int(amount)))
		trade_row.add_child(b)
		_trade_amount_buttons.append(b)
	_trade_give_option = _res_option()
	_trade_give_option.tooltip_text = "Ware, die du gibst"
	_trade_give_option.select(maxi(_res_ids.find("wood"), 0))
	_trade_give_option.item_selected.connect(_on_option_changed.unbind(1))
	trade_row.add_child(_trade_give_option)
	var get_label := _label(15, COLOR_DIM)
	get_label.text = "→"
	get_label.tooltip_text = "Menge und Ware, die du gibst → Ware, die du bekommst"
	trade_row.add_child(get_label)
	_trade_get_option = _res_option()
	_trade_get_option.tooltip_text = "Ware, die du bekommst"
	_trade_get_option.select(maxi(_res_ids.find("ore"), 0))
	_trade_get_option.item_selected.connect(_on_option_changed.unbind(1))
	trade_row.add_child(_trade_get_option)
	_trade_button = _tip_button("Tauschen")
	_trade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trade_button.tip_source = _trade_tip
	_trade_button.pressed.connect(_on_trade_pressed)
	trade_row.add_child(_trade_button)
	_trade_preview = _rich(14)
	_actions.add_child(_trade_preview)

	# 4. Aufnahme, Drohung, Krieg/Frieden, Hinspringen
	var other_row := _row(_actions)
	_annex_button = _tip_button("Ins Reich aufnehmen")
	_annex_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_annex_button.tip_source = _annex_tip
	_annex_button.pressed.connect(_on_annex_pressed)
	other_row.add_child(_annex_button)
	_threat_button = _tip_button("Drohen")
	_threat_button.custom_minimum_size = Vector2(92, 36)
	_threat_button.tip_source = _threat_tip
	_threat_button.pressed.connect(_on_threat_pressed)
	other_row.add_child(_threat_button)
	_war_button = _tip_button("Krieg erklären")
	_war_button.custom_minimum_size = Vector2(160, 36)
	_war_button.tip_source = _war_tip
	_war_button.pressed.connect(_on_war_pressed)
	other_row.add_child(_war_button)
	_jump_button = _plain_button("Hinspringen")
	_jump_button.tooltip_text = "Dorfzentrum auswählen und die Kamera hinbewegen (Fenster schliesst sich)"
	_jump_button.pressed.connect(_on_jump_pressed)
	other_row.add_child(_jump_button)
	_action_info = _rich(14)
	_action_info.custom_minimum_size = Vector2(0, 40)
	_actions.add_child(_action_info)

	# Debug (F3)
	_debug_row = _row(parent)
	var debug_title := _label(14, COLOR_WARN)
	debug_title.text = "Debug:"
	_debug_row.add_child(debug_title)
	for entry in [["Ruf +20", "rep_up"], ["Ruf −20", "rep_down"], ["Bote senden (Test)", "messenger"]]:
		var b := _plain_button(str(entry[0]))
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(debug_action.bind(str(entry[1])))
		_debug_row.add_child(b)


func _make_tab(text: String, group: ButtonGroup) -> ResearchTipButton:
	return UiStyle.tab_button(text, group, _evil)


## Reiter von aussen wählen (TAB_VILLAGES, TAB_REALMS, TAB_TRADE)
func show_tab(tab: String) -> void:
	_show_tab(tab)


## Reiter zeigen ("villages", "realms" oder "trade")
func _show_tab(tab: String) -> void:
	_tab = tab if _tabs.has(tab) else TAB_VILLAGES
	for id in _tabs:
		var entry: Dictionary = _tabs[id]
		(entry["button"] as Button).set_pressed_no_signal(id == _tab)
		(entry["page"] as Control).visible = id == _tab
	match _tab:
		TAB_REALMS:
			_footer.text = "Mit feindlichen Königreichen gibt es keinen Frieden  ·  Wissen über sie bringen Späher und Spione (K)  ·  N / Esc: schliessen"
		TAB_TRADE:
			_footer.text = "Karawanen pendeln auf Handelswegen – schütze sie, überfalle die der Feinde  ·  N / Esc: schliessen"
		_:
			_footer.text = "Ruf steigt durch Geschenke, Handel, Verträge und Schutz; Angriffe, Drohungen und Vertragsbruch senken ihn  ·  N / Esc: schliessen"
	_confirm_action = ""
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
	if _tab == TAB_TRADE and trade_list != null:
		trade_list.refresh()
	var k: Kingdom = game.player
	var vs: VillageSystem = game.village_system
	var ds: DiplomacySystem = game.diplomacy_system
	if _tab == TAB_REALMS:
		_refresh_realms(k)
		return
	var villages := sorted_villages()
	var key: Array = []
	for v in villages:
		key.append([(v as Kingdom).id, str(vs.get_record(v).get("status", ""))])
	if key != _list_key:
		_rebuild_list(villages, key)
	var found := false
	for v in villages:
		if (v as Kingdom).id == _village_id:
			found = true
	if not found:
		_village_id = (villages[0] as Kingdom).id if not villages.is_empty() else 0
	_empty_label.visible = villages.is_empty()
	for v in villages:
		_refresh_entry(k, v)
	_set_text(_count_label, "%d selbstständige Dörfer · %d Verträge" % [vs.get_villages().size(),
			ds.get_treaties_of(k).size()], COLOR_DIM)
	_detail.visible = _village_id != 0
	if _village_id != 0:
		_refresh_detail(k, game.get_kingdom(_village_id))


## Kennt der Spieler Lager, Miliz und Beziehungen des Dorfs? (Kundschaft 2 oder eigener Vertrag)
func _knows_village(k: Kingdom, v: Kingdom) -> bool:
	if not game.diplomacy_system.get_treaty_with(v, k).is_empty():
		return true
	return game.espionage_system.get_intel_level(k, v) >= 2


# --- Reiter "Reiche"

## KI-Reiche: aktive zuerst (nach Entfernung), gefallene am Ende
func sorted_realms() -> Array:
	var list: Array = game.ai_system.get_ai_kingdoms(true)
	var from := _home_pos()
	list.sort_custom(func(a: Kingdom, b: Kingdom) -> bool:
		if a.defeated != b.defeated:
			return not a.defeated
		return from.distance_squared_to(_realm_center(a)) < from.distance_squared_to(_realm_center(b)))
	return list


func _realm_center(r: Kingdom) -> Vector2:
	if is_instance_valid(r.castle):
		return r.castle.get_center()
	return _home_pos()


## Gewähltes Reich im Reiter "Reiche" (Kingdom.id, 0 = keins)
func get_realm_id() -> int:
	return _realm_id


## Reich im Reiter "Reiche" wählen und den Reiter zeigen
func select_realm(id: int) -> void:
	_realm_id = id
	_show_tab(TAB_REALMS)


func _refresh_realms(k: Kingdom) -> void:
	var realms := sorted_realms()
	var key: Array = []
	for r in realms:
		key.append([(r as Kingdom).id, (r as Kingdom).defeated])
	if key != _realm_key:
		_rebuild_realm_list(realms, key)
	var found := false
	for r in realms:
		if (r as Kingdom).id == _realm_id:
			found = true
	if not found:
		_realm_id = (realms[0] as Kingdom).id if not realms.is_empty() else 0
	_realm_empty.visible = realms.is_empty()
	var active := 0
	for r in realms:
		_refresh_realm_entry(k, r)
		if not (r as Kingdom).defeated:
			active += 1
	_set_text(_count_label, "%d feindliche Königreiche · %d gefallen" % [active, realms.size() - active], COLOR_DIM)
	_realm_detail.visible = _realm_id != 0
	if _realm_id != 0:
		_refresh_realm_detail(k, game.get_kingdom(_realm_id))


func _rebuild_realm_list(realms: Array, key: Array) -> void:
	_realm_key = key
	for child in _realm_list.get_children():
		_realm_list.remove_child(child)
		child.queue_free()
	_realm_entries.clear()
	for o in realms:
		var r: Kingdom = o
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		var tag := _label(14, COLOR_WAR)
		top.add_child(tag)
		var sub := _label(14, COLOR_DIM)
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(sub)
		_realm_entries[r.id] = {"button": b, "name": name_label, "tag": tag, "sub": sub}


func _refresh_realm_entry(k: Kingdom, r: Kingdom) -> void:
	var e: Dictionary = _realm_entries.get(r.id, {})
	if e.is_empty():
		return
	var people := str(DataDB.get_people(r.people_id).get("name", "?"))
	if r.defeated:
		_set_text(e["name"], r.display_name, COLOR_GREY)
		_set_text(e["tag"], "gefallen", COLOR_GREY)
		_set_text(e["sub"], "%s · Ruinen" % people, COLOR_GREY)
	else:
		_set_text(e["name"], r.display_name, _light)
		_set_text(e["tag"], "Krieg" if game.are_hostile(k, r) else "Frieden", COLOR_WAR if game.are_hostile(k, r) else COLOR_DIM)
		_set_text(e["sub"], "%s · %d Kacheln · Heer %s" % [people, _realm_distance(r), realm_strength_text(k, r, true)], COLOR_DIM)
	var b: Button = e["button"]
	if b.button_pressed != (r.id == _realm_id):
		b.set_pressed_no_signal(r.id == _realm_id)
	b.tooltip_text = game.espionage_system.get_intel_text(k, r)


func _realm_distance(r: Kingdom) -> int:
	return roundi(_home_pos().distance_to(_realm_center(r)) / float(game.world.tile_size))


## Stärke nach Kundschaft: "?" (keine), "etwa 20–30 Einheiten" (Bericht) oder genau;
## short: nur die Zahlen ("?", "20–30", "24") für die Liste
func realm_strength_text(k: Kingdom, r: Kingdom, short: bool = false) -> String:
	var est: Dictionary = game.espionage_system.estimate_strength(k, r)
	if not bool(est.get("known", false)):
		return "?"
	if bool(est.get("exact", false)):
		return str(int(est["units_low"])) if short else "%d Einheiten" % int(est["units_low"])
	var span := "%d–%d" % [int(est["units_low"]), int(est["units_high"])]
	return span if short else "etwa %s Einheiten" % span


func _refresh_realm_detail(k: Kingdom, r: Kingdom) -> void:
	if r == null:
		return
	var esp: EspionageSystem = game.espionage_system
	var people := DataDB.get_people(r.people_id)
	_realm_swatch.color = r.color
	_set_text(_realm_name, r.display_name, COLOR_GREY if r.defeated else _light)
	_set_text(_realm_people, "Volk: %s  ·  %d Kacheln von deiner Burg  ·  %s" % [str(people.get("name", "?")),
			_realm_distance(r), esp.get_intel_text(k, r)], _accent.lightened(0.2))
	_set_text(_realm_desc, str(people.get("description", "")), COLOR_DIM)
	_set_text(_realm_strengths, _lines("+ ", people.get("strengths", [])), COLOR_GOOD)
	_set_text(_realm_weaknesses, _lines("− ", people.get("weaknesses", [])), COLOR_BAD)
	_set_text(_realm_info, _realm_info_text(k, r), COLOR_TEXT)
	_realm_spy_button.disabled = r.defeated
	_realm_jump_button.disabled = r.defeated or not is_instance_valid(r.castle)
	var hud: Node = game.hud
	_realm_defeat_button.visible = not r.defeated and hud != null and hud.has_method("is_debug_visible") \
			and bool(hud.call("is_debug_visible"))


## Beziehung, Stärke, bekannte Kriege, Verträge und Aufmerksamkeit (je nach Kundschaft)
func _realm_info_text(k: Kingdom, r: Kingdom) -> String:
	if r.defeated:
		return "Dieses Reich ist gefallen. Seine Ruinen zerfallen mit der Zeit."
	var esp: EspionageSystem = game.espionage_system
	var level := esp.get_intel_level(k, r)
	var lines: PackedStringArray = []
	if game.are_hostile(k, r):
		lines.append("Beziehung: Krieg – Friede ist mit feindlichen Königreichen nicht möglich")
	else:
		lines.append("Beziehung: Frieden")
	lines.append("Heer: %s" % realm_strength_text(k, r))
	# Kriege: mit dir immer; Kriege gegen andere Reiche und Dörfer nur mit Kundschaft
	var wars: PackedStringArray = []
	if game.are_hostile(k, r):
		wars.append("dir")
	var unknown := false
	for o in game.ai_system.get_rivals(r):
		var other: Kingdom = o
		if level < 2 and esp.get_intel_level(k, other) < 2:
			unknown = true
			continue
		if str(game.ai_system.get_rivalry(r, other).get("state", "")) == "war" or game.are_hostile(r, other):
			wars.append(other.display_name)
	if level >= 2:
		for v in game.village_system.get_villages():
			if game.are_hostile(r, v):
				wars.append((v as Kingdom).display_name)
	else:
		unknown = true
	var war_line := "Kriege: " + ", ".join(wars)
	if unknown:
		war_line += " · weitere: ? (Kundschaft nötig)"
	lines.append(war_line)
	if level >= 2:
		var names: PackedStringArray = []
		for t in game.diplomacy_system.get_treaties_of(r):
			names.append((t["village"] as Kingdom).display_name)
		lines.append("Verträge mit Dörfern: %s" % (", ".join(names) if not names.is_empty() else "keine"))
		var tier := esp.get_awareness_tier(r, k)
		if level >= 3:
			lines.append("Aufmerksamkeit auf dich: %s (%d %%)" % [EspionageSystem.awareness_tier_name(tier),
					roundi(esp.get_awareness(r, k))])
		else:
			lines.append("Aufmerksamkeit auf dich: %s" % EspionageSystem.awareness_tier_name(tier))
	else:
		lines.append("Verträge mit Dörfern: ?")
		lines.append("Aufmerksamkeit auf dich: ?")
		lines.append("Schicke Späher oder Spione (K), um mehr zu erfahren.")
	return "\n".join(lines)


func _on_realm_pressed(id: int) -> void:
	_realm_id = id
	_refresh()


func _on_realm_spy_pressed() -> void:
	var hud: Node = game.hud
	if _realm_id != 0 and hud != null and hud.has_method("open_espionage"):
		hud.call("open_espionage", EspionagePanel.TAB_SPIES, _realm_id, 0)


func _on_realm_jump_pressed() -> void:
	var r: Kingdom = game.get_kingdom(_realm_id) if _realm_id != 0 else null
	if r == null or not is_instance_valid(r.castle):
		return
	game.selection.select([r.castle])
	game.camera.focus_on(r.castle.get_center())
	close()


func _on_realm_defeat_pressed() -> void:
	var r: Kingdom = game.get_kingdom(_realm_id) if _realm_id != 0 else null
	if r != null and not r.defeated:
		game.victory_system.debug_defeat(r, "castle")
	_refresh()


## Alle Dörfer (auch frühere): selbstständige zuerst, dann nach Entfernung zur Burg
func sorted_villages() -> Array:
	var vs: VillageSystem = game.village_system
	var list: Array = vs.get_villages(true)
	var from := _home_pos()
	list.sort_custom(func(a: Kingdom, b: Kingdom) -> bool:
		var aa := vs.is_village(a)
		var ab := vs.is_village(b)
		if aa != ab:
			return aa
		return from.distance_squared_to(vs.get_center(a)) < from.distance_squared_to(vs.get_center(b)))
	return list


func _home_pos() -> Vector2:
	var k: Kingdom = game.player
	if is_instance_valid(k.castle):
		return k.castle.get_center()
	return game.world.cell_to_world(game.world.start_cell)


## Entfernung Burg – Dorf in Kacheln
func _distance_tiles(v: Kingdom) -> int:
	return roundi(_home_pos().distance_to(game.village_system.get_center(v)) / float(game.world.tile_size))


func _rebuild_list(villages: Array, key: Array) -> void:
	_list_key = key
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_list_entries.clear()
	for o in villages:
		var v: Kingdom = o
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, ENTRY_HEIGHT)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_list_pressed.bind(v.id))
		_list.add_child(b)
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
		swatch.color = DataDB.get_people(v.people_id).get("color", v.color)
		top.add_child(swatch)
		var name_label := _label(17, _light)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.text = v.display_name
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
		_list_entries[v.id] = {"button": b, "swatch": swatch, "name": name_label, "tag": tag, "sub": sub, "bar": bar}


func _refresh_entry(k: Kingdom, v: Kingdom) -> void:
	var e: Dictionary = _list_entries.get(v.id, {})
	if e.is_empty():
		return
	var vs: VillageSystem = game.village_system
	var ds: DiplomacySystem = game.diplomacy_system
	var active := vs.is_village(v)
	var people := vs.get_people(v)
	_set_text(e["name"], v.display_name, _light if active else COLOR_GREY)
	var tag := _status_tag(k, v)
	_set_text(e["tag"], str(tag[0]), tag[1])
	var bar: HpBar = e["bar"]
	if active:
		var militia := str(vs.get_militia(v).size()) if _knows_village(k, v) else "?"
		_set_text(e["sub"], "%s · %d Kacheln · Miliz %s (%s)" % [str(people.get("name", "?")), _distance_tiles(v),
				militia, vs.get_strength_text(v)], COLOR_DIM)
		var rep := ds.get_reputation(v, k)
		var tier := DiplomacySystem.tier_for(rep)
		bar.fill_color = DiplomacySystem.tier_color(tier)
		bar.set_value(rep + 100.0, 200.0, "%s (%s)" % [DiplomacySystem.tier_name(tier), ResourceBar.format_signed(roundf(rep))])
	else:
		_set_text(e["sub"], "%s · %d Kacheln" % [str(people.get("name", "?")), _distance_tiles(v)], COLOR_GREY)
		bar.fill_color = COLOR_GREY
		bar.set_value(0.0, 1.0, "–")
	var b: Button = e["button"]
	if b.button_pressed != (v.id == _village_id):
		b.set_pressed_no_signal(v.id == _village_id)
	b.tooltip_text = vs.get_summary_text(v, k)


## Kurzer Zustand für die Liste: [Text, Farbe]
func _status_tag(k: Kingdom, v: Kingdom) -> Array:
	var vs: VillageSystem = game.village_system
	var ds: DiplomacySystem = game.diplomacy_system
	var rec := vs.get_record(v)
	match str(rec.get("status", "")):
		"annexed":
			return ["Aufgenommen", COLOR_GREY]
		"conquered":
			return ["Erobert", COLOR_GREY]
		"destroyed":
			return ["Zerstört", COLOR_GREY]
	for u in ds.get_urgent(k):
		if (u as Dictionary)["village"] == v:
			return ["Hilfe nötig!", COLOR_BAD]
	if game.are_hostile(k, v):
		return ["Krieg", COLOR_WAR]
	var mine := ds.get_treaty_with(v, k)
	if not mine.is_empty():
		var route: Dictionary = game.trade_route_system.get_route_for(k, v)
		if not route.is_empty() and str(route["state"]) == "cut":
			return ["✕ Weg", COLOR_BAD]
		return [str(TREATY_SHORT.get(mine, mine)), COLOR_ALLY if mine == "alliance" else COLOR_GOOD]
	if not ds.get_treaty(v).is_empty():
		return ["Vertrag vergeben", COLOR_DIM]
	return ["", COLOR_TEXT]


func _refresh_detail(k: Kingdom, v: Kingdom) -> void:
	if v == null:
		return
	var vs: VillageSystem = game.village_system
	var ds: DiplomacySystem = game.diplomacy_system
	var rec := vs.get_record(v)
	var people := vs.get_people(v)
	var active := vs.is_village(v)
	_swatch.color = people.get("color", v.color)
	_set_text(_name_label, v.display_name, _light if active else COLOR_GREY)
	_set_text(_people_label, "Volk: %s  ·  %d Kacheln von deiner Burg  ·  %d Hütten, %d Einwohner" % [
			str(people.get("name", "?")), _distance_tiles(v), int(rec.get("size", 0)), int(rec.get("population", 0))],
			_accent.lightened(0.2))
	_set_text(_desc_label, str(people.get("description", "")), COLOR_DIM)
	_set_text(_strengths_label, _lines("+ ", people.get("strengths", [])), COLOR_GOOD)
	_set_text(_weaknesses_label, _lines("− ", people.get("weaknesses", [])), COLOR_BAD)
	var prod := _amounts_text(vs.get_production(v))
	var economy := "Produziert pro Minute: %s" % prod
	if active and _knows_village(k, v):
		economy += "  ·  Miliz %d/%d (%s)" % [vs.get_militia(v).size(), vs.get_militia_target(v), vs.get_strength_text(v)]
		_set_text(_stock_label, "Vorrat des Dorfs: %s" % _amounts_text(v.resources), COLOR_DIM)
	elif active:
		economy += "  ·  Miliz ? (%s)" % vs.get_strength_text(v)
		_set_text(_stock_label, "Vorrat des Dorfs: ? (Späher oder Spione schicken, oder ein Vertrag)", COLOR_DIM)
	else:
		_set_text(_stock_label, "", COLOR_DIM)
	_set_text(_economy_label, economy, COLOR_TEXT)

	# Ruf
	var rep := ds.get_reputation(v, k)
	var tier := DiplomacySystem.tier_for(rep)
	_rep_bar.fill_color = DiplomacySystem.tier_color(tier) if active else COLOR_GREY
	_rep_bar.set_value(rep + 100.0, 200.0, "%s (%s)" % [DiplomacySystem.tier_name(tier), ResourceBar.format_signed(roundf(rep))])
	_set_text(_base_label, "Grundwert %s" % ResourceBar.format_signed(roundf(ds.get_base_reputation(v, k))), COLOR_DIM)
	_set_text(_history_label, _history_text(ds.get_history(v, k)), COLOR_DIM)
	var treaty_text := _treaty_text(k, v)
	if _treaty_info.text != treaty_text:
		_treaty_info.text = treaty_text
	_set_text(_relations_label, _relations_text(k, v), COLOR_DIM)

	_actions.visible = active
	_inactive_label.visible = not active
	if not active:
		_set_text(_inactive_label, _inactive_text(v), COLOR_DIM)
	else:
		_refresh_actions(k, v)
	var hud: Node = game.hud
	_debug_row.visible = active and hud != null and hud.has_method("is_debug_visible") and bool(hud.call("is_debug_visible"))


func _refresh_actions(k: Kingdom, v: Kingdom) -> void:
	var ds: DiplomacySystem = game.diplomacy_system
	var tip := ResearchTipButton
	# Geschenk
	var gift := get_gift()
	var preview := ds.preview_gift(k, v, gift)
	var reason := str(preview["reason"])
	var gift_text := ""
	if reason.is_empty():
		gift_text = tip.colored("Ruf %s" % ResourceBar.format_signed(float(preview["gain"])), COLOR_GOOD)
		gift_text += "  ·  Wert %d" % roundi(float(preview["value"]))
		var pref := float(preview["preference"])
		if not is_equal_approx(pref, 1.0):
			gift_text += "  ·  " + tip.colored("Vorliebe ×%s" % HeroUI.num(pref), COLOR_GOOD if pref > 1.0 else COLOR_WARN)
		if game.are_hostile(v, k):
			gift_text += "  ·  " + tip.colored("im Krieg nur halb so viel", COLOR_WARN)
	else:
		gift_text = tip.colored(reason, COLOR_BAD)
	gift_text = tip.colored("Mag: ", COLOR_DIM) + _likes_text(v) + "  ·  " + gift_text
	_set_rich(_gift_preview, gift_text)
	_set_disabled(_gift_button, not reason.is_empty())

	# Verträge (Grund der Sperre auch als Zeile unter den Knöpfen)
	var running := ds.get_treaty_with(v, k)
	## Grund -> gesperrte Verträge (gleiche Gründe zusammengefasst, damit die Zeile kurz bleibt)
	var reasons: Dictionary = {}
	for treaty_type in _treaty_buttons:
		var b: ResearchTipButton = _treaty_buttons[treaty_type]
		var offer := ds.get_treaty_offer(k, v, str(treaty_type))
		var label := _treaty_button_name(str(treaty_type))
		if running == treaty_type:
			label += " (läuft)"
		elif bool(offer["possible"]):
			label += " (%d %%)" % roundi(float(offer["chance"]) * 100.0)
		else:
			var names: PackedStringArray = reasons.get(str(offer["reason"]), PackedStringArray())
			names.append(label)
			reasons[str(offer["reason"])] = names
		_set_button_text(b, label)
		_set_disabled(b, not bool(offer["possible"]))
	var hint := tip.colored("Annahme-Chance steht auf dem Knopf, Bedingungen im Tooltip.", COLOR_DIM)
	if not running.is_empty():
		hint = tip.colored("Wechsel der Vertragsart ohne Strafe möglich.", COLOR_DIM)
	if reasons.size() == 1 and (reasons.values()[0] as PackedStringArray).size() + (0 if running.is_empty() else 1) == _treaty_buttons.size():
		hint = tip.colored(str(reasons.keys()[0]), COLOR_BAD)
	elif not reasons.is_empty():
		var parts: PackedStringArray = []
		for why in reasons:
			parts.append("%s: %s" % [", ".join(reasons[why] as PackedStringArray), str(why)])
		hint = tip.colored(" · ".join(parts), COLOR_BAD)
	_set_rich(_treaty_hint, hint)
	_cancel_button.visible = not running.is_empty()
	if not running.is_empty():
		var penalty := roundi(float(DataDB.diplo("treaties.%s.cancel_penalty" % running, -10)))
		_set_button_text(_cancel_button, "Wirklich kündigen?" if _is_confirm("cancel", v) else "Vertrag kündigen (Ruf %s)" %
				ResourceBar.format_signed(penalty))
		_cancel_button.tooltip_text = "%s kündigen: der Ruf sinkt um %d. Zum Bestätigen zweimal klicken." % [
				DiplomacySystem.treaty_name(running), absi(penalty)]

	# Handel
	var q := get_trade_quote()
	var trade_text := ""
	if bool(q["ok"]):
		trade_text = tip.colored("→ %d %s" % [roundi(float(q["get_amount"])), _res_name(_selected_res(_trade_get_option))], COLOR_GOOD)
	else:
		trade_text = tip.colored(str(q["reason"]), COLOR_BAD)
	trade_text += "  ·  Kurs %s  ·  heute noch Wert %d" % [("%.2f" % float(q["rate"])).replace(".", ","),
			floori(float(q["remaining_today"]))]
	_set_rich(_trade_preview, trade_text)
	_set_disabled(_trade_button, not bool(q["ok"]))

	# Aufnahme
	var annex := ds.can_annex(k, v)
	var annex_label := "Ins Reich aufnehmen"
	match str(annex["mode"]):
		"devoted":
			annex_label = "Aufnehmen (ergeben)"
		"intimidation":
			annex_label = "Aufnehmen (Einschüchterung)"
		"gift":
			annex_label = "Aufnehmen (Geschenk)"
	if _is_confirm("annex", v):
		annex_label = "Wirklich aufnehmen?"
	_set_button_text(_annex_button, annex_label)
	_set_disabled(_annex_button, not bool(annex["ok"]))

	# Drohung
	var threat := ds.get_threat_info(k, v)
	_set_disabled(_threat_button, not bool(threat["possible"]))

	# Krieg / Frieden
	var hostile: bool = game.are_hostile(k, v)
	var war_label := "Frieden anbieten" if hostile else ("Wirklich Krieg?" if _is_confirm("war", v) else "Krieg erklären")
	_set_button_text(_war_button, war_label)
	var war_color := COLOR_GOOD if hostile else COLOR_WAR
	if _war_button.get_theme_color("font_color") != war_color:
		_war_button.add_theme_color_override("font_color", war_color)
		_war_button.add_theme_color_override("font_hover_color", war_color.lightened(0.15))
	_set_disabled(_war_button, hostile and not ds.can_make_peace(k, v).is_empty())

	_set_rich(_action_info, _action_info_text(k, v, annex, threat))


## Infozeilen unter den Knöpfen: Aufnahme und Drohung bzw. Frieden (mit Grund)
func _action_info_text(k: Kingdom, v: Kingdom, annex: Dictionary, threat: Dictionary) -> String:
	var ds: DiplomacySystem = game.diplomacy_system
	var tip := ResearchTipButton
	var line1 := "Aufnahme: "
	if bool(annex["ok"]):
		match str(annex["mode"]):
			"devoted":
				line1 += tip.colored("möglich – das Dorf ist dir ergeben", COLOR_GOOD)
			"intimidation":
				line1 += tip.colored("möglich – deine Truppen schüchtern es ein (ein Teil der Miliz desertiert)", COLOR_WARN)
			_:
				line1 += "mit Geschenk " + HeroUI.cost_bbcode(k, annex["gift"])
	elif str(annex["mode"]) == "gift":
		line1 += "Geschenk " + HeroUI.cost_bbcode(k, annex["gift"])
	else:
		line1 += tip.colored(str(annex["reason"]), COLOR_BAD)
	var line2 := ""
	if game.are_hostile(k, v):
		var peace := ds.can_make_peace(k, v)
		line2 = "Frieden: " + (tip.colored("möglich", COLOR_GOOD) if peace.is_empty() else tip.colored(peace, COLOR_BAD))
	else:
		var ratio := float(threat["ratio"])
		var needed := float(DataDB.diplo("threat.min_ratio", 1.5))
		line2 = "Drohung: deine Stärke vor Ort ×%s (nötig ×%s)" % [HeroUI.num(ratio), HeroUI.num(needed)]
		if not str(threat["reason"]).is_empty():
			line2 += "  ·  " + tip.colored(str(threat["reason"]), COLOR_BAD)
		elif ratio < needed:
			line2 += "  ·  " + tip.colored("das Dorf würde lachen", COLOR_WARN)
	return line1 + "\n" + line2


func _treaty_text(k: Kingdom, v: Kingdom) -> String:
	var vs: VillageSystem = game.village_system
	var ds: DiplomacySystem = game.diplomacy_system
	var tip := ResearchTipButton
	var t := ds.get_treaty(v)
	if t.is_empty():
		return tip.colored("Kein Vertrag", COLOR_DIM)
	var treaty_type := str(t["type"])
	var partner: Kingdom = game.get_kingdom(int(t["partner_id"]))
	var tname := DiplomacySystem.treaty_name(treaty_type)
	if partner != k:
		return tip.colored("%s mit %s" % [tname, partner.display_name if partner != null else "?"], COLOR_TEXT)
	var since := maxf(GameClock.game_time - float(t["since"]), 0.0)
	var text := "[b]%s[/b] mit dir (seit %s)" % [tip.esc(tname), _duration(since)]
	var people := vs.get_people(v)
	match treaty_type:
		"protection":
			text += "  ·  Tribut an dich: %s pro Minute" % DataDB.cost_to_text(people.get("tribute", {}))
			text += "  ·  Verwarnungen %d/%d" % [int(t["strikes"]), int(DataDB.diplo("treaties.protection.max_strikes", 3))]
			var deadline := float(t["help_deadline"])
			if deadline > 0.0:
				text += "\n" + tip.colored("Hilfe nötig! Schicke Truppen hin – noch %d s" % maxi(ceili(deadline - GameClock.game_time), 0),
						COLOR_BAD)
			else:
				text += "\n" + tip.colored("Pflicht: Wird das Dorf angegriffen, schicke binnen %d s Truppen hin." % int(
						DataDB.diplo("treaties.protection.help_seconds", 60)), COLOR_DIM)
		"trade":
			var delivery: Dictionary = people.get("delivery", {})
			text += "\nNächste Lieferung in %d s: %s für %s  ·  bisher %d" % [maxi(ceili(float(t["next_delivery"]) - GameClock.game_time), 0),
					DataDB.cost_to_text(delivery.get("give", {})), DataDB.cost_to_text(delivery.get("take", {})),
					int(t.get("deliveries", 0))]
		"alliance":
			var special := str(people.get("special_unit", ""))
			text += "\nMilizen helfen dir im Umkreis von %d Kacheln" % int(DataDB.diplo("treaties.alliance.help_radius", 25))
			if not special.is_empty():
				text += "  ·  Kaserne: %s" % str(DataDB.get_unit_type(special).get("name", special))
	# Handelsweg (Phase 9)
	var route: Dictionary = game.trade_route_system.get_route_for(k, v)
	if not route.is_empty():
		text += "\n" + tip.esc(game.trade_route_system.get_route_text(route, k)) + "  ·  Reiter Handelswege"
	return text


## "Beziehungen: Krieg mit dir · Bündnis mit …" (Monster zählen nicht). Beziehungen zu
## anderen Reichen nur mit Kundschaft (Stufe 2) über das Dorf.
func _relations_text(k: Kingdom, v: Kingdom) -> String:
	var parts: PackedStringArray = []
	var known := _knows_village(k, v)
	for o in game.kingdoms:
		var other: Kingdom = o
		if other == v or other.defeated or other.controller == "wild":
			continue
		if other != k and not known:
			continue
		var who := "dir" if other == k else other.display_name
		if game.are_hostile(v, other):
			parts.append("Krieg mit %s" % who)
		elif game.are_allied(v, other):
			parts.append("Bündnis mit %s" % who)
	if not known:
		parts.append("weitere Beziehungen: ? (Späher oder Spione schicken)")
	elif parts.is_empty():
		return "Beziehungen: Frieden mit allen Reichen"
	return "Beziehungen: " + " · ".join(parts)


func _inactive_text(v: Kingdom) -> String:
	var vs: VillageSystem = game.village_system
	var rec := vs.get_record(v)
	var owner_k: Kingdom = game.get_kingdom(int(rec.get("owner_id", 0)))
	var who := "?"
	if owner_k != null:
		who = "deinem Reich" if owner_k == game.player else owner_k.display_name
	match str(rec.get("status", "")):
		"annexed":
			return "Dieses Dorf wurde in %s aufgenommen. Das Dorfzentrum ist jetzt ein Aussenposten, die Produktion fliesst ins Lager." % who
		"conquered":
			return "Dieses Dorf wurde von %s erobert. Es produziert nur noch gemindert." % who
	return "Dieses Dorf wurde zerstört."


## "+10 Geschenk · −5 Angriff" (neueste zuerst)
func _history_text(entries: Array) -> String:
	if entries.is_empty():
		return "Verlauf: noch keine Änderungen"
	var parts: PackedStringArray = []
	for i in range(entries.size() - 1, maxi(entries.size() - 1 - HISTORY_LINES, -1), -1):
		var e: Dictionary = entries[i]
		parts.append("%s %s" % [ResourceBar.format_signed(float(e["delta"])), str(e["reason"])])
	return "Verlauf: " + " · ".join(parts)


## Lieblingswaren (Vorliebe > 1), farbig: "Nahrung ×1,5, Holz ×1,3"
func _likes_text(v: Kingdom) -> String:
	var prefs: Dictionary = game.village_system.get_people(v).get("gift_preferences", {})
	var ids: Array = prefs.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return float(prefs[a]) > float(prefs[b]))
	var parts: PackedStringArray = []
	for res_id in ids:
		if float(prefs[res_id]) > 1.0 and parts.size() < 3:
			parts.append("%s ×%s" % [_res_name(str(res_id)), HeroUI.num(float(prefs[res_id]))])
	if parts.is_empty():
		return "alles gleich"
	return ResearchTipButton.colored(", ".join(parts), COLOR_GOOD)


# ---------------------------------------------------------------------------
# Tooltips
# ---------------------------------------------------------------------------

func _gift_tip() -> String:
	var v := _selected()
	if v == null:
		return ""
	var ds: DiplomacySystem = game.diplomacy_system
	var gift := get_gift()
	var preview := ds.preview_gift(game.player, v, gift)
	var lines: PackedStringArray = ["[b]Geschenk[/b]: %s" % DataDB.cost_to_text(gift)]
	lines.append("Ruf %s (Wert %d, höchstens %d je Geschenk)" % [ResourceBar.format_signed(float(preview["gain"])),
			roundi(float(preview["value"])), int(DataDB.diplo("gifts.max_per_gift", 15))])
	lines.append("Lieblingswaren zählen mehr; viele Geschenke kurz nacheinander wirken weniger.")
	if not str(preview["reason"]).is_empty():
		lines.append(ResearchTipButton.colored(str(preview["reason"]), COLOR_BAD))
	return "\n".join(lines)


func _treaty_tip(treaty_type: String) -> String:
	var v := _selected()
	if v == null:
		return ""
	var offer: Dictionary = game.diplomacy_system.get_treaty_offer(game.player, v, treaty_type)
	var text := str(offer["text"])
	if not bool(offer["possible"]):
		# Den Grund (letzte Zeile) rot hervorheben
		var lines := text.split("\n")
		lines[lines.size() - 1] = ResearchTipButton.colored(lines[lines.size() - 1], COLOR_BAD)
		text = "\n".join(lines)
	else:
		text += "\nAbgelehnt: Ruf %d und %d s Wartezeit" % [int(DataDB.diplo("events.treaty_refused", -2)),
				int(DataDB.diplo("treaties.refuse_cooldown", 120))]
	return text


func _trade_tip() -> String:
	var v := _selected()
	if v == null:
		return ""
	var q := get_trade_quote()
	var tip := ResearchTipButton
	var lines: PackedStringArray = ["[b]Tausch[/b]: %d %s gegen %d %s" % [_trade_amount, tip.esc(_res_name(_selected_res(_trade_give_option))),
			roundi(float(q["get_amount"])), tip.esc(_res_name(_selected_res(_trade_get_option)))]]
	lines.append("Kurs %s · Marge des Dorfs %d %%" % [("%.2f" % float(q["rate"])).replace(".", ","), roundi(float(q["margin"]) * 100.0)])
	lines.append("Besserer Ruf und ein Handelsvertrag senken die Marge; das Volk kauft und verkauft manche Waren günstiger.")
	lines.append("Heute noch Wert %d (Tageslimit je Dorf)" % floori(float(q["remaining_today"])))
	if not bool(q["ok"]):
		lines.append(tip.colored(str(q["reason"]), COLOR_BAD))
	return "\n".join(lines)


func _annex_tip() -> String:
	var v := _selected()
	if v == null:
		return ""
	var info: Dictionary = game.diplomacy_system.can_annex(game.player, v)
	var tip := ResearchTipButton
	var lines: PackedStringArray = ["[b]Ins Reich aufnehmen[/b]"]
	lines.append("Ergeben (Ruf ab %+d): sofort." % roundi(DiplomacySystem.tier_min("devoted", 70.0)))
	lines.append("Freundlich (Ruf ab %+d): mit grossem Geschenk oder starker Armee in der Nähe (Einschüchterung)." % roundi(
			float(DataDB.diplo("annex.min_reputation", 30))))
	lines.append("Danach: Dorfzentrum wird Aussenposten mit Gebiet, Milizen werden deine Truppen, die Produktion fliesst in dein Lager, Volkskrieger in der Kaserne.")
	if str(info["mode"]) == "gift":
		lines.append("Geschenk: " + HeroUI.cost_bbcode(game.player, info["gift"]))
	if not bool(info["ok"]):
		lines.append(tip.colored(str(info["reason"]), COLOR_BAD))
	else:
		lines.append(tip.colored("Zum Bestätigen zweimal klicken.", COLOR_WARN))
	return "\n".join(lines)


func _threat_tip() -> String:
	var v := _selected()
	if v == null:
		return ""
	var info: Dictionary = game.diplomacy_system.get_threat_info(game.player, v)
	var tip := ResearchTipButton
	var needed := float(DataDB.diplo("threat.min_ratio", 1.5))
	var lines: PackedStringArray = ["[b]Drohen[/b]"]
	lines.append("Deine Truppen im Umkreis von %d Kacheln: Stärke ×%s des Dorfs (nötig ×%s)" % [
			int(DataDB.diplo("threat.radius", 15)), HeroUI.num(float(info["ratio"])), HeroUI.num(needed)])
	lines.append("Genug: das Dorf zahlt Tribut (%s), Ruf %d." % [DataDB.cost_to_text(info["tribute"]),
			int(DataDB.diplo("events.threat_success", -10))])
	lines.append("Zu wenig: das Dorf lacht, Ruf %d." % int(DataDB.diplo("events.threat_fail", -15)))
	lines.append("Andere Dörfer hören davon (Gerücht).")
	if not str(info["reason"]).is_empty():
		lines.append(tip.colored(str(info["reason"]), COLOR_BAD))
	return "\n".join(lines)


func _war_tip() -> String:
	var v := _selected()
	if v == null:
		return ""
	var k: Kingdom = game.player
	var ds: DiplomacySystem = game.diplomacy_system
	var tip := ResearchTipButton
	if game.are_hostile(k, v):
		var reason := ds.can_make_peace(k, v)
		var lines: PackedStringArray = ["[b]Frieden anbieten[/b]"]
		lines.append("Ruf mindestens %+d und %d s ohne Angriff." % [roundi(float(DataDB.diplo("peace.min_reputation", -40))),
				int(DataDB.diplo("peace.quiet_seconds", 60))])
		lines.append(tip.colored(reason, COLOR_BAD) if not reason.is_empty() else tip.colored("Möglich (Ruf %+d)" % int(
				DataDB.diplo("events.peace_bonus", 5)), COLOR_GOOD))
		return "\n".join(lines)
	var war_lines: PackedStringArray = ["[b]Krieg erklären[/b]"]
	war_lines.append("Ruf %d, andere Dörfer in der Nähe misstrauen dir (Gerücht)." % int(DataDB.diplo("events.declare_war", -30)))
	if not ds.get_treaty_with(v, k).is_empty():
		war_lines.append(tip.colored("Vertragsbruch: Ruf zusätzlich %d" % int(DataDB.diplo("events.treaty_break", -40)), COLOR_BAD))
	war_lines.append("Das Dorf schickt Boten – fange sie ab. Dorfzentrum auf 0 Leben = erobert.")
	war_lines.append(tip.colored("Zum Bestätigen zweimal klicken.", COLOR_WARN))
	return "\n".join(war_lines)


# ---------------------------------------------------------------------------
# Klicks (öffentlich, damit der Rauchtest dieselben Wege nimmt)
# ---------------------------------------------------------------------------

## Geschenk aus der aktuellen Wahl im Fenster: {Ressource: Menge}
func get_gift() -> Dictionary:
	return {_selected_res(_gift_option): float(_gift_amount)}


## Tauschangebot aus der aktuellen Wahl im Fenster
func get_trade_quote() -> Dictionary:
	return game.diplomacy_system.get_trade_quote(game.player, _selected(), _selected_res(_trade_give_option),
			float(_trade_amount), _selected_res(_trade_get_option))


## Ware und Menge des Geschenks wählen (wie die Auswahlliste und die Mengenknöpfe)
func set_gift_choice(res_id: String, amount: int) -> void:
	var index := _res_ids.find(res_id)
	if index >= 0:
		_gift_option.select(index)
	_on_gift_amount_pressed(amount)


## Tausch wählen: gib amount von give_res für get_res
func set_trade_choice(give_res: String, amount: int, get_res: String) -> void:
	var gi := _res_ids.find(give_res)
	var ti := _res_ids.find(get_res)
	if gi >= 0:
		_trade_give_option.select(gi)
	if ti >= 0:
		_trade_get_option.select(ti)
	_on_trade_amount_pressed(amount)


func _on_list_pressed(village_id: int) -> void:
	select_village(village_id)
	_refresh()


func _on_option_changed() -> void:
	_refresh()


func _on_gift_amount_pressed(amount: int) -> void:
	_gift_amount = amount
	for i in _gift_amount_buttons.size():
		_gift_amount_buttons[i].set_pressed_no_signal(int(GIFT_AMOUNTS[i]) == amount)
	_refresh()


func _on_trade_amount_pressed(amount: int) -> void:
	_trade_amount = amount
	for i in _trade_amount_buttons.size():
		_trade_amount_buttons[i].set_pressed_no_signal(int(TRADE_AMOUNTS[i]) == amount)
	_refresh()


func _on_gift_pressed() -> void:
	var v := _selected()
	if v == null:
		return
	var ds: DiplomacySystem = game.diplomacy_system
	var gift := get_gift()
	if not ds.give_gift(game.player, v, gift):
		Notify.warning(ds.can_give_gift(game.player, v, gift))
	_refresh()


## Vertrag vorschlagen (Annahme oder Ablehnung meldet das DiplomacySystem)
func _on_treaty_pressed(treaty_type: String) -> void:
	var v := _selected()
	if v == null:
		return
	var answer: String = game.diplomacy_system.propose_treaty(game.player, v, treaty_type)
	# Abgelehnt: das System hat schon gemeldet; andere Gründe hier
	if not answer.is_empty() and not answer.begins_with("abgelehnt"):
		Notify.warning(answer)
	_refresh()


func _on_cancel_pressed() -> void:
	var v := _selected()
	if v == null:
		return
	if _is_confirm("cancel", v):
		_confirm_action = ""
		game.diplomacy_system.cancel_treaty(game.player, v)
	else:
		_ask_confirm("cancel", v)
	_refresh()


func _on_trade_pressed() -> void:
	var v := _selected()
	if v == null:
		return
	var q := get_trade_quote()
	if not bool(q["ok"]) or game.diplomacy_system.trade(game.player, v, _selected_res(_trade_give_option),
			float(_trade_amount), _selected_res(_trade_get_option)) <= 0.0:
		Notify.warning(str(q["reason"]) if not str(q["reason"]).is_empty() else "Tausch nicht möglich")
	_refresh()


func _on_annex_pressed() -> void:
	var v := _selected()
	if v == null:
		return
	var ds: DiplomacySystem = game.diplomacy_system
	var info := ds.can_annex(game.player, v)
	if not bool(info["ok"]):
		Notify.warning(str(info["reason"]))
	elif _is_confirm("annex", v):
		_confirm_action = ""
		ds.annex(game.player, v)
	else:
		_ask_confirm("annex", v)
	_refresh()


func _on_threat_pressed() -> void:
	var v := _selected()
	if v == null:
		return
	var ds: DiplomacySystem = game.diplomacy_system
	var info := ds.get_threat_info(game.player, v)
	if not bool(info["possible"]):
		Notify.warning(str(info["reason"]))
	else:
		ds.threaten(game.player, v)
	_refresh()


## Krieg erklären (zweiter Klick bestätigt) bzw. Frieden anbieten
func _on_war_pressed() -> void:
	var v := _selected()
	if v == null:
		return
	var k: Kingdom = game.player
	var ds: DiplomacySystem = game.diplomacy_system
	if game.are_hostile(k, v):
		if not ds.make_peace(k, v):
			Notify.warning(ds.can_make_peace(k, v))
	elif _is_confirm("war", v):
		_confirm_action = ""
		ds.declare_war(k, v)
	else:
		_ask_confirm("war", v)
	_refresh()


func _on_jump_pressed() -> void:
	var v := _selected()
	if v == null:
		return
	var vs: VillageSystem = game.village_system
	var hall := vs.get_hall(v)
	if hall != null:
		game.selection.select([hall])
	game.camera.focus_on(vs.get_center(v))
	close()


## Debug-Knöpfe (F3): "rep_up", "rep_down", "messenger"
func debug_action(action: String) -> void:
	var v := _selected()
	if v == null:
		return
	var k: Kingdom = game.player
	var ds: DiplomacySystem = game.diplomacy_system
	match action:
		"rep_up":
			ds.debug_set_reputation(v, k, ds.get_reputation(v, k) + 20.0)
		"rep_down":
			ds.debug_set_reputation(v, k, ds.get_reputation(v, k) - 20.0)
		"messenger":
			var ms: MessengerSystem = game.messenger_system
			var vs: VillageSystem = game.village_system
			var receiver := ms.pick_receiver(v, k)
			if receiver == null:
				Notify.warning("Debug: kein Empfänger für einen Boten aus %s" % v.display_name)
			else:
				var hall := vs.get_hall(v)
				var dest := vs.get_center(receiver)
				var origin := hall.get_approach_point(dest) if hall != null else vs.get_center(v)
				ms.send_messenger(v, origin, receiver, k)
	_refresh()


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

func _selected() -> Kingdom:
	if game == null or _village_id == 0:
		return null
	return game.get_kingdom(_village_id)


func _is_confirm(action: String, v: Kingdom) -> bool:
	return _confirm_action == action and v != null and _confirm_village == v.id \
			and Time.get_ticks_msec() - _confirm_ms <= CONFIRM_MS


func _ask_confirm(action: String, v: Kingdom) -> void:
	_confirm_action = action
	_confirm_village = v.id
	_confirm_ms = Time.get_ticks_msec()


func _selected_res(option: OptionButton) -> String:
	var i := option.selected
	return _res_ids[i] if i >= 0 and i < _res_ids.size() else ""


func _res_name(res_id: String) -> String:
	return str(DataDB.get_resource(res_id).get("name", res_id))


## Kurzname auf dem Knopf ("Schutz (75 %)"); der volle Name steht im Tooltip
func _treaty_button_name(treaty_type: String) -> String:
	return str(TREATY_SHORT.get(treaty_type, DiplomacySystem.treaty_name(treaty_type)))


## "4 Erz, 6 Stein" (gerundet, Reihenfolge wie die Ressourcenleiste)
func _amounts_text(amounts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r in DataDB.resources:
		var amount := float(amounts.get(r["id"], 0.0))
		if amount >= 0.05:
			parts.append("%s %s" % [HeroUI.num(amount), str(r["name"])])
	return "nichts" if parts.is_empty() else ", ".join(parts)


static func _lines(prefix: String, items: Array) -> String:
	var parts: PackedStringArray = []
	for s in items:
		parts.append(prefix + str(s))
	return "\n".join(parts)


static func _duration(seconds: float) -> String:
	if seconds < 60.0:
		return "%d s" % floori(seconds)
	return "%d min" % floori(seconds / 60.0)


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	return row


func _section_label(text: String) -> Label:
	var label := _label(16, _light)
	label.text = text
	label.custom_minimum_size = Vector2(78, 0)
	return label


func _res_option() -> OptionButton:
	var o := OptionButton.new()
	# Kein Tastaturfokus, sonst würde die Leertaste (Pause) die Liste öffnen
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", 15)
	o.custom_minimum_size = Vector2(108, 36)
	for r in DataDB.resources:
		o.add_item(str(r["name"]))
	o.get_popup().add_theme_font_size_override("font_size", 15)
	return o


func _amount_button(text: String, group: ButtonGroup) -> Button:
	var b := _plain_button(text)
	b.toggle_mode = true
	b.button_group = group
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(46, 36)
	return b


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


func _rich(font_size: int) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", font_size)
	rtl.add_theme_font_size_override("bold_font_size", font_size)
	rtl.add_theme_color_override("default_color", COLOR_TEXT)
	return rtl


## Aktionsknopf: langer Text wird gekürzt statt das Fenster zu verbreitern
func _tip_button(text: String) -> ResearchTipButton:
	var b := ResearchTipButton.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(0, 36)
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return b


func _plain_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(0, 36)
	return b


func _set_text(label: Label, text: String, color: Color) -> void:
	if label.text != text:
		label.text = text
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _set_rich(rtl: RichTextLabel, text: String) -> void:
	if rtl.text != text:
		rtl.text = text


func _set_button_text(b: Button, text: String) -> void:
	if b.text != text:
		b.text = text


func _set_disabled(b: Button, disabled: bool) -> void:
	if b.disabled != disabled:
		b.disabled = disabled


func _evil_or(evil_color: Color, good_color: Color) -> Color:
	return evil_color if _evil else good_color
