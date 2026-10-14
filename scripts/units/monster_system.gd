## MonsterSystem
##
## Wilde Monster: setzt beim Spielstart die Höhlen aus der Weltgenerierung
## (WorldData.sites, Art "camp"), lässt dort Monster erscheinen und ruhig um
## ihre Höhle streifen. Verluste werden ersetzt, wenn an der Höhle eine Weile
## Ruhe ist. Lager, in deren Nähe niemand ist, ruhen (kosten keine Rechenzeit).
##
## Der Zustand steckt in den Objekten (Building.extra, Unit.home_uid), damit er
## gespeichert werden kann; lairs ist nur ein Zwischenspeicher dafür.
## Wird die Höhle oder eines ihrer Monster angegriffen, verteidigt das ganze
## Lager. Fällt die Höhle, greifen die Überlebenden den Zerstörer an.
## Gekämpft wird im CombatSystem (Monster kehren um, wenn sie sich zu weit
## von ihrer Höhle entfernen).
##
## Ab Phase 8: Streifzüge (ein Teil eines Lagers zieht zu einer nahen Siedlung –
## Spieler, KI oder Dorf –, nachts häufiger), Monsterwellen (EventSystem →
## spawn_wave), wachsende Lager, neue Lager an freien Lagerplätzen, wenn Lager
## zerstört wurden, und heimatlose Monster, die sich einer Höhle anschliessen oder die
## Karte verlassen. Nachts wächst Nachwuchs schneller.
## Zustand (zusätzlich, gespeichert): raids, next_raid_id, raid_target_last,
## raid_outcomes, leaving, initial_lairs, Prüfzeitpunkte, raid_rng_state; dazu im
## Lager-extra "grown", "last_growth", "late_added".
class_name MonsterSystem
extends Node

## Monster streifen alle so viele Spielsekunden umher (zufällig dazwischen)
const WANDER_MIN := 6.0
const WANDER_MAX := 16.0
## Lager wachen auf, wenn fremde Einheiten so nah sind (Kacheln, zur Leine dazu)
const WAKE_EXTRA_TILES := 6.0

var game: Node
var world: WorldData
var unit_system: UnitSystem
## Reich der wilden Monster
var wild: Kingdom
## Höhle -> Array ihrer Monster (aus Unit.home_uid aufgebaut)
var lairs: Dictionary = {}

## Streifzüge und Wellen: {"id", "kind": "raid"|"wave", "lair_uid" (0 = Welle), "target_id",
## "target_pos", "uids", "state": "march"|"fight"|"return", "started", "state_at", "start_power",
## "next_order", "count"}
var raids: Array = []
var next_raid_id := 1
## Reich-id -> Spielzeit des letzten Streifzugs dorthin
var raid_target_last: Dictionary = {}
## Beendete Streifzüge: id -> Ausgang ("killed" = alle Monster tot, "returned", "retreated")
var raid_outcomes: Dictionary = {}
## Monster auf dem Weg aus der Karte: uid -> Zielpunkt am Rand
var leaving: Dictionary = {}
## Anzahl Lager beim Spielstart (neue Lager ersetzen nur zerstörte)
var initial_lairs := 0
var next_growth_check := -1.0
var next_lair_check := -1.0
var next_raid_check := -1.0
var next_adopt := -1.0
var raid_rng_state: int = 0
## Statistik (Laufzeit, Rauchtest): gestartete Streifzüge/Wellen, davon nachts, neue Lager
var raid_stats := {"raids": 0, "waves": 0, "night_raids": 0, "new_lairs": 0, "grown": 0, "adopted": 0}

## uid -> Streifzug-id (Laufzeit, aus raids aufgebaut)
var _raid_member: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _raid_rng := RandomNumberGenerator.new()
var _sec_acc := 0.0
var _camp_radius := 3.0
var _danger_radius := 10
var _quiet := 30.0
var _leash := 12.0
var _ts := 64.0
var _dormant_timer := 0.0


func setup(p_game: Node, p_wild: Kingdom) -> void:
	game = p_game
	world = game.world
	unit_system = game.unit_system
	wild = p_wild
	_ts = float(world.tile_size)
	_camp_radius = float(DataDB.cmb("camp_radius", 3.0))
	_danger_radius = int(DataDB.cmb("camps.danger_radius", 10))
	_quiet = float(DataDB.cmb("camps.respawn_quiet_seconds", 30.0))
	_leash = float(DataDB.cmb("leash_radius", 12.0))
	_rng.seed = hash(world.world_seed + 1337)
	_raid_rng.seed = hash(world.world_seed + 8161)
	raid_rng_state = _raid_rng.state
	GameClock.sim_tick.connect(_on_sim_tick)
	unit_system.unit_removed.connect(_on_unit_removed)
	game.building_system.building_removed.connect(_on_building_removed)
	game.combat_system.attacked.connect(_on_attacked)


