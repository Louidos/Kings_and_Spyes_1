## SpySystem
##
## Spione (Phase 7): Einheiten der Stufe "spy" (spy_good/spy_evil), immer getarnt,
## kämpfen nie. Beschworen in der Burg (nach der Kundschafter-Forschung) oder im
## Kundschafterhaus (beginnen dort eine Stufe höher). Stufe 1–3 über Erfahrung
## (espionage.json spies.levels: Geschick gegen Entdeckung, Tempo bei Aufträgen).
## Aufträge – für Spieler (Spionagefenster K) und KI dieselben Funktionen:
##   scout          – Auskundschaften: zum Ziel (Reich oder Dorf) schleichen und dort
##                    bleiben, laufend Kundschaft (Intel) liefern
##   incite_village – Dorf aufhetzen: Ruf des Dorfs gegenüber einem Reich sinkt
##   incite_rival   – Rivalen aufhetzen: Spannung zwischen zwei KI-Reichen steigt
## Im fremden Gebiet (oder nahe einer fremden Burg/Halle) würfelt der Gastgeber alle
## detect_interval Sekunden gegen die Wachsamkeit (Späher, Spione, Gebäude, Forschung):
## Entdeckt wird der Spion für reveal_seconds sichtbar (angreifbar), bricht ab und
## flieht heim; der Gastgeber wird aufmerksamer und erfährt, wer ihn geschickt hat.
##
## Zustand (gespeichert): spies (Datensatz je Spion-uid), counters, stats, rng_state.
## Laufzeit: _acc, _pending (Ankünfte aus command_finished, im eigenen Takt).
class_name SpySystem
extends Node

## Spione eines Reichs haben sich geändert (neu, Auftrag, Stufe, Tod)
signal spies_changed(employer: Kingdom)
## Ein Spion wurde entdeckt (observer = Gastgeber)
signal spy_detected(spy: Unit, employer: Kingdom, observer: Kingdom)
## Ein Auftrag ist erfüllt (ok) bzw. gescheitert
signal spy_mission_done(spy: Unit, mission: String, ok: bool)
## Ein Spion ist aufgestiegen
signal spy_leveled(spy: Unit, level: int)

const MISSIONS := ["scout", "incite_village", "incite_rival"]
const MISSION_NAMES := {"scout": "Auskundschaften", "incite_village": "Dorf aufhetzen", "incite_rival": "Rivalen aufhetzen"}
const STATE_NAMES := {"idle": "bereit", "travel": "unterwegs", "active": "am Ziel", "return": "kehrt heim"}
## So oft wird ein Weg zum Ziel neu versucht, bevor der Auftrag scheitert
const MAX_PATH_FAILS := 3
const RNG_SALT := 7601

var game: Node
var world: WorldData

## uid -> {"uid", "owner_id", "level", "xp", "number", "mission" ("" | scout | incite_village |
##   incite_rival), "target_id", "target2_id", "state" ("idle" | "travel" | "active" | "return"),
##   "dest": Vector2, "started_at", "active_since", "progress" (0..1), "next_incite", "next_detect",
##   "missions_done", "revealed", "done" (Auftrag erfüllt, Spion bleibt), "fails"}
var spies: Dictionary = {}
## Reich-id -> laufende Nummer ("Kundschafterin 3")
var counters: Dictionary = {}
var stats := {"recruited": 0, "missions": 0, "detected": 0, "killed": 0}
## Zustand des Zufalls (Zielpunkte, Entdeckungswürfe)
var rng_state: int = 0

var _ts := 64.0
var _acc := 0.0
var _rng := RandomNumberGenerator.new()
## ["arrived", uid, Befehl, ok] aus command_finished (wird im eigenen Takt abgearbeitet)
var _pending: Array = []


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_ts = float(world.tile_size)
	_rng.seed = hash(world.world_seed + RNG_SALT)
	rng_state = _rng.state
	GameClock.sim_tick.connect(_on_sim_tick)
	(game.summon_system as SummonSystem).unit_summoned.connect(_on_unit_summoned)
	(game.command_system as CommandSystem).command_finished.connect(_on_command_finished)
	(game.combat_system as CombatSystem).unit_died.connect(_on_unit_died)
	(game.unit_system as UnitSystem).unit_removed.connect(_on_unit_removed)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Ist die Einheit ein Spion?
func is_spy(u: Unit) -> bool:
	return u != null and is_instance_valid(u) and u.tier == "spy"


## Lebende Spione des Reichs (fehlende Datensätze werden angelegt)
func get_spies(k: Kingdom) -> Array:
	var list: Array = []
	if k == null:
		return list
	for u in k.units:
		if u.tier == "spy" and u.is_alive():
			get_record(u)
			list.append(u)
	return list


