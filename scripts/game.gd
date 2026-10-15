## Game
##
## Spielszene: erzeugt die Welt im Hintergrund und verbindet anschliessend
## Karte, Kamera, Systeme, HUD und Menüs. Globale Tastenkürzel (Pause, Tempo,
## Menü, Hilfe, Protokoll, Schnellspeichern) werden hier verarbeitet.
## Spielstand laden (Phase 10): steht in GameSession.pending_load_path ein Pfad, liest
## der Hintergrund-Thread die Datei, erzeugt die Welt aus dem Seed neu und wendet die
## gespeicherten Änderungen an; danach stellt SaveGame.restore Reiche, Gebäude,
## Einheiten und Systeme wieder her.
## Andere Systeme erreichen sich gegenseitig über diese Node (game.xyz).
extends Node2D

## Beziehung zweier Reiche geändert ("war", "peace", "alliance")
signal relation_changed(a: Kingdom, b: Kingdom, state: String)
## Ein Reich hat verloren (reason z. B. "king", "castle"; Dörfer "annexed", "conquered")
signal kingdom_defeated(kingdom: Kingdom, reason: String)
## Die Formation des Spielers wurde gewechselt
signal formation_changed(formation: String)

@onready var world_map: WorldMap = $WorldMap
@onready var entities: Node2D = $Entities
## Einheiten (eigene y-sortierte Ebene in Entities, damit sie beim Herauszoomen
## gemeinsam ausgeblendet werden können)
@onready var unit_layer: Node2D = $Entities/Units
@onready var unit_overlay: UnitOverlay = $UnitOverlay
@onready var combat_effects: CombatEffects = $CombatEffects
@onready var magic_effects: MagicEffects = $MagicEffects
## Zielmodus für Zauber (letzter Knoten: bekommt Mausklicks vor der Auswahl)
@onready var spell_targeting: SpellTargeting = $SpellTargeting
@onready var placement: PlacementController = $Placement
@onready var camera: RTSCamera = $Camera
@onready var building_system: BuildingSystem = $Systems/BuildingSystem
@onready var unit_system: UnitSystem = $Systems/UnitSystem
@onready var work_system: WorkSystem = $Systems/WorkSystem
@onready var economy_system: EconomySystem = $Systems/EconomySystem
@onready var combat_system: CombatSystem = $Systems/CombatSystem
@onready var command_system: CommandSystem = $Systems/CommandSystem
@onready var summon_system: SummonSystem = $Systems/SummonSystem
@onready var monster_system: MonsterSystem = $Systems/MonsterSystem
@onready var research_system: ResearchSystem = $Systems/ResearchSystem
@onready var magic_system: MagicSystem = $Systems/MagicSystem
@onready var hero_system: HeroSystem = $Systems/HeroSystem
## Neutrale Dörfer, Diplomatie und Boten (Phase 6)
@onready var village_system: VillageSystem = $Systems/VillageSystem
@onready var diplomacy_system: DiplomacySystem = $Systems/DiplomacySystem
@onready var messenger_system: MessengerSystem = $Systems/MessengerSystem
## Entdeckung, Kundschaft, Spione, gegnerische Königreiche (KI) sowie Niederlage und Sieg (Phase 7)
@onready var espionage_system: EspionageSystem = $Systems/EspionageSystem
@onready var spy_system: SpySystem = $Systems/SpySystem
@onready var ai_system: AISystem = $Systems/AISystem
@onready var victory_system: VictorySystem = $Systems/VictorySystem
## Völker, Tag/Nacht, Zufriedenheit, Ereignisse (Phase 8)
@onready var people_system: PeopleSystem = $Systems/PeopleSystem
@onready var day_night_system: DayNightSystem = $Systems/DayNightSystem
@onready var satisfaction_system: SatisfactionSystem = $Systems/SatisfactionSystem
@onready var event_system: EventSystem = $Systems/EventSystem
@onready var day_night_view: DayNightView = $DayNight
@onready var event_effects: EventEffects = $EventEffects
## Belagerung, Handelswege, Versorgung (Phase 9)
@onready var siege_system: SiegeSystem = $Systems/SiegeSystem
@onready var trade_route_system: TradeRouteSystem = $Systems/TradeRouteSystem
@onready var supply_system: SupplySystem = $Systems/SupplySystem
## Truppen: Erfahrung, Wertepunkte, Schmiede, Aussehen (troops.json)
@onready var troop_system: TroopSystem = $Systems/TroopSystem
@onready var trade_route_view: TradeRouteView = $TradeRoutes
## Tutorial (Schritte, Schutz vor Gegnern und Ereignissen, Oberfläche)
@onready var tutorial_system: TutorialSystem = $Systems/TutorialSystem
@onready var selection: SelectionController = $Selection
@onready var hud: CanvasLayer = $HUD
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var loading: CanvasLayer = $LoadingScreen

