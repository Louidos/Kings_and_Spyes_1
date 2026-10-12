## MagicSystem
##
## Zauber des Königs (spells.json). Der König zaubert nie direkten Schaden:
## - Kampf: stärkt eigene Truppen (GUT, Licht) bzw. verflucht Feinde (BÖSE)
## - Heilung: heilt sofort und danach eine Weile
## - Tarnung: eigene Truppen werden unsichtbar, bis sie angreifen (kostet laufend Mana)
## - Wetter: Gebiet für eine Weile (Regen: mehr Ertrag, Nebel: Feinde langsam)
## - Beschwörung: zeitlich begrenzte Kämpfer
## Gezaubert wird im eigenen Gebiet oder bis cast_range_outside Kacheln davor.
## Wirkungen laufen über Unit.effects (mit Ablaufzeit) und Unit.refresh_stats;
## der Zustand liegt in einfachen Feldern (speicherbar in Phase 10).
## Gleiche Schnittstelle für Spieler und (ab Phase 7) KI-Reiche.
class_name MagicSystem
extends Node

## Ein Zauber wurde gewirkt (für Effekte und Meldungen)
signal spell_cast(kingdom: Kingdom, spell_id: String, pos: Vector2, radius_px: float)
## Ein Wettergebiet oder eine Tarnung ist vorbei
signal spell_ended(kingdom: Kingdom, spell_id: String, pos: Vector2)
## Eine beschworene Einheit verschwindet (Zeit abgelaufen)
signal summon_expired(unit: Unit)

## Wetter- und Tarnwirkungen werden einmal pro Spielsekunde erneuert
const ZONE_INTERVAL := 1.0
## Wetterwirkungen auf Einheiten gelten so lange über die Sekunde hinaus
const ZONE_EFFECT_SECONDS := 1.6

var game: Node
var world: WorldData
## Wettergebiete: {"id", "spell_id", "kingdom_id", "pos", "radius" (Pixel), "until", "kind"}
var zones: Array = []
## Tarnungen mit laufenden Kosten: {"id", "spell_id", "kingdom_id", "pos", "until", "units" (uids)}
var veils: Array = []

var _ts := 64.0
var _next_id := 1
var _zone_timer := 0.0
## Einheiten mit zeitlich begrenzten Wirkungen (uid -> Unit), nur diese werden geprüft
var _affected: Dictionary = {}
## Beschworene Einheiten mit Ablaufzeit (uid -> Unit)
var _temporary: Dictionary = {}


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_ts = float(world.tile_size)
	GameClock.sim_tick.connect(_on_sim_tick)
	game.unit_system.unit_removed.connect(_on_unit_removed)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Zauber der Fraktion des Reichs (bekannte und noch nicht erforschte)
func get_spells(k: Kingdom) -> Array:
	return DataDB.get_spells_for_faction(k.faction_id)


func is_known(k: Kingdom, spell_id: String) -> bool:
	var req := str(DataDB.get_spell(spell_id).get("requires", ""))
	return req.is_empty() or k.unlocks.has(req)


## Sekunden bis der Zauber wieder bereit ist (0 = bereit)
func cooldown_left(k: Kingdom, spell_id: String) -> float:
	return maxf(float(k.spell_cooldowns.get(spell_id, 0.0)) - GameClock.game_time, 0.0)


## Liegt pos im eigenen Gebiet oder höchstens cast_range_outside Kacheln davor?
func in_range(k: Kingdom, pos: Vector2) -> bool:
	var c := world.world_to_cell(pos)
	if world.get_owner(c) == k.id:
		return true
	var r := int(DataDB.mag("settings.cast_range_outside", 8))
	var r2 := r * r
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r2 and world.get_owner(c + Vector2i(dx, dy)) == k.id:
				return true
	return false


