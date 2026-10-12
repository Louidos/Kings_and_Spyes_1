## UnitOverlay
##
## Zeichnet für alle Einheiten gemeinsam, was sich oft ändert: Lebensbalken
## (bei Verletzten und Ausgewählten) und Auswahlringe. Ein einziger Knoten
## statt eines Balkens in jeder Einheit spart Zeichenaufrufe; die Einheiten
## müssen beim Heilen nicht neu gezeichnet werden.
## Beim Herauszoomen (unter camera.terrain_detail_min_zoom) werden die
## Einheiten ausgeblendet und hier als farbige Punkte gezeichnet.
## Reine Darstellung: liest nur, verändert keinen Spielzustand.
class_name UnitOverlay
extends Node2D

## Ab dieser Vergrösserung stehen Buchstaben auf den Platzhaltern
const LETTER_MIN_ZOOM := 0.5

var game: Node
var _detail_min_zoom := 0.2
var _units_visible := true


func setup(p_game: Node) -> void:
	game = p_game
	z_index = 30
	_detail_min_zoom = float(DataDB.cfg("camera.terrain_detail_min_zoom", 0.2))


func _process(_delta: float) -> void:
	if game == null or game.world == null:
		return
	var zoom: float = game.camera.zoom.x
	# Einheiten-Knoten nur in der Nahansicht zeigen
	var show_units := zoom >= _detail_min_zoom
	if show_units != _units_visible:
		_units_visible = show_units
		game.unit_layer.visible = show_units
	var letters := zoom >= LETTER_MIN_ZOOM
	if letters != Unit.show_letters:
		Unit.show_letters = letters
		for u in game.unit_system.units:
			u.queue_redraw()
	queue_redraw()


func _draw() -> void:
	if game == null or game.world == null:
		return
	var view: Rect2 = game.camera.get_view_rect().grow(64.0)
	var zoom: float = maxf(game.camera.zoom.x, 0.01)
	if not _units_visible:
		# Fernansicht: jede Einheit als Punkt in ihrer Farbe
		var r := 3.0 / zoom
		for u in game.unit_system.units:
			if u.inside != null or not view.has_point(u.position):
				continue
			var c: Color = u.type_def.get("color", u.kingdom.color)
			draw_rect(Rect2(u.position - Vector2(r, r), Vector2(r, r) * 2.0), c, true)
		return
	var ring_w := maxf(2.0, 2.0 / zoom)
	for u in game.unit_system.units:
		if u.inside != null or (not u.selected and u.hp >= u.max_hp):
			continue
		if not view.has_point(u.position):
			continue
		var rad: float = u.get_radius()
		if u.selected:
			draw_arc(u.position + Vector2(0, rad * 0.35), rad + 5.0, 0.0, TAU, 28, Color(1, 1, 0.6, 0.95), ring_w, true)
		# Lebensbalken unter der Einheit
		var w := maxf(rad * 2.2, 26.0)
		var bar := Rect2(u.position + Vector2(-w * 0.5, rad + 4.0), Vector2(w, 5.0))
		var ratio := clampf(u.hp / u.max_hp, 0.0, 1.0)
		var color := Color(0.3, 0.9, 0.3) if ratio > 0.5 else (Color(0.95, 0.8, 0.2) if ratio > 0.25 else Color(0.95, 0.25, 0.2))
		draw_rect(bar, Color(0, 0, 0, 0.6), true)
		var inner := bar.grow(-1.0)
		inner.size.x *= ratio
		draw_rect(inner, color, true)
