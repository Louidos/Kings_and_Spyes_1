## UnitSystem
##
## Verwaltet alle Einheiten aller Reiche: erzeugen, entfernen, laufen lassen.
## - Bewegung läuft einmal pro Frame für alle Einheiten in einer Schleife
##   (statt _process in jeder Einheit) und nutzt die Spielzeit (GameClock):
##   steht bei Pause still, läuft bei 3x dreimal so schnell.
## - Wegberechnungen kommen in eine Warteschlange und werden mit Zeitbudget
##   abgearbeitet, damit viele gleichzeitige Aufträge nicht ruckeln.
## - remove_unit ist der einzige Weg, eine Einheit zu entfernen.
class_name UnitSystem
extends Node

signal unit_spawned(unit: Unit)
signal unit_removed(unit: Unit)
## Eine Einheit hat das Ende ihres Weges erreicht.
signal arrived(unit: Unit)
## Für eine Einheit wurde kein Weg gefunden.
signal path_failed(unit: Unit)
## Eine Einheit hat den Besitzer gewechselt (Dorfmilizen bei der Aufnahme; ab Phase 8 Überläufer)
signal unit_transferred(unit: Unit, from_kingdom: Kingdom, to_kingdom: Kingdom)

## Höchstens so viele Wegberechnungen bzw. so viel Zeit (µs) pro Frame
const MAX_PATHS_PER_FRAME := 8
const PATH_BUDGET_USEC := 2000
## Lange Wege werden in Abschnitten dieser Länge (Kacheln) berechnet, damit
## keine einzelne Berechnung das Spiel ruckeln lässt.
const LEG_TILES := 48.0
## So nah am Abschnittsende wird schon der nächste Abschnitt angefordert
const LEG_EARLY_TILES := 6.0

var game: Node
var world: WorldData
## Alle Einheiten aller Reiche
var units: Array = []

var _path_queue: Array = []


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	game.building_system.building_placed.connect(_on_building_placed)
	game.building_system.building_removed.connect(_on_building_removed)


## uid > 0: diese Nummer wiederverwenden (wiederbelebte Helden bleiben so in
## ihren Armeen). init(u) läuft vor dem Einfügen und vor unit_spawned (z. B.
## Heldenwerte setzen), damit alle Empfänger die fertige Einheit sehen.
func spawn_unit(kingdom: Kingdom, type_id: String, pos: Vector2, uid: int = 0,
		init: Callable = Callable()) -> Unit:
	var def := DataDB.get_unit_type(type_id)
	if def.is_empty():
		push_error("Unbekannter Einheitentyp: %s" % type_id)
		return null
	var u := Unit.new()
	u.setup(def, kingdom, uid if uid > 0 else game.next_uid())
	u.position = pos
	if init.is_valid():
		init.call(u)
	game.unit_layer.add_child(u)
	units.append(u)
	game.register_entity(u)
	kingdom.modifiers_changed.connect(u.refresh_stats)
	kingdom.units.append(u)
	kingdom.population_changed.emit()
	unit_spawned.emit(u)
	return u


