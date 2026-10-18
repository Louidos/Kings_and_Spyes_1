## VillageResidents
##
## Sichtbare Bewohner der neutralen Dörfer (Teil des VillageSystem, diplomacy.json
## village.residents). Reine Darstellung und Leben – keine Wirtschaft: die Produktion des
## Dorfs (VillageSystem.get_production) bleibt unverändert, getragene Waren landen nirgends.
## Tagesablauf je Bewohner: Ware des Volks wählen (gewichtet nach produces) → zum Arbeitsort
## gehen (Vorkommen im Dorfumkreis, Feld an einer Hütte oder das Dorfzentrum) → dort einige
## Sekunden arbeiten (Werkzeug und Text des Berufs aus jobs.json) → Ware sichtbar ins
## Dorfzentrum tragen → kurz ruhen → von vorn. Nachts schlafen sie in den Hütten, bei Alarm
## fliehen sie ins Dorfzentrum und kommen erst nach dem Alarm wieder heraus. Sie kämpfen nie
## (Befehl COMMAND: weder angreifen noch wehren). Wer einen Bewohner angreift, greift das Dorf
## an (Kampfsignal kingdom_attacked wie bei der Miliz).
##
## Zustand im Dorf-Datensatz (wird mit ihm gespeichert): "residents" (Array von
## {"uid", "phase", "task", "spot", "until", "home_uid"}), "residents_seeded" (erste Bewohner
## erschienen; fehlt bei Spielständen vor 1.3 – dann erscheinen sie im ersten Takt nach dem
## Laden), "resident_timer" (Ersatz), "resident_lost" (gefallene, noch nicht ersetzte Bewohner).
## Laufzeit: _spots (Vorkommen je Dorf und Ware, alle SPOT_REFRESH Sekunden neu gesucht).
class_name VillageResidents
extends RefCounted

## Befehl der Bewohner (CommandSystem.COMMANDS): kämpft nie, wehrt sich nicht
const COMMAND := "village_life"
## Vorkommen im Dorfumkreis so lange zwischenspeichern (Spielsekunden)
const SPOT_REFRESH := 120.0
## Länger unterwegs als so viele Sekunden: Weg gilt als gescheitert, neues Ziel
const WALK_TIMEOUT := 60.0

var vs: VillageSystem
var game: Node
var world: WorldData
var _ts := 64.0
var _rng := RandomNumberGenerator.new()
## Dorf-id -> {"t": Spielzeit, "cells": {Ware: Array[Vector2i]}}
var _spots: Dictionary = {}


func setup(p_vs: VillageSystem) -> void:
	vs = p_vs
	game = vs.game
	world = game.world
	_ts = float(world.tile_size)
	_rng.seed = hash(world.world_seed + 4711)


static func cfg(key: String, default: Variant) -> Variant:
	return DataDB.diplo("village.residents." + key, default)


## Ist die Einheit ein Dorfbewohner (units.json tier "resident")?
static func is_resident(u: Unit) -> bool:
	return u != null and u.tier == "resident"


## Soll-Anzahl sichtbarer Bewohner: je population_per_resident Einwohner einer, höchstens max_visible
static func visible_target(rec: Dictionary) -> int:
	var pop := int(rec.get("population", 0))
	if pop <= 0:
		return 0
	var per := maxf(float(cfg("population_per_resident", 4)), 1.0)
	return clampi(ceili(float(pop) / per), 1, maxi(int(cfg("max_visible", 6)), 0))


## Felder ergänzen (neue Dörfer und Spielstände vor den Bewohnern)
static func ensure_fields(rec: Dictionary) -> void:
	if not rec.has("residents"):
		rec["residents"] = []
	if not rec.has("residents_seeded"):
		rec["residents_seeded"] = false
	if not rec.has("resident_timer"):
		rec["resident_timer"] = 0.0
	if not rec.has("resident_lost"):
		rec["resident_lost"] = 0


# ---------------------------------------------------------------------------
# Erscheinen und Verschwinden
# ---------------------------------------------------------------------------