## Setzt alle Höhlen der Karte mit ihren ersten Monstern.
func spawn_camps() -> void:
	var lair_def := DataDB.get_building("monster_lair")
	if lair_def.is_empty():
		return
	var size_range: Array = DataDB.cmb("camps.size", [3, 5])
	var by_biome: Dictionary = DataDB.cmb("camps.by_biome", {})
	var max_with: Dictionary = DataDB.cmb("camps.max_size_with", {})
	var ref_points := maxf(float(DataDB.cmb("camps.loot_reference_points", 5)), 1.0)
	for camp in world.get_sites("camp"):
		var cell: Vector2i = camp["cell"]
		if not _footprint_free(cell, lair_def.get("size", Vector2i(2, 2))):
			continue
		var kinds: Array = camp.get("kinds", by_biome.get(str(camp["biome"]), ["wolf"]))
		if kinds.is_empty():
			continue
		var count := int(camp.get("size", _rng.randi_range(int(size_range[0]), int(size_range[size_range.size() - 1]))))
		# Monsterarten vorab auslosen: starke Arten begrenzen die Lagergrösse
		var chosen: Array = []
		for _i in count:
			chosen.append(str(kinds[_rng.randi_range(0, kinds.size() - 1)]))
		for kind in max_with:
			if chosen.has(kind):
				chosen.resize(mini(chosen.size(), int(max_with[kind])))
		_create_lair(lair_def, cell, chosen, ref_points)
	initial_lairs = lairs.size()


## Höhle mit ihren ersten Monstern setzen (Spielstart und neue Lager)
func _create_lair(lair_def: Dictionary, cell: Vector2i, chosen: Array, ref_points: float) -> Building:
	var lair: Building = game.building_system.place_building(lair_def, cell, wild, true)
	if lair == null:
		return null
	# Beute wächst mit der Stärke des Lagers
	var points := 0.0
	for kind in chosen:
		points += float(DataDB.get_unit_type(kind).get("kill_points", 1))
	lair.loot_factor = clampf(points / ref_points, 1.0, 3.0)
	lair.extra = {"kinds": chosen.duplicate(), "size": chosen.size(), "respawn": 0.0, "last_fight": -1000.0,
			"grown": 0, "last_growth": -1.0}
	lairs[lair] = []
	world.mark_danger(_lair_center_cell(lair), _danger_radius, 1)
	for kind in chosen:
		spawn_monster(lair, kind)
	return lair


## Lässt ein Monster an der Höhle erscheinen.
func spawn_monster(lair: Building, type_id: String) -> Unit:
	if not lairs.has(lair):
		return null
	var home := lair.get_approach_point(lair.get_center() + Vector2(0, 1000))
	var u := unit_system.spawn_unit(wild, type_id, _random_spot(lair))
	if u == null:
		return null
	u.home_uid = lair.uid
	u.has_home = true
	u.home_pos = home
	u.command = ""
	u.command_pos = home
	u.timer = _rng.randf_range(WANDER_MIN, WANDER_MAX)
	(lairs[lair] as Array).append(u)
	return u


## Daten für das Auswahlfenster: Monster (Name -> Anzahl), Sekunden bis zum
## nächsten Nachwuchs (-1 = keiner nötig), Beute, empfohlene Anzahl Kämpfer.
func get_lair_info(lair: Building) -> Dictionary:
	if not lairs.has(lair):
		return {}
	var data: Dictionary = lair.extra
	var monsters: Array = lairs[lair]
	var counts := {}
	var strength := 0.0
	for u in monsters:
		var n: String = u.get_display_name()
		counts[n] = int(counts.get(n, 0)) + 1
		strength += u.max_hp * u.attack / maxf(u.attack_interval, 0.1)
	var next := -1.0
	if monsters.size() < int(data["size"]):
		next = maxf(float(lair.def.get("respawn_seconds", 90.0)) - float(data["respawn"]), 0.0)
	# Grobe Empfehlung: Kämpfer mit vergleichbarer Stärke (Lebenspunkte × Schaden pro Sekunde)
	var faction: String = game.player.faction_id if game.player != null else "good"
	var fighter := DataDB.get_unit_for_tier(faction, "fighter")
	var f_strength := float(fighter.get("hp", 120)) * float(fighter.get("attack", 12)) / maxf(float(fighter.get("attack_interval", 1.2)), 0.1)
	var recommended := maxi(1, ceili(sqrt(strength / maxf(f_strength, 1.0)) * 1.6))
	return {"monsters": counts, "next_spawn": next, "loot": lair.get_loot(), "recommended": recommended}


