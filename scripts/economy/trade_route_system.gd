## TradeRouteSystem
##
## Handelswege (Phase 9) zwischen Reichen und Dörfern mit Handelsvertrag oder Bündnis:
## Karawanen pendeln, Lieferung bei Ankunft, Verluste mit Beute, abgeschnittene Wege und
## Wiederöffnung. Für Spieler und KI gleich.
## - Die Zeitsteuerung der Handelslieferungen bleibt im DiplomacySystem (Signal
##   trade_delivery_due, use_caravans = true); Bündniswege liefern im eigenen Takt.
## - Je Weg pendelt eine Karawane (Einheit des Vertragspartners, also des Reichs):
##   holt im Lager die Bezahlung, bringt sie ins Dorf, lädt die Ware, bringt sie heim.
## - Feinde dieses Reichs (auch Monster) können sie überfallen; wiederholte Verluste
##   oder Feinde dauerhaft am Weg schneiden den Weg ab.
##
## Zustand: routes, stats, debug_fast. Laufzeit: _tick_acc, _scan_acc, _repath_queue, _pending.
class_name TradeRouteSystem
extends Node

## Handelswege eines Reichs geändert (neu, entfernt, Zustand, Verlauf)
signal routes_changed(k: Kingdom)
signal route_state_changed(route_id: String, state: String, reason: String)
signal caravan_lost(route_id: String, killer: Kingdom)
signal caravan_arrived(route_id: String, at_partner: bool)

const STATE_NAMES := {"open": "offen", "cut": "abgeschnitten", "blocked": "kein Weg", "paused": "ruht"}

var game: Node
var world: WorldData

## "owner:partner" -> {
##   "id", "owner_id", "partner_id", "kind": "trade"|"alliance",
##   "state": "open"|"cut"|"blocked"|"paused", "state_since": float, "reason": String,
##   "home_uid": int (Burg/Lager mit Annahme, dem Dorf am nächsten), "home_pos": Vector2, "far_pos": Vector2,
##   "points": Array[Vector2] (vereinfachter Weg), "points_at": float, "points_dirty": bool,
##   "caravan_uid": int, "leg": "idle"|"out"|"back", "leg_since": float, "cargo": Dictionary, "cargo_kind": "pay"|"goods"|"",
##   "pending": int, "next_caravan_at": float, "next_delivery": float (nur alliance), "retries": int,
##   "free_caravan": bool, "load_until": float, "arrive_tries": int, "next_repath": float,
##   "losses": Array[float], "danger_time": float, "clear_time": float, "danger_pos": Vector2,
##   "seen_by": Array[int], "missed": int,
##   "stats": {"trips": int, "lost": int, "delivered": Dictionary, "paid": Dictionary, "raided_by": Dictionary} }
var routes: Dictionary = {}
var stats := {"trips": 0, "lost": 0, "cuts": 0, "reopened": 0}
## Rauchtest und F3: kurze Zeiten aus trade.json debug_fast
var debug_fast := false

var _tick_acc := 0.0
var _scan_acc := 0.0
var _repath_queue: Array = []
## Ankünfte (vom command_finished), im Takt abgearbeitet: [route_id, uid, ok]
var _pending: Array = []
var _ts := 64.0


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_ts = float(world.tile_size)
	var ds: DiplomacySystem = game.diplomacy_system
	ds.use_caravans = bool(DataDB.trade("enabled", true))
	ds.treaty_changed.connect(_on_treaty_changed)
	ds.trade_delivery_due.connect(_on_delivery_due)
	game.village_system.settlement_transferred.connect(_on_settlement_transferred)
	game.village_system.village_destroyed.connect(func(v: Kingdom, _by: Kingdom) -> void: _remove_routes_of(v, "Dorf zerstört"))
	game.kingdom_defeated.connect(func(k: Kingdom, _reason: String) -> void: _remove_routes_of(k, "Reich gefallen"))
	game.combat_system.unit_died.connect(_on_unit_died)
	game.unit_system.unit_removed.connect(_on_unit_removed)
	game.command_system.command_finished.connect(_on_command_finished)
	game.building_system.building_removed.connect(_on_building_removed)
	game.building_system.roads_changed.connect(_on_roads_changed)
	GameClock.sim_tick.connect(_on_sim_tick)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Wert aus trade.json; mit debug_fast die kurzen Zeiten aus debug_fast
func _cfg(path: String, default_value: Variant) -> Variant:
	if debug_fast:
		var key := path.get_slice(".", path.get_slice_count(".") - 1)
		var fast: Dictionary = DataDB.trade("debug_fast", {})
		if fast.has(key):
			return fast[key]
	return DataDB.trade(path, default_value)


## Eigene Handelswege eines Reichs
func get_routes(k: Kingdom) -> Array:
	var list: Array = []
	if k == null:
		return list
	for id in routes:
		if int(routes[id]["owner_id"]) == k.id:
			list.append(routes[id])
	return list


func get_route(id: String) -> Dictionary:
	return routes.get(id, {})


func get_route_for(k: Kingdom, v: Kingdom) -> Dictionary:
	if k == null or v == null:
		return {}
	return routes.get("%d:%d" % [k.id, v.id], {})


