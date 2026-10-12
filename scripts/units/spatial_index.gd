## SpatialIndex
##
## Schnelle Umgebungssuche für Einheiten: die Karte wird in grobe Felder
## (Buckets) eingeteilt; jede Einheit liegt in genau einem. Eine Suche prüft
## nur die Buckets, die den Suchkreis berühren – statt aller Einheiten.
## Wird regelmässig neu aufgebaut (das ist billiger, als jede Bewegung
## einzeln nachzuführen).
class_name SpatialIndex
extends RefCounted

## Kantenlänge eines Buckets in Weltpixeln
var bucket_size := 256.0

## Bucket-Schlüssel (x * 65536 + y) -> Array von Units
var _buckets: Dictionary = {}
## Bucket-Schlüssel -> Bitmaske der Reiche, die dort Einheiten haben (Bit = id % 31)
var _masks: Dictionary = {}
var _inv := 1.0 / 256.0


func _init(p_bucket_size: float = 256.0) -> void:
	bucket_size = p_bucket_size
	_inv = 1.0 / bucket_size


func rebuild(units: Array) -> void:
	_buckets.clear()
	_masks.clear()
	for u in units:
		if u.inside != null or u.hp <= 0.0:
			continue
		var key: int = floori(u.position.x * _inv) * 65536 + floori(u.position.y * _inv)
		var list: Array = _buckets.get(key, [])
		if list.is_empty():
			_buckets[key] = list
			_masks[key] = 0
		list.append(u)
		_masks[key] = int(_masks[key]) | (1 << (int(u.kingdom.id) % 31))


## Alle Einheiten im Kreis um pos (Weltpixel)
func query(pos: Vector2, radius: float) -> Array:
	var result: Array = []
	var r2 := radius * radius
	var x0 := floori((pos.x - radius) * _inv)
	var x1 := floori((pos.x + radius) * _inv)
	var y0 := floori((pos.y - radius) * _inv)
	var y1 := floori((pos.y + radius) * _inv)
	for bx in range(x0, x1 + 1):
		for by in range(y0, y1 + 1):
			var list: Array = _buckets.get(bx * 65536 + by, [])
			for u in list:
				if u.position.distance_squared_to(pos) <= r2:
					result.append(u)
	return result


## Steht in den Buckets um pos eine Einheit eines anderen Reichs als kingdom_id?
## Billige Vorprüfung, bevor nach Feinden gesucht wird.
func has_other_kingdom(pos: Vector2, radius: float, kingdom_id: int) -> bool:
	var own := 1 << (kingdom_id % 31)
	var x0 := floori((pos.x - radius) * _inv)
	var x1 := floori((pos.x + radius) * _inv)
	var y0 := floori((pos.y - radius) * _inv)
	var y1 := floori((pos.y + radius) * _inv)
	for bx in range(x0, x1 + 1):
		for by in range(y0, y1 + 1):
			if int(_masks.get(bx * 65536 + by, 0)) & ~own != 0:
				return true
	return false
