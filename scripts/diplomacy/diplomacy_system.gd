## DiplomacySystem
##
## Beziehungen der Reiche zu neutralen Dörfern (Phase 6): Ruf je Dorf und Reich
## (−100 … +100) mit Stufen und Verfall zum Grundwert, Geschenke mit
## abnehmendem Ertrag, drei Vertragsarten (Schutz, Handel, Bündnis) mit
## Pflichten und Lieferungen, Tauschhandel mit Tageslimit, Aufnahme ins Reich
## (ergeben, Einschüchterung, grosses Geschenk), Drohung, Krieg und Frieden,
## Seitenwechsel bei schlechtem Ruf und Gebietsverletzung.
##
## Alle Aktionen haben Kingdom-Parameter – die Spieler-Oberfläche und (ab
## Phase 7) die KI rufen dieselben Funktionen auf. Prüfungen geben "" bzw. einen
## deutschen Grund zurück. Meldungen nur über kingdom.notify (sieht nur der Spieler).
##
## Zustand (Schlüssel sind Kingdom.ids wie in Kingdom.relations; Phase 10 wandelt um):
## reputation, base_reputation, treaties, trade_used, gift_recent,
## protection_credit, cooldowns, last_attack, intrusion, history, notified,
## rng_state, use_caravans.
## Laufzeit: _pending (Folgen von Ruf-Änderungen und Kampfsignalen, im eigenen
## Takt abgearbeitet), Taktzähler.
class_name DiplomacySystem
extends Node

## Ruf eines Dorfs gegenüber einem Reich hat sich geändert
signal reputation_changed(village: Kingdom, other: Kingdom, value: float, delta: float, reason: String)
## Ruf-Stufe hat gewechselt (z. B. "neutral" -> "friendly")
signal reputation_tier_changed(village: Kingdom, other: Kingdom, old_tier: String, new_tier: String)
## Vertrag geschlossen oder beendet (treaty_type "" = beendet)
signal treaty_changed(village: Kingdom, other: Kingdom, treaty_type: String)
## Ein Dorf hat die Seite gewechselt (new_ally kann null sein: nur feindlich geworden)
signal side_switched(village: Kingdom, new_ally: Kingdom, against: Kingdom)
## Ein Reich hat (durch einen Boten) von einem Angriff erfahren – Phase 7: Entdeckung/Intel
signal aggression_reported(receiver: Kingdom, aggressor: Kingdom, village: Kingdom)
## Handelslieferung fällig (Phase 9: als Karawane, siehe use_caravans)
signal trade_delivery_due(village: Kingdom, partner: Kingdom, give: Dictionary, take: Dictionary)
## Ein Schutzbefohlener wird angegriffen und braucht bis deadline (Spielzeit) Hilfe
signal protection_requested(village: Kingdom, protector: Kingdom, attacker: Kingdom, deadline: float)

const TREATY_TYPES := ["protection", "trade", "alliance"]

var game: Node
var village_system: VillageSystem

## Dorf-id -> {Reich-id -> Ruf}
var reputation: Dictionary = {}
## Dorf-id -> {Reich-id -> Grundwert (Ziel des Verfalls)}
var base_reputation: Dictionary = {}
## Dorf-id -> {"type": "protection" | "trade" | "alliance", "partner_id", "since", "strikes",
##   "help_deadline", "help_attacker_id", "next_delivery", "deliveries" (Anzahl erfolgter Lieferungen),
##   "route": {} (Phase 9 Handelsweg)}
var treaties: Dictionary = {}
## Dorf-id -> {Reich-id -> {"day": Spieltag, "value": gehandelter Wert}}
var trade_used: Dictionary = {}
## Dorf-id -> {Reich-id -> {"value", "at"}} (kürzliche Geschenke, Halbwertszeit beim Lesen)
var gift_recent: Dictionary = {}
## Dorf-id -> {Reich-id -> {"hour", "value"}} (Ruf durch Schutz je Spielstunde)
var protection_credit: Dictionary = {}
## "dorf:reich:aktion" -> Spielzeit, ab der es wieder geht (refuse:<art>, threat, rumour:…)
var cooldowns: Dictionary = {}
## "dorf:reich" -> Spielzeit des letzten Angriffs (Frieden erst nach quiet_seconds)
var last_attack: Dictionary = {}
## "dorf:reich" -> Sekunden mit Truppen im Dorfgebiet
var intrusion: Dictionary = {}
## Dorf-id -> {Reich-id -> Array von {"t", "delta", "reason"}} (höchstens history_size)
var history: Dictionary = {}
## "dorf:reich:art" -> Spielzeit der letzten gedrosselten Meldung
var notified: Dictionary = {}
## Zustand des Zufallsgenerators (Annahme von Verträgen)
var rng_state: int = 0
## Phase 9: Handelslieferungen als Karawane (dann nur Signal, keine direkte Gutschrift)
var use_caravans := false

var _rng := RandomNumberGenerator.new()
var _ts := 64.0
var _tick_acc := 0.0
var _decay_acc := 0.0
var _intrusion_acc := 0.0
## Wartende Aufgaben: ["end_treaty", Dorf-id, Reich-id, Grund], ["side_switch", Dorf-id, Reich-id]
var _pending: Array = []


func setup(p_game: Node) -> void:
	game = p_game
	village_system = game.village_system
	_ts = float(game.world.tile_size)
	_rng.seed = hash(game.world.world_seed + 6661)
	rng_state = _rng.state
	GameClock.sim_tick.connect(_on_sim_tick)
	village_system.village_founded.connect(_init_village)
	game.combat_system.kingdom_attacked.connect(_on_kingdom_attacked)
	game.combat_system.unit_died.connect(_on_unit_died)
	game.combat_system.building_destroyed.connect(_on_building_destroyed)


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Kann das Reich Diplomatie betreiben? (Spieler oder KI, nicht besiegt)
func is_party(k: Kingdom) -> bool:
	return k != null and not k.defeated and (k.controller == "player" or k.controller == "ai")


## Ruf des Dorfs gegenüber dem Reich (legt den Startwert bei Bedarf an)
func get_reputation(village: Kingdom, other: Kingdom) -> float:
	if village == null or other == null:
		return 0.0
	_ensure(village, other)
	return float(reputation[village.id][other.id])


## Grundwert (Ziel des Verfalls) des Dorfs gegenüber dem Reich
func get_base_reputation(village: Kingdom, other: Kingdom) -> float:
	if village == null or other == null:
		return 0.0
	_ensure(village, other)
	return float(base_reputation[village.id][other.id])


## Ruf-Stufe des Dorfs gegenüber dem Reich ("hostile" … "devoted")
func get_tier(village: Kingdom, other: Kingdom) -> String:
	return tier_for(get_reputation(village, other))


## Stufe zu einem Ruf-Wert (höchste Stufe, deren Untergrenze erreicht ist)
static func tier_for(value: float) -> String:
	var result := "neutral"
	var first := true
	for t in DataDB.get_reputation_tiers():
		if first or value >= float(t["min"]):
			result = str(t["id"])
		first = false
	return result


## Anzeigename einer Stufe ("Freundlich")
static func tier_name(tier: String) -> String:
	for t in DataDB.get_reputation_tiers():
		if str(t["id"]) == tier:
			return str(t.get("name", tier))
	return tier


## Farbe einer Stufe (für Balken und Texte)
static func tier_color(tier: String) -> Color:
	for t in DataDB.get_reputation_tiers():
		if str(t["id"]) == tier:
			return t.get("color", Color.WHITE)
	return Color.WHITE


## Untergrenze einer Stufe (z. B. "devoted" -> 70)
static func tier_min(tier: String, default_value: float = 0.0) -> float:
	for t in DataDB.get_reputation_tiers():
		if str(t["id"]) == tier:
			return float(t["min"])
	return default_value


