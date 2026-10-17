## StationSystem
##
## Bündnisse (diplomacy.json station): Truppen bei einem verbündeten Dorf stationieren.
## Befehl "Bei Verbündetem stationieren" (Armeefenster, Diplomatiefenster): die Krieger
## marschieren kampfbereit zum Dorf und halten dort (Befehl "hold", Leine "guard" – sie
## greifen Angreifer in der Nähe selbstständig an). Unterhalt zahlt weiter das eigene Reich.
## Solange mindestens min_units am Dorf stehen, steigt der Ruf alle reputation_interval
## Sekunden (bis reputation_cap) und das Dorf leistet alle tribute_interval Sekunden eine
## kleine Abgabe aus seinen Waren. Stationierte Truppen zählen für die KI zur Verteidigung
## des Dorfs (guard_power) – das Dorf ist seltener Ziel von Angriffen.
## Hilferufe: Wird ein verbündetes Dorf angegriffen und stehen keine Truppen des Partners
## dort, ruft es um Hilfe (Annehmen = Truppen schicken, Ablehnen oder Verstreichen = Ruf sinkt).
## Truppenaustausch: Miliz des Dorfs anfordern (VillageSystem.dispatch_help zur eigenen Burg).
## Ein anderer Marschbefehl, "Zurückrufen" oder das Ende des Bündnisses beenden die
## Stationierung (die Truppen kehren zur Burg zurück). Die KI nutzt dieselben Funktionen.
## Zustand (gespeichert): stations, timers, help_calls, cooldowns. Laufzeit: _acc.
class_name StationSystem
extends Node

## Stationierungen eines Reichs bei einem Dorf haben sich geändert
signal stations_changed(kingdom: Kingdom, host: Kingdom)
## Hilferuf geöffnet oder beantwortet (state: "open", "accepted", "declined", "expired", "resolved",
## "ended" = Bündnis beendet)
signal help_call_changed(host: Kingdom, kingdom: Kingdom, state: String)

var game: Node
## uid -> {"kingdom_id", "host_id", "since", "arrived": bool}
var stations: Dictionary = {}
## "dorf:reich" -> {"next_rep": Spielzeit, "next_tribute": Spielzeit, "rep_total", "tribute_total": {Ware: Menge}}
var timers: Dictionary = {}
## "dorf:reich" -> {"host_id", "kingdom_id", "attacker_id", "until", "pos": Vector2}
var help_calls: Dictionary = {}
## "art:dorf:reich" -> Spielzeit, ab der es wieder geht (help, militia)
var cooldowns: Dictionary = {}

var _acc := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	GameClock.sim_tick.connect(_on_sim_tick)
	var ds: DiplomacySystem = game.diplomacy_system
	ds.treaty_changed.connect(_on_treaty_changed)
	ds.side_switched.connect(_on_side_switched)
	var vs: VillageSystem = game.village_system
	vs.village_alarm.connect(_on_village_alarm)
	vs.settlement_transferred.connect(_on_settlement_transferred)


static func cfg(key: String, default: Variant) -> Variant:
	return DataDB.diplo("station." + key, default)


static func pair(host: Kingdom, k: Kingdom) -> String:
	return "%d:%d" % [host.id, k.id]


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## "" = k darf bei host stationieren, sonst der Grund (Anzeige am gesperrten Knopf)
func host_reason(k: Kingdom, host: Kingdom) -> String:
	var vs: VillageSystem = game.village_system
	if k == null or host == null:
		return "Kein Ziel"
	if not vs.is_village(host):
		return "Nur bei verbündeten Dörfern möglich"
	if game.are_hostile(k, host):
		return "%s ist im Krieg mit dir" % host.display_name
	var ds: DiplomacySystem = game.diplomacy_system
	if ds.get_treaty_with(host, k) != "alliance":
		return "Kein Bündnis mit %s – Truppen lassen sich nur bei Verbündeten stationieren" % host.display_name
	return ""


