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
## - Phase 9: Tore je Reich, Mauerringe, Grund des Scheiterns. Tore sind im
##   Grundzustand blockiert; find_path öffnet für die Dauer einer Suche nur die
##   Tore, die das suchende Reich passieren darf (gate_rule). Von Mauern
##   eingeschlossene Flächen ("Ringe") bekommen Labels (lokale Flutfüllung nach
##   jeder Änderung); vor A* wird in O(1) über Labels und einen kleinen Torgraphen
##   geprüft, ob Start und Ziel überhaupt verbunden sind – ein eingemauertes Ziel
##   lässt A* so nie die ganze Karte absuchen. last_fail nennt den Grund.
## Spiellogik ruft find_path nie direkt auf, sondern UnitSystem.move_to().
class_name NavGrid
extends RefCounted

## Grösste "Tasche" (von Gebäuden eingeschlossene freie Fläche), die vor einer
## Wegsuche erkannt wird. Grössere Flächen gelten als offen.
const POCKET_LIMIT := 300
## Suchradius für "Gebäude in der Nähe?": Eine Tasche bis POCKET_LIMIT Kacheln
## passt immer in ein Quadrat mit diesem Radius ((2r+1)² > POCKET_LIMIT).
const POCKET_RADIUS := 9
## Fluchtrahmen der Flutfüllung: Mauerrahmen in diesem Abstand zu den Änderungen zählen mit
const DIRTY_REACH := 96

var astar := AStarGrid2D.new()
var region := Rect2i()
## Zählt jede Änderung an blockierten Kacheln (für "unerreichbar"-Merker)
var solid_version := 0
## Wird beim Verlassen während des Ladens gesetzt: Aufbau abbrechen
var cancelled := false
## Gewichtsfaktor: 1 / billigste Schrittkosten
var _scale := 1.0
## Zwischenspeicher der Taschen-Prüfung (gilt für eine solid_version + gate_version)
var _pocket_cache: Dictionary = {}
var _pocket_cache_version := -1
var _pocket_cache_gates := -1

# --- Phase 9: Tore, Mauerringe ---
## Spiegel der blockierten Kacheln (1 = blockiert), schneller als astar.is_point_solid in Schleifen
var _solid_mask := PackedByteArray()
## Tor-Kachel -> Besitzer (Kingdom.id). Tore sind im Grundzustand blockiert.
var gates: Dictionary = {}
## Tor-Kachel -> true: vom Besitzer verriegelt
var locked_gates: Dictionary = {}
## Zählt Änderungen an Toren und Beziehungen (leert die Durchlass-Zwischenspeicher)
var gate_version := 0
## Regel (vom SiegeSystem gesetzt): func(owner_id: int, kingdom_id: int, locked: bool) -> bool
var gate_rule: Callable
## Mauern/Tore/Türme: Kachel -> Besitzer (nur für Ringe und Bresche)
var barriers: Dictionary = {}
## Label eingeschlossener Flächen je Kachel (0 = offen); leer, solange es keine Mauern gibt
var region_label := PackedInt32Array()
## Label -> {"cells": PackedInt32Array, "boundary": PackedInt32Array (blockierte Nachbarkacheln), "rect": Rect2i}
var regions: Dictionary = {}
## Tor-Kachel -> Array der angrenzenden Labels (0 = offen)
var gate_links: Dictionary = {}
## Grund des letzten Scheiterns von find_path: "" | "blocked" (Ring) | "pocket" | "nopath"
var last_fail := ""
var last_fail_region := 0
var last_fail_cell := Vector2i(-1, -1)
## Messwerte (Rauchtest, Debug)
var stats := {"relabels": 0, "relabel_usec_max": 0, "relabel_usec_last": 0, "blocked": 0, "regions": 0, "open_large": 0}
## Neu entstandene Labels (sammeln sich, bis das SiegeSystem sie abholt: "Ring ohne Tor")
var new_labels: Array = []
## Besitzer -> Rect2i aller seiner Mauerkacheln (Fluchtrahmen der Flutfüllung)
var _barrier_bbox: Dictionary = {}
var _dirty_cells: Array[Vector2i] = []
var _next_label := 1
var _visit := PackedInt32Array()
var _visit_stamp := 0
## kingdom_id -> Array[Vector2i] durchlässige Tore (gilt für eine gate_version)
var _pass_cache: Dictionary = {}
var _pass_cache_version := -1
var _enclosure_max := 90000
var _enclosure_margin := 2
var _width := 0


