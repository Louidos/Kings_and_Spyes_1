## RecruitSystem
##
## Bewerber (recruits.json): Alle paar Minuten kommt zu jedem Königreich (Spieler und KI) ein
## Bewerber an den Gebietsrand und wartet dort decision_seconds. Er hat einen Namen, einen
## Wunschberuf und 1–3 Bedingungen (immer ein freier Wohnplatz, dazu z. B. ein Geschenk, ein
## fertiges Gebäude, Zufriedenheit, Burgstufe, ein ausgebautes Gebäude, keine Hungersnot).
## Fachleute arbeiten im Wunschberuf schneller und stellen strengere Bedingungen. Aufnehmen
## geht nur, wenn alle erfüllt sind (Requirements); Abweisen immer. Die Taverne verkürzt die
## Wartezeit bis zum nächsten Bewerber, ihr Ausbau noch mehr.
## Der Spieler entscheidet im Bewerberfenster (RecruitDialog), die KI über AIRecruits –
## beide rufen accept/reject mit ihrem Reich auf.
## Bewerber laufen als Einheit des Reichs "Wanderer" (EventSystem.create_wanderer_kingdom).
## Gespeichert: recruits, next_id, next_at, rng_state (Phase-10-Schnittstelle).
class_name RecruitSystem
extends Node

signal recruit_created(rec: Dictionary)
## accepted = false: abgewiesen, weitergezogen oder umgekommen
signal recruit_resolved(rec: Dictionary, accepted: bool)

var game: Node
var world: WorldData
## Bewerber: id -> {"id", "target_id", "name", "template", "title", "job", "skilled", "reqs",
## "uid", "state": "approaching"|"waiting"|"leaving", "dest", "spawned", "expires", "leave_until",
## "ai_decide_at"}
var recruits: Dictionary = {}
var next_id := 1
## Reich-id -> Spielzeit des nächsten Bewerbers
var next_at: Dictionary = {}
var rng_state := 0
## false: keine neuen Bewerber (Rauchtest/Balancing "recruits=off"; nicht gespeichert)
var enabled := true

var _rng := RandomNumberGenerator.new()
var _acc := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_rng.seed = hash(str(world.world_seed) + "bewerber")
	rng_state = _rng.state
	GameClock.sim_tick.connect(_on_sim_tick)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Offene Bewerber eines Reichs (unterwegs oder wartend), nach id
func get_recruits(k: Kingdom) -> Array:
	var list: Array = []
	var ids: Array = recruits.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = recruits[id]
		if k != null and int(r["target_id"]) == k.id and str(r["state"]) != "leaving":
			list.append(r)
	return list


func get_recruit(id: int) -> Dictionary:
	return recruits.get(id, {})


## Bewerber, zu dem diese Einheit gehört ({} = keiner)
func get_recruit_of_unit(u: Unit) -> Dictionary:
	if u == null:
		return {}
	for id in recruits:
		var r: Dictionary = recruits[id]
		if int(r["uid"]) == u.uid:
			return r
	return {}


func count_open(k: Kingdom) -> int:
	return get_recruits(k).size()


## Sekunden bis zum nächsten Bewerber (-1 = unbekannt)
func seconds_to_next(k: Kingdom) -> float:
	if not next_at.has(k.id):
		return -1.0
	return maxf(float(next_at[k.id]) - GameClock.game_time, 0.0)


## Stufe der besten fertigen Taverne (0 = keine)
func tavern_level(k: Kingdom) -> int:
	var id := str(DataDB.rec("tavern_building", "tavern"))
	var best := 0
	for b in k.buildings:
		if b.constructed and b.get_def_id() == id:
			best = maxi(best, b.level)
	return best


## Faktor auf die Wartezeit bis zum nächsten Bewerber (Taverne)
func interval_mult(k: Kingdom) -> float:
	var mults: Array = DataDB.rec("tavern_interval_mult", [1.0])
	if mults.is_empty():
		return 1.0
	return float(mults[mini(tavern_level(k), mults.size() - 1)])


## "Clara, Bäuerin (Fachkraft)" – Kopfzeile
func describe(rec: Dictionary) -> String:
	var text := "%s, %s" % [str(rec.get("name", "?")), str(rec.get("title", ""))]
	if bool(rec.get("skilled", false)):
		text += " (Fachkraft)"
	return text


## Wunschberuf und ggf. Fachkraft-Bonus als Satz
func job_text(rec: Dictionary) -> String:
	var job_name := str(DataDB.get_job(str(rec.get("job", ""))).get("name", rec.get("job", "")))
	var text := "Wunschberuf: %s" % job_name
	if bool(rec.get("skilled", false)):
		text += " · arbeitet dort %d %% schneller" % roundi(float(DataDB.rec("skilled.work_bonus", 0.2)) * 100.0)
	return text


