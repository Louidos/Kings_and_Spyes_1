## Bildschirmfotos der Oberfläche (gestartet von tests/smoke_test.gd mit ui_shots=1 shots=<ordner>,
## nur mit echtem Fenster, z. B. unter xvfb-run). Baut ein kleines Reich auf (Kaserne, Schmiede,
## Reitstall, Magierturm, Heldenhalle, je Truppentyp ein paar Einheiten mit Rängen, ein Held) und
## fotografiert nacheinander: leere Oberfläche, Kaserne, Schmiede, einzelne Truppe, gemischte
## Gruppe, Held, alle Fenster (Forschung, Helden, Diplomatie, Spionage, Reich, Armee, Hilfe,
## Speichern). Fenstergrösse mit win=<B>x<H> (Standard 1600x900).
## Ohne Prüfungen – Fehler erscheinen nur als SCRIPT ERROR.
extends RefCounted

## Bilder (warten zwischen zwei Schritten: Layout und Zeichnen)
const WAIT_FRAMES := 10

var finished := false

var _runner: Node
var _game: Node
var _step := 0
var _frames := 0
var _buildings := {}
var _units: Array = []
var _hero_wait := 0
var _prefix := ""


func _init(runner: Node, game: Node, args: Dictionary) -> void:
	_runner = runner
	_game = game
	var win := str(args.get("win", "1600x900")).split("x")
	if win.size() == 2:
		_runner.get_tree().root.size = Vector2i(int(win[0]), int(win[1]))
	_prefix = "%s_%s_" % [str(args.get("win", "1600x900")), str(args.get("ui_scale", "1"))]


func _shot(shot_name: String) -> void:
	_runner.call("_shot", _prefix + shot_name)


## Jeden Frame
func tick() -> void:
	_frames += 1
	if _frames < WAIT_FRAMES:
		return
	_frames = 0
	var g := _game
	var hud: Node = g.hud
	match _step:
		0:
			_setup()
		1:
			_shot("01_hud")
			g.selection.select([_buildings.get("barracks")])
		2:
			_shot("02_kaserne")
			g.selection.select([_buildings.get("forge")])
		3:
			_shot("03_schmiede")
			for u in _units:
				if is_instance_valid(u) and (u as Unit).vet_rank >= 2:
					g.selection.select([u])
					break
		4:
			_shot("04_truppe")
			g.selection.select_all_warriors()
		5:
			_shot("05_gruppe")
			var k: Kingdom = g.player
			if k.heroes.is_empty() and _hero_wait < 60:
				_hero_wait += 1
				return
			var hu: Unit = null
			if not k.heroes.is_empty():
				hu = g.hero_system.get_unit(k, int((k.heroes[0] as Dictionary)["id"]))
			g.selection.select([hu] if hu != null else [])
		6:
			_shot("06_held")
			g.selection.clear()
			hud.open_research()
		7:
			_shot("07_forschung")
			hud.open_heroes()
		8:
			_shot("08_helden")
			hud.open_diplomacy()
		9:
			_shot("09_diplomatie")
			hud.open_espionage()
		10:
			_shot("10_spionage")
			hud.open_kingdom()
		11:
			_shot("11_reich")
			hud.open_army()
		12:
			_shot("12_armee")
			hud.close_top_panel()
			hud.open_help()
		13:
			_shot("13_hilfe")
			hud.close_top_panel()
			g.call("_open_pause_menu")
			g.pause_menu.show_page("save")
		14:
			_shot("14_speichern")
			g.pause_menu.close()
			finished = true
	_step += 1


func _setup() -> void:
	var g := _game
	var k: Kingdom = g.player
	for r in DataDB.resources:
		k.resources[str(r["id"])] = 5000.0
	var rs: ResearchSystem = g.research_system
	for tier in ["spearman", "crossbow", "heavy", "cavalry", "battlemage", "elite"]:
		var def := DataDB.get_unit_for_tier(k.faction_id, tier)
		if def.is_empty():
			continue
		var r := DataDB.find_research_unlocking(k.faction_id, "unit:" + str(def["id"]))
		if not r.is_empty() and not k.researched.has(r["id"]):
			k.researched[r["id"]] = true
			rs.apply_effects(k, str(r["id"]))
	for id in ["barracks", "forge", "stable", "mage_tower", "hero_hall", "library"]:
		_buildings[id] = _runner.call("_place_near_castle", DataDB.get_building(id))
	# Je Truppentyp drei Einheiten bei der Burg, einige mit Rang
	var center: Vector2 = k.castle.get_center() + Vector2(0, 160)
	var i := 0
	var ts: TroopSystem = g.troop_system
	for tier in ["fighter", "archer", "spearman", "crossbow", "heavy", "cavalry", "battlemage"]:
		var def := DataDB.get_unit_for_tier(k.faction_id, tier)
		if def.is_empty():
			continue
		for n in 3:
			var pos := center + Vector2((i % 9) * 34 - 136, floori(i / 9.0) * 34)
			var u: Unit = g.unit_system.spawn_unit(k, str(def["id"]), pos)
			if u != null:
				_units.append(u)
				if n == 0:
					ts.debug_add_xp(u, 400.0)
			i += 1
	var offers: Array = g.hero_system.get_offers(k)
	if not offers.is_empty():
		g.hero_system.recruit(k, str((offers[0] as Dictionary)["id"]))
