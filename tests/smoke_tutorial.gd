## Rauchtest Tutorial (Aufruf: smoke_test.tscn mit tutorial=1). Startet eine Tutorial-Partie
## (GameSession.setup_tutorial_game) und spielt alle Schritte über dieselben öffentlichen
## Schnittstellen wie die Oberfläche durch (Gebäude setzen, Berufe, Beschwören, Befehle,
## Forschung, Zauber, Helden, Fenster öffnen, Geschenk, Speichern, Hilfe). Je Schritt wird
## geprüft: "Weiter" ist vor der Aufgabe gesperrt, die Bedingung wird erfüllt (nicht
## übersprungen), Hervorhebung bzw. Pfeil finden ihr Ziel, Geschenke werden einmal bezahlt.
## Dazu: Schutz vor KI-Angriffen, Ereignissen und Streifzügen, Zustand im Spielstand
## (Schnellspeichern im Schritt "Speichern", danach Laden in eine frische Spielszene,
## Beenden und Fortsetzen über das Spielmenü).
## Ohne tutorial=1 prüft quick_check() im normalen Rauchtest nur: Tutorial aus, kein Schutz,
## System im Spielstand angemeldet.
extends RefCounted

const SAVE_DIR := "user://saves_smoke_tutorial/"
## So lange (Spielsekunden) darf ein Schritt höchstens dauern
const STEP_TIMEOUT := 240.0

var runner: Node
var game: Node
var errors := 0
var finished := false

var _phase := "start"
var _step_id := ""
var _acted := false
var _step_started := 0.0
var _wait_until := 0.0
var _target_seen := false
var _completed: Array = []
var _troops: Array = []
var _reload_ms := 0
## Frames seit Beginn des Schritts (Fenster und Rahmen sind dann gezeichnet)
var _frames := 0
## Bildschirmfotos (shots=<ordner>, nur mit Fenster): diese Schritte
var _shots := false
const SHOT_STEPS := ["welcome", "zoom", "house", "farmer", "mana_well", "scout", "troops", "research", "heroes", "diplomacy"]


func _init(p_runner: Node, p_game: Node, args: Dictionary) -> void:
	runner = p_runner
	game = p_game
	_shots = not str(args.get("shots", "")).is_empty()


func _fail(text: String) -> void:
	errors += 1
	push_error("[smoke] Tutorial FEHLER: " + text)


func _ok(text: String) -> void:
	print("[smoke] Tutorial OK: " + text)


func _check(cond: bool, text: String) -> void:
	if cond:
		_ok(text)
	else:
		_fail(text)


## Normaler Rauchtest (ohne tutorial=1): Tutorial aus, kein Schutz, im Spielstand angemeldet
static func quick_check(p_game: Node) -> int:
	var bad := 0
	var ts: TutorialSystem = p_game.get("tutorial_system")
	var keys: Array = []
	for entry in SaveGame.system_entries(p_game):
		keys.append(entry[0])
	if ts == null or ts.is_running() or TutorialSystem.protects(p_game, p_game.player) or not keys.has("tutorial"):
		bad += 1
		push_error("[smoke] Tutorial FEHLER: im normalen Spiel aktiv, schützt den Spieler oder fehlt im Spielstand")
	else:
		print("[smoke] Tutorial OK: im normalen Spiel aus, kein Schutz, im Spielstand angemeldet")
	return bad


func tick() -> void:
	game = runner.get("_game")
	if game == null or not is_instance_valid(game) or game.get("_playing") != true:
		return
	match _phase:
		"start":
			_start_checks()
			_phase = "steps"
		"steps":
			_tick_steps()
		"reloading":
			_after_reload()
		"done":
			pass


