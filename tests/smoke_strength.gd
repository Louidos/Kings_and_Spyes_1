## Rauchtest Stärke und Haltung (diplomacy.json strength_attitude): bei gleichem Heer steigt der
## Ruf bei einem freundlichen Dorf ("fühlt sich beschützt"), bei einem neutralen ändert er sich
## nicht, ein misstrauisches misstraut etwas mehr; eine Drohung senkt den Ruf weiterhin.
extends RefCounted

const TOPIC := "Stärke"


func run(r: Node) -> void:
	var g: Node = r.game
	var k: Kingdom = g.player
	var ds: DiplomacySystem = g.diplomacy_system
	var villages: Array = g.village_system.get_villages()
	if villages.size() < 3:
		r.check(TOPIC, false, "Mindestens drei Dörfer")
		return
	r.spawn_tier(k, "fighter", 10)
	var power := ds.army_power(k)
	r.check(TOPIC, power >= float(DataDB.diplo("strength_attitude.min_power", 30)), "Heer mit Stärke %d" % roundi(power))
	var friend: Kingdom = villages[0]
	var neutral: Kingdom = villages[1]
	var wary: Kingdom = villages[2]
	ds.debug_set_reputation(friend, k, 50.0)
	ds.debug_set_reputation(neutral, k, 0.0)
	ds.debug_set_reputation(wary, k, -30.0)
	var before := [ds.get_reputation(friend, k), ds.get_reputation(neutral, k), ds.get_reputation(wary, k)]
	ds.tick_strength_attitude()
	var after := [ds.get_reputation(friend, k), ds.get_reputation(neutral, k), ds.get_reputation(wary, k)]
	var reason := str(DataDB.diplo("strength_attitude.friendly_reason", ""))
	var hist: Array = ds.get_history(friend, k)
	r.check(TOPIC, float(after[0]) > float(before[0]) and not hist.is_empty() and str((hist[-1] as Dictionary)["reason"]) == reason,
			"Freundliches Dorf %s: Ruf %+.1f → %+.1f (%s)" % [friend.display_name, before[0], after[0], reason])
	r.check(TOPIC, is_equal_approx(float(after[1]), float(before[1])), "Neutrales Dorf %s: Ruf bleibt %+.1f" % [neutral.display_name, after[1]])
	var drop := float(before[2]) - float(after[2])
	r.check(TOPIC, drop > 0.0 and drop < float(after[0]) - float(before[0]),
			"Misstrauisches Dorf %s: Ruf sinkt leicht (−%.2f), weniger als der Gewinn beim Freund" % [wary.display_name, drop])
	# Verlauf: gleiche Gründe werden zusammengezählt (kein Fluten)
	var n := hist.size()
	ds.tick_strength_attitude()
	r.check(TOPIC, ds.get_history(friend, k).size() == n, "Verlauf fasst „%s“ zusammen" % reason)
	# Anzeige im Diplomatiefenster
	var text := DiplomacyPanel.strength_text(ds.strength_effect(friend, k))
	r.check(TOPIC, text.contains(reason) and text.contains("+"), "Diplomatiefenster: %s" % text)
	r.check(TOPIC, DiplomacyPanel.strength_text(ds.strength_effect(neutral, k)).contains("keine Wirkung"), "Neutral: keine Wirkung")
	# Taten machen weiter Angst: Drohung gegen das neutrale Dorf
	var rep := ds.get_reputation(neutral, k)
	ds.threaten(k, neutral)
	r.check(TOPIC, ds.get_reputation(neutral, k) < rep, "Drohung senkt den Ruf (%+.1f → %+.1f)" % [rep, ds.get_reputation(neutral, k)])
