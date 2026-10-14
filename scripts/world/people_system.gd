## PeopleSystem
##
## Völker (Phase 8): setzt den Grundbonus des Volks (peoples.json → base_bonus) als
## Quelle "people:<id>" für jedes Reich mit Volk und die Geländeboni je Einheit
## (terrain_bonus: Faktoren auf dem Biom unter der Einheit). Das Volk einer Einheit ist
## type_def.people, sonst das Volk ihres Reichs.
## Geländeboni liegen im abgeleiteten Feld Unit.terrain_mods und werden nur bei einem
## Biomwechsel neu gesetzt; je Takt werden höchstens CHECK_PER_TICK Einheiten geprüft.
##
## Zustand: keiner. Die Volks-ids stehen in Kingdom.people_id, die Boni in
## Kingdom.modifier_sources; alles andere wird aus den Daten neu aufgebaut.
class_name PeopleSystem
extends Node

## Volk eines Reichs wurde gesetzt (Grundbonus neu)
signal people_changed(k: Kingdom)

## Einheiten, deren Biom je Takt (0,1 s) geprüft wird
const CHECK_PER_TICK := 250
## Gemeinsames leeres Dictionary (nie verändern)
const EMPTY := {}

var game: Node
var world: WorldData

## people_id -> {Biom-Index -> {Schlüssel -> Faktor}} (gemeinsame Dictionaries, nur lesen).
## "defense" ist umgerechnet auf "damage_taken" = 1 / defense.
var _tables: Dictionary = {}
## uid -> Tabelle des Volks der Einheit (oder EMPTY)
var _unit_table: Dictionary = {}
var _cursor := 0
## Rechenzeit (Rauchtest): Summe und Höchstwert in Mikrosekunden, Anzahl Takte
var tick_usec_total := 0
var tick_usec_max := 0
var tick_count := 0


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_build_tables()
	GameClock.sim_tick.connect(_on_sim_tick)
	var us: UnitSystem = game.unit_system
	us.unit_spawned.connect(_on_unit_spawned)
	us.unit_transferred.connect(_on_unit_transferred)
	us.unit_removed.connect(_on_unit_removed)


# ---------------------------------------------------------------------------
# Völker der Reiche
# ---------------------------------------------------------------------------

## Grundbonus für jedes Reich mit Volk, danach alle Einheiten neu zuordnen
func apply_all() -> void:
	for k in game.kingdoms:
		if not (k as Kingdom).people_id.is_empty():
			apply_people(k)
	for u in game.unit_system.units:
		_assign(u)
		refresh_unit(u, true)


## Volk eines Reichs wechseln (alte Quelle "people:*" weg, neue setzen)
func set_people(k: Kingdom, people_id: String) -> void:
	if k == null:
		return
	for source in k.modifier_sources.keys():
		if str(source).begins_with("people:"):
			k.clear_modifiers(str(source))
	k.people_id = people_id
	apply_people(k)
	for u in k.units:
		_assign(u)
		refresh_unit(u, true)
	people_changed.emit(k)


## Grundbonus des Volks als Quelle "people:<id>"
func apply_people(k: Kingdom) -> void:
	if k == null or k.people_id.is_empty():
		return
	var base: Dictionary = get_people(k).get("base_bonus", {})
	var factors := {}
	for key in base:
		factors[str(key)] = float(base[key])
	k.replace_modifiers("people:" + k.people_id, factors)


func get_people(k: Kingdom) -> Dictionary:
	return DataDB.get_people(k.people_id) if k != null else {}


## Volk einer Einheit: eigenes Volk des Typs (Dorfmilizen), sonst das des Reichs
func unit_people_id(u: Unit) -> String:
	var own := str(u.type_def.get("people", ""))
	if not own.is_empty():
		return own
	return u.kingdom.people_id if u.kingdom != null else ""


# ---------------------------------------------------------------------------
# Geländeboni
# ---------------------------------------------------------------------------

## Biom unter der Einheit prüfen und bei Bedarf terrain_mods setzen (force: immer neu bestimmen)
func refresh_unit(u: Unit, force: bool = false) -> void:
	if not is_instance_valid(u):
		return
	var table: Dictionary = _unit_table.get(u.uid, EMPTY)
	if force:
		u.terrain_biome = -1
	if table.is_empty():
		if not u.terrain_mods.is_empty():
			u.terrain_mods = EMPTY
			u.refresh_stats()
		return
	_check(u, table)


## "Wald (Hochelfen): +10 % Angriff, +10 % Tempo" oder "" (keine Geländeboni)
func get_terrain_text(u: Unit) -> String:
	if u == null or u.terrain_mods.is_empty() or u.terrain_biome < 0:
		return ""
	var parts: PackedStringArray = []
	for key in u.terrain_mods:
		parts.append(_mod_text(str(key), float(u.terrain_mods[key])))
	var biome_name := str(DataDB.get_biome(u.terrain_biome).get("name", "?"))
	return "%s (%s): %s" % [biome_name, DataDB.get_people_name(unit_people_id(u)), ", ".join(parts)]


