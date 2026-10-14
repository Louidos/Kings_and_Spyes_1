## SiegeSystem
##
## Belagerung (Phase 9): Mauern, Tore, Türme, Bresche, Reparatur-Hilfen, Belagerungsziele.
## - Mauern, Tore und Türme sind normale Gebäude (buildings.json fortification). Dieses
##   System meldet sie beim NavGrid an (Mauerkacheln für die Ringe, Tore je Reich mit
##   Durchlass-Regel gate_rule) und führt einen groben Index für Zielsuchen.
## - Bresche: findet eine Einheit keinen Weg (Ring, Tasche, gesperrtes Tor), sucht
##   find_breach_target das feindliche Mauerstück bzw. Tor, das den Weg versperrt.
## - Türme schiessen im Simulationstakt selbsttätig auf Feinde in Reichweite.
## - Belagerungswaffen (Rammbock, Katapult) wählen ihre Ziele über find_siege_target.
## Für Spieler und KI gleich; Meldungen nur über kingdom.notify (gebündelt, gedrosselt).
##
## Zustand: stats, notified (gedrosselte Meldungen). Gespeichert wird sonst alles an den
## Gebäuden (extra.locked am Tor, Turm extra.cd/think/target_uid).
## Laufzeit: _forts (uid -> Building), _towers, _fort_index (16er-Raster -> Gebäude),
## _built (gesammelte Baumeldungen).
class_name SiegeSystem
extends Node

## Befestigungen eines Reichs haben sich geändert (gesetzt, entfernt, Besitzer)
signal fortifications_changed(kingdom: Kingdom)
## Ein Mauerstück eines Reichs wurde zerstört
signal breach(kingdom: Kingdom, attacker: Kingdom, pos: Vector2)
signal gate_toggled(gate: Building, locked: bool)

## Rastergrösse des Befestigungsindex (Kacheln)
const INDEX_CELL := 16
## Meldungen gedrosselt je Gebiet dieser Kantenlänge (Kacheln)
const NOTIFY_AREA := 20

var game: Node
var world: WorldData
var nav: NavGrid
var stats := {"tower_shots": 0, "tower_kills": 0, "breaches": 0, "segments_lost": 0, "breach_targets": 0}
## "art:reich:gx:gy" -> Spielzeit der letzten Meldung
var notified: Dictionary = {}

var _forts: Dictionary = {}
var _towers: Array = []
var _fort_index: Dictionary = {}
## Reich-id -> true: modifiers_changed ist verbunden (Leben der Befestigungen nachführen)
var _connected: Dictionary = {}
## Reich-id -> {"count", "at", "pos"}: fertige Mauerstücke (gesammelte Meldung)
var _built: Dictionary = {}
var _ts := 64.0


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	nav = game.nav
	_ts = float(world.tile_size)
	nav.gate_rule = _gate_rule
	var bs: BuildingSystem = game.building_system
	bs.building_placed.connect(_on_building_placed)
	bs.building_removed.connect(_on_building_removed)
	bs.building_completed.connect(_on_building_completed)
	bs.building_transferred.connect(_on_building_transferred)
	game.relation_changed.connect(func(_a: Kingdom, _b: Kingdom, _s: String) -> void: nav.bump_gates())
	GameClock.sim_tick.connect(_on_sim_tick)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

func is_fortification(b: Building) -> bool:
	return is_instance_valid(b) and b.fort_kind != ""


## Anzahl fertiger Befestigungen je Art und offene Baustellen: {"wall", "gate", "tower", "sites"}
func get_counts(k: Kingdom) -> Dictionary:
	var counts := {"wall": 0, "gate": 0, "tower": 0, "sites": 0}
	for uid in _forts:
		var b: Building = _forts[uid]
		if not is_instance_valid(b) or b.kingdom != k:
			continue
		if not b.constructed:
			counts["sites"] = int(counts["sites"]) + 1
		else:
			counts[b.fort_kind] = int(counts.get(b.fort_kind, 0)) + 1
	return counts


