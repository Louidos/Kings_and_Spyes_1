## SpatialIndex
##
## Schnelle Umgebungssuche für Einheiten: die Karte wird in grobe Felder
## (Buckets) eingeteilt, getrennt nach Reich. Eine Suche prüft nur die
## Buckets, die den Suchkreis berühren – und auf Wunsch nur die Einheiten
## eines bestimmten Reichs (Feindsuche in einer Schlacht muss so nicht die
## eigene Armee durchgehen).
## Wird regelmässig neu aufgebaut (das ist billiger, als jede Bewegung
## einzeln nachzuführen).
class_name SpatialIndex
extends RefCounted

## Kantenlänge eines Buckets in Weltpixeln
var bucket_size := 256.0

## Kingdom.id -> {Bucket-Schlüssel (x * 65536 + y) -> Array von Units}
var _by_kingdom: Dictionary = {}
var _inv := 1.0 / 256.0


func _init(p_bucket_size: float = 256.0) -> void:
	bucket_size = p_bucket_size
	_inv = 1.0 / bucket_size


func rebuild(units: Array) -> void:
	_by_kingdom.clear()
	for u in units:
		if u.inside != null or u.hp <= 0.0:
			continue
		var kid: int = u.kingdom.id
		if not _by_kingdom.has(kid):
			_by_kingdom[kid] = {}
		var map: Dictionary = _by_kingdom[kid]
		var key: int = floori(u.position.x * _inv) * 65536 + floori(u.position.y * _inv)
		if map.has(key):
			(map[key] as Array).append(u)
		else:
			map[key] = [u]


## Reiche, von denen Einheiten im Index stehen
func kingdom_ids() -> Array:
	return _by_kingdom.keys()


## Alle Einheiten im Kreis um pos (Weltpixel), alle Reiche
func query(pos: Vector2, radius: float) -> Array:
	var result: Array = []
	for kid in _by_kingdom:
		_collect(_by_kingdom[kid], pos, radius, result)
	return result


## Einheiten eines Reichs im Kreis um pos
func query_kingdom(pos: Vector2, radius: float, kingdom_id: int) -> Array:
	var result: Array = []
	if _by_kingdom.has(kingdom_id):
		_collect(_by_kingdom[kingdom_id], pos, radius, result)
	return result


## Hat das Reich in den Buckets um pos überhaupt Einheiten? (billige Vorprüfung)
func any_of_kingdom(pos: Vector2, radius: float, kingdom_id: int) -> bool:
	if not _by_kingdom.has(kingdom_id):
		return false
	var map: Dictionary = _by_kingdom[kingdom_id]
	var x0 := floori((pos.x - radius) * _inv)
	var x1 := floori((pos.x + radius) * _inv)
	var y0 := floori((pos.y - radius) * _inv)
	var y1 := floori((pos.y + radius) * _inv)
	for bx in range(x0, x1 + 1):
		for by in range(y0, y1 + 1):
			if map.has(bx * 65536 + by):
				return true
	return false


## Steht in den Buckets um pos eine Einheit eines anderen Reichs als kingdom_id?
func has_other_kingdom(pos: Vector2, radius: float, kingdom_id: int) -> bool:
	for kid in _by_kingdom:
		if kid != kingdom_id and any_of_kingdom(pos, radius, kid):
			return true
	return false


func _collect(map: Dictionary, pos: Vector2, radius: float, result: Array) -> void:
	var r2 := radius * radius
	var x0 := floori((pos.x - radius) * _inv)
	var x1 := floori((pos.x + radius) * _inv)
	var y0 := floori((pos.y - radius) * _inv)
	var y1 := floori((pos.y + radius) * _inv)
	for bx in range(x0, x1 + 1):
		for by in range(y0, y1 + 1):
			var key := bx * 65536 + by
			if not map.has(key):
				continue
			for u in map[key]:
				if u.position.distance_squared_to(pos) <= r2:
					result.append(u)
