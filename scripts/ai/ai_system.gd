## AISystem
##
## Gegnerische Königreiche (Phase 7). Gründet die KI-Reiche an den "kingdom"-Plätzen
## der Weltgenerierung (je ein Volk der Gegenfraktion, Krieg mit dem Spieler), setzt
## ihre Schwierigkeit (Quelle "difficulty") und lässt je Reich ein AIBrain denken:
## gestaffelt, höchstens ein Denkvorgang je Simulationstakt (alle ai_think_interval
## Spielsekunden je Reich), dazu jede Spielsekunde ein billiger Schnelltakt für
## Verteidigung, Wellen und Zauber. Führt ausserdem die Rivalität der KI-Reiche
## untereinander (AIRivalry). Die KI handelt nur über öffentliche Schnittstellen der
## Systeme – dieselben, die die Oberfläche des Spielers benutzt.
##
## Entdeckung und Kundschaft (Aufmerksamkeit, Intel, geschätzte Stärke) liefert das
## EspionageSystem (game.espionage_system): die KI greift ein Reich erst an, wenn sie
## es entdeckt hat (Gerüchte -> Spione, entdeckt -> Angriffe).
##
## Zustand (gespeichert): order, rivalry, rng_state, debug_fast, stats; je Reich
## Kingdom.ai_state. Laufzeit: Gehirne (_brains, entstehen aus den Reichen neu),
## _rivalry, _pending, _fast_acc. Signale aus dem Kampf legen nur Einträge in
## _pending; Befehle folgen erst im eigenen Takt.
class_name AISystem
extends Node

## Ein KI-Reich wurde gegründet
signal ai_kingdom_founded(k: Kingdom)
## Eine Angriffswelle sammelt sich (target: Reich, Dorf oder das Monster-Reich bei Lagern)
signal wave_started(k: Kingdom, target: Kingdom, size: int, rally: Vector2)
## Eine Welle ist beendet ("won" | "retreat" | "timeout" | "target_gone" | "recalled" | "lost")
signal wave_ended(k: Kingdom, target: Kingdom, reason: String)
## Zwei KI-Reiche sind jetzt im Krieg bzw. im Frieden
signal rivalry_changed(a: Kingdom, b: Kingdom, state: String)

## Schnelltakt der Gehirne (Spielsekunden)
const FAST_INTERVAL := 1.0
## Salz für den Zufall (Volkswahl bzw. laufende Entscheidungen)
const PEOPLE_SALT := 7411
const RNG_SALT := 7501

var game: Node

## KI-Reich-ids in Gründungsreihenfolge
var order: Array = []
## "a:b" (a < b) -> {"tension", "state" "peace"|"war", "since", "last_incident", "known_by_player"}
var rivalry: Dictionary = {}
## Zustand des gemeinsamen Zufalls (gespeichert)
var rng_state: int = 0
## Rauchtest/Debug: Denkpause 1 s, keine Zeitsperren (Angriffe, Helden, Forschung, Lager)
var debug_fast := false
## Messwerte: Anzahl Denkvorgänge und Rechenzeit in Mikrosekunden (parts: je Teil gesamt)
var stats := {"thinks": 0, "think_usec_total": 0, "think_usec_max": 0, "parts": {}}

## Laufzeit: Kingdom.id -> AIBrain
var _brains: Dictionary = {}
var _rivalry: AIRivalry
## Laufzeit: ["alarm", Reich-id, pos, Angreifer-id] | ["help", Reich-id, Dorf-id, pos, bis]
var _pending: Array = []
var _fast_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _difficulty: Dictionary = {}
## Begrüssung (Anzahl Reiche) beim ersten Takt, wenn die Meldungsanzeige bereit ist
var _welcome_pending := false


func setup(p_game: Node) -> void:
	game = p_game
	_rng.seed = hash(game.world.world_seed + RNG_SALT)
	rng_state = _rng.state
	_rivalry = AIRivalry.new(self)
	_difficulty = {}
	GameClock.sim_tick.connect(_on_sim_tick)
	GameClock.hour_passed.connect(_on_hour_passed)
	game.combat_system.kingdom_attacked.connect(_on_kingdom_attacked)
	var ds: DiplomacySystem = game.diplomacy_system
	ds.protection_requested.connect(_on_protection_requested)
	ds.aggression_reported.connect(_on_aggression_reported)
	var esp := espionage()
	if esp != null:
		esp.enemy_spotted.connect(_on_enemy_spotted)


