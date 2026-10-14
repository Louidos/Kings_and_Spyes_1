## WorldData
##
## Reine Daten der Spielwelt (keine Nodes): Grösse, Seed und pro Kachel das
## Biom sowie Höhe und Feuchtigkeit. Alle anderen Systeme (Rendering, Bauen,
## Wegfindung, KI) fragen hier nach dem Gelände.
##
## Die Karte wird aus dem Seed vollständig neu erzeugt. Für Spielstände reicht
## es daher, Seed + Grösse zu speichern und später nur die Veränderungen
## (Vorkommen, Biome, Gebiet, Strassen, Gebäude).
class_name WorldData
extends RefCounted

## Biom oder Vorkommen einer Kachel hat sich geändert (für Darstellung/Wegfindung)
signal cell_changed(cell: Vector2i)
## Strasse einer Kachel wurde geplant, fertig oder entfernt
signal road_changed(cell: Vector2i)

## Zustände einer Strassenkachel
const ROAD_NONE := 0
const ROAD_PLANNED := 1
const ROAD_BUILT := 2

## Relief-Schattierung des Übersichtsbilds (auch vom WorldGenerator genutzt)
const SHADE_BASE := 0.82
const SHADE_PER_HEIGHT := 0.0011
const SHADE_SLOPE := 0.012
const SHADE_SLOPE_MAX := 0.18

var world_seed: int = 0
## Breite/Höhe in Kacheln
var width: int = 0
var height: int = 0
## Pixel pro Kachel
var tile_size: int = 64

## Biom-Index pro Kachel (Index in DataDB.biomes), Zeile für Zeile
var biomes := PackedByteArray()
## Höhe pro Kachel 0–255 (ausgeglichen: 255 = höchste Stelle)
var elevation := PackedByteArray()
## Feuchtigkeit pro Kachel 0–255
var moisture := PackedByteArray()

## Übersichtsbild: 1 Pixel pro Kachel (für Fernansicht und Minikarte)
var overview_image: Image
## Vorgeschlagener Startplatz des Spielers (Kachel)
var start_cell := Vector2i.ZERO
## Anzahl Kacheln je Biom-Index (Statistik/Debug)
var biome_counts := PackedInt32Array()

## Vorkommen pro Kachel: 0 = keines, sonst Index in DataDB.deposits + 1
var deposit_type := PackedByteArray()
## Restmenge des Vorkommens (-1 = unendlich)
var deposit_amount := PackedInt32Array()
## Besitzer pro Kachel (Kingdom.id), 0 = niemand
var territory := PackedByteArray()
## Kachel -> Gebäude (auch Baustellen). Dünn besetzt, daher Dictionary.
var occupancy: Dictionary = {}
## Kachel -> ROAD_PLANNED / ROAD_BUILT
var roads: Dictionary = {}
## Kachel -> Besitzer der Strasse (Kingdom.id), bleibt auch nach dem Bau erhalten
var road_owner: Dictionary = {}
## Kachel -> geleistete Bauarbeit (nur geplante Strassen)
var road_progress: Dictionary = {}
## Zählt jede Änderung an sammelbaren Vorkommen hoch (neu, leer, nachgewachsen).
## Arbeiter, die nichts gefunden haben, suchen erst wieder, wenn sich das ändert.
var deposit_version := 0
## Geleerte Vorkommen, die nachwachsen (Kachel -> true)
var regrowing: Dictionary = {}
## Übersichtsbild wurde verändert und muss neu hochgeladen werden
var overview_dirty := false
## Besondere Plätze aus der Generierung: Array von {"kind", "cell", "biome", …}.
## kind: "start" (Startplatz), "camp" (Monsterlager, cell = obere linke Kachel;
## optional "kinds" und "size"), "village" (neutrales Dorf, cell = Mitte; "people",
## "size" = Anzahl Hütten, "index"), "kingdom" (Platz für ein gegnerisches Königreich
## ab Phase 7, cell = Mitte; "index").
var sites: Array = []
## Gefahrenzonen um Monsterhöhlen: Anzahl Höhlen, deren Umkreis die Kachel
## abdeckt (0 = sicher). Bewohner sammeln dort nicht.
var danger := PackedByteArray()

var _road_speed_mult := 1.6


