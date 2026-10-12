## SpellButton
##
## Quadratischer Knopf eines Zaubers in der Zauberleiste (SpellBar):
## - Bild aus spells.json ("icon"); fehlt es, ein Platzhalter in der
##   Zauberfarbe: Leuchten, Zeichen der Schule und der Buchstabe
## - Abklingzeit: dunkler Kreisausschnitt (im Uhrzeigersinn) mit Restsekunden
## - noch nicht erforscht: abgedunkelt mit Schloss
## - zu wenig Mana: roter Schimmer
## - Zielmodus für diesen Zauber: heller, pulsierender Rahmen
## Der Tooltip ist farbig (RichTextLabel) und wird erst beim Zeigen gebaut
## (tip_source liefert BBCode mit den aktuellen Werten).
class_name SpellButton
extends BaseButton

const BUTTON_SIZE := 56.0
const COLOR_BACK := Color(0.07, 0.065, 0.1, 1.0)
const COLOR_LOCKED := Color(0.42, 0.4, 0.44)
const COLOR_BAD := Color(1.0, 0.36, 0.3)
const COOLDOWN_SHADE := Color(0.0, 0.0, 0.0, 0.64)
## Breite, ab der Tooltip-Text umbricht (Pixel)
const TIP_WIDTH := 320.0
const TIP_FONT_SIZE := 16
## So lange (Sekunden) blitzt der Knopf auf, wenn die Abklingzeit vorbei ist
const FLASH_SECONDS := 0.6

var spell_id := ""
## Liefert den BBCode des Tooltips (wird beim Zeigen aufgerufen)
var tip_source := Callable()

var _texture: Texture2D
var _color := Color.WHITE
var _letter := ""
var _school := ""
var _known := false
## Anteil der verbleibenden Abklingzeit (0 = bereit)
var _cd_ratio := 0.0
var _cd_seconds := 0
var _no_mana := false
var _targeting := false
var _flash := 0.0
var _pulse := 0.0
var _style := StyleBoxFlat.new()


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style.set_corner_radius_all(6)
	_style.anti_aliasing = true
	set_process(false)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


## Zauber aus spells.json
func setup(def: Dictionary) -> void:
	spell_id = str(def.get("id", ""))
	_color = def.get("color", Color.WHITE)
	_letter = str(def.get("letter", "?"))
	_school = str(def.get("school", ""))
	_texture = Assets.texture(str(def.get("icon", "")))
	# Nicht leer, sonst zeigt Godot gar keinen Tooltip (Inhalt kommt aus tip_source)
	tooltip_text = str(def.get("name", spell_id))
	queue_redraw()


## Zustand setzen; zeichnet nur bei einer sichtbaren Änderung neu
func set_state(known: bool, cd_ratio: float, cd_seconds: int, no_mana: bool, targeting: bool) -> void:
	var ratio := snappedf(clampf(cd_ratio, 0.0, 1.0), 0.004)
	if known == _known and is_equal_approx(ratio, _cd_ratio) and cd_seconds == _cd_seconds \
			and no_mana == _no_mana and targeting == _targeting:
		return
	# Abklingzeit gerade vorbei: kurz aufblitzen
	if _known and known and _cd_ratio > 0.0 and ratio <= 0.0:
		_flash = 1.0
	_known = known
	_cd_ratio = ratio
	_cd_seconds = cd_seconds
	_no_mana = no_mana
	_targeting = targeting
	set_process(_flash > 0.0 or _targeting)
	queue_redraw()


func is_targeting() -> bool:
	return _targeting


