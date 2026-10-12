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


func clear_cache() -> void:
	_cache.clear()