func setup(p_seed: int, p_width: int, p_height: int, p_tile_size: int) -> void:
	world_seed = p_seed
	width = p_width
	height = p_height
	tile_size = p_tile_size
	var n := width * height
	biomes.resize(n)
	elevation.resize(n)
	moisture.resize(n)
	deposit_type.resize(n)
	deposit_amount.resize(n)
	territory.resize(n)
	_road_speed_mult = maxf(float(DataDB.eco("road.speed_mult", 1.6)), 0.01)


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func cell_index(cell: Vector2i) -> int:
	return cell.y * width + cell.x


## Biom-Index an einer Kachel, -1 ausserhalb der Karte
func get_biome_index(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return -1
	return biomes[cell_index(cell)]


## Biom-Daten (Dictionary aus biomes.json) an einer Kachel, leer ausserhalb
func get_biome(cell: Vector2i) -> Dictionary:
	var i := get_biome_index(cell)
	return DataDB.get_biome(i) if i >= 0 else {}


func get_elevation(cell: Vector2i) -> float:
	return elevation[cell_index(cell)] / 255.0 if in_bounds(cell) else 0.0


func get_moisture(cell: Vector2i) -> float:
	return moisture[cell_index(cell)] / 255.0 if in_bounds(cell) else 0.0


## Weltposition (Pixel) -> Kachel
func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / tile_size), floori(pos.y / tile_size))


## Kachel -> Weltposition des Kachelmittelpunkts
func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size)


## Grösse der Welt in Pixeln
func get_pixel_size() -> Vector2:
	return Vector2(width * tile_size, height * tile_size)


func get_pixel_rect() -> Rect2:
	return Rect2(Vector2.ZERO, get_pixel_size())


# ---------------------------------------------------------------------------
# Biome
# ---------------------------------------------------------------------------

## Ändert das Biom einer Kachel (z. B. abgeholzter Wald -> Ebene).
func set_biome(cell: Vector2i, biome_index: int) -> void:
	if not in_bounds(cell):
		return
	biomes[cell_index(cell)] = biome_index
	_update_overview_pixel(cell)
	cell_changed.emit(cell)


## Farbe eines Übersichtspixels (gleiche Formel wie im WorldGenerator)
func overview_color(cell: Vector2i) -> Color:
	var i := cell_index(cell)
	var e := float(elevation[i])
	var shade := SHADE_BASE + e * SHADE_PER_HEIGHT
	if cell.x > 0 and cell.y > 0:
		shade += clampf((e - float(elevation[i - width - 1])) * SHADE_SLOPE, -SHADE_SLOPE_MAX, SHADE_SLOPE_MAX)
	var c: Color = DataDB.get_biome(biomes[i])["color"]
	return Color(clampf(c.r * shade, 0.0, 1.0), clampf(c.g * shade, 0.0, 1.0), clampf(c.b * shade, 0.0, 1.0))


func _update_overview_pixel(cell: Vector2i) -> void:
	if overview_image == null:
		return
	overview_image.set_pixelv(cell, overview_color(cell))
	overview_dirty = true


# ---------------------------------------------------------------------------
# Rohstoffvorkommen
# ---------------------------------------------------------------------------