func _on_sim_tick(dt: float) -> void:
	var now := GameClock.game_time
	var respawn_mult := float(DataDB.dn("monsters.respawn_mult", 1.5)) if _is_night() else 1.0
	_sec_acc += dt
	if _sec_acc >= 1.0:
		_sec_acc = 0.0
		_raid_rng.state = raid_rng_state
		_tick_phase8(now)
		raid_rng_state = _raid_rng.state
	_dormant_timer -= dt
	var check_dormant := _dormant_timer <= 0.0
	if check_dormant:
		_dormant_timer = 1.0
	for lair in lairs:
		if not is_instance_valid(lair):
			continue
		var data: Dictionary = lair.extra
		var monsters: Array = lairs[lair]
		# Ruht das Lager? (einmal pro Spielsekunde geprüft)
		if check_dormant:
			_update_dormant(lair, monsters)
		# Verluste ersetzen, aber nur in ruhigen Zeiten (nachts schneller)
		if monsters.size() < int(data["size"]) and now - float(data["last_fight"]) >= _quiet:
			data["respawn"] = float(data["respawn"]) + dt * respawn_mult
			if float(data["respawn"]) >= float(lair.def.get("respawn_seconds", 90.0)):
				data["respawn"] = 0.0
				var kinds: Array = data["kinds"]
				spawn_monster(lair, str(kinds[_rng.randi_range(0, kinds.size() - 1)]))
		# Umherstreifen: nur Monster ohne Ziel in wachen Lagern
		for u in monsters:
			if u.dormant or u.target != null or u.command != "" or u.moving or u.path_pending or _raid_of(u.uid) > 0:
				continue
			u.timer -= dt
			if u.timer <= 0.0:
				u.timer = _rng.randf_range(WANDER_MIN, WANDER_MAX)
				# Nur geradeaus erreichbare Plätze (spart Wegsuche; sonst später erneut)
				var spot := _random_spot(lair)
				if unit_system.can_walk_direct(u.position, spot):
					unit_system.move_direct(u, spot, 99.0)


## Höhle oder Monster angegriffen: das ganze Lager wehrt sich.
func _on_attacked(attacker: Object, victim: Object, _damage: float) -> void:
	if not (attacker is Unit) or not is_instance_valid(attacker) or attacker.kingdom == wild:
		return
	var lair: Variant = null
	if victim is Building and lairs.has(victim):
		lair = victim
	elif victim is Unit and victim.kingdom == wild and victim.home_uid > 0:
		lair = game.find_by_uid(victim.home_uid)
	if lair == null or not lairs.has(lair):
		return
	var data: Dictionary = lair.extra
	data["last_fight"] = GameClock.game_time
	data["respawn"] = 0.0
	for u in lairs[lair]:
		u.dormant = false
		if u.target == null and u.command == "" and u.is_alive():
			u.target = attacker
			u.repath_timer = 0.0


## Höhle zerstört: Gefahrenzone weg, Überlebende greifen den Zerstörer an.
func _on_building_removed(b: Building) -> void:
	if not lairs.has(b):
		return
	var monsters: Array = lairs[b]
	lairs.erase(b)
	world.mark_danger(_lair_center_cell(b), _danger_radius, -1)
	var dest := b.get_center()
	for u in monsters:
		if not is_instance_valid(u) or not u.is_alive():
			continue
		u.has_home = false
		u.home_uid = 0
		u.dormant = false
		if u.target == null:
			game.command_system.order_move([u], dest + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40)), true)


## Zufälliger freier Punkt im Lagerumkreis der Höhle
func _random_spot(lair: Building) -> Vector2:
	var center := lair.get_center()
	for _try in 8:
		var off := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(1.6, _camp_radius + 1.0) * _ts
		var c := world.world_to_cell(center + off)
		if world.in_bounds(c) and not game.nav.is_solid(c):
			return world.cell_to_world(c) + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-16, 16))
	return lair.get_approach_point(center + Vector2(0, 1000))


## Lager ruhen, solange keine fremde Einheit in der Nähe ist: kein Kampf-
## takt, kein Umherstreifen. Sie bleiben in der Umgebungssuche, damit sie
## gefunden werden können; Schaden weckt sie sofort.
func _update_dormant(lair: Building, monsters: Array) -> void:
	var radius := (_leash + WAKE_EXTRA_TILES) * _ts
	var awake: bool = game.combat_system.index.has_other_kingdom(lair.position, radius, wild.id) \
			or GameClock.game_time - float(lair.extra.get("last_fight", -1000.0)) < _quiet
	for u in monsters:
		if u.dormant and u.hp < u.max_hp:
			# Ruhende Monster erholen sich trotzdem (diese Prüfung läuft 1x pro Spielsekunde)
			u.hp = minf(u.hp + u.regen, u.max_hp)
		if awake:
			u.dormant = false
		elif not u.dormant and u.target == null and u.command == "" and u.hp >= u.max_hp:
			u.dormant = true
			if u.moving:
				unit_system.stop(u)