## Datensatz des Spions (legt ihn an, z. B. für Debug-Einheiten); {} wenn kein Spion
func get_record(u: Unit) -> Dictionary:
	if not is_spy(u):
		return {}
	if not spies.has(u.uid):
		_register(u, 1 + int(u.kingdom.bonus("spy_level")))
	return spies[u.uid]


## Stufe des Spions (1–3)
func get_level(u: Unit) -> int:
	var rec := get_record(u)
	return int(rec.get("level", 1)) if not rec.is_empty() else 1


## Werte einer Stufe: {"xp", "skill", "speed"}
static func level_def(level: int) -> Dictionary:
	var levels: Array = DataDB.esp("spies.levels", [])
	if levels.is_empty():
		return {"xp": 0, "skill": 1.0, "speed": 1.0}
	return levels[clampi(level - 1, 0, levels.size() - 1)]


## Höchste Stufe (Anzahl der Einträge in spies.levels)
static func max_level() -> int:
	return maxi((DataDB.esp("spies.levels", []) as Array).size(), 1)


## Erfahrung für die nächste Stufe (-1 = höchste Stufe erreicht)
func xp_for_next(u: Unit) -> float:
	var level := get_level(u)
	if level >= max_level():
		return -1.0
	return float(level_def(level + 1).get("xp", 0))


## Spion-Einheit der Fraktion ({} wenn keine)
static func spy_type(faction_id: String) -> Dictionary:
	return DataDB.get_unit_for_tier(faction_id, "spy")


## Höchstzahl der Spione: max_base + den_extra je fertigem Kundschafterhaus + Bonus spy_slots
func max_spies(k: Kingdom) -> int:
	if k == null:
		return 0
	var n := int(DataDB.esp("spies.max_base", 2)) + int(k.bonus("spy_slots"))
	for b in k.buildings:
		if b.constructed and bool(b.def.get("spy_den", false)):
			n += int(DataDB.esp("spies.den_extra", 1))
	return n


## Spione in Warteschlangen der Gebäude des Reichs
func count_queued(k: Kingdom) -> int:
	var id := str(spy_type(k.faction_id).get("id", ""))
	var n := 0
	for b in k.buildings:
		for entry in b.summon_queue:
			if str(entry.get("type_id", "")) == id:
				n += 1
	return n


## Gebäude für neue Spione: fertiges Kundschafterhaus, sonst die Burg (wenn dort
## freigeschaltet); null, wenn keins
func get_recruit_building(k: Kingdom) -> Building:
	if k == null:
		return null
	for b in k.buildings:
		if b.constructed and bool(b.def.get("spy_den", false)):
			return b
	var id := str(spy_type(k.faction_id).get("id", ""))
	if is_instance_valid(k.castle) and k.castle.constructed and k.has_unlock("summon:castle:%s" % id):
		return k.castle
	return null


## "" = ein Spion kann beschworen werden, sonst der Grund
func can_recruit(k: Kingdom) -> String:
	if k == null or k.defeated:
		return "Kein Reich"
	var def := spy_type(k.faction_id)
	if def.is_empty():
		return "Keine Spione für diese Fraktion"
	var requires: Array = def.get("requires", [])
	if not k.has_all_unlocks(requires):
		return "Benötigt Forschung: %s" % DataDB.describe_requirement(requires, k.faction_id)
	var limit := max_spies(k)
	if get_spies(k).size() + count_queued(k) >= limit:
		return "Höchstens %d Spione (Kundschafterhaus: +%d)" % [limit, int(DataDB.esp("spies.den_extra", 1))]
	var b := get_recruit_building(k)
	if b == null:
		return "Kein Gebäude für Spione (Burg oder Kundschafterhaus)"
	return (game.summon_system as SummonSystem).can_summon(b, str(def["id"]))


## Beschwört einen Spion (Burg oder Kundschafterhaus); false, wenn es nicht geht
func recruit(k: Kingdom) -> bool:
	if not can_recruit(k).is_empty():
		return false
	return (game.summon_system as SummonSystem).summon(get_recruit_building(k), str(spy_type(k.faction_id)["id"]))


static func mission_name(mission: String) -> String:
	return str(MISSION_NAMES.get(mission, "Kein Auftrag" if mission.is_empty() else mission))


static func state_name(state: String) -> String:
	return str(STATE_NAMES.get(state, state))


## Mögliche Ziele eines Auftrags. scout: andere Reiche (Spieler/KI) und selbstständige
## Dörfer; incite_village: selbstständige Dörfer; incite_rival: fremde KI-Reiche
func get_valid_targets(employer: Kingdom, mission: String) -> Array:
	var list: Array = []
	if employer == null:
		return list
	var vs: VillageSystem = game.village_system
	match mission:
		"scout":
			for k in _parties():
				if k != employer and is_instance_valid(k.castle):
					list.append(k)
			list.append_array(vs.get_villages())
		"incite_village":
			list.append_array(vs.get_villages())
		"incite_rival":
			for k in _ai_kingdoms():
				if k != employer:
					list.append(k)
	return list