var world: WorldData
## Reich des Spielers
var player: Kingdom
## Reich der wilden Monster (feindlich zu allen)
var wild: Kingdom
## Alle Reiche (ab Phase 7 auch die Gegner)
var kingdoms: Array = []
## Kingdom.id -> Kingdom
var kingdom_by_id: Dictionary = {}
var territory := TerritorySystem.new()
var nav: NavGrid
## Zähler für eindeutige Nummern von Gebäuden und Einheiten (wird gespeichert)
var uid_counter := 0
## uid -> Unit oder Building (für Verweise in Spielständen und Armeen)
var entity_by_uid: Dictionary = {}
var _gen_thread: Thread
## Im Hauptthread angelegt, damit das Laden abgebrochen werden kann
var _generator: WorldGenerator
var _nav_builder: NavGrid
var _playing := false
var _was_paused_before_menu := false
var _game_over: GameOverScreen

# --- Speichern und Laden (Phase 10) ---
## Wird gerade ein Spielstand wiederhergestellt? (Systeme können Seiteneffekte auslassen)
var loading_save := false
## Rauchtest: Zustand direkt nach dem Laden (SaveGame.collect) und die geladenen Daten
var last_load_check: Dictionary = {}
var last_loaded_data: Dictionary = {}
var last_load_metrics: Dictionary = {}
## Ladebericht des letzten Ladens (SaveGame.restore)
var last_load_report: Dictionary = {}
## Neu laden (F8, Laden aus dem Menü): der Rauchtest lenkt das auf sich um
var reload_handler: Callable = Callable()
## Diesen Spielstand lädt die Szene (leer = neue Partie)
var _load_path := ""
var _load_name := ""
## Kamera aus dem Spielstand ({"pos", "zoom"})
var _loaded_camera: Dictionary = {}
## Echte Sekunden seit dem letzten automatischen Speichern bzw. Start/Laden
var _autosave_acc := 0.0
## Spielzeit beim letzten Speichern (für "ungespeicherter Fortschritt")
var _last_save_game_time := 0.0


func _ready() -> void:
	GameClock.stop()
	camera.input_enabled = false
	hud.visible = false
	pause_menu.closed.connect(_on_pause_menu_closed)
	# Vorgemerkten Spielstand übernehmen und sofort leeren ("Neu starten" lädt sonst wieder)
	_load_path = GameSession.pending_load_path
	_load_name = GameSession.pending_load_name
	GameSession.pending_load_path = ""
	GameSession.pending_load_name = ""
	if _load_path.is_empty():
		Notify.clear_history()
		loading.open(GameSession.seed_text)
	else:
		loading.open(GameSession.seed_text, "Lade Spielstand „%s“ …" % _load_name)

	# Weltgenerierung im Hintergrund-Thread, damit das Fenster nicht einfriert
	_generator = WorldGenerator.new()
	_generator.progress_callback = func(p: float, text: String) -> void:
		loading.set_progress.call_deferred(p, text)
	_nav_builder = NavGrid.new()
	_gen_thread = Thread.new()
	_gen_thread.start(_generate_world.bind(GameSession.world_seed, GameSession.get_map_tiles(), _load_path))


## Läuft im Thread: nur Daten erzeugen, keine Nodes anfassen.
## Gibt [WorldData, NavGrid, {"data": Spielstand-Daten} oder {"error": Text}] zurück.
func _generate_world(world_seed: int, size: int, load_path: String) -> Array:
	var data := {}
	if not load_path.is_empty():
		loading.set_progress.call_deferred(0.02, "Lese Spielstand …")
		var res := SaveManager.read_data(load_path)
		if not str(res.get("error", "")).is_empty():
			return [null, null, {"error": str(res["error"])}]
		data = res["data"]
	var w := _generator.generate(world_seed, size)
	if _generator.cancelled:
		return [w, _nav_builder, {}]
	w.gen_fingerprint = w.compute_fingerprint()
	if not data.is_empty():
		var wd: Dictionary = data.get("world", {})
		var saved: Dictionary = wd.get("fingerprint", {})
		var diff := PackedStringArray()
		SaveCodec.deep_diff(saved, w.gen_fingerprint, "fingerprint", diff)
		if not diff.is_empty():
			return [null, null, {"error": "Die Welt dieses Spielstands passt nicht zu den aktuellen Spieldaten (Generator/Daten geändert)."}]
		loading.set_progress.call_deferred(0.97, "Wende Änderungen an …")
		w.apply_diff(wd)
	loading.set_progress.call_deferred(1.0, "Berechne Wege …")
	_nav_builder.build(w)
	return [w, _nav_builder, {"data": data}]


