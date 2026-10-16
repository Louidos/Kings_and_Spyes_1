## TutorialSystem
##
## Geführtes Tutorial (data/tutorial.json): eine Folge von Schritten mit Titel, Text,
## Hervorhebung (Bedienelement oder Stelle in der Welt) und einer Bedingung, die der
## Spieler erfüllen soll ("building_placed:house", "window_opened:heroes" …). Ohne
## Bedingung geht es mit "Weiter" voran, lange Schritte lassen sich überspringen.
##
## Die Bedingungen werden alle POLL_INTERVAL echte Sekunden aus dem Zustand des Spiels
## gelesen (billig, nur der aktuelle Schritt). Wenige Aktionen ohne bleibenden Zustand
## (Bewegungsbefehl, Speichern, Tempo) merkt sich das System über Signale, solange der
## Schritt läuft. Das Tutorial läuft in Echtzeit – auch in der Pause, die es ja erklärt.
##
## Schutz: Wurde das Tutorial beim Start der Partie eingeschaltet (Knopf "Tutorial" im
## Hauptmenü oder "Tipps/Tutorial anzeigen"), greifen die KI-Reiche den Spieler nicht an,
## Monster-Streifzüge und Zufallsereignisse treffen ihn nicht (höchstens
## settings.protect_max_minutes, danach bzw. nach dem Ende noch grace_minutes). Die
## Systeme fragen das über TutorialSystem.protects(game, kingdom) ab – nach dem Tutorial
## gelten wieder ihre normalen Regeln.
##
## Zustand (gespeichert): state ("off", "running", "aborted", "finished"), step_id, done,
## protect, started_at, ended_at, minimized, granted (Schritte, deren Geschenk bezahlt ist).
## Die Oberfläche (TutorialOverlay) legt setup_ui() an; sie zeigt nur an und ruft
## advance(), skip(), abort() auf.
class_name TutorialSystem
extends Node

## Schritt, Zustand oder "erledigt" haben sich geändert (Oberfläche neu aufbauen)
signal changed

const POLL_INTERVAL := 0.25
const STATE_OFF := "off"
const STATE_RUNNING := "running"
const STATE_ABORTED := "aborted"
const STATE_FINISHED := "finished"
## Stufen, die als Truppen zählen (Bedingung troops:<n>)
const TROOP_TIERS := ["fighter", "archer", "elite", "special", "medic"]

var game: Node
## Oberfläche (Panel und Hervorhebung)
var overlay: TutorialOverlay

# --- gespeichert ---
var state := STATE_OFF
var step_id := ""
## Bedingung des aktuellen Schritts erfüllt
var done := false
## Gegner, Monster und Ereignisse verschonen den Spieler (siehe is_protecting)
var protect := false
var started_at := -1.0
var ended_at := -1.0
var minimized := false
## ids der Schritte, deren Geschenk schon bezahlt wurde (nie doppelt, auch nicht nach Neustart)
var granted: Array = []

# --- Laufzeit ---
## Gültige Schritte (requires_hud geprüft), aus tutorial.json
var _steps: Array = []
var _timer := 0.0
## Echte Sekunden seit "erledigt" (automatisch weiter)
var _done_age := 0.0
## Aktionen während des Schritts: "move", "attack_move", "attack", "rally", "speed", "saved"
var _events: Dictionary = {}
## Ausgangswerte für camera_moved/zoomed
var _base_pos := Vector2.ZERO
var _base_zoom := 1.0


func setup(p_game: Node) -> void:
	game = p_game
	if game.get("selection") != null:
		game.selection.command_issued.connect(_on_command_issued)
	GameClock.speed_changed.connect(_on_speed_changed)
	SaveManager.save_finished.connect(_on_save_finished)


