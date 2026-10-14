## VictorySystem
##
## Niederlage und Sieg (Phase 7). Ein Reich (Spieler oder KI) fällt, wenn sein König
## stirbt oder seine Burg zerstört wird (game.defeat_kingdom). Ein gefallenes
## KI-Reich zerfällt: Helden gehen, Einheiten lösen sich auf, Gebäude werden zu
## Ruinen (reine Darstellung, blockieren nichts), das Gebiet verschwindet, Verträge
## enden, alle Kriege ruhen. Sind alle Reiche der Gegenfraktion gefallen, ist der Sieg
## erreicht (victory_reached – game.gd zeigt den Siegbildschirm mit "Weiterspielen").
## Fällt die Burg des Spielers, ist das Spiel verloren (wie beim Tod des Königs).
##
## Zustand (gespeichert): ruins, fallen, victory_done, continued.
## Laufzeit: _pending – Kampfsignale (building_destroyed, kingdom_defeated) feuern
## mitten in den Schleifen des CombatSystems und werden erst im eigenen Takt
## abgearbeitet.
class_name VictorySystem
extends Node

## Ein Reich ist gefallen und zerfallen (reason "king" | "castle" | …, by = Sieger oder null)
signal kingdom_fallen(k: Kingdom, reason: String, by: Kingdom)
## Alle feindlichen Königreiche sind besiegt
signal victory_reached
## Ruinen sind dazugekommen oder verschwunden (Darstellung)
signal ruins_changed

var game: Node

## Ruinen: {"cell": Vector2i, "size": Vector2i, "until": float, "castle": bool,
##  "kingdom_id": int, "color": String (html)}
var ruins: Array = []
## Gefallene Reiche: {"id", "name", "reason", "by_id", "at"}
var fallen: Array = []
## Der Sieg wurde ausgelöst (einmal je Partie)
var victory_done := false
## Nach dem Sieg wird weitergespielt
var continued := false

## Laufzeit: ["castle", Reich-id, Sieger-id] | ["ruin", Reich-id]
var _pending: Array = []
var _ruin_check_acc := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	GameClock.sim_tick.connect(_on_sim_tick)
	game.kingdom_defeated.connect(_on_kingdom_defeated)
	game.combat_system.building_destroyed.connect(_on_building_destroyed)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Feindliche Königreiche: KI-Reiche der Gegenfraktion des Spielers
func get_enemy_kingdoms(include_defeated: bool = true) -> Array:
	var list: Array = []
	var player: Kingdom = game.player
	if player == null:
		return list
	var enemy := AISystem.enemy_faction(player.faction_id)
	for k in game.kingdoms:
		if k.controller == "ai" and k.faction_id == enemy and (include_defeated or not k.defeated):
			list.append(k)
	return list


## Sieg prüfen: alle feindlichen Reiche gefallen, der Spieler lebt -> victory_reached
func check_victory() -> bool:
	if victory_done:
		return true
	var enemies := get_enemy_kingdoms()
	if enemies.is_empty() or game.player == null or game.player.defeated:
		return false
	for k in enemies:
		if not k.defeated:
			return false
	victory_done = true
	victory_reached.emit()
	return true


## Statistik für Sieg- und Niederlagebildschirm (mehrzeilig)
func get_stats_text(k: Kingdom) -> String:
	var lines: PackedStringArray = []
	lines.append("Gespielt: %s" % GameClock.get_time_string())
	var enemies := get_enemy_kingdoms()
	var beaten: PackedStringArray = []
	for e in enemies:
		if e.defeated:
			beaten.append(e.display_name)
	var line := "Besiegte Reiche: %d von %d" % [beaten.size(), enemies.size()]
	if not beaten.is_empty():
		line += " (%s)" % ", ".join(beaten)
	lines.append(line)
	var allied: int = game.diplomacy_system.get_allied_villages(k).size()
	var annexed := 0
	var conquered := 0
	var vs: VillageSystem = game.village_system
	for v in vs.get_villages(true):
		var rec := vs.get_record(v)
		if int(rec.get("owner_id", 0)) != k.id:
			continue
		match str(rec.get("status", "")):
			"annexed":
				annexed += 1
			"conquered":
				conquered += 1
	lines.append("Dörfer: verbündet %d, aufgenommen %d, erobert %d" % [allied, annexed, conquered])
	lines.append("Beschworene Einheiten: %d" % int(k.stats.get("summoned", 0)))
	lines.append("Besiegte Feinde: %d · Verluste: %d" % [int(k.stats.get("kills", 0)), int(k.stats.get("losses", 0))])
	lines.append("Gebäude gebaut: %d · Kampfpunkte gesamt: %d" % [int(k.stats.get("buildings_built", 0)), k.kill_points_total])
	var esp: Object = game.ai_system.espionage()
	if esp != null:
		var disc: Variant = esp.get("discovery")
		if disc is Dictionary:
			var entry: Dictionary = (disc as Dictionary).get(k.id, {})
			if not entry.is_empty():
				lines.append("Höchster Entdeckungswert: %d" % roundi(float(entry.get("peak", 0.0))))
	lines.append("Gefangene Spione: %d" % int(k.stats.get("spies_caught", 0)))
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# Debug
# ---------------------------------------------------------------------------