## Krieger der Liste, die stationiert werden können (eigene, lebende Kämpfer, Helden und
## Heiler – ohne König, Späher, Spione und beschworene Einheiten)
static func eligible(k: Kingdom, units: Array) -> Array:
	var list: Array = []
	for u in units:
		if not (u is Unit) or not is_instance_valid(u):
			continue
		var unit: Unit = u
		if unit.kingdom != k or not unit.is_alive() or unit.expires_at >= 0.0 or unit.tier == "scout" or unit.tier == "spy":
			continue
		if unit.role == "combat" or unit.role == "hero" or unit.role == "support":
			list.append(unit)
	return list


## "" = die Einheiten können zu host, sonst der Grund
func can_station(k: Kingdom, units: Array, host: Kingdom) -> String:
	var reason := host_reason(k, host)
	if not reason.is_empty():
		return reason
	if eligible(k, units).is_empty():
		return "Keine Krieger ausgewählt"
	return ""


func is_stationed(u: Unit) -> bool:
	return u != null and stations.has(u.uid)


## Gastgeber einer stationierten Einheit (sonst null)
func get_host(u: Unit) -> Kingdom:
	if not is_stationed(u):
		return null
	return game.get_kingdom(int(stations[u.uid]["host_id"]))


## Lebende stationierte Einheiten von k bei host (k = null: aller Reiche)
func get_stationed(k: Kingdom, host: Kingdom) -> Array:
	var list: Array = []
	if host == null:
		return list
	for uid in stations:
		var rec: Dictionary = stations[uid]
		if int(rec["host_id"]) != host.id or (k != null and int(rec["kingdom_id"]) != k.id):
			continue
		var u: Variant = game.find_by_uid(int(uid))
		if u is Unit and is_instance_valid(u) and (u as Unit).is_alive():
			list.append(u)
	return list


## Davon am Dorf angekommen (im Umkreis Dorfradius + radius_extra)
func get_present(k: Kingdom, host: Kingdom) -> Array:
	var list: Array = []
	for u in get_stationed(k, host):
		if _is_present(u, host):
			list.append(u)
	return list


## Dörfer, bei denen k Truppen stationiert hat
func get_hosts(k: Kingdom) -> Array:
	var seen := {}
	var list: Array = []
	for uid in stations:
		var rec: Dictionary = stations[uid]
		if int(rec["kingdom_id"]) != k.id or seen.has(int(rec["host_id"])):
			continue
		seen[int(rec["host_id"])] = true
		var host: Kingdom = game.get_kingdom(int(rec["host_id"]))
		if host != null:
			list.append(host)
	return list


## Kampfkraft aller anwesenden fremden Truppen am Dorf (KI-Zielwahl: Verteidigung)
func guard_power(host: Kingdom) -> float:
	var total := 0.0
	for u in get_present(null, host):
		total += VillageSystem.unit_power(u)
	return total


## Ruf je reputation_interval durch n anwesende Krieger
static func reputation_gain(n: int) -> float:
	if n < int(cfg("min_units", 3)):
		return 0.0
	return minf(float(cfg("reputation_per_interval", 1.5)) + float(cfg("reputation_per_unit", 0.1)) * n,
			float(cfg("reputation_max_per_interval", 3.0)))


## Abgabe je tribute_interval durch n anwesende Krieger: {Ware: Menge} (Ware des Dorfs,
## von der es am meisten hat – aus seinen Handelswaren, sonst Nahrung)
func tribute_for(host: Kingdom, n: int) -> Dictionary:
	if n < int(cfg("min_units", 3)):
		return {}
	var goods: Dictionary = game.village_system.get_people(host).get("delivery", {}).get("give", {})
	var best := "food"
	var best_amount := host.get_amount("food")
	for res_id in goods:
		if host.get_amount(str(res_id)) > best_amount:
			best = str(res_id)
			best_amount = host.get_amount(best)
	var amount := minf(float(cfg("tribute_per_unit", 2.0)) * n, float(cfg("tribute_max", 30.0)))
	amount = floorf(minf(amount, best_amount))
	return {best: amount} if amount >= 1.0 else {}


