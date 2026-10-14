## WorkSystem
##
## Berufe und Arbeits-KI aller arbeitsfähigen Einheiten (Bewohner, später
## auch beschworene Einheiten). Für jede Einheit läuft ein einfacher Ablauf:
##   Sammler:      Vorkommen suchen -> hinlaufen -> sammeln -> abliefern -> von vorn
##   Bauarbeiter:  Baustelle suchen -> hinlaufen -> bauen -> nächste Baustelle
##   Gebäudearbeiter (Bauer, Manawirker): zum Arbeitsplatz laufen und dort arbeiten
##   Unbeschäftigte: schlendern um die Burg
## Entscheidungen fallen im festen Simulationstakt (GameClock.sim_tick) und
## bei der Ankunft am Ziel – nie jeden Frame. Pro Takt wird nur eine begrenzte
## Zahl Einheiten neu "nachdenken" gelassen, damit nichts ruckelt.
class_name WorkSystem
extends Node

## Anzahl oder Verteilung der Berufe eines Reichs hat sich geändert.
signal jobs_changed(kingdom: Kingdom)

## Höchstens so viele Annahmestellen werden bei der Zielsuche verglichen
const MAX_DROPOFF_CANDIDATES := 8
## Gewicht des einmaligen Anmarschs bei der Zielwahl. Der dauerhafte Arbeitsweg
## (Vorkommen <-> Annahmestelle, hin und zurück) zählt voll – so nutzen
## Sammler eine Hütte direkt am Vorkommen statt der weit entfernten Burg.
const APPROACH_WEIGHT := 0.25

var game: Node
var world: WorldData
var unit_system: UnitSystem
var building_system: BuildingSystem

## Vorkommen-Kachel -> Anzahl Sammler, die dort arbeiten (oder unterwegs sind).
## Nur ein Zwischenspeicher: lässt sich aus Unit.target_cell neu aufbauen.
var _reservations: Dictionary = {}
## Baustelle (Building oder Vector2i) -> Anzahl Bauarbeiter (Zwischenspeicher)
var _site_workers: Dictionary = {}
## Vorkommen-Kachel -> NavGrid.solid_version, als sie unerreichbar war
## (eingebaut). Gilt, bis sich an den Gebäuden etwas ändert.
var _unreachable: Dictionary = {}
## Zählt Änderungen an Gebäuden/Reservierungen (zusammen mit
## WorldData.deposit_version: "hat sich seit der letzten Suche etwas getan?")
var _local_version := 0
## Reich, für das gerade gesucht wird (_spiral_find/_cell_ok): fremdes Gebiet
## (Dörfer, andere Reiche) ist tabu, 0 = nicht prüfen
var _search_kingdom_id := 0
var _retry_seconds := 3.0
var _wander_radius := 4
## Höchstens so viele zeitgesteuerte Entscheidungen pro Simulationstakt (alle Reiche
## zusammen; economy.json work.max_thinks_per_tick)
var _max_thinks := 20
var _tick_count := 0
var _rng := RandomNumberGenerator.new()


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	unit_system = game.unit_system
	building_system = game.building_system
	_retry_seconds = float(DataDB.eco("work.retry_seconds", 3.0))
	_wander_radius = int(DataDB.eco("work.idle_wander_radius", 4))
	_max_thinks = maxi(int(DataDB.eco("work.max_thinks_per_tick", 20)), 1)
	_rng.seed = hash(world.world_seed + 31337)
	GameClock.sim_tick.connect(_on_sim_tick)
	unit_system.arrived.connect(_on_arrived)
	unit_system.path_failed.connect(_on_path_failed)
	unit_system.unit_removed.connect(_on_unit_removed)
	building_system.building_placed.connect(_on_building_placed)
	building_system.building_completed.connect(func(_b: Building) -> void: _local_version += 1)
	building_system.building_removed.connect(on_building_removed)
	building_system.roads_changed.connect(_wake_all_builders)
	# Gebiet gewechselt (Dorf aufgenommen, neues Gebäude): Sammelplätze neu suchen
	game.territory.changed.connect(func(_kid: int, _bbox: Rect2i, _dirty: Rect2i) -> void: _local_version += 1)