## Befestigt? (Mauern ≥ ai.siege.fortified_walls oder Türme ≥ fortified_towers)
func is_fortified(k: Kingdom) -> bool:
	if k == null:
		return false
	var c := get_counts(k)
	return int(c["wall"]) + int(c["gate"]) >= int(DataDB.ai("siege.fortified_walls", 8)) \
			or int(c["tower"]) >= int(DataDB.ai("siege.fortified_towers", 2))


## Liegt die Burg in einem Mauerring mit eigenem Tor?
func is_castle_walled(k: Kingdom) -> bool:
	if k == null or not is_instance_valid(k.castle) or not nav.has_regions():
		return false
	nav.process_dirty()
	var c := world.world_to_cell(k.castle.get_approach_point(k.castle.get_center() + Vector2(0, 1000)))
	var label := nav.get_label(c)
	if label == 0:
		return false
	for g in nav.gates:
		if int(nav.gates[g]) == k.id and (nav.gate_links.get(g, []) as Array).has(label):
			return true
	return false


## Sicherheit für die Zufriedenheit (Phase 8): Ring mit Tor um die Burg, Türme
func get_safety_bonus(k: Kingdom) -> float:
	var bonus := 0.0
	if is_castle_walled(k):
		bonus += float(DataDB.siege("safety.walled", 4))
	var towers := int(get_counts(k)["tower"])
	bonus += minf(towers * float(DataDB.siege("safety.tower_each", 1)), float(DataDB.siege("safety.tower_max", 4)))
	return bonus


## Turmreichweite in Feldern (mit Zuschlag tower_range)
func get_tower_range(b: Building) -> float:
	return b.get_tower_range() if is_instance_valid(b) else 0.0


## Kachel quer vor oder hinter einem Tor? (Ausrichtung aus den Mauernachbarn; ohne
## Mauernachbarn keine) – dort darf nichts gebaut werden, sonst wäre das Tor zu
func is_gate_apron(cell: Vector2i) -> bool:
	if nav == null or nav.gates.is_empty():
		return false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var g: Vector2i = cell + d
		if not nav.gates.has(g):
			continue
		var horizontal := _is_fort_cell(g + Vector2i(1, 0)) or _is_fort_cell(g + Vector2i(-1, 0))
		var vertical := _is_fort_cell(g + Vector2i(0, 1)) or _is_fort_cell(g + Vector2i(0, -1))
		# Waagrechte Mauer: Durchgang senkrecht (oben/unten) und umgekehrt
		if horizontal and not vertical and d.x == 0:
			return true
		if vertical and not horizontal and d.y == 0:
			return true
	return false


func _is_fort_cell(c: Vector2i) -> bool:
	var b: Variant = world.occupancy.get(c, null)
	return b != null and is_instance_valid(b) and (b as Building).fort_kind != ""


func is_gate_locked(b: Building) -> bool:
	return is_instance_valid(b) and bool(b.extra.get("locked", false))


## Tor verriegeln (nur noch eigene und verbündete Einheiten) oder öffnen
func set_gate_locked(b: Building, locked: bool) -> void:
	if not is_instance_valid(b) or b.fort_kind != "gate":
		return
	b.extra["locked"] = locked
	nav.set_gate_locked(b.cell, locked)
	b.queue_redraw()
	gate_toggled.emit(b, locked)
	b.kingdom.notify("Tor verriegelt – nur eigene und verbündete Einheiten." if locked else "Tor geöffnet.", "info", b.position)


## Darf k durch ein Tor von owner_k? Eigene immer; Krieg nie; verriegelt: nur Verbündete;
## sonst auch friedliche Reiche
func gate_passable_for(owner_k: Kingdom, k: Kingdom, locked: bool) -> bool:
	if owner_k == null or k == null:
		return false
	if owner_k == k:
		return true
	if game.are_hostile(owner_k, k):
		return false
	if locked:
		return game.are_allied(owner_k, k)
	return true


