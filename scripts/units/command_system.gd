## CommandSystem
##
## Befehle an Einheiten: Bewegen (in Formation), Angriffsmarsch, Angriff auf
## ein Ziel, Halt und "Zur Arbeit". Arbeitende Einheiten unterbrechen dafür
## ihre Arbeit (WorkSystem.suspend); "Zur Arbeit" setzt sie fort.
## Verwaltet ausserdem die Armeen (Steuergruppen 1–9) jedes Reichs und ist die
## einzige Stelle, die Ankunft und Scheitern von Befehlen behandelt.
## Wird vom Spieler (SelectionController, Armeefenster) und ab Phase 7 von der KI benutzt.
## Armeefenster: Sammeln an der Burg, Rückzug zur Burg (danach Erholung), Patrouille,
## Neuaufstellung in einer Formation (Block, Linie, Keil, Kreis), Haltung (aggressiv,
## verteidigend, passiv – das CombatSystem fragt stance_allows_engage/leash_for) und
## Armee auflösen.
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

const FORMATIONS := ["block", "line", "wedge", "circle"]
const FORMATION_NAMES := {"block": "Block", "line": "Linie", "wedge": "Keil", "circle": "Kreis"}

## Haltungen (Unit.stance): wie selbstständig eine Einheit kämpft.
## aggressive – sucht Feinde und verfolgt sie weit (auch vom Posten weg)
## defensive  – sucht Feinde in Sichtweite, kehrt nach kurzer Verfolgung auf den Posten zurück
## passive    – greift nie von selbst an, wehrt sich nicht und hilft nicht; nur die
##              ausdrücklichen Befehle "Angriff" und "Angreifend vorrücken" lassen sie kämpfen
const STANCES := ["aggressive", "defensive", "passive"]
const STANCE_NAMES := {"aggressive": "Aggressiv", "defensive": "Verteidigend", "passive": "Passiv"}
const DEFAULT_STANCE := "defensive"
## Erklärung je Haltung (Tooltips im Armee- und im Auswahlfenster)
const STANCE_TIPS := {"aggressive": "Sucht Feinde und verfolgt sie weit – auch vom Posten weg",
		"defensive": "Greift Feinde in Sichtweite an und kehrt nach kurzer Verfolgung auf den Posten zurück (Standard)",
		"passive": "Greift nie von selbst an und wehrt sich nicht – nur ausdrückliche Angriffsbefehle"}
## Aggressive Einheiten geben ein Ziel erst bei so viel mehr Abstand auf (Faktor auf die
## Standardgrenze im CombatSystem)
const AGGRESSIVE_CHASE_FACTOR := 1.5
## Sammelplatz: so viele Kacheln vor dem Rand der Burg
const RALLY_TILES := 3.0

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
	# Spion (Phase 7): schleicht zum Ziel, kämpft nie, danach Befehl gelöscht
	"infiltrate": {"engage": false, "retaliate": false, "buildings": false, "leash": "none", "on_arrive": "clear", "text": "schleicht sich ans Ziel"},
	# Spion am Ziel: bleibt, kämpft nie
	"spy": {"engage": false, "retaliate": false, "buildings": false, "leash": "none", "on_arrive": "", "text": "spioniert"},
	# Überläufer (Phase 8): läuft zum Ziel, kämpft nie, danach Befehl gelöscht (SatisfactionSystem übernimmt)
	"defect": {"engage": false, "retaliate": false, "buildings": false, "leash": "none", "on_arrive": "clear", "text": "läuft über"},
	# Flüchtlinge/Wanderer (Phase 8): gehen an den Gebietsrand und warten dort auf Antwort (EventSystem)
	"seek_refuge": {"engage": false, "retaliate": false, "buildings": false, "leash": "none", "on_arrive": "clear", "text": "bittet um Aufnahme"},
	# Karawane (Phase 9): zieht mit Waren zum Ziel, kämpft nie, danach Befehl gelöscht
	"haul": {"engage": false, "retaliate": false, "buildings": false, "leash": "none", "on_arrive": "clear", "text": "zieht mit Waren"},
	# Armeefenster: Patrouille zwischen command_pos und patrol_from (kämpft unterwegs, kehrt am Ziel um)
	"patrol": {"engage": true, "retaliate": true, "buildings": false, "leash": "chase", "on_arrive": "patrol", "text": "patrouilliert"},
	# Rückzug zur Burg: läuft ohne zu kämpfen, danach "rest"
	"retreat": {"engage": false, "retaliate": false, "buildings": false, "leash": "none", "on_arrive": "rest", "text": "zieht sich zur Burg zurück"},
	# An der Burg erholen (schnellere Heilung, siehe CombatSystem); verteidigt sich wie "hold"
	"rest": {"engage": true, "retaliate": true, "buildings": false, "leash": "guard", "on_arrive": "", "text": "erholt sich an der Burg"},
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