## Wege, die viewer sieht: eigene, verbündete und gesichtete (bzw. Kundschaft ≥ 2, Phase 7)
func get_visible_routes(viewer: Kingdom) -> Array:
	var list: Array = []
	if viewer == null:
		return list
	var esp: Variant = game.get("espionage_system")
	for id in routes:
		var r: Dictionary = routes[id]
		var owner_k: Kingdom = game.get_kingdom(int(r["owner_id"]))
		if owner_k == null:
			continue
		if owner_k == viewer or game.are_allied(owner_k, viewer) or (r["seen_by"] as Array).has(viewer.id):
			list.append(r)
		elif esp != null and (esp as Object).has_method("get_intel_level") \
				and int((esp as Object).call("get_intel_level", viewer, owner_k)) >= 2:
			list.append(r)
	return list


func is_caravan(u: Unit) -> bool:
	return is_instance_valid(u) and u.role == "caravan"


## Weg zu einer Karawane (leer, wenn keiner)
func route_of_caravan(u: Unit) -> Dictionary:
	if not is_instance_valid(u):
		return {}
	for id in routes:
		if int(routes[id]["caravan_uid"]) == u.uid:
			return routes[id]
	return {}


func get_state_name(state: String) -> String:
	return str(STATE_NAMES.get(state, state))


## Text für das Auswahlfenster einer Karawane: Weg, Strecke, Ladung, Lieferungen
func get_caravan_text(u: Unit) -> String:
	var r := route_of_caravan(u)
	if r.is_empty():
		return "Karawane ohne Handelsweg"
	var v: Kingdom = game.get_kingdom(int(r["partner_id"]))
	var lines: PackedStringArray = []
	lines.append("Handelsweg nach %s (%s, %s)" % [v.display_name if v != null else "?", _kind_name(str(r["kind"])),
			get_state_name(str(r["state"]))])
	lines.append(_leg_text(r))
	var cargo: Dictionary = r["cargo"]
	lines.append("Ladung: %s" % (DataDB.cost_to_text(cargo) if not cargo.is_empty() else "leer"))
	var rs: Dictionary = r["stats"]
	lines.append("Lieferungen %d · Verluste %d" % [int(rs["trips"]), int(rs["lost"])])
	return "\n".join(lines)


## Kurzer Text eines Wegs (Diplomatiefenster, Handelsliste)
func get_route_text(r: Dictionary, viewer: Kingdom) -> String:
	if r.is_empty():
		return ""
	var text := "Handelsweg: %s" % get_state_name(str(r["state"]))
	if not str(r["reason"]).is_empty() and str(r["state"]) != "open":
		text += " (%s)" % str(r["reason"])
	var owner_k: Kingdom = game.get_kingdom(int(r["owner_id"]))
	if owner_k == viewer:
		text += " · " + _leg_text(r)
		var rs: Dictionary = r["stats"]
		text += " · Lieferungen %d · Verluste %d" % [int(rs["trips"]), int(rs["lost"])]
		if int(r["missed"]) > 0:
			text += " · ausgefallen %d" % int(r["missed"])
	return text


## Wo ist die Karawane? ("unterwegs zum Dorf", "wartet im Lager", "neue in 0:42")
func _leg_text(r: Dictionary) -> String:
	var u := _caravan(r)
	if u == null:
		var wait := maxf(float(r["next_caravan_at"]) - GameClock.game_time, 0.0)
		return "neue Karawane in %d:%02d" % [floori(wait / 60.0), floori(fmod(wait, 60.0))]
	match str(r["leg"]):
		"out":
			return "Karawane unterwegs zum Dorf"
		"back":
			return "Karawane auf dem Heimweg"
	return "Karawane wartet im Lager"


## Öffentliche Hilfen für die Oberfläche (Handelsliste)
func get_leg_text(r: Dictionary) -> String:
	return _leg_text(r)


func get_caravan(r: Dictionary) -> Unit:
	return _caravan(r)


func get_midpoint(r: Dictionary) -> Vector2:
	return _midpoint(r)


static func _kind_name(kind: String) -> String:
	return "Bündnis" if kind == "alliance" else "Handel"


## "" = Knopf "Weg freigeben" erlaubt (abgeschnitten, gerade keine Feinde am Weg)
func can_reopen(k: Kingdom, id: String) -> String:
	var r := get_route(id)
	if r.is_empty() or k == null or int(r["owner_id"]) != k.id:
		return "Kein eigener Handelsweg"
	if str(r["state"]) != "cut":
		return "Der Weg ist nicht abgeschnitten"
	if float(r["danger_time"]) > 0.0:
		return "Noch Feinde am Weg"
	return ""


## Weg freigeben (der Besitzer übernimmt den Geleitschutz)
func reopen(k: Kingdom, id: String) -> bool:
	if not can_reopen(k, id).is_empty():
		return false
	_reopen(routes[id], "Weg freigegeben")
	return true


## Punkte offener eigener Wege (SupplySystem)
func get_corridor_points(k: Kingdom) -> Array:
	var pts: Array = []
	for r in get_routes(k):
		if str(r["state"]) == "open":
			pts.append_array(r["points"])
	return pts


