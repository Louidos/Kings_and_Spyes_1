## TerritoryBorder
##
## Zeichnet die Gebiete aller (sichtbaren) Reiche: leichte Einfärbung der
## Fläche und eine deutliche Grenzlinie in der Reichsfarbe.
## Die Linien werden zeilenweise gespeichert; bei einer Gebietsänderung werden
## nur die betroffenen Zeilen neu berechnet (auch grosse Reiche bleiben flüssig).
## Weit herausgezoomt wird die Linie zur Haarlinie.
class_name TerritoryBorder
extends Node2D

## Unterhalb dieses Zooms als Haarlinie zeichnen (sonst wäre sie unsichtbar)
const HAIRLINE_ZOOM := 0.4

var line_width := 3.0
var fill_alpha := 0.07
var line_alpha := 0.85

## Kingdom.id -> {"color", "visible", "bbox": Rect2i, "rows": {y: [PackedVector2Array, Array]},
##                "segments": PackedVector2Array, "fill": Array}
var _kingdoms: Dictionary = {}
var _hairline := false


## Berechnet Grenze und Fläche eines Reichs neu. bbox = ganzes Gebiet; dirty =
## Bereich mit Änderungen (leer = alles neu).
func rebuild(world: WorldData, kingdom_id: int, bbox: Rect2i, color: Color, dirty: Rect2i = Rect2i()) -> void:
	var k: Dictionary = _kingdoms.get(kingdom_id, {"visible": true, "rows": {}})
	k["color"] = color
	k["bbox"] = bbox
	var rows: Dictionary = k["rows"]
	# Zeilen ausserhalb des Gebiets verwerfen
	for y in rows.keys():
		if y < bbox.position.y or y >= bbox.end.y:
			rows.erase(y)
	var y0 := bbox.position.y
	var y1 := bbox.end.y
	if dirty.has_area():
		var d := dirty.grow(1)
		y0 = maxi(y0, d.position.y)
		y1 = mini(y1, d.end.y)
	# Hat sich die Breite des Gebiets geändert, alle Zeilen neu berechnen
	if int(k.get("x0", -1)) != bbox.position.x or int(k.get("x1", -1)) != bbox.end.x:
		y0 = bbox.position.y
		y1 = bbox.end.y
		k["x0"] = bbox.position.x
		k["x1"] = bbox.end.x
	for y in range(y0, y1):
		rows[y] = _scan_row(world, kingdom_id, y, bbox.position.x, bbox.end.x)
	# Zusammenfügen für das Zeichnen
	var segments := PackedVector2Array()
	var fill: Array = []
	for y in rows:
		segments.append_array(rows[y][0])
		fill.append_array(rows[y][1])
	k["segments"] = segments
	k["fill"] = fill
	_kingdoms[kingdom_id] = k
	queue_redraw()


## Kanten und Füllstreifen einer Zeile (direkter Arrayzugriff, schnell)
func _scan_row(world: WorldData, kingdom_id: int, y: int, x_from: int, x_to: int) -> Array:
	var segs := PackedVector2Array()
	var fill: Array = []
	var ts := float(world.tile_size)
	var terr := world.territory
	var w := world.width
	var row := y * w
	var has_up := y > 0
	var has_down := y < world.height - 1
	var run_start := -1
	var py := y * ts
	for x in range(x_from, x_to + 1):
		var owned := x < x_to and terr[row + x] == kingdom_id
		if owned and run_start < 0:
			run_start = x
		elif not owned and run_start >= 0:
			fill.append(Rect2(run_start * ts, py, (x - run_start) * ts, ts))
			run_start = -1
		if not owned:
			continue
		var px := x * ts
		if not has_up or terr[row - w + x] != kingdom_id:
			segs.append_array([Vector2(px, py), Vector2(px + ts, py)])
		if not has_down or terr[row + w + x] != kingdom_id:
			segs.append_array([Vector2(px, py + ts), Vector2(px + ts, py + ts)])
		if x == 0 or terr[row + x - 1] != kingdom_id:
			segs.append_array([Vector2(px, py), Vector2(px, py + ts)])
		if x == w - 1 or terr[row + x + 1] != kingdom_id:
			segs.append_array([Vector2(px + ts, py), Vector2(px + ts, py + ts)])
	return [segs, fill]


## Für Phase 7: fremde Reiche erst nach Entdeckung zeigen
func set_kingdom_visible(kingdom_id: int, value: bool) -> void:
	if _kingdoms.has(kingdom_id):
		_kingdoms[kingdom_id]["visible"] = value
		queue_redraw()


func clear_all() -> void:
	_kingdoms.clear()
	queue_redraw()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var hair := cam.zoom.x < HAIRLINE_ZOOM
	if hair != _hairline:
		_hairline = hair
		queue_redraw()


func _draw() -> void:
	for id in _kingdoms:
		var k: Dictionary = _kingdoms[id]
		if not k["visible"] or not k.has("segments"):
			continue
		var color: Color = k["color"]
		var fill_color := Color(color, fill_alpha)
		for r in k["fill"]:
			draw_rect(r, fill_color, true)
		var segments: PackedVector2Array = k["segments"]
		if segments.size() >= 2:
			draw_multiline(segments, Color(color, line_alpha), -1.0 if _hairline else line_width)
