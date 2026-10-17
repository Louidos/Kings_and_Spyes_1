## Rauchtest Handel (trade.json prices, order, reputation_per_delivery): Preise je Dorf nach Angebot
## und Nachfrage (viel Holz = billiges Holz), sichtbar im Diplomatiefenster; eine Handelsroute mit
## eingestellter Menge und Abstand liefert ohne weiteres Klicken per Karawane, stärkt den Ruf, steht
## als Fluss je Minute im Reiter Handelswege und übersteht Speichern und Laden.
extends RefCounted

const TOPIC := "Handel"


func run(r: Node) -> void:
	var g: Node = r.game
	var ds: DiplomacySystem = g.diplomacy_system
	var player: Kingdom = g.player
	var villages := _free_villages(g)
	if villages.size() < 2:
		r.check(TOPIC, false, "Zu wenige freie Dörfer für den Handelstest (%d)" % villages.size())
		return
	# 1. Preise: gleiches Volk-unabhängiges Gut (Holz), einmal viel, einmal wenig auf Lager
	var rich: Kingdom = villages[0]
	var poor: Kingdom = villages[1]
	rich.add_resource("wood", 600.0 - rich.get_amount("wood"))
	poor.add_resource("wood", 10.0 - poor.get_amount("wood"))
	var p_rich: Dictionary = ds.get_prices(rich, player)
	var p_poor: Dictionary = ds.get_prices(poor, player)
	r.check(TOPIC, ds.supply_factor(rich, "wood") < 1.0 and ds.supply_factor(poor, "wood") > 1.0,
			"Knappheit Holz: %s %.2f (600 auf Lager), %s %.2f (10 auf Lager)" % [rich.display_name,
			ds.supply_factor(rich, "wood"), poor.display_name, ds.supply_factor(poor, "wood")])
	r.check(TOPIC, float(p_rich["wood"]["sell"]) < float(p_poor["wood"]["sell"]),
			"Holzpreis je Dorf verschieden: %s verlangt %.2f, %s %.2f" % [
			rich.display_name, float(p_rich["wood"]["sell"]), poor.display_name, float(p_poor["wood"]["sell"])])
	var text := DiplomacyPanel.prices_text(p_rich)
	r.check(TOPIC, text.contains("Preise") and text.contains(str(DataDB.get_resource("wood").get("name", "wood"))),
			"Preise im Diplomatiefenster: %s" % text.get_slice("\n", 0).left(120))
	# Tausch folgt dem Preis: für dieselbe Ware gibt das holzreiche Dorf mehr Holz
	player.add_resource("food", 200.0)
	var q_rich := ds.get_trade_quote(player, rich, "food", 40.0, "wood")
	var q_poor := ds.get_trade_quote(player, poor, "food", 40.0, "wood")
	r.check(TOPIC, float(q_rich["get_amount"]) > float(q_poor["get_amount"]),
			"Tausch 40 Nahrung → Holz: %s gibt %.0f, %s %.0f" % [rich.display_name, float(q_rich["get_amount"]),
			poor.display_name, float(q_poor["get_amount"])])
	# 2. Dauerhafte Route einrichten und einstellen
	var v: Kingdom = rich
	# Frühere Module (Drohung, Krieg) können den Ruf gesenkt haben: neutral-freundlich starten
	ds.change_reputation(v, player, 20.0 - ds.get_reputation(v, player), "Rauchtest")
	var err := ds.start_treaty_forced(v, player, "trade")
	r.check(TOPIC, err.is_empty(), "Handelsvertrag mit %s %s" % [v.display_name, "geschlossen" if err.is_empty() else "fehlt: " + err])
	if not err.is_empty():
		return
	var base := ds.get_delivery(v, player)
	var amounts: Array = DataDB.trade("order.amount_steps", [])
	var intervals: Array = DataDB.trade("order.interval_steps", [])
	var amount := float(amounts[amounts.size() - 2])
	var interval := float(intervals[0])
	var set_err := ds.set_trade_order(player, v, amount, interval)
	var doubled := ds.get_delivery(v, player)
	var more := true
	for res_id in base["give"]:
		more = more and float(doubled["give"][res_id]) >= float(base["give"][res_id]) * amount - 1.0
	r.check(TOPIC, set_err.is_empty() and more and is_equal_approx(ds.trade_interval(v), interval),
			"Route eingestellt: Menge ×%s, alle %d s – Lieferung %s statt %s" % [str(amount), int(interval),
			str(doubled["give"]), str(base["give"])])
	r.check(TOPIC, not ds.set_trade_order(player, v, 7.0, interval).is_empty()
			and not ds.set_trade_order(player, poor, amount, interval).is_empty(),
			"Unerlaubte Menge und Dorf ohne Vertrag werden abgelehnt")
	var flow := ds.get_trade_flow(player)
	var flow_line := TradeRouteList.flow_text(flow)
	r.check(TOPIC, not (flow["in"] as Dictionary).is_empty() and not (flow["out"] as Dictionary).is_empty()
			and flow_line.contains("+"), "Reichsfenster, Handel je Minute: %s" % flow_line)
	# 3. Läuft ohne Klicken: Karawane holt die Lieferung, Ruf steigt
	var trs: TradeRouteSystem = g.trade_route_system
	trs.debug_fast = true
	for res_id in doubled["give"]:
		v.add_resource(str(res_id), float(doubled["give"][res_id]) * 4.0)
	for res_id in doubled["take"]:
		player.add_resource(str(res_id), float(doubled["take"][res_id]) * 4.0)
	var t: Dictionary = ds.get_treaty(v)
	var deliveries0 := int(t.get("deliveries", 0))
	var rep0 := ds.get_reputation(v, player)
	t["next_delivery"] = GameClock.game_time
	var until := GameClock.game_time + 900.0
	while int(ds.get_treaty(v).get("deliveries", 0)) <= deliveries0 and GameClock.game_time < until:
		await r.wait_game_seconds(10.0)
	var delivered := int(ds.get_treaty(v).get("deliveries", 0)) - deliveries0
	r.check(TOPIC, delivered >= 1, "Karawane liefert von selbst: %d Lieferung(en) in %.0f s" % [delivered,
			GameClock.game_time - (until - 900.0)])
	r.check(TOPIC, ds.get_reputation(v, player) > rep0, "Handel stärkt den Ruf bei %s: %.1f → %.1f" % [v.display_name,
			rep0, ds.get_reputation(v, player)])
	# Die Ware wird beim Aufbruch festgelegt: Menge danach erhöhen bringt auf dieser Fahrt nicht mehr
	# (langer Abstand, damit keine weitere Lieferung dazwischenkommt; erst warten, bis die
	# Karawane daheim ist und nichts mehr aussteht)
	var slow := float(intervals[intervals.size() - 1])
	ds.set_trade_order(player, v, float(amounts[0]), slow)
	var trip: Dictionary = trs.get_route_for(player, v)
	until = GameClock.game_time + 900.0
	while (str(trip["leg"]) != "idle" or int(trip["pending"]) > 0) and GameClock.game_time < until:
		await r.wait_game_seconds(2.0)
	var small: Dictionary = ds.get_delivery(v, player)["give"]
	var delivered0: Dictionary = (trip["stats"]["delivered"] as Dictionary).duplicate()
	deliveries0 = int(ds.get_treaty(v).get("deliveries", 0))
	ds.get_treaty(v)["next_delivery"] = GameClock.game_time
	while not trip.has("order_give") and GameClock.game_time < until:
		await r.wait_game_seconds(2.0)
	var departed := trip.has("order_give")
	ds.set_trade_order(player, v, float(amounts[amounts.size() - 1]), slow)
	while int(ds.get_treaty(v).get("deliveries", 0)) <= deliveries0 and GameClock.game_time < until:
		await r.wait_game_seconds(5.0)
	var got := {}
	for res_id in small:
		got[res_id] = float((trip["stats"]["delivered"] as Dictionary).get(res_id, 0.0)) - float(delivered0.get(res_id, 0.0))
	var same := departed
	for res_id in small:
		same = same and is_equal_approx(float(got[res_id]), float(small[res_id]))
	r.check(TOPIC, same, "Menge nach der Abfahrt erhöht: geliefert %s wie beim Aufbruch bestellt (%s)" % [str(got), str(small)])
	ds.set_trade_order(player, v, amount, interval)
	trs.debug_fast = false
	# 4. Speichern und Laden: Einstellung und Route bleiben
	var vid := v.id
	var save_err: String = await r.save_and_reload("smoke_trade")
	r.check(TOPIC, save_err.is_empty(), "Speichern und Laden %s" % ("ok" if save_err.is_empty() else save_err))
	g = r.game
	ds = g.diplomacy_system
	var v2: Kingdom = g.get_kingdom(vid)
	var t2: Dictionary = ds.get_treaty(v2) if v2 != null else {}
	var route_ok := false
	for route in g.trade_route_system.get_routes(g.player):
		route_ok = route_ok or int(route["partner_id"]) == vid
	r.check(TOPIC, not t2.is_empty() and is_equal_approx(float(t2.get("amount_mult", 0.0)), amount)
			and is_equal_approx(ds.trade_interval(v2), interval) and route_ok and float(t2["next_delivery"]) > 0.0,
			"Nach dem Laden: Menge ×%s, alle %d s, Handelsweg vorhanden: %s" % [str(t2.get("amount_mult", "?")),
			int(ds.trade_interval(v2)) if v2 != null else 0, route_ok])


## Selbstständige Dörfer ohne Vertrag, nächstgelegene zuerst
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