## Kurzer Stand für das Diplomatiefenster: Anzahl, Wirkung, nächste Abgabe
func summary(k: Kingdom, host: Kingdom) -> Dictionary:
	var all := get_stationed(k, host)
	var present := get_present(k, host)
	var t: Dictionary = timers.get(pair(host, k), {})
	return {"stationed": all.size(), "present": present.size(), "power": guard_power_of(present),
			"reputation": reputation_gain(present.size()), "tribute": tribute_for(host, present.size()),
			"next_tribute": float(t.get("next_tribute", 0.0)), "rep_total": float(t.get("rep_total", 0.0)),
			"tribute_total": (t.get("tribute_total", {}) as Dictionary).duplicate()}


static func guard_power_of(units: Array) -> float:
	var total := 0.0
	for u in units:
		total += VillageSystem.unit_power(u)
	return total


## Gemeinsame Ziele: Reiche, die mit dem Dorf und mit k im Krieg sind (dazu der letzte Angreifer)
func shared_enemies(k: Kingdom, host: Kingdom) -> Array:
	var list: Array = []
	var ds: DiplomacySystem = game.diplomacy_system
	for other in game.kingdoms:
		var o: Kingdom = other
		if o == k or o == host or not ds.is_party(o):
			continue
		if game.are_hostile(host, o) and game.are_hostile(k, o):
			list.append(o)
	return list


## Offener Hilferuf von host an k (leer = keiner)
func get_help_call(host: Kingdom, k: Kingdom) -> Dictionary:
	return help_calls.get(pair(host, k), {})


## Alle offenen Hilferufe an k: [{"host", "attacker", "until"}]
func get_help_calls(k: Kingdom) -> Array:
	var list: Array = []
	for key in help_calls:
		var c: Dictionary = help_calls[key]
		if int(c["kingdom_id"]) != k.id:
			continue
		list.append({"host": game.get_kingdom(int(c["host_id"])), "attacker": game.get_kingdom(int(c["attacker_id"])),
				"until": float(c["until"])})
	return list


## "" = k kann Miliz von host anfordern, sonst der Grund
func militia_reason(k: Kingdom, host: Kingdom) -> String:
	var reason := host_reason(k, host)
	if not reason.is_empty():
		return reason.replace("Truppen lassen sich nur bei Verbündeten stationieren", "nur Verbündete schicken Miliz")
	var wait := float(cooldowns.get("militia:" + pair(host, k), 0.0)) - GameClock.game_time
	if wait > 0.0:
		return "Die Miliz ist erst vor Kurzem ausgerückt (wieder in %d s)" % ceili(wait)
	if game.village_system.get_militia(host).is_empty():
		return "%s hat gerade keine Miliz" % host.display_name
	if not is_instance_valid(k.castle):
		return "Keine Burg"
	return ""


# ---------------------------------------------------------------------------
# Befehle (Spieler und KI)
# ---------------------------------------------------------------------------

## Truppen zu host schicken und dort stationieren. "" = ok, sonst der Grund.
func station(k: Kingdom, units: Array, host: Kingdom) -> String:
	var reason := can_station(k, units, host)
	if not reason.is_empty():
		return reason
	var list := eligible(k, units)
	var vs: VillageSystem = game.village_system
	var center := vs.get_center(host)
	var hall := vs.get_hall(host)
	var from := Vector2.ZERO
	for u in list:
		from += (u as Unit).position / float(list.size())
	var post := hall.get_approach_point(from) if hall != null else center
	# Posten etwas vor dem Dorfzentrum, Richtung der ankommenden Truppen
	game.command_system.order_move(list, post, true, "circle")
	var now := GameClock.game_time
	var old_hosts := {}
	for u in list:
		var old: Dictionary = stations.get((u as Unit).uid, {})
		if not old.is_empty() and int(old["host_id"]) != host.id:
			old_hosts[int(old["host_id"])] = true
		stations[(u as Unit).uid] = {"kingdom_id": k.id, "host_id": host.id, "since": now, "arrived": false}
	# Vorher anderswo stationiert: dort aufräumen (Zähler, Fensteranzeige)
	for hid in old_hosts:
		var old_host: Kingdom = game.get_kingdom(int(hid))
		if old_host != null:
			if get_stationed(k, old_host).is_empty():
				timers.erase(pair(old_host, k))
			stations_changed.emit(k, old_host)
	var key := pair(host, k)
	if not timers.has(key):
		timers[key] = {"next_rep": now + float(cfg("reputation_interval", 120)),
				"next_tribute": now + float(cfg("tribute_interval", 300)), "rep_total": 0.0, "tribute_total": {}}
	# Ein offener Hilferuf ist damit angenommen
	if help_calls.has(key):
		_close_help(host, k, "accepted")
	k.notify("%d Krieger ziehen zu %s und schützen das Dorf." % [list.size(), host.display_name], "info", center)
	stations_changed.emit(k, host)
	return ""


