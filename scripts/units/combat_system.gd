## CombatSystem
##
## Automatischer Nah- und Fernkampf, Heilung, Erholung, Tod und Zerstörung.
## Läuft im Simulationstakt (10x pro Spielsekunde) für alle Reiche gleich.
##
## Was eine Einheit im Kampf tut, hängt von ihrem Befehl ab – die Bedeutung
## jedes Befehls steht in CommandSystem.COMMANDS (engage, retaliate, leash).
## Einheiten mit Befehl "" werden hier nur bewegt, wenn sie nicht arbeiten
## können (Monster, König): arbeitende Einheiten steuert allein das WorkSystem.
## Werden sie angegriffen, fliehen sie (flee_on_hit) oder wehren sich mit dem
## Befehl "defend" und arbeiten danach weiter.
##
## Schaden von aussen (ab Phase 4/9: Zauber, Türme, Ereignisse) läuft über
## apply_damage().
class_name CombatSystem
extends Node

signal unit_died(unit: Unit, killer_kingdom: Kingdom)
signal building_destroyed(building: Building, killer_kingdom: Kingdom)
## Ein Treffer (für Effekte): attacker ist Unit, Building oder null; victim Unit oder Building
signal attacked(attacker: Object, victim: Object, damage: float)
## Ein Geschoss wurde abgefeuert (nur Darstellung, der Schaden ist schon verrechnet)
signal projectile_fired(from_pos: Vector2, to_pos: Vector2, kind: String, flight_time: float)
signal king_died(kingdom: Kingdom)
## Ein Reich wurde von einem anderen angegriffen (höchstens alle 5 s je Paar)
signal kingdom_attacked(victim: Kingdom, attacker: Kingdom, pos: Vector2)

## Geschwindigkeit sichtbarer Geschosse in Kacheln pro Sekunde
const PROJECTILE_SPEED := 14.0
## Wie weit "hold"/"defend"-Einheiten über ihre Sichtweite hinaus verfolgen (Kacheln)
const GUARD_EXTRA := 3.0
## Bis zu dieser Entfernung (Kacheln) wird beim Verfolgen geradeaus gelaufen
const DIRECT_CHASE_TILES := 8.0
## Suchradien etwas grösser, weil die Umgebungssuche bis zu 0.2 s alt ist
const QUERY_PAD_TILES := 1.5
## Warnung "wird angegriffen": höchstens einmal je Gebiet (Kacheln) und Zeit (Spielsekunden)
const ATTACK_WARN_AREA := 20
const ATTACK_WARN_INTERVAL := 15.0
const KING_WARN_INTERVAL := 10.0
const KINGDOM_ATTACK_INTERVAL := 5.0
## Todesmeldungen werden so lange gesammelt ("2× Schwertkämpfer gefallen")
const DEATH_REPORT_DELAY := 3.0

var game: Node
var world: WorldData
var unit_system: UnitSystem
var work_system: WorkSystem
## Umgebungssuche, regelmässig neu aufgebaut
var index := SpatialIndex.new(256.0)

var _ts := 64.0
var _territory_bonus := 0.15
var _variance := 0.15
var _min_damage := 1.0
var _armor_cap := 0.8
var _regen_delay := 5.0
var _retarget := 0.8
var _chase_repath := 0.7
var _leash := 12.0
var _camp_radius := 3.0
var _worker_flee := true
var _king_flee_ratio := 0.35
var _rng := RandomNumberGenerator.new()
var _tick_count := 0
## In diesem Takt gestorbene Einheiten / zerstörte Gebäude: [Opfer, Sieger-Reich]
var _dead_units: Array = []
var _dead_buildings: Array = []
## Umgebungssuche im nächsten Takt neu aufbauen (Einheit entfernt)
var _index_dirty := true
## Gesammelte Todesfälle des Spielers: Name -> {"count", "pos"}
var _death_log: Dictionary = {}
var _death_flush_at := -1.0
## "Opfer-id:Angreifer-id" -> Spielzeit der letzten Meldung kingdom_attacked
var _attack_events: Dictionary = {}


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	unit_system = game.unit_system
	work_system = game.work_system
	_ts = float(world.tile_size)
	_territory_bonus = float(DataDB.cmb("territory_bonus", 0.15))
	_variance = float(DataDB.cmb("damage_variance", 0.15))
	_min_damage = float(DataDB.cmb("min_damage", 1.0))
	_armor_cap = float(DataDB.cmb("armor_cap", 0.8))
	_regen_delay = float(DataDB.cmb("regen_delay", 5.0))
	_retarget = maxf(float(DataDB.cmb("retarget_seconds", 0.8)), 0.1)
	_chase_repath = maxf(float(DataDB.cmb("chase_repath_seconds", 0.7)), 0.1)
	_leash = float(DataDB.cmb("leash_radius", 12.0))
	_camp_radius = float(DataDB.cmb("camp_radius", 3.0))
	_worker_flee = bool(DataDB.cmb("worker_flee", true))
	_king_flee_ratio = float(DataDB.cmb("king_flee_ratio", 0.35))
	_rng.seed = hash(world.world_seed + 4711)
	GameClock.sim_tick.connect(_on_sim_tick)
	unit_system.path_failed.connect(_on_path_failed)
	unit_system.unit_removed.connect(func(_u: Unit) -> void: _index_dirty = true)
	unit_system.unit_spawned.connect(func(u: Unit) -> void:
		# Zielsuche verteilen, damit nicht alle im selben Takt suchen
		u.think_timer = _rng.randf_range(0.0, _retarget))


