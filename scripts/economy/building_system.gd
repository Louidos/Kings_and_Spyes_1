## BuildingSystem
##
## Alles rund um Gebäude und Strassen: Platzierungsregeln, Baustellen,
## Fertigstellung (Gebiet wächst), Entfernen und die laufende Produktion
## (Bauernhof, Manabrunnen). Arbeitet für jedes Reich gleich.
##
## Regel: Simulationssysteme greifen nie auf Darstellung (WorldMap, HUD,
## Kamera) zu. Die Darstellung hört auf Signale von WorldData und den Systemen.
class_name BuildingSystem
extends Node

signal building_placed(building: Building)
signal building_completed(building: Building)
signal building_removed(building: Building)
signal roads_changed
## Ein Gebäude hat den Besitzer gewechselt (Aufnahme, Eroberung; ab Phase 8 Verrat)
signal building_transferred(building: Building, from_kingdom: Kingdom, to_kingdom: Kingdom)
## Ausbau bezahlt und begonnen bzw. abgebrochen; fertig (building.level ist die neue Stufe)
signal building_upgrade_started(building: Building)
signal building_upgrade_cancelled(building: Building)
signal building_upgraded(building: Building)

var game: Node
var world: WorldData


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	GameClock.sim_tick.connect(_on_sim_tick)


# ---------------------------------------------------------------------------
# Platzieren
# ---------------------------------------------------------------------------

## Prüft, ob ein Gebäude hier gebaut werden darf. "" = ja, sonst der Grund.
## Ab Phase 9: Tore dürfen auf eigene Mauerstücke (replaces) und eigene Strassen
## (allow_on_road); vor einem Tor muss Platz bleiben.
func can_place(def: Dictionary, cell: Vector2i, kingdom: Kingdom) -> String:
	return _place_reason(def, cell, kingdom, true)


func _place_reason(def: Dictionary, cell: Vector2i, kingdom: Kingdom, check_cost: bool) -> String:
	if def.get("is_road", false):
		var reason := can_place_road(cell, kingdom)
		if reason.is_empty() and check_cost:
			reason = kingdom.missing_text(def.get("cost", {}))
		return reason
	var type_reason := can_build_type(def, kingdom)
	if not type_reason.is_empty():
		return type_reason
	var size: Vector2i = def.get("size", Vector2i(2, 2))
	var required_id := str(def.get("requires_deposit", ""))
	var required_found := required_id.is_empty()
	var replaces: Array = def.get("replaces", [])
	var on_road := bool(def.get("allow_on_road", false))
	var siege: Variant = game.get("siege_system")
	for y in range(cell.y, cell.y + size.y):
		for x in range(cell.x, cell.x + size.x):
			var c := Vector2i(x, y)
			if not world.in_bounds(c):
				return "Ausserhalb der Karte"
			if world.get_owner(c) != kingdom.id:
				return "Nur im eigenen Gebiet – fertige Gebäude vergrössern dein Gebiet"
			var biome := world.get_biome(c)
			if not biome.get("buildable", false):
				return "Hier kann nicht gebaut werden: %s" % biome.get("name", "?")
			var occ: Variant = world.occupancy.get(c, null)
			if occ != null:
				# Tor auf ein eigenes Mauerstück: ersetzt es
				if not (is_instance_valid(occ) and occ.kingdom == kingdom and replaces.has(str(occ.def.get("id", "")))):
					return "Platz ist belegt"
			elif world.roads.has(c):
				if not on_road or int(world.road_owner.get(c, 0)) != kingdom.id:
					return "Platz ist belegt"
			if siege != null and (siege as SiegeSystem).is_gate_apron(c):
				return "Vor einem Tor muss Platz bleiben"
			var d := world.get_deposit(c)
			if not d.is_empty() and not d["biome_deposit"]:
				if d["id"] == required_id:
					required_found = true
				else:
					return "Rohstoffvorkommen im Weg: %s" % d["name"]
	if not required_found:
		return "Muss auf einer %s stehen" % DataDB.get_deposit_by_id(required_id).get("name", required_id)
	return kingdom.missing_text(def.get("cost", {})) if check_cost else ""