func _start_checks() -> void:
	runner.get_tree().root.size = Vector2i(1600, 900)
	# Ohne Fenster steht die Maus in der Ecke: Randscrollen aus, die Kamera bewegt nur der Test
	game.camera.input_enabled = false
	SaveManager.save_dir = SAVE_DIR
	_clear_dir()
	var ts: TutorialSystem = game.tutorial_system
	_check(GameSession.difficulty_id == str(DataDB.tut("game.difficulty")) and GameSession.map_size_id == str(DataDB.tut("game.map_size"))
			and GameSession.seed_text == str(DataDB.tut("game.seed")), "Tutorial-Partie: %s, %s, Seed %s" % [
			GameSession.difficulty_id, GameSession.map_size_id, GameSession.seed_text])
	_check(ts.is_running() and ts.get_step_number() == 1, "Tutorial läuft ab Schritt 1 (%d Schritte)" % ts.get_step_count())
	_check(ts.get_step_count() >= 20 and ts.get_step_count() <= 40, "Anzahl Schritte %d" % ts.get_step_count())
	_check(TutorialSystem.protects(game, game.player), "Schutz aktiv")
	_check(ts.overlay != null and ts.overlay.visible, "Tutorial-Fenster sichtbar")
	_check(ts.overlay._progress_label.text == "Schritt 1/%d" % ts.get_step_count() and not ts.overlay._title.text.is_empty(),
			"Fenster zeigt „%s“ – %s" % [ts.overlay._progress_label.text, ts.overlay._title.text])
	# Alle Texte ohne offene Platzhalter
	var bad: PackedStringArray = []
	for s in ts.get_steps():
		var text := ts.format_text(str(s.get("text", "")))
		if text.contains("{") or text.contains("\u00df"):
			bad.append(str(s.get("id", "")))
	_check(bad.is_empty(), "Texte ohne offene Platzhalter und ohne Eszett" + ("" if bad.is_empty() else ": " + ", ".join(bad)))
	_protection_checks()


## Ereignisse, KI-Wellen und Streifzüge verschonen den Spieler
func _protection_checks() -> void:
	var es: EventSystem = game.event_system
	var hits := 0
	for i in 40:
		for def in DataDB.get_events():
			var target: Kingdom = es._pick_target(def, GameClock.game_time + 99999.0)
			if target == game.player:
				hits += 1
	_check(hits == 0, "Ereignisse wählen den Spieler nicht als Ziel")
	var ai: AISystem = game.ai_system
	var player_targets := 0
	var before := ai.debug_fast
	ai.debug_fast = true
	for k in ai.get_ai_kingdoms():
		var brain := ai.get_brain(k)
		if brain == null:
			continue
		for cand in AIMilitary._candidates(brain, GameClock.game_time):
			if str(cand["kind"]) == "player":
				player_targets += 1
	ai.debug_fast = before
	_check(player_targets == 0, "KI wählt den Spieler nicht als Wellenziel (ohne Zeitsperren)")


# ---------------------------------------------------------------------------
# Schritte
# ---------------------------------------------------------------------------

func _tick_steps() -> void:
	var ts: TutorialSystem = game.tutorial_system
	var now := GameClock.game_time
	if not ts.is_running():
		_finish_steps()
		return
	var id := str(ts.get_step().get("id", ""))
	if id != _step_id:
		_step_id = id
		_acted = false
		_target_seen = false
		_step_started = now
		_wait_until = 0.0
		_frames = 0
		var s := ts.get_step()
		if not str(s.get("condition", "")).is_empty():
			_check(not ts.advance(), "Schritt %d „%s“: Weiter vor der Aufgabe gesperrt" % [ts.get_step_number(), id])
		if s.has("grant"):
			_check(ts.granted.has(id), "Schritt „%s“: Geschenk bezahlt" % id)
	# Ziele
	var hl := str(ts.get_step().get("highlight", ""))
	if not hl.is_empty() and not hl.begins_with("world:") and ts.overlay.get_target_rect().size.x > 0.0:
		_target_seen = true
	_frames += 1
	if not _acted:
		if now < _wait_until or _frames < (8 if _shots else 2):
			return
		if _shots and SHOT_STEPS.has(id) and _frames == 8:
			runner.call("_shot", "tutorial_%02d_%s" % [ts.get_step_number(), id])
		if _act(ts, id):
			_acted = true
		return
	if ts.check_now():
		_complete_step(ts, id)
		return
	if now - _step_started > STEP_TIMEOUT:
		_fail("Schritt „%s“ nicht erfüllt nach %d s (Bedingung %s)" % [id, int(STEP_TIMEOUT), str(ts.get_step().get("condition", ""))])
		if not ts.skip():
			ts.done = true
			ts.advance()


func _complete_step(ts: TutorialSystem, id: String) -> void:
	var s := ts.get_step()
	var hl := str(s.get("highlight", ""))
	if not hl.is_empty() and not hl.begins_with("world:"):
		_check(_target_seen, "Schritt „%s“: Rahmen um %s" % [id, hl])
	for key in ["world", "highlight"]:
		var spec := str(s.get(key, ""))
		if spec.begins_with("world:"):
			_check(ts.world_target(spec) is Vector2, "Schritt „%s“: Pfeil zu %s" % [id, spec])
	_completed.append(id)
	var n := ts.get_step_number()
	if str(s.get("condition", "")).is_empty():
		_check(ts.advance(), "Schritt %d „%s“ mit Weiter" % [n, id])
	else:
		_ok("Schritt %d „%s“ erfüllt (%s)" % [n, id, str(s.get("condition", ""))])
		ts.advance()


