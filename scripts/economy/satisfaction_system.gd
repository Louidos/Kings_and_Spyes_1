## SatisfactionSystem
##
## Zufriedenheit der Bewohner (Phase 8), für alle Reiche mit Wirtschaft (Spieler und
## KI) gleich. Jeder Bewohner (Einheit mit needs_housing) hat Unit.satisfaction
## (0–100); der Wert nähert sich langsam einem Zielwert aus Reichsursachen (Nahrung,
## Wohnraum, Sicherheit, Gebäude wie Taverne und Tempel, Ereignisse, Volk, Fraktion,
## Reichsboni) und persönlichen Ursachen (Laune, Seuche, ohne Arbeit, Dankbarkeit …).
## Folgen: Arbeitsleistung (Unit.work_mult), Überlaufen (der Bewohner läuft sichtbar
## zu einem Nachbarreich, einem Dorf oder zum Kartenrand; ein Befehl hält ihn auf) und
## Verrat (ein feindliches Reich erfährt über das EspionageSystem viel über das Reich).
## Feste kosten Nahrung und Mana und heben die Zufriedenheit eine Weile.
## Kampfsignale ändern nur Zeitstempel bzw. legen Einträge in _pending; Besitzerwechsel,
## Entfernen und Befehle geschehen im eigenen Takt.
##
## Zustand (gespeichert): kingdoms_state (kid -> Werte je Reich, siehe _new_state),
## defectors (uid -> Überläufer), hidden_spies (uid -> eingeschleuster Spion), personal
## (uid -> persönliche Ursachen), abort_until (uid -> Zeitpunkt), late_reports, rng_state, _pending
## (Ankünfte von Überläufern, noch nicht verarbeitet);
## dazu Unit.satisfaction. Laufzeit: work_mult der Einheiten, _idle_since, _seen_since.
class_name SatisfactionSystem
extends Node

## Durchschnitt eines Reichs hat sich geändert (|Δ| >= 0,5)
signal satisfaction_changed(k: Kingdom, avg: float)
## Ein Bewohner macht sich auf den Weg zu einem anderen Reich, Dorf oder zum Rand
signal defection_started(u: Unit, from_kingdom: Kingdom, dest_kind: String, dest: Kingdom)
## Ein Überläufer ist angekommen (u kann danach schon entfernt sein)
signal defected(u: Unit, from_kingdom: Kingdom, dest_kind: String, dest: Kingdom)
## Ein Verräter hat receiver Wissen über victim geliefert
signal betrayed(victim: Kingdom, receiver: Kingdom, discovered: bool)
## Ein Reich feiert ein Fest
signal feast_started(k: Kingdom)

## Ein Reich wird alle so viele Spielsekunden durchgerechnet (Round-Robin)
const KINGDOM_STEP := 0.5
## Höchstens so viele Einträge im Verlauf je Reich bzw. in den Zeitlisten
const LOG_SIZE := 10
const TIME_LIST_SIZE := 8
## Höchstens so viele feindliche Einheiten werden je Scan geprüft
const SCAN_LIMIT := 400

var game: Node
var world: WorldData

## kid -> Zustand je Reich (siehe _new_state)
var kingdoms_state: Dictionary = {}
## uid -> {"uid", "from_id", "dest_kind", "dest_id", "dest", "since", "traitor", "retries"}
var defectors: Dictionary = {}
## uid -> {"uid", "victim_id", "owner_id", "next_leak"}
var hidden_spies: Dictionary = {}
## uid -> Array[{"cause", "value", "until"}]
var personal: Dictionary = {}
## uid -> Spielzeit, bis zu der ein aufgehaltener Überläufer langsamer arbeitet
var abort_until: Dictionary = {}
## {"victim_id", "receiver_id", "at"}
var late_reports: Array = []
var rng_state: int = 0

var _rng := RandomNumberGenerator.new()
var _rr := 0
var _acc := 0.0
var _maint_acc := 0.0
## uid -> Spielzeit, seit der der Bewohner ohne Beruf ist (Laufzeit)
var _idle_since: Dictionary = {}
## uid -> Spielzeit, seit der der Bewohner erfasst ist (Schutz für Neuankömmlinge)
var _seen_since: Dictionary = {}
## Ankünfte/Fehlschläge von Überläufern: [uid, ok] (im eigenen Takt verarbeitet; gespeichert)
var _pending: Array = []
## Häufig gelesene Werte aus satisfaction.json (Laufzeit, einmal beim Aufbau gelesen)
var _cfg := {}
## Bewohner je Reich im laufenden Durchgang (Laufzeit)
var _inh_cache: Dictionary = {}
## Rechenzeit (Rauchtest)
var tick_usec_total := 0
var tick_usec_max := 0
var tick_count := 0


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_rng.seed = hash(world.world_seed + 8051)
	rng_state = _rng.state
	_load_cfg()
	GameClock.sim_tick.connect(_on_sim_tick)
	var cs: CombatSystem = game.combat_system
	cs.kingdom_attacked.connect(_on_kingdom_attacked)
	cs.unit_died.connect(_on_unit_died)
	cs.building_destroyed.connect(_on_building_destroyed)
	game.command_system.command_finished.connect(_on_command_finished)
	game.unit_system.unit_removed.connect(_on_unit_removed)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Wird die Zufriedenheit dieses Reichs berechnet? (Wirtschaft, Spieler oder KI, nicht besiegt)
func is_tracked(k: Kingdom) -> bool:
	return k != null and k.has_economy and not k.defeated and (k.controller == "player" or k.controller == "ai")


## Ist die Einheit ein Bewohner, dessen Zufriedenheit zählt?
func is_inhabitant(u: Unit) -> bool:
	return is_instance_valid(u) and u.is_alive() and bool(u.type_def.get("needs_housing", false)) and is_tracked(u.kingdom)


## Durchschnitt der Bewohner (-1 = keine Bewohner bzw. noch nicht berechnet)
func get_average(k: Kingdom) -> float:
	if k == null:
		return -1.0
	return float((kingdoms_state.get(k.id, {}) as Dictionary).get("avg", -1.0))


## Reichsursachen [{"cause", "value", "kind"}], nach |Wert| sortiert
func get_breakdown(k: Kingdom) -> Array:
	var list: Array = []
	if k == null:
		return list
	for p in (kingdoms_state.get(k.id, {}) as Dictionary).get("parts", []):
		list.append({"cause": str(p[0]), "value": float(p[1]), "kind": str(p[2])})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(float(a["value"])) > absf(float(b["value"])))
	return list


## Reichsursachen und persönliche Ursachen eines Bewohners
func get_unit_breakdown(u: Unit) -> Array:
	if not is_instance_valid(u):
		return []
	var list := get_breakdown(u.kingdom)
	for p in _personal_parts(u, GameClock.game_time):
		list.append({"cause": str(p[0]), "value": float(p[1]), "kind": "personal"})
	return list


