## KingdomPanel
##
## Reichsübersicht (Phase 8; Taste L, Button "Reich" oben; L, Esc oder ×
## schliesst). Gleiche Bauart wie Forschungs-, Helden- und Diplomatiefenster (eigene
## Ebene, Mitte oben); das Spiel läuft weiter, es ist immer nur eines offen.
## Reiter:
## - "Zufriedenheit": Durchschnitt mit Gesicht und Balken, Verteilung auf die Stufen,
##   Folgen (Arbeitsleistung, Gefahr von Überlaufen und Verrat, laufende Überläufer),
##   Ursachen mit Tipps, Fest feiern, Verlauf und Statistik.
## - "Ereignisse": aktive Ereignisse (mit Hinspringen), offene Angebote von Flüchtlingen
##   und Wanderern (Aufnehmen/Abweisen), Verlauf und eine kurze Erklärung.
## - "Volk & Tageszeit": Volk mit Stärken und Schwächen, Grundbonus, jetzige Wirkungen der
##   Tageszeit, Zeit bis zum Wechsel, Geländetabelle und globale Nachtwerte.
## - "Handel" (Phase 9): Handelswege, Karawanen und Versorgung (TradeRouteList, dieselbe
##   Liste wie im Diplomatiefenster, Reiter "Handelswege").
## - "Bewerber": wartende Bewerber mit Bedingungen (✓/✗), Aufnehmen/Abweisen/Ansehen, wann der
##   nächste kommt, Wirkung der Taverne und das (seltene) natürliche Wachstum (RecruitSystem).
## - "Burg": Burgstufe, Bedingungen der nächsten Stufe mit ✓/✗, Knopf "Burg ausbauen" und was
##   jede Burgstufe freischaltet (BuildingSystem.level_requirements, dieselben Regeln wie die KI).
## Im F3-Modus erscheinen Debug-Knöpfe (Ereignis auslösen, Alle beenden,
## Monsterstreifzug, Zufriedenheit ±30, Überläufer, Verrat, Tageszeit erzwingen).
## Zeigt nur an und ruft die Systeme mit dem Spieler-Reich auf (dieselben Funktionen
## nutzt die KI). Aktualisiert alle 0.25 s, solange offen; Listen nur bei Änderungen.
class_name KingdomPanel
extends PanelContainer

## Fenster wurde geöffnet oder geschlossen
signal toggled(open: bool)

const TAB_SATISFACTION := "satisfaction"
const TAB_EVENTS := "events"
const TAB_PEOPLE := "people"
## Handelswege und Versorgung (Phase 9)
const TAB_TRADE := "trade"
const TAB_CASTLE := "castle"
const TAB_RECRUITS := "recruits"
const DESIGN_WIDTH := 1048.0
const TOP := 92.0
const PAGE_HEIGHT := 600.0
const REFRESH_INTERVAL := 0.25
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.74, 0.71, 0.66)
const COLOR_GOOD := Color(0.55, 0.88, 0.5)
const COLOR_BAD := Color(1.0, 0.45, 0.38)
const COLOR_WARN := Color(1.0, 0.82, 0.35)

var game: Node
var _evil := false
var _accent := ResearchPanel.GOOD_ACCENT
var _tab := TAB_SATISFACTION
var _timer := 0.0
var _dirty := true
## Reiter: id -> {"button", "page"}
var _tabs: Dictionary = {}
var _footer: Label

# Zufriedenheit
var _mood: MoodIcon
var _avg_label: Label
var _avg_bar: HpBar
var _dist_text: RichTextLabel
var _effects_text: RichTextLabel
var _jump_defector: Button
var _causes_text: RichTextLabel
var _feast_button: ResearchTipButton
var _feast_info: Label
var _log_text: RichTextLabel
var _stats_label: Label
var _sat_debug: HBoxContainer
# Ereignisse
var _events_box: VBoxContainer
var _offers_box: VBoxContainer
var _history_text: RichTextLabel
var _event_debug: HBoxContainer
var _debug_event_option: OptionButton
var _debug_target_option: OptionButton
## Kingdom-ids in der Reihenfolge der Ziel-Liste
var _debug_target_ids: Array = []
# Volk & Tageszeit
var _people_text: RichTextLabel
var _people_debug: HBoxContainer
# Handel (Phase 9)
var trade_list: TradeRouteList
# Bewerber
var _recruit_info: RichTextLabel
var _recruit_box: VBoxContainer
## Signatur der angezeigten Bewerber (ids), Zeilen: id -> {"text", "accept"}
var _recruit_sig := ""
var _recruit_rows: Dictionary = {}
# Burg (Burgstufen)
var _castle_text: RichTextLabel
var _castle_button: Button
var _unlock_text: RichTextLabel


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


