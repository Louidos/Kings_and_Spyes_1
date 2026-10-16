## Balancing-Werkzeug (Phase 10): lange Läufe ohne Fenster mit echter KI.
## Aktiv mit balance=1 (setzt p7=natural, p8=natural, passive=1, p10=off, wenn nicht anders angegeben).
## Gibt alle sample= Spielsekunden (Standard 600) je Reich eine Zeile "[balance] …" aus, dazu
## Leistungswerte (KI-Denkzeit, Simulationsschritt, Bildzeit) und am Ende die Grösse aller
## Listen und Wörterbücher der Systeme (Langzeit-Hygiene: nichts darf ohne Grenze wachsen).
## Aufruf: tests/run_balance.sh oder
##   godot --headless res://tests/smoke_test.tscn -- balance=1 faction=good difficulty=normal size=medium seconds=10800
extends RefCounted

var game: Node
var sample := 600.0
var finished := false
## immortal=1: Burg und König des Spielers werden jeden Frame geheilt – der Lauf geht über die volle
## Dauer weiter (Wachstum der KI, wiederholte Wellen, Leistung), auch wenn der passive Spieler sonst fiele
var immortal := false

var _next_sample := 0.0
var _events_player := 0
var _events_all := 0
var _first_event_player := -1.0
var _waves_on_player := 0
var _first_wave_player := -1.0
var _defected := 0
var _sat_sum := 0.0
var _sat_n := 0
var _sat_min := 100.0
var _sat_max := 0.0
var _think_prev := {"thinks": 0, "usec": 0}
var _tick_prev := {"n": 0, "usec": 0}
var _frame_usec_sum := 0
var _frame_n := 0
var _frame_usec_max := 0
var _sizes_half: Dictionary = {}
var _seconds := 10800.0
var _wild_start := 0
var _lairs_start := 0
## Rechenzeit je Empfänger von GameClock.sim_tick: Name -> [Summe µs, Höchstwert µs]
var _tick_cost: Dictionary = {}
## Meilensteine (Spielsekunde -> geprüft): Ausbaustufen der KI
var _milestones_done := {}


func _init(p_game: Node, args: Dictionary) -> void:
	game = p_game
	sample = float(args.get("sample", "600"))
	immortal = str(args.get("immortal", "0")) == "1"
	_seconds = float(args.get("seconds", "10800"))
	var ev: EventSystem = game.event_system
	ev.event_started.connect(_on_event_started)
	(game.ai_system as AISystem).wave_started.connect(_on_wave_started)
	(game.satisfaction_system as SatisfactionSystem).defected.connect(
			func(_u: Unit, from_kingdom: Kingdom, _kind: String, _dest: Kingdom) -> void:
				if from_kingdom == game.player:
					_defected += 1)
	_wrap_sim_tick()
	_wild_start = (game.wild as Kingdom).units.size()
	_lairs_start = (game.monster_system as MonsterSystem).lairs.size()
	print("[balance] Start: %s, Schwierigkeit %s, Karte %s, Seed %s, Monster %d, Lager %d" % [GameSession.faction_id,
			GameSession.difficulty_id, GameSession.map_size_id, GameSession.seed_text,
			_wild_start, _lairs_start])


## Jeden Empfänger des Simulationstakts mit einer Zeitmessung umhüllen (nur im Balancing-Lauf)
func _wrap_sim_tick() -> void:
	for c in GameClock.sim_tick.get_connections():
		var cb: Callable = c["callable"]
		var obj := cb.get_object()
		var label := "%s.%s" % [obj.name if obj is Node else obj.get_class(), cb.get_method()]
		GameClock.sim_tick.disconnect(cb)
		_tick_cost[label] = [0, 0]
		GameClock.sim_tick.connect(func(dt: float) -> void:
			var t0 := Time.get_ticks_usec()
			cb.call(dt)
			var used := Time.get_ticks_usec() - t0
			var e: Array = _tick_cost[label]
			e[0] = int(e[0]) + used
			e[1] = maxi(int(e[1]), used))


func _on_event_started(ev: Dictionary) -> void:
	_events_all += 1
	if (ev.get("target_ids", []) as Array).has((game.player as Kingdom).id):
		_events_player += 1
		if _first_event_player < 0.0:
			_first_event_player = GameClock.game_time
		print("[balance] Ereignis beim Spieler t=%.0f: %s" % [GameClock.game_time, str(ev.get("event_id", "?"))])


