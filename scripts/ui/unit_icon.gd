## UnitIcon
##
## Kleines Bild eines Einheitentyps für Fenster (Beschwören, Warteschlange):
## die Grafik aus units.json, sonst dieselbe gezeichnete Figur wie auf der Karte
## (FigureArt, Reichsfarbe) – im gewählten Aussehen des Typs (Skin: eigene Grafik,
## sonst Figur in Skin-Farben mit Muster und Zeichen wie auf der Karte).
## Optional ein Fortschrittsbalken am unteren Rand (laufende Beschwörung).
class_name UnitIcon
extends Control

const COLOR_PROGRESS := Color(0.62, 0.52, 1.0)

## Fortschritt 0..1; negativ = kein Balken
var progress := -1.0

var _texture: Texture2D
var _figure: Texture2D
var _emblem: Texture2D
var _tint := Color.WHITE


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Einheitentyp (Dictionary aus units.json) für ein Reich; skin_id leer = Aussehen,
## das der Typ im Reich trägt (TroopRules.type_skin)
func setup(type_def: Dictionary, kingdom: Kingdom, skin_id: String = "") -> void:
	var faction := kingdom.faction_id if kingdom != null else "good"
	if skin_id.is_empty():
		skin_id = TroopRules.type_skin(kingdom, type_def)
	var skin_data := {} if skin_id == "standard" else TroopRules.skin_def(skin_id)
	_tint = Color.WHITE
	_emblem = null
	_texture = null
	if not skin_data.is_empty():
		_texture = Assets.texture(TroopRules.skin_sprite(str(type_def.get("id", "")), skin_id))
	var own_skin_file := _texture != null
	if _texture == null:
		_texture = Assets.texture(DataDB.get_unit_sprite(type_def, faction))
	_figure = null
	var fallback: Color = kingdom.color if kingdom != null else Color.GRAY
	var color: Color = type_def.get("color", fallback)
	# Wie Unit.refresh_look: Skin ohne eigene Grafik = Tönung bzw. Figur in Skin-Farben, dazu das Zeichen
	if not skin_data.is_empty() and not own_skin_file:
		_emblem = Assets.emblem(str(skin_data.get("emblem", "")), skin_data.get("trim", Color.WHITE))
		if _texture != null:
			var mix := float(DataDB.trp("skins.tint_mix", 0.55))
			var tint: Color = skin_data.get("tint", color)
			_tint = Color.WHITE.lerp(tint, mix * 0.6)
	if _texture == null:
		_figure = Assets.figure(FigureArt.spec_for(type_def, faction, color, skin_data))
	queue_redraw()


## Leeres Feld (z. B. freier Platz in der Warteschlange)
func clear() -> void:
	_texture = null
	_figure = null
	_emblem = null
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
		draw_texture_rect(_texture, rect, false, _tint)
	elif _figure != null:
		# Figur etwas grösser, Füsse am unteren Rand
		var big := Rect2(rect.position + Vector2(-side * 0.08, -side * 0.1), rect.size * 1.16)
		draw_texture_rect(_figure, big, false)
	if _emblem != null:
		# Zeichen des Skins oben links (wie über der Figur auf der Karte)
		draw_texture_rect(_emblem, Rect2(rect.position, rect.size * 0.42), false)
	if progress >= 0.0:
		var bar := Rect2(rect.position.x + 1.0, rect.end.y - 5.0, rect.size.x - 2.0, 5.0)
		SpriteDraw.draw_bar(self, bar, progress, COLOR_PROGRESS)
