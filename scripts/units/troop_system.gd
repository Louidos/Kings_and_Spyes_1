## TroopSystem
##
## Truppen (data/troops.json), für alle Reiche gleich:
## - Erfahrung und Ränge: Truppen sammeln Erfahrung (EP) mit Schaden an Feinden und für
##   den letzten Treffer; jeder Aufstieg (Rekrut … Held der Truppe) bringt Wertepunkte.
## - Wertepunkte: je Einheit auf Angriff, Leben, Rüstung oder Tempo verteilen (Auswahlfenster)
##   oder automatisch (Reichsschalter auto_stat_points, bei der KI immer an). Helden bekommen
##   Wertepunkte je Stufe (gespeichert im Heldeneintrag, "stat_alloc").
## - Schmiede: Waffen- und Rüstungsstufen je Truppenklasse, als Modifikatoren des Reichs mit
##   Quelle "upgrade:<id>" und Schlüssel "<wert>#<klasse>".
## - Aussehen (Skins) je Einheitentyp (Kingdom.unit_skins) oder einzelner Einheit (Unit.skin).
## Die KI benutzt dieselben Funktionen (AIMilitary.tick_forge). Zustand liegt in Feldern der
## Einheiten und Reiche; abgeleitet sind nur die Modifikatoren der Schmiede (rebuild_runtime).
class_name TroopSystem
extends Node

## Schmiede, Aussehen, Wertepunkte oder Ränge eines Reichs haben sich geändert (Oberfläche)
signal troops_changed(kingdom: Kingdom)
## Eine Einheit ist im Rang aufgestiegen
signal rank_gained(unit: Unit, rank: int)

var game: Node

var _xp_per_damage := 0.25
var _building_xp := 0.2
var _kill_xp := 8.0
var _kill_xp_per_point := 4.0
var _rank_heal := 0.25
var _notify_min_rank := 2
## Typ-ID -> sammelt Erfahrung? (Zwischenspeicher, die Daten ändern sich nicht)
var _veteran_types: Dictionary = {}


func setup(p_game: Node) -> void:
	game = p_game
	_xp_per_damage = float(DataDB.trp("veterancy.xp_per_damage", 0.25))
	_building_xp = float(DataDB.trp("veterancy.building_xp", 0.2))
	_kill_xp = float(DataDB.trp("veterancy.kill_xp", 8))
	_kill_xp_per_point = float(DataDB.trp("veterancy.kill_xp_per_point", 4))
	_rank_heal = float(DataDB.trp("veterancy.rank_heal", 0.25))
	_notify_min_rank = int(DataDB.trp("veterancy.notify_min_rank", 2))
	game.combat_system.attacked.connect(_on_attacked)
	game.combat_system.unit_died.connect(_on_unit_died)
	game.unit_system.unit_spawned.connect(_on_unit_spawned)
	game.hero_system.hero_leveled.connect(_on_hero_leveled)


# ---------------------------------------------------------------------------
# Erfahrung und Ränge
# ---------------------------------------------------------------------------

## Sammelt diese Einheit Erfahrung? (Truppe, kein Held, keine Zaubereinheit)
func is_veteran(u: Unit) -> bool:
	if u == null or u.hero_id != 0 or u.expires_at >= 0.0:
		return false
	if not _veteran_types.has(u.type_id):
		_veteran_types[u.type_id] = TroopRules.is_veteran_type(u.type_def)
	return bool(_veteran_types[u.type_id])


## Erfahrung gutschreiben; steigt die Einheit dabei auf, gibt es Wertepunkte
func add_xp(u: Unit, amount: float) -> void:
	if amount <= 0.0 or not is_instance_valid(u) or not u.is_alive() or not is_veteran(u):
		return
	u.vet_xp += amount
	var max_rank := TroopRules.max_rank()
	if u.vet_rank < max_rank and u.vet_xp + 0.0001 >= TroopRules.xp_for_rank(u.vet_rank + 1):
		_rank_up(u, TroopRules.rank_for_xp(u.vet_xp))


## Fortschritt zum nächsten Rang (0..1; 1 beim höchsten Rang)
func rank_progress(u: Unit) -> float:
	if u.vet_rank >= TroopRules.max_rank():
		return 1.0
	var a := TroopRules.xp_for_rank(u.vet_rank)
	var b := TroopRules.xp_for_rank(u.vet_rank + 1)
	return clampf((u.vet_xp - a) / maxf(b - a, 0.001), 0.0, 1.0)


## "230 / 420 EP" bzw. "950 EP (höchster Rang)"
func xp_text(u: Unit) -> String:
	if u.vet_rank >= TroopRules.max_rank():
		return "%d EP (höchster Rang)" % floori(u.vet_xp)
	return "%d / %d EP" % [floori(u.vet_xp), roundi(TroopRules.xp_for_rank(u.vet_rank + 1))]


