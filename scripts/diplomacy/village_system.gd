## VillageSystem
##
## Neutrale Dörfer (Phase 6). Gründet beim Spielstart an jedem Dorfplatz der
## Weltgenerierung ein Dorf: ein eigenes Reich (controller "neutral", faction
## "neutral", Volk aus peoples.json) mit Dorfzentrum, Hütten und Milizen, die
## ihre Wachposten halten. Die Wirtschaft ist vereinfacht: das Dorf erzeugt die
## Waren seines Volks direkt ins Dorflager, zahlt Tribut an seinen Schutzherrn
## und ersetzt gefallene Milizen aus dem Vorrat.
## Wird ein Dorf angegriffen, schlägt es Alarm (Milizen eilen hin); verbündete
## Dörfer schicken Hilfe, wenn ihr Partner in der Nähe angegriffen wird.
## transfer_settlement übergibt eine Siedlung an ein anderes Reich (Aufnahme,
## Eroberung; ab Phase 7 allgemein). Dorfzentren werden bei 0 Leben erobert
## statt zerstört (try_capture, aufgerufen vom CombatSystem).
##
## Zustand: villages (Datensatz je Dorf-Reich, Schlüssel Kingdom.id) und order
## (Gründungsreihenfolge). Gebäude und Einheiten nur über uids.
## Bewohner (Darstellung und Leben, keine Wirtschaft): VillageResidents (residents), ihr Zustand
## steht im Dorf-Datensatz.
## Laufzeit: _tick_acc und _pending (Folgen von Kampfsignalen, die erst im
## eigenen Takt abgearbeitet werden – die Signale feuern mitten in den
## Schleifen des CombatSystems).
class_name VillageSystem
extends Node

## Ein Dorf wurde gegründet
signal village_founded(village: Kingdom)
## Eine Siedlung hat den Besitzer gewechselt (reason "annex" | "conquest", ab Phase 7 "defeat")
signal settlement_transferred(from_kingdom: Kingdom, to_kingdom: Kingdom, reason: String)
## Ein Dorf wurde zerstört (Dorfzentrum gefallen, ohne Eroberer)
signal village_destroyed(village: Kingdom, by: Kingdom)
## Ein Dorf ist um eine Hütte gewachsen
signal village_grew(village: Kingdom, size: int)
## Ein Dorf schlägt Alarm (angegriffen oder durch einen Boten gewarnt)
signal village_alarm(village: Kingdom, attacker: Kingdom, pos: Vector2)

## Mögliche Plätze der Hütten (obere linke Kachel relativ zur oberen linken Kachel
## des Dorfzentrums); je Dorf um seine Nummer gedreht, damit nicht alle gleich aussehen
const HUT_OFFSETS := [Vector2i(-3, -1), Vector2i(4, -1), Vector2i(-1, -3), Vector2i(-1, 4), Vector2i(-3, 3),
	Vector2i(3, 3), Vector2i(3, -3), Vector2i(-3, -3), Vector2i(5, 2), Vector2i(-4, 1)]
## Umkreis (Kacheln) um den Bündnis-Einsatzort, in dem noch Feinde gesucht werden
const HELP_ENEMY_RADIUS := 8.0

var game: Node
var world: WorldData

## Dorf-Reich-id -> Datensatz:
## {"id", "people_id", "name", "site_index", "center": Vector2i, "size", "hall_uid", "hut_uids": Array,
##  "status": "active" | "annexed" | "conquered" | "destroyed", "owner_id" (bei annexed/conquered),
##  "population", "production_factor", "refill_timer", "alarm_until", "alarm_pos", "calm_since",
##  "help_until", "help_pos", "helpers": Array (uids), "posts": Array (Weltpositionen der Wachposten),
##  "slots": Dictionary (Miliz-uid -> Postennummer), Bewohner siehe VillageResidents}
var villages: Dictionary = {}
## Dorf-Reich-ids in Gründungsreihenfolge (Liste im Diplomatiefenster)
var order: Array = []

var _tick_acc := 0.0
var _tick := 1.0
var _ts := 64.0
## Wartende Aufgaben aus Kampfsignalen: ["alarm", Dorf-id, Angreifer-id, pos],
## ["help", Dorf-id, pos, Feind-id], ["destroy", Dorf-id, Täter-id]
var _pending: Array = []
## Sichtbare Dorfbewohner (Tagesablauf, Flucht, Ersatz)
var residents := VillageResidents.new()


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world
	_ts = float(world.tile_size)
	_tick = maxf(float(DataDB.diplo("village.tick_seconds", 1.0)), 0.1)
	GameClock.sim_tick.connect(_on_sim_tick)
	game.combat_system.kingdom_attacked.connect(_on_kingdom_attacked)
	game.combat_system.building_destroyed.connect(_on_building_destroyed)
	game.unit_system.unit_removed.connect(_on_unit_removed)
	residents.setup(self)


# ---------------------------------------------------------------------------
# Gründung
# ---------------------------------------------------------------------------

## Gründet alle Dörfer der Weltgenerierung (Plätze der Art "village") in ihrer Reihenfolge.
func found_villages() -> void:
	for site in world.get_sites("village"):
		found_village(site)


