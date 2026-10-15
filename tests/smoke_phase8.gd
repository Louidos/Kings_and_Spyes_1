## Rauchtest Phase 8 (gestartet von tests/smoke_test.gd): Völker, Tag/Nacht, Gelände,
## Zufriedenheit (Arbeitsleistung, Überlaufen, Verrat, Feste), Zufallsereignisse (jedes
## Ereignis per Debug ausgelöst und wieder beendet), Flüchtlinge und Wanderer
## (Aufnehmen, Abweisen, KI entscheidet), Monsterwellen und Streifzüge sowie die
## Oberfläche (Reichsübersicht, Ereignisleiste, Flüchtlingsdialog).
##
## Argumente: p8=natural (keine Debug-Stufen, nur Bericht – für lange Läufe).
## Fehler erscheinen als "ERROR: [smoke] Phase 8 FEHLER: …" (push_error).
extends RefCounted

var _game: Node
var _natural := false
var _stage := 0
var _errors := 0
var _ai0: Kingdom = null
var _defector_uid := 0
## Der Überläufer starb unterwegs (Name des Angreifers) – dann zählt er nicht als übergelaufen
var _defector_killed_by := ""
var _attack_seen := false
var _phase_changes := 0
var _wave_raid := 0
var _pop_before := 0
var _ai_offer_id := 0
var _lairs_start := 0
var _done := false
var _natural_info := {}


func _init(game: Node, args: Dictionary) -> void:
	_game = game
	_natural = str(args.get("p8", "")) == "natural"
	var dns: DayNightSystem = game.day_night_system
	dns.phase_changed.connect(func(_p: String) -> void: _phase_changes += 1)
	game.combat_system.kingdom_attacked.connect(func(victim: Kingdom, attacker: Kingdom, _pos: Vector2) -> void:
		if victim == game.player and attacker == game.wild:
			_attack_seen = true)
	_lairs_start = game.monster_system.lairs.size()
	game.combat_system.unit_died.connect(func(u: Unit, killer: Kingdom) -> void:
		if u != null and _defector_uid != 0 and u.uid == _defector_uid:
			_defector_killed_by = killer.display_name if killer != null else "?")


func _check(cond: bool, text: String) -> void:
	if cond:
		print("[smoke] Phase 8 OK: " + text)
	else:
		_errors += 1
		push_error("[smoke] Phase 8 FEHLER: " + text)


func _note(text: String) -> void:
	print("[smoke] Phase 8 Hinweis: " + text)


## Jeden Frame aufrufen (Spielzeit t)
func tick(t: float) -> void:
	if _done or _game.player.defeated:
		return
	if _natural:
		if t >= 900.0 and not _natural_info.has("defect_900"):
			_natural_info["defect_900"] = int(_game.player.stats.get("defected", 0))
		if t >= 1800.0 and not _natural_info.has("avg_1800"):
			_natural_info["avg_1800"] = _game.satisfaction_system.get_average(_game.player)
		return
	match _stage:
		0:
			if t >= 2.0:
				_s0()
				_stage = 1
		1:
			if t >= 5.0:
				_s1()
				_stage = 2
		2:
			if t >= 10.0:
				_s2()
				_stage = 3
		3:
			if t >= 13.0:
				_s2b()
				_stage = 4
		4:
			if t >= 60.0:
				_s3()
				_stage = 5
		5:
			if t >= 90.0:
				_s4()
				_stage = 6
		6:
			if t >= 100.0:
				_s5()
				_stage = 7
		7:
			if t >= 170.0:
				_s6()
				_stage = 8


# ---------------------------------------------------------------------------
# Stufen
# ---------------------------------------------------------------------------

