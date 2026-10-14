## MessengerSystem
##
## Boten (Phase 6): Wird ein Dorf von einem Reich angegriffen, schickt es (mit
## Abklingzeit) einen Boten los – zum nächsten Reich der Gegenfraktion des
## Angreifers (ab Phase 7 die KI-Reiche), sonst zum nächsten befreundeten Dorf
## in Reichweite. Boten sind sichtbare, schnelle, schwache Einheiten mit dem
## Befehl "travel"; sie kämpfen nie und sprinten vor Feinden davon.
## Kommt ein Bote an, steigt der Ruf beim Empfänger-Reich bzw. sinkt der Ruf des
## Angreifers beim gewarnten Dorf. Wird er abgefangen (getötet), kommt die
## Nachricht nicht an und der Ruf des Absenders gegenüber dem Täter sinkt etwas.
##
## Zustand: messengers (Bote-uid -> Datensatz), cooldown_until, stats.
## Laufzeit: _pending (wartende Meldungen und Ankünfte), _tick_acc.
class_name MessengerSystem
extends Node

## Ein Bote wurde losgeschickt
signal messenger_sent(messenger: Unit, sender: Kingdom, receiver: Kingdom, about: Kingdom)
## Ein Bote ist angekommen (kind z. B. "attack_report")
signal messenger_arrived(sender: Kingdom, receiver: Kingdom, about: Kingdom, kind: String)
## Ein Bote wurde abgefangen (killer: Reich, das ihn getötet hat)
signal messenger_intercepted(sender: Kingdom, killer: Kingdom, about: Kingdom)

var game: Node
var world: WorldData

## Bote-uid -> {"uid", "sender_id", "receiver_id", "about_id", "kind", "dest": Vector2, "sent_at",
##   "sprint_ready", "retries", "seen", "returning"}
var messengers: Dictionary = {}
## Absender-id -> Spielzeit, ab der er wieder einen Boten schicken darf
var cooldown_until: Dictionary = {}
## Statistik
var stats := {"sent": 0, "arrived": 0, "intercepted": 0, "lost": 0}

## Wartende Aufgaben: ["send", Dorf-id, Angreifer-id, pos], ["arrive", uid], ["retry", uid]
var _pending: Array = []
var _tick_acc := 0.0
var _ts := 64.0


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_ts = float(world.tile_size)
	GameClock.sim_tick.connect(_on_sim_tick)
	game.combat_system.kingdom_attacked.connect(_on_kingdom_attacked)
	game.combat_system.unit_died.connect(_on_unit_died)
	game.command_system.command_finished.connect(_on_command_finished)
	game.unit_system.unit_removed.connect(_on_unit_removed)


# ---------------------------------------------------------------------------
# Öffentlich
# ---------------------------------------------------------------------------

## Darf das Reich gerade einen Boten schicken? (selbstständiges Dorf, Abklingzeit
## vorbei, kein eigener Bote unterwegs; ab Phase 7 auch Reiche)
func can_send(sender: Kingdom) -> bool:
	if sender == null or not game.village_system.is_village(sender):
		return false
	if GameClock.game_time < float(cooldown_until.get(sender.id, -1.0e9)):
		return false
	for uid in messengers:
		if int(messengers[uid]["sender_id"]) == sender.id:
			return false
	return true


## Empfänger für eine Meldung über `about`:
## 1. nächstes Reich der Gegenfraktion von about (Spieler/KI, nicht besiegt, mit Burg)
## 2. sonst nächstes andere selbstständige Dorf (nicht im Krieg mit dem Absender) in Reichweite
## 3. sonst null (kein Bote)
func pick_receiver(sender: Kingdom, about: Kingdom) -> Kingdom:
	if sender == null:
		return null
	var origin: Vector2 = game.village_system.get_center(sender)
	var opposite := ""
	if about != null:
		match about.faction_id:
			"good":
				opposite = "evil"
			"evil":
				opposite = "good"
	var best: Kingdom = null
	var best_d := INF
	if not opposite.is_empty():
		for k in game.kingdoms:
			if k == about or k == sender or k.defeated or k.faction_id != opposite:
				continue
			if (k.controller != "ai" and k.controller != "player") or not is_instance_valid(k.castle):
				continue
			var d: float = origin.distance_to(k.castle.get_center())
			if d < best_d:
				best_d = d
				best = k
	if best != null:
		return best
	var max_d := float(DataDB.diplo("messenger.max_village_distance", 120)) * _ts
	for w in game.village_system.get_villages():
		if w == sender or w == about or game.are_hostile(w, sender):
			continue
		var d: float = origin.distance_to(game.village_system.get_center(w))
		if d <= max_d and d < best_d:
			best_d = d
			best = w
	return best