## Zweitziele: incite_village – Reiche, gegen die das Dorf aufgehetzt wird (nicht der
## Auftraggeber); incite_rival – andere KI-Reiche als target (nicht der Auftraggeber)
func get_valid_targets2(employer: Kingdom, mission: String, target: Kingdom) -> Array:
	var list: Array = []
	if employer == null:
		return list
	match mission:
		"incite_village":
			for k in _parties():
				if k != employer and k != target:
					list.append(k)
		"incite_rival":
			for k in _ai_kingdoms():
				if k != employer and k != target:
					list.append(k)
	return list


## "" = der Auftrag ist möglich, sonst der Grund
func can_assign(spy: Unit, mission: String, target: Kingdom, target2: Kingdom = null) -> String:
	if not is_spy(spy) or not spy.is_alive():
		return "Kein Spion gewählt"
	var employer := spy.kingdom
	var rec := get_record(spy)
	if not MISSIONS.has(mission):
		return "Unbekannter Auftrag"
	if target == null:
		return "Kein Ziel gewählt"
	if target == employer:
		return "Nicht das eigene Reich"
	if bool(rec.get("revealed", false)) and str(rec.get("state", "")) == "return":
		return "Enttarnt – erst heimkehren lassen"
	if not get_valid_targets(employer, mission).has(target):
		return "Ungültiges Ziel für %s" % mission_name(mission)
	if mission != "scout":
		if target2 == null:
			return "Zweites Ziel fehlt"
		if not get_valid_targets2(employer, mission, target).has(target2):
			return "Ungültiges zweites Ziel"
	if _target_center(target) == Vector2.INF:
		return "Ziel nicht erreichbar"
	return ""


## Auftrag erteilen: der Spion schleicht zum Ziel ("infiltrate"). "" = ok, sonst der Grund.
func assign_mission(spy: Unit, mission: String, target: Kingdom, target2: Kingdom = null) -> String:
	var reason := can_assign(spy, mission, target, target2)
	if not reason.is_empty():
		return reason
	var rec := get_record(spy)
	var now := GameClock.game_time
	rec["mission"] = mission
	rec["target_id"] = target.id
	rec["target2_id"] = target2.id if target2 != null else 0
	rec["state"] = "travel"
	rec["dest"] = _pick_dest(target)
	rec["started_at"] = now
	rec["active_since"] = -1.0
	rec["progress"] = 0.0
	rec["next_incite"] = -1.0
	rec["done"] = false
	rec["fails"] = 0
	_set_speed(spy, rec)
	(game.command_system as CommandSystem).order_travel(spy, rec["dest"], "infiltrate")
	spies_changed.emit(spy.kingdom)
	return ""


## Zurückrufen: Auftrag endet, der Spion kehrt zur eigenen Burg heim
func recall(spy: Unit) -> void:
	if not is_spy(spy) or not spy.is_alive():
		return
	var rec := get_record(spy)
	rec["mission"] = ""
	rec["done"] = false
	if not is_instance_valid(spy.kingdom.castle):
		_set_idle(spy, rec)
		return
	rec["state"] = "return"
	rec["dest"] = spy.kingdom.castle.get_approach_point(spy.position)
	(game.command_system as CommandSystem).order_travel(spy, rec["dest"], "return")
	spies_changed.emit(spy.kingdom)


## Fortschritt des Auftrags (0..1)
func get_progress(spy: Unit) -> float:
	return float(get_record(spy).get("progress", 0.0))


# ---------------------------------------------------------------------------
# Entdeckung
# ---------------------------------------------------------------------------

## Wachsamkeit des Reichs obs an pos: Grundwert + Späher und Spione in der Nähe +
## Gebäude (vigilance.buildings) im Umkreis + Bonus des Reichs (Forschung, Schwierigkeit)
func vigilance_at(obs: Kingdom, pos: Vector2) -> float:
	if obs == null:
		return 0.0
	var vig: Dictionary = DataDB.esp("spies.vigilance", {})
	var value := float(vig.get("base", 1.0))
	var index: SpatialIndex = game.combat_system.index
	var scout_r := float(vig.get("scout_radius", 8)) * _ts
	var spy_r := float(vig.get("spy_radius", 6)) * _ts
	for u in index.query_kingdom(pos, maxf(scout_r, spy_r), obs.id):
		if u.hp <= 0.0:
			continue
		var d: float = u.position.distance_to(pos)
		if u.tier == "scout" and d <= scout_r:
			value += float(vig.get("scout", 0.5))
		elif u.tier == "spy" and d <= spy_r:
			value += float(vig.get("spy", 1.0))
	var weights: Dictionary = vig.get("buildings", {})
	var b_r := float(vig.get("building_radius", 12)) * _ts
	for b in obs.buildings:
		if not b.constructed:
			continue
		var w := float(weights.get(str(b.def.get("id", "")), 0.0))
		if w > 0.0 and b.get_center().distance_to(pos) <= b_r:
			value += w
	return value + obs.bonus("vigilance")


