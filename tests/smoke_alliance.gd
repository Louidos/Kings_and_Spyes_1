## Rauchtest Bündnisse (diplomacy.json station, StationSystem): Truppen bei einem verbündeten
## Dorf stationieren (beim Nicht-Verbündeten gesperrt mit Grund, auch in der Dorfliste des
## Armeefensters); sie kommen an, greifen Angreifer am Dorf an, zählen für die KI zur
## Verteidigung, heben den Ruf und bringen Abgaben; Stationierung übersteht Speichern und
## Laden; Hilferuf ablehnen kostet Ruf; bei Bündnisbruch ziehen sie ab; die KI stationiert
## nach denselben Regeln.
extends RefCounted

const TOPIC := "Bündnis"


func run(r: Node) -> void:
	var g: Node = r.game
	var ds: DiplomacySystem = g.diplomacy_system
	var ss: StationSystem = g.station_system
	var player: Kingdom = g.player
	var villages := _free_villages(g)
	if villages.size() < 3:
		r.check(TOPIC, false, "Zu wenige freie Dörfer für den Bündnistest (%d)" % villages.size())
		return
	var v: Kingdom = villages[0]
	var other: Kingdom = villages[1]
	# Nach dem Laden gibt es neue Reichsobjekte: das dritte Dorf über seine id holen
	var third_id: int = (villages[2] as Kingdom).id
	ds.debug_set_reputation(v, player, 50.0)
	var err := ds.start_treaty_forced(v, player, "alliance")
	r.check(TOPIC, err.is_empty(), "Bündnis mit %s %s" % [v.display_name, "geschlossen" if err.is_empty() else "fehlt: " + err])
	if not err.is_empty():
		return
	var units: Array = r.spawn_tier(player, "fighter", 5)
	# 1. Gesperrt beim Nicht-Verbündeten, mit Grund (auch im Armeefenster)
	var reason := ss.can_station(player, units, other)
	r.check(TOPIC, reason.contains("Bündnis") and not ss.station(player, units, other).is_empty()
			and ss.get_stationed(player, other).is_empty(), "Bei %s gesperrt: %s" % [other.display_name, reason])
	var listed := false
	for entry in g.hud.troop_panel.station_targets():
		if entry["village"] == other:
			listed = not str(entry["reason"]).is_empty()
	r.check(TOPIC, listed, "Armeefenster: %s steht gesperrt mit Grund in der Dorfliste" % other.display_name)
	# 2. Stationieren und Ankunft
	err = ss.station(player, units, v)
	r.check(TOPIC, err.is_empty() and ss.get_stationed(player, v).size() == units.size(),
			"%d Krieger zu %s geschickt %s" % [units.size(), v.display_name, err])
	var until := GameClock.game_time + 600.0
	while ss.get_present(player, v).size() < units.size() and GameClock.game_time < until:
		await r.wait_game_seconds(10.0)
	var present := ss.get_present(player, v).size()
	r.check(TOPIC, present == units.size() and ss.guard_power(v) > 0.0,
			"Am Dorf angekommen: %d/%d, Verteidigung für die KI +%d" % [present, units.size(), roundi(ss.guard_power(v))])
	# 3. Speichern und Laden
	var vid := v.id
	var uids: Array = []
	for u in units:
		uids.append((u as Unit).uid)
	var save_err: String = await r.save_and_reload("smoke_alliance")
	g = r.game
	ds = g.diplomacy_system
	ss = g.station_system
	player = g.player
	v = g.get_kingdom(vid)
	r.check(TOPIC, save_err.is_empty() and ss.get_stationed(player, v).size() == units.size(),
			"Nach Speichern und Laden: %d Krieger stationiert %s" % [ss.get_stationed(player, v).size(), save_err])
	# 4. Ruf und Abgabe
	var rep0 := ds.get_reputation(v, player)
	var t: Dictionary = ss.timers[StationSystem.pair(v, player)]
	t["next_rep"] = GameClock.game_time
	t["next_tribute"] = GameClock.game_time
	var tribute := ss.tribute_for(v, present)
	for res_id in tribute:
		v.add_resource(str(res_id), 50.0)
	tribute = ss.tribute_for(v, present)
	var stock0 := {}
	for res_id in tribute:
		stock0[res_id] = player.get_amount(str(res_id))
	await r.wait_game_seconds(5.0)
	var got := true
	for res_id in tribute:
		got = got and player.get_amount(str(res_id)) > float(stock0[res_id])
	var history := ds.get_history(v, player)
	r.check(TOPIC, ds.get_reputation(v, player) > rep0, "Stationierte Truppen heben den Ruf: %.1f → %.1f (%s)" % [rep0,
			ds.get_reputation(v, player), str((history.back() as Dictionary).get("reason", "")) if not history.is_empty() else ""])
	r.check(TOPIC, not tribute.is_empty() and got, "Abgabe des Dorfs: %s" % DataDB.cost_to_text(tribute))
	# 5. Angreifer am Dorf werden angegriffen
	var ai: Array = g.ai_system.get_ai_kingdoms()
	if not ai.is_empty():
		var enemy: Kingdom = ai[0]
		var center: Vector2 = g.village_system.get_center(v)
		var def := DataDB.get_unit_for_tier(enemy.faction_id, "fighter")
		var raiders: Array = []
		for i in 2:
			var u: Unit = g.unit_system.spawn_unit(enemy, str(def["id"]), center + Vector2(60.0 * i, 40.0))
			u.stance = "passive"
			raiders.append(u)
		var hp0 := 0.0
		for u in raiders:
			hp0 += (u as Unit).hp
		await r.wait_game_seconds(15.0)
		var hp1 := 0.0
		var engaged := false
		for u in raiders:
			if is_instance_valid(u) and (u as Unit).is_alive():
				hp1 += (u as Unit).hp
		for u in ss.get_stationed(player, v):
			engaged = engaged or raiders.has((u as Unit).target)
		r.check(TOPIC, hp1 < hp0, "Stationierte Truppen greifen Angreifer an: Leben der Angreifer %d → %d%s" % [
				roundi(hp0), roundi(hp1), " (im Kampf)" if engaged else ""])
		for u in raiders:
			if is_instance_valid(u) and (u as Unit).is_alive():
				g.unit_system.remove_unit(u)
	# 6. Hilferuf ablehnen kostet Ruf (Truppen zuerst zurückrufen, damit das Dorf ruft)
	var before := ss.get_stationed(player, v).size()
	var back := ss.recall(player, v)
	r.check(TOPIC, back > 0 and back == before and ss.get_stationed(player, v).is_empty(), "Zurückgerufen: %d Krieger" % back)
	if not ai.is_empty():
		var rep1 := ds.get_reputation(v, player)
		g.village_system.village_alarm.emit(v, ai[0], g.village_system.get_center(v))
		var opened := not ss.get_help_call(v, player).is_empty()
		var decline := ss.answer_help(player, v, false)
		r.check(TOPIC, opened and decline.is_empty() and ss.get_help_call(v, player).is_empty()
				and ds.get_reputation(v, player) < rep1, "Hilferuf von %s abgelehnt: Ruf %.1f → %.1f" % [v.display_name,
				rep1, ds.get_reputation(v, player)])
	# 7. Bündnisbruch: Truppen ziehen ab
	var fresh: Array = []
	for uid in uids:
		var u: Variant = g.find_by_uid(int(uid))
		if u is Unit and (u as Unit).is_alive():
			fresh.append(u)
	ss.station(player, fresh, v)
	var again: Array = ss.get_stationed(player, v)
	ds.cancel_treaty(player, v)
	await r.wait_game_seconds(3.0)
	r.check(TOPIC, not again.is_empty() and ss.get_stationed(player, v).is_empty(),
			"Bündnis gekündigt: %d stationierte Krieger ziehen ab" % again.size())
	# 8. Die KI stationiert nach denselben Regeln
	if not ai.is_empty():
		var ak: Kingdom = ai[0]
		var w: Kingdom = g.get_kingdom(third_id)
		ds.debug_set_reputation(w, ak, 50.0)
		var ai_err := ds.start_treaty_forced(w, ak, "alliance")
		r.spawn_tier(ak, "fighter", 12)
		var brain: AIBrain = g.ai_system.get_brain(ak)
		if ai_err.is_empty() and brain != null:
			AIDiplomacy.tick_stations(brain, 1.0e6)
		r.check(TOPIC, ai_err.is_empty() and not ss.get_stationed(ak, w).is_empty(),
				"KI %s stationiert %d Krieger bei %s" % [ak.display_name, ss.get_stationed(ak, w).size(), w.display_name])


## Selbstständige Dörfer ohne Vertrag und ohne Krieg mit dem Spieler, nächstgelegene zuerst
func _free_villages(g: Node) -> Array:
	var ds: DiplomacySystem = g.diplomacy_system
	var vs: VillageSystem = g.village_system
	var from: Vector2 = g.player.castle.get_center()
	var list: Array = []
	for v in vs.get_villages():
		if ds.get_treaty(v).is_empty() and not g.are_hostile(v, g.player):
			list.append(v)
	list.sort_custom(func(a: Kingdom, b: Kingdom) -> bool:
		return from.distance_to(vs.get_center(a)) < from.distance_to(vs.get_center(b)))
	return list
