## AIEconomy
##
## Wirtschaft eines KI-Reichs (Phase 7): Bauliste aus ai.json, reaktives Bauen
## (Wohnraum, Nahrung), Wachstum mit der Bevölkerung, Bauplatzsuche im eigenen
## Gebiet, Arbeitsverteilung der Bewohner, Forschung und Kampfpunkt-Verbesserungen.
## Nur statische Funktionen: der Zustand liegt im AIBrain bzw. in Kingdom.ai_state.
## Benutzt ausschliesslich öffentliche Schnittstellen – dieselben wie die Oberfläche
## des Spielers (BuildingSystem.can_place/place_building, WorkSystem.assign_job/
## unassign_job, ResearchSystem.can_start/start/buy_upgrade).
class_name AIEconomy
extends RefCounted

## Ergebnis eines Bauversuchs
enum Try { PLACED, WAIT, SKIP }

## Sammelberufe in fester Reihenfolge (Gewichte in ai.json jobs.weights)
const GATHER_JOBS := ["woodcutter", "gatherer", "stonecutter", "miner"]
## Gebäudeberufe (Arbeitsplätze in Höfen und Manabrunnen)
const BUILDING_JOBS := ["farmer", "mana_worker"]
## So lange wird ein Gebäude ohne passenden Bauplatz nicht erneut gesucht (Spielsekunden)
const NO_SITE_RETRY := 60.0
## Höchstens so viele Vorkommen-Gruppen werden für eine Sammelhütte geprüft
const MAX_CLUSTERS := 4
## Höfe: höchstens so viele passende Plätze vergleichen (bester Gelände-Faktor)
const MAX_FARM_CANDIDATES := 10


# ---------------------------------------------------------------------------
# Bauen
# ---------------------------------------------------------------------------

## Höchstens ein Gebäude je Denkvorgang: zuerst reaktiv (Wohnraum, Nahrung), dann
## die Bauliste, danach Wachstum mit der Bevölkerung.
static func tick_build(b: AIBrain, now: float) -> void:
	var k := b.k
	var bs: BuildingSystem = b.game.building_system
	var ws: WorkSystem = b.game.work_system
	var sites := bs.get_building_sites(k).size()
	var builders := ws.get_job_count(k, "builder")
	var max_sites := clampi(int(DataDB.ai("build.max_sites_base", 2)) + builders * int(DataDB.ai("build.max_sites_per_builders", 1)),
			1, int(DataDB.ai("build.max_sites", 4)))
	if sites >= max_sites:
		return
	var reactive := _reactive_need(b)
	if not reactive.is_empty() and _try_build(b, reactive, now) != Try.SKIP:
		return
	for entry in DataDB.ai("build_order", []):
		var id := str((entry as Dictionary).get("building", ""))
		if bs.count_buildings(k, id, false) >= int((entry as Dictionary).get("count", 1)):
			continue
		if _try_build(b, id, now) != Try.SKIP:
			return
	if k.buildings.size() < int(DataDB.ai("build.growth.max_buildings", 90)):
		var pop := float(k.get_population())
		for pair in [["house", "house_per_pop"], ["farm", "farm_per_pop"], ["storehouse", "storehouse_per_pop"],
				["lumberyard", "lumberyard_per_pop"]]:
			var per := float(DataDB.ai("build.growth." + str(pair[1]), 0.0))
			if per <= 0.0:
				continue
			var id := str(pair[0])
			if bs.count_buildings(k, id, false) < floori(pop / per) and _try_build(b, id, now) != Try.SKIP:
				return
	# Nichts mehr geplant: kein Geld zurückhalten
	b.st["build_waiting"] = {}


