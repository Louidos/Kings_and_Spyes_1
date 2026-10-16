## Rauchtest (ohne Fenster): startet eine Partie, lässt sie im Zeitraffer laufen
## und gibt am Ende eine Zusammenfassung aus. Fehler erscheinen als
## "SCRIPT ERROR" in der Ausgabe.
## Dazu ein Heldentest über die Oberfläche (HeroTest): Heldenhalle (sofort gebaut,
## Debug-Rohstoffe), Anwerben im Heldenfenster, Stufen per Debug-Knopf, Stufenwahl,
## Fähigkeit im Zielmodus, "selbst auslösen", Ausbildung, Heldenleiste, Tod und
## Wiederbelebung über die Burg im Auswahlfenster, Lage der Leisten.
##
## Phase 6 bis 10 prüfen eigene Dateien (smoke_phase6.gd … smoke_phase10.gd), das
## Armeefenster smoke_army.gd, die Truppen (neue Einheiten, Konter, Schmiede, Ränge,
## Wertepunkte, Aussehen) smoke_troops.gd, das Tutorial smoke_tutorial.gd (tutorial=1).
## Phase 10: nach dem Hauptlauf wird ein Zwischenstand in eine frische Spielszene geladen,
## verglichen und weitergespielt (p10=off schaltet das ab, p10_after=<s> Dauer danach).
## passive=1: der Spieler tut nichts (kein Helden- und Phase-6-Test) – für lange Läufe,
## in denen nur die KI spielt.
##
## Aufruf (im Projektordner):
##   godot --headless res://tests/smoke_test.tscn -- faction=good seconds=120 size=small seed=12345
##   weitere Argumente: ai=<Anzahl KI-Reiche>, p7=natural, p8=natural, passive=1, difficulty=<id>, people=<volk>,
##   p10=off, p10_after=300, ui_scale=1.25 (Bildschirmfotos mit grösserer Oberfläche)
## Tutorial: tutorial=1 startet eine Tutorial-Partie und spielt alle Schritte durch (tests/smoke_tutorial.gd;
## ohne Helden- und Phasentests); ohne tutorial=1 prüft der Lauf nur, dass das Tutorial aus ist
## Oberfläche fotografieren: ui_shots=1 shots=<ordner> win=1600x900 ui_scale=1.25 (tests/ui_shots.gd, unter xvfb-run)
## Balancing (Phase 10): balance=1 sample=600 (tests/balance_phase10.gd; setzt p7/p8=natural, passive=1, p10=off)
extends Node

## Prüfungen der Phase 6 (Dörfer, Diplomatie, Boten) in eigener Datei
const SmokePhase6 := preload("res://tests/smoke_phase6.gd")
const SmokePhase7 := preload("res://tests/smoke_phase7.gd")
const SmokePhase8 := preload("res://tests/smoke_phase8.gd")
const SmokePhase9 := preload("res://tests/smoke_phase9.gd")
const SmokePhase10 := preload("res://tests/smoke_phase10.gd")
const BalancePhase10 := preload("res://tests/balance_phase10.gd")
## Armeefenster (Taste T): Übersicht, Auswahl, Befehle, Haltung, Speichern der Haltung
const SmokeArmy := preload("res://tests/smoke_army.gd")
const SmokeTutorial := preload("res://tests/smoke_tutorial.gd")
## Truppen: Klassen, Konter, Schmiede, Ränge, Wertepunkte, Aussehen
const SmokeTroops := preload("res://tests/smoke_troops.gd")
## Ausbaustufen der Gebäude: Ausbau, Bauarbeiter, Werte, Abbruch, Abriss, Speichern
const SmokeLevels := preload("res://tests/smoke_levels.gd")
## Bildschirmfotos der Oberfläche (ui_shots=1 shots=<ordner> win=1600x900)
const UiShots := preload("res://tests/ui_shots.gd")