# ---------------------------------------------------------------------------
# Berufe verteilen (für UI und KI-Reiche)
# ---------------------------------------------------------------------------

## Frei für einen Beruf: kann arbeiten, ist unbeschäftigt und hat keinen Befehl.
func is_available(u: Unit) -> bool:
	return u.can_work() and u.job_id == "idle" and u.command.is_empty()


## Gibt einer Einheit einen neuen Beruf. Bei Gebäude-Berufen wird ein freier
## Arbeitsplatz gesucht; gibt es keinen, bleibt alles unverändert (false).
func set_unit_job(u: Unit, job_id: String, workplace: Building = null) -> bool:
	if not is_instance_valid(u):
		return false
	var job := DataDB.get_job(job_id)
	if job.is_empty() or not get_job_block_reason(u, job_id).is_empty():
		return false
	if job.get("type") == "building":
		if workplace == null:
			workplace = _find_free_workplace(u.kingdom, job, u.position)
		if workplace == null or not workplace.has_free_slot():
			return false
	# Ein neuer Beruf hebt einen Befehl auf (Einheit kehrt zur Arbeit zurück)
	if job_id != "idle" and not u.command.is_empty():
		u.command = ""
		u.target = null
		u.follow_leader = null
		u.speed_cap = 0.0
	_release(u)
	u.job_id = job_id
	if workplace != null:
		workplace.workers.append(u)
		u.work_building = workplace
	u.state = Unit.State.IDLE
	u.timer = 0.0
	_think(u)
	jobs_changed.emit(u.kingdom)
	return true


## Unterbricht die Arbeit, weil die Einheit einen Befehl bekommt (Kampf,
## Marsch, Flucht). Der Beruf und ein Arbeitsplatz im Gebäude bleiben ihr,
## Getragenes behält sie. resume() setzt die Arbeit fort.
func suspend(u: Unit) -> void:
	if not is_instance_valid(u) or not u.can_work():
		return
	_release_reservation(u)
	_release_site(u)
	if u.inside != null:
		unit_system.set_inside(u, null)
	u.on_arrive = ""
	u.activity = ""
	u.problem = ""
	u.state = Unit.State.IDLE
	u.failed_search_version = -1
	unit_system.stop(u)


## Befehl aufheben und weiterarbeiten (Arbeiter) bzw. stehen bleiben.
func resume(u: Unit) -> void:
	if not is_instance_valid(u):
		return
	u.command = ""
	u.target = null
	if not u.can_work():
		return
	if u.inside == null:
		unit_system.stop(u)
	u.on_arrive = ""
	u.state = Unit.State.IDLE
	u.timer = 0.0


## Warum kann die Einheit diesen Beruf nicht annehmen? "" = sie kann.
## Beschworene Einheiten brauchen zum Arbeiten Wohnraum wie Bewohner.
func get_job_block_reason(u: Unit, job_id: String) -> String:
	if job_id == "idle":
		return ""
	if not u.can_work():
		return "Diese Einheit kann nicht arbeiten"
	if u.role != "worker" and u.job_id == "idle" and u.kingdom.get_population() >= u.kingdom.get_housing():
		return "Kein Wohnraum frei – baue Wohnhäuser"
	return ""


## Nimmt einen freien Unbeschäftigten (nahe der Burg) und gibt ihm den Beruf.
func assign_job(kingdom: Kingdom, job_id: String) -> bool:
	if not has_free_slot(kingdom, job_id):
		return false
	var near := kingdom.castle.get_center() if is_instance_valid(kingdom.castle) else Vector2.ZERO
	var u := _pick_unit(kingdom, "idle", near)
	return u != null and set_unit_job(u, job_id)


## Macht eine Einheit mit diesem Beruf unbeschäftigt (bevorzugt eine, die nichts trägt).
func unassign_job(kingdom: Kingdom, job_id: String) -> bool:
	if job_id == "idle":
		return false
	var u := _pick_unit(kingdom, job_id, Vector2.ZERO, true)
	return u != null and set_unit_job(u, "idle")


func get_job_count(kingdom: Kingdom, job_id: String) -> int:
	var n := 0
	for u in kingdom.units:
		if u.job_id == job_id:
			n += 1
	return n


