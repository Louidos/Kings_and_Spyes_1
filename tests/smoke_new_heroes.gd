## Rauchtest neue Helden (je Fraktion fünf, data/heroes.json): das Heldenfenster zeigt fünf Helden
## mit ✓/✗-Bedingungen; die zwei neuen Helden der Fraktion lassen sich nach Erfüllen ihrer
## Bedingungen anwerben, und jede ihrer Fähigkeiten wirkt (Reichs-Zuschlag, Aura, Wirkung auf
## Freund oder Feind, Beschwörung).
extends RefCounted

const TOPIC := "Helden"
const NEW_HEROES := {"good": ["hero_spymaster", "hero_architect"], "evil": ["hero_summoner", "hero_ironwall"]}


func run(r: Node) -> void:
	var g: Node = r.game
	var k: Kingdom = g.player
	var hs: HeroSystem = g.hero_system
	var offers: Array = hs.get_offers(k)
	r.check(TOPIC, offers.size() == 5, "%d Helden zur Auswahl" % offers.size())
	var panel: HeroPanel = g.hud.hero_panel
	g.hud.open_heroes(HeroPanel.TAB_RECRUIT)
	panel._refresh()
	var marked := 0
	for o in offers:
		var id := str((o as Dictionary)["id"])
		if panel._offer_entries.has(id):
			var text: String = ((panel._offer_entries[id] as Dictionary)["reqs"] as RichTextLabel).text
			if text.contains("✓") or text.contains("✗"):
				marked += 1
	r.check(TOPIC, marked == 5, "Heldenfenster zeigt %d Helden mit ✓/✗-Bedingungen" % marked)
	g.hud.close_top_panel()
	# Bedingungen der neuen Helden erfüllen, Heldenhalle bauen, anwerben
	var ids: Array = NEW_HEROES.get(k.faction_id, [])
	for id in ids:
		for req in hs.get_requirements(str(id)):
			_fulfil(r, req as Dictionary)
	_fulfil(r, {"type": "building", "building": "hero_hall"})
	for id in ids:
		var reason := hs.can_recruit(k, str(id))
		r.check(TOPIC, reason.is_empty(), "%s anwerbbar %s" % [id, reason])
		r.check(TOPIC, hs.recruit(k, str(id)), "%s angeworben" % id)
	await r.wait_game_seconds(70.0)
	for id in ids:
		var rec := {}
		for h in k.heroes:
			if str((h as Dictionary)["type_id"]) == str(id):
				rec = h
		if rec.is_empty():
			r.check(TOPIC, false, "%s ist erschienen" % id)
			continue
		var u: Unit = hs.get_unit(k, int(rec["id"]))
		r.check(TOPIC, u != null and u.get("_figure") != null, "%s ist erschienen (%s, eigene Figur)" % [id, hs.get_title(rec)])
		if u == null:
			continue
		for aid in DataDB.get_hero_type(str(id)).get("abilities", []):
			(rec["ranks"] as Dictionary)[str(aid)] = 1
		hs._apply_hero(rec)
		_check_autocast(r, u, rec)
		for aid in DataDB.get_hero_type(str(id)).get("abilities", []):
			await _test_ability(r, u, rec, str(aid))