static func get_stance_name(stance: String) -> String:
	return str(STANCE_NAMES.get(stance, stance))


## Darf u wegen seiner Haltung von selbst kämpfen (Ziele suchen, sich wehren, helfen)?
## Ausdrückliche Angriffsbefehle gelten immer.
static func stance_allows_engage(u: Unit) -> bool:
	return u.stance != "passive" or u.command == "attack" or u.command == "attack_move"


## Leine im Kampf: die des Befehls (COMMANDS.leash); aggressive Einheiten verfolgen
## auch vom Posten weg ("guard" wird "chase")
static func leash_for(u: Unit) -> String:
	var leash := str(flag(u.command, "leash"))
	if leash == "guard" and u.stance == "aggressive":
		return "chase"
	return leash


## Kämpft diese Einheit auf Befehl? (Bewohner und Heiler laufen nur mit)
static func is_fighter(u: Unit) -> bool:
	return u.attack > 0.0 and u.joins_fights


## Gehört die Einheit zu den Truppen (Kämpfer, Schützen, Heiler, Belagerungswaffen,
## beschworene Einheiten, Helden)? Bewohner, König, Spione, Boten und Karawanen nicht.
static func is_warrior(u: Unit) -> bool:
	if u.hero_id != 0:
		return true
	return (u.role == "combat" or u.role == "support") and bool(u.type_def.get("commandable", true))


## Lebende Truppen des Reichs (is_warrior), z. B. für "Alle Krieger auswählen"
func get_warriors(k: Kingdom) -> Array:
	var list: Array = []
	for u in k.units:
		if is_instance_valid(u) and u.is_alive() and is_warrior(u):
			list.append(u)
	return list


# ---------------------------------------------------------------------------
# Befehle
# ---------------------------------------------------------------------------

## Marschbefehl zu pos. Mehrere Einheiten verteilen sich in der Formation
## (leer = Formation des Reichs). attack_move: unterwegs kämpfen.
func order_move(units: Array, pos: Vector2, attack_move: bool = false, formation: String = "") -> void:
	_order_group(units, pos, "attack_move" if attack_move else "move", formation)


## Gruppenbefehl mit Ziel: Formation, Befehl cmd, Gruppenmarsch
func _order_group(units: Array, pos: Vector2, cmd: String, formation: String) -> void:
	var list := _keep_king_home(_commandable(units), pos)
	if list.is_empty():
		return
	if not FORMATIONS.has(formation):
		formation = list[0].kingdom.formation
	var slots := formation_slots(list, pos, formation)
	for i in list.size():
		var u: Unit = list[i]
		_prepare(u)
		u.command = cmd
		u.command_pos = slots[i]
		u.target = null
	_start_march(list, slots, pos)


## Sammeln an der Burg: Marsch in Formation zum Sammelplatz vor der Burg (danach Halt).
func order_gather(units: Array) -> void:
	var list := _commandable(units)
	if list.is_empty():
		return
	var k: Kingdom = list[0].kingdom
	if not is_instance_valid(k.castle):
		return
	order_move(list, castle_rally_point(k, _centroid(list)))


## Rückzug zur Burg: ohne zu kämpfen zum Sammelplatz, dort erholen sie sich schneller
## (Befehl "rest", CombatSystem). Ohne Burg: Halt.
func order_retreat(units: Array) -> void:
	var list := _commandable(units)
	if list.is_empty():
		return
	var k: Kingdom = list[0].kingdom
	if not is_instance_valid(k.castle):
		order_stop(list)
		return
	_order_group(list, castle_rally_point(k, _centroid(list)), "retreat", "")


