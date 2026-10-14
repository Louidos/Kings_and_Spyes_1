## Rauchtest Phase 9 (gestartet von tests/smoke_test.gd): Mauerring mit Tor (eigene
## Einheit geht hindurch, Monster bekommen "blocked" ohne Ruckeln und greifen die Mauer
## an), Wachturm erlegt Wölfe, Reparatur durch Bauarbeiter, Rammbock öffnet den Ring,
## Handelsweg mit Karawane (Fahrt, Überfall, Abschneiden und Wiederöffnen), Versorgung
## fern vom Gebiet, KI befestigt sich nach einer Bedrohung. Dazu ein kurzer Test der
## Oberfläche (Baumenü-Reiter, Mauer ziehen, Tor verriegeln im Auswahlfenster).
## Jede Stufe wartet auf ihre Bedingung oder eine Frist; abgelaufene Fristen sind Fehler.
## Fehler erscheinen als "ERROR: [smoke] Phase 9 FEHLER: …" (push_error).
extends RefCounted

## Vom Rauchtest gesetzt: der Heldentest ist fertig (die Fenster sind frei)
var ui_ready := false

var _game: Node
var _errors := 0
## Mauertest: Schritt (-1 = fertig/übersprungen)
var _wall_step := 0
var _rect := Rect2i()
var _inner := Vector2i.ZERO
var _inner_label := 0
var _gate_cell := Vector2i.ZERO
var _outside := Vector2.ZERO
var _north_wall_uid := 0
var _f_uid := 0
var _wolves: Array = []
var _tower_uid := 0
var _rams: Array = []
var _r2_fort := false
var _damaged_uid := 0
var _repair_checked := false
var _reissue_at := 0.0
## Handelstest
var _trade_step := 0
var _route_id := ""
var _village: Kingdom = null
var _lost_before := 0
var _step_t := 0.0
var _route_wolves: Array = []
## Versorgung
var _supply_step := 0
var _u_uid := 0
var _u_hp := 0.0
## KI
var _ai_step := 0
var _ui_done := false


func _init(game: Node) -> void:
	_game = game


func _check(cond: bool, text: String) -> void:
	if cond:
		print("[smoke] Phase 9 OK: " + text)
	else:
		_errors += 1
		push_error("[smoke] Phase 9 FEHLER: " + text)


## Jeden Frame aufrufen (Spielzeit t)
func tick(t: float) -> void:
	_wall_tick(t)
	_trade_tick(t)
	_supply_tick(t)
	_ai_tick(t)
	if ui_ready and not _ui_done and t >= 125.0:
		_ui_done = true
		_ui_test()


# ---------------------------------------------------------------------------
# Mauern, Tor, Turm, Rammbock
# ---------------------------------------------------------------------------