## Entdeckungschance je Prüfung (alle detect_interval Sekunden) für den Spion an seinem
## Ort (pos = Vector2: an dieser Stelle, z. B. Vorschau am Ziel). 0 = kein Gastgeber.
func detection_chance(spy: Unit, pos: Variant = null) -> float:
	if not is_spy(spy):
		return 0.0
	var at := spy.position
	if pos is Vector2:
		at = pos
	var host := _host_at(spy.kingdom, at)
	if host.is_empty():
		return 0.0
	return _chance(spy, host[0], at, float(host[1]))


## Vorschau: Entdeckungschance des Spions am Zielort eines Auftrags (Mitte von target)
func preview_detection(spy: Unit, target: Kingdom) -> float:
	var center := _target_center(target)
	if not is_spy(spy) or center == Vector2.INF:
		return 0.0
	return _chance(spy, target, center, 1.0)


func _chance(spy: Unit, obs: Kingdom, pos: Vector2, presence: float) -> float:
	var skill := float(level_def(get_level(spy)).get("skill", 1.0)) + spy.kingdom.bonus("spy_skill")
	var p := float(DataDB.esp("spies.detect_base", 0.03)) * vigilance_at(obs, pos) * presence / maxf(skill, 0.1)
	return clampf(p, float(DataDB.esp("spies.detect_min", 0.005)), float(DataDB.esp("spies.detect_max", 0.6)))


## Gastgeber an pos: [Reich, Anwesenheit] – Besitzer der Kachel (1) bzw. ein Reich mit
## Burg oder Dorfzentrum in near_tiles (outside_presence); [] wenn keiner
func _host_at(employer: Kingdom, pos: Vector2) -> Array:
	var oid := world.get_owner(world.world_to_cell(pos))
	if oid != 0 and oid != employer.id:
		var k: Kingdom = game.get_kingdom(oid)
		if _can_observe(employer, k):
			return [k, 1.0]
	var near := float(DataDB.esp("spies.near_tiles", 10)) * _ts
	var best: Kingdom = null
	var best_d := INF
	for o in game.kingdoms:
		var k: Kingdom = o
		if not _can_observe(employer, k):
			continue
		var center := _target_center(k)
		if center == Vector2.INF:
			continue
		var d := center.distance_to(pos)
		if d <= near and d < best_d:
			best_d = d
			best = k
	if best == null:
		return []
	return [best, float(DataDB.esp("spies.outside_presence", 0.3))]


func _can_observe(employer: Kingdom, k: Kingdom) -> bool:
	return k != null and k != employer and not k.defeated and k.controller != "wild" and not game.are_allied(employer, k)


## Der Spion wurde entdeckt: sichtbar, flieht heim, der Gastgeber erfährt davon
func _detect(spy: Unit, rec: Dictionary, obs: Kingdom) -> void:
	var now := GameClock.game_time
	var employer := spy.kingdom
	var ms: MagicSystem = game.magic_system
	ms.add_unit_effect(spy, {"id": "espionage:revealed", "key": "revealed", "mult": 1.0, "add": 0.0,
			"until": now + float(DataDB.esp("spies.reveal_seconds", 25)), "source": "espionage:revealed"})
	ms.add_unit_effect(spy, {"id": "espionage:flee", "key": "speed", "mult": float(DataDB.esp("spies.flee_speed", 1.5)),
			"add": 0.0, "until": now + float(DataDB.esp("spies.flee_seconds", 8)), "source": "espionage:flee"})
	var mission := str(rec.get("mission", ""))
	rec["revealed"] = true
	recall(spy)
	if not mission.is_empty():
		spy_mission_done.emit(spy, mission, false)
	var esp := _espionage()
	if esp != null:
		esp.add_awareness(obs, employer, float(DataDB.esp("awareness.caught_spy", 15)), "Spion ertappt")
		esp.grant_intel(obs, employer, int(DataDB.esp("intel.caught_spy_level", 1)), "Spion")
	var vs: VillageSystem = game.village_system
	if vs.is_village(obs):
		(game.diplomacy_system as DiplomacySystem).change_reputation(obs, employer,
				float(DataDB.esp("spies.caught_reputation", -8)), "Spion ertappt")
	stats["detected"] = int(stats["detected"]) + 1
	spy_detected.emit(spy, employer, obs)
	if obs.is_player:
		obs.flags["espionage_alert_at"] = now
		var known: bool = esp != null and esp.get_intel_level(obs, employer) >= 1
		if known:
			obs.notify("Ein fremder Spion (%s) wurde entdeckt!" % employer.display_name, "danger", spy.position)
		else:
			obs.notify("Ein fremder Spion wurde entdeckt!", "danger", spy.position)
	employer.notify("%s wurde entdeckt und flieht!" % spy.get_display_name(), "warning", spy.position)


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	if not _pending.is_empty():
		var list := _pending
		_pending = []
		for entry in list:
			_handle_arrival(int(entry[1]), str(entry[2]), bool(entry[3]))
	_acc += dt
	var step := float(DataDB.esp("spies.tick_seconds", 2))
	if _acc < step:
		return
	var elapsed := _acc
	_acc = 0.0
	var now := GameClock.game_time
	for uid in spies.keys():
		var u: Variant = game.find_by_uid(int(uid))
		if not (u is Unit) or not (u as Unit).is_alive():
			spies.erase(uid)
			continue
		_tick_spy(u, spies[uid], now, elapsed)
	rng_state = _rng.state


