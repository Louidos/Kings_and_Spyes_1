## Rauchtest Entdeckung (espionage.json awareness, ai.json difficulty): die Abstufung nach
## Schwierigkeit bleibt (leicht langsamer als episch), die Aufmerksamkeit steigt höchstens mit
## rise_per_minute (ohne Sprünge), und ein Angriff auf ein Gegnerreich entdeckt den Angreifer
## weiterhin sofort.
extends RefCounted

const TOPIC := "Entdeckung"


func run(r: Node) -> void:
	var g: Node = r.game
	var es: EspionageSystem = g.espionage_system
	var player: Kingdom = g.player
	# Abstufung der Schwierigkeit: Faktor steigt, Wartezeit sinkt von leicht bis episch
	var diffs: Dictionary = DataDB.ai("difficulty", {})
	var mults: Array = []
	var patience: Array = []
	for id in ["easy", "normal", "hard", "epic"]:
		mults.append(float((diffs.get(id, {}) as Dictionary).get("awareness_mult", 1.0)))
		patience.append(float((diffs.get(id, {}) as Dictionary).get("patience_minutes", 0.0)))
	var graded := true
	for i in range(1, 4):
		graded = graded and mults[i] > mults[i - 1] and patience[i] < patience[i - 1]
	r.check(TOPIC, graded, "Abstufung leicht → episch: Faktor %s, Wartezeit %s min" % [str(mults), str(patience)])
	var rumour := float(DataDB.esp("awareness.rumour", 30))
	var discovered := float(DataDB.esp("awareness.discovered", 60))
	r.check(TOPIC, float(DataDB.esp("awareness.patience_floor", 35)) >= rumour and discovered > rumour,
			"Schwellen: Gerüchte ab %s, entdeckt ab %s, Wartezeit hält mindestens %s" % [str(rumour), str(discovered),
			str(DataDB.esp("awareness.patience_floor", 35))])
	var ai: Array = g.ai_system.get_ai_kingdoms()
	if ai.is_empty():
		r.check(TOPIC, false, "Kein KI-Reich für den Entdeckungstest")
		return
	var enemy: Kingdom = ai[0]
	# Langsamer Anstieg: ein Takt über eine Spielminute hebt die Aufmerksamkeit von 0 aus höchstens um
	# rise_per_minute (Sprünge durch Sichtungen, Boten oder Angriffe kommen getrennt dazu)
	es.debug_set_awareness(enemy, player, 0.0)
	es._tick_awareness(60.0, GameClock.game_time)
	var rise := es.get_awareness(enemy, player)
	var limit := float(DataDB.esp("awareness.rise_per_minute", 3.0))
	r.check(TOPIC, rise <= limit + 0.001 and rise < float(DataDB.esp("awareness.rumour", 30)),
			"Anstieg in einer Minute ohne Sprünge: %.1f (höchstens %.1f)" % [rise, limit])
	# Ein Angriff entdeckt den Angreifer sofort
	g.combat_system.kingdom_attacked.emit(enemy, player, enemy.castle.get_center())
	r.check(TOPIC, es.get_awareness(enemy, player) >= discovered,
			"Angriff auf %s: Aufmerksamkeit %.1f (entdeckt ab %s)" % [enemy.display_name, es.get_awareness(enemy, player),
			str(discovered)])
