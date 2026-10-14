## Kingdom
##
## Ein Reich: Spieler, (ab Phase 7) computergesteuerter Gegner, (ab Phase 6)
## neutrales Dorf oder (ab Phase 8) wilde Monster. Hält Ressourcen, Gebäude
## und Einheiten. Alle Systeme arbeiten mit Kingdom-Objekten und sind damit
## nicht auf den Spieler festgelegt.
##
## Der gesamte Zustand liegt in einfachen Feldern, damit er sich später
## (Phase 10) speichern lässt – auch Zeitgeber und "schon gemeldet"-Merker.
class_name Kingdom
extends RefCounted

signal resources_changed
## Wird von den Systemen ausgelöst (Einheit neu/entfernt, Wohnraum geändert)
@warning_ignore("unused_signal")
signal population_changed
## Ein Modifikator hat sich geändert (Einheiten berechnen ihre Werte neu)
signal modifiers_changed

## Eindeutige Nummer (> 0). Wird auch im Gebietsraster gespeichert.
var id: int = 0
var faction_id: String = "good"
var display_name: String = ""
## Volk (peoples.json), z. B. "dwarves"; Dörfer ab Phase 6, Spieler/KI ab Phase 7/8 (wird gespeichert)
var people_id: String = ""
## Wer steuert das Reich: "player", "ai", "neutral" oder "wild"
var controller: String = "player"
var is_player: bool:
	get:
		return controller == "player"
var color := Color.WHITE
## Ressource -> Menge
var resources: Dictionary = {}
## Ressource -> Ertrag pro Spielminute (geglättet, vom EconomySystem gesetzt)
var income_rate: Dictionary = {}
## Gebäude-Nodes (auch Baustellen)
var buildings: Array = []
## Einheiten-Nodes (Bewohner, ab Phase 3 auch Kämpfer)
var units: Array = []
var castle: Building
## Der König (Einheit). Stirbt er, ist das Spiel für dieses Reich verloren.
var king: Unit = null
## Kampfpunkte für besiegte Feinde: ausgebbar (ab Phase 4 für Mana-Verbesserungen)
var kill_points: int = 0
## Alle je verdienten Kampfpunkte (Statistik)
var kill_points_total: int = 0
## Hat dieses Reich verloren (König tot oder Burg zerstört)?
var defeated: bool = false
## Beziehungen zu anderen Reichen: Kingdom.id -> "war" | "peace" | "alliance".
## Nicht eingetragen = Frieden. Wird über Game.set_relation gesetzt.
var relations: Dictionary = {}
## Armeen (Steuergruppen): Nummer 1–9 -> Array von Einheiten-uids
var armies: Dictionary = {}
## Formation für Marschbefehle dieses Reichs ("block" oder "line")
var formation: String = "block"
## Freigeschaltete Dinge (unit:<id>, building:<id>, spell:<id>, research:<id> …): ID -> true.
## Zwischenspeicher – entsteht aus unlock_sources (nur über grant_unlock/revoke_unlocks ändern).
var unlocks: Dictionary = {}
## Wer hat was freigeschaltet: Quelle ("research:<id>", ab Phase 6 "alliance:<dorf>") -> {ID: true}.
## So kann eine Quelle ihre Freischaltungen wieder entziehen, ohne andere zu stören.
var unlock_sources: Dictionary = {}
## Zuschläge (additiv), nach Quelle: Quelle -> {Schlüssel -> Wert}. bonus(key) summiert.
## Schlüssel: "cap.mana" (Mana-Maximum), "mana_regen" (Mana/s an der Burg).
var bonus_sources: Dictionary = {}
## Laufende Kosten, nach Quelle: Quelle ("spell:<id>" …) -> {Ressource -> pro Sekunde}.
## Das EconomySystem zieht sie jeden Takt ab.
var upkeep: Dictionary = {}
## Statistik für den Spielende-Bildschirm: Name -> Zahl ("summoned", "kills", "losses",
## "spells", ab Phase 7 "buildings_built", "kingdoms_defeated", "spies_caught", "spy_missions")
var stats: Dictionary = {}
## KI-Zustand (nur controller "ai"): einfache Werte, Bedeutung siehe AIBrain (wird gespeichert)
var ai_state: Dictionary = {}
# --- Forschung und Magie (Phase 4) ---
## Abgeschlossene Forschungen: ID -> true
var researched: Dictionary = {}
## Forschungs-Warteschlange (IDs, die erste wird gerade erforscht)
var research_queue: Array = []
## Fortschritt der aktiven Forschung in Sekunden
var research_progress: float = 0.0
## Zauber -> Spielzeit, ab der er wieder bereit ist
var spell_cooldowns: Dictionary = {}
## Zusätzliches Mana-Maximum (nur lesen; aus bonus_sources)
var mana_cap_bonus: float:
	get:
		return bonus("cap.mana")