func _process(delta: float) -> void:
	if _gen_thread != null and not _gen_thread.is_alive():
		var result: Array = _gen_thread.wait_to_finish()
		_gen_thread = null
		var extra: Dictionary = result[2] if result.size() > 2 else {}
		if extra.has("error"):
			_abort_load(str(extra["error"]))
			return
		world = result[0]
		nav = result[1]
		_start_game(extra.get("data", {}))
		return
	if _playing and GameClock.running and not GameClock.paused and _game_over == null:
		GameSession.play_seconds += delta
		_autosave_acc += delta
		var minutes := Settings.autosave_minutes
		if minutes > 0 and _autosave_acc >= maxf(minutes * 60.0, float(DataDB.cfg("save.autosave_min_gap_seconds", 60))) \
				and can_save().is_empty():
			_autosave_acc = 0.0
			save_game(SaveManager.next_autosave_slot(), "Autospeicherung", "auto")


## Laden gescheitert: zurück ins Hauptmenü (Hinweis dort)
func _abort_load(msg: String) -> void:
	push_warning("Laden gescheitert: " + msg)
	GameSession.last_error = "Laden gescheitert: " + msg
	GameClock.stop()
	if reload_handler.is_valid():
		return
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")


func _start_game(save_data: Dictionary = {}) -> void:
	_setup_world_and_systems()
	# Ab jetzt merkt sich die Welt jede Änderung (auch beim Gründen der Siedlungen)
	world.track_changes = true
	if save_data.is_empty():
		_found_new_world()
		_finish_start(true)
		return
	loading.set_progress(1.0, "Stelle Spielstand wieder her …")
	await get_tree().process_frame
	if not is_inside_tree():
		return
	last_loaded_data = save_data if GameSession.debug_verify_load else {}
	last_load_report = SaveGame.restore(self, save_data)
	_finish_start(false)


## Karte, Systeme und Darstellung einrichten (neue und geladene Partie gleich)
func _setup_world_and_systems() -> void:
	world_map.setup(world)
	# Simulation -> Wegfindung und Darstellung (die Simulation kennt die Darstellung nicht)
	world.cell_changed.connect(func(c: Vector2i) -> void: nav.update_cell(world, c))
	world.road_changed.connect(func(c: Vector2i) -> void: nav.update_cell(world, c))
	territory.changed.connect(_on_territory_changed)

	building_system.setup(self)
	unit_system.setup(self)
	work_system.setup(self)
	economy_system.setup(self)
	combat_system.setup(self)
	command_system.setup(self)
	summon_system.setup(self)
	research_system.setup(self)
	magic_system.setup(self)
	# Nach Kampf und Magie: der Heldentakt läuft nach dem Neuaufbau der Umgebungssuche
	hero_system.setup(self)
	# Nach dem Kampf: Dörfer lesen die Umgebungssuche und hören auf Kampfsignale
	village_system.setup(self)
	diplomacy_system.setup(self)
	messenger_system.setup(self)
	# Entdeckung und Kundschaft (hört auf Kampf, Diplomatie, Dörfer, Wirtschaft), danach
	# die Spione (Beschwörung, Befehle, Kampf, Entdeckung)
	espionage_system.setup(self)
	spy_system.setup(self)
	# Nach allen Systemen, die die KI-Gehirne aufrufen; das VictorySystem danach
	# (hört auf kingdom_defeated und building_destroyed)
	ai_system.setup(self)
	victory_system.setup(self)
	# Phase 8: Völker (Geländeboni), Tageszeit, Zufriedenheit (braucht Kampf, Arbeit,
	# Wirtschaft, Befehle, Dörfer, Spionage), Ereignisse (Magie, Kampf, Befehle, Zufriedenheit)
	people_system.setup(self)
	day_night_system.setup(self)
	satisfaction_system.setup(self)
	event_system.setup(self)
	# Phase 9: Belagerung nach Kampf, Bau, Arbeit und Befehl (setzt nav.gate_rule); Handelswege
	# nach Diplomatie und Dörfern; Versorgung danach und vor den ersten Siedlungen (Gebiet)
	siege_system.setup(self)
	trade_route_system.setup(self)
	supply_system.setup(self)
	# Truppen nach Kampf, Einheiten und Helden (hört auf Treffer, Tod, Stufenaufstieg)
	troop_system.setup(self)
	# Tutorial nach allen Systemen und vor der Auswahl (hört auf deren Befehle)
	tutorial_system.setup(self)
	placement.setup(self)
	selection.setup(self)
	unit_overlay.setup(self)
	combat_effects.setup(self)
	magic_effects.setup(self)
	spell_targeting.setup(self)
	event_effects.setup(self)
	day_night_view.setup(self)
	trade_route_view.setup(self)
	kingdom_defeated.connect(_on_kingdom_defeated)
	victory_system.victory_reached.connect(_on_victory_reached)
	camera.set_map_rect(world.get_pixel_rect())