func _lair_center_cell(lair: Building) -> Vector2i:
	return lair.cell + Vector2i(lair.size.x >> 1, lair.size.y >> 1)


func _footprint_free(cell: Vector2i, size: Vector2i) -> bool:
	for y in range(cell.y, cell.y + size.y):
		for x in range(cell.x, cell.x + size.x):
			var c := Vector2i(x, y)
			if not world.in_bounds(c) or world.occupancy.has(c) or world.roads.has(c):
				return false
	return true


func _on_unit_removed(u: Unit) -> void:
	if u.kingdom != wild or u.home_uid <= 0:
		return
	var lair: Variant = game.find_by_uid(u.home_uid)
	if lair != null and lairs.has(lair):
		(lairs[lair] as Array).erase(u)


# ---------------------------------------------------------------------------
# Phase 8: Streifzüge, Wellen, Lagerwachstum, neue Lager, Heimatlose
# ---------------------------------------------------------------------------

## Monsterwelle (EventSystem): count Monster der Arten kinds bei origin, Ziel target.
## Gibt die Streifzug-id zurück (0 = nicht möglich).
func spawn_wave(target: Kingdom, origin: Vector2, kinds: Array, count: int) -> int:
	if target == null or kinds.is_empty() or count <= 0:
		return 0
	var target_pos := _settlement_point(target, origin)
	if target_pos.x < 0.0:
		return 0
	var units: Array = []
	for i in count:
		var kind := str(kinds[i % kinds.size()])
		var off := Vector2.from_angle(_raid_rng.randf() * TAU) * _raid_rng.randf_range(0.0, 2.5) * _ts
		var c: Vector2i = game.nav.nearest_free(world.world_to_cell(origin + off), 5)
		if c.x < 0:
			continue
		var u := unit_system.spawn_unit(wild, kind, world.cell_to_world(c))
		if u == null:
			continue
		u.has_home = false
		u.home_uid = 0
		units.append(u)
	if units.is_empty():
		return 0
	raid_stats["waves"] = int(raid_stats["waves"]) + 1
	return _start_group(units, "wave", 0, target, target_pos)


## Streifzug einer Höhle zu einer Siedlung (Würfel oder Debug). Gibt die id zurück (0 = nicht möglich).
func start_raid(lair: Building, target: Kingdom) -> int:
	if lair == null or not lairs.has(lair) or target == null or _lair_in_raid(lair.uid):
		return 0
	var free_units: Array = []
	for u in lairs[lair]:
		if is_instance_valid(u) and u.is_alive() and u.target == null and _raid_of(u.uid) == 0:
			free_units.append(u)
	if free_units.is_empty():
		return 0
	var n := clampi(ceili(free_units.size() * float(DataDB.cmb("raids.share", 0.5))),
			mini(int(DataDB.cmb("raids.min_size", 2)), free_units.size()), free_units.size())
	var units: Array = free_units.slice(0, n)
	var target_pos := _settlement_point(target, lair.get_center())
	if target_pos.x < 0.0:
		return 0
	raid_target_last[target.id] = GameClock.game_time
	raid_stats["raids"] = int(raid_stats["raids"]) + 1
	if _is_night():
		raid_stats["night_raids"] = int(raid_stats["night_raids"]) + 1
	return _start_group(units, "raid", lair.uid, target, target_pos)


## Laufender Streifzug ({} wenn beendet)
func get_raid(id: int) -> Dictionary:
	for r in raids:
		if int(r["id"]) == id:
			return r
	return {}


func get_raids() -> Array:
	return raids


## Ausgang eines beendeten Streifzugs ("" = läuft noch oder unbekannt)
func get_raid_outcome(id: int) -> String:
	return str(raid_outcomes.get(id, ""))


## Für Minikarte und Ereignisleiste: [{"pos": Schwerpunkt, "target_pos", "kind", "count", "target_id"}]
func get_raid_markers() -> Array:
	var list: Array = []
	for r in raids:
		var sum := Vector2.ZERO
		var n := 0
		for uid in r["uids"]:
			var u: Variant = game.find_by_uid(int(uid))
			if u is Unit and (u as Unit).is_alive():
				sum += (u as Unit).position
				n += 1
		if n > 0:
			list.append({"pos": sum / n, "target_pos": r["target_pos"], "kind": r["kind"], "count": n,
					"target_id": int(r["target_id"])})
	return list


