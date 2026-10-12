## NotificationPanel
##
## Meldungen oben rechts (Notify.posted). Die neueste steht oben, höchstens
## MAX_ENTRIES gleichzeitig. Jede Meldung verschwindet nach LIFETIME echten
## Sekunden (blendet aus); solange die Maus darauf liegt, bleibt sie stehen.
## Klick auf eine Meldung mit Ort springt mit der Kamera dorthin,
## Meldungen ohne Ort werden per Klick geschlossen.
class_name NotificationPanel
extends VBoxContainer

const MAX_ENTRIES := 6
const LIFETIME := 8.0
const FADE_TIME := 0.8
const FONT_SIZE := 16
const KIND_COLORS := {
	"info": Color(0.96, 0.95, 0.92),
	"good": Color(0.55, 0.95, 0.5),
	"warning": Color(1.0, 0.68, 0.28),
	"danger": Color(1.0, 0.42, 0.38),
}

var game: Node

## Einträge, neueste zuerst: {button: Button, age: float}
var _entries: Array = []


func _ready() -> void:
	# Die leere Fläche zwischen den Meldungen lässt Klicks zur Karte durch
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	Notify.posted.connect(_on_posted)


func setup(p_game: Node) -> void:
	game = p_game


func _process(delta: float) -> void:
	for i in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[i]
		var b: Button = entry["button"]
		if b.is_hovered():
			entry["age"] = minf(float(entry["age"]), LIFETIME - FADE_TIME - 1.0)
			b.modulate.a = 1.0
			continue
		var age := float(entry["age"]) + delta
		entry["age"] = age
		if age >= LIFETIME:
			_remove(i)
		elif age > LIFETIME - FADE_TIME:
			b.modulate.a = clampf((LIFETIME - age) / FADE_TIME, 0.0, 1.0)


func _on_posted(text: String, kind: String, world_pos: Variant) -> void:
	var color: Color = KIND_COLORS.get(kind, KIND_COLORS["info"])
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Kein Tastaturfokus, sonst würde die Leertaste (Pause) den Button auslösen
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, color)
	b.add_theme_stylebox_override("normal", _make_style(color, 0.78))
	b.add_theme_stylebox_override("hover", _make_style(color, 0.92))
	b.add_theme_stylebox_override("pressed", _make_style(color, 0.92))
	b.add_theme_stylebox_override("hover_pressed", _make_style(color, 0.92))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var has_pos := world_pos is Vector2
	b.tooltip_text = "Klicken: zur Stelle springen" if has_pos else "Klicken: schliessen"
	b.pressed.connect(_on_entry_pressed.bind(b, world_pos))
	add_child(b)
	move_child(b, 0)
	_entries.push_front({"button": b, "age": 0.0})
	while _entries.size() > MAX_ENTRIES:
		_remove(_entries.size() - 1)


func _on_entry_pressed(b: Button, world_pos: Variant) -> void:
	if world_pos is Vector2:
		if game != null and game.camera != null:
			game.camera.focus_on(world_pos)
	else:
		for i in _entries.size():
			var entry: Dictionary = _entries[i]
			if entry["button"] == b:
				_remove(i)
				break


func _remove(index: int) -> void:
	var entry: Dictionary = _entries[index]
	_entries.remove_at(index)
	var b: Button = entry["button"]
	if is_instance_valid(b):
		b.queue_free()


## Dunkler, halbdurchsichtiger Hintergrund mit farbigem Rand links
func _make_style(color: Color, alpha: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.045, 0.07, alpha)
	s.border_width_left = 4
	s.border_color = color
	s.corner_radius_top_left = 4
	s.corner_radius_bottom_left = 4
	s.corner_radius_top_right = 4
	s.corner_radius_bottom_right = 4
	s.content_margin_left = 12.0
	s.content_margin_right = 10.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s