## Anzahl unbeschäftigter Bewohner ohne Befehl (beschworene Einheiten zählen
## nicht – sie bekommen Berufe nur einzeln im Auswahlfenster)
func get_idle_count(kingdom: Kingdom) -> int:
	var n := 0
	for u in kingdom.units:
		if u.role == "worker" and is_available(u):
			n += 1
	return n


## Anzahl Arbeitsplätze eines Gebäude-Berufs (fertige Gebäude), -1 = unbegrenzt
func get_job_capacity(kingdom: Kingdom, job_id: String) -> int:
	var job := DataDB.get_job(job_id)
	if job.get("type") != "building":
		return -1
	var slots := 0
	for b in kingdom.buildings:
		if b.constructed and b.def.get("job", "") == job_id:
			slots += b.get_worker_slots()
	return slots


## Gibt es noch freie Arbeitsplätze für diesen Beruf?
func has_free_slot(kingdom: Kingdom, job_id: String) -> bool:
	var cap := get_job_capacity(kingdom, job_id)
	return cap < 0 or get_job_count(kingdom, job_id) < cap


## Erstes Problem einer Einheit mit diesem Beruf ("" = keines)
func get_job_problem(kingdom: Kingdom, job_id: String) -> String:
	for u in kingdom.units:
		if u.job_id == job_id and not u.problem.is_empty():
			return u.problem
	return ""


## Einen Unbeschäftigten diesem Gebäude als Arbeiter zuteilen.
func assign_worker_to_building(b: Building) -> bool:
	if not b.has_free_slot():
		return false
	var u := _pick_unit(b.kingdom, "idle", b.get_center())
	return u != null and set_unit_job(u, str(b.def.get("job", "")), b)


## Einen Arbeiter dieses Gebäudes abziehen (wird unbeschäftigt).
func remove_worker_from_building(b: Building) -> bool:
	if b.workers.is_empty():
		return false
	return set_unit_job(b.workers.back(), "idle")


## Anzahl Einheiten, die gerade an dieses Gebäude liefern wollen
func get_delivering_count(b: Building) -> int:
	var n := 0
	for u in b.kingdom.units:
		if u.dropoff == b and u.state != Unit.State.WAITING:
			n += 1
	return n


## Ein Gebäude wurde entfernt: Arbeiter freistellen, Verweise lösen.
func on_building_removed(b: Building) -> void:
	_local_version += 1
	for u in b.kingdom.units.duplicate():
		if u.work_building == b:
			set_unit_job(u, "idle")
		elif u.target_building == b:
			_release_site(u)
			_think(u)
		elif u.dropoff == b:
			u.dropoff = null
			if u.on_arrive == "dropoff":
				_go_dropoff(u)
	_site_workers.erase(b)


## Arbeitstempo: bei Hungersnot langsamer (ausser für Nahrungsberufe)
func work_factor(kingdom: Kingdom, job: Dictionary) -> float:
	if kingdom.starving and not job.get("food_job", false):
		return float(DataDB.eco("starvation.work_factor", 0.5))
	return 1.0


# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	_tick_count += 1
	var thinks := 0
	for u in unit_system.units:
		if not u.can_work() or not u.command.is_empty():
			continue
		match u.state:
			Unit.State.GATHERING:
				_tick_gather(u, dt)
			Unit.State.BUILDING:
				_tick_build(u, dt)
			Unit.State.IDLE, Unit.State.WAITING:
				u.timer -= dt
				if u.timer <= 0.0 and thinks < _max_thinks:
					thinks += 1
					_think(u)
	if _tick_count % 10 == 0:
		_refresh_problem_flags()


## Entscheidet, was eine Einheit als Nächstes tut.
func _think(u: Unit) -> void:
	var job := DataDB.get_job(u.job_id)
	match str(job.get("type", "idle")):
		"builder":
			_find_build_work(u, job)
		"gather":
			if u.carry_amount >= _carry_capacity(u):
				_go_dropoff(u)
			else:
				_find_gather_work(u, job)
		"building":
			_go_to_workplace(u)
		_:
			_wander(u)