## Neue Partie: Spieler, Monster, Dörfer, KI-Reiche und Monsterlager gründen
func _found_new_world() -> void:
	player = create_kingdom({"faction_id": GameSession.faction_id, "controller": "player"})
	# Volk vor der Burg (Volksgrafik der Burg)
	player.people_id = GameSession.people_id
	# Getarnte Einheiten aus Sicht des Spielers zeichnen
	Unit.viewer_kingdom_id = player.id
	found_settlement(player, world.start_cell)
	Difficulty.apply_player_start(player)
	# Wilde Monster: ein eigenes Reich, mit allen im Krieg
	wild = create_kingdom({"faction_id": "wild", "controller": "wild", "display_name": "Wilde Monster"})
	# Schwierigkeit vor den Höhlen (Building.max_hp wird beim Aufbau festgelegt)
	Difficulty.apply_wild(wild)
	monster_system.setup(self, wild)
	# Neutrale Dörfer vor den Monsterlagern (das Monster-Reich behält id 2)
	village_system.found_villages()
	# Gegnerische Königreiche (ids nach den Dörfern)
	ai_system.found_ai_kingdoms()
	# Reich "Wanderer" für Flüchtlinge (nach allen anderen Reichen)
	event_system.create_wanderer_kingdom()
	monster_system.spawn_camps()
	# Volksboni ("people:<id>", Geländeboni) und Tageszeit ("daynight") für die Startzeit
	people_system.apply_all()
	day_night_system.apply_all()


## Start abschliessen: Kamera, HUD, Uhr, Begrüssung bzw. Ladehinweis
func _finish_start(is_new: bool) -> void:
	if not is_new and _loaded_camera.has("pos"):
		camera.focus_on(_loaded_camera["pos"], float(_loaded_camera.get("zoom", 0.8)))
	elif is_instance_valid(player.castle):
		camera.focus_on(player.castle.get_center(), float(DataDB.cfg("camera.zoom_start", 0.8)))
	hud.setup(self)
	tutorial_system.setup_ui()
	hud.visible = true
	loading.close()
	camera.input_enabled = true
	_playing = true
	_autosave_acc = 0.0
	_last_save_game_time = GameClock.game_time if not is_new else 0.0
	if not is_new:
		GameClock.start_loaded_game()
		var skipped := int(last_load_report.get("skipped_buildings", 0)) + int(last_load_report.get("skipped_units", 0))
		Notify.good("Spielstand „%s“ geladen (%s)" % [_load_name, GameClock.get_time_string()])
		if skipped > 0:
			Notify.warning("%d Einträge des Spielstands sind unbekannt und wurden ausgelassen" % skipped)
		var header: Dictionary = SaveManager.read_header(_load_path).get("header", {})
		if SaveMigration.data_changed(header):
			Notify.warning("Spieldaten geändert – Werte können vom Spielstand abweichen")
		return
	GameClock.start_new_game()
	if GameSession.start_tutorial:
		# Das Tutorial begrüsst selbst; Gegner und Ereignisse verschonen den Spieler, solange es läuft
		tutorial_system.start(true)
		return
	Notify.info("Willkommen, König! Baue dein Dorf aus: Baumenü unten, Arbeitsverteilung links (J).",
			player.castle.get_center())
	Notify.info("Burg anklicken: Späher beschwören. Monsterlager (orange auf der Minikarte) bringen Beute.",
			player.castle.get_center())
	if not player.people_id.is_empty():
		Notify.info("Dein Volk: %s – Stärken und Tageszeit-Boni in der Reichsübersicht (L)." % DataDB.get_people_name(player.people_id),
				player.castle.get_center())
	var nearest := _nearest_village()
	if nearest != null:
		Notify.info("Neutrale Dörfer in der Nähe – Diplomatie mit N: Geschenke, Handel, Verträge.",
				village_system.get_center(nearest))


## Nächstes selbstständiges Dorf zur Burg des Spielers (null, wenn keins)
func _nearest_village() -> Kingdom:
	var best: Kingdom = null
	var best_d := INF
	var from := player.castle.get_center() if is_instance_valid(player.castle) else world.cell_to_world(world.start_cell)
	for v in village_system.get_villages():
		var d := from.distance_to(village_system.get_center(v))
		if d < best_d:
			best_d = d
			best = v
	return best


