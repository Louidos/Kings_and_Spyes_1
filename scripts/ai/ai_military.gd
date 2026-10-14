## AIMilitary
##
## Militär eines KI-Reichs (Phase 7): Beschwören nach Armee-Soll und Zusammensetzung
## (ai.json army), Helden (Anwerben, Stufenwahl, Fähigkeiten, Wiederbeleben,
## Ausbildung), Zauber im Kampf, Verteidigung des eigenen Gebiets, Hilfe für Dörfer
## und Angriffswellen (Zielwahl: Spieler, Rivale, Dorf, Monsterlager; Sammeln, Marsch,
## Kampf, Rückzug). Nur statische Funktionen: der Zustand liegt in Kingdom.ai_state.
## Befehle laufen über das CommandSystem (Gruppenmarsch), Beschwörungen über das
## SummonSystem, Zauber über das MagicSystem – wie beim Spieler.
class_name AIMilitary
extends RefCounted

## Kampf-Zustand einer Welle: so oft werden untätige Einheiten neu angesetzt (Spielsekunden)
const FIGHT_ORDER_INTERVAL := 4.0
## Verteidiger werden höchstens so oft neu losgeschickt (Spielsekunden)
const DEFENSE_ORDER_INTERVAL := 8.0
## Rückzug endet spätestens nach so vielen Spielsekunden
const RETREAT_MAX_SECONDS := 120.0
## Marsch: liegengebliebene Einheiten weiter als so viele Kacheln vom Ziel neu schicken
const REISSUE_MIN_TILES := 15.0
## Helden mit mehr als diesem Lebensanteil ziehen immer mit der Welle
const HERO_WAVE_HP := 0.6


# ---------------------------------------------------------------------------
# Beschwören
# ---------------------------------------------------------------------------

## Soll-Grösse der Armee: Stützpunkte size_by_minute (linear dazwischen) × Faktor der
## Schwierigkeit × Faktor der Persönlichkeit; vor economy_first_minutes höchstens early_fighters
static func army_target(b: AIBrain, now: float) -> int:
	var points: Array = DataDB.ai("army.size_by_minute", [[0, 2]])
	var m := b.minutes(now)
	var value := float((points[0] as Array)[1]) if not points.is_empty() else 2.0
	for i in points.size():
		var p: Array = points[i]
		if m >= float(p[0]):
			value = float(p[1])
			if i + 1 < points.size():
				var q: Array = points[i + 1]
				var span := maxf(float(q[0]) - float(p[0]), 0.001)
				value = lerpf(float(p[1]), float(q[1]), clampf((m - float(p[0])) / span, 0.0, 1.0))
	value *= float(b.diff.get("army_size_mult", 1.0)) * float(b.personality.get("army_mult", 1.0))
	if not b.time_ok(now, float(DataDB.ai("army.economy_first_minutes", 12))):
		value = minf(value, float(DataDB.ai("army.early_fighters", 2)))
	return maxi(roundi(value), int(b.st.get("debug_army_min", 0)))


## Späher an der Burg und Truppen in Kaserne, Krankenstation usw., bis das Soll
## erreicht ist. Stufe mit dem grössten Rückstand gegenüber army.composition zuerst.
## Bezahlt wird nur, was die Reserve (und den gerade gesparten Bauplan) übrig lässt.
static func tick_summon(b: AIBrain, now: float) -> void:
	var k := b.k
	var ss: SummonSystem = b.game.summon_system
	# Späher
	if b.time_ok(now, float(DataDB.ai("army.economy_first_minutes", 12))) and is_instance_valid(k.castle):
		var scouts := _count_tier(k, "scout")
		if scouts < int(DataDB.ai("army.scouts", 2)) and k.castle.summon_queue.is_empty():
			for def in ss.get_options(k.castle):
				var id := str(def.get("id", ""))
				if str(def.get("tier", "")) == "scout" and ss.can_summon(k.castle, id).is_empty() \
						and b.can_spend(ss.get_cost(k, id)):
					ss.summon(k.castle, id)
					break
	# Kämpfer
	var target := army_target(b, now)
	var counts := {}
	var total := 0
	for u in b.army_units():
		counts[u.tier] = int(counts.get(u.tier, 0)) + 1
		total += 1
	for bld in k.buildings:
		for entry in bld.summon_queue:
			var tier := str(DataDB.get_unit_type(str(entry.get("type_id", ""))).get("tier", ""))
			if tier != "scout" and tier != "spy" and tier != "hero":
				counts[tier] = int(counts.get(tier, 0)) + 1
				total += 1
	if total >= target:
		return
	var composition: Dictionary = (DataDB.ai("army.composition", {}) as Dictionary).duplicate()
	# Belagerungswaffen gegen befestigte Ziele (Phase 9)
	composition.merge(AISiege.extra_composition(b))
	var alarm: Dictionary = b.st["alarm"]
	var max_queue := int(DataDB.ai("army.max_queue_per_building", 2))
	for bld in k.buildings:
		if total >= target:
			return
		if not _is_troop_building(bld) or bld.summon_queue.size() >= max_queue:
			continue
		if not bld.has_rally:
			ss.set_rally(bld, b.home_rally())
		# Optionen nach Rückstand gegenüber der Zusammensetzung sortieren
		var options: Array = []
		var weight_sum := 0.0
		for def in ss.get_options(bld):
			var tier := str(def.get("tier", ""))
			if tier == "scout" or tier == "spy" or str(def.get("role", "")) == "hero" or not composition.has(tier):
				continue
			if not k.has_all_unlocks(def.get("requires", [])):
				continue
			options.append(def)
			weight_sum += float(composition[tier])
		if options.is_empty():
			continue
		var scored: Array = []
		for def in options:
			var tier := str(def.get("tier", ""))
			var deficit := float(composition[tier]) / maxf(weight_sum, 0.001) * float(total + 1) - float(counts.get(tier, 0))
			scored.append([deficit, def])
		scored.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
		for pair in scored:
			var def: Dictionary = pair[1]
			var id := str(def.get("id", ""))
			# Bei Alarm ohne Rücksicht auf Reserve und Sparziele
			if not ss.can_summon(bld, id).is_empty() or not b.can_spend(ss.get_cost(k, id), alarm.is_empty()):
				continue
			if ss.summon(bld, id):
				var tier := str(def.get("tier", ""))
				counts[tier] = int(counts.get(tier, 0)) + 1
				total += 1
				b.log_first("first_summon", now)
				break


