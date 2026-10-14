## HeroSystem
##
## Helden: sehr starke Generäle (heroes.json). Angeworben in der Heldenhalle
## (über die Beschwörungs-Warteschlange des SummonSystems), leveln durch Kämpfe,
## Einsätze (zerstörte Höhlen) und Ausbildung, wählen bei jedem Stufenaufstieg
## eine von zwei Verbesserungen, wirken Fähigkeiten und können nach dem Tod in der
## Burg wiederbelebt werden (gleiche Einheitennummer: bleiben in ihren Armeen).
##
## Zustand je Reich in Kingdom.heroes (einfache Einträge, speicherbar):
## {"id", "kingdom_id", "type_id", "name", "level", "xp" (EP in der aktuellen Stufe),
##  "ranks" {fähigkeit: rang}, "talents" [ids], "pending" (offene Stufenwahlen),
##  "unit_uid" (fest, auch im Tod), "dead", "died_at", "cooldowns" {fähigkeit: spielzeit},
##  "train_ready_at", "autocast" {fähigkeit: bool}, "revive_notified"}
## Alles andere (Werte der Einheit, Auren, Reichs-Zuschläge) ist abgeleitet und wird
## von _apply_hero bzw. rebuild_runtime neu aufgebaut.
## Quellen: Wirkungen auf Einheiten "ability:<fähigkeit>" (gleiche Aura stapelt nicht),
## Zuschläge des Reichs "ability:<fähigkeit>#<held>", Führung "ability:leadership".
## Gleiche Schnittstelle für Spieler und (ab Phase 7) KI-Reiche.
class_name HeroSystem
extends Node

signal hero_recruited(kingdom: Kingdom, hero_id: int)
signal hero_died(kingdom: Kingdom, hero_id: int)
signal hero_revived(kingdom: Kingdom, hero_id: int)
signal hero_leveled(kingdom: Kingdom, hero_id: int, level: int)
signal xp_gained(kingdom: Kingdom, hero_id: int, amount: int, reason: String)
signal ability_used(kingdom: Kingdom, hero_id: int, ability_id: String, pos: Vector2, radius_px: float)
## Liste oder Zustand der Helden eines Reichs hat sich geändert (Anwerben, Tod, Wahl, Entlassen …)
signal heroes_changed(kingdom: Kingdom)

const MAX_LEVEL := 10
## Auren und Führung werden einmal pro Spielsekunde erneuert und gelten so lange
const AURA_INTERVAL := 1.0
const AURA_SECONDS := 1.6
## Selbst auslösende Fähigkeiten werden so oft geprüft
const AUTOCAST_INTERVAL := 0.5
## Ein laufender Wirkbefehl läuft dem Ziel höchstens so oft neu hinterher
const CAST_REPATH_INTERVAL := 0.5

var game: Node
var world: WorldData
var _ts := 64.0
var _aura_timer := 0.0
var _autocast_timer := 0.0
var _rng := RandomNumberGenerator.new()
## uid -> Spielzeit der letzten Neuplanung eines Wirkbefehls (nur Laufzeit)
var _cast_repath_at: Dictionary = {}


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_ts = float(world.tile_size)
	_rng.seed = 90917
	GameClock.sim_tick.connect(_on_sim_tick)
	game.combat_system.unit_died.connect(_on_unit_died)
	game.combat_system.building_destroyed.connect(_on_building_destroyed)
	game.unit_system.unit_removed.connect(_on_unit_removed)
	game.summon_system.unit_summoned.connect(_on_unit_summoned)
	game.command_system.command_finished.connect(_on_command_finished)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

func get_heroes(k: Kingdom) -> Array:
	return k.heroes


func get_record(k: Kingdom, hero_id: int) -> Dictionary:
	for rec in k.heroes:
		if int(rec["id"]) == hero_id:
			return rec
	return {}


## Lebende Einheit des Helden, sonst null
func get_unit(k: Kingdom, hero_id: int) -> Unit:
	var rec := get_record(k, hero_id)
	if rec.is_empty() or bool(rec["dead"]):
		return null
	var u: Variant = game.find_by_uid(int(rec["unit_uid"]))
	if is_instance_valid(u) and u is Unit and u.is_alive():
		return u
	return null


## Eintrag zu einer Heldeneinheit ({} bei anderen Einheiten)
func find_record(u: Unit) -> Dictionary:
	if u == null or not is_instance_valid(u) or u.hero_id == 0:
		return {}
	return get_record(u.kingdom, u.hero_id)


func get_type(rec: Dictionary) -> Dictionary:
	return DataDB.get_hero_type(str(rec.get("type_id", "")))


## Talente des Helden als Definitionen (für Anzeigen; allgemeine können mehrfach vorkommen)
func get_talents(rec: Dictionary) -> Array:
	return _talents_of(rec)


## "Aldric (Paladin)"
func get_title(rec: Dictionary) -> String:
	return _title(rec)


## Fertige Heldenhalle des Reichs (oder null)
func get_hall(k: Kingdom) -> Building:
	for b in k.buildings:
		if b.constructed and bool(b.def.get("hero_hall", false)):
			return b
	return null


## Heldentypen, die das Reich anwerben kann (Einheitentypen): die der eigenen
## Fraktion und freigeschaltete ("hero:<id>", ab Phase 6 z. B. Bündnisse)
func get_offers(k: Kingdom) -> Array:
	var list: Array = []
	for h in DataDB.hero_types:
		var id := str(h["id"])
		if h["faction"] == k.faction_id or h["faction"] == "any" or k.has_unlock("hero:" + id):
			list.append(DataDB.get_unit_type(id))
	return list


func max_heroes(k: Kingdom) -> int:
	return int(DataDB.hero_cfg("max_heroes", 3)) + int(k.bonus("hero_slots"))


## Helden des Reichs (lebend und gefallen) plus die gerade angeworbenen
func count_heroes(k: Kingdom) -> int:
	return k.heroes.size() + _queued(k).size()


## Kosten für den nächsten Helden: Grundkosten + Zuschlag je vorhandenem Helden
func recruit_cost(k: Kingdom, type_id: String) -> Dictionary:
	var base: Dictionary = DataDB.get_hero_type(type_id).get("cost", {})
	var extra: Dictionary = DataDB.hero_cfg("cost_per_owned", {})
	var owned := count_heroes(k)
	var cost := {}
	for res in base:
		cost[res] = float(base[res])
	for res in extra:
		cost[res] = float(cost.get(res, 0.0)) + float(extra[res]) * owned
	return cost


