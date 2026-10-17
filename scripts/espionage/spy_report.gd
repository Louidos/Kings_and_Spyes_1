## SpyReport
##
## Spionagebericht über ein Reich oder Dorf: ein Schnappschuss des Spielzustands zum
## Zeitpunkt der Kundschaft (EspionageSystem.make_report, gespeichert in
## EspionageSystem.reports) und seine Darstellung je nach Kundschaftsstufe
## (espionage.json → report):
##   Stufe 1 – Schätzungen ("etwa 20–30 Truppen"), keine Einzelheiten
##   Stufe 2 – genaue Zahlen (Truppen je Typ, Helden, Verteidigung, Vorräte, Forschung)
##   Stufe 3 – alles, dazu die Pläne (Angriffsziel, worauf gespart wird, Aufmerksamkeit)
## Ältere Berichte als report.stale_seconds erscheinen grau.
class_name SpyReport
extends RefCounted

const COLOR_HEAD := "#e8d7a8"
const COLOR_OLD := "#8a8a8a"
const STATE_NAMES := {"gather": "sammelt sich", "march": "ist unterwegs", "fight": "kämpft", "retreat": "zieht sich zurück"}


## Schnappschuss von target (alle Zahlen genau; gezeigt wird je nach level)
static func build(game: Node, viewer: Kingdom, target: Kingdom, level: int, source: String) -> Dictionary:
	var vs: VillageSystem = game.village_system
	var village := vs.is_village_kingdom(target)
	var troops := {}
	var total := 0
	var power := 0.0
	for u in target.units:
		var unit: Unit = u
		if not EspionageSystem.is_army_unit(unit) and not (village and unit.tier == "militia" and unit.is_alive()):
			continue
		if unit.role == "hero":
			continue
		var name := str(unit.type_def.get("name", unit.type_id))
		troops[name] = int(troops.get(name, 0)) + 1
		total += 1
		power += VillageSystem.unit_power(unit)
	var heroes: Array = []
	for rec in target.heroes:
		var r: Dictionary = rec
		heroes.append({"name": str(r.get("name", "?")), "type": str(DataDB.get_hero_type(str(r.get("type_id", ""))).get("name", "")),
				"level": int(r.get("level", 1)), "dead": bool(r.get("dead", false))})
		var hu: Unit = game.hero_system.get_unit(target, int(r.get("id", 0)))
		if hu != null and hu.is_alive():
			power += VillageSystem.unit_power(hu)
	# Der König verteidigt die Burg mit (zählt zur Stärke, nicht zu den Truppen)
	if target.king != null and is_instance_valid(target.king) and target.king.is_alive():
		power += VillageSystem.unit_power(target.king)
	var towers := 0
	var walls := 0
	var gates := 0
	var tower_power := 0.0
	var buildings := 0
	for b in target.buildings:
		var bld: Building = b
		if not bld.constructed:
			continue
		match str(bld.def.get("fortification", "")):
			"tower":
				towers += 1
				var t: Dictionary = bld.def.get("tower", {})
				tower_power += bld.max_hp * float(t.get("attack", 0.0)) / maxf(float(t.get("interval", 1.0)), 0.1) / 100.0
			"wall":
				walls += 1
			"gate":
				gates += 1
		if not bld.is_segment:
			buildings += 1
	var research := {}
	var rs: ResearchSystem = game.research_system
	var active := rs.get_active(target)
	if not active.is_empty():
		research = {"name": str(DataDB.get_research(active).get("name", active)), "progress": rs.get_progress_ratio(target)}
	var stock := {}
	for res in target.resources:
		if float(target.resources[res]) >= 1.0:
			stock[res] = floorf(float(target.resources[res]))
	return {
		"at": GameClock.game_time, "level": clampi(level, 1, 3), "source": source, "target_id": target.id,
		"village": village, "troops": troops, "troop_total": total, "army_power": roundf(power),
		"heroes": heroes, "towers": towers, "walls": walls, "gates": gates,
		"defense_power": roundf(power + tower_power), "buildings": buildings,
		"castle_level": 0 if village else target.get_castle_level(), "population": target.get_population(),
		"resources": stock, "research": research, "alliances": _alliances(game, target, village),
		"departing": _departing(game, target), "plans": _plans(game, viewer, target),
	}


## Verträge und Bündnisse des Ziels als Texte
static func _alliances(game: Node, target: Kingdom, village: bool) -> Array:
	var ds: DiplomacySystem = game.diplomacy_system
	var list: Array = []
	if village:
		var t := ds.get_treaty(target)
		if not t.is_empty():
			var partner: Kingdom = game.get_kingdom(int(t["partner_id"]))
			if partner != null:
				list.append("%s mit %s" % [DiplomacySystem.treaty_name(str(t["type"])), partner.display_name])
		return list
	for t in ds.get_treaties_of(target):
		list.append("%s mit %s" % [DiplomacySystem.treaty_name(str(t["type"])), (t["village"] as Kingdom).display_name])
	for o in game.kingdoms:
		var other: Kingdom = o
		if other != target and not other.defeated and other.controller != "wild" and game.are_allied(target, other) \
				and not ds.is_party(other):
			list.append("Bündnis mit %s" % other.display_name)
	return list


