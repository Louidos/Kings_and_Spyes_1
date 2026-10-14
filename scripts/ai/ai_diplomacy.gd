## AIDiplomacy
##
## Diplomatie und Kundschaft eines KI-Reichs (Phase 7): Späher (Streife am eigenen
## Gebietsrand, Erkundung fremder Reiche), Dörfer (Geschenke, Verträge, Frieden,
## Aufnahme, Drohungen über die DiplomacySystem-Schnittstellen), Spione und
## Reichstarnung. Nur statische Funktionen; Zustand in Kingdom.ai_state ("scouts",
## "next_patrol", "village_next", "gift_value_hour", "spy_next").
##
## Spione (SpySystem): angeworben, sobald über ein Reich Gerüchte umgehen (Ränkeschmiede
## immer); Auskundschaften des Spielers bzw. eines Rivalen, bis das Reich entdeckt ist
## (der Spion bestätigt die Gerüchte), sonst Dörfer gegen den Spieler aufhetzen.
## Reichstarnung (EspionageSystem) bei Persönlichkeiten mit "cloak" und genug Mana.
class_name AIDiplomacy
extends RefCounted


## Späher: einer läuft Streife (alle defense.patrol_interval Sekunden zu einem
## zufälligen Punkt am eigenen Gebietsrand), ein zweiter erkundet ein Reich, über
## das Gerüchte umgehen (Punkt 8 Kacheln in dessen Gebiet), sonst ebenfalls Streife.
static func tick_scouts(b: AIBrain, now: float) -> void:
	var k := b.k
	var roles: Dictionary = b.st["scouts"]
	var alive := {}
	for u in k.units:
		if u.tier == "scout" and u.is_alive():
			alive[u.uid] = u
	for uid in roles.keys():
		if not alive.has(int(uid)):
			roles.erase(uid)
	for uid in alive:
		if not roles.has(uid):
			roles[uid] = "patrol" if not roles.values().has("patrol") else "explore"
	if now < float(b.st["next_patrol"]):
		return
	b.st["next_patrol"] = now + float(DataDB.ai("defense.patrol_interval", 60))
	var cmd: CommandSystem = b.game.command_system
	var rumour := float(DataDB.esp("awareness.rumour", 30))
	var explore_target := _explore_target(b, rumour)
	for uid in roles:
		var u: Unit = alive[uid]
		if u.target != null and is_instance_valid(u.target):
			continue
		if str(roles[uid]) == "explore" and explore_target != null:
			cmd.order_move([u], _explore_point(b, explore_target), false)
		else:
			cmd.order_move([u], _patrol_point(b), false)


## Reich, über das Gerüchte umgehen (Aufmerksamkeit >= rumour), das nächste zuerst; sonst null
static func _explore_target(b: AIBrain, rumour: float) -> Kingdom:
	var best: Kingdom = null
	var best_d := INF
	var home := b.home_center()
	for o in b.game.kingdoms:
		var other: Kingdom = o
		if other == b.k or other.defeated or not is_instance_valid(other.castle):
			continue
		if other.controller != "player" and other.controller != "ai":
			continue
		if b.sys.get_awareness(b.k, other) < rumour:
			continue
		var d := home.distance_to(other.castle.get_center())
		if d < best_d:
			best_d = d
			best = other
	return best


## Zufälliger freier Punkt am Rand des eigenen Gebiets
static func _patrol_point(b: AIBrain) -> Vector2:
	var world := b.world
	var home := b.home_center()
	var dir := Vector2.from_angle(b.sys.rand_float() * TAU)
	var p := home + dir * (b.territory_radius_tiles() - 1.0) * float(world.tile_size)
	var cell: Vector2i = b.game.nav.nearest_free(world.world_to_cell(p), 6)
	return world.cell_to_world(cell) if cell.x >= 0 else b.home_rally()


## Punkt 8 Kacheln innerhalb des fremden Gebiets, von der eigenen Burg aus gesehen
static func _explore_point(b: AIBrain, target: Kingdom) -> Vector2:
	var world := b.world
	var their := target.castle.get_center()
	var dir := (b.home_center() - their).normalized()
	var radius := float(DataDB.get_building("castle").get("territory_radius", 14))
	var p := their + dir * maxf(radius - 8.0, 2.0) * float(world.tile_size)
	var cell: Vector2i = b.game.nav.nearest_free(world.world_to_cell(p), 6)
	return world.cell_to_world(cell) if cell.x >= 0 else their


# ---------------------------------------------------------------------------
# Dörfer
# ---------------------------------------------------------------------------