var _args := {}
var _game: Node = null
var _started_ms := 0
var _sim_seconds := 120.0
var _phase := 0
## Schritt des Heldentests (siehe _hero_test), -1 = fertig
var _hero_step := 0
var _hero_wait_until := 0.0
var _hero_id := 0
var _hero_errors := 0
var _test_wolf: Unit = null
var _p6: RefCounted = null
var _p7: RefCounted = null
var _p8: RefCounted = null
var _p9: RefCounted = null
var _p10: RefCounted = null
var _pa: RefCounted = null
var _passive := false
var _balance: RefCounted = null
## Tutorial-Lauf (tutorial=1)
var _tutorial := false
var _tut: RefCounted = null
var _troops: RefCounted = null
var _levels: RefCounted = null
## Bildschirmfotos der Oberfläche (ui_shots=1)
var _ui_shots: RefCounted = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := str(a).split("=", true, 1)
		if parts.size() == 2:
			_args[parts[0]] = parts[1]
	if str(_args.get("balance", "0")) == "1":
		for key in ["p7", "p8"]:
			if not _args.has(key):
				_args[key] = "natural"
		if not _args.has("passive"):
			_args["passive"] = "1"
		if not _args.has("p10"):
			_args["p10"] = "off"
	_sim_seconds = float(_args.get("seconds", "120"))
	# UI-Grösse für Bildschirmfotos (ui_scale=1.25); der Phase-10-Test setzt sie später zurück
	if _args.has("ui_scale"):
		Settings.ui_scale = clampf(float(_args["ui_scale"]), 0.75, 1.5)
	_passive = str(_args.get("passive", "0")) == "1"
	GameSession.ai_count_override = int(_args.get("ai", "-1"))
	_tutorial = str(_args.get("tutorial", "0")) == "1"
	if _tutorial:
		GameSession.setup_tutorial_game(str(_args.get("faction", "good")), str(_args.get("people", "")))
	else:
		GameSession.setup_new_game(str(_args.get("faction", "good")), str(_args.get("difficulty", "normal")),
				str(_args.get("size", "small")), str(_args.get("seed", "12345")), str(_args.get("people", "")))
	print("[smoke] Starte Partie: ", GameSession.faction_id, " Seed ", GameSession.seed_text)
	_started_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/game.tscn")
	_game = scene.instantiate()
	_game.set("reload_handler", swap_game)
	get_tree().root.add_child.call_deferred(_game)


## Spielszene ersetzen (Laden eines Spielstands im Rauchtest): alte Szene entfernen,
## neue erzeugen – sie liest GameSession.pending_load_path
func swap_game() -> void:
	var old := _game
	_game = null
	if old != null and is_instance_valid(old):
		if old.get_parent() != null:
			old.get_parent().remove_child(old)
		old.queue_free()
	var scene: PackedScene = load("res://scenes/game.tscn")
	_game = scene.instantiate()
	_game.set("reload_handler", swap_game)
	get_tree().root.add_child.call_deferred(_game)