## Debug: Streifzug der nächsten Höhle mit mindestens 2 Monstern auf target (ohne Sperren)
func debug_start_raid(target: Kingdom) -> bool:
	var center := _settlement_point(target, Vector2.ZERO)
	if center.x < 0.0:
		return false
	var best: Building = null
	var best_d := INF
	for lair in lairs:
		if not is_instance_valid(lair) or _lair_in_raid(lair.uid) or _alive_count(lair) < 2:
			continue
		var d: float = lair.get_center().distance_to(center)
		if d < best_d:
			best_d = d
			best = lair
	if best == null:
		return false
	_raid_rng.state = raid_rng_state
	var id := start_raid(best, target)
	raid_rng_state = _raid_rng.state
	return id > 0


func _start_group(units: Array, kind: String, lair_uid: int, target: Kingdom, target_pos: Vector2) -> int:
	var now := GameClock.game_time
	var id := next_raid_id
	next_raid_id += 1
	var uids: Array = []
	var power := 0.0
	for u in units:
		u.dormant = false
		uids.append(u.uid)
		_raid_member[u.uid] = id
		power += VillageSystem.unit_power(u)
	raids.append({"id": id, "kind": kind, "lair_uid": lair_uid, "target_id": target.id, "target_pos": target_pos,
			"uids": uids, "state": "march", "started": now, "state_at": now, "start_power": power,
			"next_order": now + 10.0, "count": uids.size()})
	game.command_system.order_move(units, target_pos, true)
	return id


func _tick_phase8(now: float) -> void:
	for r in raids.duplicate():
		_tick_raid(r, now)
	_tick_leaving()
	var raid_interval := float(DataDB.cmb("raids.check_seconds", 120))
	if next_raid_check < 0.0:
		next_raid_check = now + raid_interval
	elif now >= next_raid_check:
		next_raid_check = now + raid_interval
		if now >= float(DataDB.cmb("raids.min_minutes", 25)) * 60.0:
			_roll_raids(now)
	if next_growth_check < 0.0:
		next_growth_check = now + 60.0
	elif now >= next_growth_check:
		next_growth_check = now + 60.0
		_grow_lairs(now)
	var lair_interval := float(DataDB.cmb("new_lairs.interval", 2400))
	if next_lair_check < 0.0:
		next_lair_check = now + lair_interval
	elif now >= next_lair_check:
		next_lair_check = now + lair_interval
		if now >= float(DataDB.cmb("new_lairs.min_minutes", 60)) * 60.0 and lairs.size() < initial_lairs:
			_spawn_new_lair()
	var adopt_interval := float(DataDB.cmb("homeless.adopt_seconds", 30))
	if next_adopt < 0.0:
		next_adopt = now + adopt_interval
	elif now >= next_adopt:
		next_adopt = now + adopt_interval
		for u in wild.units.duplicate():
			if u.is_alive() and not u.has_home and u.target == null and _raid_of(u.uid) == 0 and not leaving.has(u.uid):
				_adopt(u)


func _tick_raid(r: Dictionary, now: float) -> void:
	var units: Array = []
	for uid in (r["uids"] as Array).duplicate():
		var u: Variant = game.find_by_uid(int(uid))
		if u is Unit and (u as Unit).is_alive() and (u as Unit).kingdom == wild:
			units.append(u)
		else:
			(r["uids"] as Array).erase(uid)
			_raid_member.erase(int(uid))
	if units.is_empty():
		_end_raid(r, "killed" if str(r["state"]) != "return" else "returned")
		return
	var target: Kingdom = game.get_kingdom(int(r["target_id"]))
	var target_pos: Vector2 = r["target_pos"]
	var max_seconds := float(DataDB.cmb("raids.max_seconds", 360))
	match str(r["state"]):
		"march":
			var near := 0
			for u in units:
				if u.position.distance_to(target_pos) <= float(DataDB.cmb("raids.arrive_tiles", 12)) * _ts:
					near += 1
			if target == null or target.defeated or now - float(r["started"]) > max_seconds * 1.5:
				_set_return(r, units, now)
			elif near * 2 >= units.size():
				r["state"] = "fight"
				r["state_at"] = now
				r["next_order"] = now + 10.0
				_order_fight(units, target, target_pos)
		"fight":
			var power := 0.0
			for u in units:
				power += VillageSystem.unit_power(u)
			var b: Building = null
			if target != null and not target.defeated:
				b = _nearest_building(target, target_pos, 15.0 * _ts)
			if b == null or power < float(DataDB.cmb("raids.retreat_ratio", 0.4)) * float(r["start_power"]) \
					or now - float(r["started"]) > max_seconds:
				_set_return(r, units, now)
			elif now >= float(r["next_order"]):
				r["next_order"] = now + 10.0
				var idle: Array = []
				for u in units:
					if u.target == null and (u.command == "hold" or u.command == ""):
						idle.append(u)
				if not idle.is_empty():
					game.command_system.order_attack(idle, b)
		"return":
			var lair: Variant = game.find_by_uid(int(r["lair_uid"])) if int(r["lair_uid"]) > 0 else null
			var timeout := now - float(r["state_at"]) >= float(DataDB.cmb("raids.return_seconds", 150))
			for u in units:
				if lair != null and lairs.has(lair) and u.has_home:
					if timeout or u.position.distance_to(u.home_pos) <= (_camp_radius + 1.0) * _ts:
						u.command = ""
						u.target = null
						(r["uids"] as Array).erase(u.uid)
						_raid_member.erase(u.uid)
				else:
					(r["uids"] as Array).erase(u.uid)
					_raid_member.erase(u.uid)
					u.has_home = false
					u.home_uid = 0
					_adopt(u)
			if (r["uids"] as Array).is_empty():
				_end_raid(r, "returned" if str(r["kind"]) == "raid" else "retreated")