## "" = kann angeworben werden (Halle, Platz, Typ), sonst der Grund. Kosten und
## Warteschlange prüft das SummonSystem.
func can_recruit(k: Kingdom, type_id: String) -> String:
	var h := DataDB.get_hero_type(type_id)
	if h.is_empty():
		return "Unbekannter Held"
	if not get_offers(k).has(DataDB.get_unit_type(type_id)):
		return "Dieser Held dient deinem Reich nicht"
	if _find_hall_any(k) == null:
		return "Baue zuerst eine %s" % DataDB.get_building_name(DataDB.get_building("hero_hall"), k.faction_id)
	if count_heroes(k) >= max_heroes(k):
		return "Höchstens %d Helden (gefallene zählen mit)" % max_heroes(k)
	if bool(DataDB.hero_cfg("unique_types", true)):
		for rec in k.heroes:
			if str(rec["type_id"]) == type_id:
				return "Dieser Held dient dir bereits"
		if _queued(k).has(type_id):
			return "Dieser Held wird gerade angeworben"
	return ""


## Anwerben: bezahlt und reiht den Helden in der Heldenhalle ein
func recruit(k: Kingdom, type_id: String) -> bool:
	var hall := get_hall(k)
	if hall == null:
		return false
	return game.summon_system.summon(hall, type_id)


## EP bis zur nächsten Stufe (0 = höchste Stufe)
func xp_for_next(rec: Dictionary) -> int:
	var level := int(rec["level"])
	var levels: Array = DataDB.hero_cfg("levels", [])
	if level >= MAX_LEVEL or level - 1 >= levels.size():
		return 0
	return int(levels[level - 1])


## Fortschritt in der aktuellen Stufe (0..1)
func level_progress(rec: Dictionary) -> float:
	var need := xp_for_next(rec)
	return 1.0 if need <= 0 else clampf(float(rec["xp"]) / float(need), 0.0, 1.0)


func get_rank(rec: Dictionary, ability_id: String) -> int:
	return int((rec["ranks"] as Dictionary).get(ability_id, 0))


## Werte einer Fähigkeit für diesen Helden (aktueller Rang, Talente eingerechnet):
## {"rank", "range", "radius" (Felder), "cooldown", "damage", "heal", "duration",
##  "unit_effects", "self_effects", "summon", "teleport", "aura", "stat", "mana_cap", "mana_regen", "filter"}
## Rang 0 (nicht gelernt): Werte von Rang 1, "rank" = 0.
func get_ability_values(rec: Dictionary, ability_id: String) -> Dictionary:
	var def := DataDB.get_ability(ability_id)
	if def.is_empty():
		return {}
	var rank := get_rank(rec, ability_id)
	var ranks: Array = def["ranks"]
	var rv: Dictionary = ranks[clampi(rank - 1, 0, ranks.size() - 1)] if not ranks.is_empty() else {}
	var v: Dictionary = rv.duplicate(true)
	v["rank"] = rank
	v["range"] = float(rv.get("range", def["range"]))
	v["radius"] = float(rv.get("radius", def["radius"]))
	v["cooldown"] = float(rv.get("cooldown", def["cooldown"]))
	v["damage"] = float(rv.get("damage", 0.0))
	v["heal"] = float(rv.get("heal", 0.0))
	v["duration"] = float(rv.get("duration", 0.0))
	# Talente, die diese Fähigkeit verbessern
	var effect_mult := 1.0
	for t in _talents_of(rec):
		if str(t.get("ability", "")) != ability_id:
			continue
		v["damage"] = float(v["damage"]) * float(t.get("damage_mult", 1.0))
		v["cooldown"] = float(v["cooldown"]) * float(t.get("cooldown_mult", 1.0))
		v["radius"] = float(v["radius"]) + float(t.get("radius_add", 0.0))
		v["range"] = float(v["range"]) + float(t.get("range_add", 0.0))
		effect_mult *= float(t.get("effect_mult", 1.0))
		if v.has("summon"):
			v["summon"]["count"] = int(v["summon"].get("count", 1)) + int(t.get("count_add", 0))
	if effect_mult != 1.0:
		for list_key in ["unit_effects", "self_effects"]:
			for e in v.get(list_key, []):
				if e.has("add"):
					e["add"] = float(e["add"]) * effect_mult
				if e.has("mult"):
					e["mult"] = 1.0 + (float(e["mult"]) - 1.0) * effect_mult
	return v


func cooldown_left(rec: Dictionary, ability_id: String) -> float:
	return maxf(float((rec["cooldowns"] as Dictionary).get(ability_id, 0.0)) - GameClock.game_time, 0.0)


## Wen trifft eine Fähigkeit? "enemy", "own" oder "" (Selbst, Sprung, Beschwörung)
func get_ability_side(ability_id: String) -> String:
	var def := DataDB.get_ability(ability_id)
	if def.is_empty() or (def["ranks"] as Array).is_empty():
		return ""
	var rv: Dictionary = def["ranks"][0]
	if float(rv.get("damage", 0.0)) > 0.0 or str(def["target"]) == "enemy":
		return "enemy"
	for e in rv.get("unit_effects", []):
		return "enemy" if str(e.get("side", "own")) == "enemy" else "own"
	return ""


## Einheiten, die eine Fähigkeit an dieser Stelle treffen würde (Zielanzeige, KI)
func get_ability_targets(u: Unit, ability_id: String, pos: Vector2) -> Array:
	var rec := find_record(u)
	if rec.is_empty():
		return []
	var def := DataDB.get_ability(ability_id)
	var v := get_ability_values(rec, ability_id)
	var side := get_ability_side(ability_id)
	if side.is_empty():
		return []
	var center := u.position if str(def["target"]) == "none" else pos
	var radius := float(v["radius"]) * _ts
	if str(def["target"]) == "enemy":
		var t := _enemy_at(u, pos)
		return [] if t == null else [t]
	var list: Array = []
	for w in game.magic_system.units_in(center, radius):
		if side == "enemy" and _is_enemy(u.kingdom, w):
			list.append(w)
		elif side == "own" and w.kingdom == u.kingdom and (w.joins_fights or w.can_heal()):
			list.append(w)
	return list


