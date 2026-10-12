## HpBar
##
## Schlanker Lebensbalken für Fenster (Auswahl, Tooltips): Hintergrund,
## Füllung in Ampelfarbe (wie die Balken über den Einheiten) und der Text
## "Leben / Höchstwert" in der Mitte. Selbst gezeichnet statt ProgressBar,
## damit er ohne eigenes Theme zum restlichen HUD passt.
class_name HpBar
extends Control

const COLOR_BACK := Color(0.05, 0.045, 0.06, 0.9)
const COLOR_BORDER := Color(0.0, 0.0, 0.0, 0.85)
const COLOR_GOOD := Color(0.3, 0.78, 0.32)
const COLOR_MID := Color(0.92, 0.74, 0.2)
const COLOR_LOW := Color(0.9, 0.24, 0.2)

## 0..1
var ratio := 1.0
var text := ""
var font_size := 14
## Feste Füllfarbe (z. B. für Fortschritt); Alpha 0 = Ampelfarbe nach ratio
var fill_color := Color(0, 0, 0, 0)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 20)


## Setzt Wert und Text; zeichnet nur bei einer Änderung neu
func set_value(current: float, maximum: float, label: String = "") -> void:
	var r := clampf(current / maxf(maximum, 0.001), 0.0, 1.0)
	if label.is_empty():
		label = "%d / %d" % [ceili(current), roundi(maximum)]
	if is_equal_approx(r, ratio) and label == text:
		return
	ratio = r
	text = label
	queue_redraw()


## Ampelfarbe wie bei den Balken in der Spielwelt
static func color_for(r: float) -> Color:
	if r > 0.5:
		return COLOR_GOOD
	if r > 0.25:
		return COLOR_MID
	return COLOR_LOW


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, COLOR_BACK, true)
	if ratio > 0.0:
		var fill := fill_color if fill_color.a > 0.0 else color_for(ratio)
		var inner := Rect2(rect.position + Vector2(1, 1), Vector2((rect.size.x - 2.0) * ratio, rect.size.y - 2.0))
		draw_rect(inner, fill.darkened(0.15), true)
		# Heller Streifen oben: wirkt plastischer
		draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.4)), fill.lightened(0.12), true)
	draw_rect(rect, COLOR_BORDER, false, 1.0)
	if text.is_empty():
		return
	var font := get_theme_default_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var pos := Vector2((size.x - w) * 0.5, baseline)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.98, 0.94))