## Am Ziel: Burg bzw. Halle (sonst nächstes Gebäude) angreifen
func _order_fight(units: Array, target: Kingdom, target_pos: Vector2) -> void:
	var b: Building = null
	if target != null:
		b = _nearest_building(target, target_pos, 15.0 * _ts)
	if b != null:
		game.command_system.order_attack(units, b)
	else:
		game.command_system.order_move(units, target_pos, true)


func _set_return(r: Dictionary, units: Array, now: float) -> void:
	r["state"] = "return"
	r["state_at"] = now
	var lair: Variant = game.find_by_uid(int(r["lair_uid"])) if int(r["lair_uid"]) > 0 else null
	if lair != null and lairs.has(lair):
		var home: Array = []
		for u in units:
			if u.has_home:
				home.append(u)
		if not home.is_empty():
			var b: Building = lair
			game.command_system.order_move(home, b.get_approach_point(b.get_center() + Vector2(0, 1000)))


func _end_raid(r: Dictionary, outcome: String) -> void:
	for uid in r["uids"]:
		_raid_member.erase(int(uid))
	raids.erase(r)
	raid_outcomes[int(r["id"])] = outcome
	while raid_outcomes.size() > 40:
		raid_outcomes.erase(raid_outcomes.keys()[0])


## Würfel je Höhle: Streifzug zur nächsten Siedlung (nachts häufiger)
func _roll_raids(now: float) -> void:
	var chance := float(DataDB.cmb("raids.chance", 0.02))
	if _is_night():
		chance *= float(DataDB.dn("monsters.raid_chance_mult", 2.5))
	var range_px := float(DataDB.cmb("raids.range_tiles", 45)) * _ts
	var gap := float(DataDB.cmb("raids.target_gap", 900))
	for key in lairs.keys():
		if not is_instance_valid(key):
			continue
		var lair: Building = key
		if _lair_in_raid(lair.uid):
			continue
		var idle := 0
		for u in lairs[lair]:
			if is_instance_valid(u) and u.is_alive() and u.target == null and u.hp >= u.max_hp * 0.8:
				idle += 1
		if idle < int(DataDB.cmb("raids.min_size", 2)):
			continue
		var target := _nearest_settlement(lair.get_center(), range_px)
		if target == null or now - float(raid_target_last.get(target.id, -1.0e9)) < gap:
			continue
		if _raid_rng.randf() >= chance:
			continue
		if start_raid(lair, target) > 0:
			target.notify("Monster aus einer Höhle streifen auf dein Gebiet zu!", "warning", lair.get_center())


## Ruhige Höhlen wachsen; später kommen stärkere Arten dazu
func _grow_lairs(now: float) -> void:
	var interval := float(DataDB.cmb("lair_growth.interval", 1200))
	var quiet := float(DataDB.cmb("lair_growth.quiet_seconds", 300))
	var extra_max := int(DataDB.cmb("lair_growth.extra_max", 2))
	var late_minute := float(DataDB.cmb("lair_growth.late_kinds_minute", 120))
	var late_kinds: Array = DataDB.cmb("lair_growth.late_kinds", [])
	for key in lairs.keys():
		if not is_instance_valid(key):
			continue
		var lair: Building = key
		var data: Dictionary = lair.extra
		if float(data.get("last_growth", -1.0)) < 0.0:
			data["last_growth"] = now
			continue
		if now - float(data["last_fight"]) < quiet or now - float(data["last_growth"]) < interval:
			continue
		data["last_growth"] = now
		var base_size := int(data["size"]) - int(data.get("grown", 0))
		var cap := maxi(int(lair.def.get("max_monsters", 5)), base_size) + extra_max
		if int(data["size"]) < cap:
			data["size"] = int(data["size"]) + 1
			data["grown"] = int(data.get("grown", 0)) + 1
			raid_stats["grown"] = int(raid_stats["grown"]) + 1
		if now >= late_minute * 60.0 and not bool(data.get("late_added", false)) and not late_kinds.is_empty():
			data["late_added"] = true
			(data["kinds"] as Array).append(str(late_kinds[_raid_rng.randi_range(0, late_kinds.size() - 1)]))