# ---------------------------------------------------------------------------
# Öffentliche Hilfen
# ---------------------------------------------------------------------------

## Ist t ein gültiges Angriffsziel für Einheiten des Reichs k?
## Reihenfolge wichtig: erst gültig, dann lebendig, dann Typ.
func is_valid_target(k: Kingdom, t: Variant) -> bool:
	if t == null or not is_instance_valid(t) or not t.is_alive():
		return false
	if not game.are_hostile(k, t.kingdom) or not game.can_see(k, t):
		return false
	if t is Unit:
		return t.inside == null
	return t is Building


## Kann u das Ziel t von hier aus treffen?
func is_in_reach(u: Unit, t: Object) -> bool:
	var reach := u.attack_range * _ts + u.get_radius() * 0.5
	if t is Building:
		var rect := Rect2(Vector2(t.cell) * _ts, Vector2(t.size) * _ts)
		var closest := Vector2(clampf(u.position.x, rect.position.x, rect.end.x), clampf(u.position.y, rect.position.y, rect.end.y))
		return u.position.distance_to(closest) <= reach + 8.0
	return u.position.distance_to(t.position) <= reach + t.get_radius()


## Erwarteter Schaden eines Treffers von u gegen victim (ohne Zufall, für Anzeigen)
func estimate_damage(u: Unit, victim: Object) -> float:
	return _damage_value(u, victim, 1.0)


## Aktive Boni einer Einheit als Text (für das Auswahlfenster)
func get_bonus_text(u: Unit) -> String:
	var parts: PackedStringArray = []
	var cell := world.world_to_cell(u.position)
	if world.get_owner(cell) == u.kingdom.id:
		parts.append("Eigenes Gebiet +%d %%" % roundi(_territory_bonus * 100.0))
	var biome := world.get_biome(cell)
	var def_bonus := float(biome.get("defense_bonus", 0.0))
	if def_bonus != 0.0:
		parts.append("%s %+d %% Abwehr" % [biome.get("name", "?"), roundi(def_bonus * 100.0)])
	return "  ·  ".join(parts)


## Fügt victim (Unit oder Building) Schaden zu – der einzige Weg dafür.
## source: Angreifer (Unit/Building) oder null (Zauber, Ereignis);
## source_kingdom: wer den Sieg bekommt (darf null sein).
## kind: "melee", "ranged", "spell", "event" … (für spätere Effekte und
## Resistenzen; noch ohne Wirkung). Gibt den Schaden zurück.
func apply_damage(victim: Object, amount: float, source: Object = null, source_kingdom: Kingdom = null,
		_kind: String = "melee") -> float:
	if not is_instance_valid(victim) or not victim.is_alive() or amount <= 0.0:
		return 0.0
	attacked.emit(source, victim, amount)
	if source_kingdom != null:
		_note_attack(victim.kingdom, source_kingdom, victim.position)
	if victim is Unit:
		_damage_unit(victim, amount, source, source_kingdom)
	else:
		_damage_building(victim, amount, source, source_kingdom)
	return amount


# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	_tick_count += 1
	var now := GameClock.game_time
	# Die Umgebungssuche reicht alle zwei Takte (Einheiten bewegen sich in
	# 0.2 s kaum); nach einem Todesfall sofort, damit keine Toten drinbleiben.
	if _index_dirty or _tick_count % 2 == 0:
		index.rebuild(unit_system.units)
		_index_dirty = false
	_tick_heal_auras(dt)
	for u in unit_system.units:
		# Felder direkt lesen statt Hilfsfunktionen: diese Schleife läuft für
		# alle Einheiten in jedem Takt
		if u.dormant or u.inside != null or u.hp <= 0.0:
			continue
		if u.hp < u.max_hp:
			_tick_regen(u, dt, now)
		if u.heal > 0.0:
			_tick_healer(u, dt)
			continue
		if u.attack <= 0.0 or not u.joins_fights:
			continue
		u.attack_cooldown -= dt
		u.think_timer -= dt
		u.repath_timer -= dt
		if not CommandSystem.flag(u.command, "engage"):
			continue
		if u.target != null and not is_valid_target(u.kingdom, u.target):
			_after_fight(u)
		if u.target == null:
			if u.think_timer <= 0.0:
				u.think_timer = _retarget
				if _may_auto_acquire(u):
					u.target = _find_target(u)
					if u.target != null:
						u.repath_timer = 0.0
			if u.target == null:
				continue
		_engage(u)
	if _tick_count % 2 == 0:
		_separate()
	_process_deaths()
	if _death_flush_at >= 0.0 and now >= _death_flush_at:
		_flush_death_reports()


## Darf u von selbst Feinde suchen?
func _may_auto_acquire(u: Unit) -> bool:
	if u.aggro_range <= 0.0 or not u.joins_fights:
		return false
	if u.command.is_empty():
		# Arbeitende Einheiten suchen keinen Streit, Monster und Wachen schon
		return not u.can_work()
	return bool(CommandSystem.flag(u.command, "engage"))


## Nächster sichtbarer Feind in Sichtweite. Arbeiter zählen weiter weg
## (target_priority), damit Kämpfer zuerst Kämpfer angreifen. Mit
## Befehlen, die Gebäude erlauben, auch feindliche Gebäude.
func _find_target(u: Unit) -> Object:
	var aggro := u.aggro_range * _ts
	var radius := aggro + QUERY_PAD_TILES * _ts
	var best: Object = null
	var best_score := INF
	var buildings := bool(CommandSystem.flag(u.command, "buildings"))
	if not buildings and not index.has_other_kingdom(u.position, radius, u.kingdom.id):
		return null
	for v in index.query(u.position, radius):
		if v.kingdom == u.kingdom or v.hp <= 0.0 or v.inside != null or not game.are_hostile(u.kingdom, v.kingdom):
			continue
		if u.has_home and v.position.distance_to(u.home_pos) > _leash * _ts:
			continue
		var d: float = u.position.distance_to(v.position)
		if d > aggro + v.get_radius() or not game.can_see(u.kingdom, v):
			continue
		var score: float = d * v.target_priority
		if score < best_score:
			best_score = score
			best = v
	if best == null and buildings:
		for k in game.kingdoms:
			if k == u.kingdom or not game.are_hostile(u.kingdom, k):
				continue
			for b in k.buildings:
				var d: float = u.position.distance_to(b.position) - b.get_radius()
				if d <= aggro and d < best_score:
					best_score = d
					best = b
	return best