## Gebäude, in dem Truppen beschworen werden (nicht Burg, Heldenhalle, Spionagehaus)
static func _is_troop_building(bld: Building) -> bool:
	if not bld.constructed or bld == bld.kingdom.castle:
		return false
	if bool(bld.def.get("hero_hall", false)) or bool(bld.def.get("spy_den", false)):
		return false
	return not (bld.def.get("summons", []) as Array).is_empty()


## Lebende eigene Einheiten einer Stufe plus Einträge in den Warteschlangen
static func _count_tier(k: Kingdom, tier: String) -> int:
	var n := 0
	for u in k.units:
		if u.tier == tier and u.is_alive():
			n += 1
	for bld in k.buildings:
		for entry in bld.summon_queue:
			if str(DataDB.get_unit_type(str(entry.get("type_id", ""))).get("tier", "")) == tier:
				n += 1
	return n


# ---------------------------------------------------------------------------
# Helden
# ---------------------------------------------------------------------------

## Anwerben (ab heroes.min_minute, Halle fertig, Platz frei, Kosten × reserve_factor da),
## offene Stufenwahlen treffen, Fähigkeiten selbst auslösen lassen, Gefallene
## wiederbeleben und in Ruhezeiten ausbilden
static func tick_heroes(b: AIBrain, now: float) -> void:
	var k := b.k
	var hs: HeroSystem = b.game.hero_system
	# Anwerben (bis es bezahlbar ist, wird darauf gespart: AIBrain.reserve_cost)
	b.st["hero_saving"] = ""
	if b.time_ok(now, float(DataDB.ai("heroes.min_minute", 40))) and hs.get_hall(k) != null \
			and hs.count_heroes(k) < int(b.diff.get("max_heroes", 2)):
		var factor := float(DataDB.ai("heroes.reserve_factor", 1.3))
		var offers: Array = []
		var possible := ""
		for def in hs.get_offers(k):
			var id := str(def.get("id", ""))
			if not hs.can_recruit(k, id).is_empty():
				continue
			possible = id
			var cost := hs.recruit_cost(k, id)
			var scaled := {}
			for res in cost:
				# Nie mehr verlangen, als das Lager fassen kann (Mana)
				scaled[res] = minf(float(cost[res]) * factor, maxf(k.get_capacity(str(res)), float(cost[res])))
			if k.can_afford(scaled):
				offers.append(id)
		if not offers.is_empty():
			var pick := str(offers[mini(int(b.sys.rand_float() * offers.size()), offers.size() - 1)])
			if hs.recruit(k, pick):
				b.log_first("first_hero", now)
		elif not possible.is_empty():
			b.st["hero_saving"] = possible
	var prefer := str(DataDB.ai("heroes.prefer_kind", "ability"))
	var busy := not (b.st["alarm"] as Dictionary).is_empty() or not (b.st["wave"] as Dictionary).is_empty()
	for rec in k.heroes.duplicate():
		var hero_id := int(rec["id"])
		# Stufenwahl (alle offenen)
		var guard := 0
		while int(rec["pending"]) > 0 and guard < 12:
			guard += 1
			var options := hs.get_levelup_options(k, hero_id)
			if options.is_empty():
				break
			var chosen: Dictionary = options[0]
			for o in options:
				if str(o.get("kind", "")) == prefer:
					chosen = o
					break
			if not hs.choose_upgrade(k, hero_id, str(chosen["id"])):
				break
		# Gelernte Fähigkeiten selbst auslösen lassen (Wirken übernimmt das HeroSystem)
		for aid in hs.get_type(rec).get("abilities", []):
			var ability_id := str(aid)
			var def := DataDB.get_ability(ability_id)
			if hs.get_rank(rec, ability_id) <= 0 or hs.is_autocast(rec, ability_id) or str(def.get("kind", "")) != "active":
				continue
			if bool(def.get("ai_autocast", false)) or bool(def.get("autocast", false)) \
					or str(def.get("target", "")) in ["enemy", "none"]:
				hs.set_autocast(k, hero_id, ability_id, true)
		if bool(rec["dead"]):
			if bool(DataDB.ai("heroes.revive", true)) and hs.can_revive(k, hero_id).is_empty():
				hs.revive(k, hero_id)
			continue
		if busy or not bool(DataDB.ai("heroes.train", true)) or not hs.can_train(k, hero_id).is_empty():
			continue
		var train_cost: Dictionary = DataDB.hero_cfg("training.cost", {})
		var doubled := {}
		for res in train_cost:
			doubled[res] = float(train_cost[res]) * 2.0
		if k.can_afford(doubled):
			hs.train(k, hero_id)


