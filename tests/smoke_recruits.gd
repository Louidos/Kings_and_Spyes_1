## Rauchtest Bewerber (gestartet von tests/smoke_test.gd, nicht bei passive=1):
## R0  Natürliches Wachstum ist langsam (economy.json), Bewerber-System läuft; die Taverne
##     verkürzt die Wartezeit, ihr Ausbau noch mehr
## R1  Bewerber erscheint mit Name, Wunschberuf und Bedingungen; Bedingung nicht erfüllt →
##     Aufnehmen im Bewerberfenster gesperrt; Bedingungen erfüllt → aufgenommen, Bewohner +1,
##     Geschenk bezahlt, Wunschberuf; Fachkraft arbeitet schneller; Abweisen geht immer
## R2  Ein wartender Bewerber bleibt im Speichern-Laden-Rundlauf erhalten
## Bericht: Bewerber und Aufnahmen der KI-Reiche.
## Fehler erscheinen als "ERROR: [smoke] Bewerber FEHLER: …" (push_error).
extends RefCounted

var _game: Node
var _errors := 0
var _step := 0
var _expect := {}
var _post_done := false


func _init(game: Node) -> void:
	_game = game


func _check(cond: bool, text: String) -> void:
	if cond:
		print("[smoke] Bewerber OK: " + text)
	else:
		_errors += 1
		push_error("[smoke] Bewerber FEHLER: " + text)


## Jeden Frame (Hauptlauf)
func tick(t: float) -> void:
	match _step:
		0:
			if t >= 6.0:
				_r0()
				_r1()
				_step = 1
		1:
			# Kurz vor dem Ende des Hauptlaufs: ein wartender Bewerber für den Rundlauf
			if t >= 250.0:
				_r2()
				_step = 2


func _r0() -> void:
	var k: Kingdom = _game.player
	var rs: RecruitSystem = _game.recruit_system
	_check(float(DataDB.eco("population.growth_interval", 0)) >= 180.0, "Natürliches Wachstum langsam (alle %d s)" % int(DataDB.eco("population.growth_interval", 0)))
	_check(rs != null and rs.enabled and rs.next_at.has(k.id), "Bewerber-System plant den nächsten Bewerber")
	var tav_before := rs.tavern_level(k)
	var mult_before := rs.interval_mult(k)
	var tavern := _place("tavern")
	_check(tavern != null, "Taverne gebaut")
	if tavern != null:
		var mult_1 := rs.interval_mult(k)
		_game.building_system.start_upgrade(tavern)
		tavern.complete_upgrade()
		var mult_2 := rs.interval_mult(k)
		_check(tav_before == 0 and is_equal_approx(mult_before, 1.0) and mult_1 < mult_before and mult_2 < mult_1,
				"Taverne verkürzt die Wartezeit (×%s, ausgebaut ×%s)" % [String.num(mult_1, 2), String.num(mult_2, 2)])