## Zielwert eines Bewohners (0–100)
func get_target(u: Unit) -> float:
	if not is_instance_valid(u):
		return 0.0
	return clampf(_kingdom_sum(u.kingdom) + _personal_sum(u, GameClock.game_time), 0.0, 100.0)


## Anzahl Bewohner je Stufe (Aufgebracht, Unzufrieden, Zufrieden, Glücklich)
func get_distribution(k: Kingdom) -> Array:
	var tiers: Array = DataDB.sat("effects.tiers", [])
	var counts: Array = []
	counts.resize(maxi(tiers.size(), 1))
	counts.fill(0)
	if k == null:
		return counts
	for u in k.units:
		if not is_inhabitant(u) or u.satisfaction < 0.0:
			continue
		var idx := 0
		for i in tiers.size():
			if u.satisfaction >= float((tiers[i] as Dictionary).get("min", 0)):
				idx = i
		counts[idx] = int(counts[idx]) + 1
	return counts


## Stufe zu einem Wert: {"name", "color", "index"}
static func tier_for(value: float) -> Dictionary:
	var tiers: Array = DataDB.sat("effects.tiers", [])
	var result := {"name": "–", "color": Color(0.85, 0.82, 0.75), "index": 0}
	for i in tiers.size():
		var t: Dictionary = tiers[i]
		if value >= float(t.get("min", 0)):
			result = {"name": str(t.get("name", "")), "color": Color(str(t.get("color", "#ffffff"))), "index": i}
	return result


## Arbeitsleistung zu einer Zufriedenheit (work_curve, linear zwischen den Stützstellen)
static func work_mult_for(value: float) -> float:
	var curve: Array = DataDB.satisfaction_cfg.get("effects", {}).get("work_curve", [])
	if curve.is_empty():
		return 1.0
	var prev: Array = curve[0]
	if value <= float(prev[0]):
		return float(prev[1])
	for i in range(1, curve.size()):
		var next: Array = curve[i]
		if value <= float(next[0]):
			var span := maxf(float(next[0]) - float(prev[0]), 0.0001)
			return lerpf(float(prev[1]), float(next[1]), (value - float(prev[0])) / span)
		prev = next
	return float(prev[1])


## Gefahr: Bewohner unter der Überlauf- bzw. Verratsgrenze und laufende Überläufer
func get_risk(k: Kingdom) -> Dictionary:
	var result := {"defect": 0, "betray": 0, "defecting": 0}
	if k == null:
		return result
	var below := float(DataDB.sat("defection.below", 25))
	var betray_below := float(DataDB.sat("betrayal.below", 20))
	for u in k.units:
		if not is_inhabitant(u) or u.satisfaction < 0.0:
			continue
		if is_defector(u):
			result["defecting"] = int(result["defecting"]) + 1
			continue
		if u.satisfaction < below:
			result["defect"] = int(result["defect"]) + 1
		if u.satisfaction < betray_below:
			result["betray"] = int(result["betray"]) + 1
	return result


## Verlauf (neueste zuletzt): [{"t", "text"}]
func get_log(k: Kingdom) -> Array:
	if k == null:
		return []
	return (kingdoms_state.get(k.id, {}) as Dictionary).get("log", [])


## Laufende Überläufer eines Reichs (Einheiten)
func get_defectors(k: Kingdom) -> Array:
	var list: Array = []
	for uid in defectors:
		var rec: Dictionary = defectors[uid]
		var u: Variant = game.find_by_uid(int(uid))
		if u is Unit and k != null and int(rec["from_id"]) == k.id:
			list.append(u)
	return list


func is_defector(u: Unit) -> bool:
	return is_instance_valid(u) and defectors.has(u.uid)


## Läuft u gerade zu k über? Das Zielreich (Dorf oder Reich) greift ihn dann nicht an,
## auch wenn es mit seinem Reich im Krieg ist (CombatSystem.is_valid_target).
func defects_to(u: Unit, k: Kingdom) -> bool:
	if k == null or not defectors.has(u.uid):
		return false
	return int((defectors[u.uid] as Dictionary).get("dest_id", 0)) == k.id


## "Läuft über zu Zwergendorf Eisenhall – Befehl geben hält ihn auf"
func get_defector_text(u: Unit) -> String:
	if not is_defector(u):
		return ""
	var rec: Dictionary = defectors[u.uid]
	var where := _dest_name(rec)
	if bool(rec.get("traitor", false)):
		return "Verräter auf der Flucht zu %s" % where
	return "Läuft über zu %s – Befehl geben hält ihn auf" % where


# ---------------------------------------------------------------------------
# Feste
# ---------------------------------------------------------------------------

## Kosten eines Fests: Grundkosten + Nahrung je Bewohner, × Modifikator "feast_cost"
func feast_cost(k: Kingdom) -> Dictionary:
	var cost := {}
	var base: Dictionary = DataDB.sat("feast.cost", {})
	for res in base:
		cost[res] = float(base[res])
	if k == null:
		return cost
	cost["food"] = float(cost.get("food", 0.0)) + float(DataDB.sat("feast.per_population_food", 3)) * _inhabitant_count(k)
	var f := k.mod("feast_cost")
	for res in cost:
		cost[res] = ceilf(float(cost[res]) * f)
	return cost


## Warum kein Fest möglich ist ("" = möglich)
func can_hold_feast(k: Kingdom) -> String:
	if not is_tracked(k):
		return "Dieses Reich kann keine Feste feiern"
	var st := _state(k)
	var now := GameClock.game_time
	if float(st["feast_until"]) > now:
		return "Das Fest läuft noch (%s)" % _time_text(float(st["feast_until"]) - now)
	if float(st["feast_ready"]) > now:
		return "Nächstes Fest in %s" % _time_text(float(st["feast_ready"]) - now)
	if _inhabitant_count(k) == 0:
		return "Keine Bewohner"
	var missing := k.missing_text(feast_cost(k))
	return missing


## Fest feiern: Kosten zahlen, Bonus "feast" für feast.seconds, Abklingzeit
func hold_feast(k: Kingdom) -> bool:
	if not can_hold_feast(k).is_empty():
		return false
	if not k.spend(feast_cost(k)):
		return false
	var st := _state(k)
	var now := GameClock.game_time
	var bonus := float(DataDB.sat("feast.bonus", 15))
	var seconds := float(DataDB.sat("feast.seconds", 900))
	k.set_bonus("feast", "satisfaction", bonus)
	st["feast_until"] = now + seconds
	st["feast_ready"] = now + float(DataDB.sat("feast.cooldown", 2400))
	k.add_stat("feasts")
	var pos: Variant = null
	if is_instance_valid(k.castle):
		pos = k.castle.get_center()
	k.notify("Das Fest beginnt! %+d Zufriedenheit für %s." % [roundi(bonus), _time_text(seconds)], "good", pos)
	_log(k, "Fest gefeiert (%+d)" % roundi(bonus))
	feast_started.emit(k)
	return true


# ---------------------------------------------------------------------------
# Für andere Systeme
# ---------------------------------------------------------------------------