# ---------------------------------------------------------------------------
# Debug (Rauchtest, F3)
# ---------------------------------------------------------------------------

## Karawane eines Wegs töten (killer bekommt die Beute)
func debug_kill_caravan(id: String, killer: Kingdom) -> bool:
	var r := get_route(id)
	var u := _caravan(r) if not r.is_empty() else null
	if u == null:
		return false
	if u.inside != null:
		game.unit_system.set_inside(u, null)
	game.combat_system.apply_damage(u, u.hp + 1.0, null, killer, "event")
	return true


func debug_cut(id: String) -> void:
	var r := get_route(id)
	if not r.is_empty() and str(r["state"]) == "open":
		_cut(r, "Test", _midpoint(r))


# ---------------------------------------------------------------------------
# Wegeverwaltung
# ---------------------------------------------------------------------------

func _on_treaty_changed(v: Kingdom, k: Kingdom, treaty_type: String) -> void:
	if treaty_type == "":
		_remove_routes_of(v, "Vertrag beendet")
		return
	var ds: DiplomacySystem = game.diplomacy_system
	if not (treaty_type == "trade" or treaty_type == "alliance") or not ds.is_party(k):
		return
	if not bool(DataDB.trade("routes.%s.enabled" % treaty_type, true)):
		return
	var existing := get_route_for(k, v)
	if not existing.is_empty():
		existing["kind"] = treaty_type
		routes_changed.emit(k)
		return
	_create_route(k, v, treaty_type)


func _create_route(k: Kingdom, v: Kingdom, kind: String) -> void:
	var now := GameClock.game_time
	var id := "%d:%d" % [k.id, v.id]
	var interval := float(DataDB.diplo("treaties.trade.delivery_interval", 150)) \
			* float(DataDB.trade("routes.alliance.interval_mult", 1.5))
	var r := {"id": id, "owner_id": k.id, "partner_id": v.id, "kind": kind, "state": "open", "state_since": now,
			"reason": "", "home_uid": 0, "home_pos": Vector2.ZERO, "far_pos": Vector2.ZERO, "points": [],
			"points_at": -1.0, "points_dirty": true, "caravan_uid": 0, "leg": "idle", "leg_since": now, "cargo": {},
			"cargo_kind": "", "pending": 0, "next_caravan_at": now, "next_delivery": now + interval if kind == "alliance" else 0.0,
			"retries": 0, "free_caravan": true, "load_until": -1.0, "arrive_tries": 0, "next_repath": now,
			"losses": [], "danger_time": 0.0, "clear_time": 0.0, "danger_pos": Vector2.ZERO, "seen_by": [], "missed": 0,
			"stats": {"trips": 0, "lost": 0, "delivered": {}, "paid": {}, "raided_by": {}}}
	routes[id] = r
	if not _choose_depot(r):
		_set_state(r, "paused", "Kein Lager")
	_repath_queue.append(id)
	var depot := _depot(r)
	k.notify("Handelsweg nach %s eröffnet – eine Karawane pendelt zwischen %s und dem Dorf." % [v.display_name,
			depot.get_display_name() if depot != null else "deinem Lager"], "good", game.village_system.get_center(v))
	routes_changed.emit(k)


## Weg entfernen: Karawane weg, Ladung an den Besitzer (gezahlt bleibt nicht verloren)
func _remove_route(id: String, _reason: String) -> void:
	var r: Dictionary = routes.get(id, {})
	if r.is_empty():
		return
	routes.erase(id)
	var k: Kingdom = game.get_kingdom(int(r["owner_id"]))
	var u := _caravan(r)
	if k != null and not k.defeated:
		var cargo: Dictionary = r["cargo"]
		for res_id in cargo:
			k.add_resource(str(res_id), float(cargo[res_id]))
	r["caravan_uid"] = 0
	if u != null:
		game.unit_system.remove_unit(u)
	_repath_queue.erase(id)
	if k != null:
		routes_changed.emit(k)


## Alle Wege, an denen das Reich oder Dorf beteiligt ist, entfernen
func _remove_routes_of(k: Kingdom, reason: String) -> void:
	if k == null:
		return
	for id in routes.keys():
		var r: Dictionary = routes[id]
		if int(r["owner_id"]) == k.id or int(r["partner_id"]) == k.id:
			_remove_route(id, reason)


func _on_settlement_transferred(from_kingdom: Kingdom, _to_kingdom: Kingdom, reason: String) -> void:
	_remove_routes_of(from_kingdom, reason)


## Lager mit Annahme (Burg oder Lager), das dem Dorf am nächsten liegt; setzt home/far
func _choose_depot(r: Dictionary) -> bool:
	var k: Kingdom = game.get_kingdom(int(r["owner_id"]))
	var v: Kingdom = game.get_kingdom(int(r["partner_id"]))
	if k == null or v == null:
		return false
	var vs: VillageSystem = game.village_system
	var center := vs.get_center(v)
	var best: Building = null
	var best_d := INF
	for b in k.buildings:
		if not b.constructed or not (b == k.castle or (b.def.get("dropoff", []) as Array).size() >= 3):
			continue
		var d: float = b.get_center().distance_to(center)
		if d < best_d:
			best_d = d
			best = b
	if best == null:
		return false
	r["home_uid"] = best.uid
	r["home_pos"] = best.get_approach_point(center)
	var hall := vs.get_hall(v)
	r["far_pos"] = hall.get_approach_point(r["home_pos"]) if hall != null else center
	r["points_dirty"] = true
	return true


