## Rauchtest Spione (eigene Szene tests/smoke_spies.tscn, von run_smoke.sh für beide Fraktionen
## gestartet): Zu Spielbeginn hat kein Reich Spione; ein über das Spionagefenster beschworener
## Spion existiert genau einmal (Einheit, Datensatz in SpySystem.spies, Eintrag im Fenster) –
## auch mit Auftrag und nach Speichern und Laden.
##   godot --headless res://tests/smoke_spies.tscn -- faction=good [shots=<ordner> unter xvfb-run]
## Fehler erscheinen als "ERROR: [smoke] Spione FEHLER: …" (push_error), Rückgabewert 1.
extends Node

const SLOT := "smoke_spies"

var _game: Node
var _faction := "good"
var _step := 0
var _wait_until := 0.0
var _errors := 0
var _spy_uid := 0
var _target_id := 0
## Ordner für Bildschirmfotos ("" = keine)
var _shots := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := str(a).split("=", true, 1)
		if parts.size() == 2 and parts[0] == "faction":
			_faction = parts[1]
		if parts.size() == 2 and parts[0] == "shots":
			_shots = parts[1]
	GameSession.setup_new_game(_faction, "normal", "small", "12345", "")
	_spawn_game()


func _spawn_game() -> void:
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	_game.set("reload_handler", _swap_game)
	get_tree().root.add_child.call_deferred(_game)


## Laden: alte Spielszene weg, neue liest GameSession.pending_load_path
func _swap_game() -> void:
	var old := _game
	if old.get_parent() != null:
		old.get_parent().remove_child(old)
	old.queue_free()
	_spawn_game()


## Bildschirmfoto (nur mit Fenster und shots=<ordner>)
func _shot(shot_name: String) -> void:
	if _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	get_viewport().get_texture().get_image().save_png("%s/spies_%s_%s.png" % [_shots, _faction, shot_name])


func _check(cond: bool, text: String) -> void:
	if cond:
		print("[smoke] Spione OK: " + text)
	else:
		_errors += 1
		push_error("[smoke] Spione FEHLER: " + text)


## Spione des Spielers an allen Stellen: Einheiten, Datensätze, Liste, Fenster
func _counts() -> Dictionary:
	var g := _game
	var ss: SpySystem = g.spy_system
	var k: Kingdom = g.player
	var units := 0
	for u in k.units:
		if (u as Unit).tier == "spy":
			units += 1
	var records := 0
	for uid in ss.spies:
		if int((ss.spies[uid] as Dictionary).get("owner_id", 0)) == k.id:
			records += 1
	var panel: EspionagePanel = g.hud.espionage_panel
	panel.open(EspionagePanel.TAB_SPIES)
	panel._refresh()
	var listed: int = panel._spy_list.get_child_count()
	panel.close()
	return {"units": units, "records": records, "list": ss.get_spies(k).size(), "window": listed}


func _expect(n: int, when: String) -> void:
	var c := _counts()
	_check(c["units"] == n and c["records"] == n and c["list"] == n and c["window"] == n,
			"%s: %d Spion(e) – Einheiten %d, Datensätze %d, Liste %d, Fenster %d" % [when, n, c["units"],
			c["records"], c["list"], c["window"]])