func _on_arrived(u: Unit) -> void:
	if not u.can_work() or not u.command.is_empty() or u.follow_leader != null:
		return
	var action := u.on_arrive
	u.on_arrive = ""
	match action:
		"gather":
			var job := DataDB.get_job(u.job_id)
			if world.is_gatherable(u.target_cell, job.get("deposit_indices", PackedInt32Array())):
				u.state = Unit.State.GATHERING
				u.activity = str(job.get("activity", "arbeitet"))
			else:
				_release_reservation(u)
				_think(u)
		"dropoff":
			_deliver(u)
		"build":
			if _site_valid(u):
				u.state = Unit.State.BUILDING
				u.activity = "%s: %s" % [DataDB.get_job(u.job_id).get("activity", "baut"), _site_name(u)]
			else:
				_release_site(u)
				_think(u)
		"work":
			if is_instance_valid(u.work_building) and u.work_building.constructed:
				u.state = Unit.State.WORKING
				u.activity = "%s (%s)" % [DataDB.get_job(u.job_id).get("activity", "arbeitet"), u.work_building.get_display_name()]
				unit_system.set_inside(u, u.work_building)
			else:
				_think(u)
		_:
			u.state = Unit.State.IDLE
			u.timer = _rng.randf_range(5.0, 10.0)


func _on_path_failed(u: Unit) -> void:
	if not u.can_work() or not u.command.is_empty():
		return
	if u.on_arrive == "gather" and u.target_cell.x >= 0:
		_unreachable[u.target_cell] = game.nav.solid_version
	u.on_arrive = ""
	_release_reservation(u)
	_release_site(u)
	_wait(u, "Kein Weg zum Ziel", DataDB.get_job(u.job_id))


func _on_unit_removed(u: Unit) -> void:
	# Getragenes geht mit der Einheit verloren (nicht ins Lager buchen)
	u.carry_amount = 0.0
	_release(u)


func _on_building_placed(b: Building) -> void:
	_wake_builders(b.kingdom)


# ---------------------------------------------------------------------------
# Sammeln
# ---------------------------------------------------------------------------

func _find_gather_work(u: Unit, job: Dictionary) -> void:
	var res_id := str(job.get("resource", ""))
	var indices: PackedInt32Array = job.get("deposit_indices", PackedInt32Array())
	var mask: PackedByteArray = job.get("deposit_mask", PackedByteArray())
	# Alle Annahmestellen sind Kandidaten (nicht nur die nächsten): eine Hütte
	# am Wald soll auch genutzt werden, wenn der Sammler gerade an der Burg steht
	var candidates := _dropoffs_by_distance(u.kingdom, res_id, u.position)
	if candidates.is_empty():
		_wait(u, "Keine Annahmestelle für %s" % DataDB.get_resource(res_id).get("name", res_id), job)
		return

	var best_cell := Vector2i(-1, -1)
	var best_dropoff: Building = null
	var best_score := INF
	# Bisheriges Vorkommen weiter nutzen, solange es etwas hergibt (und nicht in fremdem Gebiet liegt)
	if u.target_cell.x >= 0 and world.is_gatherable(u.target_cell, indices) \
			and not _is_foreign(u.target_cell, u.kingdom.id):
		var cw := world.cell_to_world(u.target_cell)
		for d in candidates:
			if _in_reach(d, u.target_cell, 1):
				var score: float = cw.distance_to(d.get_center()) / (1.0 + d.get_gather_bonus())
				if score < best_score:
					best_score = score
					best_dropoff = d
		if best_dropoff != null:
			best_cell = u.target_cell
	if best_dropoff == null:
		_release_reservation(u)
		# Hat sich seit der letzten erfolglosen Suche nichts geändert, gar nicht erst suchen
		if u.failed_search_version == _version():
			_wait(u, u.problem if not u.problem.is_empty() else str(job.get("hint", "")), job)
			return
		# Neues Ziel: Arbeitsweg (hin und zurück) plus etwas Anmarsch, geteilt
		# durch den Bonus der Annahmestelle. Die nächsten Annahmestellen zuerst;
		# weiter entfernte nur, solange noch nichts gefunden wurde.
		_search_kingdom_id = u.kingdom.id
		for n in candidates.size():
			if n >= MAX_DROPOFF_CANDIDATES and best_dropoff != null:
				break
			var d: Building = candidates[n]
			var cell := _spiral_find(world.world_to_cell(d.get_center()), d.get_gather_radius(), mask)
			if cell.x < 0:
				continue
			var cw := world.cell_to_world(cell)
			var score: float = (2.0 * cw.distance_to(d.get_center()) + APPROACH_WEIGHT * u.position.distance_to(cw)) \
					/ (1.0 + d.get_gather_bonus())
			if score < best_score:
				best_score = score
				best_cell = cell
				best_dropoff = d
		_search_kingdom_id = 0
		if best_dropoff == null:
			u.failed_search_version = _version()
			_wait(u, str(job.get("hint", "Nichts zu tun")), job)
			return
		_reserve(u, best_cell)

	u.failed_search_version = -1
	u.dropoff = best_dropoff
	u.problem = ""
	u.state = Unit.State.MOVING
	u.on_arrive = "gather"
	u.activity = "geht zur Arbeit"
	var offset := Vector2(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-14.0, 14.0))
	unit_system.move_to(u, world.cell_to_world(best_cell) + offset)