## "" = kann gezaubert werden, sonst der Grund (deutsch)
func can_cast(k: Kingdom, spell_id: String, pos: Vector2) -> String:
	var def := DataDB.get_spell(spell_id)
	if def.is_empty() or (def["faction"] != "any" and def["faction"] != k.faction_id):
		return "Unbekannter Zauber"
	if not is_known(k, spell_id):
		var r := DataDB.find_research_unlocking(k.faction_id, str(def.get("requires", "")))
		return "Noch nicht erforscht: %s" % str(r.get("name", "?"))
	if not is_instance_valid(k.king):
		return "Nur der König kann zaubern"
	var cd := cooldown_left(k, spell_id)
	if cd > 0.0:
		return "Bereit in %d s" % ceili(cd)
	var cost := float(def["mana_cost"])
	if k.get_amount("mana") + 0.0001 < cost:
		return "Zu wenig Mana (%d von %d)" % [floori(k.get_amount("mana")), ceili(cost)]
	if not in_range(k, pos):
		return "Nur im eigenen Gebiet oder bis %d Felder davor" % int(DataDB.mag("settings.cast_range_outside", 8))
	return ""


## Zauber wirken. Gibt false zurück (und kostet nichts), wenn es nicht geht.
func cast(k: Kingdom, spell_id: String, pos: Vector2) -> bool:
	if not can_cast(k, spell_id, pos).is_empty():
		return false
	var def := DataDB.get_spell(spell_id)
	if not k.spend({"mana": float(def["mana_cost"])}):
		return false
	var now := GameClock.game_time
	k.spell_cooldowns[spell_id] = now + float(def["cooldown"])
	var radius := float(def["radius"]) * _ts
	var duration := float(def["duration"])
	# Sofortheilung
	if float(def.get("heal_instant", 0.0)) > 0.0:
		for u in _units_in(pos, radius):
			if game.are_allied(k, u.kingdom) and u.hp < u.max_hp:
				game.combat_system.heal_unit(u, float(def["heal_instant"]))
	# Wirkungen auf Einheiten (Segen, Fluch, Heilung über Zeit)
	if def.has("effects"):
		_apply_effects(k, spell_id, def["effects"], pos, radius, now + duration)
	# Tarnung
	if bool(def.get("stealth", false)):
		_start_veil(k, spell_id, pos, radius, now + duration)
	# Wettergebiet
	if def.has("zone"):
		var zone: Dictionary = def["zone"]
		zones.append({"id": _new_id(), "spell_id": spell_id, "kingdom_id": k.id, "pos": pos,
				"radius": radius, "until": now + duration, "kind": str(zone.get("kind", ""))})
	# Beschwörung
	if def.has("summon"):
		_summon(k, def["summon"], pos, now + duration)
	k.add_stat("spells")
	spell_cast.emit(k, spell_id, pos, radius)
	return true


## Ertragsfaktor durch Wetter (Regen) für eine Ressource an dieser Stelle
## (1.0 = keiner). Gilt nur für die in zone.resources genannten Ressourcen.
func get_production_factor(k: Kingdom, pos: Vector2, res_id: String) -> float:
	if zones.is_empty():
		return 1.0
	var f := 1.0
	for z in zones:
		if int(z["kingdom_id"]) != k.id:
			continue
		var zdef: Dictionary = DataDB.get_spell(str(z["spell_id"])).get("zone", {})
		var p := float(zdef.get("production", 1.0))
		if p == 1.0 or not (zdef.get("resources", []) as Array).has(res_id):
			continue
		if pos.distance_to(z["pos"]) <= float(z["radius"]):
			f = maxf(f, p)
	return f


## Laufende Manakosten des Reichs pro Sekunde (aktive Tarnungen)
func get_upkeep_per_sec(k: Kingdom) -> float:
	var total := 0.0
	for v in veils:
		if int(v["kingdom_id"]) == k.id:
			total += float(DataDB.get_spell(str(v["spell_id"])).get("upkeep", 0.0))
	return total


## Getarnte Einheit greift an oder wird enttarnt: Tarnung endet für sie.
func reveal(u: Unit) -> void:
	if not u.stealthed:
		return
	u.stealthed = false
	u.remove_effect("stealth")
	u.modulate.a = 1.0