## Schickt einen Boten los (vom Ort origin) zum Empfänger. Gibt den Boten zurück (null = keiner).
func send_messenger(sender: Kingdom, origin: Vector2, receiver: Kingdom, about: Kingdom,
		kind: String = "attack_report") -> Unit:
	if sender == null or receiver == null or receiver == sender:
		return null
	var dest := _destination(receiver, origin)
	var u: Unit = game.unit_system.spawn_unit(sender, str(DataDB.diplo("messenger.unit", "messenger")), origin)
	if u == null:
		return null
	var now := GameClock.game_time
	messengers[u.uid] = {"uid": u.uid, "sender_id": sender.id, "receiver_id": receiver.id,
			"about_id": about.id if about != null else 0, "kind": kind, "dest": dest, "sent_at": now,
			"sprint_ready": 0.0, "retries": 0, "seen": false, "returning": false}
	_travel(u, dest)
	stats["sent"] = int(stats["sent"]) + 1
	messenger_sent.emit(u, sender, receiver, about)
	if about != null:
		about.notify("Ein Bote aus %s eilt zu %s – fange ihn ab!" % [sender.display_name, receiver.display_name],
				"warning", u.position)
	return u


## Lebende Boten
func get_messengers() -> Array:
	var list: Array = []
	for uid in messengers:
		var u: Variant = game.find_by_uid(int(uid))
		if u is Unit and (u as Unit).is_alive():
			list.append(u)
	return list


## Datensatz eines Boten ({} wenn keiner)
func get_record(u: Unit) -> Dictionary:
	if u == null:
		return {}
	return messengers.get(u.uid, {})


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	if not _pending.is_empty():
		_process_pending()
	_tick_acc += dt
	var interval := maxf(float(DataDB.diplo("messenger.tick_seconds", 0.5)), 0.1)
	if _tick_acc < interval:
		return
	_tick_acc = 0.0
	if messengers.is_empty():
		return
	var now := GameClock.game_time
	var flee := float(DataDB.diplo("messenger.flee_radius", 5)) * _ts
	var max_travel := float(DataDB.diplo("messenger.max_travel_seconds", 900))
	for uid in messengers.keys():
		var rec: Dictionary = messengers[uid]
		var found: Variant = game.find_by_uid(int(uid))
		if not (found is Unit) or not (found as Unit).is_alive():
			messengers.erase(uid)
			continue
		var u: Unit = found
		var sender: Kingdom = u.kingdom
		# Zu lange unterwegs: die Nachricht ist verloren
		if now - float(rec["sent_at"]) > max_travel:
			_lose(u)
			continue
		# Feinde in der Nähe: sprinten
		if now >= float(rec["sprint_ready"]) and _enemy_near(u, flee):
			rec["sprint_ready"] = now + float(DataDB.diplo("messenger.sprint_cooldown", 8))
			game.magic_system.add_unit_effect(u, {"id": "messenger_sprint", "key": "speed",
					"mult": float(DataDB.diplo("messenger.sprint_mult", 1.6)),
					"until": now + float(DataDB.diplo("messenger.sprint_seconds", 3)), "source": "messenger"})
		# Empfänger untergegangen: neues Ziel, sonst heimkehren
		if not bool(rec["returning"]):
			var receiver: Kingdom = game.get_kingdom(int(rec["receiver_id"]))
			if not _receiver_valid(receiver):
				var about: Kingdom = game.get_kingdom(int(rec["about_id"]))
				var other := pick_receiver(sender, about)
				if other != null and other != receiver:
					rec["receiver_id"] = other.id
					rec["dest"] = _destination(other, u.position)
				else:
					rec["returning"] = true
					rec["dest"] = game.village_system.get_center(sender)
				_travel(u, rec["dest"])
		# Fremder Bote im Gebiet eines Reichs: einmal melden
		if not bool(rec["seen"]):
			var owner_id := world.get_owner(world.world_to_cell(u.position))
			if owner_id != 0 and owner_id != sender.id:
				var host: Kingdom = game.get_kingdom(owner_id)
				if host != null and game.diplomacy_system.is_party(host):
					rec["seen"] = true
					var receiver_k: Kingdom = game.get_kingdom(int(rec["receiver_id"]))
					host.notify("Fremder Bote in deinem Gebiet (%s → %s)" % [sender.display_name,
							receiver_k.display_name if receiver_k != null else "?"], "info", u.position)


