## Rauchtest Phase 6 (gestartet von tests/smoke_test.gd): prüft über die
## öffentlichen Schnittstellen der Systeme Geschenk, Handel, Bündnis samt
## Freischaltung, Kündigung, Krieg mit Angriff und Bote, Abfangen, Aufnahme und
## Eroberung. Dazu ein Test der Oberfläche (ab t = 150 s, nach dem Heldentest):
## Diplomatiefenster öffnen (Forschung schliesst sich), Dorf wählen, Geschenk,
## Bündnis und Tausch über die Knöpfe des Fensters, Debug-Bote, Auswahlfenster
## mit Dorfzeile und Knopf "Diplomatie (N)", Gebietsname im Infobereich,
## Kriegsbestätigung per zweitem Rechtsklick und Botensymbol auf der Minikarte.
## Fehler erscheinen als "ERROR: [smoke] Phase 6 FEHLER: …" (push_error),
## damit run_smoke.sh fehlschlägt. Bildschirmfotos mit shots=<ordner> (nur mit
## echtem Fenster, z. B. unter xvfb-run): <fraktion>_p6_*.png.
extends RefCounted

## Ab dieser Spielzeit läuft der Oberflächentest (wenn ui_ready gesetzt ist)
const UI_TEST_TIME := 150.0

## Vom Rauchtest gesetzt: der Heldentest ist fertig (die Fenster sind frei)
var ui_ready := false

var _game: Node
var _stage := 0
var _errors := 0
var _a: Kingdom = null
var _b: Kingdom = null
var _c: Kingdom = null
var _d: Kingdom = null
## Unbeteiligtes Dorf (für den Ruf-Verlust durch die Eroberung) und sein Ruf davor
var _uninvolved: Kingdom = null
var _uninvolved_rep := 0.0
var _test_messenger_uid := 0
## Weiteres Dorf für den Schutzvertrag (null, wenn es keins gibt)
var _e: Kingdom = null
## Ruf bei A zu Beginn des Handelsvertrags und in Stufe 5 (danach nur noch Vertragsgewinn)
var _trade_rep := 0.0
var _trade_rep_s5 := 0.0
## Oberflächentest: Schritt (-1 = fertig), nächster Schritt ab Spielzeit, Testdorf
var _ui_step := 0
var _ui_wait_until := 0.0
var _ui_village: Kingdom = null
var _ui_debug_was_visible := false
var _ui_units: Array = []


func _init(game: Node) -> void:
	_game = game


## Jeden Frame aufrufen (Spielzeit t)
func tick(t: float) -> void:
	if _stage >= 5 and _stage != 99 and _ui_step >= 0 and ui_ready and t >= UI_TEST_TIME and t >= _ui_wait_until:
		_ui_test()
	match _stage:
		0:
			_stage = 1 if _s0() else 99
		1:
			if t >= 5.0:
				_s1()
				_stage = 2
		2:
			if t >= 8.0:
				_s2()
				_stage = 3
		3:
			if t >= 10.0:
				_s3()
				_stage = 4
		4:
			if t >= 13.0:
				_s4()
				_stage = 5
		5:
			if t >= 400.0:
				_s5()
				_stage = 6
		6:
			if t >= 402.0:
				_s6()
				_stage = 7


func _check(cond: bool, text: String) -> void:
	if cond:
		print("[smoke] Phase 6 OK: " + text)
	else:
		_errors += 1
		push_error("[smoke] Phase 6 FEHLER: " + text)


# ---------------------------------------------------------------------------
# Stufen
# ---------------------------------------------------------------------------