func _wall_tick(t: float) -> void:
	var g := _game
	match _wall_step:
		0:
			if t >= 1.0:
				_s0()
		1:
			var f: Variant = g.find_by_uid(_f_uid)
			if f is Unit and g.nav.get_label(g.world.world_to_cell((f as Unit).position)) == _inner_label:
				_check(true, "Eigene Einheit geht durch das Tor")
				g.unit_system.remove_unit(f)
				_wall_step = 2
			elif t > 40.0:
				_check(false, "Eigene Einheit kommt nicht durch das Tor (Befehl %s)" % (str((f as Unit).command) if f is Unit else "-"))
				_wall_step = 2
		2:
			if t >= 41.0:
				_s2_spawn()
				_wall_step = 3
		3:
			var hit := false
			for w in _wolves:
				if is_instance_valid(w) and w.target is Building and is_instance_valid(w.target) and (w.target as Building).fort_kind != "":
					hit = true
			var damaged := _damaged_wall()
			# Abgelenkte Wölfe (Kampf mit Truppen in der Nähe) erneut losschicken
			if t >= _reissue_at:
				_reissue_at = t + 5.0
				var idle: Array = []
				for w in _wolves:
					if is_instance_valid(w) and (w as Unit).is_alive() and not is_instance_valid((w as Unit).target) and not (w as Unit).moving:
						idle.append(w)
				if not idle.is_empty():
					g.command_system.order_move(idle, g.world.cell_to_world(_inner))
			if (hit or damaged != null) and int(g.siege_system.stats["breach_targets"]) >= 1:
				_check(true, "Wölfe finden keinen Weg und greifen die Mauer an (Bresche-Ziele %d)" % int(g.siege_system.stats["breach_targets"]))
				_wall_step = 4
			elif t > 75.0:
				var info: PackedStringArray = []
				for w in _wolves:
					if is_instance_valid(w):
						var wu: Unit = w
						info.append("%s/%s/%s/%s/%d" % [wu.command, str(wu.target), wu.path_fail, str(wu.moving), wu.breach_tries])
				_check(false, "Wölfe greifen die Mauer nicht an (Bresche-Ziele %d; %s)" % [int(g.siege_system.stats["breach_targets"]),
						", ".join(info)])
				_wall_step = 4
			if _wall_step == 4:
				var d := _damaged_wall()
				_damaged_uid = d.uid if d != null else 0
				_remove_all(_wolves)
		4:
			if t >= 77.0:
				_s3_tower()
				_wall_step = 5
		5:
			var alive := 0
			for w in _wolves:
				if is_instance_valid(w) and (w as Unit).is_alive():
					alive += 1
			var st: Dictionary = g.siege_system.stats
			if alive == 0 and int(st["tower_kills"]) >= 1 and int(st["tower_shots"]) >= int(st["tower_kills"]):
				_check(true, "Wachturm erlegt Wölfe (Schüsse %d, Abschüsse %d)" % [int(st["tower_shots"]), int(st["tower_kills"])])
				_wall_step = 6
			elif t > 125.0:
				_check(false, "Wachturm: %d Wölfe leben noch (Schüsse %d, Abschüsse %d)" % [alive, int(st["tower_shots"]), int(st["tower_kills"])])
				_remove_all(_wolves)
				_wall_step = 6
		6:
			if t >= 127.0:
				_s5_rams()
				_wall_step = 7
		7:
			var r2: Variant = _rams[1] if _rams.size() > 1 else null
			if r2 is Unit and is_instance_valid(r2) and (r2 as Unit).target is Building and is_instance_valid((r2 as Unit).target) \
					and ((r2 as Unit).target as Building).fort_kind != "":
				_r2_fort = true
			var w: Variant = g.find_by_uid(_north_wall_uid)
			if w == null:
				g.nav.process_dirty()
				var label: int = g.nav.get_label(_inner)
				var p: PackedVector2Array = g.nav.find_path(g.world, _outside, g.world.cell_to_world(_inner), g.wild.id)
				_check(label != _inner_label and not p.is_empty(), "Rammbock zerstört das Mauerstück: Ring offen (Label %d → %d), Monster finden einen Weg (%s)" % [
						_inner_label, label, g.nav.last_fail])
				if label != 0:
					var reg: Dictionary = g.nav.get_region(label)
					print("[smoke] Phase 9: Fläche %d: %d Kacheln, Rahmen %s, Ring %s, Tor %s" % [label, (reg["cells"] as PackedInt32Array).size(),
							str(reg["rect"]), str(_rect), str(_gate_cell)])
				_check(_r2_fort, "Zweiter Rammbock greift eine Befestigung an (Bresche)")
				_remove_all(_rams)
				_wall_step = -1
			elif t > 210.0:
				_check(false, "Rammbock hat das Mauerstück nicht zerstört (%d/%d Leben)" % [roundi((w as Building).hp), roundi((w as Building).max_hp)])
				_remove_all(_rams)
				_wall_step = -1
	# Reparatur (nur mit Bauarbeitern)
	if not _repair_checked and _damaged_uid != 0 and t >= 80.0:
		var b: Variant = g.find_by_uid(_damaged_uid)
		if not (b is Building):
			_repair_checked = true
		elif (b as Building).hp >= (b as Building).max_hp * 0.98:
			_repair_checked = true
			_check(true, "Bauarbeiter haben das Mauerstück repariert (Stein %.0f)" % g.player.get_amount("stone"))
		elif t > 190.0:
			_repair_checked = true
			if g.work_system.get_job_count(g.player, "builder") > 0:
				_check(false, "Mauerstück nicht repariert (%d/%d Leben)" % [roundi((b as Building).hp), roundi((b as Building).max_hp)])
			else:
				print("[smoke] Phase 9: keine Bauarbeiter – Reparatur nicht geprüft")


