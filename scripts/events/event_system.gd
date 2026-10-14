## EventSystem
##
## Zufallsereignisse (Phase 8, data/events.json): Dürre, Seuche, Magiesturm,
## Monsterwelle, Flüchtlinge, Wanderer, Erntedank und Manablüte. Sie sind selten
## (erst nach first_event_minutes, globale Mindestpause, Abklingzeit je Ereignis,
## Mindestabstand je Reich) und gelten für alle Reiche (Spieler, KI, Dörfer).
## Wirkungen auf Reiche laufen über die Quelle "event:<id>#<nr>", Wirkungen auf
## Einheiten über MagicSystem.add_unit_effect (Quelle "event:<id>").
## Flüchtlinge und Wanderer gehören dem eigenen Reich "Wanderer"; sie warten am Rand
## des Zielgebiets, bis das Ziel sie aufnimmt oder abweist (die KI entscheidet selbst).
## Unter ihnen kann ein Spion eines feindlichen Reichs sein (SatisfactionSystem).
## Monsterwellen erzeugt das MonsterSystem (spawn_wave); dieses System fragt nur
## get_raid ab.
##
## Zustand (gespeichert): active, history, cooldowns, kingdom_last, last_event_at,
## next_check, offers, next_id, wanderer_kingdom_id, rng_state. Kranke und Sturm-
## wirkungen stehen als normale Wirkungen auf den Einheiten.
class_name EventSystem
extends Node

## Ein Ereignis hat begonnen
signal event_started(ev: Dictionary)
## Ein Ereignis ist zu Ende ("time", "cleared", "debug", "target_gone", "resolved")
signal event_ended(ev: Dictionary, reason: String)
## Flüchtlinge/Wanderer bitten ein Reich um Aufnahme
signal offer_created(offer: Dictionary)
## Angebot erledigt (aufgenommen oder abgewiesen/verfallen)
signal offer_resolved(offer: Dictionary, accepted: bool)
## Blitz im Magiesturm (nur Darstellung)
signal storm_strike(pos: Vector2)

## Höchstens so viele Kranke je Seuchen-Durchgang
const PLAGUE_PER_PASS := 60
## Höchstens so viele Einheiten bekommen je Durchgang Sturmwirkungen
const STORM_UNITS := 300

var game: Node
var world: WorldData

## Laufende Ereignisse: {"uid", "event_id", "kind", "target_ids", "pos", "radius" (Pixel), "started",
## "until" (-1 = ohne Dauer), "source", "data"}
var active: Array = []
## Verlauf: {"event_id", "target_id", "started", "ended", "outcome"}
var history: Array = []
## event_id -> Spielzeit, ab der es wieder möglich ist
var cooldowns: Dictionary = {}
## Reich-id -> Spielzeit des letzten Ereignisses dort
var kingdom_last: Dictionary = {}
var last_event_at: float = -1.0e9
var next_check: float = -1.0
## Angebote: id -> {"id", "event_uid", "event_id", "target_id", "uids", "state": "approaching"|"waiting"|"leaving",
## "dest", "spawn", "spawned", "expires", "gift", "spy_owner_id", "ai_decide_at", "count", "story", "next_target_id"}
var offers: Dictionary = {}
var next_id := 1
var wanderer_kingdom_id := 0
var rng_state: int = 0
## Rechenzeit (Rauchtest)
var tick_usec_total := 0
var tick_usec_max := 0
var tick_count := 0

var _rng := RandomNumberGenerator.new()
var _acc_1s := 0.0
var _acc_2s := 0.0
## uid -> Seuchen-Ereignis-uid (Laufzeit, aus active aufgebaut)
var _infected: Dictionary = {}
var _death_notified_at := -1.0e9


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_rng.seed = hash(world.world_seed + 8101)
	rng_state = _rng.state
	GameClock.sim_tick.connect(_on_sim_tick)
	game.unit_system.unit_removed.connect(_on_unit_removed)


## Eigenes Reich "Wanderer" für Flüchtlinge und Wanderer (nach allen anderen Reichen)
func create_wanderer_kingdom() -> Kingdom:
	var existing := get_wanderer_kingdom()
	if existing != null:
		return existing
	var k: Kingdom = game.create_kingdom({"faction_id": "neutral", "controller": "neutral", "display_name": "Wanderer",
			"color": Color("#c9b8a0")})
	k.flags["wanderers"] = true
	k.has_economy = false
	wanderer_kingdom_id = k.id
	return k


func get_wanderer_kingdom() -> Kingdom:
	return game.get_kingdom(wanderer_kingdom_id) if wanderer_kingdom_id > 0 else null


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Laufende Ereignisse (mit k: nur die, die k betreffen)
func get_active(k: Kingdom = null) -> Array:
	if k == null:
		return active
	var list: Array = []
	for ev in active:
		if affects(ev, k):
			list.append(ev)
	return list


## Betrifft das Ereignis das Reich?
func affects(ev: Dictionary, k: Kingdom) -> bool:
	if k == null:
		return false
	if (ev["target_ids"] as Array).has(k.id):
		return true
	if str(ev["kind"]) == "magic_storm":
		return ((ev["data"] as Dictionary).get("affected", []) as Array).has(k.id)
	return false


## Restzeit in Spielsekunden (-1 = ohne feste Dauer)
func get_remaining(ev: Dictionary) -> float:
	if float(ev["until"]) < 0.0:
		return -1.0
	return maxf(float(ev["until"]) - GameClock.game_time, 0.0)


## Mehrzeiliger Text: Name, Beschreibung, Ziel, Wirkungen, Restzeit
func describe(ev: Dictionary, viewer: Kingdom) -> String:
	var def := DataDB.get_event(str(ev["event_id"]))
	var lines: PackedStringArray = [str(def.get("name", ev["event_id"])), str(def.get("description", ""))]
	var names: PackedStringArray = []
	for kid in ev["target_ids"]:
		var k: Kingdom = game.get_kingdom(int(kid))
		if k != null:
			names.append("dein Reich" if k == viewer else k.display_name)
	if not names.is_empty():
		lines.append("Betrifft: " + ", ".join(names))
	var mods: Dictionary = def.get("modifiers", def.get("kingdom_modifiers", {}))
	var parts: PackedStringArray = []
	for key in mods:
		parts.append(DataDB.describe_modifier(str(key), float(mods[key])))
	if not parts.is_empty():
		lines.append("Wirkung: " + ", ".join(parts))
	var sat := float(def.get("satisfaction", 0.0))
	if absf(sat) > 0.001:
		lines.append("Zufriedenheit %+d" % roundi(sat))
	match str(ev["kind"]):
		"plague":
			lines.append("Kranke: %d" % ((ev["data"] as Dictionary).get("infected", {}) as Dictionary).size())
		"monster_wave":
			var raid: Dictionary = game.monster_system.get_raid(int((ev["data"] as Dictionary).get("raid_id", 0)))
			lines.append("Monster: %d" % (raid.get("uids", []) as Array).size())
	var rest := get_remaining(ev)
	if rest >= 0.0:
		lines.append("Noch %s" % time_text(rest))
	return "\n".join(lines)


