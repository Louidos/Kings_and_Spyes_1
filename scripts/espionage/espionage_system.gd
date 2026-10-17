## EspionageSystem
##
## Entdeckung, Aufmerksamkeit, Kundschaft (Intel), Reichstarnung und Späherberichte
## (Phase 7). Alle Werte gelten für alle Reiche gleich (Spieler und KI); die KI liest
## sie über AISystem.get_awareness/get_intel_level/estimate_defense, die Oberfläche
## (Spionagefenster, Auswahlfenster) über dieselben Abfragen.
##
## - Entdeckungswert je Reich (alle discovery.tick_seconds): Gebäude, Bevölkerung,
##   Armee, Heldenstufen und abklingende Aggression (Angriffe, Zerstörung, Eroberung,
##   getötete Boten), mit Reichstarnung um cloak.reduction gesenkt; geglättet.
## - Aufmerksamkeit je Beobachter und Ziel (0–100): wandert zum Ziel
##   Entdeckungswert × Nähe × Faktor der Schwierigkeit; Sprünge durch Angriffe,
##   Boten, ertappte Spione, Sichtungen. Schwellen mit Hysterese: Gerüchte (die KI
##   schickt Spione), entdeckt (die KI plant Angriffe). Meldungen an den Spieler –
##   genau nur mit Kundschaft, sonst vage.
## - Kundschaft je Beobachter und Ziel: Stufe 0–3 mit Alter (veraltet mit der Zeit);
##   Quellen: Späher und Spione in der Nähe oder im fremden Gebiet, Boten, Verräter
##   (Phase 8), Angriffe, ertappte Spione.
## - Reichstarnung: Zauber mit realm_cloak (MagicSystem ruft start_cloak/stop_cloak),
##   laufende Manakosten über Kingdom.set_upkeep, Ende bei Manamangel.
## - Berichte: Feinde im eigenen Gebiet (immer) und nahe der Grenze (nur durch
##   Späher/Spione) – Signal enemy_spotted (KI-Alarm) und gedrosselte Meldungen.
##
## Zustand (gespeichert; Paar-Schlüssel "beobachter:ziel" als String): discovery,
## aggression, pair_aggr_at, awareness, awareness_tier, intel, cloaks, reported,
## sightings, spy_scout_since. Laufzeit: Taktzähler. Signale aus dem Kampf ändern nur
## diesen Zustand (keine Befehle).
class_name EspionageSystem
extends Node

## Entdeckungswert eines Reichs hat sich spürbar geändert
signal discovery_changed(k: Kingdom, value: float)
## Aufmerksamkeitsstufe von observer auf target gewechselt (0 keine, 1 Gerüchte, 2 entdeckt)
signal awareness_tier_changed(observer: Kingdom, target: Kingdom, old_tier: int, new_tier: int)
## Kundschaftsstufe von observer über target geändert
signal intel_changed(observer: Kingdom, target: Kingdom, level: int)
## Feinde von foe im (inside) bzw. nahe am Gebiet von observer gesehen
signal enemy_spotted(observer: Kingdom, foe: Kingdom, pos: Vector2, count: int, inside: bool)
## Reichstarnung an/aus
signal cloak_changed(k: Kingdom, active: bool)
## Neuer Spionagebericht von observer über target
signal report_made(observer: Kingdom, target: Kingdom)

## Namen der Aufmerksamkeitsstufen (Spionagefenster, Zusammenfassung)
const AWARENESS_TIER_NAMES := ["Keine", "Gerüchte", "Entdeckt"]
## Einträge in reported/sightings, die älter sind, werden gelöscht (Spielsekunden)
const PRUNE_AGE := 3600.0

var game: Node
var world: WorldData

## Reich-id -> {"value" (geglättet, mit Tarnung), "raw" (ohne Tarnung), "parts": {"buildings",
##   "population", "army", "heroes", "aggression", "cloak"}, "peak"}
var discovery: Dictionary = {}
## Reich-id -> {"value", "at"} (Halbwertszeit beim Lesen)
var aggression: Dictionary = {}
## "täter:opfer" -> Spielzeit (Drosselung je Paar)
var pair_aggr_at: Dictionary = {}
## "beobachter:ziel" -> Aufmerksamkeit 0..100
var awareness: Dictionary = {}
## "beobachter:ziel" -> 0 | 1 | 2 (mit Hysterese, für Meldungen)
var awareness_tier: Dictionary = {}
## "beobachter:ziel" -> {"level", "at", "source", "ever"}
var intel: Dictionary = {}
## Reich-id -> {"spell_id", "since", "upkeep_source", "base_upkeep"}
var cloaks: Dictionary = {}
## "reich:feind:bereichX:bereichY:inside|near" -> Spielzeit der letzten Meldung
var reported: Dictionary = {}
## "beobachter:ziel" bzw. "beobachter:ziel:inside" -> Spielzeit der letzten Sichtung (Drosselung)
var sightings: Dictionary = {}
## "beobachter:ziel" -> Spielzeit, seit der ein Späher/Spion des Beobachters im Gebiet des Ziels steht
var spy_scout_since: Dictionary = {}
## "beobachter:ziel" -> letzter Spionagebericht (SpyReport.build; nur Spieler-Beobachter)
var reports: Dictionary = {}

var _ts := 64.0
var _disc_acc := 0.0
var _aw_acc := 0.0
var _rep_acc := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_ts = float(world.tile_size)
	GameClock.sim_tick.connect(_on_sim_tick)
	var cs: CombatSystem = game.combat_system
	cs.kingdom_attacked.connect(_on_kingdom_attacked)
	cs.unit_died.connect(_on_unit_died)
	cs.building_destroyed.connect(_on_building_destroyed)
	(game.diplomacy_system as DiplomacySystem).aggression_reported.connect(_on_aggression_reported)
	(game.village_system as VillageSystem).settlement_transferred.connect(_on_settlement_transferred)
	(game.economy_system as EconomySystem).upkeep_unpaid.connect(_on_upkeep_unpaid)


# ---------------------------------------------------------------------------
# Parteien
# ---------------------------------------------------------------------------

## Nimmt das Reich an Entdeckung und Spionage teil? (Spieler oder KI, nicht besiegt)
func is_party(k: Kingdom) -> bool:
	return k != null and not k.defeated and (k.controller == "player" or k.controller == "ai")


## Alle Parteien (Spieler und aktive KI-Reiche)
func get_parties() -> Array:
	var list: Array = []
	for k in game.kingdoms:
		if is_party(k):
			list.append(k)
	return list