## Restliche Sekunden einer Wirkung (für das Auswahlfenster): Liste von {"name", "seconds", "color"}
func get_active_effects(u: Unit) -> Array:
	var now := GameClock.game_time
	var list: Array = []
	var seen := {}
	for e in u.effects:
		var spell_id := str(e.get("source", ""))
		if spell_id.is_empty() or seen.has(spell_id):
			continue
		seen[spell_id] = true
		var def := DataDB.get_spell(spell_id)
		list.append({"name": str(def.get("name", spell_id)), "seconds": maxf(float(e.get("until", now)) - now, 0.0),
				"color": def.get("color", Color.WHITE)})
	return list


# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	var now := GameClock.game_time
	_tick_effects(dt, now)
	_tick_temporary(now)
	_zone_timer -= dt
	if _zone_timer <= 0.0:
		_zone_timer = ZONE_INTERVAL
		_tick_zones(now)
		_tick_veils(now)


## Abgelaufene Wirkungen entfernen, Heilung über Zeit anwenden
func _tick_effects(dt: float, now: float) -> void:
	for uid in _affected.keys():
		var u: Variant = _affected[uid]
		if not is_instance_valid(u) or not u.is_alive():
			_affected.erase(uid)
			continue
		var expired := false
		var hot := 0.0
		for e in u.effects:
			if float(e.get("until", -1.0)) >= 0.0 and float(e["until"]) <= now:
				expired = true
			elif str(e.get("key", "")) == "heal_over_time":
				hot += float(e.get("add", 0.0))
		if hot > 0.0 and u.hp < u.max_hp:
			game.combat_system.heal_unit(u, hot * dt)
		if expired:
			var keep: Array = []
			var lost_stealth := false
			for e in u.effects:
				if float(e.get("until", -1.0)) >= 0.0 and float(e["until"]) <= now:
					if str(e.get("key", "")) == "stealth":
						lost_stealth = true
				else:
					keep.append(e)
			u.effects = keep
			u.refresh_stats()
			if lost_stealth:
				u.stealthed = false
				u.modulate.a = 1.0
		if u.effects.is_empty():
			_affected.erase(uid)


## Beschworene Einheiten verschwinden nach Ablauf
func _tick_temporary(now: float) -> void:
	for uid in _temporary.keys():
		var u: Variant = _temporary[uid]
		if not is_instance_valid(u):
			_temporary.erase(uid)
			continue
		if u.expires_at >= 0.0 and u.expires_at <= now:
			_temporary.erase(uid)
			# Sofort "tot" setzen: bis zum Löschen am Frame-Ende greift sie niemand mehr an
			u.hp = 0.0
			u.target = null
			summon_expired.emit(u)
			game.unit_system.remove_unit(u)


## Wettergebiete: Nebel bremst Feinde (kurze, ständig erneuerte Wirkung); Ablauf
func _tick_zones(now: float) -> void:
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		var k: Kingdom = game.get_kingdom(int(z["kingdom_id"]))
		if float(z["until"]) <= now or k == null:
			zones.remove_at(i)
			if k != null:
				spell_ended.emit(k, str(z["spell_id"]), z["pos"])
			continue
		var zdef: Dictionary = DataDB.get_spell(str(z["spell_id"])).get("zone", {})
		if zdef.has("effects"):
			_apply_effects(k, str(z["spell_id"]), zdef["effects"], z["pos"], float(z["radius"]),
					now + ZONE_EFFECT_SECONDS)


## Tarnungen: laufende Manakosten, Ende bei Ablauf, Manamangel oder wenn niemand mehr getarnt ist
func _tick_veils(now: float) -> void:
	for i in range(veils.size() - 1, -1, -1):
		var v: Dictionary = veils[i]
		var k: Kingdom = game.get_kingdom(int(v["kingdom_id"]))
		var units: Array = []
		for uid in v["units"]:
			var u: Variant = game.find_by_uid(int(uid))
			if is_instance_valid(u) and u is Unit and u.stealthed:
				units.append(u)
		var upkeep := float(DataDB.get_spell(str(v["spell_id"])).get("upkeep", 0.0))
		var ended := units.is_empty() or float(v["until"]) <= now or k == null
		if not ended and upkeep > 0.0:
			if k.get_amount("mana") + 0.0001 < upkeep:
				ended = true
				k.notify("%s endet – zu wenig Mana" % DataDB.get_spell(str(v["spell_id"])).get("name", ""), "warning", v["pos"])
			else:
				# Über add_resource, damit die Kosten im Ertrag pro Minute erscheinen
				k.add_resource("mana", -upkeep)
		if ended:
			for u in units:
				reveal(u)
			veils.remove_at(i)
			if k != null:
				spell_ended.emit(k, str(v["spell_id"]), v["pos"])


