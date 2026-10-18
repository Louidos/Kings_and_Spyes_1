## Rauchtest Dorf-Baustellen (diplomacy.json village.growth.build_seconds, builders, extras_at_size):
## Wächst ein Dorf, entsteht erst eine Baustelle; Bewohner bauen sichtbar daran, die Grösse, Einwohner
## und Milizplätze steigen erst bei Fertigstellung; bei Alarm ruht der Bau; Speichern und Laden setzt
## ihn fort; eine Baustelle lässt sich zerstören; grössere Dörfer haben Brunnen, Feld und Werkstatt und
## die Bewohner arbeiten dort.
extends RefCounted

const TOPIC := "Baustellen"


func run(r: Node) -> void:
	var g: Node = r.game
	var vs: VillageSystem = g.village_system
	(g.day_night_system as DayNightSystem).debug_force_phase("day")
	var villages: Array = vs.get_villages()
	# Zusatzgebäude neuer Dörfer nach ihrer Grösse
	var extras_ok := true
	var extras_text: PackedStringArray = []
	for village in villages:
		var vrec := vs.get_record(village)
		var due := 0
		for e in DataDB.diplo("village.growth.extras_at_size", []):
			if int(vrec["size"]) >= int(e["size"]):
				due += 1
		extras_ok = extras_ok and (vrec.get("extra_uids", []) as Array).size() == due
		extras_text.append("%d Hütten: %d" % [int(vrec["size"]), (vrec.get("extra_uids", []) as Array).size()])
	r.check(TOPIC, extras_ok, "Neue Dörfer mit Zusatzgebäuden nach Grösse (%s)" % ", ".join(extras_text))
	# Bewohner arbeiten an Brunnen und Werkstatt (Tätigkeit wird mit Gewicht gewählt)
	var with_extra: Kingdom = null
	for village in villages:
		if not (vs.get_record(village).get("extra_uids", []) as Array).is_empty():
			with_extra = village
			break
	if with_extra != null:
		var picks := {}
		for _i in 300:
			var t: String = vs.residents._pick_task(with_extra, vs.get_record(with_extra))
			picks[t] = int(picks.get(t, 0)) + 1
		r.check(TOPIC, picks.has("village_well"), "Bewohner von %s arbeiten auch am Brunnen: %s" % [with_extra.display_name,
				str(picks)])
	# Wachstum: erst eine Baustelle (kleinstes Dorf ohne fällige Türme oder Zusatzgebäude)
	var v: Kingdom = villages[0]
	for village in villages:
		if int(vs.get_record(village)["size"]) < int(vs.get_record(v)["size"]):
			v = village
	var rec := vs.get_record(v)
	var size0 := int(rec["size"])
	var pop0 := int(rec["population"])
	var target0 := vs.get_militia_target(v)
	var huts0 := (rec["hut_uids"] as Array).size()
	rec["last_attacked"] = -1.0e9
	rec["growth"] = 0.999
	vs.tick_growth(v, rec, 10.0, GameClock.game_time)
	var sites := vs.get_sites(v)
	var site: Building = sites[0] if not sites.is_empty() else null
	r.check(TOPIC, site != null and not site.constructed and int(rec["size"]) == size0 and int(rec["population"]) == pop0
			and vs.get_militia_target(v) == target0 and (rec["hut_uids"] as Array).size() == huts0,
			"%s: Baustelle %s, Grösse %d und Milizplätze %d noch unverändert" % [v.display_name,
			site.get_display_name() if site != null else "–", int(rec["size"]), vs.get_militia_target(v)])
	if site == null:
		return
	var site_uid := site.uid
	await r.wait_game_seconds(30.0)
	var builders := 0
	for e in rec["residents"]:
		if str(e["phase"]) == "build" and int(e.get("site_uid", 0)) == site_uid:
			builders += 1
	var p1 := site.progress
	r.check(TOPIC, builders >= 1 and builders <= int(DataDB.diplo("village.growth.builders", 2)) and p1 > 0.0
			and not site.constructed and int(rec["size"]) == size0,
			"%d Bewohner bauen, Fortschritt %d %% (Bauzeit %d s)" % [builders, roundi(site.get_progress_ratio() * 100.0),
			roundi(site.get_build_time())])
	# Alarm: der Bau ruht
	for _i in 2:
		vs.raise_alarm(v, g.wild, vs.get_center(v), false)
		await r.wait_game_seconds(3.0)
	var p2 := site.progress
	for _i in 5:
		vs.raise_alarm(v, g.wild, vs.get_center(v), false)
		await r.wait_game_seconds(3.0)
	var p3 := site.progress
	r.check(TOPIC, absf(p3 - p2) < 0.01, "Bei Alarm ruht der Bau (%.1f → %.1f)" % [p2, p3])
	await r.wait_game_seconds(float(DataDB.diplo("village.alarm_calm_seconds", 10)) + 2.0)
	# Speichern während der Baustelle, Laden: Bau läuft weiter
	var vid := v.id
	var build_time := site.get_build_time()
	var p_saved := site.progress
	var err: String = await r.save_and_reload("smoke_sites")
	r.check(TOPIC, err.is_empty(), "Gespeichert und geladen %s" % err)
	g = r.game
	vs = g.village_system
	(g.day_night_system as DayNightSystem).debug_force_phase("day")
	v = g.get_kingdom(vid)
	rec = vs.get_record(v)
	var loaded: Variant = g.find_by_uid(site_uid)
	r.check(TOPIC, loaded is Building and not (loaded as Building).constructed and (loaded as Building).progress >= p_saved - 0.01
			and (rec["sites"] as Array).size() == 1 and absf((loaded as Building).get_build_time() - build_time) < 0.01,
			"Nach dem Laden: Baustelle mit %s Fortschritt (gespeichert %d %%)" % [(str(roundi((loaded as Building).get_progress_ratio()
			* 100.0)) + " %") if loaded is Building else "–", roundi(p_saved / build_time * 100.0)])
	var waited := 0.0
	while waited < 240.0 and not (rec["sites"] as Array).is_empty():
		await r.wait_game_seconds(5.0)
		waited += 5.0
	r.check(TOPIC, (rec["sites"] as Array).is_empty() and int(rec["size"]) == size0 + 1
			and int(rec["population"]) >= pop0 + int(DataDB.diplo("village.population_per_size", 4)) - 1
			and (rec["hut_uids"] as Array).has(site_uid) and vs.get_militia_target(v) >= target0,
			"Fertig nach weiteren %d s: Grösse %d → %d, Einwohner %d → %d, Milizplätze %d → %d" % [roundi(waited), size0,
			int(rec["size"]), pop0, int(rec["population"]), target0, vs.get_militia_target(v)])
	# Eine angefangene Baustelle lässt sich zerstören: das Dorf wächst nicht
	var size1 := int(rec["size"])
	rec["last_attacked"] = -1.0e9
	rec["growth"] = 0.999
	(rec["sites"] as Array).clear()
	vs.tick_growth(v, rec, 10.0, GameClock.game_time)
	var victim_sites := vs.get_sites(v)
	if not victim_sites.is_empty():
		var doomed: Building = victim_sites[0]
		var doomed_uid := doomed.uid
		g.combat_system._destroy_building(doomed, null)
		await r.wait_game_seconds(2.0)
		r.check(TOPIC, (rec["sites"] as Array).is_empty() and int(rec["size"]) == size1
				and not (rec["hut_uids"] as Array).has(doomed_uid), "Zerstörte Baustelle: Dorf bleibt bei %d Hütten" % size1)
	(g.day_night_system as DayNightSystem).debug_force_phase("")