func _depot(r: Dictionary) -> Building:
	var b: Variant = game.find_by_uid(int(r.get("home_uid", 0)))
	return b as Building if b is Building and is_instance_valid(b) else null


func _caravan(r: Dictionary) -> Unit:
	var uid := int(r.get("caravan_uid", 0))
	if uid == 0:
		return null
	var u: Variant = game.find_by_uid(uid)
	return u as Unit if u is Unit and is_instance_valid(u) and (u as Unit).is_alive() else null


## Vereinfachter Weg (Richtungswechsel und jeder 6. Punkt); leer = kein Weg
func _repath(id: String) -> void:
	var r: Dictionary = routes.get(id, {})
	if r.is_empty() or _depot(r) == null:
		return
	var nav: NavGrid = game.nav
	var now := GameClock.game_time
	r["next_repath"] = now + float(DataDB.trade("route_repath_seconds", 120))
	var p := nav.find_path(world, r["home_pos"], r["far_pos"], int(r["owner_id"]))
	var k: Kingdom = game.get_kingdom(int(r["owner_id"]))
	if p.is_empty():
		r["retries"] = int(r["retries"]) + 1
		r["next_repath"] = now + float(DataDB.trade("cut.no_path_retry", 120))
		if str(r["state"]) == "open":
			_set_state(r, "blocked", "Kein Weg (Mauern?)")
			var v: Kingdom = game.get_kingdom(int(r["partner_id"]))
			if k != null and v != null:
				k.notify("Handelsweg nach %s: kein Weg (Mauern oder Hindernisse) – neuer Versuch später." % v.display_name,
						"warning", r["far_pos"])
		return
	var pts: Array = [r["home_pos"]]
	var last_dir := Vector2.ZERO
	for i in range(1, p.size() - 1):
		var dir := (p[i + 1] - p[i]).normalized()
		if dir.distance_to(last_dir) > 0.01 or i % 6 == 0:
			pts.append(p[i])
		last_dir = dir
	pts.append(p[p.size() - 1])
	r["points"] = pts
	r["points_at"] = now
	r["points_dirty"] = false
	r["retries"] = 0
	if str(r["state"]) == "blocked":
		_set_state(r, "open", "")
	if k != null:
		routes_changed.emit(k)


func _on_roads_changed() -> void:
	for id in routes:
		routes[id]["points_dirty"] = true


func _on_building_removed(b: Building) -> void:
	for id in routes:
		var r: Dictionary = routes[id]
		if int(r["home_uid"]) == b.uid:
			r["home_uid"] = 0


func _set_state(r: Dictionary, state: String, reason: String) -> void:
	if str(r["state"]) == state and str(r["reason"]) == reason:
		return
	r["state"] = state
	r["reason"] = reason
	r["state_since"] = GameClock.game_time
	route_state_changed.emit(str(r["id"]), state, reason)
	var k: Kingdom = game.get_kingdom(int(r["owner_id"]))
	if k != null:
		routes_changed.emit(k)


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	_tick_acc += dt
	var tick := maxf(float(DataDB.trade("tick_seconds", 1.0)), 0.1)
	if _tick_acc < tick:
		return
	var step := _tick_acc
	_tick_acc = 0.0
	var now := GameClock.game_time
	if not _pending.is_empty():
		var list := _pending
		_pending = []
		for entry in list:
			_arrive(str(entry[0]), int(entry[1]), bool(entry[2]))
	for id in routes.keys():
		if routes.has(id):
			_tick_route(routes[id], now)
	# Wegberechnung: höchstens eine je Takt
	if not _repath_queue.is_empty():
		_repath(str(_repath_queue.pop_front()))
	else:
		for id in routes:
			var r: Dictionary = routes[id]
			if now >= float(r["next_repath"]) and (bool(r["points_dirty"]) or str(r["state"]) == "blocked"):
				_repath(str(id))
				break
	_scan_acc += step
	var scan := maxf(float(_cfg("cut.scan_seconds", 5)), 0.5)
	if _scan_acc >= scan:
		_scan_dangers(_scan_acc)
		_scan_acc = 0.0