## Setzt ein Gebäude (als Baustelle, ausser instant). Zieht die Kosten ab.
## Gibt null zurück, wenn es nicht bezahlt werden kann. Ersetzt Mauerstücke (Tor).
func place_building(def: Dictionary, cell: Vector2i, kingdom: Kingdom, instant: bool = false) -> Building:
	if not instant and not kingdom.spend(def.get("cost", {})):
		return null
	var replaces: Array = def.get("replaces", [])
	if not replaces.is_empty():
		var sz: Vector2i = def.get("size", Vector2i(2, 2))
		for y in range(cell.y, cell.y + sz.y):
			for x in range(cell.x, cell.x + sz.x):
				var old: Variant = world.occupancy.get(Vector2i(x, y), null)
				if old != null and is_instance_valid(old) and old.kingdom == kingdom and replaces.has(str(old.def.get("id", ""))):
					remove_building(old, float(DataDB.siege("segments.replace_refund", 0.5)))
	var b := Building.new()
	b.setup(def, kingdom, cell, world, game.next_uid())
	var fp := b.get_footprint()
	# Geländefaktor vor dem Roden bestimmen (Wald zählt als Wald)
	b.biome_efficiency = _biome_efficiency(def, fp)
	for y in range(fp.position.y, fp.end.y):
		for x in range(fp.position.x, fp.end.x):
			var c := Vector2i(x, y)
			world.occupancy[c] = b
			_clear_biome_deposit(c)
			if b.blocks_movement():
				game.nav.set_solid(c, true)
	kingdom.buildings.append(b)
	game.entities.add_child(b)
	game.register_entity(b)
	b.finished.connect(_on_building_finished)
	b.upgraded.connect(_on_building_upgraded)
	building_placed.emit(b)
	if instant or float(def.get("build_time", 0.0)) <= 0.0:
		b.complete()
	return b


## Setzt die Königsburg einer neuen Siedlung: sofort fertig, Untergrund wird
## bebaubar gemacht.
func place_start_castle(kingdom: Kingdom, center_cell: Vector2i) -> Building:
	var castle := place_settlement_center(DataDB.get_building("castle"), kingdom, center_cell)
	kingdom.castle = castle
	return castle


## Siedlungsmittelpunkt (Burg, Dorfzentrum): Grundfläche um center_cell freiräumen
## (Vorkommen weg, unbebaubares Biom wird Ebene) und sofort fertig setzen.
## Setzt NICHT kingdom.castle.
func place_settlement_center(def: Dictionary, kingdom: Kingdom, center_cell: Vector2i) -> Building:
	var size: Vector2i = def.get("size", Vector2i(4, 4))
	var top_left := center_cell - Vector2i(size.x >> 1, size.y >> 1)
	top_left = top_left.clamp(Vector2i.ZERO, Vector2i(world.width, world.height) - size)
	var plains := int(DataDB.biome_index_by_id.get("plains", DataDB.default_biome_index))
	for y in range(top_left.y, top_left.y + size.y):
		for x in range(top_left.x, top_left.x + size.x):
			var c := Vector2i(x, y)
			if world.get_deposit_index(c) >= 0:
				world.set_deposit(c, -1, 0)
			if not world.get_biome(c).get("buildable", false):
				world.set_biome(c, plains)
	return place_building(def, top_left, kingdom, true)


## Spielstand laden (Phase 10): Gebäude aus Building.to_dict wiederherstellen. Ohne
## Kosten, ohne Roden (steht schon im Welt-Diff) und ohne Signale (building_placed,
## building_completed, finished). null bei unbekanntem Typ oder Reich.
func restore_building(d: Dictionary) -> Building:
	var def := DataDB.get_building(str(d.get("def_id", "")))
	var kingdom: Kingdom = game.get_kingdom(int(d.get("kingdom_id", 0)))
	if def.is_empty() or kingdom == null:
		return null
	var b := Building.new()
	b.extra = (d.get("extra", {}) as Dictionary).duplicate(true)
	b.setup(def, kingdom, d.get("cell", Vector2i.ZERO), world, int(d.get("uid", 0)))
	b.constructed = bool(d.get("constructed", false))
	b.progress = float(d.get("progress", 0.0))
	# Ausbaustufe (ältere Spielstände: Stufe 1, siehe SaveMigration)
	b.set_level(int(d.get("level", 1)))
	b.upgrading = b.constructed and bool(d.get("upgrading", false)) and b.level < b.get_max_level()
	b.upgrade_progress = float(d.get("upgrade_progress", 0.0)) if b.upgrading else 0.0
	b.max_hp = maxf(float(d.get("max_hp", b.max_hp)), 1.0)
	b.hp = float(d.get("hp", b.max_hp))
	b.last_damaged_at = float(d.get("last_damaged_at", -1000.0))
	b.summon_queue = (d.get("summon_queue", []) as Array).duplicate(true)
	b.rally_point = d.get("rally_point", Vector2.ZERO)
	b.has_rally = bool(d.get("has_rally", false))
	b.summon_count = int(d.get("summon_count", 0))
	b.loot_factor = float(d.get("loot_factor", 1.0))
	b.biome_efficiency = float(d.get("biome_efficiency", 1.0))
	b.refresh_look()
	var fp := b.get_footprint()
	for y in range(fp.position.y, fp.end.y):
		for x in range(fp.position.x, fp.end.x):
			var c := Vector2i(x, y)
			world.occupancy[c] = b
			if b.blocks_movement():
				game.nav.set_solid(c, true)
	kingdom.buildings.append(b)
	game.entities.add_child(b)
	game.register_entity(b)
	b.finished.connect(_on_building_finished)
	b.upgraded.connect(_on_building_upgraded)
	return b