# ---------------------------------------------------------------------------
# Gründung und Schwierigkeit
# ---------------------------------------------------------------------------

## Gründet die KI-Reiche: Anzahl aus ai.json → difficulty.kingdoms[Kartengrösse]
## (oder GameSession.ai_count_override), höchstens so viele, wie es Plätze gibt.
## Völker der Gegenfraktion, aus dem Seed gemischt (gleicher Seed = gleiche Völker).
func found_ai_kingdoms() -> void:
	var sites: Array = game.world.get_sites("kingdom")
	sites.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x.get("index", 0)) < int(y.get("index", 0)))
	var n := GameSession.ai_count_override
	if n < 0:
		n = int((get_difficulty().get("kingdoms", {}) as Dictionary).get(GameSession.map_size_id, 1))
	n = mini(n, sites.size())
	if n <= 0:
		if sites.is_empty():
			print("[ai] Warnung: keine Plätze für gegnerische Reiche auf dieser Karte")
		_welcome_pending = true
		return
	var enemy := enemy_faction(game.player.faction_id)
	var ids: Array = []
	for p in DataDB.get_peoples_of_faction(enemy):
		ids.append(str(p.get("id", "")))
	ids.sort()
	if ids.is_empty():
		push_error("ai.json/peoples.json: keine Völker der Fraktion %s" % enemy)
		return
	var shuffle := RandomNumberGenerator.new()
	shuffle.seed = hash(game.world.world_seed + PEOPLE_SALT)
	for i in range(ids.size() - 1, 0, -1):
		var j := shuffle.randi_range(0, i)
		var tmp: Variant = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	var founded: Array = []
	for i in n:
		var k := found_ai_kingdom(sites[i], str(ids[i % ids.size()]))
		if k != null:
			founded.append(k)
	for i in founded.size():
		for j in range(i + 1, founded.size()):
			_rivalry.init_pair(founded[i], founded[j])
	_welcome_pending = true


## Gründet ein KI-Reich an einem Platz: Volk, Name, Farbe, Schwierigkeit, Siedlung
## (wie beim Spieler), Startvorteil, Krieg mit dem Spieler, Gehirn
func found_ai_kingdom(site: Dictionary, people_id: String) -> Kingdom:
	var people := DataDB.get_people(people_id)
	var enemy := enemy_faction(game.player.faction_id)
	var names: Dictionary = DataDB.ai("kingdom_names", {})
	var display := str(names.get(enemy, "Reich der %s")) % str(people.get("name", people_id))
	var k: Kingdom = game.create_kingdom({"faction_id": enemy, "controller": "ai", "display_name": display,
			"color": _distinct_color(people.get("color", Color.WHITE))})
	k.people_id = people_id
	# Vor der Siedlung: Building.max_hp wird beim Aufbau festgelegt
	apply_difficulty(k)
	game.found_settlement(k, site["cell"])
	var d := get_difficulty()
	var mult := float(d.get("start_resources_mult", 1.0))
	if mult != 1.0:
		for res in k.resources.keys():
			k.resources[res] = float(k.resources[res]) * mult
	for i in int(d.get("extra_villagers", 0)):
		var pos: Vector2 = k.castle.get_approach_point(k.castle.get_center() + Vector2.from_angle(TAU * i / 5.0 + 1.1) * 1000.0)
		var u: Unit = game.unit_system.spawn_unit(k, "villager", pos)
		if u != null:
			game.work_system.set_unit_job(u, "idle")
	game.set_relation(game.player, k, "war")
	var personality_id := str((DataDB.ai("people_personality", {}) as Dictionary).get(people_id, "balanced"))
	if not (DataDB.ai("personalities", {}) as Dictionary).has(personality_id):
		personality_id = "balanced"
	k.ai_state = AIBrain.default_state(personality_id)
	_brains[k.id] = AIBrain.new(self, k)
	_apply_start_bonus(k)
	order.append(k.id)
	ai_kingdom_founded.emit(k)
	return k


