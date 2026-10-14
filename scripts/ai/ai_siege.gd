## AISiege
##
## Belagerung und Handelswege eines KI-Reichs (Phase 9): Türme und Mauerring bei
## Bedrohung, Belagerungswaffen gegen befestigte Ziele, Startvertrag für einen
## Handelsweg und Geleitschutz für abgeschnittene Wege. Nur statische Funktionen; der
## Zustand liegt in Kingdom.ai_state["siege"] (siehe default_state). Benutzt dieselben
## öffentlichen Schnittstellen wie der Spieler (BuildingSystem.can_place/place_building/
## place_line, CommandSystem.order_*, DiplomacySystem.start_treaty_forced).
class_name AISiege
extends RefCounted

## Höchstens ein Alarm je so viele Sekunden zählt als neue Bedrohung
const THREAT_INTERVAL := 60.0
## Startvertrag: so oft neu versuchen, wenn kein Dorf passt (Spielsekunden)
const TRADE_RETRY := 60.0


## Vorgaben für ai_state["siege"]: "threat" (Zahl der Alarme), "last_threat_at",
## "ring" {"rect": Rect2i, "next": int, "gates": [Vector2i], "gates_done": int, "done": bool}
## ({} = noch keiner), "next_fortify", "escort_at", "start_trade_done", "next_trade_try"
static func default_state() -> Dictionary:
	return {"threat": 0, "last_threat_at": -1.0, "ring": {}, "next_fortify": -1.0, "escort_at": -1.0,
			"start_trade_done": false, "next_trade_try": -1.0}


## Fehlende Schlüssel ergänzen (ältere Spielstände)
static func ensure_state(st: Dictionary) -> void:
	if not (st.get("siege", null) is Dictionary):
		st["siege"] = default_state()
		return
	var s: Dictionary = st["siege"]
	var d := default_state()
	for key in d:
		if not s.has(key):
			s[key] = d[key]


## Aus AIBrain.on_alarm: eine Bedrohung mehr (höchstens eine je THREAT_INTERVAL)
static func on_alarm(b: AIBrain, now: float) -> void:
	var s: Dictionary = b.st["siege"]
	if now - float(s["last_threat_at"]) < THREAT_INTERVAL and float(s["last_threat_at"]) >= 0.0:
		return
	s["threat"] = int(s["threat"]) + 1
	s["last_threat_at"] = now


## Rauchtest/F3: sofort bedroht (Türme und Ring)
static func debug_force_threat(b: AIBrain) -> void:
	var s: Dictionary = b.st["siege"]
	s["threat"] = maxi(int(s["threat"]), int(DataDB.ai("fortify.ring_threat", 2)))
	s["last_threat_at"] = GameClock.game_time
	s["next_fortify"] = -1.0


## Anzahl Gebäude ohne Mauerstücke (Wachstumsgrenze)
static func building_count(k: Kingdom) -> int:
	var n := 0
	for bld in k.buildings:
		if not bld.is_segment:
			n += 1
	return n


static func _difficulty_id(b: AIBrain) -> String:
	return str(b.diff.get("id", "normal"))


## Bedroht? Kürzlich angegriffen oder (ab min_minute) von einem Feind entdeckt
static func _threatened(b: AIBrain, now: float) -> bool:
	var s: Dictionary = b.st["siege"]
	if int(s["threat"]) >= 1 and now - float(s["last_threat_at"]) < float(DataDB.ai("fortify.threat_memory", 1200)):
		return true
	if not b.time_ok(now, float(DataDB.ai("fortify.min_minute", 25))):
		return false
	var esp: Variant = b.game.get("espionage_system")
	if esp == null or not (esp as Object).has_method("get_awareness_tier"):
		return false
	for o in b.game.kingdoms:
		var other: Kingdom = o
		if other == b.k or other.defeated or (other.controller != "player" and other.controller != "ai"):
			continue
		if b.game.are_hostile(other, b.k) and int((esp as Object).call("get_awareness_tier", other, b.k)) >= 2:
			return true
	return false


# ---------------------------------------------------------------------------
# Befestigen (aus AIBrain.think, jeder zweite Durchgang nach dem Bauen)
# ---------------------------------------------------------------------------

static func tick_fortify(b: AIBrain, now: float) -> void:
	var k := b.k
	if not is_instance_valid(k.castle) or not _threatened(b, now):
		return
	var s: Dictionary = b.st["siege"]
	_tick_towers(b, now)
	var minute := int((DataDB.ai("fortify.ring_minute", {}) as Dictionary).get(_difficulty_id(b), -1))
	var ring_due := int(s["threat"]) >= int(DataDB.ai("fortify.ring_threat", 2)) \
			or (minute >= 0 and b.time_ok(now, float(minute)))
	if ring_due:
		_tick_ring(b)