## S0: Ring sofort setzen, Tor auf die Mitte der Südseite, Wegsuchen prüfen, Kämpfer hindurch
func _s0() -> void:
	var g := _game
	var player: Kingdom = g.player
	for r in DataDB.resources:
		player.add_resource(str(r["id"]), 3000.0)
	if not _find_ring_site():
		print("[smoke] Phase 9: kein Platz für den Mauerring – Mauerprüfungen übersprungen")
		_wall_step = -1
		return
	var bs: BuildingSystem = g.building_system
	var wall := DataDB.get_building("wall")
	var gate := DataDB.get_building("gate")
	var cells := _perimeter(_rect)
	var res := bs.place_line(wall, cells, player, true)
	_check(int(res["placed"]) == cells.size(), "Mauerring gesetzt (%d von %d Stücken)" % [int(res["placed"]), cells.size()])
	_gate_cell = Vector2i(_rect.position.x + 4, _rect.end.y - 1)
	var reason := bs.can_place(gate, _gate_cell, player)
	var gb := bs.place_building(gate, _gate_cell, player, true) if reason.is_empty() else null
	_check(gb != null and gb.fort_kind == "gate", "Tor ersetzt ein Mauerstück %s" % reason)
	var north: Variant = g.world.occupancy.get(Vector2i(_rect.position.x + 4, _rect.position.y), null)
	_north_wall_uid = (north as Building).uid if north is Building else 0
	var nav: NavGrid = g.nav
	nav.process_dirty()
	_inner = _rect.position + Vector2i(4, 4)
	_inner_label = nav.get_label(_inner)
	var links: Array = nav.gate_links.get(_gate_cell, [])
	_check(_inner_label > 0 and links.has(_inner_label) and links.has(0), "Ring erkannt (Label %d, Tor verbindet %s, Neubestimmung %d µs)" % [
			_inner_label, str(links), int(nav.stats["relabel_usec_max"])])
	var oc: Vector2i = nav.nearest_free(_gate_cell + Vector2i(0, 4), 3)
	_outside = g.world.cell_to_world(oc)
	var inside: Vector2 = g.world.cell_to_world(_inner)
	var own_path: PackedVector2Array = nav.find_path(g.world, _outside, inside, player.id)
	var t0 := Time.get_ticks_usec()
	var foe_path: PackedVector2Array = nav.find_path(g.world, _outside, inside, g.wild.id)
	var usec := Time.get_ticks_usec() - t0
	_check(not own_path.is_empty(), "Eigenes Reich findet den Weg durch das Tor (%d Punkte)" % own_path.size())
	_check(foe_path.is_empty() and nav.last_fail == "blocked" and usec < 20000,
			"Monster: kein Weg (Grund %s) in %d µs" % [nav.last_fail, usec])
	var def := DataDB.get_unit_for_tier(player.faction_id, "fighter")
	var f: Unit = g.unit_system.spawn_unit(player, str(def["id"]), _outside)
	_f_uid = f.uid
	g.command_system.order_move([f], inside)
	_wall_step = 1


## Freies 9×9-Rechteck um die Burg (Ring 7–12): Umfang baubar, Inneres frei, Platz vor dem Tor
func _find_ring_site() -> bool:
	var g := _game
	var player: Kingdom = g.player
	var bs: BuildingSystem = g.building_system
	var wall := DataDB.get_building("wall")
	var c0: Vector2i = g.world.world_to_cell(player.castle.get_center())
	for r in range(7, 13):
		for off in AIEconomy.ring(r, 1):
			var rect := Rect2i(c0 + off - Vector2i(4, 4), Vector2i(9, 9))
			var ok := true
			for c in _perimeter(rect):
				if g.world.roads.has(c) or not bs.can_place_line_cell(wall, c, player).is_empty():
					ok = false
					break
			if not ok:
				continue
			for y in range(rect.position.y + 1, rect.end.y - 1):
				for x in range(rect.position.x + 1, rect.end.x - 1):
					var c := Vector2i(x, y)
					if g.world.occupancy.has(c) or g.nav.is_solid(c) or g.world.roads.has(c):
						ok = false
				if not ok:
					break
			# Vor dem Tor (Süden) und vor dem Nordstück frei
			for c in [Vector2i(rect.position.x + 4, rect.end.y), Vector2i(rect.position.x + 4, rect.end.y + 1),
					Vector2i(rect.position.x + 4, rect.position.y - 1), Vector2i(rect.position.x + 4, rect.position.y - 2)]:
				if g.world.occupancy.has(c) or g.nav.is_solid(c) or not g.world.in_bounds(c):
					ok = false
			if ok:
				_rect = rect
				return true
	return false


static func _perimeter(rect: Rect2i) -> Array:
	return AISiege._perimeter(rect)


func _north_point(tiles: int) -> Vector2:
	var c: Vector2i = _game.nav.nearest_free(Vector2i(_rect.position.x + 4, _rect.position.y - tiles), 3)
	return _game.world.cell_to_world(c)