## Alle Truppen von k bei host zurückrufen (zur Burg). Gibt die Anzahl zurück.
func recall(k: Kingdom, host: Kingdom, reason: String = "") -> int:
	var units := get_stationed(k, host)
	_forget(k, host)
	if not units.is_empty() and is_instance_valid(k.castle):
		game.command_system.order_gather(units)
	if not units.is_empty():
		var text := "%d Krieger kehren von %s zurück." % [units.size(), host.display_name]
		if not reason.is_empty():
			text = "%s: %s" % [reason, text]
		k.notify(text, "info" if reason.is_empty() else "warning", game.village_system.get_center(host))
	stations_changed.emit(k, host)
	return units.size()


## Einen Teil der Truppen von k bei host heimschicken (KI: Hilfstruppen nach dem Hilferuf).
## Gibt die Anzahl zurück.
func release(k: Kingdom, host: Kingdom, count: int) -> int:
	var units := get_stationed(k, host).slice(0, maxi(count, 0))
	if units.is_empty():
		return 0
	for u in units:
		stations.erase((u as Unit).uid)
	if is_instance_valid(k.castle):
		game.command_system.order_gather(units)
	if get_stationed(k, host).is_empty():
		timers.erase(pair(host, k))
	stations_changed.emit(k, host)
	return units.size()


## Hilferuf beantworten. accept: units (leer = nächstgelegene freie Krieger, höchstens
## help_units) ziehen hin. "" = ok, sonst der Grund.
func answer_help(k: Kingdom, host: Kingdom, accept: bool, units: Array = []) -> String:
	var key := pair(host, k)
	if not help_calls.has(key):
		return "Kein Hilferuf von %s" % host.display_name
	var ds: DiplomacySystem = game.diplomacy_system
	if not accept:
		_close_help(host, k, "declined")
		ds.change_reputation(host, k, float(cfg("help_decline_reputation", -4)), "Hilferuf abgelehnt")
		return ""
	var list := eligible(k, units)
	if list.is_empty():
		list = free_warriors(k, game.village_system.get_center(host), int(cfg("help_units", 6)))
	if list.is_empty():
		return "Keine freien Krieger"
	var err := station(k, list, host)
	if err.is_empty():
		ds.change_reputation(host, k, float(cfg("help_accept_reputation", 3)), "Hilferuf angenommen")
	return err


## Miliz des Dorfs zur eigenen Burg anfordern (Truppenaustausch). "" = ok, sonst der Grund.
func request_militia(k: Kingdom, host: Kingdom) -> String:
	var reason := militia_reason(k, host)
	if not reason.is_empty():
		return reason
	var vs: VillageSystem = game.village_system
	var cs: CommandSystem = game.command_system
	var pos := cs.castle_rally_point(k, vs.get_center(host))
	if vs.dispatch_help(host, pos, null) <= 0:
		return "Die Miliz von %s ist gerade unterwegs oder im Kampf" % host.display_name
	cooldowns["militia:" + pair(host, k)] = GameClock.game_time + float(cfg("militia_cooldown", 600))
	game.diplomacy_system.change_reputation(host, k, float(cfg("militia_reputation", -2)), "Miliz angefordert")
	k.notify("%s schickt dir Miliz zur Burg." % host.display_name, "good", pos)
	return ""