## Spielstand laden (Phase 10): Einheit aus Unit.to_dict wiederherstellen (gleiche uid).
## Verweise (Ziel, Gebäude, Arbeitsplatz) und Weg setzt SaveGame im zweiten Durchgang.
## null bei unbekanntem Typ oder Reich.
func restore_unit(d: Dictionary) -> Unit:
	var kingdom: Kingdom = game.get_kingdom(int(d.get("kingdom_id", 0)))
	var type_id := str(d.get("type_id", ""))
	if kingdom == null or DataDB.get_unit_type(type_id).is_empty():
		return null
	var init := func(nu: Unit) -> void:
		nu.hero_id = int(d.get("hero_id", 0))
		nu.custom_name = str(d.get("custom_name", ""))
		nu.effects = (d.get("effects", []) as Array).duplicate(true)
		nu.expires_at = float(d.get("expires_at", -1.0))
		for prop in Unit.SAVE_OPTIONAL:
			if d.has(prop) and nu.get(prop) != null:
				nu.set(prop, d[prop])
	var u := spawn_unit(kingdom, type_id, d.get("pos", Vector2.ZERO), int(d.get("uid", 0)), init)
	if u == null:
		return null
	u.command = str(d.get("command", ""))
	u.command_pos = d.get("command_pos", u.position)
	u.order_id = int(d.get("order_id", 0))
	u.attack_cooldown = float(d.get("attack_cooldown", 0.0))
	u.last_damaged_at = float(d.get("last_damaged_at", -1000.0))
	u.home_uid = int(d.get("home_uid", 0))
	u.has_home = bool(d.get("has_home", false))
	u.home_pos = d.get("home_pos", Vector2.ZERO)
	u.dormant = bool(d.get("dormant", false))
	u.regroup_pending = bool(d.get("regroup_pending", false))
	u.timer = float(d.get("timer", 0.0))
	u.cast_ability = str(d.get("cast_ability", ""))
	u.cast_target_uid = int(d.get("cast_target_uid", 0))
	u.cast_pos = d.get("cast_pos", Vector2.ZERO)
	u.job_id = str(d.get("job_id", "idle"))
	u.carry_res = str(d.get("carry_res", ""))
	u.carry_amount = float(d.get("carry_amount", 0.0))
	u.work_acc = float(d.get("work_acc", 0.0))
	u.state = int(d.get("state", Unit.State.IDLE))
	return u


## Spielstand laden: gespeicherten Weg fortsetzen (motion aus Unit.to_dict)
func restore_motion(u: Unit, m: Dictionary) -> void:
	u.path = m.get("path", PackedVector2Array())
	u.path_index = clampi(int(m.get("i", 0)), 0, u.path.size())
	u.moving = bool(m.get("moving", false)) and u.path_index < u.path.size()
	u.path_target = m.get("target", u.position)
	u.path_final = m.get("final", Vector2.ZERO)
	u.has_path_final = bool(m.get("has_final", false))
	u.path_pending = false
	if not u.path.is_empty():
		u.path_bounds = _bounds_of(u.path)
	if bool(m.get("pending", false)):
		_request(u, u.path_target, true)


## Der einzige Weg, eine Einheit zu entfernen (später auch Tod, Überlaufen).
func remove_unit(u: Unit) -> void:
	if not is_instance_valid(u) or not units.has(u):
		return
	units.erase(u)
	u.kingdom.units.erase(u)
	if u.kingdom.modifiers_changed.is_connected(u.refresh_stats):
		u.kingdom.modifiers_changed.disconnect(u.refresh_stats)
	game.unregister_entity(u)
	u.kingdom.population_changed.emit()
	unit_removed.emit(u)
	u.queue_free()


## Besitzerwechsel einer Einheit (Dorfmilizen bei der Aufnahme; ab Phase 8 Überläufer).
## Nicht für Helden und Könige. Die Einheit hält danach ihren Platz.
func transfer_unit(u: Unit, to: Kingdom) -> void:
	if not is_instance_valid(u) or not u.is_alive() or to == null or not units.has(u):
		return
	var from := u.kingdom
	if from == to or u.hero_id != 0 or u.role == "king":
		return
	if u.inside != null:
		set_inside(u, null)
	if u.can_work():
		# Beruf und Arbeitsplatz gehören zum alten Reich
		game.work_system.set_unit_job(u, "idle")
		game.work_system.suspend(u)
	game.command_system.remove_from_armies(from, u.uid)
	u.follow_leader = null
	u.speed_cap = 0.0
	u.target = null
	if from.modifiers_changed.is_connected(u.refresh_stats):
		from.modifiers_changed.disconnect(u.refresh_stats)
	from.units.erase(u)
	u.kingdom = to
	to.units.append(u)
	to.modifiers_changed.connect(u.refresh_stats)
	u.refresh_look()
	u.refresh_stats()
	u.update_stealth_look()
	u.command = "hold"
	u.command_pos = u.position
	stop(u)
	game.combat_system.mark_index_dirty()
	from.population_changed.emit()
	to.population_changed.emit()
	unit_transferred.emit(u, from, to)


