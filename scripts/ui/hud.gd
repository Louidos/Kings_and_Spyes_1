## HUD
##
## Spieloberfläche:
## - oben: Reich, Ressourcen, Kampfpunkte und Bewohner (ResourceBar), Buttons
##   "Forschung" mit Fortschritt, "Helden", "Diplomatie" und "Spionage" mit
##   Entdeckungswert (Balken, Punkt bei Gefahr), Datum, Tempo – die Tasten stehen
##   im Tooltip und im Steuerungshinweis (sonst wird die Leiste zu breit)
## - Forschungsfenster (ResearchPanel, Taste R), Heldenfenster (HeroPanel,
##   Taste G), Diplomatiefenster (DiplomacyPanel, Taste N) und Spionagefenster
##   (EspionagePanel, Taste K) in eigenen Ebenen darüber; es ist immer nur eines
##   davon offen (alle stehen in der Mitte)
## - oben links: Arbeitsverteilung (JobPanel, Taste J)
## - oben rechts: Meldungen (NotificationPanel)
## - unten links: Auswahlfenster (SelectionPanel), darunter die Armeeleiste
##   (ArmyBar), die Heldenleiste (HeroBar) und der Infobereich (Kachel, Gebäude oder Einheit unter der Maus)
## - unten Mitte: Baumenü (BuildMenu) mit Steuerungshinweis darüber
## - unten rechts: Minikarte
## Das HUD zeigt nur an und leitet Klicks an die Systeme weiter –
## Spiellogik liegt in den Systemen.
extends CanvasLayer

## So oft pro Sekunde wird der Infobereich neu geschrieben (Mengen ändern sich)
const INFO_REFRESH_INTERVAL := 0.25
## Zeilen, die der Infobereich immer reserviert (damit das Auswahlfenster
## darüber nicht springt, wenn die Maus über die Karte fährt)
const INFO_LINES := 7
## Einheit unter der Maus: Suchradius in Bildschirmpixeln (wie beim Anklicken)
const HOVER_PICK_RADIUS := 20.0
## Ebene des Forschungsfensters: über dem HUD und der Zauberleiste (beide 10),
## unter Spielmenü (40) und Spielende (45)
const RESEARCH_LAYER := 11
## Forschungs-Button oben: so oft pro Sekunde aktualisieren
const RESEARCH_REFRESH_INTERVAL := 0.25
const COLOR_RESEARCH_IDLE := Color(1.0, 0.85, 0.3)
## Ebene des Heldenfensters (wie das Forschungsfenster)
const HERO_LAYER := 11
## Ebene des Diplomatiefensters (wie das Forschungsfenster)
const DIPLOMACY_LAYER := 11
## Ebene des Spionagefensters (wie das Forschungsfenster)
const ESPIONAGE_LAYER := 11
## So lange (Spielsekunden) zeigt der Spionage-Knopf nach einer Gefahr einen roten Punkt
const ESPIONAGE_ALERT_SECONDS := 60.0
const COLOR_URGENT := Color(1.0, 0.36, 0.3)
## Innenabstand links/rechts der Knöpfe in der oberen Leiste (schmaler als im
## Theme, damit Ressourcen, vier Fenster-Knöpfe, Datum und Tempo in 1920 passen)
const TOP_BUTTON_MARGIN := 8.0

@onready var kingdom_label: Label = %KingdomLabel
@onready var resource_bar: ResourceBar = %ResourceBar
@onready var date_label: Label = %DateLabel
@onready var speed_bar: HBoxContainer = %SpeedBar
@onready var info_label: Label = %InfoLabel
@onready var minimap: Minimap = %Minimap
@onready var paused_label: Label = %PausedLabel
@onready var hint_label: Label = %HintLabel
@onready var debug_label: Label = %DebugLabel
@onready var build_menu: BuildMenu = %BuildMenu
@onready var job_panel: JobPanel = %JobPanel
@onready var selection_panel: SelectionPanel = %SelectionPanel
@onready var notification_panel: NotificationPanel = %NotificationPanel
@onready var bottom_left: VBoxContainer = $Root/BottomLeft
@onready var info_panel: PanelContainer = $Root/BottomLeft/InfoPanel

