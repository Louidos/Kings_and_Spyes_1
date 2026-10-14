## Rauchtest Phase 7 (gestartet von tests/smoke_test.gd): gegnerische Königreiche.
## Prüft über die öffentlichen Schnittstellen: Gründung (Burg, König, Bewohner, Gebiet,
## Krieg mit dem Spieler, Schwierigkeit), Wirtschaft der KI (baut, verteilt Berufe,
## denkt gestaffelt), Debug-Verstärkung mit schnellem Denken (Truppen, Forschung,
## Helden), eine erzwungene Angriffswelle bis zur Burg des Spielers, Rivalität (mit
## ai=2), zum Schluss die Niederlage aller KI-Reiche (Ruinen, Gebiet weg) und den
## Siegbildschirm mit "Weiterspielen". Dazu alle 300 s eine Zeile je KI-Reich.
## Spionage (EspionageSystem, SpySystem): Entdeckungswert wächst mit Gebäuden und
## Aggression, sinkt mit Reichstarnung (die bei Manamangel endet), Aufmerksamkeit der KI
## steigt (auch durch Boten), Spieler-Spione kundschaften aus (Kundschaft >= 2) und
## hetzen ein Dorf auf (Ruf sinkt), ein KI-Spion kommt zum Spieler und wird entdeckt.
## Oberfläche: Spion A bekommt seinen Auftrag über das Spionagefenster (EspionagePanel);
## ab t = 240 werden dessen Reiter, der Reiter "Reiche" im Diplomatiefenster, der
## gegenseitige Ausschluss der Fenster, Esc, der Meldungsverweis und das Auswahlfenster
## an der KI-Burg geprüft (Bildschirmfotos mit shots=<ordner> unter xvfb-run).
##
## Argumente: p7=natural (keine Debug-Stufen: lange Simulation mit echter KI),
## ai=<n> (feste Anzahl KI-Reiche, siehe smoke_test.gd).
## Fehler erscheinen als "ERROR: [smoke] Phase 7 FEHLER: …" (push_error).
extends RefCounted

## Zeitleiste: alle so viele Spielsekunden eine Zeile je KI-Reich
const SAMPLE_INTERVAL := 300.0

var _game: Node
var _natural := false
## Der Spieler tut nichts (passive=1): seine Niederlage ist dann ein Ergebnis, kein Fehler
var _passive := false
var _seconds := 600.0
var _stage := 0
var _errors := 0
var _ai: Array = []
var _ai0: Kingdom = null
## Reich-id -> Gebäude beim Start / Burgzelle
var _start_buildings: Dictionary = {}
var _castle_cells: Dictionary = {}
var _attack_seen := false
var _near_seen := false
var _rival_test := false
var _player_alive_1800 := true
var _next_sample := SAMPLE_INTERVAL
var _done := false
## Spionage: Spieler-Spione (uids), Dorf für das Aufhetzen, Werte vor den Tests
var _spy_a := 0
var _spy_b := 0
var _incite_village: Kingdom = null
var _disc_before := {}
## Spionage mit KI-Spion: -1 = noch nicht, 0 = warten, 1 = KI-Spion unterwegs, 2 = Entdeckung läuft, 3 = fertig
var _esp_stage := -1
var _esp_deadline := 0.0
var _ai_spy_uid := 0
var _detected_seen := false
var _cloak_test := false
## Gemeldete Einheiten der Welle (enemy_spotted): [nahe der Grenze, im Gebiet] (Höchstwerte)
var _spotted: Array = [0, 0]
## Spielzeit für die zweite Prüfung des Aufhetzens (-1 = keine)
var _incite_due := -1.0
## Oberflächentest (Spionagefenster, Reiter "Reiche"): Schritt (-1 = aus) und Wartezeit
var _ui_step := -1
var _ui_wait := 0.0
var _shots_dir := ""


func _init(game: Node, args: Dictionary) -> void:
	_game = game
	_natural = str(args.get("p7", "")) == "natural"
	_passive = str(args.get("passive", "0")) == "1"
	_seconds = float(args.get("seconds", "600"))
	_shots_dir = str(args.get("shots", ""))


## Jeden Frame aufrufen (Spielzeit t)
func tick(t: float) -> void:
	if _done:
		return
	var g := _game
	var player: Kingdom = g.player
	if player.defeated:
		# Der Niederlage-Bildschirm hält die Zeit an: Bericht und Ende
		var text := "Der Spieler hat verloren (t = %.0f s, %s)" % [t, str(player.flags.get("defeat_reason", "?"))]
		if _passive:
			print("[smoke] Phase 7: %s – passiver Spieler" % text)
			_check(t >= float(g.ai_system.get_difficulty().get("first_attack_minutes", 45)) * 60.0,
					"Passiver Spieler fällt nicht vor der ersten Angriffszeit")
		else:
			_check(false, text)
		_done = true
		_sample(t)
		report()
		g.get_tree().quit(1 if _errors > 0 else 0)
		return
	if t >= _next_sample:
		_next_sample += SAMPLE_INTERVAL
		_sample(t)
	if t >= 1800.0 and t < 1810.0:
		_player_alive_1800 = is_instance_valid(player.castle) and is_instance_valid(player.king)
	if _stage >= 3 and _stage < 7 and not _natural:
		_esp_tick(t)
	if _ui_step >= 0 and t >= _ui_wait:
		_ui_tick(t)
	match _stage:
		0:
			if t >= 1.0:
				_stage = 1 if _s0() else 99
		1:
			if t >= 90.0:
				_s1()
				_stage = 2
		2:
			if _natural:
				_stage = 6
			elif t >= 100.0:
				_s2()
				_stage = 3
		3:
			if t >= 220.0:
				_s3()
				_stage = 4
		4:
			if t >= 320.0:
				_s4()
				_stage = 5
		5:
			if t >= 520.0 or _attack_seen:
				if _s5(t):
					_stage = 6
		6:
			if t >= _seconds - 45.0:
				_s_growth()
				_stage = 7
		7:
			if t >= _seconds - 40.0:
				_s6()
				_stage = 8
		8:
			# Der Siegbildschirm hält die Spielzeit an: nicht auf die Zeit warten
			if _game.is_victory_shown() or t >= _seconds - 35.0:
				_s7()
				_stage = 9


