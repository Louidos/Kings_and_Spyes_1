## Rauchtest Truppen (gestartet von tests/smoke_test.gd; bei passive=1 nur der Bericht über die KI):
## T0  Kaserne, Schmiede, Bibliothek sofort bauen; neue Truppen sind ohne Forschung gesperrt;
##     Forschung freischalten, Reitstall und Magierturm bauen, jede neue Truppe über die
##     Warteschlange ihres Gebäudes beschwören
## T1  Konter (Speer gegen Reiter, Reiter gegen Schützen), Rüstungsdurchschlag der Armbrust,
##     Schmiede über das Auswahlfenster (Angriff der Fusstruppen steigt, Quelle "upgrade:<id>"),
##     Erfahrung → Rang → Wertepunkt verteilen (Wert steigt), Kampf-Erfahrung aus Treffern,
##     Mehrfachauswahl "Punkte automatisch verteilen", KI verteilt selbst, Aussehen je Typ
##     und je Einheit (Heldenbanner erst ab Elite)
## T2  Erfahrung für den Sieg (nach dem Kampftakt)
## T3  nach dem Heldentest: Wertepunkte eines Helden über das Auswahlfenster
## Nach dem Laden (Phase-10-Rundlauf): Aussehen, Rang, Wertepunkte, Schmiede und
## Heldenpunkte sind erhalten.
## Fehler erscheinen als "ERROR: [smoke] Truppen FEHLER: …" (push_error).
extends RefCounted

## Neue Truppenstufen (units.json) und das Gebäude, das sie beschwört
const NEW_TIERS := {"spearman": "barracks", "crossbow": "barracks", "heavy": "barracks", "cavalry": "stable",
		"battlemage": "mage_tower"}

## Vom Rauchtest gesetzt: der Heldentest ist fertig (Fenster und Auswahl sind frei)
var ui_ready := false
## Passiver Lauf (passive=1): keine Prüfungen, nur der Bericht über die KI
var passive := false

var _runner: Node
var _game: Node
var _errors := 0
var _step := 0
var _deadline := 0.0
var _buildings := {}
## Stufe -> uid der beschworenen Einheit
var _summoned := {}
var _kill_attacker := 0
var _kill_xp_before := 0.0
var _kill_check_at := 0.0
var _expect := {}
var _post_done := false
var _hero_done := false
## Bericht über die KI: Reichsname -> {Stufe -> höchste gesehene Zahl, "rank" -> höchste Zahl mit Rang}
var _ai_seen := {}
var _ai_sample_at := 0.0


func _init(runner: Node, game: Node) -> void:
	_runner = runner
	_game = game


func _check(cond: bool, text: String) -> void:
	if cond:
		print("[smoke] Truppen OK: " + text)
	else:
		_errors += 1
		push_error("[smoke] Truppen FEHLER: " + text)


func _unit(tier: String) -> Unit:
	var u: Variant = _game.find_by_uid(int(_summoned.get(tier, 0)))
	return u if u is Unit and is_instance_valid(u) and (u as Unit).is_alive() else null


## Jeden Frame (Hauptlauf)
func tick(t: float) -> void:
	if t >= _ai_sample_at:
		_ai_sample_at = t + 60.0
		_sample_ai()
	if passive:
		return
	match _step:
		0:
			if t >= 3.0:
				_t0_setup()
				_deadline = t + 120.0
				_step = 1
		1:
			if _summoned.size() >= NEW_TIERS.size():
				_check(true, "Alle neuen Truppen beschworen (%s)" % ", ".join(_summoned.keys()))
				_t1()
				_kill_check_at = t + 1.0
				_step = 2
			elif t > _deadline:
				_check(false, "Neue Truppen erscheinen nicht (nur %s)" % str(_summoned.keys()))
				_step = 3
		2:
			if t >= _kill_check_at:
				_t2_kill()
				_step = 3
		3:
			if ui_ready and t >= 150.0 and not _hero_done:
				_hero_done = true
				_t3_hero()


# ---------------------------------------------------------------------------
# T0: Gebäude, Freischaltung, Beschwören
# ---------------------------------------------------------------------------