## Persönliche Ursache für eine Weile (EventSystem: Dankbarkeit, Aufgehalten …)
func add_personal(u: Unit, cause: String, value: float, seconds: float) -> void:
	if not is_instance_valid(u):
		return
	var list: Array = personal.get(u.uid, [])
	for i in range(list.size() - 1, -1, -1):
		if str((list[i] as Dictionary)["cause"]) == cause:
			list.remove_at(i)
	list.append({"cause": cause, "value": value, "until": GameClock.game_time + seconds})
	personal[u.uid] = list


## Eingeschleuster Spion unter Aufgenommenen (EventSystem): verrät regelmässig victim an den Besitzer
func register_hidden_spy(u: Unit, victim: Kingdom, owner_k: Kingdom) -> void:
	if not is_instance_valid(u) or victim == null or owner_k == null:
		return
	hidden_spies[u.uid] = {"uid": u.uid, "victim_id": victim.id, "owner_id": owner_k.id, "next_leak": -1.0}


## Überlaufen beginnen: Ziel wählen (oder forced_dest), Beruf ablegen, losschicken.
## traitor = entlarvter Verräter (läuft zum Empfänger, lässt sich nicht aufhalten).
func start_defection(u: Unit, traitor: bool = false, forced_dest: Kingdom = null) -> bool:
	if not is_instance_valid(u) or not u.is_alive() or u.kingdom == null:
		return false
	var from := u.kingdom
	var now := GameClock.game_time
	var pick := _pick_destination(u, forced_dest)
	var kind := str(pick.get("kind", "edge"))
	var dest_k: Kingdom = pick.get("kingdom", null)
	var dest: Vector2 = pick.get("pos", Vector2(-1, -1))
	var old: Dictionary = defectors.get(u.uid, {})
	if dest.x < 0.0:
		# Kein erreichbarer Rand: der Bewohner verschwindet sofort
		defectors.erase(u.uid)
		from.add_stat("defected")
		_log(from, "Ein Bewohner hat das Reich verlassen")
		defected.emit(u, from, "edge", null)
		game.unit_system.remove_unit(u)
		return true
	game.work_system.set_unit_job(u, "idle")
	game.command_system.order_travel(u, dest, "defect")
	defectors[u.uid] = {"uid": u.uid, "from_id": from.id, "dest_kind": kind, "dest_id": dest_k.id if dest_k != null else 0,
			"dest": dest, "since": float(old.get("since", now)), "traitor": traitor or bool(old.get("traitor", false)),
			"retries": 0}
	if old.is_empty():
		defection_started.emit(u, from, kind, dest_k)
		if not traitor:
			from.notify("Ein unzufriedener Bewohner läuft %s über! Befehl geben hält ihn auf." % _dest_phrase(defectors[u.uid]),
					"warning", u.position)
			_log(from, "Ein Bewohner läuft %s über" % _dest_phrase(defectors[u.uid]))
	return true


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	_acc += dt
	_maint_acc += dt
	var now := GameClock.game_time
	if _acc >= KINGDOM_STEP:
		_acc = 0.0
		var t0 := Time.get_ticks_usec()
		var k := _next_kingdom()
		if k != null:
			_rng.state = rng_state
			var st := _state(k)
			var dt_k := 0.0 if float(st["last_tick"]) < 0.0 else maxf(now - float(st["last_tick"]), 0.0)
			st["last_tick"] = now
			_tick_kingdom(k, st, dt_k, now)
			rng_state = _rng.state
		var used := Time.get_ticks_usec() - t0
		tick_usec_total += used
		tick_usec_max = maxi(tick_usec_max, used)
		tick_count += 1
	if _maint_acc >= 1.0:
		_maint_acc = 0.0
		_rng.state = rng_state
		_maintain(now)
		rng_state = _rng.state


func _next_kingdom() -> Kingdom:
	var list: Array = game.kingdoms
	for _i in list.size():
		_rr = (_rr + 1) % maxi(list.size(), 1)
		var k: Kingdom = list[_rr]
		if is_tracked(k):
			return k
	return null


func _tick_kingdom(k: Kingdom, st: Dictionary, dt_k: float, now: float) -> void:
	_inh_cache.clear()
	_inh_cache[k.id] = _inhabitant_count(k)
	if now - float(st["last_scan"]) >= float(DataDB.sat("safety.scan_seconds", 5)) or float(st["last_scan"]) < 0.0:
		st["last_scan"] = now
		_scan_safety(k, st)
	var parts := _compute_parts(k, st, now)
	st["parts"] = parts
	var kingdom_sum := 0.0
	for p in parts:
		kingdom_sum += float(p[1])
	# Bewohner nähern sich ihrem Ziel
	var step := float(DataDB.sat("approach_per_minute", 8)) * dt_k / 60.0
	var es: Variant = game.get("event_system")
	var total := 0.0
	var n := 0
	for u in k.units:
		if not bool(u.type_def.get("needs_housing", false)) or not u.is_alive():
			continue
		if not _seen_since.has(u.uid):
			_seen_since[u.uid] = now
		_track_idle(u, now)
		var target := clampf(kingdom_sum + _personal_sum(u, now), 0.0, 100.0)
		if u.satisfaction < 0.0:
			u.satisfaction = target
		else:
			u.satisfaction = clampf(move_toward(u.satisfaction, target, step), 0.0, 100.0)
		var mult := work_mult_for(u.satisfaction)
		if not abort_until.is_empty() and float(abort_until.get(u.uid, -1.0)) > now:
			mult *= float(_cfg["abort_mult"])
		if es != null:
			mult *= float(es.get_plague_work_mult(u))
		u.work_mult = mult
		total += u.satisfaction
		n += 1
	var avg := total / n if n > 0 else -1.0
	var before := float(st["avg"])
	st["avg"] = avg
	if absf(avg - before) >= 0.5:
		satisfaction_changed.emit(k, avg)
	# Fest vorbei
	if float(st["feast_until"]) > 0.0 and now >= float(st["feast_until"]):
		st["feast_until"] = -1.0
		k.clear_bonuses("feast")
		k.notify("Das Fest ist vorbei.", "info")
	if k.is_player and n > 0:
		_notify_average(k, st, avg, parts, now)
	_check_defection(k, st, now)
	_check_betrayal(k, st, now)
	_inh_cache.clear()