func _check(cond: bool, text: String) -> void:
	if cond:
		print("[smoke] Phase 7 OK: " + text)
	else:
		_errors += 1
		push_error("[smoke] Phase 7 FEHLER: " + text)


# ---------------------------------------------------------------------------
# Stufen
# ---------------------------------------------------------------------------

## S0: KI-Reiche gegründet (Burg, König, Bewohner, Krieg, Schwierigkeit, Gebiet, Volk)
func _s0() -> bool:
	var g := _game
	var ai: AISystem = g.ai_system
	var player: Kingdom = g.player
	_ai = ai.get_ai_kingdoms()
	var forced := GameSession.ai_count_override
	if forced >= 0:
		_check(_ai.size() == mini(forced, g.world.get_sites("kingdom").size()), "%d KI-Reiche (ai=%d)" % [_ai.size(), forced])
	else:
		_check(_ai.size() >= 1, "%d KI-Reich(e) gegründet" % _ai.size())
	if _ai.is_empty():
		return false
	_ai0 = _ai[0]
	var enemy := AISystem.enemy_faction(player.faction_id)
	for k in _ai:
		var castle_ok: bool = is_instance_valid(k.castle) and is_instance_valid(k.king) and k.king.is_alive()
		var cell: Vector2i = g.world.world_to_cell(k.castle.get_center()) if is_instance_valid(k.castle) else Vector2i(-1, -1)
		_castle_cells[k.id] = cell
		_check(castle_ok and k.units.size() >= 5, "%s: Burg, König, %d Einheiten" % [k.display_name, k.units.size()])
		_check(g.are_hostile(player, k) and k.modifier_sources.has("difficulty"), "%s: Krieg mit dem Spieler, Quelle „Schwierigkeit“" % k.display_name)
		_check(g.world.get_owner(cell) == k.id, "%s: Gebiet um die Burg" % k.display_name)
		_check(not k.people_id.is_empty() and k.faction_id == enemy, "%s: Volk %s, Fraktion %s" % [k.display_name, k.people_id, k.faction_id])
		print("[smoke] KI-Reich %d %s (%s, %s) bei %s" % [k.id, k.display_name, k.people_id,
				str(k.ai_state.get("personality", "?")), str(cell)])
		_start_buildings[k.id] = k.buildings.size()
	_check(DataDB.ai("waves.gather_seconds") == 60.0 and DataDB.describe_effect_source("difficulty") == "Schwierigkeit",
			"DataDB.ai und Quelle „Schwierigkeit“")
	return true


## S1: die KI baut, verteilt Berufe und denkt
func _s1() -> void:
	var g := _game
	for k in _ai:
		var working := 0
		for u in k.units:
			if u.role == "worker" and u.job_id != "idle":
				working += 1
		var sites: int = g.building_system.get_building_sites(k).size()
		_check(k.buildings.size() > int(_start_buildings.get(k.id, 0)), "%s baut (%d Gebäude, davon %d Baustellen)" % [
				k.display_name, k.buildings.size(), sites])
		_check(working >= 3, "%s: %d Bewohner mit Beruf" % [k.display_name, working])
		_check(int(k.ai_state.get("think_count", 0)) >= 10, "%s denkt (%d Denkvorgänge)" % [k.display_name,
				int(k.ai_state.get("think_count", 0))])
	var esp: EspionageSystem = g.espionage_system
	var player: Kingdom = g.player
	_check(esp.get_discovery(player) > 0.0 and esp.get_discovery_parts(player).has("buildings"),
			"Entdeckungswert des Spielers %.1f (%s)" % [esp.get_discovery(player), _parts_text(esp.get_discovery_parts(player))])
	_check(esp.get_awareness(_ai0, player) > 0.5, "Aufmerksamkeit von %s auf den Spieler steigt (%.1f, Ziel aus Entdeckung × Nähe %.2f)" % [
			_ai0.display_name, esp.get_awareness(_ai0, player), esp.get_proximity(_ai0, player)])


