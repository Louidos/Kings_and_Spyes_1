## CellCursor
##
## Zeichnet einen Rahmen um die Kachel unter dem Mauszeiger.
## Später auch als Vorschau beim Platzieren von Gebäuden nutzbar.
class_name CellCursor
extends Node2D

var tile_size: int = 64:
	set(value):
		tile_size = value
		queue_redraw()
var color := Color(1, 1, 1, 0.85)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(tile_size, tile_size))
	draw_rect(r, Color(1, 1, 1, 0.08), true)
	draw_rect(r, color, false, 2.0)