## Index des Vorkommens (DataDB.deposits), -1 wenn keines
func get_deposit_index(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return -1
	return deposit_type[cell_index(cell)] - 1


func get_deposit(cell: Vector2i) -> Dictionary:
	return DataDB.get_deposit(get_deposit_index(cell))


func get_deposit_amount(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return 0
	return deposit_amount[cell_index(cell)]


## Kann hier gerade gesammelt werden? (passendes, sammelbares, nicht leeres
## Vorkommen; nachwachsende erst wieder, wenn sie voll sind)
func is_gatherable(cell: Vector2i, deposit_indices: PackedInt32Array) -> bool:
	var d := get_deposit_index(cell)
	if d < 0 or not deposit_indices.has(d):
		return false
	if not DataDB.deposits[d]["gatherable"] or regrowing.has(cell):
		return false
	return deposit_amount[cell_index(cell)] != 0


## Setzt oder entfernt (deposit_index = -1) ein Vorkommen.
func set_deposit(cell: Vector2i, deposit_index: int, amount: int) -> void:
	if not in_bounds(cell):
		return
	var i := cell_index(cell)
	deposit_type[i] = deposit_index + 1 if deposit_index >= 0 else 0
	deposit_amount[i] = amount if deposit_index >= 0 else 0
	regrowing.erase(cell)
	deposit_version += 1
	cell_changed.emit(cell)


## Entnimmt bis zu `amount` Einheiten und gibt die tatsächlich entnommene Menge
## zurück. Ist das Vorkommen danach leer, wird es entfernt (und z. B. Wald zu
## Ebene) oder es beginnt nachzuwachsen.
func harvest(cell: Vector2i, amount: int) -> int:
	if amount <= 0 or not in_bounds(cell):
		return 0
	var i := cell_index(cell)
	var t := deposit_type[i]
	if t == 0:
		return 0
	var left := deposit_amount[i]
	if left < 0:
		return amount  # unendlich
	var taken := mini(amount, left)
	left -= taken
	deposit_amount[i] = left
	if left == 0 and taken > 0:
		deposit_version += 1
		var def := DataDB.get_deposit(t - 1)
		var depleted_biome: String = def.get("depleted_biome", "")
		if not depleted_biome.is_empty():
			deposit_type[i] = 0
			set_biome(cell, DataDB.biome_index_by_id.get(depleted_biome, biomes[i]))
		elif int(def.get("regrow_per_hour", 0)) > 0:
			regrowing[cell] = true
			cell_changed.emit(cell)
		else:
			deposit_type[i] = 0
			cell_changed.emit(cell)
	return taken


## Lässt geleerte Vorkommen nachwachsen (wird stündlich aufgerufen).
func regrow(hours: int) -> void:
	for cell in regrowing.keys():
		var i := cell_index(cell)
		var def := DataDB.get_deposit(deposit_type[i] - 1)
		if def.is_empty():
			regrowing.erase(cell)
			continue
		var full: int = def["amount"][1]
		deposit_amount[i] = mini(deposit_amount[i] + int(def.get("regrow_per_hour", 0)) * hours, full)
		if deposit_amount[i] >= full:
			regrowing.erase(cell)
			deposit_version += 1
			cell_changed.emit(cell)  # wieder voll und sammelbar


# ---------------------------------------------------------------------------
# Gebiet, Gebäude, Strassen, Bewegung
# ---------------------------------------------------------------------------

## Liegt die Kachel in der Gefahrenzone einer Monsterhöhle?
func is_dangerous(cell: Vector2i) -> bool:
	return not danger.is_empty() and in_bounds(cell) and danger[cell_index(cell)] > 0


## Gefahrenzone (Kreis) hinzufügen (delta 1) oder entfernen (delta -1)
func mark_danger(center: Vector2i, radius: int, delta: int) -> void:
	if danger.is_empty():
		danger.resize(width * height)
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var c := Vector2i(x, y)
			if not in_bounds(c) or (c - center).length_squared() > radius * radius:
				continue
			var i := cell_index(c)
			danger[i] = clampi(danger[i] + delta, 0, 255)
	# Sammler, die nichts gefunden haben, sollen neu suchen
	deposit_version += 1


## Alle Plätze einer Art
func get_sites(kind: String) -> Array:
	var list: Array = []
	for site in sites:
		if site.get("kind", "") == kind:
			list.append(site)
	return list


## Besitzer der Kachel (Kingdom.id), 0 = niemand
func get_owner(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return 0
	return territory[cell_index(cell)]


## Gebäude (oder Baustelle) auf der Kachel, sonst null
func get_building_at(cell: Vector2i) -> Object:
	return occupancy.get(cell, null)


func get_road(cell: Vector2i) -> int:
	return int(roads.get(cell, ROAD_NONE))


## Setzt den Strassenzustand einer Kachel (ROAD_NONE entfernt die Strasse).
func set_road(cell: Vector2i, state: int, owner_id: int = 0) -> void:
	if state == ROAD_NONE:
		roads.erase(cell)
		road_owner.erase(cell)
		road_progress.erase(cell)
	else:
		roads[cell] = state
		if owner_id > 0:
			road_owner[cell] = owner_id
		if state == ROAD_PLANNED:
			road_progress[cell] = float(road_progress.get(cell, 0.0))
		else:
			road_progress.erase(cell)
	road_changed.emit(cell)


## Bewegungskosten einer Kachel: Biom-Kosten, auf fertigen Strassen geringer.
func get_move_cost(cell: Vector2i) -> float:
	if not in_bounds(cell):
		return 999.0
	var cost: float = DataDB.biomes[biomes[cell_index(cell)]]["movement_cost"]
	if roads.get(cell, ROAD_NONE) == ROAD_BUILT:
		cost /= _road_speed_mult
	return cost