## Schickt eine Einheit zu einer Weltposition. Der Weg wird in der
## Warteschlange berechnet; bis dahin steht die Einheit – ausser mit
## keep_path: dann läuft sie auf dem alten Weg weiter, bis der neue fertig ist.
## Weite Ziele werden in Abschnitten angesteuert (siehe LEG_TILES).
func move_to(u: Unit, target: Vector2, keep_path: bool = false) -> void:
	var leg := target
	u.has_path_final = false
	if u.position.distance_to(target) > LEG_TILES * world.tile_size:
		u.has_path_final = true
		u.path_final = target
		leg = _leg_point(u.position, target, u.kingdom.id)
	_request(u, leg, keep_path)


func _request(u: Unit, target: Vector2, keep_path: bool) -> void:
	if not keep_path or not u.moving:
		u.path = PackedVector2Array()
		u.path_index = 0
		u.moving = false
	u.path_target = target
	if not u.path_pending:
		u.path_pending = true
		_path_queue.append(u)


## Zwischenziel LEG_TILES Kacheln in Richtung to (nächste freie Kachel). Liegt es in
## einem Mauerring, der weder mit Start noch Ziel verbunden ist (für Reich kid), werden
## kürzere Abstände probiert; ohne freie Kachel gilt das Endziel.
func _leg_point(from: Vector2, to: Vector2, kid: int = 0) -> Vector2:
	var nav: NavGrid = game.nav
	var dir := (to - from).normalized()
	var a := nav.nearest_free(world.world_to_cell(from), 3)
	var b := nav.nearest_free(world.world_to_cell(to), 3)
	for tiles in [LEG_TILES, 40.0, 32.0, 24.0, 16.0, 8.0]:
		var c := nav.nearest_free(world.world_to_cell(from + dir * float(tiles) * world.tile_size), 6)
		if c.x < 0:
			continue
		if a.x < 0 or b.x < 0 or nav.leg_ok(c, a, b, kid):
			return world.cell_to_world(c)
	return to


## Nächster Abschnitt eines langen Weges (vom Ende des aktuellen aus)
func _request_next_leg(u: Unit) -> void:
	var from: Vector2 = u.path[u.path.size() - 1] if not u.path.is_empty() else u.position
	if from.distance_to(u.path_final) <= LEG_TILES * world.tile_size:
		u.has_path_final = false
		_request(u, u.path_final, true)
	else:
		_request(u, _leg_point(from, u.path_final, u.kingdom.id), true)


## Kurze Strecke ohne Wegsuche: läuft geradeaus, wenn unterwegs nichts
## blockiert (spart Wegberechnungen beim Verfolgen und Umherstreifen),
## sonst normal über move_to.
func move_direct(u: Unit, target: Vector2, max_tiles: float = 4.0) -> void:
	var dist := u.position.distance_to(target)
	if dist > max_tiles * world.tile_size or not can_walk_direct(u.position, target):
		move_to(u, target)
		return
	u.path = PackedVector2Array([target])
	u.path_index = 0
	u.path_target = target
	u.path_pending = false
	u.has_path_final = false
	u.path_bounds = Rect2i(world.world_to_cell(u.position), Vector2i.ZERO).expand(world.world_to_cell(target))
	u.moving = dist > 0.5
	if not u.moving:
		# Schon am Ziel: trotzdem "angekommen" melden (verzögert, wie nach einer Bewegung),
		# sonst warten Empfänger (Arbeit, Befehle) vergeblich
		u.path = PackedVector2Array()
		_emit_arrived_deferred.call_deferred(u)