## S2: erstes KI-Reich verstärken, schnelles Denken (keine Zeitsperren)
func _s2() -> void:
	var ai: AISystem = _game.ai_system
	ai.debug_boost(_ai0)
	ai.debug_fast = true
	_check(_game.hero_system.get_hall(_ai0) != null or _game.building_system.count_buildings(_ai0, "hero_hall", true) > 0,
			"%s: Heldenhalle nach der Verstärkung" % _ai0.display_name)
	_esp_setup()


## Spionage-Aufbau (S2): Bote, Aggression, Gebäude, Reichstarnung, zwei Spieler-Spione
func _esp_setup() -> void:
	var g := _game
	var esp: EspionageSystem = g.espionage_system
	var spies: SpySystem = g.spy_system
	var ds: DiplomacySystem = g.diplomacy_system
	var vs: VillageSystem = g.village_system
	var player: Kingdom = g.player
	# Bote: die KI erfährt von einem Angriff des Spielers
	var villages := vs.get_villages()
	var aw0 := esp.get_awareness(_ai0, player)
	if not villages.is_empty():
		ds.report_aggression(_ai0, player, villages[0])
		_check(esp.get_awareness(_ai0, player) >= minf(aw0 + 24.0, 100.0) and esp.get_intel_level(_ai0, player) >= 1,
				"Bote erhöht die Aufmerksamkeit von %s (%.1f → %.1f, Kundschaft %d)" % [_ai0.display_name, aw0,
				esp.get_awareness(_ai0, player), esp.get_intel_level(_ai0, player)])
	# Entdeckungswert: Aggression und ein neues Gebäude
	_disc_before = esp.get_discovery_parts(player).duplicate()
	esp.note_aggression(player, 20.0, "smoke")
	var lib := _place_near(player, DataDB.get_building("library"))
	_check(lib != null, "Bibliothek des Spielers für den Entdeckungstest")
	# Reichstarnung: Forschung, Mana, einschalten
	var cloak_research := "good_realm_veil" if player.faction_id == "good" else "evil_realm_shroud"
	player.researched[cloak_research] = true
	g.research_system.apply_effects(player, cloak_research)
	player.resources["mana"] = maxf(player.get_amount("mana"), 400.0)
	var reason := esp.toggle_cloak(player)
	var spell := esp.get_cloak_spell(player)
	_cloak_test = reason.is_empty() and esp.is_cloaked(player)
	_check(_cloak_test and player.get_upkeep("mana") > 0.0 and not g.magic_system.can_cast_now(player, spell).is_empty(),
			"Reichstarnung eingeschaltet (%s, %.2f Mana/s) %s" % [spell, player.get_upkeep("mana"), reason])
	# Zwei Spione: Auskundschaften (KI-Reich) und Dorf aufhetzen (Dorf nahe der KI gegen sie)
	var scouting := "good_scouting" if player.faction_id == "good" else "evil_informants"
	player.researched[scouting] = true
	g.research_system.apply_effects(player, scouting)
	var spy_id := str(SpySystem.spy_type(player.faction_id).get("id", ""))
	var a: Unit = g.summon_system.spawn_summoned(player.castle, spy_id)
	var b: Unit = g.summon_system.spawn_summoned(player.castle, spy_id)
	_check(a != null and b != null and spies.get_spies(player).size() >= 2 and a.stealthed and spies.get_level(a) == 1,
			"Zwei Spione des Spielers (getarnt, Stufe 1, %s)" % (a.get_display_name() if a != null else "-"))
	if a == null or b == null:
		return
	_spy_a = a.uid
	_spy_b = b.uid
	# Spion A über das Spionagefenster (geschlossen: dieselben Funktionen wie die Knöpfe)
	var panel: EspionagePanel = g.hud.espionage_panel
	panel.select_spy(a.uid)
	panel.set_mission_choice("scout", _ai0.id)
	var answer := panel.assign_selected()
	_check(answer.is_empty() and a.command == "infiltrate", "Spion A (Spionagefenster): Auskundschaften von %s %s" % [
			_ai0.display_name, answer])
	var castle_pos := _ai0.castle.get_center()
	var best_d := INF
	for v in villages:
		var d := castle_pos.distance_to(vs.get_center(v))
		if d < best_d:
			best_d = d
			_incite_village = v
	if _incite_village != null:
		answer = spies.assign_mission(b, "incite_village", _incite_village, _ai0)
		_check(answer.is_empty(), "Spion B: %s gegen %s aufhetzen %s" % [_incite_village.display_name, _ai0.display_name, answer])
	_check(not spies.can_assign(a, "scout", player).is_empty(), "Eigenes Reich ist kein Spionageziel")


## S3: die verstärkte KI hat Truppen beschworen; Spionage-Ergebnisse der Spieler-Spione
func _s3() -> void:
	var brain: AIBrain = _game.ai_system.get_brain(_ai0)
	var army := brain.army_units().size() if brain != null else 0
	_check(army >= 2, "%s hat %d Kampfeinheiten (Soll %d)" % [_ai0.display_name, army,
			AIMilitary.army_target(brain, GameClock.game_time) if brain != null else 0])
	_esp_results()