## Reaktiver Bedarf: "house" bei Wohnungsnot, "farm" bei Nahrungsmangel, sonst ""
static func _reactive_need(b: AIBrain) -> String:
	var k := b.k
	var bs: BuildingSystem = b.game.building_system
	var ws: WorkSystem = b.game.work_system
	if k.get_population() >= k.get_housing() - int(DataDB.ai("build.reactive.housing_margin", 2)) \
			and not _has_site(bs, k, "house"):
		return "house"
	var low := float(k.income_rate.get("food", 0.0)) < float(DataDB.ai("build.reactive.food_margin_per_min", 2.0)) \
			or k.get_amount("food") < float(DataDB.ai("build.reactive.food_low", 30))
	if low and bs.count_buildings(k, "farm", false) > 0 and not ws.has_free_slot(k, "farmer") and not _has_site(bs, k, "farm"):
		return "farm"
	return ""


static func _has_site(bs: BuildingSystem, k: Kingdom, id: String) -> bool:
	return bs.count_buildings(k, id, false) > bs.count_buildings(k, id, true)


## Versucht, ein Gebäude dieses Typs zu setzen. SKIP = nicht möglich (gesperrt, kein
## Platz, zu lange unbezahlbar), WAIT = Geld fehlt noch (wird zurückgehalten).
static func _try_build(b: AIBrain, id: String, now: float) -> Try:
	var k := b.k
	var bs: BuildingSystem = b.game.building_system
	var def := DataDB.get_building(id)
	if def.is_empty() or not bool(def.get("player_buildable", true)) or not bs.can_build_type(def, k).is_empty():
		return Try.SKIP
	var skip: Dictionary = b.st["skip_until"]
	if float(skip.get(id, -1.0)) > now:
		return Try.SKIP
	var waiting: Dictionary = b.st["build_waiting"]
	if not k.can_afford(def.get("cost", {})):
		var wait_s := float(DataDB.ai("build.wait_seconds", 90))
		if str(waiting.get("building", "")) != id:
			b.st["build_waiting"] = {"building": id, "since": now}
			return Try.WAIT
		if now - float(waiting.get("since", now)) > wait_s:
			# Zu lange unbezahlbar: eine Weile überspringen, das Geld wieder freigeben
			skip[id] = now + wait_s
			b.st["build_waiting"] = {}
			return Try.SKIP
		return Try.WAIT
	var cell := find_site(b, def)
	if cell.x < 0 or not bs.can_place(def, cell, k).is_empty():
		skip[id] = now + NO_SITE_RETRY
		return Try.SKIP
	if bs.place_building(def, cell, k) == null:
		return Try.SKIP
	if str(waiting.get("building", "")) == id:
		b.st["build_waiting"] = {}
	b.log_first("first_building", now)
	if id == "barracks":
		b.log_first("first_barracks", now)
	return Try.PLACED


# ---------------------------------------------------------------------------
# Bauplatzsuche (deterministisch, höchstens placement.max_checks Prüfungen je Denkvorgang)
# ---------------------------------------------------------------------------

## Obere linke Kachel für das Gebäude im eigenen Gebiet, (-1, -1) wenn keine passt.
## Manabrunnen auf Manaquellen, Sammelhütten an Vorkommen-Gruppen, Höfe auf gutem
## Gelände, alles andere ringförmig um die Burg.
static func find_site(b: AIBrain, def: Dictionary) -> Vector2i:
	if not is_instance_valid(b.k.castle):
		return Vector2i(-1, -1)
	var c0 := b.world.world_to_cell(b.k.castle.get_center())
	var rmax := ceili(b.territory_radius_tiles()) + 1
	var required := str(def.get("requires_deposit", ""))
	if not required.is_empty():
		return _site_on_deposit(b, def, required)
	var dropoff: Array = def.get("dropoff", [])
	if dropoff.size() == 1 and float(def.get("gather_bonus", 0.0)) > 0.0:
		return _site_for_gathering(b, def, str(dropoff[0]), c0)
	var castle_size: Vector2i = b.k.castle.size
	var r0 := (maxi(castle_size.x, castle_size.y) >> 1) + 2
	if not (def.get("biome_efficiency", {}) as Dictionary).is_empty():
		return _site_by_efficiency(b, def, c0, r0, rmax)
	return _spiral_fit(b, def, c0, r0, rmax)