func _t0_setup() -> void:
	var k: Kingdom = _game.player
	var ss: SummonSystem = _game.summon_system
	for r in DataDB.resources:
		k.resources[str(r["id"])] = maxf(k.get_amount(str(r["id"])), 5000.0)
	for id in ["barracks", "forge", "library"]:
		_buildings[id] = _runner.call("_place_near_castle", DataDB.get_building(id))
		_check(_buildings[id] != null, "%s gebaut" % DataDB.get_building_name(DataDB.get_building(id), k.faction_id))
	var barracks: Building = _buildings["barracks"]
	if barracks == null:
		return
	# Ohne Forschung gesperrt
	var spear := DataDB.get_unit_for_tier(k.faction_id, "spearman")
	_check(ss.can_summon(barracks, str(spear["id"])).begins_with("Benötigt Forschung"),
			"%s ohne Forschung gesperrt (%s)" % [str(spear["name"]), ss.can_summon(barracks, str(spear["id"]))])
	_check(not BuildMenu.lock_reason(DataDB.get_building("stable"), k).is_empty(), "Reitstall ohne Forschung gesperrt")
	# Forschung wie abgeschlossen (die Forschungen, die die neuen Truppen freischalten)
	var rs: ResearchSystem = _game.research_system
	for tier in NEW_TIERS:
		var def := DataDB.get_unit_for_tier(k.faction_id, str(tier))
		var r := DataDB.find_research_unlocking(k.faction_id, "unit:" + str(def["id"]))
		_check(not r.is_empty(), "Forschung für %s: %s" % [str(def["name"]), str(r.get("name", "-"))])
		if not r.is_empty() and not k.researched.has(r["id"]):
			k.researched[r["id"]] = true
			rs.apply_effects(k, str(r["id"]))
	for id in ["stable", "mage_tower"]:
		_buildings[id] = _runner.call("_place_near_castle", DataDB.get_building(id))
		_check(_buildings[id] != null, "%s nach der Forschung gebaut" % DataDB.get_building_name(DataDB.get_building(id), k.faction_id))
	ss.unit_summoned.connect(_on_summoned)
	# Sammelpunkt abseits der Burg: die Testtruppen sollen den Heldentest (Wolf neben dem Helden) nicht stören
	var rally := _free_point_away(18)
	for id in ["barracks", "stable", "mage_tower"]:
		if _buildings.get(id) != null:
			ss.set_rally(_buildings[id], rally)
	for tier in NEW_TIERS:
		var b: Building = _buildings.get(NEW_TIERS[tier])
		var def := DataDB.get_unit_type(str(DataDB.get_unit_for_tier(k.faction_id, str(tier))["id"]))
		if b == null:
			continue
		var options: Array = ss.get_options(b)
		_check(options.has(def), "%s bietet %s an" % [b.get_display_name(), str(def["name"])])
		var reason := ss.can_summon(b, str(def["id"]))
		_check(reason.is_empty() and ss.summon(b, str(def["id"])), "%s eingereiht%s" % [str(def["name"]),
				"" if reason.is_empty() else " – " + reason])


## Begehbarer Punkt etwa tiles Felder von der Burg (erste freie Richtung)
func _free_point_away(tiles: int) -> Vector2:
	var k: Kingdom = _game.player
	var center: Vector2i = _game.world.world_to_cell(k.castle.get_center())
	for i in 16:
		var dir := Vector2.RIGHT.rotated(TAU * i / 16.0)
		var cell := center + Vector2i(roundi(dir.x * tiles), roundi(dir.y * tiles))
		if _game.world.in_bounds(cell) and not _game.nav.is_solid(cell):
			return _game.world.cell_to_world(cell)
	return k.castle.get_center()


func _on_summoned(u: Unit, _b: Building) -> void:
	if u.kingdom == _game.player and NEW_TIERS.has(u.tier) and not _summoned.has(u.tier):
		_summoned[u.tier] = u.uid
		_check(u.unit_class == str(DataDB.get_unit_type(u.type_id).get("class", "?")),
				"%s hat die Klasse %s" % [u.get_display_name(), DataDB.get_class_name(u.unit_class)])


# ---------------------------------------------------------------------------
# T1: Konter, Schmiede, Ränge, Wertepunkte, Aussehen
# ---------------------------------------------------------------------------

