## Minimap
##
## Zeigt die ganze Karte (Übersichtsbild) und den Sichtbereich der Kamera.
## Klicken/Ziehen mit der linken Maustaste bewegt die Kamera dorthin.
## Ab späteren Phasen kommen hier Markierungen (Dörfer, Armeen, Meldungen) dazu.
class_name Minimap
extends Control

var texture: Texture2D
var world_size := Vector2.ONE
var camera: RTSCamera
var border_color := Color(0.78, 0.64, 0.36, 0.9)
var view_color := Color(1, 1, 1, 0.95)

var _dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Verkleinertes Kartenbild mit Mipmaps glätten
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func setup(p_texture: Texture2D, p_world_size: Vector2, p_camera: RTSCamera) -> void:
	texture = p_texture
	world_size = p_world_size
	camera = p_camera
	queue_redraw()


func _process(_delta: float) -> void:
	if is_visible_in_tree() and texture != null:
		queue_redraw()  # Kamerarahmen folgt der Kamera


func _draw() -> void:
	var r := _map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6), true)
	if texture == null:
		return
	draw_texture_rect(texture, r, false)
	if camera != null:
		var s := r.size / world_size
		var view := camera.get_view_rect()
		var vr := Rect2(r.position + view.position * s, view.size * s).intersection(r)
		draw_rect(vr, view_color, false, 1.5)
	draw_rect(r, border_color, false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_jump_to(mb.position)
		accept_event()  # auch das Mausrad hier nicht an die Kamera weitergeben
	elif event is InputEventMouseMotion and _dragging:
		_jump_to((event as InputEventMouseMotion).position)
		accept_event()


func _jump_to(local_pos: Vector2) -> void:
	if camera == null:
		return
	var r := _map_rect()
	var rel := ((local_pos - r.position) / r.size).clamp(Vector2.ZERO, Vector2.ONE)
	camera.focus_on(rel * world_size)


## Kartenfläche innerhalb des Controls, Seitenverhältnis bleibt erhalten
func _map_rect() -> Rect2:
	var aspect := world_size.x / world_size.y
	var w := size.x
	var h := w / aspect
	if h > size.y:
		h = size.y
		w = h * aspect
	return Rect2((size - Vector2(w, h)) * 0.5, Vector2(w, h))
