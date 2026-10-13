## ResearchTipButton
##
## Button mit farbigem Tooltip (BBCode in einem RichTextLabel). Der Text
## entsteht erst beim Zeigen (tip_source), nicht bei jeder Aktualisierung –
## so bleibt die Anzeige billig, und der Tooltip ist immer aktuell.
## Normales tooltip_text kann keine Farben (fehlende Dinge rot).
## Optional: ein Punkt oben rechts (badge_visible, z. B. "Kampfpunkte
## ausgebbar") und ein dünner Fortschrittsstrich unten (underline_ratio).
class_name ResearchTipButton
extends Button

## Breiteste Tooltipzeile (Pixel); längere Zeilen bricht make_rich_tooltip um
const TIP_MAX_WIDTH := 330.0
const TIP_FONT_SIZE := 16
const TIP_TEXT_COLOR := Color(0.95, 0.92, 0.85)

## Liefert den Tooltip als BBCode (leer = kein Tooltip)
var tip_source := Callable()
## Breiteste Tooltipzeile für diesen Button
var tip_max_width := TIP_MAX_WIDTH
## Punkt oben rechts (Aufmerksamkeit)
var badge_visible := false:
	set(value):
		if badge_visible != value:
			badge_visible = value
			queue_redraw()
var badge_color := Color(1.0, 0.62, 0.18)
## Fortschrittsstrich am unteren Rand (0..1; negativ = keiner)
var underline_ratio := -1.0:
	set(value):
		if not is_equal_approx(underline_ratio, value):
			underline_ratio = value
			queue_redraw()
var underline_color := Color(0.4, 0.68, 0.98)


func _init() -> void:
	# Kein Tastaturfokus, sonst würde die Leertaste (Pause) den Button auslösen
	focus_mode = Control.FOCUS_NONE


func _get_tooltip(_at_position: Vector2) -> String:
	return str(tip_source.call()) if tip_source.is_valid() else tooltip_text


func _make_custom_tooltip(for_text: String) -> Object:
	return make_rich_tooltip(for_text, tip_max_width)


func _draw() -> void:
	if underline_ratio >= 0.0:
		var bar := Rect2(4.0, size.y - 5.0, size.x - 8.0, 3.0)
		draw_rect(bar, Color(0.0, 0.0, 0.0, 0.45))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(underline_ratio, 0.0, 1.0), bar.size.y)), underline_color)
	if badge_visible:
		var c := Vector2(size.x - 7.0, 7.0)
		draw_circle(c, 5.5, Color(0.08, 0.05, 0.02, 0.9))
		draw_circle(c, 4.2, badge_color)


## RichTextLabel für einen Tooltip aus BBCode. Ohne Zeilenumbruch misst es
## seine Breite selbst; ist eine Zeile zu lang, wird auf max_width umgebrochen.
static func make_rich_tooltip(bbcode: String, max_width: float = TIP_MAX_WIDTH) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", TIP_FONT_SIZE)
	rtl.add_theme_font_size_override("bold_font_size", TIP_FONT_SIZE)
	rtl.add_theme_color_override("default_color", TIP_TEXT_COLOR)
	rtl.text = bbcode
	if _widest_line(rtl.get_parsed_text()) > max_width:
		rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rtl.custom_minimum_size.x = max_width
	return rtl


## Breite der längsten Zeile (ohne BBCode) in der Tooltip-Schrift
static func _widest_line(plain: String) -> float:
	var font := ThemeDB.fallback_font
	var widest := 0.0
	for line in plain.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, TIP_FONT_SIZE).x)
	return widest


## Text für BBCode entschärfen (eckige Klammern in Namen)
static func esc(plain: String) -> String:
	return plain.replace("[", "[lb]")


## "[color=#rrggbb]text[/color]"
static func colored(plain: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), esc(plain)]


## Zahl mit einer Nachkommastelle und Komma (deutsch): 11.4 -> "11,4"
static func num1(v: float) -> String:
	return ("%.1f" % v).replace(".", ",")