func _t1() -> void:
	var k: Kingdom = _game.player
	var cs: CombatSystem = _game.combat_system
	var ts: TroopSystem = _game.troop_system
	var panel: SelectionPanel = _game.hud.selection_panel
	var box: TroopSelectionBox = panel.get("_troop_box")
	var spear := _unit("spearman")
	var cav := _unit("cavalry")
	var xbow := _unit("crossbow")
	var heavy := _unit("heavy")
	var mage := _unit("battlemage")
	if spear == null or cav == null or xbow == null or heavy == null or mage == null:
		_check(false, "Neue Truppen leben nicht mehr")
		return
	# Konter: Speer gegen Reiterei (bonus_vs), Reiterei gegen Fernkämpfer (Klassen-Tabelle)
	for pair in [[spear, cav], [cav, xbow], [mage, heavy]]:
		var a: Unit = pair[0]
		var v: Unit = pair[1]
		var dmg_with := cs.estimate_damage(a, v)
		var saved := a.counter_vs
		a.counter_vs = {}
		var dmg_without := cs.estimate_damage(a, v)
		a.counter_vs = saved
		var expected := TroopRules.counter_factor(a, v)
		_check(expected > 1.0 and absf(dmg_with / maxf(dmg_without, 0.001) - expected) < 0.01,
				"Konter %s gegen %s: %.1f statt %.1f Schaden (×%.2f)" % [a.get_display_name(), v.get_display_name(),
				dmg_with, dmg_without, expected])
	# Rüstungsdurchschlag der Armbrust gegen schwere Fusstruppen
	var pierce_with := cs.estimate_damage(xbow, heavy)
	xbow.armor_pierce = 0.0
	var pierce_without := cs.estimate_damage(xbow, heavy)
	xbow.refresh_stats()
	_check(xbow.armor_pierce > 0.0 and pierce_with > pierce_without * 1.1,
			"Armbrust durchschlägt Rüstung: %.1f statt %.1f" % [pierce_with, pierce_without])

	# Schmiede über das Auswahlfenster
	var forge: Building = _buildings.get("forge")
	if forge != null:
		_game.selection.select([forge])
		panel._refresh()
		_check(box.visible and box.get_mode() == "forge", "Auswahlfenster der Schmiede zeigt die Stufen")
		var a0 := spear.attack
		var c0 := cav.attack
		_check(box.press_forge("forge_infantry_weapons"), "Schmiede: Waffen der Fusstruppen gekauft")
		var src: Dictionary = k.modifier_sources.get("upgrade:forge_infantry_weapons", {})
		_check(absf(spear.attack / a0 - 1.1) < 0.005 and is_equal_approx(cav.attack, c0) and src.has("attack#infantry"),
				"Schmiede Stufe 1: Angriff %s %.1f → %.1f, Reiter unverändert (Quelle %s)" % [spear.get_display_name(),
				a0, spear.attack, str(src)])
		_check(ts.get_forge_level(k, "forge_infantry_weapons") == 1, "Schmiede-Stufe gemerkt")
		_check(_stat_line_has(panel, spear, "Schmiede"), "Werteherkunft nennt die Schmiede")
		_game.selection.clear()

	# Erfahrung -> Rang -> Wertepunkt
	_check(not k.auto_stat_points, "Spieler verteilt Wertepunkte nicht automatisch (Standard)")
	ts.debug_add_xp(spear, 70.0)
	_check(spear.vet_rank == 1 and spear.stat_points == 1, "70 EP: %s ist %s mit %d Wertepunkt" % [spear.get_display_name(),
			TroopRules.rank_name(spear.vet_rank), spear.stat_points])
	var before := spear.attack
	_check(ts.spend_point(spear, "attack") and absf(spear.attack / before - 1.06) < 0.005 and spear.stat_points == 0,
			"Wertepunkt Angriff: %.1f → %.1f" % [before, spear.attack])
	_check(not ts.spend_point(spear, "attack"), "Ohne freie Punkte kein weiterer Punkt")
	# Über das Auswahlfenster
	ts.debug_add_xp(spear, 120.0)
	_game.selection.select([spear])
	panel._refresh()
	_check(box.visible and box.get_mode() == "unit", "Auswahlfenster zeigt Rang und Wertepunkte")
	var hp0 := spear.max_hp
	_check(spear.vet_rank == 2 and box.press_stat("hp") and spear.max_hp > hp0 * 1.07,
			"Rang %s, Wertepunkt Leben über das Auswahlfenster: %.0f → %.0f" % [TroopRules.rank_name(spear.vet_rank), hp0, spear.max_hp])

	# Kampf-Erfahrung aus Treffern
	var wolf: Unit = _game.unit_system.spawn_unit(_game.wild, "wolf", cav.position + Vector2(160, 0))
	if wolf != null:
		var xp0 := cav.vet_xp
		cs.apply_damage(wolf, 20.0, cav, k, "melee")
		_check(cav.vet_xp > xp0 + 4.0 and wolf.last_hit_by == cav.uid, "Treffer gibt Erfahrung: %.1f → %.1f EP" % [xp0, cav.vet_xp])
		_kill_attacker = cav.uid
		cs.apply_damage(wolf, 1000.0, cav, k, "melee")
		_kill_xp_before = cav.vet_xp

	# Mehrfachauswahl: automatisch verteilen
	ts.debug_add_xp(xbow, 70.0)
	ts.debug_add_xp(heavy, 70.0)
	_game.selection.select([xbow, heavy])
	panel._refresh()
	_check(box.visible and box.get_mode() == "units", "Mehrfachauswahl zeigt freie Wertepunkte")
	var spent := box.press_auto()
	_check(spent == 2 and xbow.stat_points == 0 and heavy.stat_points == 0 and int(heavy.stat_alloc.get("hp", 0)) == 1,
			"Punkte automatisch verteilen: %d (schwere Fusstruppe: %s)" % [spent, str(heavy.stat_alloc)])
	_game.selection.clear()

	# KI verteilt selbst
	for ai in _game.kingdoms:
		if ai.controller == "ai" and not ai.defeated and is_instance_valid(ai.castle):
			var fdef := DataDB.get_unit_for_tier(ai.faction_id, "fighter")
			var au: Unit = _game.unit_system.spawn_unit(ai, str(fdef["id"]), ai.castle.get_approach_point(ai.castle.get_center() + Vector2(0, 500)))
			if au != null:
				ts.debug_add_xp(au, 70.0)
				_check(ai.auto_stat_points and au.stat_points == 0 and TroopRules.spent_points(au.stat_alloc) == 1,
						"KI-Reich verteilt Wertepunkte selbst (%s)" % str(au.stat_alloc))
				_game.unit_system.remove_unit(au)
			break

	# Aussehen je Typ (Auswahlfenster) und je Einheit
	var skins := TroopRules.skins_for(k, spear.type_def)
	_check(skins.size() >= 3 and skins[0] == "standard", "%s hat %d Aussehen: %s" % [spear.get_display_name(), skins.size(), str(skins)])
	if skins.size() >= 2:
		_game.selection.select([spear])
		panel._refresh()
		var sid := str(skins[1])
		_check(box.select_type_skin(sid) and str(k.unit_skins.get(spear.type_id, "")) == sid and spear.get_skin() == sid
				and spear.get("_emblem") != null, "Aussehen aller %s: %s" % [spear.get_display_name(), TroopRules.skin_name(sid)])
		_expect["type"] = [spear.type_id, sid]
		_game.selection.clear()
	# Gezeichnete Figuren: zwei Aussehen derselben Truppe und das Standard-Aussehen ergeben verschiedene Bilder
	if skins.size() >= 3:
		var looks: Array = []
		for skin_id in [skins[0], skins[1], skins[2]]:
			var sd := {} if str(skin_id) == "standard" else TroopRules.skin_def(str(skin_id))
			looks.append(Assets.figure(FigureArt.spec_for(spear.type_def, k.faction_id, k.color, sd)).get_image().get_data())
		_check(looks[0] != looks[1] and looks[1] != looks[2] and looks[0] != looks[2],
				"Figuren: %s, %s und %s sehen verschieden aus" % [TroopRules.skin_name(str(skins[0])),
				TroopRules.skin_name(str(skins[1])), TroopRules.skin_name(str(skins[2]))])
	var bare := 0
	for u in _game.unit_system.units:
		if u.get("_figure") == null and u.get("_texture") == null:
			bare += 1
	_check(bare == 0, "Figuren: alle %d Einheiten haben eine Figur oder Grafik (%d Figurenbilder)" % [
			_game.unit_system.units.size(), Assets.figure_count()])
	_check(not ts.set_unit_skin(xbow, "hero_banner"), "Heldenbanner vor dem Rang Elite gesperrt")
	ts.debug_add_xp(xbow, 400.0)
	ts.auto_distribute(xbow)
	_game.selection.select([xbow])
	panel._refresh()
	_check(xbow.vet_rank >= 3 and box.select_unit_skin("hero_banner") and xbow.get_skin() == "hero_banner",
			"Heldenbanner für %s (Rang %s)" % [xbow.get_display_name(), TroopRules.rank_name(xbow.vet_rank)])
	_game.selection.clear()
	var d := xbow.to_dict()
	_check(str(d.get("skin", "")) == "hero_banner" and int(d.get("vet_rank", 0)) == xbow.vet_rank
			and (d.get("stat_alloc", {}) as Dictionary) == xbow.stat_alloc, "Spielstand-Eintrag der Einheit enthält Aussehen, Rang und Punkte")
	_expect["unit"] = {"uid": xbow.uid, "skin": "hero_banner", "rank": xbow.vet_rank, "alloc": xbow.stat_alloc.duplicate(),
			"xp": xbow.vet_xp}
	_expect["forge"] = ts.get_forge_level(k, "forge_infantry_weapons")
	# Die Testtruppen halten ihren Platz an der Burg (bis zum Speichern)
	_game.command_system.order_stop([spear, cav, xbow, heavy, mage])


