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

## Eindeutige Nummer (> 0). Wird auch im Gebietsraster gespeichert.
var id: int = 0
var faction_id: String = "good"
var display_name: String = ""
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
## Punkte für besiegte Feinde (ab Phase 4 für Mana-Verbesserungen)
var kill_points: int = 0
## Herrscht Hungersnot?
var starving: bool = false
## Fortschritt bis zum nächsten Bewohner (Spielsekunden)
var growth_timer := 0.0
## Merker für einmalige Meldungen u. Ä. (Name -> Wert)
var flags: Dictionary = {}
## Faktoren für Forschung, Schwierigkeit, Helden usw. (Schlüssel -> Faktor).
## Beispiele: "gather", "gather.wood", "build", "speed", "food_use",
## "growth", "production.food". Nicht gesetzt = 1.0.
var modifiers: Dictionary = {}

## Seit der letzten Messung eingenommene/verbrauchte Mengen
var _income_acc: Dictionary = {}


func setup(p_id: int, p_faction_id: String, p_controller: String = "player") -> void:
	id = p_id
	faction_id = p_faction_id
	controller = p_controller
	var faction := DataDB.get_faction(faction_id)
	color = faction.get("color", Color.WHITE)
	display_name = "Dein Königreich" if is_player else "Reich %d" % id
	for r in DataDB.resources:
		resources[r["id"]] = 0.0
		income_rate[r["id"]] = 0.0
		_income_acc[r["id"]] = 0.0


## Faktor für einen Modifikator-Schlüssel (1.0 wenn nicht gesetzt)
func mod(key: String) -> float:
	return float(modifiers.get(key, 1.0))


## Meldung an den Spieler – nur wenn dieses Reich vom Spieler gesteuert wird.
func notify(text: String, kind: String = "info", world_pos: Variant = null) -> void:
	if is_player:
		Notify.post(text, kind, world_pos)


func get_amount(res_id: String) -> float:
	return float(resources.get(res_id, 0.0))


## Lagergrenze einer Ressource ("cap" in resources.json, sonst unbegrenzt)
func get_capacity(res_id: String) -> float:
	var cap: Variant = DataDB.get_resource(res_id).get("cap", null)
	return INF if cap == null else float(cap) * mod("cap." + res_id)


## Fügt eine Menge hinzu (negativ = Verbrauch). Bestand bleibt zwischen 0 und Lagergrenze.
func add_resource(res_id: String, amount: float) -> void:
	if amount == 0.0:
		return
	var before := get_amount(res_id)
	var after := clampf(before + amount, 0.0, get_capacity(res_id))
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


func refund(cost: Dictionary, factor: float = 1.0) -> void:
	for res_id in cost:
		resources[res_id] = minf(get_amount(res_id) + float(cost[res_id]) * factor, get_capacity(res_id))
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