## Spionage-Ergebnisse (S3): Entdeckungswert, Tarnung, Kundschaft, Aufhetzen; danach
## Gerüchte bei der KI (sie schickt einen Spion) und Manamangel für die Tarnung
func _esp_results() -> void:
	var g := _game
	var esp: EspionageSystem = g.espionage_system
	var spies: SpySystem = g.spy_system
	var player: Kingdom = g.player
	var parts := esp.get_discovery_parts(player)
	_check(float(parts.get("aggression", 0.0)) >= 15.0, "Aggression im Entdeckungswert (%.1f)" % float(parts.get("aggression", 0.0)))
	_check(float(parts.get("buildings", 0.0)) >= float(_disc_before.get("buildings", 0.0)) + 1.9,
			"Gebäude im Entdeckungswert (%.1f → %.1f)" % [float(_disc_before.get("buildings", 0.0)), float(parts.get("buildings", 0.0))])
	if _cloak_test:
		_check(esp.is_cloaked(player) and float(parts.get("cloak", 0.0)) < 0.0 and esp.get_discovery(player) < esp.get_discovery_raw(player),
				"Reichstarnung senkt den Entdeckungswert (%.1f statt %.1f)" % [esp.get_discovery(player), esp.get_discovery_raw(player)])
		# Manamangel: die Tarnung endet von selbst
		player.resources["mana"] = 0.0
	var a: Variant = g.find_by_uid(_spy_a)
	if a is Unit:
		var rec := spies.get_record(a)
		var level := esp.get_intel_level(player, _ai0)
		if level >= 2:
			_check(true, "Spion A: Kundschaft über %s Stufe %d (%s, %s)" % [_ai0.display_name, level, str(rec["state"]),
					esp.get_intel_text(player, _ai0)])
			print("[smoke] Kundschaft: %s" % esp.get_kingdom_summary(_ai0, player).replace("\n", " | "))
		elif str(rec["state"]) == "travel" or bool(rec.get("revealed", false)):
			print("[smoke] Hinweis: Spion A %s (%.0f Kacheln vor dem Ziel), Kundschaft %d" % [str(rec["state"]),
					(a as Unit).position.distance_to(_ai0.castle.get_center()) / float(g.world.tile_size), level])
		else:
			_check(false, "Spion A ohne Kundschaft (Zustand %s, Kundschaft %d)" % [str(rec["state"]), level])
	else:
		print("[smoke] Hinweis: Spion A ist nicht mehr da (entdeckt und getötet?)")
	_incite_check(false)
	g.espionage_system.debug_set_awareness(_ai0, player, 45.0)
	_esp_stage = 0
	_esp_deadline = GameClock.game_time + 200.0
	_ui_step = 0
	_ui_wait = 240.0


## Aufhetzen (Spion B): Verlauf des Dorfs zeigt "Aufwiegelung" mit sinkendem Ruf.
## final = false: noch nicht aufgehetzt, aber unterwegs/gerade angekommen -> später prüfen
func _incite_check(final: bool) -> void:
	if _incite_village == null:
		return
	var g := _game
	var ds: DiplomacySystem = g.diplomacy_system
	var spies: SpySystem = g.spy_system
	var found := false
	for e in ds.get_history(_incite_village, _ai0):
		if str(e.get("reason", "")) == "Aufwiegelung" and float(e.get("delta", 0.0)) < 0.0:
			found = true
	var b: Variant = g.find_by_uid(_spy_b)
	var rec: Dictionary = spies.get_record(b) if b is Unit else {}
	var state := str(rec.get("state", "tot"))
	var waiting := not found and (state == "travel" or (state == "active"
			and GameClock.game_time - float(rec.get("active_since", 0.0)) < float(DataDB.esp("spies.incite_interval", 30)) + 5.0))
	if waiting and not final:
		_incite_due = GameClock.game_time + 60.0
		print("[smoke] Hinweis: Spion B %s, Aufhetzen wird später geprüft" % state)
		return
	_incite_due = -1.0
	if found or state == "active" or state == "idle":
		_check(found, "Aufwiegelung senkt den Ruf von %s bei %s (%+.0f, Spion B %s, Stufe %d)" % [_ai0.display_name,
				_incite_village.display_name, ds.get_reputation(_incite_village, _ai0), state, int(rec.get("level", 0))])
	else:
		print("[smoke] Hinweis: Spion B %s, kein Aufhetzen geprüft" % state)


