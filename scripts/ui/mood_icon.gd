## MoodIcon
##
## Gezeichnetes Gesicht für die Zufriedenheit (Phase 8): Kreis in der Farbe der Stufe,
## Augen und ein Mund, der je nach Wert lacht oder hängt. Liegt eine Grafik
## res://assets/ui/icons/mood_<stufe>.png vor (angry, unhappy, content, happy), wird
## sie gezeichnet. Wert < 0 = keine Bewohner (grau, gerader Mund).
class_name MoodIcon
extends Control

const TIER_FILES := ["mood_angry", "mood_unhappy", "mood_content", "mood_happy"]

var value := -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func set_value(v: float) -> void:
	if absf(v - value) >= 0.5 or (v < 0.0) != (value < 0.0):
		value = v
		queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.5 - 1.0
	var tier := SatisfactionSystem.tier_for(value) if value >= 0.0 else {"color": Color(0.6, 0.58, 0.55), "index": 2}
	var tex: Texture2D = null
	if value >= 0.0:
		tex = Assets.texture("res://assets/ui/icons/%s.png" % TIER_FILES[clampi(int(tier["index"]), 0, 3)])
	if tex != null:
		draw_texture_rect(tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
		return
	var col: Color = tier["color"]
	draw_circle(c, r + 1.0, Color(0.05, 0.04, 0.03, 0.9))
	draw_circle(c, r, col)
	var dark := Color(0.1, 0.07, 0.05)
	var eye := maxf(r * 0.13, 1.2)
	draw_circle(c + Vector2(-r * 0.35, -r * 0.22), eye, dark)
	draw_circle(c + Vector2(r * 0.35, -r * 0.22), eye, dark)
	# Mund: Bogen nach oben (froh) bzw. unten (unzufrieden)
	var mood := 0.0 if value < 0.0 else clampf((value - 50.0) / 50.0, -1.0, 1.0)
	var pts := PackedVector2Array()
	for i in 9:
		var x := (i / 8.0 - 0.5) * r * 1.1
		var y := r * 0.32 + (1.0 - pow(x / (r * 0.55), 2.0)) * r * 0.28 * mood
		pts.append(c + Vector2(x, y))
	draw_polyline(pts, dark, maxf(r * 0.12, 1.2), true)