var game: Node
var world: WorldData
## Armeeleiste (wird in setup angelegt, steht zwischen Auswahlfenster und Infobereich)
var army_bar: ArmyBar
var world_map: WorldMap
var camera: RTSCamera
## Forschungsfenster (Taste R) und der Button oben in der Leiste
var research_panel: ResearchPanel
var _research_layer: CanvasLayer
var _research_button: ResearchTipButton
var _research_timer := 0.0
## Heldenfenster (Taste G), sein Button oben und die Heldenleiste unten links
var hero_panel: HeroPanel
var hero_bar: HeroBar
var _hero_layer: CanvasLayer
var _hero_button: ResearchTipButton
## Diplomatiefenster (Taste N) und sein Button oben
var diplomacy_panel: DiplomacyPanel
var _diplomacy_layer: CanvasLayer
var _diplomacy_button: ResearchTipButton
## Spionagefenster (Taste K) und sein Button oben (Balken = Entdeckungswert)
var espionage_panel: EspionagePanel
var _espionage_layer: CanvasLayer
var _espionage_button: ResearchTipButton
## Hinweis "Kampfpunkte ausgeben" kam schon (einmal je Partie)
var _kp_hint_shown := false

var _pause_button: Button
## Ein Button je Tempostufe (gleiche Reihenfolge wie GameClock.speed_steps)
var _speed_buttons: Array[Button] = []
var _blink_time := 0.0
var _hovered_cell := Vector2i(-1, -1)
var _info_timer := 0.0


func _ready() -> void:
	_build_speed_buttons()
	GameClock.speed_changed.connect(_on_speed_changed)
	_on_speed_changed(GameClock.paused, GameClock.get_speed())
	var faction := GameSession.get_faction()
	# Nur der Fraktionsname (in Fraktionsfarbe): die obere Leiste ist voll
	kingdom_label.text = str(faction.get("name", "?"))
	kingdom_label.tooltip_text = "Dein Königreich (Fraktion %s)" % faction.get("name", "?")
	kingdom_label.mouse_filter = Control.MOUSE_FILTER_STOP
	kingdom_label.add_theme_color_override("font_color", faction.get("color", Color.WHITE))
	info_label.text = "Bewege die Maus über die Karte."
	info_label.custom_minimum_size.y = (info_label.get_line_height() + info_label.get_theme_constant("line_spacing")) * INFO_LINES
	debug_label.visible = false
	# Steuerungshinweis nach einer Weile ausblenden
	var tween := create_tween()
	tween.tween_interval(25.0)
	tween.tween_property(hint_label, "modulate:a", 0.0, 2.0)


## Wird von der Spielszene aufgerufen, sobald die Welt erzeugt ist.
func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	camera = game.camera
	world_map = game.world_map
	minimap.setup(world_map.overview_texture, world.get_pixel_size(), camera)
	minimap.setup_game(game)
	world_map.hovered_cell_changed.connect(_on_hovered_cell_changed)
	resource_bar.setup(game)
	build_menu.setup(game)
	job_panel.setup(game)
	selection_panel.setup(game)
	notification_panel.setup(game)
	# Armeeleiste direkt über dem Infobereich: ihre Lage hängt nicht von der
	# Höhe des Auswahlfensters ab (Doppelklick trifft denselben Button)
	army_bar = ArmyBar.new()
	bottom_left.add_child(army_bar)
	bottom_left.move_child(army_bar, info_panel.get_index())
	army_bar.setup(game)
	# Heldenleiste direkt über dem Infobereich (unter der Armeeleiste): feste Lage
	hero_bar = HeroBar.new()
	hero_bar.name = "HeroBar"
	bottom_left.add_child(hero_bar)
	bottom_left.move_child(hero_bar, info_panel.get_index())
	hero_bar.setup(game)
	_setup_research()
	_setup_heroes()
	_setup_diplomacy()
	_setup_espionage()


## Forschungsfenster ein-/ausblenden (Taste R, Button oben)
func toggle_research() -> void:
	if research_panel != null:
		research_panel.toggle()


## Forschungsfenster öffnen (optional auf einem Reiter: ResearchPanel.TAB_TREE / TAB_POINTS)
func open_research(tab: String = "") -> void:
	if research_panel != null:
		research_panel.open(tab)


func is_research_open() -> bool:
	return research_panel != null and research_panel.is_open()


## Heldenfenster ein-/ausblenden (Taste G, Button oben)
func toggle_heroes() -> void:
	if hero_panel != null:
		hero_panel.toggle()


## Heldenfenster öffnen (Reiter HeroPanel.TAB_HEROES / TAB_RECRUIT, optional bei einem Helden)
func open_heroes(tab: String = "", hero_id: int = 0) -> void:
	if hero_panel != null:
		hero_panel.open(tab, hero_id)


func is_heroes_open() -> bool:
	return hero_panel != null and hero_panel.is_open()


## Diplomatiefenster ein-/ausblenden (Taste N, Button oben)
func toggle_diplomacy() -> void:
	if diplomacy_panel != null:
		diplomacy_panel.toggle()