## Startvorsprung der KI-Reiche (ai.json start_bonus): zusätzliche Bewohner und fertige Gebäude
## (kostenlos, Platz wie beim normalen Bauen der KI)
func _apply_start_bonus(k: Kingdom) -> void:
	var bonus: Dictionary = DataDB.ai("start_bonus", {})
	var extra := int(bonus.get("villagers", 0))
	for i in extra:
		var pos: Vector2 = k.castle.get_approach_point(k.castle.get_center() + Vector2.from_angle(TAU * i / maxf(extra, 1.0) + 0.5) * 1000.0)
		var u: Unit = game.unit_system.spawn_unit(k, "villager", pos)
		if u != null:
			game.work_system.set_unit_job(u, "idle")
	var brain := get_brain(k)
	for id in bonus.get("buildings", []):
		var def := DataDB.get_building(str(id))
		if def.is_empty() or brain == null:
			continue
		brain.checks_left = int(DataDB.ai("placement.max_checks", 400))
		brain.scan_left = brain.checks_left * AIEconomy.SCAN_PER_CHECK
		var cell := AIEconomy.find_site(brain, def)
		if cell.x >= 0 and (game.building_system as BuildingSystem).can_place_free(def, cell, k).is_empty():
			game.building_system.place_building(def, cell, k, true)


## Schwierigkeit als Quelle "difficulty": Ertrag (gather, production), Stärke (hp,
## attack, building_hp), Tempo (build, summon, research) und Wachsamkeit (Bonus)
## (Werte und Wirkung stehen in Difficulty)
func apply_difficulty(k: Kingdom) -> void:
	Difficulty.apply_ai(k)


## Schwierigkeit der Partie für die KI (difficulties.json + ai.json, zwischengespeichert)
func get_difficulty() -> Dictionary:
	if _difficulty.is_empty():
		_difficulty = DataDB.get_ai_difficulty(GameSession.difficulty_id)
	return _difficulty


## Denkpause je Reich in Spielsekunden (1 s im Debug-Tempo)
func get_think_interval() -> float:
	if debug_fast:
		return 1.0
	return maxf(float(get_difficulty().get("ai_think_interval", 5.0)), 0.5)


## Gegenfraktion ("good" <-> "evil")
static func enemy_faction(faction_id: String) -> String:
	return "good" if faction_id == "evil" else "evil"


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## KI-Reiche in Gründungsreihenfolge (ohne include_defeated nur die aktiven)
func get_ai_kingdoms(include_defeated: bool = false) -> Array:
	var list: Array = []
	for kid in order:
		var k: Kingdom = game.get_kingdom(int(kid))
		if k != null and (include_defeated or not k.defeated):
			list.append(k)
	return list


## Gehirn eines KI-Reichs (null bei anderen oder gefallenen Reichen)
func get_brain(k: Kingdom) -> AIBrain:
	if k == null:
		return null
	return _brains.get(k.id, null)


## Persönlichkeit des Reichs (ai.json personalities, Standard balanced)
func get_personality(k: Kingdom) -> Dictionary:
	var all: Dictionary = DataDB.ai("personalities", {})
	var id := str(k.ai_state.get("personality", "balanced")) if k != null else "balanced"
	return all.get(id, all.get("balanced", {}))


## Rivalität zweier KI-Reiche ({} wenn es kein Paar gibt)
func get_rivalry(a: Kingdom, b: Kingdom) -> Dictionary:
	if a == null or b == null:
		return {}
	return rivalry.get(AIRivalry.pair_key(a, b), {})


## Andere aktive KI-Reiche
func get_rivals(k: Kingdom) -> Array:
	var list: Array = []
	for o in get_ai_kingdoms():
		if o != k:
			list.append(o)
	return list


## Spannung zwischen zwei KI-Reichen ändern (Spione, Ereignisse)
func add_tension(a: Kingdom, b: Kingdom, amount: float, reason: String) -> void:
	if a != null and b != null:
		_rivalry.add_tension(a, b, amount, reason)


## Gemeinsamer, gespeicherter Zufall
func rand_float() -> float:
	var v := _rng.randf()
	rng_state = _rng.state
	return v


func rand_range(a: float, b: float) -> float:
	var v := _rng.randf_range(a, b)
	rng_state = _rng.state
	return v