## Werteherkunft (Tooltip der Kampfwerte) nennt eine Quelle
func _stat_line_has(panel: SelectionPanel, u: Unit, text: String) -> bool:
	return panel._stat_source_line(u, "attack", "Angriff", u.attack, false).contains(text)


# ---------------------------------------------------------------------------
# T2: Erfahrung für den Sieg
# ---------------------------------------------------------------------------

func _t2_kill() -> void:
	if _kill_attacker == 0:
		return
	var a: Variant = _game.find_by_uid(_kill_attacker)
	if not (a is Unit):
		_check(false, "Angreifer für den Sieg fehlt")
		return
	var gain := (a as Unit).vet_xp - _kill_xp_before
	_check(gain >= float(DataDB.trp("veterancy.kill_xp", 8)) - 0.01, "Sieg gibt Erfahrung (+%.1f EP)" % gain)


# ---------------------------------------------------------------------------
# T3: Helden-Wertepunkte
# ---------------------------------------------------------------------------

func _t3_hero() -> void:
	var k: Kingdom = _game.player
	var hs: HeroSystem = _game.hero_system
	var ts: TroopSystem = _game.troop_system
	if k.heroes.is_empty():
		print("[smoke] Truppen: kein Held für den Wertepunkte-Test")
		return
	var rec: Dictionary = k.heroes[0]
	var u := hs.get_unit(k, int(rec["id"]))
	if u == null:
		print("[smoke] Truppen: Held gerade nicht auf dem Feld")
		return
	var free := ts.get_free_points(u)
	_check(free == ts.hero_points_total(rec) - TroopRules.spent_points(rec.get("stat_alloc", {})) and free > 0,
			"Held %s Stufe %d hat %d Wertepunkte" % [str(rec["name"]), int(rec["level"]), free])
	var panel: SelectionPanel = _game.hud.selection_panel
	var box: TroopSelectionBox = panel.get("_troop_box")
	_game.selection.select([u])
	panel._refresh()
	var a0 := u.attack
	_check(box.get_mode() == "unit" and box.press_stat("attack") and u.attack > a0 * 1.05
			and int((rec.get("stat_alloc", {}) as Dictionary).get("attack", 0)) >= 1,
			"Held: Wertepunkt Angriff über das Auswahlfenster %.1f → %.1f" % [a0, u.attack])
	_expect["hero"] = {"id": int(rec["id"]), "alloc": (rec["stat_alloc"] as Dictionary).duplicate()}
	_game.selection.clear()