## Ist cost mit der Reserve des Befestigens (fortify.reserve) bezahlbar?
static func _affordable(k: Kingdom, cost: Dictionary, times: int = 1) -> bool:
	var reserve: Dictionary = DataDB.ai("fortify.reserve", {})
	for res_id in cost:
		if k.get_amount(str(res_id)) < float(cost[res_id]) * times + float(reserve.get(res_id, 0.0)):
			return false
	return true


static func _tick_towers(b: AIBrain, now: float) -> void:
	var k := b.k
	var bs: BuildingSystem = b.game.building_system
	var def := DataDB.get_building("tower")
	if def.is_empty() or not bs.can_build_type(def, k).is_empty():
		return
	var base := int((DataDB.ai("fortify.towers", {}) as Dictionary).get(_difficulty_id(b), 3))
	var per_pop := maxf(float(DataDB.ai("fortify.tower_per_pop", 12)), 1.0)
	var want := mini(base + floori(float(k.get_population()) / per_pop), base * 2)
	var have := bs.count_buildings(k, "tower", false)
	if have >= want or not _affordable(k, def.get("cost", {})):
		return
	# Richtung: letzter Alarm, sonst der Hauptfeind; je Turm etwas gedreht
	var center := k.castle.get_center()
	var dir := Vector2.ZERO
	var alarm: Dictionary = b.st["alarm"]
	if not alarm.is_empty():
		dir = (alarm["pos"] as Vector2) - center
	else:
		var best := INF
		for o in b.game.kingdoms:
			var other: Kingdom = o
			if other == k or not b.game.are_hostile(k, other) or not is_instance_valid(other.castle):
				continue
			var d := center.distance_to(other.castle.get_center())
			if d < best:
				best = d
				dir = other.castle.get_center() - center
	dir = dir.normalized().rotated(float(have) * 1.3 * (1.0 if have % 2 == 0 else -1.0)) if dir != Vector2.ZERO \
			else Vector2.RIGHT.rotated(float(have) * 2.1)
	var cell := _tower_site(b, def, dir)
	if cell.x < 0 or not bs.can_place(def, cell, k).is_empty():
		return
	if bs.place_building(def, cell, k) != null:
		b.log_first("first_building", now)


## Platz für einen Turm im Ring tower_ring um die Burgmitte, bevorzugt in Richtung dir
static func _tower_site(b: AIBrain, def: Dictionary, dir: Vector2) -> Vector2i:
	var c0 := b.world.world_to_cell(b.k.castle.get_center())
	var radii: Array = DataDB.ai("fortify.tower_ring", [6, 9])
	var r0 := int(radii[0]) if radii.size() > 0 else 6
	var r1 := int(radii[1]) if radii.size() > 1 else 9
	var size: Vector2i = def.get("size", Vector2i(2, 2))
	var half := Vector2i(size.x >> 1, size.y >> 1)
	var cands: Array = []
	for r in range(r0, r1 + 1):
		cands.append_array(AIEconomy.ring(r, 1))
	cands.sort_custom(func(x: Vector2i, y: Vector2i) -> bool:
		return Vector2(x).normalized().dot(dir) > Vector2(y).normalized().dot(dir))
	for off in cands:
		if b.checks_left <= 0 or b.scan_left <= 0:
			break
		var cell: Vector2i = c0 + off - half
		if AIEconomy._fits(b, def, cell):
			return cell
	return Vector2i(-1, -1)