## Freie eigene Krieger (keine Befehle ausser Halten, nicht stationiert), die nächsten zu pos zuerst
func free_warriors(k: Kingdom, pos: Vector2, count: int) -> Array:
	var list: Array = []
	for u in game.command_system.get_warriors(k):
		var unit: Unit = u
		if is_stationed(unit) or unit.role == "king" or unit.tier == "scout" or unit.tier == "spy":
			continue
		if unit.command != "" and unit.command != "hold" and unit.command != "rest":
			continue
		if is_instance_valid(unit.target):
			continue
		list.append(unit)
	list.sort_custom(func(a: Unit, b: Unit) -> bool: return a.position.distance_to(pos) < b.position.distance_to(pos))
	return list.slice(0, maxi(count, 0))


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	_acc += dt
	var step := float(cfg("tick_seconds", 2))
	if _acc < step:
		return
	_acc = 0.0
	var now := GameClock.game_time
	_tick_units()
	_tick_effects(now)
	_tick_help(now)


## Tote, übergelaufene oder umbefehligte Einheiten austragen; Ankunft melden
func _tick_units() -> void:
	var vs: VillageSystem = game.village_system
	var changed := {}
	var arrived := {}
	for uid in stations.keys():
		var rec: Dictionary = stations[uid]
		var u: Variant = game.find_by_uid(int(uid))
		var host: Kingdom = game.get_kingdom(int(rec["host_id"]))
		var drop := not (u is Unit) or not is_instance_valid(u) or not (u as Unit).is_alive() or host == null \
				or (u as Unit).kingdom.id != int(rec["kingdom_id"]) or not vs.is_village(host)
		if not drop:
			var unit: Unit = u
			# Befehl weg vom Dorf (Marsch, Halten, Angriff mit erledigtem Ziel): Stationierung beendet.
			# Nur die Verfolgung eines lebenden Ziels darf kurz aus dem Umkreis führen.
			var post_tiles := vs.get_radius_tiles(host) + float(cfg("leave_extra", 12))
			var away := unit.command_pos.distance_to(vs.get_center(host)) > post_tiles * float(game.world.tile_size)
			var chasing := unit.command == "attack" and is_instance_valid(unit.target)
			drop = away and not chasing
			if not drop and not bool(rec["arrived"]) and _is_present(unit, host):
				rec["arrived"] = true
				arrived[pair(host, unit.kingdom)] = [unit.kingdom, host]
		if drop:
			stations.erase(uid)
			changed[str(rec["host_id"]) + ":" + str(rec["kingdom_id"])] = [int(rec["kingdom_id"]), int(rec["host_id"])]
	for key in arrived:
		var k: Kingdom = arrived[key][0]
		var host: Kingdom = arrived[key][1]
		if get_present(k, host).size() == get_stationed(k, host).size():
			k.notify("Deine Truppen sind bei %s angekommen und schützen das Dorf." % host.display_name, "good",
					vs.get_center(host))
	for key in changed:
		var k: Kingdom = game.get_kingdom(int(changed[key][0]))
		var host: Kingdom = game.get_kingdom(int(changed[key][1]))
		if k != null and host != null:
			if get_stationed(k, host).is_empty():
				timers.erase(pair(host, k))
			stations_changed.emit(k, host)


