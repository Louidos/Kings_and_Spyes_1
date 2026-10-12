## ResearchTipButton
##
## Button mit farbigem Tooltip (BBCode in einem RichTextLabel). Der Text
## entsteht erst beim Zeigen (tip_source), nicht bei jeder Aktualisierung –
## so bleibt die Leiste billig, und der Tooltip ist immer aktuell.
## Normales tooltip_text kann keine Farben (fehlende Dinge rot).
class_name ResearchTipButton
extends Button

## Breiteste Tooltipzeile (Pixel); längere Zeilen bricht make_rich_tooltip um
const TIP_MAX_WIDTH := 340.0
const TIP_FONT_SIZE := 16

## Liefert den Tooltip als BBCode (leer = kein Tooltip)
var tip_source := Callable()


func _init() -> void:
	# Kein Tastaturfokus, sonst würde die Leertaste (Pause) den Button auslösen
	focus_mode = Control.FOCUS_NONE


func _get_tooltip(_at_position: Vector2) -> String:
	return str(tip_source.call()) if tip_source.is_valid() else tooltip_text


func _make_custom_tooltip(for_text: String) -> Object:
	return make_rich_tooltip(for_text)


## RichTextLabel für einen Tooltip aus BBCode. Ohne Zeilenumbruch misst es
## seine Breite selbst; ist eine Zeile zu lang, wird auf TIP_MAX_WIDTH umgebrochen.
static func make_rich_tooltip(bbcode: String) -> Control:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", TIP_FONT_SIZE)
	rtl.add_theme_font_size_override("bold_font_size", TIP_FONT_SIZE)
	rtl.add_theme_color_override("default_color", Color(0.95, 0.92, 0.85))
	rtl.text = bbcode
	if rtl.get_content_width() > TIP_MAX_WIDTH:
		rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rtl.custom_minimum_size.x = TIP_MAX_WIDTH
	return rtl


## Text für BBCode entschärfen (eckige Klammern in Namen)
static func esc(text: String) -> String:
	return text.replace("[", "[lb]")


## "[color=#rrggbb]text[/color]"
static func colored(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), esc(text)]
