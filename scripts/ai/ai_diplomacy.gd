## AIDiplomacy
##
## Diplomatie und Kundschaft eines KI-Reichs (Phase 7): Späher (Streife am eigenen
## Gebietsrand, Erkundung fremder Reiche), Dörfer (Geschenke, Verträge, Frieden,
## Aufnahme, Drohungen über die DiplomacySystem-Schnittstellen), Spione und
## Reichstarnung. Nur statische Funktionen; Zustand in Kingdom.ai_state ("scouts",
## "next_patrol", "village_next", "gift_value_hour", "spy_next").
##
## Stand: Späher sind umgesetzt. Dörfer, Spione und Reichstarnung brauchen das
## EspionageSystem/SpySystem (Arbeitspaket 4 der Phase 7) und sind bis dahin leer –
## das Gehirn ruft sie bereits im richtigen Takt auf.
class_name AIDiplomacy
extends RefCounted


## Späher: einer läuft Streife (alle defense.patrol_interval Sekunden zu einem
## zufälligen Punkt am eigenen Gebietsrand), ein zweiter erkundet ein Reich, über
## das Gerüchte umgehen (Punkt 8 Kacheln in dessen Gebiet), sonst ebenfalls Streife.
static func tick_scouts(b: AIBrain, now: float) -> void:
	var k := b.k
	var roles: Dictionary = b.st["scouts"]
	var alive := {}
	for u in k.units:
		if u.tier == "scout" and u.is_alive():
			alive[u.uid] = u
	for uid in roles.keys():
		if not alive.has(int(uid)):
			roles.erase(uid)
	for uid in alive:
		if not roles.has(uid):
			roles[uid] = "patrol" if not roles.values().has("patrol") else "explore"
	if now < float(b.st["next_patrol"]):
		return
	b.st["next_patrol"] = now + float(DataDB.ai("defense.patrol_interval", 60))
	var cmd: CommandSystem = b.game.command_system
	var rumour := float(DataDB.esp("awareness.rumour", 30))
	var explore_target := _explore_target(b, rumour)
	for uid in roles:
		var u: Unit = alive[uid]
		if u.target != null and is_instance_valid(u.target):
			continue
		if str(roles[uid]) == "explore" and explore_target != null:
			cmd.order_move([u], _explore_point(b, explore_target), false)
		else:
			cmd.order_move([u], _patrol_point(b), false)


## Reich, über das Gerüchte umgehen (Aufmerksamkeit >= rumour), das nächste zuerst; sonst null
static func _explore_target(b: AIBrain, rumour: float) -> Kingdom:
	var best: Kingdom = null
	var best_d := INF
	var home := b.home_center()
	for o in b.game.kingdoms:
		var other: Kingdom = o
		if other == b.k or other.defeated or not is_instance_valid(other.castle):
			continue
		if other.controller != "player" and other.controller != "ai":
			continue
		if b.sys.get_awareness(b.k, other) < rumour:
			continue
		var d := home.distance_to(other.castle.get_center())
		if d < best_d:
			best_d = d
			best = other
	return best


## Zufälliger freier Punkt am Rand des eigenen Gebiets
static func _patrol_point(b: AIBrain) -> Vector2:
	var world := b.world
	var home := b.home_center()
	var dir := Vector2.from_angle(b.sys.rand_float() * TAU)
	var p := home + dir * (b.territory_radius_tiles() - 1.0) * float(world.tile_size)
	var cell: Vector2i = b.game.nav.nearest_free(world.world_to_cell(p), 6)
	return world.cell_to_world(cell) if cell.x >= 0 else b.home_rally()


## Punkt 8 Kacheln innerhalb des fremden Gebiets, von der eigenen Burg aus gesehen
static func _explore_point(b: AIBrain, target: Kingdom) -> Vector2:
	var world := b.world
	var their := target.castle.get_center()
	var dir := (b.home_center() - their).normalized()
	var radius := float(DataDB.get_building("castle").get("territory_radius", 14))
	var p := their + dir * maxf(radius - 8.0, 2.0) * float(world.tile_size)
	var cell: Vector2i = b.game.nav.nearest_free(world.world_to_cell(p), 6)
	return world.cell_to_world(cell) if cell.x >= 0 else their


## Dörfer (Geschenke, Verträge, Frieden, Aufnahme, Drohungen): folgt mit Arbeitspaket 4
static func tick_villages(_b: AIBrain, _now: float) -> void:
	pass


## Spione anwerben und mit Aufträgen versehen: folgt mit dem SpySystem (Arbeitspaket 4)
static func tick_spies(_b: AIBrain, _now: float) -> void:
	pass


## Reichstarnung ein-/ausschalten: folgt mit dem EspionageSystem (Arbeitspaket 4)
static func tick_cloak(_b: AIBrain, _now: float) -> void:
	pass