func _tick_spy(u: Unit, rec: Dictionary, now: float, _elapsed: float) -> void:
	var employer := u.kingdom
	if employer == null or employer.defeated:
		return
	rec["owner_id"] = employer.id
	var state := str(rec["state"])
	# Befehl von aussen geändert (der Spieler hat den Spion verschoben): Auftrag abgebrochen
	match state:
		"travel":
			if u.command != "infiltrate":
				_abort(u, rec, true)
				return
		"active":
			if u.command != "spy":
				_abort(u, rec, true)
				return
		"return":
			if u.command != "return":
				_set_idle(u, rec, false)
	state = str(rec["state"])
	if state == "travel" or state == "active":
		if not _targets_valid(rec):
			employer.notify("%s: Ziel gibt es nicht mehr – kehrt heim" % u.get_display_name(), "info", u.position)
			recall(u)
			return
	if state == "active":
		_work(u, rec, now)
	# Entdeckungswurf (nur unerkannt)
	if now >= float(rec.get("next_detect", -1.0)):
		rec["next_detect"] = now + float(DataDB.esp("spies.detect_interval", 10))
		if u.stealthed:
			var host := _host_at(employer, u.position)
			if not host.is_empty() and _rng.randf() < _chance(u, host[0], u.position, float(host[1])):
				_detect(u, rec, host[0])


## Auftrag am Ziel ausführen
func _work(u: Unit, rec: Dictionary, now: float) -> void:
	var employer := u.kingdom
	var target: Kingdom = game.get_kingdom(int(rec["target_id"]))
	var since := float(rec["active_since"])
	var skill := float(level_def(int(rec["level"])).get("skill", 1.0))
	var xp: Dictionary = DataDB.esp("spies.xp", {})
	var esp := _espionage()
	match str(rec["mission"]):
		"scout":
			if esp != null:
				var levels: Array = DataDB.esp("intel.spy_levels", [2, 3, 3])
				esp.grant_intel(employer, target, int(levels[clampi(int(rec["level"]) - 1, 0, levels.size() - 1)]), "Spion")
				if employer.controller == "ai" and now - since >= float(DataDB.esp("awareness.spy_confirm_seconds", 60)):
					esp.raise_awareness_to(employer, target, float(DataDB.esp("awareness.discovered", 60)) + 5.0, "Spion")
			rec["progress"] = clampf((now - since) / maxf(float(DataDB.esp("spies.scout_duration", 180)), 1.0), 0.0, 1.0)
			if float(rec["progress"]) >= 1.0 and not bool(rec.get("done", false)):
				rec["done"] = true
				_mission_done(u, rec, float(xp.get("scout_done", 2)))
				employer.notify("%s: %s abgeschlossen – bleibt vor Ort und meldet weiter." % [u.get_display_name(),
						mission_name("scout")], "good", u.position)
		"incite_village", "incite_rival":
			var other: Kingdom = game.get_kingdom(int(rec["target2_id"]))
			if now >= float(rec["next_incite"]):
				rec["next_incite"] = now + float(DataDB.esp("spies.incite_interval", 30))
				if str(rec["mission"]) == "incite_village":
					var ds: DiplomacySystem = game.diplomacy_system
					ds.change_reputation(target, other, float(DataDB.esp("spies.incite_reputation", -4)) * skill, "Aufwiegelung")
					ds.change_reputation(target, employer, float(DataDB.esp("spies.incite_owner_bonus", 1)), "Gerüchte")
					ds.spread_rumour(target, other, float(DataDB.esp("spies.incite_rumour", -1)), "Aufwiegelung")
				else:
					var ai: Variant = game.get("ai_system")
					if ai is AISystem:
						(ai as AISystem).add_tension(target, other, float(DataDB.esp("spies.incite_tension", 5)) * skill, "Spion")
				_add_xp(u, rec, float(xp.get("incite_tick", 0.25)))
			rec["progress"] = clampf((now - since) / maxf(float(DataDB.esp("spies.incite_duration", 240)), 1.0), 0.0, 1.0)
			if float(rec["progress"]) >= 1.0:
				var mission := str(rec["mission"])
				_mission_done(u, rec, float(xp.get("incite_done", 2)))
				employer.notify("%s: %s abgeschlossen." % [u.get_display_name(), mission_name(mission)], "good", u.position)
				rec["mission"] = ""
				_set_idle(u, rec)


