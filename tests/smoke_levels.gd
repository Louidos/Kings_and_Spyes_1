## Rauchtest Ausbaustufen (gestartet von tests/smoke_test.gd, nicht bei passive=1):
## L0  Bauernhof und Wohnhaus sofort bauen; Werte der Stufen steigen (Nahrung je Bauer, Wohnraum);
##     ohne Rohstoffe ist der Ausbau gesperrt; Ausbau beginnen (Kosten weg, Baustelle für Bauarbeiter),
##     Abbrechen erstattet die Kosten
## L1  Bauarbeiter bauen Hof und Haus auf Stufe II aus (das Gebäude arbeitet weiter); Haus danach
##     auf Stufe III; Wohnraum und Ertrag höher; Abriss erstattet die Ausbaukosten anteilig;
##     Spielstand ohne Stufe (SaveMigration, restore_building) ergibt Stufe I
## Nach dem Laden (Phase-10-Rundlauf): Stufen sind erhalten.
## Fehler erscheinen als "ERROR: [smoke] Stufen FEHLER: …" (push_error).
extends RefCounted

var _game: Node
var _errors := 0
var _step := 0
var _deadline := 0.0
var _farm: Building = null
var _house: Building = null
## uid -> erwartete Stufe nach dem Laden
var _expect := {}
var _post_done := false


func _init(_runner: Node, game: Node) -> void:
	_game = game


func _check(cond: bool, text: String) -> void:
	if cond:
		print("[smoke] Stufen OK: " + text)
	else:
		_errors += 1
		push_error("[smoke] Stufen FEHLER: " + text)


## Sofort fertig bauen, mit Abstand zur Burg und einem freien Rand rundum (andere Tests setzen
## ihre Gebäude dicht an die Burg; die Wege dorthin sollen offen bleiben)
func _place(def: Dictionary) -> Building:
	var g: Node = _game
	var k: Kingdom = g.player
	var bs: BuildingSystem = g.building_system
	var center: Vector2i = g.world.world_to_cell(k.castle.get_center())
	var size: Vector2i = def.get("size", Vector2i(2, 2))
	for r in range(9, 18):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var cell := center + Vector2i(dx, dy)
				if not bs.can_place(def, cell, k).is_empty():
					continue
				var free := true
				for y in range(cell.y - 1, cell.y + size.y + 1):
					for x in range(cell.x - 1, cell.x + size.x + 1):
						if g.world.occupancy.has(Vector2i(x, y)) or g.world.roads.has(Vector2i(x, y)):
							free = false
				if free:
					return bs.place_building(def, cell, k, true)
	return null


## Jeden Frame (Hauptlauf)
func tick(t: float) -> void:
	match _step:
		0:
			if t >= 4.0:
				_l0()
				_deadline = t + 300.0
				_step = 1 if _errors == 0 else -1
		1:
			if not is_instance_valid(_farm) or not is_instance_valid(_house):
				_check(false, "Testgebäude sind verschwunden")
				_step = -1
			elif _farm.level >= 2 and _house.level >= 2:
				_l1()
				_step = -1
			elif t > _deadline:
				_check(false, "Bauarbeiter haben den Ausbau nicht beendet (Hof %d %%, Haus %d %%)" % [
						roundi(_farm.get_upgrade_ratio() * 100.0), roundi(_house.get_upgrade_ratio() * 100.0)])
				_step = -1


func _l0() -> void:
	var k: Kingdom = _game.player
	var bs: BuildingSystem = _game.building_system
	# Werte der Stufen aus buildings.json
	var farm1 := float((DataDB.get_building_at_level("farm", 1).get("production", {}) as Dictionary).get("food", 0.0))
	var farm2 := float((DataDB.get_building_at_level("farm", 2).get("production", {}) as Dictionary).get("food", 0.0))
	var house1 := int(DataDB.get_building_at_level("house", 1).get("housing", 0))
	var house3 := int(DataDB.get_building_at_level("house", 3).get("housing", 0))
	_check(farm2 > farm1 * 1.2, "Bauernhof Stufe II: %s statt %s Nahrung je Bauer und Sekunde" % [str(farm2), str(farm1)])
	_check(house3 > house1, "Wohnhaus Stufe III: %d statt %d Wohnplätze" % [house3, house1])
	_check(DataDB.get_building_max_level("house") == 3 and DataDB.get_building_max_level("road") == 1, "Höchste Stufen (Haus III, Strasse I)")
	_farm = _place(DataDB.get_building("farm"))
	_house = _place(DataDB.get_building("house"))
	_check(_farm != null and _house != null, "Hof und Haus platziert")
	if _farm == null or _house == null:
		return
	_check(_farm.level == 1 and _house.level == 1, "Neue Gebäude stehen auf Stufe I")
	# Ohne Rohstoffe gesperrt
	var saved := k.resources.duplicate()
	for r in DataDB.resources:
		k.resources[str(r["id"])] = 0.0
	_check(not bs.can_upgrade(_house).is_empty() and not bs.start_upgrade(_house), "Ausbau ohne Rohstoffe gesperrt: " + bs.can_upgrade(_house))
	for r in DataDB.resources:
		k.resources[str(r["id"])] = 2000.0
	# Abbrechen erstattet die Kosten (cancel_refund)
	var wood := k.get_amount("wood")
	_check(bs.start_upgrade(_farm) and _farm.is_upgrading() and k.get_amount("wood") < wood, "Ausbau beginnt und kostet")
	_check(bs.get_building_sites(k).has(_farm), "Ausbau ist eine Baustelle für die Bauarbeiter")
	bs.cancel_upgrade(_farm)
	_check(not _farm.upgrading and is_equal_approx(k.get_amount("wood"), wood), "Abbruch erstattet die Ausbaukosten")
	# Jetzt richtig: beide ausbauen, die Bauarbeiter kommen
	_check(bs.start_upgrade(_farm) and bs.start_upgrade(_house), "Hof und Haus werden ausgebaut")
	_check(not bs.start_upgrade(_house), "Doppelter Ausbau gesperrt")
	_game.work_system.assign_worker_to_building(_farm)
	k.resources.merge(saved, true)
	for r in DataDB.resources:
		k.resources[str(r["id"])] = maxf(k.get_amount(str(r["id"])), 500.0)


