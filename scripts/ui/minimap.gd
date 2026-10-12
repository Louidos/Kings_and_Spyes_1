## Minimap
##
## Zeigt die ganze Karte (Übersichtsbild) und den Sichtbereich der Kamera.
## Klicken/Ziehen mit der linken Maustaste bewegt die Kamera dorthin.
## Markierungen: Gebäude aller Reiche (Reichsfarbe, Baustellen blasser), ein
## Rahmen um das Gebiet jedes Reichs, Einheiten als Punkte, Monsterlager als
## orange Rauten (immer sichtbar – der Spieler soll wissen, wo Lager sind) und
## rot pulsierende Kreise, wo das eigene Reich angegriffen wird.
##
## Leistung: Karte, Gebäude und Einheitenpunkte werden höchstens alle 0.25 s
## gezeichnet; die Punkte stehen dann schon fertig umgerechnet in Listen
## (ein Zeichenbefehl je Farbe statt einer pro Einheit). Nur der Kamerarahmen
## und die Angriffsmeldungen liegen auf einer kleinen Ebene darüber, die jedes
## Bild neu gezeichnet wird, wenn sich dort etwas bewegt.
class_name Minimap
extends Control

## So lange bleibt eine Angriffsmeldung stehen (Sekunden, Echtzeit)
const PING_SECONDS := 3.0
const MAX_PINGS := 8
## Näher als so viele Kacheln: bestehende Meldung auffrischen statt neue
const PING_MERGE_TILES := 12.0
const PING_COLOR := Color(1.0, 0.18, 0.12)
const OUTLINE_COLOR := Color(0, 0, 0, 0.85)
const LAIR_COLOR := Color(1.0, 0.55, 0.12)

var texture: Texture2D
var world_size := Vector2.ONE
var camera: RTSCamera
var border_color := Color(0.78, 0.64, 0.36, 0.9)
var view_color := Color(1, 1, 1, 0.95)
## Kleinste Kantenlänge einer Gebäudemarkierung in Pixeln
var marker_min_size := 3.0
## So oft pro Sekunde werden die Gebietsrahmen neu berechnet
var bbox_refresh_interval := 0.5
## Karte, Gebäude und Einheiten höchstens so oft neu zeichnen (Sekunden)
var redraw_interval := 0.25
## Halbe Grösse eines Lager-Symbols in Pixeln
var lair_marker_radius := 3.0
## Messwerte der letzten Aktualisierung in Mikrosekunden (Debug, Tests)
var last_cache_usec := 0
var last_draw_usec := 0

var _dragging := false
## Spielwelt und Reiche (nach setup_game)
var _game: Node
var _world: WorldData
var _kingdoms: Array = []
## Gebietsrahmen je Reich: [{color: Color, rect: Rect2i}]
var _territory_boxes: Array = []
var _bbox_timer := 0.0
var _redraw_timer := 0.0
## Fertig umgerechnete Einheitenpunkte (Pixel im Control):
## je zwei Punkte eine kurze, dicke Linie = ein Quadrat.
## [{color: Color, points: PackedVector2Array}] – eigene zuletzt (liegen oben)
var _dot_groups: Array = []
## Monster: schwarzer Rand (4×4) und Füllung (2×2)
var _monster_outline := PackedVector2Array()
var _monster_fill := PackedVector2Array()
var _monster_color := Color(0.88, 0.48, 0.13)
## Monsterlager als Mittelpunkte in Pixeln
var _lair_points := PackedVector2Array()
## Angriffsmeldungen: [{pos: Vector2 (Welt), age: float}]
var _pings: Array = []
## Obere Ebene für Kamerarahmen und Meldungen
var _overlay: Control
var _last_view := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Verkleinertes Kartenbild mit Mipmaps glätten
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	resized.connect(_refresh)


func setup(p_texture: Texture2D, p_world_size: Vector2, p_camera: RTSCamera) -> void:
	texture = p_texture
	world_size = p_world_size
	camera = p_camera
	_refresh()