## Diplomatiefenster öffnen, optional bei einem Dorf (Kingdom.id)
func open_diplomacy(village_id: int = 0) -> void:
	if diplomacy_panel != null:
		diplomacy_panel.open(village_id)


func is_diplomacy_open() -> bool:
	return diplomacy_panel != null and diplomacy_panel.is_open()


## Spionagefenster ein-/ausblenden (Taste K, Button oben)
func toggle_espionage() -> void:
	if espionage_panel != null:
		espionage_panel.toggle()


## Spionagefenster öffnen (Reiter EspionagePanel.TAB_*, optional bei einem Reich/Dorf
## oder – Reiter Spione – mit vorgewähltem Ziel und Spion)
func open_espionage(tab: String = "", target_id: int = 0, spy_uid: int = 0) -> void:
	if espionage_panel != null:
		espionage_panel.open(tab, target_id, spy_uid)


func is_espionage_open() -> bool:
	return espionage_panel != null and espionage_panel.is_open()


## Verweis aus einer Meldung öffnen ({"window": "heroes", "hero_id": …},
## "research", {"window": "diplomacy", "village_id": …} oder
## {"window": "espionage", "tab": …, "target_id": …, "spy_uid": …})
func open_link(link: Dictionary) -> void:
	match str(link.get("window", "")):
		"heroes":
			open_heroes(HeroPanel.TAB_HEROES, int(link.get("hero_id", 0)))
		"research":
			open_research()
		"diplomacy":
			open_diplomacy(int(link.get("village_id", 0)))
		"espionage":
			open_espionage(str(link.get("tab", "")), int(link.get("target_id", 0)), int(link.get("spy_uid", 0)))


## Esc schliesst das Spionage-, Diplomatie-, Helden- bzw. Forschungsfenster auch, wenn
## gerade ein Tooltip offen ist (Godot verbraucht Esc sonst nur zum Schliessen des Tooltips).
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("game_menu") or event.is_echo():
		return
	if is_espionage_open():
		espionage_panel.close()
		get_viewport().set_input_as_handled()
	elif is_diplomacy_open():
		diplomacy_panel.close()
		get_viewport().set_input_as_handled()
	elif is_heroes_open():
		hero_panel.close()
		get_viewport().set_input_as_handled()
	elif is_research_open():
		research_panel.close()
		get_viewport().set_input_as_handled()


## Arbeitsverteilung ein-/ausblenden (Taste J)
func toggle_job_panel() -> void:
	job_panel.toggle()


## Esc: schliesst das oberste offene Fenster (Spionage, Diplomatie, Helden, Forschung,
## Arbeitsverteilung). true = etwas wurde geschlossen (dann nichts weiter tun).
func close_top_panel() -> bool:
	if is_espionage_open():
		espionage_panel.close()
		return true
	if is_diplomacy_open():
		diplomacy_panel.close()
		return true
	if is_heroes_open():
		hero_panel.close()
		return true
	if is_research_open():
		research_panel.close()
		return true
	if job_panel.visible:
		job_panel.toggle()
		return true
	return false


func is_debug_visible() -> bool:
	return debug_label.visible


func toggle_debug() -> void:
	debug_label.visible = not debug_label.visible


func _process(delta: float) -> void:
	date_label.text = GameClock.get_time_string()
	if paused_label.visible:
		_blink_time += delta
		paused_label.modulate.a = 0.6 + 0.4 * cos(_blink_time * 3.0)
	if debug_label.visible and world_map != null:
		debug_label.text = "FPS %d  ·  Zoom %.2f  ·  Chunks %d  ·  Seed %s  ·  F9: +100 Ressourcen  ·  F10: König −150  ·  F11: 3 Wölfe an der Maus  ·  F12: Held +1 Stufe" % [
			Engine.get_frames_per_second(), camera.zoom.x,
			world_map.get_loaded_chunk_count(), GameSession.seed_text]
	if world != null:
		_info_timer += delta
		if _info_timer >= INFO_REFRESH_INTERVAL:
			_info_timer = 0.0
			_update_info()
	if _research_button != null:
		_research_timer += delta
		if _research_timer >= RESEARCH_REFRESH_INTERVAL:
			_research_timer = 0.0
			_refresh_research_button()
			_refresh_hero_button()
			_refresh_diplomacy_button()
			_refresh_espionage_button()


# ---------------------------------------------------------------------------
# Forschung
# ---------------------------------------------------------------------------