## Armeen, die gerade aufbrechen oder unterwegs sind (KI-Welle)
static func _departing(game: Node, target: Kingdom) -> Array:
	var list: Array = []
	var wave: Dictionary = target.ai_state.get("wave", {})
	if wave.is_empty():
		return list
	var goal: Kingdom = game.get_kingdom(int(wave.get("target_id", 0)))
	var goal_name := goal.display_name if goal != null else ("ein Monsterlager" if str(wave.get("target_kind", "")) == "lair" else "?")
	list.append({"target": goal_name, "target_id": goal.id if goal != null else 0, "units": (wave.get("uids", []) as Array).size(),
			"state": str(wave.get("state", "gather"))})
	return list


## Pläne der KI (nur Stufe 3): Ziel, worauf gespart wird, Haltung gegenüber dem Betrachter
static func _plans(game: Node, viewer: Kingdom, target: Kingdom) -> Array:
	var list: Array = []
	if target.controller != "ai":
		return list
	var st: Dictionary = target.ai_state
	var pers: Dictionary = game.ai_system.get_personality(target)
	if not pers.is_empty():
		list.append("Haltung: %s" % str(pers.get("name", "")))
	var waiting: Dictionary = st.get("build_waiting", {})
	if not waiting.is_empty():
		var def := DataDB.get_building(str(waiting.get("building", "")))
		list.append("Spart auf: %s" % DataDB.get_building_name(def, target.faction_id))
	if not str(st.get("hero_saving", "")).is_empty():
		list.append("Spart auf einen Helden: %s" % str(DataDB.get_hero_type(str(st["hero_saving"])).get("name", "")))
	if bool(st.get("castle_saving", false)):
		list.append("Spart auf den Ausbau der Burg")
	var esp: EspionageSystem = game.espionage_system
	if viewer != null and esp.is_party(viewer) and esp.is_party(target):
		var tier := esp.get_awareness_tier(target, viewer)
		list.append("Aufmerksamkeit auf dich: %d %% (%s)" % [roundi(esp.get_awareness(target, viewer)),
				EspionageSystem.awareness_tier_name(tier)])
		if tier >= 2:
			var diff: Dictionary = game.ai_system.get_difficulty()
			var first := float(diff.get("first_attack_minutes", 45)) * 60.0
			var last_end := float(st.get("last_wave_end", -1.0))
			var next := maxf(first, last_end + float(diff.get("wave_interval", 900)) if last_end >= 0.0 else first)
			if next > GameClock.game_time:
				list.append("Angriff auf dich frühestens in %d Min." % ceili((next - GameClock.game_time) / 60.0))
			else:
				list.append("Plant Angriffe auf dich")
	return list


# ---------------------------------------------------------------------------
# Darstellung
# ---------------------------------------------------------------------------

## Alter als Text ("gerade eben", "vor 3 Min.")
static func age_text(age: float) -> String:
	if age < 60.0:
		return "gerade eben"
	if age < 3600.0:
		return "vor %d Min." % floori(age / 60.0)
	return "vor %d Std. %d Min." % [floori(age / 3600.0), floori(fmod(age, 3600.0) / 60.0)]


## Ist der Bericht veraltet (grau)?
static func is_stale(report: Dictionary) -> bool:
	return GameClock.game_time - float(report.get("at", 0.0)) > float(DataDB.esp("report.stale_seconds", 900))