func _l1() -> void:
	var k: Kingdom = _game.player
	var bs: BuildingSystem = _game.building_system
	_check(_farm.level == 2 and not _farm.upgrading and float((_farm.def.get("production", {}) as Dictionary).get("food", 0.0))
			> float((DataDB.get_building("farm").get("production", {}) as Dictionary).get("food", 0.0)),
			"Bauernhof auf Stufe II: mehr Nahrung je Bauer")
	var housing_before := k.get_housing()
	_check(bs.start_upgrade(_house), "Haus Stufe III begonnen")
	_house.complete_upgrade()
	_check(_house.level == 3 and int(_house.def.get("housing", 0)) > int(DataDB.get_building("house").get("housing", 0))
			and k.get_housing() > housing_before, "Haus auf Stufe III: Wohnraum %d (Reich %d → %d)" % [
			int(_house.def.get("housing", 0)), housing_before, k.get_housing()])
	_check(bs.can_upgrade(_house) == "Höchste Stufe erreicht", "Stufe III ist die höchste")
	_check(_house.max_hp > float(DataDB.get_building("house").get("hp", 300.0)) * k.mod("building_hp") - 0.5, "Haus Stufe III hat mehr Leben")
	_expect[_farm.uid] = 2
	_expect[_house.uid] = 3
	# Abriss: Ausbaukosten zählen anteilig mit
	var extra: Building = _place(DataDB.get_building("house"))
	if extra != null:
		bs.start_upgrade(extra)
		extra.complete_upgrade()
		var stone := k.get_amount("stone")
		var dict := extra.to_dict()
		bs.cancel_or_demolish(extra)
		var expected := float(DataDB.get_building_level_entry("house", 2).get("cost", {}).get("stone", 0.0)) \
				* float(DataDB.eco("demolish_refund", 0.5))
		_check(expected > 0.0 and is_equal_approx(k.get_amount("stone") - stone, expected),
				"Abriss erstattet Ausbaukosten anteilig (%+.1f Stein)" % (k.get_amount("stone") - stone))
		# Spielstand ohne Stufe: Migration und Wiederherstellung ergeben Stufe I
		dict.erase("level")
		dict.erase("upgrading")
		dict.erase("upgrade_progress")
		var migrated := SaveMigration.migrate({"buildings": [dict.duplicate(true)]}, 1)
		_check(int(((migrated["buildings"] as Array)[0] as Dictionary).get("level", 0)) == 1, "Migration: fehlende Stufe = I")
		var restored := bs.restore_building(dict)
		_check(restored != null and restored.level == 1 and not restored.upgrading, "Gebäude ohne Stufe lädt auf Stufe I")
		if restored != null:
			bs.remove_building(restored)


## Nach dem Laden (Phase-10-Rundlauf)
func tick_after_load(game: Node, state: String) -> void:
	if _post_done or game == null or not is_instance_valid(game) or state != "continue":
		return
	_post_done = true
	if _expect.is_empty():
		print("[smoke] Stufen: keine Testgebäude zum Prüfen nach dem Laden")
		return
	for uid in _expect:
		var b: Variant = game.find_by_uid(int(uid))
		if not (b is Building):
			print("[smoke] Stufen: Testgebäude %d ist vor dem Speichern verschwunden – nicht geprüft" % int(uid))
			continue
		_check(b is Building and (b as Building).level == int(_expect[uid])
				and (b as Building).def == DataDB.get_building_at_level((b as Building).get_def_id(), int(_expect[uid])),
				"Nach dem Laden: Gebäude %d auf Stufe %s" % [int(uid), DataDB.level_numeral(int(_expect[uid]))])


func report() -> void:
	print("[smoke] Stufen: %s" % ("OK" if _errors == 0 and _step == -1 else "%d Fehler (Schritt %d)" % [_errors, _step]))
	if _step != -1 and _errors == 0:
		push_error("[smoke] Stufen FEHLER: Test nicht fertig geworden (Schritt %d)" % _step)