## Fenster in eigener Ebene (liegt über HUD und Zauberleiste) und Button oben
func _setup_research() -> void:
	_research_layer = CanvasLayer.new()
	_research_layer.layer = RESEARCH_LAYER
	_research_layer.name = "ResearchLayer"
	add_child(_research_layer)
	research_panel = ResearchPanel.new()
	research_panel.name = "ResearchPanel"
	_research_layer.add_child(research_panel)
	research_panel.setup(game)
	research_panel.toggled.connect(_on_research_toggled)
	# Eine CanvasLayer erbt die Sichtbarkeit des HUD nicht von selbst
	visibility_changed.connect(func() -> void: _research_layer.visible = visible)
	_research_layer.visible = visible

	_research_button = ResearchTipButton.new()
	_research_button.name = "ResearchButton"
	_research_button.text = "Forschung"
	_research_button.toggle_mode = true
	_research_button.add_theme_font_size_override("font_size", 16)
	_compact(_research_button)
	_research_button.tip_source = _research_button_tip
	_research_button.pressed.connect(toggle_research)
	var hbox := date_label.get_parent()
	hbox.add_child(_research_button)
	hbox.move_child(_research_button, date_label.get_index())
	resource_bar.kill_points_clicked.connect(open_research.bind(ResearchPanel.TAB_POINTS))
	var rs: ResearchSystem = game.research_system
	rs.queue_changed.connect(_on_research_state_changed)
	rs.research_completed.connect(_on_research_state_changed.unbind(1))
	_refresh_research_button()


func _on_research_toggled(open: bool) -> void:
	_research_button.set_pressed_no_signal(open)
	# Die Fenster stehen in der Mitte: nur eines offen
	if open:
		_close_other_panels(research_panel)


## Schliesst alle Fenster in der Mitte ausser keep (Forschung, Helden, Diplomatie, Spionage)
func _close_other_panels(keep: Control) -> void:
	for panel in [research_panel, hero_panel, diplomacy_panel, espionage_panel]:
		if panel != null and panel != keep and panel.is_open():
			panel.close()


func _on_research_state_changed(k: Kingdom) -> void:
	if k == game.player:
		_refresh_research_button()


## Button oben: "Forschung · 45 %" (mit Strich), gelb "Forschung ruht"
## bzw. "Forschung steht" (keine fertige Forschungsstätte),
## Punkt, wenn eine Kampfpunkt-Verbesserung bezahlbar ist
func _refresh_research_button() -> void:
	var k: Kingdom = game.player
	var rs: ResearchSystem = game.research_system
	var active := rs.get_active(k)
	var text := "Forschung"
	var idle := false
	if not active.is_empty():
		_research_button.underline_ratio = rs.get_progress_ratio(k)
		if rs.get_speed(k) <= 0.0:
			# Keine fertige Forschungsstätte mehr: Forschung steht still
			text = "Forschung steht · %d %%" % floori(rs.get_progress_ratio(k) * 100.0)
			idle = true
		else:
			text = "Forschung · %d %%" % floori(rs.get_progress_ratio(k) * 100.0)
	else:
		_research_button.underline_ratio = -1.0
		idle = rs.count_research_buildings(k) > 0
		if idle:
			text = "Forschung ruht"
	if _research_button.text != text:
		_research_button.text = text
	var font_color := COLOR_RESEARCH_IDLE if idle else Color(0.95, 0.91, 0.82)
	if _research_button.get_theme_color("font_color") != font_color:
		_research_button.add_theme_color_override("font_color", font_color)
		_research_button.add_theme_color_override("font_hover_color", font_color.lightened(0.15))
	var affordable := ResearchPanel.has_affordable_upgrade(rs, k)
	_research_button.badge_visible = affordable
	# Einmal je Partie: Hinweis, dass Kampfpunkte ausgegeben werden können
	if affordable and not _kp_hint_shown:
		_kp_hint_shown = true
		Notify.good("Du kannst Kampfpunkte ausgeben: Forschung (R) → Kampfpunkte")