## Bericht als BBCode (RichTextLabel). Ohne Bericht: "unbekannt".
static func format(report: Dictionary) -> String:
	if report.is_empty():
		return "[color=%s][b]Spionagebericht:[/b][/color] unbekannt – schicke einen Spion zum Auskundschaften (Reiter Spione)." % COLOR_HEAD
	var level := int(report.get("level", 1))
	var exact := level >= int(DataDB.esp("report.exact_from_level", 2))
	var plans := level >= int(DataDB.esp("report.plans_from_level", 3))
	var names: Array = DataDB.esp("intel.names", ["Unbekannt", "Gerüchte", "Bericht", "Genau"])
	var age := GameClock.game_time - float(report.get("at", 0.0))
	var stale := is_stale(report)
	var lines: PackedStringArray = []
	lines.append("[color=%s][b]Spionagebericht[/b] · %s · %s · Quelle: %s%s[/color]" % [COLOR_HEAD, age_text(age),
			str(names[clampi(level, 0, names.size() - 1)]), str(report.get("source", "Spion")), " · veraltet" if stale else ""])
	var seed_value := int(report.get("target_id", 0)) * 7919 + int(float(report.get("at", 0.0)))
	# Truppen
	var total := int(report.get("troop_total", 0))
	var troops: Dictionary = report.get("troops", {})
	if exact:
		var parts: PackedStringArray = []
		var keys := troops.keys()
		keys.sort()
		for t in keys:
			parts.append("%d× %s" % [int(troops[t]), str(t)])
		lines.append("[b]Truppen:[/b] %d%s" % [total, (" – " + ", ".join(parts)) if not parts.is_empty() else ""])
	else:
		var kinds := troops.keys()
		kinds.sort()
		lines.append("[b]Truppen:[/b] %s%s" % [_range(total, seed_value), (" (%s)" % ", ".join(PackedStringArray(kinds))) if not kinds.is_empty() else ""])
	# Helden
	var heroes: Array = report.get("heroes", [])
	if heroes.is_empty():
		lines.append("[b]Helden:[/b] keine")
	elif exact:
		var hs: PackedStringArray = []
		for h in heroes:
			var hd: Dictionary = h
			hs.append("%s (%s, Stufe %d%s)" % [str(hd["name"]), str(hd["type"]), int(hd["level"]), ", gefallen" if bool(hd["dead"]) else ""])
		lines.append("[b]Helden:[/b] %s" % ", ".join(hs))
	else:
		lines.append("[b]Helden:[/b] %d" % heroes.size())
	# Verteidigung
	var towers := int(report.get("towers", 0))
	var walls := int(report.get("walls", 0))
	var gates := int(report.get("gates", 0))
	var defense := int(report.get("defense_power", 0))
	if exact:
		lines.append("[b]Verteidigung:[/b] Türme %d, Mauerstücke %d, Tore %d · Gesamtstärke %d (davon Heer und König %d)" % [
				towers, walls, gates, defense, int(report.get("army_power", 0))])
	else:
		lines.append("[b]Verteidigung:[/b] %s · Gesamtstärke %s" % ["befestigt" if towers + walls > 0 else "kaum befestigt",
				_range(defense, seed_value + 3)])
	# Burg, Bewohner, Gebäude
	if bool(report.get("village", false)):
		lines.append("[b]Dorf:[/b] %s Gebäude · %s Bewohner" % [_num(int(report.get("buildings", 0)), exact, seed_value + 5),
				_num(int(report.get("population", 0)), exact, seed_value + 7)])
	else:
		lines.append("[b]Burgstufe:[/b] %d (%s) · %s Gebäude · %s Bewohner" % [int(report.get("castle_level", 1)),
				DataDB.castle_level_name(int(report.get("castle_level", 1))), _num(int(report.get("buildings", 0)), exact, seed_value + 5),
				_num(int(report.get("population", 0)), exact, seed_value + 7)])
	# Vorräte und Forschung
	var stock: Dictionary = report.get("resources", {})
	if exact:
		lines.append("[b]Vorräte:[/b] %s" % (DataDB.cost_to_text(stock) if not stock.is_empty() else "leer"))
		var research: Dictionary = report.get("research", {})
		if research.is_empty():
			lines.append("[b]Forschung:[/b] keine laufende")
		else:
			lines.append("[b]Forschung:[/b] %s (%d %%)" % [str(research["name"]), roundi(float(research["progress"]) * 100.0)])
	else:
		var sum := 0.0
		for res in stock:
			sum += float(stock[res])
		lines.append("[b]Vorräte:[/b] insgesamt %s" % _range(roundi(sum), seed_value + 11))
		lines.append("[b]Forschung:[/b] unbekannt")
	# Bündnisse
	var alliances: Array = report.get("alliances", [])
	lines.append("[b]Bündnisse:[/b] %s" % (", ".join(PackedStringArray(alliances)) if not alliances.is_empty() else "keine"))
	# Aufbrechende Armeen
	for d in report.get("departing", []):
		var dd: Dictionary = d
		var who := "%d Einheiten" % int(dd["units"]) if exact else "Ein Heer"
		lines.append("[b]Armee:[/b] %s %s – Ziel: %s" % [who, str(STATE_NAMES.get(str(dd["state"]), str(dd["state"]))),
				str(dd["target"]) if exact else "unbekannt"])
	if plans:
		for p in report.get("plans", []):
			lines.append("[b]Plan:[/b] %s" % str(p))
	var text := "\n".join(lines)
	if stale:
		text = "[color=%s]%s[/color]" % [COLOR_OLD, text]
	return text


## Zahl genau oder geschätzt
static func _num(value: int, exact: bool, seed_value: int) -> String:
	return str(value) if exact else _range(value, seed_value)


## Schätzung "etwa 20–30" (Spanne report.estimate_spread, je Bericht fest verschoben)
static func _range(value: int, seed_value: int) -> String:
	if value <= 0:
		return "kaum"
	var spread := clampf(float(DataDB.esp("report.estimate_spread", 0.3)), 0.05, 0.9)
	var skew := (float(posmod(hash(seed_value), 1001)) / 1000.0 - 0.5) * spread
	var center := float(value) * (1.0 + skew)
	var step := 5 if center >= 20.0 else 1
	var low := maxi(floori(center * (1.0 - spread) / step) * step, 0)
	var high := maxi(ceili(center * (1.0 + spread) / step) * step, low + step)
	return "etwa %d–%d" % [low, high]