# ---------------------------------------------------------------------------
# Entdeckung und Kundschaft (EspionageSystem, sobald vorhanden)
# ---------------------------------------------------------------------------

## Das EspionageSystem (game.espionage_system; null nur ohne Phase-7-Szene)
func espionage() -> EspionageSystem:
	var esp: Variant = game.get("espionage_system")
	return esp as EspionageSystem if is_instance_valid(esp) and esp is EspionageSystem else null


## Das SpySystem (game.spy_system; null nur ohne Phase-7-Szene)
func spies() -> SpySystem:
	var sys: Variant = game.get("spy_system")
	return sys as SpySystem if is_instance_valid(sys) and sys is SpySystem else null


## Aufmerksamkeit von observer auf target (0–100, EspionageSystem)
func get_awareness(observer: Kingdom, target: Kingdom) -> float:
	var esp := espionage()
	return esp.get_awareness(observer, target) if esp != null else 0.0


## Kundschaft von observer über target (0–3, EspionageSystem)
func get_intel_level(observer: Kingdom, target: Kingdom) -> int:
	var esp := espionage()
	return esp.get_intel_level(observer, target) if esp != null else 0


## Geschätzte Abwehr eines Reichs aus Sicht von viewer (Kampfkraft, ab Kundschaft 2);
## ohne Kundschaft waves.unknown_defense
func estimate_defense(viewer: Kingdom, target: Kingdom) -> float:
	var esp := espionage()
	if esp != null:
		var est := esp.estimate_strength(viewer, target)
		if bool(est.get("known", false)):
			return float(est.get("value", 0.0))
	return float(DataDB.ai("waves.unknown_defense", 60))


# ---------------------------------------------------------------------------
# Meldungen der Gehirne (Signale nach aussen)
# ---------------------------------------------------------------------------

## Welle gestartet: Signal; der Spieler hört nur mit Kundschaft (Intel >= 2) davon
func notify_wave_started(k: Kingdom, target: Kingdom, size: int, rally: Vector2) -> void:
	wave_started.emit(k, target, size, rally)
	var player: Kingdom = game.player
	if target == player and player != null and get_intel_level(player, k) >= 2:
		player.notify("Kundschaft: %s sammelt ein Heer (%d) gegen dich!" % [k.display_name, size], "danger", rally)


func notify_wave_ended(k: Kingdom, target: Kingdom, reason: String) -> void:
	wave_ended.emit(k, target, reason)


func notify_rivalry_changed(a: Kingdom, b: Kingdom, state: String) -> void:
	rivalry_changed.emit(a, b, state)


## Ein Reich ist gefallen (vom VictorySystem): Gehirn stilllegen, Welle beenden,
## Rivalität entfernen
func on_kingdom_defeated(k: Kingdom) -> void:
	if k == null:
		return
	var brain: AIBrain = _brains.get(k.id, null)
	if brain != null:
		brain.shutdown(GameClock.game_time)
		_brains.erase(k.id)
	for key in rivalry.keys():
		var parts := str(key).split(":")
		if int(parts[0]) == k.id or int(parts[1]) == k.id:
			rivalry.erase(key)


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	var now := GameClock.game_time
	if _welcome_pending:
		_welcome_pending = false
		_post_welcome()
	if not _pending.is_empty():
		var list := _pending
		_pending = []
		for entry in list:
			_handle_pending(entry)
	_fast_acc += dt
	if _fast_acc >= FAST_INTERVAL:
		_fast_acc = 0.0
		for kid in order:
			var brain: AIBrain = _brains.get(kid, null)
			if brain != null:
				brain.fast_tick(now)
	_think_one(now)


## Höchstens ein Denkvorgang je Takt: das erste Gehirn, das an der Reihe ist. Beim
## ersten Mal wird die Startzeit gestaffelt (nicht alle Reiche im selben Takt).
func _think_one(now: float) -> void:
	var interval := get_think_interval()
	var n := order.size()
	for i in n:
		var brain: AIBrain = _brains.get(order[i], null)
		if brain == null:
			continue
		var next := float(brain.st["next_think"])
		if next < 0.0:
			brain.st["next_think"] = now + interval * float(i + 1) / float(n + 1)
			continue
		if now < next:
			continue
		var t0 := Time.get_ticks_usec()
		brain.think(now)
		var used := Time.get_ticks_usec() - t0
		brain.st["next_think"] = now + interval * rand_range(0.9, 1.1)
		stats["thinks"] = int(stats["thinks"]) + 1
		stats["think_usec_total"] = int(stats["think_usec_total"]) + used
		stats["think_usec_max"] = maxi(int(stats["think_usec_max"]), used)
		return