## Besitzerwechsel eines Gebäudes (Aufnahme, Eroberung; ab Phase 8 Verrat). Arbeiter
## werden frei, Beschwörungen erstattet (an den alten Besitzer), Leben behält seinen
## Anteil, Gebiet und Wohnraum gehen mit.
func transfer_building(b: Building, to: Kingdom) -> void:
	if not is_instance_valid(b) or to == null:
		return
	var from := b.kingdom
	if from == null or from == to or not from.buildings.has(b):
		return
	# Arbeiter freigeben, solange das Gebäude noch dem alten Besitzer gehört
	game.work_system.on_building_removed(b)
	while not b.summon_queue.is_empty():
		game.summon_system.cancel(b, 0)
	from.buildings.erase(b)
	if from.castle == b:
		from.castle = null
	to.buildings.append(b)
	b.kingdom = to
	b.has_rally = false
	var ratio := clampf(b.hp / maxf(b.max_hp, 1.0), 0.0, 1.0)
	b.max_hp = b.compute_max_hp(to)
	b.hp = b.max_hp * ratio
	b.refresh_look()
	if b.constructed and int(b.def.get("territory_radius", 0)) > 0:
		game.territory.recompute_area(world, TerritorySystem.claim_rect(b, world), game.kingdoms)
	if int(b.def.get("housing", 0)) > 0:
		from.population_changed.emit()
		to.population_changed.emit()
	building_transferred.emit(b, from, to)


# ---------------------------------------------------------------------------
# Strassen (Zustand liegt in WorldData: roads, road_owner, road_progress)
# ---------------------------------------------------------------------------

## Darf das Reich diesen Gebäudetyp überhaupt bauen (unabhängig vom Ort)?
## Forschung (requires), andere fertige Gebäude (requires_buildings) und die
## Höchstzahl (max_per_kingdom, Baustellen zählen mit). "" = ja, sonst der Grund.
func can_build_type(def: Dictionary, kingdom: Kingdom) -> String:
	var requires: Array = def.get("requires", [])
	if not kingdom.has_all_unlocks(requires):
		return "Benötigt Forschung: %s" % DataDB.describe_requirement(requires, kingdom.faction_id)
	for bid in def.get("requires_buildings", []):
		if count_buildings(kingdom, str(bid), true) == 0:
			return "Benötigt: %s" % DataDB.get_building_name(DataDB.get_building(str(bid)), kingdom.faction_id)
	var max_count := int(def.get("max_per_kingdom", 0))
	if max_count > 0 and count_buildings(kingdom, str(def.get("id", "")), false) >= max_count:
		return "Nur %s %s pro Reich" % ["eine" if max_count == 1 else str(max_count),
				DataDB.get_building_name(def, kingdom.faction_id)]
	return ""


## Anzahl Gebäude dieses Typs (nur fertige oder auch Baustellen)
func count_buildings(kingdom: Kingdom, def_id: String, constructed_only: bool) -> int:
	var n := 0
	for b in kingdom.buildings:
		if str(b.def.get("id", "")) == def_id and (b.constructed or not constructed_only):
			n += 1
	return n


func can_place_road(cell: Vector2i, kingdom: Kingdom) -> String:
	if not world.in_bounds(cell):
		return "Ausserhalb der Karte"
	if world.get_owner(cell) != kingdom.id:
		return "Nur im eigenen Gebiet"
	var biome := world.get_biome(cell)
	if not biome.get("buildable", false):
		return "Hier kann keine Strasse gebaut werden: %s" % biome.get("name", "?")
	if world.roads.has(cell):
		return "Hier ist schon eine Strasse"
	if world.occupancy.has(cell):
		return "Platz ist belegt"
	var d := world.get_deposit(cell)
	if not d.is_empty() and not d["biome_deposit"]:
		return "Rohstoffvorkommen im Weg: %s" % d["name"]
	return ""