## S0: Volk und Tageszeit
func _s0() -> void:
	var g := _game
	var player: Kingdom = g.player
	var dns: DayNightSystem = g.day_night_system
	_check(not player.people_id.is_empty() and player.people_id == GameSession.people_id, "Volk des Spielers: %s" % player.people_id)
	var people := DataDB.get_people(player.people_id)
	var base: Dictionary = people.get("base_bonus", {})
	if not base.is_empty():
		_check(player.modifier_sources.has("people:" + player.people_id), "Quelle people:%s gesetzt" % player.people_id)
	_check(DayNightSystem.PHASES.has(dns.get_phase()), "Tageszeit %s" % dns.get_phase())
	var unit := _sample_unit(player)
	var sight_before := unit.sight if unit != null else 0.0
	dns.debug_force_phase("night")
	var dn: Dictionary = player.modifier_sources.get("daynight", {})
	var night_bonus: Dictionary = people.get("night_bonus", {})
	var expected_sight := float(DataDB.dn("global.night.sight", 0.8)) * float(night_bonus.get("sight", 1.0))
	_check(absf(float(dn.get("sight", 1.0)) - expected_sight) < 0.01, "Nacht: Sicht-Faktor %.2f (erwartet %.2f)" % [
			float(dn.get("sight", 1.0)), expected_sight])
	for key in night_bonus:
		if str(key) != "sight":
			_check(dn.has(str(key)), "Nachtbonus des Volks gesetzt: %s" % key)
	_check(g.wild.mod("aggro_range") > 1.0, "Monster nachts aggressiver (aggro ×%.2f)" % g.wild.mod("aggro_range"))
	if unit != null:
		_check(unit.sight < sight_before, "%s sieht nachts weniger (%.1f → %.1f)" % [unit.get_display_name(), sight_before, unit.sight])
	dns.debug_force_phase("day")
	var dd: Dictionary = player.modifier_sources.get("daynight", {})
	var day_bonus: Dictionary = people.get("day_bonus", {})
	for key in day_bonus:
		_check(dd.has(str(key)), "Tagbonus des Volks gesetzt: %s" % key)
	_check(not dd.has("sight") or day_bonus.has("sight"), "Tags keine Nachtsicht-Strafe")
	dns.debug_force_phase("")
	var ai: Array = g.ai_system.get_ai_kingdoms()
	if not ai.is_empty():
		_ai0 = ai[0]
		var ai_people := DataDB.get_people(_ai0.people_id)
		var ok := true
		dns.debug_force_phase("night")
		for key in ai_people.get("night_bonus", {}):
			if not (_ai0.modifier_sources.get("daynight", {}) as Dictionary).has(str(key)):
				ok = false
		dns.debug_force_phase("")
		_check(ok, "KI-Reich %s: daynight nach Volk %s" % [_ai0.display_name, _ai0.people_id])
	_check(g.event_system.get_wanderer_kingdom() != null, "Reich „Wanderer“ angelegt")


## S1: Geländebonus und Zufriedenheit
func _s1() -> void:
	var g := _game
	var player: Kingdom = g.player
	var ps: PeopleSystem = g.people_system
	var people := DataDB.get_people(player.people_id)
	var bonus: Dictionary = people.get("terrain_bonus", {})
	var u := _sample_unit(player)
	var world: WorldData = g.world
	var center: Vector2i = world.world_to_cell(player.castle.get_center())
	var found := Vector2i(-1, -1)
	var biome_id := ""
	for r in range(1, 61):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r or found.x >= 0:
					continue
				var c := center + Vector2i(dx, dy)
				if not world.in_bounds(c) or g.nav.is_solid(c):
					continue
				var bid := str(world.get_biome(c).get("id", ""))
				if bonus.has(bid):
					found = c
					biome_id = bid
		if found.x >= 0:
			break
	if u == null or found.x < 0:
		_note("Geländebonus übersprungen (keine passende Kachel)")
	else:
		var old_pos := u.position
		var key := str((bonus[biome_id] as Dictionary).keys()[0])
		var stat := "damage_taken" if key == "defense" else key
		# Wert ohne Geländebonus (die Einheit kann schon auf passendem Gelände stehen)
		u.terrain_mods = {}
		u.refresh_stats()
		var before := float(u.get(stat))
		u.position = world.cell_to_world(found)
		ps.refresh_unit(u, true)
		_check(not u.terrain_mods.is_empty() and not is_equal_approx(float(u.get(stat)), before),
				"Gelände %s: %s %.2f → %.2f (%s)" % [biome_id, stat, before, float(u.get(stat)), ps.get_terrain_text(u)])
		u.position = old_pos
		ps.refresh_unit(u, true)
	var ss: SatisfactionSystem = g.satisfaction_system
	var ok := true
	for v in player.units:
		if ss.is_inhabitant(v) and (v.satisfaction < 0.0 or v.satisfaction > 100.0):
			ok = false
	_check(ok, "Zufriedenheit aller Bewohner in 0–100")
	_check(ss.get_average(player) > 0.0, "Ø-Zufriedenheit %.1f" % ss.get_average(player))
	var has_base := false
	for p in ss.get_breakdown(player):
		if str(p["cause"]) == "Grundstimmung":
			has_base = true
	_check(has_base, "Ursachen enthalten „Grundstimmung“")


