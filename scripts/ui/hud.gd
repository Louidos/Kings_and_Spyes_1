## HUD
##
## Spieloberfläche:
## - oben: Reich, Ressourcen und Bewohner (ResourceBar), Datum, Tempo
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


## Arbeitsverteilung ein-/ausblenden (Taste J)
func toggle_job_panel() -> void:
	job_panel.toggle()


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
		debug_label.text = "FPS %d  ·  Zoom %.2f  ·  Chunks %d  ·  Seed %s  ·  F9: +100 Ressourcen" % [
			Engine.get_frames_per_second(), camera.zoom.x,
			world_map.get_loaded_chunk_count(), GameSession.seed_text]
	if world != null:
		_info_timer += delta
		if _info_timer >= INFO_REFRESH_INTERVAL:
			_info_timer = 0.0
			_update_info()


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
	b.custom_minimum_size = Vector2(54, 0)
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