func _tick_gather(u: Unit, dt: float) -> void:
	var job := DataDB.get_job(u.job_id)
	var indices: PackedInt32Array = job.get("deposit_indices", PackedInt32Array())
	var capacity := _carry_capacity(u)
	var res_id := str(job.get("resource", ""))
	var bonus := u.dropoff.get_gather_bonus() if is_instance_valid(u.dropoff) else 0.0
	var mult: float = u.kingdom.mod("gather") * u.kingdom.mod("gather." + res_id) * work_factor(u.kingdom, job) \
			* game.magic_system.get_production_factor(u.kingdom, u.position, res_id)
	u.work_acc += float(job.get("gather_rate", 1.0)) * (1.0 + bonus) * mult * dt
	while u.work_acc >= 1.0 and u.carry_amount < capacity:
		u.work_acc -= 1.0
		var got := world.harvest(u.target_cell, 1)
		if got <= 0:
			break
		if u.carry_res != res_id:
			u.carry_res = res_id
		u.carry_amount += got
		u.queue_redraw()
	if u.carry_amount >= capacity:
		u.work_acc = 0.0
		_go_dropoff(u)
	elif not world.is_gatherable(u.target_cell, indices):
		# Vorkommen erschöpft: halb voll -> abliefern, sonst gleich weitersuchen
		_release_reservation(u)
		u.work_acc = 0.0
		if u.carry_amount >= capacity * 0.5:
			_go_dropoff(u)
		else:
			_find_gather_work(u, job)


## Zur Annahmestelle laufen: bevorzugt die bei der Zielwahl gewählte (deren
## Bonus beim Sammeln galt), sonst die nächste (bei Gleichstand mit mehr Bonus).
func _go_dropoff(u: Unit) -> void:
	if u.carry_amount < 1.0:
		_think(u)
		return
	if is_instance_valid(u.dropoff) and u.dropoff.accepts(u.carry_res):
		_walk_to_dropoff(u, u.dropoff)
		return
	var candidates := _dropoffs_by_distance(u.kingdom, u.carry_res, u.position)
	if candidates.is_empty():
		_wait(u, "Keine Annahmestelle für %s" % DataDB.get_resource(u.carry_res).get("name", u.carry_res),
				DataDB.get_job(u.job_id))
		return
	var target: Building = candidates[0]
	var best_d := u.position.distance_to(target.get_center())
	for d in candidates:
		var dist: float = u.position.distance_to(d.get_center())
		if dist < best_d - 1.0 or (absf(dist - best_d) <= 1.0 and d.get_gather_bonus() > target.get_gather_bonus()):
			target = d
			best_d = dist
	_walk_to_dropoff(u, target)


func _walk_to_dropoff(u: Unit, target: Building) -> void:
	u.dropoff = target
	u.problem = ""
	u.state = Unit.State.MOVING
	u.on_arrive = "dropoff"
	u.activity = "bringt %s zu: %s" % [DataDB.get_resource(u.carry_res).get("name", u.carry_res), target.get_display_name()]
	unit_system.move_to(u, target.get_approach_point(u.position))