## Aktiviert die Markierungen für Gebäude, Gebiete, Einheiten und Angriffe.
func setup_game(game: Node) -> void:
	_game = game
	_world = game.world
	_kingdoms = game.kingdoms  # gleiche Liste – neue Reiche erscheinen automatisch
	game.combat_system.kingdom_attacked.connect(_on_kingdom_attacked)
	_update_territory_boxes()
	_refresh()


## Punkte neu berechnen und alles neu zeichnen
func _refresh() -> void:
	_redraw_timer = 0.0
	_rebuild_cache()
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or texture == null:
		return
	if _world != null:
		_bbox_timer += delta
		if _bbox_timer >= bbox_refresh_interval:
			_bbox_timer = 0.0
			_update_territory_boxes()
	_redraw_timer += delta
	if _redraw_timer >= redraw_interval:
		_redraw_timer = 0.0
		_rebuild_cache()
		queue_redraw()
	# Obere Ebene nur, wenn sich der Kamerarahmen bewegt oder Meldungen pulsieren
	if not _pings.is_empty():
		for p in _pings:
			p["age"] = float(p["age"]) + delta
		_pings = _pings.filter(func(p: Dictionary) -> bool: return float(p["age"]) < PING_SECONDS)
		_overlay.queue_redraw()
	elif camera != null:
		var view := camera.get_view_rect()
		if view != _last_view:
			_last_view = view
			_overlay.queue_redraw()


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	var r := _map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6), true)
	if texture == null:
		return
	draw_texture_rect(texture, r, false)
	if _world != null:
		_draw_markers(r)
		_draw_units()
	last_draw_usec = Time.get_ticks_usec() - t0


## Kamerarahmen, Angriffsmeldungen und Rand (obere Ebene)
func _draw_overlay() -> void:
	if texture == null:
		return
	var r := _map_rect()
	var s := r.size / world_size
	for p in _pings:
		var age: float = p["age"]
		var center: Vector2 = r.position + (p["pos"] as Vector2) * s
		# Pulsieren und in der letzten Sekunde ausblenden
		var fade := clampf(PING_SECONDS - age, 0.0, 1.0)
		var phase := fmod(age, 0.8) / 0.8
		var pulse_r := 4.0 + 10.0 * phase
		_overlay.draw_arc(center, pulse_r, 0.0, TAU, 24, Color(PING_COLOR, (1.0 - phase) * fade), 2.0, true)
		_overlay.draw_arc(center, 4.5, 0.0, TAU, 16, Color(0, 0, 0, 0.8 * fade), 3.5, true)
		_overlay.draw_arc(center, 4.5, 0.0, TAU, 16, Color(PING_COLOR, fade), 2.0, true)
	if camera != null:
		var view := camera.get_view_rect()
		_last_view = view
		var vr := Rect2(r.position + view.position * s, view.size * s).intersection(r)
		_overlay.draw_rect(vr, view_color, false, 1.5)
	_overlay.draw_rect(r, border_color, false, 2.0)


## Gebietsrahmen und Gebäude aller Reiche (Lager als Raute)
func _draw_markers(r: Rect2) -> void:
	var tile_px := r.size / Vector2(_world.width, _world.height)
	for box in _territory_boxes:
		var entry: Dictionary = box
		var rect: Rect2i = entry["rect"]
		var area := Rect2(r.position + Vector2(rect.position) * tile_px, Vector2(rect.size) * tile_px)
		draw_rect(area, entry["color"], false, 1.0)
	var min_size := Vector2(marker_min_size, marker_min_size)
	var outline := Color(0, 0, 0, 0.7)
	var lairs: Dictionary = _game.monster_system.lairs if _game != null else {}
	for k in _kingdoms:
		var kingdom: Kingdom = k
		for b in kingdom.buildings:
			if not is_instance_valid(b):
				continue
			var building: Building = b
			if lairs.has(building):
				continue  # eigenes Symbol, siehe _draw_units
			var marker_size := (Vector2(building.size) * tile_px).max(min_size)
			var center := r.position + (Vector2(building.cell) + Vector2(building.size) * 0.5) * tile_px
			var rect := Rect2(center - marker_size * 0.5, marker_size)
			var fill := kingdom.color if building.constructed else Color(kingdom.color, 0.55)
			draw_rect(rect.grow(1.0), outline, true)
			draw_rect(rect, fill, true)