## Zufriedenheit durch Ereignisse für ein Reich: [[Name, Wert], …]
func get_satisfaction_parts(k: Kingdom) -> Array:
	var parts: Array = []
	for ev in active:
		if not affects(ev, k):
			continue
		var def := DataDB.get_event(str(ev["event_id"]))
		var v := float(def.get("satisfaction", 0.0))
		if absf(v) < 0.001:
			continue
		if str(ev["kind"]) == "monster_wave":
			var raid: Dictionary = game.monster_system.get_raid(int((ev["data"] as Dictionary).get("raid_id", 0)))
			if raid.is_empty() or int(raid["target_id"]) != k.id:
				continue
		if str(ev["kind"]) == "refugees" or str(ev["kind"]) == "wanderers":
			continue
		parts.append([str(def.get("name", ev["event_id"])), v])
	return parts


func is_infected(u: Unit) -> bool:
	return is_instance_valid(u) and _infected.has(u.uid)


## Arbeitsleistung eines Kranken (1 = gesund)
func get_plague_work_mult(u: Unit) -> float:
	if not is_infected(u):
		return 1.0
	return float(DataDB.get_event("plague").get("work_mult", 0.5))


## Offene Angebote an ein Reich (nähern sich oder warten)
func get_offers(k: Kingdom) -> Array:
	var list: Array = []
	for id in offers:
		var o: Dictionary = offers[id]
		if k != null and int(o["target_id"]) == k.id and str(o["state"]) != "leaving":
			list.append(o)
	return list


func get_offer(offer_id: int) -> Dictionary:
	return offers.get(offer_id, {})


## Angebot, zu dem eine Einheit gehört ({} wenn keins)
func get_offer_of_unit(u: Unit) -> Dictionary:
	if not is_instance_valid(u):
		return {}
	for id in offers:
		var o: Dictionary = offers[id]
		if (o["uids"] as Array).has(u.uid):
			return o
	return {}


## Text für Dialog und Fenster: Personen, Wohnraum vorher/nachher, Nahrung, Geschenke, Warnung
func get_offer_text(offer: Dictionary, viewer: Kingdom) -> String:
	if offer.is_empty():
		return ""
	var k: Kingdom = game.get_kingdom(int(offer["target_id"]))
	var n := _alive_units(offer).size()
	var lines: PackedStringArray = []
	if k != null:
		var pop := k.get_population()
		var housing := k.get_housing()
		var line := "%d %s · Wohnraum %d/%d → %d/%d" % [n, "Person" if n == 1 else "Personen", pop, housing, pop + n, housing]
		if pop + n > housing:
			line += " (überfüllt: Zufriedenheit sinkt)"
		lines.append(line)
	var food := float(DataDB.get_unit_type("villager").get("food_per_day", 40)) * n
	lines.append("Nahrung: +%d pro Tag" % roundi(food))
	var gift: Dictionary = offer.get("gift", {})
	if not gift.is_empty():
		lines.append("Bringen mit: " + DataDB.cost_to_text(gift))
	if k != null and _has_hostile_party(k):
		lines.append("Unter Fremden können Spione sein.")
	var state := str(offer["state"])
	if state == "waiting":
		lines.append("Warten noch %s" % time_text(maxf(float(offer["expires"]) - GameClock.game_time, 0.0)))
	elif state == "approaching":
		lines.append("Unterwegs zum Rand deines Gebiets" if k == viewer else "Unterwegs")
	return "\n".join(lines)


func get_history() -> Array:
	return history


static func time_text(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	return "%d:%02d" % [floori(s / 60.0), s % 60] if s >= 60 else "%d s" % s


# ---------------------------------------------------------------------------
# Auslösen und Beenden
# ---------------------------------------------------------------------------

## Ereignis starten ("" = gestartet, sonst Grund). force: ohne Zeit- und Abklingsperren.
func trigger(event_id: String, target: Kingdom, force: bool = false) -> String:
	var def := DataDB.get_event(event_id)
	if def.is_empty():
		return "Unbekanntes Ereignis"
	if target == null or target.defeated:
		return "Kein gültiges Ziel"
	var now := GameClock.game_time
	if not force:
		if now < float(def.get("min_minutes", 0)) * 60.0:
			return "Noch zu früh"
		if float(cooldowns.get(event_id, -1.0)) > now:
			return "Klingt noch ab"
		if active.size() >= int(DataDB.evt("max_active", 3)):
			return "Zu viele Ereignisse"
	var kind := str(def["kind"])
	_rng.state = rng_state
	var ev := {"uid": next_id, "event_id": event_id, "kind": kind, "target_ids": [target.id], "pos": _center(target),
			"radius": 0.0, "started": now, "until": -1.0, "source": "event:%s#%d" % [event_id, next_id], "data": {}}
	var duration: Array = def.get("duration", [])
	if not duration.is_empty():
		var sev := 1.0 if bool(def.get("positive", false)) else _severity()
		ev["until"] = now + _rng.randf_range(float(duration[0]), float(duration[1])) * sev
	var reason := ""
	match kind:
		"drought":
			reason = _start_drought(ev, def, target)
		"kingdom_buff":
			reason = _start_buff(ev, def, target)
		"plague":
			reason = _start_plague(ev, def, target, force)
		"magic_storm":
			reason = _start_storm(ev, def, target)
		"monster_wave":
			reason = _start_wave(ev, def, target)
		"refugees", "wanderers":
			reason = _start_offer(ev, def, target)
		_:
			reason = "Unbekannte Ereignisart"
	if not reason.is_empty():
		rng_state = _rng.state
		return reason
	next_id += 1
	active.append(ev)
	cooldowns[event_id] = now + float(def.get("cooldown_minutes", 60)) * 60.0
	last_event_at = now
	for kid in ev["target_ids"]:
		kingdom_last[int(kid)] = now
	rng_state = _rng.state
	event_started.emit(ev)
	_notify_start(ev, def)
	return ""


## Ereignis beenden (Wirkungen entfernen, Verlauf, Meldung)
func end_event(ev_uid: int, reason: String) -> void:
	var ev := _find(ev_uid)
	if ev.is_empty():
		return
	var def := DataDB.get_event(str(ev["event_id"]))
	var outcome := str((ev["data"] as Dictionary).get("outcome", ""))
	match str(ev["kind"]):
		"drought", "kingdom_buff":
			for kid in ev["target_ids"]:
				var k: Kingdom = game.get_kingdom(int(kid))
				if k != null:
					k.clear_modifiers(str(ev["source"]))
		"magic_storm":
			for kid in (ev["data"] as Dictionary).get("affected", []):
				var k: Kingdom = game.get_kingdom(int(kid))
				if k != null:
					k.clear_modifiers(str(ev["source"]))
		"plague":
			_cure_all(ev)
			if outcome.is_empty():
				outcome = "überstanden" if reason == "cleared" else "abgeklungen"
		"monster_wave":
			if outcome.is_empty():
				outcome = "abgezogen"
		"refugees", "wanderers":
			if reason == "debug":
				for id in offers.keys():
					if int((offers[id] as Dictionary)["event_uid"]) == ev_uid:
						_remove_group(offers[id])
						offers.erase(id)
	if outcome.is_empty():
		outcome = str({"time": "vorbei", "debug": "beendet", "target_gone": "Ziel verloren"}.get(reason, "vorbei"))
	active.erase(ev)
	history.append({"event_id": str(ev["event_id"]), "target_id": int((ev["target_ids"] as Array)[0]) if not (ev["target_ids"] as Array).is_empty() else 0,
			"started": float(ev["started"]), "ended": GameClock.game_time, "outcome": outcome})
	while history.size() > int(DataDB.evt("history_size", 20)):
		history.remove_at(0)
	event_ended.emit(ev, reason)
	var player: Kingdom = game.player
	if player != null and affects(ev, player) and str(ev["kind"]) != "refugees" and str(ev["kind"]) != "wanderers" \
			and reason != "debug":
		if str(ev["kind"]) == "monster_wave" and outcome == "zurückgeschlagen":
			player.notify("Die Monsterwelle wurde zurückgeschlagen!", "good", ev["pos"])
		else:
			player.notify("Ereignis vorbei: %s." % str(def.get("name", ev["event_id"])), "info")


# ---------------------------------------------------------------------------
# Aufbau je Art
# ---------------------------------------------------------------------------

func _start_drought(ev: Dictionary, def: Dictionary, target: Kingdom) -> String:
	var center := _center(target)
	if center.x < 0.0:
		return "Ziel ohne Siedlung"
	var ts := float(world.tile_size)
	var r: Array = def.get("region_radius", [50, 80])
	ev["pos"] = center + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 20.0) * ts
	ev["radius"] = _rng.randf_range(float(r[0]), float(r[1])) * ts
	var ids: Array = [target.id]
	for e in game.kingdoms:
		var k: Kingdom = e
		if k == target or k.defeated or not _is_settlement(k):
			continue
		var c := _center(k)
		if c.x >= 0.0 and c.distance_to(ev["pos"]) <= float(ev["radius"]):
			ids.append(k.id)
	ev["target_ids"] = ids
	var mods := _float_dict(def.get("modifiers", {}))
	for kid in ids:
		(game.get_kingdom(int(kid)) as Kingdom).replace_modifiers(str(ev["source"]), mods)
	return ""