## Oberfläche anlegen (nach hud.setup, neue und geladene Partie)
func setup_ui() -> void:
	_steps = []
	if overlay == null:
		overlay = TutorialOverlay.new()
		overlay.name = "TutorialOverlay"
		game.add_child(overlay)
		overlay.setup(game, self)
	_capture_base()
	changed.emit()


# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------

func is_running() -> bool:
	return state == STATE_RUNNING


## Tutorial beginnen (erster Schritt). p_protect: Gegner und Ereignisse verschonen
## den Spieler, solange es läuft (nur beim Start einer Partie)
func start(p_protect: bool) -> void:
	protect = p_protect
	var list := get_steps()
	if list.is_empty():
		return
	state = STATE_RUNNING
	# Die Schutzdauer zählt ab dem ersten Start (von vorn beginnen verlängert sie nicht)
	if started_at < 0.0:
		started_at = GameClock.game_time
	ended_at = -1.0
	minimized = false
	_enter_step(str((list[0] as Dictionary).get("id", "")))


## Abgebrochenes Tutorial beim gemerkten Schritt fortsetzen
func resume() -> void:
	if state != STATE_ABORTED or _index_of(step_id) < 0:
		start(protect)
		return
	state = STATE_RUNNING
	ended_at = -1.0
	minimized = false
	_enter_step(step_id)


## Text für den Knopf im Spielmenü
func menu_action_text() -> String:
	match state:
		STATE_RUNNING:
			return "Tutorial von vorn"
		STATE_ABORTED:
			if _index_of(step_id) >= 0:
				return "Tutorial fortsetzen (Schritt %d/%d)" % [get_step_number(), get_step_count()]
	return "Tutorial starten"


func menu_action_tooltip() -> String:
	match state:
		STATE_RUNNING:
			return "Das Tutorial beginnt wieder beim ersten Schritt"
		STATE_ABORTED:
			return "Weiter beim Schritt, bei dem du aufgehört hast"
	return "Geführte Schritte durch Bauen, Truppen, Forschung, Helden, Diplomatie und Speichern"


## Knopf im Spielmenü: starten, fortsetzen bzw. von vorn beginnen
func menu_action() -> void:
	if state == STATE_ABORTED and _index_of(step_id) >= 0:
		resume()
	else:
		# Schutz bleibt, wie er beim ersten Start war (gezählt ab dem ersten Start)
		start(protect)


## "Weiter": nur ohne Bedingung oder wenn sie erfüllt ist; der letzte Schritt beendet
func advance() -> bool:
	if not is_running():
		return false
	var s := get_step()
	if not str(s.get("condition", "")).is_empty() and not done:
		return false
	_next()
	return true


## "Überspringen" (nur bei skippable)
func skip() -> bool:
	if not is_running() or not bool(get_step().get("skippable", false)):
		return false
	_next()
	return true


## "Tutorial beenden": später im Spielmenü fortsetzbar
func abort() -> void:
	if not is_running():
		return
	state = STATE_ABORTED
	ended_at = GameClock.game_time
	Notify.info("Tutorial beendet – im Spielmenü (Esc) kannst du es fortsetzen.")
	changed.emit()


func set_minimized(value: bool) -> void:
	if minimized != value:
		minimized = value
		changed.emit()


func _finish() -> void:
	state = STATE_FINISHED
	ended_at = GameClock.game_time
	done = false
	var text := "Tutorial abgeschlossen – viel Erfolg, König!"
	if is_protecting():
		text += " Die Gegner lassen dir noch etwa %d Minuten Zeit." % ceili(_protect_until() / 60.0 - GameClock.game_time / 60.0)
	Notify.good(text)
	changed.emit()


func _next() -> void:
	var list := get_steps()
	var i := _index_of(step_id)
	if i < 0 or i + 1 >= list.size():
		_finish()
		return
	_enter_step(str((list[i + 1] as Dictionary).get("id", "")))


