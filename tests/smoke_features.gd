## Rauchtest neuer Spielfunktionen (eigene Szene tests/smoke_features.tscn, von run_smoke.sh für
## beide Fraktionen gestartet): startet eine kleine Partie und lässt nacheinander die Prüfmodule
## laufen (je Modul eine Datei tests/smoke_<thema>.gd mit func run(runner) -> void, darf await
## benutzen). Fehler erscheinen als "ERROR: [smoke] <Thema> FEHLER: …" (push_error), Rückgabewert 1.
##   godot --headless res://tests/smoke_features.tscn -- faction=good [only=<thema>]
extends Node

## Prüfmodule in dieser Reihenfolge
const MODULES := {
	"Stärke": preload("res://tests/smoke_strength.gd"),
	"Bewohner": preload("res://tests/smoke_residents.gd"),
	"Baustellen": preload("res://tests/smoke_sites.gd"),
	"Dörfer": preload("res://tests/smoke_villages.gd"),
	"Helden": preload("res://tests/smoke_new_heroes.gd"),
	"Handel": preload("res://tests/smoke_trade.gd"),
	"Bündnis": preload("res://tests/smoke_alliance.gd"),
	"Entdeckung": preload("res://tests/smoke_discovery.gd"),
	"Welt": preload("res://tests/smoke_world_compat.gd"),
}

var game: Node
var faction := "good"
var errors := 0
var _only := ""
var _started := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := str(a).split("=", true, 1)
		if parts.size() == 2 and parts[0] == "faction":
			faction = parts[1]
		if parts.size() == 2 and parts[0] == "only":
			_only = parts[1]
	GameSession.setup_new_game(faction, "normal", "small", "12345", "")
	_spawn_game()


func _spawn_game() -> void:
	game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	game.set("reload_handler", _swap_game)
	get_tree().root.add_child.call_deferred(game)


func _swap_game() -> void:
	var old := game
	if old.get_parent() != null:
		old.get_parent().remove_child(old)
	old.queue_free()
	_spawn_game()


## Speichert die Partie und lädt sie in eine frische Spielszene (danach zeigt game auf die neue)
func save_and_reload(slot: String) -> String:
	var err: String = game.save_game(slot, "Rauchtest " + slot, "manual", false)
	if err.is_empty():
		err = SaveManager.request_load(slot)
	if not err.is_empty():
		return err
	game.request_reload()
	while game == null or not is_instance_valid(game) or game.get("_playing") != true:
		await get_tree().process_frame
	SaveManager.delete_save(slot)
	return ""


func _process(_delta: float) -> void:
	if _started or game == null or game.get("_playing") != true:
		return
	_started = true
	_run_all()


func _run_all() -> void:
	for topic in MODULES:
		if not _only.is_empty() and str(topic) != _only:
			continue
		var module: RefCounted = (MODULES[topic] as GDScript).new()
		await module.call("run", self)
	Engine.time_scale = 1.0
	print("[smoke] Funktionen: %s" % ("OK" if errors == 0 else "%d Fehler" % errors))
	get_tree().quit(0 if errors == 0 else 1)


func check(topic: String, cond: bool, text: String) -> void:
	if cond:
		print("[smoke] %s OK: %s" % [topic, text])
	else:
		errors += 1
		push_error("[smoke] %s FEHLER: %s" % [topic, text])


## Spielzeit vergehen lassen (Zeitraffer), dann weiter
func wait_game_seconds(seconds: float) -> void:
	GameClock.set_speed_index(GameClock.speed_steps.size() - 1)
	Engine.time_scale = 8.0
	var until := GameClock.game_time + seconds
	while GameClock.game_time < until:
		await get_tree().process_frame
	Engine.time_scale = 1.0


## Einheiten eines Typs (Stufe) für ein Reich vor seiner Burg
func spawn_tier(k: Kingdom, tier: String, count: int) -> Array:
	var list: Array = []
	var def := DataDB.get_unit_for_tier(k.faction_id, tier)
	if def.is_empty():
		return list
	for i in count:
		var pos: Vector2 = k.castle.get_approach_point(k.castle.get_center() + Vector2.from_angle(TAU * i / maxf(count, 1.0)) * 900.0)
		var u: Unit = game.unit_system.spawn_unit(k, str(def["id"]), pos)
		if u != null:
			list.append(u)
	return list