func _research_button_tip() -> String:
	var k: Kingdom = game.player
	var rs: ResearchSystem = game.research_system
	var tip := ResearchTipButton
	var lines: PackedStringArray = ["[b]Forschung[/b] (Taste R)"]
	var active := rs.get_active(k)
	if not active.is_empty():
		var remaining := rs.get_remaining_seconds(k)
		var rest := "angehalten" if remaining == INF else "noch %d s" % ceili(remaining)
		lines.append(tip.colored("Erforscht: %s – %d %% – %s" % [str(DataDB.get_research(active).get("name", active)),
				floori(rs.get_progress_ratio(k) * 100.0), rest], ResearchCard.COLOR_ACTIVE.lightened(0.2)))
		if k.research_queue.size() > 1:
			var names: PackedStringArray = []
			for i in range(1, k.research_queue.size()):
				names.append(str(DataDB.get_research(str(k.research_queue[i])).get("name", "")))
			lines.append("Danach: " + tip.esc(", ".join(names)))
	elif rs.count_research_buildings(k) > 0:
		lines.append(tip.colored("Forschung ruht – wähle eine Forschung im Fenster.", COLOR_RESEARCH_IDLE))
	elif rs.get_research_site(k) != null:
		var site := rs.get_research_site(k)
		lines.append(tip.colored("%s wird gebaut – %d %%. Danach kannst du forschen." % [site.get_display_name(),
				floori(site.get_progress_ratio() * 100.0)], COLOR_RESEARCH_IDLE))
	else:
		var bname := rs.get_research_building_name(k)
		lines.append(tip.colored("Zum Forschen brauchst du: %s (Baumenü)" % bname, COLOR_RESEARCH_IDLE))
	lines.append("Erforscht: %d von %d" % [k.researched.size(), rs.get_tree_for(k).size()])
	if ResearchPanel.has_affordable_upgrade(rs, k):
		lines.append(tip.colored("Kampfpunkte ausgeben möglich (Reiter „Kampfpunkte“)", Color(0.55, 0.88, 0.5)))
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Helden
# ---------------------------------------------------------------------------

## Heldenfenster in eigener Ebene und Button "Helden" rechts neben "Forschung"
func _setup_heroes() -> void:
	_hero_layer = CanvasLayer.new()
	_hero_layer.layer = HERO_LAYER
	_hero_layer.name = "HeroLayer"
	add_child(_hero_layer)
	hero_panel = HeroPanel.new()
	hero_panel.name = "HeroPanel"
	_hero_layer.add_child(hero_panel)
	hero_panel.setup(game)
	hero_panel.toggled.connect(_on_heroes_toggled)
	visibility_changed.connect(func() -> void: _hero_layer.visible = visible)
	_hero_layer.visible = visible

	_hero_button = ResearchTipButton.new()
	_hero_button.name = "HeroButton"
	_hero_button.text = "Helden"
	_hero_button.toggle_mode = true
	_hero_button.add_theme_font_size_override("font_size", 16)
	_compact(_hero_button)
	_hero_button.badge_color = HeroUI.COLOR_PENDING
	_hero_button.underline_color = HeroUI.COLOR_XP
	_hero_button.tip_source = _hero_button_tip
	_hero_button.pressed.connect(toggle_heroes)
	var hbox := date_label.get_parent()
	hbox.add_child(_hero_button)
	hbox.move_child(_hero_button, date_label.get_index())
	game.hero_system.heroes_changed.connect(_on_heroes_changed)
	_refresh_hero_button()


func _on_heroes_toggled(open: bool) -> void:
	_hero_button.set_pressed_no_signal(open)
	if open:
		_close_other_panels(hero_panel)


func _on_heroes_changed(k: Kingdom) -> void:
	if k == game.player:
		_refresh_hero_button()


## "Helden · 2/3"; Punkt bei offener Stufenwahl oder wenn ein Held wiederbelebt werden kann
func _refresh_hero_button() -> void:
	if _hero_button == null:
		return
	var k: Kingdom = game.player
	var hs: HeroSystem = game.hero_system
	var n := hs.count_heroes(k)
	var text := "Helden" if n == 0 else "Helden · %d/%d" % [n, hs.max_heroes(k)]
	if _hero_button.text != text:
		_hero_button.text = text
	_hero_button.badge_visible = HeroPanel.needs_attention(hs, k)


func _hero_button_tip() -> String:
	var k: Kingdom = game.player
	var hs: HeroSystem = game.hero_system
	var tip := ResearchTipButton
	var lines: PackedStringArray = ["[b]Helden[/b] (Taste G)"]
	if hs.get_heroes(k).is_empty():
		var hall_name := DataDB.get_building_name(DataDB.get_building("hero_hall"), k.faction_id)
		lines.append(tip.colored("Noch keine Helden – in der %s anwerben (Reiter „Anwerben“)" % hall_name, COLOR_RESEARCH_IDLE))
	for rec in hs.get_heroes(k):
		var line := "%s – Stufe %d" % [hs.get_title(rec), int(rec["level"])]
		if int(rec["pending"]) > 0:
			lines.append(tip.colored(line + " – Stufenwahl offen", HeroUI.COLOR_PENDING))
		elif bool(rec["dead"]):
			lines.append(tip.colored(line + " – " + HeroUI.state_text(hs, rec, null), HeroUI.COLOR_BAD))
		else:
			lines.append(tip.esc(line))
	lines.append("Helden: %d von %d" % [hs.count_heroes(k), hs.max_heroes(k)])
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Diplomatie
# ---------------------------------------------------------------------------

