## Rauchtest Dorfbewohner (VillageResidents, diplomacy.json village.residents): jedes neutrale Dorf hat
## sichtbare Bewohner (Zahl nach Einwohnern, höchstens max_visible), sie gehen tagsüber zur Arbeit und
## tragen Waren ins Dorfzentrum, schlafen nachts in den Hütten, fliehen bei Alarm ins Dorfzentrum und
## kommen danach wieder heraus; sie zählen nicht als Miliz, die Produktion bleibt gleich; ein gefallener
## Bewohner senkt die Einwohnerzahl und wird ersetzt; Speichern/Laden behält sie, Spielstände ohne
## Bewohner (1.2.x) bekommen sie im ersten Takt.
extends RefCounted

const TOPIC := "Bewohner"


func run(r: Node) -> void:
	var g: Node = r.game
	var vs: VillageSystem = g.village_system
	var dn: DayNightSystem = g.day_night_system
	var villages: Array = vs.get_villages()
	var counts: PackedStringArray = []
	var all_ok := not villages.is_empty()
	for village in villages:
		var vrec := vs.get_record(village)
		var res := vs.residents.get_residents(village)
		counts.append(str(res.size()))
		var militia_clean := true
		for m in vs.get_militia(village):
			militia_clean = militia_clean and not VillageResidents.is_resident(m)
		all_ok = all_ok and res.size() == VillageResidents.visible_target(vrec) and res.size() > 0 \
				and res.size() <= int(DataDB.diplo("village.residents.max_visible", 6)) and militia_clean
	r.check(TOPIC, all_ok, "Jedes Dorf hat Bewohner (%s), keiner zählt als Miliz" % ", ".join(counts))
	var v: Kingdom = villages[0]
	var rec: Dictionary = vs.get_record(v)
	var prod_before := vs.get_production(v)
	# Tagsüber: zur Arbeit, arbeiten, Ware ins Dorfzentrum tragen
	dn.debug_force_phase("day")
	var start := {}
	for u in vs.residents.get_residents(v):
		start[u.uid] = (u as Unit).position
	var seen := {}
	var carried := false
	for _i in 30:
		await r.wait_game_seconds(3.0)
		for e in rec["residents"]:
			seen[str(e["phase"])] = true
		for u in vs.residents.get_residents(v):
			if (u as Unit).carry_amount > 0.0:
				carried = true
	var moved := 0
	for u in vs.residents.get_residents(v):
		if start.has(u.uid) and (u as Unit).position.distance_to(start[u.uid]) > 64.0:
			moved += 1
	r.check(TOPIC, moved > 0 and seen.has("work") and seen.has("to_hall") and carried,
			"%s: %d Bewohner unterwegs, Abschnitte %s, Waren getragen: %s" % [v.display_name, moved,
			str(seen.keys()), str(carried)])
	r.check(TOPIC, vs.get_production(v) == prod_before, "Produktion unverändert: %s" % str(prod_before))
	# Auswahlfenster: Name, Dorf und Tätigkeit
	var first: Unit = vs.residents.get_residents(v)[0]
	var text := vs.residents.describe(first)
	g.selection.select([first])
	await r.get_tree().process_frame
	r.check(TOPIC, not first.custom_name.is_empty() and text.contains(v.display_name) and text.split("\n").size() >= 2,
			"Bewohner anklickbar: %s – %s" % [first.custom_name, text.replace("\n", " · ")])
	g.selection.clear()
	# Alarm: alle ins Dorfzentrum, danach wieder heraus
	var hall := vs.get_hall(v)
	# Der Alarm hält, solange er immer wieder ausgelöst wird (sonst endet er nach alarm_calm_seconds)
	for _i in 8:
		vs.raise_alarm(v, g.wild, vs.get_center(v), false)
		await r.wait_game_seconds(3.0)
	var sheltered := 0
	for u in vs.residents.get_residents(v):
		if (u as Unit).inside == hall:
			sheltered += 1
	var total := vs.residents.get_residents(v).size()
	r.check(TOPIC, total > 0 and sheltered == total, "Alarm: %d/%d Bewohner im Dorfzentrum" % [sheltered, total])
	await r.wait_game_seconds(float(DataDB.diplo("village.alarm_calm_seconds", 10)) + 8.0)
	var outside := 0
	for u in vs.residents.get_residents(v):
		if (u as Unit).inside == null:
			outside += 1
	r.check(TOPIC, float(rec["alarm_until"]) == 0.0 and outside == total,
			"Nach dem Alarm: %d/%d Bewohner wieder draussen" % [outside, total])
	# Nachts in den Hütten
	dn.debug_force_phase("night")
	await r.wait_game_seconds(30.0)
	var home := 0
	for u in vs.residents.get_residents(v):
		if (u as Unit).inside != null:
			home += 1
	r.check(TOPIC, home == total, "Nachts: %d/%d Bewohner schlafen in Hütten" % [home, total])
	dn.debug_force_phase("day")
	await r.wait_game_seconds(6.0)
	# Ein Bewohner fällt: ein Einwohner weniger, später ersetzt
	var pop0 := int(rec["population"])
	var victim: Unit = vs.residents.get_residents(v)[0]
	g.combat_system.apply_damage(victim, 9999.0)
	await r.wait_game_seconds(2.0)
	var pop1 := int(rec["population"])
	var n1 := vs.residents.get_residents(v).size()
	vs.residents.tick(v, rec, float(DataDB.diplo("village.residents.replace_seconds", 120)) + 1.0, GameClock.game_time, false)
	r.check(TOPIC, pop1 == pop0 - 1 and int(rec["population"]) == pop0 and vs.residents.get_residents(v).size() == total,
			"Bewohner gefallen: Einwohner %d → %d → %d (ersetzt), sichtbar %d → %d" % [pop0, pop1,
			int(rec["population"]), n1, vs.residents.get_residents(v).size()])
	# Speichern und Laden: dieselben Bewohner; ein zweites Dorf wie aus 1.2.x (ohne Bewohner)
	var vid := v.id
	var uids: Array = []
	for e in rec["residents"]:
		uids.append(int(e["uid"]))
	uids.sort()
	var old: Kingdom = villages[1]
	var orec := vs.get_record(old)
	vs.residents.remove_all(old, orec)
	for key in ["residents", "residents_seeded", "resident_timer", "resident_lost", "resident_seq"]:
		orec.erase(key)
	var old_id := old.id
	var err: String = await r.save_and_reload("smoke_residents")
	r.check(TOPIC, err.is_empty(), "Gespeichert und geladen %s" % err)
	g = r.game
	vs = g.village_system
	var v2: Kingdom = g.get_kingdom(vid)
	var uids2: Array = []
	for u in vs.residents.get_residents(v2):
		uids2.append(u.uid)
	uids2.sort()
	r.check(TOPIC, uids2 == uids, "Nach dem Laden: %d Bewohner, dieselben wie vorher" % uids2.size())
	await r.wait_game_seconds(3.0)
	var old2: Kingdom = g.get_kingdom(old_id)
	var n_old := vs.residents.get_residents(old2).size()
	r.check(TOPIC, n_old == VillageResidents.visible_target(vs.get_record(old2)) and n_old > 0,
			"Dorf aus altem Spielstand bekommt %d Bewohner" % n_old)
	(g.day_night_system as DayNightSystem).debug_force_phase("")