## KI-Spion beim Spieler (läuft neben den Stufen S3–S6): er wird angeworben, kommt
## in die Nähe der Spielerburg und wird mit vielen Spähern und hoher Wachsamkeit entdeckt
func _esp_tick(t: float) -> void:
	var g := _game
	var spies: SpySystem = g.spy_system
	var esp: EspionageSystem = g.espionage_system
	var player: Kingdom = g.player
	if _incite_due >= 0.0 and t >= _incite_due:
		_incite_check(true)
	if _cloak_test and t >= 300.0:
		_cloak_test = false
		_check(not esp.is_cloaked(player) and player.get_upkeep("mana") == 0.0, "Reichstarnung endet bei Manamangel")
	match _esp_stage:
		0:
			for u in spies.get_spies(_ai0):
				var rec := spies.get_record(u)
				if str(rec["mission"]) == "scout" and int(rec["target_id"]) == player.id:
					_ai_spy_uid = u.uid
					_check(true, "%s schickt einen Spion zum Spieler (%s, Zustand %s)" % [_ai0.display_name,
							u.get_display_name(), str(rec["state"])])
					_esp_stage = 1
					_esp_deadline = t + 240.0
					return
			if t >= _esp_deadline:
				_check(false, "%s schickt keinen Spion (Spione %d, Grund %s)" % [_ai0.display_name,
						spies.get_spies(_ai0).size(), spies.can_recruit(_ai0)])
				_esp_stage = 3
		1:
			var u: Variant = g.find_by_uid(_ai_spy_uid)
			if not (u is Unit):
				print("[smoke] Hinweis: KI-Spion verschwunden")
				_esp_stage = 3
				return
			var spy: Unit = u
			var tiles := spy.position.distance_to(player.castle.get_center()) / float(g.world.tile_size)
			if tiles <= 20.0 or str(spies.get_record(spy)["state"]) == "active":
				_check(not g.can_see(player, spy), "KI-Spion %.0f Kacheln vor der Spielerburg, unsichtbar für den Spieler" % tiles)
				# Viel Wachsamkeit: zwei Späher daneben, Bonus
				var scout_id := str(DataDB.get_unit_for_tier(player.faction_id, "scout").get("id", ""))
				for i in 2:
					g.unit_system.spawn_unit(player, scout_id, spy.position + Vector2(40 + 30 * i, 20))
				player.set_bonus("smoke", "vigilance", 50.0)
				spies.spy_detected.connect(func(s: Unit, _o: Kingdom, obs: Kingdom) -> void:
					if s.uid == _ai_spy_uid and obs == player:
						_detected_seen = true)
				_esp_stage = 2
				_esp_deadline = t + 80.0
			elif t >= _esp_deadline:
				print("[smoke] Hinweis: KI-Spion noch %.0f Kacheln entfernt (%s)" % [tiles, str(spies.get_record(spy)["state"])])
				_esp_stage = 3
		2:
			if _detected_seen:
				var u: Variant = g.find_by_uid(_ai_spy_uid)
				var visible: bool = u is Unit and g.can_see(player, u)
				_check(esp.get_intel_level(player, _ai0) >= 1 and int(spies.stats["detected"]) >= 1 and (visible or not (u is Unit)),
						"KI-Spion entdeckt: sichtbar %s, Kundschaft %d, Aufmerksamkeit des Spielers auf %s %.0f" % [str(visible),
						esp.get_intel_level(player, _ai0), _ai0.display_name, esp.get_awareness(player, _ai0)])
				player.clear_bonuses("smoke")
				_esp_stage = 3
			elif t >= _esp_deadline:
				_check(false, "KI-Spion nicht entdeckt (Chance %.0f %%)" % (spies.detection_chance(g.find_by_uid(_ai_spy_uid)) * 100.0
						if g.find_by_uid(_ai_spy_uid) is Unit else 0.0))
				player.clear_bonuses("smoke")
				_esp_stage = 3


## Oberflächentest: Spionagefenster (Reiter), Diplomatie "Reiche", Ausschluss, Esc,
## Meldungsverweis, Auswahlfenster an der KI-Burg
func _ui_tick(t: float) -> void:
	var g := _game
	var hud: Node = g.hud
	var panel: EspionagePanel = hud.espionage_panel
	var player: Kingdom = g.player
	_ui_wait = t + 0.5
	match _ui_step:
		0:
			hud.close_top_panel()
			hud.open_espionage(EspionagePanel.TAB_OVERVIEW)
			_check(hud.is_espionage_open() and panel.get_tab() == EspionagePanel.TAB_OVERVIEW and not hud.is_research_open()
					and not hud.is_heroes_open() and not hud.is_diplomacy_open(), "Spionagefenster offen (Übersicht)")
			_check(not EspionagePanel.causes_text(g.espionage_system.get_discovery_parts(player)).is_empty(),
					"Ursachen des Entdeckungswerts: %s" % EspionagePanel.causes_text(g.espionage_system.get_discovery_parts(player)).replace("\n", ", "))
		1:
			_shot("phase7_1_spionage")
			hud.open_espionage(EspionagePanel.TAB_REALMS, _ai0.id)
			_check(panel.get_tab() == EspionagePanel.TAB_REALMS, "Spionagefenster: Reiter Reiche & Dörfer")
		2:
			_shot("phase7_2_reiche")
			# "Spion schicken" im Reiter Reiche: wechselt zu den Spionen mit diesem Ziel
			panel.call("_on_realm_mission_pressed", "scout")
			_check(panel.get_tab() == EspionagePanel.TAB_SPIES and panel.get_spy_uid() != 0, "„Spion schicken“ öffnet den Reiter Spione")
		3:
			_shot("phase7_3_spione")
			hud.open_diplomacy()
			hud.diplomacy_panel.select_realm(_ai0.id)
			_check(hud.is_diplomacy_open() and not hud.is_espionage_open() and hud.diplomacy_panel.get_tab() == "realms",
					"Diplomatie, Reiter Reiche (Spionagefenster geschlossen)")
			var strength: String = hud.diplomacy_panel.realm_strength_text(player, _ai0)
			print("[smoke] Reiche: %s Stärke %s (Kundschaft %d)" % [_ai0.display_name, strength,
					g.espionage_system.get_intel_level(player, _ai0)])
			_check((strength == "?") == (g.espionage_system.get_intel_level(player, _ai0) < 2), "Stärke nur mit Kundschaft (%s)" % strength)
		4:
			_shot("phase7_4_diplomatie_reiche")
			hud.toggle_espionage()
			_check(hud.is_espionage_open() and not hud.is_diplomacy_open(), "K öffnet das Spionagefenster und schliesst die Diplomatie")
			_check(hud.close_top_panel() and not hud.is_espionage_open(), "Esc schliesst das Spionagefenster")
			hud.open_link({"window": "espionage", "tab": "spies", "spy_uid": _spy_a})
			_check(hud.is_espionage_open() and panel.get_tab() == EspionagePanel.TAB_SPIES and panel.get_spy_uid() == _spy_a,
					"Meldungsverweis öffnet den Spion im Spionagefenster")
			hud.close_top_panel()
			g.selection.select([_ai0.castle])
		5:
			var facts: Label = hud.selection_panel.get("_facts")
			_check(hud.selection_panel.visible and facts.text.contains("Kundschaft"), "Auswahl der KI-Burg zeigt die Kundschaft (%s)" %
					facts.text.get_slice("\n", 0))
			_shot("phase7_5_auswahl_burg")
			g.selection.clear()
			print("[smoke] Phase 7: Oberflächentest fertig")
			_ui_step = -2
	_ui_step += 1