## Name einer Vertragsart ("Schutzvertrag")
static func treaty_name(treaty_type: String) -> String:
	return str(DataDB.diplo("treaties.%s.name" % treaty_type, treaty_type))


## Laufender Vertrag des Dorfs ({} wenn keiner)
func get_treaty(village: Kingdom) -> Dictionary:
	if village == null:
		return {}
	return treaties.get(village.id, {})


## Vertragsart zwischen Dorf und Reich ("" wenn keiner)
func get_treaty_with(village: Kingdom, other: Kingdom) -> String:
	var t := get_treaty(village)
	if t.is_empty() or other == null or int(t["partner_id"]) != other.id:
		return ""
	return str(t["type"])


## Alle Verträge eines Reichs: [{"village": Kingdom, "type": String}]
func get_treaties_of(k: Kingdom) -> Array:
	var list: Array = []
	if k == null:
		return list
	for vid in treaties:
		var t: Dictionary = treaties[vid]
		if int(t["partner_id"]) == k.id:
			var v: Kingdom = game.get_kingdom(int(vid))
			if v != null:
				list.append({"village": v, "type": str(t["type"])})
	return list


## Dörfer, die mit dem Reich verbündet sind (Bündnisvertrag)
func get_allied_villages(k: Kingdom) -> Array:
	var list: Array = []
	if k == null:
		return list
	for vid in treaties:
		var t: Dictionary = treaties[vid]
		if str(t["type"]) == "alliance" and int(t["partner_id"]) == k.id:
			var v: Kingdom = game.get_kingdom(int(vid))
			if v != null:
				list.append(v)
	return list


## Letzte Ruf-Änderungen (älteste zuerst): Array von {"t", "delta", "reason"}
func get_history(village: Kingdom, other: Kingdom) -> Array:
	if village == null or other == null:
		return []
	return (history.get(village.id, {}) as Dictionary).get(other.id, [])


## Offene Schutzpflichten des Reichs: [{"village", "deadline", "attacker"}]
func get_urgent(k: Kingdom) -> Array:
	var list: Array = []
	if k == null:
		return list
	for vid in treaties:
		var t: Dictionary = treaties[vid]
		if str(t["type"]) == "protection" and int(t["partner_id"]) == k.id and float(t["help_deadline"]) > 0.0:
			list.append({"village": game.get_kingdom(int(vid)), "deadline": float(t["help_deadline"]),
					"attacker": game.get_kingdom(int(t["help_attacker_id"]))})
	return list


## Kampfkraft der Truppen eines Reichs im Umkreis (Kacheln) um pos (Bewohner und Boten zählen nicht)
func get_strength_near(k: Kingdom, pos: Vector2, radius_tiles: float) -> float:
	var total := 0.0
	if k == null:
		return total
	for u in game.combat_system.index.query_kingdom(pos, radius_tiles * _ts, k.id):
		if u.hp > 0.0 and (u.role == "combat" or u.role == "hero" or u.role == "king" or u.role == "support"):
			total += VillageSystem.unit_power(u)
	return total


# ---------------------------------------------------------------------------
# Ruf
# ---------------------------------------------------------------------------

## Ändert den Ruf (begrenzt, mit Verlauf, Signalen und Meldung bei Stufenwechsel).
## Folgen (Vertragsende, Seitenwechsel) laufen im nächsten Takt.
func change_reputation(village: Kingdom, other: Kingdom, delta: float, reason: String) -> void:
	_apply(village, other, delta, reason, true)


## Gerücht: der Ruf ändert sich bei allen anderen selbstständigen Dörfern im Umkreis
## (Kacheln, -1 = rumour_radius) um origin – je Dorf, Reich und Grund höchstens alle
## rumour_interval Sekunden.
func spread_rumour(origin: Kingdom, other: Kingdom, delta: float, reason: String, radius_tiles: float = -1.0) -> void:
	if origin == null or other == null or delta == 0.0:
		return
	var radius := radius_tiles if radius_tiles >= 0.0 else float(DataDB.diplo("events.rumour_radius", 80))
	var center := village_system.get_center(origin)
	var now := GameClock.game_time
	var interval := float(DataDB.diplo("events.rumour_interval", 30))
	for w in village_system.get_villages():
		if w == origin or w == other:
			continue
		if center.distance_to(village_system.get_center(w)) > radius * _ts:
			continue
		var key := "rumour:%d:%d:%s" % [w.id, other.id, reason]
		if now < float(cooldowns.get(key, -1.0e9)):
			continue
		cooldowns[key] = now + interval
		change_reputation(w, other, delta, reason)


## Debug (F3 im Diplomatiefenster, Rauchtest): Ruf direkt setzen
func debug_set_reputation(village: Kingdom, other: Kingdom, value: float) -> void:
	if village == null or other == null:
		return
	change_reputation(village, other, value - get_reputation(village, other), "Debug")


func _apply(village: Kingdom, other: Kingdom, delta: float, reason: String, log_it: bool) -> void:
	if village == null or other == null or village == other or delta == 0.0:
		return
	if not village_system.is_village_kingdom(village):
		return
	_ensure(village, other)
	var row: Dictionary = reputation[village.id]
	var old := float(row[other.id])
	var value := clampf(old + delta, float(DataDB.diplo("reputation.min", -100)), float(DataDB.diplo("reputation.max", 100)))
	if is_equal_approx(value, old):
		return
	row[other.id] = value
	if log_it:
		var by_village: Dictionary = history.get(village.id, {})
		var entries: Array = by_village.get(other.id, [])
		entries.append({"t": GameClock.game_time, "delta": value - old, "reason": reason})
		while entries.size() > int(DataDB.diplo("reputation.history_size", 8)):
			entries.remove_at(0)
		by_village[other.id] = entries
		history[village.id] = by_village
	reputation_changed.emit(village, other, value, value - old, reason)
	var active := village_system.is_village(village)
	var old_tier := tier_for(old)
	var new_tier := tier_for(value)
	if old_tier != new_tier:
		reputation_tier_changed.emit(village, other, old_tier, new_tier)
		if active:
			_notify_tier(village, other, value, new_tier, value > old)
	if not active:
		return
	var t := get_treaty(village)
	if not t.is_empty() and int(t["partner_id"]) == other.id \
			and value < float(DataDB.diplo("treaties.%s.keep_min" % str(t["type"]), -100)):
		_pending.append(["end_treaty", village.id, other.id, "reputation"])
	if value <= float(DataDB.diplo("side_switch.threshold", -50)) and is_party(other):
		_pending.append(["side_switch", village.id, other.id])


func _notify_tier(v: Kingdom, k: Kingdom, value: float, tier: String, up: bool) -> void:
	var text := ""
	match tier:
		"devoted":
			text = "%s ist dir jetzt ergeben" % v.display_name
		"friendly":
			text = "%s ist dir jetzt freundlich gesinnt" % v.display_name
		"neutral":
			text = "%s steht dir jetzt neutral gegenüber" % v.display_name
		"suspicious":
			text = "%s misstraut dir jetzt" % v.display_name
		"hostile":
			text = "%s ist dir jetzt feindselig gesinnt" % v.display_name
		_:
			text = "%s: %s" % [v.display_name, tier_name(tier)]
	var kind := "good" if up else "warning"
	if not up and value < tier_min("neutral", -10.0):
		kind = "danger"
	k.notify("%s (Ruf %+d)." % [text, roundi(value)], kind, village_system.get_center(v))