## Feinde und eigene Truppen im eigenen Gebiet zählen
func _scan_safety(k: Kingdom, st: Dictionary) -> void:
	var bbox := TerritorySystem.kingdom_bbox(k, world)
	var enemies := 0
	var troops := 0
	if bbox.size.x > 0:
		var ts := float(world.tile_size)
		var center := (Vector2(bbox.position) + Vector2(bbox.size) * 0.5) * ts
		var radius := Vector2(bbox.size).length() * 0.5 * ts
		var index: SpatialIndex = game.combat_system.index
		var checked := 0
		for kid in index.kingdom_ids():
			var other: Kingdom = game.get_kingdom(int(kid))
			if other == null or not game.are_hostile(k, other) or not index.any_of_kingdom(center, radius, int(kid)):
				continue
			for o in index.query_kingdom(center, radius, int(kid)):
				checked += 1
				if checked > SCAN_LIMIT:
					break
				var e: Unit = o
				if e.is_alive() and world.get_owner(world.world_to_cell(e.position)) == k.id and game.can_see(k, e):
					enemies += 1
		for u in k.units:
			var role: String = u.role
			if (role == "combat" or role == "hero" or role == "support") and u.is_alive() \
					and world.get_owner(world.world_to_cell(u.position)) == k.id:
				troops += 1
	st["enemies"] = enemies
	st["troops_ratio"] = float(troops) / maxf(float(_inhabitant_count(k)), 1.0)


## Reichsursachen [[Ursache, Wert, Art], …]
func _compute_parts(k: Kingdom, st: Dictionary, now: float) -> Array:
	var parts: Array = []
	parts.append(["Grundstimmung", float(DataDB.sat("base", 60)), "base"])
	var faction: Dictionary = DataDB.sat("faction." + k.faction_id, {})
	var fbase := float(faction.get("base", 0.0))
	if absf(fbase) > 0.001:
		parts.append(["Fraktion", fbase, "base"])
	if not k.people_id.is_empty():
		var pv := float(DataDB.sat("people." + k.people_id, 0.0))
		if absf(pv) > 0.001:
			parts.append(["Volk: %s" % DataDB.get_people_name(k.people_id), pv, "base"])
	# Nahrung
	if k.starving:
		parts.append(["Hunger", float(DataDB.sat("food.starving", -35)), "food"])
	else:
		var per_min: float = game.economy_system.get_food_consumption_per_minute(k)
		if per_min > 0.0:
			var days := k.get_amount("food") / (per_min * GameClock.seconds_per_day / 60.0)
			if days < float(DataDB.sat("food.low_days", 0.5)):
				parts.append(["Vorräte knapp", float(DataDB.sat("food.low", -10)), "food"])
			elif days >= float(DataDB.sat("food.plenty_days", 2.0)):
				parts.append(["Volle Speicher", float(DataDB.sat("food.plenty", 5)), "food"])
	# Wohnraum
	var pop := k.get_population()
	var housing := k.get_housing()
	if pop > 0:
		var over := float(pop) / maxf(float(housing), 1.0) - 1.0
		if over > 0.0:
			parts.append(["Überfüllt", maxf(float(DataDB.sat("housing.crowded_per_ratio", -50)) * over,
					float(DataDB.sat("housing.crowded_max", -30))), "housing"])
		elif housing > 0 and float(housing - pop) / float(housing) >= float(DataDB.sat("housing.free_ratio", 0.1)):
			parts.append(["Platz genug", float(DataDB.sat("housing.free", 4)), "housing"])
	# Sicherheit
	var enemies := int(st["enemies"])
	if enemies > 0:
		var v := float(DataDB.sat("safety.enemies_inside", -12))
		if enemies >= int(DataDB.sat("safety.many_count", 8)):
			v += float(DataDB.sat("safety.many_extra", -8))
		parts.append(["Feinde im Gebiet", v, "safety"])
	var attacks: Array = st["attacks"]
	if not attacks.is_empty():
		var age := now - float(attacks[attacks.size() - 1])
		var dur := float(DataDB.sat("safety.attack_seconds", 300))
		if age < dur:
			parts.append(["Angriff auf das Reich", float(DataDB.sat("safety.attack", -12)) * (1.0 - age / dur), "safety"])
	var lost := _decayed(st["lost_buildings"], now, float(DataDB.sat("safety.building_lost", -6)),
			float(DataDB.sat("safety.building_lost_seconds", 600)), float(DataDB.sat("safety.building_lost_max", -18)))
	if lost < -0.05:
		parts.append(["Gebäude verloren", lost, "safety"])
	var deaths := _decayed(st["deaths"], now, float(DataDB.sat("safety.death", -3)),
			float(DataDB.sat("safety.death_seconds", 600)), float(DataDB.sat("safety.death_max", -12)))
	if deaths < -0.05:
		parts.append(["Bewohner getötet", deaths, "safety"])
	var ratio := float(st["troops_ratio"])
	if ratio > 0.0:
		var troops_v := float(DataDB.sat("safety.troops", 6)) * float(faction.get("troops_mult", 1.0)) \
				* minf(1.0, ratio / maxf(float(DataDB.sat("safety.troops_full_ratio", 0.25)), 0.01))
		if troops_v >= 0.5:
			parts.append(["Schutz durch Truppen", troops_v, "safety"])
	# Mauerring um die Burg und Türme (Phase 9, siege.json → safety)
	var siege: Variant = game.get("siege_system")
	if siege != null:
		var fort_v := float(siege.get_safety_bonus(k))
		if fort_v >= 0.5:
			parts.append(["Schutz durch Mauern und Türme", fort_v, "safety"])
	# Gebäude (Taverne, Tempel): Plätze aller fertigen Gebäude je Typ
	var caps := {}
	for b in k.buildings:
		if not is_instance_valid(b) or not b.constructed:
			continue
		var sat: Dictionary = b.def.get("satisfaction", {})
		if sat.is_empty():
			continue
		var bid := str(b.def.get("id", ""))
		caps[bid] = int(caps.get(bid, 0)) + int(sat.get("capacity", 0))
	for bid in caps:
		var def := DataDB.get_building(str(bid))
		var sat: Dictionary = def.get("satisfaction", {})
		var cover := minf(1.0, float(caps[bid]) / maxf(float(_inhabitant_count(k)), 1.0))
		parts.append([DataDB.get_building_name(def, k.faction_id), float(sat.get("bonus", 0)) * cover, "building"])
	# Idle: persönlich; Ereignisse
	var es: Variant = game.get("event_system")
	if es != null:
		for p in es.get_satisfaction_parts(k):
			parts.append([str(p[0]), float(p[1]), "event"])
	# Reichsboni (Forschung, Fest)
	for src in k.bonus_sources:
		var entry: Dictionary = k.bonus_sources[src]
		var bv := float(entry.get("satisfaction", 0.0))
		if absf(bv) > 0.001:
			parts.append([DataDB.describe_effect_source(str(src)), bv, "bonus"])
	if k.controller == "ai":
		var ai_v := float(DataDB.sat("ai_bonus." + GameSession.difficulty_id, 0.0))
		if absf(ai_v) > 0.001:
			parts.append(["Schwierigkeit", ai_v, "base"])
	return parts


## Summe abklingender Ereignisse: je Eintrag value × (1 − Alter/Dauer), gekappt bei cap
static func _decayed(times: Array, now: float, value: float, duration: float, cap: float) -> float:
	var total := 0.0
	for t in times:
		var age := now - float(t)
		if age < duration:
			total += value * (1.0 - age / maxf(duration, 1.0))
	return maxf(total, cap)


