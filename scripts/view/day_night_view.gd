## DayNightView
##
## Abdunklung der Welt bei Dämmerung und Nacht (Phase 8): ein CanvasModulate, dessen
## Farbe linear zwischen den Stützstellen aus daynight.json (tint.keys, Paare
## [Stunde, Farbe]) an der angezeigten Uhrzeit des DayNightSystems liegt.
## Wirkt nur auf Ebene 0 (Welt, Einheiten, Effekte); HUD und Fenster liegen in eigenen
## CanvasLayers und bleiben hell. In den Einstellungen abschaltbar.
## Reine Darstellung in Echtzeit, kein Spielzustand.
class_name DayNightView
extends CanvasModulate

var game: Node
## Stützstellen: [[Stunde, Color], …] aufsteigend
var _keys: Array = []


func _ready() -> void:
	color = Color.WHITE


func setup(p_game: Node) -> void:
	game = p_game
	_keys.clear()
	for pair in DataDB.dn("tint.keys", []):
		var p: Array = pair
		_keys.append([float(p[0]), Color(str(p[1]))])


func _process(_delta: float) -> void:
	var target := Color.WHITE
	if game != null and Settings.day_night_tint and game.get("_playing") == true and not _keys.is_empty():
		target = color_at(game.day_night_system.get_display_hour())
	if absf(target.r - color.r) + absf(target.g - color.g) + absf(target.b - color.b) > 0.002:
		color = target


## Farbe der Abdunklung zu einer Uhrzeit (linear zwischen den Stützstellen)
func color_at(hour: float) -> Color:
	if _keys.is_empty():
		return Color.WHITE
	var prev: Array = _keys[0]
	if hour <= float(prev[0]):
		return prev[1]
	for i in range(1, _keys.size()):
		var next: Array = _keys[i]
		if hour <= float(next[0]):
			var span := maxf(float(next[0]) - float(prev[0]), 0.0001)
			return (prev[1] as Color).lerp(next[1], (hour - float(prev[0])) / span)
		prev = next
	return prev[1]
