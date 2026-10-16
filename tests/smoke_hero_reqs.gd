## Rauchtest Helden-Bedingungen (gestartet von tests/smoke_test.gd, nicht bei passive=1), nachdem
## der Heldentest den ersten Helden angeworben hat:
## H0  Jeder Heldentyp hat 2–3 Bedingungen; das Heldenfenster zeigt sie je Held mit ✓/✗; ein
##     gesperrter Held nennt die fehlende Bedingung
## H1  Bedingungen erfüllen (Forschung, Bibliothek Stufe II, besiegte Feinde, zerstörte Höhlen,
##     Burgstufe) schaltet die übrigen Helden frei (keine Bedingung fehlt mehr)
## Fehler erscheinen als "ERROR: [smoke] Heldenbedingungen FEHLER: …" (push_error).
extends RefCounted

var _game: Node
var _errors := 0
var _done := false


func _init(game: Node) -> void:
	_game = game


func _check(cond: bool, text: String) -> void:
	if cond:
		print("[smoke] Heldenbedingungen OK: " + text)
	else:
		_errors += 1
		push_error("[smoke] Heldenbedingungen FEHLER: " + text)


func tick(t: float, hero_recruited: bool) -> void:
	if _done or t < 20.0 or not hero_recruited:
		return
	_done = true
	var g := _game
	var k: Kingdom = g.player
	var hs: HeroSystem = g.hero_system
	var panel: HeroPanel = g.hud.hero_panel
	var offers := hs.get_offers(k)
	var locked := ""
	for o in offers:
		var id := str((o as Dictionary)["id"])
		var n := hs.get_requirements(id).size()
		_check(n >= 2 and n <= 3, "%s: %d Bedingungen" % [id, n])
		if locked.is_empty() and hs.can_recruit(k, id).begins_with("Bedingung fehlt"):
			locked = id
	_check(not locked.is_empty(), "Mindestens ein Held ist noch gesperrt: %s – %s" % [locked, hs.can_recruit(k, locked) if not locked.is_empty() else ""])
	g.hud.open_heroes(HeroPanel.TAB_RECRUIT)
	panel._refresh()
	if not locked.is_empty() and panel._offer_entries.has(locked):
		var text: String = ((panel._offer_entries[locked] as Dictionary)["reqs"] as RichTextLabel).text
		_check(text.contains("✗") and text.contains("✓"), "Heldenfenster zeigt die Bedingungen von %s mit ✓/✗" % locked)
		_check(not panel.recruit_reason(locked).is_empty() and (panel._offer_entries[locked]["button"] as Button).disabled,
				"Gesperrter Held: Anwerben-Knopf aus")
	g.hud.close_top_panel()
	# Alle Bedingungen erfüllen: Forschung, Bibliothek Stufe II, Kämpfe, Höhlen, Burgstufe
	var saved_stats := k.stats.duplicate()
	var saved_res := k.researched.duplicate()
	for o in offers:
		for req in hs.get_requirements(str((o as Dictionary)["id"])):
			var r: Dictionary = req
			match str(r.get("type", "")):
				"research":
					k.researched[Requirements.research_id(r, k)] = true
				"kills":
					k.stats["kills"] = maxi(int(k.stats.get("kills", 0)), int(r.get("count", 1)))
				"lairs":
					k.stats["lairs_destroyed"] = maxi(int(k.stats.get("lairs_destroyed", 0)), int(r.get("count", 1)))
				"building":
					var bid := str(r.get("building", ""))
					var level := int(r.get("level", 1))
					if BuildingSystem.count_of(k, bid, level) == 0:
						var b := _place(bid)
						while b != null and b.level < level:
							b.upgrading = true
							b.complete_upgrade()
	var still: PackedStringArray = []
	for o in offers:
		var id := str((o as Dictionary)["id"])
		if not hs.requirements_met(k, id):
			still.append("%s (%s)" % [id, Requirements.first_missing(hs.get_requirements(id), k, g)])
	_check(still.is_empty(), "Bedingungen erfüllt: alle Helden frei" + ("" if still.is_empty() else " – noch gesperrt: " + ", ".join(still)))
	k.stats = saved_stats
	k.researched = saved_res


func _place(id: String) -> Building:
	var def := DataDB.get_building(id)
	var g := _game
	var k: Kingdom = g.player
	var bs: BuildingSystem = g.building_system
	for r in DataDB.resources:
		k.resources[str(r["id"])] = maxf(k.get_amount(str(r["id"])), 800.0)
	# Forschung des Gebäudes (z. B. Schattenloge) für den Test freischalten
	for unlock_id in def.get("requires", []):
		k.unlocks[str(unlock_id)] = true
	var center: Vector2i = g.world.world_to_cell(k.castle.get_center())
	var size: Vector2i = def.get("size", Vector2i(2, 2))
	for r in range(12, 24):
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


func report() -> void:
	print("[smoke] Heldenbedingungen: %s" % ("OK" if _errors == 0 and _done else "%d Fehler%s" % [_errors, "" if _done else " (nicht gelaufen)"]))
	if not _done:
		push_error("[smoke] Heldenbedingungen FEHLER: Test nicht gelaufen")