## Reich besiegen wie eine echte Niederlage (über _pending, im nächsten Takt)
func debug_defeat(k: Kingdom, reason: String = "castle") -> void:
	if k == null or k.defeated:
		return
	if reason == "castle":
		_pending.append(["castle", k.id, game.player.id if game.player != null and game.player != k else 0])
	else:
		game.defeat_kingdom(k, reason, null)


# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------

## Burg zerstört (das Signal kommt vor dem Entfernen des Gebäudes): Niederlage vormerken
func _on_building_destroyed(b: Building, killer: Kingdom) -> void:
	var k := b.kingdom
	if k == null or k.defeated or b != k.castle or (k.controller != "player" and k.controller != "ai"):
		return
	_pending.append(["castle", k.id, killer.id if killer != null else 0])


## Ein KI-Reich hat verloren (König tot, Burg zerstört): Zerfall vormerken
func _on_kingdom_defeated(k: Kingdom, _reason: String) -> void:
	if k != null and k.controller == "ai":
		_pending.append(["ruin", k.id])


func _on_sim_tick(dt: float) -> void:
	while not _pending.is_empty():
		var entry: Array = _pending.pop_front()
		var k: Kingdom = game.get_kingdom(int(entry[1]))
		if k == null:
			continue
		match str(entry[0]):
			"castle":
				game.defeat_kingdom(k, "castle", game.get_kingdom(int(entry[2])))
			"ruin":
				_ruin_kingdom(k)
				check_victory()
	_ruin_check_acc += dt
	if _ruin_check_acc >= 5.0 and not ruins.is_empty():
		_ruin_check_acc = 0.0
		var now := GameClock.game_time
		var before := ruins.size()
		ruins = ruins.filter(func(r: Dictionary) -> bool: return float(r["until"]) > now)
		if ruins.size() != before:
			ruins_changed.emit()


## Zerfall eines gefallenen KI-Reichs (Reihenfolge wichtig: erst Gehirn und Spionage,
## dann Helden, Einheiten, Gebäude, Verträge, Beziehungen)
func _ruin_kingdom(k: Kingdom) -> void:
	if k.buildings.is_empty() and k.units.is_empty() and _has_fallen(k):
		return
	var pos: Vector2 = k.ai_state.get("home_rally", Vector2.ZERO)
	if is_instance_valid(k.castle):
		pos = k.castle.get_center()
	var by: Kingdom = game.get_kingdom(int(k.flags.get("defeated_by", 0)))
	var reason := str(k.flags.get("defeat_reason", "castle"))
	game.ai_system.on_kingdom_defeated(k)
	for sys_name in ["espionage_system", "spy_system"]:
		var other: Variant = game.get(sys_name)
		if other is Object and is_instance_valid(other) and (other as Object).has_method("on_kingdom_defeated"):
			(other as Object).call("on_kingdom_defeated", k)
	for rec in k.heroes.duplicate():
		game.hero_system.dismiss(k, int(rec["id"]))
	for u in k.units.duplicate():
		game.unit_system.remove_unit(u)
	k.king = null
	var until := GameClock.game_time + float(DataDB.ai("defeat.ruin_seconds", 1800))
	for b in k.buildings.duplicate():
		# Mauerstücke werden ohne Ruine entfernt (Phase 9)
		if not b.is_segment:
			ruins.append({"cell": b.cell, "size": b.size, "until": until, "castle": b == k.castle,
					"kingdom_id": k.id, "color": k.color.to_html(false)})
		game.building_system.remove_building(b, 0.0, true)
	for c in game.building_system.get_road_sites(k):
		game.building_system.remove_road(c)
	var ds: DiplomacySystem = game.diplomacy_system
	for v in game.village_system.get_villages():
		if not ds.get_treaty_with(v, k).is_empty():
			ds.end_all_treaties(v, "fallen")
	for o in game.kingdoms:
		if o != k and o.controller != "wild" and k.relations.has(o.id):
			game.set_relation(k, o, "peace")
	k.upkeep.clear()
	k.research_queue.clear()
	fallen.append({"id": k.id, "name": k.display_name, "reason": reason, "by_id": by.id if by != null else 0,
			"at": GameClock.game_time})
	if by != null:
		by.add_stat("kingdoms_defeated")
	var why := "Der König ist tot" if reason == "king" else "Die Burg ist zerstört"
	if game.player != null:
		game.player.notify("%s ist gefallen! (%s)" % [k.display_name, why], "good", pos)
	kingdom_fallen.emit(k, reason, by)
	ruins_changed.emit()


func _has_fallen(k: Kingdom) -> bool:
	for f in fallen:
		if int(f["id"]) == k.id:
			return true
	return false


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"ruins": ruins.duplicate(true), "fallen": fallen.duplicate(true), "victory_done": victory_done,
			"continued": continued, "pending": _pending.duplicate(true), "ruin_check_acc": _ruin_check_acc}


func from_dict(d: Dictionary) -> void:
	ruins = (d.get("ruins", []) as Array).duplicate(true)
	fallen = (d.get("fallen", []) as Array).duplicate(true)
	victory_done = bool(d.get("victory_done", false))
	continued = bool(d.get("continued", false))
	_pending = (d.get("pending", []) as Array).duplicate(true)
	_ruin_check_acc = float(d.get("ruin_check_acc", 0.0))


## Nach dem Laden: Ruinen neu zeichnen (die Warteliste _pending ist gespeichert und bleibt,
## sonst würde ein Reich mit zerstörter Burg nie besiegt)
func rebuild_runtime() -> void:
	ruins_changed.emit()
