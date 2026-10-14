## MagicSystem
##
## Zauber des Königs (spells.json). Der König zaubert nie direkten Schaden:
## - Kampf: stärkt eigene Truppen (GUT, Licht) bzw. verflucht Feinde (BÖSE)
## - Heilung: heilt sofort und danach eine Weile
## - Tarnung: eigene Truppen werden unsichtbar, bis sie angreifen (kostet laufend Mana)
## - Wetter: Gebiet für eine Weile (Regen: mehr Ertrag, Nebel: Feinde langsam)
## - Beschwörung: zeitlich begrenzte Kämpfer
## - Reichstarnung (realm_cloak, Phase 7): ganzes Reich, an/aus – Entdeckungswert sinkt
##   (Zustand und laufende Kosten im EspionageSystem: start_cloak/stop_cloak)
## Gezaubert wird im eigenen Gebiet oder bis cast_range_outside Kacheln davor
## (plus Forschungs-Zuschlag "spell_range").
##
## Aufbau (für spätere Phasen: Helden zaubern auch, Wetter-Ereignisse, Speichern):
## - Zeitlich begrenzte Wirkungen auf Einheiten laufen NUR über add_unit_effect /
##   remove_unit_effects. Schema: {"id", "key", "mult", "add", "until" (-1 = bis
##   zum Ende), "source" ("spell:<id>"), "kingdom_id", "ref" (Gebiet/Tarnung, 0 = keins)}.
## - Getarnt ist eine Einheit, solange sie eine Wirkung mit key "stealth" hat
##   (Unit.refresh_stats leitet stealthed daraus ab).
## - Gebiete (zones) und Tarnungen (veils) speichern ihre Werte beim Zaubern
##   (Radius, Ertrag, Wirkungen); spätere Datenänderungen ändern laufende Zauber nicht.
## - Laufende Kosten trägt das Reich (Kingdom.set_upkeep), das EconomySystem
##   zieht sie ab und meldet upkeep_unpaid, wenn es nicht reicht.
## - Werte eines Zaubers (Kosten, Abklingzeit, Radius, Dauer, Stärke) über
##   get_cast_params – Forschung ändert sie mit den Modifikatoren spell_cost,
##   spell_cooldown, spell_radius, spell_duration, spell_power.
## Der Zustand liegt in einfachen Feldern (speicherbar in Phase 10, danach rebuild_runtime).
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
## Wettergebiete: {"id", "spell_id", "kingdom_id", "pos", "radius" (Pixel), "until" (-1 = bis end_zone),
## "kind", "production", "resources", "effects", "drop_targets_beyond" (Kacheln, 0 = nein), "power"}
var zones: Array = []
## Tarnungen: {"id", "spell_id", "kingdom_id", "pos", "until", "units" (uids), "upkeep", "upkeep_source"}
var veils: Array = []