func _emit_arrived_deferred(u: Unit) -> void:
	if is_instance_valid(u) and u.is_alive() and not u.moving and not u.path_pending:
		arrived.emit(u)


## Führt die gerade Linie von a nach b an keiner blockierten Kachel vorbei? Kein
## Durchschlüpfen zwischen diagonal stossenden Hindernissen (z. B. Mauerecken).
func can_walk_direct(a: Vector2, b: Vector2) -> bool:
	var steps := ceili(a.distance_to(b) / (world.tile_size * 0.4))
	var prev := world.world_to_cell(a)
	var nav: NavGrid = game.nav
	for i in range(1, steps + 1):
		var c := world.world_to_cell(a.lerp(b, float(i) / steps))
		if not world.in_bounds(c) or nav.is_solid(c):
			return false
		if c.x != prev.x and c.y != prev.y and nav.is_solid(Vector2i(c.x, prev.y)) and nav.is_solid(Vector2i(prev.x, c.y)):
			return false
		prev = c
	return true


func stop(u: Unit) -> void:
	u.path = PackedVector2Array()
	u.path_index = 0
	u.moving = false
	u.path_pending = false
	u.has_path_final = false


## Einheit eines Reichs (oder beliebigen, wenn kingdom null) nahe einer Position.
## Einheiten in Gebäuden werden nicht gefunden.
func get_unit_at(pos: Vector2, radius: float, kingdom: Kingdom = null) -> Unit:
	var best: Unit = null
	var best_d := radius * radius
	for u in units:
		if u.inside != null or not u.is_alive() or (kingdom != null and u.kingdom != kingdom):
			continue
		var d: float = u.position.distance_squared_to(pos)
		if d <= best_d:
			best_d = d
			best = u
	return best


## Einheit betritt ein Gebäude (unsichtbar) oder verlässt es (b = null).
func set_inside(u: Unit, b: Building) -> void:
	if u.inside == b:
		return
	if b == null and is_instance_valid(u.inside):
		u.position = u.inside.get_approach_point(u.position)
	u.inside = b
	u.visible = b == null


func _process(_delta: float) -> void:
	if world == null:
		return
	_process_path_queue()
	var dt := GameClock.frame_delta
	if dt <= 0.0:
		return
	var ts := float(world.tile_size)
	var arrivals: Array = []
	var blocked: Array = []
	var leg_early := LEG_EARLY_TILES * ts
	var nav: NavGrid = game.nav
	# Tor-Prüfung beim Wegpunktwechsel (Beziehung geändert, Tor verriegelt)
	var gate_check := not nav.gates.is_empty()
	for u in units:
		if not u.moving:
			continue
		# Langer Weg: nächsten Abschnitt rechtzeitig anfordern (ohne anzuhalten)
		if u.has_path_final and not u.path_pending \
				and u.position.distance_to(u.path[u.path.size() - 1]) < leg_early:
			_request_next_leg(u)
		# Wegbudget dieses Frames; kann über mehrere Wegpunkte reichen
		var unit_speed: float = u.speed if u.speed_cap <= 0.0 else minf(u.speed, u.speed_cap)
		var base_speed: float = unit_speed * ts
		var budget := dt
		var gate_cell := Vector2i(-1, -1)
		while budget > 0.0 and u.path_index < u.path.size():
			var cost := world.get_move_cost(world.world_to_cell(u.position))
			var speed := base_speed / clampf(cost, 0.1, 50.0)
			var target: Vector2 = u.path[u.path_index]
			var dist: float = u.position.distance_to(target)
			var step := speed * budget
			if step >= dist:
				u.position = target
				budget -= dist / speed
				u.path_index += 1
				if gate_check and u.path_index < u.path.size():
					var nc := world.world_to_cell(u.path[u.path_index])
					if nav.gates.has(nc) and not nav.gate_passable(nc, u.kingdom.id):
						gate_cell = nc
						break
			else:
				u.position += (target - u.position) / dist * step
				budget = 0.0
		if gate_cell.x >= 0:
			blocked.append([u, gate_cell])
			continue
		if u.path_index >= u.path.size():
			u.moving = false
			if u.has_path_final or u.path_pending:
				# Abschnittsende (oder neuer Weg unterwegs): weiter, sobald er berechnet
				# ist – noch nicht als angekommen melden
				if not u.path_pending:
					_request_next_leg(u)
				continue
			arrivals.append(u)
	# Erst nach der Schleife melden: Empfänger dürfen Einheiten verändern
	for entry in blocked:
		var bu: Unit = entry[0]
		if not is_instance_valid(bu):
			continue
		stop(bu)
		bu.path_fail = "gate"
		bu.path_fail_cell = entry[1]
		bu.path_fail_region = 0
		path_failed.emit(bu)
	for u in arrivals:
		if is_instance_valid(u):
			arrived.emit(u)