## "" = darf jetzt aufgenommen werden, sonst der Grund
func can_accept(k: Kingdom, id: int) -> String:
	var rec: Dictionary = recruits.get(id, {})
	if rec.is_empty():
		return "Den Bewerber gibt es nicht mehr"
	if k == null or int(rec["target_id"]) != k.id or k.defeated:
		return "Der Bewerber möchte zu einem anderen Reich"
	if str(rec["state"]) == "leaving":
		return "Der Bewerber ist schon weitergezogen"
	if _unit_of(rec) == null:
		return "Der Bewerber ist nicht mehr da"
	return Requirements.first_missing(rec["reqs"], k, game)


# ---------------------------------------------------------------------------
# Aufnehmen und Abweisen
# ---------------------------------------------------------------------------

## Aufnehmen: Geschenke bezahlen, der Bewerber wird Bewohner im Wunschberuf ("" = ok)
func accept(k: Kingdom, id: int) -> String:
	var reason := can_accept(k, id)
	if not reason.is_empty():
		return reason
	var rec: Dictionary = recruits[id]
	for req in rec["reqs"]:
		if str((req as Dictionary).get("type", "")) == "gift":
			k.spend((req as Dictionary).get("cost", {}))
	var old := _unit_of(rec)
	var pos := old.position
	game.unit_system.remove_unit(old)
	var v: Unit = game.unit_system.spawn_unit(k, "villager", pos)
	if v == null:
		recruits.erase(id)
		recruit_resolved.emit(rec, false)
		return "Kein Platz für den neuen Bewohner"
	var job := str(rec.get("job", "idle"))
	if not game.work_system.set_unit_job(v, job):
		game.work_system.set_unit_job(v, "idle")
	if bool(rec.get("skilled", false)):
		v.skill_job = job
		v.skill_bonus = float(DataDB.rec("skilled.work_bonus", 0.2))
	v.satisfaction = float(DataDB.rec("start_satisfaction", 60))
	k.add_stat("recruits_accepted")
	k.notify("%s ist jetzt dein Bewohner (%s) – Wohnraum %d/%d." % [describe(rec),
			str(DataDB.get_job(v.job_id).get("name", v.job_id)), k.get_population(), k.get_housing()], "good", pos)
	recruits.erase(id)
	recruit_resolved.emit(rec, true)
	return ""


## Abweisen: der Bewerber zieht weiter ("" = ok)
func reject(k: Kingdom, id: int) -> String:
	var rec: Dictionary = recruits.get(id, {})
	if rec.is_empty():
		return "Den Bewerber gibt es nicht mehr"
	if k == null or int(rec["target_id"]) != k.id:
		return "Der Bewerber möchte zu einem anderen Reich"
	if str(rec["state"]) == "leaving":
		return "Der Bewerber zieht schon weiter"
	k.notify("%s zieht weiter." % str(rec.get("name", "Der Bewerber")), "info")
	_leave(rec)
	return ""


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	_acc += dt
	if _acc < 1.0:
		return
	_acc = 0.0
	var now := GameClock.game_time
	_rng.state = rng_state
	var interval: Array = DataDB.rec("interval", [120, 240])
	for k in game.kingdoms:
		if not _eligible(k):
			continue
		if not next_at.has(k.id):
			next_at[k.id] = now + float(DataDB.rec("first_after", 150)) + _rng.randf_range(0.0, float(interval[0]))
		elif now >= float(next_at[k.id]):
			if enabled and count_open(k) < int(DataDB.rec("max_waiting", 2)):
				spawn_recruit(k)
			next_at[k.id] = now + _rng.randf_range(float(interval[0]), float(interval[1])) * interval_mult(k)
	_tick_recruits(now)
	rng_state = _rng.state


func _eligible(k: Kingdom) -> bool:
	return (k.controller == "player" or k.controller == "ai") and not k.defeated and k.has_economy \
			and is_instance_valid(k.castle)


