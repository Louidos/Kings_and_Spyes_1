## Rauchtest Dörfer und Reiche wachsen (diplomacy.json village.growth, worldgen.json villages.size,
## ai.json start_bonus): neue Dörfer haben 4–7 Hütten, im Frieden wächst ein Dorf in 30 Spielminuten
## sichtbar (Hütten, Bewohner, Milizplätze, ab einer Grösse ein Turm), im Krieg nicht; KI-Reiche
## starten mit mehr Bewohnern und Gebäuden; Dorfgrösse und Hütten überstehen Speichern und Laden.
extends RefCounted

const TOPIC := "Dörfer"


func run(r: Node) -> void:
	var g: Node = r.game
	var vs: VillageSystem = g.village_system
	var villages: Array = vs.get_villages()
	var sizes: Array = []
	var huts_ok := true
	for village in villages:
		var vrec := vs.get_record(village)
		sizes.append(int(vrec["size"]))
		huts_ok = huts_ok and (vrec["hut_uids"] as Array).size() == int(vrec["size"])
	var range_cfg: Array = DataDB.worldgen.get("villages", {}).get("size", [4, 7])
	r.check(TOPIC, not sizes.is_empty() and sizes.min() >= int(range_cfg[0]) and sizes.max() <= int(range_cfg[-1]) and huts_ok,
			"Neue Dörfer mit %s Hütten (alle Hütten stehen)" % str(sizes))
	# KI-Reich: Startvorsprung
	var ai: Array = g.ai_system.get_ai_kingdoms()
	if not ai.is_empty():
		var k: Kingdom = ai[0]
		var p: Kingdom = g.player
		var bonus: Dictionary = DataDB.ai("start_bonus", {})
		r.check(TOPIC, k.get_population() >= p.get_population() + int(bonus.get("villagers", 0))
				and k.buildings.size() >= p.buildings.size() + (bonus.get("buildings", []) as Array).size(),
				"KI-Reich startet grösser: %d Bewohner, %d Gebäude (Spieler %d, %d)" % [k.get_population(), k.buildings.size(),
				p.get_population(), p.buildings.size()])
	# Wachstum im Frieden: 30 Spielminuten in Schritten von 10 s (dieselbe Funktion wie im Spiel)
	var v: Kingdom = villages[0]
	var rec := vs.get_record(v)
	var size0 := int(rec["size"])
	var pop0 := int(rec["population"])
	var target0 := vs.get_militia_target(v)
	var buildings0 := v.buildings.size()
	var now := GameClock.game_time + float(DataDB.diplo("village.growth.attack_pause_seconds", 900))
	rec["last_attacked"] = -1.0e9
	for i in 180:
		vs.tick_growth(v, rec, 10.0, now + i * 10.0)
	var grown := int(rec["size"]) - size0
	r.check(TOPIC, grown >= 2 and v.buildings.size() > buildings0 and int(rec["population"]) > pop0
			and (rec["hut_uids"] as Array).size() == int(rec["size"]),
			"%s nach 30 Minuten Frieden: %d → %d Hütten, %d → %d Bewohner, Milizplätze %d → %d, Gebäude %d → %d" % [
			v.display_name, size0, int(rec["size"]), pop0, int(rec["population"]), target0, vs.get_militia_target(v),
			buildings0, v.buildings.size()])
	var towers := 0
	for b in v.buildings:
		if str((b as Building).def.get("fortification", "")) == "tower":
			towers += 1
	var towers_at: Array = DataDB.diplo("village.growth.towers_at_size", [])
	r.check(TOPIC, towers_at.is_empty() or int(rec["size"]) < int(towers_at[0]) or towers >= 1,
			"Ab Grösse %s steht ein Wachturm (%d Türme bei %d Hütten)" % [str(towers_at), towers, int(rec["size"])])
	# Krieg hält das Wachstum an
	var w: Kingdom = villages[1]
	var wrec := vs.get_record(w)
	g.diplomacy_system.declare_war(g.player, w)
	var wsize := int(wrec["size"])
	for i in 180:
		vs.tick_growth(w, wrec, 10.0, now + i * 10.0)
	r.check(TOPIC, int(wrec["size"]) == wsize and vs.growth_rate(w, wrec, now) == 0.0, "%s im Krieg wächst nicht (%d Hütten)" % [w.display_name, wsize])
	# Speichern und Laden: Grösse und Hütten bleiben
	var vid := v.id
	var size_saved := int(rec["size"])
	var huts_saved := (rec["hut_uids"] as Array).duplicate()
	var err: String = await r.save_and_reload("smoke_villages")
	r.check(TOPIC, err.is_empty(), "Gespeichert und geladen %s" % err)
	var g2: Node = r.game
	var rec2: Dictionary = (g2.village_system as VillageSystem).get_record(g2.get_kingdom(vid))
	var huts_exist := true
	for uid in rec2.get("hut_uids", []):
		huts_exist = huts_exist and g2.find_by_uid(int(uid)) is Building
	r.check(TOPIC, int(rec2.get("size", 0)) == size_saved and rec2.get("hut_uids", []) == huts_saved and huts_exist,
			"Nach dem Laden: %d Hütten, alle Gebäude vorhanden" % int(rec2.get("size", 0)))