## Alle fehlenden Bewohner auf einmal (Gründung, erster Takt nach dem Laden alter Spielstände)
func seed_residents(v: Kingdom, rec: Dictionary) -> void:
	ensure_fields(rec)
	rec["residents_seeded"] = true
	var hall := vs.get_hall(v)
	if hall == null:
		return
	var n := visible_target(rec) - (rec["residents"] as Array).size()
	for i in n:
		_spawn(v, rec, hall, float(i) * 0.7)


func _spawn(v: Kingdom, rec: Dictionary, hall: Building, delay: float = 0.0) -> Unit:
	var people := vs.get_people(v)
	var type_id := str(people.get("resident_unit", ""))
	if type_id.is_empty() or DataDB.get_unit_type(type_id).is_empty():
		return null
	var names: Array = people.get("resident_names", [])
	var seq := int(rec.get("resident_seq", 0))
	rec["resident_seq"] = seq + 1
	var person := ""
	if not names.is_empty():
		person = str(names[(seq + int(rec.get("site_index", 0)) * 3) % names.size()])
	var pos := hall.get_approach_point(hall.get_center() + Vector2.from_angle(_rng.randf() * TAU) * 1000.0)
	var init := func(nu: Unit) -> void:
		nu.custom_name = person
	var u: Unit = game.unit_system.spawn_unit(v, type_id, pos, 0, init)
	if u == null:
		return null
	u.command = COMMAND
	u.command_pos = pos
	u.activity = "tritt aus dem Dorfzentrum"
	(rec["residents"] as Array).append({"uid": u.uid, "phase": "idle", "task": "", "spot": pos,
			"until": GameClock.game_time + delay, "home_uid": 0})
	return u


## Ein Bewohner wurde entfernt: aus der Liste streichen; gefallen (0 Leben) = ein Einwohner weniger
func on_unit_removed(u: Unit, rec: Dictionary) -> void:
	ensure_fields(rec)
	var list: Array = rec["residents"]
	for i in range(list.size() - 1, -1, -1):
		if int(list[i]["uid"]) == u.uid:
			list.remove_at(i)
	if u.hp <= 0.0:
		rec["population"] = maxi(int(rec.get("population", 0)) - 1, 0)
		rec["resident_lost"] = int(rec["resident_lost"]) + 1


## Alle Bewohner verschwinden (Dorf zerstört)
func remove_all(v: Kingdom, rec: Dictionary) -> void:
	for u in get_residents(v):
		game.unit_system.remove_unit(u)
	rec["residents"] = []
	rec["resident_lost"] = 0


## Lebende Bewohner des Dorfs
func get_residents(v: Kingdom) -> Array:
	var list: Array = []
	if v == null:
		return list
	for u in v.units:
		if u.is_alive() and is_resident(u):
			list.append(u)
	return list


## Übergabe (Aufnahme, Eroberung): Die Bewohner bleiben Dorfbewohner und leben am Dorfzentrum
## (jetzt des neuen Besitzers) weiter. Bei einer Eroberung sinkt die Einwohnerzahl – wer zu viel
## ist, flieht im nächsten Takt. Damit niemand sie weiter angreift, schliesst das (jetzt
## abhängige) Dorf-Reich Frieden mit allen Reichen (ohne Wildnis).
func on_transfer(from: Kingdom, rec: Dictionary) -> void:
	ensure_fields(rec)
	rec["resident_lost"] = 0
	rec["resident_timer"] = 0.0
	for o in game.kingdoms:
		var k: Kingdom = o
		if k != from and k.controller != "wild" and game.are_hostile(from, k):
			game.set_relation(from, k, "peace")


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

## Je Dorf und VillageSystem-Takt: Zahl angleichen, dann jeden Bewohner weiterschalten.
## alarm: selbstständiges Dorf mit Alarm (fliehen ins Dorfzentrum).
func tick(v: Kingdom, rec: Dictionary, step: float, now: float, alarm: bool) -> void:
	ensure_fields(rec)
	var hall := vs.get_hall(v)
	if hall == null:
		if not (rec["residents"] as Array).is_empty():
			remove_all(v, rec)
		return
	if not bool(rec["residents_seeded"]):
		seed_residents(v, rec)
	_sync_count(v, rec, hall, step, alarm)
	var night: bool = game.day_night_system.get_phase() == "night"
	for e in (rec["residents"] as Array).duplicate():
		var u: Variant = game.find_by_uid(int(e["uid"]))
		if not (u is Unit) or not (u as Unit).is_alive():
			continue
		_tick_one(v, rec, hall, u, e, now, alarm, night)