## Nächste eindeutige Nummer für ein Gebäude oder eine Einheit
func next_uid() -> int:
	uid_counter += 1
	return uid_counter


func register_entity(e: Object) -> void:
	entity_by_uid[e.uid] = e


func unregister_entity(e: Object) -> void:
	entity_by_uid.erase(e.uid)


## Einheit oder Gebäude mit dieser Nummer (null, wenn es sie nicht mehr gibt)
func find_by_uid(uid: int) -> Variant:
	var e: Variant = entity_by_uid.get(uid, null)
	return e if is_instance_valid(e) else null


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
	# Spielstand: Beziehungen kommen aus Kingdom.from_dict (keine Signale)
	if bool(setup.get("restore", false)):
		return k
	# Monster sind mit allen verfeindet
	for other in kingdoms:
		if other != k and (other.controller == "wild" or k.controller == "wild"):
			set_relation(k, other, "war")
	return k


func get_kingdom(id: int) -> Kingdom:
	return kingdom_by_id.get(id, null)


## Setzt die Beziehung zweier Reiche (gilt in beide Richtungen):
## "war" (Krieg), "peace" (Frieden) oder "alliance" (Bündnis).
func set_relation(a: Kingdom, b: Kingdom, state: String) -> void:
	if a == null or b == null or a == b:
		return
	a.relations[b.id] = state
	b.relations[a.id] = state
	relation_changed.emit(a, b, state)


## Sind zwei Reiche im Krieg?
func are_hostile(a: Kingdom, b: Kingdom) -> bool:
	if a == null or b == null or a == b:
		return false
	return a.relations.get(b.id, "peace") == "war"


## Gleiches Reich oder verbündet? (Heilen, Hilfe rufen)
func are_allied(a: Kingdom, b: Kingdom) -> bool:
	if a == null or b == null:
		return false
	return a == b or a.relations.get(b.id, "peace") == "alliance"


## Kann das Reich observer dieses Objekt (Unit/Building) sehen? In Phase 3 ist
## alles sichtbar, ausser getarnten Einheiten fremder Reiche (Phase 7: Spione).
func can_see(observer: Kingdom, obj: Object) -> bool:
	if obj == null or not is_instance_valid(obj):
		return false
	if obj.get("stealthed") == true and not are_allied(observer, obj.kingdom):
		return false
	return true


## Ein Reich hat verloren (by = Sieger oder null). Für den Spieler:
## Spielende-Bildschirm; KI-Reiche zerfallen (VictorySystem).
func defeat_kingdom(k: Kingdom, reason: String, by: Kingdom = null) -> void:
	if k == null or k.defeated:
		return
	k.defeated = true
	k.flags["defeat_reason"] = reason
	k.flags["defeated_by"] = by.id if by != null else 0
	k.flags["defeated_at"] = GameClock.game_time
	kingdom_defeated.emit(k, reason)


## Gründet eine Siedlung: Startressourcen, Burg, König, Startbewohner und ihre Berufe.
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
	# Der König steht vor seiner Burg und verteidigt sie
	var king_def := DataDB.get_unit_for_tier(kingdom.faction_id, "king")
	if not king_def.is_empty():
		var king_pos := kingdom.castle.get_approach_point(center + Vector2(0, 1000))
		var king := unit_system.spawn_unit(kingdom, str(king_def["id"]), king_pos)
		if king != null:
			king.command = "hold"
			king.command_pos = king_pos
			kingdom.king = king


## Verliert der Spieler (sein König stirbt oder seine Burg fällt), ist das Spiel vorbei.
func _on_kingdom_defeated(kingdom: Kingdom, reason: String) -> void:
	if not kingdom.is_player:
		return
	if _game_over != null:
		# Siegbildschirm offen: durch den Niederlage-Bildschirm ersetzen
		_game_over.queue_free()
		_game_over = null
	_pause_for_screen()
	_game_over = GameOverScreen.new()
	add_child(_game_over)
	var title := "Dein Reich ist untergegangen"
	match reason:
		"king":
			title = "Der König ist gefallen"
		"castle":
			title = "Deine Burg ist gefallen"
	_game_over.open(title, "Das Spiel ist vorbei.\n\n" + victory_system.get_stats_text(kingdom))


## Alle feindlichen Königreiche besiegt: Siegbildschirm (pausiert, "Weiterspielen" möglich)
func _on_victory_reached() -> void:
	if _game_over != null or player.defeated:
		return
	_pause_for_screen()
	_game_over = GameOverScreen.new()
	add_child(_game_over)
	_game_over.continue_pressed.connect(continue_after_victory)
	_game_over.open_victory("Sieg!", "Alle feindlichen Königreiche sind gefallen.\n\n" + victory_system.get_stats_text(player))


