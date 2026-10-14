## AIBrain
##
## Das Gehirn eines KI-Reichs (Phase 7). Denkt im Takt des AISystems
## (alle ai_think_interval Spielsekunden, gestaffelt) und hat dazu einen billigen
## Schnelltakt (jede Spielsekunde) für Verteidigung, Angriffswellen, Zauber und
## Hilfe für Dörfer. Die eigentliche Arbeit steckt in Modulen mit statischen
## Funktionen, die das Gehirn bekommen:
##   AIEconomy  – Bauen, Bauplatz, Berufe, Forschung, Kampfpunkte
##   AIMilitary – Beschwören, Helden, Zauber, Verteidigung, Wellen, Lager, Rückzug
##   AIDiplomacy – Dörfer, Späher, Spione, Reichstarnung
## Alle Aktionen laufen über dieselben öffentlichen Schnittstellen wie beim Spieler.
##
## Zustand: nur in Kingdom.ai_state (einfache Werte, wird gespeichert; Schlüssel
## siehe default_state). Das Gehirn selbst ist Laufzeit und entsteht nach dem
## Laden aus dem Reich neu (AISystem.rebuild_runtime). Zeitstempel -1 = "noch nicht
## gesetzt" (werden beim ersten Takt gesetzt, weil die Spielzeit erst nach dem
## Aufbau zurückgesetzt wird).
class_name AIBrain
extends RefCounted

var sys: AISystem
var game: Node
var world: WorldData
var k: Kingdom
## Verweis auf k.ai_state
var st: Dictionary = {}
## Persönlichkeit (ai.json personalities) und Schwierigkeit (zwischengespeichert)
var personality: Dictionary = {}
var diff: Dictionary = {}

## Laufzeit: nächster Verteidigungs-Scan und letzte Feindstärke im Gebiet (AIMilitary)
var next_scan := -1.0
var enemy_power := 0.0
## Laufzeit: Prüfbudget der Bauplatzsuche im aktuellen Denkvorgang (AIEconomy):
## can_place-Aufrufe und betrachtete Kacheln (begrenzt die Rechenzeit im schlechtesten Fall)
var checks_left := 0
var scan_left := 0


func _init(p_sys: AISystem, p_kingdom: Kingdom) -> void:
	sys = p_sys
	game = p_sys.game
	world = game.world
	k = p_kingdom
	ensure_state()
	st = k.ai_state
	personality = sys.get_personality(k)
	diff = sys.get_difficulty()


## Vorgaben für Kingdom.ai_state (alles einfache Werte):
## "personality", "next_think" (-1 = noch nicht), "think_count",
## "build_waiting" {"building", "since"} (wartet auf Geld), "skip_until" {Gebäude-id: Spielzeit},
## "ring_hint" {Gebäude-id: Ring des letzten Bauplatzes um die Burg},
## "home_rally" (ZERO = noch nicht), "mana_spots" [Vector2i], "mana_spots_key", "mana_spots_at",
## "alarm" {"pos", "attacker_id", "until", "last_enemy", "next_order"} ({} = keiner),
## "defending" [uids], "help" {"village_id", "pos", "until", "uids"},
## "wave" ({} = keine) {"id", "target_id", "target_kind" "kingdom"|"village"|"lair", "target_uid",
##   "target_pos", "rally", "uids", "state" "gather"|"march"|"fight"|"retreat", "started_at",
##   "state_at", "start_power", "next_reissue", "vs_player"},
## "waves_sent", "player_waves", "last_wave_end" (-1 = noch keine), "wave_counter",
## "scouts" {uid: "patrol"|"explore"}, "next_patrol", "village_next", "gift_value_hour", "spy_next",
## "upgrade_flip", "debug_army_min", "hero_saving" (Heldentyp, auf den gespart wird, "" = keiner),
## "log" {"first_building", "first_barracks", "first_summon", "first_research", "first_spy",
##   "first_wave", "first_player_wave", "first_lair", "first_hero"} (-1 = noch nicht; Rauchtest, README)
static func default_state(personality_id: String) -> Dictionary:
	return {
		"personality": personality_id, "next_think": -1.0, "think_count": 0,
		"build_waiting": {}, "skip_until": {}, "ring_hint": {},
		"home_rally": Vector2.ZERO, "mana_spots": [], "mana_spots_key": "", "mana_spots_at": -1.0,
		"alarm": {}, "defending": [], "help": {},
		"wave": {}, "waves_sent": 0, "player_waves": 0, "last_wave_end": -1.0, "wave_counter": 0,
		"scouts": {}, "next_patrol": -1.0, "village_next": -1.0,
		"gift_value_hour": {"hour": -1, "value": 0.0}, "spy_next": -1.0,
		"upgrade_flip": false, "debug_army_min": 0, "hero_saving": "",
		"log": {"first_building": -1.0, "first_barracks": -1.0, "first_summon": -1.0, "first_research": -1.0,
				"first_spy": -1.0, "first_wave": -1.0, "first_player_wave": -1.0, "first_lair": -1.0, "first_hero": -1.0},
	}