## Zu viele (Einwohner weniger, z. B. nach einer Eroberung): wer übrig ist, verlässt das Dorf.
## Zu wenige oder Gefallene: alle replace_seconds (nicht während eines Alarms) ein neuer Bewohner.
func _sync_count(v: Kingdom, rec: Dictionary, hall: Building, step: float, alarm: bool) -> void:
	if alarm:
		return
	var list: Array = rec["residents"]
	var target := visible_target(rec)
	if list.size() > target:
		var extra: Variant = game.find_by_uid(int(list.back()["uid"]))
		if extra is Unit:
			game.unit_system.remove_unit(extra)
		else:
			list.pop_back()
		return
	var lost := int(rec["resident_lost"])
	if list.size() >= target and lost <= 0:
		rec["resident_timer"] = 0.0
		return
	rec["resident_timer"] = float(rec["resident_timer"]) + step
	if float(rec["resident_timer"]) < float(cfg("replace_seconds", 120)):
		return
	rec["resident_timer"] = 0.0
	if lost > 0:
		rec["resident_lost"] = lost - 1
		rec["population"] = int(rec.get("population", 0)) + 1
	if list.size() < visible_target(rec):
		_spawn(v, rec, hall)


func _tick_one(v: Kingdom, rec: Dictionary, hall: Building, u: Unit, e: Dictionary, now: float, alarm: bool,
		night: bool) -> void:
	var phase := str(e["phase"])
	# Alarm: ins Dorfzentrum (wer in seiner Hütte schläft, bleibt dort in Sicherheit)
	if alarm:
		if phase == "home" and u.inside != null:
			return
		if phase == "shelter":
			return
		if phase != "to_shelter":
			_go_inside(u, e, hall, "to_shelter", "flieht ins Dorfzentrum", now)
		elif _arrived(u, e, now):
			game.unit_system.set_inside(u, hall)
			e["phase"] = "shelter"
			u.activity = "versteckt sich im Dorfzentrum"
		return
	if phase == "shelter" or phase == "to_shelter":
		_come_out(u, e, now, "verlässt das Dorfzentrum")
		return
	# Nachts schlafen alle in den Hütten (sonst im Dorfzentrum)
	if night:
		if phase == "home" and u.inside != null:
			return
		if phase != "to_home":
			_go_inside(u, e, _home_of(rec, e, hall), "to_home", "geht heim", now)
		elif _arrived(u, e, now):
			var home: Variant = game.find_by_uid(int(e.get("home_uid", 0)))
			game.unit_system.set_inside(u, home as Building if home is Building else hall)
			e["phase"] = "home"
			u.activity = "schläft"
		return
	if phase == "home" or phase == "to_home":
		_come_out(u, e, now, "steht auf")
		return
	match phase:
		"idle", "rest":
			if now >= float(e["until"]):
				_start_work(v, rec, hall, u, e, now)
		"to_work":
			if _arrived(u, e, now):
				var span: Array = cfg("work_seconds", [6, 12])
				e["phase"] = "work"
				e["until"] = now + _rng.randf_range(float(span[0]), float(span[-1]))
				u.activity = str(DataDB.get_job(u.job_id).get("activity", "arbeitet"))
		"work":
			if now >= float(e["until"]):
				var res_id := str(e["task"])
				u.carry_res = res_id
				u.carry_amount = float(cfg("carry", 5))
				u.activity = "bringt %s ins Dorfzentrum" % str(DataDB.get_resource(res_id).get("name", res_id))
				e["phase"] = "to_hall"
				e["until"] = now + WALK_TIMEOUT
				_walk(u, hall.get_approach_point(u.position))
		"to_hall":
			if _arrived(u, e, now):
				_drop_carry(u)
				var span: Array = cfg("rest_seconds", [2, 5])
				e["phase"] = "rest"
				e["until"] = now + _rng.randf_range(float(span[0]), float(span[-1]))
				u.activity = "liefert ab und ruht sich aus"
		_:
			e["phase"] = "idle"