## Gründet ein Dorf an einem Dorfplatz: Reich, Lager, Dorfzentrum, Hütten, Milizen.
## Gibt das Dorf-Reich zurück (null, wenn Volk oder Gebäude fehlen).
func found_village(site: Dictionary) -> Kingdom:
	var people := DataDB.get_people(str(site.get("people", "")))
	var hall_def := DataDB.get_building(str(DataDB.diplo("village.hall", "village_hall")))
	if people.is_empty() or hall_def.is_empty():
		push_error("VillageSystem: Dorf ohne Volk oder Dorfzentrum (%s)" % str(site))
		return null
	var people_id := str(people["id"])
	var index := int(site.get("index", order.size()))
	var village_name := _pick_name(people, index)
	var k: Kingdom = game.create_kingdom({"faction_id": "neutral", "controller": "neutral",
			"display_name": "%s %s" % [str(people.get("village_title", "Dorf")), village_name],
			"color": people.get("color", Color.WHITE)})
	k.people_id = people_id
	var stock: Dictionary = DataDB.diplo("village.start_stock", {})
	for res_id in stock:
		k.resources[res_id] = float(stock[res_id])
	var center: Vector2i = site.get("cell", Vector2i.ZERO)
	var hall: Building = game.building_system.place_settlement_center(hall_def, k, center)
	hall.extra["people_id"] = people_id
	hall.refresh_look()
	var village_size := clampi(int(site.get("size", 2)), 1, maxi(int(DataDB.diplo("village.growth.max_size", 10)), 1))
	var hut_uids: Array = []
	for _j in village_size:
		var hut := _place_hut(k, hall, index + hut_uids.size())
		if hut == null:
			break
		hut_uids.append(hut.uid)
	var rec := {"id": k.id, "people_id": people_id, "name": village_name, "site_index": index,
			"center": center, "size": village_size, "hall_uid": hall.uid, "hut_uids": hut_uids,
			"status": "active", "owner_id": 0,
			"population": village_size * int(DataDB.diplo("village.population_per_size", 4)),
			"production_factor": 1.0, "refill_timer": 0.0, "alarm_until": 0.0, "alarm_pos": Vector2.ZERO,
			"calm_since": 0.0, "help_until": 0.0, "help_pos": Vector2.ZERO, "helpers": [], "posts": [], "slots": {},
			"growth": 0.0, "last_attacked": -1.0e9, "tower_uids": []}
	villages[k.id] = rec
	order.append(k.id)
	# Wachposten rund um das Dorfzentrum (nach den Hütten: Posten liegen auf freien Kacheln)
	var target := get_militia_target(k)
	rec["posts"] = _make_posts(hall, target)
	for i in target:
		_spawn_militia(k, rec, i, rec["posts"][i])
	residents.seed_residents(k, rec)
	village_founded.emit(k)
	return k


