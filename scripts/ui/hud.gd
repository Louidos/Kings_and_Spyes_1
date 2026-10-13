## HUD
##
## Spieloberfläche:
## - oben: Reich, Ressourcen, Kampfpunkte und Bewohner (ResourceBar), Button
##   "Forschung (R)" mit Fortschritt, Datum, Tempo
## - Forschungsfenster (ResearchPanel, Taste R) in einer eigenen Ebene darüber
## - oben links: Arbeitsverteilung (JobPanel, Taste J)
## - oben rechts: Meldungen (NotificationPanel)
## - unten links: Auswahlfenster (SelectionPanel), darunter die Armeeleiste
##   (ArmyBar) und der Infobereich (Kachel, Gebäude oder Einheit unter der Maus)
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
	kingdom_label.text = "Dein Königreich  ·  %s" % faction.get("name", "?")
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
	_setup_research()


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


## Esc schliesst das Forschungsfenster auch, wenn gerade ein Tooltip offen ist
## (Godot verbraucht Esc sonst nur zum Schliessen des Tooltips).
func _input(event: InputEvent) -> void:
	if is_research_open() and event.is_action_pressed("game_menu") and not event.is_echo():
		research_panel.close()
		get_viewport().set_input_as_handled()


## Arbeitsverteilung ein-/ausblenden (Taste J)
func toggle_job_panel() -> void:
	job_panel.toggle()


## Esc: schliesst das oberste offene Fenster (Forschung, Arbeitsverteilung).
## true = etwas wurde geschlossen (dann nichts weiter tun).
func close_top_panel() -> bool:
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
		debug_label.text = "FPS %d  ·  Zoom %.2f  ·  Chunks %d  ·  Seed %s  ·  F9: +100 Ressourcen  ·  F10: König −150  ·  F11: 3 Wölfe an der Maus" % [
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
	_research_button.text = "Forschung (R)"
	_research_button.toggle_mode = true
	_research_button.add_theme_font_size_override("font_size", 16)
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


func _on_research_state_changed(k: Kingdom) -> void:
	if k == game.player:
		_refresh_research_button()


## Button oben: "Forschung (R) · 45 %" (mit Strich), gelb "Forschung ruht (R)"
## bzw. "Forschung angehalten (R)" (keine fertige Forschungsstätte),
## Punkt, wenn eine Kampfpunkt-Verbesserung bezahlbar ist
func _refresh_research_button() -> void:
	var k: Kingdom = game.player
	var rs: ResearchSystem = game.research_system
	var active := rs.get_active(k)
	var text := "Forschung (R)"
	var idle := false
	if not active.is_empty():
		_research_button.underline_ratio = rs.get_progress_ratio(k)
		if rs.get_speed(k) <= 0.0:
			# Keine fertige Forschungsstätte mehr: Forschung steht still
			text = "Forschung angehalten (R) · %d %%" % floori(rs.get_progress_ratio(k) * 100.0)
			idle = true
		else:
			text = "Forschung (R) · %d %%" % floori(rs.get_progress_ratio(k) * 100.0)
	else:
		_research_button.underline_ratio = -1.0
		idle = rs.count_research_buildings(k) > 0
		if idle:
			text = "Forschung ruht (R)"
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
	b.custom_minimum_size = Vector2(48, 0)
	speed_bar.add_child(b)
	return b


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


func _territory_text(cell: Vector2i) -> String:
	var owner_id := world.get_owner(cell)
	if owner_id == 0:
		return "Niemandsland"
	var player: Kingdom = game.player if game != null else null
	if player != null and owner_id == player.id:
		return "Eigenes Gebiet"
	return "Fremdes Gebiet"


func _set_info(text: String) -> void:
	if info_label.text != text:
		info_label.text = text