func _s2_spawn() -> void:
	var g := _game
	_wolves.clear()
	for i in 3:
		var w: Unit = g.unit_system.spawn_unit(g.wild, "wolf", _north_point(4) + Vector2(float(i - 1) * 30.0, 0))
		if w != null:
			# Zäh: Truppen in der Nähe sollen sie nicht sofort erlegen
			w.add_effect({"id": "test:hp", "key": "hp", "mult": 10.0, "until": -1.0, "source": "test"})
			_wolves.append(w)
	# Marschbefehl (ohne Angriff unterwegs): ohne Weg brechen Kämpfer durch die Mauer
	g.command_system.order_move(_wolves, g.world.cell_to_world(_inner))


func _damaged_wall() -> Building:
	for c in _perimeter(_rect):
		var b: Variant = _game.world.occupancy.get(c, null)
		if b is Building and (b as Building).hp < (b as Building).max_hp - 0.5:
			return b
	return null


func _remove_all(list: Array) -> void:
	for u in list:
		if is_instance_valid(u) and (u as Unit).is_alive():
			_game.unit_system.remove_unit(u)
	list.clear()


## S3: Turm sofort östlich des Rings, drei Wölfe (halten) in Reichweite
func _s3_tower() -> void:
	var g := _game
	var bs: BuildingSystem = g.building_system
	var def := DataDB.get_building("tower")
	var tower: Building = null
	for dy in [3, 2, 4, 1, 5, 0, 6]:
		for dx in [3, 4, 2, 5, 6]:
			var cell := Vector2i(_rect.end.x - 1 + int(dx), _rect.position.y + int(dy))
			if bs.can_place(def, cell, g.player).is_empty():
				tower = bs.place_building(def, cell, g.player, true)
				break
		if tower != null:
			break
	if tower == null:
		print("[smoke] Phase 9: kein Platz für den Turm – Turmprüfung übersprungen")
		_wall_step = 6
		return
	_tower_uid = tower.uid
	_wolves.clear()
	for i in 3:
		var c: Vector2i = g.nav.nearest_free(g.world.world_to_cell(tower.get_center() + Vector2(4.0 * 64.0, float(i - 1) * 40.0)), 3)
		var w: Unit = g.unit_system.spawn_unit(g.wild, "wolf", g.world.cell_to_world(c))
		if w != null:
			# Schwach: der Turm soll sie erlegen, bevor andere Truppen eingreifen
			w.hp = 12.0
			_wolves.append(w)
	g.command_system.order_stop(_wolves)


## S5: Rammbock 1 greift ein Mauerstück an (innen und aussen frei – nach dem Mauerbau können
## Gebäude im Ring stehen), Rammbock 2 will hinein (Bresche)
func _s5_rams() -> void:
	var g := _game
	var nav: NavGrid = g.nav
	var w: Building = null
	var out_dir := Vector2i.ZERO
	var center := Vector2(_rect.get_center())
	for c in _perimeter(_rect):
		var cell: Vector2i = c
		var b: Variant = g.world.occupancy.get(cell, null)
		if not (b is Building) or (b as Building).fort_kind != "wall":
			continue
		var d := Vector2i.ZERO
		if cell.y == _rect.position.y and cell.x > _rect.position.x and cell.x < _rect.end.x - 1:
			d = Vector2i(0, -1)
		elif cell.y == _rect.end.y - 1 and cell.x > _rect.position.x and cell.x < _rect.end.x - 1:
			d = Vector2i(0, 1)
		elif cell.x == _rect.position.x and cell.y > _rect.position.y and cell.y < _rect.end.y - 1:
			d = Vector2i(-1, 0)
		elif cell.x == _rect.end.x - 1 and cell.y > _rect.position.y and cell.y < _rect.end.y - 1:
			d = Vector2i(1, 0)
		if d == Vector2i.ZERO or nav.is_solid(cell - d) or nav.is_solid(cell + d) or nav.is_solid(cell + d * 2) \
				or nav.is_gate(cell + Vector2i(d.y, d.x)) or nav.is_gate(cell - Vector2i(d.y, d.x)):
			continue
		if w == null or Vector2(cell).distance_to(center + Vector2(0, -10)) < Vector2(w.cell).distance_to(center + Vector2(0, -10)):
			w = b
			out_dir = d
	if w == null:
		print("[smoke] Phase 9: kein freies Mauerstück – Rammbock-Prüfung übersprungen")
		_wall_step = -1
		return
	_north_wall_uid = w.uid
	_inner = w.cell - out_dir
	nav.process_dirty()
	_inner_label = nav.get_label(_inner)
	_rams.clear()
	var side := Vector2(out_dir.y, out_dir.x) * 50.0
	for i in 2:
		var cpos: Vector2i = nav.nearest_free(w.cell + out_dir * 2, 2)
		var ram: Unit = g.unit_system.spawn_unit(g.wild, "ram_evil", g.world.cell_to_world(cpos) + side * (float(i) - 0.5))
		# Für den Test zäher (Türme und Truppen in der Nähe)
		ram.add_effect({"id": "test:hp", "key": "hp", "mult": 6.0, "until": -1.0, "source": "test"})
		_rams.append(ram)
	g.command_system.order_attack([_rams[0]], w)
	g.command_system.order_move([_rams[1]], g.world.cell_to_world(_inner), true)


