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
	if shape == "well" or shape == "field" or shape == "workshop":
		_draw_village_shape(ci, rect, color, shape, tint)
	elif shape == "circle":
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


## Platzhalter der Dorfgebäude (buildings.json shape): Brunnen (Steinring mit Wasser und Dach),
## Feld (Acker mit Furchen und Ähren, flach) und Werkstatt (Haus mit Esse und Rauch)
static func _draw_village_shape(ci: CanvasItem, rect: Rect2, color: Color, shape: String, tint: Color) -> void:
	var inner := rect.grow(-3.0)
	var shadow := Color(0, 0, 0, 0.25 * tint.a)
	match shape:
		"well":
			var c := rect.get_center()
			var r := minf(rect.size.x, rect.size.y) * 0.36
			ci.draw_circle(c + Vector2(1.5, 2.5), r, shadow)
			ci.draw_circle(c, r, color * tint)
			ci.draw_arc(c, r, 0.0, TAU, 24, color.darkened(0.45) * tint, 2.0, true)
			ci.draw_circle(c, r * 0.62, Color(0.22, 0.45, 0.78) * tint)
			ci.draw_arc(c, r * 0.62, 0.0, TAU, 20, color.darkened(0.3) * tint, 1.5, true)
			# Pfosten und Dachbalken mit Kurbel
			var wood := Color(0.45, 0.3, 0.17) * tint
			ci.draw_line(c + Vector2(-r, 0), c + Vector2(-r, -r * 1.4), wood, 3.0)
			ci.draw_line(c + Vector2(r, 0), c + Vector2(r, -r * 1.4), wood, 3.0)
			ci.draw_line(c + Vector2(-r * 1.2, -r * 1.4), c + Vector2(r * 1.2, -r * 1.4), wood.darkened(0.2), 4.0)
			ci.draw_line(c + Vector2(0, -r * 1.4), c + Vector2(0, -r * 0.4), Color(0.75, 0.7, 0.55) * tint, 1.5)
		"field":
			ci.draw_rect(inner.grow(2.0), shadow, true)
			ci.draw_rect(inner, color.darkened(0.25) * tint, true)
			var rows := maxi(int(inner.size.y / 12.0), 3)
			var crop := Color(0.84, 0.74, 0.3) * tint
			for i in rows:
				var y := inner.position.y + (i + 0.5) * inner.size.y / rows
				ci.draw_line(Vector2(inner.position.x + 4, y), Vector2(inner.end.x - 4, y), color.darkened(0.5) * tint, 2.0)
				var x := inner.position.x + 8.0 + (i % 2) * 6.0
				while x < inner.end.x - 6.0:
					ci.draw_line(Vector2(x, y - 1.0), Vector2(x, y - 6.0), crop, 2.0)
					x += 12.0
			ci.draw_rect(inner, color.darkened(0.55) * tint, false, 2.0)
		"workshop":
			ci.draw_rect(inner.grow(2.0), shadow, true)
			ci.draw_rect(inner, color * tint, true)
			ci.draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.42)), color.lightened(0.18) * tint, true)
			ci.draw_rect(inner, color.darkened(0.45) * tint, false, 2.0)
			# Esse mit Glut und Rauch, Tür
			var chimney := Rect2(inner.end.x - inner.size.x * 0.28, inner.position.y - inner.size.y * 0.12,
					inner.size.x * 0.14, inner.size.y * 0.32)
			ci.draw_rect(chimney, Color(0.42, 0.38, 0.36) * tint, true)
			ci.draw_rect(chimney, Color(0.2, 0.18, 0.17) * tint, false, 1.5)
			var top := Vector2(chimney.get_center().x, chimney.position.y)
			ci.draw_circle(top + Vector2(2, -6), 4.0, Color(0.7, 0.7, 0.7, 0.5 * tint.a))
			ci.draw_circle(top + Vector2(6, -13), 5.0, Color(0.75, 0.75, 0.75, 0.35 * tint.a))
			var door := Rect2(inner.get_center().x - inner.size.x * 0.12, inner.end.y - inner.size.y * 0.36,
					inner.size.x * 0.24, inner.size.y * 0.36)
			ci.draw_rect(door, Color(0.3, 0.2, 0.12) * tint, true)
			ci.draw_rect(Rect2(door.position + Vector2(door.size.x * 0.3, door.size.y * 0.2), door.size * Vector2(0.4, 0.25)),
					Color(1.0, 0.55, 0.15, 0.9 * tint.a), true)


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