func _gate_rule(owner_id: int, kingdom_id: int, locked: bool) -> bool:
	return gate_passable_for(game.get_kingdom(owner_id), game.get_kingdom(kingdom_id), locked)


## Befestigungen im Umkreis (Weltpixel) um pos
func query_forts(pos: Vector2, radius_px: float) -> Array:
	var result: Array = []
	var c := world.world_to_cell(pos)
	var r := ceili(radius_px / _ts)
	var x0 := floori(float(c.x - r) / INDEX_CELL)
	var x1 := floori(float(c.x + r) / INDEX_CELL)
	var y0 := floori(float(c.y - r) / INDEX_CELL)
	var y1 := floori(float(c.y + r) / INDEX_CELL)
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			var key := Vector2i(gx, gy)
			if not _fort_index.has(key):
				continue
			for b in _fort_index[key]:
				if is_instance_valid(b) and (b as Building).get_center().distance_to(pos) <= radius_px + (b as Building).get_radius():
					result.append(b)
	return result


# ---------------------------------------------------------------------------
# Bresche und Belagerungsziele
# ---------------------------------------------------------------------------

## Bresche: feindliches Mauerstück/Tor (oder Gebäude), das den Weg von u versperrt (null = keins angreifbar)
func find_breach_target(u: Unit) -> Building:
	u.breach_tries += 1
	if u.breach_tries > int(DataDB.siege("breach.max_tries", 4)):
		return null
	var result: Building = null
	match u.path_fail:
		"gate":
			var b := _building_at(u.path_fail_cell)
			if b != null and game.combat_system.is_valid_target(u.kingdom, b):
				result = b
		"blocked":
			var reg := nav.get_region(u.path_fail_region)
			result = _best_on_boundary(u, reg.get("boundary", PackedInt32Array()))
		"pocket":
			result = _best_on_boundary(u, nav.pocket_boundary(u.path_fail_cell))
	if result != null:
		stats["breach_targets"] = int(stats["breach_targets"]) + 1
	return result


## Bestes angreifbares Gebäude auf den Randkacheln: bevorzugt von der eigenen Seite
## erreichbar (4er-Nachbar mit dem Label der Einheit), Tore und Türme rechnen näher
func _best_on_boundary(u: Unit, boundary: PackedInt32Array) -> Building:
	if boundary.is_empty():
		return null
	var combat: CombatSystem = game.combat_system
	var own_cell := nav.nearest_free(world.world_to_cell(u.position), 2)
	var own := nav.get_label(own_cell) if own_cell.x >= 0 else 0
	var gate_f := float(DataDB.siege("breach.siege_gate_factor" if u.target_mode != "" else "breach.gate_factor", 0.9))
	var best: Building = null
	var best_score := INF
	var any: Building = null
	var any_score := INF
	var checked := {}
	for i in boundary:
		var c := nav.index_to_cell(i)
		var b := _building_at(c)
		if b == null:
			continue
		var reachable := _touches_label(c, own)
		var key := Vector2i(b.uid, 1 if reachable else 0)
		if checked.has(key):
			continue
		checked[key] = true
		if not combat.is_valid_target(u.kingdom, b):
			continue
		var score := u.position.distance_to(world.cell_to_world(c))
		if b.fort_kind == "gate":
			score *= gate_f
		elif b.fort_kind == "tower":
			score *= 0.8
		if reachable and score < best_score:
			best_score = score
			best = b
		if score < any_score:
			any_score = score
			any = b
	return best if best != null else any


