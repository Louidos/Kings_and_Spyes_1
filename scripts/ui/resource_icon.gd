## ResourceIcon
##
## Kleines Ressourcen-Symbol für Leisten, Tooltips und Fenster.
## Nutzt die Grafik aus resources.json ("icon"). Fehlt die Datei, wird ein
## Kreis in der Ressourcenfarbe mit dem Anfangsbuchstaben gezeichnet –
## so lassen sich die Symbole jederzeit ohne Code-Änderung austauschen.
class_name ResourceIcon
extends Control

var res_id: String = ""
var icon_size: float = 24.0

var _texture: Texture2D
var _color := Color.WHITE
var _letter: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


## Legt die Ressource und die Kantenlänge (Pixel) fest.
func setup(p_res_id: String, p_size: float = 24.0) -> void:
	res_id = p_res_id
	icon_size = p_size
	var res := DataDB.get_resource(res_id)
	_texture = Assets.texture(str(res.get("icon", "")))
	_color = res.get("color", Color.WHITE)
	_letter = str(res.get("name", res_id)).substr(0, 1).to_upper()
	custom_minimum_size = Vector2(p_size, p_size)
	queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	if _texture != null:
		draw_texture_rect(_texture, rect, false)
		return
	# Platzhalter: Kreis in Ressourcenfarbe mit Anfangsbuchstabe
	var center := rect.get_center()
	var radius := side * 0.5 - 1.0
	draw_circle(center, radius, _color)
	draw_arc(center, radius, 0.0, TAU, 24, _color.darkened(0.55), 1.5, true)
	var font := get_theme_default_font()
	var font_size := maxi(int(side * 0.6), 8)
	var text_w := font.get_string_size(_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var text_color := Color(0.08, 0.06, 0.05) if _color.get_luminance() > 0.5 else Color.WHITE
	draw_string(font, Vector2(center.x - text_w * 0.5, baseline), _letter,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