# ---------------------------------------------------------------------------
# Verteidigung
# ---------------------------------------------------------------------------

## Alle defense.scan_interval Sekunden: sichtbare feindliche Einheiten (keine Monster)
## im eigenen Gebiet -> Alarm. Bei Alarm ziehen die Heimtruppen (ohne home_guard_share)
## im Angriffsmarsch zum Alarmort; eine Welle beim Sammeln wird abgebrochen, eine nahe
## Welle zurückgerufen, wenn zu Hause die Kraft fehlt. Nach calm_seconds Ruhe zurück.
static func fast_defense(b: AIBrain, now: float) -> void:
	if now >= b.next_scan:
		b.next_scan = now + float(DataDB.ai("defense.scan_interval", 2))
		var found := _scan_enemies(b)
		if not found.is_empty():
			b.enemy_power = float(found["power"])
			b.on_alarm(found["pos"], int(found["kingdom_id"]))
	var alarm: Dictionary = b.st["alarm"]
	if alarm.is_empty():
		return
	var rally := b.home_rally()
	if now > float(alarm["until"]) and now - float(alarm["last_enemy"]) > float(DataDB.ai("defense.calm_seconds", 20)):
		# Ruhe: Verteidiger zurück an den Sammelpunkt
		var back: Array = []
		for u in b.units_of(b.st["defending"]):
			if u.target == null or not is_instance_valid(u.target):
				back.append(u)
		if not back.is_empty():
			b.game.command_system.order_move(back, rally, false)
		b.st["alarm"] = {}
		b.st["defending"] = []
		b.enemy_power = 0.0
		return
	# Welle in der Nähe: beim Sammeln abbrechen, sonst bei Unterlegenheit zurückrufen
	var wave: Dictionary = b.st["wave"]
	if not wave.is_empty():
		if str(wave["state"]) == "gather":
			end_wave(b, now, "recalled")
		elif str(wave["state"]) == "march" or str(wave["state"]) == "fight":
			var wave_units := b.units_of(wave["uids"])
			var dist_tiles := AIBrain.centroid(wave_units).distance_to(b.home_center()) / float(b.world.tile_size)
			if dist_tiles < float(DataDB.ai("defense.recall_distance", 60)) and b.power_of(b.home_pool()) < b.enemy_power:
				start_retreat(b, now, "recalled")
	if now < float(alarm.get("next_order", 0.0)):
		return
	alarm["next_order"] = now + DEFENSE_ORDER_INTERVAL
	var pool := b.home_pool()
	if pool.is_empty():
		return
	# Die nächsten zum Sammelpunkt bleiben als Wache (home_guard_share)
	pool.sort_custom(func(x: Unit, y: Unit) -> bool:
		return x.position.distance_squared_to(rally) < y.position.distance_squared_to(rally))
	var guard := floori(pool.size() * float(DataDB.ai("defense.home_guard_share", 0.3)))
	var defenders: Array = pool.slice(mini(guard, pool.size() - 1))
	var send: Array = []
	for u in defenders:
		if u.target == null or not is_instance_valid(u.target):
			send.append(u)
	if not send.is_empty():
		b.game.command_system.order_move(send, alarm["pos"], true)
	var uids: Array = b.st["defending"]
	for u in defenders:
		if not uids.has(u.uid):
			uids.append(u.uid)


## Sichtbare feindliche Einheiten (Reiche und Dörfer im Krieg, keine Monster) im
## eigenen Gebiet: {"pos", "kingdom_id", "count", "power"} oder {}
static func _scan_enemies(b: AIBrain) -> Dictionary:
	var k := b.k
	var world := b.world
	var index: SpatialIndex = b.game.combat_system.index
	var center := b.home_center()
	var radius := (b.territory_radius_tiles() + 1.0) * float(world.tile_size)
	var best := {}
	for kid in index.kingdom_ids():
		if int(kid) == k.id:
			continue
		var other: Kingdom = b.game.get_kingdom(int(kid))
		if other == null or other.controller == "wild" or not b.game.are_hostile(k, other):
			continue
		if not index.any_of_kingdom(center, radius, int(kid)):
			continue
		var count := 0
		var pos_sum := Vector2.ZERO
		var power := 0.0
		for u in index.query_kingdom(center, radius, int(kid)):
			if u.hp <= 0.0 or u.inside != null or not b.game.can_see(k, u):
				continue
			if world.get_owner(world.world_to_cell(u.position)) != k.id:
				continue
			count += 1
			pos_sum += u.position
			power += b.power(u)
		if count > 0 and power > float(best.get("power", 0.0)):
			best = {"pos": pos_sum / float(count), "kingdom_id": int(kid), "count": count, "power": power}
	return best