## Stufenwahl: die zwei Angebote für die nächste offene Wahl (leer, wenn keine offen)
## [{"id": "rank:<fähigkeit>" | "talent:<id>", "kind": "ability"|"talent", "ability_id",
##   "rank", "name", "text"}]
func get_levelup_options(k: Kingdom, hero_id: int) -> Array:
	var rec := get_record(k, hero_id)
	if rec.is_empty() or int(rec["pending"]) <= 0:
		return []
	# Die Wahl gehört zu dieser Stufe (bei mehreren offenen zur ältesten)
	var choice_level := int(rec["level"]) - int(rec["pending"]) + 1
	var options: Array = []
	var rank_opt := _rank_option(rec, choice_level)
	if not rank_opt.is_empty():
		options.append(rank_opt)
	var used: Array = []
	while options.size() < 2:
		var t := _talent_option(rec, choice_level, used)
		if t.is_empty():
			break
		used.append(t["id"])
		options.append(t)
	return options


## Kosten der Wiederbelebung (Mana gedeckelt)
func revive_cost(rec: Dictionary) -> Dictionary:
	var base: Dictionary = get_type(rec).get("cost", {})
	var f := float(DataDB.hero_cfg("revive_cost_factor", 0.5)) \
			* (1.0 + float(DataDB.hero_cfg("revive_level_factor", 0.1)) * (int(rec["level"]) - 1))
	var cost := {}
	for res in base:
		cost[res] = ceilf(float(base[res]) * f)
	if cost.has("mana"):
		cost["mana"] = minf(float(cost["mana"]), float(DataDB.hero_cfg("revive_mana_cap", 60)))
	return cost


## Sekunden, bis ein gefallener Held wiederbelebt werden kann (0 = jetzt)
func revive_ready_in(rec: Dictionary) -> float:
	if not bool(rec["dead"]):
		return 0.0
	var left := float(rec["died_at"]) + float(DataDB.hero_cfg("revive_delay", 60)) - GameClock.game_time
	# Rundungsreste (z. B. direkt nach debug_revive_now) zählen nicht
	return left if left > 0.001 else 0.0


## Höchste Stufe, bis zu der ausgebildet werden kann
func train_cap(k: Kingdom) -> int:
	return int(DataDB.hero_cfg("training.max_level", 5)) + int(k.bonus("hero_train_cap"))


# ---------------------------------------------------------------------------
# Fähigkeiten
# ---------------------------------------------------------------------------

## "" = kann jetzt hier gewirkt werden, sonst der Grund (deutsch).
## ignore_range: Reichweite nicht prüfen (order_ability läuft erst hin).
func can_use(u: Unit, ability_id: String, target: Variant = null, ignore_range: bool = false) -> String:
	if u == null or not is_instance_valid(u) or not u.is_alive():
		return "Der Held lebt nicht"
	var rec := find_record(u)
	if rec.is_empty():
		return "Kein Held"
	var def := DataDB.get_ability(ability_id)
	if def.is_empty() or not (get_type(rec).get("abilities", []) as Array).has(ability_id):
		return "Unbekannte Fähigkeit"
	if get_rank(rec, ability_id) <= 0:
		return "Noch nicht gelernt"
	if str(def["kind"]) != "active":
		return "Wirkt von selbst (passiv)"
	if u.inside != null:
		return "Der Held ist in einem Gebäude"
	var cd := cooldown_left(rec, ability_id)
	if cd > 0.0:
		return "Bereit in %d s" % ceili(cd)
	var v := get_ability_values(rec, ability_id)
	var range_px := float(v["range"]) * _ts
	match str(def["target"]):
		"enemy":
			var t: Variant = target
			if not (is_instance_valid(t) and t is Unit and t.is_alive() and _is_enemy(u.kingdom, t)):
				return "Wähle einen Feind als Ziel"
			if not ignore_range and u.position.distance_to(t.position) > range_px + t.get_radius() + u.get_radius():
				return "Zu weit – höchstens %s Felder" % ResourceBar.format_number(float(v["range"]))
			if bool(v.get("teleport", false)) and _jump_cell(u, t.position, true).x < 0:
				return "Dort kann der Held nicht hin"
		"point":
			if not (target is Vector2):
				return "Wähle eine Stelle"
			var p: Vector2 = target
			if not ignore_range and u.position.distance_to(p) > range_px:
				return "Zu weit – höchstens %s Felder" % ResourceBar.format_number(float(v["range"]))
			if bool(v.get("teleport", false)):
				if ignore_range and u.position.distance_to(p) > range_px:
					return "Zu weit – höchstens %s Felder" % ResourceBar.format_number(float(v["range"]))
				if _jump_cell(u, p, false).x < 0:
					return "Dort kann der Held nicht hin"
	return ""


## Wirkt eine Fähigkeit sofort (Ziel in Reichweite). target: Unit (enemy),
## Vector2 (point) oder null (self/none). Gibt true zurück, wenn gewirkt.
func use_ability(u: Unit, ability_id: String, target: Variant = null) -> bool:
	if not can_use(u, ability_id, target).is_empty():
		return false
	var rec := find_record(u)
	var k := u.kingdom
	var def := DataDB.get_ability(ability_id)
	var v := get_ability_values(rec, ability_id)
	var now := GameClock.game_time
	var source := "ability:" + ability_id
	var radius_px := float(v["radius"]) * _ts
	var center := u.position
	# Angriffe heben die Tarnung auf
	if get_ability_side(ability_id) == "enemy":
		game.magic_system.reveal(u)
	match str(def["target"]):
		"enemy":
			var t: Unit = target
			center = t.position
			if bool(v.get("teleport", false)):
				_teleport(u, _jump_cell(u, t.position, true))
			if float(v["damage"]) > 0.0:
				game.combat_system.ability_damage(t, float(v["damage"]), u)
			if is_instance_valid(t) and t.is_alive():
				for e in v.get("unit_effects", []):
					_add_effect(t, k, source, e, now + float(v["duration"]), int(rec["id"]))
			# Der Held kämpft danach gegen dieses Ziel weiter
			if is_instance_valid(t) and t.is_alive() and u.command != "move" and u.command != "flee":
				u.target = t
		"point":
			center = target
			if bool(v.get("teleport", false)):
				_teleport(u, _jump_cell(u, center, false))
				center = u.position
			_area(u, rec, v, source, center, radius_px, now, bool(def.get("buildings", false)))
		"self":
			for e in v.get("self_effects", []):
				_add_effect(u, k, source, e, now + float(v["duration"]), int(rec["id"]))
		_:
			_area(u, rec, v, source, center, radius_px, now, bool(def.get("buildings", false)))
	(rec["cooldowns"] as Dictionary)[ability_id] = now + float(v["cooldown"])
	ability_used.emit(k, int(rec["id"]), ability_id, center, radius_px)
	return true