func _rank_up(u: Unit, new_rank: int) -> void:
	var gained := 0
	while u.vet_rank < new_rank:
		u.vet_rank += 1
		gained += TroopRules.points_for_rank(u.vet_rank)
	u.stat_points += gained
	if u.kingdom.auto_stat_points:
		auto_distribute(u, false)
	u.refresh_stats()
	if not u.skin.is_empty():
		u.refresh_look()
	game.combat_system.heal_unit(u, u.max_hp * _rank_heal)
	if u.vet_rank >= _notify_min_rank:
		# Kurz (eine Zeile in den Meldungen); Klick springt zur Einheit
		var text := "%s ist jetzt %s" % [u.get_display_name(), TroopRules.rank_name(u.vet_rank)]
		if u.stat_points > 0:
			text += " – Punkte frei"
		u.kingdom.notify(text, "good", u.position)
	rank_gained.emit(u, u.vet_rank)
	troops_changed.emit(u.kingdom)


func _on_attacked(attacker: Object, victim: Object, damage: float) -> void:
	if attacker == null or victim == null or not is_instance_valid(attacker) or not is_instance_valid(victim):
		return
	if not (attacker is Unit):
		return
	var a: Unit = attacker
	var victim_kingdom: Kingdom = victim.get("kingdom")
	if a.kingdom == null or victim_kingdom == a.kingdom:
		return
	var hp_before := float(victim.get("hp"))
	if victim is Unit:
		(victim as Unit).last_hit_by = a.uid
	if not is_veteran(a):
		return
	var dealt := minf(damage, maxf(hp_before, 0.0))
	add_xp(a, dealt * _xp_per_damage * (1.0 if victim is Unit else _building_xp))


## Der letzte Treffer bekommt die Erfahrung für den Sieg
func _on_unit_died(u: Unit, _killer: Kingdom) -> void:
	if u.last_hit_by == 0:
		return
	var a: Variant = game.find_by_uid(u.last_hit_by)
	if a == null or not is_instance_valid(a) or not (a is Unit):
		return
	var au: Unit = a
	if au.kingdom == u.kingdom or not au.is_alive():
		return
	add_xp(au, _kill_xp + _kill_xp_per_point * float(u.type_def.get("kill_points", 0.0)))


# ---------------------------------------------------------------------------
# Wertepunkte
# ---------------------------------------------------------------------------

## Noch freie Wertepunkte (Helden: aus ihrer Stufe)
func get_free_points(u: Unit) -> int:
	if u == null or not is_instance_valid(u):
		return 0
	if u.hero_id != 0:
		var rec: Dictionary = game.hero_system.find_record(u)
		if rec.is_empty():
			return 0
		return maxi(hero_points_total(rec) - TroopRules.spent_points(rec.get("stat_alloc", {})), 0)
	return u.stat_points


## Wertepunkte eines Helden insgesamt: (Stufe − 1) × hero_points_per_level
func hero_points_total(rec: Dictionary) -> int:
	return maxi(int(rec.get("level", 1)) - 1, 0) * int(DataDB.trp("veterancy.hero_points_per_level", 1))


## Kann diese Einheit Wertepunkte bekommen? (Truppen mit Erfahrung, Helden)
func has_stat_points(u: Unit) -> bool:
	return u != null and is_instance_valid(u) and (u.hero_id != 0 or is_veteran(u))


## "" = Punkt kann auf diesen Wert, sonst der Grund
func can_spend_point(u: Unit, stat_id: String) -> String:
	if u == null or not is_instance_valid(u) or not u.is_alive():
		return "Einheit fehlt"
	if not has_stat_points(u):
		return "Diese Einheit sammelt keine Erfahrung"
	if TroopRules.stat_def(stat_id).is_empty():
		return "Unbekannter Wert"
	if get_free_points(u) <= 0:
		if u.hero_id != 0:
			return "Keine Wertepunkte – Helden bekommen einen je Stufe"
		return "Keine Wertepunkte – sie kommen mit jedem Aufstieg im Rang (Erfahrung im Kampf)"
	if int(u.stat_alloc.get(stat_id, 0)) >= TroopRules.max_per_stat():
		return "Höchstens %d Punkte je Wert" % TroopRules.max_per_stat()
	return ""


## Einen Wertepunkt verteilen
func spend_point(u: Unit, stat_id: String) -> bool:
	if not can_spend_point(u, stat_id).is_empty():
		return false
	_apply_point(u, stat_id)
	troops_changed.emit(u.kingdom)
	return true