func _mission_done(u: Unit, rec: Dictionary, xp_gain: float) -> void:
	rec["missions_done"] = int(rec.get("missions_done", 0)) + 1
	stats["missions"] = int(stats["missions"]) + 1
	u.kingdom.add_stat("spy_missions")
	spy_mission_done.emit(u, str(rec["mission"]), true)
	_add_xp(u, rec, xp_gain)
	spies_changed.emit(u.kingdom)


## Sind die Ziele des Auftrags noch gültig?
func _targets_valid(rec: Dictionary) -> bool:
	var target: Kingdom = game.get_kingdom(int(rec.get("target_id", 0)))
	if target == null or target.defeated or _target_center(target) == Vector2.INF:
		return false
	var mission := str(rec.get("mission", ""))
	if mission == "incite_village" or mission == "incite_rival":
		var other: Kingdom = game.get_kingdom(int(rec.get("target2_id", 0)))
		if other == null or other.defeated:
			return false
		if mission == "incite_village" and not (game.village_system as VillageSystem).is_village(target):
			return false
	return true


## Auftrag abgebrochen (z. B. vom Spieler verschoben): bereit, wo er gerade steht
func _abort(u: Unit, rec: Dictionary, tell: bool) -> void:
	var mission := str(rec.get("mission", ""))
	rec["mission"] = ""
	_set_idle(u, rec, false)
	if not mission.is_empty():
		spy_mission_done.emit(u, mission, false)
		if tell:
			u.kingdom.notify("%s: %s abgebrochen." % [u.get_display_name(), mission_name(mission)], "info", u.position)


## Bereit (ohne Auftrag); hold: hält an der aktuellen Stelle (sonst bleibt der Befehl)
func _set_idle(u: Unit, rec: Dictionary, hold: bool = true) -> void:
	rec["state"] = "idle"
	rec["progress"] = 0.0
	rec["active_since"] = -1.0
	(game.magic_system as MagicSystem).remove_unit_effects(u, "espionage:speed")
	if hold:
		u.command = "hold"
		u.command_pos = u.position
		u.target = null
	spies_changed.emit(u.kingdom)


## Tempo bei Aufträgen (Stufe)
func _set_speed(u: Unit, rec: Dictionary) -> void:
	var ms: MagicSystem = game.magic_system
	ms.remove_unit_effects(u, "espionage:speed")
	var mult := float(level_def(int(rec["level"])).get("speed", 1.0))
	if mult != 1.0:
		ms.add_unit_effect(u, {"id": "espionage:speed", "key": "speed", "mult": mult, "add": 0.0, "until": -1.0,
				"source": "espionage:speed"})


