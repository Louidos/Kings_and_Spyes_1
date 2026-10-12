## HUD
##
## Spieloberfläche: Leiste oben (Reich, Ressourcen ab Phase 2, Datum, Tempo),
## Infobereich unten links (Kachel unter der Maus), Minikarte unten rechts.
## Das HUD zeigt nur an und leitet Klicks weiter – Spiellogik liegt in den Systemen.
extends CanvasLayer

@onready var kingdom_label: Label = %KingdomLabel
@onready var resource_bar: HBoxContainer = %ResourceBar
@onready var date_label: Label = %DateLabel
@onready var speed_bar: HBoxContainer = %SpeedBar
@onready var info_label: Label = %InfoLabel
@onready var minimap: Minimap = %Minimap
@onready var paused_label: Label = %PausedLabel
@onready var hint_label: Label = %HintLabel
@onready var debug_label: Label = %DebugLabel

var world: WorldData
var world_map: WorldMap
var camera: RTSCamera

var _pause_button: Button
## Ein Button je Tempostufe (gleiche Reihenfolge wie GameClock.speed_steps)
var _speed_buttons: Array[Button] = []
var _blink_time := 0.0


func _ready() -> void:
	_build_speed_buttons()
	GameClock.speed_changed.connect(_on_speed_changed)
	_on_speed_changed(GameClock.paused, GameClock.get_speed())
	var faction := GameSession.get_faction()
	kingdom_label.text = "Dein Königreich  ·  %s" % faction.get("name", "?")
	kingdom_label.add_theme_color_override("font_color", faction.get("color", Color.WHITE))
	info_label.text = "Bewege die Maus über die Karte."
	debug_label.visible = false
	# Steuerungshinweis nach einer Weile ausblenden
	var tween := create_tween()
	tween.tween_interval(25.0)
	tween.tween_property(hint_label, "modulate:a", 0.0, 2.0)


## Wird von der Spielszene aufgerufen, sobald die Welt erzeugt ist.
func setup(game: Node) -> void:
	world = game.world
	camera = game.camera
	world_map = game.world_map
	minimap.setup(world_map.overview_texture, world.get_pixel_size(), camera)
	world_map.hovered_cell_changed.connect(_on_hovered_cell_changed)


func toggle_job_panel() -> void:
	pass


func is_debug_visible() -> bool:
	return debug_label.visible


func _process(delta: float) -> void:
	date_label.text = GameClock.get_time_string()
	if paused_label.visible:
		_blink_time += delta
		paused_label.modulate.a = 0.6 + 0.4 * cos(_blink_time * 3.0)
	if debug_label.visible and world_map != null:
		debug_label.text = "FPS %d  ·  Zoom %.2f  ·  Chunks %d  ·  Seed %s" % [
			Engine.get_frames_per_second(), camera.zoom.x,
			world_map.get_loaded_chunk_count(), GameSession.seed_text]


func toggle_debug() -> void:
	debug_label.visible = not debug_label.visible


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
# Infobereich
# ---------------------------------------------------------------------------

func _on_hovered_cell_changed(cell: Vector2i) -> void:
	if cell.x < 0:
		info_label.text = "Bewege die Maus über die Karte."
		return
	var b := world.get_biome(cell)
	var defense := float(b.get("defense_bonus", 0.0))
	info_label.text = "%s\nKachel %d, %d\nBewegung: %.1f×   Verteidigung: %+d %%\nBebaubar: %s   Höhe: %d %%" % [
		b.get("name", "?"), cell.x, cell.y,
		float(b.get("movement_cost", 1.0)), roundi(defense * 100.0),
		"ja" if b.get("buildable", false) else "nein",
		roundi(world.get_elevation(cell) * 100.0)]