## Neue Hütte auf einem freien Platz um das Dorfzentrum (zuerst die festen Plätze HUT_OFFSETS,
## je Dorf gedreht, dann Ringe bis growth.hut_search_radius); null, wenn kein Platz frei ist
func _place_hut(v: Kingdom, hall: Building, rotate: int) -> Building:
	var hut_def := DataDB.get_building(str(DataDB.diplo("village.hut", "village_hut")))
	if hut_def.is_empty() or hall == null:
		return null
	var cells: Array = []
	for j in HUT_OFFSETS.size():
		cells.append(hall.cell + (HUT_OFFSETS[(rotate + j) % HUT_OFFSETS.size()] as Vector2i))
	var center := hall.cell + Vector2i(1, 1)
	for r in range(3, int(DataDB.diplo("village.growth.hut_search_radius", 8)) + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r or absi(dy) == r:
					cells.append(center + Vector2i(dx, dy))
	return _place_village_building(v, hut_def, cells)


## Setzt ein Dorfgebäude (fertig, kostenlos) auf die erste passende Kachel der Liste
func _place_village_building(v: Kingdom, def: Dictionary, cells: Array) -> Building:
	var bs: BuildingSystem = game.building_system
	for c in cells:
		var cell: Vector2i = c
		if not bs.can_place_free(def, cell, v).is_empty():
			continue
		var b: Building = bs.place_building(def, cell, v, true)
		if b == null:
			continue
		b.extra["people_id"] = v.people_id
		b.refresh_look()
		return b
	return null


## Dorfname ohne Doppelte: Name Nummer index (reihum), belegte werden übersprungen
func _pick_name(people: Dictionary, index: int) -> String:
	var names: Array = people.get("village_names", [])
	if names.is_empty():
		return "Nr. %d" % (index + 1)
	var used := {}
	for vid in villages:
		used[str(villages[vid]["name"])] = true
	for j in names.size():
		var candidate := str(names[(index + j) % names.size()])
		if not used.has(candidate):
			return candidate
	return "%s %d" % [str(names[index % names.size()]), floori(float(index) / names.size()) + 1]


## Wachposten (Weltpositionen) im Kreis um das Dorfzentrum, abwechselnd nah und weiter weg
func _make_posts(hall: Building, count: int) -> Array:
	var posts: Array = []
	var radii: Array = DataDB.diplo("village.guard_radius", [3.5, 5.0])
	var center := hall.get_center()
	for i in count:
		var angle := TAU * i / maxf(float(count), 1.0) + 0.3
		var r := float(radii[i % radii.size()]) if not radii.is_empty() else 4.0
		var pos := center + Vector2.from_angle(angle) * r * _ts
		var cell: Vector2i = game.nav.nearest_free(world.world_to_cell(pos), 3)
		posts.append(world.cell_to_world(cell) if cell.x >= 0 else hall.get_approach_point(pos))
	return posts


## Miliz an einem Posten erscheinen lassen (spawn_pos: Erscheinungsort)
func _spawn_militia(v: Kingdom, rec: Dictionary, slot: int, spawn_pos: Vector2) -> Unit:
	var type_id := str(get_people(v).get("militia_unit", ""))
	if type_id.is_empty():
		return null
	var u: Unit = game.unit_system.spawn_unit(v, type_id, spawn_pos)
	if u == null:
		return null
	var posts: Array = rec["posts"]
	var post: Vector2 = posts[slot] if slot >= 0 and slot < posts.size() else spawn_pos
	(rec["slots"] as Dictionary)[u.uid] = slot
	u.command = "hold"
	u.command_pos = post
	if u.position.distance_to(post) > _ts * 0.6:
		game.unit_system.move_to(u, post)
	return u


# ---------------------------------------------------------------------------
# Abfragen
# ---------------------------------------------------------------------------

## Ist das Reich ein Dorf, das noch selbstständig ist (Status "active")?
func is_village(k: Kingdom) -> bool:
	if k == null or not villages.has(k.id):
		return false
	return str(villages[k.id]["status"]) == "active"


## Ist (oder war) das Reich ein Dorf – auch aufgenommen, erobert oder zerstört?
func is_village_kingdom(k: Kingdom) -> bool:
	return k != null and villages.has(k.id)


## Datensatz des Dorfs ({} wenn keins)
func get_record(k: Kingdom) -> Dictionary:
	if k == null:
		return {}
	return villages.get(k.id, {})


## Dorf-Reiche in Gründungsreihenfolge (ohne include_inactive nur selbstständige)
func get_villages(include_inactive: bool = false) -> Array:
	var list: Array = []
	for vid in order:
		var k: Kingdom = game.get_kingdom(int(vid))
		if k != null and (include_inactive or is_village(k)):
			list.append(k)
	return list


## Volk des Dorfs (peoples.json, {} wenn keins)
func get_people(k: Kingdom) -> Dictionary:
	var rec := get_record(k)
	if rec.is_empty():
		return DataDB.get_people(k.people_id) if k != null else {}
	return DataDB.get_people(str(rec["people_id"]))


## Dorfzentrum (über die uid; null, wenn es nicht mehr steht)
func get_hall(k: Kingdom) -> Building:
	var rec := get_record(k)
	if rec.is_empty():
		return null
	var b: Variant = game.find_by_uid(int(rec["hall_uid"]))
	return b as Building if b is Building else null


## Mitte des Dorfs in Weltpixeln (Dorfzentrum, sonst der Dorfplatz)
func get_center(k: Kingdom) -> Vector2:
	var hall := get_hall(k)
	if hall != null:
		return hall.get_center()
	var rec := get_record(k)
	if rec.is_empty():
		return Vector2.ZERO
	return world.cell_to_world(rec["center"])


## Ungefährer Radius des Dorfs in Kacheln (Gebiet des Dorfzentrums + 1,5)
func get_radius_tiles(_k: Kingdom = null) -> float:
	var hall_def := DataDB.get_building(str(DataDB.diplo("village.hall", "village_hall")))
	return float(hall_def.get("territory_radius", 8)) + 1.5


## Lebende Milizen des Dorfs (alle Einheiten ausser Boten und Bewohnern)
func get_militia(k: Kingdom) -> Array:
	var list: Array = []
	if k == null:
		return list
	for u in k.units:
		if u.is_alive() and u.role != "messenger" and not VillageResidents.is_resident(u):
			list.append(u)
	return list


## Soll-Anzahl der Milizen: (Grundzahl + je Hütte) × Volksfaktor, begrenzt, mindestens 1
func get_militia_target(k: Kingdom) -> int:
	var rec := get_record(k)
	var village_size := int(rec.get("size", 2))
	var base := float(DataDB.diplo("village.militia_base", 2)) + float(DataDB.diplo("village.militia_per_size", 1)) * village_size
	var n := roundi(base * float(get_people(k).get("militia_factor", 1.0)))
	return clampi(n, 1, maxi(int(DataDB.diplo("village.militia_max", 7)), 1))


## Kampfkraft einer Einheit (Leben × Schaden pro Sekunde, grob; Heiler zählen mit)
static func unit_power(u: Unit) -> float:
	return u.max_hp * maxf(maxf(u.attack, u.heal), 1.0) / maxf(u.attack_interval, 0.1) / 100.0


## Summe der Kampfkraft aller Milizen des Dorfs
func get_strength(k: Kingdom) -> float:
	var total := 0.0
	for u in get_militia(k):
		total += unit_power(u)
	return total


## Grobe Stärke als Wort: "schwach", "mittel" oder "stark"
func get_strength_text(k: Kingdom) -> String:
	var s := get_strength(k)
	if s < float(DataDB.diplo("strength.weak", 40)):
		return "schwach"
	if s < float(DataDB.diplo("strength.medium", 90)):
		return "mittel"
	return "stark"


## Produktion pro Spielminute (Ressource -> Menge): Waren des Volks × Produktionsfaktor
## (aufgenommen voll, erobert gemindert) × Modifikatoren des Dorfreichs (Phase 8:
## Dürre, Erntedank). Zerstörte Dörfer produzieren nichts.
func get_production(k: Kingdom) -> Dictionary:
	var rec := get_record(k)
	var result := {}
	if rec.is_empty() or str(rec["status"]) == "destroyed":
		return result
	var produces: Dictionary = get_people(k).get("produces", {})
	var factor := float(rec.get("production_factor", 1.0))
	for res_id in produces:
		result[res_id] = float(produces[res_id]) * factor * k.mod("production") * k.mod("production." + str(res_id))
	return result


## Flüchtlinge/Überläufer ziehen ins Dorf: Bevölkerung + n (Anzeige, ab Phase 9 evtl. Produktion)
func add_population(v: Kingdom, n: int) -> void:
	var rec := get_record(v)
	if rec.is_empty() or n <= 0:
		return
	rec["population"] = int(rec.get("population", 0)) + n


## Dorf, dem die Kachel gehört (nur selbstständige Dörfer), sonst null
func village_at_cell(cell: Vector2i) -> Kingdom:
	var owner_id := world.get_owner(cell)
	if owner_id == 0:
		return null
	var k: Kingdom = game.get_kingdom(owner_id)
	return k if is_village(k) else null


## Sind Feinde des Dorfs (sichtbare, lebende Einheiten verfeindeter Reiche) im Umkreis?
func has_enemies_near(v: Kingdom, pos: Vector2, radius_tiles: float) -> bool:
	var index: SpatialIndex = game.combat_system.index
	var radius := radius_tiles * _ts
	for kid in index.kingdom_ids():
		if int(kid) == v.id:
			continue
		var other: Kingdom = game.get_kingdom(int(kid))
		if other == null or not game.are_hostile(v, other):
			continue
		for u in index.query_kingdom(pos, radius, int(kid)):
			if u.hp > 0.0 and not u.stealthed:
				return true
	return false


## Mehrzeiliger Text für das Auswahlfenster (Volk, Ruf, Vertrag, Produktion, Miliz)
func get_summary_text(v: Kingdom, viewer: Kingdom) -> String:
	var rec := get_record(v)
	if rec.is_empty():
		return ""
	var people := get_people(v)
	var ds: DiplomacySystem = game.diplomacy_system
	var lines: PackedStringArray = []
	var status := str(rec["status"])
	if status != "active":
		var owner_k: Kingdom = game.get_kingdom(int(rec.get("owner_id", 0)))
		match status:
			"annexed":
				lines.append("Aufgenommen von %s" % (owner_k.display_name if owner_k != null else "?"))
			"conquered":
				lines.append("Erobert von %s" % (owner_k.display_name if owner_k != null else "?"))
			_:
				lines.append("Zerstört")
		return "\n".join(lines)
	var head := "Volk: %s" % str(people.get("name", "?"))
	if viewer != null and viewer != v:
		var rep := ds.get_reputation(v, viewer)
		head += "  ·  Ruf: %s (%+d)" % [DiplomacySystem.tier_name(DiplomacySystem.tier_for(rep)), roundi(rep)]
	lines.append(head)
	var treaty := ds.get_treaty(v)
	if treaty.is_empty():
		lines.append("Kein Vertrag")
	else:
		var partner: Kingdom = game.get_kingdom(int(treaty["partner_id"]))
		lines.append("%s mit %s" % [DiplomacySystem.treaty_name(str(treaty["type"])),
				partner.display_name if partner != null else "?"])
	lines.append("Produziert: %s pro Minute" % _amounts_text(get_production(v)))
	lines.append("Miliz: %d/%d (%s)  ·  Einwohner: %d" % [get_militia(v).size(), get_militia_target(v),
			get_strength_text(v), int(rec["population"])])
	if float(rec["alarm_until"]) > GameClock.game_time:
		lines.append("Alarm!")
	return "\n".join(lines)


## Für eigene Dorfzentren aufgenommener/eroberter Dörfer:
## "Aufgenommenes Dorf (Zwerge): +4 Erz, +6 Stein pro Minute" ("" sonst)
func get_annexed_text(b: Building) -> String:
	if b == null or b.kingdom == null:
		return ""
	for vid in villages:
		var rec: Dictionary = villages[vid]
		if int(rec["hall_uid"]) != b.uid:
			continue
		var status := str(rec["status"])
		if (status != "annexed" and status != "conquered") or int(rec["owner_id"]) != b.kingdom.id:
			return ""
		var v: Kingdom = game.get_kingdom(int(vid))
		var parts: PackedStringArray = []
		var prod := get_production(v)
		for res in DataDB.resources:
			var amount := float(prod.get(res["id"], 0.0))
			if amount > 0.0:
				parts.append("+%s %s" % [_num(amount), str(res["name"])])
		return "%s Dorf (%s): %s pro Minute" % ["Aufgenommenes" if status == "annexed" else "Erobertes",
				str(get_people(v).get("name", "?")), ", ".join(parts)]
	return ""


# ---------------------------------------------------------------------------
# Alarm, Bündnishilfe
# ---------------------------------------------------------------------------

## Alarm: Milizen am Posten eilen zum Ort des Angriffs (Angriffsmarsch). Nach
## alarm_calm_seconds ohne Feinde kehren sie zurück. send_militia = false: nur
## Alarmzustand (z. B. Warnung durch einen Boten), die Milizen bleiben am Posten.
func raise_alarm(v: Kingdom, attacker: Kingdom, pos: Vector2, send_militia: bool = true) -> void:
	if not is_village(v):
		return
	var rec := get_record(v)
	var now := GameClock.game_time
	rec["alarm_until"] = now + float(DataDB.diplo("messenger.alarm_seconds", 120.0))
	rec["alarm_pos"] = pos
	rec["calm_since"] = now
	if send_militia:
		var helpers: Array = rec["helpers"]
		var idle: Array = []
		for u in get_militia(v):
			if u.command == "hold" and not is_instance_valid(u.target) and not helpers.has(u.uid):
				idle.append(u)
		if not idle.is_empty():
			game.command_system.order_move(idle, pos, true)
	village_alarm.emit(v, attacker, pos)


## Bündnisfall: ein Teil der freien Milizen zieht zum angegriffenen Partner.
## Ist der Feind ein Reich, mit dem das Dorf noch Frieden hat, erklärt es ihm den Krieg.
## Gibt die Anzahl der losgeschickten Milizen zurück (0 = keine frei oder schon unterwegs).
func dispatch_help(v: Kingdom, pos: Vector2, enemy: Kingdom) -> int:
	if not is_village(v):
		return 0
	var rec := get_record(v)
	var now := GameClock.game_time
	if float(rec["help_until"]) > now:
		return 0
	if enemy != null and enemy != v and enemy.controller != "wild" and not game.are_hostile(v, enemy):
		var ds: DiplomacySystem = game.diplomacy_system
		# Keine Kriege zwischen Dörfern: nur gegen Reiche
		if not ds.is_party(enemy):
			return 0
		game.set_relation(v, enemy, "war")
		ds.change_reputation(v, enemy, float(DataDB.diplo("events.alliance_call", -20)), "Bündnisfall")
		enemy.notify("%s steht seinem Verbündeten bei und ist jetzt dein Feind!" % v.display_name, "danger",
				get_center(v))
	var free: Array = []
	for u in get_militia(v):
		if not is_instance_valid(u.target):
			free.append(u)
	if free.is_empty():
		return 0
	free.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.position.distance_squared_to(pos) < b.position.distance_squared_to(pos))
	var share := float(DataDB.diplo("treaties.alliance.help_share", 0.5))
	var n := clampi(ceili(free.size() * share), 1, free.size())
	var list: Array = free.slice(0, n)
	game.command_system.order_move(list, pos, true)
	var uids: Array = []
	for u in list:
		uids.append(u.uid)
	rec["helpers"] = uids
	rec["help_until"] = now + float(DataDB.diplo("treaties.alliance.help_seconds", 90.0))
	rec["help_pos"] = pos
	return list.size()