## Passt das Gebäude hier hin? Billige Vorprüfung (eigenes Gebiet an den Ecken, Rand
## von placement.margin Kacheln frei, damit Wege offen bleiben), dann can_place.
static func _fits(b: AIBrain, def: Dictionary, cell: Vector2i) -> bool:
	if b.checks_left <= 0:
		return false
	var world := b.world
	var size: Vector2i = def.get("size", Vector2i(2, 2))
	var last := cell + size - Vector2i.ONE
	for corner in [cell, last, Vector2i(cell.x, last.y), Vector2i(last.x, cell.y)]:
		if world.get_owner(corner) != b.k.id:
			return false
	var m := int(DataDB.ai("placement.margin", 1))
	for y in range(cell.y - m, last.y + m + 1):
		for x in range(cell.x - m, last.x + m + 1):
			var c := Vector2i(x, y)
			if world.occupancy.has(c) or world.roads.has(c):
				return false
	b.checks_left -= 1
	return (b.game.building_system as BuildingSystem).can_place(def, cell, b.k).is_empty()


## Ringförmig um center (Mitte der Grundfläche), Ring r0 bis rmax: erster passender Platz
static func _spiral_fit(b: AIBrain, def: Dictionary, center: Vector2i, r0: int, rmax: int, step: int = 1) -> Vector2i:
	var size: Vector2i = def.get("size", Vector2i(2, 2))
	var half := Vector2i(size.x >> 1, size.y >> 1)
	for r in range(r0, rmax + 1, step):
		for off in ring(r, step):
			if b.checks_left <= 0:
				return Vector2i(-1, -1)
			var cell: Vector2i = center + off - half
			if _fits(b, def, cell):
				return cell
	return Vector2i(-1, -1)


## Versätze eines quadratischen Rings mit Radius r (Kacheln), Schrittweite step,
## in fester Reihenfolge (oben, unten, links, rechts)
static func ring(r: int, step: int = 1) -> Array:
	var list: Array = []
	if r <= 0:
		list.append(Vector2i.ZERO)
		return list
	for i in range(-r, r + 1, step):
		list.append(Vector2i(i, -r))
		list.append(Vector2i(i, r))
	for i in range(-r + step, r, step):
		list.append(Vector2i(-r, i))
		list.append(Vector2i(r, i))
	return list


## Manabrunnen: Ecken, deren Grundfläche eine Manaquelle im eigenen Gebiet enthält.
## Die Quellen werden nur neu gesucht, wenn sich Vorkommen oder Gebiet geändert haben.
static func _site_on_deposit(b: AIBrain, def: Dictionary, deposit_id: String) -> Vector2i:
	var world := b.world
	var dep_index := int(DataDB.deposit_index_by_id.get(deposit_id, -1))
	if dep_index < 0:
		return Vector2i(-1, -1)
	var rect := b.territory_rect()
	var key := "%s:%d:%s" % [deposit_id, world.deposit_version, str(rect)]
	if str(b.st["mana_spots_key"]) != key:
		var spots: Array = []
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var c := Vector2i(x, y)
				if world.get_deposit_index(c) == dep_index and world.get_owner(c) == b.k.id:
					spots.append(c)
		b.st["mana_spots"] = spots
		b.st["mana_spots_key"] = key
	var size: Vector2i = def.get("size", Vector2i(2, 2))
	for spot in b.st["mana_spots"]:
		var s: Vector2i = spot
		if world.occupancy.has(s):
			continue
		for dy in size.y:
			for dx in size.x:
				var cell := s - Vector2i(dx, dy)
				if _fits(b, def, cell):
					return cell
	return Vector2i(-1, -1)