## Baut das Raster für die ganze Karte (darf im Hintergrund-Thread laufen).
func build(world: WorldData) -> void:
	region = Rect2i(0, 0, world.width, world.height)
	_width = world.width
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
	_solid_mask.resize(world.width * world.height)
	_enclosure_max = int(DataDB.siege("nav.enclosure_max_cells", 90000))
	_enclosure_margin = int(DataDB.siege("nav.enclosure_margin", 2))


func contains(cell: Vector2i) -> bool:
	return region.has_point(cell)


## Nach Änderung einer Kachel (Strasse, Rodung) Gewicht anpassen.
func update_cell(world: WorldData, cell: Vector2i) -> void:
	if astar.is_dirty() or not astar.is_in_boundsv(cell):
		return
	astar.set_point_weight_scale(cell, world.get_move_cost(cell) * _scale)


## Kachel blockieren oder freigeben (Gebäude). Ab Phase 9 auch: Spiegel pflegen; Änderungen
## nahe Mauern lassen die Ringe neu bestimmen (z. B. ein Haus schliesst eine Lücke).
func set_solid(cell: Vector2i, solid: bool) -> void:
	if astar.is_dirty() or not astar.is_in_boundsv(cell):
		return
	astar.set_point_solid(cell, solid)
	solid_version += 1
	var i := cell.y * _width + cell.x
	if i >= 0 and i < _solid_mask.size():
		_solid_mask[i] = 1 if solid else 0
	if not _barrier_bbox.is_empty() and _near_barriers(cell, 2):
		_dirty_cells.append(cell)


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
## die nächste freie Kachel angesteuert. Leeres Ergebnis = kein Weg (Grund in last_fail).
## kingdom_id: Tore, die dieses Reich passieren darf, sind für diese Suche offen
## (0 = keine Tore).
## Wichtig: Nie zu einer blockierten Kachel suchen – A* würde sonst die ganze
## Karte absuchen (Ruckler von fast einer Sekunde).
func find_path(world: WorldData, from_pos: Vector2, to_pos: Vector2, kingdom_id: int = 0) -> PackedVector2Array:
	last_fail = ""
	last_fail_region = 0
	last_fail_cell = Vector2i(-1, -1)
	if not _dirty_cells.is_empty():
		process_dirty()
	var opened := _open_gates_for(kingdom_id)
	var result := _find_path_inner(world, from_pos, to_pos, kingdom_id, opened.size())
	for c in opened:
		astar.set_point_solid(c, true)
	return result