func _tick_route(r: Dictionary, now: float) -> void:
	var id := str(r["id"])
	var k: Kingdom = game.get_kingdom(int(r["owner_id"]))
	var v: Kingdom = game.get_kingdom(int(r["partner_id"]))
	var vs: VillageSystem = game.village_system
	if k == null or k.defeated or v == null or not vs.is_village(v):
		_remove_route(id, "Partner weg")
		return
	# 1. Gültigkeit: Krieg ruht, Lager weg
	if game.are_hostile(k, v):
		if str(r["state"]) != "paused":
			_set_state(r, "paused", "Krieg")
		return
	if str(r["state"]) == "paused" and str(r["reason"]) == "Krieg":
		_set_state(r, "open", "")
	var depot := _depot(r)
	if depot == null:
		if not _choose_depot(r):
			if str(r["state"]) != "paused":
				_set_state(r, "paused", "Kein Lager")
			return
		depot = _depot(r)
	if str(r["state"]) == "paused" and str(r["reason"]) == "Kein Lager":
		_set_state(r, "open", "")
	# 2. Bündniswege: Lieferung fällig (Ware ohne Bezahlung)
	if str(r["kind"]) == "alliance" and now >= float(r["next_delivery"]):
		var interval := float(DataDB.diplo("treaties.trade.delivery_interval", 150)) \
				* float(DataDB.trade("routes.alliance.interval_mult", 1.5))
		r["next_delivery"] = now + interval
		if str(r["state"]) == "open":
			r["pending"] = mini(int(r["pending"]) + 1, int(DataDB.trade("pending_max", 2)))
		else:
			r["missed"] = int(r["missed"]) + 1
	var u := _caravan(r)
	# 3. Neue Karawane
	if u == null:
		r["caravan_uid"] = 0
		if str(r["state"]) != "open" or now < float(r["next_caravan_at"]):
			return
		if not bool(r["free_caravan"]):
			var cost: Dictionary = DataDB.trade("caravan_cost", {})
			if not k.spend(cost):
				r["next_caravan_at"] = now + 30.0
				if _throttle(r, "caravan_cost", 120.0):
					k.notify("Keine neue Karawane nach %s: %s" % [v.display_name, k.missing_text(cost)], "warning",
							depot.get_center())
				return
		r["free_caravan"] = false
		u = game.unit_system.spawn_unit(k, str(DataDB.trade("caravan_unit", "caravan")), depot.get_approach_point(r["far_pos"]))
		if u == null:
			return
		r["caravan_uid"] = u.uid
		r["leg"] = "idle"
		r["leg_since"] = now
		r["cargo"] = {}
		r["cargo_kind"] = ""
		game.unit_system.set_inside(u, depot)
		return
	# 4. Abfahrt: Lieferung fällig und Weg offen
	var leg := str(r["leg"])
	if leg == "idle" and int(r["pending"]) > 0 and str(r["state"]) == "open":
		var cargo := {}
		if str(r["kind"]) == "trade":
			# Menge und Preis der Route (DiplomacySystem.get_delivery: Einstellung und Angebot/Nachfrage)
			var take: Dictionary = game.diplomacy_system.get_delivery(v, k)["take"]
			if not k.spend(take):
				r["pending"] = int(r["pending"]) - 1
				r["missed"] = int(r["missed"]) + 1
				if _throttle(r, "pay_missing", 300.0):
					k.notify("Handelslieferung aus %s fällt aus: %s" % [v.display_name, k.missing_text(take)], "warning",
							vs.get_center(v))
				return
			cargo = take.duplicate()
			_add_to(r["stats"]["paid"], take)
		r["cargo"] = cargo
		r["cargo_kind"] = "pay"
		r["leg"] = "out"
		r["leg_since"] = now
		r["arrive_tries"] = 0
		game.unit_system.set_inside(u, null)
		game.command_system.order_travel(u, r["far_pos"], "haul")
		return
	# Beladen im Dorf, dann heim
	if leg == "back" and float(r["load_until"]) >= 0.0 and now >= float(r["load_until"]):
		r["load_until"] = -1.0
		r["leg_since"] = now
		game.command_system.order_travel(u, r["home_pos"], "haul")
		return
	# 5. Feststecken
	if leg != "idle" and now - float(r["leg_since"]) > float(DataDB.trade("cut.max_travel_seconds", 900)):
		_give_back(r, k)
		r["next_caravan_at"] = now + float(_cfg("respawn_seconds", 60))
		r["caravan_uid"] = 0
		game.unit_system.remove_unit(u)
		_set_state(r, "blocked", "Karawane steckt fest")
		r["next_repath"] = now


## Ladung an den Besitzer zurück (Bezahlung, nicht gelieferte Ware)
func _give_back(r: Dictionary, k: Kingdom) -> void:
	var cargo: Dictionary = r["cargo"]
	if k != null:
		for res_id in cargo:
			k.add_resource(str(res_id), float(cargo[res_id]))
	if str(r["cargo_kind"]) == "goods":
		r["pending"] = maxi(int(r["pending"]) - 1, 0)
	r["cargo"] = {}
	r["cargo_kind"] = ""
	r["leg"] = "idle"


# ---------------------------------------------------------------------------
# Lieferungen, Ankunft, Verlust
# ---------------------------------------------------------------------------

## Fällige Handelslieferung (DiplomacySystem): eine Fahrt mehr
func _on_delivery_due(v: Kingdom, k: Kingdom, _give: Dictionary, _take: Dictionary) -> void:
	var r := get_route_for(k, v)
	if r.is_empty():
		_create_route(k, v, "trade")
		r = get_route_for(k, v)
		if r.is_empty():
			return
	var state := str(r["state"])
	if state == "open" or state == "paused":
		r["pending"] = mini(int(r["pending"]) + 1, int(DataDB.trade("pending_max", 2)))
	else:
		r["missed"] = int(r["missed"]) + 1
		if _throttle(r, "missed", 600.0):
			k.notify("Lieferung aus %s fällt aus – der Handelsweg ist abgeschnitten." % v.display_name, "warning",
					game.village_system.get_center(v))