## Angreifen, wenn in Reichweite, sonst verfolgen (oder aufgeben).
func _engage(u: Unit) -> void:
	var t: Object = u.target
	if is_in_reach(u, t):
		if u.moving or u.path_pending:
			unit_system.stop(u)
		if u.attack_cooldown <= 0.0:
			u.attack_cooldown = u.attack_interval
			_attack(u, t)
		return
	# Aufgeben? Je nach Befehl: Monster an der Leine, Wachen nicht zu weit vom
	# Posten, selbst gesuchte Ziele, die davonlaufen.
	var t_pos: Vector2 = t.position
	var aggro_px := maxf(u.aggro_range, u.attack_range) * _ts
	match str(CommandSystem.flag(u.command, "leash")):
		"home":
			if u.has_home and u.position.distance_to(u.home_pos) > _leash * _ts:
				_after_fight(u)
				return
		"guard":
			if u.position.distance_to(u.command_pos) > aggro_px + GUARD_EXTRA * _ts:
				_after_fight(u)
				return
	if u.command != "attack" and u.position.distance_to(t_pos) > maxf(aggro_px, 4.0 * _ts) * 2.0:
		_after_fight(u)
		return
	# Verfolgen: neu planen, wenn der Weg fehlt oder das Ziel weitergezogen ist.
	# Der alte Weg wird bis zum neuen weitergelaufen (kein Stehenbleiben).
	var has_path := u.moving or u.path_pending
	if u.repath_timer <= 0.0 and (not has_path or t_pos.distance_to(u.last_target_pos) > _ts):
		u.repath_timer = _chase_repath
		u.last_target_pos = t_pos
		var point := _chase_point(u, t)
		if u.position.distance_to(point) <= DIRECT_CHASE_TILES * _ts and unit_system.can_walk_direct(u.position, point):
			unit_system.move_direct(u, point, DIRECT_CHASE_TILES)
		else:
			unit_system.move_to(u, point, true)


## Punkt, zu dem u zum Angreifen läuft: bei Einheiten etwas vor dem Ziel aus
## der eigenen Richtung (so verteilen sich Angreifer rundherum).
func _chase_point(u: Unit, t: Object) -> Vector2:
	if t is Building:
		return t.get_approach_point(u.position)
	var dir: Vector2 = (u.position - t.position)
	if dir.length() < 1.0:
		dir = Vector2.RIGHT.rotated(_rng.randf() * TAU)
	var reach := u.attack_range * _ts
	return t.position + dir.normalized() * minf(reach * 0.7 + t.get_radius(), dir.length())


## Ein Angriff: Schaden sofort, Fernkampf zeigt zusätzlich ein Geschoss.
func _attack(u: Unit, t: Object) -> void:
	var dmg := _damage_value(u, t, _rng.randf_range(1.0 - _variance, 1.0 + _variance))
	var kind := str(u.type_def.get("projectile", ""))
	if not kind.is_empty():
		var to_pos: Vector2 = t.position
		projectile_fired.emit(u.position, to_pos, kind, u.position.distance_to(to_pos) / (PROJECTILE_SPEED * _ts))
	apply_damage(t, dmg, u, u.kingdom, "melee" if kind.is_empty() else "ranged")


## Schaden = Angriff × Streuung × (1 + Gebietsbonus des Angreifers)
##          × (1 − Verteidigung) × (1 − Gebietsbonus des Verteidigers).
## Verteidigung = Rüstung + Geländebonus (biomes.json), begrenzt.
## Gegen Gebäude zählt building_damage des Angreifers und die Gebäuderüstung.
func _damage_value(u: Unit, victim: Object, spread: float) -> float:
	var dmg := u.attack * spread
	if world.get_owner(world.world_to_cell(u.position)) == u.kingdom.id:
		dmg *= 1.0 + _territory_bonus
	var defense := 0.0
	var victim_kingdom: Kingdom = victim.kingdom
	if victim is Unit:
		var cell := world.world_to_cell(victim.position)
		defense = victim.armor + float(world.get_biome(cell).get("defense_bonus", 0.0))
		if world.get_owner(cell) == victim_kingdom.id:
			dmg *= 1.0 - _territory_bonus
	else:
		defense = float(victim.def.get("armor", 0.0))
		dmg *= u.building_damage
	defense = clampf(defense, -0.5, _armor_cap)
	dmg *= (1.0 - defense) / maxf(victim_kingdom.mod("defense"), 0.1)
	return maxf(dmg, _min_damage)


func _damage_unit(v: Unit, dmg: float, source: Object, source_kingdom: Kingdom) -> void:
	v.hp -= dmg
	v.last_damaged_at = GameClock.game_time
	v.dormant = false
	v.flash()
	if v.hp <= 0.0:
		v.hp = 0.0
		_dead_units.append([v, source_kingdom])
		return
	if v.role == "king":
		_warn_king(v)
	else:
		_warn_attacked(v.kingdom, v.position, "Bewohner werden angegriffen!" if v.flee_on_hit else "Deine Einheiten werden angegriffen!")
	if source is Unit and is_instance_valid(source):
		_react_to_hit(v, source)