## Aktion des Schritts über die öffentlichen Schnittstellen; true = erledigt (dann warten)
func _act(ts: TutorialSystem, id: String) -> bool:
	var k: Kingdom = game.player
	var hud: Node = game.hud
	var faction := k.faction_id
	match id:
		"welcome", "resources", "finish":
			_complete_step(ts, id)
			return false
		"castle", "castle_city":
			var want := 2 if id == "castle" else 3
			_check(k.get_castle_level() >= want, "Burgstufe %d als Geschenk (jetzt %d)" % [want, k.get_castle_level()])
			_complete_step(ts, id)
			return false
		"camera":
			game.camera.focus_on(k.castle.get_center() + Vector2(900, 300))
		"zoom":
			game.camera.focus_on(game.camera.position, game.camera.zoom.x * 1.6)
		"pause":
			GameClock.set_paused(true)
		"speed":
			GameClock.set_speed_index(GameClock.speed_steps.size() - 1)
		"house":
			_check(_place("house", false) != null, "Wohnhaus gesetzt (Baustelle)")
		"farm":
			_check(_place("farm", true) != null, "Bauernhof gesetzt")
		"roads":
			_check(_place_roads(5) >= 4, "Strasse gezogen")
		"farmer":
			if game.work_system.get_idle_count(k) == 0:
				game.work_system.unassign_job(k, "woodcutter")
			_check(game.work_system.assign_job(k, "farmer"), "Bauer zugewiesen")
		"mana_well":
			_check(_place_mana_well() != null, "Manabrunnen auf der Manaquelle")
		"scout":
			game.selection.select([k.castle])
			_check(game.summon_system.summon(k.castle, str(DataDB.get_unit_for_tier(faction, "scout")["id"])), "Späher eingereiht")
		"select":
			var scout := _first_unit("scout")
			if scout == null:
				return false
			game.selection.select([scout])
		"move":
			var own: Array = game.selection.get_own_units()
			game.selection._issue_order(own, k.castle.get_center() + Vector2(300, 420), false)
		"barracks":
			_check(_place("barracks", true) != null, "Kaserne gesetzt")
		"troops":
			var barracks := _building("barracks")
			game.selection.select([barracks])
			var fighter := str(DataDB.get_unit_for_tier(faction, "fighter")["id"])
			var reason: String = game.summon_system.can_summon(barracks, fighter)
			_check(game.summon_system.summon(barracks, fighter) and game.summon_system.summon(barracks, fighter),
					"Zwei Kämpfer eingereiht " + reason)
		"army":
			_troops = _units_of_tier("fighter")
			game.selection.select(_troops)
			game.command_system.set_army(k, 1, _troops)
		"attack_move":
			game.selection.select(_troops)
			game.selection._issue_order(game.selection.get_own_units(), k.castle.get_center() + Vector2(-400, 300), true)
		"library":
			_check(_place("library", true) != null, "Bibliothek gesetzt")
		"research":
			var rid := _alias("healing", faction)
			var reason: String = game.research_system.can_start(k, rid)
			_check(game.research_system.start(k, rid), "Forschung %s gestartet %s" % [rid, reason])
		"spell":
			var spell := _alias("heal_spell", faction)
			if not game.magic_system.is_known(k, spell):
				_wait_until = GameClock.game_time + 2.0
				return false
			var pos: Vector2 = k.king.position if is_instance_valid(k.king) else k.castle.get_center()
			var reason: String = game.magic_system.can_cast(k, spell, pos)
			_check(game.magic_system.cast(k, spell, pos), "Zauber %s gewirkt %s" % [spell, reason])
		"hero_hall":
			_check(_place("hero_hall", true) != null, "Heldenhalle gesetzt")
		"heroes":
			hud.open_heroes(HeroPanel.TAB_RECRUIT)
			var offers: Array = game.hero_system.get_offers(k)
			var type_id := str((offers[0] as Dictionary)["id"]) if not offers.is_empty() else ""
			var reason: String = game.hero_system.can_recruit(k, type_id)
			_check(game.hero_system.recruit(k, type_id), "Held %s angeworben %s" % [type_id, reason])
		"diplomacy":
			hud.close_top_panel()
			hud.open_diplomacy()
		"gift":
			var village := _nearest_village()
			_check(village != null and game.diplomacy_system.give_gift(k, village, {"food": 30}), "Geschenk an ein Dorf")
		"espionage":
			hud.open_espionage()
		"kingdom":
			hud.open_kingdom()
		"army_window":
			if hud.has_method("toggle_army"):
				hud.call("toggle_army")
			else:
				ts.skip()
				return false
		"select_all":
			# Knopf im Armeefenster (wie Strg+A)
			var panel: TroopPanel = hud.troop_panel
			(panel.buttons["all"] as Button).pressed.emit()
		"stance":
			game.selection.select_all_warriors()
			var stance_row: HBoxContainer = hud.selection_panel.get("_stance_row")
			_check(stance_row.visible, "Auswahlfenster zeigt die Haltung")
			(hud.selection_panel.get("_stance_buttons")["aggressive"] as Button).pressed.emit()
		"forge":
			hud.close_top_panel()
			var forge := _place("forge", true)
			_check(forge != null, "Schmiede gesetzt")
			if forge == null:
				ts.skip()
				return false
			game.selection.select([forge])
			hud.selection_panel._refresh()
			var box: TroopSelectionBox = hud.selection_panel.get("_troop_box")
			_check(box.get_mode() == "forge" and box.press_forge("forge_infantry_weapons"), "Schmiede-Stufe gekauft")
		"stat_points":
			var promoted: Unit = null
			for u in k.units:
				if is_instance_valid(u) and u.is_alive() and game.troop_system.get_free_points(u) > 0:
					promoted = u
					break
			_check(promoted != null, "Ein Krieger ist aufgestiegen und hat einen Wertepunkt")
			if promoted == null:
				ts.skip()
				return false
			game.selection.select([promoted])
			hud.selection_panel._refresh()
			var tbox: TroopSelectionBox = hud.selection_panel.get("_troop_box")
			_check(tbox.press_stat("hp"), "Wertepunkt auf Leben verteilt")
		"save":
			hud.close_top_panel()
			_check(game.quick_save(false).is_empty(), "Schnellspeichern im Tutorial")
		"help":
			hud.open_help()
		_:
			_fail("Unbekannter Schritt „%s“ – Rauchtest ergänzen" % id)
			ts.skip()
			return false
	_wait_until = GameClock.game_time + 0.3
	return true


