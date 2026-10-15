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


## Platzhalter-Spielfigur in dieser Farbe und Form (einmal erzeugt, dann gemerkt)
func unit_token(color: Color, shape: String) -> Texture2D:
	var key := "token:%s:%s" % [color.to_html(), shape]
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(PlaceholderArt.make_unit_token(color, shape))
	_cache[key] = tex
	return tex


## Platzhalter-Spielfigur eines Skins: Farbe (schon getönt) mit breitem Rand in trim
## (einmal je Kombination erzeugt, dann gemerkt)
func unit_skin_token(color: Color, shape: String, trim: Color) -> Texture2D:
	var key := "skin_token:%s:%s:%s" % [color.to_html(), shape, trim.to_html()]
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(PlaceholderArt.make_unit_skin_token(color, shape, trim))
	_cache[key] = tex
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


func clear_cache() -> void:
	_cache.clear()