## Fehlende Schlüssel ergänzen (nach dem Laden eines älteren Spielstands)
func ensure_state() -> void:
	var defaults := default_state(str(k.ai_state.get("personality", "balanced")))
	for key in defaults:
		if not k.ai_state.has(key):
			k.ai_state[key] = defaults[key]
	var log_entry: Dictionary = k.ai_state["log"]
	for key in defaults["log"]:
		if not log_entry.has(key):
			log_entry[key] = -1.0


## Kann das Reich noch handeln? (nicht besiegt, Burg steht)
func is_active() -> bool:
	return not k.defeated and is_instance_valid(k.castle)


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

## Ein Denkvorgang (vom AISystem gestaffelt aufgerufen)
func think(now: float) -> void:
	st["think_count"] = int(st["think_count"]) + 1
	if not is_active():
		return
	checks_left = int(DataDB.ai("placement.max_checks", 400))
	scan_left = checks_left * AIEconomy.SCAN_PER_CHECK
	var n := int(st["think_count"])
	var t0 := Time.get_ticks_usec()
	AIEconomy.tick_build(self, now)
	t0 = _measure("build", t0)
	# Berufe jeden zweiten Denkvorgang, bei Unbeschäftigten sofort
	if n % 2 == 0 or (game.work_system as WorkSystem).get_idle_count(k) > 0:
		AIEconomy.tick_jobs(self)
		t0 = _measure("jobs", t0)
	if n % 2 == 0:
		AIEconomy.tick_research(self, now)
		AIEconomy.tick_upgrades(self)
		t0 = _measure("research", t0)
	AIMilitary.tick_summon(self, now)
	t0 = _measure("summon", t0)
	if n % 3 == 0:
		AIMilitary.tick_heroes(self, now)
		t0 = _measure("heroes", t0)
	if now >= float(st["spy_next"]):
		var spy_mult := maxf(float(personality.get("spy_mult", 1.0)), 0.1)
		st["spy_next"] = now + float(DataDB.ai("spies.interval", 30)) / spy_mult
		AIDiplomacy.tick_scouts(self, now)
		AIDiplomacy.tick_spies(self, now)
	if now >= float(st["village_next"]):
		st["village_next"] = now + float(DataDB.ai("villages.interval", 60))
		AIDiplomacy.tick_villages(self, now)
	t0 = _measure("diplomacy", t0)
	if (st["wave"] as Dictionary).is_empty() and (st["alarm"] as Dictionary).is_empty():
		AIMilitary.plan_wave(self, now)
	t0 = _measure("waves", t0)
	AIMilitary.tick_peace_spells(self, now)
	AIDiplomacy.tick_cloak(self, now)
	_measure("spells", t0)


## Rechenzeit eines Teils des Denkvorgangs in AISystem.stats.parts eintragen
## (Mikrosekunden gesamt); gibt den neuen Startzeitpunkt zurück
func _measure(part: String, since: int) -> int:
	var now_usec := Time.get_ticks_usec()
	var parts: Dictionary = sys.stats.get("parts", {})
	parts[part] = int(parts.get(part, 0)) + now_usec - since
	sys.stats["parts"] = parts
	return now_usec


## Schnelltakt (jede Spielsekunde): billig, nur Zustandsmaschinen
func fast_tick(now: float) -> void:
	if not is_active():
		return
	AIMilitary.fast_defense(self, now)
	AIMilitary.fast_wave(self, now)
	AIMilitary.fast_spells(self, now)
	AIMilitary.fast_help(self, now)