## S2: Zufriedenheit sinkt, Überlaufen, Verrat
func _s2() -> void:
	var g := _game
	var player: Kingdom = g.player
	var ss: SatisfactionSystem = g.satisfaction_system
	ss.debug_set_all(player, 5.0)
	var u := ss.debug_force_defection(player)
	_check(u != null and u.command == "defect" and ss.is_defector(u), "Überläufer unterwegs (%s)" % (ss.get_defector_text(u) if u != null else "-"))
	if u != null:
		_defector_uid = u.uid
	var esp: EspionageSystem = g.get("espionage_system")
	if esp != null and _ai0 != null:
		var aw0 := esp.get_awareness(_ai0, player)
		_check(ss.debug_force_betrayal(player, _ai0), "Verrat erzwungen")
		_check(esp.get_awareness(_ai0, player) >= minf(aw0 + 10.0, 100.0) and esp.get_intel_level(_ai0, player) >= 2,
				"Verrat: Aufmerksamkeit %.1f → %.1f, Kundschaft %d" % [aw0, esp.get_awareness(_ai0, player), esp.get_intel_level(_ai0, player)])
	else:
		_note("Verrat übersprungen (keine Spionage oder kein KI-Reich)")


func _s2b() -> void:
	var ss: SatisfactionSystem = _game.satisfaction_system
	var low := 1.0
	for u in _game.player.units:
		if ss.is_inhabitant(u) and not ss.is_defector(u):
			low = minf(low, u.work_mult)
	_check(low < 0.75, "Arbeitsleistung unzufriedener Bewohner ×%.2f" % low)


## S3: jedes Ereignis erzwingen (nach dem Heldentest: die Welle stört ihn sonst)
func _s3() -> void:
	var g := _game
	var player: Kingdom = g.player
	var es: EventSystem = g.event_system
	for id in ["drought", "plague", "magic_storm", "monster_wave", "harvest_festival", "mana_bloom"]:
		var reason := es.debug_trigger(id, player)
		_check(reason.is_empty(), "Ereignis %s ausgelöst %s" % [id, reason])
	var drought := false
	for source in player.modifier_sources:
		if str(source).begins_with("event:drought#"):
			drought = absf(float((player.modifier_sources[source] as Dictionary).get("production.food", 1.0)) - 0.5) < 0.01
	_check(drought, "Dürre: production.food ×0,5")
	var infected := 0
	var with_effect := 0
	for u in player.units:
		if es.is_infected(u):
			infected += 1
			for e in u.effects:
				if str(e.get("source", "")) == "event:plague":
					with_effect += 1
					break
	_check(infected >= 1 and with_effect == infected, "Seuche: %d Kranke mit Wirkung" % infected)
	for ev in es.active:
		if str(ev["kind"]) == "magic_storm":
			_check(float(ev["radius"]) > 0.0, "Magiesturm mit Radius %.0f" % float(ev["radius"]))
			if (ev["data"]["affected"] as Array).has(player.id):
				_check(player.mod("spell_cost") < 1.0, "Sturm: Zauber billiger (×%.2f)" % player.mod("spell_cost"))
		if str(ev["kind"]) == "monster_wave":
			_wave_raid = int(ev["data"]["raid_id"])
	var raid: Dictionary = g.monster_system.get_raid(_wave_raid)
	_check(not raid.is_empty() and int(raid["target_id"]) == player.id and (raid["uids"] as Array).size() >= 3,
			"Monsterwelle mit %d Monstern" % (raid.get("uids", []) as Array).size())
	var harvest := false
	for p in es.get_satisfaction_parts(player):
		if str(p[0]) == "Erntedank":
			harvest = true
	_check(harvest, "Erntedank in den Zufriedenheits-Ursachen")
	_check(g.hud.event_banner.get_chip_count() >= 3, "Ereignisleiste: %d Karten" % g.hud.event_banner.get_chip_count())
	# Flüchtlinge aufnehmen
	_pop_before = player.get_population()
	_check(es.debug_trigger("refugees", player).is_empty(), "Flüchtlinge ausgelöst")
	var offers := es.get_offers(player)
	_check(offers.size() == 1, "Genau ein Angebot an den Spieler (%d)" % offers.size())
	if offers.size() == 1:
		var n := (offers[0]["uids"] as Array).size()
		var reason := es.accept_offer(player, int(offers[0]["id"]))
		_check(reason.is_empty() and player.get_population() == _pop_before + n,
				"Flüchtlinge aufgenommen: Bevölkerung %d → %d (+%d) %s" % [_pop_before, player.get_population(), n, reason])
		var grateful := false
		for u in player.units:
			for p in g.satisfaction_system.get_unit_breakdown(u):
				if str(p["cause"]).begins_with("Dankbar"):
					grateful = true
		_check(grateful, "Aufgenommene sind dankbar")
	# Wanderer abweisen
	_check(es.debug_trigger("wanderers", player).is_empty(), "Wanderer ausgelöst")
	offers = es.get_offers(player)
	if not offers.is_empty():
		var offer: Dictionary = offers[0]
		_check(es.reject_offer(player, int(offer["id"])).is_empty() and str(offer["state"]) == "leaving", "Wanderer abgewiesen, ziehen weiter")
	if _ai0 != null and not _ai0.defeated:
		_check(es.debug_trigger("refugees", _ai0).is_empty(), "Flüchtlinge zur KI ausgelöst")
		var ai_offers := es.get_offers(_ai0)
		if not ai_offers.is_empty():
			_ai_offer_id = int(ai_offers[0]["id"])