func _enter_step(id: String) -> void:
	step_id = id
	done = false
	_done_age = 0.0
	_events.clear()
	var s := get_step()
	var k: Kingdom = game.player
	# Geschenk des Hofschatzmeisters (einmal je Partie)
	var grant: Dictionary = s.get("grant", {})
	if not grant.is_empty() and not granted.has(id) and k != null:
		granted.append(id)
		var parts: PackedStringArray = []
		for res_id in grant:
			k.add_resource(str(res_id), float(grant[res_id]))
			parts.append("+%d %s" % [int(grant[res_id]), str(DataDB.get_resource(str(res_id)).get("name", res_id))])
		k.resources_changed.emit()
		Notify.good("Der Hofschatzmeister schenkt dir für das Tutorial: " + ", ".join(parts))
	# Burgstufe als Geschenk (castle_level): die Burg wächst ohne Bedingungen, einmal je Partie
	var castle_level := int(s.get("castle_level", 0))
	if castle_level > 0 and not granted.has(id + ":castle") and k != null and k.get_castle_level() < castle_level:
		granted.append(id + ":castle")
		game.building_system.set_castle_level(k, castle_level)
		Notify.good("Der Hofschatzmeister lässt deine Burg ausbauen: %s (Burgstufe %d)" % [
				DataDB.castle_level_name(castle_level), castle_level])
	# Aufstieg (Schritt Wertepunkte): ein Krieger ohne Rang steigt auf, einmal je Partie
	var promote := int(s.get("promote", 0))
	if promote > 0 and not granted.has(id + ":promote") and k != null:
		granted.append(id + ":promote")
		_promote_one(k, promote)
	var focus := str(s.get("focus", ""))
	if not focus.is_empty():
		var pos: Variant = world_target("world:" + focus)
		if pos is Vector2:
			game.camera.focus_on(pos)
	_capture_base()
	_timer = POLL_INTERVAL  # sofort prüfen
	changed.emit()


## Ersten Krieger ohne Rang um ranks Ränge aufsteigen lassen (Erfahrung bis zur Schwelle)
func _promote_one(k: Kingdom, ranks: int) -> void:
	var ts: Variant = game.get("troop_system")
	if not (ts is TroopSystem):
		return
	var steps: Array = DataDB.trp("veterancy.ranks", [])
	for u in k.units:
		if not is_instance_valid(u) or not u.is_alive() or u.hero_id != 0 or not CommandSystem.is_warrior(u):
			continue
		if not (ts as TroopSystem).has_stat_points(u) or u.vet_rank > 0:
			continue
		var target := mini(u.vet_rank + ranks, steps.size() - 1)
		var need: float = float((steps[target] as Dictionary).get("xp", 0)) - float(u.vet_xp)
		if need > 0.0:
			(ts as TroopSystem).add_xp(u, need + 0.5)
		return


func _capture_base() -> void:
	var cam: Variant = game.get("camera") if game != null else null
	if cam is Camera2D:
		_base_pos = (cam as Camera2D).position
		_base_zoom = maxf((cam as Camera2D).zoom.x, 0.01)


func _process(delta: float) -> void:
	if state != STATE_RUNNING or game == null or game.player == null:
		return
	if done:
		if str(get_step().get("condition", "")).is_empty():
			return
		_done_age += delta
		if _done_age >= float(DataDB.tut("settings.auto_advance_seconds", 1.6)):
			_next()
		return
	_timer += delta
	if _timer < POLL_INTERVAL:
		return
	_timer = 0.0
	check_now()


## Bedingung des aktuellen Schritts jetzt prüfen (true = erfüllt; auch für den Rauchtest)
func check_now() -> bool:
	if not is_running():
		return false
	if done:
		return true
	var cond := str(get_step().get("condition", ""))
	if cond.is_empty():
		return false
	if check_condition(cond):
		done = true
		_done_age = 0.0
		changed.emit()
	return done


# ---------------------------------------------------------------------------
# Schritte
# ---------------------------------------------------------------------------