## Startwert anlegen: Haltung des Volks zur Fraktion + Zuneigung zum Volk des Reichs
## + feste Streuung aus dem Welt-Seed
func _ensure(village: Kingdom, other: Kingdom) -> void:
	var row: Dictionary = reputation.get(village.id, {})
	if row.has(other.id):
		return
	var people := DataDB.get_people(village.people_id)
	var value := float((people.get("leaning", {}) as Dictionary).get(other.faction_id, 0.0))
	if not other.people_id.is_empty():
		value += float((people.get("affinity", {}) as Dictionary).get(other.people_id, 0.0))
	var jitter := int(DataDB.diplo("reputation.start_jitter", 5))
	if jitter > 0:
		value += float(posmod(hash([game.world.world_seed, village.id, other.id]), 2 * jitter + 1) - jitter)
	value = clampf(value, float(DataDB.diplo("reputation.min", -100)), float(DataDB.diplo("reputation.max", 100)))
	row[other.id] = value
	reputation[village.id] = row
	var base_row: Dictionary = base_reputation.get(village.id, {})
	base_row[other.id] = value
	base_reputation[village.id] = base_row


## Neues Dorf: Startruf gegenüber allen Reichen, die Diplomatie betreiben
func _init_village(v: Kingdom) -> void:
	for k in game.kingdoms:
		if is_party(k):
			_ensure(v, k)


# ---------------------------------------------------------------------------
# Geschenke
# ---------------------------------------------------------------------------

## Wert eines Geschenks: Menge × Warenwert × Vorliebe des Volks
func gift_value(village: Kingdom, gift: Dictionary) -> float:
	var values: Dictionary = DataDB.diplo("gifts.resource_value", {})
	var prefs: Dictionary = village_system.get_people(village).get("gift_preferences", {})
	var total := 0.0
	for res_id in gift:
		total += maxf(float(gift[res_id]), 0.0) * float(values.get(res_id, 1.0)) * float(prefs.get(res_id, 1.0))
	return total


## Vorschau: {"value", "gain" (Rufgewinn), "reason" ("" = möglich), "preference" (Faktor bei einer Ware)}
func preview_gift(giver: Kingdom, village: Kingdom, gift: Dictionary) -> Dictionary:
	var value := gift_value(village, gift)
	var gain := 0.0
	if village != null and giver != null:
		var per_point := maxf(float(DataDB.diplo("gifts.value_per_point", 10)), 0.01)
		gain = minf(value / per_point, float(DataDB.diplo("gifts.max_per_gift", 15)))
		gain /= 1.0 + _recent_gifts(village, giver) / maxf(float(DataDB.diplo("gifts.saturation", 300)), 1.0)
		if game.are_hostile(village, giver):
			gain *= float(DataDB.diplo("gifts.war_factor", 0.5))
	var pref := 1.0
	if gift.size() == 1:
		var prefs: Dictionary = village_system.get_people(village).get("gift_preferences", {})
		pref = float(prefs.get(gift.keys()[0], 1.0))
	return {"value": value, "gain": gain, "reason": can_give_gift(giver, village, gift), "preference": pref}


## "" = das Geschenk ist möglich, sonst der Grund
func can_give_gift(giver: Kingdom, village: Kingdom, gift: Dictionary) -> String:
	if not village_system.is_village(village):
		return "Kein selbstständiges Dorf"
	if not is_party(giver):
		return "Nur Reiche können schenken"
	var total := 0.0
	for res_id in gift:
		total += float(gift[res_id])
	if total <= 0.0:
		return "Wähle Ressource und Menge"
	if gift_value(village, gift) < float(DataDB.diplo("gifts.min_value", 10)):
		return "Zu wenig für ein Geschenk (mindestens Wert %d)" % int(DataDB.diplo("gifts.min_value", 10))
	return giver.missing_text(gift)


## Schenkt dem Dorf Ressourcen: Ruf steigt (abnehmend bei vielen Geschenken nacheinander)
func give_gift(giver: Kingdom, village: Kingdom, gift: Dictionary) -> bool:
	if not can_give_gift(giver, village, gift).is_empty():
		return false
	var preview := preview_gift(giver, village, gift)
	if not giver.spend(gift):
		return false
	for res_id in gift:
		village.add_resource(res_id, float(gift[res_id]))
	var recent := _recent_gifts(village, giver) + float(preview["value"])
	var row: Dictionary = gift_recent.get(village.id, {})
	row[giver.id] = {"value": recent, "at": GameClock.game_time}
	gift_recent[village.id] = row
	change_reputation(village, giver, float(preview["gain"]), "Geschenk")
	giver.notify("%s nimmt dein Geschenk an (Ruf %+.0f)." % [village.display_name, float(preview["gain"])], "good",
			village_system.get_center(village))
	return true


## Kürzliche Geschenke (Wert), halbieren sich alle half_life Sekunden
func _recent_gifts(village: Kingdom, giver: Kingdom) -> float:
	var entry: Dictionary = (gift_recent.get(village.id, {}) as Dictionary).get(giver.id, {})
	if entry.is_empty():
		return 0.0
	var dt := maxf(GameClock.game_time - float(entry["at"]), 0.0)
	return float(entry["value"]) * pow(0.5, dt / maxf(float(DataDB.diplo("gifts.half_life", 600)), 1.0))


# ---------------------------------------------------------------------------
# Verträge
# ---------------------------------------------------------------------------

## Angebot eines Vertrags: {"possible", "reason", "chance", "terms": {"tribute", "give", "take",
## "unlock", "rate_bonus", "help_seconds"}, "text" (Tooltip)}
func get_treaty_offer(proposer: Kingdom, village: Kingdom, treaty_type: String) -> Dictionary:
	var reason := _treaty_reason(proposer, village, treaty_type)
	var people := village_system.get_people(village)
	var terms := {"tribute": {}, "give": {}, "take": {}, "unlock": "", "rate_bonus": 0.0, "help_seconds": 0.0}
	var lines: PackedStringArray = []
	var tname := treaty_name(treaty_type)
	lines.append("[b]%s[/b]" % tname)
	match treaty_type:
		"protection":
			terms["tribute"] = people.get("tribute", {})
			terms["help_seconds"] = float(DataDB.diplo("treaties.protection.help_seconds", 60))
			lines.append("Das Dorf zahlt Tribut: %s pro Minute" % DataDB.cost_to_text(terms["tribute"]))
			lines.append("Pflicht: Wird es angegriffen, schicke binnen %d s Truppen hin." % int(terms["help_seconds"]))
		"trade":
			var delivery: Dictionary = people.get("delivery", {})
			terms["give"] = delivery.get("give", {})
			terms["take"] = delivery.get("take", {})
			terms["rate_bonus"] = float(DataDB.diplo("treaties.trade.rate_bonus", 0.15))
			lines.append("Alle %d s: %s für %s" % [int(DataDB.diplo("treaties.trade.delivery_interval", 150)),
					DataDB.cost_to_text(terms["give"]), DataDB.cost_to_text(terms["take"])])
			lines.append("Bessere Kurse (+%d %%), höheres Tageslimit" % roundi(float(terms["rate_bonus"]) * 100.0))
		"alliance":
			var special := str(people.get("special_unit", ""))
			terms["unlock"] = "summon:barracks:%s" % special if not special.is_empty() else ""
			terms["help_seconds"] = float(DataDB.diplo("treaties.alliance.help_seconds", 90))
			lines.append("Milizen helfen dir in der Nähe des Dorfs.")
			if not special.is_empty():
				lines.append("Neu in der Kaserne: %s" % str(DataDB.get_unit_type(special).get("name", special)))
	var min_rep := float(DataDB.diplo("treaties.%s.min_reputation" % treaty_type, 0))
	lines.append("Bedingung: Ruf mindestens %s (%+d)" % [tier_name(tier_for(min_rep)), roundi(min_rep)])
	var chance := 0.0
	if reason.is_empty():
		chance = _treaty_chance(proposer, village, treaty_type)
		lines.append("Annahme-Chance: %d %%" % roundi(chance * 100.0))
	else:
		lines.append(reason)
	return {"possible": reason.is_empty(), "reason": reason, "chance": chance, "terms": terms, "text": "\n".join(lines)}