## Milizen zurück auf ihre Posten (nach Alarm oder Bündnishilfe); only_uids: nur diese,
## sonst alle ausser denen, die gerade Bündnishilfe leisten
func _return_to_posts(v: Kingdom, rec: Dictionary, only_uids: Array = []) -> void:
	var helpers: Array = rec["helpers"]
	for u in get_militia(v):
		if not only_uids.is_empty() and not only_uids.has(u.uid):
			continue
		if only_uids.is_empty() and helpers.has(u.uid):
			continue
		_send_to_post(v, rec, u)


func _send_to_post(v: Kingdom, rec: Dictionary, u: Unit) -> void:
	var slots: Dictionary = rec["slots"]
	var posts: Array = rec["posts"]
	var slot := int(slots.get(u.uid, -1))
	if slot < 0:
		slot = _free_slot(rec)
		if slot >= 0:
			slots[u.uid] = slot
	var post: Vector2 = posts[slot] if slot >= 0 and slot < posts.size() else get_center(v)
	u.follow_leader = null
	u.speed_cap = 0.0
	u.order_id += 1
	u.command = "hold"
	u.command_pos = post
	u.target = null
	if u.position.distance_to(post) > _ts * 0.6:
		game.unit_system.move_to(u, post)
	else:
		game.unit_system.stop(u)