func _damage_building(b: Building, dmg: float, source: Object, source_kingdom: Kingdom) -> void:
	b.hp -= dmg
	b.last_damaged_at = GameClock.game_time
	b.flash()
	if b.hp <= 0.0:
		b.hp = 0.0
		_dead_buildings.append([b, source_kingdom])
		return
	_warn_attacked(b.kingdom, b.position, "%s wird angegriffen!" % b.get_display_name())
	if source is Unit and is_instance_valid(source):
		_call_for_help(b.kingdom, b.position, 6.0, source)


## Getroffene Einheit: Arbeiter fliehen, Kämpfer wehren sich und rufen Hilfe.
func _react_to_hit(v: Unit, attacker: Unit) -> void:
	if not CommandSystem.flag(v.command, "retaliate"):
		return
	if v.flee_on_hit:
		if _worker_flee:
			_flee(v, attacker)
		return
	# Der König zieht sich schwer verletzt in die Burg zurück
	if v.role == "king" and v.hp < v.max_hp * _king_flee_ratio and is_instance_valid(v.kingdom.castle):
		_flee(v, attacker)
		return
	if not v.joins_fights or v.attack <= 0.0:
		return
	if v.target != null and is_instance_valid(v.target):
		return
	if v.command.is_empty() and v.can_work():
		# Arbeitende Kämpfer: Arbeit unterbrechen, wehren, danach weiterarbeiten
		work_system.suspend(v)
		v.command = "defend"
		v.command_pos = v.position
	v.target = attacker
	v.repath_timer = 0.0
	_call_for_help(v.kingdom, v.position, 4.0, attacker)


## Untätige Kämpfer und Monster verbündeter Reiche in der Nähe greifen an.
func _call_for_help(k: Kingdom, pos: Vector2, radius_tiles: float, attacker: Unit) -> void:
	if not is_instance_valid(attacker) or not attacker.is_alive():
		return
	for w in index.query(pos, (radius_tiles + QUERY_PAD_TILES) * _ts):
		if w.target != null or not w.joins_fights or w.attack <= 0.0 or not game.are_allied(k, w.kingdom):
			continue
		if w.command == "hold" or w.command == "attack_move" or (w.command.is_empty() and not w.can_work()):
			w.target = attacker
			w.repath_timer = 0.0
			w.dormant = false


## Läuft zur Burg (oder vom Angreifer weg); Arbeiter arbeiten danach weiter.
func _flee(v: Unit, attacker: Unit) -> void:
	if v.command.is_empty() and v.can_work():
		work_system.suspend(v)
	v.command = "flee"
	v.target = null
	v.follow_leader = null
	var castle := v.kingdom.castle
	var dest: Vector2
	if is_instance_valid(castle):
		dest = castle.get_approach_point(v.position)
	else:
		dest = v.position + (v.position - attacker.position).normalized() * 6.0 * _ts
	v.command_pos = dest
	unit_system.move_to(v, dest)


## Warnung mit Ort – höchstens einmal je Gebiet (20 Kacheln) und 15 Spielsekunden
func _warn_attacked(k: Kingdom, pos: Vector2, text: String) -> void:
	if not k.is_player:
		return
	var c := world.world_to_cell(pos)
	var key := "attack_warned:%d:%d" % [floori(float(c.x) / ATTACK_WARN_AREA), floori(float(c.y) / ATTACK_WARN_AREA)]
	if GameClock.game_time - float(k.flags.get(key, -1000.0)) < ATTACK_WARN_INTERVAL:
		return
	k.flags[key] = GameClock.game_time
	k.notify(text, "warning", pos)


func _warn_king(v: Unit) -> void:
	var k := v.kingdom
	if not k.is_player or GameClock.game_time - float(k.flags.get("king_warned_at", -1000.0)) < KING_WARN_INTERVAL:
		return
	k.flags["king_warned_at"] = GameClock.game_time
	k.notify("Der König wird angegriffen! (%d %% Leben)" % roundi(v.hp / v.max_hp * 100.0), "danger", v.position)


## Ereignis für Diplomatie und KI (ab Phase 6/7), je Paar gedrosselt
func _note_attack(victim: Kingdom, attacker: Kingdom, pos: Vector2) -> void:
	if victim == null or attacker == null or victim == attacker:
		return
	var key := "%d:%d" % [victim.id, attacker.id]
	if GameClock.game_time - float(_attack_events.get(key, -1000.0)) < KINGDOM_ATTACK_INTERVAL:
		return
	_attack_events[key] = GameClock.game_time
	kingdom_attacked.emit(victim, attacker, pos)