## Mauerring um die Burg: Tore zuerst, dann je Durchgang höchstens
## ring_segments_per_think Umfangskacheln (Lücken an verbauten Stellen sind erlaubt)
static func _tick_ring(b: AIBrain) -> void:
	var k := b.k
	var bs: BuildingSystem = b.game.building_system
	var s: Dictionary = b.st["siege"]
	var ring: Dictionary = s["ring"]
	if ring.is_empty():
		var c := b.world.world_to_cell(k.castle.get_center())
		var r := int(DataDB.ai("fortify.ring_radius", 12))
		var rect := Rect2i(c - Vector2i(r, r), Vector2i(r * 2 + 1, r * 2 + 1))
		var mids: Array = [Vector2i(c.x, rect.position.y), Vector2i(c.x, rect.end.y - 1),
				Vector2i(rect.position.x, c.y), Vector2i(rect.end.x - 1, c.y)]
		mids.resize(mini(mids.size(), int(DataDB.ai("fortify.ring_gates", 4))))
		ring = {"rect": rect, "next": 0, "gates": mids, "gates_done": 0, "done": false}
		s["ring"] = ring
	if bool(ring["done"]):
		return
	var gate_def := DataDB.get_building("gate")
	var wall_def := DataDB.get_building("wall")
	if gate_def.is_empty() or wall_def.is_empty():
		return
	var gates: Array = ring["gates"]
	# Tore zuerst (eines je Durchgang)
	while int(ring["gates_done"]) < gates.size():
		var g: Vector2i = gates[int(ring["gates_done"])]
		var occ: Variant = b.world.occupancy.get(g, null)
		if occ != null and is_instance_valid(occ) and (occ as Building).fort_kind == "gate":
			ring["gates_done"] = int(ring["gates_done"]) + 1
			continue
		if not _affordable(k, gate_def.get("cost", {})):
			return
		if bs.can_place(gate_def, g, k).is_empty():
			bs.place_building(gate_def, g, k)
		ring["gates_done"] = int(ring["gates_done"]) + 1
		return
	# Umfang in fester Reihenfolge
	var cells := _perimeter(ring["rect"])
	var start := int(ring["next"])
	if start >= cells.size():
		ring["done"] = true
		return
	var cost: Dictionary = wall_def.get("cost", {})
	var count := int(DataDB.ai("fortify.ring_segments_per_think", 16))
	while count > 0 and not _affordable(k, cost, count):
		count -= 1
	if count <= 0:
		return
	var batch: Array = []
	var i := start
	while i < cells.size() and batch.size() < count:
		var cell: Vector2i = cells[i]
		i += 1
		if not gates.has(cell):
			batch.append(cell)
	ring["next"] = i
	if not batch.is_empty():
		bs.place_line(wall_def, batch, k)


## Umfangskacheln eines Rechtecks im Uhrzeigersinn (oben, rechts, unten, links)
static func _perimeter(rect: Rect2i) -> Array:
	var list: Array = []
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x - 1
	var y1 := rect.end.y - 1
	for x in range(x0, x1 + 1):
		list.append(Vector2i(x, y0))
	for y in range(y0 + 1, y1 + 1):
		list.append(Vector2i(x1, y))
	for x in range(x1 - 1, x0 - 1, -1):
		list.append(Vector2i(x, y1))
	for y in range(y1 - 1, y0, -1):
		list.append(Vector2i(x0, y))
	return list


# ---------------------------------------------------------------------------
# Belagerungswaffen
# ---------------------------------------------------------------------------

## Zusätzliche Gewichte für AIMilitary.tick_summon: Belagerungswaffen, wenn das
## (bevorzugte) Wellenziel befestigt ist und die Werkstatt steht; begrenzt auf
## max_units + per_wave × bisherige Wellen (höchstens cap)
static func extra_composition(b: AIBrain) -> Dictionary:
	var k := b.k
	var bs: BuildingSystem = b.game.building_system
	if bs.count_buildings(k, "siege_workshop", true) == 0:
		return {}
	var siege: SiegeSystem = b.game.siege_system
	var target: Kingdom = null
	var wave: Dictionary = b.st["wave"]
	if not wave.is_empty():
		target = b.game.get_kingdom(int(wave.get("target_id", 0)))
	if target == null or not siege.is_fortified(target):
		target = null
		for o in b.game.kingdoms:
			var other: Kingdom = o
			if other != k and not other.defeated and (other.controller == "player" or other.controller == "ai") \
					and b.game.are_hostile(k, other) and siege.is_fortified(other):
				target = other
				break
	if target == null:
		return {}
	var cap := mini(int(DataDB.ai("siege.max_units", 2)) + floori(float(DataDB.ai("siege.per_wave", 0.5)) * int(b.st["waves_sent"])),
			int(DataDB.ai("siege.cap", 5)))
	var have := 0
	for u in k.units:
		if u.is_alive() and (u.tier == "ram" or u.tier == "catapult"):
			have += 1
	for bld in k.buildings:
		for entry in bld.summon_queue:
			var tier := str(DataDB.get_unit_type(str(entry.get("type_id", ""))).get("tier", ""))
			if tier == "ram" or tier == "catapult":
				have += 1
	if have >= cap:
		return {}
	return {"ram": 1.0, "catapult": 1.0}


