## Rauchtest (ohne Fenster): startet eine Partie, lässt sie im Zeitraffer laufen
## und gibt am Ende eine Zusammenfassung aus. Fehler erscheinen als
## "SCRIPT ERROR" in der Ausgabe.
##
## Aufruf (im Projektordner):
##   godot --headless res://tests/smoke_test.tscn -- faction=good seconds=120 size=small seed=12345
extends Node

var _args := {}
var _game: Node = null
var _started_ms := 0
var _sim_seconds := 120.0
var _phase := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := str(a).split("=", true, 1)
		if parts.size() == 2:
			_args[parts[0]] = parts[1]
	_sim_seconds = float(_args.get("seconds", "120"))
	GameSession.setup_new_game(str(_args.get("faction", "good")), str(_args.get("difficulty", "normal")),
			str(_args.get("size", "small")), str(_args.get("seed", "12345")))
	print("[smoke] Starte Partie: ", GameSession.faction_id, " Seed ", GameSession.seed_text)
	_started_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/game.tscn")
	_game = scene.instantiate()
	get_tree().root.add_child.call_deferred(_game)


func _process(_delta: float) -> void:
	if _game == null or not is_instance_valid(_game):
		return
	if _phase == 0:
		if _game.get("_playing") == true:
			_phase = 1
			print("[smoke] Welt fertig nach %d ms" % (Time.get_ticks_msec() - _started_ms))
			GameClock.set_speed_index(GameClock.speed_steps.size() - 1)
			Engine.time_scale = float(_args.get("time_scale", "8"))
			Engine.physics_ticks_per_second = 60
			if _game.has_method("smoke_test_setup"):
				_game.smoke_test_setup()
		elif Time.get_ticks_msec() - _started_ms > 120000:
			push_error("[smoke] Weltgenerierung dauert zu lange")
			get_tree().quit(2)
	elif _phase == 1:
		if GameClock.game_time >= _sim_seconds:
			_phase = 2
			_report()
			get_tree().quit(0)


func _report() -> void:
	print("[smoke] Spielzeit %.0f s (Tag %d)" % [GameClock.game_time, GameClock.get_day()])
	for k in _game.kingdoms:
		var res := []
		for r in k.resources:
			res.append("%s %.0f" % [r, float(k.resources[r])])
		print("[smoke] Reich %d %s (%s, %s): Gebäude %d, Einheiten %d, besiegt %s | %s" % [
				k.id, k.display_name, k.faction_id, k.controller, k.buildings.size(), k.units.size(),
				str(k.defeated), ", ".join(res)])
	if _game.has_method("smoke_test_report"):
		_game.smoke_test_report()