## Ziel weg (tot, ausser Reichweite, zu weit weg): nächstes Ziel suchen oder
## je nach Befehl zurückkehren, weiterarbeiten oder weitermarschieren.
func _after_fight(u: Unit) -> void:
	u.target = null
	if _may_auto_acquire(u):
		u.target = _find_target(u)
		if u.target != null:
			u.repath_timer = 0.0
			return
	match u.command:
		"hold":
			if u.position.distance_to(u.command_pos) > _ts * 0.6:
				unit_system.move_to(u, u.command_pos)
			else:
				unit_system.stop(u)
		"attack_move":
			# Im Gruppenmarsch übernimmt das Folgen, sonst selbst weiter
			if u.follow_leader == null:
				unit_system.move_to(u, u.command_pos)
		"attack":
			u.command = "hold"
			u.command_pos = u.position
			unit_system.stop(u)
		"defend":
			work_system.resume(u)
		"":
			if u.has_home and u.position.distance_to(u.home_pos) > _camp_radius * _ts:
				u.command = "return"
				unit_system.move_to(u, u.home_pos)
			else:
				unit_system.stop(u)


## Verfolgung ohne Weg: Ziel fallen lassen und eine Weile nicht neu suchen
func _on_path_failed(u: Unit) -> void:
	if u.target == null or not is_instance_valid(u.target):
		return
	u.target = null
	u.think_timer = 3.0


# ---------------------------------------------------------------------------
# Heilung und Erholung
# ---------------------------------------------------------------------------

func _tick_regen(u: Unit, dt: float, now: float) -> void:
	var amount := u.regen
	if amount <= 0.0:
		return
	if u.command == "return":
		amount *= 3.0
	elif now - u.last_damaged_at < _regen_delay:
		return
	_heal(u, amount * dt)


func _heal(u: Unit, amount: float) -> void:
	u.hp = minf(u.hp + amount, u.max_hp)


## Heiler: heilt die am stärksten verletzte verbündete Einheit in Reichweite.
## Ist niemand in Reichweite, aber jemand in der Nähe verletzt, geht er hin.
func _tick_healer(u: Unit, dt: float) -> void:
	if u.command == "move" or u.command == "flee":
		return
	var heal_range := u.heal_range * _ts
	var best: Unit = null
	var best_ratio := 1.0
	var far: Unit = null
	var far_ratio := 1.0
	for v in index.query(u.position, heal_range + (4.0 + QUERY_PAD_TILES) * _ts):
		if v == u or v.hp >= v.max_hp or v.hp <= 0.0 or not game.are_allied(u.kingdom, v.kingdom):
			continue
		var ratio: float = v.hp / v.max_hp
		if u.position.distance_to(v.position) <= heal_range + v.get_radius():
			if ratio < best_ratio:
				best_ratio = ratio
				best = v
		elif ratio < far_ratio:
			far_ratio = ratio
			far = v
	u.target = best
	if best != null:
		_heal(best, u.heal * dt)
		if u.moving or u.path_pending:
			unit_system.stop(u)
		return
	u.repath_timer -= dt
	if far != null and u.follow_leader == null and u.position.distance_to(u.command_pos) < 8.0 * _ts:
		if u.repath_timer <= 0.0:
			u.repath_timer = _chase_repath
			unit_system.move_direct(u, far.position, DIRECT_CHASE_TILES)
	elif u.command == "hold" and not u.moving and not u.path_pending \
			and u.position.distance_to(u.command_pos) > _ts:
		unit_system.move_to(u, u.command_pos)


## Krankenstationen heilen verbündete Einheiten in ihrer Nähe.
func _tick_heal_auras(dt: float) -> void:
	for k in game.kingdoms:
		for b in k.buildings:
			if not b.constructed or not b.def.has("heal_aura"):
				continue
			var aura: Dictionary = b.def["heal_aura"]
			var amount := float(aura.get("hp_per_sec", 0.0)) * dt
			for v in index.query(b.position, float(aura.get("radius", 4.0)) * _ts):
				if v.hp < v.max_hp and game.are_allied(k, v.kingdom):
					_heal(v, amount)


# ---------------------------------------------------------------------------
# Tod und Zerstörung
# ---------------------------------------------------------------------------