## Legt Strassenbaustellen in der gegebenen Reihenfolge an, solange sie gültig
## und bezahlbar sind. Gibt die Anzahl der gesetzten Strassen zurück.
func place_roads(cells: Array, kingdom: Kingdom) -> int:
	var cost: Dictionary = DataDB.get_building("road").get("cost", {})
	var placed := 0
	for c in cells:
		if not can_place_road(c, kingdom).is_empty():
			continue
		if not kingdom.spend(cost):
			break
		_clear_biome_deposit(c)
		world.set_road(c, WorldData.ROAD_PLANNED, kingdom.id)
		placed += 1
	if placed > 0:
		roads_changed.emit()
	return placed


## Eine Kachel einer Linie (Strasse oder Mauer): "" = ok (ohne Kosten). Mauern: auf eigener
## Strasse gilt die Prüfung des Tors (def.line_gate).
func can_place_line_cell(def: Dictionary, cell: Vector2i, kingdom: Kingdom) -> String:
	if bool(def.get("is_road", false)):
		return can_place_road(cell, kingdom)
	var gate_id := str(def.get("line_gate", ""))
	if not gate_id.is_empty() and world.roads.has(cell) and int(world.road_owner.get(cell, 0)) == kingdom.id \
			and not world.occupancy.has(cell):
		return _place_reason(DataDB.get_building(gate_id), cell, kingdom, false)
	return _place_reason(def, cell, kingdom, false)


## Gebäude, das auf dieser Kachel einer Linie entstehen würde (Tor über eigener Strasse)
func line_def_at(def: Dictionary, cell: Vector2i, kingdom: Kingdom) -> Dictionary:
	var gate_id := str(def.get("line_gate", ""))
	if not gate_id.is_empty() and world.roads.has(cell) and int(world.road_owner.get(cell, 0)) == kingdom.id \
			and not world.occupancy.has(cell):
		return DataDB.get_building(gate_id)
	return def


## Setzt eine Linie in Reihenfolge, solange gültig und bezahlbar: Strassen wie place_roads,
## Mauern als Baustellen (instant: sofort fertig – KI-Debug/Rauchtest); über eigenen
## Strassen ein Tor. Höchstens segments.line_max Kacheln.
## Rückgabe {"placed": int, "gates": int, "reason": String (erster Grund, wenn nichts ging)}
func place_line(def: Dictionary, cells: Array, kingdom: Kingdom, instant: bool = false) -> Dictionary:
	var result := {"placed": 0, "gates": 0, "reason": ""}
	if bool(def.get("is_road", false)):
		result["placed"] = place_roads(cells, kingdom)
		if int(result["placed"]) == 0 and not cells.is_empty():
			var reason := kingdom.missing_text(def.get("cost", {}))
			result["reason"] = reason if not reason.is_empty() else can_place_road(cells[0], kingdom)
		return result
	var line_max := int(DataDB.siege("segments.line_max", 80))
	var first_reason := ""
	var n := 0
	for c in cells:
		if n >= line_max:
			break
		n += 1
		var reason := can_place_line_cell(def, c, kingdom)
		if not reason.is_empty():
			if first_reason.is_empty():
				first_reason = reason
			continue
		var d := line_def_at(def, c, kingdom)
		if not instant and not kingdom.can_afford(d.get("cost", {})):
			first_reason = kingdom.missing_text(d.get("cost", {}))
			break
		if place_building(d, c, kingdom, instant) == null:
			continue
		result["placed"] = int(result["placed"]) + 1
		if d != def:
			result["gates"] = int(result["gates"]) + 1
	if int(result["placed"]) == 0:
		result["reason"] = first_reason
	return result


func is_road_site(cell: Vector2i) -> bool:
	return world.road_progress.has(cell)


## Bauarbeit an einer Strasse. Gibt true zurück, wenn sie dadurch fertig wurde.
func add_road_work(cell: Vector2i, amount: float) -> bool:
	if not world.road_progress.has(cell):
		return false
	world.road_progress[cell] = float(world.road_progress[cell]) + amount
	if world.road_progress[cell] < float(DataDB.get_building("road").get("build_time", 2.0)):
		return false
	world.set_road(cell, WorldData.ROAD_BUILT)
	roads_changed.emit()
	return true