func _on_command_finished(u: Unit, command: String, ok: bool) -> void:
	if command != "haul" or not is_caravan(u):
		return
	var r := route_of_caravan(u)
	if not r.is_empty():
		_pending.append([str(r["id"]), u.uid, ok])


func _arrive(id: String, uid: int, ok: bool) -> void:
	var r: Dictionary = routes.get(id, {})
	if r.is_empty() or int(r["caravan_uid"]) != uid:
		return
	var u := _caravan(r)
	if u == null:
		return
	var k: Kingdom = game.get_kingdom(int(r["owner_id"]))
	var v: Kingdom = game.get_kingdom(int(r["partner_id"]))
	if k == null or v == null:
		return
	var leg := str(r["leg"])
	var dest: Vector2 = r["far_pos"] if leg == "out" else r["home_pos"]
	var near := u.position.distance_to(dest) <= float(DataDB.trade("arrival_radius", 3)) * _ts
	if not ok and not near:
		r["arrive_tries"] = int(r["arrive_tries"]) + 1
		if int(r["arrive_tries"]) <= 2:
			var c: Vector2i = game.nav.nearest_free(world.world_to_cell(dest), 4)
			game.command_system.order_travel(u, world.cell_to_world(c) if c.x >= 0 else dest, "haul")
			return
		_set_state(r, "blocked", "Kein Weg (Mauern?)")
		r["next_repath"] = GameClock.game_time
		if leg == "out":
			# Umkehren: die Bezahlung kommt zurück
			r["leg"] = "back"
			r["arrive_tries"] = 0
			r["leg_since"] = GameClock.game_time
			game.command_system.order_travel(u, r["home_pos"], "haul")
			return
	r["arrive_tries"] = 0
	var now := GameClock.game_time
	if leg == "out":
		var delivery: Dictionary = game.village_system.get_people(v).get("delivery", {})
		var give: Dictionary = delivery.get("give", {})
		var goods := {}
		if str(r["kind"]) == "trade":
			give = game.diplomacy_system.get_delivery(v, k)["give"]
			if v.can_afford(give):
				for res_id in r["cargo"]:
					v.add_resource(str(res_id), float(r["cargo"][res_id]))
				v.spend(give)
				goods = give.duplicate()
			else:
				# Ware fehlt: Bezahlung fährt wieder heim
				r["pending"] = maxi(int(r["pending"]) - 1, 0)
				r["missed"] = int(r["missed"]) + 1
				if _throttle(r, "goods_missing", 300.0):
					k.notify("Handelslieferung aus %s fällt aus: dem Dorf fehlt Ware." % v.display_name, "warning",
							game.village_system.get_center(v))
		else:
			var factor := float(DataDB.trade("routes.alliance.goods_factor", 0.4))
			for res_id in give:
				var amount := minf(float(give[res_id]) * factor, v.get_amount(str(res_id)))
				if amount >= 1.0:
					goods[res_id] = floorf(amount)
			v.spend(goods)
		if not goods.is_empty():
			r["cargo"] = goods
			r["cargo_kind"] = "goods"
		r["leg"] = "back"
		r["leg_since"] = now
		r["load_until"] = now + float(_cfg("load_seconds", 4))
		caravan_arrived.emit(id, true)
		return
	# Heim angekommen
	var cargo: Dictionary = r["cargo"]
	for res_id in cargo:
		k.add_resource(str(res_id), float(cargo[res_id]))
	if str(r["cargo_kind"]) == "goods":
		var rs: Dictionary = r["stats"]
		rs["trips"] = int(rs["trips"]) + 1
		_add_to(rs["delivered"], cargo)
		stats["trips"] = int(stats["trips"]) + 1
		r["pending"] = maxi(int(r["pending"]) - 1, 0)
		if str(r["kind"]) == "trade":
			game.diplomacy_system.note_delivery(v)
		k.notify("Karawane aus %s angekommen: %s" % [v.display_name, DataDB.cost_to_text(cargo)], "info", u.position)
	r["cargo"] = {}
	r["cargo_kind"] = ""
	r["leg"] = "idle"
	r["leg_since"] = now
	var depot := _depot(r)
	if depot != null:
		game.unit_system.set_inside(u, depot)
	caravan_arrived.emit(id, false)
	routes_changed.emit(k)