## Hilfe für ein Dorf (Schutzvertrag, Bote): help_share der Heimtruppen (mindestens
## help_min_units) ziehen hin, wenn es nicht weiter als help_distance Kacheln ist;
## nach Ablauf zurück
static func fast_help(b: AIBrain, now: float) -> void:
	var help: Dictionary = b.st["help"]
	if help.is_empty():
		return
	var helpers := b.units_of(help.get("uids", []))
	if now >= float(help.get("until", 0.0)):
		if not helpers.is_empty():
			b.game.command_system.order_move(helpers, b.home_rally(), false)
		b.st["help"] = {}
		return
	if not helpers.is_empty():
		return
	var pos: Vector2 = help["pos"]
	var ts := float(b.world.tile_size)
	var village: Kingdom = b.game.get_kingdom(int(help.get("village_id", 0)))
	var min_units := int(DataDB.ai("villages.help_min_units", 3))
	var pool := b.home_pool()
	if village == null or village.defeated or pool.size() < min_units \
			or b.home_center().distance_to(pos) > float(DataDB.ai("villages.help_distance", 80)) * ts \
			or not (b.st["alarm"] as Dictionary).is_empty():
		b.st["help"] = {}
		return
	pool.sort_custom(func(x: Unit, y: Unit) -> bool:
		return x.position.distance_squared_to(pos) < y.position.distance_squared_to(pos))
	var n := clampi(ceili(pool.size() * float(DataDB.ai("villages.help_share", 0.3))), min_units, pool.size())
	var sent: Array = pool.slice(0, n)
	b.game.command_system.order_move(sent, pos, true)
	help["uids"] = AIBrain.uids_of(sent)


# ---------------------------------------------------------------------------
# Angriffswellen
# ---------------------------------------------------------------------------

## Plant eine Welle (keine läuft, kein Alarm): Ziele Spieler, Rivale (Krieg und
## entdeckt), Dorf (Krieg, Verbündeter eines Feindes oder schwach bei Eroberern),
## Monsterlager in der Nähe. Wertung nach Gewicht, Aggression, Entfernung und
## geschätzter Abwehr; die Welle muss stark genug sein (strength_ratio).
static func plan_wave(b: AIBrain, now: float) -> void:
	var last := float(b.st["last_wave_end"])
	var interval := float(b.diff.get("wave_interval", 900))
	if last >= 0.0 and now - last < interval * 0.5:
		return
	var pool := _sorted_pool(b)
	if pool.is_empty():
		return
	var best := {}
	var best_score := 0.0
	for cand in _candidates(b, now):
		var c: Dictionary = cand
		if str(c["kind"]) != "lair" and last >= 0.0 and now - last < interval:
			continue
		var units := _select_units(b, c, pool)
		if units.is_empty():
			continue
		var wave_power := b.power_of(units)
		var ratio := 1.0 if str(c["kind"]) == "lair" else float(DataDB.ai("waves.strength_ratio", 1.2))
		if wave_power < ratio * float(c["defense"]):
			continue
		var score := _score(b, c)
		if score > best_score:
			best_score = score
			best = c
			best["units"] = units
	if not best.is_empty():
		start_wave(b, now, best, best["units"])


## Heimtruppen nach Stärke absteigend; gesunde Helden zuerst (ziehen immer mit)
static func _sorted_pool(b: AIBrain) -> Array:
	var pool := b.home_pool()
	pool.sort_custom(func(x: Unit, y: Unit) -> bool:
		var hx := x.hero_id != 0 and x.hp > x.max_hp * HERO_WAVE_HP
		var hy := y.hero_id != 0 and y.hp > y.max_hp * HERO_WAVE_HP
		if hx != hy:
			return hx
		return VillageSystem.unit_power(x) > VillageSystem.unit_power(y))
	return pool


## Mögliche Ziele: [{"kind": "player"|"rival"|"village"|"lair", "kingdom": Kingdom,
## "uid": int (Halle/Höhle, sonst 0), "pos": Vector2, "defense": float, "tiles": float}]
static func _candidates(b: AIBrain, now: float) -> Array:
	var k := b.k
	var list: Array = []
	var home := b.home_center()
	var ts := float(b.world.tile_size)
	var discovered := float(DataDB.esp("awareness.discovered", 60))
	for o in b.game.kingdoms:
		var other: Kingdom = o
		if other == k or other.defeated or not is_instance_valid(other.castle):
			continue
		if (other.controller != "player" and other.controller != "ai") or not b.game.are_hostile(k, other):
			continue
		if other.controller == "player" and not b.time_ok(now, float(b.diff.get("first_attack_minutes", 45))):
			continue
		if not b.sys.debug_fast and b.sys.get_awareness(k, other) < discovered:
			continue
		var pos := other.castle.get_approach_point(home)
		list.append({"kind": "player" if other.controller == "player" else "rival", "kingdom": other, "uid": 0,
				"pos": pos, "defense": b.sys.estimate_defense(k, other), "tiles": home.distance_to(pos) / ts})
	var vs: VillageSystem = b.game.village_system
	var ds: DiplomacySystem = b.game.diplomacy_system
	if b.time_ok(now, float(b.diff.get("first_village_attack_minutes", 30))):
		var conqueror := str(b.personality.get("village_style", "")) == "conqueror"
		var pool_power := b.power_of(b.home_pool())
		var max_tiles := float(DataDB.ai("villages.max_distance", 140))
		for v in vs.get_villages():
			var hall := vs.get_hall(v)
			if hall == null:
				continue
			var tiles := home.distance_to(hall.get_center()) / ts
			if tiles > max_tiles:
				continue
			var strength := vs.get_strength(v)
			var reason: bool = b.game.are_hostile(k, v)
			var treaty := ds.get_treaty(v)
			if not reason and not treaty.is_empty() and str(treaty.get("type", "")) == "alliance":
				var partner: Kingdom = b.game.get_kingdom(int(treaty.get("partner_id", 0)))
				reason = partner != null and partner != k and b.game.are_hostile(k, partner)
			if not reason and conqueror and treaty.is_empty() \
					and strength * float(DataDB.ai("villages.attack_weak_ratio", 2.5)) < pool_power:
				reason = true
			if not reason:
				continue
			var pos := hall.get_approach_point(home)
			list.append({"kind": "village", "kingdom": v, "uid": hall.uid, "pos": pos, "defense": strength, "tiles": tiles})
	if b.time_ok(now, float(DataDB.ai("lairs.min_minute", 10))):
		var max_lair := float(DataDB.ai("lairs.max_distance", 40))
		var ms: MonsterSystem = b.game.monster_system
		for lair in ms.lairs:
			if not is_instance_valid(lair):
				continue
			var lb: Building = lair
			var tiles := home.distance_to(lb.get_center()) / ts
			if tiles > max_lair:
				continue
			var defense := 0.0
			for m in ms.lairs[lair]:
				if is_instance_valid(m) and (m as Unit).is_alive():
					defense += VillageSystem.unit_power(m)
			list.append({"kind": "lair", "kingdom": lb.kingdom, "uid": lb.uid, "pos": lb.get_approach_point(home),
					"defense": defense, "tiles": tiles})
	return list


