## Rauchtest Phase 10: Speichern und Laden, Oberfläche, Autospeichern, Einstellungen,
## Hilfe, Protokoll, Schwierigkeit. Wird von smoke_test.gd aufgerufen.
## S0  Codec-Selbsttest, Schnittstelle aller Systeme, eigene Test-Ordner
## S1  Zwischenstand speichern (synchron) + Messwerte
## S2  Oberfläche: Speichern mit Name + Überschreiben-Rückfrage, Liste, Löschen,
##     Autospeichern reihum, Einstellungen speichern/laden, Hilfe, Protokoll
## S3  nach dem Hauptlauf: Zwischenstand in eine frische Spielszene laden
## S4  Vergleich mit den Messwerten + Idempotenz (sofort wieder eingesammelt = geladen)
## S5  weiterlaufen (p10_after Spielsekunden): hängende Einheiten, Arbeit, KI, Bewegung
## S6  Schnellspeichern/-laden und Vergleich, kurz weiterlaufen; aufräumen
## Argumente: p10=roundtrip (Standard) | off, p10_after=<Spielsekunden> (Standard 300)
extends RefCounted

const SAVE_DIR := "user://saves_smoke/"
const SETTINGS_FILE := "user://settings_smoke.cfg"

var runner: Node
var game: Node
var enabled := true
var after := 300.0
var errors := 0
var finished := false

var _seconds := 900.0
var _step := 0
var _mid_at := 330.0
var _ui_at := 0.0
var _snapshot: Dictionary = {}
var _snapshot_working := 0
var _save_ms := 0.0
var _save_kb := 0.0
var _rt_state := ""
var _rt_wait_ms := 0
var _load_ms := 0
var _cont_start := 0.0
var _cont_checked := false
var _cont_base: Dictionary = {}
var _quick_metrics: Dictionary = {}
var _quick_until := 0.0


func _init(p_runner: Node, p_game: Node, args: Dictionary) -> void:
	runner = p_runner
	game = p_game
	enabled = str(args.get("p10", "roundtrip")) != "off"
	after = float(args.get("p10_after", "300"))
	_seconds = float(args.get("seconds", "900"))
	_mid_at = maxf(_seconds * 0.5, 330.0)
	if _mid_at > _seconds - 30.0:
		_mid_at = maxf(_seconds - 60.0, 30.0)


func _fail(text: String) -> void:
	errors += 1
	push_error("[smoke] Phase 10 FEHLER: " + text)


func _ok(text: String) -> void:
	print("[smoke] Phase 10 OK: " + text)


func _check(cond: bool, text: String) -> void:
	if cond:
		_ok(text)
	else:
		_fail(text)


## Hauptlauf (jeder Frame); hero_done: Heldentest des Runners ist fertig
func tick(t: float, hero_done: bool) -> void:
	if not enabled:
		return
	match _step:
		0:
			if t >= 1.0:
				_s0()
				_step = 1
		1:
			if t >= _mid_at and hero_done:
				_s1()
				_ui_at = t + 5.0
				_step = 2
		2:
			if t >= _ui_at:
				_s2()
				_step = 3


# ---------------------------------------------------------------------------
# S0
# ---------------------------------------------------------------------------

func _s0() -> void:
	SaveManager.save_dir = SAVE_DIR
	Settings.file_path = SETTINGS_FILE
	_clear_dir()
	_codec_selftest()
	var keys: Array = []
	for entry in SaveGame.system_entries(game):
		keys.append(entry[0])
	_check(SaveGame.interface_errors.is_empty(), "Alle Systeme haben to_dict/from_dict/rebuild_runtime (%s)" % ", ".join(keys))
	# Schwierigkeit: Quellen gesetzt
	var wild: Kingdom = game.wild
	var m := Difficulty.value("monster_strength_mult", 1.0)
	_check(is_equal_approx(float((wild.modifier_sources.get("difficulty", {}) as Dictionary).get("hp", -1.0)), m),
			"Monster-Stärke der Schwierigkeit %s: ×%s" % [GameSession.difficulty_id, str(m)])
	for k in game.kingdoms:
		if k.controller == "ai":
			_check(is_equal_approx(float((k.modifier_sources.get("difficulty", {}) as Dictionary).get("gather", -1.0)),
					Difficulty.value("enemy_income_mult", 1.0)), "KI-Reich %s mit Schwierigkeitsquelle" % k.display_name)
			break