# ---------------------------------------------------------------------------
# Handelsweg und Karawane
# ---------------------------------------------------------------------------

func _trade_tick(t: float) -> void:
	var g := _game
	var trs: TradeRouteSystem = g.trade_route_system
	match _trade_step:
		0:
			if t >= 20.0:
				_s6_route()
		1:
			if t >= _step_t + 3.0:
				var r := trs.get_route(_route_id)
				_check(not r.is_empty() and not (r["points"] as Array).is_empty() and g.diplomacy_system.use_caravans,
						"Handelsweg nach %s mit %d Wegpunkten, Lieferungen per Karawane" % [_village.display_name,
						(r["points"] as Array).size() if not r.is_empty() else 0])
				_trade_step = 2 if not r.is_empty() else -1
		2:
			var r := trs.get_route(_route_id)
			var t_v: Dictionary = g.diplomacy_system.get_treaty(_village)
			if not r.is_empty() and int(trs.stats["trips"]) >= 1 and int(t_v.get("deliveries", 0)) >= 1:
				_check(true, "Karawane hat den Handelsweg abgeschlossen (Fahrten %d, Lieferungen %d)" % [
						int(trs.stats["trips"]), int(t_v.get("deliveries", 0))])
				_lost_before = int(trs.stats["lost"])
				_village.add_resource("food", 200.0)
				_force_delivery()
				_trade_step = 3
				_step_t = t
			elif t > 480.0 or r.is_empty():
				_check(false, "Karawane hat keine Fahrt abgeschlossen (Zustand %s, Karawane %s)" % [
						str(r.get("state", "-")), str(r.get("leg", "-"))])
				_trade_step = -1
		3:
			var r := trs.get_route(_route_id)
			if r.is_empty():
				_trade_step = -1
			elif str(r["leg"]) == "out":
				trs.debug_kill_caravan(_route_id, g.wild)
				_trade_step = 4
				_step_t = t
			elif t > _step_t + 120.0:
				_check(false, "Karawane fährt nicht wieder los (Weg %s, %d fällig)" % [str(r["state"]), int(r["pending"])])
				_trade_step = -1
		4:
			var r := trs.get_route(_route_id)
			if r.is_empty():
				_trade_step = -1
			elif t >= _step_t + 8.0:
				_check(int(trs.stats["lost"]) == _lost_before + 1 and str(r["state"]) == "open" and int(r["caravan_uid"]) != 0,
						"Karawane überfallen: Verluste %d, Weg %s, neue Karawane %s" % [int(trs.stats["lost"]), str(r["state"]),
						str(int(r["caravan_uid"]) != 0)])
				_route_wolves.clear()
				var mid := trs.get_midpoint(r)
				for i in 3:
					var c: Vector2i = g.nav.nearest_free(g.world.world_to_cell(mid + Vector2(float(i - 1) * 40.0, 0)), 3)
					var w: Unit = g.unit_system.spawn_unit(g.wild, "wolf", g.world.cell_to_world(c))
					if w != null:
						w.add_effect({"id": "test:hp", "key": "hp", "mult": 10.0, "until": -1.0, "source": "test"})
						_route_wolves.append(w)
				g.command_system.order_stop(_route_wolves)
				_trade_step = 5
				_step_t = t
		5:
			var r := trs.get_route(_route_id)
			if r.is_empty():
				_trade_step = -1
			elif str(r["state"]) == "cut":
				_check(true, "Handelsweg abgeschnitten (%s)" % str(r["reason"]))
				_remove_all(_route_wolves)
				_trade_step = 6
				_step_t = t
			elif t > _step_t + 15.0:
				_check(false, "Handelsweg trotz Wölfen nicht abgeschnitten (Gefahr %.1f s)" % float(r["danger_time"]))
				_remove_all(_route_wolves)
				_trade_step = -1
		6:
			var r := trs.get_route(_route_id)
			if r.is_empty():
				_trade_step = -1
			elif str(r["state"]) == "open":
				_check(true, "Handelsweg wieder offen")
				_trade_step = -1
				trs.debug_fast = false
			elif t > _step_t + 20.0:
				_check(false, "Handelsweg nicht wieder offen (%s, frei seit %.1f s)" % [str(r["state"]), float(r["clear_time"])])
				_trade_step = -1
				trs.debug_fast = false