func _on_wave_started(_k: Kingdom, target: Kingdom, size: int, _rally: Vector2) -> void:
	if target == game.player:
		_waves_on_player += 1
		if _first_wave_player < 0.0:
			_first_wave_player = GameClock.game_time
		print("[balance] Welle gegen den Spieler t=%.0f von %s (%d Einheiten)" % [GameClock.game_time, _k.display_name, size])


## Jeden Frame aufrufen
func tick(t: float) -> void:
	if finished:
		return
	var frame_usec := int(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0)
	_frame_usec_sum += frame_usec
	_frame_n += 1
	_frame_usec_max = maxi(_frame_usec_max, frame_usec)
	var player: Kingdom = game.player
	if immortal:
		if is_instance_valid(player.castle):
			player.castle.hp = player.castle.max_hp
		if is_instance_valid(player.king):
			player.king.hp = player.king.max_hp
	if player.defeated:
		print("[balance] Spieler gefallen t=%.0f (%s)" % [t, str(player.flags.get("defeat_reason", "?"))])
		report(t)
		return
	if t >= _next_sample:
		_next_sample += sample
		_sample(t)
	_check_milestones(t)
	if _sizes_half.is_empty() and t >= _seconds * 0.5:
		_sizes_half = _collect_sizes()


func _sample(t: float) -> void:
	var g := game
	var sat: SatisfactionSystem = g.satisfaction_system
	var player: Kingdom = g.player
	var avg := sat.get_average(player)
	if avg >= 0.0:
		_sat_sum += avg
		_sat_n += 1
		_sat_min = minf(_sat_min, avg)
		_sat_max = maxf(_sat_max, avg)
	for k in g.kingdoms:
		var kk: Kingdom = k
		if kk.controller != "ai" or kk.defeated:
			continue
		var brain: AIBrain = g.ai_system.get_brain(kk)
		var army := brain.army_units().size() if brain != null else 0
		var target := AIMilitary.army_target(brain, t) if brain != null else 0
		var log_d: Dictionary = kk.ai_state.get("log", {})
		print("[balance] t=%5.0f KI %d %s: Burgstufe %d, Bewohner %d (Bewerber %d), Gebäude %d (ausgebaut %d), Einheiten %d, Armee %d/%d, Wellen %d (Spieler ab %s), Forschung %d, Helden %d, Zufr. %.0f, %s" % [
				t, kk.id, kk.display_name, kk.get_castle_level(), kk.get_population(), int(kk.stats.get("recruits_accepted", 0)), kk.buildings.size(), (g.building_system as BuildingSystem).count_buildings_at_level(kk, "", 2),
				kk.units.size(), army, target, int(kk.ai_state.get("waves_sent", 0)),
				str(log_d.get("first_player_wave", "-")), kk.researched.size(), kk.heroes.size(), sat.get_average(kk),
				DataDB.cost_to_text(kk.resources)])
	# Zusammensetzung der KI-Reiche (Gebäude je Typ ohne Mauern, Berufe, Sammelprobleme)
	for k in g.kingdoms:
		var kk: Kingdom = k
		if kk.controller != "ai" or kk.defeated:
			continue
		var types := {}
		for bld in kk.buildings:
			if not bld.is_segment:
				types[bld.get_def_id()] = int(types.get(bld.get_def_id(), 0)) + 1
		var jobs := {}
		var problems: PackedStringArray = []
		for j in DataDB.jobs:
			var jid := str((j as Dictionary)["id"])
			var n: int = g.work_system.get_job_count(kk, jid)
			if n > 0:
				jobs[jid] = n
			var p: String = g.work_system.get_job_problem(kk, jid)
			if not p.is_empty():
				problems.append("%s: %s" % [jid, p])
		var idle_info: PackedStringArray = []
		for u in kk.units:
			if u.job_id == "idle" and u.role == "worker":
				idle_info.append("%s/%s/%s" % [u.command, str(u.state), u.problem])
		print("[balance] t=%5.0f KI %d Aufbau: %s | Berufe %s%s%s" % [t, kk.id, str(types), str(jobs),
				"" if problems.is_empty() else " | Probleme " + "; ".join(problems),
				"" if idle_info.is_empty() else " | Unbeschäftigt " + ", ".join(idle_info)])
	var think: Dictionary = g.ai_system.stats
	var dn := int(think["thinks"]) - int(_think_prev["thinks"])
	var du := int(think["think_usec_total"]) - int(_think_prev["usec"])
	_think_prev = {"thinks": int(think["thinks"]), "usec": int(think["think_usec_total"])}
	var tn := GameClock.tick_count - int(_tick_prev["n"])
	var tu := GameClock.tick_usec_total - int(_tick_prev["usec"])
	_tick_prev = {"n": GameClock.tick_count, "usec": GameClock.tick_usec_total}
	var units_total := 0
	for k in g.kingdoms:
		units_total += (k as Kingdom).units.size()
	print("[balance] t=%5.0f Spieler: Gebäude %d, Einheiten %d, Zufr. %.0f, Ereignisse %d, Wellen %d, Überläufer %d | Einheiten gesamt %d, Monster %d, Lager %d, Streifzüge %s | KI Ø %.2f ms, Schritt Ø %.2f ms (max %.1f), Bild Ø %.2f ms, verworfen %d" % [
			t, player.buildings.size(), player.units.size(), avg, _events_player, _waves_on_player, _defected, units_total,
			(g.wild as Kingdom).units.size(), (g.monster_system as MonsterSystem).lairs.size(),
			str((g.monster_system as MonsterSystem).raid_stats.get("raids", 0)),
			float(du) / maxi(dn, 1) / 1000.0, float(tu) / maxi(tn, 1) / 1000.0, GameClock.tick_usec_max / 1000.0,
			float(_frame_usec_sum) / maxi(_frame_n, 1) / 1000.0, GameClock.dropped_ticks])