## Selbstauslösung: Schutz für den Helden nur im Kampf, Hilfe für die eigenen Truppen nur, wenn
## eine kämpft oder verwundet ist (sonst wäre die Fähigkeit im Kampf gerade im Abklingen)
func _check_autocast(r: Node, u: Unit, rec: Dictionary) -> void:
	var g: Node = r.game
	var hs: HeroSystem = g.hero_system
	var k: Kingdom = u.kingdom
	var abilities: Array = hs.get_type(rec).get("abilities", [])
	for aid in abilities:
		var def := DataDB.get_ability(str(aid))
		var target := str(def.get("target", ""))
		if str(def.get("kind", "")) != "active" or not (target == "self" or (target == "none" and hs.get_ability_side(str(aid)) == "own")):
			continue
		for other in abilities:
			hs.set_autocast(k, int(rec["id"]), str(other), str(other) == str(aid))
		u.target = null
		u.hp = u.max_hp
		# Ruhige Lage: eigene Truppen im Umkreis gesund und ohne Gegner
		for w in hs.get_ability_targets(u, str(aid), u.position):
			(w as Unit).hp = (w as Unit).max_hp
			(w as Unit).target = null
		var idle: Dictionary = hs.pick_auto_cast(u)
		var foe: Unit = null
		var friend: Unit = null
		if target == "self":
			foe = _enemy_near(r, u)
			u.target = foe
		else:
			friend = r.spawn_tier(k, "fighter", 1)[0]
			friend.position = u.position + Vector2(30, 0)
			friend.hp = friend.max_hp * 0.5
		var busy: Dictionary = hs.pick_auto_cast(u)
		r.check(TOPIC, idle.is_empty() and str(busy.get("ability_id", "")) == str(aid),
				"%s löst %s nur im Ernstfall selbst aus (ruhig: %s, im Kampf/verwundet: %s)" % [hs.get_title(rec), aid,
				str(idle.get("ability_id", "-")), str(busy.get("ability_id", "-"))])
		u.target = null
		for w in [foe, friend]:
			if w != null and is_instance_valid(w):
				g.unit_system.remove_unit(w)
	for other in abilities:
		hs.set_autocast(k, int(rec["id"]), str(other), false)


## Eine Fähigkeit auslösen bzw. ihre dauerhafte Wirkung prüfen
func _test_ability(r: Node, u: Unit, rec: Dictionary, aid: String) -> void:
	var g: Node = r.game
	var k: Kingdom = u.kingdom
	var hs: HeroSystem = g.hero_system
	var def := DataDB.get_ability(aid)
	var v := hs.get_ability_values(rec, aid)
	var source := "ability:" + aid
	if str(def["kind"]) == "passive":
		var ok := true
		var parts: PackedStringArray = []
		var bonuses: Dictionary = v.get("kingdom_bonus", {})
		for key in bonuses:
			ok = ok and k.bonus(str(key)) >= float(bonuses[key]) - 0.001
			parts.append("%s %+.2f" % [key, k.bonus(str(key))])
		var factors: Dictionary = v.get("kingdom_mods", {})
		for key in factors:
			ok = ok and k.mod(str(key)) >= float(factors[key]) - 0.001
			parts.append("%s ×%.2f" % [key, k.mod(str(key))])
		if v.has("mana_regen"):
			ok = ok and k.bonus("mana_regen") >= float(v["mana_regen"]) - 0.0001
			parts.append("Mana/s %+.2f" % k.bonus("mana_regen"))
		if v.has("aura"):
			var friend: Unit = r.spawn_tier(k, "fighter", 1)[0]
			friend.position = u.position + Vector2(40, 0)
			await r.wait_game_seconds(3.0)
			ok = ok and _has_effect(friend, source)
			parts.append("Aura auf %s" % friend.get_display_name())
		r.check(TOPIC, ok and not parts.is_empty(), "%s (passiv): %s" % [def["name"], ", ".join(parts)])
		return
	hs.debug_reset_cooldowns(k, int(rec["id"]))
	var target: Variant = null
	var probe: Unit = null
	var side := hs.get_ability_side(aid)
	match str(def["target"]):
		"enemy":
			probe = _enemy_near(r, u)
			target = probe
		"point":
			target = u.position + Vector2(30, 0)
	if str(def["target"]) != "enemy" and side == "enemy":
		probe = _enemy_near(r, u)
	elif str(def["target"]) != "enemy" and str(def["target"]) != "self":
		probe = r.spawn_tier(k, "fighter", 1)[0]
		probe.position = u.position + Vector2(30, 10)
	var summon_type := str((v.get("summon", {}) as Dictionary).get("unit", ""))
	var before := _count_type(k, summon_type)
	var reason := hs.can_use(u, aid, target)
	var used := hs.use_ability(u, aid, target)
	var effect_ok := false
	var what := ""
	if not summon_type.is_empty():
		effect_ok = _count_type(k, summon_type) > before
		what = "%d× %s" % [_count_type(k, summon_type) - before, summon_type]
	elif str(def["target"]) == "self":
		effect_ok = _has_effect(u, source)
		what = "Wirkung auf den Helden"
	else:
		effect_ok = probe != null and is_instance_valid(probe) and (_has_effect(probe, source) or not probe.is_alive())
		what = "Wirkung auf %s" % (probe.get_display_name() if probe != null and is_instance_valid(probe) else "?")
	r.check(TOPIC, used and effect_ok, "%s (%s): %s %s" % [def["name"], def["target"], what, reason])