func _process_pending() -> void:
	var list := _pending
	_pending = []
	for entry in list:
		match str(entry[0]):
			"send":
				var sender: Kingdom = game.get_kingdom(int(entry[1]))
				var about: Kingdom = game.get_kingdom(int(entry[2]))
				if not can_send(sender):
					continue
				var receiver := pick_receiver(sender, about)
				if receiver == null:
					continue
				var hall: Building = game.village_system.get_hall(sender)
				var origin: Vector2 = hall.get_approach_point(_destination(receiver, hall.get_center())) if hall != null \
						else game.village_system.get_center(sender)
				if send_messenger(sender, origin, receiver, about) != null:
					cooldown_until[sender.id] = GameClock.game_time + float(DataDB.diplo("messenger.cooldown", 90))
			"arrive":
				var found: Variant = game.find_by_uid(int(entry[1]))
				if found is Unit and messengers.has(int(entry[1])):
					_on_arrival(found as Unit)
			"retry":
				var found_r: Variant = game.find_by_uid(int(entry[1]))
				if found_r is Unit and messengers.has(int(entry[1])):
					_retry(found_r as Unit)


## Am Ziel angekommen: zustellen (oder heimgekehrt: verschwinden)
func _on_arrival(u: Unit) -> void:
	var rec: Dictionary = messengers[u.uid]
	var dest: Vector2 = rec["dest"]
	if u.position.distance_to(dest) > float(DataDB.diplo("messenger.arrival_radius", 3)) * _ts:
		_retry(u)
		return
	if bool(rec["returning"]):
		_lose(u)
		return
	_deliver(rec, u)


## Kein Weg oder zu weit vom Ziel: erneut versuchen (bis retry_limit), sonst verloren
func _retry(u: Unit) -> void:
	var rec: Dictionary = messengers[u.uid]
	rec["retries"] = int(rec["retries"]) + 1
	if int(rec["retries"]) > int(DataDB.diplo("messenger.retry_limit", 3)):
		_lose(u)
		return
	var cell: Vector2i = game.nav.nearest_free(world.world_to_cell(rec["dest"]), 4)
	if cell.x >= 0:
		rec["dest"] = world.cell_to_world(cell)
	_travel(u, rec["dest"])


## Nachricht zustellen: Reich -> Ruf beim Absender steigt, Reich erfährt vom Angreifer;
## Dorf -> Ruf des Angreifers sinkt dort, das Dorf ist gewarnt.
func _deliver(rec: Dictionary, u: Unit) -> void:
	var sender: Kingdom = game.get_kingdom(int(rec["sender_id"]))
	var receiver: Kingdom = game.get_kingdom(int(rec["receiver_id"]))
	var about: Kingdom = game.get_kingdom(int(rec["about_id"]))
	var ds: DiplomacySystem = game.diplomacy_system
	var vs: VillageSystem = game.village_system
	if receiver != null and not receiver.defeated:
		if vs.is_village_kingdom(receiver):
			if about != null and vs.is_village(receiver):
				ds.change_reputation(receiver, about, float(DataDB.diplo("events.messenger_report", -10)),
						"Bote aus %s" % sender.display_name)
				vs.raise_alarm(receiver, about, vs.get_center(receiver), false)
				about.notify("Der Bote aus %s hat %s erreicht (Ruf dort %d)." % [sender.display_name, receiver.display_name,
						roundi(ds.get_reputation(receiver, about))], "warning", u.position)
		else:
			if sender != null and vs.is_village(sender):
				ds.change_reputation(sender, receiver, float(DataDB.diplo("events.messenger_arrival_bonus", 5)), "Bote empfangen")
			if about != null:
				ds.report_aggression(receiver, about, sender)
				receiver.notify("Bote aus %s: %s hat das Dorf angegriffen." % [sender.display_name, about.display_name],
						"good", u.position)
	stats["arrived"] = int(stats["arrived"]) + 1
	messengers.erase(u.uid)
	messenger_arrived.emit(sender, receiver, about, str(rec["kind"]))
	game.unit_system.remove_unit(u)


## Bote verschwindet ohne Zustellung
func _lose(u: Unit) -> void:
	messengers.erase(u.uid)
	stats["lost"] = int(stats["lost"]) + 1
	game.unit_system.remove_unit(u)


## Zielpunkt beim Empfänger: Anfahrpunkt der Burg bzw. des Dorfzentrums
func _destination(receiver: Kingdom, from_pos: Vector2) -> Vector2:
	if game.village_system.is_village_kingdom(receiver):
		var hall: Building = game.village_system.get_hall(receiver)
		if hall != null:
			return hall.get_approach_point(from_pos)
		return game.village_system.get_center(receiver)
	if is_instance_valid(receiver.castle):
		return receiver.castle.get_approach_point(from_pos)
	return from_pos