func _on_unit_died(u: Unit, killer: Kingdom) -> void:
	if not is_caravan(u):
		return
	var r := route_of_caravan(u)
	if r.is_empty():
		return
	var now := GameClock.game_time
	var k: Kingdom = game.get_kingdom(int(r["owner_id"]))
	var v: Kingdom = game.get_kingdom(int(r["partner_id"]))
	var losses: Array = r["losses"]
	losses.append(now)
	var window := float(DataDB.trade("cut.loss_window", 900))
	while not losses.is_empty() and now - float(losses[0]) > window:
		losses.pop_front()
	var rs: Dictionary = r["stats"]
	rs["lost"] = int(rs["lost"]) + 1
	stats["lost"] = int(stats["lost"]) + 1
	r["next_caravan_at"] = now + float(_cfg("respawn_seconds", 60))
	r["caravan_uid"] = 0
	var cargo: Dictionary = r["cargo"]
	var ds: DiplomacySystem = game.diplomacy_system
	if killer != null and killer != k and ds.is_party(killer):
		var loot := {}
		var share := float(DataDB.trade("loot_share", 0.6))
		for res_id in cargo:
			var amount := floorf(float(cargo[res_id]) * share)
			if amount > 0.0:
				loot[res_id] = amount
				killer.add_resource(str(res_id), amount)
		var raided: Dictionary = rs["raided_by"]
		raided[killer.id] = int(raided.get(killer.id, 0)) + 1
		if v != null and killer != v and game.village_system.is_village(v):
			ds.change_reputation(v, killer, float(DataDB.trade("raid_reputation", -2)), "Karawane überfallen")
		var esp: Variant = game.get("espionage_system")
		if esp != null and (esp as Object).has_method("note_aggression") and k != null:
			(esp as Object).call("note_aggression", killer, float(DataDB.esp("aggression.kill_caravan", 2)), "caravan", k)
		killer.notify("Karawane von %s überfallen – Beute: %s" % [k.display_name if k != null else "?",
				DataDB.cost_to_text(loot) if not loot.is_empty() else "nichts"], "good", u.position)
	if k != null:
		k.notify("Karawane nach %s überfallen – Ladung verloren: %s" % [v.display_name if v != null else "?",
				DataDB.cost_to_text(cargo) if not cargo.is_empty() else "nichts"], "danger", u.position)
	if str(r["cargo_kind"]) == "goods":
		r["pending"] = maxi(int(r["pending"]) - 1, 0)
	r["cargo"] = {}
	r["cargo_kind"] = ""
	r["leg"] = "idle"
	r["load_until"] = -1.0
	if losses.size() >= int(DataDB.trade("cut.losses", 2)) and str(r["state"]) == "open":
		_cut(r, "Zu viele Überfälle", u.position)
	caravan_lost.emit(str(r["id"]), killer)
	if k != null:
		routes_changed.emit(k)


## Karawane ohne Tod entfernt (Besitzerwechsel, Abbau): ohne Verlustzählung
func _on_unit_removed(u: Unit) -> void:
	if not is_caravan(u):
		return
	var r := route_of_caravan(u)
	if r.is_empty():
		return
	r["caravan_uid"] = 0
	var k: Kingdom = game.get_kingdom(int(r["owner_id"]))
	_give_back(r, k)


# ---------------------------------------------------------------------------
# Gefahr am Weg, Abschneiden, Wiederöffnen
# ---------------------------------------------------------------------------

func _scan_dangers(step: float) -> void:
	var combat: CombatSystem = game.combat_system
	var index: SpatialIndex = combat.index
	var radius := float(DataDB.trade("cut.danger_radius", 4)) * _ts
	var sample := maxf(float(DataDB.trade("cut.sample_tiles", 4)), 1.0) * _ts
	var now := GameClock.game_time
	for id in routes.keys():
		var r: Dictionary = routes[id]
		var state := str(r["state"])
		var k: Kingdom = game.get_kingdom(int(r["owner_id"]))
		if k == null:
			continue
		_note_sightings(r, k)
		if state != "open" and state != "cut":
			continue
		var pts: Array = r["points"]
		var found := false
		var at := Vector2.ZERO
		var foes: Array = []
		for kid in index.kingdom_ids():
			if kid == k.id:
				continue
			var other: Kingdom = game.get_kingdom(kid)
			if other != null and combat.hostile(k, other):
				foes.append(kid)
		if not foes.is_empty():
			for i in range(pts.size() - 1):
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[i + 1]
				var n := maxi(ceili(a.distance_to(b) / sample), 1)
				for j in n + 1:
					var p := a.lerp(b, float(j) / n)
					if _danger_at(index, p, radius, foes):
						found = true
						at = p
						break
				if found:
					break
		if found:
			r["danger_time"] = float(r["danger_time"]) + step
			r["danger_pos"] = at
			r["clear_time"] = 0.0
		else:
			r["danger_time"] = maxf(float(r["danger_time"]) - step, 0.0)
			r["clear_time"] = float(r["clear_time"]) + step
		if state == "open" and float(r["danger_time"]) >= float(_cfg("cut.danger_seconds", 30)):
			_cut(r, "Feinde auf dem Weg", r["danger_pos"])
		elif state == "cut" and now - float(r["state_since"]) >= float(_cfg("cut.min_cut_seconds", 180)) \
				and float(r["clear_time"]) >= float(_cfg("cut.clear_seconds", 45)):
			_reopen(r, "Weg wieder frei")


## Feindliche Kämpfer (lebend, nicht getarnt, nicht schlafend) nahe p?
func _danger_at(index: SpatialIndex, p: Vector2, radius: float, foes: Array) -> bool:
	for kid in foes:
		if not index.any_of_kingdom(p, radius, int(kid)):
			continue
		for e in index.query_kingdom(p, radius, int(kid)):
			if e.attack > 0.0 and e.hp > 0.0 and not e.stealthed and not e.dormant:
				return true
	return false