## Siegbildschirm schliessen und weiterspielen (Knopf und Rauchtest)
func continue_after_victory() -> void:
	if _game_over == null or not _game_over.is_victory():
		return
	victory_system.continued = true
	_game_over.queue_free()
	_game_over = null
	camera.input_enabled = true
	GameClock.set_paused(false)


## Ist gerade der Siegbildschirm zu sehen?
func is_victory_shown() -> bool:
	return _game_over != null and is_instance_valid(_game_over) and _game_over.is_victory()


## Für Sieg- und Niederlagebildschirm: anhalten, Bauen/Auswahl abbrechen, Kamera aus
func _pause_for_screen() -> void:
	GameClock.set_paused(true)
	placement.cancel()
	selection.clear()
	camera.input_enabled = false


func _on_territory_changed(kingdom_id: int, bbox: Rect2i, dirty: Rect2i) -> void:
	var k := get_kingdom(kingdom_id)
	if k != null:
		world_map.territory_border.rebuild(world, kingdom_id, bbox, k.color, dirty)


func _unhandled_input(event: InputEvent) -> void:
	if not _playing or pause_menu.is_open or _game_over != null:
		return
	if event.is_action_pressed("quick_save"):
		quick_save()
	elif event.is_action_pressed("quick_load"):
		quick_load()
	elif event.is_action_pressed("toggle_help"):
		if hud.has_method("toggle_help"):
			hud.call("toggle_help")
	elif event.is_action_pressed("toggle_log"):
		if hud.has_method("toggle_log"):
			hud.call("toggle_log")
	elif event.is_action_pressed("game_menu"):
		# Esc: erst offene Fenster (Helden, Forschung, Arbeitsverteilung) schliessen, dann
		# Zielmodus/Bauen abbrechen, dann Auswahl aufheben, dann Menü
		if hud.close_top_panel():
			pass
		elif spell_targeting.is_active():
			spell_targeting.cancel()
		elif placement.is_active():
			placement.cancel()
		elif not selection.selected.is_empty():
			selection.clear()
		else:
			_open_pause_menu()
	elif event.is_action_pressed("toggle_jobs"):
		hud.toggle_job_panel()
	elif event.is_action_pressed("toggle_research"):
		hud.toggle_research()
	elif event.is_action_pressed("toggle_heroes"):
		hud.toggle_heroes()
	elif event.is_action_pressed("toggle_kingdom"):
		hud.toggle_kingdom()
	elif event.is_action_pressed("toggle_army"):
		if hud.has_method("toggle_army"):
			hud.call("toggle_army")
	elif event.is_action_pressed("select_all_warriors"):
		selection.select_all_warriors()
	elif event.is_action_pressed("toggle_diplomacy"):
		# Das Diplomatiefenster gehört zur Oberfläche (HUD); ohne Fenster nichts tun
		if hud.has_method("toggle_diplomacy"):
			hud.call("toggle_diplomacy")
	elif event.is_action_pressed("toggle_espionage"):
		if hud.has_method("toggle_espionage"):
			hud.call("toggle_espionage")
	elif event.is_action_pressed("hero_ability_1"):
		use_hero_ability(0)
	elif event.is_action_pressed("hero_ability_2"):
		use_hero_ability(1)
	elif event.is_action_pressed("hero_ability_3"):
		use_hero_ability(2)
	elif event.is_action_pressed("hero_cycle"):
		selection.cycle_hero()
	elif event.is_action_pressed("demolish_mode"):
		placement.start_demolish()
	elif event.is_action_pressed("debug_resources") and hud.is_debug_visible():
		for r in DataDB.resources:
			player.add_resource(r["id"], 100.0)
		Notify.info("Debug: +100 von jeder Ressource")
	elif event.is_action_pressed("debug_damage_king") and hud.is_debug_visible():
		# Zum Testen des Spielendes: der König erleidet 150 Schaden
		if is_instance_valid(player.king):
			combat_system.apply_damage(player.king, 150.0, null, null, "event")
			Notify.warning("Debug: König −150 Leben", player.king.position)
	elif event.is_action_pressed("debug_spawn_wolves") and hud.is_debug_visible():
		var key := event as InputEventKey
		if key != null and key.shift_pressed:
			_debug_spawn_golem()
		elif key != null and key.ctrl_pressed:
			_debug_spawn_ram()
		else:
			_debug_spawn_wolves()
	elif event.is_action_pressed("debug_hero_level") and hud.is_debug_visible():
		_debug_hero_level()
	elif event.is_action_pressed("game_pause"):
		GameClock.toggle_pause()
	elif event.is_action_pressed("game_speed_up") or _is_char(event, "+"):
		GameClock.faster()
	elif event.is_action_pressed("game_speed_down") or _is_char(event, "-"):
		GameClock.slower()
	elif event.is_action_pressed("toggle_formation"):
		toggle_formation()
	elif event.is_action_pressed("camera_home"):
		camera.focus_on(player.castle.get_center() if is_instance_valid(player.castle) else world.cell_to_world(world.start_cell))
	elif event.is_action_pressed("toggle_debug"):
		hud.toggle_debug()
	else:
		return
	get_viewport().set_input_as_handled()


