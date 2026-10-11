## Game
##
## Spielszene: erzeugt die Welt im Hintergrund und verbindet anschliessend
## Karte, Kamera, HUD und Menüs. Globale Tastenkürzel (Pause, Tempo, Menü)
## werden hier verarbeitet.
extends Node2D

@onready var world_map: WorldMap = $WorldMap
@onready var camera: RTSCamera = $Camera
@onready var hud: CanvasLayer = $HUD
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var loading: CanvasLayer = $LoadingScreen

var world: WorldData
var _gen_thread: Thread
var _playing := false
var _was_paused_before_menu := false


func _ready() -> void:
	GameClock.stop()
	camera.input_enabled = false
	hud.visible = false
	pause_menu.closed.connect(_on_pause_menu_closed)
	loading.open(GameSession.seed_text)

	# Weltgenerierung im Hintergrund-Thread, damit das Fenster nicht einfriert
	_gen_thread = Thread.new()
	_gen_thread.start(_generate_world.bind(GameSession.world_seed, GameSession.get_map_tiles()))


## Läuft im Thread: nur Daten erzeugen, keine Nodes anfassen.
func _generate_world(world_seed: int, size: int) -> WorldData:
	var generator := WorldGenerator.new()
	generator.progress_callback = func(p: float, text: String) -> void:
		loading.set_progress.call_deferred(p, text)
	return generator.generate(world_seed, size)


func _process(_delta: float) -> void:
	if _gen_thread != null and not _gen_thread.is_alive():
		world = _gen_thread.wait_to_finish()
		_gen_thread = null
		_start_game()


func _start_game() -> void:
	world_map.setup(world)
	camera.set_map_rect(world.get_pixel_rect())
	camera.focus_on(world.cell_to_world(world.start_cell), float(DataDB.cfg("camera.zoom_start", 0.8)))
	hud.setup(world, camera, world_map)
	hud.visible = true
	loading.close()
	camera.input_enabled = true
	_playing = true
	GameClock.start_new_game()


func _unhandled_input(event: InputEvent) -> void:
	if not _playing or pause_menu.is_open:
		return
	if event.is_action_pressed("game_menu"):
		_open_pause_menu()
	elif event.is_action_pressed("game_pause"):
		GameClock.toggle_pause()
	elif event.is_action_pressed("game_speed_up"):
		GameClock.faster()
	elif event.is_action_pressed("game_speed_down"):
		GameClock.slower()
	elif event.is_action_pressed("camera_home"):
		camera.focus_on(world.cell_to_world(world.start_cell))
	elif event.is_action_pressed("toggle_debug"):
		hud.toggle_debug()
	else:
		return
	get_viewport().set_input_as_handled()


func _open_pause_menu() -> void:
	_was_paused_before_menu = GameClock.paused
	GameClock.set_paused(true)
	camera.input_enabled = false
	pause_menu.open()


func _on_pause_menu_closed() -> void:
	camera.input_enabled = true
	GameClock.set_paused(_was_paused_before_menu)


func _exit_tree() -> void:
	# Verlässt man die Szene während der Generierung, Thread sauber beenden
	if _gen_thread != null and _gen_thread.is_started():
		_gen_thread.wait_to_finish()
	GameClock.stop()
