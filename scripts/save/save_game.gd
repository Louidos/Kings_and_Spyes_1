## SaveGame
##
## Inhalt eines Spielstands: sammelt den Zustand der Partie ein (collect) und stellt
## ihn in einer festen Reihenfolge wieder her (restore). Die Welt selbst wird aus dem
## Seed neu erzeugt (Spielszene, Hintergrund-Thread); gespeichert werden nur ihre
## Änderungen (WorldData.diff_to_dict).
##
## Jedes System hat dieselbe Schnittstelle:
##   to_dict() -> Dictionary     gespeicherter Zustand (nur einfache Werte, Verweise als uid, Kopien)
##   from_dict(d) -> void        nur Daten übernehmen (keine Signale, keine Befehle)
##   rebuild_runtime() -> void   danach: Zwischenspeicher und Wirkungen neu aufbauen (idempotent)
## Die Systeme stehen im Register SYSTEMS (Schlüssel im Spielstand, Eigenschaft an der
## Spielszene). Fehlt ein System (spätere Phase), wird es übersprungen. Weitere Nodes
## unter Systems mit den drei Methoden werden automatisch mitgespeichert (Schlüssel =
## Node-Name in snake_case ohne "_system").
## Dateiformat und Schreiben: SaveManager. Typen in JSON: SaveCodec.
class_name SaveGame
extends RefCounted

## Inhaltsschema (erhöhen nur, wenn alte Werte umgedeutet werden müssen; siehe SaveMigration)
const SAVE_VERSION := 1

## Register: [Schlüssel im Spielstand, Eigenschaft an der Spielszene]; Reihenfolge von from_dict
const SYSTEMS := [["building", "building_system"], ["unit", "unit_system"], ["work", "work_system"],
		["economy", "economy_system"], ["combat", "combat_system"], ["command", "command_system"],
		["summon", "summon_system"], ["research", "research_system"], ["magic", "magic_system"],
		["hero", "hero_system"], ["village", "village_system"], ["diplomacy", "diplomacy_system"],
		["messenger", "messenger_system"], ["espionage", "espionage_system"], ["spy", "spy_system"],
		["ai", "ai_system"], ["victory", "victory_system"], ["people", "people_system"],
		["day_night", "day_night_system"], ["satisfaction", "satisfaction_system"], ["event", "event_system"],
		["monster", "monster_system"], ["siege", "siege_system"], ["fortification", "fortification_system"],
		["trade_route", "trade_route_system"], ["supply", "supply_system"]]

## Reihenfolge von rebuild_runtime (Schlüssel aus SYSTEMS; "@difficulty" = Difficulty.reapply_all).
## Wegfindung (Belagerung) zuerst, dann Wirkungen auf Reiche (Forschung, Schwierigkeit, Volk,
## Tag/Nacht, Bündnisse), dann Werte der Einheiten (Magie rechnet alle neu), Helden, Monster,
## Spionage/KI/Sieg, Phase-8/9-Systeme, zuletzt Kampf, Arbeit, Befehle und Wege.
## Nicht genannte Systeme folgen danach in Registerreihenfolge.
const REBUILD_ORDER := ["siege", "fortification", "research", "@difficulty", "people", "day_night", "diplomacy",
		"village", "messenger", "magic", "hero", "monster", "espionage", "spy", "ai", "victory", "satisfaction",
		"event", "trade_route", "supply", "combat", "work", "command", "unit", "economy"]

## Schnittstellenfehler (System ohne die drei Methoden; der Rauchtest prüft: leer)
static var interface_errors: PackedStringArray = PackedStringArray()


# ---------------------------------------------------------------------------
# Register
# ---------------------------------------------------------------------------

## Alle vorhandenen Systeme: [[Schlüssel, Node], …] in Registerreihenfolge, danach weitere
## Nodes unter Systems, die die Schnittstelle haben
static func system_entries(game: Node) -> Array:
	var list: Array = []
	var seen := {}
	for entry in SYSTEMS:
		var node: Variant = game.get(str(entry[1]))
		if not (node is Node) or not is_instance_valid(node):
			continue
		if not _check_interface(node as Node, str(entry[0])):
			continue
		list.append([str(entry[0]), node])
		seen[node] = true
	var systems_node := game.get_node_or_null("Systems")
	if systems_node != null:
		for child in systems_node.get_children():
			if seen.has(child) or not child.has_method("to_dict"):
				continue
			if not _check_interface(child, str(child.name)):
				continue
			list.append([str(child.name).to_snake_case().trim_suffix("_system"), child])
	return list


