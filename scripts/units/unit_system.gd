## UnitSystem
##
## Verwaltet alle Einheiten aller Reiche: erzeugen, entfernen, laufen lassen.
## - Bewegung läuft einmal pro Frame für alle Einheiten in einer Schleife
##   (statt _process in jeder Einheit) und nutzt die Spielzeit (GameClock):
##   steht bei Pause still, läuft bei 3x dreimal so schnell.
## - Wegberechnungen kommen in eine Warteschlange und werden mit Zeitbudget
##   abgearbeitet, damit viele gleichzeitige Aufträge nicht ruckeln.
## - remove_unit ist der einzige Weg, eine Einheit zu entfernen.
class_name UnitSystem
extends Node

signal unit_spawned(unit: Unit)
signal unit_removed(unit: Unit)
## Eine Einheit hat das Ende ihres Weges erreicht.
signal arrived(unit: Unit)
## Für eine Einheit wurde kein Weg gefunden.
signal path_failed(unit: Unit)

## Höchstens so viele Wegberechnungen bzw. so viel Zeit (µs) pro Frame
const MAX_PATHS_PER_FRAME := 8
const PATH_BUDGET_USEC := 2000

var game: Node
var world: WorldData
## Alle Einheiten aller Reiche
var units: Array = []

var _path_queue: Array = []


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	game.building_system.building_placed.connect(_on_building_placed)


func spawn_unit(kingdom: Kingdom, type_id: String, pos: Vector2) -> Unit:
	var def := DataDB.get_unit_type(type_id)
	if def.is_empty():
		push_error("Unbekannter Einheitentyp: %s" % type_id)
		return null
	var u := Unit.new()
	u.setup(def, kingdom, game.next_uid())
	u.position = pos
	game.entities.add_child(u)
	units.append(u)
	kingdom.units.append(u)
	kingdom.population_changed.emit()
	unit_spawned.emit(u)
	return u


## Der einzige Weg, eine Einheit zu entfernen (später auch Tod, Überlaufen).
func remove_unit(u: Unit) -> void:
	if not is_instance_valid(u) or not units.has(u):
		return
	units.erase(u)
	u.kingdom.units.erase(u)
	u.kingdom.population_changed.emit()
	unit_removed.emit(u)
	u.queue_free()


## Schickt eine Einheit zu einer Weltposition. Der Weg wird in der
## Warteschlange berechnet; bis dahin steht die Einheit.
func move_to(u: Unit, target: Vector2) -> void:
	u.path = PackedVector2Array()
	u.path_index = 0
	u.moving = false
	u.path_target = target
	if not u.path_pending:
		u.path_pending = true
		_path_queue.append(u)


## Kurze Strecke ohne Wegsuche: läuft geradeaus, wenn unterwegs nichts
## blockiert (spart Wegberechnungen beim Verfolgen und Umherstreifen),
## sonst normal über move_to.
func move_direct(u: Unit, target: Vector2, max_tiles: float = 4.0) -> void:
	var dist := u.position.distance_to(target)
	if dist > max_tiles * world.tile_size or not can_walk_direct(u.position, target):
		move_to(u, target)
		return
	u.path = PackedVector2Array([target])
	u.path_index = 0
	u.path_target = target
	u.path_pending = false
	u.moving = dist > 0.5


## Führt die gerade Linie von a nach b an keiner blockierten Kachel vorbei?
func can_walk_direct(a: Vector2, b: Vector2) -> bool:
	var steps := ceili(a.distance_to(b) / (world.tile_size * 0.4))
	for i in range(1, steps + 1):
		var c := world.world_to_cell(a.lerp(b, float(i) / steps))
		if not world.in_bounds(c) or game.nav.is_solid(c):
			return false
	return true


func stop(u: Unit) -> void:
	u.path = PackedVector2Array()
	u.path_index = 0
	u.moving = false
	u.path_pending = false


## Einheit eines Reichs (oder beliebigen, wenn kingdom null) nahe einer Position.
## Einheiten in Gebäuden werden nicht gefunden.
func get_unit_at(pos: Vector2, radius: float, kingdom: Kingdom = null) -> Unit:
	var best: Unit = null
	var best_d := radius * radius
	for u in units:
		if u.inside != null or (kingdom != null and u.kingdom != kingdom):
			continue
		var d: float = u.position.distance_squared_to(pos)
		if d <= best_d:
			best_d = d
			best = u
	return best


## Einheit betritt ein Gebäude (unsichtbar) oder verlässt es (b = null).
func set_inside(u: Unit, b: Building) -> void:
	if u.inside == b:
		return
	if b == null and is_instance_valid(u.inside):
		u.position = u.inside.get_approach_point(u.position)
	u.inside = b
	u.visible = b == null


func _process(_delta: float) -> void:
	if world == null:
		return
	_process_path_queue()
	var dt := GameClock.frame_delta
	if dt <= 0.0:
		return
	var ts := float(world.tile_size)
	var arrivals: Array = []
	for u in units:
		if not u.moving:
			continue
		# Wegbudget dieses Frames; kann über mehrere Wegpunkte reichen
		var base_speed: float = u.type_def.get("speed", 2.0) * ts * u.kingdom.mod("speed")
		var budget := dt
		while budget > 0.0 and u.path_index < u.path.size():
			var cost := world.get_move_cost(world.world_to_cell(u.position))
			var speed := base_speed / clampf(cost, 0.1, 50.0)
			var target: Vector2 = u.path[u.path_index]
			var dist: float = u.position.distance_to(target)
			var step := speed * budget
			if step >= dist:
				u.position = target
				budget -= dist / speed
				u.path_index += 1
			else:
				u.position += (target - u.position) / dist * step
				budget = 0.0
		if u.path_index >= u.path.size():
			u.moving = false
			arrivals.append(u)
	# Erst nach der Schleife melden: Empfänger dürfen Einheiten verändern
	for u in arrivals:
		if is_instance_valid(u):
			arrived.emit(u)


## Ein neues Gebäude blockiert Kacheln: Einheiten, deren Weg hindurchführt,
## planen neu; Einheiten, die darauf stehen, treten zur Seite.
func _on_building_placed(b: Building) -> void:
	if not b.blocks_movement():
		return
	var fp := b.get_footprint()
	for u in units:
		if u.inside != null:
			continue
		if fp.has_point(world.world_to_cell(u.position)):
			u.position = b.get_approach_point(u.position)
		if not u.moving:
			continue
		for i in range(u.path_index, u.path.size()):
			if fp.has_point(world.world_to_cell(u.path[i])):
				move_to(u, u.path[u.path.size() - 1])
				break


func _process_path_queue() -> void:
	var start := Time.get_ticks_usec()
	var done := 0
	while not _path_queue.is_empty() and done < MAX_PATHS_PER_FRAME:
		if Time.get_ticks_usec() - start > PATH_BUDGET_USEC:
			break
		var u = _path_queue.pop_front()  # untypisiert: kann bereits gelöscht sein
		if not is_instance_valid(u) or not u.path_pending:
			continue
		u.path_pending = false
		done += 1
		var p: PackedVector2Array = game.nav.find_path(world, u.position, u.path_target)
		if p.is_empty():
			path_failed.emit(u)
			continue
		u.path = p
		u.path_index = 0
		u.moving = true