func _process(_delta: float) -> void:
	if _game == null or not is_instance_valid(_game) or _game.get("_playing") != true:
		return
	var g := _game
	var k: Kingdom = g.player
	var ss: SpySystem = g.spy_system
	match _step:
		0:
			_expect(0, "Spielbeginn (Spieler)")
			var others := 0
			for o in g.kingdoms:
				for u in (o as Kingdom).units:
					if (u as Unit).tier == "spy":
						others += 1
			_check(others == 0 and ss.spies.is_empty(), "Spielbeginn: kein Reich hat Spione (%d Einheiten, %d Datensätze)" % [
					others, ss.spies.size()])
			# Forschung und Rohstoffe, dann über das Fenster beschwören (wie der Spieler)
			var r := DataDB.find_research_unlocking(k.faction_id, "unit:" + str(SpySystem.spy_type(k.faction_id)["id"]))
			_check(not r.is_empty(), "Forschung für Spione: %s" % str(r.get("name", "-")))
			if not r.is_empty():
				g.research_system._complete(k, str(r["id"]))
			for res in k.resources:
				k.resources[res] = 5000.0
			var panel: EspionagePanel = g.hud.espionage_panel
			panel.open(EspionagePanel.TAB_SPIES)
			_check(ss.can_recruit(k).is_empty(), "Spion beschwörbar (%s)" % ss.can_recruit(k))
			panel._on_recruit_pressed()
			panel.close()
			_check(ss.count_queued(k) == 1, "Ein Spion in Arbeit")
			GameClock.set_speed_index(GameClock.speed_steps.size() - 1)
			Engine.time_scale = 8.0
			_wait_until = GameClock.game_time + 240.0
			_step = 1
		1:
			if ss.get_spies(k).is_empty():
				if GameClock.game_time > _wait_until:
					_check(false, "Spion erscheint nicht")
					_finish()
				return
			_expect(1, "Nach dem Beschwören")
			var spy: Unit = ss.get_spies(k)[0]
			_spy_uid = spy.uid
			_check(int(ss.counters.get(k.id, 0)) == 1, "Laufende Nummer 1 (%s)" % spy.get_display_name())
			# Auftrag über das Fenster: Auskundschaften beim nächsten KI-Reich
			var ai: Array = g.ai_system.get_ai_kingdoms()
			_target_id = (ai[0] as Kingdom).id if not ai.is_empty() else 0
			var panel: EspionagePanel = g.hud.espionage_panel
			panel.select_spy(_spy_uid)
			panel.set_mission_choice("scout", _target_id)
			var answer := panel.assign_selected()
			_check(answer.is_empty(), "Auftrag Auskundschaften erteilt %s" % answer)
			_wait_until = GameClock.game_time + 10.0
			_step = 2
		2:
			if GameClock.game_time < _wait_until:
				return
			_expect(1, "Mit Auftrag")
			var err: String = g.save_game(SLOT, "Rauchtest Spione", "manual", false)
			_check(err.is_empty(), "Gespeichert %s" % err)
			err = SaveManager.request_load(SLOT)
			_check(err.is_empty(), "Laden angefordert %s" % err)
			_step = 3
			g.request_reload()
		3:
			_expect(1, "Nach dem Laden")
			var rec: Dictionary = ss.spies.get(_spy_uid, {})
			_check(not rec.is_empty() and str(rec.get("mission", "")) == "scout" and int(rec.get("target_id", 0)) == _target_id,
					"Nach dem Laden: derselbe Spion mit seinem Auftrag")
			_wait_until = GameClock.game_time + 10.0
			_step = 4
		4:
			if GameClock.game_time < _wait_until:
				return
			_expect(1, "10 s nach dem Laden")
			# Zweiter Spion, der schon vor der Beschwörungs-Meldung abgefragt wird (Datensatz entsteht
			# beim Abfragen): die Meldung legt keinen zweiten Datensatz und keine zweite Nummer an
			var spy_id := str(SpySystem.spy_type(k.faction_id)["id"])
			var u: Unit = g.unit_system.spawn_unit(k, spy_id, k.castle.get_approach_point(k.castle.get_center()))
			ss.get_spies(k)
			var number := int(ss.counters.get(k.id, 0))
			g.summon_system.unit_summoned.emit(u, k.castle)
			_expect(2, "Abfrage vor der Beschwörungs-Meldung")
			_check(int(ss.counters.get(k.id, 0)) == number and number == 2,
					"Keine doppelte Nummer (%s, Zähler %d)" % [u.get_display_name(), int(ss.counters.get(k.id, 0))])
			_step = 98
			await _report_test(u)
			_finish()