# ---------------------------------------------------------------------------
# Nach dem Laden (Phase-10-Rundlauf)
# ---------------------------------------------------------------------------

## Jeden Frame des Rundlaufs; prüft einmal, sobald der geladene Stand weiterläuft
func tick_after_load(game: Node, state: String) -> void:
	if _post_done or game == null or not is_instance_valid(game) or state != "continue":
		return
	_post_done = true
	_game = game
	var k: Kingdom = game.player
	var ts: TroopSystem = game.troop_system
	if _expect.has("type"):
		var pair: Array = _expect["type"]
		_check(str(k.unit_skins.get(str(pair[0]), "")) == str(pair[1]), "Nach dem Laden: Aussehen des Typs %s" % str(pair[1]))
		for u in k.units:
			if u.type_id == str(pair[0]) and u.skin.is_empty():
				_check(u.get_skin() == str(pair[1]) and u.get("_emblem") != null, "Nach dem Laden: Einheit trägt das Aussehen des Typs")
				break
	if _expect.has("forge"):
		_check(ts.get_forge_level(k, "forge_infantry_weapons") == int(_expect["forge"])
				and (k.modifier_sources.get("upgrade:forge_infantry_weapons", {}) as Dictionary).has("attack#infantry"),
				"Nach dem Laden: Schmiede-Stufe und Wirkung")
	if _expect.has("unit"):
		var e: Dictionary = _expect["unit"]
		var u: Variant = game.find_by_uid(int(e["uid"]))
		# Gespeicherter Eintrag der Einheit (Rundlauf mit debug_verify_load): Rang und Punkte können
		# sich bis zum Speichern durch Kämpfe noch erhöht haben – verglichen wird mit dem Spielstand
		var saved := {}
		for ud in (game.get("last_loaded_data") as Dictionary).get("units", []):
			if int((ud as Dictionary).get("uid", 0)) == int(e["uid"]):
				saved = ud
		if u is Unit and not saved.is_empty():
			var uu: Unit = u
			_check(uu.skin == str(e["skin"]) and str(saved.get("skin", "")) == str(e["skin"]) and uu.get_skin() == str(e["skin"])
					and uu.vet_rank == int(saved.get("vet_rank", -1)) and uu.vet_rank >= int(e["rank"])
					and uu.stat_alloc == (saved.get("stat_alloc", {}) as Dictionary)
					and absf(uu.vet_xp - float(saved.get("vet_xp", -1.0))) < 0.01 and uu.get("_emblem") != null,
					"Nach dem Laden: Einheit mit Aussehen %s, Rang %s, Punkten %s" % [uu.skin, TroopRules.rank_name(uu.vet_rank),
					str(uu.stat_alloc)])
		else:
			print("[smoke] Truppen: Testeinheit ist vor dem Speichern gefallen – nur Reichswerte geprüft")
	if _expect.has("hero"):
		var h: Dictionary = _expect["hero"]
		var rec: Dictionary = game.hero_system.get_record(k, int(h["id"]))
		if not rec.is_empty():
			_check((rec.get("stat_alloc", {}) as Dictionary) == (h["alloc"] as Dictionary), "Nach dem Laden: Wertepunkte des Helden")
			var hu: Unit = game.hero_system.get_unit(k, int(h["id"]))
			if hu != null:
				_check(hu.stat_alloc == (h["alloc"] as Dictionary) and not hu.vet_mods.is_empty(), "Nach dem Laden: Held hat seine Punkte")
	print("[smoke] Truppen nach dem Laden: %s" % ("OK" if _errors == 0 else "%d Fehler" % _errors))


