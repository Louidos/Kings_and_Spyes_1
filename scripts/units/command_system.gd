## CommandSystem
##
## Befehle an Einheiten: Bewegen (in Formation), Angriffsmarsch, Angriff auf
## ein Ziel, Halt und "Zur Arbeit". Arbeitende Einheiten unterbrechen dafür
## ihre Arbeit (WorkSystem.suspend); "Zur Arbeit" setzt sie fort.
## Verwaltet ausserdem die Armeen (Steuergruppen 1–9) jedes Reichs und ist die
## einzige Stelle, die Ankunft und Scheitern von Befehlen behandelt.
## Wird vom Spieler (SelectionController) und ab Phase 7 von der KI benutzt.
##
## Gruppenmarsch: Statt für jede Einheit einen langen Weg zu berechnen, läuft
## ein Anführer den Weg; die anderen folgen ihm mit ihrem Formationsabstand
## (kurze, gerade Wege) und biegen am Ende auf ihren Platz ein.
class_name CommandSystem
extends Node

## Steuergruppen eines Reichs haben sich geändert
signal armies_changed(kingdom: Kingdom)
## Ein Befehl ist beendet (Ziel erreicht: ok = true, kein Weg: ok = false)
signal command_finished(unit: Unit, command: String, ok: bool)

const FORMATIONS := ["block", "line"]
const FORMATION_NAMES := {"block": "Block", "line": "Linie"}

## Alle Befehle und ihre Bedeutung (eine Tabelle statt verstreuter Abfragen):
## engage    – sucht selbst Feinde in Sichtweite
## retaliate – wehrt sich, wenn angegriffen
## buildings – greift auch Gebäude an
## leash     – wie weit verfolgt wird: "none", "home" (Monster: bis zur Leine),
##             "guard" (nur ein Stück vom Posten), "chase" (begrenzt), "unlimited"
## on_arrive – nach Ankunft: "hold" (Posten halten; Bewohner arbeiten weiter),
##             "resume_work" (weiterarbeiten), "clear" (Befehl löschen), "" (nichts)
const COMMANDS := {
	"": {"engage": true, "retaliate": true, "buildings": false, "leash": "home", "on_arrive": "", "text": ""},
	"move": {"engage": false, "retaliate": false, "buildings": false, "leash": "none", "on_arrive": "hold", "text": "marschiert"},
	"attack_move": {"engage": true, "retaliate": true, "buildings": true, "leash": "chase", "on_arrive": "hold", "text": "marschiert kampfbereit"},
	"attack": {"engage": true, "retaliate": true, "buildings": true, "leash": "unlimited", "on_arrive": "", "text": "greift an"},
	"hold": {"engage": true, "retaliate": true, "buildings": false, "leash": "guard", "on_arrive": "", "text": "hält die Stellung"},
	"defend": {"engage": true, "retaliate": true, "buildings": false, "leash": "guard", "on_arrive": "", "text": "wehrt sich"},
	"flee": {"engage": false, "retaliate": false, "buildings": false, "leash": "none", "on_arrive": "resume_work", "text": "flieht zur Burg"},
	"return": {"engage": false, "retaliate": false, "buildings": false, "leash": "none", "on_arrive": "clear", "text": "kehrt heim"},
	# Held läuft in Reichweite einer Fähigkeit (HeroSystem wirkt sie dort, siehe Unit.cast_*)
	"cast": {"engage": false, "retaliate": false, "buildings": false, "leash": "none", "on_arrive": "hold", "text": "wirkt eine Fähigkeit"},
	# Bote (ab Phase 9 auch Karawane): reist zum Ziel, kämpft nie, danach Befehl gelöscht
	"travel": {"engage": false, "retaliate": false, "buildings": false, "leash": "none", "on_arrive": "clear", "text": "überbringt eine Nachricht"},
}