## Bildschirmfoto (nur mit shots=<ordner> und echtem Fenster, z. B. unter xvfb-run)
func _shot(shot_name: String) -> void:
	if _shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	var img := _game.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s_%s.png" % [_shots_dir, GameSession.faction_id, shot_name])


## Gebäude sofort fertig in der Nähe der Burg (Spirale)
func _place_near(k: Kingdom, def: Dictionary) -> Building:
	var g := _game
	var center: Vector2i = g.world.world_to_cell(k.castle.get_center())
	for r in range(4, 18):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var cell := center + Vector2i(dx, dy)
				if g.building_system.can_place(def, cell, k).is_empty():
					return g.building_system.place_building(def, cell, k, true)
	return null


static func _parts_text(parts: Dictionary) -> String:
	var list: PackedStringArray = []
	for key in parts:
		list.append("%s %.1f" % [str(key), float(parts[key])])
	return ", ".join(list)


## S4: erzwungene Welle gegen den Spieler
func _s4() -> void:
	var g := _game
	var ai: AISystem = g.ai_system
	var ok := ai.debug_force_attack(_ai0, g.player)
	var wave: Dictionary = _ai0.ai_state.get("wave", {})
	_check(ok and str(wave.get("state", "")) in ["gather", "march"] and (wave.get("uids", []) as Array).size() >= 3,
			"%s: Welle gegen den Spieler (%s, %d Einheiten)" % [_ai0.display_name, str(wave.get("state", "-")),
			(wave.get("uids", []) as Array).size()])
	g.combat_system.kingdom_attacked.connect(func(victim: Kingdom, attacker: Kingdom, _pos: Vector2) -> void:
		if victim == g.player and attacker == _ai0:
			_attack_seen = true)
	(g.espionage_system as EspionageSystem).enemy_spotted.connect(func(observer: Kingdom, foe: Kingdom, _pos: Vector2,
			count: int, inside: bool) -> void:
		if observer == g.player and foe == _ai0:
			_spotted[1 if inside else 0] = maxi(int(_spotted[1 if inside else 0]), count))


## S5: die Welle hat den Spieler erreicht; danach zurückrufen (der Test soll nicht
## am Spielende hängen) und wieder normal denken. Mit zwei KI-Reichen: Rivalen in den Krieg.
func _s5(t: float) -> bool:
	var g := _game
	var ai: AISystem = g.ai_system
	var player: Kingdom = g.player
	var wave: Dictionary = _ai0.ai_state.get("wave", {})
	var brain: AIBrain = ai.get_brain(_ai0)
	if brain != null and not wave.is_empty() and is_instance_valid(player.castle):
		for u in brain.units_of(wave.get("uids", [])):
			if u.position.distance_to(player.castle.get_center()) <= 30.0 * float(g.world.tile_size):
				_near_seen = true
	if not _attack_seen and not _near_seen and t < 520.0:
		return false
	_check(_attack_seen or _near_seen, "Welle von %s erreicht den Spieler (Angriff gemeldet: %s, nahe der Burg: %s, Zustand %s)" % [
			_ai0.display_name, str(_attack_seen), str(_near_seen), str(wave.get("state", "beendet"))])
	_check(int(_spotted[1]) > 0, "Feinde im Gebiet des Spielers gemeldet (bis %d im Gebiet, %d nahe der Grenze)" % [
			int(_spotted[1]), int(_spotted[0])])
	ai.debug_recall_wave(_ai0)
	ai.debug_fast = false
	if _ai.size() >= 2:
		ai.debug_set_tension(_ai[0], _ai[1], 95.0)
		_rival_test = true
	return true