static func pair_key(observer: Kingdom, target: Kingdom) -> String:
	return "%d:%d" % [observer.id, target.id]


# ---------------------------------------------------------------------------
# Entdeckung
# ---------------------------------------------------------------------------

## Entdeckungswert des Reichs (geglättet, mit Reichstarnung)
func get_discovery(k: Kingdom) -> float:
	if k == null:
		return 0.0
	return float((discovery.get(k.id, {}) as Dictionary).get("value", 0.0))


## Entdeckungswert ohne Tarnung (ungeglättet)
func get_discovery_raw(k: Kingdom) -> float:
	if k == null:
		return 0.0
	return float((discovery.get(k.id, {}) as Dictionary).get("raw", 0.0))


## Ursachen des Entdeckungswerts: {"buildings", "population", "army", "heroes", "aggression",
## "cloak" (negativ)} – vor dem Glätten, für das Spionagefenster
func get_discovery_parts(k: Kingdom) -> Dictionary:
	if k == null:
		return {}
	return (discovery.get(k.id, {}) as Dictionary).get("parts", {})


## Höchster Entdeckungswert der Partie (Statistik)
func get_discovery_peak(k: Kingdom) -> float:
	if k == null:
		return 0.0
	return float((discovery.get(k.id, {}) as Dictionary).get("peak", 0.0))


## Stufe zu einem Entdeckungswert: {"name", "color" (Color), "min"} aus discovery.tiers
static func discovery_tier(value: float) -> Dictionary:
	var result := {"name": "", "color": Color.WHITE, "min": 0.0}
	for t in DataDB.esp("discovery.tiers", []):
		var tier: Dictionary = t
		if value >= float(tier.get("min", 0.0)) or str(result["name"]).is_empty():
			result = {"name": str(tier.get("name", "")), "color": Color(str(tier.get("color", "#ffffff"))),
					"min": float(tier.get("min", 0.0))}
	return result


## Aggressive Tat des Reichs k (Angriff, Zerstörung, Eroberung …): erhöht seine
## Aggression (klingt ab). Mit victim höchstens alle pair_cooldown Sekunden je Paar.
func note_aggression(k: Kingdom, amount: float, reason: String, victim: Kingdom = null) -> void:
	if not is_party(k) or amount <= 0.0:
		return
	var now := GameClock.game_time
	if victim != null:
		var key := "%d:%d:%s" % [k.id, victim.id, reason]
		if now - float(pair_aggr_at.get(key, -1.0e9)) < float(DataDB.esp("aggression.pair_cooldown", 60)):
			return
		pair_aggr_at[key] = now
	var value := minf(get_aggression(k) + amount, float(DataDB.esp("aggression.max", 60)))
	aggression[k.id] = {"value": value, "at": now}


## Aktuelle Aggression des Reichs (halbiert sich alle half_life Sekunden)
func get_aggression(k: Kingdom) -> float:
	if k == null:
		return 0.0
	var entry: Dictionary = aggression.get(k.id, {})
	if entry.is_empty():
		return 0.0
	var dt := maxf(GameClock.game_time - float(entry["at"]), 0.0)
	return float(entry["value"]) * pow(0.5, dt / maxf(float(DataDB.esp("aggression.half_life", 900)), 1.0))


## Rechnet den Entdeckungswert eines Reichs neu (Teile, Tarnung, Glättung)
func _update_discovery(k: Kingdom) -> void:
	var weights: Dictionary = DataDB.esp("discovery.building_weights", {})
	var default_w := float(weights.get("default", 1.0))
	var site_factor := float(DataDB.esp("discovery.construction_factor", 0.5))
	var b_part := 0.0
	for b in k.buildings:
		var w := float(weights.get(str(b.def.get("id", "")), default_w))
		b_part += w if b.constructed else w * site_factor
	var pop_part := float(k.get_population()) * float(DataDB.esp("discovery.per_population", 0.4))
	var power := 0.0
	for u in k.units:
		if is_army_unit(u):
			power += VillageSystem.unit_power(u)
	var army_part := power * float(DataDB.esp("discovery.per_army_power", 0.12))
	var hero_part := 0.0
	for rec in k.heroes:
		hero_part += float(rec.get("level", 1)) * float(DataDB.esp("discovery.per_hero_level", 1.0))
	var aggr_part := get_aggression(k)
	var raw := b_part + pop_part + army_part + hero_part + aggr_part
	var cloak_part := 0.0
	if is_cloaked(k):
		cloak_part = -raw * clampf(float(DataDB.esp("cloak.reduction", 0.4)), 0.0, 1.0)
	var target := maxf(raw + cloak_part, 0.0)
	var entry: Dictionary = discovery.get(k.id, {})
	var old := float(entry.get("value", -1.0))
	var value := target
	if old >= 0.0:
		value = old + (target - old) * clampf(float(DataDB.esp("discovery.smoothing", 0.25)), 0.01, 1.0)
	entry["value"] = value
	entry["raw"] = raw
	entry["parts"] = {"buildings": b_part, "population": pop_part, "army": army_part, "heroes": hero_part,
			"aggression": aggr_part, "cloak": cloak_part}
	entry["peak"] = maxf(float(entry.get("peak", 0.0)), value)
	discovery[k.id] = entry
	if old < 0.0 or absf(value - old) >= 0.5:
		discovery_changed.emit(k, value)
	if is_cloaked(k):
		var c: Dictionary = cloaks[k.id]
		k.set_upkeep(str(c["upkeep_source"]), {"mana": cloak_upkeep(k)})


## Zählt die Einheit als Armee (Entdeckung, Stärke)? Kämpfer, Helden und Heiler –
## ohne Späher, Spione, Boten, König und beschworene Zaubereinheiten
static func is_army_unit(u: Unit) -> bool:
	if not u.is_alive() or u.expires_at >= 0.0:
		return false
	if u.role != "combat" and u.role != "hero" and u.role != "support":
		return false
	return u.tier != "scout" and u.tier != "spy"


# ---------------------------------------------------------------------------
# Reichstarnung
# ---------------------------------------------------------------------------

## Ist die Reichstarnung des Reichs aktiv?
func is_cloaked(k: Kingdom) -> bool:
	return k != null and cloaks.has(k.id)


## Zauber mit realm_cloak, den das Reich kennen kann ("" wenn keiner)
func get_cloak_spell(k: Kingdom) -> String:
	if k == null:
		return ""
	for sp in (game.magic_system as MagicSystem).get_spells(k):
		if bool(sp.get("realm_cloak", false)):
			return str(sp.get("id", ""))
	return ""