## Diplomatiefenster in eigener Ebene und Button "Diplomatie" rechts neben "Helden"
func _setup_diplomacy() -> void:
	_diplomacy_layer = CanvasLayer.new()
	_diplomacy_layer.layer = DIPLOMACY_LAYER
	_diplomacy_layer.name = "DiplomacyLayer"
	add_child(_diplomacy_layer)
	diplomacy_panel = DiplomacyPanel.new()
	diplomacy_panel.name = "DiplomacyPanel"
	_diplomacy_layer.add_child(diplomacy_panel)
	diplomacy_panel.setup(game)
	diplomacy_panel.toggled.connect(_on_diplomacy_toggled)
	visibility_changed.connect(func() -> void: _diplomacy_layer.visible = visible)
	_diplomacy_layer.visible = visible

	_diplomacy_button = ResearchTipButton.new()
	_diplomacy_button.name = "DiplomacyButton"
	_diplomacy_button.text = "Diplomatie"
	_diplomacy_button.toggle_mode = true
	_diplomacy_button.add_theme_font_size_override("font_size", 16)
	_compact(_diplomacy_button)
	_diplomacy_button.badge_color = COLOR_URGENT
	_diplomacy_button.tip_source = _diplomacy_button_tip
	_diplomacy_button.pressed.connect(toggle_diplomacy)
	var hbox := date_label.get_parent()
	hbox.add_child(_diplomacy_button)
	hbox.move_child(_diplomacy_button, date_label.get_index())
	_refresh_diplomacy_button()


func _on_diplomacy_toggled(open: bool) -> void:
	_diplomacy_button.set_pressed_no_signal(open)
	if open:
		_close_other_panels(diplomacy_panel)


## Punkt (rot), solange ein Schutzbefohlener Hilfe braucht
func _refresh_diplomacy_button() -> void:
	if _diplomacy_button == null:
		return
	_diplomacy_button.badge_visible = not game.diplomacy_system.get_urgent(game.player).is_empty()


func _diplomacy_button_tip() -> String:
	var k: Kingdom = game.player
	var ds: DiplomacySystem = game.diplomacy_system
	var vs: VillageSystem = game.village_system
	var tip := ResearchTipButton
	var lines: PackedStringArray = ["[b]Diplomatie[/b] (Taste N)"]
	var villages := vs.get_villages()
	lines.append("Selbstständige Dörfer: %d" % villages.size())
	var hostile := 0
	for v in villages:
		if game.are_hostile(k, v):
			hostile += 1
	if hostile > 0:
		lines.append(tip.colored("Im Krieg mit %d %s" % [hostile, "Dorf" if hostile == 1 else "Dörfern"], COLOR_URGENT))
	var treaties := ds.get_treaties_of(k)
	if treaties.is_empty():
		lines.append("Noch keine Verträge – Geschenke verbessern den Ruf")
	for t in treaties:
		lines.append(tip.esc("%s mit %s" % [DiplomacySystem.treaty_name(str(t["type"])), (t["village"] as Kingdom).display_name]))
	for u in ds.get_urgent(k):
		var v: Kingdom = u["village"]
		lines.append(tip.colored("Hilfe nötig: %s – noch %d s" % [v.display_name if v != null else "?",
				maxi(ceili(float(u["deadline"]) - GameClock.game_time), 0)], COLOR_URGENT))
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Spionage
# ---------------------------------------------------------------------------

## Spionagefenster in eigener Ebene und Button "Spionage · 42" rechts neben "Diplomatie"
## (Strich = Entdeckungswert in der Farbe seiner Stufe, roter Punkt bei Gefahr)
func _setup_espionage() -> void:
	_espionage_layer = CanvasLayer.new()
	_espionage_layer.layer = ESPIONAGE_LAYER
	_espionage_layer.name = "EspionageLayer"
	add_child(_espionage_layer)
	espionage_panel = EspionagePanel.new()
	espionage_panel.name = "EspionagePanel"
	_espionage_layer.add_child(espionage_panel)
	espionage_panel.setup(game)
	espionage_panel.toggled.connect(_on_espionage_toggled)
	visibility_changed.connect(func() -> void: _espionage_layer.visible = visible)
	_espionage_layer.visible = visible

	_espionage_button = ResearchTipButton.new()
	_espionage_button.name = "EspionageButton"
	_espionage_button.text = "Spionage"
	_espionage_button.toggle_mode = true
	_espionage_button.add_theme_font_size_override("font_size", 16)
	_compact(_espionage_button)
	_espionage_button.badge_color = COLOR_URGENT
	_espionage_button.tip_source = _espionage_button_tip
	_espionage_button.pressed.connect(toggle_espionage)
	var hbox := date_label.get_parent()
	hbox.add_child(_espionage_button)
	hbox.move_child(_espionage_button, date_label.get_index())
	_refresh_espionage_button()