## S0: Dörfer und Reichsplätze ausgeben, Testdörfer wählen, Rohstoffe geben
func _s0() -> bool:
	var g := _game
	var vs: VillageSystem = g.village_system
	var player: Kingdom = g.player
	var villages := vs.get_villages()
	var sites: PackedStringArray = []
	for s in g.world.get_sites("kingdom"):
		sites.append("%s (%s)" % [str(s["cell"]), str(s["biome"])])
	print("[smoke] Reichsplätze: %s" % ", ".join(sites))
	for v in villages:
		var rec := vs.get_record(v)
		print("[smoke] Dorf %d %s (%s) bei %s, Grösse %d, Miliz %d, Ruf Spieler %+.0f" % [v.id, v.display_name,
				str(rec["people_id"]), str(rec["center"]), int(rec["size"]), vs.get_militia(v).size(),
				g.diplomacy_system.get_reputation(v, player)])
	if villages.size() < 4:
		print("[smoke] Phase 6: nur %d Dörfer – Prüfungen übersprungen" % villages.size())
		return false
	_check(vs.get_hall(villages[0]) != null and not vs.get_militia(villages[0]).is_empty(),
			"Dörfer haben Dorfzentrum und Miliz")
	var from: Vector2 = player.castle.get_center()
	var sorted := villages.duplicate()
	sorted.sort_custom(func(x: Kingdom, y: Kingdom) -> bool:
		return from.distance_to(vs.get_center(x)) < from.distance_to(vs.get_center(y)))
	_a = sorted[0]
	var max_d := float(DataDB.diplo("messenger.max_village_distance", 120)) * float(g.world.tile_size)
	# B: ein Dorf, das A (bleibt selbstständig) in Botenreichweite hat; sonst irgendein Nachbar
	for v in sorted.slice(1):
		if vs.get_center(v).distance_to(vs.get_center(_a)) <= max_d:
			_b = v
			break
	if _b == null:
		for v in sorted.slice(1):
			for w in villages:
				if w != v and vs.get_center(v).distance_to(vs.get_center(w)) <= max_d:
					_b = v
					break
			if _b != null:
				break
	if _b == null:
		_b = sorted[1]
	var rest: Array = []
	for v in sorted:
		if v != _a and v != _b:
			rest.append(v)
	_c = rest[0]
	_d = rest[1]
	for v in rest.slice(2):
		if _uninvolved == null:
			_uninvolved = v
		elif _e == null:
			_e = v
	if _uninvolved == null:
		_uninvolved = _a
	print("[smoke] Phase 6: A=%s, B=%s, C=%s, D=%s, unbeteiligt=%s" % [_a.display_name, _b.display_name,
			_c.display_name, _d.display_name, _uninvolved.display_name])
	for r in DataDB.resources:
		player.add_resource(str(r["id"]), 2000.0)
	_check_gather_territory()
	return true


## Sammler des Spielers suchen keine Vorkommen im Gebiet eines Dorfs (WorkSystem)
func _check_gather_territory() -> void:
	var g := _game
	var ws: WorkSystem = g.work_system
	var player: Kingdom = g.player
	var center: Vector2i = g.world.world_to_cell(g.village_system.get_center(_a))
	var inside := 0
	var foreign := 0
	for j in DataDB.jobs:
		var mask: PackedByteArray = (j as Dictionary).get("deposit_mask", PackedByteArray())
		if mask.is_empty():
			continue
		var free_cell := ws._spiral_find(center, 8, mask)
		if free_cell.x >= 0 and g.world.get_owner(free_cell) == _a.id:
			inside += 1
		ws._search_kingdom_id = player.id
		var cell := ws._spiral_find(center, 8, mask)
		ws._search_kingdom_id = 0
		if cell.x >= 0 and g.world.get_owner(cell) != 0 and g.world.get_owner(cell) != player.id:
			foreign += 1
	_check(foreign == 0, "Sammler meiden das Gebiet von %s (%d Berufe fänden dort sonst etwas)" % [_a.display_name, inside])