func _codec_selftest() -> void:
	SaveCodec.errors.clear()
	var data := {"int": 5, "neg": -7, "big": 9007199254740993, "rng": -6917529027641081856, "float": 2.5,
			"float_whole": 3.0, "inf": INF, "ninf": -INF, "str": "Grüezi #1", "bool": true, "null": null,
			"v2": Vector2(1.5, -2.0), "v2i": Vector2i(3, 4), "r2i": Rect2i(1, 2, 3, 4), "col": Color(0.1, 0.2, 0.3, 1.0),
			"int_keys": {1: "a", 22: {"x": [1, 2.5, Vector2i(1, 1)]}}, "v2i_keys": {Vector2i(5, 6): 1.25},
			"hash_key": {"#d": 1}, "pv2": PackedVector2Array([Vector2(1, 2), Vector2(3.5, 4)]),
			"pb": PackedByteArray([1, 2, 255]), "pi32": PackedInt32Array([1, -2, 300000]),
			"pf32": PackedFloat32Array([0.5, 1.5]), "ps": PackedStringArray(["a", "b"]),
			"nested": [[1, [2.0, "x"]], {"k": []}]}
	var back := SaveCodec.from_json(SaveCodec.to_json(data))
	var diff := PackedStringArray()
	SaveCodec.deep_diff(data, back, "codec", diff)
	_check(diff.is_empty(), "Codec-Selbsttest (Typen erhalten)" + ("" if diff.is_empty() else ": " + ", ".join(diff)))
	_check(SaveCodec.errors.is_empty(), "Codec ohne nicht speicherbare Werte")


# ---------------------------------------------------------------------------
# S1
# ---------------------------------------------------------------------------

func _s1() -> void:
	SaveCodec.errors.clear()
	var t := Time.get_ticks_usec()
	var err: String = game.save_game("smoke_p10_mid", "Rauchtest Mitte", "manual", false)
	_save_ms = (Time.get_ticks_usec() - t) / 1000.0
	_snapshot = SaveGame.metrics(game)
	_snapshot_working = _working_count()
	_check(err.is_empty(), "Zwischenstand gespeichert bei %.0f s" % GameClock.game_time)
	var path := SaveManager.slot_path("smoke_p10_mid")
	_check(FileAccess.file_exists(path), "Datei vorhanden")
	var res := SaveManager.read_data(path)
	_check(str(res.get("error", "")).is_empty(), "Datei lesbar, Prüfsumme stimmt " + str(res.get("error", "")))
	var h: Dictionary = res.get("header", {})
	_save_kb = float(h.get("payload_bytes", 0)) / 1024.0
	print("[smoke] P10 Speichern: %.0f ms (Einsammeln + Schreiben), %.0f KB gespeichert, %.0f KB JSON, %s" % [
			_save_ms, _save_kb, float(h.get("payload_size", 0)) / 1024.0, str(h.get("compression", ""))])
	_check(SaveCodec.errors.is_empty(), "Keine nicht speicherbaren Werte " + ", ".join(SaveCodec.errors))


# ---------------------------------------------------------------------------
# S2 Oberfläche
# ---------------------------------------------------------------------------