func _process(_delta: float) -> void:
	if _phase == 3:
		_p10.tick_roundtrip()
		if _troops != null:
			_troops.tick_after_load(_game, str(_p10.get("_rt_state")))
		if _levels != null:
			_levels.tick_after_load(_game, str(_p10.get("_rt_state")))
		if _p10.get("finished") == true:
			_phase = 4
			_p10.report()
			get_tree().quit(0)
		return
	if _game == null or not is_instance_valid(_game):
		return
	if _phase == 0:
		if _game.get("_playing") == true:
			_phase = 1
			print("[smoke] Welt fertig nach %d ms" % (Time.get_ticks_msec() - _started_ms))
			GameClock.set_speed_index(GameClock.speed_steps.size() - 1)
			Engine.time_scale = float(_args.get("time_scale", "8"))
			Engine.physics_ticks_per_second = 60
			if _game.has_method("smoke_test_setup"):
				_game.smoke_test_setup()
			if _tutorial:
				_hero_step = -1
				_tut = SmokeTutorial.new(self, _game, _args)
				return
			if str(_args.get("ui_shots", "0")) == "1":
				_hero_step = -1
				Engine.time_scale = 1.0
				_ui_shots = UiShots.new(self, _game, _args)
				return
			if _passive:
				_hero_step = -1
			else:
				_p6 = SmokePhase6.new(_game)
				_pa = SmokeArmy.new(_game)
				if _game.get("siege_system") != null:
					_p9 = SmokePhase9.new(_game)
				if _game.get("troop_system") != null:
					_troops = SmokeTroops.new(self, _game)
				_levels = SmokeLevels.new(self, _game)
			# Passiv: nur der Bericht, was die KI von den neuen Truppen nutzt
			if _passive and _game.get("troop_system") != null:
				_troops = SmokeTroops.new(self, _game)
				_troops.set("passive", true)
			_p7 = SmokePhase7.new(_game, _args)
			_p8 = SmokePhase8.new(_game, _args)
			_p10 = SmokePhase10.new(self, _game, _args)
			if str(_args.get("balance", "0")) == "1":
				_balance = BalancePhase10.new(_game, _args)
		elif Time.get_ticks_msec() - _started_ms > 120000:
			push_error("[smoke] Weltgenerierung dauert zu lange")
			get_tree().quit(2)
	elif _phase == 1 and _ui_shots != null:
		_ui_shots.tick()
		if _ui_shots.get("finished") == true:
			_phase = 4
			get_tree().quit(0)
	elif _phase == 1 and _tut != null:
		_tut.tick()
		if _tut.get("finished") == true or GameClock.game_time >= _sim_seconds * 4.0:
			if _tut.get("finished") != true:
				push_error("[smoke] Tutorial FEHLER: nicht fertig nach %d Spielsekunden" % int(GameClock.game_time))
			_phase = 4
			_report()
			_tut.report()
			get_tree().quit(0)
	elif _phase == 1:
		if _hero_step >= 0 and GameClock.game_time >= _hero_wait_until:
			_hero_test()
		if _balance != null:
			_balance.tick(GameClock.game_time)
		if _p6 != null:
			_p6.set("ui_ready", _hero_step < 0)
			_p6.tick(GameClock.game_time)
		if _p7 != null:
			_p7.tick(GameClock.game_time)
		if _p8 != null:
			_p8.tick(GameClock.game_time)
		if _p9 != null:
			_p9.set("ui_ready", _hero_step < 0)
			_p9.tick(GameClock.game_time)
		if _pa != null:
			_pa.set("ui_ready", _hero_step < 0)
			_pa.tick(GameClock.game_time)
		if _troops != null:
			_troops.set("ui_ready", _hero_step < 0)
			_troops.tick(GameClock.game_time)
		if _levels != null:
			_levels.tick(GameClock.game_time)
		if _p10 != null:
			_p10.tick(GameClock.game_time, _hero_step < 0)
		if _balance != null and GameClock.game_time >= _sim_seconds - 50.0:
			_balance.report(GameClock.game_time)
		if GameClock.game_time >= _sim_seconds:
			_phase = 2
			_report()
			if _p10 != null and _p10.get("enabled") == true:
				_phase = 3
				_p10.start_roundtrip()
			else:
				get_tree().quit(0)


func _report() -> void:
	print("[smoke] Spielzeit %.0f s (Tag %d)" % [GameClock.game_time, GameClock.get_day()])
	for k in _game.kingdoms:
		var res := []
		for r in k.resources:
			res.append("%s %.0f" % [r, float(k.resources[r])])
		print("[smoke] Reich %d %s (%s, %s): Gebäude %d, Einheiten %d, besiegt %s | %s" % [
				k.id, k.display_name, k.faction_id, k.controller, k.buildings.size(), k.units.size(),
				str(k.defeated), ", ".join(res)])
	if _hero_step >= 0:
		_hero_fail("Heldentest nicht fertig geworden (Schritt %d)" % _hero_step)
	if not _passive and not _tutorial:
		print("[smoke] Heldentest: %s" % ("OK" if _hero_errors == 0 else "%d Fehler" % _hero_errors))
	if _game.has_method("smoke_test_report"):
		_game.smoke_test_report()
	if not _tutorial:
		SmokeTutorial.quick_check(_game)
	if _p6 != null:
		_p6.report()
	if _p7 != null:
		_p7.report()
	if _p8 != null:
		_p8.report()
	if _p9 != null:
		_p9.report()
	if _pa != null:
		_pa.report()
	if _troops != null:
		_troops.report()
	if _levels != null:
		_levels.report()


# ---------------------------------------------------------------------------
# Heldentest (Oberfläche: Heldenfenster, Heldenleiste, Auswahlfenster, Zielmodus)
# ---------------------------------------------------------------------------

