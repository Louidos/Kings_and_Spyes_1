## AbilityButton
##
## Knopf einer Heldenfähigkeit (Auswahlfenster, Heldenfenster). Wie ein
## Zauberknopf (SpellButton: Bild bzw. Platzhalter in der Fähigkeitsfarbe,
## Abklingzeit als dunkler Ausschnitt mit Restsekunden, Schloss = noch nicht
## gelernt, pulsierender Rahmen im Zielmodus), dazu:
## - Taste oben links (C / V / B), Rang als Punkte oben rechts (I–III)
## - goldener Rahmen: "selbst auslösen" ist an
## - passive Fähigkeiten: Schriftzug "passiv"
## Rechtsklick meldet autocast_requested (schaltet "selbst auslösen" um).
## Der Tooltip kommt wie beim Zauberknopf aus tip_source (BBCode).
class_name AbilityButton
extends SpellButton

## Rechtsklick auf den Knopf ("selbst auslösen" an/aus)
signal autocast_requested(ability_id: String)

var ability_id := ""
var key_text := ""

var _rank := 0
var _max_rank := 3
var _autocast := false
var _passive := false


## Fähigkeit aus heroes.json und die Taste ("C", "V", "B" oder leer)
func setup_ability(def: Dictionary, key: String) -> void:
	setup(def)
	ability_id = str(def.get("id", ""))
	key_text = key
	_max_rank = maxi((def.get("ranks", []) as Array).size(), 1)
	_passive = str(def.get("kind", "active")) != "active"
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)
	queue_redraw()


## Rang und "selbst auslösen" (zeichnet nur bei einer Änderung neu)
func set_extra(rank: int, autocast: bool) -> void:
	if rank == _rank and autocast == _autocast:
		return
	_rank = rank
	_autocast = autocast
	queue_redraw()


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		autocast_requested.emit(ability_id)


func _draw() -> void:
	super()
	var rect := Rect2(Vector2.ZERO, size)
	var font := get_theme_default_font()
	# Taste oben links
	if not key_text.is_empty():
		var pos := Vector2(5, 4 + font.get_ascent(13))
		draw_string_outline(font, pos, key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
		draw_string(font, pos, key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.97, 0.88))
	# Rang: Punkte oben rechts (gefüllt = gelernt)
	for i in _max_rank:
		var c := Vector2(size.x - 7.0 - float(_max_rank - 1 - i) * 7.0, 7.0)
		draw_circle(c, 3.2, Color(0, 0, 0, 0.8))
		if i < _rank:
			draw_circle(c, 2.4, HeroUI.COLOR_XP.lightened(0.25))
		else:
			draw_arc(c, 2.2, 0.0, TAU, 10, Color(0.6, 0.58, 0.55, 0.8), 1.0, true)
	# Passiv: kleiner Schriftzug unten
	if _passive:
		var text := "passiv"
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var pos := Vector2((size.x - w) * 0.5, size.y - 5.0)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, 0.9))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.92, 0.9, 0.84))
	# Selbst auslösen: goldener Rahmen mit Eckmarken
	if _autocast:
		draw_rect(rect.grow(-1.5), Color(HeroUI.COLOR_AUTOCAST, 0.95), false, 3.0)
		var m := 9.0
		for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
			var p: Vector2 = corner
			var dx := m if p.x == 0.0 else -m
			var dy := m if p.y == 0.0 else -m
			draw_line(p, p + Vector2(dx, 0), HeroUI.COLOR_AUTOCAST.lightened(0.3), 4.0)
			draw_line(p, p + Vector2(0, dy), HeroUI.COLOR_AUTOCAST.lightened(0.3), 4.0)