## Wirkt die Fähigkeit – ist das Ziel zu weit, läuft der Held erst hin (Befehl "cast").
## "" = gewirkt oder unterwegs, sonst der Grund.
func order_ability(u: Unit, ability_id: String, target: Variant = null) -> String:
	var reason := can_use(u, ability_id, target, true)
	if not reason.is_empty():
		return reason
	if can_use(u, ability_id, target).is_empty():
		use_ability(u, ability_id, target)
		return ""
	u.cast_ability = ability_id
	u.cast_target_uid = 0
	u.cast_pos = u.position
	if target is Unit:
		u.cast_target_uid = target.uid
		u.cast_pos = target.position
	elif target is Vector2:
		u.cast_pos = target
	game.command_system.order_cast(u, u.cast_pos)
	_cast_repath_at[u.uid] = GameClock.game_time
	return ""


## Selbst auslösen an/aus (Rechtsklick auf den Knopf)
func set_autocast(k: Kingdom, hero_id: int, ability_id: String, on: bool) -> void:
	var rec := get_record(k, hero_id)
	if rec.is_empty():
		return
	(rec["autocast"] as Dictionary)[ability_id] = on
	heroes_changed.emit(k)


func is_autocast(rec: Dictionary, ability_id: String) -> bool:
	return bool((rec["autocast"] as Dictionary).get(ability_id, false))


## Was der Held jetzt von selbst wirken würde: {"ability_id", "target"} oder {}.
## (Auch für die KI ab Phase 7.)
func pick_auto_cast(u: Unit) -> Dictionary:
	var rec := find_record(u)
	if rec.is_empty() or u.inside != null or u.command in ["move", "flee", "cast", "return"]:
		return {}
	for aid in get_type(rec).get("abilities", []):
		var ability_id := str(aid)
		if not is_autocast(rec, ability_id) or get_rank(rec, ability_id) <= 0 or cooldown_left(rec, ability_id) > 0.0:
			continue
		var def := DataDB.get_ability(ability_id)
		match str(def["target"]):
			"enemy":
				var t: Variant = u.target
				if is_instance_valid(t) and t is Unit and can_use(u, ability_id, t).is_empty():
					return {"ability_id": ability_id, "target": t}
			"none":
				if not get_ability_targets(u, ability_id, u.position).is_empty():
					return {"ability_id": ability_id, "target": null}
	return {}


# ---------------------------------------------------------------------------
# Stufen, Wiederbelebung, Ausbildung
# ---------------------------------------------------------------------------

## Einziger Weg zu Erfahrung (Kämpfe, Einsätze, Ausbildung, ab Phase 6 Aufträge).
## Der Faktor "hero_xp" des Reichs (Forschung) wird eingerechnet.
func add_xp(k: Kingdom, hero_id: int, amount: int, reason: String = "") -> void:
	var rec := get_record(k, hero_id)
	if rec.is_empty() or amount <= 0 or int(rec["level"]) >= MAX_LEVEL:
		return
	var gained := maxi(roundi(amount * k.mod("hero_xp")), 1)
	rec["xp"] = int(rec["xp"]) + gained
	xp_gained.emit(k, hero_id, gained, reason)
	while int(rec["level"]) < MAX_LEVEL and xp_for_next(rec) > 0 and int(rec["xp"]) >= xp_for_next(rec):
		rec["xp"] = int(rec["xp"]) - xp_for_next(rec)
		rec["level"] = int(rec["level"]) + 1
		rec["pending"] = int(rec["pending"]) + 1
		_on_level_up(k, rec)
	if int(rec["level"]) >= MAX_LEVEL:
		rec["xp"] = 0


## Eine der angebotenen Verbesserungen wählen
func choose_upgrade(k: Kingdom, hero_id: int, option_id: String) -> bool:
	var rec := get_record(k, hero_id)
	if rec.is_empty():
		return false
	var chosen: Dictionary = {}
	for o in get_levelup_options(k, hero_id):
		if str(o["id"]) == option_id:
			chosen = o
	if chosen.is_empty():
		return false
	if str(chosen["kind"]) == "ability":
		(rec["ranks"] as Dictionary)[str(chosen["ability_id"])] = int(chosen["rank"])
		# Neu gelernte selbst auslösende Fähigkeiten gleich einschalten
		if int(chosen["rank"]) == 1 and bool(DataDB.get_ability(str(chosen["ability_id"])).get("autocast", false)):
			(rec["autocast"] as Dictionary)[str(chosen["ability_id"])] = true
	else:
		(rec["talents"] as Array).append(str(chosen["id"]).trim_prefix("talent:"))
	rec["pending"] = int(rec["pending"]) - 1
	_apply_hero(rec)
	heroes_changed.emit(k)
	return true


func can_revive(k: Kingdom, hero_id: int) -> String:
	var rec := get_record(k, hero_id)
	if rec.is_empty():
		return "Unbekannter Held"
	if not bool(rec["dead"]):
		return "Der Held lebt"
	var wait := revive_ready_in(rec)
	if wait > 0.0:
		return "Wiederbelebung in %d s möglich" % ceili(wait)
	if not is_instance_valid(k.castle):
		return "Keine Burg"
	return k.missing_text(revive_cost(rec))


## Belebt einen gefallenen Helden an der Burg wieder (gleiche Stufe, volle Leben)
func revive(k: Kingdom, hero_id: int) -> bool:
	if not can_revive(k, hero_id).is_empty():
		return false
	var rec := get_record(k, hero_id)
	if not k.spend(revive_cost(rec)):
		return false
	var u := _spawn_hero(k, rec, k.castle.get_approach_point(k.castle.get_center() + Vector2(0, 1000)))
	if u == null:
		k.refund(revive_cost(rec))
		return false
	rec["dead"] = false
	hero_revived.emit(k, int(rec["id"]))
	heroes_changed.emit(k)
	k.notify("%s ist wiederbelebt" % _title(rec), "good", u.position)
	return true


func can_train(k: Kingdom, hero_id: int) -> String:
	var rec := get_record(k, hero_id)
	if rec.is_empty():
		return "Unbekannter Held"
	if bool(rec["dead"]):
		return "Gefallene Helden können nicht ausgebildet werden"
	if get_hall(k) == null:
		return "Braucht eine fertige %s" % DataDB.get_building_name(DataDB.get_building("hero_hall"), k.faction_id)
	if int(rec["level"]) >= train_cap(k):
		return "Ausbildung nur bis Stufe %d – danach nur noch im Kampf" % train_cap(k)
	var wait := float(rec["train_ready_at"]) - GameClock.game_time
	if wait > 0.0:
		return "Nächste Ausbildung in %d s" % ceili(wait)
	return k.missing_text(DataDB.hero_cfg("training.cost", {}))