## S1: Geschenk, Handel, Bündnis, Kündigung, Aufnahme, Krieg mit Angriff
func _s1() -> void:
	var g := _game
	var ds: DiplomacySystem = g.diplomacy_system
	var vs: VillageSystem = g.village_system
	var player: Kingdom = g.player
	# 1. Geschenk
	var before := ds.get_reputation(_a, player)
	var preview := ds.preview_gift(player, _a, {"food": 200})
	var gift_ok := ds.give_gift(player, _a, {"food": 200})
	_check(gift_ok and ds.get_reputation(_a, player) > before, "Geschenk an %s: Ruf %+.1f → %+.1f (Vorschau %+.1f)" % [
			_a.display_name, before, ds.get_reputation(_a, player), float(preview["gain"])])
	# 2. Handel (Ware mit Vorrat im Dorf) und Tageslimit
	var got := 0.0
	var get_res := ""
	var last_reason := ""
	for r in DataDB.resources:
		var res_id := str(r["id"])
		if res_id == "wood":
			continue
		var q := ds.get_trade_quote(player, _a, "wood", 50.0, res_id)
		last_reason = str(q["reason"])
		if bool(q["ok"]):
			get_res = res_id
			got = ds.trade(player, _a, "wood", 50.0, res_id)
			break
	_check(got > 0.0, "Handel mit %s: 50 Holz → %d %s %s" % [_a.display_name, roundi(got),
			str(DataDB.get_resource(get_res).get("name", get_res)), last_reason])
	var big := ds.get_trade_quote(player, _a, "wood", 5000.0, get_res if not get_res.is_empty() else "stone")
	_check(not bool(big["ok"]), "Tausch über dem Tageslimit abgelehnt (%s)" % str(big["reason"]))
	# 3. Bündnis samt Freischaltung der Spezialeinheit
	var special := str(vs.get_people(_a).get("special_unit", ""))
	ds.debug_set_reputation(_a, player, 75.0)
	var offer := ds.get_treaty_offer(player, _a, "alliance")
	var answer := ds.propose_treaty(player, _a, "alliance")
	_check(answer.is_empty() and g.are_allied(player, _a) and player.has_unlock("summon:barracks:" + special),
			"Bündnis mit %s (Chance %d %%), Kaserne: %s %s" % [_a.display_name, roundi(float(offer["chance"]) * 100.0),
			special, answer])
	var barracks: Building = null
	for b in player.buildings:
		if str(b.def.get("id", "")) == "barracks" and b.constructed:
			barracks = b
	if barracks != null:
		var offered := false
		for def in g.summon_system.get_options(barracks):
			if str(def.get("id", "")) == special:
				offered = true
		_check(offered, "Kaserne bietet %s an" % special)
	# 4. Kündigung
	var cancelled: bool = ds.cancel_treaty(player, _a)
	_check(cancelled and not player.has_unlock("summon:barracks:" + special) and not g.are_allied(player, _a)
			and not g.are_hostile(player, _a), "Bündnis gekündigt: Freischaltung entzogen, Frieden")
	# 5. Aufnahme
	ds.debug_set_reputation(_c, player, 80.0)
	var info := ds.can_annex(player, _c)
	var militia_before := vs.get_militia(_c).size()
	var annexed := ds.annex(player, _c)
	var hall := vs.get_hall(_c)
	var player_militia := 0
	for u in player.units:
		if (u as Unit).tier == "militia":
			player_militia += 1
	_check(annexed and str(info["mode"]) == "devoted" and hall != null and hall.kingdom == player
			and str(vs.get_record(_c)["status"]) == "annexed" and g.world.get_owner(hall.cell) == player.id
			and player_militia >= militia_before and militia_before > 0 and _c.units.is_empty(),
			"Aufnahme von %s: Dorfzentrum, Gebiet und %d Milizen gehören dem Spieler" % [_c.display_name, player_militia])
	_check(not vs.get_annexed_text(hall).is_empty() if hall != null else false, "Aufgenommenes Dorf: %s" % (
			vs.get_annexed_text(hall) if hall != null else "-"))
	# 6. Krieg und Angriff auf B
	ds.declare_war(player, _b)
	var hall_b := vs.get_hall(_b)
	if hall_b != null:
		g.combat_system.apply_damage(hall_b, 50.0, null, player, "event")
	_check(g.are_hostile(player, _b) and hall_b != null, "Krieg mit %s, Dorfzentrum angegriffen (Ruf %+.0f)" % [
			_b.display_name, ds.get_reputation(_b, player)])


