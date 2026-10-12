## SelectionBox
##
## Zeichnet den Auswahlrahmen beim Ziehen mit der linken Maustaste – in
## Bildschirmkoordinaten (eigene CanvasLayer), damit die Linie bei jedem Zoom
## gleich dünn bleibt. Reine Darstellung: der SelectionController setzt das
## Rechteck und wertet es aus.
class_name SelectionBox
extends Control

const FILL_COLOR := Color(1.0, 0.95, 0.55, 0.12)
const LINE_COLOR := Color(1.0, 0.95, 0.6, 0.95)
const LINE_WIDTH := 1.5
## Dunkler Schatten unter der Linie: bleibt auch auf hellem Sand/Schnee sichtbar
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)

var _rect := Rect2()


func _ready() -> void:
	# Darf keine Klicks abfangen – die Welt darunter bleibt bedienbar
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## Rahmen zwischen zwei Bildschirmpunkten anzeigen
func show_box(a: Vector2, b: Vector2) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b)
	if visible and r == _rect:
		return
	_rect = r
	visible = true
	queue_redraw()


func hide_box() -> void:
	if visible:
		visible = false
		queue_redraw()


func _draw() -> void:
	if _rect.size.x < 1.0 and _rect.size.y < 1.0:
		return
	draw_rect(_rect, FILL_COLOR, true)
	# Auf halbe Pixel legen, damit die dünne Linie scharf statt verwaschen ist;
	# 1.5 px, weil das Fenster meist kleiner als die 1920er-Basisgrösse skaliert
	var line := Rect2(_rect.position.floor() + Vector2(0.5, 0.5), _rect.size.floor())
	draw_rect(line.grow(1.25), SHADOW_COLOR, false, 1.0)
	draw_rect(line, LINE_COLOR, false, LINE_WIDTH)