var _ts := 64.0
var _zone_timer := 0.0
## Einheiten mit Wirkungen (uid -> Unit), nur diese werden geprüft
var _affected: Dictionary = {}
## Früheste Ablaufzeit je Einheit (uid -> Spielzeit; kann zu früh sein, dann wird neu gerechnet)
var _due: Dictionary = {}
## Früheste Ablaufzeit überhaupt: davor muss _tick_effects nichts ablaufen lassen
var _next_due := INF
## Einheiten mit Lebenspunkten pro Sekunde (uid -> Unit)
var _hp_units: Dictionary = {}
## Beschworene Einheiten mit Ablaufzeit (uid -> Unit)
var _temporary: Dictionary = {}


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_ts = float(world.tile_size)
	GameClock.sim_tick.connect(_on_sim_tick)
	game.unit_system.unit_removed.connect(_on_unit_removed)
	game.economy_system.upkeep_unpaid.connect(_on_upkeep_unpaid)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Zauber, die das Reich kennen kann: die der eigenen Fraktion (auch noch nicht
## erforschte) und fremde, die es freigeschaltet hat (ab Phase 6: Bündnisse).
func get_spells(k: Kingdom) -> Array:
	var list := DataDB.get_spells_for_faction(k.faction_id)
	for sp in DataDB.spells:
		if not list.has(sp) and not (sp["requires"] as Array).is_empty() and k.has_all_unlocks(sp["requires"]):
			list.append(sp)
	return list


func is_known(k: Kingdom, spell_id: String) -> bool:
	var def := DataDB.get_spell(spell_id)
	return not def.is_empty() and k.has_all_unlocks(def["requires"])


## Sekunden bis der Zauber wieder bereit ist (0 = bereit)
func cooldown_left(k: Kingdom, spell_id: String) -> float:
	return maxf(float(k.spell_cooldowns.get(spell_id, 0.0)) - GameClock.game_time, 0.0)


## Tatsächliche Werte eines Zaubers für dieses Reich (Forschung eingerechnet):
## {"mana_cost", "upkeep" (pro s), "cooldown", "radius" (Kacheln), "duration" (-1 = bis zum Ende),
##  "power" (Stärke der Wirkungen, 1 = wie in den Daten), "range" (Kacheln ausserhalb des Gebiets)}
func get_cast_params(k: Kingdom, spell_id: String) -> Dictionary:
	var def := DataDB.get_spell(spell_id)
	var duration := float(def.get("duration", 0.0))
	return {
		"mana_cost": float(def.get("mana_cost", 0.0)) * k.mod("spell_cost"),
		"upkeep": float(def.get("upkeep", 0.0)) * k.mod("spell_cost"),
		"cooldown": float(def.get("cooldown", 0.0)) * k.mod("spell_cooldown"),
		"radius": float(def.get("radius", 0.0)) * k.mod("spell_radius"),
		"duration": -1.0 if duration < 0.0 else duration * k.mod("spell_duration"),
		"power": k.mod("spell_power"),
		"range": get_cast_range(k),
	}


## Kacheln ausserhalb des eigenen Gebiets, in denen noch gezaubert werden darf
func get_cast_range(k: Kingdom) -> int:
	return int(DataDB.mag("settings.cast_range_outside", 16)) + int(k.bonus("spell_range"))


## Liegt pos im eigenen Gebiet oder höchstens get_cast_range Kacheln davor?
## range_mode "caster" (für spätere Zauberer): höchstens def.cast_range Kacheln vom Zaubernden.
func in_range(k: Kingdom, pos: Vector2, spell_id: String = "", caster: Unit = null) -> bool:
	var def := DataDB.get_spell(spell_id)
	if str(def.get("range_mode", "territory")) == "caster":
		var who := _caster_of(k, caster)
		return who != null and who.position.distance_to(pos) <= float(def.get("cast_range", 8.0)) * _ts
	var c := world.world_to_cell(pos)
	if world.get_owner(c) == k.id:
		return true
	var r := get_cast_range(k)
	var r2 := r * r
	# Ring für Ring nach aussen: eine nahe Grenze wird schnell gefunden
	for ring in range(1, r + 1):
		for dy in range(-ring, ring + 1):
			var step := 1 if absi(dy) == ring else ring * 2
			for dx in range(-ring, ring + 1, step):
				if dx * dx + dy * dy <= r2 and world.get_owner(c + Vector2i(dx, dy)) == k.id:
					return true
	return false


## Wen trifft der Zauber? "own" (eigene/verbündete), "enemy" (Feinde) oder "" (Gebiet, Beschwörung)
func get_target_side(spell_id: String) -> String:
	var def := DataDB.get_spell(spell_id)
	if def.has("zone") or def.has("summon"):
		return ""
	for e in def.get("effects", []):
		return str(e.get("side", "own"))
	if bool(def.get("stealth", false)) or float(def.get("heal_instant", 0.0)) > 0.0:
		return "own"
	return ""


## Einheiten, die ein Zauber an dieser Stelle treffen würde (für Zielanzeige und KI)
func get_targets(k: Kingdom, spell_id: String, pos: Vector2) -> Array:
	var side := get_target_side(spell_id)
	if side.is_empty():
		return []
	var def := DataDB.get_spell(spell_id)
	var radius := float(get_cast_params(k, spell_id)["radius"]) * _ts
	var stealth := bool(def.get("stealth", false))
	var list: Array = []
	for u in _units_in(pos, radius):
		if stealth:
			if u.kingdom == k and u.role != "king":
				list.append(u)
		elif side == "own":
			if game.are_allied(k, u.kingdom):
				list.append(u)
		elif game.are_hostile(k, u.kingdom) and game.can_see(k, u):
			list.append(u)
	return list


## Grund, der nicht von der Zielstelle abhängt ("" = bereit): unbekannt, nicht
## erforscht, kein Zaubernder, Abklingzeit, Mana. Für die Zauberleiste.
func can_cast_now(k: Kingdom, spell_id: String, caster: Unit = null) -> String:
	var def := DataDB.get_spell(spell_id)
	if def.is_empty():
		return "Unbekannter Zauber"
	if not is_known(k, spell_id):
		return "Noch nicht erforscht: %s" % DataDB.describe_requirement(def["requires"], k.faction_id)
	# Reichstarnung (Phase 7): läuft sie schon, schaltet ein Klick sie ab (EspionageSystem.toggle_cloak)
	if bool(def.get("realm_cloak", false)):
		var esp := _espionage()
		if esp != null and esp.is_cloaked(k):
			return "Reichstarnung ist schon aktiv – Klick schaltet sie ab"
	if _caster_of(k, caster) == null:
		return "Nur der König kann zaubern"
	var cd := cooldown_left(k, spell_id)
	if cd > 0.0:
		return "Bereit in %d s" % ceili(cd)
	var cost := float(get_cast_params(k, spell_id)["mana_cost"])
	if k.get_amount("mana") + 0.0001 < cost:
		return "Zu wenig Mana (%d von %d)" % [floori(k.get_amount("mana")), ceili(cost)]
	return ""


## "" = kann an dieser Stelle gezaubert werden, sonst der Grund (deutsch)
func can_cast(k: Kingdom, spell_id: String, pos: Vector2, caster: Unit = null) -> String:
	var reason := can_cast_now(k, spell_id, caster)
	if not reason.is_empty():
		return reason
	if not in_range(k, pos, spell_id, caster):
		return "Nur im eigenen Gebiet oder bis %d Felder davor" % get_cast_range(k)
	# Kein Mana für einen Zauber verschwenden, der niemanden trifft
	var side := get_target_side(spell_id)
	if not side.is_empty() and get_targets(k, spell_id, pos).is_empty():
		return "Keine Feinde im Kreis" if side == "enemy" else "Keine eigenen Einheiten im Kreis"
	return ""


## Zauber wirken. Gibt false zurück (und kostet nichts), wenn es nicht geht.
## caster: wer zaubert (null = der König des Reichs).
func cast(k: Kingdom, spell_id: String, pos: Vector2, caster: Unit = null) -> bool:
	if not can_cast(k, spell_id, pos, caster).is_empty():
		return false
	var def := DataDB.get_spell(spell_id)
	var p := get_cast_params(k, spell_id)
	if not k.spend({"mana": float(p["mana_cost"])}):
		return false
	var now := GameClock.game_time
	k.spell_cooldowns[spell_id] = now + float(p["cooldown"])
	var radius := float(p["radius"]) * _ts
	var power := float(p["power"])
	var until := -1.0 if float(p["duration"]) < 0.0 else now + float(p["duration"])
	var source := "spell:" + spell_id
	# Sofortheilung
	if float(def.get("heal_instant", 0.0)) > 0.0:
		for u in _units_in(pos, radius):
			if game.are_allied(k, u.kingdom) and u.hp < u.max_hp:
				game.combat_system.heal_unit(u, float(def["heal_instant"]) * power)
	# Wirkungen auf Einheiten (Segen, Fluch, Heilung über Zeit)
	if def.has("effects"):
		_apply_effects(k, source, def["effects"], pos, radius, until, power, 0)
	# Tarnung
	if bool(def.get("stealth", false)):
		_start_veil(k, spell_id, pos, radius, until, float(p["upkeep"]))
	# Wettergebiet
	if def.has("zone"):
		add_zone(k, spell_id, pos, radius, until, def["zone"], power)
	# Beschwörung
	if def.has("summon"):
		_summon(k, def["summon"], pos, until)
	# Reichstarnung (Phase 7): Entdeckungswert sinkt, laufende Kosten trägt das EspionageSystem
	if bool(def.get("realm_cloak", false)):
		var esp := _espionage()
		if esp != null:
			esp.start_cloak(k, spell_id, float(p["upkeep"]))
	k.add_stat("spells")
	spell_cast.emit(k, spell_id, pos, radius)
	return true


## Beendet alle laufenden Gebiete und Tarnungen dieses Zaubers (z. B. zum Abschalten;
## bei der Reichstarnung auch diese)
func end_spell(k: Kingdom, spell_id: String) -> void:
	if bool(DataDB.get_spell(spell_id).get("realm_cloak", false)):
		var esp := _espionage()
		if esp != null:
			esp.stop_cloak(k, "ended")
	for z in zones.duplicate():
		if int(z["kingdom_id"]) == k.id and str(z["spell_id"]) == spell_id:
			end_zone(int(z["id"]))
	for v in veils.duplicate():
		if int(v["kingdom_id"]) == k.id and str(v["spell_id"]) == spell_id:
			_end_veil(v)


## Ertragsfaktor durch Wetter für eine Ressource an dieser Stelle (1.0 = keiner).
## Gilt nur für die in zone.resources genannten Ressourcen.
func get_zone_factor(k: Kingdom, pos: Vector2, res_id: String) -> float:
	if zones.is_empty():
		return 1.0
	var f := 1.0
	for z in zones:
		if int(z["kingdom_id"]) != k.id:
			continue
		var p := float(z["production"])
		if p == 1.0 or not (z["resources"] as Array).has(res_id):
			continue
		if pos.distance_to(z["pos"]) <= float(z["radius"]):
			f = maxf(f, p)
	return f


## Alter Name (Oberfläche, Wirtschaft)
func get_production_factor(k: Kingdom, pos: Vector2, res_id: String = "") -> float:
	return get_zone_factor(k, pos, res_id)


## Einheiten mit Wirkungen (uid -> Unit) – nur lesen (Darstellung der Auren).
## Kann bereits gelöschte Einheiten enthalten: vor dem Zugriff is_instance_valid.
func get_affected_units() -> Dictionary:
	return _affected


## Laufende Manakosten des Reichs pro Sekunde (aktive Tarnungen usw.)
func get_upkeep_per_sec(k: Kingdom) -> float:
	return k.get_upkeep("mana")


## Getarnte Einheit greift an: Tarnwirkungen, die beim Angriff enden, entfernen.
func reveal(u: Unit) -> void:
	if not u.stealthed:
		return
	var changed := false
	for i in range(u.effects.size() - 1, -1, -1):
		var e: Dictionary = u.effects[i]
		if str(e.get("key", "")) == "stealth" and bool(e.get("breaks_on_attack", true)):
			u.effects.remove_at(i)
			changed = true
	if changed:
		u.refresh_stats()


## Laufende Wirkungen einer Einheit (für das Auswahlfenster): Liste von
## {"name", "seconds" (-1 = bis zum Ende des Zaubers), "color", "source"}
func get_active_effects(u: Unit) -> Array:
	var now := GameClock.game_time
	var list: Array = []
	var seen := {}
	for e in u.effects:
		var source := str(e.get("source", ""))
		if source.is_empty() or seen.has(source):
			continue
		seen[source] = true
		var until := float(e.get("until", -1.0))
		list.append({"name": DataDB.describe_effect_source(source),
				"seconds": -1.0 if until < 0.0 else maxf(until - now, 0.0),
				"color": DataDB.get_effect_source_color(source), "source": source})
	return list


# ---------------------------------------------------------------------------
# Wirkungen auf Einheiten (einziger Weg für zeitlich begrenzte Wirkungen)
# ---------------------------------------------------------------------------

## Fügt eine Wirkung hinzu. Gibt es schon eine mit derselben id, wird nur ihre
## Ablaufzeit verlängert (kein Neuberechnen). Gibt true zurück, wenn neu.
## refresh = false: der Aufrufer rechnet die Werte selbst neu (mehrere Wirkungen auf einmal).
func add_unit_effect(u: Unit, effect: Dictionary, refresh: bool = true) -> bool:
	var existing := _find_effect(u, str(effect.get("id", "")))
	if not existing.is_empty():
		var until := float(effect.get("until", -1.0))
		var old := float(existing.get("until", -1.0))
		existing["until"] = -1.0 if until < 0.0 or old < 0.0 else maxf(old, until)
		existing["ref"] = effect.get("ref", existing.get("ref", 0))
		return false
	u.effects.append(effect)
	_track(u, effect)
	if refresh:
		u.refresh_stats()
	return true


## Merkt sich Ablaufzeit und Lebenspunkt-Wirkung einer neuen Wirkung
func _track(u: Unit, effect: Dictionary) -> void:
	_affected[u.uid] = u
	var until := float(effect.get("until", -1.0))
	if until >= 0.0:
		_due[u.uid] = minf(float(_due.get(u.uid, INF)), until)
		_next_due = minf(_next_due, until)
	if str(effect.get("key", "")) == "hp_per_sec":
		_hp_units[u.uid] = u


## Entfernt Wirkungen einer Quelle ("spell:<id>"); mit ref nur die eines Gebiets/einer Tarnung.
func remove_unit_effects(u: Unit, source: String, ref: int = -1) -> void:
	var changed := false
	for i in range(u.effects.size() - 1, -1, -1):
		var e: Dictionary = u.effects[i]
		if str(e.get("source", "")) == source and (ref < 0 or int(e.get("ref", 0)) == ref):
			u.effects.remove_at(i)
			changed = true
	if changed:
		u.refresh_stats()


## Nach dem Laden (Phase 10): Zwischenspeicher aus dem gespeicherten Zustand neu aufbauen
func rebuild_runtime() -> void:
	_affected.clear()
	_due.clear()
	_hp_units.clear()
	_next_due = INF
	_temporary.clear()
	for u in game.unit_system.units:
		u.refresh_stats()
		for e in u.effects:
			_track(u, e)
		if u.expires_at >= 0.0:
			_temporary[u.uid] = u
	for v in veils:
		var k: Kingdom = game.get_kingdom(int(v["kingdom_id"]))
		var upkeep := float(v.get("upkeep", 0.0))
		if k != null and upkeep > 0.0:
			k.set_upkeep(str(v["upkeep_source"]), {"mana": upkeep})


# ---------------------------------------------------------------------------
# Gebiete (Wetter)
# ---------------------------------------------------------------------------

## Legt ein Wettergebiet an (Zauber oder später Ereignisse). Werte werden kopiert.
## until -1 = bis end_zone. Gibt die id zurück.
func add_zone(k: Kingdom, spell_id: String, pos: Vector2, radius_px: float, until: float,
		zone_def: Dictionary, power: float = 1.0) -> int:
	var id: int = game.next_uid()
	zones.append({"id": id, "spell_id": spell_id, "kingdom_id": k.id, "pos": pos, "radius": radius_px,
			"until": until, "kind": str(zone_def.get("kind", "")),
			"production": 1.0 + (float(zone_def.get("production", 1.0)) - 1.0) * power,
			"resources": (zone_def.get("resources", []) as Array).duplicate(),
			"effects": (zone_def.get("effects", []) as Array).duplicate(true),
			"drop_targets_beyond": float(zone_def.get("drop_targets_beyond", 0.0)),
			"power": power})
	return id


## Beendet ein Gebiet sofort (Wirkungen auf Einheiten laufen kurz aus)
func end_zone(zone_id: int) -> void:
	for i in zones.size():
		var z: Dictionary = zones[i]
		if int(z["id"]) != zone_id:
			continue
		zones.remove_at(i)
		var k: Kingdom = game.get_kingdom(int(z["kingdom_id"]))
		if k != null:
			spell_ended.emit(k, str(z["spell_id"]), z["pos"])
		return


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


## Lebenspunkte pro Sekunde anwenden (hp_per_sec: positiv = Heilung, negativ =
## Schaden) und abgelaufene Wirkungen entfernen. Geprüft werden nur Einheiten mit
## hp_per_sec und – erst ab der frühesten Ablaufzeit – die mit fälligen Wirkungen.
func _tick_effects(dt: float, now: float) -> void:
	for uid in _hp_units.keys():
		var u: Variant = _hp_units[uid]
		if not is_instance_valid(u) or not u.is_alive():
			_hp_units.erase(uid)
			continue
		var hp_rate := 0.0
		var found := false
		var damage_kingdom: Kingdom = null
		for e in u.effects:
			if str(e.get("key", "")) == "hp_per_sec":
				found = true
				var add := float(e.get("add", 0.0))
				hp_rate += add
				if add < 0.0:
					damage_kingdom = game.get_kingdom(int(e.get("kingdom_id", -1)))
		if not found:
			_hp_units.erase(uid)
		elif hp_rate > 0.0 and u.hp < u.max_hp:
			game.combat_system.heal_unit(u, hp_rate * dt)
		elif hp_rate < 0.0:
			game.combat_system.apply_damage(u, -hp_rate * dt, null, damage_kingdom, "spell")
	if now < _next_due:
		return
	_next_due = INF
	for uid in _affected.keys():
		var u: Variant = _affected[uid]
		if not is_instance_valid(u) or not u.is_alive():
			_forget(uid)
			continue
		var due := float(_due.get(uid, INF))
		if due > now:
			_next_due = minf(_next_due, due)
			continue
		# Fällig: Abgelaufenes entfernen, nächste Ablaufzeit neu bestimmen
		var stats_changed := false
		var next := INF
		for i in range(u.effects.size() - 1, -1, -1):
			var until := float(u.effects[i].get("until", -1.0))
			if until >= 0.0 and until <= now:
				# hp_per_sec ändert keine Werte – dann muss nicht neu gerechnet werden
				if str(u.effects[i].get("key", "")) != "hp_per_sec":
					stats_changed = true
				u.effects.remove_at(i)
			elif until >= 0.0:
				next = minf(next, until)
		if stats_changed:
			u.refresh_stats()
		if u.effects.is_empty():
			_forget(uid)
			continue
		_due[uid] = next
		_next_due = minf(_next_due, next)


func _forget(uid: int) -> void:
	_affected.erase(uid)
	_due.erase(uid)
	_hp_units.erase(uid)


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


## Wettergebiete: Wirkungen auf Einheiten (kurz, ständig erneuert), Nebel lässt
## Feinde von fernen Zielen ablassen; Ablauf
func _tick_zones(now: float) -> void:
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		var k: Kingdom = game.get_kingdom(int(z["kingdom_id"]))
		var until := float(z["until"])
		if (until >= 0.0 and until <= now) or k == null:
			zones.remove_at(i)
			if k != null:
				spell_ended.emit(k, str(z["spell_id"]), z["pos"])
			continue
		var effects: Array = z["effects"]
		if not effects.is_empty():
			_apply_effects(k, "spell:" + str(z["spell_id"]), effects, z["pos"], float(z["radius"]),
					now + ZONE_EFFECT_SECONDS, float(z["power"]), int(z["id"]), true)
		var drop := float(z["drop_targets_beyond"]) * _ts
		if drop > 0.0:
			_drop_far_targets(k, z["pos"], float(z["radius"]), drop)


## Feinde im Nebel verlieren Ziele, die weiter als drop Pixel entfernt sind
## (ausser bei ausdrücklichem Angriffsbefehl)
func _drop_far_targets(k: Kingdom, pos: Vector2, radius: float, drop: float) -> void:
	for u in _units_in(pos, radius, true):
		if not game.are_hostile(k, u.kingdom) or u.command == "attack":
			continue
		var t: Variant = u.target
		if is_same(t, null) or not is_instance_valid(t):
			continue
		var dist: float = u.position.distance_to(t.position) - t.get_radius()
		if dist > drop:
			u.target = null
			u.regroup_pending = true
			# Nicht im nächsten Takt dasselbe Ziel wieder aufnehmen
			u.think_timer = ZONE_INTERVAL + 0.5


## Tarnungen: Ende bei Ablauf oder wenn niemand mehr getarnt ist.
## (Manamangel meldet das EconomySystem über upkeep_unpaid.)
func _tick_veils(now: float) -> void:
	for v in veils.duplicate():
		var k: Kingdom = game.get_kingdom(int(v["kingdom_id"]))
		var until := float(v["until"])
		var ended := k == null or (until >= 0.0 and until <= now)
		if not ended:
			var alive: Array = []
			for uid in v["units"]:
				var u: Variant = game.find_by_uid(int(uid))
				if is_instance_valid(u) and u is Unit and _has_ref(u, int(v["id"])):
					alive.append(uid)
			v["units"] = alive
			ended = alive.is_empty()
		if ended:
			_end_veil(v)


func _on_upkeep_unpaid(k: Kingdom, source: String) -> void:
	for v in veils.duplicate():
		if str(v["upkeep_source"]) == source:
			k.notify("%s endet – zu wenig Mana" % DataDB.get_spell(str(v["spell_id"])).get("name", ""), "warning", v["pos"])
			_end_veil(v)


# ---------------------------------------------------------------------------
# Intern
# ---------------------------------------------------------------------------

## Öffentlich (Heldenauren, Fähigkeiten, später Ereignisse): Wirkungen auf alle
## Einheiten im Kreis wie bei Zaubern. source z. B. "ability:<fähigkeit>", until -1 =
## bis zum Entfernen. Im Simulationstakt use_index = true (schneller).
## replace_values: bestehende gleiche Wirkungen übernehmen neue Werte (Aura stieg
## eine Stufe); filter "fighters": nur kämpfende Einheiten (keine Bewohner);
## exclude_uid: diese Einheit auslassen (z. B. der Held selbst).
func apply_area_effects(k: Kingdom, source: String, effects: Array, pos: Vector2, radius_px: float, until: float,
		power: float = 1.0, ref: int = 0, use_index: bool = false, replace_values: bool = false,
		filter: String = "", exclude_uid: int = 0) -> void:
	_apply_effects(k, source, effects, pos, radius_px, until, power, ref, use_index, replace_values, filter, exclude_uid)


## Einheiten im Kreis (öffentlich, z. B. Flächenschaden der Helden). use_index nur im Simulationstakt.
func units_in(pos: Vector2, radius_px: float, use_index: bool = false) -> Array:
	return _units_in(pos, radius_px, use_index)


## Wirkungen auf Einheiten im Kreis. side own = verbündet, own_kingdom = nur das
## eigene Reich, enemy = feindlich.
## power verstärkt die Wirkung (mult 1.25 mit power 1.2 -> 1.30, add × power).
## Eine bestehende gleiche Wirkung wird nur verlängert (kein Neuberechnen) –
## Wettergebiete erneuern ihre Wirkungen jede Sekunde, das muss billig sein.
func _apply_effects(k: Kingdom, source: String, effects: Array, pos: Vector2, radius: float, until: float,
		power: float, ref: int, use_index: bool = false, replace_values: bool = false,
		filter: String = "", exclude_uid: int = 0) -> void:
	var prepared: Array = []
	for e in effects:
		var key := str(e.get("key", ""))
		prepared.append({"side": str(e.get("side", "own")), "id": "%s:%s" % [source, key], "key": key,
				"mult": 1.0 + (float(e.get("mult", 1.0)) - 1.0) * power, "add": float(e.get("add", 0.0)) * power})
	for u in _units_in(pos, radius, use_index):
		if exclude_uid != 0 and u.uid == exclude_uid:
			continue
		if filter == "fighters" and not u.joins_fights and not u.can_heal():
			continue
		var allied: bool = game.are_allied(k, u.kingdom)
		var hostile: bool = not allied and game.are_hostile(k, u.kingdom)
		var changed := false
		for pe in prepared:
			var side: String = pe["side"]
			if (side == "own" and not allied) or (side == "enemy" and not hostile) \
					or (side == "own_kingdom" and u.kingdom != k):
				continue
			var existing := _find_effect(u, pe["id"])
			if not existing.is_empty():
				var old := float(existing.get("until", -1.0))
				existing["until"] = -1.0 if until < 0.0 or old < 0.0 else maxf(old, until)
				existing["ref"] = ref
				if replace_values and (not is_equal_approx(float(existing.get("mult", 1.0)), float(pe["mult"])) \
						or not is_equal_approx(float(existing.get("add", 0.0)), float(pe["add"]))):
					existing["mult"] = pe["mult"]
					existing["add"] = pe["add"]
					_track(u, existing)
					changed = true
				continue
			var effect := {"id": pe["id"], "key": pe["key"], "mult": pe["mult"], "add": pe["add"], "until": until,
					"source": source, "kingdom_id": k.id, "ref": ref}
			u.effects.append(effect)
			_track(u, effect)
			changed = true
		if changed:
			u.refresh_stats()


func _start_veil(k: Kingdom, spell_id: String, pos: Vector2, radius: float, until: float, upkeep: float) -> void:
	var id: int = game.next_uid()
	var source := "spell:" + spell_id
	var breaks := bool(DataDB.mag("settings.stealth_breaks_on_attack", true))
	var uids: Array = []
	for u in _units_in(pos, radius):
		if u.kingdom != k or u.role == "king":
			continue
		# Eine ältere Tarnung derselben Art wird durch diese ersetzt
		remove_unit_effects(u, source)
		add_unit_effect(u, {"id": source + ":stealth", "key": "stealth", "mult": 1.0, "add": 0.0,
				"until": until, "source": source, "kingdom_id": k.id, "ref": id, "breaks_on_attack": breaks})
		uids.append(u.uid)
	if uids.is_empty():
		return
	var upkeep_source := "%s#%d" % [source, id]
	veils.append({"id": id, "spell_id": spell_id, "kingdom_id": k.id, "pos": pos, "until": until,
			"units": uids, "upkeep": upkeep, "upkeep_source": upkeep_source})
	if upkeep > 0.0:
		k.set_upkeep(upkeep_source, {"mana": upkeep})


func _end_veil(v: Dictionary) -> void:
	var i := veils.find(v)
	if i < 0:
		return
	veils.remove_at(i)
	var k: Kingdom = game.get_kingdom(int(v["kingdom_id"]))
	var source := "spell:" + str(v["spell_id"])
	for uid in v["units"]:
		var u: Variant = game.find_by_uid(int(uid))
		if is_instance_valid(u) and u is Unit:
			remove_unit_effects(u, source, int(v["id"]))
	if k != null:
		k.clear_upkeep(str(v["upkeep_source"]))
		spell_ended.emit(k, str(v["spell_id"]), v["pos"])


func _summon(k: Kingdom, summon: Dictionary, pos: Vector2, until: float) -> void:
	summon_units(k, str(summon.get("unit", "")), int(summon.get("count", 1)), pos, until)


## Beschwört count Einheiten im Kreis um pos (auch für Heldenfähigkeiten). until:
## Spielzeit, zu der sie verschwinden (-1 = bleiben). Gibt die neuen Einheiten zurück.
func summon_units(k: Kingdom, type_id: String, count: int, pos: Vector2, until: float) -> Array:
	var list: Array = []
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
		if until >= 0.0:
			_temporary[u.uid] = u
		list.append(u)
	return list


## Wer zaubert: der angegebene (lebend) oder der König des Reichs, sonst null
func _caster_of(k: Kingdom, caster: Unit) -> Unit:
	if caster != null and is_instance_valid(caster) and caster.is_alive():
		return caster
	if is_instance_valid(k.king) and k.king.is_alive():
		return k.king
	return null


## Das EspionageSystem (Phase 7; null, solange es keins gibt)
func _espionage() -> EspionageSystem:
	var esp: Variant = game.get("espionage_system")
	return esp as EspionageSystem if esp is EspionageSystem else null


func _find_effect(u: Unit, effect_id: String) -> Dictionary:
	for e in u.effects:
		if str(e.get("id", "")) == effect_id:
			return e
	return {}


func _has_ref(u: Unit, ref: int) -> bool:
	for e in u.effects:
		if int(e.get("ref", 0)) == ref:
			return true
	return false


## Einheiten im Kreis (ausserhalb von Gebäuden).
## use_index: über die Umgebungssuche des CombatSystems (nur im Simulationstakt –
## das CombatSystem baut sie dort vorher neu auf; ausserhalb davon, z. B. beim
## Zaubern per Mausklick, kann sie schon gelöschte Einheiten enthalten).
func _units_in(pos: Vector2, radius: float, use_index: bool = false) -> Array:
	var list: Array = []
	var r2 := radius * radius
	if use_index:
		# Etwas Rand: die Umgebungssuche ist bis zu zwei Takte alt
		for u in game.combat_system.index.query(pos, radius + _ts):
			if is_instance_valid(u) and u.inside == null and u.hp > 0.0 and u.position.distance_squared_to(pos) <= r2:
				list.append(u)
		return list
	for u in game.unit_system.units:
		if u.inside == null and u.hp > 0.0 and u.position.distance_squared_to(pos) <= r2:
			list.append(u)
	return list


func _on_unit_removed(u: Unit) -> void:
	_forget(u.uid)
	_temporary.erase(u.uid)