## Aufbauen (das Fenster muss schon im Baum hängen)
func setup(p_game: Node) -> void:
	game = p_game
	_evil = game.player.faction_id == "evil"
	_accent = ResearchPanel.EVIL_ACCENT if _evil else ResearchPanel.GOOD_ACCENT
	add_theme_stylebox_override("panel", _panel_style())
	custom_minimum_size = Vector2(DESIGN_WIDTH, 0)
	_build()
	var ss: SatisfactionSystem = game.satisfaction_system
	var es: EventSystem = game.event_system
	ss.satisfaction_changed.connect(func(k: Kingdom, _avg: float) -> void:
		if k == game.player:
			_dirty = true)
	ss.defected.connect(func(_u: Unit, _f: Kingdom, _kind: String, _d: Kingdom) -> void: _dirty = true)
	ss.betrayed.connect(func(_v: Kingdom, _r: Kingdom, _d: bool) -> void: _dirty = true)
	es.event_started.connect(func(_ev: Dictionary) -> void: _dirty = true)
	es.event_ended.connect(func(_ev: Dictionary, _r: String) -> void: _dirty = true)
	es.offer_created.connect(func(_o: Dictionary) -> void: _dirty = true)
	es.offer_resolved.connect(func(_o: Dictionary, _a: bool) -> void: _dirty = true)
	game.day_night_system.phase_changed.connect(func(_p: String) -> void: _dirty = true)
	get_viewport().size_changed.connect(_place)
	Settings.changed.connect(_place)
	minimum_size_changed.connect(func() -> void:
		if visible:
			_place.call_deferred())
	show_tab(TAB_SATISFACTION)


func is_open() -> bool:
	return visible


func get_tab() -> String:
	return _tab


## Öffnen, optional auf einem Reiter
func open(tab: String = "") -> void:
	if not tab.is_empty():
		show_tab(tab)
	if visible:
		_refresh()
		return
	visible = true
	set_process(true)
	_timer = 0.0
	_dirty = true
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


## Reiter zeigen (Phase 9 ergänzt "trade")
func show_tab(tab: String) -> void:
	_tab = tab if _tabs.has(tab) else TAB_SATISFACTION
	for id in _tabs:
		var entry: Dictionary = _tabs[id]
		(entry["button"] as Button).set_pressed_no_signal(id == _tab)
		(entry["page"] as Control).visible = id == _tab
	_dirty = true
	if visible:
		_refresh()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH_INTERVAL:
		return
	_timer = 0.0
	_refresh()


# ---------------------------------------------------------------------------
# Aufbau
# ---------------------------------------------------------------------------

func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var title_row := UiStyle.window_header(root, "Reich", _evil, "Schliessen (L oder Esc)", close)
	var group := ButtonGroup.new()
	var pages := MarginContainer.new()
	pages.custom_minimum_size = Vector2(0, PAGE_HEIGHT)
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in [[TAB_SATISFACTION, "Zufriedenheit", "Zufriedenheit der Bewohner: Ursachen, Folgen, Feste"],
			[TAB_EVENTS, "Ereignisse", "Laufende Ereignisse, Flüchtlinge und Wanderer, Verlauf"],
			[TAB_PEOPLE, "Volk & Tageszeit", "Stärken und Schwächen deines Volks, Tag und Nacht, Gelände"],
			[TAB_TRADE, "Handel", "Handelswege, Karawanen, gesichtete fremde Wege und Versorgung"],
			[TAB_RECRUITS, "Bewerber", "Wartende Bewerber mit ihren Bedingungen, Taverne und natürliches Wachstum"],
			[TAB_CASTLE, "Burg", "Burgstufe, Bedingungen für die nächste Stufe und was sie freischaltet"]]:
		var b := _make_tab(str(entry[1]), group)
		b.tooltip_text = str(entry[2])
		b.pressed.connect(show_tab.bind(str(entry[0])))
		UiStyle.header_add(title_row, b)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		pages.add_child(scroll)
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 8)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(page)
		_tabs[str(entry[0])] = {"button": b, "page": scroll}
		match str(entry[0]):
			TAB_SATISFACTION:
				_build_satisfaction(page)
			TAB_EVENTS:
				_build_events(page)
			TAB_PEOPLE:
				_build_people(page)
			TAB_TRADE:
				_build_trade(page)
			TAB_CASTLE:
				_build_castle(page)
			TAB_RECRUITS:
				_build_recruits(page)
	root.add_child(pages)
	_footer = _label(15, COLOR_DIM)
	_footer.text = "Zufriedenheit: Nahrung, Wohnraum, Sicherheit, Taverne und Tempel, Feste  ·  L / Esc: schliessen"
	root.add_child(_footer)


