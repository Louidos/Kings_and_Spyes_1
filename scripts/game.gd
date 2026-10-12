## Game
##
## Spielszene: erzeugt die Welt im Hintergrund und verbindet anschliessend
## Karte, Kamera, Systeme, HUD und Menüs. Globale Tastenkürzel (Pause, Tempo,
## Menü) werden hier verarbeitet.
## Andere Systeme erreichen sich gegenseitig über diese Node (game.xyz).
extends Node2D

@onready var world_map: WorldMap = $WorldMap
@onready var entities: Node2D = $Entities
@onready var placement: PlacementController = $Placement
@onready var camera: RTSCamera = $Camera
@onready var building_system: BuildingSystem = $Systems/BuildingSystem
@onready var unit_system: UnitSystem = $Systems/UnitSystem
@onready var work_system: WorkSystem = $Systems/WorkSystem
@onready var economy_system: EconomySystem = $Systems/EconomySystem
@onready var selection: SelectionController = $Selection
@onready var hud: CanvasLayer = $HUD
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var loading: CanvasLayer = $LoadingScreen

var world: WorldData
## Reich des Spielers
var player: Kingdom
## Alle Reiche (ab Phase 7 auch die Gegner)
var kingdoms: Array = []
## Kingdom.id -> Kingdom
var kingdom_by_id: Dictionary = {}
var territory := TerritorySystem.new()
var nav: NavGrid
## Zähler für eindeutige Nummern von Gebäuden und Einheiten (wird gespeichert)
var uid_counter := 0
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
## Gibt [WorldData, NavGrid] zurück.
func _generate_world(world_seed: int, size: int) -> Array:
	var generator := WorldGenerator.new()
	generator.progress_callback = func(p: float, text: String) -> void:
		loading.set_progress.call_deferred(p, text)
	var w := generator.generate(world_seed, size)
	loading.set_progress.call_deferred(1.0, "Berechne Wege …")
	var grid := NavGrid.new()
	grid.build(w)
	return [w, grid]


func _process(_delta: float) -> void:
	if _gen_thread != null and not _gen_thread.is_alive():
		var result: Array = _gen_thread.wait_to_finish()
		_gen_thread = null
		world = result[0]
		nav = result[1]
		_start_game()


func _start_game() -> void:
	world_map.setup(world)
	# Simulation -> Wegfindung und Darstellung (die Simulation kennt die Darstellung nicht)
	world.cell_changed.connect(func(c: Vector2i) -> void: nav.update_cell(world, c))
	world.road_changed.connect(func(c: Vector2i) -> void: nav.update_cell(world, c))
	territory.changed.connect(_on_territory_changed)

	building_system.setup(self)
	unit_system.setup(self)
	work_system.setup(self)
	economy_system.setup(self)
	placement.setup(self)
	selection.setup(self)

	player = create_kingdom({"faction_id": GameSession.faction_id, "controller": "player"})
	found_settlement(player, world.start_cell)

	camera.set_map_rect(world.get_pixel_rect())
	camera.focus_on(player.castle.get_center(), float(DataDB.cfg("camera.zoom_start", 0.8)))
	hud.setup(self)
	hud.visible = true
	loading.close()
	camera.input_enabled = true
	_playing = true
	GameClock.start_new_game()
	Notify.info("Willkommen, König! Baue dein Dorf aus: Baumenü unten, Arbeitsverteilung links (J).",
			player.castle.get_center())


## Nächste eindeutige Nummer für ein Gebäude oder eine Einheit
func next_uid() -> int:
	uid_counter += 1
	return uid_counter


## Legt ein Reich an. setup: faction_id, controller ("player"/"ai"/"neutral"/"wild"),
## optional id, color, display_name.
func create_kingdom(setup: Dictionary) -> Kingdom:
	var k := Kingdom.new()
	var id := int(setup.get("id", kingdoms.size() + 1))
	k.setup(id, str(setup.get("faction_id", "good")), str(setup.get("controller", "ai")))
	if setup.has("color"):
		k.color = setup["color"]
	if setup.has("display_name"):
		k.display_name = setup["display_name"]
	kingdoms.append(k)
	kingdom_by_id[id] = k
	return k


func get_kingdom(id: int) -> Kingdom:
	return kingdom_by_id.get(id, null)


## Gründet eine Siedlung: Startressourcen, Burg, Startbewohner und ihre Berufe.
## Wird für den Spieler genutzt und ab Phase 7 genauso für die KI-Reiche.
func found_settlement(kingdom: Kingdom, center_cell: Vector2i) -> void:
	var start_res: Dictionary = DataDB.eco("start.resources", {})
	for res_id in start_res:
		kingdom.resources[res_id] = float(start_res[res_id])
	building_system.place_start_castle(kingdom, center_cell)
	var count := int(DataDB.eco("start.villagers", 5))
	var center := kingdom.castle.get_center()
	for i in count:
		var dir := Vector2.from_angle(TAU * i / maxf(count, 1.0) + 0.4)
		var pos := kingdom.castle.get_approach_point(center + dir * 1000.0)
		var u := unit_system.spawn_unit(kingdom, "villager", pos)
		work_system.set_unit_job(u, "idle")
	var jobs: Dictionary = DataDB.eco("start.jobs", {})
	for job_id in jobs:
		for _i in int(jobs[job_id]):
			work_system.assign_job(kingdom, job_id)


func _on_territory_changed(kingdom_id: int, bbox: Rect2i) -> void:
	var k := get_kingdom(kingdom_id)
	if k != null:
		world_map.territory_border.rebuild(world, kingdom_id, bbox, k.color)


func _unhandled_input(event: InputEvent) -> void:
	if not _playing or pause_menu.is_open:
		return
	if event.is_action_pressed("game_menu"):
		# Esc: erst Bauen abbrechen, dann Auswahl aufheben, dann Menü
		if placement.is_active():
			placement.cancel()
		elif not selection.selected.is_empty():
			selection.clear()
		else:
			_open_pause_menu()
	elif event.is_action_pressed("toggle_jobs"):
		hud.toggle_job_panel()
	elif event.is_action_pressed("demolish_mode"):
		placement.start_demolish()
	elif event.is_action_pressed("debug_resources") and hud.is_debug_visible():
		for r in DataDB.resources:
			player.add_resource(r["id"], 100.0)
		Notify.info("Debug: +100 von jeder Ressource")
	elif event.is_action_pressed("game_pause"):
		GameClock.toggle_pause()
	elif event.is_action_pressed("game_speed_up"):
		GameClock.faster()
	elif event.is_action_pressed("game_speed_down"):
		GameClock.slower()
	elif event.is_action_pressed("camera_home"):
		camera.focus_on(player.castle.get_center() if is_instance_valid(player.castle) else world.cell_to_world(world.start_cell))
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