## Erster Posten ohne Miliz (-1 = alle besetzt)
func _free_slot(rec: Dictionary) -> int:
	var taken := {}
	var slots: Dictionary = rec["slots"]
	for uid in slots:
		taken[int(slots[uid])] = true
	for i in (rec["posts"] as Array).size():
		if not taken.has(i):
			return i
	return -1


# ---------------------------------------------------------------------------
# Übergabe, Eroberung, Zerstörung
# ---------------------------------------------------------------------------

## Dorfzentrum auf 0 Leben: wird erobert statt zerstört, wenn der Angreifer ein
## Reich (Spieler oder KI) ist. Gibt true zurück, wenn erobert wurde.
func try_capture(b: Building, attacker: Kingdom) -> bool:
	if b == null or attacker == null or attacker.defeated:
		return false
	if attacker.controller == "wild" or attacker.controller == "neutral":
		return false
	var v := b.kingdom
	if not is_village(v) or int(get_record(v)["hall_uid"]) != b.uid:
		return false
	b.hp = b.max_hp * float(DataDB.diplo("annex.capture_hp_ratio", 0.25))
	transfer_settlement(v, attacker, "conquest")
	return true


## Übergibt eine Siedlung (alle Gebäude; bei "annex" auch die Milizen) an ein
## anderes Reich. reason: "annex" (Aufnahme), "conquest" (Eroberung; übrige
## Milizen fliehen), ab Phase 7 "defeat". Das alte Reich gilt danach als besiegt.
func transfer_settlement(from: Kingdom, to: Kingdom, reason: String) -> void:
	if from == null or to == null or from == to:
		return
	var rec := get_record(from)
	var ds: DiplomacySystem = game.diplomacy_system
	var center := get_center(from)
	if not rec.is_empty():
		ds.end_all_treaties(from, "transfer")
	for b in from.buildings.duplicate():
		game.building_system.transfer_building(b, to)
	var militia: Array = get_militia(from)
	if reason == "annex":
		for u in militia:
			game.unit_system.transfer_unit(u, to)
	elif reason == "conquest":
		# Verbliebene Milizen fliehen (keine Kampfpunkte)
		for u in militia:
			game.unit_system.remove_unit(u)
	if not rec.is_empty():
		var conquest := reason == "conquest"
		rec["status"] = "conquered" if conquest else "annexed"
		rec["owner_id"] = to.id
		rec["production_factor"] = float(DataDB.diplo("annex.conquest_production_factor" if conquest
				else "annex.production_factor", 1.0))
		if conquest:
			var loss := float(DataDB.diplo("annex.conquest_population_loss", 0.5))
			rec["population"] = int(roundf(float(rec["population"]) * (1.0 - loss)))
		rec["slots"] = {}
		rec["helpers"] = []
		rec["alarm_until"] = 0.0
		rec["help_until"] = 0.0
		# Die Bewohner bleiben Dorfbewohner (siehe VillageResidents.on_transfer)
		residents.on_transfer(from, rec)
		var people := get_people(from)
		var special := str(people.get("special_unit", ""))
		if not special.is_empty():
			to.grant_unlock("annex:%d" % from.id, "summon:barracks:%s" % special)
		if ds.is_party(to):
			if conquest:
				for w in get_villages():
					ds.change_reputation(w, to, float(DataDB.diplo("events.conquest_all", -15)),
							"Eroberung von %s" % from.display_name)
				ds.spread_rumour(from, to, float(DataDB.diplo("events.conquest_rumour", -10)),
						"Gerücht: Eroberung von %s" % from.display_name)
			else:
				for w in get_villages():
					if w.people_id == from.people_id:
						ds.change_reputation(w, to, float(DataDB.diplo("events.annex_same_people", 5)),
								"Aufnahme eines Brudervolks")
		game.defeat_kingdom(from, "conquered" if conquest else "annexed", to)
		if conquest:
			to.notify("%s erobert. Die Bewohner fliehen zum Teil." % from.display_name, "good", center)
		else:
			to.notify("%s gehört jetzt zu deinem Reich! Neue Einheit in der Kaserne: %s" % [from.display_name,
					str(DataDB.get_unit_type(special).get("name", special))], "good", center)
	else:
		game.defeat_kingdom(from, reason, to)
	settlement_transferred.emit(from, to, reason)