## Alle Schritte durch: Zustand prüfen, dann den Spielstand aus dem Schritt "Speichern" laden
func _finish_steps() -> void:
	var ts: TutorialSystem = game.tutorial_system
	var hud: Node = game.hud
	hud.close_top_panel()
	if hud.is_help_open():
		hud.help_panel.close()
	_check(ts.state == TutorialSystem.STATE_FINISHED, "Tutorial abgeschlossen (%d Schritte erfüllt)" % _completed.size())
	var expected := 0
	for s in ts.get_steps():
		if not str(s.get("condition", "")).is_empty():
			expected += 1
	var conds := 0
	for id in _completed:
		for s in ts.get_steps():
			if str(s.get("id", "")) == id and not str(s.get("condition", "")).is_empty():
				conds += 1
	_check(conds == expected, "Alle Bedingungen erfüllt: %d von %d" % [conds, expected])
	_check(not ts.overlay.visible, "Tutorial-Fenster nach dem Ende ausgeblendet")
	_check(ts.is_protecting(), "Schutz gilt nach dem Ende noch (Schonfrist)")
	var d := ts.to_dict()
	var copy := TutorialSystem.new()
	copy.from_dict(d)
	_check(SaveCodec.encode(copy.to_dict()) == SaveCodec.encode(d), "to_dict/from_dict gleich")
	copy.free()
	_check(ts.menu_action_text() == "Tutorial starten", "Spielmenü bietet „Tutorial starten“ an")
	# Spielstand aus dem Schritt "Speichern" in eine frische Spielszene laden
	var err := SaveManager.request_load(SaveManager.QUICK_SLOT)
	_check(err.is_empty(), "Schnellspeicherstand ladbar " + err)
	if not err.is_empty():
		_phase = "done"
		finished = true
		return
	_reload_ms = Time.get_ticks_msec()
	_phase = "reloading"
	game.request_reload()