func _find_path_inner(world: WorldData, from_pos: Vector2, to_pos: Vector2, kingdom_id: int, opened: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	var from_cell := world.world_to_cell(from_pos)
	var to_cell := world.world_to_cell(to_pos)
	if astar.is_dirty() or not contains(to_cell):
		last_fail = "nopath"
		return result
	var goal := nearest_free(to_cell)
	if goal.x < 0:
		last_fail = "nopath"
		return result
	var goal_pos := to_pos if goal == to_cell else world.cell_to_world(goal)
	if from_cell == goal:
		result.append(goal_pos)
		return result
	var start := nearest_free(from_cell)
	if start.x < 0:
		last_fail = "nopath"
		return result
	# Mauerringe (zuerst, O(1)): verbunden über Tore, die dieses Reich passieren darf?
	if has_regions():
		var ls := labels_at(start)
		var lg := labels_at(goal)
		if not labels_connected(ls, lg, kingdom_id):
			last_fail = "blocked"
			last_fail_region = int(lg[0]) if int(lg[0]) != 0 else int(ls[0])
			last_fail_cell = goal if int(lg[0]) != 0 else start
			stats["blocked"] = int(stats["blocked"]) + 1
			return result
	# Eingeschlossene Ziele (oder Starts) vorab erkennen: A* würde sonst die
	# ganze Karte absuchen, bevor es aufgibt.
	var sig := kingdom_id if opened > 0 else 0
	var goal_pocket := _pocket(goal, sig)
	if not goal_pocket.is_empty() and not goal_pocket.has(start):
		last_fail = "pocket"
		last_fail_cell = goal
		return result
	var start_pocket := _pocket(start, sig)
	if not start_pocket.is_empty() and not start_pocket.has(goal):
		last_fail = "pocket"
		last_fail_cell = start
		return result
	if start != from_cell:
		result.append(world.cell_to_world(start))
		if start == goal:
			result.append(goal_pos)
			return result
	var ids := astar.get_id_path(start, goal)
	if ids.is_empty():
		last_fail = "nopath"
		return PackedVector2Array()
	for i in range(1, ids.size() - 1):
		result.append(world.cell_to_world(ids[i]))
	result.append(goal_pos)
	return result


## Sind beide Kacheln begehbar und (soweit erkennbar) gegenseitig erreichbar?
## Erkennt kleine eingeschlossene Flächen und Mauerringe (z. B. für Sprünge von Helden).
func same_area(a: Vector2i, b: Vector2i, kingdom_id: int = 0) -> bool:
	if not region.has_point(a) or not region.has_point(b) or astar.is_point_solid(a) or astar.is_point_solid(b):
		return false
	var pa := _pocket(a, 0)
	if not pa.is_empty() and not pa.has(b):
		return false
	var pb := _pocket(b, 0)
	if not pb.is_empty() and not pb.has(a):
		return false
	if has_regions():
		if not _dirty_cells.is_empty():
			process_dirty()
		return labels_connected(labels_at(a), labels_at(b), kingdom_id)
	return true


# ---------------------------------------------------------------------------
# Tore
# ---------------------------------------------------------------------------

## Mauer/Tor/Turm-Kachel an- oder abmelden (SiegeSystem); die Ringe werden beim nächsten Bedarf neu bestimmt
func mark_barrier(cell: Vector2i, owner_id: int, present: bool) -> void:
	if not contains(cell):
		return
	if region_label.is_empty():
		region_label.resize(region.size.x * region.size.y)
		_visit.resize(region.size.x * region.size.y)
	if present:
		barriers[cell] = owner_id
		var r: Rect2i = _barrier_bbox.get(owner_id, Rect2i(cell, Vector2i.ONE))
		_barrier_bbox[owner_id] = r.merge(Rect2i(cell, Vector2i.ONE))
	else:
		var old := int(barriers.get(cell, -1))
		barriers.erase(cell)
		if old >= 0:
			_recompute_bbox(old)
	_dirty_cells.append(cell)


func _recompute_bbox(owner_id: int) -> void:
	var first := true
	var r := Rect2i()
	for c in barriers:
		if int(barriers[c]) != owner_id:
			continue
		var one := Rect2i(c, Vector2i.ONE)
		r = one if first else r.merge(one)
		first = false
	if first:
		_barrier_bbox.erase(owner_id)
	else:
		_barrier_bbox[owner_id] = r


func add_gate(cell: Vector2i, owner_id: int) -> void:
	gates[cell] = owner_id
	gate_version += 1
	_dirty_cells.append(cell)


func remove_gate(cell: Vector2i) -> void:
	if gates.erase(cell):
		gate_version += 1
	locked_gates.erase(cell)
	gate_links.erase(cell)
	_dirty_cells.append(cell)


func set_gate_locked(cell: Vector2i, locked: bool) -> void:
	if locked:
		locked_gates[cell] = true
	else:
		locked_gates.erase(cell)
	gate_version += 1


## Beziehungen geändert: Durchlässigkeit der Tore neu bestimmen
func bump_gates() -> void:
	gate_version += 1


func is_gate(cell: Vector2i) -> bool:
	return gates.has(cell)


## Darf das Reich durch das Tor? Besitzer immer; kingdom_id 0 nie; sonst gate_rule
func gate_passable(cell: Vector2i, kingdom_id: int) -> bool:
	if not gates.has(cell):
		return true
	var owner_id := int(gates[cell])
	if owner_id == kingdom_id:
		return true
	if kingdom_id == 0 or not gate_rule.is_valid():
		return false
	return bool(gate_rule.call(owner_id, kingdom_id, locked_gates.has(cell)))


## Tore, die das Reich passieren darf (zwischengespeichert je gate_version)
func _pass_list(kingdom_id: int) -> Array:
	if kingdom_id == 0 or gates.is_empty():
		return []
	if _pass_cache_version != gate_version:
		_pass_cache.clear()
		_pass_cache_version = gate_version
	if _pass_cache.has(kingdom_id):
		return _pass_cache[kingdom_id]
	var list: Array = []
	for c in gates:
		if gate_passable(c, kingdom_id):
			list.append(c)
	_pass_cache[kingdom_id] = list
	return list


## Öffnet die durchlässigen Tore für eine Suche (find_path schliesst sie danach wieder)
func _open_gates_for(kingdom_id: int) -> Array:
	var list := _pass_list(kingdom_id)
	var opened: Array = []
	for c in list:
		if astar.is_in_boundsv(c) and astar.is_point_solid(c):
			astar.set_point_solid(c, false)
			opened.append(c)
	return opened


# ---------------------------------------------------------------------------
# Ringe (eingeschlossene Flächen)
# ---------------------------------------------------------------------------

func has_regions() -> bool:
	return not regions.is_empty()


## Label der Kachel (0 = offen oder keine Ringe)
func get_label(cell: Vector2i) -> int:
	if region_label.is_empty() or not contains(cell):
		return 0
	return region_label[cell.y * _width + cell.x]


## Labels einer Kachel: Tor = alle angrenzenden Flächen, sonst [Label]
func labels_at(cell: Vector2i) -> Array:
	if gates.has(cell):
		var links: Array = gate_links.get(cell, [])
		return links if not links.is_empty() else [0]
	return [get_label(cell)]


## Sind die Flächen verbunden – über Tore, die kingdom_id passieren darf?
func labels_connected(a: Array, b: Array, kingdom_id: int) -> bool:
	for x in a:
		if b.has(x):
			return true
	var passable := _pass_list(kingdom_id)
	if passable.is_empty():
		return false
	var reached := {}
	for x in a:
		reached[int(x)] = true
	var changed := true
	while changed:
		changed = false
		for c in passable:
			var links: Array = gate_links.get(c, [])
			var touches := false
			for l in links:
				if reached.has(int(l)):
					touches = true
					break
			if not touches:
				continue
			for l in links:
				if not reached.has(int(l)):
					reached[int(l)] = true
					changed = true
					if b.has(l):
						return true
	return false


## Prüft für die Abschnittsplanung, ob cell mit a oder b verbunden ist (für kingdom_id)
func leg_ok(cell: Vector2i, a: Vector2i, b: Vector2i, kingdom_id: int) -> bool:
	if not has_regions():
		return true
	var lc := labels_at(cell)
	return labels_connected(lc, labels_at(a), kingdom_id) or labels_connected(lc, labels_at(b), kingdom_id)


func get_region(label: int) -> Dictionary:
	return regions.get(label, {})


## Blockierte Nachbarkacheln einer kleinen Tasche um cell (für die Bresche bei "pocket")
func pocket_boundary(cell: Vector2i) -> PackedInt32Array:
	var result := PackedInt32Array()
	var pocket := _find_pocket(cell)
	if pocket.is_empty():
		return result
	var seen := {}
	for c in pocket:
		var p: Vector2i = c
		for n in [Vector2i(p.x + 1, p.y), Vector2i(p.x - 1, p.y), Vector2i(p.x, p.y + 1), Vector2i(p.x, p.y - 1)]:
			if region.has_point(n) and astar.is_point_solid(n) and not seen.has(n):
				seen[n] = true
				result.append(n.y * _width + n.x)
	return result


## Kachel zu einem Index (Ringe, Ränder)
func index_to_cell(i: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(i % _width, i / _width)


## Ringe für die gesammelten Änderungen neu bestimmen (läuft auch zu Beginn von find_path)
func process_dirty() -> void:
	if _dirty_cells.is_empty() or region_label.is_empty():
		_dirty_cells.clear()
		return
	var t0 := Time.get_ticks_usec()
	# 1. Samen: jede schmutzige Kachel und ihre 8 Nachbarn; betroffene Ringe löschen
	var seeds: Array[int] = []
	var area := Rect2i(_dirty_cells[0], Vector2i.ONE)
	for c in _dirty_cells:
		area = area.merge(Rect2i(c, Vector2i.ONE))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := c + Vector2i(dx, dy)
				if not region.has_point(n):
					continue
				var i := n.y * _width + n.x
				var l := region_label[i]
				if l != 0:
					seeds.append(_clear_region(l))
				seeds.append(i)
	_dirty_cells.clear()
	# 2. Fluchtrahmen: Mauerrahmen in der Nähe der Änderungen
	var reach := area.grow(DIRTY_REACH)
	var bounds := Rect2i()
	var first := true
	for owner_id in _barrier_bbox:
		var r: Rect2i = _barrier_bbox[owner_id]
		if r.intersects(reach):
			bounds = r if first else bounds.merge(r)
			first = false
	if first:
		bounds = area
	bounds = bounds.grow(_enclosure_margin).intersection(region)
	# 3. Flutfüllung je Same
	_visit_stamp += 1
	if _visit_stamp > 2000000000:
		_visit.fill(0)
		_visit_stamp = 1
	for s in seeds:
		if s < 0 or _solid_mask[s] != 0 or _visit[s] == _visit_stamp:
			continue
		_flood(s, bounds)
	# 4. Tore neu verknüpfen
	_relink_gates()
	stats["relabels"] = int(stats["relabels"]) + 1
	var dt := Time.get_ticks_usec() - t0
	stats["relabel_usec_last"] = dt
	stats["relabel_usec_max"] = maxi(int(stats["relabel_usec_max"]), dt)
	stats["regions"] = regions.size()


## Nach dem Laden: alle Ringe neu (SiegeSystem.rebuild_runtime)
func relabel_all() -> void:
	if region_label.is_empty():
		return
	regions.clear()
	region_label.fill(0)
	gate_links.clear()
	_barrier_bbox.clear()
	for c in barriers:
		var owner_id := int(barriers[c])
		var r: Rect2i = _barrier_bbox.get(owner_id, Rect2i(c, Vector2i.ONE))
		_barrier_bbox[owner_id] = r.merge(Rect2i(c, Vector2i.ONE))
	_dirty_cells.clear()
	for c in barriers:
		_dirty_cells.append(c)
	process_dirty()


## Label löschen; gibt eine Zelle des Bereichs zurück (als zusätzlicher Same)
func _clear_region(label: int) -> int:
	var reg: Dictionary = regions.get(label, {})
	regions.erase(label)
	var cells: PackedInt32Array = reg.get("cells", PackedInt32Array())
	for i in cells:
		region_label[i] = 0
	return cells[0] if not cells.is_empty() else -1


## Flutfüllung (4er-Nachbarschaft, Tore blockiert). Verlässt sie bounds oder wird
## sie grösser als enclosure_max_cells, ist die Fläche offen (kein Label).
func _flood(start: int, bounds: Rect2i) -> void:
	var queue := PackedInt32Array([start])
	_visit[start] = _visit_stamp
	var boundary := {}
	var head := 0
	var open := false
	var x0 := bounds.position.x
	var y0 := bounds.position.y
	var x1 := bounds.end.x
	var y1 := bounds.end.y
	var w := _width
	var h := region.size.y
	var rect := Rect2i(index_to_cell(start), Vector2i.ONE)
	while head < queue.size():
		var i := queue[head]
		head += 1
		@warning_ignore("integer_division")
		var y := i / w
		var x := i - y * w
		for k in 4:
			var nx := x
			var ny := y
			match k:
				0:
					nx = x + 1
				1:
					nx = x - 1
				2:
					ny = y + 1
				_:
					ny = y - 1
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue  # Kartenrand zählt wie eine Wand
			var n := ny * w + nx
			if _solid_mask[n] != 0:
				boundary[n] = true
				continue
			if nx < x0 or ny < y0 or nx >= x1 or ny >= y1:
				open = true
				break
			if _visit[n] == _visit_stamp:
				continue
			_visit[n] = _visit_stamp
			queue.append(n)
		if open:
			break
		if queue.size() > _enclosure_max:
			open = true
			stats["open_large"] = int(stats["open_large"]) + 1
			break
	if open:
		# Restliche Zellen der offenen Fläche nicht als Samen weiterverfolgen: bleiben markiert
		return
	for i in queue:
		var c := index_to_cell(i)
		rect = rect.merge(Rect2i(c, Vector2i.ONE))
	var label := _next_label
	_next_label += 1
	for i in queue:
		region_label[i] = label
	var b := PackedInt32Array()
	for n in boundary:
		b.append(int(n))
	regions[label] = {"cells": queue, "boundary": b, "rect": rect}
	new_labels.append(label)


## gate_links für alle Tore neu: Labels der freien 4er-Nachbarn; zusammenhängende
## Tore (z. B. doppelt breite Tore) teilen sich ihre Labels
func _relink_gates() -> void:
	gate_links.clear()
	var done := {}
	for c in gates:
		if done.has(c):
			continue
		# Gruppe zusammenhängender Tore
		var group: Array = [c]
		done[c] = true
		var head := 0
		while head < group.size():
			var g: Vector2i = group[head]
			head += 1
			for n in [Vector2i(g.x + 1, g.y), Vector2i(g.x - 1, g.y), Vector2i(g.x, g.y + 1), Vector2i(g.x, g.y - 1)]:
				if gates.has(n) and not done.has(n):
					done[n] = true
					group.append(n)
		var links: Array = []
		for g in group:
			var gc: Vector2i = g
			for n in [Vector2i(gc.x + 1, gc.y), Vector2i(gc.x - 1, gc.y), Vector2i(gc.x, gc.y + 1), Vector2i(gc.x, gc.y - 1)]:
				if not region.has_point(n):
					continue
				var i: int = n.y * _width + n.x
				if _solid_mask[i] != 0:
					continue
				var l := region_label[i]
				if not links.has(l):
					links.append(l)
		for g in group:
			gate_links[g] = links


## Liegt cell innerhalb (Rand pad) des Rahmens irgendeiner Mauer?
func _near_barriers(cell: Vector2i, pad: int) -> bool:
	for owner_id in _barrier_bbox:
		if (_barrier_bbox[owner_id] as Rect2i).grow(pad).has_point(cell):
			return true
	return false


# ---------------------------------------------------------------------------
# Taschen (kleine, von Gebäuden eingeschlossene Flächen)
# ---------------------------------------------------------------------------

## Liegt cell in einer kleinen, von Gebäuden eingeschlossenen Fläche? Gibt die
## Kacheln dieser Fläche zurück (leer = offene Fläche). Begrenzte Breitensuche;
## nur nötig, wenn überhaupt ein Gebäude in der Nähe ist. sig = Reich, dessen Tore
## gerade offen sind (0 = keine).
func _pocket(cell: Vector2i, sig: int) -> Dictionary:
	if _pocket_cache_version != solid_version or _pocket_cache_gates != gate_version:
		_pocket_cache.clear()
		_pocket_cache_version = solid_version
		_pocket_cache_gates = gate_version
	var key := Vector3i(cell.x, cell.y, sig)
	if _pocket_cache.has(key):
		return _pocket_cache[key]
	var result := _find_pocket(cell)
	_pocket_cache[key] = result
	return result


func _find_pocket(cell: Vector2i) -> Dictionary:
	if not _solid_near(cell, POCKET_RADIUS):
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
			# Kartenrand zählt wie eine Wand
			if not region.has_point(c) or astar.is_point_solid(c):
				return true
	return false