## S2: Bote unterwegs? Abfangen; dazu ein Testbote von D nach A
func _s2() -> void:
	var g := _game
	var ms: MessengerSystem = g.messenger_system
	var vs: VillageSystem = g.village_system
	var player: Kingdom = g.player
	var target: Unit = null
	for u in ms.get_messengers():
		var rec := ms.get_record(u)
		if int(rec["about_id"]) == player.id and int(rec["sender_id"]) == _b.id:
			target = u
	_check(int(ms.stats["sent"]) >= 1 and target != null, "%s schickt einen Boten (gesendet %d)" % [_b.display_name,
			int(ms.stats["sent"])])
	if target != null:
		var receiver: Kingdom = g.get_kingdom(int(ms.get_record(target)["receiver_id"]))
		print("[smoke] Phase 6: Bote von %s nach %s wird abgefangen" % [_b.display_name,
				receiver.display_name if receiver != null else "?"])
		g.combat_system.apply_damage(target, 9999.0, null, player, "event")
	# Eine Miliz von A fällt (ohne Täter): das Dorf ersetzt sie später aus seinem Vorrat
	var militia_a := vs.get_militia(_a)
	if not militia_a.is_empty():
		g.combat_system.apply_damage(militia_a[0], 9999.0, null, null, "event")
	var hall_d := vs.get_hall(_d)
	if hall_d != null:
		var test := ms.send_messenger(_d, hall_d.get_approach_point(vs.get_center(_a)), _a, player)
		_check(test != null and test.command == "travel", "Testbote von %s nach %s unterwegs" % [_d.display_name, _a.display_name])
		if test != null:
			_test_messenger_uid = test.uid


## S3: Abfangen gezählt, Ruf-Verlauf; Eroberung von D
func _s3() -> void:
	var g := _game
	var ms: MessengerSystem = g.messenger_system
	var ds: DiplomacySystem = g.diplomacy_system
	var vs: VillageSystem = g.village_system
	var player: Kingdom = g.player
	var found := false
	for e in ds.get_history(_b, player):
		if str(e["reason"]) == "Bote getötet":
			found = true
	_check(int(ms.stats["intercepted"]) >= 1 and found, "Bote abgefangen (abgefangen %d), Verlauf von %s: „Bote getötet“" % [
			int(ms.stats["intercepted"]), _b.display_name])
	ds.declare_war(player, _d)
	if vs.is_village(_uninvolved):
		_uninvolved_rep = ds.get_reputation(_uninvolved, player)
	var hall_d := vs.get_hall(_d)
	if hall_d != null:
		g.combat_system.apply_damage(hall_d, hall_d.hp + 10.0, null, player, "event")