## Ausbildung in der Heldenhalle: Rohstoffe gegen Erfahrung
func train(k: Kingdom, hero_id: int) -> bool:
	if not can_train(k, hero_id).is_empty():
		return false
	var rec := get_record(k, hero_id)
	if not k.spend(DataDB.hero_cfg("training.cost", {})):
		return false
	rec["train_ready_at"] = GameClock.game_time + float(DataDB.hero_cfg("training.cooldown", 60))
	add_xp(k, hero_id, int(DataDB.hero_cfg("training.xp", 80)), "training")
	heroes_changed.emit(k)
	return true


## Entlässt einen Helden (gibt den Platz frei; nichts wird erstattet)
func dismiss(k: Kingdom, hero_id: int) -> void:
	var rec := get_record(k, hero_id)
	if rec.is_empty():
		return
	rec["dismissing"] = true
	var u := get_unit(k, hero_id)
	if u != null:
		game.unit_system.remove_unit(u)
	game.command_system.remove_from_armies(k, int(rec["unit_uid"]))
	_clear_kingdom_bonuses(k, rec)
	k.heroes.erase(rec)
	heroes_changed.emit(k)
	k.notify("%s hat dein Reich verlassen" % _title(rec), "info")


## Gespeicherter Zustand (Phase 10); die Helden selbst stehen in Kingdom.heroes
func to_dict() -> Dictionary:
	return {"rng": _rng.state, "aura_timer": _aura_timer, "autocast_timer": _autocast_timer}


func from_dict(d: Dictionary) -> void:
	_rng.state = int(d.get("rng", _rng.state))
	_aura_timer = float(d.get("aura_timer", 0.0))
	_autocast_timer = float(d.get("autocast_timer", 0.0))


## Nach dem Laden (Phase 10): abgeleitete Werte neu aufbauen (beliebig oft aufrufbar)
func rebuild_runtime() -> void:
	_cast_repath_at.clear()
	for k in game.kingdoms:
		for src in k.bonus_sources.keys():
			if str(src).begins_with("ability:"):
				k.clear_bonuses(str(src))
		for rec in k.heroes:
			var u: Variant = game.find_by_uid(int(rec["unit_uid"]))
			if not bool(rec["dead"]) and is_instance_valid(u) and u is Unit:
				u.hero_id = int(rec["id"])
			_apply_hero(rec)


# ---------------------------------------------------------------------------
# Debug (F3): zum Testen ohne lange Kämpfe
# ---------------------------------------------------------------------------

func debug_level_up(k: Kingdom, hero_id: int) -> void:
	var rec := get_record(k, hero_id)
	if not rec.is_empty() and int(rec["level"]) < MAX_LEVEL:
		add_xp(k, hero_id, maxi(xp_for_next(rec) - int(rec["xp"]), 1), "debug")


func debug_reset_cooldowns(k: Kingdom, hero_id: int) -> void:
	var rec := get_record(k, hero_id)
	if not rec.is_empty():
		(rec["cooldowns"] as Dictionary).clear()
		heroes_changed.emit(k)


## Wiederbelebung sofort möglich machen (Wartezeit überspringen)
func debug_revive_now(k: Kingdom, hero_id: int) -> void:
	var rec := get_record(k, hero_id)
	if not rec.is_empty() and bool(rec["dead"]):
		rec["died_at"] = GameClock.game_time - float(DataDB.hero_cfg("revive_delay", 60)) - 0.01


## Der Held fällt (über den normalen Schadensweg)
func debug_kill(k: Kingdom, hero_id: int) -> void:
	var u := get_unit(k, hero_id)
	if u != null:
		game.combat_system.apply_damage(u, u.hp + 1.0, null, null, "event")


# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	var now := GameClock.game_time
	_tick_casts(now)
	_aura_timer -= dt
	if _aura_timer <= 0.0:
		_aura_timer = AURA_INTERVAL
		_tick_auras(now)
		_tick_revive_notes()
	_autocast_timer -= dt
	if _autocast_timer <= 0.0:
		_autocast_timer = AUTOCAST_INTERVAL
		_tick_autocast()


## Laufende Wirkbefehle: in Reichweite wirken, sonst dem Ziel folgen
func _tick_casts(now: float) -> void:
	for k in game.kingdoms:
		for rec in k.heroes:
			var u := get_unit(k, int(rec["id"]))
			if u == null or u.cast_ability.is_empty():
				continue
			if u.command != "cast":
				_clear_cast(u)
				continue
			var target: Variant = _cast_target(u)
			if target == null:
				# Ziel weg (tot, unsichtbar): aufgeben und stehen bleiben
				_clear_cast(u)
				game.command_system.order_stop([u])
				continue
			if can_use(u, u.cast_ability, target).is_empty():
				var ability_id := u.cast_ability
				_clear_cast(u)
				game.unit_system.stop(u)
				u.command = "hold"
				u.command_pos = u.position
				use_ability(u, ability_id, target)
			elif target is Unit and now - float(_cast_repath_at.get(u.uid, 0.0)) >= CAST_REPATH_INTERVAL \
					and target.position.distance_to(u.cast_pos) > _ts:
				# Das Ziel bewegt sich: hinterher
				_cast_repath_at[u.uid] = now
				u.cast_pos = target.position
				u.command_pos = target.position
				game.unit_system.move_to(u, target.position, true)


## Am Ziel angekommen (oder Weg gescheitert): einmal versuchen, dann aufgeben
func _on_command_finished(u: Unit, cmd: String, _ok: bool) -> void:
	if cmd != "cast" or not is_instance_valid(u) or u.cast_ability.is_empty():
		return
	var ability_id := u.cast_ability
	var target: Variant = _cast_target(u)
	_clear_cast(u)
	if target != null and can_use(u, ability_id, target).is_empty():
		use_ability(u, ability_id, target)