func _start_buff(ev: Dictionary, def: Dictionary, target: Kingdom) -> String:
	target.replace_modifiers(str(ev["source"]), _float_dict(def.get("modifiers", {})))
	return ""


func _start_plague(ev: Dictionary, def: Dictionary, target: Kingdom, force: bool) -> String:
	var inhabitants: Array = []
	for u in target.units:
		if bool(u.type_def.get("needs_housing", false)) and u.is_alive() and not _infected.has(u.uid):
			inhabitants.append(u)
	if inhabitants.is_empty():
		return "Keine Bewohner"
	if not force and inhabitants.size() < int(def.get("min_population", 0)):
		return "Zu wenige Bewohner"
	ev["data"] = {"infected": {}, "immune": [], "next_spread": GameClock.game_time + float(def.get("spread_interval", 10))}
	var start: Array = def.get("start_infected", [1, 2])
	var n := clampi(_rng.randi_range(int(start[0]), int(start[1])), 1, inhabitants.size())
	for i in n:
		var j := _rng.randi_range(i, inhabitants.size() - 1)
		var tmp: Variant = inhabitants[i]
		inhabitants[i] = inhabitants[j]
		inhabitants[j] = tmp
		_infect(ev, def, inhabitants[i])
	ev["pos"] = (inhabitants[0] as Unit).position
	return ""


func _start_storm(ev: Dictionary, def: Dictionary, target: Kingdom) -> String:
	var center := _center(target)
	if center.x < 0.0:
		return "Ziel ohne Siedlung"
	var ts := float(world.tile_size)
	var r: Array = def.get("region_radius", [35, 55])
	ev["pos"] = center + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 10.0) * ts
	ev["radius"] = _rng.randf_range(float(r[0]), float(r[1])) * ts
	var now := GameClock.game_time
	ev["data"] = {"drift": Vector2.from_angle(_rng.randf() * TAU) * float(def.get("drift_tiles_per_minute", 6)) / 60.0,
			"affected": [], "next_swing": now + float((def.get("mana_swing", {}) as Dictionary).get("interval", 30)),
			"next_strike": now + float(def.get("strike_interval", 6)), "next_affect": now}
	_update_storm_kingdoms(ev, def)
	return ""


func _start_wave(ev: Dictionary, def: Dictionary, target: Kingdom) -> String:
	var center := _center(target)
	if center.x < 0.0:
		return "Ziel ohne Siedlung"
	var ms: MonsterSystem = game.monster_system
	var ts := float(world.tile_size)
	var now := GameClock.game_time
	var origin := Vector2(-1, -1)
	var from_lair := false
	var best_d := float(def.get("prefer_lair_within", 80)) * ts
	for key in ms.lairs:
		if not is_instance_valid(key):
			continue
		var lair: Building = key
		var d := lair.get_center().distance_to(center)
		if d <= best_d:
			best_d = d
			origin = lair.get_approach_point(center)
			from_lair = true
	if origin.x < 0.0:
		var dist: Array = def.get("spawn_distance", [40, 70])
		for _try in 10:
			var p := center + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(float(dist[0]), float(dist[1])) * ts
			var c: Vector2i = game.nav.nearest_free(world.world_to_cell(p), 6)
			if c.x < 0:
				continue
			var owner_k := world.get_owner(c)
			if owner_k != 0 and owner_k != target.id:
				continue
			origin = world.cell_to_world(c)
			break
	if origin.x < 0.0:
		return "Kein Startplatz für die Welle"
	var count := clampf(float(def.get("size_base", 4)) + float(def.get("size_per_hour", 2)) * now / 3600.0,
			1.0, float(def.get("size_max", 18))) * _severity()
	if game.day_night_system.is_night():
		count *= float(def.get("night_size_mult", 1.3))
	var kinds: Array = ["wolf"]
	for entry in def.get("types_by_minute", []):
		if now >= float(entry[0]) * 60.0:
			kinds = entry[1]
	var shuffled: Array = kinds.duplicate()
	shuffled.shuffle()
	var raid_id := ms.spawn_wave(target, origin, shuffled, maxi(roundi(count), 1))
	if raid_id <= 0:
		return "Welle nicht möglich"
	ev["pos"] = origin
	ev["data"] = {"raid_id": raid_id, "count": maxi(roundi(count), 1), "origin": origin, "from_lair": from_lair}
	return ""


