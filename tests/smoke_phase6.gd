## Rauchtest Phase 6 (gestartet von tests/smoke_test.gd): prüft über die
## öffentlichen Schnittstellen der Systeme Geschenk, Handel, Bündnis samt
## Freischaltung, Kündigung, Krieg mit Angriff und Bote, Abfangen, Aufnahme und
## Eroberung. Fehler erscheinen als "ERROR: [smoke] Phase 6 FEHLER: …" (push_error),
## damit run_smoke.sh fehlschlägt.
extends RefCounted

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


func _init(game: Node) -> void:
	_game = game


## Jeden Frame aufrufen (Spielzeit t)
func tick(t: float) -> void:
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
	return true


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
	if _stage == 99:
		print("[smoke] Phase 6: übersprungen (zu wenige Dörfer)")
	elif _stage < 5 or (_stage < 7 and GameClock.game_time > 410.0):
		_check(false, "Phase-6-Test nicht fertig geworden (Stufe %d)" % _stage)
	print("[smoke] Phase 6: %s" % ("OK" if _errors == 0 else "%d Fehler" % _errors))