func _tick_recruits(now: float) -> void:
	var ts := float(world.tile_size)
	for id in recruits.keys():
		if not recruits.has(id):
			continue
		var rec: Dictionary = recruits[id]
		var u := _unit_of(rec)
		if u == null:
			recruits.erase(id)
			if str(rec["state"]) != "leaving":
				recruit_resolved.emit(rec, false)
			continue
		var dest: Vector2 = rec["dest"]
		var arrived := u.position.distance_to(dest) <= 3.0 * ts or (not u.moving and not u.path_pending \
				and u.command != "seek_refuge" and u.command != "travel")
		var target: Kingdom = game.get_kingdom(int(rec["target_id"]))
		match str(rec["state"]):
			"approaching", "waiting":
				if target == null or target.defeated or not is_instance_valid(target.castle):
					_leave(rec)
					continue
				if str(rec["state"]) == "approaching" and arrived:
					rec["state"] = "waiting"
					rec["expires"] = now + float(DataDB.rec("decision_seconds", 120))
					var link := {"window": "recruit", "recruit_id": int(id), "pos": u.position}
					target.notify("Bewerber: %s wartet am Rand deines Gebiets (%d s) – klicken, um die Bedingungen zu sehen." % [
							describe(rec), roundi(float(DataDB.rec("decision_seconds", 120)))], "info", link)
				elif str(rec["state"]) == "waiting" and now >= float(rec["expires"]):
					target.notify("%s hat lange genug gewartet und zieht weiter." % str(rec.get("name", "Der Bewerber")), "info", u.position)
					_leave(rec)
			"leaving":
				if arrived or now >= float(rec.get("leave_until", now)):
					game.unit_system.remove_unit(u)
					recruits.erase(id)


func _unit_of(rec: Dictionary) -> Unit:
	var u: Variant = game.find_by_uid(int(rec.get("uid", 0)))
	return u if u is Unit and is_instance_valid(u) and (u as Unit).is_alive() else null


func _leave(rec: Dictionary) -> void:
	var was_open := str(rec["state"]) != "leaving"
	rec["state"] = "leaving"
	var u := _unit_of(rec)
	if u == null:
		recruits.erase(int(rec["id"]))
	else:
		var target: Kingdom = game.get_kingdom(int(rec["target_id"]))
		var away := u.position
		if target != null and is_instance_valid(target.castle):
			away = u.position + (u.position - target.castle.get_center()).normalized() * 14.0 * float(world.tile_size)
		var c: Vector2i = game.nav.nearest_free(world.world_to_cell(away), 6)
		rec["dest"] = world.cell_to_world(c) if c.x >= 0 else u.position
		rec["leave_until"] = GameClock.game_time + 60.0
		game.command_system.order_travel(u, rec["dest"], "travel")
	if was_open:
		recruit_resolved.emit(rec, false)


## Neuen Bewerber für k erzeugen (auch Rauchtest). Gibt die id zurück (0 = kein Platz).
func spawn_recruit(k: Kingdom, template_id: String = "") -> int:
	if not _eligible(k):
		return 0
	var template := _pick_template(k, template_id)
	if template.is_empty():
		return 0
	var spawn := _spawn_point(k)
	if spawn.is_empty():
		return 0
	var wk: Kingdom = game.event_system.create_wanderer_kingdom()
	var u: Unit = game.unit_system.spawn_unit(wk, str(DataDB.rec("unit", "wanderer")), spawn["from"])
	if u == null:
		return 0
	game.command_system.order_travel(u, spawn["to"], "seek_refuge")
	var skilled := _rng.randf() < float(DataDB.rec("skilled.chance", 0.25)) \
			+ float(DataDB.rec("skilled.chance_per_tavern_level", 0.0)) * tavern_level(k)
	var names: Array = (DataDB.rec("names", {}) as Dictionary).get(k.faction_id, ["Fremder"])
	var rec := {"id": next_id, "target_id": k.id, "name": str(names[_rng.randi_range(0, names.size() - 1)]),
			"template": str(template.get("id", "")), "title": str(template.get("name", "")),
			"job": str(template.get("job", "idle")), "skilled": skilled, "reqs": _make_requirements(template, skilled),
			"uid": u.uid, "state": "approaching", "dest": spawn["to"], "spawned": GameClock.game_time,
			"expires": -1.0, "leave_until": -1.0,
			"ai_decide_at": -1.0}
	if k.controller == "ai":
		var think: Array = DataDB.rec("ai_accept.think_seconds", [10, 30])
		rec["ai_decide_at"] = GameClock.game_time + _rng.randf_range(float(think[0]), float(think[1]))
	recruits[next_id] = rec
	next_id += 1
	recruit_created.emit(rec)
	return int(rec["id"])


func _pick_template(k: Kingdom, template_id: String) -> Dictionary:
	var candidates: Array = []
	var total := 0.0
	for t in DataDB.rec("templates", []):
		var tpl: Dictionary = t
		if not template_id.is_empty():
			if str(tpl.get("id", "")) == template_id:
				return tpl
			continue
		if int(tpl.get("min_castle_level", 1)) > k.get_castle_level():
			continue
		candidates.append(tpl)
		total += maxf(float(tpl.get("weight", 1.0)), 0.0)
	if candidates.is_empty() or total <= 0.0:
		return {}
	var roll := _rng.randf() * total
	for tpl in candidates:
		roll -= maxf(float((tpl as Dictionary).get("weight", 1.0)), 0.0)
		if roll <= 0.0:
			return tpl
	return candidates[candidates.size() - 1]