func _start_offer(ev: Dictionary, def: Dictionary, target: Kingdom) -> String:
	if not (target.controller == "player" or target.controller == "ai") or not is_instance_valid(target.castle):
		return "Nur Königreiche nehmen Flüchtlinge auf"
	var wk := create_wanderer_kingdom()
	var center := target.castle.get_center()
	var ts := float(world.tile_size)
	var dist: Array = def.get("spawn_distance", [25, 40])
	var spawn := Vector2(-1, -1)
	var dir := Vector2.RIGHT
	for _try in 10:
		dir = Vector2.from_angle(_rng.randf() * TAU)
		var c: Vector2i = game.nav.nearest_free(world.world_to_cell(center + dir * _rng.randf_range(float(dist[0]), float(dist[1])) * ts), 6)
		if c.x >= 0 and world.get_owner(c) != target.id:
			spawn = world.cell_to_world(c)
			break
	if spawn.x < 0.0:
		return "Kein Platz für die Gruppe"
	var bbox := TerritorySystem.kingdom_bbox(target, world)
	var edge := (Vector2(bbox.size).length() * 0.5 + 2.0) * ts
	var dc: Vector2i = game.nav.nearest_free(world.world_to_cell(center + dir * minf(edge, center.distance_to(spawn))), 6)
	var dest := world.cell_to_world(dc) if dc.x >= 0 else spawn
	var group: Array = def.get("group", [2, 6])
	var n := _rng.randi_range(int(group[0]), int(group[1]))
	var uids: Array = []
	for i in n:
		var off := Vector2.from_angle(TAU * i / maxf(n, 1.0)) * 30.0
		var u: Unit = game.unit_system.spawn_unit(wk, str(def.get("unit", "refugee")), spawn + off)
		if u == null:
			continue
		uids.append(u.uid)
		game.command_system.order_travel(u, dest + off, "seek_refuge")
	if uids.is_empty():
		return "Gruppe nicht möglich"
	var gift := {}
	var gift_table: Dictionary = def.get("gift", {})
	var keys: Array = gift_table.keys()
	for i in mini(int(def.get("gift_kinds", 0)), keys.size()):
		var j := _rng.randi_range(i, keys.size() - 1)
		var tmp: Variant = keys[i]
		keys[i] = keys[j]
		keys[j] = tmp
		var range_list: Array = gift_table[keys[i]]
		gift[str(keys[i])] = float(_rng.randi_range(int(range_list[0]), int(range_list[1])))
	var stories: Array = def.get("stories", [])
	var offer := {"id": next_id, "event_uid": int(ev["uid"]), "event_id": str(ev["event_id"]), "target_id": target.id,
			"uids": uids, "state": "approaching", "dest": dest, "spawn": spawn, "spawned": GameClock.game_time,
			"expires": -1.0, "gift": gift, "spy_owner_id": _pick_spy_owner(target, float(def.get("spy_chance", 0.0))),
			"ai_decide_at": -1.0, "count": uids.size(),
			"story": str(stories[_rng.randi_range(0, stories.size() - 1)]) if not stories.is_empty() else "",
			"next_target_id": 0}
	if target.controller == "ai":
		var think: Array = (def.get("ai_accept", {}) as Dictionary).get("think_seconds", [5, 20])
		offer["ai_decide_at"] = GameClock.game_time + _rng.randf_range(float(think[0]), float(think[1]))
	ev["pos"] = spawn
	ev["data"] = {"offer_id": next_id}
	offers[next_id] = offer
	offer_created.emit(offer)
	return ""


# ---------------------------------------------------------------------------
# Aufnehmen und Abweisen
# ---------------------------------------------------------------------------

## Flüchtlinge/Wanderer aufnehmen: sie werden Bewohner ("" = ok)
func accept_offer(k: Kingdom, offer_id: int) -> String:
	var offer: Dictionary = offers.get(offer_id, {})
	if offer.is_empty():
		return "Das Angebot gibt es nicht mehr"
	if k == null or int(offer["target_id"]) != k.id or k.defeated:
		return "Das Angebot gilt einem anderen Reich"
	if str(offer["state"]) == "leaving":
		return "Die Gruppe ist schon weitergezogen"
	var def := DataDB.get_event(str(offer["event_id"]))
	var sat: Variant = game.get("satisfaction_system")
	var units := _alive_units(offer)
	if units.is_empty():
		offers.erase(offer_id)
		return "Die Gruppe ist nicht mehr da"
	var villagers: Array = []
	var pos: Vector2 = (units[0] as Unit).position
	for u in units:
		var p: Vector2 = u.position
		game.unit_system.remove_unit(u)
		var v: Unit = game.unit_system.spawn_unit(k, "villager", p)
		if v == null:
			continue
		game.work_system.set_unit_job(v, "idle")
		v.satisfaction = float(def.get("start_satisfaction", 55))
		if sat != null:
			sat.add_personal(v, "Dankbar für Aufnahme", float(def.get("grateful_bonus", 8)), float(def.get("grateful_seconds", 1200)))
		villagers.append(v)
	for res in offer.get("gift", {}):
		k.add_resource(str(res), float(offer["gift"][res]))
	var spy_owner: Kingdom = game.get_kingdom(int(offer.get("spy_owner_id", 0)))
	if spy_owner != null and sat != null and not villagers.is_empty() and not spy_owner.defeated:
		sat.register_hidden_spy(villagers[_rng.randi_range(0, villagers.size() - 1)], k, spy_owner)
	k.add_stat("refugees_accepted", villagers.size())
	var text := "%d Menschen sind jetzt deine Bewohner (Wohnraum %d/%d)" % [villagers.size(), k.get_population(), k.get_housing()]
	if villagers.size() == 1:
		text = "1 Mensch ist jetzt dein Bewohner (Wohnraum %d/%d)" % [k.get_population(), k.get_housing()]
	if k.get_population() > k.get_housing():
		text += " – baue Häuser!"
	else:
		text += "."
	if not (offer.get("gift", {}) as Dictionary).is_empty():
		text += " Geschenk: " + DataDB.cost_to_text(offer["gift"]) + "."
	k.notify(text, "good", pos)
	offers.erase(offer_id)
	_finish_offer_event(offer, "aufgenommen")
	offer_resolved.emit(offer, true)
	return ""


## Abweisen: die Gruppe zieht weiter (anderes Dorf, andere Partei oder Kartenrand)
func reject_offer(k: Kingdom, offer_id: int) -> String:
	var offer: Dictionary = offers.get(offer_id, {})
	if offer.is_empty():
		return "Das Angebot gibt es nicht mehr"
	if k == null or int(offer["target_id"]) != k.id:
		return "Das Angebot gilt einem anderen Reich"
	if str(offer["state"]) == "leaving":
		return "Die Gruppe zieht schon weiter"
	var units := _alive_units(offer)
	var where: Variant = null
	if not units.is_empty():
		where = (units[0] as Unit).position
	k.notify("Die Gruppe zieht weiter.", "info", where)
	_send_away(offer, k)
	return ""


func _send_away(offer: Dictionary, from: Kingdom) -> void:
	var units := _alive_units(offer)
	if units.is_empty():
		offers.erase(int(offer["id"]))
		_finish_offer_event(offer, "abgewiesen")
		offer_resolved.emit(offer, false)
		return
	var pos: Vector2 = (units[0] as Unit).position
	var ts := float(world.tile_size)
	var best: Kingdom = null
	var best_d := 150.0 * ts
	var tried: Array = offer.get("tried", [])
	tried.append(from.id)
	offer["tried"] = tried
	for e in game.kingdoms:
		var k: Kingdom = e
		if tried.has(k.id) or k.defeated:
			continue
		var village: bool = game.village_system.is_village(k)
		var party := (k.controller == "player" or k.controller == "ai") and is_instance_valid(k.castle)
		if not village and not party:
			continue
		var c := _center(k)
		if c.x < 0.0:
			continue
		var d := pos.distance_to(c)
		if d < best_d:
			best_d = d
			best = k
	var dest := Vector2(-1, -1)
	if best != null:
		if game.village_system.is_village(best):
			var hall: Building = game.village_system.get_hall(best)
			dest = hall.get_approach_point(pos) if hall != null else Vector2(-1, -1)
		else:
			dest = best.castle.get_approach_point(pos)
	if dest.x < 0.0:
		best = null
		dest = _edge_point(pos)
	offer["state"] = "leaving"
	offer["next_target_id"] = best.id if best != null else 0
	offer["dest"] = dest
	if dest.x < 0.0:
		_remove_group(offer)
		offers.erase(int(offer["id"]))
	else:
		for i in units.size():
			game.command_system.order_travel(units[i], dest + Vector2.from_angle(TAU * i / maxf(units.size(), 1.0)) * 30.0, "travel")
	_finish_offer_event(offer, "abgewiesen")
	offer_resolved.emit(offer, false)