## Dörfer (ab villages.min_minute alle villages.interval Sekunden, höchstens max_actions Handlungen): nahe
## Dörfer nach Entfernung. Krieg ohne laufende Welle dorthin -> Frieden. Diplomaten und
## Ränkeschmiede: Aufnahme (ergeben), Bündnis (freundlich), Handels- oder Schutzvertrag,
## sonst Geschenke bis Freundlich. Eroberer: Drohung, wenn genug Truppen in der Nähe
## stehen (schwache Dörfer werden Wellenziele, siehe AIMilitary).
static func tick_villages(b: AIBrain, now: float) -> void:
	# Erst die Wirtschaft (gilt auch im Debug-Tempo)
	if b.minutes(now) < float(DataDB.ai("villages.min_minute", 10)):
		return
	var k := b.k
	var vs: VillageSystem = b.game.village_system
	var ds: DiplomacySystem = b.game.diplomacy_system
	var home := b.home_center()
	var ts := float(b.world.tile_size)
	var max_tiles := float(DataDB.ai("villages.max_distance", 140))
	var near: Array = []
	for v in vs.get_villages():
		var tiles := home.distance_to(vs.get_center(v)) / ts
		if tiles <= max_tiles:
			near.append([tiles, v])
	near.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var actions := int(DataDB.ai("villages.max_actions", 2))
	var style := str(b.personality.get("village_style", "diplomat"))
	var wave: Dictionary = b.st["wave"]
	var wave_target := int(wave.get("target_id", 0)) if not wave.is_empty() else 0
	for entry in near:
		if actions <= 0:
			break
		var v: Kingdom = entry[1]
		if b.game.are_hostile(k, v):
			if v.id != wave_target and ds.can_make_peace(k, v).is_empty() and ds.make_peace(k, v):
				actions -= 1
			continue
		if style == "conqueror":
			if _try_threaten(b, v):
				actions -= 1
			continue
		if _village_diplomacy(b, v, now):
			actions -= 1


## Eine diplomatische Handlung mit dem Dorf (Aufnahme, Vertrag, Geschenk); true = gehandelt
static func _village_diplomacy(b: AIBrain, v: Kingdom, now: float) -> bool:
	var k := b.k
	var ds: DiplomacySystem = b.game.diplomacy_system
	var rep := ds.get_reputation(v, k)
	var friendly := DiplomacySystem.tier_min("friendly", 30.0)
	if bool(DataDB.ai("villages.annex", true)) and rep >= DiplomacySystem.tier_min("devoted", 70.0):
		var info := ds.can_annex(k, v)
		if bool(info["ok"]) and str(info["mode"]) == "devoted":
			return ds.annex(k, v)
	var treaty := ds.get_treaty(v)
	var own := not treaty.is_empty() and int(treaty.get("partner_id", 0)) == k.id
	# Phase 9: erst ein Handelsweg (Handelsvertrag), solange das Reich keinen hat
	var trs: Variant = b.game.get("trade_route_system")
	if treaty.is_empty() and bool(DataDB.ai("routes.prefer_trade_first", true)) and trs != null \
			and (trs as TradeRouteSystem).get_routes(k).is_empty():
		var trade_offer := ds.get_treaty_offer(k, v, "trade")
		if bool(trade_offer["possible"]) and float(trade_offer["chance"]) >= float(DataDB.ai("villages.other_treaty_min_chance", 0.7)):
			ds.propose_treaty(k, v, "trade")
			return true
	if rep >= friendly and (treaty.is_empty() or (own and str(treaty["type"]) != "alliance")):
		var offer := ds.get_treaty_offer(k, v, "alliance")
		if bool(offer["possible"]) and float(offer["chance"]) >= float(DataDB.ai("villages.alliance_min_chance", 0.6)):
			ds.propose_treaty(k, v, "alliance")
			return true
	if treaty.is_empty():
		var min_chance := float(DataDB.ai("villages.other_treaty_min_chance", 0.7))
		for treaty_type in ["trade", "protection"]:
			var offer := ds.get_treaty_offer(k, v, str(treaty_type))
			if bool(offer["possible"]) and float(offer["chance"]) >= min_chance:
				ds.propose_treaty(k, v, str(treaty_type))
				return true
	if rep < friendly:
		return _try_gift(b, v, now)
	return false