## Sammelhütte: nächste Gruppe passender Vorkommen (Spirale um die Burg, Schrittweite 2,
## mindestens deposit_cluster_min im 5×5-Feld, nicht schon von einer gleichen Hütte
## versorgt), dann der nächste passende Platz im eigenen Gebiet in Sammelreichweite.
static func _site_for_gathering(b: AIBrain, def: Dictionary, res_id: String, c0: Vector2i) -> Vector2i:
	var world := b.world
	var job := gather_job_for(res_id)
	if job.is_empty():
		return _spiral_fit(b, def, c0, 3, ceili(b.territory_radius_tiles()))
	var mask: PackedByteArray = job.get("deposit_mask", PackedByteArray())
	var reach := maxi(int(def.get("gather_radius", 10)), 4)
	var search := int(DataDB.ai("placement.resource_search_radius", 26))
	var cluster_min := int(DataDB.ai("placement.deposit_cluster_min", 3))
	var same: Array = []
	for bld in b.k.buildings:
		if str(bld.def.get("id", "")) == str(def.get("id", "")):
			same.append(world.world_to_cell(bld.get_center()))
	var clusters := 0
	for r in range(0, search + 1, 2):
		for off in ring(r, 2):
			var cell: Vector2i = c0 + off
			if not world.in_bounds(cell) or world.is_dangerous(cell):
				continue
			var owner_id := world.get_owner(cell)
			if owner_id != 0 and owner_id != b.k.id:
				continue
			var covered := false
			for s in same:
				if absi((s as Vector2i).x - cell.x) <= reach * 0.6 and absi((s as Vector2i).y - cell.y) <= reach * 0.6:
					covered = true
					break
			if covered or _count_deposits(world, cell, mask) < cluster_min:
				continue
			var found := _spiral_fit(b, def, cell, 0, reach - 3)
			if found.x >= 0:
				return found
			clusters += 1
			if clusters >= MAX_CLUSTERS or b.checks_left <= 0:
				return Vector2i(-1, -1)
	return Vector2i(-1, -1)


## Anzahl sammelbarer Vorkommen (Berufs-Maske) im 5×5-Feld um cell
static func _count_deposits(world: WorldData, cell: Vector2i, mask: PackedByteArray) -> int:
	var n := 0
	for y in range(cell.y - 2, cell.y + 3):
		for x in range(cell.x - 2, cell.x + 3):
			if x < 0 or y < 0 or x >= world.width or y >= world.height:
				continue
			var i := y * world.width + x
			if mask[world.deposit_type[i]] != 0 and world.deposit_amount[i] != 0:
				n += 1
	return n


## Sammelberuf für eine Ressource (jobs.json, Typ gather), {} wenn keiner
static func gather_job_for(res_id: String) -> Dictionary:
	for j in DataDB.jobs:
		if str(j.get("type", "")) == "gather" and str(j.get("resource", "")) == res_id:
			return j
	return {}


## Höfe: der erste Platz mit Gelände-Faktor >= farm_min_efficiency, sonst der beste
## von höchstens MAX_FARM_CANDIDATES passenden
static func _site_by_efficiency(b: AIBrain, def: Dictionary, c0: Vector2i, r0: int, rmax: int) -> Vector2i:
	var bs: BuildingSystem = b.game.building_system
	var min_eff := float(DataDB.ai("placement.farm_min_efficiency", 0.9))
	var size: Vector2i = def.get("size", Vector2i(2, 2))
	var half := Vector2i(size.x >> 1, size.y >> 1)
	var best := Vector2i(-1, -1)
	var best_eff := -1.0
	var seen := 0
	for r in range(r0, rmax + 1):
		for off in ring(r):
			if b.checks_left <= 0:
				return best
			var cell: Vector2i = c0 + off - half
			if not _fits(b, def, cell):
				continue
			var eff := bs.estimate_efficiency(def, cell)
			if eff >= min_eff:
				return cell
			if eff > best_eff:
				best_eff = eff
				best = cell
			seen += 1
			if seen >= MAX_FARM_CANDIDATES:
				return best
	return best


# ---------------------------------------------------------------------------
# Berufe
# ---------------------------------------------------------------------------