## Schlägt einen Vertrag vor. "" = angenommen, sonst der Grund (auch "abgelehnt (Chance …)").
func propose_treaty(proposer: Kingdom, village: Kingdom, treaty_type: String) -> String:
	var reason := _treaty_reason(proposer, village, treaty_type)
	if not reason.is_empty():
		return reason
	var chance := _treaty_chance(proposer, village, treaty_type)
	_rng.state = rng_state
	var roll := _rng.randf()
	rng_state = _rng.state
	if roll >= chance:
		change_reputation(village, proposer, float(DataDB.diplo("events.treaty_refused", -2)), "Vertrag abgelehnt")
		cooldowns["%d:%d:refuse:%s" % [village.id, proposer.id, treaty_type]] = GameClock.game_time \
				+ float(DataDB.diplo("treaties.refuse_cooldown", 120))
		proposer.notify("%s lehnt den %s ab." % [village.display_name, treaty_name(treaty_type)], "warning",
				village_system.get_center(village))
		return "abgelehnt (Chance %d %%)" % roundi(chance * 100.0)
	if not get_treaty(village).is_empty():
		# Gleicher Partner wechselt die Vertragsart: alter Vertrag endet ohne Strafe
		_end_treaty(village, "", 0.0, false)
	_start_treaty(village, proposer, treaty_type)
	return ""


## Kündigung durch das Reich (Ruf sinkt um cancel_penalty)
func cancel_treaty(by: Kingdom, village: Kingdom) -> bool:
	var t := get_treaty(village)
	if t.is_empty() or by == null or int(t["partner_id"]) != by.id:
		return false
	var treaty_type := str(t["type"])
	var penalty := float(DataDB.diplo("treaties.%s.cancel_penalty" % treaty_type, -10))
	_end_treaty(village, "Vertrag gekündigt", penalty, false)
	by.notify("Du hast den %s mit %s gekündigt (Ruf %+d)." % [treaty_name(treaty_type), village.display_name,
			roundi(penalty)], "warning", village_system.get_center(village))
	return true


## Beendet alle Verträge des Dorfs ohne Strafe (Aufnahme, Eroberung, Seitenwechsel …)
func end_all_treaties(village: Kingdom, _reason: String) -> void:
	if village != null and treaties.has(village.id):
		_end_treaty(village, "", 0.0, false)


func _treaty_reason(proposer: Kingdom, village: Kingdom, treaty_type: String) -> String:
	if not TREATY_TYPES.has(treaty_type):
		return "Unbekannte Vertragsart"
	if not village_system.is_village(village):
		return "Kein selbstständiges Dorf"
	if not is_party(proposer):
		return "Nur Reiche schliessen Verträge"
	var t := get_treaty(village)
	if not t.is_empty():
		if int(t["partner_id"]) != proposer.id:
			var other: Kingdom = game.get_kingdom(int(t["partner_id"]))
			return "%s hat bereits einen Vertrag mit %s" % [village.display_name, other.display_name if other != null else "?"]
		if str(t["type"]) == treaty_type:
			return "Dieser Vertrag läuft bereits"
	if game.are_hostile(village, proposer):
		return "Im Krieg – erst Frieden schliessen"
	var min_rep := float(DataDB.diplo("treaties.%s.min_reputation" % treaty_type, 0))
	if get_reputation(village, proposer) < min_rep:
		return "Ruf zu niedrig (mindestens %s)" % tier_name(tier_for(min_rep))
	var ready_at := float(cooldowns.get("%d:%d:refuse:%s" % [village.id, proposer.id, treaty_type], -1.0e9))
	if GameClock.game_time < ready_at:
		return "Lehnt noch %d s ab" % ceili(ready_at - GameClock.game_time)
	return ""


## Annahme-Chance 0…1 (Schutzvertrag: Bonus, wenn eigene Truppen in der Nähe stark genug sind)
func _treaty_chance(proposer: Kingdom, village: Kingdom, treaty_type: String) -> float:
	var min_rep := float(DataDB.diplo("treaties.%s.min_reputation" % treaty_type, 0))
	var chance := float(DataDB.diplo("treaties.chance_base", 0.5)) \
			+ (get_reputation(village, proposer) - min_rep) / maxf(float(DataDB.diplo("treaties.chance_span", 40)), 1.0)
	if treaty_type == "protection":
		var strength := village_system.get_strength(village)
		if strength > 0.0 and get_strength_near(proposer, village_system.get_center(village), 15.0) >= strength:
			chance += float(DataDB.diplo("treaties.protection.strength_bonus", 0.2))
	return clampf(chance, 0.0, 1.0)


func _start_treaty(village: Kingdom, k: Kingdom, treaty_type: String) -> void:
	var now := GameClock.game_time
	treaties[village.id] = {"type": treaty_type, "partner_id": k.id, "since": now, "strikes": 0,
			"help_deadline": 0.0, "help_attacker_id": 0, "deliveries": 0,
			"next_delivery": now + float(DataDB.diplo("treaties.trade.delivery_interval", 150)) if treaty_type == "trade" else 0.0,
			"route": {}}
	if treaty_type == "alliance":
		_apply_alliance(village, k)
	treaty_changed.emit(village, k, treaty_type)
	k.notify("%s mit %s geschlossen!" % [treaty_name(treaty_type), village.display_name], "good",
			village_system.get_center(village))


## Bündnis wirksam machen: Beziehung "alliance", Spezialeinheit freischalten (idempotent)
func _apply_alliance(village: Kingdom, k: Kingdom) -> void:
	if village.get_relation(k) != "alliance":
		game.set_relation(village, k, "alliance")
	var special := str(village_system.get_people(village).get("special_unit", ""))
	if not special.is_empty():
		k.grant_unlock("alliance:%d" % village.id, "summon:barracks:%s" % special)
	_refresh_stealth(village, k)


## Vertrag beenden: Freischaltungen entziehen, Bündnis -> Frieden, optional Ruf-Strafe und Meldung
func _end_treaty(village: Kingdom, reason_text: String, penalty: float, notify_partner: bool) -> void:
	var t: Dictionary = treaties.get(village.id, {})
	if t.is_empty():
		return
	treaties.erase(village.id)
	var k: Kingdom = game.get_kingdom(int(t["partner_id"]))
	if k != null:
		k.revoke_unlocks("alliance:%d" % village.id)
		if village.get_relation(k) == "alliance":
			game.set_relation(village, k, "peace")
			_refresh_stealth(village, k)
		if penalty != 0.0:
			change_reputation(village, k, penalty, reason_text)
		if notify_partner:
			k.notify("%s kündigt den %s%s." % [village.display_name, treaty_name(str(t["type"])),
					"" if reason_text.is_empty() else " (%s)" % reason_text], "danger", village_system.get_center(village))
	treaty_changed.emit(village, k, "")


## Getarnte Einheiten beider Reiche neu zeichnen (verbündet = halb sichtbar)
func _refresh_stealth(a: Kingdom, b: Kingdom) -> void:
	for k in [a, b]:
		for u in (k as Kingdom).units:
			if u.stealthed:
				u.update_stealth_look()


# ---------------------------------------------------------------------------
# Handel
# ---------------------------------------------------------------------------