## S6: Handelsweg des Spielers (Phase 6 schliesst bei t = 13 einen Handelsvertrag), sonst erzwingen
func _s6_route() -> void:
	var g := _game
	var trs: TradeRouteSystem = g.trade_route_system
	var ds: DiplomacySystem = g.diplomacy_system
	var player: Kingdom = g.player
	for r in trs.get_routes(player):
		if str(r["kind"]) == "trade":
			_route_id = str(r["id"])
			break
	if _route_id.is_empty():
		var vs: VillageSystem = g.village_system
		var from: Vector2 = player.castle.get_center()
		var best: Kingdom = null
		var best_d := INF
		for v in vs.get_villages():
			if not ds.get_treaty(v).is_empty() or g.are_hostile(v, player):
				continue
			var d := from.distance_to(vs.get_center(v))
			if d < best_d:
				best_d = d
				best = v
		if best == null or not ds.start_treaty_forced(best, player, "trade").is_empty():
			print("[smoke] Phase 9: kein Dorf für einen Handelsweg – Handelsprüfung übersprungen")
			_trade_step = -1
			return
		_route_id = "%d:%d" % [player.id, best.id]
	var route := trs.get_route(_route_id)
	_village = g.get_kingdom(int(route["partner_id"]))
	trs.debug_fast = true
	_village.add_resource("food", 300.0)
	var delivery: Dictionary = g.village_system.get_people(_village).get("delivery", {})
	var give: Dictionary = delivery.get("give", {})
	for res_id in give:
		_village.add_resource(str(res_id), float(give[res_id]) * 3.0)
	_force_delivery()
	_trade_step = 1
	_step_t = GameClock.game_time


func _force_delivery() -> void:
	var t: Dictionary = _game.diplomacy_system.get_treaty(_village)
	if not t.is_empty() and str(t.get("type", "")) == "trade":
		t["next_delivery"] = GameClock.game_time
	var give: Dictionary = (_game.village_system.get_people(_village).get("delivery", {}) as Dictionary).get("give", {})
	for res_id in give:
		_village.add_resource(str(res_id), float(give[res_id]) * 2.0)


# ---------------------------------------------------------------------------
# Versorgung
# ---------------------------------------------------------------------------

func _supply_tick(t: float) -> void:
	var g := _game
	match _supply_step:
		0:
			if t >= 200.0:
				var cell := _far_cell()
				if cell.x < 0:
					print("[smoke] Phase 9: kein Platz fern vom Gebiet – Versorgung nicht geprüft")
					_supply_step = -1
					return
				var def := DataDB.get_unit_for_tier(g.player.faction_id, "fighter")
				var u: Unit = g.unit_system.spawn_unit(g.player, str(def["id"]), g.world.cell_to_world(cell))
				g.command_system.order_stop([u])
				u.hp = u.max_hp * 0.5
				_u_uid = u.uid
				_supply_step = 1
				_step_t = t
		1:
			var u: Variant = g.find_by_uid(_u_uid)
			if not (u is Unit):
				_supply_step = -1
			elif t >= _step_t + 6.0:
				_check(SupplySystem._has_effect(u), "Einheit fern vom Gebiet ohne Versorgung (Wirkung supply:regen)")
				_u_hp = (u as Unit).hp
				_supply_step = 2
				_step_t = t
		2:
			var u: Variant = g.find_by_uid(_u_uid)
			if not (u is Unit):
				_supply_step = -1
			elif t >= _step_t + 5.0:
				_check((u as Unit).hp <= _u_hp + 0.01, "Ohne Versorgung keine Erholung (%.1f → %.1f)" % [_u_hp, (u as Unit).hp])
				var castle: Building = g.player.castle
				(u as Unit).position = castle.get_approach_point(castle.get_center() + Vector2(0, 2000))
				g.command_system.order_stop([u])
				_u_hp = (u as Unit).hp
				_supply_step = 3
				_step_t = t
		3:
			var u: Variant = g.find_by_uid(_u_uid)
			if not (u is Unit):
				_supply_step = -1
			elif not SupplySystem._has_effect(u) and (u as Unit).hp > _u_hp + 0.1:
				_check(true, "Im eigenen Gebiet wieder versorgt (Leben %.1f → %.1f)" % [_u_hp, (u as Unit).hp])
				g.unit_system.remove_unit(u)
				_supply_step = -1
			elif t > _step_t + 8.0:
				_check(false, "Versorgung im eigenen Gebiet fehlt (Wirkung %s, Leben %.1f → %.1f)" % [
						str(SupplySystem._has_effect(u)), _u_hp, (u as Unit).hp])
				_supply_step = -1