func _s2() -> void:
	var pm: Node = game.pause_menu
	game._open_pause_menu()
	pm.show_page("save")
	var panel: SaveLoadPanel = pm.get_save_panel()
	panel.async_save = false
	panel.set_name_text("Rauchtest Oberfläche")
	panel.press_save()
	_check(not panel.has_pending() and SaveManager.exists(SaveManager.slot_for_name("Rauchtest Oberfläche")),
			"Speichern über das Fenster (%s)" % SaveManager.slot_for_name("Rauchtest Oberfläche"))
	panel.set_name_text("Rauchtest Oberfläche")
	panel.press_save()
	_check(panel.has_pending(), "Überschreiben-Rückfrage erscheint")
	panel.confirm_pending()
	panel.refresh()
	var count := 0
	for r in panel.get_rows():
		if str(r["name"]) == "Rauchtest Oberfläche":
			count += 1
	_check(count == 1, "Liste enthält „Rauchtest Oberfläche“ genau einmal (%d)" % count)
	game.save_game("smoke_p10_tmp", "Rauchtest Temp", "manual", false)
	pm.show_page("load")
	var lp: SaveLoadPanel = pm.get_load_panel()
	var rows: Array = lp.get_rows()
	_check(rows.size() >= 2 and bool(rows[0]["compatible"]), "Ladeliste: %d Einträge, ladbar" % rows.size())
	var sorted := true
	var last := 9223372036854775807
	for e in SaveManager.list_saves():
		var at := int((e["header"] as Dictionary).get("saved_at", 0))
		sorted = sorted and at <= last
		last = at
	_check(sorted, "Ladeliste neueste zuerst")
	lp.press_delete("smoke_p10_tmp")
	_check(lp.has_pending(), "Löschen-Rückfrage erscheint")
	lp.confirm_pending()
	_check(not SaveManager.exists("smoke_p10_tmp"), "Spielstand gelöscht")
	# Einstellungen
	pm.show_page("settings")
	var form: SettingsForm = pm.get_settings_form()
	form.set_values(1.25, 5, 0.6)
	form.save_and_close()
	Settings.ui_scale = 1.0
	Settings.autosave_minutes = 10
	Settings.load_settings()
	_check(is_equal_approx(Settings.ui_scale, 1.25) and Settings.autosave_minutes == 5 \
			and is_equal_approx(Settings.get_volume("Master"), 0.6), "Einstellungen gespeichert und geladen")
	_check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("UI") >= 0
			and absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.6)) < 0.1, "Audio-Busse vorhanden, Lautstärke wirkt")
	var hud_layer: CanvasLayer = game.hud
	_check(is_equal_approx(hud_layer.scale.x, 1.25), "UI-Grösse 1,25 auf das HUD angewendet")
	Settings.reset_defaults()
	Settings.apply()
	_check(is_equal_approx(hud_layer.scale.x, 1.0), "UI-Grösse zurück auf 1")
	pm.show_page("main")
	pm.close()
	# Autospeichern reihum
	var slots: Array = []
	for i in 4:
		var slot := SaveManager.next_autosave_slot()
		slots.append(slot)
		game.save_game(slot, "Autospeicherung", "auto", false)
	var autos := 0
	for e in SaveManager.list_saves():
		if str(e["slot"]).begins_with(SaveManager.AUTO_PREFIX):
			autos += 1
	_check(autos == int(DataDB.cfg("save.autosave_slots", 3)) and slots[3] == slots[0],
			"Autospeichern reihum: %d Dateien, %s" % [autos, ", ".join(slots)])
	# Hilfe und Protokoll
	var hud: Node = game.hud
	hud.toggle_help()
	_check(hud.is_help_open(), "Hilfe (F1) offen")
	var listed := HelpPanel.listed_actions()
	var missing: Array = []
	for action in InputMap.get_actions():
		var a := str(action)
		if a.begins_with("ui_") or a.begins_with("debug_") or (a.begins_with("camera_") and a != "camera_home"):
			continue
		if not listed.has(a):
			missing.append(a)
	_check(missing.is_empty(), "Hilfe nennt alle Aktionen" + ("" if missing.is_empty() else " – es fehlen: " + str(missing)))
	hud.close_top_panel()
	hud.toggle_log()
	_check(hud.is_log_open() and hud.message_log.get_shown_count() > 0, "Protokoll (M) zeigt %d Meldungen" % hud.message_log.get_shown_count())
	hud.message_log.set_filter("danger")
	hud.message_log.set_filter("")
	hud.close_top_panel()
	_check(not hud.is_log_open(), "Esc schliesst das Protokoll")