## Auren: Führung (alle Helden), passive Auren; einmal pro Sekunde, kurz gültig.
## Niedrige Stufen zuerst: bei Überschneidung gilt die Führung des stärksten Helden.
func _tick_auras(now: float) -> void:
	var until := now + AURA_SECONDS
	var lead_radius := float(DataDB.hero_cfg("leadership.radius", 6)) * _ts
	var ms: MagicSystem = game.magic_system
	for k in game.kingdoms:
		if k.heroes.is_empty():
			continue
		var list: Array = k.heroes.duplicate()
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["level"]) < int(b["level"]))
		for rec in list:
			var u := get_unit(k, int(rec["id"]))
			if u == null or u.inside != null:
				continue
			var hid := int(rec["id"])
			# Führung: + Angriff für eigene Truppen (wächst mit der Stufe)
			var lead_mult := 1.0 + float(DataDB.hero_cfg("leadership.attack_base", 0.05)) \
					+ float(DataDB.hero_cfg("leadership.attack_per_level", 0.01)) * int(rec["level"])
			for t in _talents_of(rec):
				var lead: Dictionary = t.get("leadership", {})
				if str(lead.get("key", "")) == "attack":
					lead_mult *= float(lead.get("mult", 1.0))
			ms.apply_area_effects(k, "ability:leadership", [{"side": "own_kingdom", "key": "attack", "mult": lead_mult}],
					u.position, lead_radius, until, 1.0, hid, true, true, "fighters", u.uid)
			# Führungs-Eigenschaft des Heldentyps
			var trait_effects: Array = get_type(rec).get("leadership", [])
			if not trait_effects.is_empty():
				ms.apply_area_effects(k, "ability:leadership_" + str(rec["type_id"]), trait_effects, u.position,
						lead_radius, until, 1.0, hid, true, true, "fighters", u.uid)
			# Passive Auren (Heilige Aura, Fluchaura)
			for aid in get_type(rec).get("abilities", []):
				var ability_id := str(aid)
				if get_rank(rec, ability_id) <= 0:
					continue
				var v := get_ability_values(rec, ability_id)
				if not v.has("aura"):
					continue
				var aura: Dictionary = v["aura"]
				ms.apply_area_effects(k, "ability:" + ability_id, aura.get("effects", []), u.position,
						float(v["radius"]) * _ts, until, 1.0, hid, true, true, str(aura.get("filter", "")))


## Meldung, sobald ein gefallener Held wiederbelebt werden kann
func _tick_revive_notes() -> void:
	for k in game.kingdoms:
		for rec in k.heroes:
			if bool(rec["dead"]) and not bool(rec.get("revive_notified", false)) and revive_ready_in(rec) <= 0.0:
				rec["revive_notified"] = true
				# Klick auf die Meldung öffnet das Heldenfenster bei diesem Helden
				k.notify("%s kann in der Burg wiederbelebt werden (Klick oder G)" % _title(rec), "info",
						{"window": "heroes", "hero_id": int(rec["id"])})
				heroes_changed.emit(k)


func _tick_autocast() -> void:
	for k in game.kingdoms:
		for rec in k.heroes:
			var u := get_unit(k, int(rec["id"]))
			if u == null:
				continue
			var pick := pick_auto_cast(u)
			if not pick.is_empty():
				use_ability(u, str(pick["ability_id"]), pick["target"])


## Neuer Held aus der Heldenhalle: Eintrag anlegen
func _on_unit_summoned(u: Unit, _b: Building) -> void:
	if u.role != "hero" or u.hero_id != 0:
		return
	var k := u.kingdom
	var h := DataDB.get_hero_type(u.type_id)
	var first := str((h.get("abilities", []) as Array)[0]) if not (h.get("abilities", []) as Array).is_empty() else ""
	var rec := {"id": game.next_uid(), "kingdom_id": k.id, "type_id": u.type_id, "name": _pick_name(k),
			"level": 1, "xp": 0, "ranks": {}, "talents": [], "pending": 0, "unit_uid": u.uid,
			"dead": false, "died_at": 0.0, "cooldowns": {}, "train_ready_at": 0.0, "autocast": {},
			"revive_notified": false}
	if not first.is_empty():
		rec["ranks"][first] = 1
		rec["autocast"][first] = bool(DataDB.get_ability(first).get("autocast", false))
	k.heroes.append(rec)
	u.hero_id = int(rec["id"])
	_apply_hero(rec)
	u.hp = u.max_hp
	hero_recruited.emit(k, int(rec["id"]))
	heroes_changed.emit(k)
	k.notify("Held angeworben: %s" % _title(rec), "good", u.position)


## Einziger Ort, an dem der Tod eines Helden verbucht wird (Einheit entfernt mit 0 Leben)
func _on_unit_removed(u: Unit) -> void:
	if u.hero_id == 0:
		return
	_cast_repath_at.erase(u.uid)
	var k := u.kingdom
	var rec := get_record(k, u.hero_id)
	if rec.is_empty() or bool(rec.get("dismissing", false)) or u.hp > 0.0:
		return
	rec["dead"] = true
	rec["died_at"] = GameClock.game_time
	rec["cooldowns"] = {}
	rec["revive_notified"] = false
	_clear_kingdom_bonuses(k, rec)
	hero_died.emit(k, int(rec["id"]))
	heroes_changed.emit(k)
	var at: Variant = u.position
	k.notify("%s ist gefallen – in %d s kann er in der Burg wiederbelebt werden" % [_title(rec),
			int(DataDB.hero_cfg("revive_delay", 60))], "danger", at)


## Erfahrung für besiegte Feinde: alle eigenen Helden in der Nähe
func _on_unit_died(u: Unit, killer: Kingdom) -> void:
	if killer == null or killer.heroes.is_empty() or u.expires_at >= 0.0 or u.kingdom == killer:
		return
	var points := int(u.type_def.get("kill_points", 0)) + u.kill_points_bonus
	_share_xp(killer, u.position, points * int(DataDB.hero_cfg("xp_per_kill_point", 10)), "kill")


func _on_building_destroyed(b: Building, killer: Kingdom) -> void:
	if killer == null or killer.heroes.is_empty() or b.kingdom == killer:
		return
	var xp := float(b.def.get("kill_points", 0)) * float(DataDB.hero_cfg("xp_per_kill_point", 10))
	if str(b.def.get("id", "")) == "monster_lair":
		xp *= float(DataDB.hero_cfg("lair_xp_factor", 1.5))
	_share_xp(killer, b.get_center(), roundi(xp), "mission")