## Am Ziel (steht und wartet auf keinen Weg) oder zu lange unterwegs
func _arrived(u: Unit, e: Dictionary, now: float) -> bool:
	return (not u.moving and not u.path_pending) or now >= float(e["until"])


func _go_inside(u: Unit, e: Dictionary, b: Building, phase: String, text: String, now: float) -> void:
	if u.inside != null:
		game.unit_system.set_inside(u, null)
	_drop_carry(u)
	e["phase"] = phase
	e["until"] = now + WALK_TIMEOUT
	u.activity = text
	_walk(u, b.get_approach_point(u.position), phase == "to_shelter")


## Aus Hütte oder Dorfzentrum heraus, kurz danach weiter (nicht alle gleichzeitig)
func _come_out(u: Unit, e: Dictionary, now: float, text: String) -> void:
	if u.inside != null:
		game.unit_system.set_inside(u, null)
	game.unit_system.stop(u)
	e["phase"] = "idle"
	e["until"] = now + _rng.randf_range(0.0, 4.0)
	u.activity = text


## Alltagswege mit niedrigem Vorrang (UnitSystem.move_to_background): bremsen bei vielen Dörfern
## keine Armeen, Karawanen oder Arbeiter; die Flucht bei Alarm läuft mit normalem Vorrang
func _walk(u: Unit, target: Vector2, urgent: bool = false) -> void:
	if urgent:
		game.unit_system.move_to(u, target)
	else:
		game.unit_system.move_to_background(u, target, float(cfg("work_radius", 9)) + 4.0)


func _drop_carry(u: Unit) -> void:
	u.carry_amount = 0.0
	u.carry_res = ""


## Eigene Hütte (fest je Bewohner, solange sie steht), sonst das Dorfzentrum
func _home_of(rec: Dictionary, e: Dictionary, hall: Building) -> Building:
	var home: Variant = game.find_by_uid(int(e.get("home_uid", 0)))
	if home is Building and (home as Building).is_alive() and (home as Building).constructed:
		return home
	var huts := _huts(rec)
	if huts.is_empty():
		e["home_uid"] = hall.uid
		return hall
	var b: Building = huts[int(e["uid"]) % huts.size()]
	e["home_uid"] = b.uid
	return b


func _huts(rec: Dictionary) -> Array:
	var list: Array = []
	for uid in rec.get("hut_uids", []):
		var b: Variant = game.find_by_uid(int(uid))
		if b is Building and (b as Building).is_alive() and (b as Building).constructed:
			list.append(b)
	return list


# ---------------------------------------------------------------------------
# Arbeit wählen
# ---------------------------------------------------------------------------

func _start_work(v: Kingdom, rec: Dictionary, hall: Building, u: Unit, e: Dictionary, now: float) -> void:
	var res_id := _pick_task(v)
	var tasks: Dictionary = cfg("tasks", {})
	var task: Dictionary = tasks.get(res_id, {})
	var job_id := str(task.get("job", "idle"))
	if u.job_id != job_id:
		u.job_id = job_id
	e["task"] = res_id
	e["spot"] = _find_spot(v, rec, hall, res_id, str(task.get("at", "")), job_id)
	e["phase"] = "to_work"
	e["until"] = now + WALK_TIMEOUT
	u.activity = "geht zur Arbeit"
	_walk(u, e["spot"])


## Ware des Volks, gewichtet nach der Produktion (nur Waren mit einer Tätigkeit in tasks)
func _pick_task(v: Kingdom) -> String:
	var produces: Dictionary = vs.get_people(v).get("produces", {})
	var tasks: Dictionary = cfg("tasks", {})
	var total := 0.0
	for res_id in produces:
		if tasks.has(res_id):
			total += maxf(float(produces[res_id]), 0.0)
	if total <= 0.0:
		return "food" if tasks.has("food") else ""
	var roll := _rng.randf() * total
	for res_id in produces:
		if not tasks.has(res_id):
			continue
		roll -= maxf(float(produces[res_id]), 0.0)
		if roll <= 0.0:
			return str(res_id)
	return str(produces.keys().back())