## Wohnplatz immer, Pflicht-Gebäude der Vorlage, dann count Bausteine aus pool (Fachkraft: dazu
## extra_requirements aus strict); jeder Baustein höchstens einmal
func _make_requirements(template: Dictionary, skilled: bool) -> Array:
	var reqs: Array = [{"type": "housing"}]
	var building := str(template.get("building", ""))
	if not building.is_empty():
		reqs.append({"type": "building", "building": building, "level": int(template.get("building_level", 1))})
	var count_range: Array = template.get("count", [1, 2])
	var used := {}
	_pick_blocks(reqs, DataDB.rec("pool", []), _rng.randi_range(int(count_range[0]), int(count_range[1])), used)
	if skilled:
		_pick_blocks(reqs, DataDB.rec("strict", []), int(DataDB.rec("skilled.extra_requirements", 1)), used)
	return reqs


func _pick_blocks(reqs: Array, names: Array, n: int, used: Dictionary) -> void:
	var options: Array = []
	for name_id in names:
		if not used.has(str(name_id)):
			options.append(str(name_id))
	for i in mini(n, options.size()):
		var j := _rng.randi_range(i, options.size() - 1)
		var tmp: Variant = options[i]
		options[i] = options[j]
		options[j] = tmp
		used[str(options[i])] = true
		var block: Dictionary = (DataDB.rec("requirements", {}) as Dictionary).get(str(options[i]), {})
		var req := _concrete(block)
		if not req.is_empty():
			reqs.append(req)


## Baustein mit Bereichen ([von, bis]) → feste Werte
func _concrete(block: Dictionary) -> Dictionary:
	var type := str(block.get("type", ""))
	match type:
		"gift":
			var table: Dictionary = block.get("cost", {})
			var keys: Array = table.keys()
			var cost := {}
			for i in mini(int(block.get("kinds", 1)), keys.size()):
				var j := _rng.randi_range(i, keys.size() - 1)
				var tmp: Variant = keys[i]
				keys[i] = keys[j]
				keys[j] = tmp
				var r: Array = table[keys[i]]
				cost[str(keys[i])] = float(_rng.randi_range(int(r[0]), int(r[1])))
			return {"type": "gift", "cost": cost}
		"satisfaction":
			var r: Variant = block.get("min", 50)
			var v := float(_rng.randi_range(int(r[0]), int(r[1]))) if r is Array else float(r)
			return {"type": "satisfaction", "min": v}
		"":
			return {}
	return block.duplicate(true)


## Startpunkt ausserhalb des Gebiets und Ziel am Gebietsrand ({} = kein Platz)
func _spawn_point(k: Kingdom) -> Dictionary:
	var center := k.castle.get_center()
	var ts := float(world.tile_size)
	var dist: Array = DataDB.rec("spawn_distance", [24, 34])
	for _try in 12:
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		var c: Vector2i = game.nav.nearest_free(world.world_to_cell(center + dir * _rng.randf_range(float(dist[0]), float(dist[1])) * ts), 6)
		if c.x < 0 or world.get_owner(c) == k.id:
			continue
		var from := world.cell_to_world(c)
		var bbox := TerritorySystem.kingdom_bbox(k, world)
		var edge := (Vector2(bbox.size).length() * 0.5 + 2.0) * ts
		var dc: Vector2i = game.nav.nearest_free(world.world_to_cell(center + dir * minf(edge, center.distance_to(from))), 6)
		return {"from": from, "to": world.cell_to_world(dc) if dc.x >= 0 else from}
	return {}


# ---------------------------------------------------------------------------
# Speichern (Phase-10-Schnittstelle)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"recruits": recruits.duplicate(true), "next_id": next_id, "next_at": next_at.duplicate(), "rng_state": rng_state,
			"acc": _acc}


func from_dict(d: Dictionary) -> void:
	recruits.clear()
	var saved: Dictionary = d.get("recruits", {})
	for id in saved:
		recruits[int(id)] = (saved[id] as Dictionary).duplicate(true)
	next_id = int(d.get("next_id", 1))
	next_at.clear()
	var saved_next: Dictionary = d.get("next_at", {})
	for kid in saved_next:
		next_at[int(kid)] = float(saved_next[kid])
	rng_state = int(d.get("rng_state", rng_state))
	_acc = float(d.get("acc", 0.0))


func rebuild_runtime() -> void:
	pass