## Persönliche Ursachen [[Ursache, Wert], …]
func _personal_parts(u: Unit, now: float) -> Array:
	var parts: Array = []
	var spread := float(_cfg["spread"])
	var mood := (float(absi(hash(u.uid * 7919)) % 1000) / 1000.0 * 2.0 - 1.0) * spread
	if absf(mood) >= 0.5:
		parts.append(["Laune", mood])
	var es: Variant = game.get("event_system")
	if es != null and bool(es.is_infected(u)):
		parts.append(["Seuche", float(_cfg["plague"])])
	if u.can_work() and u.job_id == "idle" and _idle_since.has(u.uid) \
			and now - float(_idle_since[u.uid]) > float(_cfg["idle_s"]):
		parts.append(["Ohne Arbeit", float(_cfg["idle_v"])])
	for e in personal.get(u.uid, []):
		var entry: Dictionary = e
		if float(entry["until"]) > now:
			parts.append([str(entry["cause"]), float(entry["value"])])
	return parts


func _personal_sum(u: Unit, now: float) -> float:
	var total := 0.0
	for p in _personal_parts(u, now):
		total += float(p[1])
	return total


func _kingdom_sum(k: Kingdom) -> float:
	var total := 0.0
	for p in (kingdoms_state.get(k.id, {}) as Dictionary).get("parts", []):
		total += float(p[1])
	return total


func _track_idle(u: Unit, now: float) -> void:
	if u.job_id == "idle" and u.command.is_empty():
		if not _idle_since.has(u.uid):
			_idle_since[u.uid] = now
	else:
		_idle_since.erase(u.uid)


## Warnung an den Spieler, wenn der Durchschnitt unter avg_low bzw. avg_critical fällt
func _notify_average(k: Kingdom, st: Dictionary, avg: float, parts: Array, now: float) -> void:
	var tier := 0
	if avg < float(DataDB.sat("notify.avg_critical", 25)):
		tier = 2
	elif avg < float(DataDB.sat("notify.avg_low", 40)):
		tier = 1
	var notified := int(st["notified_tier"])
	if tier <= notified:
		st["notified_tier"] = tier
		return
	if now - float(st["notified_at"]) < float(DataDB.sat("notify.interval", 600)):
		return
	st["notified_tier"] = tier
	st["notified_at"] = now
	var neg: Array = []
	for p in parts:
		if float(p[1]) < 0.0:
			neg.append(p)
	neg.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	var causes: PackedStringArray = []
	for i in mini(2, neg.size()):
		causes.append(str(neg[i][0]))
	var text := "Deine Bewohner sind unzufrieden (Ø %d)" % roundi(avg)
	if not causes.is_empty():
		text += ": " + ", ".join(causes)
	text += ". Reich (L)"
	var link := {"window": "kingdom", "tab": "satisfaction"}
	if is_instance_valid(k.castle):
		link["pos"] = k.castle.get_center()
	k.notify(text, "danger" if tier == 2 else "warning", link)


## Würfel fürs Überlaufen (alle check_seconds)
func _check_defection(k: Kingdom, st: Dictionary, now: float) -> void:
	var interval := float(DataDB.sat("defection.check_seconds", 30))
	if float(st["next_defect_check"]) < 0.0:
		st["next_defect_check"] = now + interval
		return
	if now < float(st["next_defect_check"]):
		return
	st["next_defect_check"] = now + interval
	if now < float(DataDB.sat("defection.min_minutes", 15)) * 60.0 \
			or now - float(st["last_defection"]) < float(DataDB.sat("defection.kingdom_gap", 180)):
		return
	var below := float(DataDB.sat("defection.below", 25))
	var chance := float(DataDB.sat("defection.chance", 0.08)) * (1.0 - clampf(k.bonus("loyalty"), 0.0, 0.95))
	var newcomer := float(DataDB.sat("defection.newcomer_seconds", 300))
	for u in k.units.duplicate():
		if not _may_leave(u, below, newcomer, now):
			continue
		if _rng.randf() < chance * (below - u.satisfaction) / below:
			if start_defection(u):
				st["last_defection"] = now
			return


## Würfel für Verrat (alle check_seconds, nur mit feindlichem Empfänger)
func _check_betrayal(k: Kingdom, st: Dictionary, now: float) -> void:
	var interval := float(DataDB.sat("betrayal.check_seconds", 60))
	if float(st["next_betray_check"]) < 0.0:
		st["next_betray_check"] = now + interval
		return
	if now < float(st["next_betray_check"]):
		return
	st["next_betray_check"] = now + interval
	if now < float(DataDB.sat("betrayal.min_minutes", 30)) * 60.0 \
			or now - float(st["last_betrayal"]) < float(DataDB.sat("betrayal.kingdom_gap", 900)):
		return
	var receiver := _pick_receiver(k)
	if receiver == null:
		return
	var below := float(DataDB.sat("betrayal.below", 20))
	var chance := float(DataDB.sat("betrayal.chance", 0.04)) * (1.0 - clampf(k.bonus("loyalty"), 0.0, 0.95))
	var newcomer := float(DataDB.sat("defection.newcomer_seconds", 300))
	for u in k.units.duplicate():
		if not _may_leave(u, below, newcomer, now):
			continue
		if _rng.randf() < chance * (below - u.satisfaction) / below:
			_betray(k, u, receiver)
			return


func _may_leave(u: Unit, below: float, newcomer: float, now: float) -> bool:
	return is_inhabitant(u) and u.satisfaction >= 0.0 and u.satisfaction < below and not is_defector(u) \
			and u.hero_id == 0 and u.role != "king" and now - float(_seen_since.get(u.uid, now)) >= newcomer


## Verrat: der Empfänger erfährt viel; vielleicht wird der Verräter sofort entlarvt
func _betray(k: Kingdom, u: Unit, receiver: Kingdom) -> void:
	var st := _state(k)
	var now := GameClock.game_time
	var esp: Variant = game.get("espionage_system")
	if esp != null and (esp as Object).has_method("report_betrayal"):
		esp.report_betrayal(k, receiver)
	k.add_stat("betrayals")
	st["last_betrayal"] = now
	var chance := float(DataDB.sat("betrayal.discover_chance", 0.35))
	if _has_temple(k):
		chance += float(DataDB.sat("betrayal.temple_discover_bonus", 0.25))
	var discovered := _rng.randf() < chance
	if discovered:
		k.notify("Ein Verräter wurde entlarvt – er flieht zu %s!" % receiver.display_name, "danger", u.position)
		_log(k, "Verräter entlarvt (zu %s)" % receiver.display_name)
		start_defection(u, true, receiver)
	else:
		var range_list: Array = DataDB.sat("betrayal.late_discover_seconds", [300, 900])
		late_reports.append({"victim_id": k.id, "receiver_id": receiver.id,
				"at": now + _rng.randf_range(float(range_list[0]), float(range_list[range_list.size() - 1]))})
	receiver.notify("Ein Verräter aus %s liefert dir Kundschaft." % k.display_name, "good")
	betrayed.emit(k, receiver, discovered)


