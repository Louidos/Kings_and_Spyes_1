## CommandSystem
##
## Befehle an Einheiten: Bewegen (in Formation), Angriffsmarsch, Angriff auf
## ein Ziel, Halt und "Zur Arbeit". Arbeitende Einheiten unterbrechen dafür
## ihre Arbeit (WorkSystem.suspend); "Zur Arbeit" setzt sie fort.
## Wird vom Spieler (SelectionController) und ab Phase 7 von der KI benutzt.
class_name CommandSystem
extends Node

signal formation_changed(formation: String)

const FORMATIONS := ["block", "line"]
const FORMATION_NAMES := {"block": "Block", "line": "Linie"}

var game: Node
var world: WorldData
var unit_system: UnitSystem
var work_system: WorkSystem
## Aktuelle Formation für Marschbefehle
var formation := "block"

var _spacing := 0.9


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	unit_system = game.unit_system
	work_system = game.work_system
	_spacing = float(DataDB.cmb("formation.spacing", 0.9))
	var default_formation := str(DataDB.cmb("formation.default", "block"))
	formation = default_formation if FORMATIONS.has(default_formation) else "block"


## Formation wechseln (Block <-> Linie)
func toggle_formation() -> void:
	set_formation("line" if formation == "block" else "block")


func set_formation(f: String) -> void:
	if not FORMATIONS.has(f) or f == formation:
		return
	formation = f
	formation_changed.emit(formation)


func get_formation_name() -> String:
	return str(FORMATION_NAMES.get(formation, formation))


## Marschbefehl zu pos. Mehrere Einheiten verteilen sich in der Formation.
## attack_move: unterwegs kämpfen.
func order_move(units: Array, pos: Vector2, attack_move: bool = false) -> void:
	var list := _keep_king_home(_commandable(units), pos)
	if list.is_empty():
		return
	var slots := formation_slots(list, pos)
	for i in list.size():
		var u: Unit = list[i]
		_prepare(u)
		u.command = "attack_move" if attack_move else "move"
		u.command_pos = slots[i]
		u.target = null
		unit_system.move_to(u, slots[i])


## Angriff auf ein bestimmtes Ziel (Unit oder Building). Heiler folgen nur.
func order_attack(units: Array, target: Object) -> void:
	if not is_instance_valid(target):
		return
	var list := _keep_king_home(_commandable(units), target.position)
	if list.is_empty():
		return
	for u in list:
		if not is_fighter(u):
			continue
		_prepare(u)
		u.command = "attack"
		u.command_pos = u.position
		u.target = target
		u.repath_timer = 0.0
		u.think_timer = 0.0
	var followers: Array = []
	for u in list:
		if not is_fighter(u):
			followers.append(u)
	if not followers.is_empty():
		order_move(followers, target.position)


## Halt: stehen bleiben und den Platz verteidigen.
func order_stop(units: Array) -> void:
	for u in _commandable(units):
		_prepare(u)
		u.command = "hold"
		u.command_pos = u.position
		u.target = null
		unit_system.stop(u)


## Befehl aufheben: Arbeiter arbeiten weiter, andere halten ihren Platz.
func order_return_to_work(units: Array) -> void:
	for u in _commandable(units):
		if u.can_work():
			work_system.resume(u)
		else:
			u.command = "hold"
			u.command_pos = u.position
			u.target = null
			unit_system.stop(u)


## Zielplätze für eine Gruppe: Reihen quer zur Marschrichtung. Nahkämpfer
## stehen vorne, Fernkämpfer dahinter, Heiler hinten. Innerhalb einer Reihe
## werden die Einheiten nach ihrer seitlichen Lage verteilt (wenig Kreuzungen).
## Gibt die Plätze in derselben Reihenfolge wie units zurück.
func formation_slots(units: Array, dest: Vector2) -> Array:
	var n := units.size()
	var result: Array = []
	result.resize(n)
	if n == 1:
		result[0] = dest
		return result
	var centroid := Vector2.ZERO
	for u in units:
		centroid += u.position
	centroid /= float(n)
	var forward := dest - centroid
	forward = Vector2.DOWN if forward.length() < 1.0 else forward.normalized()
	var right := Vector2(-forward.y, forward.x)
	var cols: int
	if formation == "line":
		cols = n if n <= 12 else ceili(n / 2.0)
	else:
		cols = ceili(sqrt(float(n)))
	var rows := ceili(float(n) / cols)
	var spacing := _spacing * world.tile_size + _max_radius(units) * 0.6

	# Reihenfolge: Rolle (vorne -> hinten), dann seitliche Lage
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ra := _rank(units[a])
		var rb := _rank(units[b])
		if ra != rb:
			return ra < rb
		return (units[a].position - centroid).dot(forward) > (units[b].position - centroid).dot(forward))
	for row in rows:
		var start := row * cols
		var count := mini(cols, n - start)
		var row_units: Array = order.slice(start, start + count)
		row_units.sort_custom(func(a: int, b: int) -> bool:
			return (units[a].position - centroid).dot(right) < (units[b].position - centroid).dot(right))
		var y := ((rows - 1) * 0.5 - row) * spacing
		for col in count:
			var x := (col - (count - 1) * 0.5) * spacing
			result[row_units[col]] = dest + right * x + forward * y
	return result


## Kämpft diese Einheit auf Befehl? (Bewohner und Heiler laufen nur mit)
static func is_fighter(u: Unit) -> bool:
	return u.attack > 0.0 and (u.role == "combat" or u.role == "king" or u.role == "monster")


# ---------------------------------------------------------------------------

## Der König verlässt sein Reich nicht: Befehle mit Ziel ausserhalb des
## eigenen Gebiets gelten nicht für ihn.
func _keep_king_home(list: Array, dest: Vector2) -> Array:
	var result: Array = []
	for u in list:
		if u.role == "king" and world.get_owner(world.world_to_cell(dest)) != u.kingdom.id:
			u.kingdom.notify("Der König verlässt sein Reich nicht.", "warning", u.position)
			continue
		result.append(u)
	return result


## Nur lebende Einheiten ausserhalb von Gebäuden
func _commandable(units: Array) -> Array:
	var list: Array = []
	for u in units:
		if is_instance_valid(u) and u is Unit and u.is_alive():
			list.append(u)
	return list


## Vor einem Befehl: Arbeit unterbrechen, Gebäude verlassen.
func _prepare(u: Unit) -> void:
	if u.can_work() and (u.command.is_empty() or u.command == "defend" or u.command == "flee"):
		work_system.suspend(u)
	elif u.inside != null:
		unit_system.set_inside(u, null)


## Formation: 0 = vorne (Nahkampf), 1 = Fernkampf, 2 = Heiler/Arbeiter
func _rank(u: Unit) -> int:
	if u.can_heal() or u.get_role() == "worker":
		return 2
	if float(u.type_def.get("range", 0.8)) >= 2.0:
		return 1
	return 0


func _max_radius(units: Array) -> float:
	var r := 0.0
	for u in units:
		r = maxf(r, u.get_radius())
	return r