## Mana pro Sekunde an der Burg (nur lesen; aus bonus_sources, mal Faktor "mana_regen")
var mana_regen: float:
	get:
		return bonus("mana_regen") * mod("mana_regen")
## Stufe der Mana-Verbesserungen (ID -> Stufe)
var mana_upgrades: Dictionary = {}
## Helden des Reichs (Phase 5): einfache Einträge, siehe HeroSystem
var heroes: Array = []
## Hat dieses Reich eine Wirtschaft (Nahrung, Wachstum)? Monster nicht.
var has_economy: bool = true
## Herrscht Hungersnot?
var starving: bool = false
## Fortschritt bis zum nächsten Bewohner (Spielsekunden)
var growth_timer := 0.0
## Merker für einmalige Meldungen u. Ä. (Name -> Wert)
var flags: Dictionary = {}
## Faktoren für Forschung, Schwierigkeit, Helden usw., nach Quelle getrennt:
## Quelle -> {Schlüssel -> Faktor}. mod(key) liefert das Produkt aller Quellen.
## Schlüssel (nicht gesetzt = 1.0):
## Wirtschaft: "gather", "gather.<res>", "build", "food_use", "growth",
##   "production", "production.<res>", "cap.<res>"
## Einheiten: "hp", "attack", "attack_interval", "range", "armor", "aggro_range",
##   "sight", "speed", "regen", "heal", "heal_range" – jeweils auch
##   "<wert>.<stufe>" (z. B. "attack.archer"); dazu "defense" (erlittener
##   Schaden wird geteilt), "summon" (Beschwörungstempo), "building_hp".
var modifier_sources: Dictionary = {}
## Produkt je Schlüssel (aus modifier_sources berechnet)
var modifiers: Dictionary = {}

## Seit der letzten Messung eingenommene/verbrauchte Mengen
var _income_acc: Dictionary = {}


func setup(p_id: int, p_faction_id: String, p_controller: String = "player") -> void:
	id = p_id
	faction_id = p_faction_id
	controller = p_controller
	var faction := DataDB.get_faction(faction_id)
	color = faction.get("color", Color.WHITE)
	has_economy = bool(faction.get("economy", true))
	display_name = "Dein Königreich" if is_player else "Reich %d" % id
	for r in DataDB.resources:
		resources[r["id"]] = 0.0
		income_rate[r["id"]] = 0.0
		_income_acc[r["id"]] = 0.0


## Faktor für einen Modifikator-Schlüssel (1.0 wenn nicht gesetzt)
func mod(key: String) -> float:
	return float(modifiers.get(key, 1.0))


## Setzt einen Faktor einer Quelle (z. B. "difficulty", "research:schmiede")
func set_modifier(source: String, key: String, factor: float) -> void:
	var entry: Dictionary = modifier_sources.get(source, {})
	entry[key] = factor
	modifier_sources[source] = entry
	_recompute_modifiers()


## Setzt mehrere Faktoren einer Quelle auf einmal (Einheiten rechnen nur einmal neu)
func set_modifiers(source: String, factors: Dictionary) -> void:
	var entry: Dictionary = modifier_sources.get(source, {})
	for key in factors:
		entry[key] = float(factors[key])
	modifier_sources[source] = entry
	_recompute_modifiers()


## Entfernt alle Faktoren einer Quelle
func clear_modifiers(source: String) -> void:
	if modifier_sources.erase(source):
		_recompute_modifiers()


func _recompute_modifiers() -> void:
	modifiers.clear()
	for source in modifier_sources:
		var entry: Dictionary = modifier_sources[source]
		for key in entry:
			modifiers[key] = float(modifiers.get(key, 1.0)) * float(entry[key])
	modifiers_changed.emit()


## Schaltet etwas frei (Quelle merken, damit sie es später wieder entziehen kann)
func grant_unlock(source: String, unlock_id: String) -> void:
	var entry: Dictionary = unlock_sources.get(source, {})
	entry[unlock_id] = true
	unlock_sources[source] = entry
	unlocks[unlock_id] = true


## Entzieht alle Freischaltungen einer Quelle (andere Quellen bleiben gültig)
func revoke_unlocks(source: String) -> void:
	if not unlock_sources.erase(source):
		return
	unlocks.clear()
	for src in unlock_sources:
		for unlock_id in unlock_sources[src]:
			unlocks[unlock_id] = true


func has_unlock(unlock_id: String) -> bool:
	return unlocks.has(unlock_id)


## Sind alle Freischaltungen der Liste vorhanden?
func has_all_unlocks(ids: Array) -> bool:
	for unlock_id in ids:
		if not unlocks.has(unlock_id):
			return false
	return true


