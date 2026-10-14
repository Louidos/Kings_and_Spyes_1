## Game
##
## Spielszene: erzeugt die Welt im Hintergrund und verbindet anschliessend
## Karte, Kamera, Systeme, HUD und Menüs. Globale Tastenkürzel (Pause, Tempo,
## Menü) werden hier verarbeitet.
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


func _ready() -> void:
	GameClock.stop()
	camera.input_enabled = false
	hud.visible = false
	pause_menu.closed.connect(_on_pause_menu_closed)
	loading.open(GameSession.seed_text)

	# Weltgenerierung im Hintergrund-Thread, damit das Fenster nicht einfriert
	_generator = WorldGenerator.new()
	_generator.progress_callback = func(p: float, text: String) -> void:
		loading.set_progress.call_deferred(p, text)
	_nav_builder = NavGrid.new()
	_gen_thread = Thread.new()
	_gen_thread.start(_generate_world.bind(GameSession.world_seed, GameSession.get_map_tiles()))


## Läuft im Thread: nur Daten erzeugen, keine Nodes anfassen.
## Gibt [WorldData, NavGrid] zurück.
func _generate_world(world_seed: int, size: int) -> Array:
	var w := _generator.generate(world_seed, size)
	if not _generator.cancelled:
		loading.set_progress.call_deferred(1.0, "Berechne Wege …")
		_nav_builder.build(w)
	return [w, _nav_builder]


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
	placement.setup(self)
	selection.setup(self)
	unit_overlay.setup(self)
	combat_effects.setup(self)
	magic_effects.setup(self)
	spell_targeting.setup(self)
	kingdom_defeated.connect(_on_kingdom_defeated)
	victory_system.victory_reached.connect(_on_victory_reached)

	player = create_kingdom({"faction_id": GameSession.faction_id, "controller": "player"})
	# Getarnte Einheiten aus Sicht des Spielers zeichnen
	Unit.viewer_kingdom_id = player.id
	found_settlement(player, world.start_cell)
	# Wilde Monster: ein eigenes Reich, mit allen im Krieg
	wild = create_kingdom({"faction_id": "wild", "controller": "wild", "display_name": "Wilde Monster"})
	monster_system.setup(self, wild)
	# Neutrale Dörfer vor den Monsterlagern (das Monster-Reich behält id 2)
	village_system.found_villages()
	# Gegnerische Königreiche (ids nach den Dörfern)
	ai_system.found_ai_kingdoms()
	monster_system.spawn_camps()

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
	Notify.info("Burg anklicken: Späher beschwören. Monsterlager (orange auf der Minikarte) bringen Beute.",
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
	if event.is_action_pressed("game_menu"):
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


## Formation des Spielers wechseln (Block <-> Linie); gilt für die nächsten Marschbefehle
func toggle_formation() -> void:
	player.formation = "line" if player.formation == "block" else "block"
	formation_changed.emit(player.formation)
	Notify.info("Formation: %s" % CommandSystem.get_formation_name(player.formation))


## Taste mit diesem Zeichen gedrückt? (z. B. "+" liegt auf Schweizer Tastaturen auf Shift+1)
func _is_char(event: InputEvent, ch: String) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.unicode == ch.unicode_at(0)


func _open_pause_menu() -> void:
	_was_paused_before_menu = GameClock.paused
	GameClock.set_paused(true)
	camera.input_enabled = false
	pause_menu.open()


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
