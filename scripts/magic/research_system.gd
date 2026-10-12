## ResearchSystem
##
## Forschung je Reich: eine Warteschlange (die erste Forschung läuft), bezahlt
## wird beim Einreihen, Abbrechen erstattet alles. Geforscht wird nur, wenn
## das Reich mindestens eine fertige Forschungsstätte hat (Bibliothek bzw.
## Dunkles Archiv); jede weitere beschleunigt.
## Wirkungen (research.json → effects) gehen über das Reich, jeweils mit der
## Quelle "research:<id>": Freischaltungen (Kingdom.grant_unlock), Modifikatoren
## (Kingdom.set_modifiers) und Zuschläge (Kingdom.set_bonus, z. B. spell_range).
## Ausserdem: Mana-Verbesserungen gegen Kampfpunkte (spells.json → upgrades,
## Quelle "upgrade:<id>").
## Gleiche Schnittstelle für Spieler und (ab Phase 7) KI-Reiche.
class_name ResearchSystem
extends Node

signal research_started(kingdom: Kingdom, research_id: String)
signal research_completed(kingdom: Kingdom, research_id: String)
## Warteschlange eines Reichs geändert (Start, Abbruch, Abschluss)
signal queue_changed(kingdom: Kingdom)
signal upgrade_bought(kingdom: Kingdom, upgrade_id: String, level: int)

## Höchstens so viele Forschungen in der Warteschlange (inklusive der laufenden)
const QUEUE_LIMIT := 3
## Jede weitere Forschungsstätte forscht so viel schneller (+25 %)
const EXTRA_BUILDING_SPEED := 0.25
## Schlüssel in spells.json → upgrades.per_level -> Zuschlag-Schlüssel des Reichs
const UPGRADE_KEYS := {"mana_cap": "cap.mana", "mana_regen": "mana_regen"}

var game: Node


func setup(p_game: Node) -> void:
	game = p_game
	GameClock.sim_tick.connect(_on_sim_tick)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Alle Forschungen, die dieses Reich erforschen kann (eigene Fraktion)
func get_tree_for(k: Kingdom) -> Array:
	return DataDB.get_research_for_faction(k.faction_id)


## "done", "active", "queued", "available" oder "locked"
func get_state(k: Kingdom, id: String) -> String:
	if k.researched.has(id):
		return "done"
	var i := k.research_queue.find(id)
	if i == 0:
		return "active"
	if i > 0:
		return "queued"
	return "available" if _missing_requirements(k, DataDB.get_research(id)).is_empty() else "locked"


## "" = kann gestartet/eingereiht werden, sonst der Grund (deutsch)
func can_start(k: Kingdom, id: String) -> String:
	var def := DataDB.get_research(id)
	if def.is_empty():
		return "Unbekannte Forschung"
	if def["faction"] != "any" and def["faction"] != k.faction_id:
		return "Nicht für dein Reich"
	if k.researched.has(id):
		return "Bereits erforscht"
	if k.research_queue.has(id):
		return "Bereits in der Warteschlange"
	var missing := _missing_requirements(k, def)
	if not missing.is_empty():
		return "Benötigt zuerst: " + ", ".join(missing)
	if k.research_queue.size() >= QUEUE_LIMIT:
		return "Warteschlange voll (%d)" % QUEUE_LIMIT
	if count_research_buildings(k) == 0:
		return "Baue zuerst eine Forschungsstätte (%s)" % get_research_building_name(k)
	return k.missing_text(def.get("cost", {}))


## Anzahl fertiger Forschungsstätten
func count_research_buildings(k: Kingdom) -> int:
	var n := 0
	for b in k.buildings:
		if b.constructed and bool(b.def.get("research", false)):
			n += 1
	return n


## Name der Forschungsstätte für die Fraktion des Reichs
func get_research_building_name(k: Kingdom) -> String:
	for def in DataDB.buildings:
		if bool(def.get("research", false)):
			return DataDB.get_building_name(def, k.faction_id)
	return "Forschungsstätte"


func get_active(k: Kingdom) -> String:
	return str(k.research_queue[0]) if not k.research_queue.is_empty() else ""


## Fortschritt der laufenden Forschung (0..1)
func get_progress_ratio(k: Kingdom) -> float:
	var def := DataDB.get_research(get_active(k))
	if def.is_empty():
		return 0.0
	return clampf(k.research_progress / float(def["time"]), 0.0, 1.0)