## Einschüchterung bei der Aufnahme: ein Teil der Milizen desertiert (verschwindet)
func desert_militia(v: Kingdom, share: float) -> void:
	var militia := get_militia(v)
	var n := clampi(floori(militia.size() * clampf(share, 0.0, 1.0)), 0, militia.size())
	for i in n:
		game.unit_system.remove_unit(militia[militia.size() - 1 - i])


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	if not _pending.is_empty():
		_process_pending()
	_tick_acc += dt
	if _tick_acc < _tick:
		return
	var step := _tick_acc
	_tick_acc = 0.0
	var now := GameClock.game_time
	for vid in order:
		var rec: Dictionary = villages[vid]
		var v: Kingdom = game.get_kingdom(int(vid))
		if v == null:
			continue
		match str(rec["status"]):
			"active":
				_tick_active(v, rec, step, now)
			"annexed", "conquered":
				_tick_owned(v, rec, step)


## Selbstständiges Dorf: Produktion, Tribut, Milizen nachfüllen, Alarm und Hilfe beenden
func _tick_active(v: Kingdom, rec: Dictionary, step: float, now: float) -> void:
	var cap := float(DataDB.diplo("village.stock_cap", 400))
	var prod := get_production(v)
	for res_id in prod:
		var room := cap - v.get_amount(res_id)
		if room > 0.0:
			v.add_resource(res_id, minf(float(prod[res_id]) / 60.0 * step, room))
	# Tribut an den Schutzherrn (höchstens der Vorrat)
	var treaty: Dictionary = game.diplomacy_system.get_treaty(v)
	if not treaty.is_empty() and str(treaty["type"]) == "protection":
		var protector: Kingdom = game.get_kingdom(int(treaty["partner_id"]))
		if protector != null and not protector.defeated:
			var tribute: Dictionary = get_people(v).get("tribute", {})
			for res_id in tribute:
				var amount := minf(float(tribute[res_id]) / 60.0 * step, v.get_amount(res_id))
				if amount > 0.0:
					v.add_resource(res_id, -amount)
					protector.add_resource(res_id, amount)
	var alarm := float(rec["alarm_until"]) > 0.0
	# Milizen nachfüllen (nicht während eines Alarms)
	var militia_count := get_militia(v).size()
	if not alarm and militia_count < get_militia_target(v):
		rec["refill_timer"] = float(rec["refill_timer"]) + step
		if float(rec["refill_timer"]) >= float(DataDB.diplo("village.refill_seconds", 120)):
			_refill(v, rec)
	else:
		rec["refill_timer"] = 0.0
	# Alarm beenden, sobald eine Weile kein Feind mehr in der Nähe ist
	if alarm:
		var radius := get_radius_tiles(v) + float(DataDB.diplo("village.alarm_radius_extra", 4))
		if has_enemies_near(v, get_center(v), radius) or has_enemies_near(v, rec["alarm_pos"], radius * 0.5):
			rec["calm_since"] = now
		if now - float(rec["calm_since"]) >= float(DataDB.diplo("village.alarm_calm_seconds", 10)) \
				or now > float(rec["alarm_until"]):
			rec["alarm_until"] = 0.0
			_return_to_posts(v, rec)
	tick_growth(v, rec, step, now)
	residents.tick(v, rec, step, now, float(rec["alarm_until"]) > 0.0)
	# Bündnishilfe beenden (Zeit um oder keine Feinde mehr am Einsatzort)
	if float(rec["help_until"]) > 0.0:
		if now >= float(rec["help_until"]) or not has_enemies_near(v, rec["help_pos"], HELP_ENEMY_RADIUS):
			var helpers: Array = rec["helpers"]
			rec["help_until"] = 0.0
			rec["helpers"] = []
			_return_to_posts(v, rec, helpers)


## Wachstum (diplomacy.json village.growth): Im Frieden sammelt das Dorf Wachstum (Handel und
## Bündnisse beschleunigen es); voll ergibt es eine neue Hütte, mehr Bewohner, mehr Milizen und ab
## towers_at_size einen Wachturm. Krieg mit einem Reich, Alarm oder ein Angriff in den letzten
## attack_pause_seconds halten es an. Höchstens max_size Hütten.
func tick_growth(v: Kingdom, rec: Dictionary, step: float, now: float) -> void:
	var rate := growth_rate(v, rec, now)
	if rate <= 0.0:
		return
	# Zerstörte Hütten und Türme werden im selben Takt wieder aufgebaut, auch bei voller Grösse
	var full := int(rec.get("size", 1)) >= int(DataDB.diplo("village.growth.max_size", 10))
	if full and not _needs_rebuild(rec):
		return
	var interval := maxf(float(DataDB.diplo("village.growth.interval", 600)), 1.0)
	rec["growth"] = float(rec.get("growth", 0.0)) + rate * step / interval
	if float(rec["growth"]) >= 1.0:
		rec["growth"] = float(rec["growth"]) - 1.0
		# Erst Zerstörtes ersetzen; findet sich dafür kein Platz, wächst das Dorf wie sonst
		var hall := get_hall(v)
		var rebuilt := hall != null and _needs_rebuild(rec) and _rebuild(v, rec, hall)
		if not rebuilt and not full:
			grow(v, rec)


