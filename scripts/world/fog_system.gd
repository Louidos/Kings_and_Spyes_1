## FogSystem
##
## Kriegsnebel: Sichtraster je Reich mit drei Zuständen je Kachel –
## UNEXPLORED (nie gesehen, schwarz), EXPLORED (früher gesehen, abgedunkelt, zeigt
## Gelände und zuletzt gesehene Gebäude) und VISIBLE (jetzt gesehen).
##
## Sicht geben eigene Einheiten (Unit.sight, schon mit Tag/Nacht- und Volksboni),
## eigene Gebäude (game_config.json → fog: building_sight, building_sight_by_type),
## verbündete Reiche (Dörfer mit Bündnis) und Spione beim Auskundschaften (Umkreis des
## Ziels, solange der Spion am Ziel ist).
##
## Das Raster wird nur für Reiche mit controller "player" geführt: Der Nebel gilt für Anzeige
## und Befehle des Spielers. Die KI behält ihr System aus Entdeckung und Kundschaft
## (EspionageSystem); Game.can_see fragt das Raster nur für Beobachter mit Raster.
## Aus ist der Nebel mit der Option "fog" = "off" im Dialog "Neues Spiel" und im Tutorial.
##
## Zustand (gespeichert): je Reich die erkundeten Kacheln (Bitfeld, komprimiert) und die
## zuletzt gesehenen fremden Gebäude (uid). Laufzeit: Zustand je Kachel, Liste der gerade
## sichtbaren Kacheln, Takt.
## Alte Spielstände ohne Nebel-Daten: eigenes Gebiet und Umkreis gelten als erkundet.
class_name FogSystem
extends Node

## Das Raster eines Reichs wurde neu berechnet (Darstellung, Minikarte)
signal updated(kingdom_id: int)

const UNEXPLORED := 0
const EXPLORED := 1
const VISIBLE := 2

var game: Node
var world: WorldData

## Reich-id -> PackedByteArray (Zustand je Kachel, Index y * width + x)
var grids: Dictionary = {}
## Reich-id -> {Gebäude-uid: true} – fremde Gebäude, die das Reich schon gesehen hat
var known_buildings: Dictionary = {}
## Zuletzt gemessene Dauer einer Aktualisierung (Mikrosekunden; Leistungsmessung)
var last_update_usec := 0
## Anzahl der bisherigen Aktualisierungen (Rauchtest)
var update_count := 0

var _enabled_option := true
## Reich-id -> PackedInt32Array der gerade sichtbaren Kacheln (zum schnellen Zurücksetzen)
var _visible_lists: Dictionary = {}
var _tick := 0
var _interval := 5
## Radius -> PackedInt32Array der Versätze (dx, dy abwechselnd) im Kreis
var _offsets: Dictionary = {}
var _ts := 64.0


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_ts = float(world.tile_size)
	_interval = maxi(int(DataDB.cfg("fog.update_interval_ticks", 5)), 1)
	_enabled_option = GameSession.get_option("fog") != "off"
	GameClock.sim_tick.connect(_on_sim_tick)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Ist der Kriegsnebel in dieser Partie an? (Option "Neues Spiel", nie im Tutorial)
func is_enabled() -> bool:
	if not _enabled_option:
		return false
	var tut: Variant = game.get("tutorial_system")
	if tut is TutorialSystem and (tut as TutorialSystem).is_running():
		return false
	return true


## Hat das Reich ein Sichtraster? (nur Spieler, und nur mit Nebel)
func has_grid(k: Kingdom) -> bool:
	return k != null and is_enabled() and grids.has(k.id)


## Zustand einer Kachel für das Reich (ohne Raster: VISIBLE)
func get_state(k: Kingdom, cell: Vector2i) -> int:
	if not has_grid(k) or not world.in_bounds(cell):
		return VISIBLE
	return (grids[k.id] as PackedByteArray)[cell.y * world.width + cell.x]


## Zustand an einer Weltposition
func get_state_at(k: Kingdom, pos: Vector2) -> int:
	return get_state(k, world.world_to_cell(pos))


## Sieht das Reich gerade diese Stelle?
func is_visible_at(k: Kingdom, pos: Vector2) -> bool:
	return get_state_at(k, pos) == VISIBLE


## Hat das Reich dieses fremde Gebäude schon gesehen? (zuletzt gesehen)
func is_building_known(k: Kingdom, b: Building) -> bool:
	if not has_grid(k) or b == null:
		return true
	return (known_buildings.get(k.id, {}) as Dictionary).has(b.uid)


## Anteil der Kacheln je Zustand (Rauchtest, Anzeige): {"unexplored", "explored", "visible"}
func get_counts(k: Kingdom) -> Dictionary:
	var out := {"unexplored": 0, "explored": 0, "visible": 0}
	if not grids.has(k.id):
		return out
	var g: PackedByteArray = grids[k.id]
	var vis: PackedInt32Array = _visible_lists.get(k.id, PackedInt32Array())
	out["visible"] = vis.size()
	var explored := g.count(EXPLORED)
	out["explored"] = explored
	out["unexplored"] = g.size() - explored - vis.size()
	return out


