## DayClock
##
## Symbol der Tageszeit in der oberen Leiste (Phase 8): Himmelskreis (Farbe nach dem
## Tageslicht), Bogen für den Fortschritt des Abschnitts, Sonne mit Strahlen bzw.
## Mondsichel. Optional ersetzen assets/ui/icons/daytime_sun.png bzw. daytime_moon.png
## die Zeichnung. Farbiger Tooltip mit Abschnitt, Uhrzeit, Zeit bis zum Wechsel,
## globalen Nachtwerten und den Tag-/Nachtboni des eigenen Volks. Klick öffnet die
## Reichsübersicht (Reiter "Volk & Tageszeit").
class_name DayClock
extends Control

signal clicked

const SIZE := 30.0

var game: Node
var _last_key := ""


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func setup(p_game: Node) -> void:
	game = p_game


func _process(_delta: float) -> void:
	if game == null or not is_visible_in_tree():
		return
	var dns: DayNightSystem = game.day_night_system
	var key := "%s %d" % [dns.get_phase(), roundi(dns.get_display_hour() * 4.0)]
	if key != _last_key:
		_last_key = key
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		accept_event()


func _get_tooltip(_at_position: Vector2) -> String:
	return tooltip()


func _make_custom_tooltip(for_text: String) -> Object:
	return ResearchTipButton.make_rich_tooltip(for_text, 420.0)


## Tooltip als BBCode
func tooltip() -> String:
	if game == null:
		return ""
	var dns: DayNightSystem = game.day_night_system
	var tip := ResearchTipButton
	var lines: PackedStringArray = []
	var next := dns.seconds_to_next()
	var h := dns.get_display_hour()
	lines.append("[b]Tageszeit: %s (%02d:%02d)[/b]" % [dns.get_phase_name(), int(h), int(h * 60.0) % 60])
	if float(next["seconds"]) >= 0.0:
		lines.append("%s beginnt in ca. %d s" % [dns.get_phase_name(str(next["phase"])), ceili(float(next["seconds"]))])
	else:
		lines.append(tip.colored("Tageszeit festgehalten (Debug)", Color(1.0, 0.82, 0.35)))
	for line in dns.describe_kingdom(game.player):
		lines.append(tip.esc(line))
	var night: Dictionary = DataDB.dn("global.night", {})
	var parts: PackedStringArray = []
	for key in night:
		parts.append(DataDB.describe_modifier(str(key), float(night[key])))
	if not parts.is_empty():
		lines.append(tip.colored("Nachts (alle): " + ", ".join(parts) + "; Monster aktiver", Color(0.74, 0.71, 0.66)))
	var player: Kingdom = game.player
	var own := DayNightSystem.people_daynight_text(player.people_id)
	if not own.is_empty():
		lines.append(tip.colored("Dein Volk (%s): %s" % [DataDB.get_people_name(player.people_id), own], Color(0.62, 0.7, 1.0)))
	lines.append(tip.colored("Klick: Reichsübersicht (L) – Volk & Tageszeit", Color(0.74, 0.71, 0.66)))
	return "\n".join(lines)


func _draw() -> void:
	if game == null:
		return
	var dns: DayNightSystem = game.day_night_system
	var light := dns.get_daylight()
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.5 - 1.0
	var sky := Color(0.16, 0.18, 0.36).lerp(Color(0.45, 0.68, 0.95), light)
	draw_circle(c, r + 1.0, Color(0.05, 0.04, 0.03, 0.9))
	draw_circle(c, r, sky)
	# Fortschritt des Tages als Bogen (0 Uhr oben)
	var h := dns.get_display_hour()
	draw_arc(c, r - 1.0, -PI * 0.5, -PI * 0.5 + TAU * h / 24.0, 24, Color(1.0, 0.95, 0.75, 0.55), 2.0, true)
	var is_day := light >= 0.5
	var tex: Texture2D = Assets.texture("res://assets/ui/icons/%s.png" % ("daytime_sun" if is_day else "daytime_moon"))
	if tex != null:
		draw_texture_rect(tex, Rect2(c - Vector2(r, r) * 0.75, Vector2(r, r) * 1.5), false)
		return
	if is_day:
		var sun := Color(1.0, 0.86, 0.3)
		for i in 8:
			var a := TAU * i / 8.0
			draw_line(c + Vector2.from_angle(a) * r * 0.42, c + Vector2.from_angle(a) * r * 0.68, sun, 1.6, true)
		draw_circle(c, r * 0.32, sun)
	else:
		var moon := Color(0.92, 0.92, 0.8)
		draw_circle(c, r * 0.45, moon)
		draw_circle(c + Vector2(r * 0.2, -r * 0.12), r * 0.4, sky)