func _apply_point(u: Unit, stat_id: String) -> void:
	u.stat_alloc[stat_id] = int(u.stat_alloc.get(stat_id, 0)) + 1
	if u.hero_id != 0:
		var rec: Dictionary = game.hero_system.find_record(u)
		if not rec.is_empty():
			rec["stat_alloc"] = u.stat_alloc.duplicate()
	else:
		u.stat_points = maxi(u.stat_points - 1, 0)
	u.refresh_stats()


## Alle freien Punkte nach der Reihenfolge der Klasse verteilen. Gibt die Zahl verteilter Punkte zurück.
func auto_distribute(u: Unit, notify_ui: bool = true) -> int:
	if not has_stat_points(u):
		return 0
	var n := 0
	while get_free_points(u) > 0:
		var stat_id := TroopRules.pick_auto_stat(u.unit_class, u.stat_alloc)
		if stat_id.is_empty():
			break
		_apply_point(u, stat_id)
		n += 1
	if n > 0 and notify_ui:
		troops_changed.emit(u.kingdom)
	return n


## Mehrfachauswahl: alle freien Punkte verteilen; gibt die Zahl verteilter Punkte zurück
func auto_distribute_units(units: Array) -> int:
	var n := 0
	var kingdoms := {}
	for o in units:
		if o is Unit and is_instance_valid(o):
			var spent := auto_distribute(o as Unit, false)
			if spent > 0:
				n += spent
				kingdoms[(o as Unit).kingdom] = true
	for k in kingdoms:
		troops_changed.emit(k)
	return n


## Summe freier Punkte in einer Auswahl
func free_points_of(units: Array) -> int:
	var n := 0
	for o in units:
		if o is Unit and is_instance_valid(o):
			n += get_free_points(o as Unit)
	return n


## Reichsschalter: neue Wertepunkte automatisch verteilen (beim Einschalten gleich alle offenen)
func set_auto_points(k: Kingdom, on: bool) -> void:
	k.auto_stat_points = on
	if on:
		for u in k.units:
			if get_free_points(u) > 0:
				auto_distribute(u, false)
	troops_changed.emit(k)


func _on_hero_leveled(k: Kingdom, hero_id: int, _level: int) -> void:
	if not k.auto_stat_points:
		return
	var u: Unit = game.hero_system.get_unit(k, hero_id)
	if u != null:
		auto_distribute(u)


## Helden: verteilte Punkte aus dem Heldeneintrag übernehmen (neu angeworben, wiederbelebt, geladen)
func _on_unit_spawned(u: Unit) -> void:
	if u.hero_id == 0:
		return
	_sync_hero(u)
	if u.kingdom.auto_stat_points and get_free_points(u) > 0:
		auto_distribute(u, false)


func _sync_hero(u: Unit) -> void:
	var rec: Dictionary = game.hero_system.get_record(u.kingdom, u.hero_id)
	if rec.is_empty():
		return
	var alloc: Variant = rec.get("stat_alloc", {})
	u.stat_alloc = (alloc as Dictionary).duplicate() if alloc is Dictionary else {}
	u.refresh_stats()


## Debug (F3) und Rauchtest: Erfahrung geben
func debug_add_xp(u: Unit, amount: float) -> void:
	add_xp(u, amount)
	troops_changed.emit(u.kingdom)


# ---------------------------------------------------------------------------
# Aussehen
# ---------------------------------------------------------------------------

## Aussehen eines ganzen Einheitentyps im Reich ("standard" = Farben des Reichs)
func set_type_skin(k: Kingdom, type_id: String, skin_id: String) -> bool:
	var def := DataDB.get_unit_type(type_id)
	if not TroopRules.skins_for(k, def).has(skin_id):
		return false
	if skin_id == "standard":
		k.unit_skins.erase(type_id)
	else:
		k.unit_skins[type_id] = skin_id
	for u in k.units:
		if u.type_id == type_id:
			u.refresh_look()
	troops_changed.emit(k)
	return true


## Eigenes Aussehen einer Einheit ("" = wie ihr Typ)
func set_unit_skin(u: Unit, skin_id: String) -> bool:
	if not is_instance_valid(u):
		return false
	if not skin_id.is_empty() and not TroopRules.skins_for(u.kingdom, u.type_def, u.vet_rank).has(skin_id):
		return false
	u.skin = skin_id
	u.refresh_look()
	troops_changed.emit(u.kingdom)
	return true


## Aussehen des Typs im Reich
func get_type_skin(k: Kingdom, type_id: String) -> String:
	return str(k.unit_skins.get(type_id, "standard"))