# ---------------------------------------------------------------------------
# S3–S6 Rundlauf
# ---------------------------------------------------------------------------

## Nach dem Hauptlauf: Zwischenstand laden
func start_roundtrip() -> void:
	if not enabled or _snapshot.is_empty():
		if enabled:
			_fail("Kein Zwischenstand gespeichert (Lauf zu kurz?)")
		finished = true
		return
	GameSession.debug_verify_load = true
	var err := SaveManager.request_load("smoke_p10_mid")
	if not err.is_empty():
		_fail("Laden nicht möglich: " + err)
		finished = true
		return
	_rt_state = "loading_mid"
	_rt_wait_ms = Time.get_ticks_msec()
	game.request_reload()


## Rundlauf (jeder Frame, nach dem Hauptlauf)
func tick_roundtrip() -> void:
	if finished:
		return
	game = runner.get("_game")
	match _rt_state:
		"loading_mid", "loading_quick":
			if game == null or not is_instance_valid(game):
				return
			if game.get("_playing") != true:
				if Time.get_ticks_msec() - _rt_wait_ms > 120000:
					_fail("Laden dauert zu lange")
					_finish()
				return
			_load_ms = Time.get_ticks_msec() - _rt_wait_ms
			print("[smoke] P10 Laden gesamt %d ms (inkl. Weltgenerierung), Bericht: %s" % [_load_ms, str(game.last_load_report)])
			if _rt_state == "loading_mid":
				_s4()
				print("[smoke] P10 Arbeiter in Gebäuden nach dem Laden: %d" % _working_count())
				_cont_start = GameClock.game_time
				_cont_base = _continue_base()
				_rt_state = "continue"
			else:
				_compare(_quick_metrics, game.last_load_metrics, "Schnellladen")
				_quick_until = GameClock.game_time + 30.0
				_rt_state = "after_quick"
		"continue":
			var t := GameClock.game_time
			if not _cont_checked and t >= _cont_start + 10.0:
				_cont_checked = true
				_check_hanging()
			if t >= _cont_start + after:
				_s5_end()
				_s6_start()
		"after_quick":
			if GameClock.game_time >= _quick_until:
				_ok("30 s nach dem Schnellladen ohne Fehler")
				_finish()


func _s4() -> void:
	_compare(_snapshot, game.last_load_metrics, "Rundlauf")
	# Idempotenz: sofort nach dem Laden eingesammelt = geladen
	var loaded: Dictionary = game.last_loaded_data
	var check: Dictionary = game.last_load_check
	if loaded.is_empty() or check.is_empty():
		_fail("Keine Daten für den Idempotenz-Vergleich")
		return
	var a: Dictionary = SaveCodec.encode(loaded)
	var b: Dictionary = SaveCodec.encode(check)
	_normalize_units(a, b)
	var diff := PackedStringArray()
	var ignore := PackedStringArray(["data.clock.tick_accumulator", "data.kingdoms[*].income_rate*",
			"data.units[*].state", "data.units[*].timer", "data.systems.*.tick_acc", "data.game.camera*",
			"data.game.last_save_name"])
	SaveCodec.deep_diff(a, b, "data", diff, 20, 0.0001, ignore)
	# Betroffene Einheiten benennen (Typ, Reich, Befehl), damit der Verursacher erkennbar ist
	var named := {}
	var units_a: Array = a.get("units", [])
	for line in diff.duplicate():
		if not line.begins_with("data.units["):
			continue
		var idx := int(line.get_slice("[", 1).get_slice("]", 0))
		if named.has(idx) or idx < 0 or idx >= units_a.size():
			continue
		named[idx] = true
		var ud: Dictionary = units_a[idx]
		diff.append("  units[%d] = %s#%s Reich %s, Befehl „%s“" % [idx, str(ud.get("type_id", "?")), str(ud.get("uid", "?")),
				str(ud.get("kingdom_id", "?")), str(ud.get("command", ""))])
	_check(diff.is_empty(), "Idempotenz: geladen = sofort wieder eingesammelt" + ("" if diff.is_empty() else "\n  " + "\n  ".join(diff)))