## Debug (F11 im F3-Modus): drei Wölfe ohne Höhle an der Maus – zum Testen der
## Zauber im eigenen Gebiet (Fluch, Nebel, Tarnung, Heilung)
func _debug_spawn_wolves() -> void:
	var pos := world_map.get_global_mouse_position()
	var spawned := 0
	for i in 3:
		var c: Vector2i = nav.nearest_free(world.world_to_cell(pos + Vector2.from_angle(TAU * i / 3.0) * 40.0), 4)
		if c.x < 0:
			continue
		if unit_system.spawn_unit(wild, "wolf", world.cell_to_world(c)) != null:
			spawned += 1
	Notify.warning("Debug: %d Wölfe erscheinen" % spawned, pos)


## Debug (Umschalt+F11): ein Übungsgolem ohne Höhle an der Maus (viel Leben, Rüstung)
func _debug_spawn_golem() -> void:
	var pos := world_map.get_global_mouse_position()
	var c: Vector2i = nav.nearest_free(world.world_to_cell(pos), 4)
	if c.x >= 0 and unit_system.spawn_unit(wild, "golem", world.cell_to_world(c)) != null:
		Notify.warning("Debug: Übungsgolem erscheint", pos)


## Debug (Strg+F11): ein feindlicher Rammbock (Monster-Reich, Typ der Gegenfraktion)
## an der Maus, der zur Burg des Spielers marschiert
func _debug_spawn_ram() -> void:
	var pos := world_map.get_global_mouse_position()
	var c: Vector2i = nav.nearest_free(world.world_to_cell(pos), 4)
	var type_id := "ram_evil" if player.faction_id == "good" else "ram_good"
	if c.x < 0:
		return
	var ram := unit_system.spawn_unit(wild, type_id, world.cell_to_world(c))
	if ram == null:
		return
	if is_instance_valid(player.castle):
		command_system.order_move([ram], player.castle.get_approach_point(ram.position), true)
	Notify.warning("Debug: feindlicher Rammbock erscheint", pos)


## Debug (F12): ausgewählter Held (sonst der erste lebende) steigt eine Stufe auf
func _debug_hero_level() -> void:
	var hero_id := 0
	for u in selection.selected:
		if is_instance_valid(u) and u is Unit and u.hero_id != 0:
			hero_id = u.hero_id
			break
	if hero_id == 0:
		for rec in player.heroes:
			if not bool(rec["dead"]):
				hero_id = int(rec["id"])
				break
	if hero_id == 0:
		Notify.warning("Debug: kein lebender Held")
		return
	hero_system.debug_level_up(player, hero_id)


## C / V / B: Fähigkeit index (0–2) des aktiven Helden der Auswahl – auch wenn
## er mit seiner Armee ausgewählt ist. Mit Ziel startet der Zielmodus.
func use_hero_ability(index: int) -> void:
	var u := selection.get_focus_hero()
	if u == null:
		Notify.info("Kein Held ausgewählt – Heldenleiste unten links")
		return
	var abilities: Array = hero_system.get_type(hero_system.find_record(u)).get("abilities", [])
	if index < 0 or index >= abilities.size():
		return
	var ability_id := str(abilities[index])
	if HeroUI.is_passive(ability_id):
		Notify.info("%s wirkt von selbst (passiv)" % str(DataDB.get_ability(ability_id).get("name", "")))
		return
	spell_targeting.start_ability(u, ability_id)


## Formation des Spielers wechseln (Block -> Linie -> Keil -> Kreis); gilt für die nächsten Marschbefehle
func toggle_formation() -> void:
	var list := CommandSystem.FORMATIONS
	set_formation(str(list[(list.find(player.formation) + 1) % list.size()]))
	Notify.info("Formation: %s" % CommandSystem.get_formation_name(player.formation))


## Formation des Spielers setzen (CommandSystem.FORMATIONS; Armeefenster, Taste F)
func set_formation(formation: String) -> void:
	if not CommandSystem.FORMATIONS.has(formation) or player.formation == formation:
		return
	player.formation = formation
	formation_changed.emit(formation)