func _on_espionage_toggled(open: bool) -> void:
	_espionage_button.set_pressed_no_signal(open)
	if open:
		_close_other_panels(espionage_panel)


## "Spionage · 42" mit Strich (Entdeckungswert); roter Punkt, wenn kürzlich ein fremder
## Spion entdeckt wurde oder die bekannte Aufmerksamkeit eines Reichs gestiegen ist
func _refresh_espionage_button() -> void:
	if _espionage_button == null:
		return
	var k: Kingdom = game.player
	var esp: EspionageSystem = game.espionage_system
	var value := esp.get_discovery(k)
	var text := "Spionage · %d" % roundi(value)
	if _espionage_button.text != text:
		_espionage_button.text = text
	_espionage_button.underline_ratio = clampf(value / maxf(float(DataDB.esp("discovery.max_display", 150)), 1.0), 0.0, 1.0)
	_espionage_button.underline_color = EspionageSystem.discovery_tier(value)["color"]
	_espionage_button.badge_visible = espionage_alert(k)


## Gab es in den letzten ESPIONAGE_ALERT_SECONDS eine Spionage-Gefahr (Merker in k.flags)?
static func espionage_alert(k: Kingdom) -> bool:
	var at := float(k.flags.get("espionage_alert_at", -1.0e9))
	return GameClock.game_time - at <= ESPIONAGE_ALERT_SECONDS


func _espionage_button_tip() -> String:
	var k: Kingdom = game.player
	var esp: EspionageSystem = game.espionage_system
	var spies: SpySystem = game.spy_system
	var tip := ResearchTipButton
	var value := esp.get_discovery(k)
	var tier := EspionageSystem.discovery_tier(value)
	var lines: PackedStringArray = ["[b]Spionage[/b] (Taste K)"]
	lines.append(tip.colored("Entdeckungswert %d – %s" % [roundi(value), str(tier["name"])], tier["color"]))
	lines.append(tip.esc(EspionagePanel.causes_text(esp.get_discovery_parts(k), esp.get_aggression(k) > 0.5).replace("\n", " · ")))
	if esp.is_cloaked(k):
		lines.append(tip.colored("Reichstarnung aktiv – %s Mana/min" % tip.num1(esp.cloak_upkeep(k) * 60.0), Color(0.55, 0.88, 0.5)))
	lines.append("Spione: %d von %d" % [spies.get_spies(k).size(), spies.max_spies(k)])
	if espionage_alert(k):
		lines.append(tip.colored("Gefahr: fremder Spion entdeckt oder ein Reich ist aufmerksamer geworden", COLOR_URGENT))
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Tempo
# ---------------------------------------------------------------------------

func _build_speed_buttons() -> void:
	for child in speed_bar.get_children():
		child.queue_free()
	var group := ButtonGroup.new()
	_pause_button = _make_speed_button("Pause", group, "Pause (Leertaste)")
	_pause_button.pressed.connect(GameClock.set_paused.bind(true))
	for i in GameClock.speed_steps.size():
		var step := float(GameClock.speed_steps[i])
		var b := _make_speed_button(_speed_text(step), group, "Spieltempo %s (+ / −)" % _speed_text(step))
		b.pressed.connect(GameClock.set_speed_index.bind(i))
		_speed_buttons.append(b)