# ---------------------------------------------------------------------------
# Schmiede
# ---------------------------------------------------------------------------

func get_forge_upgrades() -> Array:
	return DataDB.trp("forge.upgrades", [])


## Name einer Verbesserung für die Fraktion des Reichs ("Stahlklingen")
func upgrade_name(k: Kingdom, up: Dictionary) -> String:
	var names: Dictionary = up.get("names", {})
	return str(names.get(k.faction_id if k != null else "", up.get("name", up.get("id", ""))))


func get_forge_level(k: Kingdom, upgrade_id: String) -> int:
	return int(k.forge_levels.get(upgrade_id, 0))


## Kosten der nächsten Stufe ({} = höchste Stufe erreicht oder unbekannt)
func get_forge_cost(k: Kingdom, upgrade_id: String) -> Dictionary:
	var up := DataDB.get_forge_upgrade(upgrade_id)
	var level := get_forge_level(k, upgrade_id)
	var costs: Array = up.get("cost", [])
	return costs[level] if level < costs.size() else {}


## Fertige Schmiede des Reichs (oder null)
func get_forge(k: Kingdom) -> Building:
	for b in k.buildings:
		if b.constructed and bool(b.def.get("forge", false)):
			return b
	return null


## "" = Stufe kann gekauft werden, sonst der Grund
func can_buy_forge(k: Kingdom, upgrade_id: String) -> String:
	var up := DataDB.get_forge_upgrade(upgrade_id)
	if up.is_empty():
		return "Unbekannte Verbesserung"
	if get_forge_level(k, upgrade_id) >= int(up.get("max_level", 0)):
		return "Höchste Stufe erreicht"
	if get_forge(k) == null:
		return "Benötigt eine fertige %s" % DataDB.get_building_name(DataDB.get_building("forge"), k.faction_id)
	return k.missing_text(get_forge_cost(k, upgrade_id))


## Nächste Stufe kaufen (Kosten sofort, Wirkung sofort)
func buy_forge(k: Kingdom, upgrade_id: String) -> bool:
	if not can_buy_forge(k, upgrade_id).is_empty():
		return false
	if not k.spend(get_forge_cost(k, upgrade_id)):
		return false
	var level := get_forge_level(k, upgrade_id) + 1
	k.forge_levels[upgrade_id] = level
	apply_forge_upgrade(k, upgrade_id)
	var up := DataDB.get_forge_upgrade(upgrade_id)
	var forge := get_forge(k)
	var at: Variant = null
	if forge != null:
		at = forge.get_center()
	k.notify("%s: %s Stufe %d – %s" % [DataDB.get_building_name(DataDB.get_building("forge"), k.faction_id),
			upgrade_name(k, up), level, forge_effect_text(up, level)], "good", at)
	k.add_stat("forge_upgrades")
	troops_changed.emit(k)
	return true


## Wirkung einer Stufe als Text: "+20 % Angriff (Fusstruppen)"
func forge_effect_text(up: Dictionary, level: int) -> String:
	var parts: PackedStringArray = []
	var per: Dictionary = up.get("per_level", {})
	for stat in per:
		var key := "%s#%s" % [str(stat), str(up.get("class", ""))]
		parts.append(DataDB.describe_modifier(key, 1.0 + float(per[stat]) * level))
	return ", ".join(parts)


## Modifikatoren einer Verbesserung setzen (Quelle "upgrade:<id>"; mehrfach aufrufbar)
func apply_forge_upgrade(k: Kingdom, upgrade_id: String) -> void:
	var up := DataDB.get_forge_upgrade(upgrade_id)
	var source := "upgrade:" + upgrade_id
	var level := get_forge_level(k, upgrade_id)
	if up.is_empty() or level <= 0:
		k.clear_modifiers(source)
		return
	var factors := {}
	var per: Dictionary = up.get("per_level", {})
	for stat in per:
		factors["%s#%s" % [str(stat), str(up.get("class", ""))]] = 1.0 + float(per[stat]) * level
	k.replace_modifiers(source, factors)


## Alle Schmiede-Stufen eines Reichs anwenden
func apply_forge(k: Kingdom) -> void:
	for id in k.forge_levels:
		apply_forge_upgrade(k, str(id))


# ---------------------------------------------------------------------------
# Speichern (Phase 10): der Zustand steht in Einheiten, Reichen und Heldeneinträgen
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {}


func from_dict(_d: Dictionary) -> void:
	pass


## Schmiede-Modifikatoren und Heldenpunkte neu aufbauen (idempotent)
func rebuild_runtime() -> void:
	for k in game.kingdoms:
		apply_forge(k)
		for u in k.units:
			if u.hero_id != 0:
				_sync_hero(u)