## Einheiten weiter als so viele Kacheln vom Gruppenmittelpunkt marschieren einzeln
const GROUP_RADIUS_TILES := 12.0
## Gruppenmarsch erst ab dieser Entfernung (darunter laufen alle direkt)
const MARCH_MIN_TILES := 10.0
## Folgende Einheiten passen ihr Ziel alle so viele Takte an
const FOLLOW_TICKS := 5
## Gruppenmarsch: ab so vielen Kacheln Rückstand wartet der Anführer (geht
## langsamer), bis alle wieder so nah sind; Tempo des Anführers dabei
const CATCH_UP_START := 8.0
const CATCH_UP_END := 4.0
const CATCH_UP_SPEED := 0.5

var game: Node
var world: WorldData
var unit_system: UnitSystem
var work_system: WorkSystem

var _spacing := 0.9
var _tick_count := 0
var _next_march_id := 1
## Gruppenmärsche: id -> {"leader": Unit, "members": Array, "command": String}
var _marches: Dictionary = {}


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	unit_system = game.unit_system
	work_system = game.work_system
	_spacing = float(DataDB.cmb("formation.spacing", 0.9))
	unit_system.arrived.connect(_on_arrived)
	unit_system.path_failed.connect(_on_path_failed)
	unit_system.unit_removed.connect(_on_unit_removed)
	GameClock.sim_tick.connect(_on_sim_tick)


static func flag(cmd: String, key: String) -> Variant:
	return COMMANDS.get(cmd, COMMANDS[""]).get(key)


static func get_command_text(cmd: String) -> String:
	return str(COMMANDS.get(cmd, COMMANDS[""]).get("text", ""))


static func get_formation_name(f: String) -> String:
	return str(FORMATION_NAMES.get(f, f))


## Kämpft diese Einheit auf Befehl? (Bewohner und Heiler laufen nur mit)
static func is_fighter(u: Unit) -> bool:
	return u.attack > 0.0 and u.joins_fights


# ---------------------------------------------------------------------------
# Befehle
# ---------------------------------------------------------------------------

## Marschbefehl zu pos. Mehrere Einheiten verteilen sich in der Formation
## (leer = Formation des Reichs). attack_move: unterwegs kämpfen.
func order_move(units: Array, pos: Vector2, attack_move: bool = false, formation: String = "") -> void:
	var list := _keep_king_home(_commandable(units), pos)
	if list.is_empty():
		return
	if not FORMATIONS.has(formation):
		formation = list[0].kingdom.formation
	var slots := formation_slots(list, pos, formation)
	var cmd := "attack_move" if attack_move else "move"
	for i in list.size():
		var u: Unit = list[i]
		_prepare(u)
		u.command = cmd
		u.command_pos = slots[i]
		u.target = null
	_start_march(list, slots, pos)


## Angriff auf ein bestimmtes Ziel (Unit oder Building). Bewohner und Heiler
## gehen nur mit.
func order_attack(units: Array, target: Object) -> void:
	if not is_instance_valid(target):
		return
	var list := _keep_king_home(_commandable(units), target.position)
	if list.is_empty():
		return
	var followers: Array = []
	for u in list:
		if not is_fighter(u):
			followers.append(u)
			continue
		_prepare(u)
		u.command = "attack"
		u.command_pos = u.position
		u.target = target
		u.repath_timer = 0.0
		u.think_timer = 0.0
	if not followers.is_empty():
		order_move(followers, target.position)


## Halt: stehen bleiben und den Platz verteidigen.
## Held läuft zu approach_pos, um eine Fähigkeit zu wirken. Was gewirkt wird,
## steht in u.cast_ability / cast_target_uid / cast_pos (setzt das HeroSystem);
## es wirkt sie, sobald der Held in Reichweite ist.
func order_cast(u: Unit, approach_pos: Vector2) -> void:
	_prepare(u)
	u.command = "cast"
	u.command_pos = approach_pos
	u.target = null
	unit_system.move_to(u, approach_pos)


## Eine Einheit aus allen Armeen nehmen (z. B. entlassener Held)
func remove_from_armies(k: Kingdom, uid: int) -> void:
	var changed := false
	for n in k.armies.keys():
		var uids: Array = k.armies[n]
		if uids.has(uid):
			uids.erase(uid)
			changed = true
			if uids.is_empty():
				k.armies.erase(n)
	if changed:
		armies_changed.emit(k)


