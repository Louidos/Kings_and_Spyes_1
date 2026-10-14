## GameSession (Autoload)
##
## Hält die Parameter der aktuellen Partie (Fraktion, Schwierigkeit, Kartengrösse,
## Seed). Das Hauptmenü füllt diese Werte, die Spielszene liest sie.
## Ab Phase 10 wird hier auch der Spielstand gespeichert/geladen.
extends Node

## "good" oder "evil"
var faction_id: String = "good"
var difficulty_id: String = "normal"
var map_size_id: String = "large"
## Seed so, wie der Spieler ihn eingegeben hat (Zahl oder Text)
var seed_text: String = ""
## Daraus berechneter Zahlen-Seed für die Generatoren
var world_seed: int = 0
## Rauchtest/Debug: feste Anzahl KI-Reiche (−1 = aus Daten)
var ai_count_override := -1


func _ready() -> void:
	difficulty_id = DataDB.default_difficulty
	map_size_id = DataDB.cfg("map.default_size", "large")


## Startet eine neue Partie mit den gegebenen Parametern.
func setup_new_game(p_faction: String, p_difficulty: String, p_map_size: String, p_seed_text: String) -> void:
	faction_id = p_faction
	difficulty_id = p_difficulty
	map_size_id = p_map_size
	seed_text = p_seed_text.strip_edges()
	if seed_text.is_empty():
		seed_text = random_seed_text()
	world_seed = seed_from_text(seed_text)


## Kartenbreite/-höhe in Kacheln
func get_map_tiles() -> int:
	var entry := DataDB.get_map_size(map_size_id)
	return int(entry.get("tiles", 512))


func get_faction() -> Dictionary:
	return DataDB.get_faction(faction_id)


func get_difficulty() -> Dictionary:
	return DataDB.get_difficulty(difficulty_id)


## Wandelt eine Eingabe in einen Zahlen-Seed um. Reine Zahlen werden direkt
## übernommen, Text wird gehasht (z. B. "Drachenland").
func seed_from_text(text: String) -> int:
	if text.is_valid_int():
		return text.to_int()
	return text.hash()


func random_seed_text() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return str(rng.randi_range(1, 999_999_999))