func _hero_fail(text: String) -> void:
	_hero_errors += 1
	push_error("[smoke] Heldentest: " + text)


func _hero_check(ok: bool, text: String) -> void:
	if not ok:
		_hero_fail(text)


func _hero_test() -> void:
	var g: Node = _game
	var k: Kingdom = g.player
	var hs: HeroSystem = g.hero_system
	var hud: Node = g.hud
	var panel: HeroPanel = hud.hero_panel
	var rec := hs.get_record(k, _hero_id)
	var u := hs.get_unit(k, _hero_id)
	# Nächster Schritt frühestens nach einer halben Spielsekunde (Layout, Zeichnen)
	_hero_wait_until = GameClock.game_time + 0.5
	match _hero_step:
		0:
			# Fenster wie im Spiel (1600×900, logisch 1920×1080) – ohne Fenster ist es sonst quadratisch
			get_tree().root.size = Vector2i(1600, 900)
			# Debug-Rohstoffe, Kaserne und Heldenhalle sofort bauen, im Fenster anwerben
			for r in DataDB.resources:
				k.resources[str(r["id"])] = 5000.0
			var barracks := _place_near_castle(DataDB.get_building("barracks"))
			var hall := _place_near_castle(DataDB.get_building("hero_hall"))
			_hero_check(barracks != null and hall != null, "Kaserne/Heldenhalle nicht platzierbar")
			if hall == null:
				_hero_step = -1
				return
			hud.open_heroes(HeroPanel.TAB_RECRUIT)
			_hero_check(panel.is_open() and panel.get_tab() == HeroPanel.TAB_RECRUIT, "Heldenfenster (Anwerben) nicht offen")
			var offers := hs.get_offers(k)
			_hero_check(not offers.is_empty(), "keine Heldenangebote")
			var type_id := str((offers[0] as Dictionary)["id"])
			_hero_check(panel.recruit_reason(type_id).is_empty(), "Anwerben gesperrt: " + panel.recruit_reason(type_id))
			panel._on_recruit_pressed(type_id)
			_hero_check(hall.summon_queue.size() == 1, "Anwerben hat nichts eingereiht")
			# Zweiter Held desselben Typs: Grund muss erscheinen
			_hero_check(not panel.recruit_reason(type_id).is_empty(), "Doppelter Heldentyp nicht gesperrt")
			print("[smoke] Heldentest: %s wird angeworben" % type_id)
			_hero_step = 1
		1:
			_shot("1_anwerben")
			hud.close_top_panel()
			# Halle auswählen: Beschwören-Knöpfe mit Heldenkosten, Ausbildung
			g.selection.select([hs.get_hall(k)])
			_hero_step = 2
		2:
			_shot("2_heldenhalle")
			if k.heroes.is_empty():
				_hero_wait_until = GameClock.game_time + 1.0
				_hero_step = 2 if GameClock.game_time < 300.0 else -1
				if _hero_step < 0:
					_hero_fail("Held erscheint nicht")
				return
			_hero_id = int((k.heroes[0] as Dictionary)["id"])
			rec = hs.get_record(k, _hero_id)
			_hero_check(hs.get_unit(k, _hero_id) != null, "Heldeneinheit fehlt")
			# Heldenfenster: zwei Stufen per Debug-Knopf
			hud.toggle_debug()
			hud.open_heroes(HeroPanel.TAB_HEROES, _hero_id)
			_hero_check(panel.get_hero_id() == _hero_id, "Heldenfenster zeigt den Helden nicht")
			panel.debug_action("level")
			panel.debug_action("level")
			_hero_check(int(rec["level"]) == 3 and int(rec["pending"]) == 2, "Debug-Stufen: Stufe %d, offen %d" % [
					int(rec["level"]), int(rec["pending"])])
			_hero_check(HeroPanel.needs_attention(hs, k), "Offene Stufenwahl nicht markiert")
			_hero_step = 3
		3:
			_shot("3_heldenfenster_stufenwahl")
			_hero_check(panel.choose_option(0), "Stufenwahl 1 fehlgeschlagen")
			_hero_check(panel.choose_option(1), "Stufenwahl 2 fehlgeschlagen")
			_hero_check(int(rec["pending"]) == 0, "Stufenwahl offen geblieben")
			print("[smoke] Heldentest: %s Stufe %d, Ränge %s, Talente %s" % [str(rec["name"]), int(rec["level"]),
					str(rec["ranks"]), str(rec["talents"])])
			panel._on_train_pressed()
			_hero_check(float(rec["train_ready_at"]) > GameClock.game_time, "Ausbildung nicht gelaufen")
			_hero_step = 4
		4:
			_shot("4_heldenfenster")
			hud.close_top_panel()
			hud.hero_bar._refresh()
			_hero_check(hud.hero_bar.visible, "Heldenleiste unsichtbar")
			# Gemischte Auswahl: Held mit Truppen (zwei Kämpfer dazu)
			var fighter := str(DataDB.get_unit_for_tier(k.faction_id, "fighter").get("id", ""))
			for i in 2:
				g.unit_system.spawn_unit(k, fighter, u.position + Vector2(-40 - 30 * i, 30))
			var army: Array = [u]
			for o in k.units:
				if o != u and (o as Unit).joins_fights and o != k.king and army.size() < 4:
					army.append(o)
			g.selection.select(army)
			_hero_check(g.selection.get_focus_hero() == u, "Aktiver Held der Auswahl fehlt")
			g.selection.cycle_hero()
			_hero_check(g.selection.get_focus_hero() == u, "Tab wechselt weg vom einzigen Helden")
			hud.selection_panel._refresh()
			_hero_check(hud.selection_panel._hero_box.visible, "Heldenabschnitt bei gemischter Auswahl unsichtbar")
			_hero_step = 5
		5:
			_shot("5_gemischte_auswahl")
			g.selection.select([u])
			hud.selection_panel._refresh()
			_hero_check(hud.selection_panel._hero_box.visible, "Heldenabschnitt beim Helden unsichtbar")
			_hero_step = 6
		6:
			if u == null:
				_hero_fail("Held vor dem Fähigkeitstest gefallen")
				_hero_step = -1
				return
			_layout_report(hud)
			_shot("6_held_auswahl")
			# Fähigkeit 1 (Feind als Ziel) gegen einen Wolf neben dem Helden: Zielmodus
			var wolf: Unit = g.unit_system.spawn_unit(g.wild, "wolf", u.position + Vector2(96, 0))
			_test_wolf = wolf
			var first := str((hs.get_type(rec).get("abilities", []) as Array)[0])
			hs.debug_reset_cooldowns(k, _hero_id)
			g.use_hero_ability(0)
			if HeroUI.needs_target(first):
				_hero_check(g.spell_targeting.is_ability_targeting(u.uid, first), "Zielmodus der Fähigkeit nicht aktiv")
				# Maus auf den Wolf (für das Bild des Zielmodus)
				if is_instance_valid(wolf):
					g.camera.focus_on(u.position)
					g.spell_targeting._mouse_screen = g.get_viewport().get_canvas_transform() * wolf.position
					g.spell_targeting._mouse_seen = true
			_hero_step = 7
		7:
			var first := str((hs.get_type(rec).get("abilities", []) as Array)[0])
			_shot("7_zielmodus")
			if g.spell_targeting.is_active():
				if is_instance_valid(_test_wolf) and _test_wolf.is_alive():
					g.spell_targeting._try_ability(_test_wolf.position)
					_hero_check(not g.spell_targeting.is_active(), "Zielmodus nach dem Wirken noch aktiv")
				else:
					# Der Wolf ist schon tot (z. B. selbst ausgelöster Lichtschlag): nur abbrechen
					g.spell_targeting.cancel()
			_hero_check(hs.cooldown_left(rec, first) > 0.0 or (u != null and not u.cast_ability.is_empty()), "Fähigkeit nicht gewirkt")
			# Alle Fähigkeiten einmal (ohne Ziel sofort, mit Ziel Zielmodus und abbrechen)
			for aid in hs.get_type(rec).get("abilities", []):
				hs.debug_reset_cooldowns(k, _hero_id)
				g.spell_targeting.start_ability(u, str(aid))
				g.spell_targeting.cancel()
			var auto_before := hs.is_autocast(rec, first)
			HeroSelectionBox.toggle_autocast(g, u, first)
			_hero_check(hs.is_autocast(rec, first) != auto_before or not HeroUI.can_autocast(first),
					"Selbst auslösen nicht umgeschaltet")
			HeroSelectionBox.toggle_autocast(g, u, first)
			hud.open_heroes(HeroPanel.TAB_HEROES, _hero_id)
			panel.debug_action("cooldowns")
			# Held fällt
			panel.debug_action("kill")
			hud.close_top_panel()
			_hero_wait_until = GameClock.game_time + 1.0
			_hero_step = 8
		8:
			_hero_check(bool(rec["dead"]), "Held ist nicht gefallen")
			hud.hero_bar._refresh()
			_hero_check(not hud.hero_bar.tooltip_for(_hero_id).is_empty(), "Heldenleiste ohne Tooltip")
			hud.open_heroes(HeroPanel.TAB_HEROES, _hero_id)
			panel.debug_action("revive")
			hud.close_top_panel()
			# Wiederbeleben über die Burg im Auswahlfenster
			g.selection.select([k.castle])
			hud.selection_panel._refresh()
			_hero_check(hud.selection_panel._hero_box.visible, "Burg zeigt keine Wiederbelebung")
			_hero_step = 9
		9:
			_shot("8_burg_wiederbeleben")
			var box: HeroSelectionBox = hud.selection_panel._hero_box
			box._on_row_pressed(_hero_id)
			_hero_check(not bool(rec["dead"]), "Wiederbelebung fehlgeschlagen: " + hs.can_revive(k, _hero_id))
			hud.open_link({"window": "heroes", "hero_id": _hero_id})
			_hero_check(hud.is_heroes_open(), "Verweis öffnet das Heldenfenster nicht")
			hud.toggle_research()
			_hero_check(not hud.is_heroes_open(), "Forschungs- und Heldenfenster gleichzeitig offen")
			hud.close_top_panel()
			hud.toggle_debug()
			g.selection.clear()
			print("[smoke] Heldentest: Tod und Wiederbelebung OK")
			_hero_step = -1