## Lager und Einheitenpunkte aus den vorbereiteten Listen. Reihenfolge:
## Lager zuunterst (Monster stehen meist darauf und sollen sichtbar bleiben),
## dann Monster, fremde Reiche, eigene Einheiten zuoberst.
func _draw_units() -> void:
	var lr := lair_marker_radius
	var lo := lr + 1.5
	for c in _lair_points:
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -lo), c + Vector2(lo, 0),
				c + Vector2(0, lo), c + Vector2(-lo, 0)]), OUTLINE_COLOR)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -lr), c + Vector2(lr, 0),
				c + Vector2(0, lr), c + Vector2(-lr, 0)]), LAIR_COLOR)
	if not _monster_outline.is_empty():
		draw_multiline(_monster_outline, OUTLINE_COLOR, 4.0)
		draw_multiline(_monster_fill, _monster_color, 2.0)
	for g in _dot_groups:
		var group: Dictionary = g
		draw_multiline(group["points"], group["color"], 2.0)


## Einheiten in Pixel umrechnen (ein Durchlauf über alle Einheiten).
## Eigene und verbündete Einheiten immer, fremde nur, wenn der Spieler sie sieht.
func _rebuild_cache() -> void:
	var t0 := Time.get_ticks_usec()
	_dot_groups.clear()
	_monster_outline = PackedVector2Array()
	_monster_fill = PackedVector2Array()
	_lair_points = PackedVector2Array()
	if _game == null or _world == null or texture == null:
		return
	var r := _map_rect()
	var origin := r.position
	var s := r.size / world_size
	var player: Kingdom = _game.player
	var own_group: Dictionary = {}
	for k in _kingdoms:
		var kingdom: Kingdom = k
		if kingdom.units.is_empty():
			continue
		var visible_all: bool = _game.are_allied(player, kingdom)
		if kingdom.controller == "wild":
			_monster_color = kingdom.color
			for u in kingdom.units:
				if u.inside != null or (not visible_all and u.stealthed):
					continue
				# Auf ganze Pixel runden, sonst verschwimmen die kleinen Quadrate
				var p: Vector2 = (origin + u.position * s).floor()
				_monster_outline.append(Vector2(p.x - 2.0, p.y))
				_monster_outline.append(Vector2(p.x + 2.0, p.y))
				_monster_fill.append(Vector2(p.x - 1.0, p.y))
				_monster_fill.append(Vector2(p.x + 1.0, p.y))
			continue
		var points := PackedVector2Array()
		for u in kingdom.units:
			if u.inside != null or (not visible_all and u.stealthed):
				continue
			var p: Vector2 = (origin + u.position * s).floor()
			points.append(Vector2(p.x - 1.0, p.y))
			points.append(Vector2(p.x + 1.0, p.y))
		if points.is_empty():
			continue
		var group := {"color": kingdom.color, "points": points}
		if kingdom == player:
			own_group = group
		else:
			_dot_groups.append(group)
	if not own_group.is_empty():
		_dot_groups.append(own_group)
	for lair in _game.monster_system.lairs:
		if is_instance_valid(lair):
			_lair_points.append((origin + (lair as Building).get_center() * s).floor() + Vector2(0.5, 0.5))
	last_cache_usec = Time.get_ticks_usec() - t0


## Angriff auf das eigene Reich: pulsierender Kreis an der Stelle
func _on_kingdom_attacked(victim: Variant, _attacker: Variant, pos: Vector2) -> void:
	if _game == null or victim != _game.player:
		return
	var merge := PING_MERGE_TILES * float(_world.tile_size)
	for p in _pings:
		if (p["pos"] as Vector2).distance_to(pos) < merge:
			p["pos"] = pos
			p["age"] = 0.0
			return
	if _pings.size() >= MAX_PINGS:
		_pings.remove_at(0)
	_pings.append({"pos": pos, "age": 0.0})
	if _overlay != null:
		_overlay.queue_redraw()


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