## Ereignis zum Angebot beenden (Ausgang im Verlauf)
func _finish_offer_event(offer: Dictionary, outcome: String) -> void:
	var ev := _find(int(offer.get("event_uid", 0)))
	if ev.is_empty():
		return
	(ev["data"] as Dictionary)["outcome"] = outcome
	end_event(int(ev["uid"]), "resolved")


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	_acc_1s += dt
	_acc_2s += dt
	if _acc_1s < 1.0:
		return
	var t0 := Time.get_ticks_usec()
	var step := _acc_1s
	_acc_1s = 0.0
	var now := GameClock.game_time
	_rng.state = rng_state
	_schedule(now)
	for ev in active.duplicate():
		if not active.has(ev):
			continue
		if float(ev["until"]) >= 0.0 and now >= float(ev["until"]):
			end_event(int(ev["uid"]), "time")
			continue
		match str(ev["kind"]):
			"plague":
				_tick_plague(ev, now)
			"magic_storm":
				_tick_storm(ev, now, step)
			"monster_wave":
				var raid_id := int((ev["data"] as Dictionary).get("raid_id", 0))
				if game.monster_system.get_raid(raid_id).is_empty():
					var out: String = game.monster_system.get_raid_outcome(raid_id)
					(ev["data"] as Dictionary)["outcome"] = "zurückgeschlagen" if out == "killed" else "abgezogen"
					end_event(int(ev["uid"]), "cleared")
	if _acc_2s >= 2.0:
		_acc_2s = 0.0
		for ev in active:
			if str(ev["kind"]) == "magic_storm":
				_storm_units(ev, now)
	_tick_offers(now)
	rng_state = _rng.state
	var used := Time.get_ticks_usec() - t0
	tick_usec_total += used
	tick_usec_max = maxi(tick_usec_max, used)
	tick_count += 1


## Zeitplan: seltene Würfel, gewichtete Wahl von Ereignis und Ziel
func _schedule(now: float) -> void:
	var interval := float(DataDB.evt("check_interval", 25))
	if next_check < 0.0:
		next_check = now + interval
		return
	if now < next_check:
		return
	next_check = now + interval
	var freq := float(DataDB.evt("difficulty.%s.frequency" % GameSession.difficulty_id, 1.0))
	if now < float(DataDB.evt("first_event_minutes", 20)) * 60.0 or active.size() >= int(DataDB.evt("max_active", 3)) \
			or now - last_event_at < float(DataDB.evt("global_min_gap", 1500)) / maxf(freq, 0.01):
		return
	if _rng.randf() >= float(DataDB.evt("chance_per_check", 0.08)) * freq:
		return
	var candidates: Array = []
	var total := 0.0
	for e in DataDB.get_events():
		var def: Dictionary = e
		if now < float(def.get("min_minutes", 0)) * 60.0 or float(cooldowns.get(str(def["id"]), -1.0)) > now:
			continue
		candidates.append(def)
		total += float(def.get("weight", 1))
	if candidates.is_empty() or total <= 0.0:
		return
	var roll := _rng.randf() * total
	var chosen: Dictionary = candidates[candidates.size() - 1]
	for def in candidates:
		roll -= float(def.get("weight", 1))
		if roll <= 0.0:
			chosen = def
			break
	var target := _pick_target(chosen, now)
	if target != null:
		rng_state = _rng.state
		trigger(str(chosen["id"]), target)
		_rng.state = rng_state


func _pick_target(def: Dictionary, now: float) -> Kingdom:
	var targets: Array = def.get("targets", [])
	var weights: Dictionary = DataDB.evt("target_weights", {})
	var gap := float(DataDB.evt("kingdom_min_gap", 3000))
	var per_kingdom := int(DataDB.evt("max_active_per_kingdom", 1))
	var list: Array = []
	var total := 0.0
	for e in game.kingdoms:
		var k: Kingdom = e
		if k.defeated:
			continue
		var kind := ""
		if k.controller == "player" or k.controller == "ai":
			kind = k.controller
		elif game.village_system.is_village(k):
			kind = "neutral"
		if kind.is_empty() or not targets.has(kind):
			continue
		if now - float(kingdom_last.get(k.id, -1.0e9)) < gap or get_active(k).size() >= per_kingdom:
			continue
		if k.get_population() < int(def.get("min_population", 0)):
			continue
		var w := float(weights.get(kind, 1.0))
		if w <= 0.0:
			continue
		list.append([k, w])
		total += w
	if list.is_empty():
		return null
	var roll := _rng.randf() * total
	for entry in list:
		roll -= float(entry[1])
		if roll <= 0.0:
			return entry[0]
	return list[list.size() - 1][0]


# ---------------------------------------------------------------------------
# Seuche
# ---------------------------------------------------------------------------

func _infect(ev: Dictionary, def: Dictionary, u: Unit) -> void:
	var data: Dictionary = ev["data"]
	(data["infected"] as Dictionary)[str(u.uid)] = GameClock.game_time
	_infected[u.uid] = int(ev["uid"])
	for line in def.get("unit_effects", []):
		var e: Dictionary = line
		var key := str(e.get("key", ""))
		var effect := {"id": "event:plague:" + key, "key": key, "until": -1.0, "source": "event:plague", "kingdom_id": 0}
		if e.has("mult"):
			effect["mult"] = float(e["mult"])
		if e.has("add"):
			effect["add"] = float(e["add"])
		game.magic_system.add_unit_effect(u, effect, false)
	u.refresh_stats()


func _cure(ev: Dictionary, u: Unit, immune: bool) -> void:
	var data: Dictionary = ev["data"]
	(data["infected"] as Dictionary).erase(str(u.uid))
	_infected.erase(u.uid)
	if immune:
		(data["immune"] as Array).append(u.uid)
	game.magic_system.remove_unit_effects(u, "event:plague")


func _cure_all(ev: Dictionary) -> void:
	for key in ((ev["data"] as Dictionary).get("infected", {}) as Dictionary).keys():
		var u: Variant = game.find_by_uid(int(key))
		_infected.erase(int(key))
		if u is Unit:
			game.magic_system.remove_unit_effects(u, "event:plague")
	(ev["data"] as Dictionary)["infected"] = {}