## Vor dem Ende: die KI ist gewachsen (Gebäude, Truppen, Forschung, Beschwörungen);
## die verstärkte KI hat einen Helden und eine Welle geschickt
func _s_growth() -> void:
	var g := _game
	var long_run := _seconds >= 1500.0
	for k in _ai:
		if k.defeated:
			continue
		var brain: AIBrain = g.ai_system.get_brain(k)
		var army := brain.army_units().size() if brain != null else 0
		var min_buildings := 12 if _natural and _seconds >= 3600.0 else (10 if long_run else int(_start_buildings.get(k.id, 1)) + 3)
		# Kurze Läufe: nur die verstärkte KI muss schon Truppen haben (sonst Wirtschaft zuerst)
		var min_army := 5 if _natural and _seconds >= 3600.0 else (3 if long_run else (1 if k == _ai0 and not _natural else 0))
		var min_research := 3 if _natural and _seconds >= 3600.0 else (2 if long_run else 0)
		_check(k.buildings.size() >= min_buildings, "%s: %d Gebäude (mindestens %d)" % [k.display_name, k.buildings.size(), min_buildings])
		_check(army >= min_army, "%s: %d Kampfeinheiten (mindestens %d)" % [k.display_name, army, min_army])
		_check(k.researched.size() >= min_research, "%s: %d Forschungen (mindestens %d)" % [k.display_name, k.researched.size(), min_research])
		_check(int(k.stats.get("summoned", 0)) >= mini(min_army, 3), "%s: %d Einheiten beschworen" % [k.display_name,
				int(k.stats.get("summoned", 0))])
		if k == _ai0 and not _natural:
			_check(not k.heroes.is_empty(), "%s: Held angeworben (%d)" % [k.display_name, k.heroes.size()])
			_check(int(k.ai_state.get("waves_sent", 0)) >= 1, "%s: %d Wellen geschickt" % [k.display_name,
					int(k.ai_state.get("waves_sent", 0))])
		if _natural:
			var first_player := float((k.ai_state.get("log", {}) as Dictionary).get("first_player_wave", -1.0))
			var limit := float(g.ai_system.get_difficulty().get("first_attack_minutes", 45)) * 60.0
			_check(first_player < 0.0 or first_player >= limit, "%s: erste Welle gegen den Spieler %s (frühestens %.0f s)" % [
					k.display_name, "keine" if first_player < 0.0 else "%.0f s" % first_player, limit])
	if _rival_test and _ai.size() >= 2:
		_check(g.are_hostile(_ai[0], _ai[1]), "Rivalen %s und %s im Krieg" % [_ai[0].display_name, _ai[1].display_name])
	if _natural and _seconds >= 1800.0:
		_check(_player_alive_1800, "Burg und König des Spielers stehen bei t = 1800 s")
	_check(_think_ms() < 3.0, "KI-Denkzeit im Schnitt unter 3 ms (%.2f ms)" % _think_ms())
	# Speichern (Phase 10): Zustand der Spionage-Systeme übersteht to_dict/from_dict/rebuild_runtime
	var esp: EspionageSystem = g.espionage_system
	var spies: SpySystem = g.spy_system
	var esp_d := esp.to_dict()
	var spy_d := spies.to_dict()
	esp.from_dict(esp_d)
	esp.rebuild_runtime()
	spies.from_dict(spy_d)
	spies.rebuild_runtime()
	_check(esp.awareness.size() == (esp_d["awareness"] as Dictionary).size() and spies.spies.size() <= (spy_d["spies"] as Dictionary).size()
			and esp.get_discovery(g.player) > 0.0, "Spionage: to_dict/from_dict/rebuild_runtime (%d Aufmerksamkeiten, %d Spione)" % [
			esp.awareness.size(), spies.spies.size()])


## Mittlere Denkzeit eines KI-Denkvorgangs in Millisekunden
func _think_ms() -> float:
	var stats: Dictionary = _game.ai_system.stats
	return float(stats["think_usec_total"]) / maxi(int(stats["thinks"]), 1) / 1000.0


## S6: alle KI-Reiche besiegen (Burg zerstört, wie eine echte Niederlage)
func _s6() -> void:
	for k in _ai:
		_game.victory_system.debug_defeat(k, "castle")


## S7: Zerfall (keine Gebäude/Einheiten, Gebiet weg, Ruinen), Siegbildschirm, Weiterspielen
func _s7() -> void:
	var g := _game
	for k in _ai:
		var cell: Vector2i = _castle_cells.get(k.id, Vector2i(-1, -1))
		_check(k.defeated and k.buildings.is_empty() and k.units.is_empty() and g.world.get_owner(cell) != k.id,
				"%s gefallen: Gebäude %d, Einheiten %d, Gebiet weg" % [k.display_name, k.buildings.size(), k.units.size()])
	_check(not (g.victory_system.ruins as Array).is_empty(), "Ruinen: %d" % (g.victory_system.ruins as Array).size())
	_check(g.is_victory_shown(), "Siegbildschirm zu sehen")
	g.continue_after_victory()
	_check(not GameClock.paused and not g.is_victory_shown(), "Weiterspielen nach dem Sieg")


# ---------------------------------------------------------------------------
# Bericht
# ---------------------------------------------------------------------------