## Gültige Schritte in Reihenfolge (Schritte mit requires_hud nur, wenn das HUD die
## Methode hat – z. B. Fenster, die erst später dazukommen)
func get_steps() -> Array:
	if not _steps.is_empty():
		return _steps
	var hud: Variant = game.get("hud") if game != null else null
	for e in DataDB.tut("steps", []):
		var s: Dictionary = e
		var need := str(s.get("requires_hud", ""))
		if not need.is_empty() and not (hud is Object and (hud as Object).has_method(need)):
			continue
		_steps.append(s)
	return _steps


func get_step() -> Dictionary:
	var i := _index_of(step_id)
	return get_steps()[i] if i >= 0 else {}


## 1-basiert (0 = kein Schritt)
func get_step_number() -> int:
	return _index_of(step_id) + 1


func get_step_count() -> int:
	return get_steps().size()


func is_step_done() -> bool:
	return done


func is_last_step() -> bool:
	return get_step_number() == get_step_count()


func _index_of(id: String) -> int:
	var list := get_steps()
	for i in list.size():
		if str((list[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


## Text mit Platzhaltern: {b:<gebäude>}, {u:<stufe>}, {r:<alias>}, {s:<alias>}, {key:<aktion>}
func format_text(text: String) -> String:
	var faction: String = game.player.faction_id if game != null and game.player != null else GameSession.faction_id
	var out := text
	var guard := 0
	while guard < 40:
		guard += 1
		var a := out.find("{")
		if a < 0:
			break
		var b := out.find("}", a)
		if b < 0:
			break
		var token := out.substr(a + 1, b - a - 1)
		out = out.substr(0, a) + _resolve_token(token, faction) + out.substr(b + 1)
	return out


func _resolve_token(token: String, faction: String) -> String:
	var kind := token.get_slice(":", 0)
	var arg := token.get_slice(":", 1)
	match kind:
		"b":
			return DataDB.get_building_name(DataDB.get_building(arg), faction)
		"u":
			return str(DataDB.get_unit_for_tier(faction, arg).get("name", arg))
		"r":
			return str(DataDB.get_research(_alias(arg, faction)).get("name", arg))
		"s":
			return str(DataDB.get_spell(_alias(arg, faction)).get("name", arg))
		"key":
			return HelpPanel.keys_text(arg)
	return token


func _alias(name_id: String, faction: String) -> String:
	var entry: Variant = (DataDB.tut("aliases", {}) as Dictionary).get(name_id, null)
	if entry is Dictionary:
		return str((entry as Dictionary).get(faction, name_id))
	return name_id


# ---------------------------------------------------------------------------
# Bedingungen
# ---------------------------------------------------------------------------

## Ist die Bedingung ("art:wert") gerade erfüllt?
func check_condition(cond: String) -> bool:
	var kind := cond.get_slice(":", 0)
	var arg := cond.get_slice(":", 1) if cond.contains(":") else ""
	var k: Kingdom = game.player
	match kind:
		"camera_moved":
			var tiles := float(DataDB.tut("settings.camera_move_tiles", 6))
			return game.camera.position.distance_to(_base_pos) >= tiles * float(game.world.tile_size)
		"zoomed":
			return absf(game.camera.zoom.x - _base_zoom) / _base_zoom >= float(DataDB.tut("settings.zoom_change", 0.12))
		"paused":
			return GameClock.paused
		"unpaused":
			return not GameClock.paused
		"speed_changed":
			return _events.has("speed")
		"building_placed":
			return game.building_system.count_buildings(k, arg, false) > 0
		"building_done":
			return game.building_system.count_buildings(k, arg, true) > 0
		"job_assigned":
			for u in k.units:
				if u.job_id == arg and u.is_alive():
					return true
			return false
		"road_placed":
			return _count_roads(k) >= (int(arg) if arg.is_valid_int() else int(DataDB.tut("settings.road_cells", 4)))
		"building_selected":
			var p: Variant = game.selection.get_primary()
			return p is Building and (p as Building).kingdom == k and str((p as Building).def.get("id", "")) == arg
		"unit_summoned":
			for u in k.units:
				if u.tier == arg and u.is_alive():
					return true
			return false
		"units_selected":
			return not game.selection.get_own_units().is_empty()
		"move_order":
			return _events.has("move") or _events.has("attack_move") or _events.has("attack")
		"attack_move":
			return _events.has("attack_move") or _events.has("attack")
		"troops":
			var n := 0
			for u in k.units:
				if u.is_alive() and u.hero_id == 0 and TROOP_TIERS.has(u.tier):
					n += 1
			return n >= maxi(int(arg), 1)
		"warriors_selected":
			var warriors: Array = game.command_system.get_warriors(k)
			if warriors.size() < 2:
				return false
			var selected: Array = game.selection.selected
			for u in warriors:
				if not selected.has(u):
					return false
			return true
		"stance_set":
			for u in game.command_system.get_warriors(k):
				if (u as Unit).stance != CommandSystem.DEFAULT_STANCE:
					return true
			return false
		"forge_bought":
			for up_id in k.forge_levels:
				if int(k.forge_levels[up_id]) > 0:
					return true
			return false
		"stat_point_spent":
			for u in k.units:
				if is_instance_valid(u) and u.is_alive() and u.hero_id == 0 and not (u.stat_alloc as Dictionary).is_empty():
					return true
			return false
		"army_saved":
			for n in k.armies:
				if not (k.armies[n] as Array).is_empty():
					return true
			return false
		"research_started":
			return not k.research_queue.is_empty() or not k.researched.is_empty()
		"spell_cast":
			return int(k.stats.get("spells", 0)) > 0
		"hero_recruited":
			if not k.heroes.is_empty():
				return true
			var hall: Building = game.hero_system.get_hall(k)
			return hall != null and not hall.summon_queue.is_empty()
		"window_opened":
			var method := "is_%s_open" % arg
			return game.hud.has_method(method) and bool(game.hud.call(method))
		"gift_sent":
			for vid in game.diplomacy_system.gift_recent:
				if (game.diplomacy_system.gift_recent[vid] as Dictionary).has(k.id):
					return true
			return false
		"saved":
			return _events.has("saved")
	push_warning("Tutorial: unbekannte Bedingung " + cond)
	return false


## Geplante und fertige Strassen im eigenen Gebiet
func _count_roads(k: Kingdom) -> int:
	var world: WorldData = game.world
	var n := 0
	for cell in world.roads:
		if world.get_owner(cell) == k.id:
			n += 1
	return n


func _on_command_issued(_pos: Vector2, kind: String) -> void:
	if is_running():
		_events[kind] = true


func _on_speed_changed(paused: bool, _speed: float) -> void:
	if is_running() and not paused:
		_events["speed"] = true


func _on_save_finished(slot: String, ok: bool, _message: String) -> void:
	if is_running() and ok and not slot.begins_with(SaveManager.AUTO_PREFIX):
		_events["saved"] = true


# ---------------------------------------------------------------------------
# Ziele in der Welt
# ---------------------------------------------------------------------------

## Stelle in der Welt zu "world:castle", "world:mana", "world:village", "world:lair",
## "world:building:<id>" (null, wenn es keine gibt)
func world_target(spec: String) -> Variant:
	if game == null or game.player == null or not spec.begins_with("world:"):
		return null
	var k: Kingdom = game.player
	var what := spec.substr(6)
	var home: Vector2 = k.castle.get_center() if is_instance_valid(k.castle) else game.world.cell_to_world(game.world.start_cell)
	if what == "castle":
		return home
	if what == "mana":
		return _nearest_deposit(home, "mana_spring", 16)
	if what == "village":
		var best: Variant = null
		var best_d := INF
		for v in game.village_system.get_villages():
			var c: Vector2 = game.village_system.get_center(v)
			if home.distance_to(c) < best_d:
				best_d = home.distance_to(c)
				best = c
		return best
	if what == "lair":
		var best_l: Variant = null
		var best_ld := INF
		for lair in game.monster_system.lairs:
			if is_instance_valid(lair) and home.distance_to((lair as Building).get_center()) < best_ld:
				best_ld = home.distance_to((lair as Building).get_center())
				best_l = (lair as Building).get_center()
		return best_l
	if what.begins_with("building:"):
		var id := what.substr(9)
		for b in k.buildings:
			if is_instance_valid(b) and str(b.def.get("id", "")) == id:
				return b.get_center()
	return null


## Nächste Kachel mit diesem Vorkommen (z. B. Manaquelle) um die Burg – eine freie zuerst,
## sonst eine bebaute (dann zeigt der Pfeil auf den Brunnen)
func _nearest_deposit(home: Vector2, deposit_id: String, radius: int) -> Variant:
	var world: WorldData = game.world
	var center := world.world_to_cell(home)
	var best: Variant = null
	var best_d := INF
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dy)
			if not world.in_bounds(c) or str(world.get_deposit(c).get("id", "")) != deposit_id:
				continue
			# Bebaute Quellen zählen nur, wenn es keine freie gibt
			var d := Vector2(dx, dy).length() + (1000.0 if world.get_building_at(c) != null else 0.0)
			if d < best_d:
				best_d = d
				best = world.cell_to_world(c)
	return best


# ---------------------------------------------------------------------------
# Schutz
# ---------------------------------------------------------------------------

## Verschont das Tutorial gerade den Spieler? (KI-Angriffe, Streifzüge, Ereignisse)
func is_protecting() -> bool:
	if not protect or started_at < 0.0:
		return false
	return GameClock.game_time < _protect_until()


## Spielzeit, bis zu der der Schutz gilt
func _protect_until() -> float:
	var cap := started_at + float(DataDB.tut("settings.protect_max_minutes", 120)) * 60.0
	if state == STATE_RUNNING:
		return cap
	if ended_at < 0.0:
		return -1.0
	return minf(ended_at, cap) + float(DataDB.tut("settings.grace_minutes", 10)) * 60.0


## Für die Systeme: wird dieses Reich gerade vom Tutorial geschützt?
static func protects(p_game: Node, k: Kingdom) -> bool:
	if p_game == null or k == null or not k.is_player:
		return false
	var ts: Variant = p_game.get("tutorial_system")
	return ts is TutorialSystem and (ts as TutorialSystem).is_protecting()


# ---------------------------------------------------------------------------
# Speichern
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"state": state, "step_id": step_id, "done": done, "protect": protect, "started_at": started_at,
			"ended_at": ended_at, "minimized": minimized, "granted": granted.duplicate()}


func from_dict(d: Dictionary) -> void:
	state = str(d.get("state", STATE_OFF))
	step_id = str(d.get("step_id", ""))
	done = bool(d.get("done", false))
	protect = bool(d.get("protect", false))
	started_at = float(d.get("started_at", -1.0))
	ended_at = float(d.get("ended_at", -1.0))
	minimized = bool(d.get("minimized", false))
	granted = (d.get("granted", []) as Array).duplicate()


func rebuild_runtime() -> void:
	_steps = []
	_events.clear()
	_timer = 0.0
	_done_age = 0.0
	# Ein Schritt, den es (nach geänderten Daten) nicht mehr gibt: beim ersten weitermachen
	if state == STATE_RUNNING and _index_of(step_id) < 0:
		var list := get_steps()
		step_id = str((list[0] as Dictionary).get("id", "")) if not list.is_empty() else ""
		done = false
		if step_id.is_empty():
			state = STATE_FINISHED
	_capture_base()
	changed.emit()