## Bildschirmfoto (nur mit shots=<ordner> und echtem Fenster, z. B. unter xvfb-run)
func _shot(shot_name: String) -> void:
	var dir := str(_args.get("shots", ""))
	if dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s_%s.png" % [dir, GameSession.faction_id, shot_name])


## Gebäude sofort fertig in der Nähe der Burg (Spirale um die Burg)
func _place_near_castle(def: Dictionary) -> Building:
	var g: Node = _game
	var k: Kingdom = g.player
	var center: Vector2i = g.world.world_to_cell(k.castle.get_center())
	for r in range(4, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var cell := center + Vector2i(dx, dy)
				if g.building_system.can_place(def, cell, k).is_empty():
					return g.building_system.place_building(def, cell, k, true)
	return null


## Lage der Leisten (logische Grösse 1920×1080; 1600×900 wird gleich skaliert). Ohne Fenster
## (--headless) rechnet die Schrift anders – verlässlich ist die Lage nur mit Fenster (xvfb-run).
func _layout_report(hud: Node) -> void:
	var rects := {"Arbeitsverteilung": hud.job_panel.get_global_rect(), "Auswahl": hud.selection_panel.get_global_rect(),
			"Heldenleiste": hud.hero_bar.get_global_rect(), "Meldungen": hud.notification_panel.get_global_rect(),
			"Info": hud.info_panel.get_global_rect()}
	var parts: PackedStringArray = []
	for key in rects:
		var r: Rect2 = rects[key]
		parts.append("%s %d,%d %dx%d" % [key, r.position.x, r.position.y, r.size.x, r.size.y])
	print("[smoke] Layout (%s): %s" % [str(hud.get_viewport().get_visible_rect().size), ", ".join(parts)])
	var bar: Rect2 = rects["Heldenleiste"]
	for key in ["Arbeitsverteilung", "Auswahl", "Meldungen", "Info"]:
		if bar.intersects(rects[key] as Rect2):
			_hero_fail("Heldenleiste überdeckt %s" % key)
