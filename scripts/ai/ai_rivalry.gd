## AIRivalry
##
## Rivalität zwischen den KI-Reichen (Phase 7): je Paar eine Spannung 0–100, die jede
## Spielstunde zufällig schwankt, bei nahen Grenzen steigt, im Krieg durch
## Kriegsmüdigkeit sinkt und durch Zwischenfälle (Kämpfe) und Spione springt. Ab
## war_at erklären sich die Reiche den Krieg, unter peace_at schliessen sie Frieden
## (jeweils erst nach einer Mindestdauer). Der Spieler erfährt davon nur mit
## Kundschaft (Intel >= 2). Die Kriegserklärung gegen den Spieler bleibt immer.
##
## Zustand: liegt im AISystem (rivalry: "a:b" mit a < b -> {"tension", "state",
## "since" (-1 = noch nicht gesetzt), "last_incident", "known_by_player",
## "skip_min" (nur Debug: Mindestdauer beim nächsten Wechsel übergehen)}).
class_name AIRivalry
extends RefCounted

var sys: AISystem


func _init(p_sys: AISystem) -> void:
	sys = p_sys


## Schlüssel eines Paars ("2:9", kleinere id zuerst)
static func pair_key(a: Kingdom, b: Kingdom) -> String:
	return "%d:%d" % [mini(a.id, b.id), maxi(a.id, b.id)]


## Paar anlegen: Startspannung start_tension ± jitter, Frieden
func init_pair(a: Kingdom, b: Kingdom) -> void:
	var jitter := float(DataDB.ai("rivalry.jitter", 10))
	sys.rivalry[pair_key(a, b)] = {"tension": float(DataDB.ai("rivalry.start_tension", 40)) + sys.rand_range(-jitter, jitter),
			"state": "peace", "since": -1.0, "last_incident": -1.0e9, "known_by_player": false}


## Jede Spielstunde: Zufallsschritt, Grenznähe, Kriegsmüdigkeit, dann Wechsel prüfen
func on_hour() -> void:
	var now := GameClock.game_time
	var game: Node = sys.game
	for key in sys.rivalry.keys():
		var pair: Dictionary = sys.rivalry[key]
		var ka: Kingdom = game.get_kingdom(int(str(key).get_slice(":", 0)))
		var kb: Kingdom = game.get_kingdom(int(str(key).get_slice(":", 1)))
		if ka == null or kb == null or ka.defeated or kb.defeated:
			continue
		if float(pair["since"]) < 0.0:
			pair["since"] = now
		var drift := float(DataDB.ai("rivalry.drift_per_hour", 1.5))
		var tension := float(pair["tension"]) + sys.rand_range(-drift, drift)
		if _border_gap(ka, kb) < float(DataDB.ai("rivalry.border_tiles", 40)):
			tension += float(DataDB.ai("rivalry.border_per_hour", 0.4))
		if str(pair["state"]) == "war":
			tension -= float(DataDB.ai("rivalry.war_weariness_per_hour", 0.8))
		pair["tension"] = clampf(tension, 0.0, 100.0)
		_check_switch(ka, kb, pair, now)


## Kampf zwischen zwei KI-Reichen: Spannung + incident (höchstens alle incident_cooldown s)
func on_incident(a: Kingdom, b: Kingdom) -> void:
	var pair: Dictionary = sys.rivalry.get(pair_key(a, b), {})
	if pair.is_empty():
		return
	var now := GameClock.game_time
	if now - float(pair["last_incident"]) < float(DataDB.ai("rivalry.incident_cooldown", 60)):
		return
	pair["last_incident"] = now
	pair["tension"] = clampf(float(pair["tension"]) + float(DataDB.ai("rivalry.incident", 4)), 0.0, 100.0)


## Spannung ändern (Spione, Ereignisse); der Wechsel folgt zur nächsten vollen Stunde
func add_tension(a: Kingdom, b: Kingdom, amount: float, _reason: String) -> void:
	var pair: Dictionary = sys.rivalry.get(pair_key(a, b), {})
	if not pair.is_empty():
		pair["tension"] = clampf(float(pair["tension"]) + amount, 0.0, 100.0)


## Debug: Spannung setzen; Mindestdauern zählen dann nicht (Wechsel zur nächsten Stunde)
func set_tension(a: Kingdom, b: Kingdom, value: float) -> void:
	var pair: Dictionary = sys.rivalry.get(pair_key(a, b), {})
	if pair.is_empty():
		return
	pair["tension"] = clampf(value, 0.0, 100.0)
	pair["skip_min"] = true


## Abstand der Gebiets-Rechtecke zweier Reiche in Kacheln (0 = sie berühren sich)
func _border_gap(a: Kingdom, b: Kingdom) -> float:
	var world: WorldData = sys.game.world
	var ra := TerritorySystem.kingdom_bbox(a, world)
	var rb := TerritorySystem.kingdom_bbox(b, world)
	if not ra.has_area() or not rb.has_area():
		return INF
	var dx := maxi(0, maxi(ra.position.x - rb.end.x, rb.position.x - ra.end.x))
	var dy := maxi(0, maxi(ra.position.y - rb.end.y, rb.position.y - ra.end.y))
	return float(maxi(dx, dy))


## Krieg ab war_at (nach min_peace_seconds Frieden), Frieden unter peace_at (nach
## min_war_seconds Krieg). Meldung an den Spieler nur mit Kundschaft.
func _check_switch(a: Kingdom, b: Kingdom, pair: Dictionary, now: float) -> void:
	var state := str(pair["state"])
	var tension := float(pair["tension"])
	var since := INF if bool(pair.get("skip_min", false)) else now - float(pair["since"])
	var new_state := state
	if state == "peace" and tension >= float(DataDB.ai("rivalry.war_at", 70)) \
			and since >= float(DataDB.ai("rivalry.min_peace_seconds", 1200)):
		new_state = "war"
	elif state == "war" and tension <= float(DataDB.ai("rivalry.peace_at", 25)) \
			and since >= float(DataDB.ai("rivalry.min_war_seconds", 1800)):
		new_state = "peace"
	if new_state == state:
		return
	pair["state"] = new_state
	pair["since"] = now
	pair.erase("skip_min")
	sys.game.set_relation(a, b, new_state)
	sys.notify_rivalry_changed(a, b, new_state)
	var player: Kingdom = sys.game.player
	if player == null or maxi(sys.get_intel_level(player, a), sys.get_intel_level(player, b)) < 2:
		return
	pair["known_by_player"] = true
	var mid := Vector2.ZERO
	if is_instance_valid(a.castle) and is_instance_valid(b.castle):
		mid = (a.castle.get_center() + b.castle.get_center()) * 0.5
	if new_state == "war":
		player.notify("Kundschaft: %s und %s liegen jetzt im Krieg!" % [a.display_name, b.display_name], "good", mid)
	else:
		player.notify("Kundschaft: %s und %s haben Frieden geschlossen." % [a.display_name, b.display_name], "info", mid)