func _tick_plague(ev: Dictionary, now: float) -> void:
	var data: Dictionary = ev["data"]
	if now < float(data["next_spread"]):
		return
	var def := DataDB.get_event("plague")
	data["next_spread"] = now + float(def.get("spread_interval", 10))
	var k: Kingdom = game.get_kingdom(int((ev["target_ids"] as Array)[0]))
	if k == null or k.defeated:
		end_event(int(ev["uid"]), "target_gone")
		return
	var ts := float(world.tile_size)
	var infected: Dictionary = data["infected"]
	var immune: Array = data["immune"]
	var infirmaries := _infirmaries(k)
	var spread_mult := 1.0
	if not infirmaries.is_empty():
		spread_mult *= float(def.get("infirmary_spread_mult", 0.5))
	var temple_mult := _temple_spread_mult(k)
	spread_mult *= temple_mult
	var pop := maxi(k.get_population(), 1)
	var cap := ceili(pop * float(def.get("max_infected_ratio", 0.6)))
	var recover := float(def.get("recover_seconds", 360))
	var index: SpatialIndex = game.combat_system.index
	var processed := 0
	for key in infected.keys():
		if processed >= PLAGUE_PER_PASS:
			break
		processed += 1
		var u: Variant = game.find_by_uid(int(key))
		if not (u is Unit) or not (u as Unit).is_alive() or (u as Unit).kingdom != k:
			infected.erase(key)
			_infected.erase(int(key))
			continue
		var unit: Unit = u
		var since := float(infected[key])
		var near_infirmary := _near_infirmary(unit, infirmaries, def)
		var needed := recover / (float(def.get("infirmary_recover_mult", 2.0)) if near_infirmary else 1.0)
		var cured := now - since >= needed
		if not cured and _medic_near(unit, k, float(def.get("medic_cure_radius", 4)) * ts) \
				and _rng.randf() < float(def.get("medic_cure_chance", 0.15)):
			cured = true
		if cured:
			var death := float(def.get("death_chance", 0.08))
			if not infirmaries.is_empty():
				death *= float(def.get("infirmary_death_mult", 0.3))
			if _rng.randf() < death:
				_cure(ev, unit, false)
				if now - _death_notified_at >= 60.0:
					_death_notified_at = now
					k.notify("Ein Bewohner ist an der Seuche gestorben.", "danger", unit.position)
				game.combat_system.apply_damage(unit, unit.hp + 1.0, null, null, "event")
			else:
				_cure(ev, unit, true)
			continue
		# Ansteckung in der Nähe
		if infected.size() >= cap:
			continue
		for o in index.query_kingdom(unit.position, float(def.get("spread_radius", 3)) * ts, k.id):
			var v: Unit = o
			if infected.size() >= cap:
				break
			if v == unit or not v.is_alive() or not bool(v.type_def.get("needs_housing", false)) \
					or _infected.has(v.uid) or immune.has(v.uid):
				continue
			if _rng.randf() < float(def.get("spread_chance", 0.07)) * spread_mult:
				_infect(ev, def, v)
	if infected.is_empty():
		data["outcome"] = "überstanden"
		k.notify("Die Seuche ist überstanden.", "good")
		end_event(int(ev["uid"]), "cleared")


func _infirmaries(k: Kingdom) -> Array:
	var list: Array = []
	for b in k.buildings:
		if is_instance_valid(b) and b.constructed and not (b.def.get("heal_aura", {}) as Dictionary).is_empty() \
				and str(b.def.get("id", "")) == "infirmary":
			list.append(b)
	return list


func _near_infirmary(u: Unit, infirmaries: Array, def: Dictionary) -> bool:
	var ts := float(world.tile_size)
	for b in infirmaries:
		var r := float((b.def.get("heal_aura", {}) as Dictionary).get("radius", 4)) * float(def.get("infirmary_radius_mult", 3.0)) * ts
		if (b as Building).get_center().distance_to(u.position) <= r:
			return true
	return false


func _temple_spread_mult(k: Kingdom) -> float:
	var m := 1.0
	for b in k.buildings:
		if is_instance_valid(b) and b.constructed:
			var sat: Dictionary = b.def.get("satisfaction", {})
			if sat.has("plague_spread_mult"):
				m = minf(m, float(sat["plague_spread_mult"]))
	return m


func _medic_near(u: Unit, k: Kingdom, radius: float) -> bool:
	for o in game.combat_system.index.query_kingdom(u.position, radius, k.id):
		if (o as Unit).heal > 0.0 and (o as Unit).is_alive():
			return true
	return false


# ---------------------------------------------------------------------------
# Magiesturm
# ---------------------------------------------------------------------------

func _tick_storm(ev: Dictionary, now: float, step: float) -> void:
	var def := DataDB.get_event("magic_storm")
	var data: Dictionary = ev["data"]
	var ts := float(world.tile_size)
	var drift: Vector2 = data["drift"]
	var pos: Vector2 = ev["pos"] + drift * ts * step
	var size := world.get_pixel_size()
	if pos.x < 0.0 or pos.x > size.x:
		drift.x = -drift.x
		pos.x = clampf(pos.x, 0.0, size.x)
	if pos.y < 0.0 or pos.y > size.y:
		drift.y = -drift.y
		pos.y = clampf(pos.y, 0.0, size.y)
	data["drift"] = drift
	ev["pos"] = pos
	if now >= float(data["next_affect"]):
		data["next_affect"] = now + 5.0
		_update_storm_kingdoms(ev, def)
	var swing: Dictionary = def.get("mana_swing", {})
	if now >= float(data["next_swing"]):
		data["next_swing"] = now + float(swing.get("interval", 30))
		for kid in data["affected"]:
			var k: Kingdom = game.get_kingdom(int(kid))
			if k != null:
				k.add_resource("mana", _rng.randf_range(float(swing.get("min", -25)), float(swing.get("max", 40))))
	if now >= float(data["next_strike"]):
		data["next_strike"] = now + float(def.get("strike_interval", 6))
		if _rng.randf() < float(def.get("strike_chance", 0.5)):
			var units: Array = game.combat_system.index.query(pos, float(ev["radius"]))
			if not units.is_empty():
				var u: Unit = units[_rng.randi_range(0, units.size() - 1)]
				if u.is_alive():
					storm_strike.emit(u.position)
					game.combat_system.apply_damage(u, float(def.get("strike_damage", 12)), null, null, "event")


## Reiche mit Siedlung im Sturm bekommen die Reichswirkung, andere verlieren sie
func _update_storm_kingdoms(ev: Dictionary, def: Dictionary) -> void:
	var data: Dictionary = ev["data"]
	var before: Array = data["affected"]
	var now_in: Array = []
	for e in game.kingdoms:
		var k: Kingdom = e
		if k.defeated or not _is_settlement(k):
			continue
		var c := _center(k)
		if c.x >= 0.0 and c.distance_to(ev["pos"]) <= float(ev["radius"]):
			now_in.append(k.id)
	var mods := _float_dict(def.get("kingdom_modifiers", {}))
	for kid in now_in:
		if not before.has(kid):
			(game.get_kingdom(int(kid)) as Kingdom).replace_modifiers(str(ev["source"]), mods)
	for kid in before:
		if not now_in.has(kid):
			var k: Kingdom = game.get_kingdom(int(kid))
			if k != null:
				k.clear_modifiers(str(ev["source"]))
	data["affected"] = now_in