func _deliver(u: Unit) -> void:
	if not is_instance_valid(u.dropoff) or not u.dropoff.accepts(u.carry_res):
		_go_dropoff(u)
		return
	if u.carry_amount >= 1.0:
		u.kingdom.add_resource(u.carry_res, floorf(u.carry_amount))
	u.carry_amount = 0.0
	u.carry_res = ""
	u.state = Unit.State.IDLE
	_think(u)


# ---------------------------------------------------------------------------
# Bauen (Gebäude-Baustellen und Strassen werden getrennt geführt)
# ---------------------------------------------------------------------------

func _find_build_work(u: Unit, job: Dictionary) -> void:
	_release_site(u)
	var max_per_site := int(job.get("max_per_site", 4))
	var best_building: Building = null
	var best_road := Vector2i(-1, -1)
	var best_d := INF
	var any_site := false
	for b in building_system.get_building_sites(u.kingdom):
		any_site = true
		if int(_site_workers.get(b, 0)) >= max_per_site:
			continue
		var d: float = u.position.distance_squared_to(b.get_center())
		if d < best_d:
			best_d = d
			best_building = b
	for c in building_system.get_road_sites(u.kingdom):
		any_site = true
		if int(_site_workers.get(c, 0)) >= 1:
			continue
		var d: float = u.position.distance_squared_to(world.cell_to_world(c))
		if d < best_d:
			best_d = d
			best_building = null
			best_road = c
	if best_building == null and best_road.x < 0:
		u.problem = ""
		u.activity = "alle Baustellen besetzt" if any_site else "wartet auf Baustellen"
		_wander(u, false)
		return
	var target: Vector2
	if best_building != null:
		u.target_building = best_building
		_site_workers[best_building] = int(_site_workers.get(best_building, 0)) + 1
		target = best_building.get_approach_point(u.position)
	else:
		u.target_road = best_road
		_site_workers[best_road] = int(_site_workers.get(best_road, 0)) + 1
		target = world.cell_to_world(best_road)
	u.problem = ""
	u.state = Unit.State.MOVING
	u.on_arrive = "build"
	u.activity = "geht zur Baustelle: %s" % _site_name(u)
	unit_system.move_to(u, target)


func _tick_build(u: Unit, dt: float) -> void:
	if not _site_valid(u):
		_release_site(u)
		_think(u)
		return
	var job := DataDB.get_job(u.job_id)
	var amount := float(job.get("work_rate", 1.0)) * u.kingdom.mod("build") * work_factor(u.kingdom, job) * dt
	var finished := false
	if u.target_road.x >= 0:
		finished = building_system.add_road_work(u.target_road, amount)
	else:
		finished = u.target_building.add_work(amount)
	if finished:
		_release_site(u)
		_think(u)


func _site_valid(u: Unit) -> bool:
	if u.target_road.x >= 0:
		return building_system.is_road_site(u.target_road)
	var b := u.target_building
	return b != null and is_instance_valid(b) and not b.constructed and b.is_inside_tree()


func _site_name(u: Unit) -> String:
	if u.target_road.x >= 0:
		return "Strasse"
	return u.target_building.get_display_name() if is_instance_valid(u.target_building) else "?"


## Bauarbeiter ohne Baustelle sofort nach neuer Arbeit suchen lassen.
func _wake_builders(kingdom: Kingdom) -> void:
	for u in kingdom.units:
		if u.job_id == "builder" and u.target_building == null and u.target_road.x < 0 and u.command.is_empty():
			_think(u)


func _wake_all_builders() -> void:
	for k in game.kingdoms:
		_wake_builders(k)


# ---------------------------------------------------------------------------
# Arbeitsplatz, Schlendern, Warten
# ---------------------------------------------------------------------------

func _go_to_workplace(u: Unit) -> void:
	var b := u.work_building
	if not is_instance_valid(b) or not b.constructed:
		set_unit_job(u, "idle")
		return
	u.problem = ""
	u.state = Unit.State.MOVING
	u.on_arrive = "work"
	u.activity = "geht zur Arbeit: %s" % b.get_display_name()
	unit_system.move_to(u, b.get_approach_point(u.position))