## Zeitleiste: je KI-Reich Gebäude, Bewohner, Armee, Wellen, Forschung, Helden
func _sample(t: float) -> void:
	var g := _game
	for k in _ai:
		if k.defeated:
			continue
		var brain: AIBrain = g.ai_system.get_brain(k)
		var workers := 0
		for u in k.units:
			if u.role == "worker":
				workers += 1
		var wave: Dictionary = k.ai_state.get("wave", {})
		var waiting: Dictionary = k.ai_state.get("build_waiting", {})
		var skipped: PackedStringArray = []
		var skip: Dictionary = k.ai_state.get("skip_until", {})
		for id in skip:
			if float(skip[id]) > t:
				skipped.append(str(id))
		print("[smoke] P7 t=%4.0f %s: Gebäude %d, Bewohner %d, Armee %d (Soll %d), Wellen %d (%s), Forschung %d, Helden %d, %s | spart: %s, übersprungen: %s" % [
				t, k.display_name, k.buildings.size(), workers, brain.army_units().size() if brain != null else 0,
				AIMilitary.army_target(brain, t) if brain != null else 0, int(k.ai_state.get("waves_sent", 0)),
				str(wave.get("state", "-")), k.researched.size(), k.heroes.size(), DataDB.cost_to_text(k.resources),
				str(waiting.get("building", "-")), ", ".join(skipped)])
	var player: Kingdom = g.player
	print("[smoke] P7 t=%4.0f Spieler: Gebäude %d, Einheiten %d, König %s, Burg %s" % [t, player.buildings.size(),
			player.units.size(), "lebt" if is_instance_valid(player.king) else "tot",
			"steht" if is_instance_valid(player.castle) else "zerstört"])
	var esp: EspionageSystem = g.espionage_system
	var aw: PackedStringArray = []
	for k in _ai:
		if not k.defeated:
			aw.append("%s %.0f (%s, Spione %d)" % [k.display_name, esp.get_awareness(k, player),
					EspionageSystem.awareness_tier_name(esp.get_awareness_tier(k, player)), g.spy_system.get_spies(k).size()])
	print("[smoke] P7 t=%4.0f Entdeckung Spieler %.1f (%s) | Aufmerksamkeit auf den Spieler: %s" % [t, esp.get_discovery(player),
			_parts_text(esp.get_discovery_parts(player)), ", ".join(aw)])


func report() -> void:
	var g := _game
	var ai: AISystem = g.ai_system
	for k in ai.get_ai_kingdoms(true):
		var log_entry: Dictionary = k.ai_state.get("log", {})
		var parts: PackedStringArray = []
		for key in log_entry:
			var v := float(log_entry[key])
			parts.append("%s %s" % [str(key).trim_prefix("first_"), "-" if v < 0.0 else "%.0f s" % v])
		print("[smoke] KI %s (%s): %s | Wellen %d (gegen Spieler %d) | Zeitleiste: %s" % [k.display_name,
				str(k.ai_state.get("personality", "?")), "gefallen" if k.defeated else "aktiv",
				int(k.ai_state.get("waves_sent", 0)), int(k.ai_state.get("player_waves", 0)), ", ".join(parts)])
	for key in ai.rivalry:
		var pair: Dictionary = ai.rivalry[key]
		print("[smoke] Rivalität %s: Spannung %.0f, %s" % [str(key), float(pair["tension"]), str(pair["state"])])
	print("[smoke] KI-Denkzeit: %d Denkvorgänge, Ø %.2f ms, max %.2f ms" % [int(ai.stats["thinks"]), _think_ms(),
			float(ai.stats["think_usec_max"]) / 1000.0])
	var part_texts: PackedStringArray = []
	var by_part: Dictionary = ai.stats.get("parts", {})
	for part in by_part:
		part_texts.append("%s %.2f" % [str(part), float(by_part[part]) / maxi(int(ai.stats["thinks"]), 1) / 1000.0])
	print("[smoke] KI-Denkzeit je Teil (ms je Denkvorgang): %s" % ", ".join(part_texts))
	for f in g.victory_system.fallen:
		print("[smoke] Gefallen: %s (%s) bei %.0f s" % [str(f["name"]), str(f["reason"]), float(f["at"])])
	var esp: EspionageSystem = g.espionage_system
	var parties := esp.get_parties()
	for o in parties:
		var row: PackedStringArray = []
		for t in parties:
			if t != o:
				row.append("%s: Aufmerksamkeit %.0f, Kundschaft %d" % [t.display_name, esp.get_awareness(o, t), esp.get_intel_level(o, t)])
		print("[smoke] Spionage %s (Entdeckung %.1f, Höchstwert %.1f): %s" % [o.display_name, esp.get_discovery(o),
				esp.get_discovery_peak(o), " | ".join(row)])
	print("[smoke] Spione: %s" % str(g.spy_system.stats))
	if _ui_step >= 0:
		_check(false, "Oberflächentest Phase 7 nicht fertig geworden (Schritt %d)" % _ui_step)
	if _stage != 99 and _stage < 9 and GameClock.game_time >= _seconds - 1.0:
		_check(false, "Phase-7-Test nicht fertig geworden (Stufe %d)" % _stage)
	print("[smoke] Phase 7: %s" % ("OK" if _errors == 0 else "%d Fehler" % _errors))