## Taste mit diesem Zeichen gedrückt? (z. B. "+" liegt auf Schweizer Tastaturen auf Shift+1)
func _is_char(event: InputEvent, ch: String) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.unicode == ch.unicode_at(0)


func _open_pause_menu() -> void:
	_was_paused_before_menu = GameClock.paused
	GameClock.set_paused(true)
	camera.input_enabled = false
	pause_menu.open(self)


## Ist das Spiel gerade nur wegen des Spielmenüs pausiert? (SaveGame speichert die Pause davor)
func is_menu_pause() -> bool:
	return pause_menu.is_open


# ---------------------------------------------------------------------------
# Speichern und Laden (Phase 10)
# ---------------------------------------------------------------------------

## "" = Speichern möglich, sonst der Grund
func can_save() -> String:
	if not _playing:
		return "Die Welt wird noch geladen"
	if _game_over != null:
		return "Das Spiel ist vorbei"
	if SaveManager.is_busy():
		return "Es wird gerade gespeichert"
	return ""


## Speichert die Partie. kind: "manual", "quick" oder "auto". async: im Hintergrund schreiben.
## Gibt "" zurück, wenn es geklappt hat (bzw. gestartet wurde), sonst den Grund.
func save_game(slot: String, display_name: String, kind: String = "manual", async: bool = true) -> String:
	var reason := can_save()
	if not reason.is_empty():
		return reason
	var t := Time.get_ticks_usec()
	var res := SaveGame.collect(self, slot, display_name, kind)
	var collect_ms := (Time.get_ticks_usec() - t) / 1000.0
	if not SaveManager.save_finished.is_connected(_on_save_finished):
		SaveManager.save_finished.connect(_on_save_finished)
	_pending_save = {"slot": slot, "name": display_name, "kind": kind}
	var err := SaveManager.write_save(slot, res[0], res[1], async)
	if not err.is_empty():
		Notify.danger("Speichern fehlgeschlagen: " + err)
		return err
	print("[save] %s (%s): Einsammeln %.0f ms" % [slot, kind, collect_ms])
	return ""


var _pending_save: Dictionary = {}


func _on_save_finished(slot: String, ok: bool, message: String) -> void:
	if _pending_save.is_empty() or str(_pending_save.get("slot", "")) != slot:
		return
	var kind := str(_pending_save.get("kind", "manual"))
	var display_name := str(_pending_save.get("name", slot))
	_pending_save = {}
	if not ok:
		Notify.danger("Speichern fehlgeschlagen: " + message)
		return
	_last_save_game_time = GameClock.game_time
	if kind != "auto":
		GameSession.last_save_name = display_name
		Notify.good("Gespeichert: %s" % display_name)


## Spielsekunden seit dem letzten Speichern (bzw. Start/Laden)
func seconds_since_save() -> float:
	return GameClock.game_time - _last_save_game_time


## F5: Schnellspeichern (vorige Datei bleibt als .bak)
func quick_save(async: bool = true) -> String:
	var err := save_game(SaveManager.QUICK_SLOT, "Schnellspeicherung", "quick", async)
	if not err.is_empty():
		Notify.warning("Schnellspeichern nicht möglich: " + err)
	return err


## F8: Schnellladen
func quick_load() -> String:
	if not SaveManager.exists(SaveManager.QUICK_SLOT):
		Notify.info("Kein Schnellspeicherstand vorhanden (F5 speichert).")
		return "Kein Schnellspeicherstand"
	var err := SaveManager.request_load(SaveManager.QUICK_SLOT)
	if not err.is_empty():
		Notify.danger("Laden nicht möglich: " + err)
		return err
	request_reload()
	return ""


## Spielszene neu laden (lädt den vorgemerkten Spielstand). Der Rauchtest lenkt das um.
func request_reload() -> void:
	GameClock.stop()
	if reload_handler.is_valid():
		reload_handler.call()
		return
	get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


## Fenster schliessen: ungespeicherten Fortschritt vorher in den Autospeicherplatz sichern
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _playing and can_save().is_empty() \
			and seconds_since_save() > float(DataDB.cfg("save.unsaved_warning_seconds", 60)):
		save_game(SaveManager.next_autosave_slot(), "Autospeicherung (Beenden)", "auto", false)


func _on_pause_menu_closed() -> void:
	camera.input_enabled = true
	GameClock.set_paused(_was_paused_before_menu)


func _exit_tree() -> void:
	# Verlässt man die Szene während der Generierung: abbrechen und Thread beenden
	if _gen_thread != null and _gen_thread.is_started():
		_generator.cancelled = true
		_nav_builder.cancelled = true
		_gen_thread.wait_to_finish()
	GameClock.stop()