## Neues Lager an einem freien Lagerplatz fern von Siedlungen
func _spawn_new_lair() -> void:
	var lair_def := DataDB.get_building("monster_lair")
	if lair_def.is_empty():
		return
	var sites: Array = world.get_sites("camp").duplicate()
	var min_d := float(DataDB.cmb("new_lairs.min_distance_settlement", 35)) * _ts
	var by_biome: Dictionary = DataDB.cmb("camps.by_biome", {})
	var size_range: Array = DataDB.cmb("camps.size", [3, 5])
	for i in sites.size():
		var j := _raid_rng.randi_range(i, sites.size() - 1)
		var tmp: Variant = sites[i]
		sites[i] = sites[j]
		sites[j] = tmp
	for site in sites:
		var camp: Dictionary = site
		var cell: Vector2i = camp["cell"]
		var center := world.cell_to_world(cell)
		if not _footprint_free(cell, lair_def.get("size", Vector2i(2, 2))) or world.get_owner(cell) != 0:
			continue
		if _nearest_settlement(center, min_d) != null:
			continue
		var kinds: Array = camp.get("kinds", by_biome.get(str(camp["biome"]), ["wolf"]))
		if kinds.is_empty():
			continue
		var chosen: Array = []
		for _i in _raid_rng.randi_range(int(size_range[0]), int(size_range[size_range.size() - 1])):
			chosen.append(str(kinds[_raid_rng.randi_range(0, kinds.size() - 1)]))
		var lair := _create_lair(lair_def, cell, chosen, maxf(float(DataDB.cmb("camps.loot_reference_points", 5)), 1.0))
		if lair == null:
			continue
		raid_stats["new_lairs"] = int(raid_stats["new_lairs"]) + 1
		var player: Kingdom = game.player
		if player != null and is_instance_valid(player.castle) \
				and player.castle.get_center().distance_to(center) <= float(DataDB.cmb("new_lairs.notify_radius", 60)) * _ts:
			player.notify("Ein neues Monsterlager wurde gesichtet.", "info", lair.get_center())
		return


## Heimatloses Monster: nächste Höhle in adopt_radius, sonst zum Kartenrand und dort verschwinden
func _adopt(u: Unit) -> void:
	var best: Building = null
	var best_d := float(DataDB.cmb("homeless.adopt_radius", 40)) * _ts
	for key in lairs:
		if not is_instance_valid(key):
			continue
		var lair: Building = key
		var d := lair.get_center().distance_to(u.position)
		if d <= best_d:
			best_d = d
			best = lair
	if best != null:
		u.home_uid = best.uid
		u.has_home = true
		u.home_pos = best.get_approach_point(best.get_center() + Vector2(0, 1000))
		if not (lairs[best] as Array).has(u):
			(lairs[best] as Array).append(u)
		u.target = null
		u.command = "return"
		u.command_pos = u.home_pos
		unit_system.move_to(u, u.home_pos)
		raid_stats["adopted"] = int(raid_stats["adopted"]) + 1
		return
	var edge := _edge_point(u.position)
	if edge.x < 0.0:
		unit_system.remove_unit(u)
		return
	leaving[u.uid] = edge
	game.command_system.order_move([u], edge)


## Monster am Kartenrand angekommen: entfernen
func _tick_leaving() -> void:
	for uid in leaving.keys():
		var u: Variant = game.find_by_uid(int(uid))
		if not (u is Unit) or not (u as Unit).is_alive():
			leaving.erase(uid)
			continue
		var unit: Unit = u
		var dest: Vector2 = leaving[uid]
		if unit.position.distance_to(dest) <= 2.0 * _ts or (not unit.moving and not unit.path_pending and unit.target == null):
			leaving.erase(uid)
			unit_system.remove_unit(unit)


## Nächste Siedlung (Burg eines Reichs mit Wirtschaft oder Halle eines Dorfs) in max_px
func _nearest_settlement(pos: Vector2, max_px: float) -> Kingdom:
	var best: Kingdom = null
	var best_d := max_px
	for e in game.kingdoms:
		var k: Kingdom = e
		if k.defeated or k == wild:
			continue
		var c := Vector2(-1, -1)
		if k.has_economy and is_instance_valid(k.castle):
			c = k.castle.get_center()
		elif game.village_system.is_village(k):
			var hall: Building = game.village_system.get_hall(k)
			if hall != null:
				c = hall.get_center()
		if c.x < 0.0:
			continue
		var d := pos.distance_to(c)
		if d <= best_d:
			best_d = d
			best = k
	return best


