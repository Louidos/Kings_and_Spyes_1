## Minimap
##
## Zeigt die ganze Karte (Übersichtsbild) und den Sichtbereich der Kamera.
## Klicken/Ziehen mit der linken Maustaste bewegt die Kamera dorthin.
## Markierungen: Gebäude aller Reiche (Reichsfarbe, Baustellen blasser) und
## ein Rahmen um das Gebiet jedes Reichs. Ab späteren Phasen kommen Armeen
## und Meldungen dazu.
class_name Minimap
extends Control

var texture: Texture2D
var world_size := Vector2.ONE
var camera: RTSCamera
var border_color := Color(0.78, 0.64, 0.36, 0.9)
var view_color := Color(1, 1, 1, 0.95)
## Kleinste Kantenlänge einer Gebäudemarkierung in Pixeln
var marker_min_size := 3.0
## So oft pro Sekunde werden die Gebietsrahmen neu berechnet
var bbox_refresh_interval := 0.5

var _dragging := false
## Spielwelt und Reiche (nach setup_game)
var _world: WorldData
var _kingdoms: Array = []
## Gebietsrahmen je Reich: [{color: Color, rect: Rect2i}]
var _territory_boxes: Array = []
var _bbox_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Verkleinertes Kartenbild mit Mipmaps glätten
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func setup(p_texture: Texture2D, p_world_size: Vector2, p_camera: RTSCamera) -> void:
	texture = p_texture
	world_size = p_world_size
	camera = p_camera
	queue_redraw()


## Aktiviert die Markierungen für Gebäude und Gebiete der Reiche.
func setup_game(game: Node) -> void:
	_world = game.world
	_kingdoms = game.kingdoms  # gleiche Liste – neue Reiche erscheinen automatisch
	_update_territory_boxes()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or texture == null:
		return
	if _world != null:
		_bbox_timer += delta
		if _bbox_timer >= bbox_refresh_interval:
			_bbox_timer = 0.0
			_update_territory_boxes()
	queue_redraw()  # Kamerarahmen folgt der Kamera


func _draw() -> void:
	var r := _map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6), true)
	if texture == null:
		return
	draw_texture_rect(texture, r, false)
	if _world != null:
		_draw_markers(r)
	if camera != null:
		var s := r.size / world_size
		var view := camera.get_view_rect()
		var vr := Rect2(r.position + view.position * s, view.size * s).intersection(r)
		draw_rect(vr, view_color, false, 1.5)
	draw_rect(r, border_color, false, 2.0)


## Gebietsrahmen und Gebäude aller Reiche
func _draw_markers(r: Rect2) -> void:
	var tile_px := r.size / Vector2(_world.width, _world.height)
	for box in _territory_boxes:
		var entry: Dictionary = box
		var rect: Rect2i = entry["rect"]
		var area := Rect2(r.position + Vector2(rect.position) * tile_px, Vector2(rect.size) * tile_px)
		draw_rect(area, entry["color"], false, 1.0)
	var min_size := Vector2(marker_min_size, marker_min_size)
	var outline := Color(0, 0, 0, 0.7)
	for k in _kingdoms:
		var kingdom: Kingdom = k
		for b in kingdom.buildings:
			var building: Building = b
			if not is_instance_valid(building):
				continue
			var marker_size := (Vector2(building.size) * tile_px).max(min_size)
			var center := r.position + (Vector2(building.cell) + Vector2(building.size) * 0.5) * tile_px
			var rect := Rect2(center - marker_size * 0.5, marker_size)
			var fill := kingdom.color if building.constructed else Color(kingdom.color, 0.55)
			draw_rect(rect.grow(1.0), outline, true)
			draw_rect(rect, fill, true)


func _update_territory_boxes() -> void:
	_territory_boxes.clear()
	if _world == null:
		return
	for k in _kingdoms:
		var kingdom: Kingdom = k
		var rect := TerritorySystem.kingdom_bbox(kingdom, _world)
		if rect.has_area():
			_territory_boxes.append({"color": Color(kingdom.color, 0.75), "rect": rect})


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