## Einheiten für eine Welle gegen das Ziel: Anteil waves.share des Heimbestands, mindestens
## die Mindestgrösse (Lager: lairs.min_army, sonst wave_min_size); gegen den Spieler
## höchstens first_wave_max (+ growth_per_wave je früherer Welle). [] = zu wenige.
static func _select_units(b: AIBrain, cand: Dictionary, pool: Array) -> Array:
	var kind := str(cand["kind"])
	var min_size := int(DataDB.ai("lairs.min_army", 6)) if kind == "lair" else int(b.diff.get("wave_min_size", 6))
	var max_units := pool.size()
	if kind == "player":
		max_units = int(b.diff.get("first_wave_max", 8)) + int(DataDB.ai("waves.growth_per_wave", 3)) * int(b.st["player_waves"])
		min_size = mini(min_size, max_units)
	var n := mini(maxi(ceili(pool.size() * float(DataDB.ai("waves.share", 0.7))), min_size), mini(max_units, pool.size()))
	if n < min_size or n <= 0:
		return []
	return pool.slice(0, n)


## Wertung eines Ziels: Gewicht × Aggression (nicht bei Lagern) / (1 + distance_weight × Kacheln)
## / Wurzel der geschätzten Abwehr
static func _score(b: AIBrain, cand: Dictionary) -> float:
	var kind := str(cand["kind"])
	var weights: Dictionary = DataDB.ai("waves.target_weights", {})
	var score := float(weights.get(kind, 0.5))
	if kind != "lair":
		score *= float(b.personality.get("aggression", 1.0))
	score /= 1.0 + float(DataDB.ai("waves.distance_weight", 0.004)) * float(cand["tiles"])
	return score / sqrt(maxf(float(cand["defense"]), 1.0))


## Welle starten: Einheiten sammeln sich am Gebietsrand in Richtung Ziel
static func start_wave(b: AIBrain, now: float, cand: Dictionary, units: Array) -> void:
	var k := b.k
	var world := b.world
	var target: Kingdom = cand["kingdom"]
	var kind := str(cand["kind"])
	if kind == "village" and not b.game.are_hostile(k, target):
		(b.game.diplomacy_system as DiplomacySystem).declare_war(k, target)
	var home := b.home_center()
	var target_pos: Vector2 = cand["pos"]
	var dir := (target_pos - home).normalized() if target_pos.distance_to(home) > 1.0 else Vector2.DOWN
	var rally_px := home + dir * (b.territory_radius_tiles() + 4.0) * float(world.tile_size)
	if home.distance_to(target_pos) < home.distance_to(rally_px):
		rally_px = home.lerp(target_pos, 0.5)
	var cell: Vector2i = b.game.nav.nearest_free(world.world_to_cell(rally_px), 6)
	var rally := world.cell_to_world(cell) if cell.x >= 0 else rally_px
	b.st["wave_counter"] = int(b.st["wave_counter"]) + 1
	var power := b.power_of(units)
	b.st["wave"] = {"id": int(b.st["wave_counter"]), "target_id": target.id, "target_kind": "lair" if kind == "lair" \
			else ("village" if kind == "village" else "kingdom"), "target_uid": int(cand.get("uid", 0)),
			"target_pos": target_pos, "rally": rally, "uids": AIBrain.uids_of(units), "state": "gather",
			"started_at": now, "state_at": now, "start_power": power, "next_reissue": now,
			"vs_player": kind == "player"}
	b.st["waves_sent"] = int(b.st["waves_sent"]) + 1
	if kind == "player":
		b.st["player_waves"] = int(b.st["player_waves"]) + 1
		b.log_first("first_player_wave", now)
	b.log_first("first_lair" if kind == "lair" else "first_wave", now)
	b.game.command_system.order_move(units, rally, false)
	b.sys.notify_wave_started(k, target, units.size(), rally)