## Laufende Kosten der Tarnung in Mana pro Sekunde: aktuell bzw. (ausgeschaltet) beim
## Einschalten – Grundwert des Zaubers + upkeep_per_point × Entdeckungswert ohne Tarnung
func cloak_upkeep(k: Kingdom) -> float:
	if k == null:
		return 0.0
	var base := 0.0
	if is_cloaked(k):
		base = float((cloaks[k.id] as Dictionary).get("base_upkeep", 0.0))
	else:
		var id := get_cloak_spell(k)
		if id.is_empty():
			return 0.0
		base = float((game.magic_system as MagicSystem).get_cast_params(k, id)["upkeep"])
	return base + float(DataDB.esp("cloak.upkeep_per_point", 0.002)) * get_discovery_raw(k)


## "" = die Tarnung kann jetzt umgeschaltet werden, sonst der Grund (Ausschalten geht immer)
func can_toggle_cloak(k: Kingdom) -> String:
	if not is_party(k):
		return "Nur Reiche können sich tarnen"
	if is_cloaked(k):
		return ""
	var id := get_cloak_spell(k)
	if id.is_empty():
		return "Keine Reichstarnung für dieses Reich"
	var ms: MagicSystem = game.magic_system
	if not ms.is_known(k, id):
		var def := DataDB.get_spell(id)
		return "Noch nicht erforscht: %s" % DataDB.describe_requirement(def.get("requires", []), k.faction_id)
	if not is_instance_valid(k.castle):
		return "Keine Burg"
	return ms.can_cast_now(k, id)


## Schaltet die Reichstarnung um: an = Zauber an der Burg (kostet Mana, Abklingzeit),
## aus = Zauber beenden. "" = umgeschaltet, sonst der Grund.
func toggle_cloak(k: Kingdom) -> String:
	if is_cloaked(k):
		var spell_id := str((cloaks[k.id] as Dictionary).get("spell_id", ""))
		(game.magic_system as MagicSystem).end_spell(k, spell_id)
		if is_cloaked(k):
			stop_cloak(k, "ended")
		return ""
	var reason := can_toggle_cloak(k)
	if not reason.is_empty():
		return reason
	var id := get_cloak_spell(k)
	var ms: MagicSystem = game.magic_system
	var pos := k.castle.get_center()
	if not ms.cast(k, id, pos):
		var why := ms.can_cast(k, id, pos)
		return why if not why.is_empty() else "Zauber misslungen"
	return ""


## Tarnung beginnt (nur vom MagicSystem nach dem Zaubern aufgerufen)
func start_cloak(k: Kingdom, spell_id: String, base_upkeep: float) -> void:
	if not is_party(k):
		return
	var source := "spell:" + spell_id
	cloaks[k.id] = {"spell_id": spell_id, "since": GameClock.game_time, "upkeep_source": source,
			"base_upkeep": base_upkeep}
	k.set_upkeep(source, {"mana": cloak_upkeep(k)})
	cloak_changed.emit(k, true)
	k.notify("Reichstarnung aktiv – kostet laufend %s Mana/min" % _num(cloak_upkeep(k) * 60.0), "good", _castle_pos(k))


## Tarnung endet (reason "ended" = abgeschaltet, "mana" = Manamangel, "defeated")
func stop_cloak(k: Kingdom, reason: String) -> void:
	if k == null or not cloaks.has(k.id):
		return
	var c: Dictionary = cloaks[k.id]
	cloaks.erase(k.id)
	k.clear_upkeep(str(c["upkeep_source"]))
	cloak_changed.emit(k, false)
	var pos: Variant = _castle_pos(k)
	match reason:
		"mana":
			k.notify("Reichstarnung endet – zu wenig Mana", "warning", pos)
		"ended":
			k.notify("Reichstarnung abgeschaltet", "info", pos)


# ---------------------------------------------------------------------------
# Aufmerksamkeit
# ---------------------------------------------------------------------------

## Aufmerksamkeit von observer auf target (0–100)
func get_awareness(observer: Kingdom, target: Kingdom) -> float:
	if observer == null or target == null or observer == target:
		return 0.0
	return float(awareness.get(pair_key(observer, target), 0.0))


## Stufe: 0 ahnungslos, 1 Gerüchte, 2 entdeckt (mit Hysterese)
func get_awareness_tier(observer: Kingdom, target: Kingdom) -> int:
	if observer == null or target == null or observer == target:
		return 0
	var key := pair_key(observer, target)
	if awareness_tier.has(key):
		return int(awareness_tier[key])
	return _raw_tier(get_awareness(observer, target))


static func awareness_tier_name(tier: int) -> String:
	return str(AWARENESS_TIER_NAMES[clampi(tier, 0, AWARENESS_TIER_NAMES.size() - 1)])


## Sprung der Aufmerksamkeit (Boten, Sichtungen, ertappte Spione …)
func add_awareness(observer: Kingdom, target: Kingdom, amount: float, _reason: String) -> void:
	if not is_party(observer) or not is_party(target) or observer == target or amount == 0.0:
		return
	var key := pair_key(observer, target)
	awareness[key] = clampf(float(awareness.get(key, 0.0)) + amount, 0.0, 100.0)


## Aufmerksamkeit mindestens auf value heben (Angriff, Bestätigung durch Spione)
func raise_awareness_to(observer: Kingdom, target: Kingdom, value: float, _reason: String) -> void:
	if not is_party(observer) or not is_party(target) or observer == target:
		return
	var key := pair_key(observer, target)
	awareness[key] = clampf(maxf(float(awareness.get(key, 0.0)), value), 0.0, 100.0)


## Nähe zweier Reiche für die Aufmerksamkeit: 1 bis near_tiles Burgabstand, min_proximity
## ab far_tiles, + border_bonus bei nahen Grenzen
func get_proximity(observer: Kingdom, target: Kingdom, bboxes: Dictionary = {}) -> float:
	if observer == null or target == null or not is_instance_valid(observer.castle) or not is_instance_valid(target.castle):
		return 0.0
	var d := observer.castle.get_center().distance_to(target.castle.get_center()) / _ts
	var near := float(DataDB.esp("awareness.near_tiles", 80))
	var far := float(DataDB.esp("awareness.far_tiles", 450))
	var p := clampf(1.0 - (d - near) / maxf(far - near, 1.0), float(DataDB.esp("awareness.min_proximity", 0.35)), 1.0)
	var ra: Rect2i = bboxes[observer.id] if bboxes.has(observer.id) else TerritorySystem.kingdom_bbox(observer, world)
	var rb: Rect2i = bboxes[target.id] if bboxes.has(target.id) else TerritorySystem.kingdom_bbox(target, world)
	if ra.has_area() and rb.has_area() and _rect_gap(ra, rb) < int(DataDB.esp("awareness.border_tiles", 30)):
		p += float(DataDB.esp("awareness.border_bonus", 0.2))
	return p