## Prüfungen zu festen Spielzeiten (Fehler als push_error, run_balance.sh meldet sie):
## nach 10 Minuten hat kein KI-Reich Gebäude ab Burgstufe 3, nach 30 Minuten mindestens eines ein
## ausgebautes Gebäude, nach 40 Minuten mindestens eines Burgstufe 3
func _check_milestones(t: float) -> void:
	if t >= 600.0 and not _milestones_done.has(600):
		_milestones_done[600] = true
		var early: PackedStringArray = []
		for k in game.kingdoms:
			var kk: Kingdom = k
			if kk.controller != "ai":
				continue
			for b in kk.buildings:
				if int(b.def.get("requires_castle_level", 1)) >= 3 or (b != kk.castle and b.level >= 3):
					early.append("%s: %s" % [kk.display_name, b.get_display_name()])
		if early.is_empty():
			print("[balance] PRÜFUNG OK t=600: kein KI-Reich hat Gebäude ab Burgstufe 3 (Burgstufen %s)" % _castle_levels())
		else:
			push_error("[balance] PRÜFUNG FEHLER t=600: Gebäude ab Burgstufe 3 zu früh (%s)" % ", ".join(early))
	if t >= 2400.0 and not _milestones_done.has(2400):
		_milestones_done[2400] = true
		var best := 0
		for k in game.kingdoms:
			if (k as Kingdom).controller == "ai" and not (k as Kingdom).defeated:
				best = maxi(best, (k as Kingdom).get_castle_level())
		# Ohne Bewerber (recruits=off): das natürliche Wachstum allein reicht für Burgstufe 2
		if game.get("recruit_system") != null and not game.recruit_system.enabled:
			if best >= 2:
				print("[balance] PRÜFUNG OK t=2400: ohne Bewerber erreicht die KI Burgstufe 2 (%s)" % _castle_levels())
			else:
				push_error("[balance] PRÜFUNG FEHLER t=2400: ohne Bewerber keine Burgstufe 2 (%s)" % _castle_levels())
		elif best >= 3:
			print("[balance] PRÜFUNG OK t=2400: KI erreicht Burgstufe 3 (%s)" % _castle_levels())
		else:
			push_error("[balance] PRÜFUNG FEHLER t=2400: kein KI-Reich auf Burgstufe 3 (%s)" % _castle_levels())
	if t >= 1800.0 and not _milestones_done.has(1800):
		_milestones_done[1800] = true
		var best := 0
		var names: PackedStringArray = []
		for k in game.kingdoms:
			var kk: Kingdom = k
			if kk.controller != "ai" or kk.defeated:
				continue
			var n := (game.building_system as BuildingSystem).count_buildings_at_level(kk, "", 2)
			best = maxi(best, n)
			names.append("%s %d" % [kk.display_name, n])
		if best > 0:
			print("[balance] PRÜFUNG OK t=1800: ausgebaute Gebäude der KI (%s)" % ", ".join(names))
		else:
			push_error("[balance] PRÜFUNG FEHLER t=1800: kein KI-Reich hat ein ausgebautes Gebäude (%s)" % ", ".join(names))