## Welle sofort planen, ohne Sperren (Debug, Rauchtest). false, wenn niemand da ist.
static func force_wave(b: AIBrain, now: float, target: Kingdom) -> bool:
	if target == null or not b.is_active():
		return false
	if not (b.st["wave"] as Dictionary).is_empty():
		end_wave(b, now, "recalled")
	var pool := _sorted_pool(b)
	if pool.is_empty():
		return false
	var home := b.home_center()
	var cand := {}
	if is_instance_valid(target.castle):
		cand = {"kind": "player" if target.controller == "player" else "rival", "kingdom": target, "uid": 0,
				"pos": target.castle.get_approach_point(home), "defense": 0.0, "tiles": 0.0}
	elif (b.game.village_system as VillageSystem).get_hall(target) != null:
		var hall := (b.game.village_system as VillageSystem).get_hall(target)
		cand = {"kind": "village", "kingdom": target, "uid": hall.uid, "pos": hall.get_approach_point(home),
				"defense": 0.0, "tiles": 0.0}
	else:
		return false
	start_wave(b, now, cand, pool)
	return true


## Zustandsmaschine der Welle (jede Spielsekunde): gather -> march -> fight, Rückzug
## bei zu hohen Verlusten oder nach max_duration
static func fast_wave(b: AIBrain, now: float) -> void:
	var wave: Dictionary = b.st["wave"]
	if wave.is_empty():
		return
	var units := b.units_of(wave["uids"])
	wave["uids"] = AIBrain.uids_of(units)
	if units.is_empty():
		end_wave(b, now, "lost")
		return
	var cmd: CommandSystem = b.game.command_system
	var ts := float(b.world.tile_size)
	var state := str(wave["state"])
	var target_pos: Vector2 = wave["target_pos"]
	if state == "retreat":
		var rally := b.home_rally()
		var near := 0
		for u in units:
			if u.position.distance_to(rally) <= 10.0 * ts:
				near += 1
		if near >= ceili(units.size() * 0.8) or now - float(wave["state_at"]) > RETREAT_MAX_SECONDS:
			end_wave(b, now, str(wave.get("end_reason", "retreat")))
		return
	if state != "gather":
		if b.power_of(units) < float(b.diff.get("retreat_ratio", 0.4)) * float(wave["start_power"]):
			start_retreat(b, now, "retreat")
			return
		if now - float(wave["started_at"]) > float(DataDB.ai("waves.max_duration", 900)):
			start_retreat(b, now, "timeout")
			return
	if _target_defeated(b, wave):
		if state == "fight" or state == "march":
			cmd.order_move(units, b.home_rally(), false)
		end_wave(b, now, "won" if state == "fight" or state == "march" else "target_gone")
		return
	match state:
		"gather":
			var rally: Vector2 = wave["rally"]
			var near := 0
			for u in units:
				if u.position.distance_to(rally) <= float(DataDB.ai("waves.gather_radius", 8)) * ts:
					near += 1
			if near >= ceili(units.size() * 0.8) or now - float(wave["state_at"]) >= float(DataDB.ai("waves.gather_seconds", 60)):
				cmd.order_move(units, target_pos, true)
				wave["state"] = "march"
				wave["state_at"] = now
				wave["next_reissue"] = now + float(DataDB.ai("waves.reissue_seconds", 30))
		"march":
			var fight_r := float(DataDB.ai("waves.fight_building_radius", 14)) * ts
			var near := 0
			for u in units:
				if u.position.distance_to(target_pos) <= fight_r:
					near += 1
			AISiege.wave_tick(b, wave, now)
			if near >= ceili(units.size() * 0.5):
				wave["state"] = "fight"
				wave["state_at"] = now
				wave["next_reissue"] = now
			elif now >= float(wave["next_reissue"]):
				wave["next_reissue"] = now + float(DataDB.ai("waves.reissue_seconds", 30))
				var stuck: Array = []
				for u in units:
					if (u.command == "hold" or u.command.is_empty()) and (u.target == null or not is_instance_valid(u.target)) \
							and u.position.distance_to(target_pos) > REISSUE_MIN_TILES * ts:
						stuck.append(u)
				if not stuck.is_empty():
					cmd.order_move(stuck, target_pos, true)
		"fight":
			AISiege.wave_tick(b, wave, now)
			if now >= float(wave["next_reissue"]):
				wave["next_reissue"] = now + FIGHT_ORDER_INTERVAL
				_fight_orders(b, now, wave, units)


## Kampf am Ziel: untätige Einheiten greifen sichtbare Feinde in der Nähe an
## (Angriffsmarsch), sonst ein Gebäude des Ziels (Burg, Dorfzentrum, Höhle zuerst)
static func _fight_orders(b: AIBrain, now: float, wave: Dictionary, units: Array) -> void:
	var idle: Array = []
	for u in units:
		if (u.command == "hold" or u.command.is_empty()) and (u.target == null or not is_instance_valid(u.target)):
			idle.append(u)
	if idle.is_empty():
		return
	var cmd: CommandSystem = b.game.command_system
	var target: Kingdom = b.game.get_kingdom(int(wave["target_id"]))
	var center := AIBrain.centroid(units)
	var ts := float(b.world.tile_size)
	var fight_r := float(DataDB.ai("waves.fight_building_radius", 14)) * ts
	# Feinde des Ziels in der Nähe der Welle
	var foe := _nearest_enemy_unit(b, target, center, fight_r)
	if foe != null:
		cmd.order_move(idle, foe.position, true)
		return
	var bld := _target_building(b, wave, target, fight_r)
	if bld != null:
		cmd.order_attack(idle, bld)
		return
	# Nichts mehr zu tun am Ziel
	cmd.order_move(units, b.home_rally(), false)
	end_wave(b, now, "won")