## Geschenk: die Ware mit dem grössten Überschuss (Vorrat − 2 × Reserve) × Vorliebe des
## Volks, höchstens gift_amount; nur bei genug Rufgewinn und im Stundenbudget
static func _try_gift(b: AIBrain, v: Kingdom, now: float) -> bool:
	var k := b.k
	var ds: DiplomacySystem = b.game.diplomacy_system
	var vs: VillageSystem = b.game.village_system
	var hour := floori(now / maxf(GameClock.seconds_per_day / 24.0, 1.0))
	var budget: Dictionary = b.st["gift_value_hour"]
	if int(budget.get("hour", -1)) != hour:
		budget = {"hour": hour, "value": 0.0}
		b.st["gift_value_hour"] = budget
	var max_value := float(DataDB.ai("villages.max_gift_value_per_hour", 150))
	if float(budget["value"]) >= max_value:
		return false
	var reserve := b.reserve_cost()
	var prefs: Dictionary = vs.get_people(v).get("gift_preferences", {})
	var values: Dictionary = DataDB.diplo("gifts.resource_value", {})
	var gift_amount := float(DataDB.ai("villages.gift_amount", 60))
	var best_res := ""
	var best_amount := 0.0
	var best_score := 0.0
	for res in values:
		if str(res) == "mana":
			continue
		var surplus := k.get_amount(str(res)) - 2.0 * float(reserve.get(res, 0.0))
		if surplus < 10.0:
			continue
		var amount := floorf(minf(gift_amount, surplus))
		var score := amount * float(values[res]) * float(prefs.get(res, 1.0))
		if score > best_score:
			best_score = score
			best_res = str(res)
			best_amount = amount
	if best_res.is_empty():
		return false
	var gift := {best_res: best_amount}
	var preview := ds.preview_gift(k, v, gift)
	if not str(preview["reason"]).is_empty() or float(preview["gain"]) < float(DataDB.ai("villages.gift_min_gain", 2)):
		return false
	if float(budget["value"]) + float(preview["value"]) > max_value:
		return false
	if not ds.give_gift(k, v, gift):
		return false
	budget["value"] = float(budget["value"]) + float(preview["value"])
	return true


## Drohung (Eroberer): nur mit genug eigenen Truppen in der Nähe (threaten_ratio)
static func _try_threaten(b: AIBrain, v: Kingdom) -> bool:
	var ds: DiplomacySystem = b.game.diplomacy_system
	var info := ds.get_threat_info(b.k, v)
	if not bool(info["possible"]) or float(info["ratio"]) < float(DataDB.ai("villages.threaten_ratio", 2.0)):
		return false
	ds.threaten(b.k, v)
	return true


# ---------------------------------------------------------------------------
# Spione
# ---------------------------------------------------------------------------

## Spione: anwerben (Gerüchte über ein Reich oder Ränkeschmied, bis spies.max ×
## spy_mult), freie Spione auskundschaften lassen (Spieler zuerst, dann Rivalen – bis
## das Reich entdeckt ist und genaue Kundschaft vorliegt), sonst ein dem Spieler
## freundliches Dorf aufhetzen, sonst heimkehren. Auskundschaftende Spione bleiben, bis
## das Ziel auch ohne sie entdeckt ist (dann nach spies.scout_seconds zurück).
static func tick_spies(b: AIBrain, now: float) -> void:
	var k := b.k
	var spy_sys := b.sys.spies()
	var esp := b.sys.espionage()
	if spy_sys == null or esp == null:
		return
	var rumour := float(DataDB.esp("awareness.rumour", 30))
	var discovered := float(DataDB.esp("awareness.discovered", 60))
	var style := str(b.personality.get("village_style", ""))
	var targets := _spy_targets(b, rumour)
	var spies := spy_sys.get_spies(k)
	var max_n := maxi(roundi(float(DataDB.ai("spies.max", 2)) * float(b.personality.get("spy_mult", 1.0))), 1)
	if spies.size() + spy_sys.count_queued(k) < max_n and (not targets.is_empty() or style == "inciter") \
			and spy_sys.can_recruit(k).is_empty() and b.can_spend(SpySystem.spy_type(k.faction_id).get("cost", {})):
		spy_sys.recruit(k)
	var busy := {}
	for u in spies:
		var rec := spy_sys.get_record(u)
		if not str(rec["mission"]).is_empty():
			busy["%s:%d" % [str(rec["mission"]), int(rec["target_id"])]] = true
	var scout_seconds := float(DataDB.ai("spies.scout_seconds", 240))
	for u in spies:
		var spy: Unit = u
		var rec := spy_sys.get_record(spy)
		var state := str(rec["state"])
		if state == "active" and str(rec["mission"]) == "scout" and now - float(rec["active_since"]) >= scout_seconds:
			var target: Kingdom = b.game.get_kingdom(int(rec["target_id"]))
			if target == null or esp.get_awareness(k, target) >= discovered + 10.0 or not targets.has(target):
				spy_sys.recall(spy)
			continue
		if state != "idle":
			continue
		var assigned := false
		for t in targets:
			var target: Kingdom = t
			if busy.has("scout:%d" % target.id):
				continue
			if esp.get_intel_level(k, target) >= 3 and esp.get_awareness(k, target) >= discovered:
				continue
			if spy_sys.assign_mission(spy, "scout", target).is_empty():
				busy["scout:%d" % target.id] = true
				_log_spy(b, target, now)
				assigned = true
				break
		if assigned or _try_incite(b, spy_sys, spy, rumour, busy, now):
			continue
		if not b.is_near_home(spy.position, 2.0):
			spy_sys.recall(spy)