## Das Reich ist gefallen: laufende Welle beenden, nichts mehr befehlen
func shutdown(now: float) -> void:
	if not (st["wave"] as Dictionary).is_empty():
		AIMilitary.end_wave(self, now, "recalled")
	st["alarm"] = {}
	st["help"] = {}
	st["defending"] = []


# ---------------------------------------------------------------------------
# Ereignisse (nur Zustand – Befehle folgen im Schnelltakt)
# ---------------------------------------------------------------------------

## Angriff auf das Reich bei pos (vom AISystem aus kingdom_attacked oder Sichtungen).
## Gilt nur im eigenen Gebiet (plus defense.defense_radius Kacheln).
func on_alarm(pos: Vector2, attacker_id: int) -> void:
	if not is_active() or not is_near_home(pos, float(DataDB.ai("defense.defense_radius", 12))):
		return
	var now := GameClock.game_time
	var alarm: Dictionary = st["alarm"]
	if alarm.is_empty():
		st["alarm"] = {"pos": pos, "attacker_id": attacker_id, "until": now + float(DataDB.ai("defense.alarm_seconds", 30)),
				"last_enemy": now, "next_order": now}
	else:
		alarm["pos"] = pos
		alarm["attacker_id"] = attacker_id
		alarm["until"] = now + float(DataDB.ai("defense.alarm_seconds", 30))
		alarm["last_enemy"] = now


## Ein Dorf bittet um Hilfe (Schutzvertrag, Bote): bis until bei pos helfen
func request_help(village: Kingdom, pos: Vector2, until: float) -> void:
	if not is_active() or village == null:
		return
	var help: Dictionary = st["help"]
	if not help.is_empty() and int(help.get("village_id", 0)) != village.id and GameClock.game_time < float(help["until"]):
		return  # schon woanders im Einsatz
	var uids: Array = help.get("uids", []) if int(help.get("village_id", 0)) == village.id else []
	st["help"] = {"village_id": village.id, "pos": pos, "until": until, "uids": uids}


## Merkt die Spielzeit eines ersten Ereignisses (Zeitleiste für Rauchtest/README)
func log_first(key: String, now: float) -> void:
	var log_entry: Dictionary = st["log"]
	if float(log_entry.get(key, -1.0)) < 0.0:
		log_entry[key] = now


# ---------------------------------------------------------------------------
# Hilfen für die Module
# ---------------------------------------------------------------------------

## Spielminuten
func minutes(now: float) -> float:
	return now / 60.0


## Zeitsperre erfüllt? (Debug-Tempo des AISystems hebt alle Sperren auf)
func time_ok(now: float, min_minutes: float) -> bool:
	return sys.debug_fast or minutes(now) >= min_minutes


## Kampfkraft einer Einheit (wie bei Dörfern und der Entdeckung)
func power(u: Unit) -> float:
	return VillageSystem.unit_power(u)


## Summe der Kampfkraft
func power_of(units: Array) -> float:
	var total := 0.0
	for u in units:
		total += power(u)
	return total


## Eigene lebende Truppen: Kämpfer, Helden und Heiler – ohne Späher, Spione, Boten,
## König und beschworene Zaubereinheiten
func army_units() -> Array:
	var list: Array = []
	for u in k.units:
		if not u.is_alive() or u.expires_at >= 0.0:
			continue
		if u.role != "combat" and u.role != "hero" and u.role != "support":
			continue
		if u.tier == "scout" or u.tier == "spy":
			continue
		list.append(u)
	return list


## Truppen zu Hause: ohne Wellen- und Hilfstrupps
func home_pool() -> Array:
	var busy := {}
	for uid in (st["wave"] as Dictionary).get("uids", []):
		busy[int(uid)] = true
	for uid in (st["help"] as Dictionary).get("uids", []):
		busy[int(uid)] = true
	var list: Array = []
	for u in army_units():
		if not busy.has(u.uid):
			list.append(u)
	return list


