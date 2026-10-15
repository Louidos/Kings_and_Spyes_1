## Rauchtest Armeefenster (gestartet von tests/smoke_test.gd, nicht bei passive=1):
## T öffnet das Fenster (die anderen Fenster in der Mitte schliessen sich), Strg+A und
## "Alle Krieger auswählen" wählen genau die Krieger, Testtruppe als Armee 9 speichern,
## Befehle über das Fenster: Angreifend vorrücken (Zielmodus + Klick), Halten, Patrouille
## (kehrt am Ziel um), Sammeln, Formation Keil/Kreis, Rückzug zur Burg (Erholung).
## Haltung passiv verhindert Angriffe auf einen Übungsgolem, verteidigend greift an;
## Haltung und Patrouille überstehen Speichern/Laden (Unit.to_dict → JSON → restore_unit).
## Dazu: Fenster passt bei UI-Grösse 100/150 %, alle Knöpfe haben Tooltips, Armee auflösen.
## Fehler erscheinen als "ERROR: [smoke] Armee FEHLER: …" (push_error).
extends RefCounted

## Ab dieser Spielzeit (und wenn der Heldentest fertig ist) beginnt der Test
const START_TIME := 260.0
const ARMY := 9

## Vom Rauchtest gesetzt: der Heldentest ist fertig (die Fenster sind frei)
var ui_ready := false

var _game: Node
var _errors := 0
var _step := 0
var _wait_until := 0.0
## Testtruppe (uids) und Übungsgolem
var _uids: Array = []
var _golem: Unit = null
var _spot := Vector2.ZERO
## Angriffe der Testtruppe (Signal CombatSystem.attacked)
var _test_hits := 0
var _patrol_start: Dictionary = {}
var _hp_before := 0.0


func _init(game: Node) -> void:
	_game = game
	game.combat_system.attacked.connect(_on_attacked)


func _check(cond: bool, text: String) -> void:
	if cond:
		print("[smoke] Armee OK: " + text)
	else:
		_errors += 1
		push_error("[smoke] Armee FEHLER: " + text)


func _on_attacked(attacker: Object, _victim: Object, _damage: float) -> void:
	if is_instance_valid(attacker) and attacker is Unit and _uids.has((attacker as Unit).uid):
		_test_hits += 1


## Jeden Frame aufrufen (Spielzeit t)
func tick(t: float) -> void:
	if _step < 0 or t < _wait_until:
		return
	match _step:
		0:
			if ui_ready and t >= START_TIME:
				_s0_window()
				_step = 1
		1:
			_s1_orders(t)
			_step = 2
		2:
			_s2_patrol_turn(t)
		3:
			_s3_passive(t)
		4:
			_s4_defensive(t)
		5:
			_s5_retreat(t)
		6:
			_s6_rest(t)


func _units() -> Array:
	var list: Array = []
	for uid in _uids:
		var u: Variant = _game.find_by_uid(int(uid))
		if is_instance_valid(u) and u is Unit and (u as Unit).is_alive():
			list.append(u)
	return list


func _panel() -> TroopPanel:
	return _game.hud.troop_panel