## Abstand zweier Rechtecke in Kacheln (0 bei Überlappung)
static func _rect_gap(a: Rect2i, b: Rect2i) -> int:
	var dx := maxi(0, maxi(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxi(0, maxi(a.position.y - b.end.y, b.position.y - a.end.y))
	return maxi(dx, dy)


## Faktor der Schwierigkeit für KI-Beobachter (ai.json difficulty.awareness_mult), sonst 1
## Ab dieser Spielminute sinkt die Aufmerksamkeit der KI nicht mehr unter patience_floor:
## patience_minutes der Schwierigkeit (ai.json difficulty), sonst espionage.json
func _patience_minutes() -> float:
	var fallback := float(DataDB.esp("awareness.patience_minutes", 120))
	var ai: Variant = game.get("ai_system")
	if ai is AISystem:
		return float((ai as AISystem).get_difficulty().get("patience_minutes", fallback))
	return fallback


func _awareness_mult(observer: Kingdom) -> float:
	if observer.controller != "ai":
		return 1.0
	var ai: Variant = game.get("ai_system")
	if ai is AISystem:
		return float((ai as AISystem).get_difficulty().get("awareness_mult", 1.0))
	return 1.0


func _raw_tier(value: float) -> int:
	if value >= float(DataDB.esp("awareness.discovered", 60)):
		return 2
	if value >= float(DataDB.esp("awareness.rumour", 30)):
		return 1
	return 0


func _tick_awareness(dt: float, now: float) -> void:
	var parties := get_parties()
	var bboxes := {}
	for k in parties:
		bboxes[k.id] = TerritorySystem.kingdom_bbox(k, world)
	var rise := float(DataDB.esp("awareness.rise_per_minute", 3.0)) * dt / 60.0
	var fall := float(DataDB.esp("awareness.fall_per_minute", 1.0)) * dt / 60.0
	var patient := now / 60.0 >= _patience_minutes()
	var floor_value := float(DataDB.esp("awareness.patience_floor", 35))
	for o in parties:
		var observer: Kingdom = o
		if not is_instance_valid(observer.castle):
			continue
		var mult := _awareness_mult(observer)
		for t in parties:
			var target: Kingdom = t
			if target == observer or not is_instance_valid(target.castle):
				continue
			var goal := get_discovery(target) * get_proximity(observer, target, bboxes) * mult
			if patient and observer.controller == "ai":
				goal = maxf(goal, floor_value)
			goal = clampf(goal, 0.0, 100.0)
			var key := pair_key(observer, target)
			var aw := float(awareness.get(key, 0.0))
			# Liegt die Aufmerksamkeit über dem Ziel (Sprünge), sinkt sie nur langsam
			aw = minf(goal, aw + rise) if aw < goal else maxf(goal, aw - fall)
			awareness[key] = aw
			_update_tier(observer, target, aw, now)


## Schwellen mit Hysterese; Meldung an den Spieler, wenn eine KI aufmerksamer wird
func _update_tier(observer: Kingdom, target: Kingdom, aw: float, now: float) -> void:
	var key := pair_key(observer, target)
	var old := int(awareness_tier.get(key, 0))
	var up := _raw_tier(aw)
	var new_tier := old
	if up > old:
		new_tier = up
	elif up < old:
		var h := float(DataDB.esp("awareness.hysteresis", 5))
		new_tier = mini(old, _raw_tier(aw + h))
	if new_tier == old:
		return
	awareness_tier[key] = new_tier
	awareness_tier_changed.emit(observer, target, old, new_tier)
	if new_tier <= old or not target.is_player or observer.controller != "ai":
		return
	var ai: Variant = game.get("ai_system")
	if ai is AISystem:
		var brain := (ai as AISystem).get_brain(observer)
		if brain != null:
			brain.log_first("first_rumour_player" if new_tier == 1 else "first_discovered_player", now)
	var pos: Variant = _castle_pos(target)
	target.flags["espionage_alert_at"] = now
	if get_intel_level(target, observer) >= 2:
		if new_tier == 1:
			target.notify("%s hört Gerüchte über dein Reich – erste Spione sind zu erwarten." % observer.display_name, "warning", pos)
		else:
			target.notify("%s hat dein Reich entdeckt und plant Angriffe!" % observer.display_name, "danger", pos)
	elif new_tier == 1:
		target.notify("Gerüchte: Fremde fragen in den Dörfern nach deinem Reich.", "warning", pos)
	else:
		target.notify("Ein fremdes Reich ist auf dich aufmerksam geworden.", "danger", pos)


# ---------------------------------------------------------------------------
# Kundschaft (Intel)
# ---------------------------------------------------------------------------

## Kundschaftsstufe 0–3 von observer über target (veraltet mit dem Alter; einmal
## bekannt nie unter 1). Eigenes Reich, Verbündete und Monster: 3. Dörfer mindestens
## village_default, ab gespeicherter Stufe 2 genau.
func get_intel_level(observer: Kingdom, target: Kingdom) -> int:
	if observer == null or target == null:
		return 0
	if observer == target or game.are_allied(observer, target) or target.controller == "wild":
		return 3
	var entry: Dictionary = intel.get(pair_key(observer, target), {})
	var level := 0
	if not entry.is_empty():
		var stale := maxf(float(DataDB.esp("intel.stale_seconds", 900)), 1.0)
		var age := maxf(GameClock.game_time - float(entry["at"]), 0.0)
		level = int(entry["level"]) - floori(age / stale)
		if bool(entry.get("ever", false)):
			level = maxi(level, 1)
	if _is_village_kingdom(target):
		if not entry.is_empty() and int(entry["level"]) >= 2:
			level = 3
		level = maxi(level, int(DataDB.esp("intel.village_default", 1)))
	return clampi(level, 0, 3)


## Alter der Kundschaft in Spielsekunden (INF = nie)
func get_intel_age(observer: Kingdom, target: Kingdom) -> float:
	if observer == null or target == null:
		return INF
	var entry: Dictionary = intel.get(pair_key(observer, target), {})
	if entry.is_empty():
		return INF
	return maxf(GameClock.game_time - float(entry["at"]), 0.0)


## Quelle der letzten Kundschaft ("Späher", "Spion", "Bote" …; "" = keine)
func get_intel_source(observer: Kingdom, target: Kingdom) -> String:
	if observer == null or target == null:
		return ""
	return str((intel.get(pair_key(observer, target), {}) as Dictionary).get("source", ""))


## Neue Kundschaft: frischer Bericht der Stufe level. Ist die vorhandene noch besser,
## bleibt sie (wird aber nicht aufgefrischt).
func grant_intel(observer: Kingdom, target: Kingdom, level: int, source: String) -> void:
	if observer == null or target == null or observer == target or level <= 0:
		return
	var before := get_intel_level(observer, target)
	var key := pair_key(observer, target)
	if level < before and intel.has(key):
		return
	intel[key] = {"level": clampi(level, 0, 3), "at": GameClock.game_time, "source": source, "ever": true}
	var after := get_intel_level(observer, target)
	if after != before:
		intel_changed.emit(observer, target, after)


## Spionagebericht (Schnappschuss) von observer über target anlegen bzw. erneuern – höchstens alle
## report.refresh_seconds; Meldung ins Protokoll beim ersten Bericht und wenn der letzte älter als
## report.notify_seconds ist. Nur für den Spieler (die KI liest den Spielzustand selbst).
func make_report(observer: Kingdom, target: Kingdom, level: int, source: String, force: bool = false) -> void:
	if observer == null or target == null or observer == target or not observer.is_player or level <= 0:
		return
	var key := pair_key(observer, target)
	var old: Dictionary = reports.get(key, {})
	var age := GameClock.game_time - float(old.get("at", -INF))
	if not force and not old.is_empty() and age < float(DataDB.esp("report.refresh_seconds", 60)) \
			and int(old.get("level", 0)) >= level:
		return
	reports[key] = SpyReport.build(game, observer, target, level, source)
	report_made.emit(observer, target)
	if old.is_empty() or age >= float(DataDB.esp("report.notify_seconds", 300)):
		var names: Array = DataDB.esp("intel.names", ["Unbekannt", "Gerüchte", "Bericht", "Genau"])
		observer.notify("Spionagebericht über %s (%s) – Spionagefenster (K)" % [target.display_name,
				str(names[clampi(level, 0, names.size() - 1)])], "info",
				{"window": "espionage", "tab": "realms", "target_id": target.id, "pos": _castle_pos(target)})


## Letzter Spionagebericht von observer über target ({} = keiner)
func get_report(observer: Kingdom, target: Kingdom) -> Dictionary:
	if observer == null or target == null:
		return {}
	return reports.get(pair_key(observer, target), {})


## Darf viewer Einzelheiten über k sehen (Stufe min_level)? Eigenes und verbündetes
## Reich, Monster und Dörfer (ab Stufe 1) immer.
func details_visible(viewer: Kingdom, k: Kingdom, min_level: int) -> bool:
	if viewer == null or k == null or viewer == k or game.are_allied(viewer, k) or k.controller == "wild":
		return true
	if _is_village_kingdom(k) and min_level <= 1:
		return true
	return get_intel_level(viewer, k) >= min_level


## Geschätzte Kampfkraft von k aus Sicht von viewer: {"known" (ab Kundschaft 2),
## "value", "low", "high", "units_low", "units_high", "exact"}. Stufe 2: Spanne ±
## estimate_spread (leicht verschoben, je Bericht fest); Stufe 3: genau.
func estimate_strength(viewer: Kingdom, k: Kingdom) -> Dictionary:
	var result := {"known": false, "value": 0.0, "low": 0.0, "high": 0.0, "units_low": 0, "units_high": 0, "exact": false}
	if k == null:
		return result
	var power := 0.0
	var count := 0
	if _is_village_kingdom(k):
		var vs: VillageSystem = game.village_system
		power = vs.get_strength(k)
		count = vs.get_militia(k).size()
	else:
		for u in k.units:
			if is_army_unit(u) or (u.role == "king" and u.is_alive()):
				power += VillageSystem.unit_power(u)
				count += 1
	var level := 3 if details_visible(viewer, k, 3) else get_intel_level(viewer, k)
	if level < 2:
		return result
	result["known"] = true
	if level >= 3:
		result["value"] = power
		result["low"] = power
		result["high"] = power
		result["units_low"] = count
		result["units_high"] = count
		result["exact"] = true
		return result
	var spread := clampf(float(DataDB.esp("intel.estimate_spread", 0.25)), 0.0, 0.9)
	var at := float((intel.get(pair_key(viewer, k), {}) as Dictionary).get("at", 0.0))
	var skew := (float(posmod(hash([viewer.id, k.id, int(at)]), 1001)) / 1000.0 - 0.5) * spread
	var center := power * (1.0 + skew)
	result["value"] = center
	result["low"] = center * (1.0 - spread)
	result["high"] = center * (1.0 + spread)
	var units_center := float(count) * (1.0 + skew)
	result["units_low"] = maxi(floori(units_center * (1.0 - spread)), 0)
	result["units_high"] = ceili(units_center * (1.0 + spread))
	return result


## "Kundschaft: Bericht (vor 4 min)" bzw. "Kundschaft: Unbekannt"
func get_intel_text(viewer: Kingdom, k: Kingdom) -> String:
	var level := get_intel_level(viewer, k)
	var names: Array = DataDB.esp("intel.names", ["Unbekannt", "Gerüchte", "Bericht", "Genau"])
	var text := "Kundschaft: %s" % str(names[clampi(level, 0, names.size() - 1)])
	if viewer == null or k == null or viewer == k or game.are_allied(viewer, k) or k.controller == "wild":
		return text
	var age := get_intel_age(viewer, k)
	if age == INF:
		return text
	if age < 60.0:
		return text + " (gerade eben)"
	return text + " (vor %d min)" % floori(age / 60.0)


## Mehrzeilige Zusammenfassung eines Reichs aus Sicht von viewer, je nach Kundschaft
## (Auswahlfenster an der Burg, Spionagefenster). Dörfer: Dorftext aus Phase 6.
func get_kingdom_summary(k: Kingdom, viewer: Kingdom) -> String:
	if k == null:
		return ""
	var vs: VillageSystem = game.village_system
	if vs.is_village_kingdom(k):
		return vs.get_summary_text(k, viewer)
	var level := 3 if details_visible(viewer, k, 3) else get_intel_level(viewer, k)
	var lines: PackedStringArray = []
	lines.append(get_intel_text(viewer, k))
	if level <= 1:
		lines.append("Keine Kundschaft – schicke Späher oder Spione (K). Bekannt: Burg, Gebiet.")
		return "\n".join(lines)
	var est := estimate_strength(viewer, k)
	if level >= 3:
		lines.append("Heer: %d Einheiten (Stärke %d)" % [int(est["units_low"]), roundi(float(est["value"]))])
		lines.append("Gebäude: %d" % k.buildings.size())
	else:
		lines.append("Heer: etwa %d–%d Einheiten (Stärke %d–%d)" % [int(est["units_low"]), int(est["units_high"]),
				roundi(float(est["low"])), roundi(float(est["high"]))])
		lines.append("Gebäude: etwa %d" % maxi(roundi(k.buildings.size() / 5.0) * 5, 5))
	lines.append("Kriege: %s" % _wars_text(k, viewer))
	var treaties: Array = (game.diplomacy_system as DiplomacySystem).get_treaties_of(k)
	if level >= 3 and not treaties.is_empty():
		var names: PackedStringArray = []
		for t in treaties:
			names.append((t["village"] as Kingdom).display_name)
		lines.append("Verträge: %d Dörfer (%s)" % [treaties.size(), ", ".join(names)])
	else:
		lines.append("Verträge: %d Dörfer" % treaties.size())
	if level >= 3:
		var stock := {}
		for res in k.resources:
			stock[res] = roundf(float(k.resources[res]) / 10.0) * 10.0
		lines.append("Vorräte: %s" % DataDB.cost_to_text(stock))
		var last := ""
		for id in k.researched:
			last = str(id)
		var research_line := "Forschungen: %d" % k.researched.size()
		if not last.is_empty():
			research_line += " (zuletzt: %s)" % str(DataDB.get_research(last).get("name", last))
		lines.append(research_line)
		var heroes: PackedStringArray = []
		for rec in k.heroes:
			heroes.append("%s (Stufe %d)" % [str(rec.get("name", "?")), int(rec.get("level", 1))])
		lines.append("Helden: %s" % (", ".join(heroes) if not heroes.is_empty() else "keine"))
		lines.append("Entdeckungswert: %d" % roundi(get_discovery(k)))
	if is_party(viewer) and is_party(k) and viewer != k:
		if level >= 3:
			lines.append("Aufmerksamkeit auf dich: %d %% (%s)" % [roundi(get_awareness(k, viewer)),
					awareness_tier_name(get_awareness_tier(k, viewer))])
		else:
			lines.append("Aufmerksamkeit auf dich: %s" % awareness_tier_name(get_awareness_tier(k, viewer)))
	return "\n".join(lines)


## Kriege des Reichs (andere Reiche und Dörfer) als Text; Beziehungen zum Betrachter zählen mit
func _wars_text(k: Kingdom, viewer: Kingdom) -> String:
	var names: PackedStringArray = []
	for o in game.kingdoms:
		var other: Kingdom = o
		if other == k or other.defeated or other.controller == "wild" or not game.are_hostile(k, other):
			continue
		if other.controller == "neutral" and not (game.village_system as VillageSystem).is_village(other):
			continue
		names.append("dir" if other == viewer else other.display_name)
	return ", ".join(names) if not names.is_empty() else "keine"


func _is_village_kingdom(k: Kingdom) -> bool:
	return (game.village_system as VillageSystem).is_village_kingdom(k)


# ---------------------------------------------------------------------------
# Späher, Spione, Berichte
# ---------------------------------------------------------------------------

func _tick_reports(now: float) -> void:
	var index: SpatialIndex = game.combat_system.index
	var ids := index.kingdom_ids()
	for k in get_parties():
		var bbox := TerritorySystem.kingdom_bbox(k, world)
		_scan_inside(k, bbox, ids, now)
		_scan_observers(k, bbox, ids, now)


## Dürfen Einheiten dieses Reichs gemeldet werden? (Monster nur mit reports.report_monsters)
func _reportable(f: Kingdom) -> bool:
	return f != null and (f.controller != "wild" or bool(DataDB.esp("reports.report_monsters", false)))


## Feinde im eigenen Gebiet (ohne Späher): je feindlichem Reich enemy_spotted und Meldung
func _scan_inside(k: Kingdom, bbox: Rect2i, ids: Array, now: float) -> void:
	if not bbox.has_area():
		return
	var index: SpatialIndex = game.combat_system.index
	var center := (Vector2(bbox.position) + Vector2(bbox.size) * 0.5) * _ts
	var radius := Vector2(bbox.size).length() * 0.5 * _ts + _ts
	for kid in ids:
		if int(kid) == k.id:
			continue
		var f: Kingdom = game.get_kingdom(int(kid))
		if f == null or not _reportable(f) or not game.are_hostile(k, f):
			continue
		if not index.any_of_kingdom(center, radius, f.id):
			continue
		var n := 0
		var sum := Vector2.ZERO
		for u in index.query_kingdom(center, radius, f.id):
			if u.hp <= 0.0 or u.role == "messenger" or not game.can_see(k, u):
				continue
			var p: Vector2 = u.position
			if world.get_owner(world.world_to_cell(p)) != k.id:
				continue
			n += 1
			sum += p
		if n > 0:
			var pos := sum / float(n)
			enemy_spotted.emit(k, f, pos, n, true)
			_report(k, f, pos, n, true, now)


## Späher und Spione des Reichs: Kundschaft über gesehene Reiche, Sichtungen, Feinde
## nahe der Grenze, Aufenthalt im fremden Gebiet (KI: bestätigt die Gerüchte)
func _scan_observers(k: Kingdom, bbox: Rect2i, ids: Array, now: float) -> void:
	var observers: Array = []
	var max_obs := int(DataDB.esp("reports.max_observers", 16))
	for u in k.units:
		if (u.tier == "scout" or u.tier == "spy") and u.is_alive() and u.inside == null:
			observers.append(u)
			if observers.size() >= max_obs:
				break
	var inside_pairs := {}
	if not observers.is_empty():
		var index: SpatialIndex = game.combat_system.index
		var near_rect := bbox.grow(int(DataDB.esp("reports.near_tiles", 12))) if bbox.has_area() else Rect2i()
		var near_found := {}
		var scout_level := int(DataDB.esp("intel.scout_level", 2))
		var spy_levels: Array = DataDB.esp("intel.spy_levels", [2, 3, 3])
		var spies: Variant = game.get("spy_system")
		var discovered := float(DataDB.esp("awareness.discovered", 60))
		var confirm := float(DataDB.esp("awareness.spy_confirm_seconds", 60))
		for o in observers:
			var ob: Unit = o
			var level := scout_level
			var source := "Späher"
			if ob.tier == "spy":
				var spy_level := (spies as SpySystem).get_level(ob) if spies is SpySystem else 1
				level = int(spy_levels[clampi(spy_level - 1, 0, spy_levels.size() - 1)])
				source = "Spion"
			var ocell := world.world_to_cell(ob.position)
			var owner_id := world.get_owner(ocell)
			var at_home := owner_id == k.id or near_rect.has_point(ocell)
			var sight_px := ob.sight * _ts
			for kid in ids:
				if int(kid) == k.id:
					continue
				var f: Kingdom = game.get_kingdom(int(kid))
				if f == null or game.are_allied(k, f) or not _reportable(f):
					continue
				if not index.any_of_kingdom(ob.position, sight_px, f.id):
					continue
				var hostile: bool = game.are_hostile(k, f)
				var count := 0
				var near_n := 0
				var near_sum := Vector2.ZERO
				for u in index.query_kingdom(ob.position, sight_px, f.id):
					if u.hp <= 0.0 or u.role == "messenger" or not game.can_see(k, u):
						continue
					count += 1
					if at_home and hostile:
						var p: Vector2 = u.position
						var c := world.world_to_cell(p)
						if world.get_owner(c) != k.id and near_rect.has_point(c):
							near_n += 1
							near_sum += p
				if count > 0:
					grant_intel(k, f, level, source)
					_sighting(k, f, float(DataDB.esp("awareness.scout_sighting", 0.5)), "", now)
				if near_n > 0:
					var entry: Array = near_found.get(f.id, [0, Vector2.ZERO])
					near_found[f.id] = [int(entry[0]) + near_n, (entry[1] as Vector2) + near_sum]
			# Im fremden Gebiet: Kundschaft auch ohne Einheiten in Sicht
			if owner_id != 0 and owner_id != k.id:
				var host: Kingdom = game.get_kingdom(owner_id)
				if host != null and not game.are_allied(k, host) and _reportable(host):
					grant_intel(k, host, level, source)
					var key := pair_key(k, host)
					inside_pairs[key] = true
					if not spy_scout_since.has(key):
						spy_scout_since[key] = now
					if is_party(host):
						_sighting(k, host, float(DataDB.esp("awareness.scout_inside", 2.0)), ":inside", now)
						if k.controller == "ai" and now - float(spy_scout_since[key]) >= confirm:
							raise_awareness_to(k, host, discovered + 5.0, "Kundschaft")
		for fid in near_found:
			var f: Kingdom = game.get_kingdom(int(fid))
			var entry: Array = near_found[fid]
			var pos := (entry[1] as Vector2) / float(maxi(int(entry[0]), 1))
			enemy_spotted.emit(k, f, pos, int(entry[0]), false)
			_report(k, f, pos, int(entry[0]), false, now)
	var prefix := "%d:" % k.id
	for key in spy_scout_since.keys():
		if str(key).begins_with(prefix) and not inside_pairs.has(key):
			spy_scout_since.erase(key)


## Sichtung: Aufmerksamkeit + amount, je Paar höchstens alle sighting_cooldown Sekunden
func _sighting(k: Kingdom, f: Kingdom, amount: float, suffix: String, now: float) -> void:
	if not is_party(k) or not is_party(f) or amount <= 0.0:
		return
	var key := pair_key(k, f) + suffix
	if now - float(sightings.get(key, -1.0e9)) < float(DataDB.esp("awareness.sighting_cooldown", 10)):
		return
	sightings[key] = now
	add_awareness(k, f, amount, "Sichtung")


## Gedrosselte Meldung an den Spieler (je Feldbereich und Feind)
func _report(k: Kingdom, f: Kingdom, pos: Vector2, n: int, inside: bool, now: float) -> void:
	if not k.is_player:
		return
	var area := maxi(int(DataDB.esp("reports.area_tiles", 20)), 1)
	var c := world.world_to_cell(pos)
	var key := "%d:%d:%d:%d:%s" % [k.id, f.id, floori(float(c.x) / area), floori(float(c.y) / area),
			"inside" if inside else "near"]
	var interval := float(DataDB.esp("reports.inside_interval" if inside else "reports.near_interval", 60))
	if now - float(reported.get(key, -1.0e9)) < interval:
		return
	reported[key] = now
	if inside:
		var what := "Eine feindliche Einheit" if n == 1 else "%d feindliche Einheiten" % n
		k.notify("%s (%s) in deinem Gebiet!" % [what, f.display_name], "danger", pos)
	else:
		k.notify("Späher melden: %d Einheiten von %s nahe deiner Grenze." % [n, f.display_name], "warning", pos)


# ---------------------------------------------------------------------------
# Signale anderer Systeme (nur Zustand)
# ---------------------------------------------------------------------------

## Angriff: Aggression des Täters; ist das Opfer ein Reich, weiss es sofort Bescheid
func _on_kingdom_attacked(victim: Kingdom, attacker: Kingdom, _pos: Vector2) -> void:
	if victim == null or attacker == null or victim == attacker or not is_party(attacker) or victim.controller == "wild":
		return
	if _is_village_kingdom(victim):
		note_aggression(attacker, float(DataDB.esp("aggression.attack_village", 6)), "attack", victim)
	elif is_party(victim):
		note_aggression(attacker, float(DataDB.esp("aggression.attack_kingdom", 4)), "attack", victim)
		raise_awareness_to(victim, attacker, float(DataDB.esp("awareness.attacked", 100)), "Angriff")
		grant_intel(victim, attacker, 1, "Angriff")


func _on_building_destroyed(b: Building, killer: Kingdom) -> void:
	if b == null or killer == null or b.kingdom == null or b.kingdom == killer or b.kingdom.controller == "wild":
		return
	note_aggression(killer, float(DataDB.esp("aggression.destroy_building", 3)), "destroy")


func _on_unit_died(u: Unit, killer: Kingdom) -> void:
	if killer == null or u.kingdom == killer or u.role != "messenger":
		return
	note_aggression(killer, float(DataDB.esp("aggression.kill_messenger", 2)), "messenger")


func _on_settlement_transferred(from_kingdom: Kingdom, to_kingdom: Kingdom, reason: String) -> void:
	if reason == "conquest":
		note_aggression(to_kingdom, float(DataDB.esp("aggression.conquest", 15)), "conquest", from_kingdom)


## Ein Bote meldet einen Angriff: Aufmerksamkeit und Kundschaft über den Angreifer
func _on_aggression_reported(receiver: Kingdom, aggressor: Kingdom, _village: Kingdom) -> void:
	if not is_party(receiver) or aggressor == null or aggressor == receiver:
		return
	add_awareness(receiver, aggressor, float(DataDB.esp("awareness.messenger", 25)), "Bote")
	grant_intel(receiver, aggressor, int(DataDB.esp("intel.messenger_level", 1)), "Bote")


func _on_upkeep_unpaid(k: Kingdom, source: String) -> void:
	if k != null and cloaks.has(k.id) and str((cloaks[k.id] as Dictionary)["upkeep_source"]) == source:
		stop_cloak(k, "mana")


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	var now := GameClock.game_time
	_disc_acc += dt
	if _disc_acc >= float(DataDB.esp("discovery.tick_seconds", 5)):
		_disc_acc = 0.0
		for k in get_parties():
			_update_discovery(k)
	_aw_acc += dt
	if _aw_acc >= float(DataDB.esp("awareness.tick_seconds", 5)):
		var step := _aw_acc
		_aw_acc = 0.0
		_tick_awareness(step, now)
		_prune(now)
	_rep_acc += dt
	if _rep_acc >= float(DataDB.esp("reports.interval", 2)):
		_rep_acc = 0.0
		_tick_reports(now)


## Alte Drosselungs-Einträge löschen (wachsen sonst über die Partie)
func _prune(now: float) -> void:
	for dict in [reported, sightings, pair_aggr_at]:
		var d: Dictionary = dict
		for key in d.keys():
			if now - float(d[key]) > PRUNE_AGE:
				d.erase(key)


# ---------------------------------------------------------------------------
# Phase 8 und Niederlage
# ---------------------------------------------------------------------------

## Verräter (Phase 8): receiver erfährt von victim (Aufmerksamkeit und Kundschaft)
func report_betrayal(victim: Kingdom, receiver: Kingdom) -> void:
	if not is_party(receiver) or victim == null or victim == receiver:
		return
	add_awareness(receiver, victim, float(DataDB.esp("awareness.messenger", 25)), "Verräter")
	grant_intel(receiver, victim, int(DataDB.esp("intel.traitor_level", 2)), "Verräter")


## Ein Reich ist gefallen: Tarnung beenden, seine Aufmerksamkeit vergessen
func on_kingdom_defeated(k: Kingdom) -> void:
	if k == null:
		return
	if cloaks.has(k.id):
		var c: Dictionary = cloaks[k.id]
		cloaks.erase(k.id)
		k.clear_upkeep(str(c["upkeep_source"]))
		cloak_changed.emit(k, false)
	var prefix := "%d:" % k.id
	var suffix := ":%d" % k.id
	for dict in [awareness, awareness_tier, spy_scout_since, reports]:
		var d: Dictionary = dict
		for key in d.keys():
			if str(key).begins_with(prefix) or str(key).ends_with(suffix):
				d.erase(key)


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"discovery": discovery.duplicate(true), "aggression": aggression.duplicate(true),
			"pair_aggr_at": pair_aggr_at.duplicate(), "awareness": awareness.duplicate(),
			"awareness_tier": awareness_tier.duplicate(), "intel": intel.duplicate(true), "cloaks": cloaks.duplicate(true),
			"reported": reported.duplicate(), "sightings": sightings.duplicate(), "spy_scout_since": spy_scout_since.duplicate(),
			"reports": reports.duplicate(true), "acc": [_disc_acc, _aw_acc, _rep_acc]}


func from_dict(d: Dictionary) -> void:
	discovery = (d.get("discovery", {}) as Dictionary).duplicate(true)
	aggression = (d.get("aggression", {}) as Dictionary).duplicate(true)
	pair_aggr_at = (d.get("pair_aggr_at", {}) as Dictionary).duplicate()
	awareness = (d.get("awareness", {}) as Dictionary).duplicate()
	awareness_tier = (d.get("awareness_tier", {}) as Dictionary).duplicate()
	intel = (d.get("intel", {}) as Dictionary).duplicate(true)
	cloaks = (d.get("cloaks", {}) as Dictionary).duplicate(true)
	reported = (d.get("reported", {}) as Dictionary).duplicate()
	sightings = (d.get("sightings", {}) as Dictionary).duplicate()
	spy_scout_since = (d.get("spy_scout_since", {}) as Dictionary).duplicate()
	# Spielstände vor den Spionageberichten: keine Berichte
	reports = (d.get("reports", {}) as Dictionary).duplicate(true)
	var acc: Array = d.get("acc", [0.0, 0.0, 0.0])
	if acc.size() >= 3:
		_disc_acc = float(acc[0])
		_aw_acc = float(acc[1])
		_rep_acc = float(acc[2])


## Nach dem Laden: Tarnungs-Upkeep wieder setzen (idempotent)
func rebuild_runtime() -> void:
	for kid in cloaks.keys():
		var k: Kingdom = game.get_kingdom(int(kid))
		if k == null or k.defeated:
			cloaks.erase(kid)
			continue
		k.set_upkeep(str((cloaks[kid] as Dictionary)["upkeep_source"]), {"mana": cloak_upkeep(k)})


# ---------------------------------------------------------------------------
# Debug (F3-Knöpfe, Rauchtest)
# ---------------------------------------------------------------------------

## Aufmerksamkeit direkt setzen (Stufe folgt im nächsten Takt)
func debug_set_awareness(observer: Kingdom, target: Kingdom, value: float) -> void:
	if observer == null or target == null or observer == target:
		return
	awareness[pair_key(observer, target)] = clampf(value, 0.0, 100.0)


## Genaue Kundschaft über alle Reiche und Dörfer
func debug_full_intel(observer: Kingdom) -> void:
	if observer == null:
		return
	for k in game.kingdoms:
		if k != observer and k.controller != "wild":
			grant_intel(observer, k, 3, "Debug")


## Mitte der Burg (Ort für Meldungen) oder null
static func _castle_pos(k: Kingdom) -> Variant:
	if k != null and is_instance_valid(k.castle):
		return k.castle.get_center()
	return null


## Zahl mit Komma: "0,5", "12"
static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return str(roundi(v))
	return ("%.1f" % v).replace(".", ",")