## S4: D erobert, Ruf eines unbeteiligten Dorfs gesunken
func _s4() -> void:
	var g := _game
	var ds: DiplomacySystem = g.diplomacy_system
	var vs: VillageSystem = g.village_system
	var player: Kingdom = g.player
	var hall := vs.get_hall(_d)
	_check(str(vs.get_record(_d)["status"]) == "conquered" and hall != null and hall.kingdom == player and _d.defeated
			and hall.hp > 0.0, "Eroberung von %s: Dorfzentrum gehört dem Spieler (%d/%d Leben)" % [_d.display_name,
			roundi(hall.hp) if hall != null else 0, roundi(hall.max_hp) if hall != null else 0])
	if vs.is_village(_uninvolved):
		var now := ds.get_reputation(_uninvolved, player)
		_check(now < _uninvolved_rep - 5.0, "Ruf bei %s nach der Eroberung gesunken (%+.0f → %+.0f)" % [
				_uninvolved.display_name, _uninvolved_rep, now])
	# Handelsvertrag mit A (Lieferungen und Ruf-Gewinn prüft der Bericht)
	ds.debug_set_reputation(_a, player, 40.0)
	_trade_rep = ds.get_reputation(_a, player)
	var answer := ds.propose_treaty(player, _a, "trade")
	_check(answer.is_empty() and ds.get_treaty_with(_a, player) == "trade", "Handelsvertrag mit %s %s" % [_a.display_name, answer])
	# Schutzvertrag mit E: Angriff (Monster) -> Schutzpflicht; Aufnahme mit Geschenk möglich
	if _e != null:
		ds.debug_set_reputation(_e, player, 40.0)
		var info := ds.can_annex(player, _e)
		_check(str(info["mode"]) == "gift" and not (info["gift"] as Dictionary).is_empty(),
				"Aufnahme von %s mit Geschenk: %s" % [_e.display_name, DataDB.cost_to_text(info["gift"])])
		var protection := ds.propose_treaty(player, _e, "protection")
		var hall_e := vs.get_hall(_e)
		if protection.is_empty() and hall_e != null:
			g.combat_system.apply_damage(hall_e, 10.0, null, g.wild, "event")
		_check(protection.is_empty() and ds.get_urgent(player).size() == 1, "Schutzvertrag mit %s, Angriff -> Schutzpflicht %s" % [
				_e.display_name, protection])
	# Drohung ohne Truppen in der Nähe: wird verlacht, Ruf sinkt
	if vs.is_village(_uninvolved) and _uninvolved != _a:
		var before := ds.get_reputation(_uninvolved, player)
		var threat := ds.get_threat_info(player, _uninvolved)
		var paid := ds.threaten(player, _uninvolved)
		_check(bool(threat["possible"]) and not paid and ds.get_reputation(_uninvolved, player) < before,
				"Drohung gegen %s verlacht (Verhältnis %.1f)" % [_uninvolved.display_name, float(threat["ratio"])])


## S5: Frieden mit B, Seitenwechsel des unbeteiligten Dorfs auslösen
func _s5() -> void:
	var g := _game
	var ds: DiplomacySystem = g.diplomacy_system
	var vs: VillageSystem = g.village_system
	var player: Kingdom = g.player
	_trade_rep_s5 = ds.get_reputation(_a, player)
	ds.debug_set_reputation(_b, player, -20.0)
	var reason := ds.can_make_peace(player, _b)
	var peace := ds.make_peace(player, _b)
	_check(peace and not g.are_hostile(player, _b), "Frieden mit %s %s" % [_b.display_name, reason])
	if _e != null:
		_check(ds.get_urgent(player).is_empty(), "Schutzpflicht ohne Angreifer erledigt")
	if vs.is_village(_uninvolved) and _uninvolved != _a:
		ds.debug_set_reputation(_uninvolved, player, -60.0)
	# Alarm von S1 vorbei: Milizen von B wieder auf ihren Posten
	var rec_b := vs.get_record(_b)
	var holding := 0
	for u in vs.get_militia(_b):
		if (u as Unit).command == "hold":
			holding += 1
	_check(float(rec_b["alarm_until"]) == 0.0 and holding == vs.get_militia(_b).size(),
			"Alarm in %s beendet, %d Milizen halten ihre Posten" % [_b.display_name, holding])
	# Gefallene Miliz von A ersetzt
	_check(vs.get_militia(_a).size() == vs.get_militia_target(_a), "Miliz von %s nachgefüllt (%d/%d)" % [_a.display_name,
			vs.get_militia(_a).size(), vs.get_militia_target(_a)])
	# Bündnishilfe (direkt ausgelöst): Milizen ziehen los und kehren ohne Feinde wieder um
	vs.dispatch_help(_a, vs.get_center(_a) + Vector2(320.0, 0.0), g.wild)
	_check(not (vs.get_record(_a)["helpers"] as Array).is_empty(), "Bündnishilfe von %s unterwegs" % _a.display_name)


## S6: Seitenwechsel (ohne Gegnerreiche: das Dorf wird feindlich)
func _s6() -> void:
	var g := _game
	var vs: VillageSystem = g.village_system
	if vs.is_village(_uninvolved) and _uninvolved != _a:
		_check(g.are_hostile(g.player, _uninvolved), "%s ist nach Ruf −60 feindlich" % _uninvolved.display_name)
	_check((vs.get_record(_a)["helpers"] as Array).is_empty(), "Bündnishilfe ohne Feinde beendet")