func _handle_pending(entry: Array) -> void:
	var brain: AIBrain = _brains.get(int(entry[1]), null)
	if brain == null:
		return
	match str(entry[0]):
		"alarm":
			brain.on_alarm(entry[2], int(entry[3]))
		"help":
			var village: Kingdom = game.get_kingdom(int(entry[2]))
			brain.request_help(village, entry[3], float(entry[4]))


func _on_hour_passed(_day: int, _hour: int) -> void:
	_rivalry.on_hour()


## Begrüssung: Anzahl der feindlichen Reiche (Ort: nächste KI-Burg)
func _post_welcome() -> void:
	var player: Kingdom = game.player
	if player == null:
		return
	var list := get_ai_kingdoms()
	if list.is_empty():
		player.notify("Keine gegnerischen Reiche auf dieser Karte – freies Spiel.", "info")
		return
	var from: Vector2 = player.castle.get_center() if is_instance_valid(player.castle) else Vector2.ZERO
	var nearest: Kingdom = null
	var best := INF
	for k in list:
		if is_instance_valid(k.castle) and from.distance_to(k.castle.get_center()) < best:
			best = from.distance_to(k.castle.get_center())
			nearest = k
	var pos: Variant = null
	if nearest != null:
		pos = nearest.castle.get_center()
	player.notify("Im Land herrschen %d feindliche Königreiche. Je grösser und lauter dein Reich, desto eher wirst du entdeckt – Spionage mit K." \
			% list.size(), "info", pos)


## Kampfsignal (mitten in der Kampfschleife): nur vormerken
func _on_kingdom_attacked(victim: Kingdom, attacker: Kingdom, pos: Vector2) -> void:
	if victim == null or attacker == null or victim == attacker:
		return
	if _brains.has(victim.id):
		_pending.append(["alarm", victim.id, pos, attacker.id])
	if _brains.has(victim.id) and _brains.has(attacker.id):
		_rivalry.on_incident(victim, attacker)


## Späher melden Feinde im Gebiet (EspionageSystem)
func _on_enemy_spotted(observer: Kingdom, foe: Kingdom, pos: Vector2, _count: int, inside: bool) -> void:
	if inside and observer != null and foe != null and _brains.has(observer.id):
		_pending.append(["alarm", observer.id, pos, foe.id])


## Schutzvertrag: das angegriffene Dorf bittet seinen Schutzherrn um Hilfe
func _on_protection_requested(village: Kingdom, protector: Kingdom, _attacker: Kingdom, deadline: float) -> void:
	if village == null or protector == null or not _brains.has(protector.id):
		return
	_pending.append(["help", protector.id, village.id, game.village_system.get_center(village), deadline])


## Bote: ein Dorf meldet einen Angriff. Die KI hilft nur befreundeten Dörfern oder
## Vertragspartnern.
func _on_aggression_reported(receiver: Kingdom, _aggressor: Kingdom, village: Kingdom) -> void:
	if receiver == null or village == null or not _brains.has(receiver.id):
		return
	var ds: DiplomacySystem = game.diplomacy_system
	var friendly := ds.get_reputation(village, receiver) >= DiplomacySystem.tier_min("friendly", 30.0)
	if not friendly and ds.get_treaty_with(village, receiver).is_empty():
		return
	_pending.append(["help", receiver.id, village.id, game.village_system.get_center(village),
			GameClock.game_time + float(DataDB.ai("villages.help_seconds", 90))])