## Ein neues Gebäude blockiert Kacheln: Einheiten, deren Weg hindurchführt,
## planen neu; Einheiten, die darauf stehen, treten zur Seite.
func _on_building_placed(b: Building) -> void:
	if not b.blocks_movement():
		return
	var fp := b.get_footprint()
	var near := fp.grow(1)
	for u in units:
		if u.inside != null:
			continue
		if fp.has_point(world.world_to_cell(u.position)):
			u.position = b.get_approach_point(u.position)
		# Nur Wege prüfen, deren Bereich das Gebäude überhaupt berührt
		if not u.moving or not u.path_bounds.grow(1).intersects(near):
			continue
		for i in range(u.path_index, u.path.size()):
			if fp.has_point(world.world_to_cell(u.path[i])):
				move_to(u, u.path_final if u.has_path_final else u.path[u.path.size() - 1])
				break


## Ein Gebäude verschwindet: wer darin ist, kommt heraus.
func _on_building_removed(b: Building) -> void:
	for u in units:
		if u.inside == b:
			set_inside(u, null)


func _process_path_queue() -> void:
	var start := Time.get_ticks_usec()
	var done := 0
	while not _path_queue.is_empty() and done < MAX_PATHS_PER_FRAME:
		if Time.get_ticks_usec() - start > PATH_BUDGET_USEC:
			break
		var u = _path_queue.pop_front()  # untypisiert: kann bereits gelöscht sein
		if not is_instance_valid(u) or not u.path_pending:
			continue
		u.path_pending = false
		done += 1
		var nav: NavGrid = game.nav
		var p: PackedVector2Array = nav.find_path(world, u.position, u.path_target, u.kingdom.id)
		if p.is_empty():
			u.has_path_final = false
			u.moving = false
			u.path_fail = nav.last_fail
			u.path_fail_region = nav.last_fail_region
			u.path_fail_cell = nav.last_fail_cell
			path_failed.emit(u)
			continue
		u.path_fail = ""
		u.path = p
		u.path_index = 0
		u.moving = true
		u.path_bounds = _bounds_of(p)


func _bounds_of(p: PackedVector2Array) -> Rect2i:
	var r := Rect2i(world.world_to_cell(p[0]), Vector2i.ZERO)
	for pt in p:
		r = r.expand(world.world_to_cell(pt))
	return r


# ---------------------------------------------------------------------------
# Speichern (Phase 10): Einheiten speichert SaveGame selbst, Wege neu berechnet
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {}


func from_dict(_d: Dictionary) -> void:
	pass


## Wartende Wegberechnungen ohne gültige Einheit verwerfen
func rebuild_runtime() -> void:
	var keep: Array = []
	for u in _path_queue:
		if is_instance_valid(u) and u.path_pending and not keep.has(u):
			keep.append(u)
	_path_queue = keep