## Fehlt eine Hütte (zerstört) oder ein Turm, der zur Grösse gehört?
func _needs_rebuild(rec: Dictionary) -> bool:
	var towers_at: Array = DataDB.diplo("village.growth.towers_at_size", [])
	var towers := (rec.get("tower_uids", []) as Array).size()
	var due := 0
	for at in towers_at:
		if int(rec.get("size", 1)) >= int(at):
			due += 1
	return (rec.get("hut_uids", []) as Array).size() < int(rec.get("size", 1)) or towers < due


## Eine zerstörte Hütte neu bauen, sonst einen fehlenden Turm; true = gebaut
func _rebuild(v: Kingdom, rec: Dictionary, hall: Building) -> bool:
	var huts: Array = rec["hut_uids"]
	if huts.size() < int(rec["size"]):
		var hut := _place_hut(v, hall, int(rec.get("site_index", 0)) + huts.size())
		if hut != null:
			huts.append(hut.uid)
			return true
	return _place_missing_tower(v, rec, hall)


## Wachstum je growth.interval (0 = angehalten): 1 im Frieden, + trade_bonus mit Handelsvertrag oder
## Handelsweg, + alliance_bonus mit Schutz- oder Bündnisvertrag
func growth_rate(v: Kingdom, rec: Dictionary, now: float) -> float:
	var cfg: Dictionary = DataDB.diplo("village.growth", {})
	if cfg.is_empty() or not is_village(v) or float(rec.get("alarm_until", 0.0)) > 0.0:
		return 0.0
	if now - float(rec.get("last_attacked", -1.0e9)) < float(cfg.get("attack_pause_seconds", 900)):
		return 0.0
	for o in game.kingdoms:
		var k: Kingdom = o
		if k != v and not k.defeated and k.controller != "wild" and game.diplomacy_system.is_party(k) and game.are_hostile(v, k):
			return 0.0
	var rate := float(cfg.get("base", 1.0))
	var treaty: Dictionary = game.diplomacy_system.get_treaty(v)
	var kind := str(treaty.get("type", ""))
	# Handelsvertrag oder offener Handelsweg (auch der Karawanenweg eines Bündnisses)
	var partner: Kingdom = game.get_kingdom(int(treaty.get("partner_id", 0))) if not treaty.is_empty() else null
	var route: Dictionary = game.trade_route_system.get_route_for(partner, v) if partner != null else {}
	if kind == "trade" or str(route.get("state", "")) == "open":
		rate += float(cfg.get("trade_bonus", 0.5))
	if kind == "protection" or kind == "alliance":
		rate += float(cfg.get("alliance_bonus", 0.25))
	return rate


## Das Dorf wächst um eine Hütte: Bewohner, Milizplätze, ggf. Wachturm
func grow(v: Kingdom, rec: Dictionary) -> bool:
	var hall := get_hall(v)
	if hall == null:
		return false
	var hut := _place_hut(v, hall, int(rec.get("site_index", 0)) + int(rec.get("size", 1)))
	if hut == null:
		return false
	(rec["hut_uids"] as Array).append(hut.uid)
	rec["size"] = int(rec["size"]) + 1
	add_population(v, int(DataDB.diplo("village.population_per_size", 4)))
	# Mehr Milizplätze: Posten neu verteilen, der Vorrat füllt sie nach und nach auf
	rec["posts"] = _make_posts(hall, get_militia_target(v))
	_return_to_posts(v, rec)
	_place_missing_tower(v, rec, hall)
	village_grew.emit(v, int(rec["size"]))
	return true


## Wachturm bauen, wenn zur Grösse einer fehlt (growth.towers_at_size); true = gebaut
func _place_missing_tower(v: Kingdom, rec: Dictionary, hall: Building) -> bool:
	var towers_at: Array = DataDB.diplo("village.growth.towers_at_size", [])
	var tower_uids: Array = rec.get("tower_uids", [])
	rec["tower_uids"] = tower_uids
	if tower_uids.size() >= towers_at.size() or int(rec["size"]) < int(towers_at[tower_uids.size()]):
		return false
	var tower_def := DataDB.get_building(str(DataDB.diplo("village.growth.tower", "tower")))
	var cells: Array = []
	var center := hall.cell + Vector2i(1, 1)
	var angle := TAU * tower_uids.size() / maxf(float(towers_at.size()), 1.0) + 0.8
	for r in range(4, 9):
		cells.append(center + Vector2i((Vector2.from_angle(angle) * r).round()))
		cells.append(center + Vector2i((Vector2.from_angle(angle + 0.5) * r).round()))
	var tower := _place_village_building(v, tower_def, cells)
	if tower == null:
		return false
	tower_uids.append(tower.uid)
	return true


## Eine Miliz aus dem Dorfvorrat ersetzen (erscheint am Dorfzentrum, läuft zum freien Posten)
func _refill(v: Kingdom, rec: Dictionary) -> void:
	var hall := get_hall(v)
	var type_id := str(get_people(v).get("militia_unit", ""))
	var cost: Dictionary = DataDB.get_unit_type(type_id).get("cost", {})
	if hall == null or type_id.is_empty() or not v.can_afford(cost):
		return
	var slot := _free_slot(rec)
	if slot < 0:
		return
	v.spend(cost)
	rec["refill_timer"] = 0.0
	var post: Vector2 = rec["posts"][slot]
	_spawn_militia(v, rec, slot, hall.get_approach_point(post))


## Aufgenommenes/erobertes Dorf: Produktion fliesst dem Besitzer zu, solange er das Dorfzentrum hält
func _tick_owned(v: Kingdom, rec: Dictionary, step: float) -> void:
	residents.tick(v, rec, step, GameClock.game_time, false)
	var hall := get_hall(v)
	if hall == null or hall.kingdom == null or hall.kingdom.id != int(rec["owner_id"]):
		return
	var prod := get_production(v)
	for res_id in prod:
		hall.kingdom.add_resource(res_id, float(prod[res_id]) / 60.0 * step)