## S4: Wirkung und Aufräumen
func _s4() -> void:
	var g := _game
	var player: Kingdom = g.player
	var es: EventSystem = g.event_system
	var u: Variant = g.find_by_uid(_defector_uid)
	if u is Unit and (u as Unit).kingdom == player:
		_note("Überläufer noch unterwegs (%s, %.0f Kacheln von der Burg)" % [(u as Unit).command,
				(u as Unit).position.distance_to(player.castle.get_center()) / g.world.tile_size])
	elif not _defector_killed_by.is_empty() and int(player.stats.get("defected", 0)) == 0:
		_note("Überläufer wurde unterwegs getötet (%s)" % _defector_killed_by)
	else:
		_check(int(player.stats.get("defected", 0)) >= 1, "Überläufer ist gegangen (Statistik %d)" % int(player.stats.get("defected", 0)))
	var near := false
	var raid: Dictionary = g.monster_system.get_raid(_wave_raid)
	for uid in raid.get("uids", []):
		var m: Variant = g.find_by_uid(int(uid))
		if m is Unit and (m as Unit).position.distance_to(player.castle.get_center()) <= 25.0 * g.world.tile_size:
			near = true
	_check(_attack_seen or near or raid.is_empty(), "Monsterwelle erreicht das Reich (Angriff %s, nah %s)" % [str(_attack_seen), str(near)])
	if _ai_offer_id > 0:
		_check(es.get_offer(_ai_offer_id).is_empty() or str(es.get_offer(_ai_offer_id)["state"]) == "leaving",
				"KI hat über die Flüchtlinge entschieden")
	es.debug_end_all()
	var left := false
	for source in player.modifier_sources:
		if str(source).begins_with("event:"):
			left = true
	_check(not left, "Keine Ereignis-Quellen mehr")
	var plague_left := false
	for v in player.units:
		for e in v.effects:
			if str(e.get("source", "")) == "event:plague":
				plague_left = true
	_check(not plague_left, "Keine Seuchenwirkung mehr")
	_check(es.get_active(player).is_empty(), "Keine aktiven Ereignisse mehr")
	# Restliche Wellenmonster entfernen (Ruhe für die übrigen Tests)
	for uid in raid.get("uids", []):
		var m: Variant = g.find_by_uid(int(uid))
		if m is Unit:
			g.unit_system.remove_unit(m)
	g.satisfaction_system.debug_set_all(player, 70.0)