static func _check_interface(node: Node, key: String) -> bool:
	for m in ["to_dict", "from_dict", "rebuild_runtime"]:
		if not node.has_method(m):
			var text := "SaveGame: System %s (%s) hat keine Methode %s" % [key, node.name, m]
			if not interface_errors.has(text):
				interface_errors.append(text)
				push_error(text)
			return false
	return true


# ---------------------------------------------------------------------------
# Einsammeln
# ---------------------------------------------------------------------------

## Zustand der Partie einsammeln (Kopien, im Hauptthread). Gibt [Kopf, Daten] zurück.
static func collect(game: Node, slot: String = "", display_name: String = "", kind: String = "manual") -> Array:
	var data := {}
	data["session"] = GameSession.to_dict()
	var clock := GameClock.to_dict()
	if game.has_method("is_menu_pause"):
		# Aus dem Spielmenü gespeichert: die Pause des Menüs gehört nicht in den Spielstand
		if bool(game.call("is_menu_pause")):
			clock["paused"] = bool(game.get("_was_paused_before_menu"))
	data["clock"] = clock
	var cam: Node2D = game.get("camera")
	data["game"] = {"uid_counter": int(game.get("uid_counter")),
			"player_id": game.player.id if game.player != null else 0,
			"wild_id": game.wild.id if game.wild != null else 0,
			"camera": {"pos": cam.position if cam != null else Vector2.ZERO, "zoom": cam.zoom.x if cam != null else 1.0},
			"last_save_name": display_name}
	data["world"] = (game.world as WorldData).diff_to_dict()
	var kingdoms: Array = game.kingdoms.duplicate()
	kingdoms.sort_custom(func(a: Kingdom, b: Kingdom) -> bool: return a.id < b.id)
	var kd: Array = []
	var buildings: Array = []
	for k in kingdoms:
		kd.append(k.to_dict())
		for b in k.buildings:
			if is_instance_valid(b):
				buildings.append(b)
	data["kingdoms"] = kd
	buildings.sort_custom(func(a: Building, b: Building) -> bool: return a.uid < b.uid)
	var bd: Array = []
	for b in buildings:
		bd.append(b.to_dict())
	data["buildings"] = bd
	var units: Array = []
	for u in game.unit_system.units:
		if is_instance_valid(u) and u.hp > 0.0 and u.kingdom != null and game.kingdom_by_id.has(u.kingdom.id):
			units.append(u)
	units.sort_custom(func(a: Unit, b: Unit) -> bool: return a.uid < b.uid)
	var ud: Array = []
	for u in units:
		ud.append(u.to_dict())
	data["units"] = ud
	var systems := {}
	for entry in system_entries(game):
		var sd: Variant = entry[1].call("to_dict")
		systems[entry[0]] = (sd as Dictionary).duplicate(true) if sd is Dictionary else {}
	data["systems"] = systems
	data["ui"] = {"message_log": Notify.history.duplicate(true)}
	return [make_header(game, slot, display_name, kind, data), data]


