## TerritoryBorder
##
## Zeichnet die Gebiete aller (sichtbaren) Reiche: leichte Einfärbung der
## Fläche und eine deutliche Grenzlinie in der Reichsfarbe. Die Linien werden
## nur bei Gebietsänderungen neu berechnet; danach zeichnet Godot das
## zwischengespeicherte Ergebnis. Weit herausgezoomt wird die Linie dünn.
class_name TerritoryBorder
extends Node2D

## Unterhalb dieses Zooms als Haarlinie zeichnen (sonst wäre sie unsichtbar)
const HAIRLINE_ZOOM := 0.4

var line_width := 3.0
var fill_alpha := 0.07
var line_alpha := 0.85

## Kingdom.id -> {"color": Color, "segments": PackedVector2Array, "fill": Array[Rect2], "visible": bool}
var _kingdoms: Dictionary = {}
var _hairline := false


## Berechnet Grenze und Fläche eines Reichs innerhalb bbox neu.
func rebuild(world: WorldData, kingdom_id: int, bbox: Rect2i, color: Color) -> void:
	var segments := PackedVector2Array()
	var fill: Array[Rect2] = []
	var ts := float(world.tile_size)
	var terr := world.territory
	for y in range(bbox.position.y, bbox.end.y):
		var row := y * world.width
		var run_start := -1
		for x in range(bbox.position.x, bbox.end.x + 1):
			var owned := x < bbox.end.x and terr[row + x] == kingdom_id
			# Füllung: zusammenhängende Läufe pro Zeile
			if owned and run_start < 0:
				run_start = x
			elif not owned and run_start >= 0:
				fill.append(Rect2(run_start * ts, y * ts, (x - run_start) * ts, ts))
				run_start = -1
			if not owned:
				continue
			# Grenzkanten: Nachbar gehört nicht zum Reich
			var px := x * ts
			var py := y * ts
			if not _owned(world, x, y - 1, kingdom_id):
				segments.append_array([Vector2(px, py), Vector2(px + ts, py)])
			if not _owned(world, x, y + 1, kingdom_id):
				segments.append_array([Vector2(px, py + ts), Vector2(px + ts, py + ts)])
			if not _owned(world, x - 1, y, kingdom_id):
				segments.append_array([Vector2(px, py), Vector2(px, py + ts)])
			if not _owned(world, x + 1, y, kingdom_id):
				segments.append_array([Vector2(px + ts, py), Vector2(px + ts, py + ts)])
	var visible_flag: bool = _kingdoms.get(kingdom_id, {}).get("visible", true)
	_kingdoms[kingdom_id] = {"color": color, "segments": segments, "fill": fill, "visible": visible_flag}
	queue_redraw()


## Für Phase 7: fremde Reiche erst nach Entdeckung zeigen
func set_kingdom_visible(kingdom_id: int, value: bool) -> void:
	if _kingdoms.has(kingdom_id):
		_kingdoms[kingdom_id]["visible"] = value
		queue_redraw()


func clear_all() -> void:
	_kingdoms.clear()
	queue_redraw()


func _owned(world: WorldData, x: int, y: int, kingdom_id: int) -> bool:
	if x < 0 or y < 0 or x >= world.width or y >= world.height:
		return false
	return world.territory[y * world.width + x] == kingdom_id


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
		if not k["visible"]:
			continue
		var color: Color = k["color"]
		var fill_color := Color(color, fill_alpha)
		for r in k["fill"]:
			draw_rect(r, fill_color, true)
		var segments: PackedVector2Array = k["segments"]
		if segments.size() >= 2:
			draw_multiline(segments, Color(color, line_alpha), -1.0 if _hairline else line_width)