## Einheiten im Gruppenmarsch und solche, die das CommandSystem neu losschickt, ohne Weg vergleichen
func _normalize_units(a: Dictionary, b: Dictionary) -> void:
	var by_uid := {}
	for u in b.get("units", []):
		by_uid[u.get("uid")] = u
	for u in a.get("units", []):
		var other: Variant = by_uid.get(u.get("uid"), null)
		if u.has("follows") or (other is Dictionary and not u.has("motion") and (other as Dictionary).has("motion")):
			u.erase("follows")
			u.erase("motion")
			if other is Dictionary:
				(other as Dictionary).erase("follows")
				(other as Dictionary).erase("motion")


func _compare(before: Dictionary, now: Dictionary, what: String) -> void:
	var diff := PackedStringArray()
	if absf(float(before["game_time"]) - float(now["game_time"])) > 0.01:
		diff.append("game_time %s ≠ %s" % [str(before["game_time"]), str(now["game_time"])])
	if int(before["uid_counter"]) != int(now["uid_counter"]):
		diff.append("uid_counter %d ≠ %d" % [int(before["uid_counter"]), int(now["uid_counter"])])
	var bk: Dictionary = before["kingdoms"]
	var nk: Dictionary = now["kingdoms"]
	for kid in bk:
		if not nk.has(kid):
			diff.append("Reich %s fehlt" % str(kid))
			continue
		var x: Dictionary = (bk[kid] as Dictionary).duplicate(true)
		var y: Dictionary = (nk[kid] as Dictionary).duplicate(true)
		var hx := float(x["hp_sum"])
		var hy := float(y["hp_sum"])
		if absf(hx - hy) > maxf(hx * 0.005, 0.5):
			diff.append("Reich %s Leben %.1f ≠ %.1f" % [str(kid), hx, hy])
		x.erase("hp_sum")
		y.erase("hp_sum")
		SaveCodec.deep_diff(x, y, "reich%s" % str(kid), diff, 30, 0.01)
	var bp: Dictionary = before["unit_pos"]
	var np: Dictionary = now["unit_pos"]
	var moved := 0
	for uid in bp:
		if not np.has(uid):
			diff.append("Einheit %s fehlt" % str(uid))
		elif (bp[uid] as Vector2).distance_to(np[uid]) > 1.0:
			moved += 1
	if moved > 0:
		diff.append("%d Einheiten an anderer Stelle" % moved)
	if np.size() != bp.size():
		diff.append("Einheiten %d ≠ %d" % [bp.size(), np.size()])
	for key in ["building_cells", "roads", "changed_cells", "rng", "extra"]:
		SaveCodec.deep_diff(before[key], now[key], key, diff, 30, 0.000001)
	_check(diff.is_empty(), "%s: Reiche, Gebäude, Einheiten, Ressourcen, Helden, Diplomatie, KI gleich (%d Einheiten, %d Gebäude)%s" % [
			what, np.size(), (now["building_cells"] as Dictionary).size(), "" if diff.is_empty() else "\n  " + "\n  ".join(diff.slice(0, 20))])


## Einheiten mit Marschbefehl, die weder laufen noch auf einen Weg warten und nicht am Ziel sind
func _check_hanging() -> void:
	var ts := float(game.world.tile_size)
	var hanging: Array = []
	for u in game.unit_system.units:
		if not ["move", "attack_move", "travel", "return", "flee"].has(u.command):
			continue
		if u.moving or u.path_pending or u.inside != null or u.target != null:
			continue
		# Mitglieder eines Gruppenmarschs folgen ihrem Anführer (stehen kurz, wenn sie an ihrem
		# Platz neben ihm sind) – geprüft wird der Anführer
		if is_instance_valid(u.follow_leader) and (u.follow_leader as Unit).is_alive():
			continue
		if u.position.distance_to(u.command_pos) > ts:
			hanging.append("%s#%d %s (%.0f Kacheln vom Ziel, Weg %s, Gebiet %d, Reich %d, folgt %s, Takt %s)" % [u.type_id, u.uid, u.command,
					u.position.distance_to(u.command_pos) / ts, u.path_fail if u.path_fail != "" else "-",
					game.world.get_owner(game.world.world_to_cell(u.command_pos)), u.kingdom.id,
					str(u.follow_leader.uid) if is_instance_valid(u.follow_leader) else "-",
					str((u.kingdom.ai_state.get("wave", {}) as Dictionary).get("state", "-"))])
	_check(hanging.is_empty(), "10 s nach dem Laden keine hängenden Einheiten" + ("" if hanging.is_empty() else ": " + str(hanging.slice(0, 10))))