## Entfernt eine Strasse. Nur der Besitzer darf das (kingdom = null: ohne Prüfung).
## Geplante Strassen werden erstattet, fertige nicht.
func remove_road(cell: Vector2i, kingdom: Kingdom = null) -> bool:
	if not world.roads.has(cell):
		return false
	var owner_id := int(world.road_owner.get(cell, 0))
	if kingdom != null and owner_id != kingdom.id:
		return false
	if world.road_progress.has(cell):
		var owner_kingdom: Kingdom = game.get_kingdom(owner_id)
		if owner_kingdom != null:
			owner_kingdom.refund(DataDB.get_building("road").get("cost", {}), float(DataDB.eco("cancel_refund", 1.0)))
	world.set_road(cell, WorldData.ROAD_NONE)
	roads_changed.emit()
	return true


# ---------------------------------------------------------------------------
# Baustellen, Entfernen, Abfragen
# ---------------------------------------------------------------------------

## Anzahl Gebäude ohne Mauerstücke (KI-Wachstum, Statistik)
func count_real_buildings(kingdom: Kingdom) -> int:
	var n := 0
	for b in kingdom.buildings:
		if not b.is_segment:
			n += 1
	return n


## Fertige, beschädigte Gebäude, die Bauarbeiter reparieren dürfen (repairable,
## hp < threshold × max_hp, seit delay_seconds ohne Schaden)
func get_repair_sites(kingdom: Kingdom) -> Array:
	var sites: Array = []
	var threshold := float(DataDB.siege("repair.threshold", 0.98))
	var delay := float(DataDB.siege("repair.delay_seconds", 10))
	var now := GameClock.game_time
	for b in kingdom.buildings:
		if b.constructed and b.hp < b.max_hp * threshold and now - b.last_damaged_at >= delay \
				and bool(b.def.get("repairable", true)):
			sites.append(b)
	return sites


## Kosten für amount Leben Reparatur (cost_factor × Baukosten / max_hp, sonst default_cost_per_hp)
func repair_cost(b: Building, amount: float) -> Dictionary:
	var cost := {}
	var base: Dictionary = b.def.get("cost", {})
	if base.is_empty():
		var per_hp: Dictionary = DataDB.siege("repair.default_cost_per_hp", {})
		for res_id in per_hp:
			cost[res_id] = float(per_hp[res_id]) * amount
		return cost
	var factor := float(DataDB.siege("repair.cost_factor", 0.5))
	for res_id in base:
		if str(res_id) == "mana":
			continue
		cost[res_id] = factor * float(base[res_id]) / maxf(b.max_hp, 1.0) * amount
	return cost


## Reparaturarbeit: heilt hp_per_work × amount, zieht die Kosten ab. Gibt "" zurück,
## "done" (heil) oder den Grund (fehlende Rohstoffe)
func add_repair_work(b: Building, amount: float) -> String:
	if not is_instance_valid(b) or not b.constructed:
		return "done"
	var gain := minf(float(DataDB.siege("repair.hp_per_work", 20)) * amount, b.max_hp - b.hp)
	if gain <= 0.0:
		return "done"
	var cost := repair_cost(b, gain)
	if not b.kingdom.can_afford(cost):
		return b.kingdom.missing_text(cost)
	b.kingdom.spend(cost)
	b.hp = minf(b.hp + gain, b.max_hp)
	b.queue_redraw()
	if b.hp >= b.max_hp - 0.01:
		b.hp = b.max_hp
		return "done"
	return ""


## Offene Gebäude-Baustellen eines Reichs (auch laufende Ausbauten)
func get_building_sites(kingdom: Kingdom) -> Array:
	var sites: Array = []
	for b in kingdom.buildings:
		if not b.constructed or b.upgrading:
			sites.append(b)
	return sites


# ---------------------------------------------------------------------------
# Ausbaustufen (buildings.json → levels)
# ---------------------------------------------------------------------------

## Darf das Gebäude jetzt auf die nächste Stufe ausgebaut werden? "" = ja, sonst der Grund.
## check_cost = false: nur Bedingungen (Stufe, Forschung, Gebäude), nicht die Kosten.
func can_upgrade(b: Building, check_cost: bool = true) -> String:
	if not is_instance_valid(b) or b.kingdom == null:
		return "Kein Gebäude"
	if not b.constructed:
		return "Erst fertig bauen"
	if b.upgrading:
		return "Wird schon ausgebaut"
	if b.level >= b.get_max_level():
		return "Höchste Stufe erreicht" if b.get_max_level() > 1 else "Kann nicht ausgebaut werden"
	var reason := level_requirement_reason(b.get_next_level_entry(), b.kingdom)
	if not reason.is_empty():
		return reason
	return b.kingdom.missing_text(b.get_next_level_entry().get("cost", {})) if check_cost else ""