## Freie Kachel mindestens 40 Felder von jedem Gebiet und Handelsweg
func _far_cell() -> Vector2i:
	var g := _game
	var world: WorldData = g.world
	var c0: Vector2i = world.world_to_cell(g.player.castle.get_center())
	var pts: Array = []
	for k in g.kingdoms:
		for r in g.trade_route_system.get_routes(k):
			pts.append_array(r["points"])
	for r in range(50, 200, 6):
		for off in AIEconomy.ring(r, 6):
			var c: Vector2i = c0 + off
			if not world.in_bounds(c) or g.nav.is_solid(c) or world.get_owner(c) != 0:
				continue
			var ok := true
			for dy in range(-40, 41, 5):
				for dx in range(-40, 41, 5):
					var n := c + Vector2i(dx, dy)
					if world.in_bounds(n) and world.get_owner(n) != 0:
						ok = false
						break
				if not ok:
					break
			var pos := world.cell_to_world(c)
			for p in pts:
				if (p as Vector2).distance_to(pos) < 40.0 * world.tile_size:
					ok = false
					break
			if ok:
				return c
	return Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# KI
# ---------------------------------------------------------------------------

func _ai_tick(t: float) -> void:
	var g := _game
	if g.get("ai_system") == null:
		return
	var ai: AISystem = g.ai_system
	match _ai_step:
		0:
			if t >= 30.0:
				var kingdoms := ai.get_ai_kingdoms()
				if kingdoms.is_empty():
					_ai_step = -1
					return
				var brain := ai.get_brain(kingdoms[0])
				AISiege.debug_force_threat(brain)
				for res_id in ["stone", "wood"]:
					(kingdoms[0] as Kingdom).add_resource(res_id, 600.0)
				_ai_step = 1
		1:
			var k: Kingdom = ai.get_ai_kingdoms()[0] if not ai.get_ai_kingdoms().is_empty() else null
			if k == null:
				_ai_step = -1
				return
			var c: Dictionary = g.siege_system.get_counts(k)
			var total := int(c["wall"]) + int(c["gate"]) + int(c["tower"]) + int(c["sites"])
			if total >= 1:
				_check(true, "%s befestigt sich nach der Bedrohung (%s)" % [k.display_name, str(c)])
				_ai_step = -1
			elif t > 400.0:
				_check(false, "%s baut keine Befestigung (%s)" % [k.display_name, str(c)])
				_ai_step = -1


# ---------------------------------------------------------------------------
# Oberfläche
# ---------------------------------------------------------------------------

