## Rauchtest Optionen des neuen Spiels (game_config.json → new_game, GameSession.options): mit allen
## Werten auf „Standard“ ergibt derselbe Seed dieselbe Welt; Dörfer und Gegnerreiche ändern die Zahl der
## Plätze; eine Partie mit 1 Gegner, wenigen Dörfern, vielen Vorräten, ohne Monster und ohne Ereignisse
## hat genau das; Speichern und Laden behält die Optionen. Läuft als letztes Modul (startet eine neue Partie).
extends RefCounted

const TOPIC := "Neues Spiel"


func run(r: Node) -> void:
	# Weltgenerator: Standard = unverändert, Dörfer und Gegnerplätze nach Option
	var counts := {}
	for entry in [["standard", {}], ["few", {"villages": "few"}], ["many", {"villages": "many"}], ["max", {"ai_kingdoms": "max"}],
			["one", {"ai_kingdoms": "1"}]]:
		GameSession.options = entry[1]
		var w: WorldData = WorldGenerator.new().generate(4242, 256)
		counts[entry[0]] = [w.get_sites("village").size(), w.get_sites("kingdom").size(), w.compute_fingerprint()]
	GameSession.options = {}
	var std: Array = counts["standard"]
	r.check(TOPIC, str(counts["one"][2]) == str(std[2]) and counts["few"][0] < std[0] and counts["many"][0] > std[0]
			and counts["max"][1] > std[1],
			"Welt: Standard %d Dörfer/%d Gegnerplätze; wenige %d, viele %d Dörfer; so viele wie möglich %d Plätze; 1 Gegner = gleiche Welt" % [
			std[0], std[1], counts["few"][0], counts["many"][0], counts["max"][1]])
	# Neue Partie mit Optionen
	var options := {"ai_kingdoms": "1", "villages": "few", "resources": "high", "monsters": "off", "events": "off"}
	GameSession.setup_new_game(r.faction, "normal", "small", "777", "", options)
	r.call("_swap_game")
	while r.game == null or not is_instance_valid(r.game) or r.game.get("_playing") != true:
		await r.get_tree().process_frame
	var g: Node = r.game
	var start_wood := float(DataDB.eco("start.resources.wood", 80))
	var wood := float(g.player.get_amount("wood"))
	var ai: Array = g.ai_system.get_ai_kingdoms()
	var monsters := 0
	for u in g.wild.units:
		if (u as Unit).is_alive():
			monsters += 1
	r.check(TOPIC, ai.size() == 1 and monsters == 0 and (g.monster_system.lairs as Dictionary).is_empty()
			and g.village_system.get_villages().size() == roundi(6 * 0.5) and wood >= start_wood * 1.5,
			"Partie: %d Gegnerreich, %d Monster, %d Dörfer, Holz %d (Standard %d)" % [ai.size(), monsters,
			g.village_system.get_villages().size(), roundi(wood), roundi(start_wood)])
	# Keine Zufallsereignisse, auch wenn ihre Zeit gekommen wäre
	var es: EventSystem = g.event_system
	for i in 200:
		es.next_check = 0.0
		es.last_event_at = -1.0e9
		es._schedule(3600.0 + i * 30.0)
	r.check(TOPIC, es.get_active().is_empty() and es.get_history().is_empty(), "Zufallsereignisse aus: keins in 200 Prüfungen")
	# Speichern und Laden behält die Optionen (und dieselbe Welt)
	var err: String = await r.save_and_reload("smoke_new_game")
	r.check(TOPIC, err.is_empty() and GameSession.options == options and r.game.ai_system.get_ai_kingdoms().size() == 1
			and r.game.village_system.get_villages().size() == roundi(6 * 0.5),
			"Gespeichert und geladen %s: Optionen %s" % [err, str(GameSession.options)])
	GameSession.options = {}