## Spionagebericht: ohne Kundschaft "unbekannt"; ein Spion der höchsten Stufe am Ziel liefert
## genaue Truppen- und Verteidigungszahlen, die zum Spielzustand passen, und eine Meldung
func _report_test(spy: Unit) -> void:
	var g := _game
	var k: Kingdom = g.player
	var ss: SpySystem = g.spy_system
	var esp: EspionageSystem = g.espionage_system
	var panel: EspionagePanel = g.hud.espionage_panel
	var villages: Array = g.village_system.get_villages()
	if not villages.is_empty():
		var v: Kingdom = villages[0]
		panel.open(EspionagePanel.TAB_REALMS, v.id)
		panel._refresh()
		_check(esp.get_report(k, v).is_empty() and panel._realm_report.text.contains("unbekannt"),
				"Bericht ohne Kundschaft über %s: unbekannt" % v.display_name)
		panel.close()
	var ai: Array = g.ai_system.get_ai_kingdoms()
	if ai.is_empty():
		_check(false, "Kein KI-Reich für den Spionagebericht")
		return
	var target: Kingdom = ai[0]
	# Ein Turm beim Ziel, damit die Verteidigung etwas zu zählen hat
	var tower_def := DataDB.get_building("tower")
	var center: Vector2i = g.world.world_to_cell(target.castle.get_center())
	var placed := false
	for r in range(4, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell := center + Vector2i(dx, dy)
				if placed or (absi(dx) != r and absi(dy) != r) or not _free_2x2(target, cell):
					continue
				for res in tower_def.get("cost", {}):
					target.resources[res] = float(target.resources.get(res, 0.0)) + float(tower_def["cost"][res])
				placed = g.building_system.place_building(tower_def, cell, target, true) != null
	_check(placed, "Turm beim Ziel gebaut")
	# Ein paar Truppen beim Ziel (3 Nahkämpfer, 2 Schützen)
	for tier in ["fighter", "fighter", "fighter", "archer", "archer"]:
		var def := DataDB.get_unit_for_tier(target.faction_id, tier)
		g.unit_system.spawn_unit(target, str(def["id"]), target.castle.get_approach_point(target.castle.get_center() + Vector2(0, 900)))
	# Spion auf höchster Stufe am Ziel, Auskundschaften läuft
	var rec := ss.get_record(spy)
	rec["level"] = SpySystem.max_level()
	rec["mission"] = "scout"
	rec["target_id"] = target.id
	rec["state"] = "active"
	rec["active_since"] = GameClock.game_time
	spy.position = target.castle.get_center() + Vector2(0, 300)
	var notes_before := Notify.history.size()
	ss._work(spy, rec, GameClock.game_time)
	var report := esp.get_report(k, target)
	var troops := 0
	var power := 0.0
	var towers := 0
	for u in target.units:
		if EspionageSystem.is_army_unit(u) and (u as Unit).role != "hero":
			troops += 1
	for u in target.units:
		if EspionageSystem.is_army_unit(u) or (u as Unit) == target.king:
			power += VillageSystem.unit_power(u)
	var tower_power := 0.0
	for b in target.buildings:
		if (b as Building).constructed and str((b as Building).def.get("fortification", "")) == "tower":
			towers += 1
			var t: Dictionary = (b as Building).def.get("tower", {})
			tower_power += (b as Building).max_hp * float(t.get("attack", 0.0)) / maxf(float(t.get("interval", 1.0)), 0.1) / 100.0
	_check(not report.is_empty() and int(report["level"]) == 3, "Bericht über %s auf Stufe 3" % target.display_name)
	_check(int(report.get("troop_total", -1)) == troops and int(report.get("towers", -1)) == towers
			and int(report.get("defense_power", -1)) == roundi(power + tower_power)
			and int(report.get("castle_level", -1)) == target.get_castle_level()
			and int(report.get("population", -1)) == target.get_population(),
			"Bericht stimmt mit dem Spielzustand: %d Truppen, %d Türme, Stärke %d, Burgstufe %d, %d Bewohner" % [
			troops, towers, roundi(power + tower_power), target.get_castle_level(), target.get_population()])
	panel.open(EspionagePanel.TAB_REALMS, target.id)
	panel._refresh()
	var text := panel._realm_report.text
	await get_tree().process_frame
	await get_tree().process_frame
	_shot("bericht")
	_check(text.contains("Truppen:[/b] %d" % troops) and text.contains("Türme %d" % towers)
			and text.contains("Gesamtstärke %d" % roundi(power + tower_power)) and text.contains("[b]Plan:[/b]"),
			"Spionagefenster zeigt die genauen Zahlen und Pläne")
	panel.close()
	var noted := false
	for i in range(notes_before, Notify.history.size()):
		if str((Notify.history[i] as Dictionary).get("text", "")).contains("Spionagebericht"):
			noted = true
	_check(noted, "Neuer Bericht steht im Protokoll")


## 2 × 2 freie, bebaubare Kacheln im Gebiet von k (ohne Strasse und Vorkommen)
func _free_2x2(k: Kingdom, cell: Vector2i) -> bool:
	var w: WorldData = _game.world
	for y in range(cell.y, cell.y + 2):
		for x in range(cell.x, cell.x + 2):
			var c := Vector2i(x, y)
			if not w.in_bounds(c) or w.get_owner(c) != k.id or not bool(w.get_biome(c).get("buildable", false)) \
					or w.occupancy.get(c, null) != null or w.roads.has(c) or not w.get_deposit(c).is_empty():
				return false
	return true


func _finish() -> void:
	_step = 99
	Engine.time_scale = 1.0
	SaveManager.delete_save(SLOT)
	print("[smoke] Spione: %s" % ("OK" if _errors == 0 else "%d Fehler" % _errors))
	get_tree().quit(0 if _errors == 0 else 1)