func _r1() -> void:
	var k: Kingdom = _game.player
	var rs: RecruitSystem = _game.recruit_system
	var dialog: RecruitDialog = _game.hud.recruit_dialog
	_ensure_housing(k)
	var id := rs.spawn_recruit(k, "farmer")
	var rec := rs.get_recruit(id)
	_check(id > 0 and not str(rec.get("name", "")).is_empty() and str(rec.get("job", "")) == "farmer"
			and (rec.get("reqs", []) as Array).size() >= 2, "Bewerber erscheint: %s, %s, %d Bedingungen" % [
			rs.describe(rec), rs.job_text(rec), (rec.get("reqs", []) as Array).size()])
	if id <= 0:
		return
	# Nicht erfüllbare Bedingung: Aufnehmen gesperrt
	rec["reqs"] = [{"type": "housing"}, {"type": "building", "building": "temple", "level": 3}]
	_game.hud.open_recruit_dialog(id)
	dialog._refresh()
	_check(dialog.is_open() and dialog._accept.disabled and dialog._text.text.contains("✗"),
			"Bewerberfenster: Bedingung fehlt (✗), Aufnehmen gesperrt")
	_check(not rs.accept(k, id).is_empty(), "Aufnehmen ohne erfüllte Bedingungen abgelehnt")
	# Erfüllbar: Wohnplatz und Geschenk
	k.resources["wood"] = maxf(k.get_amount("wood"), 100.0)
	rec["reqs"] = [{"type": "housing"}, {"type": "gift", "cost": {"wood": 7.0}}, {"type": "no_famine"}]
	rec["skilled"] = true
	dialog._refresh()
	_check(not dialog._accept.disabled, "Alle Bedingungen erfüllt (✓): Aufnehmen frei")
	var pop := k.get_population()
	var wood := k.get_amount("wood")
	var units_before := k.units.size()
	dialog._on_accept_pressed()
	_check(k.get_population() == pop + 1 and is_equal_approx(k.get_amount("wood"), wood - 7.0) and rs.get_recruit(id).is_empty()
			and not dialog.is_open(), "Aufgenommen: Bewohner %d → %d, Geschenk bezahlt" % [pop, k.get_population()])
	if k.units.size() > units_before:
		var v: Unit = k.units[k.units.size() - 1]
		var job := DataDB.get_job("farmer")
		var plain: float = _game.work_system.work_factor(k, job, null) * v.work_mult
		_check(v.skill_job == "farmer" and _game.work_system.work_factor(k, job, v) > plain + 0.1,
				"Fachkraft arbeitet im Wunschberuf schneller (%s, Beruf %s)" % [String.num(_game.work_system.work_factor(k, job, v), 2), v.job_id])
	# Abweisen geht immer
	var id2 := rs.spawn_recruit(k, "woodcutter")
	if id2 > 0:
		(rs.get_recruit(id2) as Dictionary)["reqs"] = [{"type": "castle_level", "min": 9}]
		_check(rs.reject(k, id2).is_empty() and str(rs.get_recruit(id2).get("state", "leaving")) == "leaving",
				"Abweisen trotz fehlender Bedingungen: der Bewerber zieht weiter")


func _r2() -> void:
	var k: Kingdom = _game.player
	var rs: RecruitSystem = _game.recruit_system
	var id := rs.spawn_recruit(k, "stonecutter")
	var rec := rs.get_recruit(id)
	if id > 0:
		_expect = {"id": id, "name": str(rec["name"]), "reqs": (rec["reqs"] as Array).size(), "job": str(rec["job"])}
	print("[smoke] Bewerber: für den Rundlauf wartet %s" % (rs.describe(rec) if id > 0 else "niemand"))


func _ensure_housing(k: Kingdom) -> void:
	var tries := 0
	while k.get_population() >= k.get_housing() and tries < 6:
		tries += 1
		if _place("house") == null:
			break


## Sofort fertig bauen, mit Abstand zur Burg und freiem Rand rundum
func _place(id: String) -> Building:
	var def := DataDB.get_building(id)
	var g := _game
	var k: Kingdom = g.player
	var bs: BuildingSystem = g.building_system
	for r in DataDB.resources:
		k.resources[str(r["id"])] = maxf(k.get_amount(str(r["id"])), 500.0)
	var center: Vector2i = g.world.world_to_cell(k.castle.get_center())
	var size: Vector2i = def.get("size", Vector2i(2, 2))
	for r in range(11, 22):
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
	if _expect.is_empty():
		return
	var rec: Dictionary = game.recruit_system.get_recruit(int(_expect["id"]))
	if rec.is_empty():
		print("[smoke] Bewerber: Testbewerber vor dem Speichern weitergezogen – nicht geprüft")
		return
	_check(str(rec["name"]) == str(_expect["name"]) and (rec["reqs"] as Array).size() == int(_expect["reqs"])
			and str(rec["job"]) == str(_expect["job"]) and game.find_by_uid(int(rec["uid"])) is Unit,
			"Nach dem Laden: Bewerber %s mit %d Bedingungen und Einheit" % [str(rec["name"]), int(_expect["reqs"])])


func report() -> void:
	var parts: PackedStringArray = []
	for k in _game.kingdoms:
		var kk: Kingdom = k
		if kk.controller == "ai" or kk.controller == "player":
			parts.append("%s: aufgenommen %d" % [kk.display_name, int(kk.stats.get("recruits_accepted", 0))])
	print("[smoke] Bewerber: %s | %s" % ["OK" if _errors == 0 else "%d Fehler" % _errors, ", ".join(parts)])