func _process(delta: float) -> void:
	# Nur für das Aufblitzen und das Pulsieren im Zielmodus (UI: Echtzeit)
	_pulse = fmod(_pulse + delta, TAU)
	if _flash > 0.0:
		_flash = maxf(_flash - delta / FLASH_SECONDS, 0.0)
	if _flash <= 0.0 and not _targeting:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var inner := rect.grow(-3.0)
	var hovered := is_hovered() and not disabled
	var bright := _bright(_color)

	# Hintergrund
	_style.bg_color = COLOR_BACK
	_style.set_border_width_all(0)
	draw_style_box(_style, rect)

	# Bild oder Platzhalter
	if _texture != null:
		draw_texture_rect(_texture, inner, false, Color.WHITE if _known else Color(0.55, 0.55, 0.55))
	else:
		_draw_placeholder(inner, bright)

	# Abklingzeit: dunkler Ausschnitt ab 12 Uhr im Uhrzeigersinn
	if _known and _cd_ratio > 0.0:
		_draw_cooldown(inner, _cd_ratio)
	# Zu wenig Mana: roter Schimmer
	if _known and _no_mana and _cd_ratio <= 0.0:
		draw_rect(inner, Color(0.8, 0.1, 0.08, 0.32))
	# Noch nicht erforscht: abgedunkelt mit Schloss
	if not _known:
		draw_rect(inner, Color(0.03, 0.03, 0.05, 0.55))
		_draw_lock(rect.get_center() + Vector2(0, 3))
	if _known and _cd_ratio > 0.0:
		_draw_centered_text(str(_cd_seconds), rect.get_center(), 21, Color.WHITE)
	if _flash > 0.0:
		draw_rect(inner, Color(1.0, 1.0, 0.95, 0.4 * _flash))
	if is_pressed() and hovered:
		draw_rect(inner, Color(0, 0, 0, 0.25))

	# Rahmen
	var border := Color(_color, 0.85)
	var width := 2
	if not _known:
		border = COLOR_LOCKED
		width = 1
	elif _no_mana and _cd_ratio <= 0.0:
		border = COLOR_BAD
	if hovered:
		border = border.lightened(0.35)
		width = 2
	if _targeting:
		# Pulsierender Lichtschein um den Knopf
		var glow := 0.5 + 0.5 * sin(_pulse * 5.0)
		draw_rect(rect.grow(2.0), Color(bright, 0.18 + 0.22 * glow), false, 4.0)
		border = bright.lightened(0.3)
		width = 3
	_style.bg_color = Color(0, 0, 0, 0)
	_style.border_color = border
	_style.set_border_width_all(width)
	draw_style_box(_style, rect)