## Sichtweite eines Gebäudes in Kacheln
static func building_sight(b: Building) -> float:
	var by_type: Dictionary = DataDB.cfg("fog.building_sight_by_type", {})
	return float(by_type.get(b.get_def_id(), DataDB.cfg("fog.building_sight", 6.0)))


# ---------------------------------------------------------------------------
# Aktualisierung
# ---------------------------------------------------------------------------

func _on_sim_tick(_dt: float) -> void:
	_tick += 1
	if _tick % _interval != 0:
		return
	update_all()


## Raster aller Spieler-Reiche neu berechnen
func update_all() -> void:
	if not is_enabled():
		_reveal_all_units()
		return
	for k in game.kingdoms:
		var kingdom: Kingdom = k
		if kingdom.controller == "player" and not kingdom.defeated:
			update_kingdom(kingdom)


## Raster eines Reichs neu berechnen: sichtbare Kacheln zurück auf "erkundet", dann alle
## Sichtquellen eintragen, danach fremde Einheiten aus- bzw. einblenden und Gebäude merken.
func update_kingdom(k: Kingdom) -> void:
	var t0 := Time.get_ticks_usec()
	var g := _ensure_grid(k)
	var old_vis: PackedInt32Array = _visible_lists.get(k.id, PackedInt32Array())
	for i in old_vis:
		g[i] = EXPLORED
	var vis := PackedInt32Array()
	# Gleiche Kachel und gleicher Radius nur einmal eintragen (Gruppen, Arbeiter am Gebäude)
	var stamped := {}
	for src in _collect_sources(k):
		var cell: Vector2i = src[0]
		var r := maxi(int(round(float(src[1]))), 1)
		var key := (cell.y * world.width + cell.x) * 64 + mini(r, 63)
		if stamped.has(key):
			continue
		stamped[key] = true
		_stamp(g, vis, cell, r)
	_visible_lists[k.id] = vis
	grids[k.id] = g
	_apply_visibility(k, g)
	update_count += 1
	last_update_usec = Time.get_ticks_usec() - t0
	updated.emit(k.id)


## Sichtquellen: [Kachel, Radius] von eigenen und verbündeten Einheiten und Gebäuden,
## dazu Spione beim Auskundschaften (Umkreis des Ziels)
func _collect_sources(k: Kingdom) -> Array:
	var out: Array = []
	var min_sight := float(DataDB.cfg("fog.unit_sight_min", 3.0))
	for other in game.kingdoms:
		var o: Kingdom = other
		if o.defeated or not game.are_allied(k, o):
			continue
		for u in o.units:
			if is_instance_valid(u) and u.is_alive():
				out.append([world.world_to_cell(u.position), maxf(u.sight, min_sight)])
		for b in o.buildings:
			if is_instance_valid(b):
				var building: Building = b
				out.append([world.world_to_cell(building.get_center()), building_sight(building)
						+ maxf(building.size.x, building.size.y) * 0.5])
	var spy_system: Variant = game.get("spy_system")
	if spy_system is SpySystem:
		var reveal := float(DataDB.cfg("fog.spy_reveal_radius", 14.0))
		for u in (spy_system as SpySystem).get_spies(k):
			var rec: Dictionary = (spy_system as SpySystem).get_record(u)
			if str(rec.get("mission", "")) != "scout" or str(rec.get("state", "")) != "active":
				continue
			var target: Kingdom = game.get_kingdom(int(rec.get("target_id", 0)))
			var center: Vector2 = u.position
			if target != null and is_instance_valid(target.castle):
				center = target.castle.get_center()
			elif target != null and game.village_system.get_hall(target) != null:
				center = game.village_system.get_hall(target).get_center()
			out.append([world.world_to_cell(center), reveal])
	return out


## Kreis mit Radius r um cell als sichtbar eintragen
func _stamp(g: PackedByteArray, vis: PackedInt32Array, cell: Vector2i, r: int) -> void:
	var offs := _get_offsets(r)
	var w := world.width
	var h := world.height
	var n := offs.size()
	var i := 0
	while i < n:
		var x := cell.x + offs[i]
		var y := cell.y + offs[i + 1]
		i += 2
		if x < 0 or y < 0 or x >= w or y >= h:
			continue
		var idx := y * w + x
		if g[idx] != VISIBLE:
			g[idx] = VISIBLE
			vis.append(idx)


func _get_offsets(r: int) -> PackedInt32Array:
	if _offsets.has(r):
		return _offsets[r]
	var offs := PackedInt32Array()
	var r2 := (r + 0.5) * (r + 0.5)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r2:
				offs.append(dx)
				offs.append(dy)
	_offsets[r] = offs
	return offs