## Verteilt die Bewohner (höchstens jobs.max_changes Wechsel): Unbeschäftigte zuerst,
## dann (jeden dritten Denkvorgang) vom grössten Überschuss zum grössten Mangel.
## Beschworene Kampfeinheiten bekommen keine Berufe.
static func tick_jobs(b: AIBrain) -> void:
	var k := b.k
	var ws: WorkSystem = b.game.work_system
	var counts := {}
	var workers := 0
	for u in k.units:
		if u.role != "worker" or not u.can_work() or not u.is_alive():
			continue
		workers += 1
		counts[u.job_id] = int(counts.get(u.job_id, 0)) + 1
	if workers == 0:
		return
	var targets := job_targets(b, workers)
	var max_changes := int(DataDB.ai("jobs.max_changes", 4))
	var changes := 0
	while changes < max_changes and ws.get_idle_count(k) > 0:
		var job := _largest_deficit(targets, counts, "")
		if job.is_empty() or not ws.assign_job(k, job):
			break
		counts[job] = int(counts.get(job, 0)) + 1
		counts["idle"] = int(counts.get("idle", 0)) - 1
		changes += 1
	if int(b.st["think_count"]) % 3 != 0:
		return
	while changes < max_changes:
		var to := _largest_deficit(targets, counts, "")
		if to.is_empty():
			break
		var from := _largest_surplus(targets, counts, to)
		if from.is_empty() or not ws.unassign_job(k, from):
			break
		counts[from] = int(counts.get(from, 0)) - 1
		changes += 1
		if not ws.assign_job(k, to):
			counts["idle"] = int(counts.get("idle", 0)) + 1
			break
		counts[to] = int(counts.get(to, 0)) + 1


## Soll-Verteilung der Bewohner: Beruf -> Anzahl (Summe = workers)
static func job_targets(b: AIBrain, workers: int) -> Dictionary:
	var k := b.k
	var ws: WorkSystem = b.game.work_system
	var bs: BuildingSystem = b.game.building_system
	var targets := {"idle": 0}
	var sites := bs.get_building_sites(k).size()
	var builders := clampi(sites * int(DataDB.ai("jobs.builders_per_site", 1)), int(DataDB.ai("jobs.builders_min", 1)),
			int(DataDB.ai("jobs.builders_max", 4)))
	builders = mini(builders, maxi(workers - 2, 1))
	targets["builder"] = builders
	var rest := workers - builders
	# Höfe voll besetzen, aber immer mindestens zwei Sammler (Holz) lassen
	var farmers := mini(maxi(ws.get_job_capacity(k, "farmer"), 0), maxi(rest - 2, 0))
	targets["farmer"] = farmers
	rest -= farmers
	var mana_cap := maxi(ws.get_job_capacity(k, "mana_worker"), 0)
	var mana := 0
	if rest >= 3 and mana_cap > 0:
		mana = mini(mana_cap, maxi(1, ceili(rest * 0.25)))
	targets["mana_worker"] = mana
	rest -= mana
	# Sammler nach Gewicht × (1 + Mangel)
	var weights: Dictionary = DataDB.ai("jobs.weights", {})
	var stock: Dictionary = DataDB.ai("jobs.target_stock", {})
	var food_low := float(DataDB.ai("build.reactive.food_low", 30))
	var farms := bs.count_buildings(k, "farm", true)
	var w := {}
	var total := 0.0
	for job in GATHER_JOBS:
		var res := str(DataDB.get_job(job).get("resource", ""))
		var value := float(weights.get(job, 1.0))
		var want := maxf(float(stock.get(res, 100.0)), 1.0)
		value *= 1.0 + maxf(want - k.get_amount(res), 0.0) / want
		if job == "gatherer":
			if k.starving or k.get_amount("food") < food_low:
				value *= float(DataDB.ai("jobs.hunger_gatherer_mult", 3.0))
			if farms >= int(DataDB.ai("jobs.gatherer_until_farms", 2)):
				value *= 0.5
		if not _has_gather_site(b, job):
			value = 0.0
		elif not ws.get_job_problem(k, job).is_empty():
			value *= 0.5
		w[job] = value
		total += value
	if total <= 0.0:
		w["woodcutter"] = 1.0
		total = 1.0
	# Grösste Reste zuerst (ganze Zahlen, Summe = rest)
	var assigned := 0
	var remainders: Array = []
	for job in GATHER_JOBS:
		var exact := float(rest) * float(w[job]) / total
		targets[job] = floori(exact)
		assigned += floori(exact)
		remainders.append([exact - floorf(exact), job])
	remainders.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
	var i := 0
	while assigned < rest and i < remainders.size():
		var job := str(remainders[i][1])
		targets[job] = int(targets[job]) + 1
		assigned += 1
		i += 1
	return targets