## Nächste sichtbare lebende Einheit des Ziels im Umkreis (null = keine)
static func _nearest_enemy_unit(b: AIBrain, target: Kingdom, pos: Vector2, radius: float) -> Unit:
	if target == null:
		return null
	var index: SpatialIndex = b.game.combat_system.index
	var best: Unit = null
	var best_d := INF
	for u in index.query_kingdom(pos, radius, target.id):
		if u.hp <= 0.0 or u.inside != null or not b.game.can_see(b.k, u):
			continue
		var d := pos.distance_squared_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	return best


## Angriffsziel am Zielort: Burg (Reich), Dorfzentrum (Dorf) oder Höhle (Lager), sonst
## das nächste Gebäude des Ziels im Kampfgebiet (null = keins mehr)
static func _target_building(b: AIBrain, wave: Dictionary, target: Kingdom, radius: float) -> Building:
	var target_pos: Vector2 = wave["target_pos"]
	var uid := int(wave.get("target_uid", 0))
	if uid != 0:
		var e: Variant = b.game.find_by_uid(uid)
		if e is Building and is_instance_valid(e) and b.game.are_hostile(b.k, (e as Building).kingdom):
			return e
	if target == null or not b.game.are_hostile(b.k, target):
		return null
	if str(wave["target_kind"]) == "kingdom" and is_instance_valid(target.castle):
		return target.castle
	var best: Building = null
	var best_d := INF
	for bld in target.buildings:
		var d := target_pos.distance_to(bld.get_center())
		if d <= radius * 1.5 and d < best_d:
			best_d = d
			best = bld
	return best


## Ist das Ziel der Welle erledigt? (Reich besiegt oder ohne Burg, Dorf nicht mehr
## selbstständig, Höhle zerstört)
static func _target_defeated(b: AIBrain, wave: Dictionary) -> bool:
	var target: Kingdom = b.game.get_kingdom(int(wave["target_id"]))
	match str(wave["target_kind"]):
		"kingdom":
			return target == null or target.defeated or not is_instance_valid(target.castle)
		"village":
			return target == null or not (b.game.village_system as VillageSystem).is_village(target)
		"lair":
			var e: Variant = b.game.find_by_uid(int(wave.get("target_uid", 0)))
			return not (e is Building and is_instance_valid(e))
	return true


## Rückzug zum Sammelpunkt (Tarnung beim Rückzug, wenn bekannt)
static func start_retreat(b: AIBrain, now: float, reason: String) -> void:
	var wave: Dictionary = b.st["wave"]
	if wave.is_empty() or str(wave["state"]) == "retreat":
		return
	var units := b.units_of(wave["uids"])
	wave["state"] = "retreat"
	wave["state_at"] = now
	wave["end_reason"] = reason
	if not units.is_empty():
		b.game.command_system.order_move(units, b.home_rally(), false)
		if bool(DataDB.ai("spells.veil_on_retreat", true)):
			_cast_school(b, "stealth", AIBrain.centroid(units))


## Welle beenden: Einheiten gehören wieder zum Heimbestand
static func end_wave(b: AIBrain, now: float, reason: String) -> void:
	var wave: Dictionary = b.st["wave"]
	if wave.is_empty():
		return
	b.st["wave"] = {}
	b.st["last_wave_end"] = now
	b.sys.notify_wave_ended(b.k, b.game.get_kingdom(int(wave["target_id"])), reason)


# ---------------------------------------------------------------------------
# Zauber und Heldenfähigkeiten im Kampf
# ---------------------------------------------------------------------------

## Höchstens ein Zauber je Spielsekunde, nur bei Alarm oder kämpfender Welle (im
## Zauberbereich). Auswahl nach Zauberschule, nicht nach ids.
static func fast_spells(b: AIBrain, _now: float) -> void:
	var alarm: Dictionary = b.st["alarm"]
	var wave: Dictionary = b.st["wave"]
	var fighting := not wave.is_empty() and str(wave["state"]) == "fight"
	if alarm.is_empty() and not fighting:
		return
	_hero_abilities(b)
	if not is_instance_valid(b.k.king) or not b.k.king.is_alive():
		return
	var spots: Array = []
	if not alarm.is_empty():
		spots.append(alarm["pos"])
	if fighting:
		spots.append(AIBrain.centroid(b.units_of(wave["uids"])))
	var spells := DataDB.ai("spells", {}) as Dictionary
	for spot in spots:
		var pos: Vector2 = spot
		if _try_heal(b, pos, spells) or _try_combat(b, pos, spells):
			return
		if not alarm.is_empty() and pos == alarm["pos"]:
			if bool(spells.get("summon_when_defending", true)) and _cast_school(b, "summon", pos):
				return
			if _cast_enemy_zone(b, pos):
				return