func order_stop(units: Array) -> void:
	for u in _commandable(units):
		_prepare(u)
		u.command = "hold"
		u.command_pos = u.position
		u.target = null
		unit_system.stop(u)


## Befehl aufheben: Arbeiter arbeiten weiter, andere halten ihren Platz.
## Beschworene Einheiten ohne Beruf bleiben als Wache stehen.
func order_return_to_work(units: Array) -> void:
	for u in _commandable(units):
		_stop_following(u)
		if u.can_work() and (u.role == "worker" or u.job_id != "idle"):
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
func formation_slots(units: Array, dest: Vector2, formation: String = "block") -> Array:
	var n := units.size()
	var result: Array = []
	result.resize(n)
	if n == 1:
		result[0] = dest
		return result
	var centroid := _centroid(units)
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

	# Reihenfolge: Rang (vorne -> hinten), dann Lage in Marschrichtung
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = units[a].formation_rank
		var rb: int = units[b].formation_rank
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


# ---------------------------------------------------------------------------
# Steuergruppen (Armeen)
# ---------------------------------------------------------------------------

## Speichert die Einheiten als Armee n (1–9) des Reichs (ersetzt die alte).
func set_army(k: Kingdom, n: int, units: Array) -> void:
	var uids: Array = []
	for u in _commandable(units):
		if u.kingdom == k and u.role != "king":
			uids.append(u.uid)
	if uids.is_empty():
		k.armies.erase(n)
	else:
		k.armies[n] = uids
	armies_changed.emit(k)


func add_to_army(k: Kingdom, n: int, units: Array) -> void:
	var uids: Array = k.armies.get(n, [])
	for u in _commandable(units):
		if u.kingdom == k and u.role != "king" and not uids.has(u.uid):
			uids.append(u.uid)
	if uids.is_empty():
		return
	k.armies[n] = uids
	armies_changed.emit(k)


## Lebende Einheiten der Armee n
func get_army(k: Kingdom, n: int) -> Array:
	var list: Array = []
	for uid in k.armies.get(n, []):
		var u: Variant = game.find_by_uid(int(uid))
		if is_instance_valid(u) and u is Unit and u.is_alive():
			list.append(u)
	return list


## Nummer der ersten Armee, zu der die Einheit gehört (0 = keine)
func get_army_number(u: Unit) -> int:
	for n in u.kingdom.armies:
		if (u.kingdom.armies[n] as Array).has(u.uid):
			return int(n)
	return 0


# ---------------------------------------------------------------------------
# Ankunft und Scheitern
# ---------------------------------------------------------------------------

func _on_arrived(u: Unit) -> void:
	if is_instance_valid(u.target) and u.target != null:
		return  # Verfolgung: entscheidet der Kampftakt
	if u.follow_leader != null:
		return  # Zwischenschritt beim Folgen
	_finish(u, true)


func _on_path_failed(u: Unit) -> void:
	if is_instance_valid(u.target) and u.target != null:
		return  # Verfolgung: entscheidet der Kampftakt
	if u.follow_leader != null:
		_stop_following(u)
	_finish(u, false)


## Befehl am Ziel (oder gescheitert) abschliessen
func _finish(u: Unit, ok: bool) -> void:
	var cmd := u.command
	match str(flag(cmd, "on_arrive")):
		"hold":
			if u.role == "worker" and u.can_work():
				# Bewohner arbeiten nach dem Marsch weiter (mit "Halt" bleiben sie stehen)
				_resume_later(u, cmd)
			else:
				u.command = "hold"
				u.command_pos = u.position
		"resume_work":
			if u.can_work():
				_resume_later(u, cmd)
			elif u.role == "king" and cmd == "flee" and is_instance_valid(u.kingdom.castle):
				# Der verletzte König ruht in der Burg, bis er sich erholt hat (CombatSystem)
				unit_system.set_inside(u, u.kingdom.castle)
				u.command = "hold"
				u.kingdom.notify("Der König zieht sich in die Burg zurück.", "warning", u.position)
			else:
				u.command = "hold"
				u.command_pos = u.position
		"clear":
			u.command = ""
		_:
			return
	u.speed_cap = 0.0
	command_finished.emit(u, cmd, ok)