func _share_xp(k: Kingdom, pos: Vector2, xp: int, reason: String) -> void:
	if xp <= 0:
		return
	var radius := float(DataDB.hero_cfg("xp_share_radius", 10)) * _ts
	var near: Array = []
	for rec in k.heroes:
		var hu := get_unit(k, int(rec["id"]))
		if hu != null and hu.position.distance_to(pos) <= radius:
			near.append(int(rec["id"]))
	if near.is_empty():
		return
	var shares: Array = DataDB.hero_cfg("xp_share", [1.0, 0.6, 0.45])
	var f := float(shares[mini(near.size(), shares.size()) - 1])
	for hid in near:
		add_xp(k, int(hid), maxi(roundi(xp * f), 1), reason)


# ---------------------------------------------------------------------------
# Intern
# ---------------------------------------------------------------------------

func _on_level_up(k: Kingdom, rec: Dictionary) -> void:
	_apply_hero(rec)
	var u := get_unit(k, int(rec["id"]))
	if u != null:
		game.combat_system.heal_unit(u, u.max_hp * float(DataDB.hero_cfg("level_heal", 0.3)))
	hero_leveled.emit(k, int(rec["id"]), int(rec["level"]))
	heroes_changed.emit(k)
	# Klick auf die Meldung öffnet das Heldenfenster mit der Stufenwahl
	k.notify("%s erreicht Stufe %d – wähle eine Verbesserung (Klick oder G)" % [_title(rec), int(rec["level"])],
			"good", {"window": "heroes", "hero_id": int(rec["id"])})


## Abgeleitete Werte eines Helden setzen: Stufenwachstum, Talente und passive
## Fähigkeiten (hero_mods), Kampfpunkte, Name; Mana-Zuschläge des Reichs
func _apply_hero(rec: Dictionary) -> void:
	var k: Kingdom = game.get_kingdom(int(rec["kingdom_id"]))
	if k == null:
		return
	var level := int(rec["level"])
	var mods := {}
	var growth: Dictionary = DataDB.hero_cfg("growth", {})
	for key in growth:
		var m := pow(1.0 + float(growth[key]), level - 1)
		if level > 1:
			_mod_part(mods, str(key), "Stufe %d" % level, 0.0, m)
	for t in _talents_of(rec):
		var st: Dictionary = t.get("stat", {})
		for key in st:
			_mod_part(mods, str(key), str(t.get("name", "")), float(st[key].get("add", 0.0)), float(st[key].get("mult", 1.0)))
	_clear_kingdom_bonuses(k, rec)
	var alive := not bool(rec["dead"])
	for aid in get_type(rec).get("abilities", []):
		var ability_id := str(aid)
		if get_rank(rec, ability_id) <= 0:
			continue
		var v := get_ability_values(rec, ability_id)
		var aname := str(DataDB.get_ability(ability_id).get("name", ability_id))
		var st: Dictionary = v.get("stat", {})
		for key in st:
			_mod_part(mods, str(key), aname, float(st[key].get("add", 0.0)), float(st[key].get("mult", 1.0)))
		# Zuschläge des Reichs nur, solange der Held lebt
		if alive:
			var src := "ability:%s#%d" % [ability_id, int(rec["id"])]
			if v.has("mana_cap"):
				k.set_bonus(src, "cap.mana", float(v["mana_cap"]))
			if v.has("mana_regen"):
				k.set_bonus(src, "mana_regen", float(v["mana_regen"]))
	var u: Variant = game.find_by_uid(int(rec["unit_uid"]))
	if alive and is_instance_valid(u) and u is Unit:
		u.hero_mods = mods
		u.custom_name = str(rec["name"])
		u.kill_points_bonus = int(DataDB.hero_cfg("hero_kill_points_base", 10)) \
				+ int(DataDB.hero_cfg("hero_kill_points_per_level", 2)) * level
		u.refresh_stats()


func _mod_part(mods: Dictionary, key: String, label: String, add: float, mult: float) -> void:
	var m: Dictionary = mods.get(key, {"add": 0.0, "mult": 1.0, "parts": []})
	m["add"] = float(m["add"]) + add
	m["mult"] = float(m["mult"]) * mult
	(m["parts"] as Array).append([label, add, mult])
	mods[key] = m


func _clear_kingdom_bonuses(k: Kingdom, rec: Dictionary) -> void:
	var suffix := "#%d" % int(rec["id"])
	for src in k.bonus_sources.keys():
		if str(src).begins_with("ability:") and str(src).ends_with(suffix):
			k.clear_bonuses(str(src))


## Talente des Helden als Definitionen (eigene und allgemeine, wiederholbare)
func _talents_of(rec: Dictionary) -> Array:
	var list: Array = []
	for tid in rec["talents"]:
		var t := _talent_def(rec, str(tid))
		if not t.is_empty():
			list.append(t)
	return list


func _talent_def(rec: Dictionary, tid: String) -> Dictionary:
	for t in get_type(rec).get("talents", []):
		if str(t.get("id", "")) == tid:
			return t
	for t in DataDB.hero_cfg("generic_talents", []):
		if str(t.get("id", "")) == tid:
			return t
	return {}


## Angebot "nächster Rang": zuerst noch nicht gelernte Fähigkeiten, dann der
## niedrigste Rang, jeweils erst ab der nötigen Heldenstufe (rank_min_level)
func _rank_option(rec: Dictionary, choice_level: int) -> Dictionary:
	var min_levels: Array = DataDB.hero_cfg("rank_min_level", [1, 3, 6])
	var best: Dictionary = {}
	var best_rank := 99
	for aid in get_type(rec).get("abilities", []):
		var ability_id := str(aid)
		var rank := get_rank(rec, ability_id)
		var max_rank := (DataDB.get_ability(ability_id)["ranks"] as Array).size()
		if rank >= max_rank or rank >= min_levels.size() or choice_level < int(min_levels[rank]):
			continue
		if rank < best_rank:
			best_rank = rank
			var def := DataDB.get_ability(ability_id)
			best = {"id": "rank:" + ability_id, "kind": "ability", "ability_id": ability_id, "rank": rank + 1,
					"name": "%s %s" % [str(def.get("name", ability_id)), _roman(rank + 1)],
					"text": ("Neue Fähigkeit: " if rank == 0 else "Stärker: ") + str(def.get("description", ""))}
	return best