## Kurs und Menge eines Tauschs: {"ok", "reason", "get_amount", "rate", "value",
## "remaining_today", "margin"}
func get_trade_quote(trader: Kingdom, village: Kingdom, give_res: String, give_amount: float, get_res: String) -> Dictionary:
	var q := {"ok": false, "reason": "", "get_amount": 0.0, "rate": 0.0, "value": 0.0, "remaining_today": 0.0, "margin": 0.0}
	if not village_system.is_village(village):
		q["reason"] = "Kein selbstständiges Dorf"
		return q
	if not is_party(trader):
		q["reason"] = "Nur Reiche können handeln"
		return q
	if give_res == get_res or DataDB.get_resource(give_res).is_empty() or DataDB.get_resource(get_res).is_empty():
		q["reason"] = "Wähle zwei verschiedene Waren"
		return q
	var values: Dictionary = DataDB.diplo("gifts.resource_value", {})
	var people := village_system.get_people(village)
	var rates: Dictionary = people.get("trade_rates", {})
	var buys: Dictionary = rates.get("buys", {})
	var sells: Dictionary = rates.get("sells", {})
	var rep := get_reputation(village, trader)
	var treaty_bonus := float(DataDB.diplo("treaties.trade.rate_bonus", 0.15)) if get_treaty_with(village, trader) == "trade" else 0.0
	var margin := float(DataDB.diplo("trade.base_margin", 0.3)) - rep / 100.0 * float(DataDB.diplo("trade.rep_bonus_per_100", 0.15)) \
			- treaty_bonus - float(people.get("trade_bonus", 0.0))
	margin = clampf(margin, float(DataDB.diplo("trade.min_margin", 0.05)), float(DataDB.diplo("trade.max_margin", 0.6)))
	var give_value := float(values.get(give_res, 1.0))
	var rate := give_value * float(buys.get(give_res, 1.0)) \
			/ maxf(float(values.get(get_res, 1.0)) * float(sells.get(get_res, 1.0)), 0.01) * (1.0 - margin)
	var value := maxf(give_amount, 0.0) * give_value
	var remaining := maxf(_trade_limit(village, trader) - _trade_used(village, trader), 0.0)
	var get_amount := floorf(maxf(give_amount, 0.0) * rate)
	q["margin"] = margin
	q["rate"] = rate
	q["value"] = value
	q["remaining_today"] = remaining
	q["get_amount"] = get_amount
	if game.are_hostile(village, trader):
		q["reason"] = "Im Krieg wird nicht gehandelt"
	elif rep < float(DataDB.diplo("trade.min_reputation", -10)):
		q["reason"] = "Ruf zu niedrig (mindestens %s)" % tier_name(tier_for(float(DataDB.diplo("trade.min_reputation", -10))))
	elif give_amount <= 0.0:
		q["reason"] = "Wähle eine Menge"
	elif value > remaining + 0.001:
		q["reason"] = "Tageslimit erreicht (heute noch Wert %d)" % floori(remaining)
	elif get_amount < 1.0:
		q["reason"] = "Zu wenig für einen Tausch"
	elif get_amount > village.get_amount(get_res) + 0.001:
		q["reason"] = "%s hat nur %d %s" % [village.display_name, floori(village.get_amount(get_res)),
				str(DataDB.get_resource(get_res).get("name", get_res))]
	else:
		q["reason"] = trader.missing_text({give_res: give_amount})
	q["ok"] = str(q["reason"]).is_empty()
	return q


## Tausch ausführen. Gibt die erhaltene Menge zurück (0 = kein Tausch).
func trade(trader: Kingdom, village: Kingdom, give_res: String, give_amount: float, get_res: String) -> float:
	var q := get_trade_quote(trader, village, give_res, give_amount, get_res)
	if not bool(q["ok"]):
		return 0.0
	var n := float(q["get_amount"])
	if not trader.spend({give_res: give_amount}):
		return 0.0
	village.add_resource(give_res, give_amount)
	village.add_resource(get_res, -n)
	trader.add_resource(get_res, n)
	var row: Dictionary = trade_used.get(village.id, {})
	row[trader.id] = {"day": GameClock.get_day(), "value": _trade_used(village, trader) + float(q["value"])}
	trade_used[village.id] = row
	change_reputation(village, trader, float(DataDB.diplo("events.trade_per_100_value", 1.0)) * float(q["value"]) / 100.0, "Handel")
	trader.notify("Handel mit %s: %d %s gegen %d %s" % [village.display_name, roundi(give_amount),
			str(DataDB.get_resource(give_res).get("name", give_res)), roundi(n),
			str(DataDB.get_resource(get_res).get("name", get_res))], "info", village_system.get_center(village))
	return n


## Heute schon gehandelter Wert (setzt sich mit jedem Spieltag zurück)
func _trade_used(village: Kingdom, trader: Kingdom) -> float:
	var entry: Dictionary = (trade_used.get(village.id, {}) as Dictionary).get(trader.id, {})
	if entry.is_empty() or int(entry["day"]) != GameClock.get_day():
		return 0.0
	return float(entry["value"])


func _trade_limit(village: Kingdom, trader: Kingdom) -> float:
	var limit := float(DataDB.diplo("trade.daily_value_limit", 300))
	if get_treaty_with(village, trader) == "trade":
		limit *= float(DataDB.diplo("treaties.trade.limit_factor", 1.5))
	return limit


# ---------------------------------------------------------------------------
# Aufnahme, Drohung, Krieg, Frieden
# ---------------------------------------------------------------------------

## Kann das Reich das Dorf aufnehmen? {"ok", "reason", "mode": "devoted" | "intimidation" | "gift", "gift": {}}
func can_annex(k: Kingdom, village: Kingdom) -> Dictionary:
	var result := {"ok": false, "reason": "", "mode": "", "gift": {}}
	if not village_system.is_village(village):
		result["reason"] = "Kein selbstständiges Dorf"
		return result
	if not is_party(k) or not is_instance_valid(k.castle):
		result["reason"] = "Nur Reiche mit Burg können Dörfer aufnehmen"
		return result
	if game.are_hostile(village, k):
		result["reason"] = "Im Krieg – schliesse Frieden oder erobere das Dorf"
		return result
	var rep := get_reputation(village, k)
	if rep >= tier_min("devoted", 70.0):
		result["ok"] = true
		result["mode"] = "devoted"
		return result
	var min_rep := float(DataDB.diplo("annex.min_reputation", 30))
	if rep < min_rep:
		result["reason"] = "Ruf zu niedrig (mindestens %s, ohne Geschenk %s)" % [tier_name(tier_for(min_rep)),
				tier_name("devoted")]
		return result
	var strength := village_system.get_strength(village)
	var near := get_strength_near(k, village_system.get_center(village), float(DataDB.diplo("annex.intimidation_radius", 15)))
	if near > 0.0 and near >= float(DataDB.diplo("annex.intimidation_ratio", 2.5)) * maxf(strength, 1.0):
		result["ok"] = true
		result["mode"] = "intimidation"
		return result
	var gift := {}
	var base: Dictionary = village_system.get_people(village).get("annex_gift", {})
	var scale := float(village_system.get_record(village).get("size", 3)) * float(DataDB.diplo("annex.gift_size_scale", 0.333))
	for res_id in base:
		gift[res_id] = float(ceili(float(base[res_id]) * scale))
	result["mode"] = "gift"
	result["gift"] = gift
	result["reason"] = k.missing_text(gift)
	result["ok"] = str(result["reason"]).is_empty()
	return result


## Nimmt das Dorf ins Reich auf (Geschenk wird bezahlt; Einschüchterung: Gerücht und Deserteure)
func annex(k: Kingdom, village: Kingdom) -> bool:
	var info := can_annex(k, village)
	if not bool(info["ok"]):
		return false
	match str(info["mode"]):
		"gift":
			if not k.spend(info["gift"]):
				return false
		"intimidation":
			spread_rumour(village, k, float(DataDB.diplo("events.intimidation_rumour", -8)),
					"Gerücht: Einschüchterung von %s" % village.display_name)
			village_system.desert_militia(village, float(DataDB.diplo("annex.intimidation_desert_share", 0.5)))
	village_system.transfer_settlement(village, k, "annex")
	return true