## Patrouille zwischen dem jetzigen Ort der Gruppe und pos (hin und her, kämpft
## unterwegs wie beim angreifenden Vorrücken). Jede Einheit läuft einzeln zu ihrem
## Platz in der Formation am jeweiligen Wendepunkt.
func order_patrol(units: Array, pos: Vector2, formation: String = "") -> void:
	var list := _keep_king_home(_commandable(units), pos)
	if list.is_empty():
		return
	if not FORMATIONS.has(formation):
		formation = list[0].kingdom.formation
	var start := _centroid(list)
	var slots := formation_slots(list, pos, formation)
	for i in list.size():
		var u: Unit = list[i]
		_prepare(u)
		u.command = "patrol"
		u.patrol_from = start + (slots[i] - pos)
		u.command_pos = slots[i]
		u.target = null
		unit_system.move_to(u, slots[i])


## Gruppe an ihrem Ort in einer Formation neu aufstellen (Mitte der Gruppe)
func order_reform(units: Array, formation: String) -> void:
	var list := _commandable(units)
	if list.is_empty():
		return
	order_move(list, _centroid(list), false, formation)


## Haltung setzen (STANCES). Passive Einheiten lassen selbst gesuchte Kämpfe fallen.
func set_stance(units: Array, stance: String) -> void:
	if not STANCES.has(stance):
		return
	for u in _commandable(units):
		u.stance = stance
		if stance == "passive" and u.command != "attack" and u.command != "attack_move" and u.target != null:
			u.target = null
			u.regroup_pending = true


## Sammelplatz vor der Burg des Reichs, auf der Seite zu from (freie Kachel)
func castle_rally_point(k: Kingdom, from: Vector2) -> Vector2:
	var castle := k.castle
	if not is_instance_valid(castle):
		return from
	var center := castle.get_center()
	var dir := from - center
	dir = Vector2.DOWN if dir.length() < 1.0 else dir.normalized()
	var p := center + dir * (castle.get_radius() + RALLY_TILES * world.tile_size)
	var c: Vector2i = game.nav.nearest_free(world.world_to_cell(p), 4)
	return world.cell_to_world(c) if c.x >= 0 else p


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
		# Rammböcke greifen keine Einheiten an: sie gehen nur mit
		if not is_fighter(u) or (u.target_mode == "buildings" and target is Unit):
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


## Einzelreise ohne Kampf (Spione, Boten, ab Phase 9 Karawanen): Befehl cmd ("travel",
## "infiltrate", "return", "haul"), Ziel dest. command_finished(u, cmd, ok) meldet die Ankunft.
func order_travel(u: Unit, dest: Vector2, cmd: String = "travel") -> void:
	if not is_instance_valid(u) or not u.is_alive():
		return
	_prepare(u)
	u.command = cmd
	u.command_pos = dest
	u.target = null
	unit_system.move_to(u, dest)


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


## Halt: stehen bleiben und den Platz verteidigen.
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
	# Keil: Reihe r hat r + 1 Plätze (Spitze vorne)
	if formation == "wedge":
		rows = 0
		while rows * (rows + 1) < 2 * n:
			rows += 1
	var spacing := _spacing * world.tile_size + _max_radius(units) * 0.6
	if formation == "circle":
		return _circle_slots(units, dest, centroid, forward, spacing)

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
		if formation == "wedge":
			start = (row * (row + 1)) >> 1
			count = mini(row + 1, n - start)
		var row_units: Array = order.slice(start, start + count)
		row_units.sort_custom(func(a: int, b: int) -> bool:
			return (units[a].position - centroid).dot(right) < (units[b].position - centroid).dot(right))
		var y := ((rows - 1) * 0.5 - row) * spacing
		for col in count:
			var x := (col - (count - 1) * 0.5) * spacing
			result[row_units[col]] = dest + right * x + forward * y
	return result