## Additiver Zuschlag einer Quelle (ersetzt den alten Wert der Quelle für diesen Schlüssel)
func set_bonus(source: String, key: String, value: float) -> void:
	var entry: Dictionary = bonus_sources.get(source, {})
	entry[key] = value
	bonus_sources[source] = entry
	resources_changed.emit()


func clear_bonuses(source: String) -> void:
	if bonus_sources.erase(source):
		resources_changed.emit()


## Summe aller Zuschläge für einen Schlüssel
func bonus(key: String) -> float:
	var total := 0.0
	for src in bonus_sources:
		total += float(bonus_sources[src].get(key, 0.0))
	return total


## Laufende Kosten einer Quelle setzen (pro Sekunde), z. B. {"mana": 0.5}
func set_upkeep(source: String, cost: Dictionary) -> void:
	upkeep[source] = cost.duplicate()


func clear_upkeep(source: String) -> void:
	upkeep.erase(source)


## Summe der laufenden Kosten einer Ressource pro Sekunde
func get_upkeep(res_id: String) -> float:
	var total := 0.0
	for src in upkeep:
		total += float(upkeep[src].get(res_id, 0.0))
	return total


## Beziehung zu einem anderen Reich ("war", "peace", "alliance"); eigenes Reich = "self"
func get_relation(other: Kingdom) -> String:
	if other == self:
		return "self"
	return str(relations.get(other.id, "peace"))


## Zählt einen Statistikwert hoch
func add_stat(key: String, amount: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


## Meldung an den Spieler – nur wenn dieses Reich vom Spieler gesteuert wird.
## world_pos: Vector2 (Klick springt hin), null oder ein Verweis (siehe Notify.post).
func notify(text: String, kind: String = "info", world_pos: Variant = null) -> void:
	if is_player:
		Notify.post(text, kind, world_pos)


func get_amount(res_id: String) -> float:
	return float(resources.get(res_id, 0.0))


## Lagergrenze einer Ressource ("cap" in resources.json, sonst unbegrenzt)
func get_capacity(res_id: String) -> float:
	var cap: Variant = DataDB.get_resource(res_id).get("cap", null)
	if cap == null:
		return INF
	return float(cap) * mod("cap." + res_id) + bonus("cap." + res_id)


## Fügt eine Menge hinzu (negativ = Verbrauch). Bestand bleibt zwischen 0 und Lagergrenze.
func add_resource(res_id: String, amount: float) -> void:
	if amount == 0.0:
		return
	var before := get_amount(res_id)
	# Über dem Maximum (z. B. nach Erstattung) wird nichts abgezogen, nur nichts mehr dazu
	var after := maxf(before + amount, 0.0)
	if amount > 0.0:
		after = minf(after, maxf(get_capacity(res_id), before))
	resources[res_id] = after
	_income_acc[res_id] = float(_income_acc.get(res_id, 0.0)) + (after - before)
	resources_changed.emit()


func can_afford(cost: Dictionary) -> bool:
	for res_id in cost:
		if get_amount(res_id) + 0.0001 < float(cost[res_id]):
			return false
	return true


## Zieht die Kosten ab. Gibt false zurück (und zieht nichts ab), wenn es nicht reicht.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for res_id in cost:
		resources[res_id] = maxf(get_amount(res_id) - float(cost[res_id]), 0.0)
	resources_changed.emit()
	return true


## Erstattung: darf das Lagermaximum überschreiten (Erstattetes geht nie verloren)
func refund(cost: Dictionary, factor: float = 1.0) -> void:
	for res_id in cost:
		resources[res_id] = get_amount(res_id) + float(cost[res_id]) * factor
	resources_changed.emit()


## "Es fehlen: 10 Holz, 5 Stein" – leer, wenn alles bezahlbar ist.
func missing_text(cost: Dictionary) -> String:
	var missing := {}
	for res_id in cost:
		var lack := float(cost[res_id]) - get_amount(res_id)
		if lack > 0.0001:
			missing[res_id] = lack
	if missing.is_empty():
		return ""
	return "Es fehlen: " + DataDB.cost_to_text(missing)


## Wohnplätze aller fertigen Gebäude
func get_housing() -> int:
	var total := 0
	for b in buildings:
		if b.constructed:
			total += int(b.def.get("housing", 0))
	return total


## Bevölkerung = Einheiten, die Wohnraum brauchen: Bewohner und beschworene
## Einheiten, die einen Beruf haben (wer arbeitet, wohnt im Dorf).
func get_population() -> int:
	var n := 0
	for u in units:
		if u.type_def.get("needs_housing", false) or (u.role != "worker" and u.job_id != "idle"):
			n += 1
	return n


## Gibt die seit dem letzten Aufruf eingenommenen Mengen zurück und setzt sie zurück.
func take_income_sample() -> Dictionary:
	var sample := _income_acc
	_income_acc = {}
	for res_id in sample:
		_income_acc[res_id] = 0.0
	return sample