## "Reich 2, Reich 3" mit Burgstufe je KI-Reich
func _castle_levels() -> String:
	var parts: PackedStringArray = []
	for k in game.kingdoms:
		var kk: Kingdom = k
		if kk.controller == "ai":
			parts.append("%s %d%s" % [kk.display_name, kk.get_castle_level(), " (gefallen)" if kk.defeated else ""])
	return ", ".join(parts)


## Grösse aller Listen/Wörterbücher (Skriptvariablen) der Systeme und von Notify
func _collect_sizes() -> Dictionary:
	var out := {}
	var objs := {"Notify": Notify}
	for node in game.get_node("Systems").get_children():
		objs[node.name] = node
	for key in objs:
		var o: Object = objs[key]
		for p in o.get_property_list():
			if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var v: Variant = o.get(str(p["name"]))
			if v is Array or v is Dictionary:
				out["%s.%s" % [key, str(p["name"])]] = (v as Array).size() if v is Array else (v as Dictionary).size()
	return out


func report(t: float) -> void:
	if finished:
		return
	finished = true
	_sample(t)
	var think: Dictionary = game.ai_system.stats
	print("[balance] ERGEBNIS t=%.0f: Ereignisse Spieler %d (erstes %s), alle %d | Wellen gegen Spieler %d (erste %s) | Zufriedenheit Ø %.0f (%.0f–%.0f) | Überläufer %d | Monster %d→%d, Lager %d→%d, Streifzüge %s" % [
			t, _events_player, "-" if _first_event_player < 0.0 else "%.0f s" % _first_event_player, _events_all, _waves_on_player,
			"-" if _first_wave_player < 0.0 else "%.0f s" % _first_wave_player, _sat_sum / maxi(_sat_n, 1), _sat_min, _sat_max,
			_defected, _wild_start, (game.wild as Kingdom).units.size(), _lairs_start, (game.monster_system as MonsterSystem).lairs.size(),
			str((game.monster_system as MonsterSystem).raid_stats)])
	print("[balance] LEISTUNG: KI-Denkzeit Ø %.2f ms, max %.1f ms (%d) | Simulationsschritt Ø %.2f ms, max %.1f ms | Bild Ø %.2f ms, max %.1f ms | verworfene Schritte %d" % [
			float(think["think_usec_total"]) / maxi(int(think["thinks"]), 1) / 1000.0, int(think["think_usec_max"]) / 1000.0,
			int(think["thinks"]), float(GameClock.tick_usec_total) / maxi(GameClock.tick_count, 1) / 1000.0,
			GameClock.tick_usec_max / 1000.0, float(_frame_usec_sum) / maxi(_frame_n, 1) / 1000.0, _frame_usec_max / 1000.0,
			GameClock.dropped_ticks])
	var costs: Array = []
	for label in _tick_cost:
		costs.append([label, int((_tick_cost[label] as Array)[0]), int((_tick_cost[label] as Array)[1])])
	costs.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	var cost_parts: PackedStringArray = []
	for e in costs.slice(0, 10):
		cost_parts.append("%s %.2f (max %.1f)" % [str(e[0]), float(e[1]) / maxi(GameClock.tick_count, 1) / 1000.0, int(e[2]) / 1000.0])
	print("[balance] TAKT je Schritt (ms): " + ", ".join(cost_parts))
	var sizes := _collect_sizes()
	var parts: PackedStringArray = []
	var grown: PackedStringArray = []
	for key in sizes:
		var n := int(sizes[key])
		if n >= 20:
			parts.append("%s %d" % [key, n])
		if _sizes_half.has(key):
			var h := int(_sizes_half[key])
			if n >= 50 and n > h * 2:
				grown.append("%s %d→%d" % [key, h, n])
	print("[balance] LISTEN (≥ 20): " + ", ".join(parts))
	print("[balance] LISTEN gewachsen (2. Hälfte > ×2): " + ("keine" if grown.is_empty() else ", ".join(grown)))
