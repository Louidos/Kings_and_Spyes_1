## RTSCamera
##
## Strategie-Kamera von oben:
## - Verschieben: WASD / Pfeiltasten, Bildschirmrand, mittlere Maustaste ziehen
## - Zoomen: Mausrad (zum Mauszeiger hin), Q/E, Touchpad-Gesten
## - Bleibt immer innerhalb der Karte; ganz herausgezoomt sieht man das ganze Land
## Läuft in Echtzeit, also auch bei Pause und unabhängig vom Spieltempo.
class_name RTSCamera
extends Camera2D

## Sichtbarer Bereich der Welt in Pixeln (wird von der Spielszene gesetzt)
var map_rect := Rect2(0, 0, 4096, 4096)
var zoom_min: float = 0.05
var zoom_max: float = 2.0
var zoom_step: float = 1.15
var zoom_smoothing: float = 14.0
var pan_speed: float = 1100.0
var edge_margin: int = 8
## Kann von aussen gesperrt werden (z. B. während Ladebildschirm oder Menüs)
var input_enabled: bool = true

var _target_zoom: float = 1.0
## Bildschirmpunkt, um den gerade gezoomt wird
var _zoom_anchor := Vector2.ZERO
var _dragging: bool = false


func _ready() -> void:
	zoom_max = float(DataDB.cfg("camera.zoom_max", zoom_max))
	zoom_step = float(DataDB.cfg("camera.zoom_step", zoom_step))
	zoom_smoothing = float(DataDB.cfg("camera.zoom_smoothing", zoom_smoothing))
	pan_speed = float(DataDB.cfg("camera.pan_speed", pan_speed))
	edge_margin = int(DataDB.cfg("camera.edge_scroll_margin", edge_margin))
	_target_zoom = zoom.x
	# Eigene Glättung; die eingebaute würde das Zoomen zum Mauszeiger stören
	position_smoothing_enabled = false
	get_viewport().size_changed.connect(_on_viewport_resized)


## Setzt die Kartengrenzen und berechnet den kleinsten Zoom (ganze Karte sichtbar).
func set_map_rect(rect: Rect2) -> void:
	map_rect = rect
	_update_zoom_min()
	_clamp_position()


## Springt zu einer Weltposition, optional mit neuem Zoom.
func focus_on(world_pos: Vector2, new_zoom: float = -1.0) -> void:
	if new_zoom > 0.0:
		_target_zoom = clampf(new_zoom, zoom_min, zoom_max)
		zoom = Vector2(_target_zoom, _target_zoom)
	position = world_pos
	_clamp_position()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_by(pow(zoom_step, _wheel_steps(mb)), mb.position)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_by(1.0 / pow(zoom_step, _wheel_steps(mb)), mb.position)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_MIDDLE:
				_dragging = mb.pressed
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		position -= (event as InputEventMouseMotion).relative / zoom.x
		_clamp_position()
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		_zoom_by(g.factor, g.position)
	elif event is InputEventPanGesture:
		position += (event as InputEventPanGesture).delta * 12.0 / zoom.x
		_clamp_position()


func _process(delta: float) -> void:
	if not input_enabled:
		_dragging = false
		return
	var dir := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if Settings.edge_scroll and not _dragging:
		dir += _edge_scroll_direction()
	if dir != Vector2.ZERO:
		var speed := pan_speed * Settings.camera_speed
		position += dir.limit_length(1.0) * speed * delta / zoom.x

	# Zoom per Tastatur (gedrückt halten), Zentrum = Bildmitte
	var key_zoom := Input.get_axis("camera_zoom_out", "camera_zoom_in")
	if key_zoom != 0.0:
		_target_zoom = clampf(_target_zoom * pow(zoom_step, key_zoom * delta * 10.0), zoom_min, zoom_max)
		_zoom_anchor = get_viewport_rect().size * 0.5

	# Weiches Zoomen zum Ziel, der Punkt unter dem Anker bleibt fest
	if not is_equal_approx(zoom.x, _target_zoom):
		var z := lerpf(zoom.x, _target_zoom, 1.0 - exp(-zoom_smoothing * delta))
		if absf(z - _target_zoom) < _target_zoom * 0.001:
			z = _target_zoom
		_apply_zoom(z, _zoom_anchor)

	_clamp_position()


## Mausrad: 1 Raste = 1 Zoomstufe; Präzisions-Touchpads melden Bruchteile.
func _wheel_steps(mb: InputEventMouseButton) -> float:
	return mb.factor if mb.factor > 0.0 else 1.0


## Zoom-Faktor relativ ändern, um einen Bildschirmpunkt herum.
func _zoom_by(factor: float, screen_point: Vector2) -> void:
	_target_zoom = clampf(_target_zoom * factor, zoom_min, zoom_max)
	_zoom_anchor = screen_point


## Setzt den Zoom so, dass der Weltpunkt unter `screen_point` an seiner Stelle bleibt.
func _apply_zoom(z: float, screen_point: Vector2) -> void:
	var offset := screen_point - get_viewport_rect().size * 0.5
	var world_point := position + offset / zoom.x
	zoom = Vector2(z, z)
	position = world_point - offset / z


func _edge_scroll_direction() -> Vector2:
	# Nur scrollen, wenn das Fenster den Fokus hat und die Maus darin ist
	if not get_window().has_focus():
		return Vector2.ZERO
	var m := get_viewport().get_mouse_position()
	var size := get_viewport_rect().size
	if not Rect2(Vector2.ZERO, size).has_point(m):
		return Vector2.ZERO
	var d := Vector2.ZERO
	if m.x <= edge_margin:
		d.x -= 1.0
	elif m.x >= size.x - edge_margin:
		d.x += 1.0
	if m.y <= edge_margin:
		d.y -= 1.0
	elif m.y >= size.y - edge_margin:
		d.y += 1.0
	return d


## Hält den Sichtbereich innerhalb der Karte. Ist die Sicht grösser als die
## Karte, wird die Karte zentriert.
func _clamp_position() -> void:
	var half := get_viewport_rect().size * 0.5 / zoom.x
	var lo := map_rect.position + half
	var hi := map_rect.end - half
	position.x = map_rect.get_center().x if lo.x > hi.x else clampf(position.x, lo.x, hi.x)
	position.y = map_rect.get_center().y if lo.y > hi.y else clampf(position.y, lo.y, hi.y)


func _update_zoom_min() -> void:
	var vp := get_viewport_rect().size
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return
	# Ganze Karte passt auf den Bildschirm, mit etwas Rand für die Bedienleisten
	zoom_min = minf(vp.x / map_rect.size.x, vp.y / map_rect.size.y) * 0.88
	_target_zoom = clampf(_target_zoom, zoom_min, zoom_max)


func _on_viewport_resized() -> void:
	_update_zoom_min()
	_clamp_position()


## Aktuell sichtbarer Weltbereich (für Minikarte und Culling)
func get_view_rect() -> Rect2:
	var size := get_viewport_rect().size / zoom
	return Rect2(get_screen_center_position() - size * 0.5, size)