## Drohung: {"possible", "reason", "ratio" (eigene Stärke / Dorfstärke), "tribute": {}}
func get_threat_info(k: Kingdom, village: Kingdom) -> Dictionary:
	var result := {"possible": false, "reason": "", "ratio": 0.0, "tribute": {}}
	if not village_system.is_village(village):
		result["reason"] = "Kein selbstständiges Dorf"
		return result
	if not is_party(k):
		result["reason"] = "Nur Reiche können drohen"
		return result
	var center := village_system.get_center(village)
	var near := get_strength_near(k, center, float(DataDB.diplo("threat.radius", 15)))
	result["ratio"] = near / maxf(village_system.get_strength(village), 1.0)
	var tribute := {}
	var fraction := float(DataDB.diplo("threat.tribute_fraction", 0.5))
	var cap := float(DataDB.diplo("threat.tribute_max", 150))
	for res in DataDB.resources:
		var amount := floorf(minf(village.get_amount(res["id"]) * fraction, cap))
		if amount > 0.0:
			tribute[res["id"]] = amount
	result["tribute"] = tribute
	var ready_at := float(cooldowns.get("%d:%d:threat" % [village.id, k.id], -1.0e9))
	if game.are_hostile(village, k):
		result["reason"] = "Im Krieg – Drohungen wirken nicht mehr"
	elif GameClock.game_time < ready_at:
		result["reason"] = "Erst in %d s wieder" % ceili(ready_at - GameClock.game_time)
	result["possible"] = str(result["reason"]).is_empty()
	return result


## Droht dem Dorf: genug Truppen in der Nähe (min_ratio) -> Tribut, sonst Spott.
## Der Ruf sinkt in beiden Fällen. Gibt true zurück, wenn Tribut gezahlt wurde.
func threaten(k: Kingdom, village: Kingdom) -> bool:
	var info := get_threat_info(k, village)
	if not bool(info["possible"]):
		return false
	cooldowns["%d:%d:threat" % [village.id, k.id]] = GameClock.game_time + float(DataDB.diplo("threat.cooldown", 600))
	var center := village_system.get_center(village)
	if float(info["ratio"]) >= float(DataDB.diplo("threat.min_ratio", 1.5)):
		var tribute: Dictionary = info["tribute"]
		for res_id in tribute:
			village.add_resource(res_id, -float(tribute[res_id]))
			k.add_resource(res_id, float(tribute[res_id]))
		change_reputation(village, k, float(DataDB.diplo("events.threat_success", -10)), "Drohung")
		spread_rumour(village, k, float(DataDB.diplo("events.rumour_threat", -3)), "Gerücht: Drohung gegen %s" % village.display_name)
		k.notify("%s beugt sich und zahlt Tribut: %s" % [village.display_name, DataDB.cost_to_text(tribute)], "good", center)
		return true
	change_reputation(village, k, float(DataDB.diplo("events.threat_fail", -15)), "Drohung verlacht")
	k.notify("%s lacht über deine Drohung." % village.display_name, "warning", center)
	return false


## Krieg erklären: laufender Vertrag bricht (starke Strafe, Gerücht bei allen Dörfern)
func declare_war(k: Kingdom, village: Kingdom) -> void:
	if not village_system.is_village(village) or not is_party(k) or game.are_hostile(village, k):
		return
	if get_treaty_with(village, k) != "":
		_end_treaty(village, "Vertragsbruch", float(DataDB.diplo("events.treaty_break", -40)), false)
		spread_rumour(village, k, float(DataDB.diplo("events.treaty_break_rumour", -5)), "Gerücht: Vertragsbruch", 1.0e6)
	game.set_relation(village, k, "war")
	change_reputation(village, k, float(DataDB.diplo("events.declare_war", -30)), "Kriegserklärung")
	spread_rumour(village, k, float(DataDB.diplo("events.rumour_war", -10)), "Gerücht: Krieg gegen %s" % village.display_name)
	last_attack["%d:%d" % [village.id, k.id]] = GameClock.game_time
	k.notify("Krieg mit %s!" % village.display_name, "danger", village_system.get_center(village))


## "" = Frieden ist möglich, sonst der Grund
func can_make_peace(k: Kingdom, village: Kingdom) -> String:
	if not village_system.is_village(village):
		return "Kein selbstständiges Dorf"
	if not is_party(k):
		return "Nur Reiche schliessen Frieden"
	if not game.are_hostile(village, k):
		return "Kein Krieg"
	var min_rep := float(DataDB.diplo("peace.min_reputation", -40))
	if get_reputation(village, k) < min_rep:
		return "Ruf zu niedrig (mindestens %+d) – Geschenke helfen" % roundi(min_rep)
	var quiet := float(DataDB.diplo("peace.quiet_seconds", 60))
	var since := GameClock.game_time - float(last_attack.get("%d:%d" % [village.id, k.id], -1.0e9))
	if since < quiet:
		return "Erst %d s nach dem letzten Angriff" % ceili(quiet - since)
	return ""


func make_peace(k: Kingdom, village: Kingdom) -> bool:
	if not can_make_peace(k, village).is_empty():
		return false
	game.set_relation(village, k, "peace")
	change_reputation(village, k, float(DataDB.diplo("events.peace_bonus", 5)), "Frieden")
	k.notify("Frieden mit %s." % village.display_name, "good", village_system.get_center(village))
	return true


## Boten melden einen Angriff (MessengerSystem): Signal für Phase 7 (Entdeckung, Intel)
func report_aggression(receiver: Kingdom, aggressor: Kingdom, village: Kingdom) -> void:
	aggression_reported.emit(receiver, aggressor, village)


# ---------------------------------------------------------------------------
# Seitenwechsel
# ---------------------------------------------------------------------------

## Ruf unter der Schwelle: das Dorf schliesst sich einem Reich der Gegenfraktion an
## (falls es eines mag), sonst wird es dem Reich gegenüber feindlich.
func _check_side_switch(village: Kingdom, k: Kingdom) -> void:
	if not village_system.is_village(village) or not is_party(k) or game.are_hostile(village, k):
		return
	var rep := get_reputation(village, k)
	if rep > float(DataDB.diplo("side_switch.threshold", -50)):
		return
	var opposite := ""
	match k.faction_id:
		"good":
			opposite = "evil"
		"evil":
			opposite = "good"
	var best: Kingdom = null
	var best_rep := rep
	for e in game.kingdoms:
		if e == k or not is_party(e) or e.faction_id != opposite or not is_instance_valid(e.castle):
			continue
		var r := get_reputation(village, e)
		if r > best_rep:
			best_rep = r
			best = e
	var center := village_system.get_center(village)
	if best != null:
		if get_treaty_with(village, best) != "alliance":
			end_all_treaties(village, "side_switch")
			_start_treaty(village, best, "alliance")
		elif get_treaty_with(village, k) != "":
			end_all_treaties(village, "side_switch")
		game.set_relation(village, k, "war")
		side_switched.emit(village, best, k)
		k.notify("%s hat sich %s angeschlossen und ist jetzt dein Feind!" % [village.display_name, best.display_name],
				"danger", center)
	else:
		if get_treaty_with(village, k) != "":
			end_all_treaties(village, "side_switch")
		game.set_relation(village, k, "war")
		side_switched.emit(village, null, k)
		k.notify("%s ist dir jetzt feindlich gesinnt." % village.display_name, "danger", center)


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	if not _pending.is_empty():
		_process_pending()
	_tick_acc += dt
	if _tick_acc < 1.0:
		return
	var step := _tick_acc
	_tick_acc = 0.0
	var now := GameClock.game_time
	_tick_protection(now)
	_tick_deliveries(now)
	_decay_acc += step
	var decay_interval := maxf(float(DataDB.diplo("reputation.decay_interval", 25)), 1.0)
	if _decay_acc >= decay_interval:
		_decay_acc -= decay_interval
		_decay(decay_interval)
	_intrusion_acc += step
	var check := maxf(float(DataDB.diplo("events.intrusion_check", 5)), 1.0)
	if _intrusion_acc >= check:
		_tick_intrusion(_intrusion_acc)
		_intrusion_acc = 0.0