func _key(physical: Key, ctrl: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.ctrl_pressed = ctrl
	ev.pressed = true
	_game._unhandled_input(ev)


# ---------------------------------------------------------------------------

## Fenster, Auswahl, Armee 9
func _s0_window() -> void:
	var g := _game
	var k: Kingdom = g.player
	var hud: Node = g.hud
	var panel := _panel()
	if not is_instance_valid(k.castle):
		_check(false, "Keine Burg – Test übersprungen")
		_step = -1
		return
	# Testtruppe östlich der Burg
	var center: Vector2 = k.castle.get_center()
	var ts := float(g.world.tile_size)
	var cell: Vector2i = g.nav.nearest_free(g.world.world_to_cell(center + Vector2(9.0 * ts, 0.0)), 6)
	_spot = g.world.cell_to_world(cell)
	var fighter := "fighter_" + k.faction_id
	var archer := "archer_" + k.faction_id
	for i in 6:
		var c: Vector2i = g.nav.nearest_free(cell + Vector2i(i % 3, 1 if i >= 3 else 0), 4)
		var u: Unit = g.unit_system.spawn_unit(k, fighter if i < 4 else archer, g.world.cell_to_world(c))
		if u != null:
			u.command = "hold"
			u.command_pos = u.position
			_uids.append(u.uid)
	_check(_uids.size() == 6, "Testtruppe (4 Kämpfer, 2 Schützen) erschienen")
	# T öffnet, andere Fenster schliessen sich
	hud.open_research()
	_key(KEY_T, false)
	_check(panel.is_open() and not hud.is_research_open(), "T öffnet das Armeefenster und schliesst die Forschung")
	panel.refresh()
	_check(panel._type_rows.has(fighter) and panel._type_rows.has(archer), "Zeilen für Kämpfer und Schützen")
	var counts := TroopPanel.count_states(_units())
	_check(int(counts[TroopPanel.STATE_IDLE]) == 6, "Testtruppe gilt als untätig (%s)" % TroopPanel.states_text(counts))
	_check(hud.top_bar_fits(), "Obere Leiste passt mit dem Knopf „Armee“")
	_check(panel.location_text(_spot).contains("Kacheln") or panel.location_text(_spot).contains("Burg"),
			"Ortsangabe: %s" % panel.location_text(_spot))
	# Alle Krieger: Knopf und Strg+A
	var warriors: Array = g.command_system.get_warriors(k)
	(panel.buttons["all"] as Button).pressed.emit()
	var sel: Array = g.selection.get_own_units()
	var only_warriors := true
	for u in sel:
		if not CommandSystem.is_warrior(u) or (u as Unit).role == "king" or (u as Unit).role == "worker":
			only_warriors = false
	_check(sel.size() == warriors.size() and only_warriors and _contains_all(sel, _units()),
			"„Alle Krieger auswählen“: %d Krieger, ohne Bewohner und König" % sel.size())
	g.selection.clear()
	_key(KEY_A, true)
	_check(g.selection.get_own_units().size() == warriors.size(), "Strg+A wählt alle Krieger (%d)" % g.selection.get_own_units().size())
	# Untätige und Verwundete
	panel.choose_group(TroopPanel.GROUP_IDLE)
	_check(_contains_all(g.selection.get_own_units(), _units()), "„Untätige“ enthält die Testtruppe")
	var hurt: Unit = _units()[0]
	hurt.hp = hurt.max_hp * 0.3
	panel.choose_group(TroopPanel.GROUP_WOUNDED)
	_check(g.selection.get_own_units().has(hurt), "„Verwundete“ enthält die verletzte Einheit")
	hurt.hp = hurt.max_hp
	# Auswahl → Armee 9
	g.selection.select(_units())
	panel.assign_selection_to_army(ARMY)
	_check(g.command_system.get_army(k, ARMY).size() == 6, "Auswahl als Armee %d gespeichert" % ARMY)
	panel.refresh()
	_check(panel._army_rows.has(ARMY), "Armee %d steht in der Liste" % ARMY)
	panel.choose_group(TroopPanel.GROUP_ARMY, str(ARMY))
	_check(panel.group_units().size() == 6 and panel.group_name() == "Armee %d" % ARMY, "Befehlsgruppe Armee %d" % ARMY)
	# Fenster passt bei 100 % und 150 %, Tooltips
	var old_scale := Settings.ui_scale
	var vp_w: float = panel.get_viewport_rect().size.x
	var bad: PackedStringArray = []
	for s in [1.0, 1.5]:
		Settings.ui_scale = s
		Settings.apply()
		panel._place()
		var right := panel.position.x + panel.size.x * panel.scale.x
		if right > vp_w + 1.0 or panel.position.x < -1.0 or panel.size.x > TroopPanel.DESIGN_WIDTH + 1.0:
			bad.append("%d %% (rechts %d, Breite %d)" % [roundi(s * 100.0), roundi(right), roundi(panel.size.x)])
		if not hud.top_bar_fits():
			bad.append("Leiste bei %d %%" % roundi(s * 100.0))
	Settings.ui_scale = old_scale
	Settings.apply()
	if not bad.is_empty():
		# Welcher Teil ist zu breit? (Mindestbreiten der Zeilen und Spalten)
		var widths: PackedStringArray = []
		for c in panel.get_child(0).get_children():
			widths.append("%s %d" % [c.get_class(), roundi((c as Control).get_combined_minimum_size().x)])
			if c is HBoxContainer:
				for cc in c.get_children():
					widths.append("  %s %d" % [cc.get_class(), roundi((cc as Control).get_combined_minimum_size().x)])
		bad.append("Mindestbreiten: " + ", ".join(widths))
	_check(bad.is_empty(), "Fenster und Leiste passen bei UI-Grösse 100/150 %%%s" % ("" if bad.is_empty() else ": " + ", ".join(bad)))
	var missing := _missing_tooltips(panel)
	_check(missing.is_empty(), "Alle Knöpfe des Armeefensters haben Tooltips%s" % ("" if missing.is_empty() else ": " + ", ".join(missing)))
	# Formationen: Plätze verschieden, Neuaufstellung
	var cs: CommandSystem = g.command_system
	for f in ["wedge", "circle"]:
		var slots := cs.formation_slots(_units(), _spot, str(f))
		var distinct := {}
		for p in slots:
			distinct[Vector2i((p as Vector2).round())] = true
		_check(distinct.size() == slots.size(), "Formation %s: %d verschiedene Plätze" % [CommandSystem.get_formation_name(f), distinct.size()])
	var old_formation: String = k.formation
	panel.set_formation("wedge")
	_check(k.formation == "wedge" and _all_command("move"), "Formation Keil: Gruppe stellt sich auf")
	panel.set_formation(old_formation)


## Befehle über das Fenster (Zielmodus wie beim Klick auf die Karte)
func _s1_orders(t: float) -> void:
	var g := _game
	var panel := _panel()
	var ts := float(g.world.tile_size)
	var target: Vector2 = g.world.cell_to_world(g.nav.nearest_free(g.world.world_to_cell(_spot + Vector2(6.0 * ts, 3.0 * ts)), 6))
	if not panel.is_open():
		g.hud.open_army()
	panel.choose_group(TroopPanel.GROUP_ARMY, str(ARMY))
	_check(panel.order("attack_move") and not panel.is_open() and g.selection.get_armed_order() == "attack_move"
			and g.selection.is_attack_move_armed(), "„Angreifend vorrücken“ schliesst das Fenster und wartet auf den Zielklick")
	g.selection._issue_armed_order(g.selection.get_own_units(), target)
	_check(_all_command("attack_move") and g.selection.get_armed_order() == "", "Angreifend vorrücken: alle marschieren kampfbereit")
	g.hud.open_army()
	panel.order("hold")
	_check(_all_command("hold"), "Halten: alle halten die Stellung")
	panel.order("gather")
	_check(_all_command("move"), "Sammeln an der Burg: alle marschieren")
	panel.order("patrol")
	_check(g.selection.get_armed_order() == "patrol" and not g.selection.is_attack_move_armed(), "Patrouille wartet auf den Zielklick")
	g.selection._issue_armed_order(g.selection.get_own_units(), target)
	_check(_all_command("patrol"), "Patrouille: alle patrouillieren")
	_patrol_start.clear()
	for u in _units():
		_patrol_start[(u as Unit).uid] = (u as Unit).patrol_from
	# Speichern/Laden: Haltung und Patrouille bleiben erhalten
	var u0: Unit = _units()[0]
	g.command_system.set_stance([u0], "aggressive")
	var d: Dictionary = SaveCodec.from_json(SaveCodec.to_json(u0.to_dict()))
	d["uid"] = 0
	var copy: Unit = g.unit_system.restore_unit(d)
	_check(copy != null and copy.stance == "aggressive" and copy.command == "patrol" and copy.patrol_from.distance_to(u0.patrol_from) < 0.01,
			"Speichern/Laden: Haltung „%s“ und Patrouille bleiben erhalten" % (copy.stance if copy != null else "-"))
	if copy != null:
		# Haltung wirkt auf die Leine: aggressiv verfolgt auch vom Posten weg
		copy.command = "hold"
		var aggressive_leash := CommandSystem.leash_for(copy)
		copy.stance = "defensive"
		_check(aggressive_leash == "chase" and CommandSystem.leash_for(copy) == "guard",
				"Leine beim Halten: aggressiv %s, verteidigend %s" % [aggressive_leash, CommandSystem.leash_for(copy)])
		g.unit_system.remove_unit(copy)
	g.command_system.set_stance([u0], CommandSystem.DEFAULT_STANCE)
	_wait_until = t + 1.0


## Patrouille kehrt am Ziel um
func _s2_patrol_turn(t: float) -> void:
	var turned := false
	for u in _units():
		var start: Variant = _patrol_start.get((u as Unit).uid)
		if start != null and (u as Unit).command == "patrol" and (u as Unit).command_pos.distance_to(start) < 1.0:
			turned = true
	if turned or t > START_TIME + 120.0:
		_check(turned, "Patrouille kehrt am Wendepunkt um")
		# Passiv: Übungsgolem neben der Truppe – niemand greift an
		var g := _game
		var panel := _panel()
		g.hud.open_army()
		panel.choose_group(TroopPanel.GROUP_ARMY, str(ARMY))
		panel.order("hold")
		panel.set_stance("passive")
		_check(_all_stance("passive"), "Haltung passiv gesetzt")
		var units := _units()
		var c: Vector2i = g.nav.nearest_free(g.world.world_to_cell(TroopPanel.centroid_of(units) + Vector2(1.5 * g.world.tile_size, 0.0)), 4)
		_golem = g.unit_system.spawn_unit(g.wild, "golem", g.world.cell_to_world(c))
		_test_hits = 0
		_step = 3
		_wait_until = t + 8.0


func _s3_passive(t: float) -> void:
	var targets := 0
	for u in _units():
		if (u as Unit).target != null and is_instance_valid((u as Unit).target):
			targets += 1
	_check(_test_hits == 0 and targets == 0, "Passiv: kein Angriff auf den Golem (Treffer %d, Ziele %d)" % [_test_hits, targets])
	# Golem inzwischen von anderen erlegt: neuen neben die Truppe setzen
	if not is_instance_valid(_golem) or not _golem.is_alive():
		var g := _game
		var c: Vector2i = g.nav.nearest_free(g.world.world_to_cell(TroopPanel.centroid_of(_units()) + Vector2(1.5 * g.world.tile_size, 0.0)), 4)
		_golem = g.unit_system.spawn_unit(g.wild, "golem", g.world.cell_to_world(c))
	_panel().set_stance("defensive")
	_test_hits = 0
	_step = 4
	_wait_until = t + 8.0


func _s4_defensive(t: float) -> void:
	_check(_test_hits > 0, "Verteidigend: die Truppe wehrt sich (%d Treffer)" % _test_hits)
	if is_instance_valid(_golem) and _golem.is_alive():
		_game.unit_system.remove_unit(_golem)
	_golem = null
	_step = 5
	_wait_until = t + 1.0


## Rückzug zur Burg: verletzt, danach "rest" und Erholung
func _s5_retreat(t: float) -> void:
	var panel := _panel()
	_game.hud.open_army()
	panel.choose_group(TroopPanel.GROUP_ARMY, str(ARMY))
	_hp_before = 0.0
	for u in _units():
		(u as Unit).hp = (u as Unit).max_hp * 0.4
		_hp_before += (u as Unit).hp
	panel.order("retreat")
	_check(_all_command("retreat"), "Rückzug zur Burg: alle ziehen sich zurück")
	panel.close()
	_step = 6
	_wait_until = t + 1.0


func _s6_rest(t: float) -> void:
	var resting := _all_command("rest")
	if not resting and t < START_TIME + 400.0:
		return
	var hp := 0.0
	for u in _units():
		hp += (u as Unit).hp
	if resting and hp <= _hp_before + 1.0 and t < START_TIME + 400.0:
		return
	_check(resting, "Rückzug: alle erholen sich an der Burg")
	_check(hp > _hp_before, "Erholung an der Burg: Leben %d → %d" % [roundi(_hp_before), roundi(hp)])
	var panel := _panel()
	panel.dissolve_army(ARMY)
	_check(not _game.player.armies.has(ARMY), "Armee %d aufgelöst" % ARMY)
	for u in _units():
		_game.unit_system.remove_unit(u)
	_step = -1


# ---------------------------------------------------------------------------

func _all_command(cmd: String) -> bool:
	var units := _units()
	if units.is_empty():
		return false
	for u in units:
		if (u as Unit).command != cmd:
			return false
	return true


func _all_stance(stance: String) -> bool:
	for u in _units():
		if (u as Unit).stance != stance:
			return false
	return true


static func _contains_all(list: Array, part: Array) -> bool:
	var lookup := {}
	for o in list:
		lookup[o] = true
	for o in part:
		if not lookup.has(o):
			return false
	return true


## Sichtbare Knöpfe ohne Tooltip
static func _missing_tooltips(root: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem and not (n as CanvasItem).visible:
			continue
		for c in n.get_children():
			stack.append(c)
		if n is BaseButton and (n as Control).tooltip_text.is_empty():
			out.append((n as Button).text if n is Button else str(n.name))
	return out


func report() -> void:
	if _step == 0 and GameClock.game_time < START_TIME:
		print("[smoke] Armeetest: nicht gelaufen (Lauf kürzer als %d s)" % roundi(START_TIME))
		return
	if _step >= 0:
		_check(false, "Armeetest nicht fertig geworden (Schritt %d)" % _step)
	print("[smoke] Armeetest: %s" % ("OK" if _errors == 0 else "%d Fehler" % _errors))