## Erst im nächsten Takt weiterarbeiten (das WorkSystem hat diese Ankunft
## bereits ignoriert, weil die Einheit noch einen Befehl hatte)
func _resume_later(u: Unit, expected_command: String) -> void:
	_resume_deferred.call_deferred(u, expected_command)


func _resume_deferred(u: Variant, expected_command: String) -> void:
	if is_instance_valid(u) and u.command == expected_command:
		work_system.resume(u)


# ---------------------------------------------------------------------------
# Gruppenmarsch
# ---------------------------------------------------------------------------

func _start_march(list: Array, slots: Array, dest: Vector2) -> void:
	var ts := float(world.tile_size)
	var centroid := _centroid(list)
	# Anführer: die Einheit nächst dem Mittelpunkt; weit entfernte laufen einzeln
	var leader_i := -1
	var best := INF
	var members: Array = []
	var slowest := INF
	var hero_i := -1
	for i in list.size():
		var u: Unit = list[i]
		var d := u.position.distance_to(centroid)
		if d > GROUP_RADIUS_TILES * ts:
			continue
		members.append(i)
		slowest = minf(slowest, u.speed)
		# Ein Held führt seine Armee an (er ist ihr General)
		if u.hero_id != 0 and hero_i < 0:
			hero_i = i
		# Heiler führen nicht (sie bleiben zum Heilen stehen)
		if d < best and not u.can_heal():
			best = d
			leader_i = i
	if hero_i >= 0:
		leader_i = hero_i
	if members.size() < 3 or leader_i < 0 or centroid.distance_to(dest) < MARCH_MIN_TILES * ts:
		for i in list.size():
			unit_system.move_to(list[i], slots[i])
		return
	var leader: Unit = list[leader_i]
	var march := {"leader": leader, "members": [], "command": leader.command, "order": leader.order_id,
			"slowest": slowest, "slow": false}
	leader.speed_cap = slowest
	unit_system.move_to(leader, slots[leader_i])
	for i in list.size():
		var u: Unit = list[i]
		if i == leader_i:
			continue
		if not members.has(i):
			unit_system.move_to(u, slots[i])
			continue
		u.follow_leader = leader
		u.follow_offset = slots[i] - slots[leader_i]
		u.speed_cap = slowest
		march["members"].append(u)
		unit_system.move_direct(u, leader.position + u.follow_offset, 12.0)
	_marches[_next_march_id] = march
	_next_march_id += 1


func _on_sim_tick(_dt: float) -> void:
	_tick_count += 1
	for id in _marches.keys():
		var march: Dictionary = _marches[id]
		var leader: Variant = march["leader"]
		var members: Array = march["members"]
		# Wer inzwischen einen anderen Befehl hat, gehört nicht mehr dazu
		for i in range(members.size() - 1, -1, -1):
			var m: Variant = members[i]
			if not is_instance_valid(m) or not m.is_alive() or m.follow_leader != leader:
				members.remove_at(i)
		if not is_instance_valid(leader) or not leader.is_alive():
			leader = _promote_leader(march)
		# Ende: Anführer am Ziel (Befehl gewechselt) oder hat einen neuen Befehl bekommen
		if leader == null or leader.command != march["command"] or leader.order_id != march["order"]:
			# Anführer ist am Ziel (oder hat einen neuen Befehl): alle auf ihre Plätze
			for m in members:
				_stop_following(m)
				if m.target == null:
					unit_system.move_to(m, m.command_pos)
			if leader != null:
				leader.speed_cap = 0.0
			_marches.erase(id)
			continue
		if members.is_empty():
			leader.speed_cap = 0.0
			_marches.erase(id)
			continue
		if _tick_count % FOLLOW_TICKS == 0:
			_pace_leader(march, leader, members)
		# Folgende passen ihr Ziel an (verteilt über mehrere Takte)
		var ahead: Vector2 = _leader_heading(leader) * leader.speed * world.tile_size * 0.5
		for m in members:
			if m.target != null or (m.uid + _tick_count) % FOLLOW_TICKS != 0:
				continue
			var goal: Vector2 = leader.position + m.follow_offset + ahead
			if m.position.distance_to(goal) > world.tile_size * 0.4 or not m.moving:
				unit_system.move_direct(m, goal, 12.0)