func _process_pending() -> void:
	var list := _pending
	_pending = []
	var done := {}
	for entry in list:
		var key := "%s:%d:%d" % [str(entry[0]), int(entry[1]), int(entry[2])]
		if done.has(key):
			continue
		done[key] = true
		var v: Kingdom = game.get_kingdom(int(entry[1]))
		var k: Kingdom = game.get_kingdom(int(entry[2]))
		if v == null or k == null:
			continue
		match str(entry[0]):
			"end_treaty":
				var t := get_treaty(v)
				if t.is_empty() or int(t["partner_id"]) != k.id:
					continue
				if str(entry[3]) == "reputation":
					var keep := float(DataDB.diplo("treaties.%s.keep_min" % str(t["type"]), -100))
					if get_reputation(v, k) >= keep:
						continue
					_end_treaty(v, "Ruf zu niedrig", 0.0, true)
				else:
					_end_treaty(v, str(entry[3]), 0.0, true)
			"side_switch":
				_check_side_switch(v, k)


## Schutzpflicht: Truppen des Schutzherrn vor Ort = Erfolg, Frist abgelaufen = Strafe
func _tick_protection(now: float) -> void:
	for vid in treaties.keys():
		var t: Dictionary = treaties[vid]
		if str(t["type"]) != "protection" or float(t["help_deadline"]) <= 0.0:
			continue
		var v: Kingdom = game.get_kingdom(int(vid))
		var p: Kingdom = game.get_kingdom(int(t["partner_id"]))
		if not village_system.is_village(v) or not is_party(p):
			t["help_deadline"] = 0.0
			continue
		var center := village_system.get_center(v)
		var radius := village_system.get_radius_tiles(v) + float(DataDB.diplo("treaties.protection.help_radius_extra", 6))
		var helpers := 0
		for u in game.combat_system.index.query_kingdom(center, radius * _ts, p.id):
			if u.hp > 0.0 and (u.role == "combat" or u.role == "hero" or u.role == "king"):
				helpers += 1
		if helpers >= int(DataDB.diplo("treaties.protection.help_min_units", 3)):
			t["help_deadline"] = 0.0
			change_reputation(v, p, float(DataDB.diplo("events.protection_help_success", 5)), "Schutz geleistet")
			p.notify("%s dankt dir für deinen Schutz." % v.display_name, "good", center)
		elif not village_system.has_enemies_near(v, center, radius):
			# Angreifer weg, bevor Hilfe nötig war: ohne Folgen
			t["help_deadline"] = 0.0
		elif now >= float(t["help_deadline"]):
			t["help_deadline"] = 0.0
			t["strikes"] = int(t["strikes"]) + 1
			change_reputation(v, p, float(DataDB.diplo("events.protection_help_failed", -15)), "Schutz versäumt")
			var max_strikes := int(DataDB.diplo("treaties.protection.max_strikes", 3))
			p.notify("Du hast %s nicht beschützt (Verwarnung %d/%d)." % [v.display_name, int(t["strikes"]), max_strikes],
					"danger", center)
			if int(t["strikes"]) >= max_strikes:
				_pending.append(["end_treaty", v.id, p.id, "Schutz zu oft versäumt"])


## Handelsverträge: regelmässige Lieferung (Ware des Dorfs gegen Bezahlung)
func _tick_deliveries(now: float) -> void:
	var interval := maxf(float(DataDB.diplo("treaties.trade.delivery_interval", 150)), 1.0)
	for vid in treaties.keys():
		var t: Dictionary = treaties[vid]
		if str(t["type"]) != "trade" or now < float(t["next_delivery"]):
			continue
		t["next_delivery"] = now + interval
		var v: Kingdom = game.get_kingdom(int(vid))
		var k: Kingdom = game.get_kingdom(int(t["partner_id"]))
		if not village_system.is_village(v) or not is_party(k):
			continue
		var delivery: Dictionary = village_system.get_people(v).get("delivery", {})
		var give: Dictionary = delivery.get("give", {})
		var take: Dictionary = delivery.get("take", {})
		if use_caravans:
			trade_delivery_due.emit(v, k, give, take)
			continue
		var center := village_system.get_center(v)
		if not v.can_afford(give):
			_notify_throttled(v, k, "delivery_missing", "Handelslieferung aus %s fällt aus: dem Dorf fehlt Ware." % v.display_name,
					"warning", center, interval * 2.0)
			continue
		if not k.can_afford(take):
			_notify_throttled(v, k, "delivery_missing", "Handelslieferung aus %s fällt aus: %s" % [v.display_name,
					k.missing_text(take)], "warning", center, interval * 2.0)
			continue
		v.spend(give)
		k.spend(take)
		t["deliveries"] = int(t.get("deliveries", 0)) + 1
		for res_id in give:
			k.add_resource(res_id, float(give[res_id]))
		for res_id in take:
			v.add_resource(res_id, float(take[res_id]))
		k.notify("Handelslieferung aus %s: %s für %s" % [v.display_name, DataDB.cost_to_text(give),
				DataDB.cost_to_text(take)], "info", center)


## Verfall (einmal pro Spielstunde): mit laufendem Vertrag steigt der Ruf, sonst
## wandert er langsam zum Grundwert zurück. Danach die Seitenwechsel-Prüfung.
func _decay(_interval: float) -> void:
	var step := float(DataDB.diplo("reputation.decay_per_interval", 0.4))
	var threshold := float(DataDB.diplo("side_switch.threshold", -50))
	for vid in reputation.keys():
		var v: Kingdom = game.get_kingdom(int(vid))
		if not village_system.is_village(v):
			continue
		var row: Dictionary = reputation[vid]
		var t := get_treaty(v)
		for kid in row.keys():
			var k: Kingdom = game.get_kingdom(int(kid))
			if not is_party(k):
				continue
			var value := float(row[kid])
			if not t.is_empty() and int(t["partner_id"]) == k.id:
				_apply(v, k, float(DataDB.diplo("treaties.%s.rep_per_hour" % str(t["type"]), 0.0)), "Vertrag", false)
			else:
				var base := float((base_reputation.get(vid, {}) as Dictionary).get(kid, value))
				var delta := clampf(base - value, -step, step)
				if absf(delta) > 0.0001:
					_apply(v, k, delta, "Verfall", false)
			if float(row[kid]) <= threshold:
				_pending.append(["side_switch", v.id, k.id])


