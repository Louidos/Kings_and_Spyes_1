## Rauchtest Burgstufen (gestartet von tests/smoke_test.gd gleich zu Beginn, nicht bei passive=1
## und nicht im Tutorial):
## C0  Spielstart auf Burgstufe I: Heldenhalle, Schmiede, Magierturm, Mine … sind im Baumenü
##     gesperrt, der Tooltip nennt die Burgstufe und was für die nächste fehlt; can_place sperrt
##     ebenso; die Burg lässt sich ohne Bewohner und Gebäude nicht ausbauen
## C1  Lager, Bauernhof und Bewohner dazu: Ausbau zum Dorf (Stufe II), Mine frei, Schmiede weiter
##     gesperrt, Gebäudestufe III braucht Burgstufe 3, Reichsfenster (Reiter Burg) zeigt die Stufe
## C2  Burg auf Königssitz (Stufe IV) setzen, damit die übrigen Tests alle Gebäude bauen dürfen
## Nach dem Laden (Phase-10-Rundlauf): die Burgstufe ist erhalten.
## Fehler erscheinen als "ERROR: [smoke] Burg FEHLER: …" (push_error).
extends RefCounted

var _game: Node
var _errors := 0
var _post_done := false


func _init(game: Node) -> void:
	_game = game
	_run()


func _check(cond: bool, text: String) -> void:
	if cond:
		print("[smoke] Burg OK: " + text)
	else:
		_errors += 1
		push_error("[smoke] Burg FEHLER: " + text)


func _run() -> void:
	var g := _game
	var k: Kingdom = g.player
	var bs: BuildingSystem = g.building_system
	var castle := k.castle
	_check(k.get_castle_level() == 1 and castle.get_max_level() == 4, "Spielstart: Burgstufe I von IV (%s)" % DataDB.castle_level_name(1))
	# C0: Sperren im Baumenü
	for id in ["hero_hall", "forge", "mage_tower", "siege_workshop", "temple", "stable"]:
		var lock := BuildMenu.lock_reason(DataDB.get_building(id), k)
		_check(lock.begins_with("Braucht Burgstufe"), "%s gesperrt: %s" % [id, lock])
	var mine_reason := BuildMenu.lock_reason(DataDB.get_building("mine"), k)
	_check(mine_reason.contains("Burgstufe 2") and mine_reason.contains("Bewohner"), "Tooltip nennt, was fehlt: " + mine_reason)
	for id in ["house", "storehouse", "lumberyard", "quarry", "hunter", "farm", "road", "wall"]:
		_check(BuildMenu.lock_reason(DataDB.get_building(id), k).is_empty(), "%s ab Burgstufe I frei" % id)
	var menu: BuildMenu = g.hud.build_menu
	var tip: String = menu._build_tip("hero_hall")
	_check(tip.contains("Burgstufe 3") and tip.contains("Burg ausbauen"), "Baumenü-Tooltip der Heldenhalle nennt die Burgstufe")
	_check(not bs.can_build_type(DataDB.get_building("forge"), k).is_empty(), "Schmiede: can_build_type gesperrt")
	var castle_reason := bs.can_upgrade(castle)
	_check(castle_reason.contains("Bewohner"), "Burg ohne Bewohner nicht ausbaubar: " + castle_reason)
	# C1: Bedingungen erfüllen und zum Dorf ausbauen
	for r in DataDB.resources:
		k.resources[str(r["id"])] = 5000.0
	_check(_place("storehouse") != null and _place("farm") != null, "Lager und Bauernhof gebaut")
	var need := int(DataDB.get_building_level_entry("castle", 2).get("requires_population", 0))
	var tries := 0
	while k.get_population() < need and tries < 40:
		tries += 1
		var u: Unit = g.unit_system.spawn_unit(k, "villager", castle.get_approach_point(castle.get_center() + Vector2(0, 900)))
		if u != null:
			g.work_system.set_unit_job(u, "idle")
	var reqs := BuildingSystem.level_requirements(castle.get_next_level_entry(), k)
	var all_ok := true
	for req in reqs:
		all_ok = all_ok and bool(req["ok"])
	_check(reqs.size() >= 3 and all_ok, "Bedingungen für das Dorf erfüllt (%d Bewohner)" % k.get_population())
	_check(bs.can_upgrade(castle).is_empty() and bs.start_upgrade(castle) and castle.is_upgrading(), "Burgausbau begonnen")
	castle.complete_upgrade()
	_check(k.get_castle_level() == 2 and int(castle.def.get("housing", 0)) > int(DataDB.get_building("castle").get("housing", 0)),
			"Burgstufe II (%s), Wohnraum %d" % [DataDB.castle_level_name(2), int(castle.def.get("housing", 0))])
	_check(BuildMenu.lock_reason(DataDB.get_building("mine"), k).is_empty(), "Mine ab Burgstufe II frei")
	_check(BuildMenu.lock_reason(DataDB.get_building("forge"), k).contains("Burgstufe 3"), "Schmiede braucht weiter Burgstufe 3")
	var house := _place("house")
	if house != null:
		bs.start_upgrade(house)
		house.complete_upgrade()
		_check(house.level == 2 and bs.can_upgrade(house).contains("Burgstufe 3"), "Gebäudestufe III braucht Burgstufe 3: " + bs.can_upgrade(house))
	g.hud.open_kingdom(KingdomPanel.TAB_CASTLE)
	var panel: KingdomPanel = g.hud.kingdom_panel
	panel._refresh()
	_check(panel.is_open() and panel.get_tab() == KingdomPanel.TAB_CASTLE and panel._castle_text.text.contains("Dorf")
			and panel._castle_text.text.contains("✗"), "Reichsfenster, Reiter Burg: Stufe und Bedingungen mit ✓/✗")
	g.hud.close_top_panel()
	# C2: alles freischalten für die übrigen Tests
	bs.set_castle_level(k, 4)
	var locked: PackedStringArray = []
	for def in DataDB.buildings:
		if bool(def.get("player_buildable", true)) and BuildMenu.lock_reason(def, k).begins_with("Braucht Burgstufe"):
			locked.append(str(def["id"]))
	_check(k.get_castle_level() == 4 and locked.is_empty(), "Burgstufe IV (%s): keine Burgsperren mehr" % DataDB.castle_level_name(4))
	print("[smoke] Burg: %s" % ("OK" if _errors == 0 else "%d Fehler" % _errors))


## Sofort fertig bauen, mit Abstand zur Burg und freiem Rand rundum
func _place(id: String) -> Building:
	var def := DataDB.get_building(id)
	var g := _game
	var k: Kingdom = g.player
	var bs: BuildingSystem = g.building_system
	var center: Vector2i = g.world.world_to_cell(k.castle.get_center())
	var size: Vector2i = def.get("size", Vector2i(2, 2))
	for r in range(10, 20):
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


## Nach dem Laden (Phase-10-Rundlauf)
func tick_after_load(game: Node, state: String) -> void:
	if _post_done or game == null or not is_instance_valid(game) or state != "continue":
		return
	_post_done = true
	var k: Kingdom = game.player
	_check(k.get_castle_level() == 4 and k.castle.def == DataDB.get_building_at_level("castle", 4), "Nach dem Laden: Burgstufe IV")


func report() -> void:
	if _errors > 0:
		print("[smoke] Burg: %d Fehler" % _errors)