func report() -> void:
	if not passive:
		print("[smoke] Truppen: %s (%d neue Truppen beschworen)" % ["OK" if _errors == 0 else "%d Fehler" % _errors, _summoned.size()])
	# Zur Information: was die KI-Reiche von den neuen Truppen nutzen (höchste Zahl je Stufe, Ränge, Schmiede)
	_sample_ai()
	for k in _game.kingdoms:
		if k.controller == "ai":
			print("[smoke] Truppen KI %s: höchstens gesehen %s, Schmiede %s" % [k.display_name,
					str(_ai_seen.get(k.display_name, {})), str(k.forge_levels)])


## KI-Reiche zählen (neue Truppenstufen und Einheiten mit Rang)
func _sample_ai() -> void:
	for k in _game.kingdoms:
		if k.controller != "ai" or k.defeated:
			continue
		var counts := {}
		for u in k.units:
			if NEW_TIERS.has(u.tier):
				counts[u.tier] = int(counts.get(u.tier, 0)) + 1
			if u.vet_rank > 0:
				counts["rank"] = int(counts.get("rank", 0)) + 1
		for b in k.buildings:
			var bid := str(b.def.get("id", ""))
			if bid == "forge" or bid == "stable" or bid == "mage_tower":
				counts[bid] = int(counts.get(bid, 0)) + 1
		for rid in ["good_knights", "evil_dread", "good_blessing", "evil_curse"]:
			if k.researched.has(rid):
				counts[rid] = 1
		var seen: Dictionary = _ai_seen.get(k.display_name, {})
		for key in counts:
			seen[key] = maxi(int(seen.get(key, 0)), int(counts[key]))
		_ai_seen[k.display_name] = seen
