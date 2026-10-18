## Rauchtest neue Gebäude (buildings.json well, granary, market): alle drei stehen im Baumenü mit ihrer
## Wirkung im Tooltip und im Auswahlfenster; Brunnen: Bewohner im Umkreis zufriedener (satisfaction_aura);
## Kornspeicher: Annahmestelle nur für Nahrung, weniger Nahrungsverbrauch (kingdom_mods food_use, einmal);
## Markt: kleinere Handelsmarge (kingdom_bonus trade_bonus); Wirkungen enden mit dem Abriss und
## überstehen Speichern und Laden; die KI hat sie in ihrer Bauliste.
extends RefCounted

const TOPIC := "Gebäude"
const IDS := ["well", "granary", "market"]


func run(r: Node) -> void:
	var g: Node = r.game
	var k: Kingdom = g.player
	var bs: BuildingSystem = g.building_system
	var menu: BuildMenu = g.hud.build_menu
	# Baumenü und Tooltip
	for id in IDS:
		var def := DataDB.get_building(id)
		var tip := BuildMenu.build_tooltip(def)
		var effects := BuildMenu.effect_lines(def)
		r.check(TOPIC, menu._buttons.has(id) and not effects.is_empty() and tip.contains(effects[0]),
				"%s im Baumenü, Tooltip: %s" % [DataDB.get_building_name(def, k.faction_id), effects[0]])
	# Markt braucht Burgstufe 2
	if k.castle.level < 2:
		bs.set_castle_level(k, 2)
	var placed := {}
	for id in IDS:
		var b := _place(g, k, id)
		placed[id] = b
		r.check(TOPIC, b != null and b.constructed, "%s gebaut" % id)
	if placed.values().has(null):
		return
	await r.wait_game_seconds(3.0)
	# Brunnen: Bewohner im Umkreis +5, weit weg nichts
	var well: Building = placed["well"]
	var sat: SatisfactionSystem = g.satisfaction_system
	var aura: Dictionary = DataDB.get_building("well")["satisfaction_aura"]
	var near: Unit = null
	for u in k.units:
		if bool(u.type_def.get("needs_housing", false)) and u.inside == null:
			near = u
			break
	if near != null:
		near.position = well.get_center() + Vector2(64, 64)
		var parts: Array = sat._personal_parts(near, GameClock.game_time)
		var found := 0.0
		for p in parts:
			if str(p[0]) == str(aura["cause"]):
				found = float(p[1])
		near.position = well.get_center() + Vector2(64.0 * (float(aura["radius"]) + 6.0), 0)
		var far := 0.0
		for p in sat._personal_parts(near, GameClock.game_time):
			if str(p[0]) == str(aura["cause"]):
				far = float(p[1])
		r.check(TOPIC, is_equal_approx(found, float(aura["bonus"])) and far == 0.0,
				"Brunnen: Bewohner in der Nähe %+d Zufriedenheit, weit weg %+d" % [roundi(found), roundi(far)])
	# Kornspeicher: nur Nahrung, Verbrauch −10 %
	var granary: Building = placed["granary"]
	var use := k.mod("food_use")
	r.check(TOPIC, granary.accepts("food") and not granary.accepts("wood") and is_equal_approx(use, 0.9),
			"Kornspeicher nimmt nur Nahrung an, Nahrungsverbrauch ×%s" % String.num(use, 2))
	var second := _place(g, k, "granary")
	r.check(TOPIC, second != null and is_equal_approx(k.mod("food_use"), use), "Zweiter Kornspeicher zählt nicht doppelt")
	if second != null:
		bs.remove_building(second)
	# Markt: Handelsmarge kleiner
	var ds: DiplomacySystem = g.diplomacy_system
	var village: Kingdom = g.village_system.get_villages()[0]
	var with_market := ds.trade_margin(village, k)
	bs.remove_building(placed["market"])
	var without := ds.trade_margin(village, k)
	r.check(TOPIC, without - with_market > 0.05 and k.bonus("trade_bonus") == 0.0,
			"Markt: Handelsmarge %d %% statt %d %%, nach dem Abriss wieder ohne Bonus" % [roundi(with_market * 100.0),
			roundi(without * 100.0)])
	placed["market"] = _place(g, k, "market")
	# Auswahlfenster zeigt die Wirkung
	g.selection.select([granary])
	await r.get_tree().process_frame
	var facts: String = g.hud.selection_panel._facts.text
	r.check(TOPIC, facts.contains("Nahrungsverbrauch"), "Auswahlfenster Kornspeicher: %s" % facts.replace("\n", " · "))
	g.selection.clear()
	# Speichern und Laden: Wirkungen bleiben
	var err: String = await r.save_and_reload("smoke_new_buildings")
	r.check(TOPIC, err.is_empty(), "Gespeichert und geladen %s" % err)
	var k2: Kingdom = r.game.player
	r.check(TOPIC, is_equal_approx(k2.mod("food_use"), 0.9) and is_equal_approx(k2.bonus("trade_bonus"), 0.1),
			"Nach dem Laden: Nahrungsverbrauch ×%s, Handelsbonus %s" % [String.num(k2.mod("food_use"), 2),
			String.num(k2.bonus("trade_bonus"), 2)])
	# Die KI hat alle drei in der Bauliste
	var order := {}
	for entry in DataDB.ai("build_order", []):
		order[str(entry["building"])] = true
	r.check(TOPIC, order.has("well") and order.has("granary") and order.has("market"), "KI-Bauliste enthält Brunnen, Kornspeicher und Markt")


## Gebäude sofort fertig auf den ersten freien Platz im eigenen Gebiet um die Burg
static func _place(g: Node, k: Kingdom, id: String) -> Building:
	var bs: BuildingSystem = g.building_system
	var def := DataDB.get_building(id)
	var center: Vector2i = k.castle.cell + Vector2i(1, 1)
	for radius in range(3, 14):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var cell := center + Vector2i(dx, dy)
				if bs.can_place_free(def, cell, k).is_empty():
					return bs.place_building(def, cell, k, true)
	return null