## Ziele für Kundschaft: andere Reiche (Spieler, KI) mit Aufmerksamkeit >= Gerüchte;
## der Spieler zuerst, dann nach Entfernung
static func _spy_targets(b: AIBrain, rumour: float) -> Array:
	var list: Array = []
	var home := b.home_center()
	for o in b.game.kingdoms:
		var other: Kingdom = o
		if other == b.k or other.defeated or not is_instance_valid(other.castle):
			continue
		if other.controller != "player" and other.controller != "ai":
			continue
		if b.sys.get_awareness(b.k, other) >= rumour:
			list.append(other)
	list.sort_custom(func(x: Kingdom, y: Kingdom) -> bool:
		if x.is_player != y.is_player:
			return x.is_player
		return home.distance_to(x.castle.get_center()) < home.distance_to(y.castle.get_center()))
	return list


## Dorf aufhetzen: das dem Spieler am meisten zugeneigte Dorf (Ruf >= Freundlich) gegen
## den Spieler – nur im Krieg mit ihm (incite_when_war, Ränkeschmiede immer) und wenn
## über ihn schon Gerüchte umgehen
static func _try_incite(b: AIBrain, spy_sys: SpySystem, spy: Unit, rumour: float, busy: Dictionary, now: float) -> bool:
	var k := b.k
	var enemy: Kingdom = b.game.player
	if enemy == null or enemy.defeated or not b.game.are_hostile(k, enemy):
		return false
	if str(b.personality.get("village_style", "")) != "inciter" and not bool(DataDB.ai("spies.incite_when_war", true)):
		return false
	if b.sys.get_awareness(k, enemy) < rumour:
		return false
	var ds: DiplomacySystem = b.game.diplomacy_system
	var best: Kingdom = null
	var best_rep := DiplomacySystem.tier_min("friendly", 30.0)
	for v in (b.game.village_system as VillageSystem).get_villages():
		if busy.has("incite_village:%d" % v.id):
			continue
		var rep := ds.get_reputation(v, enemy)
		if rep >= best_rep:
			best_rep = rep
			best = v
	if best == null or not spy_sys.assign_mission(spy, "incite_village", best, enemy).is_empty():
		return false
	busy["incite_village:%d" % best.id] = true
	_log_spy(b, enemy, now)
	return true


static func _log_spy(b: AIBrain, target: Kingdom, now: float) -> void:
	b.log_first("first_spy", now)
	if target != null and target.is_player:
		b.log_first("first_spy_player", now)


# ---------------------------------------------------------------------------
# Reichstarnung
# ---------------------------------------------------------------------------

## Reichstarnung einschalten (Persönlichkeit mit "cloak"): Zauber bekannt, Mana über
## cloak_min_mana_ratio der Lagergrenze und Mana-Ertrag >= cloak_min_mana_rate pro
## Minute. Bei Manamangel endet sie von selbst (EspionageSystem).
static func tick_cloak(b: AIBrain, now: float) -> void:
	if not bool(b.personality.get("cloak", false)):
		return
	var esp := b.sys.espionage()
	var k := b.k
	if esp == null or esp.is_cloaked(k) or not esp.can_toggle_cloak(k).is_empty():
		return
	var cap := k.get_capacity("mana")
	if cap == INF or k.get_amount("mana") < cap * float(DataDB.ai("spells.cloak_min_mana_ratio", 0.6)):
		return
	if float(k.income_rate.get("mana", 0.0)) < float(DataDB.ai("spells.cloak_min_mana_rate", 12)):
		return
	if esp.toggle_cloak(k).is_empty():
		b.log_first("first_cloak", now)
