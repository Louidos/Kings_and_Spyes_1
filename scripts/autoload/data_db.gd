## DataDB (Autoload)
##
## Lädt alle Spieldaten aus dem Ordner /data (JSON) und stellt sie dem Rest
## des Spiels zur Verfügung. Kein anderes System liest JSON direkt – so gibt
## es eine einzige Stelle, an der Daten geprüft und umgewandelt werden.
extends Node

const DATA_DIR := "res://data/"

## Allgemeine Konfiguration (game_config.json)
var config: Dictionary = {}
## Parameter der Weltgenerierung (worldgen.json)
var worldgen: Dictionary = {}
## Biome in Regel-Reihenfolge. Der Array-Index ist die Biom-Nummer im Kartenarray.
var biomes: Array = []
## Biom-ID ("forest") -> Index in `biomes`
var biome_index_by_id: Dictionary = {}
## Index des Standard-Bioms (wenn keine Regel zutrifft)
var default_biome_index: int = 0
var factions: Array = []
var peoples: Array = []
var difficulties: Array = []
var default_difficulty: String = "normal"


func _ready() -> void:
	reload()


## Lädt alle Datendateien (neu). Kann z. B. für Hot-Reload erneut aufgerufen werden.
func reload() -> void:
	config = _load_json("game_config.json")
	worldgen = _load_json("worldgen.json")
	_load_biomes()
	var faction_data := _load_json("factions.json")
	factions = faction_data.get("factions", [])
	peoples = faction_data.get("peoples", [])
	for f in factions:
		f["color"] = _parse_color(f.get("color", "#ffffff"))
	var diff_data := _load_json("difficulties.json")
	difficulties = diff_data.get("difficulties", [])
	default_difficulty = diff_data.get("default", "normal")


## Liest einen Wert aus game_config.json über einen Punkt-Pfad, z. B. "camera.zoom_max".
func cfg(path: String, default_value: Variant = null) -> Variant:
	var node: Variant = config
	for key in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return default_value
	return node


func get_biome(index: int) -> Dictionary:
	return biomes[index]


func get_faction(id: String) -> Dictionary:
	return _find_by_id(factions, id)


func get_difficulty(id: String) -> Dictionary:
	return _find_by_id(difficulties, id)


func get_map_size(id: String) -> Dictionary:
	return _find_by_id(cfg("map.sizes", []), id)


func get_peoples_of_faction(faction_id: String) -> Array:
	return peoples.filter(func(p): return p.get("faction") == faction_id)


# ---------------------------------------------------------------------------
# Intern
# ---------------------------------------------------------------------------

func _load_biomes() -> void:
	var data := _load_json("biomes.json")
	biomes = data.get("biomes", [])
	biome_index_by_id.clear()
	if biomes.size() > 255:
		push_error("biomes.json: Maximal 255 Biome erlaubt.")
		biomes.resize(255)
	for i in biomes.size():
		var b: Dictionary = biomes[i]
		b["index"] = i
		b["color"] = _parse_color(b.get("color", "#ff00ff"))
		b["movement_cost"] = float(b.get("movement_cost", 1.0))
		b["defense_bonus"] = float(b.get("defense_bonus", 0.0))
		b["buildable"] = bool(b.get("buildable", true))
		if not b.has("conditions"):
			b["conditions"] = {}
		if not b.has("sprites"):
			b["sprites"] = []
		biome_index_by_id[b.get("id", "biome_%d" % i)] = i
	default_biome_index = biome_index_by_id.get(data.get("default_biome", ""), maxi(biomes.size() - 1, 0))
	if biomes.is_empty():
		push_error("biomes.json enthält keine Biome – die Karte kann nicht erzeugt werden.")


func _load_json(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("Datendatei fehlt: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("Fehler in %s, Zeile %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		push_error("%s: Oberste Ebene muss ein Objekt { ... } sein." % path)
		return {}
	return json.data


func _parse_color(value: Variant) -> Color:
	if value is Color:
		return value
	var s := str(value)
	if Color.html_is_valid(s):
		return Color.html(s)
	push_warning("Ungültige Farbe in Daten: %s" % s)
	return Color.MAGENTA


func _find_by_id(list: Array, id: String) -> Dictionary:
	for entry in list:
		if entry is Dictionary and entry.get("id") == id:
			return entry
	return {}