## Welle unterwegs oder im Kampf: Belagerungswaffen ohne Ziel greifen die nächste
## feindliche Befestigung um das Wellenziel an (Türme zuerst), sonst ein Gebäude des Ziels
static func wave_tick(b: AIBrain, wave: Dictionary, _now: float) -> void:
	var units := b.units_of(wave.get("uids", []))
	var siege_units: Array = []
	for u in units:
		var unit: Unit = u
		if unit.target_mode != "" and (unit.target == null or not is_instance_valid(unit.target)):
			siege_units.append(unit)
	if siege_units.is_empty():
		return
	var target: Kingdom = b.game.get_kingdom(int(wave.get("target_id", 0)))
	if target == null:
		return
	var siege: SiegeSystem = b.game.siege_system
	var combat: CombatSystem = b.game.combat_system
	var target_pos: Vector2 = wave["target_pos"]
	var radius := float(DataDB.ai("siege.attack_radius", 16)) * float(b.world.tile_size)
	var best: Building = null
	var best_score := INF
	for f in siege.query_forts(target_pos, radius):
		var bld: Building = f
		if bld.kingdom != target or not combat.is_valid_target(b.k, bld):
			continue
		var score := target_pos.distance_to(bld.get_center()) * (0.5 if bld.fort_kind == "tower" else 1.0)
		if score < best_score:
			best_score = score
			best = bld
	if best == null:
		if str(wave.get("target_kind", "")) == "kingdom" and is_instance_valid(target.castle) \
				and combat.is_valid_target(b.k, target.castle):
			best = target.castle
	if best != null:
		(b.game.command_system as CommandSystem).order_attack(siege_units, best)


# ---------------------------------------------------------------------------
# Handelswege (aus AIBrain.think, im Takt der Dorfdiplomatie)
# ---------------------------------------------------------------------------

static func tick_routes(b: AIBrain, now: float) -> void:
	var trs: Variant = b.game.get("trade_route_system")
	if trs == null:
		return
	var s: Dictionary = b.st["siege"]
	if not bool(s["start_trade_done"]) and b.time_ok(now, float(DataDB.ai("routes.start_trade_minute", 6))) \
			and now >= float(s["next_trade_try"]):
		s["next_trade_try"] = now + TRADE_RETRY
		if _start_trade(b):
			s["start_trade_done"] = true
	_escort(b, now, trs as TradeRouteSystem)


## Einmaliger Startvertrag mit dem nächsten freien Dorf (nicht mit dem Spieler verbündet)
static func _start_trade(b: AIBrain) -> bool:
	var k := b.k
	var vs: VillageSystem = b.game.village_system
	var ds: DiplomacySystem = b.game.diplomacy_system
	var trs: TradeRouteSystem = b.game.trade_route_system
	if not trs.get_routes(k).is_empty():
		return true
	var home := b.home_center()
	var max_d := float(DataDB.ai("routes.start_trade_max_distance", 90)) * float(b.world.tile_size)
	var best: Kingdom = null
	var best_d := INF
	for v in vs.get_villages():
		var village: Kingdom = v
		if not ds.get_treaty(village).is_empty() or b.game.are_hostile(village, k):
			continue
		if b.game.player != null and b.game.are_allied(village, b.game.player):
			continue
		var d := home.distance_to(vs.get_center(village))
		if d <= max_d and d < best_d:
			best_d = d
			best = village
	if best == null:
		return false
	return ds.start_treaty_forced(best, k, "trade").is_empty()


## Geleitschutz: abgeschnittener eigener Weg mit Feinden nahe der Heimat
static func _escort(b: AIBrain, now: float, trs: TradeRouteSystem) -> void:
	var s: Dictionary = b.st["siege"]
	if now - float(s["escort_at"]) < float(DataDB.ai("routes.escort_cooldown", 300)) and float(s["escort_at"]) >= 0.0:
		return
	var home := b.home_center()
	var max_d := float(DataDB.ai("routes.escort_distance", 70)) * float(b.world.tile_size)
	for r in trs.get_routes(b.k):
		var route: Dictionary = r
		if str(route["state"]) != "cut" or str(route["reason"]) != "Feinde auf dem Weg":
			continue
		var pos: Vector2 = route["danger_pos"]
		if pos.distance_to(home) > max_d:
			continue
		var pool := b.home_pool()
		if pool.size() < int(DataDB.ai("routes.escort_min", 3)):
			return
		var n := maxi(ceili(pool.size() * float(DataDB.ai("routes.escort_share", 0.25))), 1)
		(b.game.command_system as CommandSystem).order_move(pool.slice(0, n), pos, true)
		s["escort_at"] = now
		return