## Kopf eines Spielstands (Zeile 2 der Datei; die Ladeliste liest nur ihn)
static func make_header(game: Node, slot: String, display_name: String, kind: String, data: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var player: Kingdom = game.player
	var max_level := 0
	var enemies := 0
	var allied := 0
	for k in game.kingdoms:
		if k.controller == "ai" and not k.defeated:
			enemies += 1
		if k.controller == "neutral" and player != null and k.get_relation(player) == "alliance":
			allied += 1
	if player != null:
		for rec in player.heroes:
			max_level = maxi(max_level, int(rec.get("level", 1)))
	var faction := GameSession.get_faction()
	var diff := GameSession.get_difficulty()
	var map_size := DataDB.get_map_size(GameSession.map_size_id)
	return {"format": SaveMigration.FORMAT, "format_version": SaveMigration.FORMAT_VERSION,
			"save_version": SAVE_VERSION, "game_version": str(ProjectSettings.get_setting("application/config/version", "1.0.0")),
			"generator_version": WorldGenerator.VERSION, "data_fingerprint": DataDB.data_fingerprint,
			"slot": slot, "name": display_name, "kind": kind,
			"saved_at": now, "saved_at_text": Time.get_datetime_string_from_unix_time(now + _tz_offset(), true),
			"game_time": GameClock.game_time, "time_text": GameClock.get_time_string(),
			"play_seconds": GameSession.play_seconds,
			"faction_id": GameSession.faction_id, "faction_name": str(faction.get("name", GameSession.faction_id)),
			"people_id": GameSession.people_id, "people_name": DataDB.get_people_name(GameSession.people_id) if not GameSession.people_id.is_empty() else "",
			"difficulty_id": GameSession.difficulty_id, "difficulty_name": str(diff.get("name", GameSession.difficulty_id)),
			"map_size_id": GameSession.map_size_id, "map_size_name": str(map_size.get("name", GameSession.map_size_id)),
			"seed_text": GameSession.seed_text, "world_seed": GameSession.world_seed,
			"summary": {"buildings": player.buildings.size() if player != null else 0,
				"units": player.units.size() if player != null else 0, "heroes_max_level": max_level,
				"enemies_left": enemies, "villages_allied": allied,
				"kingdoms": (data.get("kingdoms", []) as Array).size()}}


## Zeitzone für die Anzeige "14.10.2026 18:42" (Sekunden)
static func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## "14.10.2026 18:42" aus einer Unix-Zeit
static func format_date(unix: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix + _tz_offset())
	return "%02d.%02d.%04d %02d:%02d" % [int(dt["day"]), int(dt["month"]), int(dt["year"]), int(dt["hour"]), int(dt["minute"])]


# ---------------------------------------------------------------------------
# Wiederherstellen
# ---------------------------------------------------------------------------

## Stellt die Partie aus d wieder her (Welt ist schon erzeugt und mit dem Diff versehen,
## alle Systeme sind eingerichtet). Gibt einen Ladebericht zurück.
static func restore(game: Node, d: Dictionary) -> Dictionary:
	var report := {"skipped_buildings": 0, "skipped_units": 0, "times": {}}
	var times: Dictionary = report["times"]
	var t0 := Time.get_ticks_usec()
	var t := t0
	# R0: still und im Lademodus
	Notify.muted = true
	game.set("loading_save", true)
	# R1: Uhr (Zeitstempel der Systeme stimmen ab jetzt), Sitzung
	GameClock.load_state(d.get("clock", {}))
	GameSession.apply_session(d.get("session", {}))
	var gd: Dictionary = d.get("game", {})
	# R2: Zähler für uids
	game.set("uid_counter", int(gd.get("uid_counter", 0)))
	# R3: Reiche (erst alle anlegen, dann Daten; keine Beziehungs-Signale)
	var kingdom_data: Array = d.get("kingdoms", [])
	for kd in kingdom_data:
		game.create_kingdom({"id": int(kd.get("id", 0)), "faction_id": str(kd.get("faction_id", "good")),
				"controller": str(kd.get("controller", "ai")), "restore": true})
	for kd in kingdom_data:
		var k: Kingdom = game.get_kingdom(int(kd.get("id", 0)))
		k.from_dict(kd)
	game.player = game.get_kingdom(int(gd.get("player_id", 1)))
	game.wild = game.get_kingdom(int(gd.get("wild_id", 0)))
	if game.player != null:
		Unit.viewer_kingdom_id = game.player.id
	if game.wild != null:
		game.monster_system.setup(game, game.wild)
	times["R3_reiche"] = _lap(t)
	t = Time.get_ticks_usec()
	# R4: Strassen und Übersichtsbild zeichnen
	game.world_map.refresh_all()
	# R5: Gebäude
	var bs: BuildingSystem = game.building_system
	for bdict in d.get("buildings", []):
		if bs.restore_building(bdict) == null:
			report["skipped_buildings"] = int(report["skipped_buildings"]) + 1
	for kd in kingdom_data:
		var k: Kingdom = game.get_kingdom(int(kd.get("id", 0)))
		var castle: Variant = game.find_by_uid(int(kd.get("castle_uid", 0)))
		k.castle = castle if castle is Building else null
	times["R5_gebaeude"] = _lap(t)
	t = Time.get_ticks_usec()
	# R6: Gebiet aus allen fertigen Gebäuden (älteste uid gewinnt)
	_recompute_territory(game)
	times["R6_gebiet"] = _lap(t)
	t = Time.get_ticks_usec()
	# R7: Einheiten
	var us: UnitSystem = game.unit_system
	var unit_data: Array = d.get("units", [])
	for udict in unit_data:
		if us.restore_unit(udict) == null:
			report["skipped_units"] = int(report["skipped_units"]) + 1
	times["R7_einheiten"] = _lap(t)
	t = Time.get_ticks_usec()
	# R8: zweiter Durchgang – Verweise über uid
	_resolve_references(game, d, kingdom_data, unit_data)
	times["R8_verweise"] = _lap(t)
	t = Time.get_ticks_usec()
	# R9: Systeme – nur Daten
	var entries := system_entries(game)
	var sys_data: Dictionary = d.get("systems", {})
	for entry in entries:
		entry[1].call("from_dict", (sys_data.get(entry[0], {}) as Dictionary))
	times["R9_systeme"] = _lap(t)
	t = Time.get_ticks_usec()
	# R10: Laufzeit neu aufbauen in fester Reihenfolge
	var by_key := {}
	for entry in entries:
		by_key[entry[0]] = entry[1]
	var done := {}
	for key in REBUILD_ORDER:
		if key == "@difficulty":
			Difficulty.reapply_all(game)
			continue
		if by_key.has(key):
			by_key[key].call("rebuild_runtime")
			done[key] = true
	for entry in entries:
		if not done.has(entry[0]):
			entry[1].call("rebuild_runtime")
	times["R10_aufbau"] = _lap(t)
	t = Time.get_ticks_usec()
	# R11: Leben der Einheiten erst jetzt (refresh_stats hält sonst nur den Anteil), Tarnung
	var hp_by_uid := {}
	for udict in unit_data:
		hp_by_uid[int(udict.get("uid", 0))] = float(udict.get("hp", 1.0))
	for u in us.units:
		if hp_by_uid.has(u.uid):
			u.hp = clampf(float(hp_by_uid[u.uid]), 0.0, u.max_hp)
		u.update_stealth_look()
	# R12: Leben der Gebäude noch einmal (Belagerung könnte sie neu skaliert haben)
	for bdict in d.get("buildings", []):
		var b: Variant = game.find_by_uid(int(bdict.get("uid", 0)))
		if b is Building:
			b.max_hp = maxf(float(bdict.get("max_hp", b.max_hp)), 1.0)
			b.hp = clampf(float(bdict.get("hp", b.max_hp)), 0.0, b.max_hp)
			b.queue_redraw()
	# R13: Anzeigen auffrischen, Protokoll
	for k in game.kingdoms:
		k.population_changed.emit()
		k.resources_changed.emit()
	Notify.load_history((d.get("ui", {}) as Dictionary).get("message_log", []))
	GameSession.last_save_name = str(gd.get("last_save_name", ""))
	game.set("_loaded_camera", gd.get("camera", {}))
	times["R11_R13_rest"] = _lap(t)
	# R15: Rauchtest – sofort wieder einsammeln (Idempotenz-Vergleich)
	if GameSession.debug_verify_load:
		game.set("last_load_check", collect(game)[1])
		game.set("last_load_metrics", metrics(game))
	# R16: Meldungen wieder an
	Notify.muted = false
	game.set("loading_save", false)
	report["total_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	report["kingdoms"] = kingdom_data.size()
	report["buildings"] = (d.get("buildings", []) as Array).size()
	report["units"] = unit_data.size()
	print("[save] Geladen: %d Reiche, %d Gebäude, %d Einheiten (übersprungen: %d Gebäude, %d Einheiten) in %.0f ms %s" % [
			int(report["kingdoms"]), int(report["buildings"]), int(report["units"]),
			int(report["skipped_buildings"]), int(report["skipped_units"]), float(report["total_ms"]), str(times)])
	return report


static func _lap(t: int) -> float:
	return (Time.get_ticks_usec() - t) / 1000.0


## Gebiet aller Reiche aus den fertigen Gebäuden neu berechnen (nur im Bereich der Ansprüche)
static func _recompute_territory(game: Node) -> void:
	var world: WorldData = game.world
	var rect := Rect2i()
	var first := true
	for k in game.kingdoms:
		for b in k.buildings:
			if not b.constructed or int(b.def.get("territory_radius", 0)) <= 0:
				continue
			var r := TerritorySystem.claim_rect(b, world)
			rect = r if first else rect.merge(r)
			first = false
	if not first:
		(game.territory as TerritorySystem).recompute_area(world, rect, game.kingdoms)


## R8: Ziel, Gebäude, Arbeitsplatz, König, Weg und Arbeitszustand
static func _resolve_references(game: Node, d: Dictionary, kingdom_data: Array, unit_data: Array) -> void:
	var us: UnitSystem = game.unit_system
	for udict in unit_data:
		var found: Variant = game.find_by_uid(int(udict.get("uid", 0)))
		if not (found is Unit):
			continue
		var u: Unit = found
		var target: Variant = game.find_by_uid(int(udict.get("target_uid", 0)))
		u.target = target if (target is Unit or target is Building) else null
		var inside: Variant = game.find_by_uid(int(udict.get("inside_uid", 0)))
		if inside is Building:
			us.set_inside(u, inside)
		var work: Variant = game.find_by_uid(int(udict.get("work_uid", 0)))
		u.work_building = work if work is Building else null
		# Arbeitszustand: nur wer in seinem Arbeitsplatz arbeitet, bleibt dabei; alle anderen
		# suchen ihren Arbeitsschritt gestaffelt neu (Reservierungen sind Laufzeit)
		if u.can_work() and u.command.is_empty():
			if u.state == Unit.State.WORKING and u.work_building != null and u.inside == u.work_building \
					and u.work_building.constructed:
				u.activity = "%s (%s)" % [DataDB.get_job(u.job_id).get("activity", "arbeitet"), u.work_building.get_display_name()]
			else:
				u.state = Unit.State.IDLE
				u.timer = float(u.uid % 10) * 0.15
		else:
			u.state = Unit.State.IDLE
		# Weg fortsetzen (Mitglieder eines Gruppenmarschs schickt das CommandSystem einzeln neu)
		var motion: Variant = udict.get("motion", null)
		if motion is Dictionary and not bool(udict.get("follows", false)):
			us.restore_motion(u, motion)
	# Arbeiter der Gebäude (Reihenfolge wie gespeichert)
	for bdict in d.get("buildings", []):
		var found_b: Variant = game.find_by_uid(int(bdict.get("uid", 0)))
		if not (found_b is Building):
			continue
		var b: Building = found_b
		b.workers.clear()
		for uid in bdict.get("worker_uids", []):
			var w: Variant = game.find_by_uid(int(uid))
			if w is Unit and (w as Unit).work_building == b and not b.workers.has(w):
				b.workers.append(w)
	for u in us.units:
		if u.work_building != null and not u.work_building.workers.has(u):
			u.work_building.workers.append(u)
	# Könige
	for kd in kingdom_data:
		var k: Kingdom = game.get_kingdom(int(kd.get("id", 0)))
		var king: Variant = game.find_by_uid(int(kd.get("king_uid", 0)))
		k.king = king if king is Unit else null


# ---------------------------------------------------------------------------
# Messwerte (Rauchtest: Vergleich vor dem Speichern und nach dem Laden)
# ---------------------------------------------------------------------------

static func metrics(game: Node) -> Dictionary:
	var world: WorldData = game.world
	var terr_count := {}
	for i in world.territory.size():
		var owner_id := world.territory[i]
		if owner_id != 0:
			terr_count[owner_id] = int(terr_count.get(owner_id, 0)) + 1
	var ks := {}
	for k in game.kingdoms:
		var by_def := {}
		var constructed := 0
		for b in k.buildings:
			var id := str(b.def.get("id", ""))
			by_def[id] = int(by_def.get(id, 0)) + 1
			if b.constructed:
				constructed += 1
		var by_type := {}
		var hp_sum := 0.0
		for u in k.units:
			if u.hp <= 0.0:
				continue
			by_type[u.type_id] = int(by_type.get(u.type_id, 0)) + 1
			hp_sum += u.hp
		var heroes: Array = []
		for rec in k.heroes:
			heroes.append([int(rec["id"]), int(rec["level"]), int(rec["xp"]), bool(rec["dead"]),
					(rec.get("ranks", {}) as Dictionary).duplicate(true), (rec.get("talents", []) as Array).duplicate()])
		var researched: Array = k.researched.keys()
		researched.sort()
		var wave: Dictionary = k.ai_state.get("wave", {})
		ks[k.id] = {"controller": k.controller, "defeated": k.defeated, "buildings": by_def, "constructed": constructed,
				"units": by_type, "hp_sum": hp_sum, "resources": k.resources.duplicate(), "researched": researched,
				"research_queue": k.research_queue.duplicate(), "kill_points": k.kill_points,
				"relations": k.relations.duplicate(), "armies": k.armies.duplicate(true), "heroes": heroes,
				"wave_state": str(wave.get("state", "")), "think_count": int(k.ai_state.get("think_count", 0)),
				"territory": int(terr_count.get(k.id, 0))}
	var unit_pos := {}
	for u in game.unit_system.units:
		if u.hp > 0.0:
			unit_pos[u.uid] = u.position
	var building_cells := {}
	for k in game.kingdoms:
		for b in k.buildings:
			building_cells[b.uid] = b.cell
	var rng := {}
	for entry in system_entries(game):
		var sd: Dictionary = entry[1].call("to_dict")
		for key in ["rng", "rng_state"]:
			if sd.has(key):
				rng[entry[0]] = sd[key]
	var extra := {}
	var ds: Variant = game.get("diplomacy_system")
	if ds is Node:
		extra["reputation"] = ds.get("reputation").duplicate(true)
		extra["treaties"] = ds.get("treaties").duplicate(true)
	var es: Variant = game.get("espionage_system")
	if es is Node:
		extra["awareness"] = es.get("awareness").duplicate(true)
		extra["intel"] = es.get("intel").duplicate(true)
	_phase8_9_metrics(game, extra)
	return {"game_time": GameClock.game_time, "uid_counter": int(game.get("uid_counter")), "kingdoms": ks,
			"unit_pos": unit_pos, "building_cells": building_cells, "roads": world.roads.size(),
			"changed_cells": world.changed_cells.size(), "rng": rng, "extra": extra}


## Messwerte der Phasen 8 und 9 (Laufzeit, die rebuild_runtime wieder aufbaut): Zufriedenheit,
## Tageszeit, Ereignisse, Streifzüge, Befestigungen (auch Mauerring und Tore der Wegfindung),
## Handelswege, Einheiten ohne Versorgung
static func _phase8_9_metrics(game: Node, extra: Dictionary) -> void:
	var ss: Variant = game.get("satisfaction_system")
	var siege: Variant = game.get("siege_system")
	var trs: Variant = game.get("trade_route_system")
	var sat := {}
	var forts := {}
	var routes := {}
	for k in game.kingdoms:
		if ss is Node:
			sat[k.id] = float(ss.get_average(k))
		if siege is Node and (k.controller == "player" or k.controller == "ai"):
			var c: Dictionary = (siege.get_counts(k) as Dictionary).duplicate()
			c["walled"] = bool(siege.is_castle_walled(k))
			forts[k.id] = c
		if trs is Node:
			for r in trs.get_routes(k):
				routes[str(r["id"])] = str(r["state"])
	if ss is Node:
		extra["satisfaction"] = sat
	if siege is Node:
		extra["forts"] = forts
		extra["gates"] = (game.nav.gates as Dictionary).size()
	if trs is Node:
		extra["routes"] = routes
	var dns: Variant = game.get("day_night_system")
	if dns is Node:
		extra["day_phase"] = str(dns.get_phase())
	var evs: Variant = game.get("event_system")
	if evs is Node:
		var ids: Array = []
		for ev in evs.get("active"):
			ids.append(str(ev["event_id"]))
		extra["events"] = ids
		extra["offers"] = (evs.get("offers") as Dictionary).size()
	var ms: Variant = game.get("monster_system")
	if ms is Node:
		extra["raids"] = (ms.get("raids") as Array).size()
		extra["lairs"] = (ms.get("lairs") as Dictionary).size()
	var unsupplied := 0
	for u in game.unit_system.units:
		for e in u.effects:
			if str(e.get("id", "")) == SupplySystem.EFFECT_ID:
				unsupplied += 1
				break
	extra["unsupplied"] = unsupplied