## Der Anführer ist gefallen: ein anderes Gruppenmitglied übernimmt.
func _promote_leader(march: Dictionary) -> Variant:
	var members: Array = march["members"]
	if members.is_empty():
		return null
	var new_leader: Unit = members.pop_front()
	_stop_following(new_leader)
	march["order"] = new_leader.order_id
	for m in members:
		m.follow_leader = new_leader
		m.follow_offset = m.command_pos - new_leader.command_pos
	march["leader"] = new_leader
	new_leader.speed_cap = float(march.get("slowest", 0.0)) if not members.is_empty() else 0.0
	unit_system.move_to(new_leader, new_leader.command_pos)
	return new_leader


## Aufholen: Folgende haben dasselbe Höchsttempo wie der Anführer und holen
## einen Rückstand (z. B. durch Wald, Hügel oder einen Kampf unterwegs) sonst nie
## auf. Fällt jemand mehr als CATCH_UP_START Kacheln zurück, geht der Anführer
## halb so schnell, bis alle wieder höchstens CATCH_UP_END Kacheln entfernt sind.
func _pace_leader(march: Dictionary, leader: Unit, members: Array) -> void:
	var ts := float(world.tile_size)
	var max_gap := 0.0
	for m in members:
		if m.target == null:
			max_gap = maxf(max_gap, m.position.distance_to(leader.position + m.follow_offset))
	var slow := bool(march.get("slow", false))
	if not slow and max_gap > CATCH_UP_START * ts:
		slow = true
	elif slow and max_gap < CATCH_UP_END * ts:
		slow = false
	march["slow"] = slow
	var slowest := float(march.get("slowest", leader.speed_cap))
	leader.speed_cap = slowest * (CATCH_UP_SPEED if slow else 1.0)


func _leader_heading(leader: Unit) -> Vector2:
	if leader.moving and leader.path_index < leader.path.size():
		var d: Vector2 = leader.path[leader.path_index] - leader.position
		if d.length() > 1.0:
			return d.normalized()
	return Vector2.ZERO


func _stop_following(u: Unit) -> void:
	u.follow_leader = null
	u.speed_cap = 0.0


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


## Nur lebende Einheiten
func _commandable(units: Array) -> Array:
	var list: Array = []
	for u in units:
		if is_instance_valid(u) and u is Unit and u.is_alive():
			list.append(u)
	return list


## Vor einem Befehl: Arbeit unterbrechen, Gebäude verlassen, Marsch beenden.
## order_id zählt jeden neuen Befehl (ein Gruppenmarsch endet, wenn sein
## Anführer einen neuen Befehl bekommt).
func _prepare(u: Unit) -> void:
	_stop_following(u)
	u.order_id += 1
	if u.can_work() and (u.command.is_empty() or u.command == "defend" or u.command == "flee"):
		work_system.suspend(u)
	elif u.inside != null:
		unit_system.set_inside(u, null)


func _centroid(units: Array) -> Vector2:
	var c := Vector2.ZERO
	for u in units:
		c += u.position
	return c / maxf(float(units.size()), 1.0)


func _max_radius(units: Array) -> float:
	var r := 0.0
	for u in units:
		r = maxf(r, u.get_radius())
	return r


func _on_unit_removed(u: Unit) -> void:
	# Gefallene Helden bleiben in ihren Armeen: wiederbelebt behalten sie ihre Nummer
	if u.hero_id != 0 and u.hp <= 0.0:
		return
	var k := u.kingdom
	var changed := false
	for n in k.armies.keys():
		var uids: Array = k.armies[n]
		if uids.has(u.uid):
			uids.erase(u.uid)
			changed = true
			if uids.is_empty():
				k.armies.erase(n)
	if changed:
		armies_changed.emit(k)