## Bedingungen eines levels-Eintrags (Forschung, fertige Gebäude). "" = erfüllt
func level_requirement_reason(entry: Dictionary, kingdom: Kingdom) -> String:
	var requires: Array = entry.get("requires", [])
	if not kingdom.has_all_unlocks(requires):
		return "Benötigt Forschung: %s" % DataDB.describe_requirement(requires, kingdom.faction_id)
	for bid in entry.get("requires_buildings", []):
		if count_buildings(kingdom, str(bid), true) == 0:
			return "Benötigt: %s" % DataDB.get_building_name(DataDB.get_building(str(bid)), kingdom.faction_id)
	return ""


## Ausbau bezahlen und beginnen: die Bauarbeiter kommen wie zu einer Baustelle, das Gebäude
## arbeitet weiter. false, wenn es nicht geht (can_upgrade).
func start_upgrade(b: Building) -> bool:
	if not can_upgrade(b).is_empty():
		return false
	if not b.kingdom.spend(b.get_next_level_entry().get("cost", {})):
		return false
	b.upgrading = true
	b.upgrade_progress = 0.0
	b.queue_redraw()
	game.work_system.request_wake(b.kingdom)
	building_upgrade_started.emit(b)
	return true


## Laufenden Ausbau abbrechen: Kosten zurück (cancel_refund), Stufe bleibt.
func cancel_upgrade(b: Building) -> void:
	if not is_instance_valid(b) or not b.is_upgrading():
		return
	b.kingdom.refund(b.get_next_level_entry().get("cost", {}), float(DataDB.eco("cancel_refund", 1.0)))
	b.upgrading = false
	b.upgrade_progress = 0.0
	b.queue_redraw()
	building_upgrade_cancelled.emit(b)


## Anzahl fertiger Gebäude eines Reichs mit mindestens dieser Stufe (def_id "" = alle Typen)
func count_buildings_at_level(kingdom: Kingdom, def_id: String, min_level: int) -> int:
	var n := 0
	for b in kingdom.buildings:
		if b.constructed and b.level >= min_level and (def_id.is_empty() or b.get_def_id() == def_id):
			n += 1
	return n


