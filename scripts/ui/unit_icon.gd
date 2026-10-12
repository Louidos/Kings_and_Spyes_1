## UnitIcon
##
## Kleines Bild eines Einheitentyps für Fenster (Beschwören, Warteschlange):
## die Grafik aus units.json, sonst dieselbe Spielfigur wie auf der Karte
## (Scheibe in Reichsfarbe mit Buchstabe). Optional ein Fortschrittsbalken
## am unteren Rand (laufende Beschwörung).
class_name UnitIcon
extends Control

const COLOR_PROGRESS := Color(0.62, 0.52, 1.0)

## Fortschritt 0..1; negativ = kein Balken
var progress := -1.0

var _texture: Texture2D
var _token: Texture2D
var _letter := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Einheitentyp (Dictionary aus units.json) für ein Reich
func setup(type_def: Dictionary, kingdom: Kingdom) -> void:
	var faction := kingdom.faction_id if kingdom != null else "good"
	_texture = Assets.texture(DataDB.get_unit_sprite(type_def, faction))
	_token = null
	if _texture == null:
		var fallback: Color = kingdom.color if kingdom != null else Color.GRAY
		var color: Color = type_def.get("color", fallback)
		_token = Assets.unit_token(color, "diamond" if str(type_def.get("role", "")) == "monster" else "circle")
	_letter = str(type_def.get("letter", ""))
	queue_redraw()


## Leeres Feld (z. B. freier Platz in der Warteschlange)
func clear() -> void:
	_texture = null
	_token = null
	_letter = ""
	progress = -1.0
	queue_redraw()


func set_progress(p: float) -> void:
	if not is_equal_approx(p, progress):
		progress = p
		queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	if _texture != null:
		draw_texture_rect(_texture, rect, false)
	elif _token != null:
		draw_texture_rect(_token, rect, false)
		if not _letter.is_empty():
			SpriteDraw.draw_label(self, _letter, rect.get_center(), maxi(int(side * 0.42), 9))
	if progress >= 0.0:
		var bar := Rect2(rect.position.x + 1.0, rect.end.y - 5.0, rect.size.x - 2.0, 5.0)
		SpriteDraw.draw_bar(self, bar, progress, COLOR_PROGRESS)