## Heilzauber, wenn genug eigene Einheiten verletzt sind
static func _try_heal(b: AIBrain, pos: Vector2, spells: Dictionary) -> bool:
	var ms: MagicSystem = b.game.magic_system
	for sp in ms.get_spells(b.k):
		var id := str(sp["id"])
		if str(sp.get("school", "")) != "healing" or not ms.can_cast_now(b.k, id).is_empty():
			continue
		var hurt: Array = []
		for u in ms.get_targets(b.k, id, pos):
			if u.kingdom == b.k and u.hp < u.max_hp * float(spells.get("heal_below", 0.6)):
				hurt.append(u)
		if hurt.size() < int(spells.get("heal_min_units", 3)):
			continue
		var at := AIBrain.centroid(hurt)
		if ms.can_cast(b.k, id, at).is_empty() and ms.cast(b.k, id, at):
			return true
	return false


## Kampfzauber: Segen auf genug eigene Kämpfer, Flüche auf genug Feinde
static func _try_combat(b: AIBrain, pos: Vector2, spells: Dictionary) -> bool:
	var ms: MagicSystem = b.game.magic_system
	for sp in ms.get_spells(b.k):
		var id := str(sp["id"])
		if str(sp.get("school", "")) != "combat" or not ms.can_cast_now(b.k, id).is_empty():
			continue
		var side := ms.get_target_side(id)
		var targets := ms.get_targets(b.k, id, pos)
		var need := int(spells.get("buff_min_units", 6)) if side == "own" else int(spells.get("curse_min_enemies", 5))
		if targets.size() < need:
			continue
		var at := AIBrain.centroid(targets)
		if ms.can_cast(b.k, id, at).is_empty() and ms.cast(b.k, id, at):
			return true
	return false


## Wetterzone mit Wirkung auf Feinde (Nebel) am Alarmort
static func _cast_enemy_zone(b: AIBrain, pos: Vector2) -> bool:
	var ms: MagicSystem = b.game.magic_system
	for sp in ms.get_spells(b.k):
		var zone: Dictionary = sp.get("zone", {})
		if zone.is_empty():
			continue
		var hits_enemies := false
		for e in zone.get("effects", []):
			if str(e.get("side", "")) == "enemy":
				hits_enemies = true
		var id := str(sp["id"])
		if hits_enemies and ms.can_cast(b.k, id, pos).is_empty() and ms.cast(b.k, id, pos):
			return true
	return false


## Ersten bereiten Zauber dieser Schule an pos wirken (Beschwörung, Tarnung)
static func _cast_school(b: AIBrain, school: String, pos: Vector2) -> bool:
	var ms: MagicSystem = b.game.magic_system
	for sp in ms.get_spells(b.k):
		var id := str(sp["id"])
		if str(sp.get("school", "")) != school or bool(sp.get("realm_cloak", false)):
			continue
		if ms.can_cast(b.k, id, pos).is_empty() and ms.cast(b.k, id, pos):
			return true
	return false


## Helden wirken Fähigkeiten mit Ortsziel auf Feinde (z. B. Pfeilregen) und Schutz
## auf sich selbst, wenn sie verletzt sind (die übrigen löst das HeroSystem selbst aus)
static func _hero_abilities(b: AIBrain) -> void:
	var hs: HeroSystem = b.game.hero_system
	for rec in b.k.heroes:
		var u := hs.get_unit(b.k, int(rec["id"]))
		if u == null or u.target == null or not is_instance_valid(u.target):
			continue
		for aid in hs.get_type(rec).get("abilities", []):
			var ability_id := str(aid)
			var def := DataDB.get_ability(ability_id)
			if str(def.get("kind", "")) != "active" or hs.get_rank(rec, ability_id) <= 0 or hs.cooldown_left(rec, ability_id) > 0.0:
				continue
			match str(def.get("target", "")):
				"point":
					var t: Object = u.target
					if hs.get_ability_side(ability_id) == "enemy" and t is Unit and hs.can_use(u, ability_id, (t as Unit).position).is_empty():
						hs.use_ability(u, ability_id, (t as Unit).position)
						return
				"self":
					if u.hp < u.max_hp * 0.5 and hs.can_use(u, ability_id).is_empty():
						hs.use_ability(u, ability_id)
						return


## Zauber im Frieden (im Denkvorgang): Regen über den Höfen, wenn genug Mana da ist
static func tick_peace_spells(b: AIBrain, _now: float) -> void:
	if not (b.st["alarm"] as Dictionary).is_empty() or not is_instance_valid(b.k.king):
		return
	var cap := b.k.get_capacity("mana")
	if cap == INF or b.k.get_amount("mana") < cap * float(DataDB.ai("spells.rain_mana_ratio", 0.8)):
		return
	var ms: MagicSystem = b.game.magic_system
	var farms: Array = []
	for bld in b.k.buildings:
		if bld.constructed and str(bld.def.get("job", "")) == "farmer":
			farms.append(bld)
	if farms.is_empty():
		return
	var pos := AIBrain.centroid(farms)
	for sp in ms.get_spells(b.k):
		var zone: Dictionary = sp.get("zone", {})
		if zone.is_empty() or float(zone.get("production", 1.0)) <= 1.0:
			continue
		var id := str(sp["id"])
		if ms.can_cast(b.k, id, pos).is_empty() and ms.cast(b.k, id, pos):
			return
