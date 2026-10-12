## SummonSystem
##
## Beschwörung von Einheiten in Gebäuden (Burg: Späher, Kaserne: Kämpfer,
## Schützen, Elite; Krankenstation: Heiler). Jedes Gebäude hat eine
## Warteschlange; bezahlt wird beim Einreihen, Abbrechen erstattet alles.
## Neue Einheiten erscheinen am Gebäude und laufen zum Sammelpunkt.
class_name SummonSystem
extends Node

signal unit_summoned(unit: Unit, building: Building)
## Warteschlange eines Gebäudes hat sich geändert (für das Auswahlfenster)
signal queue_changed(building: Building)

var game: Node
var unit_system: UnitSystem
var _queue_limit := 5


func setup(p_game: Node) -> void:
	game = p_game
	unit_system = game.unit_system
	_queue_limit = int(DataDB.cmb("queue_limit", 5))
	GameClock.sim_tick.connect(_on_sim_tick)
	game.building_system.building_removed.connect(_on_building_removed)


## Einheitentypen (Dictionaries aus units.json), die dieses Gebäude beschwören
## kann. Einträge in "summons" sind Stufen (z. B. "fighter", dann die Einheit
## der eigenen Fraktion) oder Einheiten-IDs; dazu kommen Freischaltungen des
## Reichs (kingdom.unlocks "summon:<gebäude>:<einheit>", ab Phase 4/6).
func get_options(b: Building) -> Array:
	var list: Array = []
	var entries: Array = b.def.get("summons", []).duplicate()
	var prefix := "summon:%s:" % str(b.def.get("id", ""))
	for key in b.kingdom.unlocks:
		if str(key).begins_with(prefix):
			entries.append(str(key).substr(prefix.length()))
	for entry in entries:
		var def := DataDB.get_unit_type(str(entry))
		if def.is_empty():
			def = DataDB.get_unit_for_tier(b.kingdom.faction_id, str(entry))
		if not def.is_empty() and not list.has(def):
			list.append(def)
	return list


## "" = kann beschworen werden, sonst der Grund
func can_summon(b: Building, type_id: String) -> String:
	if not is_instance_valid(b):
		return "Gebäude fehlt"
	if not b.constructed:
		return "Das Gebäude ist noch im Bau"
	var def := DataDB.get_unit_type(type_id)
	if def.is_empty():
		return "Unbekannte Einheit"
	for req in def.get("requires", []):
		if not b.kingdom.unlocks.has(req):
			return "Benötigt: %s" % str(req)
	if b.summon_queue.size() >= _queue_limit:
		return "Warteschlange voll (%d)" % _queue_limit
	var cost: Dictionary = def.get("cost", {})
	var reason := b.kingdom.missing_text(cost)
	if not reason.is_empty() and b.kingdom.get_amount("mana") + 0.0001 < float(cost.get("mana", 0.0)):
		reason += "\nMana: Manabrunnen auf einer Manaquelle bauen und Manawirker zuweisen (J)"
	return reason


## Bezahlt und reiht die Beschwörung ein.
func summon(b: Building, type_id: String) -> bool:
	if not can_summon(b, type_id).is_empty():
		return false
	var def := DataDB.get_unit_type(type_id)
	var cost: Dictionary = def.get("cost", {})
	if not b.kingdom.spend(cost):
		return false
	b.summon_queue.append({"type_id": type_id, "progress": 0.0,
			"time": maxf(float(def.get("summon_time", 10.0)), 0.1), "cost": cost.duplicate()})
	b.queue_redraw()
	queue_changed.emit(b)
	return true


## Bricht einen Eintrag ab (volle Erstattung).
func cancel(b: Building, index: int) -> void:
	if not is_instance_valid(b) or index < 0 or index >= b.summon_queue.size():
		return
	var entry: Dictionary = b.summon_queue[index]
	b.kingdom.refund(entry.get("cost", {}))
	b.summon_queue.remove_at(index)
	b.queue_redraw()
	queue_changed.emit(b)


func set_rally(b: Building, pos: Vector2) -> void:
	b.rally_point = pos
	b.has_rally = true
	b.queue_redraw()


func clear_rally(b: Building) -> void:
	b.has_rally = false
	b.queue_redraw()


func _on_sim_tick(dt: float) -> void:
	for k in game.kingdoms:
		var factor: float = k.mod("summon")
		for b in k.buildings:
			if b.summon_queue.is_empty() or not b.constructed:
				continue
			var entry: Dictionary = b.summon_queue[0]
			entry["progress"] = float(entry["progress"]) + dt * factor
			b.queue_redraw()
			if float(entry["progress"]) >= float(entry["time"]):
				b.summon_queue.remove_at(0)
				spawn_summoned(b, str(entry["type_id"]))
				queue_changed.emit(b)


## Lässt eine beschworene Einheit am Gebäude erscheinen (auch für Zauber und
## Ereignisse nutzbar). Ohne Sammelpunkt stellt sie sich in Reihen auf.
func spawn_summoned(b: Building, type_id: String) -> Unit:
	var toward := b.rally_point if b.has_rally else b.get_center() + Vector2(0, 1000)
	var pos := b.get_approach_point(toward)
	var u := unit_system.spawn_unit(b.kingdom, type_id, pos)
	if u == null:
		return null
	b.summon_count += 1
	b.kingdom.add_stat("summoned")
	# Neue Truppen halten ihren Platz und verteidigen ihn
	u.command = "hold"
	if b.has_rally:
		u.command_pos = pos
		game.command_system.order_move([u], b.rally_point)
	else:
		# Ohne Sammelpunkt: in Reihen vor dem Gebäude aufstellen (nicht übereinander)
		var slot := _spawn_slot(b, pos, b.summon_count - 1)
		u.command_pos = slot
		unit_system.move_direct(u, slot)
	b.kingdom.notify("%s beschworen" % u.get_display_name(), "good", pos)
	unit_summoned.emit(u, b)
	return u


## Platz Nummer n (4 je Reihe, 3 Reihen, dann von vorn) vor dem Gebäude
func _spawn_slot(b: Building, base: Vector2, n: int) -> Vector2:
	var spacing: float = float(DataDB.cmb("formation.spacing", 0.9)) * game.world.tile_size
	var dir := base - b.get_center()
	dir = Vector2.DOWN if dir.length() < 1.0 else dir.normalized()
	var right := Vector2(-dir.y, dir.x)
	var k := n % 12
	var col := k % 4
	var row := k >> 2
	return base + right * (col - 1.5) * spacing + dir * (row + 0.5) * spacing


## Abriss/Zerstörung: laufende Beschwörungen werden erstattet.
func _on_building_removed(b: Building) -> void:
	for entry in b.summon_queue:
		b.kingdom.refund(entry.get("cost", {}))
	b.summon_queue.clear()