## Was sich von Werten a zu Werten b ändert (Zeilen für Tooltips: "Wohnraum 4 → 5" …)
static func level_change_lines(a: Dictionary, b: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var pairs := [["housing", "Wohnraum", false], ["workers", "Arbeitsplätze", false],
			["gather_radius", "Sammelradius (Felder)", false], ["gather_bonus", "Sammeltempo", true],
			["hp", "Leben", false], ["armor", "Rüstung", true], ["summon_speed", "Beschwörungstempo", true],
			["research_speed", "Forschungstempo", true], ["forge_discount", "Rabatt in der Schmiede", true]]
	for p in pairs:
		var key := str(p[0])
		var default_value := 1.0 if key.ends_with("_speed") else 0.0
		var va := float(a.get(key, default_value))
		var vb := float(b.get(key, default_value))
		if is_equal_approx(va, vb):
			continue
		lines.append("%s: %s → %s" % [p[1], _level_value(va, bool(p[2])), _level_value(vb, bool(p[2]))])
	for table_key in ["production", "base_production"]:
		var ta: Dictionary = a.get(table_key, {})
		var tb: Dictionary = b.get(table_key, {})
		for res_id in tb:
			var va := float(ta.get(res_id, 0.0)) * 60.0
			var vb := float(tb[res_id]) * 60.0
			if not is_equal_approx(va, vb):
				lines.append("%s %s: %s → %s pro Minute" % ["Ertrag je Arbeiter" if table_key == "production" else "Grundertrag",
						str(DataDB.get_resource(str(res_id)).get("name", res_id)), _level_value(va, false), _level_value(vb, false)])
	var tw_a: Dictionary = a.get("tower", {})
	var tw_b: Dictionary = b.get("tower", {})
	if not tw_b.is_empty():
		if not is_equal_approx(float(tw_a.get("attack", 0.0)), float(tw_b.get("attack", 0.0))):
			lines.append("Turm-Angriff: %s → %s" % [_level_value(float(tw_a.get("attack", 0.0)), false),
					_level_value(float(tw_b.get("attack", 0.0)), false)])
		if not is_equal_approx(float(tw_a.get("range", 0.0)), float(tw_b.get("range", 0.0))):
			lines.append("Reichweite: %s → %s Felder" % [_level_value(float(tw_a.get("range", 0.0)), false),
					_level_value(float(tw_b.get("range", 0.0)), false)])
	var sat_a: Dictionary = a.get("satisfaction", {})
	var sat_b: Dictionary = b.get("satisfaction", {})
	if not sat_b.is_empty():
		if int(sat_a.get("capacity", 0)) != int(sat_b.get("capacity", 0)):
			lines.append("Versorgt Bewohner: %d → %d" % [int(sat_a.get("capacity", 0)), int(sat_b.get("capacity", 0))])
		if not is_equal_approx(float(sat_a.get("bonus", 0.0)), float(sat_b.get("bonus", 0.0))):
			lines.append("Zufriedenheit: %+d → %+d" % [roundi(float(sat_a.get("bonus", 0.0))), roundi(float(sat_b.get("bonus", 0.0)))])
	var aura_a: Dictionary = a.get("heal_aura", {})
	var aura_b: Dictionary = b.get("heal_aura", {})
	if not aura_b.is_empty() and not is_equal_approx(float(aura_a.get("hp_per_sec", 0.0)), float(aura_b.get("hp_per_sec", 0.0))):
		lines.append("Heilung: %s → %s Leben/s" % [_level_value(float(aura_a.get("hp_per_sec", 0.0)), false),
				_level_value(float(aura_b.get("hp_per_sec", 0.0)), false)])
	return lines


static func _level_value(v: float, percent_value: bool) -> String:
	if percent_value:
		return "%d %%" % roundi(v * 100.0)
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else String.num(v, 1).replace(".", ",")


## Geplante Strassen eines Reichs (Kacheln)
func get_road_sites(kingdom: Kingdom) -> Array:
	var sites: Array = []
	for c in world.road_progress:
		if int(world.road_owner.get(c, 0)) == kingdom.id:
			sites.append(c)
	return sites


## Baustelle abbrechen (volle Rückerstattung) oder fertiges Gebäude abreissen (teilweise).
func cancel_or_demolish(b: Building) -> void:
	if not is_instance_valid(b):
		return
	if b == b.kingdom.castle:
		b.kingdom.notify("Die Königsburg kann nicht abgerissen werden.", "warning")
		return
	var factor := float(DataDB.eco("demolish_refund", 0.5)) if b.constructed else float(DataDB.eco("cancel_refund", 1.0))
	remove_building(b, factor)


## Der einzige Weg, ein Gebäude zu entfernen (Abriss, Abbruch, Zerstörung).
## destroyed = true: zerstört (Feind, Untergang) – die Beschwörungs-Warteschlange wird
## dann nicht erstattet (nur bei eigenem Abriss bzw. Abbruch).
func remove_building(b: Building, refund_factor: float = 0.0, destroyed: bool = false) -> void:
	if not is_instance_valid(b) or not b.kingdom.buildings.has(b):
		return
	var kingdom := b.kingdom
	b.destroyed = destroyed
	if refund_factor > 0.0:
		# Bau- und Ausbaukosten anteilig; ein laufender Ausbau wird wie eine Baustelle erstattet
		kingdom.refund(b.get_invested_cost() if b.constructed else b.def.get("cost", {}), refund_factor)
		if b.is_upgrading():
			kingdom.refund(b.get_next_level_entry().get("cost", {}), float(DataDB.eco("cancel_refund", 1.0)))
	var fp := b.get_footprint()
	for y in range(fp.position.y, fp.end.y):
		for x in range(fp.position.x, fp.end.x):
			var c := Vector2i(x, y)
			world.occupancy.erase(c)
			game.nav.set_solid(c, false)
	kingdom.buildings.erase(b)
	if kingdom.castle == b:
		kingdom.castle = null
	game.unregister_entity(b)
	building_removed.emit(b)
	if b.constructed:
		if int(b.def.get("territory_radius", 0)) > 0:
			game.territory.recompute_area(world, TerritorySystem.claim_rect(b, world), game.kingdoms)
		kingdom.population_changed.emit()
	b.queue_free()


func get_building_at(cell: Vector2i) -> Building:
	return world.occupancy.get(cell, null)


## Fertige Gebäude eines Reichs, die diese Ressource annehmen
func get_dropoffs(kingdom: Kingdom, res_id: String) -> Array:
	var list: Array = []
	for b in kingdom.buildings:
		if b.accepts(res_id):
			list.append(b)
	return list


# ---------------------------------------------------------------------------
# Intern
# ---------------------------------------------------------------------------

func _on_building_finished(b: Building) -> void:
	var kingdom := b.kingdom
	if int(b.def.get("territory_radius", 0)) > 0:
		game.territory.recompute_area(world, TerritorySystem.claim_rect(b, world), game.kingdoms)
	if int(b.def.get("housing", 0)) > 0:
		kingdom.population_changed.emit()
	if float(b.def.get("build_time", 0.0)) > 0.0 and not b.is_segment:
		kingdom.add_stat("buildings_built")
		var text := "%s fertiggestellt" % b.get_display_name()
		if b.get_worker_slots() > 0:
			text += " – weise in der Arbeitsverteilung (J) Arbeiter zu"
		elif not b.def.get("summons", []).is_empty():
			text += " – auswählen, um Einheiten zu beschwören"
		kingdom.notify(text, "good", b.get_center())
	building_completed.emit(b)


## Ausbau fertig: Wohnraum und Arbeitsplätze neu, Meldung
func _on_building_upgraded(b: Building) -> void:
	var kingdom := b.kingdom
	if int(b.def.get("housing", 0)) > 0:
		kingdom.population_changed.emit()
	kingdom.add_stat("buildings_upgraded")
	kingdom.notify("%s auf Stufe %s ausgebaut" % [b.get_display_name(), DataDB.level_numeral(b.level)], "good", b.get_center())
	building_upgraded.emit(b)


## Wald o. Ä. unter einem Gebäude oder einer Strasse roden (Biom wird z. B. Ebene).
func _clear_biome_deposit(c: Vector2i) -> void:
	var d := world.get_deposit(c)
	if d.is_empty() or not d["biome_deposit"]:
		return
	world.set_deposit(c, -1, 0)
	var after := str(d.get("depleted_biome", ""))
	if not after.is_empty() and DataDB.biome_index_by_id.has(after):
		world.set_biome(c, DataDB.biome_index_by_id[after])


## Geschätzter Gelände-Faktor (biome_efficiency) eines Gebäudes an dieser Stelle,
## bevor es gebaut wird (Bauplatzsuche der KI, Vorschau). 1.0 ohne Tabelle.
func estimate_efficiency(def: Dictionary, cell: Vector2i) -> float:
	return _biome_efficiency(def, Rect2i(cell, def.get("size", Vector2i(2, 2))))


## Durchschnittlicher Gelände-Faktor der Grundfläche (für Produktion)
func _biome_efficiency(def: Dictionary, fp: Rect2i) -> float:
	var table: Dictionary = def.get("biome_efficiency", {})
	if table.is_empty():
		return 1.0
	var total := 0.0
	for y in range(fp.position.y, fp.end.y):
		for x in range(fp.position.x, fp.end.x):
			total += float(table.get(world.get_biome(Vector2i(x, y)).get("id", ""), 1.0))
	return total / maxf(float(fp.get_area()), 1.0)


## Laufende Produktion fertiger Gebäude (pro Simulationsschritt)
func _on_sim_tick(dt: float) -> void:
	for kingdom in game.kingdoms:
		for b in kingdom.buildings:
			if not b.constructed:
				continue
			var per_worker: Dictionary = b.def.get("production", {})
			var base: Dictionary = b.def.get("base_production", {})
			if per_worker.is_empty() and base.is_empty():
				continue
			# Arbeiter zählen nach ihrer Arbeitsleistung (Zufriedenheit, Seuche)
			var working := 0.0
			for u in b.workers:
				if u.state == Unit.State.WORKING:
					working += u.work_mult
			var job := DataDB.get_job(str(b.def.get("job", "")))
			var factor: float = game.work_system.work_factor(kingdom, job)
			var gains := {}
			for res_id in per_worker:
				gains[res_id] = float(per_worker[res_id]) * working * factor
			for res_id in base:
				gains[res_id] = float(gains.get(res_id, 0.0)) + float(base[res_id])
			for res_id in gains:
				if gains[res_id] > 0.0:
					# Wetterzauber (Segensregen) im Gebiet des Gebäudes
					var weather: float = game.magic_system.get_production_factor(kingdom, b.position, res_id)
					var mult: float = kingdom.mod("production") * kingdom.mod("production." + res_id) * weather
					kingdom.add_resource(res_id, gains[res_id] * b.biome_efficiency * mult * dt)


# ---------------------------------------------------------------------------
# Speichern (Phase 10): Gebäude und Strassen speichert SaveGame selbst
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {}


func from_dict(_d: Dictionary) -> void:
	pass


func rebuild_runtime() -> void:
	pass