## Gebietsverletzung: viele fremde Truppen (ohne Vertrag/Bündnis, ohne Krieg) lange im Dorfgebiet
func _tick_intrusion(step: float) -> void:
	var extra := float(DataDB.diplo("events.intrusion_radius_extra", 2))
	var min_units := int(DataDB.diplo("events.intrusion_min_units", 3))
	var limit := float(DataDB.diplo("events.intrusion_seconds", 30))
	var touched := {}
	for v in village_system.get_villages():
		var center := village_system.get_center(v)
		var counts := {}
		for u in game.combat_system.index.query(center, (village_system.get_radius_tiles(v) + extra) * _ts):
			if u.kingdom == v or u.hp <= 0.0 or (u.role != "combat" and u.role != "hero"):
				continue
			counts[u.kingdom.id] = int(counts.get(u.kingdom.id, 0)) + 1
		for kid in counts:
			var k: Kingdom = game.get_kingdom(int(kid))
			if not is_party(k) or int(counts[kid]) < min_units:
				continue
			if game.are_hostile(v, k) or game.are_allied(v, k) or get_treaty_with(v, k) == "protection":
				continue
			var key := "%d:%d" % [v.id, k.id]
			touched[key] = true
			intrusion[key] = float(intrusion.get(key, 0.0)) + step
			if float(intrusion[key]) >= limit:
				intrusion[key] = 0.0
				change_reputation(v, k, float(DataDB.diplo("events.intrusion_penalty", -2)), "Gebietsverletzung")
				_notify_throttled(v, k, "intrusion", "Deine Truppen beunruhigen %s (Ruf %d)." % [v.display_name,
						roundi(get_reputation(v, k))], "warning", center, 120.0)
	for key in intrusion.keys():
		if not touched.has(key):
			intrusion.erase(key)


func _notify_throttled(v: Kingdom, k: Kingdom, kind_key: String, text: String, kind: String, pos: Vector2, interval: float) -> void:
	var key := "%d:%d:%s" % [v.id, k.id, kind_key]
	var now := GameClock.game_time
	if now - float(notified.get(key, -1.0e9)) < interval:
		return
	notified[key] = now
	k.notify(text, kind, pos)


# ---------------------------------------------------------------------------
# Kampfsignale
# ---------------------------------------------------------------------------

## Angriff auf ein Dorf: Ruf sinkt (dazu Gerücht); Schutzvertrag: der Schutzherr muss helfen
func _on_kingdom_attacked(victim: Kingdom, attacker: Kingdom, pos: Vector2) -> void:
	if not village_system.is_village(victim) or attacker == null:
		return
	var now := GameClock.game_time
	if is_party(attacker):
		change_reputation(victim, attacker, float(DataDB.diplo("events.attack", -5)), "Angriff")
		last_attack["%d:%d" % [victim.id, attacker.id]] = now
		spread_rumour(victim, attacker, float(DataDB.diplo("events.rumour_attack", -2)),
				"Gerücht: Angriff auf %s" % victim.display_name)
	var t := get_treaty(victim)
	if t.is_empty() or str(t["type"]) != "protection" or int(t["partner_id"]) == attacker.id \
			or float(t["help_deadline"]) > 0.0:
		return
	var protector: Kingdom = game.get_kingdom(int(t["partner_id"]))
	if not is_party(protector):
		return
	var seconds := float(DataDB.diplo("treaties.protection.help_seconds", 60))
	t["help_deadline"] = now + seconds
	t["help_attacker_id"] = attacker.id
	protection_requested.emit(victim, protector, attacker, now + seconds)
	protector.notify("%s wird angegriffen – du hast Schutz versprochen! (noch %d s)" % [victim.display_name, roundi(seconds)],
			"danger", pos)


## Miliz getötet: Ruf sinkt. Feind eines Dorfs in seiner Nähe getötet: Schutz geleistet.
func _on_unit_died(u: Unit, killer: Kingdom) -> void:
	if killer == null or not is_party(killer):
		return
	var victim_kingdom := u.kingdom
	if village_system.is_village(victim_kingdom) and u.role != "messenger":
		change_reputation(victim_kingdom, killer, float(DataDB.diplo("events.kill_militia", -3)), "Miliz getötet")
		return
	var hour := floori(GameClock.game_time / maxf(float(DataDB.diplo("reputation.decay_interval", 25)), 1.0))
	var cap := float(DataDB.diplo("events.protection_cap_per_hour", 15))
	var per_point := float(DataDB.diplo("events.protection_kill_per_point", 2.0))
	var extra := float(DataDB.diplo("treaties.protection.help_radius_extra", 6))
	for w in village_system.get_villages():
		if w == killer or w == victim_kingdom or not game.are_hostile(w, victim_kingdom) or game.are_hostile(w, killer):
			continue
		if u.position.distance_to(village_system.get_center(w)) > (village_system.get_radius_tiles(w) + extra) * _ts:
			continue
		var row: Dictionary = protection_credit.get(w.id, {})
		var entry: Dictionary = row.get(killer.id, {"hour": hour, "value": 0.0})
		if int(entry["hour"]) != hour:
			entry = {"hour": hour, "value": 0.0}
		var gain := minf(per_point * float(u.type_def.get("kill_points", 1)), cap - float(entry["value"]))
		if gain > 0.0:
			entry["value"] = float(entry["value"]) + gain
			change_reputation(w, killer, gain, "Schutz geleistet")
		row[killer.id] = entry
		protection_credit[w.id] = row


func _on_building_destroyed(b: Building, killer: Kingdom) -> void:
	if killer != null and is_party(killer) and village_system.is_village(b.kingdom):
		change_reputation(b.kingdom, killer, float(DataDB.diplo("events.destroy_building", -10)), "Gebäude zerstört")


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"reputation": reputation.duplicate(true), "base_reputation": base_reputation.duplicate(true),
			"treaties": treaties.duplicate(true), "trade_used": trade_used.duplicate(true),
			"gift_recent": gift_recent.duplicate(true), "protection_credit": protection_credit.duplicate(true),
			"cooldowns": cooldowns.duplicate(), "last_attack": last_attack.duplicate(),
			"intrusion": intrusion.duplicate(), "history": history.duplicate(true), "notified": notified.duplicate(),
			"rng_state": rng_state, "use_caravans": use_caravans, "pending": _pending.duplicate(true),
			"tick_acc": _tick_acc, "decay_acc": _decay_acc, "intrusion_acc": _intrusion_acc}


func from_dict(d: Dictionary) -> void:
	reputation = (d.get("reputation", {}) as Dictionary).duplicate(true)
	base_reputation = (d.get("base_reputation", {}) as Dictionary).duplicate(true)
	treaties = (d.get("treaties", {}) as Dictionary).duplicate(true)
	trade_used = (d.get("trade_used", {}) as Dictionary).duplicate(true)
	gift_recent = (d.get("gift_recent", {}) as Dictionary).duplicate(true)
	protection_credit = (d.get("protection_credit", {}) as Dictionary).duplicate(true)
	cooldowns = (d.get("cooldowns", {}) as Dictionary).duplicate()
	last_attack = (d.get("last_attack", {}) as Dictionary).duplicate()
	intrusion = (d.get("intrusion", {}) as Dictionary).duplicate()
	history = (d.get("history", {}) as Dictionary).duplicate(true)
	notified = (d.get("notified", {}) as Dictionary).duplicate()
	rng_state = int(d.get("rng_state", rng_state))
	use_caravans = bool(d.get("use_caravans", false))
	_pending = (d.get("pending", []) as Array).duplicate(true)
	_tick_acc = float(d.get("tick_acc", 0.0))
	_decay_acc = float(d.get("decay_acc", 0.0))
	_intrusion_acc = float(d.get("intrusion_acc", 0.0))


## Nach dem Laden: Bündnisse wieder wirksam machen (Beziehung, Freischaltung; idempotent)
func rebuild_runtime() -> void:
	_rng.state = rng_state
	for vid in treaties:
		var t: Dictionary = treaties[vid]
		if str(t["type"]) != "alliance":
			continue
		var v: Kingdom = game.get_kingdom(int(vid))
		var k: Kingdom = game.get_kingdom(int(t["partner_id"]))
		if v != null and k != null:
			_apply_alliance(v, k)