## Empfänger eines Verrats: feindliche Partei mit der höchsten Aufmerksamkeit auf k
## (bei Gleichstand die nächste); ohne EspionageSystem keiner
func _pick_receiver(k: Kingdom) -> Kingdom:
	var esp: Variant = game.get("espionage_system")
	if esp == null or not (esp as Object).has_method("is_party") or not (esp as Object).has_method("get_awareness"):
		return null
	var best: Kingdom = null
	var best_aw := -1.0
	var best_d := INF
	var from := k.castle.get_center() if is_instance_valid(k.castle) else Vector2.ZERO
	for e in game.kingdoms:
		var other: Kingdom = e
		if other == k or not bool(esp.is_party(other)) or not game.are_hostile(k, other):
			continue
		var aw := float(esp.get_awareness(other, k))
		var d := from.distance_to(other.castle.get_center()) if is_instance_valid(other.castle) else INF
		if aw > best_aw + 0.001 or (absf(aw - best_aw) <= 0.001 and d < best_d):
			best = other
			best_aw = aw
			best_d = d
	return best


# ---------------------------------------------------------------------------
# Pflege: Überläufer, eingeschleuste Spione, späte Meldungen (jede Sekunde)
# ---------------------------------------------------------------------------

func _maintain(now: float) -> void:
	var pending := _pending
	_pending = []
	for entry in pending:
		_process_arrival(int(entry[0]), bool(entry[1]), now)
	for uid in defectors.keys():
		if not defectors.has(uid):
			continue
		var rec: Dictionary = defectors[uid]
		var u: Variant = game.find_by_uid(int(uid))
		if not (u is Unit) or not (u as Unit).is_alive() or (u as Unit).kingdom == null \
				or (u as Unit).kingdom.id != int(rec["from_id"]):
			defectors.erase(uid)
			continue
		var unit: Unit = u
		var traitor := bool(rec.get("traitor", false))
		if str(rec["dest_kind"]) != "edge":
			var dest_k: Kingdom = game.get_kingdom(int(rec["dest_id"]))
			var gone := dest_k == null or dest_k.defeated
			if str(rec["dest_kind"]) == "village" and not gone:
				gone = not game.village_system.is_village(dest_k)
			if gone:
				start_defection(unit, traitor, null)
				continue
		if unit.command != "defect":
			if traitor:
				game.command_system.order_travel(unit, rec["dest"], "defect")
			else:
				_abort(unit, rec, now)
	for uid in hidden_spies.keys():
		_tick_hidden_spy(int(uid), now)
	for i in range(late_reports.size() - 1, -1, -1):
		var r: Dictionary = late_reports[i]
		if float(r["at"]) > now:
			continue
		late_reports.remove_at(i)
		var victim: Kingdom = game.get_kingdom(int(r["victim_id"]))
		var receiver: Kingdom = game.get_kingdom(int(r["receiver_id"]))
		if victim != null and receiver != null and not victim.defeated:
			victim.notify("Späte Erkenntnis: Ein Verräter hat %s Wissen über dein Reich verraten." % receiver.display_name,
					"warning", {"window": "kingdom", "tab": "satisfaction"})
			_log(victim, "Verrat an %s entdeckt" % receiver.display_name)


## Der Spieler hat dem Überläufer einen Befehl gegeben: er bleibt – widerwillig
func _abort(u: Unit, _rec: Dictionary, now: float) -> void:
	defectors.erase(u.uid)
	var seconds := float(DataDB.sat("defection.abort_seconds", 300))
	abort_until[u.uid] = now + seconds
	add_personal(u, "Widerwillig", -5.0, seconds)
	u.kingdom.notify("Der Bewohner bleibt – widerwillig.", "info", u.position)
	_log(u.kingdom, "Ein Überläufer wurde aufgehalten")


func _tick_hidden_spy(uid: int, now: float) -> void:
	var rec: Dictionary = hidden_spies[uid]
	var u: Variant = game.find_by_uid(uid)
	var victim: Kingdom = game.get_kingdom(int(rec["victim_id"]))
	var owner_k: Kingdom = game.get_kingdom(int(rec["owner_id"]))
	if not (u is Unit) or not (u as Unit).is_alive() or victim == null or owner_k == null or owner_k.defeated \
			or (u as Unit).kingdom != victim:
		hidden_spies.erase(uid)
		return
	var leak := float(DataDB.sat("hidden_spy.leak_seconds", 600))
	if float(rec["next_leak"]) < 0.0:
		rec["next_leak"] = now + leak
		return
	if now < float(rec["next_leak"]):
		return
	var esp: Variant = game.get("espionage_system")
	if esp != null and (esp as Object).has_method("report_betrayal"):
		esp.report_betrayal(victim, owner_k)
	var chance := float(DataDB.sat("hidden_spy.discover_chance", 0.2)) \
			+ victim.bonus("vigilance") * float(DataDB.sat("hidden_spy.vigilance_factor", 0.1))
	if _has_temple(victim):
		chance += float(DataDB.sat("hidden_spy.temple_discover_bonus", 0.2))
	if _rng.randf() < chance:
		hidden_spies.erase(uid)
		var unit: Unit = u
		victim.notify("Unter den Aufgenommenen war ein Spion aus %s – er flieht!" % owner_k.display_name, "danger", unit.position)
		_log(victim, "Eingeschleuster Spion aus %s entlarvt" % owner_k.display_name)
		start_defection(unit, true, owner_k)
	else:
		rec["next_leak"] = float(rec["next_leak"]) + leak