## Zu einem zufälligen Punkt nahe der Burg schlendern.
func _wander(u: Unit, set_activity: bool = true) -> void:
	u.state = Unit.State.MOVING
	u.on_arrive = "wander"
	if set_activity:
		u.problem = ""
		u.activity = "ruht sich aus"
	var castle := u.kingdom.castle
	var center := castle.get_center() if is_instance_valid(castle) else u.position
	var r := float(_wander_radius * world.tile_size)
	var target := center + Vector2(_rng.randf_range(-r, r), _rng.randf_range(-r, r))
	# Nicht mitten in die Burg laufen
	if is_instance_valid(castle) and castle.get_footprint().has_point(world.world_to_cell(target)):
		target = castle.get_approach_point(target)
	unit_system.move_to(u, target)


## Nichts zu tun: kurz warten (leicht zufällig versetzt) und es dann erneut
## versuchen. Das Problem wird dem Spieler einmal gemeldet (pro Beruf), bis es
## behoben ist; danach sieht man es in der Arbeitsverteilung.
func _wait(u: Unit, problem: String, job: Dictionary) -> void:
	unit_system.stop(u)
	u.state = Unit.State.WAITING
	u.timer = _retry_seconds * _rng.randf_range(0.7, 1.3)
	u.problem = problem
	u.activity = "wartet"
	var key := "problem:" + u.job_id
	if not problem.is_empty() and not u.kingdom.flags.get(key, false):
		u.kingdom.flags[key] = true
		u.kingdom.notify("%s: %s" % [job.get("name", u.job_id), problem], "warning", u.position)


## Meldungs-Merker zurücksetzen, sobald kein Arbeiter des Berufs mehr ein Problem hat.
func _refresh_problem_flags() -> void:
	for k in game.kingdoms:
		for key in k.flags.keys():
			if str(key).begins_with("problem:") and get_job_problem(k, str(key).substr(8)).is_empty():
				k.flags.erase(key)


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

## Löst alle Bindungen einer Einheit (Reservierung, Baustelle, Arbeitsplatz)
## und liefert Getragenes ab, damit beim Berufswechsel nichts verloren geht.
func _release(u: Unit) -> void:
	_release_reservation(u)
	_release_site(u)
	if is_instance_valid(u.work_building):
		u.work_building.workers.erase(u)
	if u.inside != null:
		unit_system.set_inside(u, null)
	u.work_building = null
	u.dropoff = null
	if u.carry_amount >= 1.0 and not u.carry_res.is_empty():
		u.kingdom.add_resource(u.carry_res, floorf(u.carry_amount))
	u.carry_amount = 0.0
	u.carry_res = ""
	u.work_acc = 0.0
	u.problem = ""
	u.activity = ""
	u.on_arrive = ""
	u.failed_search_version = -1
	unit_system.stop(u)


## Aktueller Stand von Vorkommen, Gebäuden, Wegen und Reservierungen
func _version() -> int:
	return (world.deposit_version * 100003 + _local_version) * 31 + game.nav.solid_version


func _reserve(u: Unit, cell: Vector2i) -> void:
	u.target_cell = cell
	_reservations[cell] = int(_reservations.get(cell, 0)) + 1


func _release_reservation(u: Unit) -> void:
	if u.target_cell.x < 0:
		return
	var n := int(_reservations.get(u.target_cell, 0)) - 1
	if n <= 0:
		_reservations.erase(u.target_cell)
	else:
		_reservations[u.target_cell] = n
	u.target_cell = Vector2i(-1, -1)
	_local_version += 1


func _release_site(u: Unit) -> void:
	var key: Variant = null
	if u.target_road.x >= 0:
		key = u.target_road
	elif u.target_building != null:
		key = u.target_building
	u.target_road = Vector2i(-1, -1)
	u.target_building = null
	if key == null:
		return
	var n := int(_site_workers.get(key, 0)) - 1
	if n <= 0:
		_site_workers.erase(key)
	else:
		_site_workers[key] = n