func _touches_label(c: Vector2i, label: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if nav.contains(n) and not nav.is_solid(n) and nav.get_label(n) == label:
			return true
	return false


func _building_at(c: Vector2i) -> Building:
	var b: Variant = world.occupancy.get(c, null)
	if b == null or not is_instance_valid(b):
		return null
	return b as Building


## Ziel für Belagerungswaffen (targets != ""): Türme > Tore > Mauern > Gebäude im Umkreis,
## sonst (buildings_first) Einheiten
func find_siege_target(u: Unit, radius_px: float) -> Object:
	var combat: CombatSystem = game.combat_system
	var best: Object = null
	var best_score := INF
	for b in query_forts(u.position, radius_px):
		var bld: Building = b
		if not combat.is_valid_target(u.kingdom, bld):
			continue
		var f := 1.0
		match bld.fort_kind:
			"tower":
				f = 0.4
			"gate":
				f = 0.6
		var score := maxf(u.position.distance_to(bld.get_center()) - bld.get_radius(), 1.0) * f
		if score < best_score:
			best_score = score
			best = bld
	if best == null:
		for k in game.kingdoms:
			if k == u.kingdom or not combat.hostile(u.kingdom, k):
				continue
			for bld in k.buildings:
				if bld.is_segment or bld.fort_kind != "":
					continue
				var d: float = u.position.distance_to(bld.position) - bld.get_radius()
				if d <= radius_px and d * 1.2 < best_score:
					best_score = d * 1.2
					best = bld
	if best == null and u.target_mode == "buildings_first":
		return combat.find_unit_target(u, radius_px)
	return best


# ---------------------------------------------------------------------------
# Meldungen
# ---------------------------------------------------------------------------

## Mauerstück zerstört: gebündelte, gedrosselte Meldungen für Besitzer und Angreifer
func on_segment_destroyed(b: Building, killer: Kingdom) -> void:
	stats["segments_lost"] = int(stats["segments_lost"]) + 1
	var k := b.kingdom
	if killer == null or killer == k:
		return
	stats["breaches"] = int(stats["breaches"]) + 1
	breach.emit(k, killer, b.position)
	var interval := float(DataDB.siege("breach.breach_notify_interval", 30))
	if _throttle("breach_own", k, b.position, interval):
		k.notify("Mauer durchbrochen!", "danger", b.position)
	if _throttle("breach_foe", killer, b.position, interval):
		killer.notify("Bresche geschlagen!", "good", b.position)


## Weg versperrt: Spielertruppen brechen durch (gedrosselt)
func notify_blocked(u: Unit, wall: Building) -> void:
	if not u.kingdom.is_player or not is_instance_valid(wall):
		return
	if _throttle("blocked", u.kingdom, u.position, float(DataDB.siege("breach.notify_interval", 20))):
		u.kingdom.notify("Weg versperrt – deine Truppen brechen durch die Mauer von %s." % wall.kingdom.display_name,
				"info", wall.position)


## Kein Weg wegen eigener oder friedlicher Mauern (gedrosselt)
func notify_no_way(u: Unit) -> void:
	if not u.kingdom.is_player or not (u.path_fail in ["blocked", "pocket", "gate"]):
		return
	if not _throttle("noway", u.kingdom, u.position, float(DataDB.siege("breach.notify_interval", 20))):
		return
	var owner_k: Kingdom = null
	var boundary := PackedInt32Array()
	match u.path_fail:
		"blocked":
			boundary = nav.get_region(u.path_fail_region).get("boundary", PackedInt32Array())
		"pocket":
			boundary = nav.pocket_boundary(u.path_fail_cell)
		"gate":
			var g := _building_at(u.path_fail_cell)
			owner_k = g.kingdom if g != null else null
	for i in boundary:
		var b := _building_at(nav.index_to_cell(i))
		if b != null and b.fort_kind != "":
			owner_k = b.kingdom
			break
	if owner_k == u.kingdom or owner_k == null:
		u.kingdom.notify("Kein Weg: deine Mauern haben hier kein Tor.", "warning", u.position)
	else:
		u.kingdom.notify("Kein Weg: Mauern von %s versperren den Weg (kein Krieg – nicht angreifbar)." % owner_k.display_name,
				"warning", u.position)


## Gedrosselte Meldung je Art, Reich und Gebiet: true = jetzt melden
func _throttle(kind: String, k: Kingdom, pos: Vector2, interval: float) -> bool:
	if k == null:
		return false
	var c := world.world_to_cell(pos)
	var key := "%s:%d:%d:%d" % [kind, k.id, floori(float(c.x) / NOTIFY_AREA), floori(float(c.y) / NOTIFY_AREA)]
	var now := GameClock.game_time
	if now - float(notified.get(key, -1.0e9)) < interval:
		return false
	notified[key] = now
	return true


## Text für das Auswahlfenster (Mauer, Tor, Turm)
func get_building_facts(b: Building) -> String:
	if not is_instance_valid(b) or b.fort_kind == "":
		return ""
	var armor := roundi(float(b.def.get("armor", 0.0)) * 100.0)
	var parts: PackedStringArray = []
	match b.fort_kind:
		"wall":
			parts.append("Mauerstück · Rüstung %d %%" % armor)
		"gate":
			parts.append("Tor · Rüstung %d %%" % armor)
			parts.append("verriegelt: nur eigene und verbündete Einheiten" if is_gate_locked(b)
					else "offen für Verbündete und Friedliche")
		"tower":
			var tw: Dictionary = b.def.get("tower", {})
			var dmg := float(tw.get("attack", 0.0)) * b.kingdom.mod("tower_attack")
			parts.append("Turm · %d Schaden alle %s s · Reichweite %s Felder" % [roundi(dmg),
					String.num(float(tw.get("interval", 1.0)), 1).replace(".", ","),
					String.num(get_tower_range(b), 1).replace(".", ",")])
			var t: Variant = game.find_by_uid(int(b.extra.get("target_uid", 0))) if int(b.extra.get("target_uid", 0)) != 0 else null
			if t is Unit and is_instance_valid(t):
				parts.append("Ziel: %s" % (t as Unit).get_display_name())
	if b.constructed and b.hp < b.max_hp - 0.5:
		var cost: Dictionary = game.building_system.repair_cost(b, b.max_hp - b.hp)
		var rounded := {}
		for res_id in cost:
			rounded[res_id] = maxf(roundf(float(cost[res_id])), 1.0)
		parts.append("beschädigt: Bauarbeiter reparieren (≈ %s)" % DataDB.cost_to_text(rounded))
	return " · ".join(parts)


# ---------------------------------------------------------------------------
# Anmelden und Abmelden
# ---------------------------------------------------------------------------

func _on_building_placed(b: Building) -> void:
	if not is_fortification(b):
		return
	_register(b)
	fortifications_changed.emit(b.kingdom)


func _on_building_removed(b: Building) -> void:
	if not _forts.has(b.uid):
		return
	_unregister(b)
	fortifications_changed.emit(b.kingdom)


func _on_building_transferred(b: Building, from_kingdom: Kingdom, to_kingdom: Kingdom) -> void:
	if not _forts.has(b.uid):
		return
	_unregister(b)
	_register(b)
	fortifications_changed.emit(from_kingdom)
	fortifications_changed.emit(to_kingdom)


func _on_building_completed(b: Building) -> void:
	if not b.is_segment:
		return
	var entry: Dictionary = _built.get(b.kingdom.id, {"count": 0, "at": 0.0, "pos": b.position})
	entry["count"] = int(entry["count"]) + 1
	entry["at"] = GameClock.game_time
	entry["pos"] = b.position
	_built[b.kingdom.id] = entry


func _register(b: Building) -> void:
	var k := b.kingdom
	_forts[b.uid] = b
	var fp := b.get_footprint()
	for y in range(fp.position.y, fp.end.y):
		for x in range(fp.position.x, fp.end.x):
			nav.mark_barrier(Vector2i(x, y), k.id, true)
	if b.fort_kind == "gate":
		nav.add_gate(b.cell, k.id)
		if bool(b.extra.get("locked", false)):
			nav.set_gate_locked(b.cell, true)
	elif b.fort_kind == "tower" and not _towers.has(b):
		_towers.append(b)
	var key := _index_key(b)
	if not _fort_index.has(key):
		_fort_index[key] = []
	(_fort_index[key] as Array).append(b)
	if not _connected.has(k.id):
		_connected[k.id] = true
		k.modifiers_changed.connect(_rescale_forts.bind(k))
	_redraw_neighbors(b)


func _unregister(b: Building) -> void:
	_forts.erase(b.uid)
	var fp := b.get_footprint()
	for y in range(fp.position.y, fp.end.y):
		for x in range(fp.position.x, fp.end.x):
			nav.mark_barrier(Vector2i(x, y), 0, false)
	if b.fort_kind == "gate":
		nav.remove_gate(b.cell)
	_towers.erase(b)
	var key := _index_key(b)
	if _fort_index.has(key):
		(_fort_index[key] as Array).erase(b)
		if (_fort_index[key] as Array).is_empty():
			_fort_index.erase(key)
	_redraw_neighbors(b)


func _index_key(b: Building) -> Vector2i:
	return Vector2i(floori(float(b.cell.x) / INDEX_CELL), floori(float(b.cell.y) / INDEX_CELL))


## Verbindungen der Nachbarstücke neu zeichnen
func _redraw_neighbors(b: Building) -> void:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n := _building_at(b.cell + d)
		if n != null and n.fort_kind != "":
			n.queue_redraw()


## Modifikatoren des Reichs geändert (z. B. "Steinmauern"): Leben der Befestigungen
## nachführen, der Anteil bleibt
func _rescale_forts(k: Kingdom) -> void:
	for uid in _forts:
		var b: Building = _forts[uid]
		if not is_instance_valid(b) or b.kingdom != k:
			continue
		var new_max := b.compute_max_hp(k)
		if absf(new_max - b.max_hp) < 0.01:
			continue
		var ratio := clampf(b.hp / maxf(b.max_hp, 1.0), 0.0, 1.0)
		b.max_hp = new_max
		b.hp = ratio * new_max
		b.queue_redraw()


# ---------------------------------------------------------------------------
# Takt: Türme, gesammelte Meldungen, Ringe ohne Tor
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	if not _towers.is_empty():
		_tick_towers(dt)
	if not _built.is_empty():
		_flush_built()
	nav.process_dirty()
	if not nav.new_labels.is_empty():
		_check_new_rings()


func _tick_towers(dt: float) -> void:
	var combat: CombatSystem = game.combat_system
	var think_s := float(DataDB.siege("towers.think_seconds", 0.5))
	for tb in _towers.duplicate():
		if not is_instance_valid(tb):
			_towers.erase(tb)
			continue
		var b: Building = tb
		if not b.constructed or b.hp <= 0.0:
			continue
		var cd := maxf(float(b.extra.get("cd", 0.0)) - dt, 0.0)
		var think := float(b.extra.get("think", 0.0)) - dt
		var range_px := b.get_tower_range() * _ts
		var t: Variant = null
		var uid := int(b.extra.get("target_uid", 0))
		if uid != 0:
			t = game.find_by_uid(uid)
		var valid: bool = t is Unit and combat.is_valid_target(b.kingdom, t) \
				and (t as Unit).position.distance_to(b.position) <= range_px + (t as Unit).get_radius()
		if not valid or think <= 0.0:
			think = think_s
			t = _tower_target(b, range_px)
			b.extra["target_uid"] = (t as Unit).uid if t != null else 0
		if cd <= 0.0 and t != null:
			var tw: Dictionary = b.def.get("tower", {})
			cd = float(tw.get("interval", 1.4))
			stats["tower_shots"] = int(stats["tower_shots"]) + 1
			var victim: Unit = t
			var victim_name := victim.get_display_name()
			if combat.tower_attack(b, victim):
				stats["tower_kills"] = int(stats["tower_kills"]) + 1
				b.extra["target_uid"] = 0
				if b.kingdom.is_player and not bool(b.kingdom.flags.get("tower_first_kill", false)):
					b.kingdom.flags["tower_first_kill"] = true
					b.kingdom.notify("Dein Wachturm hat %s erlegt." % victim_name, "info", b.position)
		b.extra["cd"] = cd
		b.extra["think"] = think


## Bestes Ziel eines Turms: feindliche, sichtbare Einheiten in Reichweite;
## Wertung Abstand × priority[Stufe] × priority[Rolle]
func _tower_target(b: Building, range_px: float) -> Unit:
	var combat: CombatSystem = game.combat_system
	var index: SpatialIndex = combat.index
	var prio: Dictionary = (b.def.get("tower", {}) as Dictionary).get("priority", {})
	var pad := 1.5 * _ts
	var best: Unit = null
	var best_score := INF
	for kid in index.kingdom_ids():
		if kid == b.kingdom.id:
			continue
		var other: Kingdom = game.get_kingdom(kid)
		if other == null or not combat.hostile(b.kingdom, other):
			continue
		if not index.any_of_kingdom(b.position, range_px + pad, kid):
			continue
		for v in index.query_kingdom(b.position, range_px + pad, kid):
			if not combat.is_valid_target(b.kingdom, v):
				continue
			var d: float = b.position.distance_to(v.position)
			if d > range_px + v.get_radius():
				continue
			var score: float = d * float(prio.get(v.tier, 1.0)) * float(prio.get(v.role, 1.0))
			if score < best_score:
				best_score = score
				best = v
	return best


## Fertige Mauerstücke gesammelt melden ("Mauerbau fertig (12 Stücke)")
func _flush_built() -> void:
	var now := GameClock.game_time
	var delay := float(DataDB.siege("segments.built_notify_delay", 4))
	for kid in _built.keys():
		var entry: Dictionary = _built[kid]
		if now - float(entry["at"]) < delay:
			continue
		_built.erase(kid)
		var k: Kingdom = game.get_kingdom(int(kid))
		if k != null:
			var n := int(entry["count"])
			k.notify("Mauerbau fertig (%d %s)" % [n, "Stück" if n == 1 else "Stücke"], "good", entry["pos"])


## Neue Ringe: nur Mauern eines Reichs als Rand und kein Tor dieses Reichs -> Warnung
func _check_new_rings() -> void:
	var labels := nav.new_labels.duplicate()
	nav.new_labels.clear()
	for l in labels:
		var reg := nav.get_region(int(l))
		if reg.is_empty() or (reg["cells"] as PackedInt32Array).size() < 9:
			continue
		var owners := {}
		var pos := Vector2.ZERO
		for i in (reg["boundary"] as PackedInt32Array):
			var c := nav.index_to_cell(i)
			if nav.barriers.has(c):
				owners[int(nav.barriers[c])] = true
				pos = world.cell_to_world(c)
		if owners.size() != 1:
			continue
		var owner_id := int(owners.keys()[0])
		var has_gate := false
		for g in nav.gates:
			if int(nav.gates[g]) == owner_id and (nav.gate_links.get(g, []) as Array).has(int(l)):
				has_gate = true
				break
		if has_gate:
			continue
		var k: Kingdom = game.get_kingdom(owner_id)
		if k != null and _throttle("ring_no_gate", k, pos, 30.0):
			k.notify("Mauerring ohne Tor: deine Leute kommen nicht hindurch. Setze ein Tor (Baumenü → Verteidigung).",
					"warning", pos)


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"stats": stats.duplicate(true), "notified": notified.duplicate()}


func from_dict(d: Dictionary) -> void:
	var s: Dictionary = d.get("stats", {})
	for key in s:
		stats[key] = s[key]
	notified = (d.get("notified", {}) as Dictionary).duplicate()


## Befestigungen neu anmelden (NavGrid: Tore, Sperren, Mauerkacheln), Ringe neu, Index, Türme
func rebuild_runtime() -> void:
	_forts.clear()
	_towers.clear()
	_fort_index.clear()
	_built.clear()
	nav.barriers.clear()
	nav.gates.clear()
	nav.locked_gates.clear()
	nav.bump_gates()
	for k in game.kingdoms:
		for b in (k as Kingdom).buildings:
			if is_fortification(b):
				_register(b)
	nav.relabel_all()
	nav.new_labels.clear()