## Einheiten im Sturm: kurze Wirkungen, die verlängert werden
func _storm_units(ev: Dictionary, now: float) -> void:
	var def := DataDB.get_event("magic_storm")
	var effects: Array = def.get("unit_effects", [])
	if effects.is_empty():
		return
	var units: Array = game.combat_system.index.query(ev["pos"], float(ev["radius"]))
	var n := 0
	for o in units:
		if n >= STORM_UNITS:
			break
		var u: Unit = o
		if not u.is_alive():
			continue
		n += 1
		var changed := false
		for line in effects:
			var e: Dictionary = line
			var key := str(e.get("key", ""))
			var effect := {"id": "event:magic_storm:" + key, "key": key, "until": now + 2.5, "source": "event:magic_storm",
					"kingdom_id": 0}
			if e.has("mult"):
				effect["mult"] = float(e["mult"])
			if e.has("add"):
				effect["add"] = float(e["add"])
			if game.magic_system.add_unit_effect(u, effect, false):
				changed = true
		if changed:
			u.refresh_stats()


# ---------------------------------------------------------------------------
# Angebote (Flüchtlinge, Wanderer)
# ---------------------------------------------------------------------------

func _tick_offers(now: float) -> void:
	var ts := float(world.tile_size)
	for id in offers.keys():
		if not offers.has(id):
			continue
		var offer: Dictionary = offers[id]
		var units := _alive_units(offer)
		var target: Kingdom = game.get_kingdom(int(offer["target_id"]))
		if units.is_empty():
			offers.erase(id)
			_finish_offer_event(offer, "umgekommen")
			if str(offer["state"]) != "leaving":
				offer_resolved.emit(offer, false)
			continue
		var dest: Vector2 = offer["dest"]
		var arrived := false
		for u in units:
			if u.position.distance_to(dest) <= 3.0 * ts or (not u.moving and not u.path_pending and u.command != "seek_refuge" \
					and u.command != "travel"):
				arrived = true
				break
		match str(offer["state"]):
			"approaching", "waiting":
				if target == null or target.defeated:
					_send_away(offer, target if target != null else get_wanderer_kingdom())
					continue
				var def := DataDB.get_event(str(offer["event_id"]))
				if str(offer["state"]) == "approaching" and arrived:
					offer["state"] = "waiting"
					offer["expires"] = now + float(def.get("decision_seconds", 180))
					var link := {"window": "refugees", "offer_id": int(id), "pos": units[0].position}
					target.notify("Die %s warten am Rand deines Gebiets (%s)." % [str(def.get("name", "Fremden")),
							time_text(float(def.get("decision_seconds", 180)))], "info", link)
				if float(offer["ai_decide_at"]) >= 0.0 and now >= float(offer["ai_decide_at"]) and target.controller == "ai":
					if _ai_accepts(target, offer, def):
						accept_offer(target, int(id))
					else:
						_send_away(offer, target)
					continue
				if str(offer["state"]) == "waiting" and now >= float(offer["expires"]):
					target.notify("Die %s ziehen enttäuscht weiter." % str(def.get("name", "Fremden")), "info", units[0].position)
					_send_away(offer, target)
			"leaving":
				if not arrived:
					continue
				var next: Kingdom = game.get_kingdom(int(offer.get("next_target_id", 0)))
				if next != null and not next.defeated and game.village_system.is_village(next):
					game.village_system.add_population(next, units.size())
					_remove_group(offer)
					offers.erase(id)
				elif next != null and not next.defeated and is_instance_valid(next.castle):
					_reoffer(offer, next, now)
				else:
					_remove_group(offer)
					offers.erase(id)


## Abgewiesene Gruppe bittet das nächste Reich um Aufnahme (ohne neues Ereignis)
func _reoffer(offer: Dictionary, k: Kingdom, now: float) -> void:
	var def := DataDB.get_event(str(offer["event_id"]))
	offer["target_id"] = k.id
	offer["state"] = "waiting"
	offer["event_uid"] = 0
	offer["expires"] = now + float(def.get("decision_seconds", 180))
	offer["next_target_id"] = 0
	var units := _alive_units(offer)
	offer["dest"] = (units[0] as Unit).position
	offer["ai_decide_at"] = -1.0
	if k.controller == "ai":
		var think: Array = (def.get("ai_accept", {}) as Dictionary).get("think_seconds", [5, 20])
		offer["ai_decide_at"] = now + _rng.randf_range(float(think[0]), float(think[1]))
	offer_created.emit(offer)
	k.notify("%d %s bitten um Aufnahme (abgewiesen von einem Nachbarn). %s" % [units.size(), str(def.get("name", "Fremde")),
			str(offer.get("story", ""))], "info", {"window": "refugees", "offer_id": int(offer["id"]), "pos": offer["dest"]})


## Regeln der KI: genug Wohnraum oder zufriedene Bewohner, und genug Nahrung
func _ai_accepts(k: Kingdom, offer: Dictionary, def: Dictionary) -> bool:
	var rules: Dictionary = def.get("ai_accept", {})
	var n := _alive_units(offer).size()
	var free := float(k.get_housing() - k.get_population())
	var sat: Variant = game.get("satisfaction_system")
	var avg := float(sat.get_average(k)) if sat != null else 60.0
	var room := free >= float(rules.get("min_free_housing_share", 0.5)) * n or avg >= float(rules.get("min_satisfaction", 45))
	return room and k.get_amount("food") >= float(rules.get("min_food", 50))


func _alive_units(offer: Dictionary) -> Array:
	var list: Array = []
	for uid in offer["uids"]:
		var u: Variant = game.find_by_uid(int(uid))
		if u is Unit and (u as Unit).is_alive():
			list.append(u)
	return list


func _remove_group(offer: Dictionary) -> void:
	for u in _alive_units(offer):
		game.unit_system.remove_unit(u)


## Feindliche Partei, deren Spion sich unter die Gruppe mischt (0 = keiner)
func _pick_spy_owner(target: Kingdom, chance: float) -> int:
	if chance <= 0.0 or _rng.randf() >= chance:
		return 0
	var esp: Variant = game.get("espionage_system")
	var list: Array = []
	var total := 0.0
	for e in game.kingdoms:
		var k: Kingdom = e
		if k == target or not game.are_hostile(target, k):
			continue
		if esp != null and (esp as Object).has_method("is_party"):
			if not bool(esp.is_party(k)):
				continue
		elif k.controller != "player" and k.controller != "ai":
			continue
		var w := 1.0
		if esp != null and (esp as Object).has_method("get_awareness"):
			w += float(esp.get_awareness(k, target))
		list.append([k.id, w])
		total += w
	if list.is_empty():
		return 0
	var roll := _rng.randf() * total
	for entry in list:
		roll -= float(entry[1])
		if roll <= 0.0:
			return int(entry[0])
	return int(list[list.size() - 1][0])


func _has_hostile_party(k: Kingdom) -> bool:
	for e in game.kingdoms:
		var o: Kingdom = e
		if o != k and not o.defeated and (o.controller == "player" or o.controller == "ai") and game.are_hostile(k, o):
			return true
	return false


# ---------------------------------------------------------------------------
# Meldungen
# ---------------------------------------------------------------------------