## Arbeitsort: am Dorfzentrum (at "hall"), auf dem Feld neben einer Hütte (at "hut") oder an
## einem passenden Vorkommen im Dorfumkreis (sonst doch neben einer Hütte)
func _find_spot(v: Kingdom, rec: Dictionary, hall: Building, res_id: String, at: String, job_id: String) -> Vector2:
	var jitter := Vector2(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-14.0, 14.0))
	if at == "hall":
		return hall.get_approach_point(hall.get_center() + Vector2.from_angle(_rng.randf() * TAU) * 1000.0) + jitter
	if at != "hut":
		var cells := _deposit_cells(v, hall, res_id, job_id)
		if not cells.is_empty():
			return world.cell_to_world(cells[_rng.randi() % cells.size()]) + jitter
	var huts := _huts(rec)
	var b: Building = hall if huts.is_empty() else huts[_rng.randi() % huts.size()]
	var away := b.get_center() + Vector2.from_angle(_rng.randf() * TAU) * 1000.0
	var p := b.get_approach_point(away)
	# Ein Stück vom Haus weg aufs Feld
	return p + (p - b.get_center()).normalized() * _ts * _rng.randf_range(0.3, 1.0) + jitter


## Vorkommen der Ware im Umkreis work_radius ums Dorfzentrum (nicht in fremdem Gebiet), zwischengespeichert
func _deposit_cells(v: Kingdom, hall: Building, res_id: String, job_id: String) -> Array:
	var now := GameClock.game_time
	var entry: Dictionary = _spots.get(v.id, {})
	if entry.is_empty() or now - float(entry["t"]) > SPOT_REFRESH:
		entry = {"t": now, "cells": {}}
		_spots[v.id] = entry
	var by_res: Dictionary = entry["cells"]
	if by_res.has(res_id):
		return by_res[res_id]
	var cells: Array = []
	var indices: PackedInt32Array = DataDB.get_job(job_id).get("deposit_indices", PackedInt32Array())
	if not indices.is_empty():
		var center := world.world_to_cell(hall.get_center())
		var r := int(cfg("work_radius", 9))
		var own := [0, v.id, hall.kingdom.id if hall.kingdom != null else v.id]
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := center + Vector2i(dx, dy)
				if world.in_bounds(c) and world.is_gatherable(c, indices) and own.has(world.get_owner(c)):
					cells.append(c)
	by_res[res_id] = cells
	return cells


# ---------------------------------------------------------------------------
# Anzeige und Speichern
# ---------------------------------------------------------------------------

## Zeilen für das Auswahlfenster: "Zwergenbewohner aus Zwergendorf Eisenhall" + Tätigkeit
func describe(u: Unit) -> String:
	var v := u.kingdom
	var rec := vs.get_record(v)
	var line := "%s aus %s" % [str(u.type_def.get("name", "Bewohner")), v.display_name if v != null else "?"]
	var status := str(rec.get("status", "active"))
	if status == "annexed" or status == "conquered":
		var owner_k: Kingdom = game.get_kingdom(int(rec.get("owner_id", 0)))
		line += " (%s %s)" % ["aufgenommen von" if status == "annexed" else "erobert von",
				owner_k.display_name if owner_k != null else "?"]
	var doing := u.activity if not u.activity.is_empty() else "lebt im Dorf"
	return "%s\n%s" % [line, doing.substr(0, 1).to_upper() + doing.substr(1)]


## Nach dem Laden: Einträge ohne passende Einheit entfernen; Bewohner ohne Eintrag (sollte nicht
## vorkommen) neu aufnehmen. Wege laufen über den gespeicherten Bewegungszustand weiter.
func rebuild_runtime(vid: int, rec: Dictionary) -> void:
	ensure_fields(rec)
	_spots.clear()
	var list: Array = rec["residents"]
	var known := {}
	for i in range(list.size() - 1, -1, -1):
		var u: Variant = game.find_by_uid(int(list[i]["uid"]))
		if not (u is Unit) or (u as Unit).kingdom == null or (u as Unit).kingdom.id != vid or not is_resident(u):
			list.remove_at(i)
		else:
			known[int(list[i]["uid"])] = true
	var v: Kingdom = game.get_kingdom(vid)
	if v == null:
		return
	for u in v.units:
		if is_resident(u) and u.is_alive() and not known.has(u.uid):
			list.append({"uid": u.uid, "phase": "idle", "task": "", "spot": u.position, "until": 0.0, "home_uid": 0})
