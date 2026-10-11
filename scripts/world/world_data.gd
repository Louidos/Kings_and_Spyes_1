## WorldData
##
## Reine Daten der Spielwelt (keine Nodes): Grösse, Seed und pro Kachel das
## Biom sowie Höhe und Feuchtigkeit. Alle anderen Systeme (Rendering, Bauen,
## Wegfindung, KI) fragen hier nach dem Gelände.
##
## Die Karte wird aus dem Seed vollständig neu erzeugt. Für Spielstände reicht
## es daher, Seed + Grösse zu speichern und später nur die Veränderungen.
class_name WorldData
extends RefCounted

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


func setup(p_seed: int, p_width: int, p_height: int, p_tile_size: int) -> void:
	world_seed = p_seed
	width = p_width
	height = p_height
	tile_size = p_tile_size
	var n := width * height
	biomes.resize(n)
	elevation.resize(n)
	moisture.resize(n)


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
