## GameSession (Autoload)
##
## Hält die Parameter der aktuellen Partie (Fraktion, Schwierigkeit, Kartengrösse,
## Seed). Das Hauptmenü füllt diese Werte, die Spielszene liest sie.
## Ab Phase 10 merkt sich die Sitzung auch, welcher Spielstand geladen werden soll
## (pending_load_path), die echte Spielzeit und Fehler für das Hauptmenü.
## Optionen des neuen Spiels (game_config.json → new_game: Gegnerreiche, Dörfer, Startvorräte,
## Monster, Zufallsereignisse) stehen in options und im Spielstand; fehlt eine, gilt "standard".
## Tutorial: start_tutorial startet es mit der neuen Partie (Knopf "Tutorial" im Hauptmenü
## bzw. "Tipps/Tutorial anzeigen"); sein Zustand liegt danach im TutorialSystem.
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
## Volk des Spielers (ab Phase 8; leer = keins)
var people_id: String = ""
## Echte Spielzeit der Partie in Sekunden (ohne Pause; wird gespeichert)
var play_seconds: float = 0.0
## Diesen Spielstand lädt die Spielszene beim Start ("" = neue Partie)
var pending_load_path: String = ""
var pending_load_name: String = ""
## Zuletzt benutzter Speichername (Vorschlag im Speichern-Fenster)
var last_save_name: String = ""
## Fehler beim Laden (zeigt das Hauptmenü einmal an)
var last_error: String = ""
## Rauchtest: nach dem Laden den Zustand erneut einsammeln (Idempotenz-Vergleich)
var debug_verify_load := false
## Neue Partie startet mit dem Tutorial (gilt auch für "Neu starten" derselben Partie;
## ein geladener Spielstand bringt seinen eigenen Tutorial-Zustand mit)
var start_tutorial := false
## Optionen des neuen Spiels: Schlüssel (ai_kingdoms, villages, resources, monsters, events) -> id;
## fehlende Schlüssel = "standard"
var options: Dictionary = {}

## Schlüssel der Optionen in game_config.json → new_game (Reihenfolge im Dialog)
const OPTION_KEYS := ["ai_kingdoms", "villages", "resources", "monsters", "events"]


func _ready() -> void:
	difficulty_id = DataDB.default_difficulty
	map_size_id = DataDB.cfg("map.default_size", "large")


## Startet eine neue Partie mit den gegebenen Parametern. p_people: Volk des Spielers
## (leer oder unpassend = erstes Volk der Fraktion).
func setup_new_game(p_faction: String, p_difficulty: String, p_map_size: String, p_seed_text: String,
		p_people: String = "", p_options: Dictionary = {}) -> void:
	faction_id = p_faction
	people_id = p_people
	if str(DataDB.get_people(people_id).get("faction", "")) != faction_id:
		var list := DataDB.get_peoples_of_faction(faction_id)
		people_id = str((list[0] as Dictionary).get("id", "")) if not list.is_empty() else ""
	difficulty_id = p_difficulty
	map_size_id = p_map_size
	seed_text = p_seed_text.strip_edges()
	if seed_text.is_empty():
		seed_text = random_seed_text()
	world_seed = seed_from_text(seed_text)
	pending_load_path = ""
	pending_load_name = ""
	last_save_name = ""
	play_seconds = 0.0
	start_tutorial = false
	options = {}
	for key in p_options:
		if OPTION_KEYS.has(str(key)) and not get_option_entry(str(key), str(p_options[key])).is_empty():
			options[str(key)] = str(p_options[key])


## Gewählte Option (id, "standard" wenn nicht gesetzt)
func get_option(key: String) -> String:
	return str(options.get(key, "standard"))


## Eintrag einer Option aus game_config.json → new_game ({} wenn unbekannt)
static func get_option_entry(key: String, id: String) -> Dictionary:
	for e in DataDB.cfg("new_game." + key, []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == id:
			return e
	return {}


## Zahl der gewählten Option (factor bzw. count), default bei "standard" oder unbekannt
func option_number(key: String, field: String, default: float) -> float:
	return float(get_option_entry(key, get_option(key)).get(field, default))


## Gewünschte Zahl der Gegnerreiche (-1 = Standard nach Schwierigkeit und Kartengrösse)
func get_ai_kingdoms_option() -> int:
	return int(option_number("ai_kingdoms", "count", -1.0))


## Tutorial-Partie (Knopf "Tutorial"): fester Seed, Kartengrösse und Schwierigkeit aus
## tutorial.json, gewählte Fraktion; das Tutorial startet mit der Partie
func setup_tutorial_game(p_faction: String, p_people: String = "") -> void:
	setup_new_game(p_faction, str(DataDB.tut("game.difficulty", "easy")), str(DataDB.tut("game.map_size", "small")),
			str(DataDB.tut("game.seed", "Lernreich")), p_people)
	start_tutorial = true


## Gespeicherte Werte der Partie (Spielstand)
func to_dict() -> Dictionary:
	return {"faction_id": faction_id, "difficulty_id": difficulty_id, "map_size_id": map_size_id,
			"seed_text": seed_text, "world_seed": world_seed, "people_id": people_id,
			"ai_count_override": ai_count_override, "play_seconds": play_seconds, "options": options.duplicate()}


## Partie aus einem Spielstand (Kopf oder session-Teil) übernehmen
func apply_session(d: Dictionary) -> void:
	faction_id = str(d.get("faction_id", faction_id))
	difficulty_id = str(d.get("difficulty_id", difficulty_id))
	map_size_id = str(d.get("map_size_id", map_size_id))
	seed_text = str(d.get("seed_text", seed_text))
	world_seed = int(d.get("world_seed", seed_from_text(seed_text)))
	people_id = str(d.get("people_id", ""))
	if d.has("ai_count_override"):
		ai_count_override = int(d["ai_count_override"])
	play_seconds = float(d.get("play_seconds", 0.0))
	# Spielstände vor den Optionen (1.2.x): alles "standard"
	options = (d.get("options", {}) as Dictionary).duplicate() if d.get("options", {}) is Dictionary else {}
	start_tutorial = false


## Kartenbreite/-höhe in Kacheln
func get_map_tiles() -> int:
	var entry := DataDB.get_map_size(map_size_id)
	return int(entry.get("tiles", 512))


func get_faction() -> Dictionary:
	return DataDB.get_faction(faction_id)


## Volk des Spielers ({} wenn keins)
func get_people() -> Dictionary:
	return DataDB.get_people(people_id)


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