## Bericht am Ende der Partie
func report() -> void:
	var g := _game
	var vs: VillageSystem = g.village_system
	var ds: DiplomacySystem = g.diplomacy_system
	var ms: MessengerSystem = g.messenger_system
	var player: Kingdom = g.player
	for v in vs.get_villages(true):
		var rec := vs.get_record(v)
		var owner_k: Kingdom = g.get_kingdom(int(rec.get("owner_id", 0)))
		var treaty := ds.get_treaty(v)
		print("[smoke] Dorf %d %s (%s): %s, Besitzer %s, Ruf Spieler %+.1f (Grundwert %+.1f), Vertrag %s, Miliz %d, Vorrat %s" % [
				v.id, v.display_name, str(rec["people_id"]), str(rec["status"]),
				owner_k.display_name if owner_k != null else "-", ds.get_reputation(v, player),
				ds.get_base_reputation(v, player), str(treaty.get("type", "-")), vs.get_militia(v).size(),
				DataDB.cost_to_text(v.resources)])
	print("[smoke] Boten: gesendet %d, angekommen %d, abgefangen %d, verloren %d" % [int(ms.stats["sent"]),
			int(ms.stats["arrived"]), int(ms.stats["intercepted"]), int(ms.stats["lost"])])
	if int(ms.stats["arrived"]) == 0:
		print("[smoke] Hinweis: bis zum Ende kam kein Bote an")
	if _stage >= 5 and vs.is_village(_a):
		var treaty := ds.get_treaty(_a)
		var deliveries := int(treaty.get("deliveries", 0))
		var rep_now := ds.get_reputation(_a, player)
		if GameClock.game_time > 600.0:
			_check(str(treaty.get("type", "")) == "trade" and deliveries >= 1 and rep_now > _trade_rep_s5,
					"Handelsvertrag mit %s: %d Lieferungen, Ruf %+.1f (Beginn) → %+.1f (t=400) → %+.1f" % [
					_a.display_name, deliveries, _trade_rep, _trade_rep_s5, rep_now])
	if _stage != 99 and _ui_step >= 0 and GameClock.game_time > UI_TEST_TIME + 60.0:
		_check(false, "Oberflächentest nicht fertig geworden (Schritt %d, Heldentest fertig: %s)" % [_ui_step, str(ui_ready)])
	if _stage == 99:
		print("[smoke] Phase 6: übersprungen (zu wenige Dörfer)")
	elif _stage < 5 or (_stage < 7 and GameClock.game_time > 410.0):
		_check(false, "Phase-6-Test nicht fertig geworden (Stufe %d)" % _stage)
	print("[smoke] Phase 6: %s" % ("OK" if _errors == 0 else "%d Fehler" % _errors))


# ---------------------------------------------------------------------------
# Oberfläche (Diplomatiefenster, Auswahlfenster, Kriegsbestätigung, Minikarte)
# ---------------------------------------------------------------------------