func _after_reload() -> void:
	var ts: TutorialSystem = game.tutorial_system
	print("[smoke] Tutorial: Spielstand geladen nach %d ms" % (Time.get_ticks_msec() - _reload_ms))
	_check(ts.is_running() and str(ts.get_step().get("id", "")) == "save", "Geladen: Tutorial läuft beim Schritt „Speichern“ (%s, %s)" % [
			ts.state, ts.step_id])
	_check(ts.protect and TutorialSystem.protects(game, game.player), "Geladen: Schutz aktiv")
	_check(ts.overlay != null and ts.overlay.visible, "Geladen: Tutorial-Fenster sichtbar")
	_check(ts.granted.has("heroes"), "Geladen: bezahlte Geschenke gemerkt")
	ts.abort()
	_check(ts.state == TutorialSystem.STATE_ABORTED and not ts.overlay.visible, "Beenden blendet das Tutorial aus")
	_check(ts.menu_action_text().begins_with("Tutorial fortsetzen"), "Spielmenü: " + ts.menu_action_text())
	game.call("_open_pause_menu")
	var pm: Node = game.pause_menu
	var button: Button = pm.get("_tutorial_button")
	_check(button != null and button.visible and button.text.begins_with("Tutorial fortsetzen"), "Knopf im Spielmenü: " + (button.text if button != null else "-"))
	button.emit_signal("pressed")
	_check(not pm.is_open and ts.is_running() and ts.step_id == "save", "Fortsetzen beim gemerkten Schritt")
	var res_before := float(game.player.get_amount("food"))
	ts.menu_action()
	_check(ts.is_running() and ts.get_step_number() == 1, "Von vorn beginnen")
	ts._enter_step("heroes")
	_check(float(game.player.get_amount("food")) <= res_before + 0.01, "Geschenke werden nach Neustart nicht doppelt bezahlt")
	ts.abort()
	_phase = "done"
	finished = true


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

func _alias(name_id: String, faction: String) -> String:
	return str(((DataDB.tut("aliases", {}) as Dictionary).get(name_id, {}) as Dictionary).get(faction, name_id))


## Gebäude in der Nähe der Burg (Spirale), instant = sofort fertig (ohne Kosten)
func _place(def_id: String, instant: bool) -> Building:
	var k: Kingdom = game.player
	var def := DataDB.get_building(def_id)
	var center: Vector2i = game.world.world_to_cell(k.castle.get_center())
	for r in range(3, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var cell := center + Vector2i(dx, dy)
				# Sofort fertig kostet nichts: Kosten nicht prüfen
				var reason: String = game.building_system._place_reason(def, cell, k, not instant)
				if reason.is_empty():
					return game.building_system.place_building(def, cell, k, instant)
	return null


func _place_mana_well() -> Building:
	var k: Kingdom = game.player
	var def := DataDB.get_building("mana_well")
	var pos: Variant = game.tutorial_system.world_target("world:mana")
	if not (pos is Vector2):
		return null
	var spring: Vector2i = game.world.world_to_cell(pos)
	for dy in range(-1, 1):
		for dx in range(-1, 1):
			var cell := spring + Vector2i(dx, dy)
			if game.building_system.can_place(def, cell, k).is_empty():
				return game.building_system.place_building(def, cell, k, true)
	push_warning("[smoke] Manabrunnen: " + game.building_system.can_place(def, spring, k))
	return null


## Gerade Strasse im eigenen Gebiet (n Kacheln)
func _place_roads(n: int) -> int:
	var k: Kingdom = game.player
	var center: Vector2i = game.world.world_to_cell(k.castle.get_center())
	for r in range(3, 12):
		for dir in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var cells: Array = []
			for i in n:
				var c: Vector2i = center + dir * (r + i) + Vector2i(dir.y, dir.x) * 2
				if not game.building_system.can_place_road(c, k).is_empty():
					break
				cells.append(c)
			if cells.size() == n:
				return game.building_system.place_roads(cells, k)
	return 0


func _building(def_id: String) -> Building:
	for b in game.player.buildings:
		if is_instance_valid(b) and str(b.def.get("id", "")) == def_id:
			return b
	return null


func _first_unit(tier: String) -> Unit:
	var list := _units_of_tier(tier)
	return list[0] if not list.is_empty() else null


func _units_of_tier(tier: String) -> Array:
	var list: Array = []
	for u in game.player.units:
		if is_instance_valid(u) and u.is_alive() and u.tier == tier:
			list.append(u)
	return list


func _nearest_village() -> Kingdom:
	var best: Kingdom = null
	var best_d := INF
	var home: Vector2 = game.player.castle.get_center()
	for v in game.village_system.get_villages():
		var d := home.distance_to(game.village_system.get_center(v))
		if d < best_d:
			best_d = d
			best = v
	return best


func _clear_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return
	for f in DirAccess.get_files_at(SAVE_DIR):
		DirAccess.remove_absolute(SAVE_DIR + f)


func report() -> void:
	_clear_dir()
	print("[smoke] Tutorial: %s (%d Schritte erfüllt)" % ["OK" if errors == 0 else "%d Fehler" % errors, _completed.size()])
