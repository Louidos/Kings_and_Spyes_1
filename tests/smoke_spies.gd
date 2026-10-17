## Rauchtest Spione (eigene Szene tests/smoke_spies.tscn, von run_smoke.sh für beide Fraktionen
## gestartet): Zu Spielbeginn hat kein Reich Spione; ein über das Spionagefenster beschworener
## Spion existiert genau einmal (Einheit, Datensatz in SpySystem.spies, Eintrag im Fenster) –
## auch mit Auftrag und nach Speichern und Laden.
##   godot --headless res://tests/smoke_spies.tscn -- faction=good
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


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := str(a).split("=", true, 1)
		if parts.size() == 2 and parts[0] == "faction":
			_faction = parts[1]
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
			_finish()


func _finish() -> void:
	_step = 99
	Engine.time_scale = 1.0
	SaveManager.delete_save(SLOT)
	print("[smoke] Spione: %s" % ("OK" if _errors == 0 else "%d Fehler" % _errors))
	get_tree().quit(0 if _errors == 0 else 1)