## Ruf und Abgaben je Dorf und Reich
func _tick_effects(now: float) -> void:
	var ds: DiplomacySystem = game.diplomacy_system
	var vs: VillageSystem = game.village_system
	for key in timers.keys():
		var t: Dictionary = timers[key]
		var parts := str(key).split(":")
		var host: Kingdom = game.get_kingdom(int(parts[0]))
		var k: Kingdom = game.get_kingdom(int(parts[1]))
		if host == null or k == null:
			timers.erase(key)
			continue
		var n := get_present(k, host).size()
		if now >= float(t["next_rep"]):
			t["next_rep"] = now + float(cfg("reputation_interval", 120))
			var gain := reputation_gain(n)
			var cap := float(cfg("reputation_cap", 75))
			gain = minf(gain, cap - ds.get_reputation(host, k))
			if gain > 0.0:
				ds._apply(host, k, gain, "Stationierte Truppen", true, true)
				t["rep_total"] = float(t["rep_total"]) + gain
		if now >= float(t["next_tribute"]):
			t["next_tribute"] = now + float(cfg("tribute_interval", 300))
			var tribute := tribute_for(host, n)
			if not tribute.is_empty() and host.spend(tribute):
				var totals: Dictionary = t["tribute_total"]
				for res_id in tribute:
					k.add_resource(str(res_id), float(tribute[res_id]))
					totals[res_id] = float(totals.get(res_id, 0.0)) + float(tribute[res_id])
				k.notify("%s dankt deinen Truppen: %s" % [host.display_name, DataDB.cost_to_text(tribute)], "good",
						vs.get_center(host))


## Hilferufe: erledigt, sobald Truppen da sind oder kein Feind mehr; Frist abgelaufen = Ruf sinkt
func _tick_help(now: float) -> void:
	var vs: VillageSystem = game.village_system
	for key in help_calls.keys():
		var c: Dictionary = help_calls[key]
		var host: Kingdom = game.get_kingdom(int(c["host_id"]))
		var k: Kingdom = game.get_kingdom(int(c["kingdom_id"]))
		if host == null or k == null or not vs.is_village(host):
			help_calls.erase(key)
			continue
		if game.diplomacy_system.get_treaty_with(host, k) != "alliance":
			_close_help(host, k, "ended")
			continue
		var center := vs.get_center(host)
		if not get_present(k, host).is_empty() or not vs.has_enemies_near(host, center, vs.get_radius_tiles(host) + 6.0):
			_close_help(host, k, "resolved")
		elif now >= float(c["until"]):
			_close_help(host, k, "expired")
			game.diplomacy_system.change_reputation(host, k, float(cfg("help_ignore_reputation", -2)), "Hilferuf überhört")


func _is_present(u: Unit, host: Kingdom) -> bool:
	var vs: VillageSystem = game.village_system
	var radius := (vs.get_radius_tiles(host) + float(cfg("radius_extra", 4))) * float(game.world.tile_size)
	return u.position.distance_to(vs.get_center(host)) <= radius


func _forget(k: Kingdom, host: Kingdom) -> void:
	for uid in stations.keys():
		var rec: Dictionary = stations[uid]
		if int(rec["kingdom_id"]) == k.id and int(rec["host_id"]) == host.id:
			stations.erase(uid)
	timers.erase(pair(host, k))


func _close_help(host: Kingdom, k: Kingdom, state: String) -> void:
	help_calls.erase(pair(host, k))
	help_call_changed.emit(host, k, state)


# ---------------------------------------------------------------------------
# Signale
# ---------------------------------------------------------------------------

## Bündnis beendet (oder anderer Vertrag): Truppen ziehen ab
func _on_treaty_changed(village: Kingdom, other: Kingdom, treaty_type: String) -> void:
	if village == null:
		return
	for k in _kingdoms_at(village):
		var kk: Kingdom = k
		if treaty_type == "alliance" and kk == other:
			continue
		if game.diplomacy_system.get_treaty_with(village, kk) != "alliance":
			recall(kk, village, "Bündnis mit %s beendet" % village.display_name)
	# Offene Hilferufe gelten nur, solange das Bündnis besteht
	for key in help_calls.keys():
		var c: Dictionary = help_calls[key]
		var kk: Kingdom = game.get_kingdom(int(c["kingdom_id"]))
		if int(c["host_id"]) == village.id and (kk == null or game.diplomacy_system.get_treaty_with(village, kk) != "alliance"):
			if kk != null:
				_close_help(village, kk, "ended")
			else:
				help_calls.erase(key)