## Arbeiter aller Reiche im Zustand WORKING in ihren Gebäuden
func _working_count() -> int:
	var n := 0
	for k in game.kingdoms:
		for b in k.buildings:
			for w in b.workers:
				if is_instance_valid(w) and w.state == Unit.State.WORKING:
					n += 1
	return n


func _continue_base() -> Dictionary:
	var pos := {}
	for u in game.unit_system.units:
		pos[u.uid] = u.position
	var think := 0
	for k in game.kingdoms:
		think += int(k.ai_state.get("think_count", 0))
	return {"wood": game.player.get_amount("wood"), "food": game.player.get_amount("food"), "pos": pos, "think": think}


func _s5_end() -> void:
	var p: Kingdom = game.player
	_check(not is_equal_approx(p.get_amount("wood"), float(_cont_base["wood"])) or not is_equal_approx(p.get_amount("food"), float(_cont_base["food"])),
			"Wirtschaft läuft nach dem Laden (Holz %.0f → %.0f, Nahrung %.0f → %.0f)" % [float(_cont_base["wood"]), p.get_amount("wood"),
			float(_cont_base["food"]), p.get_amount("food")])
	var think := 0
	var has_ai := false
	for k in game.kingdoms:
		think += int(k.ai_state.get("think_count", 0))
		has_ai = has_ai or k.controller == "ai"
	if has_ai:
		_check(think > int(_cont_base["think"]), "KI denkt nach dem Laden weiter (%d → %d)" % [int(_cont_base["think"]), think])
	var pos: Dictionary = _cont_base["pos"]
	var moved := 0
	var total := 0
	for u in game.unit_system.units:
		if pos.has(u.uid):
			total += 1
			if (pos[u.uid] as Vector2).distance_to(u.position) > 4.0:
				moved += 1
	_check(total > 0 and moved * 10 >= total, "%d von %d Einheiten haben sich bewegt" % [moved, total])
	var working := _working_count()
	_check(working > 0 or _snapshot_working == 0, "Arbeiter arbeiten wieder in Gebäuden (%d, beim Speichern %d)" % [working, _snapshot_working])
	for rec in p.heroes:
		var u: Variant = game.find_by_uid(int(rec["unit_uid"]))
		if not bool(rec["dead"]) and u is Unit:
			_check(not (u as Unit).hero_mods.is_empty(), "Held %s hat seine Werte (Stufe %d)" % [str(rec["name"]), int(rec["level"])])
			break
	_ok("%.0f s nach dem Laden weitergelaufen" % after)


func _s6_start() -> void:
	var err: String = game.quick_save(false)
	_check(err.is_empty(), "Schnellspeichern (F5)")
	_quick_metrics = SaveGame.metrics(game)
	_rt_state = "loading_quick"
	_rt_wait_ms = Time.get_ticks_msec()
	err = game.quick_load()
	if not err.is_empty():
		_fail("Schnellladen: " + err)
		_finish()


func _finish() -> void:
	finished = true
	_clear_dir()
	if FileAccess.file_exists(SETTINGS_FILE):
		DirAccess.remove_absolute(SETTINGS_FILE)


func _clear_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return
	for f in DirAccess.get_files_at(SAVE_DIR):
		DirAccess.remove_absolute(SAVE_DIR + f)


func report() -> void:
	if not enabled:
		return
	print("[smoke] Phase 10: %s (Speichern %.0f ms, %.0f KB, Laden %d ms)" % [
			"OK" if errors == 0 else "%d Fehler" % errors, _save_ms, _save_kb, _load_ms])