func _build_satisfaction(page: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	page.add_child(head)
	_mood = MoodIcon.new()
	_mood.custom_minimum_size = Vector2(52, 52)
	head.add_child(_mood)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(col)
	_avg_label = _label(22, COLOR_TEXT)
	col.add_child(_avg_label)
	_avg_bar = HpBar.new()
	_avg_bar.custom_minimum_size = Vector2(0, 18)
	col.add_child(_avg_bar)
	_dist_text = _rich(16)
	page.add_child(_dist_text)
	_effects_text = _rich(16)
	page.add_child(_effects_text)
	_jump_defector = _small_button("Zum Überläufer springen", "Kamera zum ersten laufenden Überläufer – ein Befehl hält ihn auf")
	_jump_defector.pressed.connect(_on_jump_defector)
	page.add_child(_jump_defector)
	page.add_child(_section("Ursachen"))
	_causes_text = _rich(16)
	page.add_child(_causes_text)
	var feast_row := HBoxContainer.new()
	feast_row.add_theme_constant_override("separation", 10)
	page.add_child(feast_row)
	_feast_button = ResearchTipButton.new()
	_feast_button.add_theme_font_size_override("font_size", 16)
	_feast_button.tip_source = _feast_tip
	_feast_button.pressed.connect(_on_feast_pressed)
	feast_row.add_child(_feast_button)
	_feast_info = _label(15, COLOR_DIM)
	_feast_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feast_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feast_row.add_child(_feast_info)
	page.add_child(_section("Verlauf"))
	_log_text = _rich(15)
	page.add_child(_log_text)
	_stats_label = _label(15, COLOR_DIM)
	page.add_child(_stats_label)
	_sat_debug = HBoxContainer.new()
	_sat_debug.add_theme_constant_override("separation", 6)
	page.add_child(_sat_debug)
	for entry in [["Zufriedenheit −30", "minus"], ["Zufriedenheit +30", "plus"], ["Überläufer jetzt", "defect"],
			["Verrat jetzt", "betray"]]:
		var b := _small_button(str(entry[0]), "Debug (F3)")
		b.pressed.connect(debug_action.bind(str(entry[1])))
		_sat_debug.add_child(b)


func _build_events(page: VBoxContainer) -> void:
	page.add_child(_section("Laufende Ereignisse"))
	_events_box = VBoxContainer.new()
	_events_box.add_theme_constant_override("separation", 6)
	page.add_child(_events_box)
	page.add_child(_section("Flüchtlinge und Wanderer"))
	_offers_box = VBoxContainer.new()
	_offers_box.add_theme_constant_override("separation", 6)
	page.add_child(_offers_box)
	page.add_child(_section("Verlauf"))
	_history_text = _rich(15)
	page.add_child(_history_text)
	var info := _label(15, COLOR_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Ereignisse sind selten: frühestens nach 20 Minuten, danach etwa alle halbe Stunde irgendwo im Land.\nSie treffen alle Reiche – auch die Gegner und die Dörfer."
	page.add_child(info)
	_event_debug = HBoxContainer.new()
	_event_debug.add_theme_constant_override("separation", 6)
	page.add_child(_event_debug)
	_debug_event_option = OptionButton.new()
	_debug_event_option.focus_mode = Control.FOCUS_NONE
	_debug_event_option.tooltip_text = "Debug (F3): Ereignis zum Auslösen"
	for e in DataDB.get_events():
		_debug_event_option.add_item(str((e as Dictionary).get("name", "")))
		_debug_event_option.set_item_metadata(_debug_event_option.item_count - 1, str((e as Dictionary)["id"]))
	_event_debug.add_child(_debug_event_option)
	_debug_target_option = OptionButton.new()
	_debug_target_option.focus_mode = Control.FOCUS_NONE
	_debug_target_option.tooltip_text = "Debug (F3): betroffenes Reich"
	_event_debug.add_child(_debug_target_option)
	for entry in [["Auslösen", "trigger"], ["Alle beenden", "end_all"], ["Monsterstreifzug", "raid"]]:
		var b := _small_button(str(entry[0]), "Debug (F3)")
		b.pressed.connect(debug_action.bind(str(entry[1])))
		_event_debug.add_child(b)


## Handel (Phase 9): dieselbe Liste wie im Diplomatiefenster (Reiter "Handelswege")
func _build_trade(page: VBoxContainer) -> void:
	trade_list = TradeRouteList.new()
	trade_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(trade_list)
	trade_list.setup(game)
	trade_list.jump_requested.connect(func(pos: Vector2) -> void: game.camera.focus_on(pos))


func _build_recruits(page: VBoxContainer) -> void:
	page.add_child(_section("Wartende Bewerber"))
	_recruit_box = VBoxContainer.new()
	_recruit_box.add_theme_constant_override("separation", 8)
	page.add_child(_recruit_box)
	page.add_child(_section("Wie neue Bewohner kommen"))
	_recruit_info = _rich(15)
	page.add_child(_recruit_info)


func _build_castle(page: VBoxContainer) -> void:
	_castle_text = _rich(16)
	page.add_child(_castle_text)
	var row := HBoxContainer.new()
	page.add_child(row)
	_castle_button = _small_button("Burg ausbauen", "")
	_castle_button.pressed.connect(_on_castle_pressed)
	row.add_child(_castle_button)
	page.add_child(_section("Freischaltungen je Burgstufe"))
	_unlock_text = _rich(15)
	page.add_child(_unlock_text)


func _build_people(page: VBoxContainer) -> void:
	_people_text = _rich(16)
	page.add_child(_people_text)
	_people_debug = HBoxContainer.new()
	_people_debug.add_theme_constant_override("separation", 6)
	page.add_child(_people_debug)
	for entry in [["Tag", "day"], ["Nacht", "night"], ["Dämmerung", "dusk"], ["Echte Zeit", "real"]]:
		var b := _small_button(str(entry[0]), "Debug (F3): Tageszeit erzwingen")
		b.pressed.connect(debug_action.bind("phase_" + str(entry[1])))
		_people_debug.add_child(b)


# ---------------------------------------------------------------------------
# Aktualisieren
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if game == null or not visible:
		return
	var debug: bool = game.hud.is_debug_visible() if game.hud != null and game.hud.has_method("is_debug_visible") else false
	_sat_debug.visible = debug
	_event_debug.visible = debug
	_people_debug.visible = debug
	match _tab:
		TAB_SATISFACTION:
			_refresh_satisfaction()
		TAB_EVENTS:
			_refresh_events()
		TAB_PEOPLE:
			_refresh_people()
		TAB_CASTLE:
			_refresh_castle()
		TAB_RECRUITS:
			_refresh_recruits()
		TAB_TRADE:
			if trade_list != null:
				trade_list.refresh()
	_dirty = false


func _refresh_satisfaction() -> void:
	var k: Kingdom = game.player
	var ss: SatisfactionSystem = game.satisfaction_system
	var tip := ResearchTipButton
	var avg := ss.get_average(k)
	var tier := SatisfactionSystem.tier_for(maxf(avg, 0.0))
	_mood.set_value(avg)
	_set_label(_avg_label, "Keine Bewohner" if avg < 0.0 else "Ø %d – %s" % [roundi(avg), str(tier["name"])])
	_avg_bar.fill_color = tier["color"]
	_avg_bar.set_value(maxf(avg, 0.0), 100.0, "%d / 100" % roundi(maxf(avg, 0.0)))
	var tiers: Array = DataDB.sat("effects.tiers", [])
	var dist := ss.get_distribution(k)
	var parts: PackedStringArray = []
	for i in mini(tiers.size(), dist.size()):
		var t: Dictionary = tiers[i]
		parts.append(tip.colored("%s: %d" % [str(t.get("name", "")), int(dist[i])], Color(str(t.get("color", "#ffffff")))))
	_set_rich(_dist_text, "Verteilung: " + "  ·  ".join(parts))
	var lines: PackedStringArray = []
	var mult := SatisfactionSystem.work_mult_for(maxf(avg, 0.0))
	lines.append("Arbeitsleistung ×%s" % String.num(mult, 2).replace(".", ","))
	var risk := ss.get_risk(k)
	if int(risk["defect"]) > 0:
		lines.append(tip.colored("%d Bewohner unter %d: sie könnten überlaufen" % [int(risk["defect"]),
				int(DataDB.sat("defection.below", 25))], COLOR_BAD))
	if int(risk["betray"]) > 0:
		lines.append(tip.colored("%d unter %d: Verrat möglich" % [int(risk["betray"]), int(DataDB.sat("betrayal.below", 20))], COLOR_BAD))
	if int(risk["defecting"]) > 0:
		lines.append(tip.colored("%d läuft gerade über – ein Befehl hält ihn auf" % int(risk["defecting"]), COLOR_WARN))
	_set_rich(_effects_text, "\n".join(lines))
	_jump_defector.visible = int(risk["defecting"]) > 0
	var tips: Dictionary = DataDB.sat("tips", {})
	var cause_lines: PackedStringArray = []
	var pop := k.get_population()
	for p in ss.get_breakdown(k):
		var v := float(p["value"])
		var cause := str(p["cause"])
		var text := "%+d %s" % [roundi(v), cause]
		if cause == "Überfüllt":
			text += " (%d/%d)" % [pop, k.get_housing()]
		elif str(p["kind"]) == "building":
			text += " – %s" % _coverage_text(k, cause)
		var line := tip.colored(text.replace("-", "−"), COLOR_GOOD if v > 0.0 else (COLOR_BAD if v < 0.0 else COLOR_TEXT))
		if v < 0.0 and tips.has(cause):
			line += "  " + tip.colored(str(tips[cause]), COLOR_DIM)
		cause_lines.append(line)
	_set_rich(_causes_text, "\n".join(cause_lines))
	var cost := ss.feast_cost(k)
	var bonus := roundi(float(DataDB.sat("feast.bonus", 15)))
	var minutes := roundi(float(DataDB.sat("feast.seconds", 900)) / 60.0)
	var label := "Fest feiern (%s) – %+d für %d min" % [DataDB.cost_to_text(cost), bonus, minutes]
	if _feast_button.text != label:
		_feast_button.text = label
	var reason := ss.can_hold_feast(k)
	_feast_button.disabled = not reason.is_empty()
	_set_label(_feast_info, reason)
	var log_lines: PackedStringArray = []
	var log_list := ss.get_log(k)
	for i in range(log_list.size() - 1, maxi(log_list.size() - 9, -1), -1):
		var entry: Dictionary = log_list[i]
		log_lines.append("%s  %s" % [tip.colored(_clock(float(entry["t"])), COLOR_DIM), tip.esc(str(entry["text"]))])
	_set_rich(_log_text, "\n".join(log_lines) if not log_lines.is_empty() else tip.colored("Noch nichts geschehen.", COLOR_DIM))
	_set_label(_stats_label, "Überläufer: %d  ·  aufgenommene Überläufer: %d  ·  aufgenommene Flüchtlinge: %d  ·  Verrat: %d  ·  Feste: %d" % [
			int(k.stats.get("defected", 0)), int(k.stats.get("defectors_received", 0)), int(k.stats.get("refugees_accepted", 0)),
			int(k.stats.get("betrayals", 0)), int(k.stats.get("feasts", 0))])


func _coverage_text(k: Kingdom, cause: String) -> String:
	var cap := 0
	for b in k.buildings:
		if is_instance_valid(b) and b.constructed and DataDB.get_building_name(b.def, k.faction_id) == cause:
			cap += int((b.def.get("satisfaction", {}) as Dictionary).get("capacity", 0))
	var n := 0
	for u in k.units:
		if bool(u.type_def.get("needs_housing", false)):
			n += 1
	return "%d von %d Bewohnern versorgt" % [mini(cap, n), n]


func _refresh_events() -> void:
	var es: EventSystem = game.event_system
	var k: Kingdom = game.player
	var tip := ResearchTipButton
	if _dirty:
		_rebuild_event_rows()
		_rebuild_offer_rows()
		_rebuild_debug_targets()
	for row in _events_box.get_children():
		if not row.has_meta("text"):
			continue
		var uid := int(row.get_meta("uid", 0))
		var text: RichTextLabel = row.get_meta("text")
		for ev in es.active:
			if int(ev["uid"]) == uid:
				_set_rich(text, _event_text(ev))
	for row in _offers_box.get_children():
		if not row.has_meta("text"):
			continue
		var text: RichTextLabel = row.get_meta("text")
		var offer := es.get_offer(int(row.get_meta("offer_id", 0)))
		if not offer.is_empty():
			var def := DataDB.get_event(str(offer["event_id"]))
			_set_rich(text, "[b]%s[/b] %s\n%s" % [tip.esc(str(def.get("name", ""))), tip.esc(str(offer.get("story", ""))),
					tip.esc(es.get_offer_text(offer, k))])
	var hist: PackedStringArray = []
	var esp: Variant = game.get("espionage_system")
	var history := es.get_history()
	for i in range(history.size() - 1, -1, -1):
		if hist.size() >= 10:
			break
		var h: Dictionary = history[i]
		var target: Kingdom = game.get_kingdom(int(h["target_id"]))
		var visible_entry := target == k
		if not visible_entry and target != null and esp != null and (esp as Object).has_method("get_intel_level"):
			visible_entry = int(esp.get_intel_level(k, target)) >= 2
		if not visible_entry:
			continue
		var def := DataDB.get_event(str(h["event_id"]))
		hist.append("%s  %s – %s (%s)" % [tip.colored(_clock(float(h["started"])), COLOR_DIM), tip.esc(str(def.get("name", ""))),
				tip.esc("dein Reich" if target == k else target.display_name), tip.esc(str(h["outcome"]))])
	_set_rich(_history_text, "\n".join(hist) if not hist.is_empty() else tip.colored("Noch keine Ereignisse.", COLOR_DIM))


func _event_text(ev: Dictionary) -> String:
	var es: EventSystem = game.event_system
	var lines := es.describe(ev, game.player).split("\n")
	var def := DataDB.get_event(str(ev["event_id"]))
	var color: Color = def.get("color", COLOR_TEXT)
	var out: PackedStringArray = [ResearchTipButton.colored(lines[0], color)]
	for i in range(1, lines.size()):
		out.append(ResearchTipButton.esc(lines[i]))
	return "\n".join(out)


func _rebuild_event_rows() -> void:
	for c in _events_box.get_children():
		c.queue_free()
	var es: EventSystem = game.event_system
	var k: Kingdom = game.player
	var radius := float(DataDB.evt("player_notify_radius", 30)) * float(game.world.tile_size)
	var home := k.castle.get_center() if is_instance_valid(k.castle) else Vector2(-1.0e9, -1.0e9)
	var n := 0
	for ev in es.active:
		var kind := str(ev["kind"])
		if kind == "refugees" or kind == "wanderers":
			continue
		var near := home.distance_to(ev["pos"]) <= float(ev["radius"]) + radius
		if not es.affects(ev, k) and not near:
			continue
		n += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var text := _rich(15)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var jump := _small_button("Hinspringen", "Kamera zur Stelle des Ereignisses")
		jump.pressed.connect(_on_jump_event.bind(int(ev["uid"])))
		row.add_child(jump)
		row.set_meta("uid", int(ev["uid"]))
		row.set_meta("text", text)
		_events_box.add_child(row)
	if n == 0:
		var none := _label(15, COLOR_DIM)
		none.text = "Zurzeit kein Ereignis in deiner Nähe."
		_events_box.add_child(none)


func _rebuild_offer_rows() -> void:
	for c in _offers_box.get_children():
		c.queue_free()
	var es: EventSystem = game.event_system
	var offers := es.get_offers(game.player)
	if offers.is_empty():
		var none := _label(15, COLOR_DIM)
		none.text = "Niemand bittet gerade um Aufnahme."
		_offers_box.add_child(none)
		return
	for offer in offers:
		var id := int(offer["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var text := _rich(15)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var accept := _small_button("Aufnehmen", "Die Gruppe wird Teil deines Reichs")
		accept.add_theme_color_override("font_color", COLOR_GOOD)
		accept.pressed.connect(_on_accept_pressed.bind(id))
		row.add_child(accept)
		var reject := _small_button("Abweisen", "Die Gruppe zieht weiter")
		reject.pressed.connect(_on_reject_pressed.bind(id))
		row.add_child(reject)
		row.set_meta("offer_id", id)
		row.set_meta("text", text)
		_offers_box.add_child(row)


func _rebuild_debug_targets() -> void:
	var keep := -1
	if _debug_target_option.selected >= 0 and _debug_target_option.selected < _debug_target_ids.size():
		keep = int(_debug_target_ids[_debug_target_option.selected])
	_debug_target_option.clear()
	_debug_target_ids.clear()
	for e in game.kingdoms:
		var kk: Kingdom = e
		if kk.defeated:
			continue
		var is_village: bool = game.village_system.is_village(kk)
		if not (kk.controller == "player" or kk.controller == "ai" or is_village):
			continue
		_debug_target_option.add_item("Spieler" if kk == game.player else kk.display_name)
		_debug_target_ids.append(kk.id)
		if kk.id == keep:
			_debug_target_option.select(_debug_target_option.item_count - 1)


func _refresh_recruits() -> void:
	var k: Kingdom = game.player
	var rs: RecruitSystem = game.recruit_system
	var tip := ResearchTipButton
	var list := rs.get_recruits(k)
	var sig := ""
	for r in list:
		sig += "%d," % int(r["id"])
	if sig != _recruit_sig:
		_recruit_sig = sig
		_recruit_rows.clear()
		for c in _recruit_box.get_children():
			c.queue_free()
		if list.is_empty():
			var none := _label(15, COLOR_DIM)
			none.text = "Gerade wartet niemand."
			_recruit_box.add_child(none)
		for r in list:
			var id := int(r["id"])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_recruit_box.add_child(row)
			var text := _rich(15)
			row.add_child(text)
			var accept := _small_button("Aufnehmen", "")
			accept.pressed.connect(func() -> void:
				var reason: String = rs.accept(k, id)
				if not reason.is_empty():
					Notify.warning(reason)
				_refresh())
			row.add_child(accept)
			var reject := _small_button("Abweisen", "Der Bewerber zieht weiter")
			reject.pressed.connect(func() -> void:
				rs.reject(k, id)
				_refresh())
			row.add_child(reject)
			var view := _small_button("Ansehen", "Bewerberfenster öffnen")
			view.pressed.connect(func() -> void: game.hud.open_recruit_dialog(id))
			row.add_child(view)
			_recruit_rows[id] = {"text": text, "accept": accept}
	for r in list:
		var row: Dictionary = _recruit_rows.get(int(r["id"]), {})
		if row.is_empty():
			continue
		var lines: PackedStringArray = ["[b]%s[/b] – %s" % [tip.esc(rs.describe(r)), tip.esc(rs.job_text(r))]]
		for res in Requirements.check_all(r["reqs"], k, game):
			lines.append(tip.colored(("✓ " if bool(res["ok"]) else "✗ ") + str(res["text"]), COLOR_GOOD if bool(res["ok"]) else COLOR_BAD))
		if str(r["state"]) == "waiting":
			lines.append(tip.colored("Wartet noch %d s" % ceili(maxf(float(r["expires"]) - GameClock.game_time, 0.0)), COLOR_DIM))
		else:
			lines.append(tip.colored("Unterwegs zum Gebietsrand", COLOR_DIM))
		_set_rich(row["text"], "\n".join(lines))
		var reason := rs.can_accept(k, int(r["id"]))
		var accept: Button = row["accept"]
		accept.disabled = not reason.is_empty()
		accept.tooltip_text = "Wird dein Bewohner im Wunschberuf" if reason.is_empty() else "Noch nicht möglich – " + reason
	var info: PackedStringArray = []
	var next := rs.seconds_to_next(k)
	if next >= 0.0:
		info.append("Nächster Bewerber in etwa %d s (höchstens %d warten gleichzeitig)." % [ceili(next), int(DataDB.rec("max_waiting", 2))])
	var tav := rs.tavern_level(k)
	if tav > 0:
		info.append(tip.colored("Deine Taverne (Stufe %s) lockt Bewerber an: Wartezeit ×%s." % [DataDB.level_numeral(tav),
				String.num(rs.interval_mult(k), 2).replace(".", ",")], COLOR_GOOD))
	else:
		info.append("Eine Taverne lockt mehr Bewerber an, ausgebaut noch mehr.")
	info.append("Fachleute arbeiten in ihrem Wunschberuf %d %% schneller, stellen aber strengere Bedingungen." % roundi(
			float(DataDB.rec("skilled.work_bonus", 0.2)) * 100.0))
	var es: EconomySystem = game.economy_system
	var growth := "Natürlicher Zuwachs (selten): "
	match es.get_growth_state(k):
		EconomySystem.Growth.GROWING:
			growth += "nächster Bewohner in %d s" % ceili(es.get_seconds_to_growth(k))
		EconomySystem.Growth.HOUSING_FULL:
			growth += "gestoppt – Wohnraum voll"
		EconomySystem.Growth.LOW_FOOD:
			growth += "gestoppt – zu wenig Nahrung"
		EconomySystem.Growth.STARVING:
			growth += "gestoppt – Hungersnot"
		EconomySystem.Growth.LOW_SATISFACTION:
			growth += "gestoppt – Zufriedenheit unter %d" % int(DataDB.eco("population.growth_min_satisfaction", 50))
	info.append(growth)
	_set_rich(_recruit_info, "\n".join(info))


func _refresh_castle() -> void:
	var k: Kingdom = game.player
	var bs: BuildingSystem = game.building_system
	var tip := ResearchTipButton
	var castle := k.castle
	var level := k.get_castle_level()
	var max_level := DataDB.get_castle_max_level()
	var lines: PackedStringArray = []
	lines.append("[font_size=22]Burgstufe %s – %s[/font_size]" % [DataDB.level_numeral(level), DataDB.castle_level_name(level)])
	if not is_instance_valid(castle):
		lines.append(tip.colored("Deine Burg ist gefallen.", COLOR_BAD))
		_castle_button.visible = false
	elif level >= max_level:
		lines.append(tip.colored("Höchste Burgstufe erreicht – alle Gebäude sind freigeschaltet.", COLOR_GOOD))
		_castle_button.visible = false
	else:
		var next := level + 1
		var entry := DataDB.get_building_level_entry("castle", next)
		lines.append("[b]Nächste Stufe: %s – %s[/b]" % [DataDB.level_numeral(next), DataDB.castle_level_name(next)])
		var missing := k.missing_text(entry.get("cost", {}))
		lines.append("Kosten: %s · %d s Arbeit der Bauarbeiter%s" % [DataDB.cost_to_text(entry.get("cost", {})),
				roundi(float(entry.get("build_time", 0.0))), "" if missing.is_empty() else " · " + tip.colored(missing, COLOR_BAD)])
		lines.append("Bedingungen:")
		for req in BuildingSystem.level_requirements(entry, k):
			lines.append("  " + tip.colored(("✓ " if bool(req["ok"]) else "✗ ") + str(req["text"]),
					COLOR_GOOD if bool(req["ok"]) else COLOR_BAD))
		var unlocked := DataDB.buildings_unlocked_at(next, k.faction_id)
		if not unlocked.is_empty():
			lines.append("Schaltet frei: " + ", ".join(unlocked))
		_castle_button.visible = true
		if castle.is_upgrading():
			lines.append(tip.colored("Wird ausgebaut: %d %%" % roundi(castle.get_upgrade_ratio() * 100.0), COLOR_WARN))
			_castle_button.text = "Ausbau abbrechen"
			_castle_button.disabled = false
			_castle_button.tooltip_text = "Ausbau der Burg abbrechen – die Kosten kommen zurück."
		else:
			var reason := bs.can_upgrade(castle)
			_castle_button.text = "Burg ausbauen: %s" % DataDB.castle_level_name(next)
			_castle_button.disabled = not reason.is_empty()
			_castle_button.tooltip_text = "Die Bauarbeiter bauen die Burg aus; sie arbeitet dabei weiter." if reason.is_empty() \
					else "Noch nicht möglich: " + reason
	_set_rich(_castle_text, "\n".join(lines))
	var rows: PackedStringArray = []
	for lv in range(1, max_level + 1):
		var names := DataDB.buildings_unlocked_at(lv, k.faction_id)
		var head := "%s %s – %s" % ["✓" if lv <= level else "·", DataDB.level_numeral(lv), DataDB.castle_level_name(lv)]
		var text := ", ".join(names) if not names.is_empty() else "–"
		if lv == 3:
			text += "; Gebäude auf Stufe III"
		rows.append("%s: %s" % [tip.colored(head, COLOR_GOOD if lv <= level else COLOR_DIM), tip.esc(text)])
	_set_rich(_unlock_text, "\n".join(rows))


func _on_castle_pressed() -> void:
	var castle := (game.player as Kingdom).castle
	if not is_instance_valid(castle):
		return
	if castle.is_upgrading():
		game.building_system.cancel_upgrade(castle)
	else:
		game.building_system.start_upgrade(castle)
	_refresh()


func _refresh_people() -> void:
	var k: Kingdom = game.player
	var ps: PeopleSystem = game.people_system
	var dns: DayNightSystem = game.day_night_system
	var tip := ResearchTipButton
	var lines: PackedStringArray = []
	var summary := ps.get_summary(k)
	if summary.is_empty():
		lines.append(tip.colored("Dein Reich hat kein Volk.", COLOR_DIM))
	else:
		lines.append("[font_size=22]%s[/font_size]" % tip.colored(str(summary["name"]), summary["color"]))
		lines.append(tip.esc(str(summary["description"])))
		for s in summary["strengths"]:
			lines.append(tip.colored("+ " + str(s), COLOR_GOOD))
		for s in summary["weaknesses"]:
			lines.append(tip.colored("− " + str(s), COLOR_BAD))
		if not str(summary["base_text"]).is_empty():
			lines.append("Immer: " + tip.esc(str(summary["base_text"])))
		if not str(summary["preferred_text"]).is_empty():
			lines.append("Bevorzugtes Gelände: " + tip.esc(str(summary["preferred_text"])))
	lines.append("")
	var next := dns.seconds_to_next()
	var phase_line := "[b]Tageszeit: %s[/b]" % dns.get_phase_name()
	if float(next["seconds"]) >= 0.0:
		phase_line += " – %s in ca. %d s" % [dns.get_phase_name(str(next["phase"])), ceili(float(next["seconds"]))]
	else:
		phase_line += " – festgehalten (Debug)"
	lines.append(phase_line)
	var now_lines := dns.describe_kingdom(k)
	if now_lines.is_empty():
		lines.append(tip.colored("Jetzt: keine Wirkungen der Tageszeit", COLOR_DIM))
	for line_text in now_lines:
		lines.append("Jetzt – " + tip.esc(line_text))
	var own := DayNightSystem.people_daynight_text(k.people_id)
	if not own.is_empty():
		lines.append(tip.colored("Dein Volk: " + own, Color(0.62, 0.7, 1.0)))
	var night: Dictionary = DataDB.dn("global.night", {})
	var parts: PackedStringArray = []
	for key in night:
		parts.append(DataDB.describe_modifier(str(key), float(night[key])))
	lines.append(tip.colored("Nachts für alle: %s; wilde Monster sind aktiver und streifen häufiger umher." % ", ".join(parts), COLOR_DIM))
	lines.append("")
	lines.append("[b]Gelände[/b] (Einheiten deines Volks auf diesem Biom)")
	for row in ps.get_terrain_table(k.people_id):
		var r: Dictionary = row
		var name_text := str(r["name"]) + (" ★" if bool(r["preferred"]) else "")
		lines.append("%s: %s" % [tip.colored(name_text, COLOR_WARN if bool(r["preferred"]) else COLOR_TEXT), tip.esc(str(r["text"]))])
	_set_rich(_people_text, "\n".join(lines))


# ---------------------------------------------------------------------------
# Aktionen
# ---------------------------------------------------------------------------

## Fest feiern (auch Rauchtest)
func _on_feast_pressed() -> void:
	var ss: SatisfactionSystem = game.satisfaction_system
	var reason := ss.can_hold_feast(game.player)
	if not reason.is_empty():
		Notify.warning(reason)
		return
	ss.hold_feast(game.player)
	_refresh()


func _feast_tip() -> String:
	var ss: SatisfactionSystem = game.satisfaction_system
	var k: Kingdom = game.player
	var lines: PackedStringArray = ["[b]Fest feiern[/b]", "Kosten: " + DataDB.cost_to_text(ss.feast_cost(k)),
			"Bringt %+d Zufriedenheit für %d min, danach Pause (%d min)." % [roundi(float(DataDB.sat("feast.bonus", 15))),
			roundi(float(DataDB.sat("feast.seconds", 900)) / 60.0), roundi(float(DataDB.sat("feast.cooldown", 2400)) / 60.0)]]
	var reason := ss.can_hold_feast(k)
	if not reason.is_empty():
		lines.append(ResearchTipButton.colored(reason, COLOR_BAD))
	return "\n".join(lines)


## Angebot annehmen (auch Rauchtest)
func _on_accept_pressed(offer_id: int) -> void:
	var reason: String = game.event_system.accept_offer(game.player, offer_id)
	if not reason.is_empty():
		Notify.warning(reason)
	_dirty = true
	_refresh()


## Angebot abweisen (auch Rauchtest)
func _on_reject_pressed(offer_id: int) -> void:
	var reason: String = game.event_system.reject_offer(game.player, offer_id)
	if not reason.is_empty():
		Notify.warning(reason)
	_dirty = true
	_refresh()


func _on_jump_event(uid: int) -> void:
	for ev in game.event_system.active:
		if int(ev["uid"]) == uid:
			game.camera.focus_on(ev["pos"])
			return


func _on_jump_defector() -> void:
	var list: Array = game.satisfaction_system.get_defectors(game.player)
	if not list.is_empty():
		game.camera.focus_on((list[0] as Unit).position)
		game.selection.select([list[0]])


## Debug-Knöpfe (F3)
func debug_action(action: String) -> void:
	var k: Kingdom = game.player
	var ss: SatisfactionSystem = game.satisfaction_system
	var es: EventSystem = game.event_system
	match action:
		"minus", "plus":
			var avg := maxf(ss.get_average(k), 0.0)
			ss.debug_set_all(k, avg + (-30.0 if action == "minus" else 30.0))
		"defect":
			var u := ss.debug_force_defection(k)
			if u == null:
				Notify.warning("Debug: kein Bewohner kann überlaufen")
			else:
				Notify.info("Debug: ein Bewohner läuft über", u.position)
		"betray":
			if not ss.debug_force_betrayal(k):
				Notify.warning("Debug: kein feindliches Reich für Verrat")
		"trigger":
			var idx := _debug_event_option.selected
			var tidx := _debug_target_option.selected
			if idx < 0 or tidx < 0 or tidx >= _debug_target_ids.size():
				return
			var target: Kingdom = game.get_kingdom(int(_debug_target_ids[tidx]))
			var reason := es.debug_trigger(str(_debug_event_option.get_item_metadata(idx)), target)
			if not reason.is_empty():
				Notify.warning("Debug: " + reason)
		"end_all":
			es.debug_end_all()
		"raid":
			if not game.monster_system.debug_start_raid(k):
				Notify.warning("Debug: keine Höhle mit Monstern in Reichweite")
		"phase_day", "phase_night", "phase_dusk", "phase_real":
			var p := action.trim_prefix("phase_")
			game.day_night_system.debug_force_phase("" if p == "real" else p)
	_dirty = true
	_refresh()


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

func _place() -> void:
	if not visible:
		return
	UiStyle.place_window(self, DESIGN_WIDTH, TOP)


func _panel_style() -> StyleBoxFlat:
	return UiStyle.window_style(_evil)


func _make_tab(text: String, group: ButtonGroup) -> ResearchTipButton:
	return UiStyle.tab_button(text, group, _evil)


func _section(text: String) -> Label:
	var l := _label(18, ResearchPanel.EVIL_LIGHT if _evil else ResearchPanel.GOOD_ACCENT)
	l.text = text
	return l


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
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
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rtl


func _small_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _set_label(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
	label.visible = not text.is_empty()


func _set_rich(rtl: RichTextLabel, text: String) -> void:
	if rtl.text != text:
		rtl.text = text


## Spielzeit als "T2 14:05"
static func _clock(t: float) -> String:
	var h := fmod(GameClock.start_hour + t / GameClock.seconds_per_day * 24.0, 24.0)
	var day := int((GameClock.start_hour + t / GameClock.seconds_per_day * 24.0) / 24.0) + 1
	return "T%d %02d:%02d" % [day, int(h), int(h * 60.0) % 60]