## Sucht ringförmig um center die nächste sammelbare, nicht voll besetzte
## Kachel. Liest die Kartenarrays direkt (schnell); mask ist die Berufs-Maske.
func _spiral_find(center: Vector2i, radius: int, mask: PackedByteArray) -> Vector2i:
	if mask.is_empty():
		return Vector2i(-1, -1)
	if _cell_ok(center, mask):
		return center
	for r in range(1, radius + 1):
		for i in range(-r, r + 1):
			var top := Vector2i(center.x + i, center.y - r)
			if _cell_ok(top, mask):
				return top
			var bottom := Vector2i(center.x + i, center.y + r)
			if _cell_ok(bottom, mask):
				return bottom
		for i in range(-r + 1, r):
			var left := Vector2i(center.x - r, center.y + i)
			if _cell_ok(left, mask):
				return left
			var right := Vector2i(center.x + r, center.y + i)
			if _cell_ok(right, mask):
				return right
	return Vector2i(-1, -1)


func _cell_ok(c: Vector2i, mask: PackedByteArray) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= world.width or c.y >= world.height:
		return false
	var i := c.y * world.width + c.x
	var t := world.deposit_type[i]
	if mask[t] == 0 or world.deposit_amount[i] == 0 or world.regrowing.has(c):
		return false
	# Nicht bei Monsterhöhlen sammeln (bis das Lager besiegt ist)
	if not world.danger.is_empty() and world.danger[i] > 0:
		return false
	# Nicht im Gebiet eines anderen Reichs (z. B. eines neutralen Dorfs)
	if _search_kingdom_id != 0 and world.territory[i] != 0 and world.territory[i] != _search_kingdom_id:
		return false
	if _unreachable.has(c):
		if int(_unreachable[c]) == game.nav.solid_version:
			return false
		_unreachable.erase(c)
	var max_g: int = DataDB.deposits[t - 1]["max_gatherers"]
	return int(_reservations.get(c, 0)) < max_g


## Gehört die Kachel einem anderen Reich als kingdom_id?
func _is_foreign(c: Vector2i, kingdom_id: int) -> bool:
	var owner_id := world.get_owner(c)
	return owner_id != 0 and owner_id != kingdom_id


## Liegt die Kachel im Sammelradius der Annahmestelle (plus Toleranz)?
func _in_reach(d: Building, cell: Vector2i, tolerance: int) -> bool:
	var center := world.world_to_cell(d.get_center())
	var r := d.get_gather_radius() + tolerance
	return absi(cell.x - center.x) <= r and absi(cell.y - center.y) <= r


## Fertige Annahmestellen für eine Ressource, die nächsten zuerst
func _dropoffs_by_distance(kingdom: Kingdom, res_id: String, pos: Vector2) -> Array:
	var list := building_system.get_dropoffs(kingdom, res_id)
	list.sort_custom(func(a: Building, b: Building) -> bool:
		return a.get_center().distance_squared_to(pos) < b.get_center().distance_squared_to(pos))
	return list


func _find_free_workplace(kingdom: Kingdom, job: Dictionary, pos: Vector2) -> Building:
	var best: Building = null
	var best_d := INF
	for b in kingdom.buildings:
		if b.def.get("job", "") != job.get("id") or not b.has_free_slot():
			continue
		var d: float = b.get_center().distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = b
	return best


## Wählt eine Einheit mit dem Beruf, die pos am nächsten ist. Bei "idle" nur
## Einheiten ohne Befehl (Armeen werden nie zur Arbeit abgezogen).
func _pick_unit(kingdom: Kingdom, job_id: String, pos: Vector2, prefer_empty_handed: bool = false) -> Unit:
	var best: Unit = null
	var best_score := INF
	for u in kingdom.units:
		if u.job_id != job_id or not u.can_work() or not u.command.is_empty():
			continue
		# Armeen werden nie über die Arbeitsverteilung eingezogen
		if job_id == "idle" and u.role != "worker":
			continue
		var score: float = u.position.distance_squared_to(pos)
		if prefer_empty_handed and u.carry_amount >= 1.0:
			score += 1.0e12
		if score < best_score:
			best_score = score
			best = u
	return best


func _carry_capacity(u: Unit) -> float:
	return maxf(float(u.type_def.get("carry", 10)), 1.0)