## Überläufer am Ziel (ok) oder ohne Weg (nicht ok)
func _process_arrival(uid: int, ok: bool, now: float) -> void:
	if not defectors.has(uid):
		return
	var rec: Dictionary = defectors[uid]
	var u: Variant = game.find_by_uid(uid)
	if not (u is Unit) or not (u as Unit).is_alive():
		defectors.erase(uid)
		return
	var unit: Unit = u
	var from: Kingdom = game.get_kingdom(int(rec["from_id"]))
	var kind := str(rec["dest_kind"])
	var dest_k: Kingdom = game.get_kingdom(int(rec["dest_id"]))
	if not ok:
		var retries := int(rec.get("retries", 0))
		if retries < 2:
			rec["retries"] = retries + 1
			var c: Vector2i = game.nav.nearest_free(world.world_to_cell(rec["dest"]), 6)
			if c.x >= 0:
				rec["dest"] = world.cell_to_world(c)
			game.command_system.order_travel(unit, rec["dest"], "defect")
			return
		if kind != "edge":
			rec["dest_kind"] = "edge"
			var edge := _edge_point(unit.position)
			if edge.x >= 0.0:
				rec["dest"] = edge
				rec["dest_id"] = 0
				rec["retries"] = 0
				game.command_system.order_travel(unit, edge, "defect")
				return
		kind = "edge"
	if kind == "kingdom" and (dest_k == null or dest_k.defeated):
		start_defection(unit, bool(rec.get("traitor", false)), null)
		return
	defectors.erase(uid)
	match kind:
		"kingdom":
			game.unit_system.transfer_unit(unit, dest_k)
			game.work_system.set_unit_job(unit, "idle")
			game.command_system.order_return_to_work([unit])
			unit.satisfaction = float(DataDB.sat("defection.arrive_satisfaction", 50))
			_seen_since[unit.uid] = now
			dest_k.add_stat("defectors_received")
			var esp: Variant = game.get("espionage_system")
			if esp != null and from != null and (esp as Object).has_method("grant_intel"):
				esp.grant_intel(dest_k, from, int(DataDB.sat("defection.intel_level", 1)), "Überläufer")
			dest_k.notify("Ein Überläufer aus %s ist angekommen." % (from.display_name if from != null else "?"), "good", unit.position)
			_log(dest_k, "Überläufer aus %s aufgenommen" % (from.display_name if from != null else "?"))
		"village":
			if dest_k != null:
				game.village_system.add_population(dest_k, 1)
			defected.emit(unit, from, kind, dest_k)
			game.unit_system.remove_unit(unit)
		_:
			defected.emit(unit, from, kind, null)
			game.unit_system.remove_unit(unit)
	if from != null:
		from.add_stat("defected")
		_log(from, "Ein Bewohner lief %s über" % _dest_phrase({"dest_kind": kind, "dest_id": dest_k.id if dest_k != null else 0}))
	if kind == "kingdom":
		defected.emit(unit, from, kind, dest_k)


func _on_command_finished(u: Unit, cmd: String, ok: bool) -> void:
	if cmd == "defect" and is_instance_valid(u) and defectors.has(u.uid):
		_pending.append([u.uid, ok])


# ---------------------------------------------------------------------------
# Zielwahl
# ---------------------------------------------------------------------------

## Ziel eines Überläufers: {"kind": "kingdom"|"village"|"edge", "kingdom": Kingdom|null, "pos": Vector2}
func _pick_destination(u: Unit, forced: Kingdom) -> Dictionary:
	var vs: VillageSystem = game.village_system
	if forced != null and not forced.defeated:
		if vs.is_village(forced):
			var hall := vs.get_hall(forced)
			if hall != null:
				return {"kind": "village", "kingdom": forced, "pos": hall.get_approach_point(u.position)}
		elif is_instance_valid(forced.castle):
			return {"kind": "kingdom", "kingdom": forced, "pos": forced.castle.get_approach_point(u.position)}
	var ts := float(world.tile_size)
	var max_d := float(DataDB.sat("defection.max_distance", 140)) * ts
	var weights: Dictionary = DataDB.sat("defection.weights", {})
	var best := {}
	var best_score := -1.0
	var esp: Variant = game.get("espionage_system")
	for e in game.kingdoms:
		var k: Kingdom = e
		if k == u.kingdom or k.defeated or not is_instance_valid(k.castle):
			continue
		var party := (k.controller == "player" or k.controller == "ai")
		if esp != null and (esp as Object).has_method("is_party"):
			party = bool(esp.is_party(k))
		if not party:
			continue
		var d := u.position.distance_to(k.castle.get_center())
		if d > max_d:
			continue
		var avg := get_average(k)
		var score := float(weights.get("kingdom", 1.0)) * (avg if avg >= 0.0 else 60.0) / 100.0 / (1.0 + d / ts / 50.0)
		if score > best_score:
			best_score = score
			best = {"kind": "kingdom", "kingdom": k, "pos": k.castle.get_approach_point(u.position)}
	for v in vs.get_villages():
		var hall := vs.get_hall(v)
		if hall == null:
			continue
		var d := u.position.distance_to(hall.get_center())
		if d > max_d:
			continue
		var score := float(weights.get("village", 1.0)) * 0.6 / (1.0 + d / ts / 50.0)
		if score > best_score:
			best_score = score
			best = {"kind": "village", "kingdom": v, "pos": hall.get_approach_point(u.position)}
	var edge := _edge_point(u.position)
	if edge.x >= 0.0:
		var score := float(weights.get("edge", 0.5)) * 0.6 / (1.0 + u.position.distance_to(edge) / ts / 50.0)
		if score > best_score or best.is_empty():
			best = {"kind": "edge", "kingdom": null, "pos": edge}
	if best.is_empty():
		return {"kind": "edge", "kingdom": null, "pos": Vector2(-1, -1)}
	return best


## Nächster freier Punkt am Kartenrand (mit edge_margin), (-1, -1) wenn keiner
func _edge_point(pos: Vector2) -> Vector2:
	var c := world.world_to_cell(pos)
	var margin := int(DataDB.sat("defection.edge_margin", 3))
	var options := [
		[c.x, Vector2i(margin, c.y)], [world.width - 1 - c.x, Vector2i(world.width - 1 - margin, c.y)],
		[c.y, Vector2i(c.x, margin)], [world.height - 1 - c.y, Vector2i(c.x, world.height - 1 - margin)]]
	options.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	for o in options:
		var cell: Vector2i = o[1]
		cell = Vector2i(clampi(cell.x, 0, world.width - 1), clampi(cell.y, 0, world.height - 1))
		var free: Vector2i = game.nav.nearest_free(cell, 8)
		if free.x >= 0:
			return world.cell_to_world(free)
	return Vector2(-1, -1)


func _dest_name(rec: Dictionary) -> String:
	match str(rec.get("dest_kind", "edge")):
		"kingdom", "village":
			var k: Kingdom = game.get_kingdom(int(rec.get("dest_id", 0)))
			return k.display_name if k != null else "?"
	return "den Kartenrand"


## "zu Zwergendorf Eisenhall" bzw. "aus dem Land" (Kartenrand)
func _dest_phrase(rec: Dictionary) -> String:
	if str(rec.get("dest_kind", "edge")) == "edge":
		return "aus dem Land"
	return "zu " + _dest_name(rec)


# ---------------------------------------------------------------------------
# Kampfsignale (nur Zeitstempel)
# ---------------------------------------------------------------------------

func _on_kingdom_attacked(victim: Kingdom, _attacker: Kingdom, pos: Vector2) -> void:
	if not is_tracked(victim) or world.get_owner(world.world_to_cell(pos)) != victim.id:
		return
	_state(victim)["attacks"] = [GameClock.game_time]


func _on_building_destroyed(b: Building, _killer: Kingdom) -> void:
	# Mauerstücke und Tore (Phase 9) zählen nicht als verlorene Gebäude
	if b == null or b.is_segment or not is_tracked(b.kingdom):
		return
	_push_time(_state(b.kingdom)["lost_buildings"])


func _on_unit_died(u: Unit, _killer: Kingdom) -> void:
	if u == null or u.kingdom == null or not is_tracked(u.kingdom) or not bool(u.type_def.get("needs_housing", false)):
		return
	_push_time(_state(u.kingdom)["deaths"])