func _ui_test() -> void:
	var g := _game
	var menu: BuildMenu = g.hud.build_menu
	menu.select_tab("defense")
	var shown: Array = []
	for id in menu._buttons:
		if (menu._buttons[id] as Button).visible:
			shown.append(str(id))
	_check(shown.has("wall") and shown.has("gate") and shown.has("tower") and not shown.has("house"),
			"Baumenü-Reiter Verteidigung zeigt %s" % str(shown))
	menu.select_tab("economy")
	# Mauer ziehen über den PlacementController (ausserhalb des Testrings)
	var placement: PlacementController = g.placement
	var player: Kingdom = g.player
	var c0: Vector2i = g.world.world_to_cell(player.castle.get_center())
	var before := int(g.siege_system.get_counts(player)["sites"]) + int(g.siege_system.get_counts(player)["wall"])
	var wall := DataDB.get_building("wall")
	var placed := false
	for r in range(5, 13):
		for off in AIEconomy.ring(r, 2):
			var a: Vector2i = c0 + off
			var b := a + Vector2i(3, 0)
			var ok := true
			for x in range(a.x, b.x + 1):
				if not g.building_system.can_place_line_cell(wall, Vector2i(x, a.y), player).is_empty() or _rect.has_point(Vector2i(x, a.y)):
					ok = false
			if not ok:
				continue
			placement.start(wall)
			placement._drag_start = a
			placement._mouse_cell = b
			placement._finish_drag()
			placement.cancel()
			placed = true
			break
		if placed:
			break
	var after := int(g.siege_system.get_counts(player)["sites"]) + int(g.siege_system.get_counts(player)["wall"])
	_check(placed and after >= before + 4, "Mauer über die Bauvorschau gezogen (%d → %d Stücke)" % [before, after])
	# Tor im Auswahlfenster verriegeln
	var gate: Variant = g.world.occupancy.get(_gate_cell, null) if _wall_step != 0 else null
	if gate is Building and (gate as Building).fort_kind == "gate":
		g.selection.select([gate])
		var panel: SelectionPanel = g.hud.selection_panel
		var row_visible := panel._gate_row.visible
		panel._on_gate_pressed()
		var locked: bool = g.siege_system.is_gate_locked(gate)
		g.siege_system.set_gate_locked(gate, false)
		g.selection.clear()
		_check(row_visible and locked, "Auswahlfenster: Tor verriegeln (Zeile %s, verriegelt %s)" % [str(row_visible), str(locked)])
	# Handelsliste: Diplomatiefenster (Reiter "Handelswege") und Reichsübersicht (Reiter "Handel")
	var hud: Node = g.hud
	var own_routes: int = g.trade_route_system.get_routes(player).size()
	hud.open_trade()
	var dp: DiplomacyPanel = hud.diplomacy_panel
	_check(dp.is_open() and dp.get_tab() == DiplomacyPanel.TAB_TRADE and dp.trade_list != null,
			"Diplomatiefenster: Reiter Handelswege (%d eigene Wege)" % own_routes)
	var kp: Variant = hud.get("kingdom_panel")
	if kp is KingdomPanel:
		hud.open_kingdom(KingdomPanel.TAB_TRADE)
		var kpanel := kp as KingdomPanel
		var rows: int = kpanel.trade_list._rows.size() if kpanel.trade_list != null else -1
		_check(kpanel.is_open() and not dp.is_open() and kpanel.get_tab() == KingdomPanel.TAB_TRADE and rows == own_routes,
				"Reichsübersicht: Reiter Handel zeigt %d von %d Handelswegen" % [rows, own_routes])
		kpanel.close()
	if dp.is_open():
		dp.close()


# ---------------------------------------------------------------------------
# Bericht
# ---------------------------------------------------------------------------

func report() -> void:
	var g := _game
	for k in g.kingdoms:
		var kingdom: Kingdom = k
		if kingdom.controller == "player" or kingdom.controller == "ai":
			print("[smoke] Phase 9: %s Befestigungen %s" % [kingdom.display_name, str(g.siege_system.get_counts(kingdom))])
	var nav: NavGrid = g.nav
	print("[smoke] Phase 9: Wegfindung %s" % str(nav.stats))
	print("[smoke] Phase 9: Belagerung %s" % str(g.siege_system.stats))
	var trs: TradeRouteSystem = g.trade_route_system
	print("[smoke] Phase 9: Handelswege %s" % str(trs.stats))
	for id in trs.routes:
		var r: Dictionary = trs.routes[id]
		var owner_k: Kingdom = g.get_kingdom(int(r["owner_id"]))
		var v: Kingdom = g.get_kingdom(int(r["partner_id"]))
		print("[smoke] Phase 9: Weg %s → %s (%s): %s, Fahrten %d, Verluste %d, ausgefallen %d, Karawane %s" % [
				owner_k.display_name if owner_k != null else "?", v.display_name if v != null else "?", str(r["kind"]),
				str(r["state"]), int(r["stats"]["trips"]), int(r["stats"]["lost"]), int(r["missed"]),
				str(int(r["caravan_uid"]) != 0)])
	for k in g.kingdoms:
		var kingdom: Kingdom = k
		var n: int = g.supply_system.get_unsupplied(kingdom).size()
		if n > 0:
			print("[smoke] Phase 9: %s – %d Einheiten ohne Versorgung" % [kingdom.display_name, n])
	if int(nav.stats["relabel_usec_max"]) > 50000:
		print("[smoke] Phase 9 WARNUNG: Neubestimmung der Ringe dauerte bis %d µs" % int(nav.stats["relabel_usec_max"]))
	if _wall_step > 0 or _trade_step > 0 or _supply_step > 0 or _ai_step > 0:
		_check(false, "Phase-9-Test nicht fertig (Mauern %d, Handel %d, Versorgung %d, KI %d)" % [_wall_step, _trade_step,
				_supply_step, _ai_step])
	print("[smoke] Phase 9: %s" % ("OK" if _errors == 0 else "%d Fehler" % _errors))
