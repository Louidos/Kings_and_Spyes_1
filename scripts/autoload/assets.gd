## Assets (Autoload)
##
## Lädt Texturen über ihren Pfad und merkt sie sich. Fehlt eine Datei, wird
## null zurückgegeben – der Aufrufer zeichnet dann einen Platzhalter.
## So können Grafiken jederzeit durch PNG-Dateien ersetzt werden.
extends Node

## Pfad -> Texture2D oder null (auch Fehltreffer werden gemerkt)
var _cache: Dictionary = {}


func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		# Noch nicht vom Editor importierte PNG direkt lesen
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	_cache[path] = tex
	return tex


## Abzeichen eines Skins (crown, sun, skull, fang, star, moon, shield) in der Farbe trim;
## null ohne Abzeichen
func emblem(kind: String, trim: Color) -> Texture2D:
	if kind.is_empty():
		return null
	var key := "emblem:%s:%s" % [kind, trim.to_html()]
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(PlaceholderArt.make_emblem(kind, trim))
	_cache[key] = tex
	return tex


## Gezeichnete Spielfigur (FigureArt) zu einer Beschreibung (FigureArt.spec_for); einmal je
## Beschreibung erzeugt, dann gemerkt – viele Einheiten teilen sich wenige Bilder
func figure(spec: Dictionary, size: int = 0) -> Texture2D:
	if size <= 0:
		size = int(DataDB.unit_figures().get("size", 64))
	var key := FigureArt.spec_key(spec, size)
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(FigureArt.make_figure(spec, size))
	_cache[key] = tex
	return tex


## Anzahl der erzeugten Figurenbilder (Rauchtest, Leistung)
func figure_count() -> int:
	var n := 0
	for key in _cache:
		if str(key).begins_with("figure:"):
			n += 1
	return n


func clear_cache() -> void:
	_cache.clear()