## Anfahrpunkt der Siedlung (Burg bzw. Dorfhalle), (-1, -1) wenn keine
func _settlement_point(k: Kingdom, from: Vector2) -> Vector2:
	if k == null:
		return Vector2(-1, -1)
	if is_instance_valid(k.castle):
		return k.castle.get_approach_point(from)
	var hall: Building = game.village_system.get_hall(k)
	if hall != null:
		return hall.get_approach_point(from)
	return Vector2(-1, -1)


## Gebäude des Reichs in max_px um pos: Burg bzw. Halle bevorzugt, sonst das nächste
func _nearest_building(k: Kingdom, pos: Vector2, max_px: float) -> Building:
	if k == null:
		return null
	if is_instance_valid(k.castle) and k.castle.get_center().distance_to(pos) <= max_px:
		return k.castle
	var hall: Building = game.village_system.get_hall(k)
	if hall != null and hall.get_center().distance_to(pos) <= max_px:
		return hall
	var best: Building = null
	var best_d := max_px
	for e in k.buildings:
		if not is_instance_valid(e):
			continue
		var b: Building = e
		if bool(b.def.get("is_road", false)):
			continue
		var d := b.get_center().distance_to(pos)
		if d <= best_d:
			best_d = d
			best = b
	return best


func _edge_point(pos: Vector2) -> Vector2:
	var c := world.world_to_cell(pos)
	var options := [[c.x, Vector2i(2, c.y)], [world.width - 1 - c.x, Vector2i(world.width - 3, c.y)],
			[c.y, Vector2i(c.x, 2)], [world.height - 1 - c.y, Vector2i(c.x, world.height - 3)]]
	options.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	for o in options:
		var free: Vector2i = game.nav.nearest_free(o[1], 8)
		if free.x >= 0:
			return world.cell_to_world(free)
	return Vector2(-1, -1)


func _raid_of(uid: int) -> int:
	return int(_raid_member.get(uid, 0))


func _lair_in_raid(lair_uid: int) -> bool:
	for r in raids:
		if int(r["lair_uid"]) == lair_uid:
			return true
	return false


func _alive_count(lair: Building) -> int:
	var n := 0
	for u in lairs.get(lair, []):
		if is_instance_valid(u) and u.is_alive():
			n += 1
	return n


func _is_night() -> bool:
	var dns: Variant = game.get("day_night_system")
	return dns != null and bool(dns.is_night())


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"raids": raids.duplicate(true), "next_raid_id": next_raid_id, "raid_target_last": raid_target_last.duplicate(),
			"raid_outcomes": raid_outcomes.duplicate(), "leaving": leaving.duplicate(), "initial_lairs": initial_lairs,
			"next_growth_check": next_growth_check, "next_lair_check": next_lair_check, "next_raid_check": next_raid_check,
			"next_adopt": next_adopt, "raid_rng_state": raid_rng_state}


func from_dict(d: Dictionary) -> void:
	raids = (d.get("raids", []) as Array).duplicate(true)
	next_raid_id = int(d.get("next_raid_id", 1))
	raid_target_last = (d.get("raid_target_last", {}) as Dictionary).duplicate()
	raid_outcomes = (d.get("raid_outcomes", {}) as Dictionary).duplicate()
	leaving = (d.get("leaving", {}) as Dictionary).duplicate()
	initial_lairs = int(d.get("initial_lairs", 0))
	next_growth_check = float(d.get("next_growth_check", -1.0))
	next_lair_check = float(d.get("next_lair_check", -1.0))
	next_raid_check = float(d.get("next_raid_check", -1.0))
	next_adopt = float(d.get("next_adopt", -1.0))
	raid_rng_state = int(d.get("raid_rng_state", raid_rng_state))


## Höhlen aus den Gebäuden des Monster-Reichs, Monster über home_uid, Gefahr-Raster neu
func rebuild_runtime() -> void:
	lairs.clear()
	world.danger.fill(0)
	for e in wild.buildings:
		if is_instance_valid(e) and str((e as Building).def.get("id", "")) == "monster_lair":
			lairs[e] = []
			world.mark_danger(_lair_center_cell(e), _danger_radius, 1)
	for u in wild.units:
		if u.home_uid <= 0:
			continue
		var lair: Variant = game.find_by_uid(u.home_uid)
		if lair != null and lairs.has(lair):
			(lairs[lair] as Array).append(u)
		else:
			u.has_home = false
			u.home_uid = 0
	_raid_member.clear()
	for r in raids:
		for uid in r["uids"]:
			_raid_member[int(uid)] = int(r["id"])
	_raid_rng.state = raid_rng_state
	_sec_acc = 0.0