func _process_deaths() -> void:
	if not _dead_units.is_empty():
		var list := _dead_units
		_dead_units = []
		for entry in list:
			_kill_unit(entry[0], entry[1])
	if not _dead_buildings.is_empty():
		var list := _dead_buildings
		_dead_buildings = []
		for entry in list:
			_destroy_building(entry[0], entry[1])


func _kill_unit(u: Variant, killer: Kingdom) -> void:
	if not is_instance_valid(u) or not unit_system.units.has(u):
		return
	var k: Kingdom = u.kingdom
	var points := int(u.type_def.get("kill_points", 0))
	if killer != null and killer != k:
		killer.kill_points += points
		killer.kill_points_total += points
		killer.add_stat("kills")
		if killer.is_player and k.controller == "wild":
			killer.notify("Monster besiegt: %s (+%d Kampfpunkte)" % [u.get_display_name(), points], "good", u.position)
	k.add_stat("losses")
	var was_king: bool = u.role == "king"
	if k.is_player and not was_king:
		_log_death(u)
	unit_died.emit(u, killer)
	if was_king and k.king == u:
		k.king = null
	unit_system.remove_unit(u)
	if was_king:
		king_died.emit(k)
		game.defeat_kingdom(k, "king", killer)


func _destroy_building(b: Variant, killer: Kingdom) -> void:
	if not is_instance_valid(b):
		return
	var k: Kingdom = b.kingdom
	if not k.buildings.has(b):
		return
	if killer != null and killer != k:
		var loot: Dictionary = b.get_loot()
		for res_id in loot:
			killer.add_resource(res_id, float(loot[res_id]))
		var points := int(b.def.get("kill_points", 0))
		killer.kill_points += points
		killer.kill_points_total += points
		var text := "%s zerstört" % b.get_display_name()
		if not loot.is_empty():
			text += " – Beute: " + DataDB.cost_to_text(loot)
		if points > 0:
			text += " (+%d Kampfpunkte)" % points
		killer.notify(text, "good", b.position)
	if k.is_player:
		k.notify("%s wurde zerstört!" % b.get_display_name(), "danger", b.position)
	building_destroyed.emit(b, killer)
	game.building_system.remove_building(b, 0.0)


## Todesfälle des Spielers sammeln und gebündelt melden
func _log_death(u: Unit) -> void:
	var name_text := u.get_display_name()
	var entry: Dictionary = _death_log.get(name_text, {"count": 0, "pos": u.position})
	entry["count"] = int(entry["count"]) + 1
	entry["pos"] = u.position
	_death_log[name_text] = entry
	if _death_flush_at < 0.0:
		_death_flush_at = GameClock.game_time + DEATH_REPORT_DELAY


func _flush_death_reports() -> void:
	_death_flush_at = -1.0
	var player: Kingdom = game.player
	for name_text in _death_log:
		var entry: Dictionary = _death_log[name_text]
		var n := int(entry["count"])
		var text := ("%s ist gefallen" % name_text) if n == 1 else ("%d× %s gefallen" % [n, name_text])
		if player != null:
			player.notify(text, "warning", entry["pos"])
	_death_log.clear()


# ---------------------------------------------------------------------------
# Abstand halten
# ---------------------------------------------------------------------------

## Kämpfende Einheiten schieben sich leicht auseinander, damit Nahkämpfer
## nicht auf einem Punkt kleben. Ruhende Gruppen stehen schon mit Abstand.
func _separate() -> void:
	for u in unit_system.units:
		if u.target == null or u.moving or u.inside != null or u.hp <= 0.0:
			continue
		var r: float = u.get_radius()
		var push := Vector2.ZERO
		for v in index.query(u.position, r * 2.0):
			if v == u or v.flee_on_hit:
				continue
			var diff: Vector2 = u.position - v.position
			var min_d: float = (r + v.get_radius()) * 0.8
			var d := diff.length()
			if d >= min_d:
				continue
			if d < 0.01:
				diff = Vector2.RIGHT.rotated(float(u.uid) * 2.39996)
				d = 0.01
			push += diff / d * (min_d - d) * 0.35
		if push == Vector2.ZERO:
			continue
		var new_pos: Vector2 = u.position + push.limit_length(r * 0.5)
		var c := world.world_to_cell(new_pos)
		if world.in_bounds(c) and not game.nav.is_solid(c):
			u.position = new_pos