func _process_pending() -> void:
	var list := _pending
	_pending = []
	for entry in list:
		var v: Kingdom = game.get_kingdom(int(entry[1]))
		match str(entry[0]):
			"alarm":
				raise_alarm(v, game.get_kingdom(int(entry[2])), entry[3])
			"help":
				dispatch_help(v, entry[2], game.get_kingdom(int(entry[3])))
			"destroy":
				_destroy_village(v, game.get_kingdom(int(entry[2])))


## Dorfzentrum ohne Eroberer gefallen (z. B. durch Monster): das Dorf geht unter
func _destroy_village(v: Kingdom, by: Kingdom) -> void:
	if not is_village(v):
		return
	var rec := get_record(v)
	var center := get_center(v)
	rec["status"] = "destroyed"
	game.diplomacy_system.end_all_treaties(v, "destroyed")
	for b in v.buildings.duplicate():
		game.building_system.remove_building(b, 0.0, true)
	for u in get_militia(v):
		game.unit_system.remove_unit(u)
	residents.remove_all(v, rec)
	rec["slots"] = {}
	rec["helpers"] = []
	game.defeat_kingdom(v, "destroyed", by)
	for k in game.kingdoms:
		if game.diplomacy_system.is_party(k):
			k.notify("Das Dorf %s wurde zerstört" % v.display_name, "warning", center)
	village_destroyed.emit(v, by)


# ---------------------------------------------------------------------------
# Signale
# ---------------------------------------------------------------------------

## Angriff auf ein Dorf: Alarm. Angriff auf einen Bündnispartner in der Nähe: Hilfe.
func _on_kingdom_attacked(victim: Kingdom, attacker: Kingdom, pos: Vector2) -> void:
	if is_village(victim):
		get_record(victim)["last_attacked"] = GameClock.game_time
		_pending.append(["alarm", victim.id, attacker.id, pos])
		return
	var help_radius := float(DataDB.diplo("treaties.alliance.help_radius", 25)) * _ts
	for w in game.diplomacy_system.get_allied_villages(victim):
		if w == attacker or game.are_allied(w, attacker) or not is_village(w):
			continue
		if get_center(w).distance_to(pos) <= help_radius:
			_pending.append(["help", w.id, pos, attacker.id])


## Dorfzentrum zerstört (kein Eroberer): Untergang im nächsten Takt
func _on_building_destroyed(b: Building, killer: Kingdom) -> void:
	var v := b.kingdom
	if not is_village(v):
		return
	var rec := get_record(v)
	if int(rec["hall_uid"]) == b.uid:
		_pending.append(["destroy", v.id, killer.id if killer != null else 0])
	else:
		# Zerstörte Hütte oder Turm: Plünderung hält das Wachstum an
		(rec["hut_uids"] as Array).erase(b.uid)
		(rec.get("tower_uids", []) as Array).erase(b.uid)
		rec["last_attacked"] = GameClock.game_time


func _on_unit_removed(u: Unit) -> void:
	if u.kingdom == null or not villages.has(u.kingdom.id):
		return
	var rec: Dictionary = villages[u.kingdom.id]
	if VillageResidents.is_resident(u):
		residents.on_unit_removed(u, rec)
		return
	(rec["slots"] as Dictionary).erase(u.uid)
	(rec["helpers"] as Array).erase(u.uid)


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"villages": villages.duplicate(true), "order": order.duplicate(), "pending": _pending.duplicate(true),
			"tick_acc": _tick_acc}


func from_dict(d: Dictionary) -> void:
	villages = (d.get("villages", {}) as Dictionary).duplicate(true)
	# Spielstände vor dem Dorfwachstum (1.1.0): Felder ergänzen
	for vid in villages:
		var rec: Dictionary = villages[vid]
		if not rec.has("growth"):
			rec["growth"] = 0.0
		if not rec.has("last_attacked"):
			rec["last_attacked"] = -1.0e9
		if not rec.has("tower_uids"):
			rec["tower_uids"] = []
		# Spielstände vor den Dorfbewohnern (1.2.x): sie erscheinen im ersten Takt
		VillageResidents.ensure_fields(rec)
	order = (d.get("order", []) as Array).duplicate()
	_pending = (d.get("pending", []) as Array).duplicate(true)
	_tick_acc = float(d.get("tick_acc", 0.0))


## Nach dem Laden: Verweise auf nicht mehr vorhandene Milizen und Bewohner entfernen (die Warteliste
## _pending ist gespeichert und bleibt)
func rebuild_runtime() -> void:
	for vid in villages:
		var rec: Dictionary = villages[vid]
		var slots: Dictionary = rec["slots"]
		for uid in slots.keys():
			var u: Variant = game.find_by_uid(int(uid))
			if not (u is Unit) or (u as Unit).kingdom == null or (u as Unit).kingdom.id != int(vid):
				slots.erase(uid)
		var helpers: Array = rec["helpers"]
		for uid in helpers.duplicate():
			if game.find_by_uid(int(uid)) == null:
				helpers.erase(uid)
		residents.rebuild_runtime(int(vid), rec)


# ---------------------------------------------------------------------------

## "4 Erz, 6 Stein" (in Reihenfolge der Ressourcen, Kommazahlen mit Komma)
func _amounts_text(amounts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for res in DataDB.resources:
		var amount := float(amounts.get(res["id"], 0.0))
		if amount > 0.0:
			parts.append("%s %s" % [_num(amount), str(res["name"])])
	return "nichts" if parts.is_empty() else ", ".join(parts)


static func _num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(roundi(x))
	return String.num(x, 1).replace(".", ",")
