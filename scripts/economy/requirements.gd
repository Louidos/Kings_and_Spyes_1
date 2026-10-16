## Requirements
##
## Gemeinsame Bedingungsprüfung für Bewerber (recruits.json) und Helden (heroes.json →
## requirements). Eine Bedingung ist ein Dictionary mit "type" und Werten:
##   housing                        freier Wohnplatz
##   gift          {"cost": {...}}  Begrüssungsgeschenk (wird beim Aufnehmen bezahlt)
##   building      {"building", "level"}  fertiges Gebäude (mindestens auf dieser Stufe)
##   satisfaction  {"min"}          Ø-Zufriedenheit der Bewohner
##   castle_level  {"min"}          Mindest-Burgstufe
##   upgraded      {"count"}        so viele Gebäude mindestens auf Stufe II
##   no_famine                      keine Hungersnot
##   research      {"research"}     erforscht (id aus research.json, oder "alias" je Fraktion)
##   kills         {"count"}        besiegte Feinde (Statistik "kills")
##   lairs         {"count"}        zerstörte Monsterhöhlen (Statistik "lairs_destroyed")
##   population    {"min"}          Mindestzahl Bewohner
## Dieselben Prüfungen gelten für Spieler und KI.
class_name Requirements
extends RefCounted


## {"ok": bool, "text": "Freier Wohnplatz (frei: 2)"} für eine Bedingung
static func check(req: Dictionary, k: Kingdom, game: Node) -> Dictionary:
	var type := str(req.get("type", ""))
	match type:
		"housing":
			var free := k.get_housing() - k.get_population()
			return {"ok": free > 0, "text": "Freier Wohnplatz (frei: %d)" % maxi(free, 0)}
		"gift":
			var cost: Dictionary = req.get("cost", {})
			return {"ok": k.can_afford(cost), "text": "Begrüssungsgeschenk: %s" % DataDB.cost_to_text(cost)}
		"building":
			var id := str(req.get("building", ""))
			var level := maxi(int(req.get("level", 1)), 1)
			var bname := DataDB.get_building_name(DataDB.get_building(id), k.faction_id)
			var text := ("%s auf Stufe %s" % [bname, DataDB.level_numeral(level)]) if level > 1 else "Fertiges Gebäude: %s" % bname
			return {"ok": BuildingSystem.count_of(k, id, level) > 0, "text": text}
		"satisfaction":
			var need := float(req.get("min", 50))
			var avg := satisfaction_of(k, game)
			return {"ok": avg >= need, "text": "Zufriedenheit mindestens %d (jetzt %d)" % [roundi(need), roundi(avg)]}
		"castle_level":
			var need := int(req.get("min", 1))
			return {"ok": k.get_castle_level() >= need,
					"text": "Burgstufe %d (%s)" % [need, DataDB.castle_level_name(need)]}
		"upgraded":
			var need := int(req.get("count", 1))
			var have := BuildingSystem.count_of(k, "", 2)
			return {"ok": have >= need, "text": "%d Gebäude auf Stufe II (jetzt %d)" % [need, have]}
		"no_famine":
			return {"ok": not k.starving, "text": "Keine Hungersnot"}
		"research":
			var id := research_id(req, k)
			return {"ok": k.researched.has(id),
					"text": "Forschung: %s" % str(DataDB.get_research(id).get("name", id))}
		"kills":
			var need := int(req.get("count", 1))
			var have := int(k.stats.get("kills", 0))
			return {"ok": have >= need, "text": "%d besiegte Feinde (jetzt %d)" % [need, have]}
		"lairs":
			var need := int(req.get("count", 1))
			var have := int(k.stats.get("lairs_destroyed", 0))
			return {"ok": have >= need, "text": "%d zerstörte Monsterhöhle%s (jetzt %d)" % [need, "" if need == 1 else "n", have]}
		"population":
			var need := int(req.get("min", 1))
			return {"ok": k.get_population() >= need, "text": "%d Bewohner (jetzt %d)" % [need, k.get_population()]}
	return {"ok": false, "text": "Unbekannte Bedingung: %s" % type}


## Alle Bedingungen: [{"ok", "text"}, …]
static func check_all(reqs: Array, k: Kingdom, game: Node) -> Array:
	var out: Array = []
	for r in reqs:
		if r is Dictionary:
			out.append(check(r, k, game))
	return out


## Sind alle erfüllt?
static func all_met(reqs: Array, k: Kingdom, game: Node) -> bool:
	for r in reqs:
		if r is Dictionary and not bool(check(r, k, game)["ok"]):
			return false
	return true


## Erste fehlende Bedingung als Text ("" = alle erfüllt)
static func first_missing(reqs: Array, k: Kingdom, game: Node) -> String:
	for r in reqs:
		if not (r is Dictionary):
			continue
		var res := check(r, k, game)
		if not bool(res["ok"]):
			return "Fehlt: " + str(res["text"])
	return ""


## Zeilen "✓ …" / "✗ …"
static func lines(reqs: Array, k: Kingdom, game: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for res in check_all(reqs, k, game):
		out.append(("✓ " if bool(res["ok"]) else "✗ ") + str(res["text"]))
	return out


## Ø-Zufriedenheit der Bewohner (ohne Bewohner bzw. ohne System: 50)
static func satisfaction_of(k: Kingdom, game: Node) -> float:
	var ss: Variant = game.get("satisfaction_system")
	if ss == null:
		return 50.0
	var avg := float(ss.get_average(k))
	return avg if avg >= 0.0 else 50.0


## Forschungs-id einer Bedingung: "research" direkt oder "alias": {"good": …, "evil": …}
static func research_id(req: Dictionary, k: Kingdom) -> String:
	var alias: Variant = req.get("alias", null)
	if alias is Dictionary:
		return str((alias as Dictionary).get(k.faction_id, ""))
	return str(req.get("research", ""))