func _receiver_valid(k: Kingdom) -> bool:
	if k == null or k.defeated:
		return false
	if game.village_system.is_village_kingdom(k):
		return game.village_system.is_village(k)
	return is_instance_valid(k.castle)


func _travel(u: Unit, dest: Vector2) -> void:
	u.order_id += 1
	u.follow_leader = null
	u.command = "travel"
	u.command_pos = dest
	u.target = null
	game.unit_system.move_to(u, dest)


## Feind des Absenders (sichtbar, lebend) im Umkreis radius (Pixel)?
func _enemy_near(u: Unit, radius: float) -> bool:
	var index: SpatialIndex = game.combat_system.index
	for kid in index.kingdom_ids():
		if int(kid) == u.kingdom.id:
			continue
		var other: Kingdom = game.get_kingdom(int(kid))
		if other == null or not game.are_hostile(u.kingdom, other):
			continue
		for v in index.query_kingdom(u.position, radius, int(kid)):
			if v.hp > 0.0 and v.attack > 0.0:
				return true
	return false


# ---------------------------------------------------------------------------
# Signale
# ---------------------------------------------------------------------------

## Angriff auf ein Dorf durch ein Reich (keine Monster): Bote vormerken
func _on_kingdom_attacked(victim: Kingdom, attacker: Kingdom, pos: Vector2) -> void:
	if attacker == null or attacker.controller == "wild" or attacker.controller == "neutral":
		return
	if not can_send(victim):
		return
	for entry in _pending:
		if str(entry[0]) == "send" and int(entry[1]) == victim.id:
			return
	_pending.append(["send", victim.id, attacker.id, pos])


func _on_command_finished(u: Unit, cmd: String, ok: bool) -> void:
	if cmd != "travel" or not messengers.has(u.uid):
		return
	_pending.append(["arrive" if ok else "retry", u.uid])


## Bote getötet: abgefangen (durch ein Reich) bzw. verloren (Monster)
func _on_unit_died(u: Unit, killer: Kingdom) -> void:
	if not messengers.has(u.uid):
		return
	var rec: Dictionary = messengers[u.uid]
	messengers.erase(u.uid)
	var sender: Kingdom = game.get_kingdom(int(rec["sender_id"]))
	var about: Kingdom = game.get_kingdom(int(rec["about_id"]))
	var ds: DiplomacySystem = game.diplomacy_system
	if killer != null and ds.is_party(killer):
		stats["intercepted"] = int(stats["intercepted"]) + 1
		messenger_intercepted.emit(sender, killer, about)
		if sender != null and game.village_system.is_village_kingdom(sender):
			ds.change_reputation(sender, killer, float(DataDB.diplo("events.messenger_killed", -4)), "Bote getötet")
		killer.notify("Bote abgefangen – die Nachricht kommt nicht an.", "good", u.position)
	else:
		stats["lost"] = int(stats["lost"]) + 1


## Bote auf andere Weise entfernt (z. B. Eroberung): Datensatz aufräumen
func _on_unit_removed(u: Unit) -> void:
	if messengers.erase(u.uid):
		stats["lost"] = int(stats["lost"]) + 1


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"messengers": messengers.duplicate(true), "cooldown_until": cooldown_until.duplicate(),
			"stats": stats.duplicate(), "pending": _pending.duplicate(true), "tick_acc": _tick_acc}


func from_dict(d: Dictionary) -> void:
	messengers = (d.get("messengers", {}) as Dictionary).duplicate(true)
	cooldown_until = (d.get("cooldown_until", {}) as Dictionary).duplicate()
	var s: Dictionary = d.get("stats", {})
	for key in stats:
		stats[key] = int(s.get(key, 0))
	_pending = (d.get("pending", []) as Array).duplicate(true)
	_tick_acc = float(d.get("tick_acc", 0.0))


## Nach dem Laden: Boten ohne Weg wieder auf den Weg schicken. Wer unterwegs ist (SaveGame stellt
## den Weg wieder her) oder gerade angekommen ist (Ankunft in _pending), bleibt unverändert.
func rebuild_runtime() -> void:
	var arriving := {}
	for entry in _pending:
		if str(entry[0]) != "send":
			arriving[int(entry[1])] = true
	for uid in messengers.keys():
		var found: Variant = game.find_by_uid(int(uid))
		if not (found is Unit):
			messengers.erase(uid)
			continue
		var u: Unit = found
		if arriving.has(u.uid) or (u.command == "travel" and (u.moving or u.path_pending)):
			continue
		_travel(u, messengers[uid]["dest"])