## Restzeit der laufenden Forschung in Spielsekunden (INF ohne Forschungsstätte)
func get_remaining_seconds(k: Kingdom) -> float:
	var def := DataDB.get_research(get_active(k))
	if def.is_empty():
		return 0.0
	var speed := get_speed(k)
	if speed <= 0.0:
		return INF
	return maxf(float(def["time"]) - k.research_progress, 0.0) / speed


## Forschungstempo: 0 ohne Forschungsstätte, jede weitere +25 %
func get_speed(k: Kingdom) -> float:
	var n := count_research_buildings(k)
	if n == 0:
		return 0.0
	return (1.0 + EXTRA_BUILDING_SPEED * (n - 1)) * k.mod("research")


## Kurzbeschreibung der Wirkungen ("Schaltet frei: Ritter", "+10 % Angriff (Kämpfer)" …)
func describe_effects(k: Kingdom, id: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	for e in DataDB.get_research(id).get("effects", []):
		match str(e.get("type", "")):
			"unlock":
				lines.append("Schaltet frei: " + DataDB.describe_unlock(str(e.get("id", "")), k.faction_id))
			"modifier":
				lines.append(DataDB.describe_modifier(str(e.get("key", "")), float(e.get("factor", 1.0))))
			"bonus":
				lines.append(DataDB.describe_bonus(str(e.get("key", "")), float(e.get("add", 0.0))))
			"mana_cap":
				lines.append(DataDB.describe_bonus("cap.mana", float(e.get("add", 0.0))))
			"mana_regen":
				lines.append(DataDB.describe_bonus("mana_regen", float(e.get("add", 0.0))))
	return lines


# ---------------------------------------------------------------------------
# Aktionen
# ---------------------------------------------------------------------------

## Bezahlt und reiht die Forschung ein.
func start(k: Kingdom, id: String) -> bool:
	if not can_start(k, id).is_empty():
		return false
	var def := DataDB.get_research(id)
	if not k.spend(def.get("cost", {})):
		return false
	k.research_queue.append(id)
	if k.research_queue.size() == 1:
		k.research_progress = 0.0
		research_started.emit(k, id)
	queue_changed.emit(k)
	return true


## Bricht eine eingereihte oder laufende Forschung ab (volle Erstattung).
## Forschungen in der Warteschlange, die darauf aufbauen, werden mit abgebrochen.
func cancel(k: Kingdom, id: String) -> void:
	var i := k.research_queue.find(id)
	if i < 0:
		return
	var to_cancel: Array = [id]
	# Abhängige (später eingereihte) mitnehmen
	var changed := true
	while changed:
		changed = false
		for qid in k.research_queue:
			if to_cancel.has(qid):
				continue
			for req in DataDB.get_research(str(qid)).get("requires", []):
				if to_cancel.has(req):
					to_cancel.append(qid)
					changed = true
					break
	var was_active := i == 0
	for cid in to_cancel:
		k.refund(DataDB.get_research(str(cid)).get("cost", {}))
		k.research_queue.erase(cid)
	if was_active:
		k.research_progress = 0.0
		if not k.research_queue.is_empty():
			research_started.emit(k, str(k.research_queue[0]))
	queue_changed.emit(k)


## Wendet die Wirkungen einer Forschung an. Mehrfach aufrufbar (z. B. beim Laden):
## alles läuft über die Quelle "research:<id>" und ersetzt deren alten Stand.
func apply_effects(k: Kingdom, id: String) -> void:
	var source := "research:" + id
	# Die Forschung selbst gilt auch als Freischaltung (für requires anderer Dinge)
	k.grant_unlock(source, source)
	var factors := {}
	for e in DataDB.get_research(id).get("effects", []):
		match str(e.get("type", "")):
			"unlock":
				k.grant_unlock(source, str(e.get("id", "")))
			"modifier":
				factors[str(e.get("key", ""))] = float(e.get("factor", 1.0))
			"bonus":
				k.set_bonus(source, str(e.get("key", "")), float(e.get("add", 0.0)))
			"mana_cap":
				k.set_bonus(source, "cap.mana", float(e.get("add", 0.0)))
			"mana_regen":
				k.set_bonus(source, "mana_regen", float(e.get("add", 0.0)))
	# Alle Faktoren auf einmal: die Einheiten rechnen nur einmal neu
	if not factors.is_empty():
		k.set_modifiers(source, factors)


## Nach dem Laden (Phase 10): alle Wirkungen aus researched und mana_upgrades
## neu aufbauen (Modifikatoren, Freischaltungen und Zuschläge sind abgeleitet).
func restore(k: Kingdom) -> void:
	for rid in k.researched:
		apply_effects(k, str(rid))
	recompute_mana(k)


## Zuschläge der Kampfpunkt-Verbesserungen neu setzen (Quelle "upgrade:<id>").
## per_level: "mana_cap" -> Mana-Maximum, "mana_regen" -> Mana/s an der Burg.
func recompute_mana(k: Kingdom) -> void:
	for up in DataDB.mag("upgrades", []):
		var up_id := str(up.get("id", ""))
		var level := int(k.mana_upgrades.get(up_id, 0))
		var per: Dictionary = up.get("per_level", {})
		for key in per:
			k.set_bonus("upgrade:" + up_id, str(UPGRADE_KEYS.get(key, key)), float(per[key]) * level)


# ---------------------------------------------------------------------------
# Mana-Verbesserungen gegen Kampfpunkte
# ---------------------------------------------------------------------------

func get_upgrades() -> Array:
	return DataDB.mag("upgrades", [])


func get_upgrade_level(k: Kingdom, upgrade_id: String) -> int:
	return int(k.mana_upgrades.get(upgrade_id, 0))


## Kosten der nächsten Stufe in Kampfpunkten (-1 = höchste Stufe erreicht)
func get_upgrade_cost(k: Kingdom, upgrade_id: String) -> int:
	for up in get_upgrades():
		if str(up.get("id", "")) == upgrade_id:
			var costs: Array = up.get("cost_kill_points", [])
			var level := get_upgrade_level(k, upgrade_id)
			return int(costs[level]) if level < costs.size() else -1
	return -1


## "" = kann gekauft werden, sonst der Grund
func can_buy_upgrade(k: Kingdom, upgrade_id: String) -> String:
	var cost := get_upgrade_cost(k, upgrade_id)
	if cost < 0:
		return "Höchste Stufe erreicht"
	if k.kill_points < cost:
		return "Zu wenig Kampfpunkte (%d von %d) – besiege Monster und Feinde" % [k.kill_points, cost]
	return ""


func buy_upgrade(k: Kingdom, upgrade_id: String) -> bool:
	if not can_buy_upgrade(k, upgrade_id).is_empty():
		return false
	k.kill_points -= get_upgrade_cost(k, upgrade_id)
	var level := get_upgrade_level(k, upgrade_id) + 1
	k.mana_upgrades[upgrade_id] = level
	recompute_mana(k)
	upgrade_bought.emit(k, upgrade_id, level)
	return true


# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	for k in game.kingdoms:
		if k.research_queue.is_empty():
			continue
		var speed := get_speed(k)
		if speed <= 0.0:
			continue
		k.research_progress += dt * speed
		var id := str(k.research_queue[0])
		var def := DataDB.get_research(id)
		if def.is_empty():
			k.research_queue.remove_at(0)
			continue
		if k.research_progress >= float(def["time"]):
			_complete(k, id)


func _complete(k: Kingdom, id: String) -> void:
	k.research_queue.erase(id)
	k.research_progress = 0.0
	k.researched[id] = true
	apply_effects(k, id)
	var def := DataDB.get_research(id)
	var text := "Forschung abgeschlossen: %s" % def.get("name", id)
	var effects := describe_effects(k, id)
	if not effects.is_empty():
		text += " – " + ", ".join(effects)
	k.notify(text, "good", k.castle.get_center() if is_instance_valid(k.castle) else null)
	research_completed.emit(k, id)
	if not k.research_queue.is_empty():
		research_started.emit(k, str(k.research_queue[0]))
	queue_changed.emit(k)


## Fehlende Voraussetzungen (Namen), die weder fertig noch vorher eingereiht sind
func _missing_requirements(k: Kingdom, def: Dictionary) -> PackedStringArray:
	var missing: PackedStringArray = []
	for req in def.get("requires", []):
		if not k.researched.has(req) and not k.research_queue.has(req):
			missing.append(str(DataDB.get_research(str(req)).get("name", req)))
	return missing
