## EconomySystem
##
## Laufende Wirtschaft aller Reiche:
## - Nahrungsverbrauch der Einheiten und Hungersnot
## - Bevölkerungswachstum (Wohnraum + Nahrung nötig)
## - Ertrag pro Minute je Ressource (für die Anzeige)
## - stündliches Nachwachsen geernteter Vorkommen (Beeren, Wild)
class_name EconomySystem
extends Node

## Alle so viele Spielsekunden werden die Ertragsraten neu berechnet
const RATE_INTERVAL := 6.0

## Warum gerade kein Wachstum stattfindet
enum Growth { GROWING, HOUSING_FULL, LOW_FOOD, STARVING }

var game: Node
var world: WorldData
## Zwischenstand für die Ertragsraten (nur Anzeige, muss nicht gespeichert werden)
var _rate_timer := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	GameClock.sim_tick.connect(_on_sim_tick)
	GameClock.hour_passed.connect(_on_hour_passed)


## Wachstumszustand eines Reichs (für Tooltip/Anzeige)
func get_growth_state(kingdom: Kingdom) -> int:
	if kingdom.starving:
		return Growth.STARVING
	if kingdom.get_population() >= kingdom.get_housing():
		return Growth.HOUSING_FULL
	if kingdom.get_amount("food") < float(DataDB.eco("population.growth_food_min", 30)):
		return Growth.LOW_FOOD
	return Growth.GROWING


## Sekunden bis zum nächsten Bewohner (nur sinnvoll im Zustand GROWING)
func get_seconds_to_growth(kingdom: Kingdom) -> float:
	return maxf(_growth_interval(kingdom) - kingdom.growth_timer, 0.0)


## Nahrungsverbrauch pro Spielminute
func get_food_consumption_per_minute(kingdom: Kingdom) -> float:
	return _food_per_day(kingdom) / maxf(GameClock.seconds_per_day, 1.0) * 60.0


func _growth_interval(kingdom: Kingdom) -> float:
	return float(DataDB.eco("population.growth_interval", 45.0)) / maxf(kingdom.mod("growth"), 0.01)


func _on_sim_tick(dt: float) -> void:
	for kingdom in game.kingdoms:
		if not kingdom.has_economy:
			continue  # z. B. Monster: essen nicht, vermehren sich über ihre Höhlen
		_consume_food(kingdom, dt)
		_grow(kingdom, dt)
		# Mana aus Forschung und Kampfpunkt-Verbesserungen (die Burg erzeugt es)
		if kingdom.mana_regen > 0.0 and is_instance_valid(kingdom.castle):
			kingdom.add_resource("mana", kingdom.mana_regen * dt)
	_rate_timer += dt
	if _rate_timer >= RATE_INTERVAL:
		for kingdom in game.kingdoms:
			var sample: Dictionary = kingdom.take_income_sample()
			for res_id in sample:
				var rate := float(sample[res_id]) / _rate_timer * 60.0
				# Glätten, damit die Anzeige nicht springt
				kingdom.income_rate[res_id] = lerpf(float(kingdom.income_rate.get(res_id, 0.0)), rate, 0.5)
		_rate_timer = 0.0


func _on_hour_passed(_day: int, _hour: int) -> void:
	world.regrow(1)


func _food_per_day(kingdom: Kingdom) -> float:
	var total := 0.0
	for u in kingdom.units:
		total += float(u.type_def.get("food_per_day", 0.0))
	return total * kingdom.mod("food_use")


func _consume_food(kingdom: Kingdom, dt: float) -> void:
	var need := _food_per_day(kingdom) / maxf(GameClock.seconds_per_day, 1.0) * dt
	if need > 0.0:
		kingdom.add_resource("food", -need)
	var hungry := kingdom.get_amount("food") <= 0.0 and need > 0.0
	if hungry and not kingdom.starving:
		kingdom.starving = true
		kingdom.resources_changed.emit()
		kingdom.notify("Hungersnot! Die Arbeit geht nur noch halb so schnell. Setze mehr Sammler oder Bauern ein.", "danger")
	elif kingdom.starving and kingdom.get_amount("food") >= float(DataDB.eco("starvation.recover_food", 10.0)):
		kingdom.starving = false
		kingdom.resources_changed.emit()
		kingdom.notify("Die Hungersnot ist vorbei.", "good")


func _grow(kingdom: Kingdom, dt: float) -> void:
	var state := get_growth_state(kingdom)
	if state == Growth.HOUSING_FULL:
		if not kingdom.flags.get("housing_full_notified", false):
			kingdom.flags["housing_full_notified"] = true
			kingdom.notify("Kein Wohnraum mehr – baue Wohnhäuser, damit neue Bewohner kommen.", "info")
		return
	kingdom.flags.erase("housing_full_notified")
	if state != Growth.GROWING or not is_instance_valid(kingdom.castle):
		return
	kingdom.growth_timer += dt
	if kingdom.growth_timer < _growth_interval(kingdom):
		return
	kingdom.growth_timer = 0.0
	kingdom.add_resource("food", -float(DataDB.eco("population.growth_food_cost", 10)))
	var pos := kingdom.castle.get_approach_point(kingdom.castle.get_center() + Vector2(0, 1000))
	var u: Unit = game.unit_system.spawn_unit(kingdom, "villager", pos)
	if u != null:
		game.work_system.set_unit_job(u, "idle")
		kingdom.notify("Ein neuer Bewohner ist angekommen – gib ihm Arbeit (J).", "good", pos)
