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

var _rng := RandomNumberGenerator.new()
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
		var lair: Building = game.building_system.place_building(lair_def, cell, wild, true)
		if lair == null:
			continue
		# Beute wächst mit der Stärke des Lagers
		var points := 0.0
		for kind in chosen:
			points += float(DataDB.get_unit_type(kind).get("kill_points", 1))
		lair.loot_factor = clampf(points / ref_points, 1.0, 3.0)
		lair.extra = {"kinds": chosen.duplicate(), "size": chosen.size(), "respawn": 0.0, "last_fight": -1000.0}
		lairs[lair] = []
		world.mark_danger(_lair_center_cell(lair), _danger_radius, 1)
		for kind in chosen:
			spawn_monster(lair, kind)


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
		# Verluste ersetzen, aber nur in ruhigen Zeiten
		if monsters.size() < int(data["size"]) and now - float(data["last_fight"]) >= _quiet:
			data["respawn"] = float(data["respawn"]) + dt
			if float(data["respawn"]) >= float(lair.def.get("respawn_seconds", 90.0)):
				data["respawn"] = 0.0
				var kinds: Array = data["kinds"]
				spawn_monster(lair, str(kinds[_rng.randi_range(0, kinds.size() - 1)]))
		# Umherstreifen: nur Monster ohne Ziel in wachen Lagern
		for u in monsters:
			if u.dormant or u.target != null or u.command != "" or u.moving or u.path_pending:
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