func _make_speed_button(text: String, group: ButtonGroup, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.tooltip_text = tooltip
	# Kein Tastaturfokus, sonst würde die Leertaste den Button auslösen
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(42, 0)
	_compact(b)
	speed_bar.add_child(b)
	return b


## Knopf der oberen Leiste mit schmalerem Innenabstand (Theme-Stile kopiert)
func _compact(b: Button) -> void:
	for style_name in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var base := b.get_theme_stylebox(style_name)
		if base == null:
			continue
		var style := base.duplicate() as StyleBox
		style.content_margin_left = TOP_BUTTON_MARGIN
		style.content_margin_right = TOP_BUTTON_MARGIN
		b.add_theme_stylebox_override(style_name, style)


func _speed_text(step: float) -> String:
	return ("%sx" % str(step)).replace(".0x", "x")


func _on_speed_changed(paused: bool, _speed: float) -> void:
	var active := _pause_button if paused else _speed_buttons[GameClock.speed_index]
	_pause_button.set_pressed_no_signal(_pause_button == active)
	for b in _speed_buttons:
		b.set_pressed_no_signal(b == active)
	paused_label.visible = paused
	_blink_time = 0.0


# ---------------------------------------------------------------------------
# Infobereich (Kachel unter der Maus)
# ---------------------------------------------------------------------------

func _on_hovered_cell_changed(cell: Vector2i) -> void:
	_hovered_cell = cell
	_info_timer = 0.0
	_update_info()


func _update_info() -> void:
	var cell := _hovered_cell
	if cell.x < 0 or not world.in_bounds(cell):
		_set_info("Bewege die Maus über die Karte.")
		return
	var b := world.get_biome(cell)
	var defense := float(b.get("defense_bonus", 0.0))
	var lines: PackedStringArray = []
	lines.append("%s\nKachel %d, %d\nBewegung: %.1f×   Verteidigung: %+d %%\nBebaubar: %s   Höhe: %d %%" % [
		b.get("name", "?"), cell.x, cell.y,
		float(b.get("movement_cost", 1.0)), roundi(defense * 100.0),
		"ja" if b.get("buildable", false) else "nein",
		roundi(world.get_elevation(cell) * 100.0)])
	var deposit := _deposit_text(cell)
	if not deposit.is_empty():
		lines.append(deposit)
	match world.get_road(cell):
		WorldData.ROAD_BUILT:
			lines.append("Strasse")
		WorldData.ROAD_PLANNED:
			lines.append("Strasse (geplant)")
	var building: Object = world.get_building_at(cell)
	if is_instance_valid(building) and building is Building:
		var bld := building as Building
		var text := bld.get_display_name()
		if not bld.constructed:
			text += " (Baustelle %d %%)" % roundi(bld.get_progress_ratio() * 100.0)
		elif bld.hp < bld.max_hp or bld.kingdom != game.player:
			text += "  ·  Leben %d/%d" % [ceili(bld.hp), roundi(bld.max_hp)]
		lines.append(text)
	else:
		# Höchstens eine Zeile mehr als ein Gebäude – der Bereich behält seine Höhe
		var unit_text := _unit_text()
		if not unit_text.is_empty():
			lines.append(unit_text)
	lines.append(_territory_text(cell))
	_set_info("\n".join(lines))


## Einheit unter der Maus: "Wolf (Wilde Monster)  ·  Leben 40/60"
func _unit_text() -> String:
	if game == null or get_viewport().gui_get_hovered_control() != null:
		return ""
	var radius := HOVER_PICK_RADIUS / maxf(camera.zoom.x, 0.25)
	var u: Unit = game.unit_system.get_unit_at(world_map.get_global_mouse_position(), radius)
	if u == null or not game.can_see(game.player, u):
		return ""
	var text := u.get_display_name()
	if u.kingdom != game.player:
		text += " (%s)" % u.kingdom.display_name
	return text + "  ·  Leben %d/%d" % [ceili(u.hp), roundi(u.max_hp)]


## "Baumgruppe: 180 Holz", "Manaquelle (unerschöpflich)", "Beeren & Wild: wächst nach"
func _deposit_text(cell: Vector2i) -> String:
	var dep := world.get_deposit(cell)
	if dep.is_empty():
		return ""
	var dep_name := str(dep.get("name", "?"))
	var amount := world.get_deposit_amount(cell)
	if amount < 0:
		return "%s (unerschöpflich)" % dep_name
	if world.regrowing.has(cell):
		return "%s: wächst nach" % dep_name
	var res_name := str(DataDB.get_resource(str(dep.get("resource", ""))).get("name", ""))
	return "%s: %d %s" % [dep_name, amount, res_name]


## "Eigenes Gebiet", "Niemandsland" oder "Gebiet: Zwergendorf Eisenhall (Freundlich)"
func _territory_text(cell: Vector2i) -> String:
	var owner_id := world.get_owner(cell)
	if owner_id == 0:
		return "Niemandsland"
	var player: Kingdom = game.player if game != null else null
	if player != null and owner_id == player.id:
		return "Eigenes Gebiet"
	var owner_k: Kingdom = game.get_kingdom(owner_id) if game != null else null
	if owner_k == null:
		return "Fremdes Gebiet"
	var text := "Gebiet: %s" % owner_k.display_name
	if player != null and game.village_system.is_village(owner_k):
		if game.are_hostile(player, owner_k):
			text += " (Krieg)"
		else:
			text += " (%s)" % DiplomacySystem.tier_name(game.diplomacy_system.get_tier(owner_k, player))
	return text


func _set_info(text: String) -> void:
	if info_label.text != text:
		info_label.text = text