func _add_xp(u: Unit, rec: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	rec["xp"] = float(rec["xp"]) + amount
	var level := int(rec["level"])
	while level < max_level() and float(rec["xp"]) >= float(level_def(level + 1).get("xp", 0)):
		level += 1
	if level == int(rec["level"]):
		return
	rec["level"] = level
	if str(rec["state"]) != "idle":
		_set_speed(u, rec)
	spy_leveled.emit(u, level)
	spies_changed.emit(u.kingdom)
	u.kingdom.notify("%s steigt auf Stufe %d (geschickter, schneller)." % [u.get_display_name(), level], "good", u.position)


# ---------------------------------------------------------------------------
# Signale
# ---------------------------------------------------------------------------

## Neuer Spion aus einem Gebäude: Stufe (Kundschafterhaus +1), Nummer, Meldung
func _on_unit_summoned(u: Unit, b: Building) -> void:
	if not is_spy(u):
		return
	var level := 1 + int(u.kingdom.bonus("spy_level"))
	if b != null and bool(b.def.get("spy_den", false)):
		level += 1
	_register(u, level)
	stats["recruited"] = int(stats["recruited"]) + 1
	u.kingdom.notify("%s bereit – Auftrag im Spionagefenster (K)" % u.get_display_name(), "info",
			{"window": "espionage", "tab": "spies", "spy_uid": u.uid, "pos": u.position})


func _register(u: Unit, level: int) -> void:
	var k := u.kingdom
	level = clampi(level, 1, max_level())
	var number := int(counters.get(k.id, 0)) + 1
	counters[k.id] = number
	spies[u.uid] = {"uid": u.uid, "owner_id": k.id, "level": level, "xp": float(level_def(level).get("xp", 0)),
			"number": number, "mission": "", "target_id": 0, "target2_id": 0, "state": "idle", "dest": u.position,
			"started_at": -1.0, "active_since": -1.0, "progress": 0.0, "next_incite": -1.0, "next_detect": -1.0,
			"missions_done": 0, "revealed": false, "done": false, "fails": 0}
	if u.custom_name.is_empty():
		u.custom_name = "%s %d" % [str(u.type_def.get("name", "Spion")), number]
	spies_changed.emit(k)


func _on_command_finished(u: Unit, command: String, ok: bool) -> void:
	if (command == "infiltrate" or command == "return") and spies.has(u.uid):
		_pending.append(["arrived", u.uid, command, ok])


## Ankunft am Ziel (infiltrate) bzw. zu Hause (return)
func _handle_arrival(uid: int, command: String, ok: bool) -> void:
	var u: Variant = game.find_by_uid(uid)
	if not (u is Unit) or not spies.has(uid):
		return
	var spy: Unit = u
	var rec: Dictionary = spies[uid]
	var now := GameClock.game_time
	if command == "return":
		if str(rec["state"]) != "return":
			return
		var escaped := bool(rec.get("revealed", false))
		rec["revealed"] = false
		_set_idle(spy, rec)
		if escaped:
			_add_xp(spy, rec, float(DataDB.esp("spies.xp.escape", 1)))
		return
	if str(rec["state"]) != "travel" or not spy.command.is_empty():
		return
	if ok:
		rec["state"] = "active"
		rec["active_since"] = now
		rec["progress"] = 0.0
		rec["next_incite"] = now + float(DataDB.esp("spies.incite_interval", 30))
		spy.command = "spy"
		spy.command_pos = spy.position
		spies_changed.emit(spy.kingdom)
		return
	rec["fails"] = int(rec.get("fails", 0)) + 1
	var target: Kingdom = game.get_kingdom(int(rec["target_id"]))
	if int(rec["fails"]) >= MAX_PATH_FAILS or target == null:
		spy.kingdom.notify("%s findet keinen Weg zum Ziel – Auftrag abgebrochen." % spy.get_display_name(), "info", spy.position)
		rec["mission"] = ""
		_set_idle(spy, rec)
		return
	rec["dest"] = _pick_dest(target)
	(game.command_system as CommandSystem).order_travel(spy, rec["dest"], "infiltrate")


## Spion getötet: Statistik, der Täter wird aufmerksamer, Meldung an den Besitzer
func _on_unit_died(u: Unit, killer: Kingdom) -> void:
	if not is_spy(u):
		return
	stats["killed"] = int(stats["killed"]) + 1
	var employer := u.kingdom
	if killer != null and killer != employer:
		var esp := _espionage()
		if esp != null:
			esp.add_awareness(killer, employer, float(DataDB.esp("awareness.spy_killed_extra", 10)), "Spion getötet")
		killer.add_stat("spies_caught")
	employer.notify("%s wurde gefangen und getötet." % u.get_display_name(), "danger", u.position)


func _on_unit_removed(u: Unit) -> void:
	if spies.has(u.uid):
		spies.erase(u.uid)
		if u.kingdom != null:
			spies_changed.emit(u.kingdom)


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

## Mitte eines Ziels: Burg bzw. Dorfzentrum (Vector2.INF, wenn es keins gibt)
func _target_center(k: Kingdom) -> Vector2:
	if k == null:
		return Vector2.INF
	if is_instance_valid(k.castle):
		return k.castle.get_center()
	var vs: VillageSystem = game.village_system
	if vs.is_village(k):
		var hall := vs.get_hall(k)
		if hall != null:
			return hall.get_center()
	return Vector2.INF


## Zielpunkt am Ziel: Reich – target_offset Kacheln von der Burg in zufälliger Richtung
## (möglichst im Gebiet des Ziels); Dorf – am Rand des Dorfgebiets
func _pick_dest(target: Kingdom) -> Vector2:
	var center := _target_center(target)
	if center == Vector2.INF:
		return Vector2.ZERO
	var offsets: Array = DataDB.esp("spies.target_offset", [6, 10])
	var lo := float(offsets[0]) if offsets.size() > 0 else 6.0
	var hi := float(offsets[1]) if offsets.size() > 1 else lo
	var vs: VillageSystem = game.village_system
	if vs.is_village(target):
		lo = maxf(vs.get_radius_tiles(target) - 3.0, 1.0)
		hi = maxf(vs.get_radius_tiles(target) - 2.0, lo)
	var fallback := Vector2.INF
	for attempt in 8:
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		var p := center + dir * _rng.randf_range(lo, hi) * _ts
		var cell: Vector2i = game.nav.nearest_free(world.world_to_cell(p), 6)
		if cell.x < 0:
			continue
		var pos := world.cell_to_world(cell)
		if world.get_owner(cell) == target.id:
			rng_state = _rng.state
			return pos
		if fallback == Vector2.INF:
			fallback = pos
	rng_state = _rng.state
	if fallback != Vector2.INF:
		return fallback
	if is_instance_valid(target.castle):
		return target.castle.get_approach_point(center + Vector2(0, 1000))
	return center


func _parties() -> Array:
	var list: Array = []
	for k in game.kingdoms:
		if not k.defeated and (k.controller == "player" or k.controller == "ai"):
			list.append(k)
	return list


func _ai_kingdoms() -> Array:
	var list: Array = []
	for k in game.kingdoms:
		if not k.defeated and k.controller == "ai" and is_instance_valid(k.castle):
			list.append(k)
	return list


func _espionage() -> EspionageSystem:
	var esp: Variant = game.get("espionage_system")
	return esp as EspionageSystem if esp is EspionageSystem else null


## Text für das Auswahlfenster: Stufe, Erfahrung, Auftrag, Ziel, Fortschritt, Gefahr
func get_spy_text(u: Unit) -> String:
	if not is_spy(u):
		return ""
	var rec := get_record(u)
	var lines: PackedStringArray = []
	var next := xp_for_next(u)
	var xp_text := "%s/%s" % [_num(float(rec["xp"])), _num(next)] if next >= 0.0 else "%s (höchste Stufe)" % _num(float(rec["xp"]))
	lines.append("Spion Stufe %d · EP %s · %d Aufträge erfüllt" % [int(rec["level"]), xp_text, int(rec.get("missions_done", 0))])
	var mission := str(rec["mission"])
	var state := str(rec["state"])
	if mission.is_empty():
		lines.append("Kein Auftrag (%s) – Spionagefenster (K)" % state_name(state))
	else:
		var target: Kingdom = game.get_kingdom(int(rec["target_id"]))
		var text := "%s → %s" % [mission_name(mission), target.display_name if target != null else "?"]
		var other: Kingdom = game.get_kingdom(int(rec.get("target2_id", 0)))
		if other != null:
			text += (" gegen %s" if mission == "incite_village" else " und %s") % other.display_name
		text += " (%s" % state_name(state)
		if state == "active":
			text += ", %d %%" % roundi(float(rec["progress"]) * 100.0)
		lines.append(text + ")")
	if bool(rec.get("revealed", false)) and not u.stealthed:
		lines.append("Enttarnt – flieht heim!")
	var chance := detection_chance(u)
	if chance > 0.0:
		lines.append("Entdeckungsgefahr hier: ~%d %% je %d s" % [roundi(chance * 100.0), int(DataDB.esp("spies.detect_interval", 10))])
	return "\n".join(lines)


static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return str(roundi(v))
	return ("%.1f" % v).replace(".", ",")


# ---------------------------------------------------------------------------
# Niederlage und Speichern
# ---------------------------------------------------------------------------

## Ein Reich ist gefallen: seine Spione verschwinden (Datensätze); Aufträge gegen das
## Reich enden im nächsten Takt (Ziel ungültig)
func on_kingdom_defeated(k: Kingdom) -> void:
	if k == null:
		return
	for uid in spies.keys():
		if int((spies[uid] as Dictionary).get("owner_id", 0)) == k.id:
			spies.erase(uid)
	counters.erase(k.id)
	spies_changed.emit(k)


func to_dict() -> Dictionary:
	rng_state = _rng.state
	return {"spies": spies.duplicate(true), "counters": counters.duplicate(), "stats": stats.duplicate(),
			"rng_state": rng_state, "pending": _pending.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	spies = (d.get("spies", {}) as Dictionary).duplicate(true)
	counters = (d.get("counters", {}) as Dictionary).duplicate()
	stats = (d.get("stats", stats) as Dictionary).duplicate()
	rng_state = int(d.get("rng_state", rng_state))
	_pending = (d.get("pending", []) as Array).duplicate(true)


## Nach dem Laden: Datensätze ohne Einheit löschen, Reisen neu befehlen (idempotent)
func rebuild_runtime() -> void:
	_acc = 0.0
	_rng.state = rng_state
	var cmd: CommandSystem = game.command_system
	# Ankünfte, die beim Speichern noch nicht verarbeitet waren: nicht neu losschicken
	var arriving := {}
	for entry in _pending:
		arriving[int(entry[1])] = true
	for uid in spies.keys():
		var u: Variant = game.find_by_uid(int(uid))
		if not (u is Unit) or not (u as Unit).is_alive():
			spies.erase(uid)
			continue
		var spy: Unit = u
		var rec: Dictionary = spies[uid]
		match str(rec["state"]):
			"travel":
				if not spy.moving and not spy.path_pending and not arriving.has(spy.uid):
					cmd.order_travel(spy, rec["dest"], "infiltrate")
			"return":
				if not spy.moving and not spy.path_pending and not arriving.has(spy.uid):
					cmd.order_travel(spy, rec["dest"], "return")