func _has_effect(w: Unit, source: String) -> bool:
	for e in w.effects:
		if str((e as Dictionary).get("source", "")) == source:
			return true
	return false


func _count_type(k: Kingdom, type_id: String) -> int:
	var n := 0
	for w in k.units:
		if (w as Unit).type_id == type_id and (w as Unit).is_alive():
			n += 1
	return n


## Ein Feind (KI-Reich) direkt neben dem Helden, sichtbar
func _enemy_near(r: Node, u: Unit) -> Unit:
	var g: Node = r.game
	var foe: Kingdom = (g.ai_system.get_ai_kingdoms() as Array)[0]
	var def := DataDB.get_unit_for_tier(foe.faction_id, "elite")
	var w: Unit = g.unit_system.spawn_unit(foe, str(def["id"]), u.position + Vector2(90, 0))
	w.command = "hold"
	w.command_pos = w.position
	return w


func _fulfil(r: Node, req: Dictionary) -> void:
	var g: Node = r.game
	var k: Kingdom = g.player
	match str(req.get("type", "")):
		"research":
			k.researched[Requirements.research_id(req, k)] = true
		"kills":
			k.stats["kills"] = maxi(int(k.stats.get("kills", 0)), int(req.get("count", 1)))
		"lairs":
			k.stats["lairs_destroyed"] = maxi(int(k.stats.get("lairs_destroyed", 0)), int(req.get("count", 1)))
		"castle_level":
			while k.castle.level < int(req.get("min", 1)):
				k.castle.upgrading = true
				k.castle.complete_upgrade()
		"building":
			var bid := str(req.get("building", ""))
			var level := int(req.get("level", 1))
			if BuildingSystem.count_of(k, bid, level) == 0:
				var b := _place(r, bid)
				while b != null and b.level < level:
					b.upgrading = true
					b.complete_upgrade()


func _place(r: Node, id: String) -> Building:
	var g: Node = r.game
	var def := DataDB.get_building(id)
	var k: Kingdom = g.player
	var bs: BuildingSystem = g.building_system
	for res in DataDB.resources:
		k.resources[str(res["id"])] = maxf(k.get_amount(str(res["id"])), 2000.0)
	for unlock_id in def.get("requires", []):
		k.unlocks[str(unlock_id)] = true
	# Vorausgesetzte Gebäude zuerst (z. B. Kaserne vor der Heldenhalle)
	for bid in def.get("requires_buildings", []):
		if bs.count_buildings(k, str(bid), true) == 0:
			_place(r, str(bid))
	var center: Vector2i = g.world.world_to_cell(k.castle.get_center())
	var size: Vector2i = def.get("size", Vector2i(2, 2))
	for rr in range(6, 26):
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				if absi(dx) != rr and absi(dy) != rr:
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
	var c0 := center + Vector2i(8, 0)
	print("[smoke] Helden: kein Platz für %s (Beispiel %s: %s)" % [id, str(c0), bs.can_place(def, c0, k)])
	return null
