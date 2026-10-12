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
## Lange Wege werden in Abschnitten dieser Länge (Kacheln) berechnet, damit
## keine einzelne Berechnung das Spiel ruckeln lässt.
const LEG_TILES := 48.0
## So nah am Abschnittsende wird schon der nächste Abschnitt angefordert
const LEG_EARLY_TILES := 6.0

var game: Node
var world: WorldData
## Alle Einheiten aller Reiche
var units: Array = []

var _path_queue: Array = []


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	game.building_system.building_placed.connect(_on_building_placed)
	game.building_system.building_removed.connect(_on_building_removed)


func spawn_unit(kingdom: Kingdom, type_id: String, pos: Vector2) -> Unit:
	var def := DataDB.get_unit_type(type_id)
	if def.is_empty():
		push_error("Unbekannter Einheitentyp: %s" % type_id)
		return null
	var u := Unit.new()
	u.setup(def, kingdom, game.next_uid())
	u.position = pos
	game.unit_layer.add_child(u)
	units.append(u)
	game.register_entity(u)
	kingdom.modifiers_changed.connect(u.refresh_stats)
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
	if u.kingdom.modifiers_changed.is_connected(u.refresh_stats):
		u.kingdom.modifiers_changed.disconnect(u.refresh_stats)
	game.unregister_entity(u)
	u.kingdom.population_changed.emit()
	unit_removed.emit(u)
	u.queue_free()


## Schickt eine Einheit zu einer Weltposition. Der Weg wird in der
## Warteschlange berechnet; bis dahin steht die Einheit – ausser mit
## keep_path: dann läuft sie auf dem alten Weg weiter, bis der neue fertig ist.
## Weite Ziele werden in Abschnitten angesteuert (siehe LEG_TILES).
func move_to(u: Unit, target: Vector2, keep_path: bool = false) -> void:
	var leg := target
	u.has_path_final = false
	if u.position.distance_to(target) > LEG_TILES * world.tile_size:
		u.has_path_final = true
		u.path_final = target
		leg = _leg_point(u.position, target)
	_request(u, leg, keep_path)


func _request(u: Unit, target: Vector2, keep_path: bool) -> void:
	if not keep_path or not u.moving:
		u.path = PackedVector2Array()
		u.path_index = 0
		u.moving = false
	u.path_target = target
	if not u.path_pending:
		u.path_pending = true
		_path_queue.append(u)


## Zwischenziel LEG_TILES Kacheln in Richtung to (nächste freie Kachel)
func _leg_point(from: Vector2, to: Vector2) -> Vector2:
	var p := from + (to - from).normalized() * LEG_TILES * world.tile_size
	return world.cell_to_world(game.nav.nearest_free(world.world_to_cell(p), 6))


## Nächster Abschnitt eines langen Weges (vom Ende des aktuellen aus)
func _request_next_leg(u: Unit) -> void:
	var from: Vector2 = u.path[u.path.size() - 1] if not u.path.is_empty() else u.position
	if from.distance_to(u.path_final) <= LEG_TILES * world.tile_size:
		u.has_path_final = false
		_request(u, u.path_final, true)
	else:
		_request(u, _leg_point(from, u.path_final), true)


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
	u.has_path_final = false
	u.path_bounds = Rect2i(world.world_to_cell(u.position), Vector2i.ZERO).expand(world.world_to_cell(target))
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
	u.has_path_final = false


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
	var leg_early := LEG_EARLY_TILES * ts
	for u in units:
		if not u.moving:
			continue
		# Langer Weg: nächsten Abschnitt rechtzeitig anfordern (ohne anzuhalten)
		if u.has_path_final and not u.path_pending \
				and u.position.distance_to(u.path[u.path.size() - 1]) < leg_early:
			_request_next_leg(u)
		# Wegbudget dieses Frames; kann über mehrere Wegpunkte reichen
		var unit_speed: float = u.speed if u.speed_cap <= 0.0 else minf(u.speed, u.speed_cap)
		var base_speed: float = unit_speed * ts
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
			if u.has_path_final or u.path_pending:
				# Abschnittsende (oder neuer Weg unterwegs): weiter, sobald er berechnet
				# ist – noch nicht als angekommen melden
				if not u.path_pending:
					_request_next_leg(u)
				continue
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
	var near := fp.grow(1)
	for u in units:
		if u.inside != null:
			continue
		if fp.has_point(world.world_to_cell(u.position)):
			u.position = b.get_approach_point(u.position)
		# Nur Wege prüfen, deren Bereich das Gebäude überhaupt berührt
		if not u.moving or not u.path_bounds.grow(1).intersects(near):
			continue
		for i in range(u.path_index, u.path.size()):
			if fp.has_point(world.world_to_cell(u.path[i])):
				move_to(u, u.path_final if u.has_path_final else u.path[u.path.size() - 1])
				break


## Ein Gebäude verschwindet: wer darin ist, kommt heraus.
func _on_building_removed(b: Building) -> void:
	for u in units:
		if u.inside == b:
			set_inside(u, null)


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
			u.has_path_final = false
			u.moving = false
			path_failed.emit(u)
			continue
		u.path = p
		u.path_index = 0
		u.moving = true
		u.path_bounds = _bounds_of(p)


func _bounds_of(p: PackedVector2Array) -> Rect2i:
	var r := Rect2i(world.world_to_cell(p[0]), Vector2i.ZERO)
	for pt in p:
		r = r.expand(world.world_to_cell(pt))
	return r