## Geländetabelle eines Volks: [{"biome", "name", "text", "preferred"}]
func get_terrain_table(people_id: String) -> Array:
	var p := DataDB.get_people(people_id)
	var bonus: Dictionary = p.get("terrain_bonus", {})
	var preferred: Array = p.get("preferred_biomes", [])
	var list: Array = []
	for b in DataDB.biomes:
		var biome_id := str(b.get("id", ""))
		var parts: PackedStringArray = []
		var entry: Dictionary = bonus.get(biome_id, {})
		for key in entry:
			parts.append(DataDB.describe_modifier("defense" if str(key) == "defense" else str(key), float(entry[key])))
		list.append({"biome": biome_id, "name": str(b.get("name", biome_id)),
				"text": "–" if parts.is_empty() else ", ".join(parts), "preferred": preferred.has(biome_id)})
	return list


## Zusammenfassung eines Volks für Fenster: Name, Farbe, Beschreibung, Stärken,
## Schwächen, Grundbonus und bevorzugtes Gelände als Text
func get_summary(k: Kingdom) -> Dictionary:
	var p := get_people(k)
	if p.is_empty():
		return {}
	var base_parts: PackedStringArray = []
	var base: Dictionary = p.get("base_bonus", {})
	for key in base:
		base_parts.append(DataDB.describe_modifier(str(key), float(base[key])))
	var biome_names: PackedStringArray = []
	for biome_id in p.get("preferred_biomes", []):
		var index := int(DataDB.biome_index_by_id.get(str(biome_id), -1))
		biome_names.append(str(DataDB.get_biome(index).get("name", biome_id)) if index >= 0 else str(biome_id))
	return {"name": str(p.get("name", k.people_id)), "color": p.get("color", Color.WHITE),
			"description": str(p.get("description", "")), "strengths": p.get("strengths", []),
			"weaknesses": p.get("weaknesses", []), "base_text": ", ".join(base_parts),
			"preferred_text": ", ".join(biome_names)}


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(_dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var units: Array = game.unit_system.units
	var n := units.size()
	if n == 0:
		return
	if _cursor >= n:
		_cursor = 0
	var count := mini(CHECK_PER_TICK, n)
	for _i in count:
		var u: Unit = units[_cursor]
		_cursor += 1
		if _cursor >= n:
			_cursor = 0
		var table: Dictionary = _unit_table.get(u.uid, EMPTY)
		if table.is_empty() or u.inside != null or u.hp <= 0.0:
			continue
		_check(u, table)
	var used := Time.get_ticks_usec() - t0
	tick_usec_total += used
	tick_usec_max = maxi(tick_usec_max, used)
	tick_count += 1


## Biom unter der Einheit (direkt aus dem Kartenarray); nur bei Wechsel neu rechnen
func _check(u: Unit, table: Dictionary) -> void:
	var c := world.world_to_cell(u.position)
	if not world.in_bounds(c):
		return
	var bi := int(world.biomes[world.cell_index(c)])
	if bi == u.terrain_biome:
		return
	u.terrain_biome = bi
	var mods: Dictionary = table.get(bi, EMPTY)
	if not is_same(mods, u.terrain_mods):
		u.terrain_mods = mods
		u.refresh_stats()


func _on_unit_spawned(u: Unit) -> void:
	_assign(u)
	refresh_unit(u, true)


func _on_unit_transferred(u: Unit, _from: Kingdom, _to: Kingdom) -> void:
	_assign(u)
	refresh_unit(u, true)


func _on_unit_removed(u: Unit) -> void:
	_unit_table.erase(u.uid)


func _assign(u: Unit) -> void:
	_unit_table[u.uid] = _tables.get(unit_people_id(u), EMPTY)


## Tabellen je Volk: Biom-Index -> Faktoren (defense als damage_taken)
func _build_tables() -> void:
	_tables.clear()
	for p in DataDB.peoples:
		var bonus: Dictionary = (p as Dictionary).get("terrain_bonus", {})
		if bonus.is_empty():
			continue
		var table := {}
		for biome_id in bonus:
			var index := int(DataDB.biome_index_by_id.get(str(biome_id), -1))
			if index < 0:
				continue
			var mods := {}
			var entry: Dictionary = bonus[biome_id]
			for key in entry:
				var f := float(entry[key])
				if str(key) == "defense":
					mods["damage_taken"] = 1.0 / maxf(f, 0.05)
				else:
					mods[str(key)] = f
			table[index] = mods
		_tables[str(p.get("id", ""))] = table


## "+10 % Angriff"; damage_taken als Verteidigung
static func _mod_text(key: String, factor: float) -> String:
	if key == "damage_taken":
		return DataDB.describe_modifier("defense", 1.0 / maxf(factor, 0.01))
	return DataDB.describe_modifier(key, factor)


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {}


func from_dict(_d: Dictionary) -> void:
	pass


## Tabellen neu, Volksboni aller Reiche, Geländeboni aller Einheiten neu bestimmen
func rebuild_runtime() -> void:
	_build_tables()
	_unit_table.clear()
	_cursor = 0
	apply_all()