func _ensure_grid(k: Kingdom) -> PackedByteArray:
	if grids.has(k.id):
		return grids[k.id]
	var g := PackedByteArray()
	g.resize(world.width * world.height)
	g.fill(UNEXPLORED)
	grids[k.id] = g
	known_buildings[k.id] = {}
	return g


## Fremde Einheiten ausserhalb der Sicht aus-, sichtbare einblenden; fremde Gebäude, die
## gerade zu sehen sind, als "zuletzt gesehen" merken; nie gesehene ausblenden.
## Nur für das Reich, aus dessen Sicht gezeichnet wird (der Spieler).
func _apply_visibility(k: Kingdom, g: PackedByteArray) -> void:
	if k != game.player:
		return
	var known: Dictionary = known_buildings.get(k.id, {})
	var w := world.width
	for other in game.kingdoms:
		var o: Kingdom = other
		var allied: bool = game.are_allied(k, o)
		for u in o.units:
			if not is_instance_valid(u):
				continue
			var hide := false
			if not allied:
				var c: Vector2i = world.world_to_cell(u.position)
				hide = not world.in_bounds(c) or g[c.y * w + c.x] != VISIBLE
			(u as Unit).set_fog_hidden(hide)
		for b in o.buildings:
			if not is_instance_valid(b):
				continue
			var building: Building = b
			if allied:
				building.visible = true
				continue
			if not known.has(building.uid) and _building_in_sight(building, g):
				known[building.uid] = true
			building.visible = known.has(building.uid)
	known_buildings[k.id] = known


## Ist eine Kachel des Gebäudes gerade sichtbar?
func _building_in_sight(b: Building, g: PackedByteArray) -> bool:
	var w := world.width
	for dy in b.size.y:
		for dx in b.size.x:
			var c := b.cell + Vector2i(dx, dy)
			if world.in_bounds(c) and g[c.y * w + c.x] == VISIBLE:
				return true
	return false


## Nebel aus: alle Einheiten und Gebäude zeigen (einmal, z. B. nach dem Tutorial-Start)
func _reveal_all_units() -> void:
	if grids.is_empty() and _visible_lists.is_empty():
		return
	for other in game.kingdoms:
		for u in (other as Kingdom).units:
			if is_instance_valid(u):
				(u as Unit).set_fog_hidden(false)
		for b in (other as Kingdom).buildings:
			if is_instance_valid(b):
				(b as Building).visible = true
	grids.clear()
	_visible_lists.clear()
	updated.emit(game.player.id if game.player != null else 0)


## Alles erkundet markieren, was das Reich gerade besitzt, mit Umkreis (alte Spielstände)
func explore_own_area(k: Kingdom, margin: float) -> void:
	var g := _ensure_grid(k)
	var vis := PackedInt32Array()
	for b in k.buildings:
		if is_instance_valid(b):
			var building: Building = b
			_stamp(g, vis, world.world_to_cell(building.get_center()),
					int(round(building_sight(building) + margin)))
	for i in vis:
		g[i] = EXPLORED
	grids[k.id] = g


# ---------------------------------------------------------------------------
# Speichern und Laden
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out := {}
	for kid in grids:
		var g: PackedByteArray = grids[kid]
		# Rohes Raster komprimiert (VISIBLE gilt beim Laden als erkundet)
		out[str(kid)] = {"size": g.size(), "cells": g.compress(FileAccess.COMPRESSION_DEFLATE),
				"known": (known_buildings.get(kid, {}) as Dictionary).keys()}
	return {"grids": out}


func from_dict(d: Dictionary) -> void:
	grids.clear()
	known_buildings.clear()
	_visible_lists.clear()
	var saved: Dictionary = d.get("grids", {}) if d.get("grids", {}) is Dictionary else {}
	for key in saved:
		var e: Dictionary = saved[key]
		var n := int(e.get("size", 0))
		if n != world.width * world.height:
			continue
		var raw: Variant = e.get("cells", PackedByteArray())
		if not (raw is PackedByteArray):
			continue
		var g: PackedByteArray = (raw as PackedByteArray).decompress(n, FileAccess.COMPRESSION_DEFLATE)
		if g.size() != n:
			continue
		var i := g.find(VISIBLE)
		while i >= 0:
			g[i] = EXPLORED
			i = g.find(VISIBLE, i + 1)
		grids[int(key)] = g
		var known := {}
		for uid in e.get("known", []):
			known[int(uid)] = true
		known_buildings[int(key)] = known


func rebuild_runtime() -> void:
	_enabled_option = GameSession.get_option("fog") != "off"
	if not is_enabled():
		_reveal_all_units()
		return
	# Spielstand ohne Nebel-Daten (1.3.x): eigenes Gebiet und Umkreis gelten als erkundet
	for k in game.kingdoms:
		var kingdom: Kingdom = k
		if kingdom.controller == "player" and not grids.has(kingdom.id):
			explore_own_area(kingdom, float(DataDB.cfg("fog.legacy_explored_margin", 12.0)))
	update_all()