## Lebende Einheiten zu den uids
func units_of(uids: Array) -> Array:
	var list: Array = []
	for uid in uids:
		var u: Variant = game.find_by_uid(int(uid))
		if u is Unit and is_instance_valid(u) and (u as Unit).is_alive() and (u as Unit).kingdom == k:
			list.append(u)
	return list


## uids einer Liste von Einheiten
static func uids_of(units: Array) -> Array:
	var list: Array = []
	for u in units:
		list.append(u.uid)
	return list


## Mittelpunkt einer Gruppe (ZERO bei leerer Liste)
static func centroid(units: Array) -> Vector2:
	if units.is_empty():
		return Vector2.ZERO
	var c := Vector2.ZERO
	for u in units:
		c += u.position
	return c / float(units.size())


## Mitte der Burg (Weltpixel)
func home_center() -> Vector2:
	return k.castle.get_center() if is_instance_valid(k.castle) else st.get("home_rally", Vector2.ZERO)


## Gebiet des Reichs als Rechteck (Kacheln)
func territory_rect() -> Rect2i:
	return TerritorySystem.kingdom_bbox(k, world)


## Halbe Ausdehnung des Gebiets in Kacheln (mindestens der Burgradius)
func territory_radius_tiles() -> float:
	var rect := territory_rect()
	var c := world.world_to_cell(home_center())
	var r := 0
	if rect.has_area():
		r = maxi(maxi(c.x - rect.position.x, rect.end.x - c.x), maxi(c.y - rect.position.y, rect.end.y - c.y))
	return maxf(float(r), float(DataDB.get_building("castle").get("territory_radius", 14)))


## Liegt pos im eigenen Gebiet oder höchstens extra_tiles davor (Rechteck)?
func is_near_home(pos: Vector2, extra_tiles: float) -> bool:
	var cell := world.world_to_cell(pos)
	if world.get_owner(cell) == k.id:
		return true
	var rect := territory_rect().grow(ceili(extra_tiles))
	return rect.has_point(cell)


## Sammelpunkt vor der Burg (Richtung Kartenmitte, 5 Kacheln vor dem Anfahrpunkt);
## einmal berechnet und in ai_state gemerkt
func home_rally() -> Vector2:
	var rally: Vector2 = st.get("home_rally", Vector2.ZERO)
	if rally != Vector2.ZERO or not is_instance_valid(k.castle):
		return rally
	var center := k.castle.get_center()
	var mid := world.get_pixel_size() * 0.5
	var dir := (mid - center).normalized() if mid.distance_to(center) > 1.0 else Vector2.DOWN
	var approach := k.castle.get_approach_point(center + dir * 1000.0)
	var cell: Vector2i = game.nav.nearest_free(world.world_to_cell(approach + dir * 5.0 * world.tile_size), 6)
	rally = world.cell_to_world(cell) if cell.x >= 0 else approach
	st["home_rally"] = rally
	return rally


## Kosten, die nach einer Ausgabe mindestens übrig bleiben müssen: Reserve
## (army.reserve) plus der Bauplan und der Held, auf die gerade gespart wird
func reserve_cost() -> Dictionary:
	var total: Dictionary = (DataDB.ai("army.reserve", {}) as Dictionary).duplicate()
	var waiting: Dictionary = st["build_waiting"]
	if not waiting.is_empty():
		var cost: Dictionary = DataDB.get_building(str(waiting.get("building", ""))).get("cost", {})
		for res in cost:
			total[res] = float(total.get(res, 0.0)) + float(cost[res])
	var hero := str(st.get("hero_saving", ""))
	if not hero.is_empty():
		var hero_cost: Dictionary = game.hero_system.recruit_cost(k, hero)
		for res in hero_cost:
			total[res] = float(total.get(res, 0.0)) + float(hero_cost[res])
	return total


## Kann das Reich cost ausgeben und behält dabei die Reserve? (Nur die Ressourcen,
## die cost braucht: ein Sparziel in Erz hält keine Bogenschützen ohne Erz auf.)
func can_spend(cost: Dictionary, with_reserve: bool = true) -> bool:
	if not with_reserve:
		return k.can_afford(cost)
	var reserve := reserve_cost()
	for res in cost:
		if float(cost[res]) > 0.0 and k.get_amount(str(res)) + 0.0001 < float(cost[res]) + float(reserve.get(res, 0.0)):
			return false
	return true
