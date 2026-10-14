## TradeRouteView
##
## Zeichnet die Handelswege (Phase 9) als gestrichelte Linien in die Welt: eigene,
## verbündete und gesichtete fremde Wege (TradeRouteSystem.get_visible_routes). Farbe nach
## Zustand (offen, abgeschnitten, kein Weg, ruht), fremde Wege braun; an beiden Enden ein
## kleiner Kreis, bei abgeschnittenen Wegen ein rotes ✕ an der Gefahrenstelle.
## Liegt über Strassen und Gebietsgrenzen, unter der Bodenebene der Kampfeffekte. Neu
## gezeichnet nur bei Änderungen der Wege oder deutlicher Kamerabewegung (Echtzeit).
class_name TradeRouteView
extends Node2D

## Rand um den Sichtbereich (Weltpixel)
const VIEW_MARGIN := 64.0

var game: Node
var _dirty := true
var _last_zoom := 1.0
var _last_view := Rect2()
var _colors: Dictionary = {}
## Gesichtete fremde Wege kommen ohne Signal dazu: alle paar Sekunden neu zeichnen
var _timer := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	var trs: TradeRouteSystem = game.trade_route_system
	trs.routes_changed.connect(func(_k: Kingdom) -> void: _dirty = true)
	trs.route_state_changed.connect(func(_id: String, _s: String, _r: String) -> void: _dirty = true)
	var cols: Dictionary = DataDB.trade("display.colors", {})
	for key in cols:
		_colors[key] = Color.from_string(str(cols[key]), Color.WHITE)


func _process(delta: float) -> void:
	if game == null:
		return
	_timer += delta
	if _timer >= 2.0:
		_timer = 0.0
		_dirty = true
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return
	var zoom := cam.zoom.x
	var view: Rect2 = (game.camera as RTSCamera).get_view_rect()
	if _dirty or absf(zoom - _last_zoom) > _last_zoom * 0.1 or not _last_view.encloses(view):
		_dirty = false
		_last_zoom = zoom
		# Etwas grösser merken, damit kleine Kamerabewegungen nicht neu zeichnen
		_last_view = view.grow(view.size.x * 0.25)
		queue_redraw()


func _draw() -> void:
	if game == null or game.player == null:
		return
	var trs: TradeRouteSystem = game.trade_route_system
	var view := _last_view.grow(VIEW_MARGIN)
	var zoom := maxf(_last_zoom, 0.05)
	var width := float(DataDB.trade("display.width", 3)) / zoom
	var dash := float(DataDB.trade("display.dash", 18)) / zoom
	var player: Kingdom = game.player
	for r in trs.get_visible_routes(player):
		var route: Dictionary = r
		var pts: Array = route["points"]
		if pts.size() < 2:
			continue
		var own := int(route["owner_id"]) == player.id
		var state := str(route["state"])
		var color: Color = _colors.get(state, Color.WHITE) if own else _colors.get("foreign", Color(0.75, 0.5, 0.25))
		if not own and state == "cut":
			color = _colors.get("cut", color)
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			if not view.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(1.0)):
				continue
			draw_dashed_line(a, b, Color(0, 0, 0, 0.45), width + 2.0 / zoom, dash)
			draw_dashed_line(a, b, color, width, dash)
		for end in [pts[0], pts[pts.size() - 1]]:
			var e: Vector2 = end
			if view.has_point(e):
				draw_circle(e, 5.0 / zoom + width, Color(0, 0, 0, 0.5))
				draw_circle(e, 4.0 / zoom + width * 0.6, color)
		if state == "cut":
			var p: Vector2 = route["danger_pos"]
			if p == Vector2.ZERO:
				p = pts[pts.size() >> 1]
			if view.has_point(p):
				var s := 12.0 / zoom
				var red: Color = _colors.get("cut", Color(0.9, 0.3, 0.25))
				draw_line(p - Vector2(s, s), p + Vector2(s, s), Color(0, 0, 0, 0.6), width * 2.0 + 2.0 / zoom)
				draw_line(p - Vector2(s, -s), p + Vector2(s, -s), Color(0, 0, 0, 0.6), width * 2.0 + 2.0 / zoom)
				draw_line(p - Vector2(s, s), p + Vector2(s, s), red, width * 2.0)
				draw_line(p - Vector2(s, -s), p + Vector2(s, -s), red, width * 2.0)