func _on_side_switched(village: Kingdom, _new_ally: Kingdom, against: Kingdom) -> void:
	if village != null and against != null and not get_stationed(against, village).is_empty():
		recall(against, village, "%s hat die Seite gewechselt" % village.display_name)


func _on_settlement_transferred(from_kingdom: Kingdom, _to_kingdom: Kingdom, _reason: String) -> void:
	if from_kingdom == null:
		return
	for k in _kingdoms_at(from_kingdom):
		recall(k, from_kingdom, "%s ist kein freies Dorf mehr" % from_kingdom.display_name)


## Verbündetes Dorf angegriffen: Hilferuf an den Bündnispartner, wenn keine Truppen dort stehen
func _on_village_alarm(village: Kingdom, attacker: Kingdom, pos: Vector2) -> void:
	var ds: DiplomacySystem = game.diplomacy_system
	var t := ds.get_treaty(village)
	if t.is_empty() or str(t["type"]) != "alliance" or attacker == null:
		return
	var k: Kingdom = game.get_kingdom(int(t["partner_id"]))
	if k == null or k == attacker or not ds.is_party(k) or not get_present(k, village).is_empty():
		return
	# Nur echte Angriffe: Warnungen durch Boten (kein Feind vor Ort) rufen nicht um Hilfe
	var vs: VillageSystem = game.village_system
	if not vs.has_enemies_near(village, vs.get_center(village), vs.get_radius_tiles(village) + 6.0):
		return
	var key := pair(village, k)
	var now := GameClock.game_time
	if help_calls.has(key) or now < float(cooldowns.get("help:" + key, 0.0)):
		return
	var seconds := float(cfg("help_seconds", 120))
	help_calls[key] = {"host_id": village.id, "kingdom_id": k.id, "attacker_id": attacker.id, "until": now + seconds, "pos": pos}
	cooldowns["help:" + key] = now + float(cfg("help_cooldown", 300))
	help_call_changed.emit(village, k, "open")
	k.notify("Hilferuf: %s wird von %s angegriffen! Diplomatie → Bündnis: Truppen schicken (noch %d s)" % [
			village.display_name, attacker.display_name, roundi(seconds)], "danger", pos)


func _kingdoms_at(host: Kingdom) -> Array:
	var seen := {}
	var list: Array = []
	for uid in stations:
		var rec: Dictionary = stations[uid]
		if int(rec["host_id"]) != host.id or seen.has(int(rec["kingdom_id"])):
			continue
		seen[int(rec["kingdom_id"])] = true
		var k: Kingdom = game.get_kingdom(int(rec["kingdom_id"]))
		if k != null:
			list.append(k)
	return list


# ---------------------------------------------------------------------------
# Speichern
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"stations": stations.duplicate(true), "timers": timers.duplicate(true), "help_calls": help_calls.duplicate(true),
			"cooldowns": cooldowns.duplicate(), "acc": _acc}


func from_dict(d: Dictionary) -> void:
	stations.clear()
	var saved: Dictionary = d.get("stations", {})
	for uid in saved:
		var rec: Dictionary = (saved[uid] as Dictionary).duplicate(true)
		rec["kingdom_id"] = int(rec.get("kingdom_id", 0))
		rec["host_id"] = int(rec.get("host_id", 0))
		rec["arrived"] = bool(rec.get("arrived", false))
		stations[int(uid)] = rec
	timers = (d.get("timers", {}) as Dictionary).duplicate(true)
	help_calls.clear()
	var calls: Dictionary = d.get("help_calls", {})
	for key in calls:
		var c: Dictionary = (calls[key] as Dictionary).duplicate(true)
		var p: Variant = c.get("pos", Vector2.ZERO)
		c["pos"] = p if p is Vector2 else Vector2.ZERO
		help_calls[str(key)] = c
	cooldowns = (d.get("cooldowns", {}) as Dictionary).duplicate()
	_acc = float(d.get("acc", 0.0))


func rebuild_runtime() -> void:
	pass