## Gibt es für den Sammelberuf eine passende Annahmestelle? Bergleute brauchen eine
## eigene Erzmine (Erz liegt meist ausserhalb der Reichweite der Burg).
static func _has_gather_site(b: AIBrain, job: String) -> bool:
	if job != "miner":
		return true
	var res := str(DataDB.get_job(job).get("resource", ""))
	for bld in b.k.buildings:
		if bld.accepts(res) and bld.get_gather_bonus() > 0.0:
			return true
	return false


## Beruf mit dem grössten Mangel (Soll − Ist >= 1), "" wenn keiner
static func _largest_deficit(targets: Dictionary, counts: Dictionary, exclude: String) -> String:
	var best := ""
	var best_d := 0
	for job in targets:
		if job == "idle" or job == exclude:
			continue
		var d := int(targets[job]) - int(counts.get(job, 0))
		if d > best_d:
			best_d = d
			best = str(job)
	return best


## Beruf mit dem grössten Überschuss (Ist − Soll >= 1), "" wenn keiner
static func _largest_surplus(targets: Dictionary, counts: Dictionary, exclude: String) -> String:
	var best := ""
	var best_d := 0
	for job in counts:
		if job == "idle" or job == exclude:
			continue
		var d := int(counts[job]) - int(targets.get(job, 0))
		if d > best_d:
			best_d = d
			best = str(job)
	return best


# ---------------------------------------------------------------------------
# Forschung und Kampfpunkte
# ---------------------------------------------------------------------------

## Eine Forschung einreihen (nur wenn keine läuft): bevorzugte Reihenfolge der Fraktion,
## sonst nach Zweig-Gewichten der Persönlichkeit und günstigster Stufe
static func tick_research(b: AIBrain, now: float) -> void:
	var k := b.k
	var rs: ResearchSystem = b.game.research_system
	if not b.time_ok(now, float(DataDB.ai("research.min_minute", 8))):
		return
	if rs.count_research_buildings(k) == 0 or k.research_queue.size() >= 1:
		return
	var pick := ""
	for id in (DataDB.ai("research.prefer", {}) as Dictionary).get(k.faction_id, []):
		if _can_research(b, rs, str(id)):
			pick = str(id)
			break
	if pick.is_empty():
		var weights: Dictionary = b.personality.get("branch_weights", {})
		var penalty := float(DataDB.ai("research.tier_penalty", 0.15))
		var best_score := -INF
		for r in rs.get_tree_for(k):
			var id := str(r["id"])
			if not _can_research(b, rs, id):
				continue
			var score := float(weights.get(str(r["branch"]), 1.0)) * (1.0 - penalty * (int(r["tier"]) - 1))
			if score > best_score:
				best_score = score
				pick = id
	if not pick.is_empty() and rs.start(k, pick):
		b.log_first("first_research", now)


static func _can_research(b: AIBrain, rs: ResearchSystem, id: String) -> bool:
	return rs.can_start(b.k, id).is_empty() and b.can_spend(DataDB.get_research(id).get("cost", {}))


## Kampfpunkte abwechselnd in Manaherz (mana_regen) und Manakristall (mana_cap)
static func tick_upgrades(b: AIBrain) -> void:
	if not bool(DataDB.ai("army.kill_point_upgrades", true)):
		return
	var rs: ResearchSystem = b.game.research_system
	var flip := bool(b.st["upgrade_flip"])
	var order: Array = ["mana_cap", "mana_regen"] if flip else ["mana_regen", "mana_cap"]
	for id in order:
		if rs.can_buy_upgrade(b.k, str(id)).is_empty() and rs.buy_upgrade(b.k, str(id)):
			b.st["upgrade_flip"] = not flip
			return
