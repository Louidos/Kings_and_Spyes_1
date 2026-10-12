## TerritorySystem
##
## Berechnet das Gebiet der Reiche: jedes fertige Gebäude beansprucht einen
## Kreis (territory_radius) um seine Mitte. Überschneiden sich Ansprüche,
## gewinnt das ältere Gebäude (kleinere uid). Dadurch ist das Ergebnis
## eindeutig und unabhängig davon, in welcher Reihenfolge gebaut wurde –
## wichtig für Spielstände und für Gebietsverluste in späteren Phasen.
## Ergebnis steht in WorldData.territory.
class_name TerritorySystem
extends RefCounted

## Gebiet eines Reichs hat sich geändert (bbox = Rechteck um das ganze Gebiet,
## dirty = Bereich, in dem sich etwas geändert haben kann)
signal changed(kingdom_id: int, bbox: Rect2i, dirty: Rect2i)


## Rechteck, das der Anspruch eines Gebäudes abdeckt
static func claim_rect(b: Building, world: WorldData) -> Rect2i:
	var r: int = b.def.get("territory_radius", 0)
	var fp := b.get_footprint()
	var rect := Rect2i(fp.position - Vector2i(r, r), fp.size + Vector2i(r, r) * 2)
	return rect.intersection(Rect2i(0, 0, world.width, world.height))


## Gesamtes Gebiet eines Reichs als Rechteck (aus seinen Gebäuden)
static func kingdom_bbox(kingdom: Kingdom, world: WorldData) -> Rect2i:
	var bbox := Rect2i()
	var first := true
	for b in kingdom.buildings:
		if not b.constructed or int(b.def.get("territory_radius", 0)) <= 0:
			continue
		var r := claim_rect(b, world)
		bbox = r if first else bbox.merge(r)
		first = false
	return bbox


## Berechnet die Besitzer aller Kacheln in rect neu (alle Reiche).
func recompute_area(world: WorldData, rect: Rect2i, kingdoms: Array) -> void:
	rect = rect.intersection(Rect2i(0, 0, world.width, world.height))
	if not rect.has_area():
		return
	var terr := world.territory
	var touched := {}
	# 1. Alles im Bereich löschen (und merken, wem es gehörte)
	for y in range(rect.position.y, rect.end.y):
		var row := y * world.width
		for x in range(rect.position.x, rect.end.x):
			var owner_id := terr[row + x]
			if owner_id != 0:
				touched[owner_id] = true
				terr[row + x] = 0

	# 2. Alle Ansprüche, die den Bereich berühren – ältere zuerst
	var claims: Array = []
	for k in kingdoms:
		for b in k.buildings:
			if b.constructed and int(b.def.get("territory_radius", 0)) > 0 and claim_rect(b, world).intersects(rect):
				claims.append(b)
	claims.sort_custom(func(a: Building, b: Building) -> bool: return a.uid < b.uid)

	for b in claims:
		var id: int = b.kingdom.id
		touched[id] = true
		var r: int = b.def["territory_radius"]
		var fp: Rect2i = b.get_footprint()
		var center := Vector2(fp.position) + Vector2(fp.size) * 0.5
		var r2 := float(r * r)
		var area := claim_rect(b, world).intersection(rect)
		for y in range(area.position.y, area.end.y):
			var row := y * world.width
			var dy := y + 0.5 - center.y
			for x in range(area.position.x, area.end.x):
				var dx := x + 0.5 - center.x
				if dx * dx + dy * dy <= r2 and terr[row + x] == 0:
					terr[row + x] = id

	for k in kingdoms:
		if touched.has(k.id):
			changed.emit(k.id, kingdom_bbox(k, world), rect)