## Angebot "Talent": zufällig (fest je Held und Stufe) aus den noch nicht gewählten
## Talenten des Helden, sonst ein allgemeines (Stärke/Ausdauer)
func _talent_option(rec: Dictionary, choice_level: int, exclude: Array) -> Dictionary:
	var pool: Array = []
	for t in get_type(rec).get("talents", []):
		var tid := str(t.get("id", ""))
		if not (rec["talents"] as Array).has(tid) and not exclude.has("talent:" + tid):
			pool.append(t)
	if pool.is_empty():
		for t in DataDB.hero_cfg("generic_talents", []):
			if not exclude.has("talent:" + str(t.get("id", ""))):
				pool.append(t)
	if pool.is_empty():
		return {}
	_rng.seed = int(rec["id"]) * 7919 + choice_level * 104729 + exclude.size() * 31
	var t: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
	return {"id": "talent:" + str(t.get("id", "")), "kind": "talent", "ability_id": "", "rank": 0,
			"name": str(t.get("name", "")), "text": str(t.get("text", ""))}


func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV"][clampi(n, 0, 4)]


## Fläche um center: Schaden an Feinden, Wirkungen, Beschwörung, Heilung
func _area(u: Unit, rec: Dictionary, v: Dictionary, source: String, center: Vector2, radius_px: float, now: float,
		hit_buildings: bool) -> void:
	var k := u.kingdom
	var ms: MagicSystem = game.magic_system
	if float(v["damage"]) > 0.0 and radius_px > 0.0:
		for w in ms.units_in(center, radius_px):
			if _is_enemy(k, w):
				game.combat_system.ability_damage(w, float(v["damage"]), u)
		if hit_buildings:
			for other in game.kingdoms:
				if not game.are_hostile(k, other):
					continue
				for b in other.buildings:
					if b.get_center().distance_to(center) <= radius_px + b.get_radius():
						game.combat_system.ability_damage(b, float(v["damage"]), u)
	if float(v["heal"]) > 0.0:
		for w in ms.units_in(center, radius_px):
			if w.kingdom == k:
				game.combat_system.heal_unit(w, float(v["heal"]))
	var effects: Array = v.get("unit_effects", [])
	if not effects.is_empty():
		ms.apply_area_effects(k, source, effects, center, radius_px, now + float(v["duration"]), 1.0,
				int(rec["id"]), false, true, str(v.get("filter", "")))
	if v.has("summon"):
		var s: Dictionary = v["summon"]
		ms.summon_units(k, str(s.get("unit", "")), int(s.get("count", 1)), center, now + float(v["duration"]))


func _add_effect(target: Unit, k: Kingdom, source: String, e: Dictionary, until: float, ref: int) -> void:
	var key := str(e.get("key", ""))
	game.magic_system.add_unit_effect(target, {"id": "%s:%s" % [source, key], "key": key,
			"mult": float(e.get("mult", 1.0)), "add": float(e.get("add", 0.0)), "until": until,
			"source": source, "kingdom_id": k.id, "ref": ref})


func _is_enemy(k: Kingdom, w: Variant) -> bool:
	return is_instance_valid(w) and w is Unit and w.is_alive() and w.inside == null \
			and game.are_hostile(k, w.kingdom) and game.can_see(k, w)


## Feind an/nahe der Stelle (für Fähigkeiten mit Einzelziel)
func _enemy_at(u: Unit, pos: Vector2) -> Unit:
	var best: Unit = null
	var best_d := INF
	for w in game.magic_system.units_in(pos, _ts * 0.8):
		if _is_enemy(u.kingdom, w):
			var d: float = w.position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = w
	return best


## Sprungziel: freie, erreichbare Kachel bei pos (beside = neben einem Feind).
## (-1, -1), wenn keine.
func _jump_cell(u: Unit, pos: Vector2, beside: bool) -> Vector2i:
	var spot := pos
	if beside:
		var dir := (u.position - pos)
		spot = pos + (dir.normalized() if dir.length() > 1.0 else Vector2.RIGHT) * _ts * 0.9
	var c: Vector2i = game.nav.nearest_free(world.world_to_cell(spot), 2)
	if c.x < 0 or not game.nav.same_area(world.world_to_cell(u.position), c):
		return Vector2i(-1, -1)
	return c


func _teleport(u: Unit, cell: Vector2i) -> void:
	if cell.x < 0:
		return
	# Marsch und Wege beenden, dann versetzen
	game.command_system.order_stop([u])
	u.position = world.cell_to_world(cell)
	u.command_pos = u.position
	game.combat_system.mark_index_dirty()


func _cast_target(u: Unit) -> Variant:
	var def := DataDB.get_ability(u.cast_ability)
	match str(def.get("target", "")):
		"enemy":
			var t: Variant = game.find_by_uid(u.cast_target_uid)
			return t if _is_enemy(u.kingdom, t) else null
		"point":
			return u.cast_pos
	return null


func _clear_cast(u: Unit) -> void:
	u.cast_ability = ""
	u.cast_target_uid = 0
	_cast_repath_at.erase(u.uid)


func _spawn_hero(k: Kingdom, rec: Dictionary, pos: Vector2) -> Unit:
	var hid := int(rec["id"])
	var u: Unit = game.unit_system.spawn_unit(k, str(rec["type_id"]), pos, int(rec["unit_uid"]),
			func(nu: Unit) -> void: nu.hero_id = hid)
	if u == null:
		return null
	rec["dead"] = false
	_apply_hero(rec)
	u.hp = u.max_hp
	u.command = "hold"
	u.command_pos = u.position
	return u


## Name, der im Reich noch frei ist
func _pick_name(k: Kingdom) -> String:
	var names: Array = DataDB.hero_cfg("names.%s" % k.faction_id, [])
	var free: Array = []
	for n in names:
		var used := false
		for rec in k.heroes:
			if str(rec["name"]) == str(n):
				used = true
		if not used:
			free.append(str(n))
	if free.is_empty():
		return "Held %d" % (k.heroes.size() + 1)
	_rng.seed = k.id * 131 + k.heroes.size() * 977 + int(GameClock.game_time)
	return free[_rng.randi_range(0, free.size() - 1)]


## "Aldric (Paladin)"
func _title(rec: Dictionary) -> String:
	return "%s (%s)" % [str(rec["name"]), str(get_type(rec).get("name", ""))]


## Heldenhalle auch als Baustelle (für den Grund "Baue zuerst …")
func _find_hall_any(k: Kingdom) -> Building:
	for b in k.buildings:
		if bool(b.def.get("hero_hall", false)):
			return b
	return null


## Heldentypen, die gerade in einer Halle angeworben werden
func _queued(k: Kingdom) -> Array:
	var list: Array = []
	for b in k.buildings:
		if not bool(b.def.get("hero_hall", false)):
			continue
		for entry in b.summon_queue:
			list.append(str(entry.get("type_id", "")))
	return list
