## SpriteDraw
##
## Zeichnet eine Spielfigur oder ein Gebäude: die echte Grafik, wenn vorhanden,
## sonst einen Platzhalter (farbige Form mit kurzer Beschriftung).
## Wird von Gebäuden, Bewohnern und der Bauvorschau gemeinsam genutzt.
class_name SpriteDraw
extends RefCounted


static func draw_entity(ci: CanvasItem, tex: Texture2D, rect: Rect2, color: Color, label: String,
		shape: String = "rect", tint: Color = Color.WHITE) -> void:
	if tex != null:
		ci.draw_texture_rect(tex, rect, false, tint)
		return
	var fill := color * tint
	var border := color.darkened(0.45) * tint
	if shape == "circle":
		var r := minf(rect.size.x, rect.size.y) * 0.5
		var c := rect.get_center()
		ci.draw_circle(c + Vector2(1.5, 2.5), r, Color(0, 0, 0, 0.3 * tint.a))  # Schatten
		ci.draw_circle(c, r, fill)
		ci.draw_arc(c, r, 0.0, TAU, 24, border, 2.0, true)
	else:
		var inner := rect.grow(-3.0)
		ci.draw_rect(inner.grow(2.0), Color(0, 0, 0, 0.25 * tint.a), true)  # Schatten/Rand
		ci.draw_rect(inner, fill, true)
		# Dach-Andeutung: hellere obere Hälfte
		ci.draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.42)), fill.lightened(0.18), true)
		ci.draw_rect(inner, border, false, 2.0)
	if not label.is_empty():
		draw_label(ci, label, rect.get_center(), clampi(int(rect.size.y * 0.28), 10, 26), tint.a)


## Zentrierter Text mit dunkler Kontur.
static func draw_label(ci: CanvasItem, text: String, center: Vector2, font_size: int, alpha: float = 1.0) -> void:
	var font := ThemeDB.fallback_font
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := center + Vector2(-size.x * 0.5, font.get_ascent(font_size) - size.y * 0.5)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.8 * alpha))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, alpha))


## Fortschrittsbalken (z. B. Baufortschritt)
static func draw_bar(ci: CanvasItem, rect: Rect2, ratio: float, color: Color) -> void:
	ci.draw_rect(rect, Color(0, 0, 0, 0.6), true)
	var inner := rect.grow(-1.0)
	inner.size.x *= clampf(ratio, 0.0, 1.0)
	ci.draw_rect(inner, color, true)