func _on_unit_removed(u: Unit) -> void:
	_idle_since.erase(u.uid)
	_seen_since.erase(u.uid)
	personal.erase(u.uid)
	abort_until.erase(u.uid)
	hidden_spies.erase(u.uid)
	defectors.erase(u.uid)


static func _push_time(list: Array) -> void:
	list.append(GameClock.game_time)
	while list.size() > TIME_LIST_SIZE:
		list.remove_at(0)


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

func _state(k: Kingdom) -> Dictionary:
	if not kingdoms_state.has(k.id):
		kingdoms_state[k.id] = _new_state()
	return kingdoms_state[k.id]


func _load_cfg() -> void:
	_cfg = {"spread": float(DataDB.sat("personal_spread", 6)), "idle_s": float(DataDB.sat("idle.seconds", 180)),
			"idle_v": float(DataDB.sat("idle.value", -4)), "abort_mult": float(DataDB.sat("defection.abort_work_mult", 0.5)),
			"plague": float(DataDB.get_event("plague").get("satisfaction_infected", -15))}


static func _new_state() -> Dictionary:
	return {"avg": -1.0, "parts": [], "last_tick": -1.0, "last_scan": -1.0, "enemies": 0, "troops_ratio": 0.0,
			"attacks": [], "lost_buildings": [], "deaths": [], "next_defect_check": -1.0, "next_betray_check": -1.0,
			"last_defection": -1.0e9, "last_betrayal": -1.0e9, "feast_until": -1.0, "feast_ready": -1.0,
			"notified_at": -1.0e9, "notified_tier": 0, "log": []}


func _inhabitant_count(k: Kingdom) -> int:
	if _inh_cache.has(k.id):
		return int(_inh_cache[k.id])
	var n := 0
	for u in k.units:
		if bool(u.type_def.get("needs_housing", false)) and u.is_alive():
			n += 1
	return n


## Hat das Reich einen fertigen Tempel (Gebäude mit satisfaction.discover_bonus)?
func _has_temple(k: Kingdom) -> bool:
	for b in k.buildings:
		if is_instance_valid(b) and b.constructed and float((b.def.get("satisfaction", {}) as Dictionary).get("discover_bonus", 0.0)) > 0.0:
			return true
	return false


func _log(k: Kingdom, text: String) -> void:
	if k == null:
		return
	var log_list: Array = _state(k)["log"]
	log_list.append({"t": GameClock.game_time, "text": text})
	while log_list.size() > LOG_SIZE:
		log_list.remove_at(0)


static func _time_text(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	if s >= 60:
		return "%d min" % ceili(s / 60.0)
	return "%d s" % s


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"kingdoms_state": kingdoms_state.duplicate(true), "defectors": defectors.duplicate(true),
			"hidden_spies": hidden_spies.duplicate(true), "personal": personal.duplicate(true),
			"abort_until": abort_until.duplicate(), "late_reports": late_reports.duplicate(true), "rng_state": rng_state,
			"pending": _pending.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	kingdoms_state = (d.get("kingdoms_state", {}) as Dictionary).duplicate(true)
	defectors = (d.get("defectors", {}) as Dictionary).duplicate(true)
	hidden_spies = (d.get("hidden_spies", {}) as Dictionary).duplicate(true)
	personal = (d.get("personal", {}) as Dictionary).duplicate(true)
	abort_until = (d.get("abort_until", {}) as Dictionary).duplicate()
	late_reports = (d.get("late_reports", []) as Array).duplicate(true)
	rng_state = int(d.get("rng_state", rng_state))
	_pending = (d.get("pending", []) as Array).duplicate(true)


## Arbeitsleistung aller Bewohner neu, Überläufer erneut losschicken, Feste prüfen
func rebuild_runtime() -> void:
	_load_cfg()
	# _pending (Ankünfte von Überläufern) ist gespeichert und bleibt
	_idle_since.clear()
	_seen_since.clear()
	_acc = 0.0
	_maint_acc = 0.0
	_rng.state = rng_state
	var now := GameClock.game_time
	for u in game.unit_system.units:
		var unit: Unit = u
		if not bool(unit.type_def.get("needs_housing", false)):
			unit.work_mult = 1.0
			continue
		_seen_since[unit.uid] = now
		unit.work_mult = work_mult_for(unit.satisfaction) if unit.satisfaction >= 0.0 else 1.0
	for uid in defectors.keys():
		var u: Variant = game.find_by_uid(int(uid))
		if not (u is Unit):
			defectors.erase(uid)
			continue
		# Mit gespeichertem Weg (SaveGame) läuft er schon weiter – nur ohne Weg neu losschicken
		if (u as Unit).command == "defect" and not (u as Unit).moving and not (u as Unit).path_pending:
			game.command_system.order_travel(u, (defectors[uid] as Dictionary)["dest"], "defect")
	for kid in kingdoms_state:
		var k: Kingdom = game.get_kingdom(int(kid))
		var st: Dictionary = kingdoms_state[kid]
		if k != null and float(st.get("feast_until", -1.0)) > now and not k.bonus_sources.has("feast"):
			k.set_bonus("feast", "satisfaction", float(DataDB.sat("feast.bonus", 15)))


# ---------------------------------------------------------------------------
# Debug (F3-Knöpfe, Rauchtest)
# ---------------------------------------------------------------------------

## Alle Bewohner auf value setzen (der Zielwert bleibt; sie nähern sich ihm wieder)
func debug_set_all(k: Kingdom, value: float) -> void:
	if k == null:
		return
	for u in k.units:
		if is_inhabitant(u):
			u.satisfaction = clampf(value, 0.0, 100.0)
			u.work_mult = work_mult_for(u.satisfaction)
	var st := _state(k)
	st["avg"] = clampf(value, 0.0, 100.0)
	satisfaction_changed.emit(k, float(st["avg"]))


## Den unzufriedensten Bewohner überlaufen lassen (ohne Würfel und Sperren)
func debug_force_defection(k: Kingdom) -> Unit:
	var u := _least_satisfied(k)
	if u == null or not start_defection(u):
		return null
	_state(k)["last_defection"] = GameClock.game_time
	return u if is_instance_valid(u) else null


## Verrat erzwingen (Empfänger: receiver oder die feindliche Partei mit der höchsten Aufmerksamkeit)
func debug_force_betrayal(k: Kingdom, receiver: Kingdom = null) -> bool:
	var r := receiver if receiver != null else _pick_receiver(k)
	var u := _least_satisfied(k)
	if r == null or u == null:
		return false
	_rng.state = rng_state
	_betray(k, u, r)
	rng_state = _rng.state
	return true


func _least_satisfied(k: Kingdom) -> Unit:
	if k == null:
		return null
	var best: Unit = null
	for u in k.units:
		if not is_inhabitant(u) or is_defector(u) or u.role == "king" or u.hero_id != 0:
			continue
		if best == null or u.satisfaction < best.satisfaction:
			best = u
	return best