## Farbe, die sich vom Spieler und den anderen KI-Reichen abhebt (sonst abwechselnd
## heller bzw. dunkler)
func _distinct_color(base: Color) -> Color:
	var color := base
	var others: Array = [game.player.color]
	for k in get_ai_kingdoms(true):
		others.append(k.color)
	for attempt in 6:
		var clash := false
		for o in others:
			var oc: Color = o
			if absf(color.r - oc.r) + absf(color.g - oc.g) + absf(color.b - oc.b) < 0.25:
				clash = true
				break
		if not clash:
			break
		var step := 0.3 * float((attempt >> 1) + 1)
		color = base.lightened(step) if attempt % 2 == 0 else base.darkened(step)
	return color


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	rng_state = _rng.state
	return {"order": order.duplicate(), "rivalry": rivalry.duplicate(true), "rng_state": rng_state,
			"debug_fast": debug_fast, "stats": stats.duplicate(true), "pending": _pending.duplicate(true),
			"fast_acc": _fast_acc}


func from_dict(d: Dictionary) -> void:
	order = (d.get("order", []) as Array).duplicate()
	rivalry = (d.get("rivalry", {}) as Dictionary).duplicate(true)
	rng_state = int(d.get("rng_state", 0))
	debug_fast = bool(d.get("debug_fast", false))
	stats = (d.get("stats", stats) as Dictionary).duplicate(true)
	_pending = (d.get("pending", []) as Array).duplicate(true)
	_fast_acc = float(d.get("fast_acc", 0.0))


## Gehirne aus den Reichen neu aufbauen (nach dem Laden; die Schwierigkeit setzt
## Difficulty.reapply_all davor, die Warteliste _pending ist gespeichert)
func rebuild_runtime() -> void:
	_rng.state = rng_state
	_rivalry = AIRivalry.new(self)
	_difficulty = {}
	_brains.clear()
	for kid in order:
		var k: Kingdom = game.get_kingdom(int(kid))
		if k != null and not k.defeated:
			_brains[k.id] = AIBrain.new(self, k)


# ---------------------------------------------------------------------------
# Debug (F3-Knöpfe, Rauchtest)
# ---------------------------------------------------------------------------

## +2000 je Ressource, Burgstufe Stadt, Kundschafter-, Waffen- und Elite-Forschung, fehlende Kaserne,
## Bibliothek und Heldenhalle sofort bauen; das Armee-Soll steigt auf mindestens 8
func debug_boost(k: Kingdom) -> void:
	var brain := get_brain(k)
	if brain == null:
		return
	var gift := {}
	for r in DataDB.resources:
		gift[str(r["id"])] = 2000.0
	k.refund(gift)
	var rs: ResearchSystem = game.research_system
	var wanted: Array = ["good_tools", "good_weapons", "good_knights", "good_scouting"] if k.faction_id == "good" \
			else ["evil_hardhand", "evil_blades", "evil_dread", "evil_informants"]
	for id in wanted:
		if not DataDB.get_research(str(id)).is_empty() and not k.researched.has(id):
			k.researched[id] = true
			rs.apply_effects(k, str(id))
	var bs: BuildingSystem = game.building_system
	# Burgstufe Stadt: Kaserne, Bibliothek und Heldenhalle dürfen stehen
	bs.set_castle_level(k, 3)
	for id in ["barracks", "library", "hero_hall"]:
		var def := DataDB.get_building(str(id))
		if def.is_empty() or bs.count_buildings(k, str(id), true) > 0:
			continue
		brain.checks_left = 2000
		brain.scan_left = 20000
		var cell := AIEconomy.find_site(brain, def)
		if cell.x >= 0:
			bs.place_building(def, cell, k, true)
	k.ai_state["debug_army_min"] = 8
	print("[ai] Debug: %s verstärkt" % k.display_name)


## Welle sofort planen, alle Sperren aus. false, wenn das Reich keine Truppen hat.
func debug_force_attack(k: Kingdom, target: Kingdom) -> bool:
	var brain := get_brain(k)
	if brain == null:
		return false
	return AIMilitary.force_wave(brain, GameClock.game_time, target)


## Laufende Welle zurückrufen (Rückzug zum Sammelpunkt)
func debug_recall_wave(k: Kingdom) -> void:
	var brain := get_brain(k)
	if brain != null:
		AIMilitary.start_retreat(brain, GameClock.game_time, "recalled")


## Spannung zweier KI-Reiche setzen (Wechsel zur nächsten vollen Spielstunde)
func debug_set_tension(a: Kingdom, b: Kingdom, value: float) -> void:
	if a != null and b != null:
		_rivalry.set_tension(a, b, value)
