## HeroPortrait
##
## Bild eines Helden für Fenster und die Heldenleiste: das Porträt aus
## heroes.json ("portrait", 128 × 128); fehlt die Datei, die gezeichnete Heldenfigur
## wie auf der Karte vor einem Hintergrund in der Heldenfarbe.
## Gefallene Helden erscheinen grau. Optional die Stufe als Abzeichen unten
## rechts und eine goldene Markierung oben rechts (offene Stufenwahl).
class_name HeroPortrait
extends Control

var _texture: Texture2D
var _figure: Texture2D
var _color := Color.GRAY
var _dead := false
var _level := 0
var _pending := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Heldentyp (Dictionary aus heroes.json, DataDB.get_hero_type)
func setup(hero_type: Dictionary) -> void:
	_texture = Assets.texture(str(hero_type.get("portrait", "")))
	_color = hero_type.get("color", Color.GRAY)
	_figure = null
	if _texture == null:
		var unit_def := DataDB.get_unit_type(str(hero_type.get("id", "")))
		_figure = Assets.figure(FigureArt.spec_for(unit_def, str(hero_type.get("faction", "good")), _color, {}))
	queue_redraw()


## Zustand setzen (zeichnet nur bei einer Änderung neu). level 0 = kein Abzeichen.
func set_state(dead: bool, level: int, pending: bool) -> void:
	if dead == _dead and level == _level and pending == _pending:
		return
	_dead = dead
	_level = level
	_pending = pending
	queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	var tint := Color(0.5, 0.5, 0.5) if _dead else Color.WHITE
	if _texture != null:
		draw_texture_rect(_texture, rect, false, tint)
	else:
		# Ohne Porträt: dunkler Grund in der Heldenfarbe, gezeichnete Heldenfigur
		var bg := _color.darkened(0.72)
		if _dead:
			bg = Color(0.16, 0.16, 0.17)
		draw_rect(rect, bg, true)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.45)), Color(_color, 0.12 if not _dead else 0.04), true)
		if _figure != null:
			# Brustbild: Figur vergrössert, Kopf im oberen Drittel
			var zoom := side * 1.9
			var fig := Rect2(rect.get_center() + Vector2(-zoom * 0.5, -zoom * 0.42), Vector2(zoom, zoom))
			draw_texture_rect_region(_figure, rect.intersection(fig), _source_region(rect, fig), tint)
	draw_rect(rect, Color(0, 0, 0, 0.85) if not _dead else Color(0.3, 0.3, 0.3), false, 1.0)
	if _dead:
		# Gefallen: dunkler Schleier und schräger Strich
		draw_rect(rect, Color(0.02, 0.02, 0.03, 0.35), true)
		draw_line(rect.position + Vector2(side * 0.2, side * 0.8), rect.position + Vector2(side * 0.8, side * 0.2),
				Color(0.8, 0.3, 0.26, 0.8), maxf(side * 0.05, 1.5), true)
	if _level > 0:
		var r := maxf(side * 0.17, 7.0)
		var c := rect.end - Vector2(r, r)
		draw_circle(c, r + 1.0, Color(0, 0, 0, 0.85))
		draw_circle(c, r, Color(0.2, 0.16, 0.08) if not _dead else Color(0.22, 0.22, 0.22))
		draw_arc(c, r, 0.0, TAU, 20, HeroUI.COLOR_XP if not _dead else HeroUI.COLOR_DEAD, 1.5, true)
		SpriteDraw.draw_label(self, str(_level), c, maxi(int(r * 1.15), 8))
	if _pending:
		# Offene Stufenwahl: goldener Stern-Punkt oben rechts
		var c := Vector2(rect.end.x - 6.0, rect.position.y + 6.0)
		draw_circle(c, 6.5, Color(0.1, 0.06, 0.0, 0.9))
		draw_circle(c, 5.0, HeroUI.COLOR_PENDING)
		SpriteDraw.draw_label(self, "+", c, 11)


## Ausschnitt des Figurenbilds, der im Rahmen rect sichtbar ist (fig = ganzes Bild auf dem Schirm)
func _source_region(rect: Rect2, fig: Rect2) -> Rect2:
	var vis := rect.intersection(fig)
	var ratio := _figure.get_size() / fig.size
	return Rect2((vis.position - fig.position) * ratio, vis.size * ratio)