func _ui_test() -> void:
	var g := _game
	var hud: Node = g.hud
	var ds: DiplomacySystem = g.diplomacy_system
	var vs: VillageSystem = g.village_system
	var ms: MessengerSystem = g.messenger_system
	var panel: DiplomacyPanel = hud.diplomacy_panel
	var player: Kingdom = g.player
	_ui_wait_until = GameClock.game_time + 0.5
	match _ui_step:
		0:
			# Testdorf: das unbeteiligte Dorf (Bündnis, Krieg); sonst A (nur Geschenk)
			_ui_village = _uninvolved if vs.is_village(_uninvolved) and _uninvolved != _a else _a
			if not vs.is_village(_ui_village):
				print("[smoke] Phase 6: Oberflächentest übersprungen (kein selbstständiges Dorf)")
				_ui_step = -1
				return
			_ui_debug_was_visible = hud.is_debug_visible()
			if not _ui_debug_was_visible:
				hud.toggle_debug()
			hud.toggle_research()
			hud.toggle_diplomacy()
			_check(hud.is_diplomacy_open() and not hud.is_research_open() and not hud.is_heroes_open(),
					"Diplomatiefenster mit N geöffnet, Forschung schliesst sich")
			var bar: Control = hud.date_label.get_parent()
			var vp_w: float = hud.get_viewport().get_visible_rect().size.x
			var parts: PackedStringArray = []
			for c in bar.get_children():
				parts.append("%s %d" % [(c as Control).name, roundi((c as Control).get_combined_minimum_size().x)])
			_check(bar.get_combined_minimum_size().x <= vp_w, "Obere Leiste passt (%d von %d Pixeln: %s)" % [
					roundi(bar.get_combined_minimum_size().x), roundi(vp_w), ", ".join(parts)])
			panel.select_village(_ui_village.id)
			_check(panel.get_village_id() == _ui_village.id and panel.sorted_villages().size() == vs.get_villages(true).size(),
					"Fenster zeigt %s (Liste mit %d Dörfern)" % [_ui_village.display_name, panel.sorted_villages().size()])
			var before := ds.get_reputation(_ui_village, player)
			panel.set_gift_choice("food", 100)
			_check(int(panel.get_gift().get("food", 0)) == 100, "Geschenkwahl im Fenster: 100 Nahrung")
			panel._on_gift_pressed()
			_check(ds.get_reputation(_ui_village, player) > before, "Geschenk über das Fenster: Ruf %+.1f → %+.1f" % [
					before, ds.get_reputation(_ui_village, player)])
			_ui_step = 1
		1:
			_shot("p6_1_diplomatie")
			var r: Rect2 = panel.get_global_rect()
			var vp: Rect2 = panel.get_viewport_rect()
			_check(vp.encloses(Rect2(r.position, r.size * panel.scale)) and r.size.x <= DiplomacyPanel.DESIGN_WIDTH + 0.5,
					"Diplomatiefenster liegt im Bild und ist nicht breiter als geplant (%s)" % str(r))
			if _ui_village == _a:
				_ui_step = 3
				return
			# Bündnis über den Vertragsknopf (Ruf per F3-Knopf hoch: Chance 100 %)
			for i in 6:
				if ds.get_reputation(_ui_village, player) >= 55.0:
					break
				panel.debug_action("rep_up")
			var offer := ds.get_treaty_offer(player, _ui_village, "alliance")
			panel._on_treaty_pressed("alliance")
			_check(ds.get_treaty_with(_ui_village, player) == "alliance" and g.are_allied(player, _ui_village),
					"Bündnis über das Fenster mit %s (Chance %d %%)" % [_ui_village.display_name, roundi(float(offer["chance"]) * 100.0)])
			# Tausch über das Fenster: Ware, die das Dorf vorrätig hat
			var get_res := ""
			for res in DataDB.resources:
				var res_id := str(res["id"])
				if res_id != "wood" and _ui_village.get_amount(res_id) >= 20.0:
					get_res = res_id
					break
			if not get_res.is_empty():
				panel.set_trade_choice("wood", 10, get_res)
				var q := panel.get_trade_quote()
				var had := player.get_amount(get_res)
				panel._on_trade_pressed()
				_check(not bool(q["ok"]) or player.get_amount(get_res) > had, "Tausch über das Fenster: 10 Holz → %d %s %s" % [
						roundi(float(q["get_amount"])), get_res, str(q["reason"])])
			# Debug-Bote (F3-Knopf) für die Minikarte
			var sent := int(ms.stats["sent"])
			panel.debug_action("messenger")
			_check(int(ms.stats["sent"]) == sent + 1 or ms.pick_receiver(_ui_village, player) == null,
					"Debug-Bote aus %s losgeschickt" % _ui_village.display_name)
			_ui_step = 2
		2:
			_shot("p6_2_vertrag")
			_ui_step = 3
		3:
			hud.close_top_panel()
			_check(not hud.is_diplomacy_open(), "Esc schliesst das Diplomatiefenster")
			var hall := vs.get_hall(_ui_village)
			g.selection.select([hall])
			hud.selection_panel._refresh()
			var sp: SelectionPanel = hud.selection_panel
			_check(sp._village_row.visible and sp._owner.text.contains("(") and sp._facts.text.contains("Volk:"),
					"Auswahlfenster: %s | %s" % [sp._owner.text, sp._facts.text.get_slice("\n", 0)])
			var territory: String = hud._territory_text(hall.cell)
			_check(territory.begins_with("Gebiet: "), "Infobereich: %s" % territory)
			hud.minimap._rebuild_cache()
			var messengers: Array = hud.minimap._messenger_groups
			_check(ms.get_messengers().is_empty() or not messengers.is_empty(), "Boten auf der Minikarte (%d Gruppen)" % messengers.size())
			_ui_step = 4
		4:
			_shot("p6_3_auswahl")
			var sp: SelectionPanel = hud.selection_panel
			sp._on_diplo_pressed()
			_check(hud.is_diplomacy_open() and panel.get_village_id() == _ui_village.id, "Knopf „Diplomatie (N)“ öffnet das Fenster beim Dorf")
			hud.toggle_heroes()
			_check(hud.is_heroes_open() and not hud.is_diplomacy_open(), "Heldenfenster schliesst das Diplomatiefenster")
			hud.close_top_panel()
			if _ui_village == _a:
				_ui_step = 6
				return
			# Kriegsbestätigung: zwei Rechtsklicks mit eigenen Truppen auf eine Dorfwache
			var fighter := str(DataDB.get_unit_for_tier(player.faction_id, "fighter").get("id", ""))
			_ui_units.clear()
			for i in 2:
				var u: Unit = g.unit_system.spawn_unit(player, fighter, player.castle.get_center() + Vector2(80.0 + 40.0 * i, 120.0))
				if u != null:
					_ui_units.append(u)
			var militia := vs.get_militia(_ui_village)
			if militia.is_empty() or _ui_units.is_empty():
				print("[smoke] Phase 6: Kriegsbestätigung übersprungen (keine Miliz/Truppen)")
				_ui_step = 6
				return
			var target: Unit = militia[0]
			g.camera.focus_on(target.position)
			g.selection.select(_ui_units)
			g.selection._issue_order(_ui_units, target.position, false)
			_check(not g.are_hostile(player, _ui_village), "Erster Rechtsklick auf %s: nur Hinweis, kein Krieg" % _ui_village.display_name)
			g.selection._issue_order(_ui_units, target.position, false)
			_check(g.are_hostile(player, _ui_village) and ds.get_treaty_with(_ui_village, player).is_empty(),
					"Zweiter Rechtsklick: Krieg mit %s, Bündnis gebrochen (Ruf %+.0f)" % [_ui_village.display_name,
					ds.get_reputation(_ui_village, player)])
			_ui_step = 5
		5:
			_shot("p6_4_krieg")
			# Truppen zurück (der Test soll das Dorf nicht erobern)
			var alive: Array = []
			for u in _ui_units:
				if is_instance_valid(u) and (u as Unit).is_alive():
					alive.append(u)
			if not alive.is_empty():
				g.command_system.order_move(alive, player.castle.get_center() + Vector2(0.0, 160.0), false)
			g.selection.clear()
			_ui_step = 6
		6:
			if hud.is_debug_visible() != _ui_debug_was_visible:
				hud.toggle_debug()
			print("[smoke] Phase 6: Oberflächentest fertig")
			_ui_step = -1


## Bildschirmfoto (nur mit shots=<ordner> und echtem Fenster, z. B. unter xvfb-run)
func _shot(shot_name: String) -> void:
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("shots="):
			dir = str(a).substr(6)
	if dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	var img := _game.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s_%s.png" % [dir, GameSession.faction_id, shot_name])