## Kreis: Ringe um dest; vordere Ränge (Nahkämpfer) aussen, Fernkämpfer und Heiler
## innen. Innerhalb eines Rings nach dem Winkel um den Gruppenmittelpunkt verteilt.
func _circle_slots(units: Array, dest: Vector2, centroid: Vector2, forward: Vector2, spacing: float) -> Array:
	var n := units.size()
	var result: Array = []
	result.resize(n)
	# Plätze je Ring von innen (1, dann etwa 2πr), der äusserste nimmt den Rest
	var counts: Array = []
	var left := n
	while left > 0:
		var ring := counts.size()
		var count := mini(1 if ring == 0 else floori(TAU * ring), left)
		counts.append(count)
		left -= count
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool:
		return units[a].formation_rank < units[b].formation_rank)
	var index := 0
	for ring in range(counts.size() - 1, -1, -1):
		var count: int = counts[ring]
		var ring_units: Array = order.slice(index, index + count)
		ring_units.sort_custom(func(a: int, b: int) -> bool:
			return fposmod(forward.angle_to(units[a].position - centroid), TAU) \
					< fposmod(forward.angle_to(units[b].position - centroid), TAU))
		for i in count:
			var offset := forward.rotated(TAU * float(i) / float(count)) * float(ring) * spacing
			result[ring_units[i]] = dest + offset
		index += count
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


## Armee n auflösen (die Einheiten bleiben, wo sie sind)
func dissolve_army(k: Kingdom, n: int) -> void:
	if k.armies.has(n):
		k.armies.erase(n)
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
	# Weg versperrt (Phase 9): Kämpfer brechen durch die Mauer, die den Weg versperrt
	if u.path_fail != "" and (u.command == "attack_move" or u.command == "attack" \
			or (u.command == "move" and is_fighter(u))):
		var siege: SiegeSystem = game.siege_system
		var wall := siege.find_breach_target(u)
		if wall != null:
			if u.command == "move":
				u.command = "attack_move"
				siege.notify_blocked(u, wall)
			u.target = wall
			u.repath_timer = 0.0
			return
		siege.notify_no_way(u)
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
		"rest":
			if u.role == "worker" and u.can_work():
				# Bewohner (mit dem Armeefenster zurückgezogen) arbeiten an der Burg weiter
				_resume_later(u, cmd)
			else:
				u.command = "rest"
				u.command_pos = u.position
		"patrol":
			if ok:
				# Wendepunkt: zum anderen Ende zurück
				var back := u.patrol_from
				u.patrol_from = u.command_pos
				u.command_pos = back
				u.speed_cap = 0.0
				unit_system.move_to(u, back)
				command_finished.emit(u, cmd, ok)
				return
			u.command = "hold"
			u.command_pos = u.position
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


## Nur lebende Einheiten, die Befehle annehmen (Karawanen nicht, Phase 9)
func _commandable(units: Array) -> Array:
	var list: Array = []
	for u in units:
		if is_instance_valid(u) and u is Unit and u.is_alive() and bool(u.type_def.get("commandable", true)):
			list.append(u)
	return list


## Vor einem Befehl: Arbeit unterbrechen, Gebäude verlassen, Marsch beenden.
## order_id zählt jeden neuen Befehl (ein Gruppenmarsch endet, wenn sein
## Anführer einen neuen Befehl bekommt).
func _prepare(u: Unit) -> void:
	_stop_following(u)
	u.order_id += 1
	u.breach_tries = 0
	u.resume_target_uid = 0
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


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"next_march_id": _next_march_id, "tick_count": _tick_count}


func from_dict(d: Dictionary) -> void:
	_next_march_id = int(d.get("next_march_id", 1))
	_tick_count = int(d.get("tick_count", 0))


## Gruppenmärsche sind Laufzeit: Einheiten mit Marschbefehl, die nicht (mehr) laufen und
## noch nicht am Ziel sind, gehen einzeln weiter (Ziele bleiben erhalten)
func rebuild_runtime() -> void:
	_marches.clear()
	var ts := float(world.tile_size)
	for u in unit_system.units:
		u.follow_leader = null
		u.speed_cap = 0.0
		if u.command != "move" and u.command != "attack_move" and u.command != "patrol" and u.command != "retreat":
			continue
		if u.moving or u.path_pending or u.inside != null:
			continue
		if u.position.distance_to(u.command_pos) > ts:
			unit_system.move_to(u, u.command_pos)