## S5: Oberfläche
func _s5() -> void:
	var g := _game
	var player: Kingdom = g.player
	var hud: Node = g.hud
	hud.open_kingdom("satisfaction")
	var panel: KingdomPanel = hud.kingdom_panel
	panel.show_tab("events")
	panel.show_tab("people")
	_check(panel.is_open() and hud.is_kingdom_open(), "Reichsübersicht offen")
	panel.show_tab("satisfaction")
	player.resources["food"] = maxf(player.get_amount("food"), 500.0)
	player.resources["mana"] = maxf(player.get_amount("mana"), 50.0)
	panel._on_feast_pressed()
	_check(player.bonus_sources.has("feast"), "Fest gefeiert (Quelle „feast“)")
	hud.close_top_panel()
	_check(not hud.is_kingdom_open(), "Esc schliesst die Reichsübersicht")
	var es: EventSystem = g.event_system
	var pop := player.get_population()
	if es.debug_trigger("refugees", player).is_empty():
		var offers := es.get_offers(player)
		if not offers.is_empty():
			hud.open_refugee_dialog(int(offers[0]["id"]))
			_check(hud.refugee_dialog.is_open(), "Flüchtlingsdialog offen")
			hud.refugee_dialog._on_accept_pressed()
			_check(player.get_population() > pop and not hud.refugee_dialog.is_open(), "Dialog: aufgenommen (%d → %d)" % [pop, player.get_population()])
	if g.monster_system.debug_start_raid(player):
		print("[smoke] Phase 8: Monsterstreifzug gestartet")
	else:
		_note("keine Höhle mit Monstern für einen Streifzug")


## S6: Annäherung und Tag/Nacht-Wechsel
func _s6() -> void:
	var avg: float = _game.satisfaction_system.get_average(_game.player)
	_check(avg > 30.0, "Ø-Zufriedenheit nach der Annäherung %.1f" % avg)


func _sample_unit(k: Kingdom) -> Unit:
	if is_instance_valid(k.king):
		return k.king
	for u in k.units:
		if u.is_alive():
			return u
	return null


func report() -> void:
	var g := _game
	var ss: SatisfactionSystem = g.satisfaction_system
	for k in g.kingdoms:
		if not ss.is_tracked(k):
			continue
		print("[smoke] Phase 8 Reich %s (%s): Ø %.1f, Verteilung %s, Überläufer %d, empfangen %d, Verrat %d, Flüchtlinge %d, Feste %d" % [
				k.display_name, k.people_id, ss.get_average(k), str(ss.get_distribution(k)), int(k.stats.get("defected", 0)),
				int(k.stats.get("defectors_received", 0)), int(k.stats.get("betrayals", 0)), int(k.stats.get("refugees_accepted", 0)),
				int(k.stats.get("feasts", 0))])
	var es: EventSystem = g.event_system
	for h in es.get_history():
		var target: Kingdom = g.get_kingdom(int(h["target_id"]))
		print("[smoke] Phase 8 Ereignis %s → %s: %.0f–%.0f s, %s" % [h["event_id"], target.display_name if target != null else "?",
				float(h["started"]), float(h["ended"]), h["outcome"]])
	var ms: MonsterSystem = g.monster_system
	print("[smoke] Phase 8 Monster: %s, Lager %d → %d, laufende Streifzüge %d" % [str(ms.raid_stats), _lairs_start, ms.lairs.size(), ms.raids.size()])
	print("[smoke] Phase 8 Tageszeit-Wechsel: %d (Signal), %d (System)" % [_phase_changes, g.day_night_system.changes])
	for entry in [["Satisfaction", ss], ["Event", es], ["People", g.people_system]]:
		var sys: Object = entry[1]
		var n := maxi(int(sys.get("tick_count")), 1)
		print("[smoke] Phase 8 Takt %s: Ø %.3f ms, max %.3f ms (%d Takte)" % [entry[0], float(sys.get("tick_usec_total")) / n / 1000.0,
				float(sys.get("tick_usec_max")) / 1000.0, n])
	if _natural:
		print("[smoke] Phase 8 natürlich: %d Ereignisse, Überläufer bis 15 min: %s, Ø bei 30 min: %s" % [es.get_history().size() + es.active.size(),
				str(_natural_info.get("defect_900", "-")), str(_natural_info.get("avg_1800", "-"))])
		if _natural_info.has("defect_900"):
			_check(int(_natural_info["defect_900"]) == 0, "Kein Überläufer vor Minute 15")
	elif GameClock.game_time >= 590.0:
		_check(_phase_changes >= 1, "Mindestens ein Tageszeit-Wechsel (%d)" % _phase_changes)
	print("[smoke] Phase 8: %s" % ("OK" if _errors == 0 else "%d Fehler" % _errors))