## Leuchten in der Zauberfarbe, Zeichen der Schule, Buchstabe
func _draw_placeholder(r: Rect2, bright: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var col := _color if _known else COLOR_LOCKED
	draw_circle(c, s * 0.46, Color(col, 0.13))
	draw_circle(c, s * 0.34, Color(col, 0.16))
	draw_circle(c, s * 0.22, Color(col, 0.2))
	_draw_school_glyph(c, s, Color(bright if _known else COLOR_LOCKED, 0.5))
	var letter_color := bright.lightened(0.25) if _known else Color(0.62, 0.6, 0.62)
	_draw_centered_text(_letter, c + Vector2(0, -1), int(s * 0.46), letter_color)


## Einfaches Zeichen je Schule (hinter dem Buchstaben)
func _draw_school_glyph(c: Vector2, s: float, col: Color) -> void:
	var w := maxf(s * 0.05, 1.5)
	match _school:
		"combat":
			# Zwei gekreuzte Klingen
			var a := s * 0.36
			draw_line(c + Vector2(-a, a), c + Vector2(a, -a), col, w, true)
			draw_line(c + Vector2(a, a), c + Vector2(-a, -a), col, w, true)
			draw_line(c + Vector2(-a * 0.75, a * 0.45), c + Vector2(-a * 0.45, a * 0.75), col, w, true)
			draw_line(c + Vector2(a * 0.75, a * 0.45), c + Vector2(a * 0.45, a * 0.75), col, w, true)
		"healing":
			# Kreuz
			var a := s * 0.36
			var t := s * 0.12
			draw_rect(Rect2(c - Vector2(t, a), Vector2(t * 2.0, a * 2.0)), col)
			draw_rect(Rect2(c - Vector2(a, t), Vector2(a * 2.0, t * 2.0)), col)
		"stealth":
			# Halb geschlossenes Auge
			var r := s * 0.42
			draw_arc(c + Vector2(0, r * 0.55), r, deg_to_rad(-150), deg_to_rad(-30), 18, col, w, true)
			draw_arc(c - Vector2(0, r * 0.55), r, deg_to_rad(30), deg_to_rad(150), 18, col, w, true)
		"weather":
			# Wolke mit Tropfen
			var y := c.y - s * 0.16
			draw_circle(Vector2(c.x - s * 0.16, y + s * 0.04), s * 0.13, col)
			draw_circle(Vector2(c.x + s * 0.02, y - s * 0.03), s * 0.17, col)
			draw_circle(Vector2(c.x + s * 0.2, y + s * 0.05), s * 0.12, col)
			for i in 3:
				var x := c.x + (float(i) - 1.0) * s * 0.17
				draw_line(Vector2(x, c.y + s * 0.12), Vector2(x - s * 0.05, c.y + s * 0.32), col, w, true)
		"summon":
			# Kreis mit Strahlen (Tor)
			draw_arc(c, s * 0.3, 0.0, TAU, 28, col, w, true)
			for i in 8:
				var d := Vector2.from_angle(TAU * float(i) / 8.0)
				draw_line(c + d * s * 0.36, c + d * s * 0.46, col, w, true)


## Dunkler Ausschnitt für die verbleibende Abklingzeit, auf das Quadrat begrenzt
func _draw_cooldown(r: Rect2, ratio: float) -> void:
	var c := r.get_center()
	var half := r.size * 0.5
	var pts := PackedVector2Array()
	pts.append(c)
	var steps := maxi(ceili(ratio * 48.0), 2)
	# Von 12 Uhr aus: der bereits abgelaufene Teil ist hell, der Rest dunkel
	var start := -PI * 0.5 + TAU * (1.0 - ratio)
	for i in steps + 1:
		var a := start + TAU * ratio * float(i) / float(steps)
		var d := Vector2(cos(a), sin(a))
		var t := minf(half.x / maxf(absf(d.x), 0.0001), half.y / maxf(absf(d.y), 0.0001))
		pts.append(c + d * t)
	if pts.size() >= 3:
		draw_colored_polygon(pts, COOLDOWN_SHADE)


func _draw_lock(c: Vector2) -> void:
	var body := Rect2(c + Vector2(-8, -2), Vector2(16, 12))
	var col := Color(0.86, 0.84, 0.8)
	draw_arc(c + Vector2(0, -3), 5.0, PI, TAU, 12, Color(0, 0, 0, 0.7), 4.5, true)
	draw_arc(c + Vector2(0, -3), 5.0, PI, TAU, 12, col, 2.5, true)
	draw_line(c + Vector2(-5, -3), c + Vector2(-5, -1), col, 2.5)
	draw_line(c + Vector2(5, -3), c + Vector2(5, -1), col, 2.5)
	draw_rect(body.grow(1.0), Color(0, 0, 0, 0.7))
	draw_rect(body, col)
	draw_rect(Rect2(c + Vector2(-1, 2), Vector2(2, 4)), Color(0.2, 0.2, 0.22))


func _draw_centered_text(text: String, center: Vector2, font_size: int, col: Color) -> void:
	var font := get_theme_default_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := center + Vector2(-w * 0.5, (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(roundi(font_size * 0.2), 3), Color(0, 0, 0, 0.85))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


## Farbiger Tooltip (siehe Button-Tooltips in Godot: nur so mit Farbe)
func _make_custom_tooltip(_for_text: String) -> Object:
	if not tip_source.is_valid():
		return null
	return make_rich_tooltip(str(tip_source.call()))


## Dunkle Zauberfarben (Schattenmantel) auf dunklem Grund lesbar machen
static func _bright(col: Color) -> Color:
	return col.lightened(0.4) if col.get_luminance() < 0.45 else col


## Lesbare Textfarbe einer Zauberfarbe als BBCode-Farbwert ("#rrggbb")
static func text_color_html(col: Color) -> String:
	return "#" + _bright(col).to_html(false)


## RichTextLabel für Tooltips: BBCode, Höhe passt sich an, kein automatischer
## Umbruch (lange Zeilen vorher mit wrap_text umbrechen)
static func make_rich_tooltip(bbcode: String) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in ["normal_font_size", "bold_font_size"]:
		rtl.add_theme_font_size_override(key, TIP_FONT_SIZE)
	rtl.add_theme_color_override("default_color", Color(0.95, 0.92, 0.85))
	rtl.text = bbcode
	return rtl


## Bricht Text an Wortgrenzen so um, dass keine Zeile breiter als max_width ist
static func wrap_text(text: String, max_width: float = TIP_WIDTH, font_size: int = TIP_FONT_SIZE) -> String:
	var font := ThemeDB.fallback_font
	var lines: PackedStringArray = []
	var line := ""
	for word in text.split(" ", false):
		var probe := word if line.is_empty() else line + " " + word
		if not line.is_empty() and font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
			lines.append(line)
			line = word
		else:
			line = probe
	if not line.is_empty():
		lines.append(line)
	return "\n".join(lines)