## Gesichtet: Karawane im Gebiet eines anderen Reichs oder nahe fremden Einheiten
func _note_sightings(r: Dictionary, k: Kingdom) -> void:
	var u := _caravan(r)
	if u == null or u.inside != null:
		return
	var seen: Array = r["seen_by"]
	var owner_id := world.get_owner(world.world_to_cell(u.position))
	if owner_id != 0 and owner_id != k.id and not seen.has(owner_id):
		seen.append(owner_id)
	var index: SpatialIndex = game.combat_system.index
	for kid in index.kingdom_ids():
		if kid != k.id and not seen.has(kid) and index.any_of_kingdom(u.position, u.sight * _ts, kid):
			var other: Kingdom = game.get_kingdom(kid)
			if other != null and (other.controller == "player" or other.controller == "ai"):
				seen.append(kid)


func _cut(r: Dictionary, reason: String, pos: Vector2) -> void:
	r["danger_pos"] = pos
	_set_state(r, "cut", reason)
	stats["cuts"] = int(stats["cuts"]) + 1
	var k: Kingdom = game.get_kingdom(int(r["owner_id"]))
	var v: Kingdom = game.get_kingdom(int(r["partner_id"]))
	if k != null:
		k.notify("Handelsweg nach %s abgeschnitten: %s. Keine Lieferungen, bis der Weg wieder frei ist." % [
				v.display_name if v != null else "?", reason], "danger", pos)
	# Auf dem Hinweg kehrt die Karawane um (Bezahlung zurück); auf dem Rückweg fährt sie weiter
	var u := _caravan(r)
	if u != null and str(r["leg"]) == "out":
		r["leg"] = "back"
		r["leg_since"] = GameClock.game_time
		game.command_system.order_travel(u, r["home_pos"], "haul")


func _reopen(r: Dictionary, reason: String) -> void:
	(r["losses"] as Array).clear()
	r["danger_time"] = 0.0
	_set_state(r, "open", "")
	stats["reopened"] = int(stats["reopened"]) + 1
	var k: Kingdom = game.get_kingdom(int(r["owner_id"]))
	var v: Kingdom = game.get_kingdom(int(r["partner_id"]))
	if k != null:
		k.notify("Handelsweg nach %s ist wieder offen. (%s)" % [v.display_name if v != null else "?", reason], "good",
				_midpoint(r))


func _midpoint(r: Dictionary) -> Vector2:
	var pts: Array = r["points"]
	if pts.is_empty():
		return (r["home_pos"] as Vector2).lerp(r["far_pos"], 0.5)
	return pts[pts.size() >> 1]


## Gedrosselte Meldung je Weg und Art (true = jetzt melden)
func _throttle(r: Dictionary, kind: String, interval: float) -> bool:
	var key := "notified_" + kind
	var now := GameClock.game_time
	if now - float(r.get(key, -1.0e9)) < interval:
		return false
	r[key] = now
	return true


static func _add_to(total: Dictionary, add: Dictionary) -> void:
	for res_id in add:
		total[res_id] = float(total.get(res_id, 0.0)) + float(add[res_id])


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"routes": routes.duplicate(true), "stats": stats.duplicate(), "debug_fast": debug_fast,
			"pending": _pending.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	routes = (d.get("routes", {}) as Dictionary).duplicate(true)
	var s: Dictionary = d.get("stats", {})
	for key in s:
		stats[key] = s[key]
	debug_fast = bool(d.get("debug_fast", false))
	_pending = (d.get("pending", []) as Array).duplicate(true)


## Karawanen wieder anbinden (wartende ins Lager, fahrende zum aktuellen Ziel), Wege neu berechnen
func rebuild_runtime() -> void:
	_tick_acc = 0.0
	_scan_acc = 0.0
	_repath_queue.clear()
	# Ankünfte, die beim Speichern noch nicht verarbeitet waren (_pending, gespeichert)
	var arriving := {}
	for entry in _pending:
		arriving[int(entry[1])] = true
	for id in routes:
		var r: Dictionary = routes[id]
		_repath_queue.append(id)
		var u := _caravan(r)
		if u == null:
			r["caravan_uid"] = 0
			continue
		# Unterwegs mit gespeichertem Weg (SaveGame stellt ihn wieder her) oder gerade angekommen
		# (Ankunft in _pending): nicht neu losschicken, sonst ändern sich Befehl und Weg (Idempotenz)
		var travelling := (u.command == "haul" and (u.moving or u.path_pending)) or arriving.has(u.uid)
		match str(r["leg"]):
			"idle":
				var depot := _depot(r)
				if depot != null:
					game.unit_system.set_inside(u, depot)
			"out":
				if not travelling:
					game.command_system.order_travel(u, r["far_pos"], "haul")
			"back":
				if float(r["load_until"]) < 0.0 and not travelling:
					game.command_system.order_travel(u, r["home_pos"], "haul")
		var k: Kingdom = game.get_kingdom(int(r["owner_id"]))
		if k != null:
			routes_changed.emit(k)