func _notify_start(ev: Dictionary, def: Dictionary) -> void:
	var player: Kingdom = game.player
	if player == null:
		return
	var name_text := str(def.get("name", ev["event_id"]))
	var kind := str(ev["kind"])
	var pos: Vector2 = ev["pos"]
	if kind == "refugees" or kind == "wanderers":
		var offer: Dictionary = offers.get(int((ev["data"] as Dictionary).get("offer_id", 0)), {})
		if not offer.is_empty() and int(offer["target_id"]) == player.id:
			player.notify("%d %s nähern sich deinem Reich und bitten um Aufnahme. %s" % [(offer["uids"] as Array).size(),
					name_text, str(offer.get("story", ""))], "info", {"window": "refugees", "offer_id": int(offer["id"]), "pos": pos})
		return
	var rest := get_remaining(ev)
	var minutes := "%d min" % maxi(roundi(rest / 60.0), 1) if rest > 0.0 else ""
	if affects(ev, player):
		match kind:
			"drought":
				player.notify("Dürre! Die Ernte in deinem Reich verdorrt (Nahrung −50 %% für %s)." % minutes, "danger", pos)
			"plague":
				player.notify("Seuche! Eine Krankheit bricht in deinem Reich aus – Krankenstation, Heiler und Tempel helfen.", "danger", pos)
			"magic_storm":
				player.notify("Magiesturm über deinem Reich! Mana schwankt, Zauber sind billiger, Blitze schlagen ein.", "warning", pos)
			"monster_wave":
				var data: Dictionary = ev["data"]
				player.notify("Monsterwelle! %d Monster ziehen %s auf dein Reich zu." % [int(data.get("count", 0)),
						"aus einer Höhle" if bool(data.get("from_lair", false)) else "aus der Wildnis"], "danger", pos)
			_:
				player.notify("%s! %s (%s)" % [name_text, str(def.get("description", "")), minutes],
						"good" if bool(def.get("positive", false)) else "warning", pos)
		return
	var radius := float(DataDB.evt("player_notify_radius", 30)) * float(world.tile_size)
	if kind == "magic_storm" and is_instance_valid(player.castle) \
			and player.castle.get_center().distance_to(pos) <= float(ev["radius"]) + radius:
		player.notify("Ein Magiesturm tobt in der Nähe.", "warning", pos)
		return
	var esp: Variant = game.get("espionage_system")
	var target: Kingdom = game.get_kingdom(int((ev["target_ids"] as Array)[0]))
	if target != null and esp != null and (esp as Object).has_method("get_intel_level") \
			and int(esp.get_intel_level(player, target)) >= 2:
		player.notify("Kundschaft: In %s – %s." % [target.display_name, name_text], "info", pos)


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

func _find(ev_uid: int) -> Dictionary:
	for ev in active:
		if int(ev["uid"]) == ev_uid:
			return ev
	return {}


## Mitte der Siedlung (Burg bzw. Dorfhalle), (-1, -1) wenn keine
func _center(k: Kingdom) -> Vector2:
	if k == null:
		return Vector2(-1, -1)
	if is_instance_valid(k.castle):
		return k.castle.get_center()
	var hall: Building = game.village_system.get_hall(k)
	if hall != null:
		return hall.get_center()
	return Vector2(-1, -1)


## Reich mit Siedlung, das Ereignisse treffen können (Spieler, KI, aktive Dörfer)
func _is_settlement(k: Kingdom) -> bool:
	return (k.has_economy and (k.controller == "player" or k.controller == "ai")) or game.village_system.is_village(k)


func _severity() -> float:
	return float(DataDB.evt("difficulty.%s.severity" % GameSession.difficulty_id, 1.0))


static func _float_dict(d: Dictionary) -> Dictionary:
	var res := {}
	for key in d:
		res[str(key)] = float(d[key])
	return res


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


func _on_unit_removed(u: Unit) -> void:
	if _infected.has(u.uid):
		var ev := _find(int(_infected[u.uid]))
		if not ev.is_empty():
			((ev["data"] as Dictionary)["infected"] as Dictionary).erase(str(u.uid))
		_infected.erase(u.uid)


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "history": history.duplicate(true), "cooldowns": cooldowns.duplicate(),
			"kingdom_last": kingdom_last.duplicate(), "last_event_at": last_event_at, "next_check": next_check,
			"offers": offers.duplicate(true), "next_id": next_id, "wanderer_kingdom_id": wanderer_kingdom_id,
			"rng_state": rng_state}


func from_dict(d: Dictionary) -> void:
	active = (d.get("active", []) as Array).duplicate(true)
	history = (d.get("history", []) as Array).duplicate(true)
	cooldowns = (d.get("cooldowns", {}) as Dictionary).duplicate()
	kingdom_last = (d.get("kingdom_last", {}) as Dictionary).duplicate()
	last_event_at = float(d.get("last_event_at", -1.0e9))
	next_check = float(d.get("next_check", -1.0))
	offers = (d.get("offers", {}) as Dictionary).duplicate(true)
	next_id = int(d.get("next_id", 1))
	wanderer_kingdom_id = int(d.get("wanderer_kingdom_id", 0))
	rng_state = int(d.get("rng_state", rng_state))


## Reichs-Modifikatoren aus active neu setzen, verwaiste "event:"-Quellen entfernen,
## Kranke neu erfassen, Gruppen erneut losschicken
func rebuild_runtime() -> void:
	_acc_1s = 0.0
	_acc_2s = 0.0
	_rng.state = rng_state
	_infected.clear()
	var sources := {}
	for ev in active:
		var def := DataDB.get_event(str(ev["event_id"]))
		var source := str(ev["source"])
		sources[source] = true
		match str(ev["kind"]):
			"drought", "kingdom_buff":
				for kid in ev["target_ids"]:
					var k: Kingdom = game.get_kingdom(int(kid))
					if k != null:
						k.replace_modifiers(source, _float_dict(def.get("modifiers", {})))
			"magic_storm":
				for kid in (ev["data"] as Dictionary).get("affected", []):
					var k: Kingdom = game.get_kingdom(int(kid))
					if k != null:
						k.replace_modifiers(source, _float_dict(def.get("kingdom_modifiers", {})))
			"plague":
				for key in ((ev["data"] as Dictionary).get("infected", {}) as Dictionary):
					_infected[int(key)] = int(ev["uid"])
	for e in game.kingdoms:
		var k: Kingdom = e
		for source in k.modifier_sources.keys():
			if str(source).begins_with("event:") and not sources.has(str(source)):
				k.clear_modifiers(str(source))
	for id in offers:
		var offer: Dictionary = offers[id]
		var cmd := "travel" if str(offer["state"]) == "leaving" else "seek_refuge"
		if str(offer["state"]) == "waiting":
			continue
		for u in _alive_units(offer):
			# Mit gespeichertem Weg (SaveGame) nicht neu losschicken (Idempotenz)
			if u.command == cmd and (u.moving or u.path_pending):
				continue
			game.command_system.order_travel(u, offer["dest"], cmd)


# ---------------------------------------------------------------------------
# Debug (F3-Knöpfe, Rauchtest)
# ---------------------------------------------------------------------------

## Ereignis sofort auslösen (ohne Zeit- und Abklingsperren)
func debug_trigger(event_id: String, target: Kingdom) -> String:
	return trigger(event_id, target, true)


## Alle laufenden Ereignisse beenden
func debug_end_all() -> void:
	for ev in active.duplicate():
		end_event(int(ev["uid"]), "debug")