# ---------------------------------------------------------------------------
# Intern
# ---------------------------------------------------------------------------

## Wirkungen auf Einheiten im Kreis. side own = verbündet, enemy = feindlich.
## Eine bestehende gleiche Wirkung wird nur verlängert (kein Neuberechnen).
func _apply_effects(k: Kingdom, spell_id: String, effects: Array, pos: Vector2, radius: float, until: float) -> void:
	for u in _units_in(pos, radius):
		var changed := false
		for e in effects:
			var side := str(e.get("side", "own"))
			if side == "own" and not game.are_allied(k, u.kingdom):
				continue
			if side == "enemy" and not game.are_hostile(k, u.kingdom):
				continue
			var key := str(e.get("key", ""))
			var effect_id := "spell:%s:%s" % [spell_id, key]
			var existing := _find_effect(u, effect_id)
			if not existing.is_empty():
				existing["until"] = maxf(float(existing["until"]), until)
				continue
			u.effects.append({"id": effect_id, "key": key, "mult": float(e.get("mult", 1.0)),
					"add": float(e.get("add", 0.0)), "until": until, "source": spell_id})
			changed = true
		if changed:
			u.refresh_stats()
			_affected[u.uid] = u


func _start_veil(k: Kingdom, spell_id: String, pos: Vector2, radius: float, until: float) -> void:
	var uids: Array = []
	for u in _units_in(pos, radius):
		if u.kingdom != k or u.role == "king":
			continue
		u.stealthed = true
		u.modulate.a = 0.45
		var existing := _find_effect(u, "stealth")
		if existing.is_empty():
			u.effects.append({"id": "stealth", "key": "stealth", "mult": 1.0, "add": 0.0, "until": until, "source": spell_id})
		else:
			existing["until"] = until
			existing["source"] = spell_id
		_affected[u.uid] = u
		uids.append(u.uid)
	if not uids.is_empty():
		veils.append({"id": _new_id(), "spell_id": spell_id, "kingdom_id": k.id, "pos": pos, "until": until, "units": uids})


func _summon(k: Kingdom, summon: Dictionary, pos: Vector2, until: float) -> void:
	var type_id := str(summon.get("unit", ""))
	var count := int(summon.get("count", 1))
	for i in count:
		var spot := pos + Vector2.from_angle(TAU * i / maxf(count, 1.0)) * _ts * 0.9
		var c: Vector2i = game.nav.nearest_free(world.world_to_cell(spot), 4)
		if c.x < 0:
			continue
		var u: Unit = game.unit_system.spawn_unit(k, type_id, world.cell_to_world(c))
		if u == null:
			continue
		u.expires_at = until
		u.command = "hold"
		u.command_pos = u.position
		_temporary[u.uid] = u


func _find_effect(u: Unit, effect_id: String) -> Dictionary:
	for e in u.effects:
		if str(e.get("id", "")) == effect_id:
			return e
	return {}


## Einheiten im Kreis (ausserhalb von Gebäuden)
func _units_in(pos: Vector2, radius: float) -> Array:
	var list: Array = []
	for u in game.unit_system.units:
		if u.inside == null and u.hp > 0.0 and u.position.distance_squared_to(pos) <= radius * radius:
			list.append(u)
	return list


func _new_id() -> int:
	_next_id += 1
	return _next_id


func _on_unit_removed(u: Unit) -> void:
	_affected.erase(u.uid)
	_temporary.erase(u.uid)
