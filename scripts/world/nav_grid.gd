## NavGrid
##
## Wegfindung (A*) über die ganze Karte auf dem Kachelraster.
## - Gewicht jeder Kachel = Bewegungskosten (Gelände, Strassen), so skaliert,
##   dass der billigste mögliche Schritt 1.0 kostet. Nur so bleibt die
##   A*-Schätzung gültig und Wege führen wirklich über Strassen.
## - Gebäude blockieren (solid). Startet eine Einheit auf einer blockierten
##   Kachel (z. B. neben einer frischen Baustelle), läuft sie erst zur nächsten
##   freien Kachel.
## - Aufgebaut wird einmal beim Laden (im Hintergrund-Thread), danach werden
##   nur einzelne Kacheln angepasst.
## Spiellogik ruft find_path nie direkt auf, sondern UnitSystem.move_to().
class_name NavGrid
extends RefCounted

## Grösste "Tasche" (von Gebäuden eingeschlossene freie Fläche), die vor einer
## Wegsuche erkannt wird. Grössere Flächen gelten als offen.
const POCKET_LIMIT := 300

var astar := AStarGrid2D.new()
var region := Rect2i()
## Zählt jede Änderung an blockierten Kacheln (für "unerreichbar"-Merker)
var solid_version := 0
## Wird beim Verlassen während des Ladens gesetzt: Aufbau abbrechen
var cancelled := false
## Gewichtsfaktor: 1 / billigste Schrittkosten
var _scale := 1.0
## Zwischenspeicher der Taschen-Prüfung (gilt für eine solid_version)
var _pocket_cache: Dictionary = {}
var _pocket_cache_version := -1


## Baut das Raster für die ganze Karte (darf im Hintergrund-Thread laufen).
func build(world: WorldData) -> void:
	region = Rect2i(0, 0, world.width, world.height)
	astar.region = region
	astar.cell_size = Vector2(world.tile_size, world.tile_size)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

	# Gewicht pro Biom vorberechnen (schneller als get_move_cost pro Kachel)
	var road_mult := maxf(float(DataDB.eco("road.speed_mult", 1.6)), 0.01)
	var min_cost := INF
	var weights := PackedFloat32Array()
	weights.resize(DataDB.biomes.size())
	for b in DataDB.biomes:
		min_cost = minf(min_cost, float(b["movement_cost"]))
	_scale = 1.0 / maxf(min_cost / road_mult, 0.001)
	for b in DataDB.biomes:
		weights[b["index"]] = float(b["movement_cost"]) * _scale
	# Häufigstes Biom auf einen Schlag füllen, dann nur die Abweichungen setzen
	var most := 0
	for i in world.biome_counts.size():
		if world.biome_counts[i] > world.biome_counts[most]:
			most = i
	var fill := weights[most] if weights.size() > 0 else 1.0
	astar.fill_weight_scale_region(region, fill)
	var bio := world.biomes
	for y in world.height:
		if cancelled:
			return
		var row := y * world.width
		for x in world.width:
			var w := weights[bio[row + x]]
			if w != fill:
				astar.set_point_weight_scale(Vector2i(x, y), w)
	for cell in world.roads:
		update_cell(world, cell)


func contains(cell: Vector2i) -> bool:
	return region.has_point(cell)


## Nach Änderung einer Kachel (Strasse, Rodung) Gewicht anpassen.
func update_cell(world: WorldData, cell: Vector2i) -> void:
	if astar.is_dirty() or not astar.is_in_boundsv(cell):
		return
	astar.set_point_weight_scale(cell, world.get_move_cost(cell) * _scale)


## Kachel blockieren oder freigeben (Gebäude)
func set_solid(cell: Vector2i, solid: bool) -> void:
	if astar.is_dirty() or not astar.is_in_boundsv(cell):
		return
	astar.set_point_solid(cell, solid)
	solid_version += 1


func is_solid(cell: Vector2i) -> bool:
	return astar.is_in_boundsv(cell) and astar.is_point_solid(cell)


## Nächste freie Kachel um cell (cell selbst, wenn frei). (-1,-1) wenn keine
## im Umkreis max_ring.
func nearest_free(cell: Vector2i, max_ring: int = 3) -> Vector2i:
	if contains(cell) and not astar.is_point_solid(cell):
		return cell
	for r in range(1, max_ring + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := cell + Vector2i(dx, dy)
				if contains(c) and not astar.is_point_solid(c):
					return c
	return Vector2i(-1, -1)


## Weg von from_pos nach to_pos als Weltpositionen (Kachelmitten; der letzte
## Punkt ist genau to_pos). Liegt das Ziel auf einer blockierten Kachel, wird
## die nächste freie Kachel angesteuert. Leeres Ergebnis = kein Weg.
## Wichtig: Nie zu einer blockierten Kachel suchen – A* würde sonst die ganze
## Karte absuchen (Ruckler von fast einer Sekunde).
func find_path(world: WorldData, from_pos: Vector2, to_pos: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	var from_cell := world.world_to_cell(from_pos)
	var to_cell := world.world_to_cell(to_pos)
	if astar.is_dirty() or not contains(to_cell):
		return result
	var goal := nearest_free(to_cell)
	if goal.x < 0:
		return result
	var goal_pos := to_pos if goal == to_cell else world.cell_to_world(goal)
	if from_cell == goal:
		result.append(goal_pos)
		return result
	var start := nearest_free(from_cell)
	if start.x < 0:
		return result
	# Eingeschlossene Ziele (oder Starts) vorab erkennen: A* würde sonst die
	# ganze Karte absuchen, bevor es aufgibt.
	var goal_pocket := _pocket(goal)
	if not goal_pocket.is_empty() and not goal_pocket.has(start):
		return result
	var start_pocket := _pocket(start)
	if not start_pocket.is_empty() and not start_pocket.has(goal):
		return result
	if start != from_cell:
		result.append(world.cell_to_world(start))
		if start == goal:
			result.append(goal_pos)
			return result
	var ids := astar.get_id_path(start, goal)
	if ids.is_empty():
		return PackedVector2Array()
	for i in range(1, ids.size() - 1):
		result.append(world.cell_to_world(ids[i]))
	result.append(goal_pos)
	return result


## Liegt cell in einer kleinen, von Gebäuden eingeschlossenen Fläche? Gibt die
## Kacheln dieser Fläche zurück (leer = offene Fläche). Begrenzte Breitensuche;
## nur nötig, wenn überhaupt ein Gebäude in der Nähe ist.
func _pocket(cell: Vector2i) -> Dictionary:
	if _pocket_cache_version != solid_version:
		_pocket_cache.clear()
		_pocket_cache_version = solid_version
	if _pocket_cache.has(cell):
		return _pocket_cache[cell]
	var result := _find_pocket(cell)
	_pocket_cache[cell] = result
	return result


func _find_pocket(cell: Vector2i) -> Dictionary:
	if not _solid_near(cell, 3):
		return {}
	var seen := {cell: true}
	var queue: Array[Vector2i] = [cell]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for n in [Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)]:
			if seen.has(n) or not region.has_point(n) or astar.is_point_solid(n):
				continue
			seen[n] = true
			queue.append(n)
			if queue.size() > POCKET_LIMIT:
				return {}
	return seen


func _solid_near(cell: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := cell + Vector2i(dx, dy)
			if region.has_point(c) and astar.is_point_solid(c):
				return true
	return false
