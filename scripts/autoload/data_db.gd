## DataDB (Autoload)
##
## Lädt alle Spieldaten aus dem Ordner /data (JSON) und stellt sie dem Rest
## des Spiels zur Verfügung. Kein anderes System liest JSON direkt – so gibt
## es eine einzige Stelle, an der Daten geprüft und umgewandelt werden.
extends Node

const DATA_DIR := "res://data/"

## Allgemeine Konfiguration (game_config.json)
var config: Dictionary = {}
## Parameter der Weltgenerierung (worldgen.json)
var worldgen: Dictionary = {}
## Biome in Regel-Reihenfolge. Der Array-Index ist die Biom-Nummer im Kartenarray.
var biomes: Array = []
## Biom-ID ("forest") -> Index in `biomes`
var biome_index_by_id: Dictionary = {}
## Index des Standard-Bioms (wenn keine Regel zutrifft)
var default_biome_index: int = 0
var factions: Array = []
## Völker aller Fraktionen (peoples.json) in Datei-Reihenfolge
var peoples: Array = []
## Volk-ID ("dwarves") -> Volk
var people_by_id: Dictionary = {}
var difficulties: Array = []
var default_difficulty: String = "normal"

## Ressourcen (resources.json) in fester Reihenfolge
var resources: Array = []
var resource_by_id: Dictionary = {}
## Rohstoffvorkommen. Auf der Karte gespeichert als Index + 1 (0 = kein Vorkommen).
var deposits: Array = []
var deposit_index_by_id: Dictionary = {}
## Ganze resources.json (Start-Garantien usw.)
var deposit_cfg: Dictionary = {}
## Gebäude (buildings.json)
var buildings: Array = []
var building_by_id: Dictionary = {}
## Berufe (jobs.json)
var jobs: Array = []
var job_by_id: Dictionary = {}
## Wirtschaft und Bevölkerung (economy.json)
var economy: Dictionary = {}
## Einheitentypen (units.json), z. B. "villager"
var units: Array = []
var unit_by_id: Dictionary = {}
## Kampfregeln (combat.json)
var combat: Dictionary = {}
## Forschung (research.json): Zweige und Forschungen
var research_branches: Array = []
var research: Array = []
var research_by_id: Dictionary = {}
## Zauber (spells.json) und Magie-Einstellungen/Mana-Verbesserungen
var spells: Array = []
var spell_by_id: Dictionary = {}
var magic: Dictionary = {}
## Helden (heroes.json): Einstellungen, Heldentypen (auch als Einheitentyp in
## unit_by_id, Rolle "hero"), Fähigkeiten
var hero_data: Dictionary = {}
var hero_types: Array = []
var hero_type_by_id: Dictionary = {}
var abilities: Array = []
var ability_by_id: Dictionary = {}
## Diplomatie mit neutralen Dörfern (diplomacy.json): Ruf, Verträge, Handel, Dörfer, Boten
var diplomacy: Dictionary = {}


func _ready() -> void:
	reload()


## Lädt alle Datendateien (neu). Kann z. B. für Hot-Reload erneut aufgerufen werden.
func reload() -> void:
	config = _load_json("game_config.json")
	worldgen = _load_json("worldgen.json")
	_load_biomes()
	var faction_data := _load_json("factions.json")
	factions = faction_data.get("factions", [])
	for f in factions:
		f["color"] = _parse_color(f.get("color", "#ffffff"))
	_load_peoples(faction_data)
	var diff_data := _load_json("difficulties.json")
	difficulties = diff_data.get("difficulties", [])
	default_difficulty = diff_data.get("default", "normal")
	_load_resources()
	_load_buildings()
	_load_jobs()
	economy = _load_json("economy.json")
	_load_units()
	diplomacy = _load_json("diplomacy.json")
	_prepare_diplomacy()
	combat = _load_json("combat.json")
	_load_research()
	_load_spells()
	_load_heroes()
	_validate_peoples()


## Liest einen Wert aus game_config.json über einen Punkt-Pfad, z. B. "camera.zoom_max".
func cfg(path: String, default_value: Variant = null) -> Variant:
	var node: Variant = config
	for key in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return default_value
	return node


func get_biome(index: int) -> Dictionary:
	return biomes[index]


func get_faction(id: String) -> Dictionary:
	return _find_by_id(factions, id)


func get_difficulty(id: String) -> Dictionary:
	return _find_by_id(difficulties, id)


func get_map_size(id: String) -> Dictionary:
	return _find_by_id(cfg("map.sizes", []), id)


func get_peoples_of_faction(faction_id: String) -> Array:
	return peoples.filter(func(p): return p.get("faction") == faction_id)


## Volk nach ID ({} wenn unbekannt)
func get_people(id: String) -> Dictionary:
	return people_by_id.get(id, {})


## Name eines Volks ("Zwerge"), sonst die ID
func get_people_name(id: String) -> String:
	return str(get_people(id).get("name", id))


## Völker, die Dörfer bilden (faction neutral und militia_unit gesetzt), in Datei-Reihenfolge
func get_village_peoples() -> Array:
	var list: Array = []
	for p in peoples:
		if str(p.get("faction", "")) == "neutral" and not str(p.get("militia_unit", "")).is_empty():
			list.append(p)
	return list


## Liest einen Wert aus diplomacy.json über einen Punkt-Pfad, z. B. "treaties.alliance.min_reputation".
func diplo(path: String, default_value: Variant = null) -> Variant:
	var node: Variant = diplomacy
	for key in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return default_value
	return node


## Ruf-Stufen aus diplomacy.json (sortiert nach min aufsteigend, color als Color)
func get_reputation_tiers() -> Array:
	return diplo("reputation.tiers", [])


## Liest einen Wert aus economy.json über einen Punkt-Pfad, z. B. "villager.speed".
func eco(path: String, default_value: Variant = null) -> Variant:
	var node: Variant = economy
	for key in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return default_value
	return node


func get_resource(id: String) -> Dictionary:
	return resource_by_id.get(id, {})


## Vorkommen nach Array-Index ({} wenn ungültig)
func get_deposit(index: int) -> Dictionary:
	if index < 0 or index >= deposits.size():
		return {}
	return deposits[index]


func get_deposit_by_id(id: String) -> Dictionary:
	return get_deposit(deposit_index_by_id.get(id, -1))


func get_building(id: String) -> Dictionary:
	return building_by_id.get(id, {})


func get_job(id: String) -> Dictionary:
	return job_by_id.get(id, {})


func get_unit_type(id: String) -> Dictionary:
	return unit_by_id.get(id, {})


## Einheitentyp einer Stufe für eine Fraktion (z. B. "fighter" für "evil").
## Typen mit faction "any" passen zu jeder Fraktion. {} wenn es keinen gibt.
func get_unit_for_tier(faction_id: String, tier: String) -> Dictionary:
	var fallback := {}
	for u in units:
		if u.get("tier", "") != tier:
			continue
		if u.get("faction", "any") == faction_id:
			return u
		if u.get("faction", "any") == "any":
			fallback = u
	return fallback


## Grafikpfad eines Einheitentyps für eine Fraktion ("" wenn keiner)
func get_unit_sprite(def: Dictionary, faction_id: String) -> String:
	if def.has("sprite"):
		return str(def["sprite"])
	var sprites: Dictionary = def.get("sprites", {})
	return str(sprites.get(faction_id, sprites.get("good", "")))


## Liest einen Wert aus combat.json über einen Punkt-Pfad, z. B. "camps.size".
func cmb(path: String, default_value: Variant = null) -> Variant:
	var node: Variant = combat
	for key in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return default_value
	return node


## Name eines Gebäudes für eine Fraktion (z. B. "Bibliothek" / "Dunkles Archiv")
func get_building_name(def: Dictionary, faction_id: String) -> String:
	var names: Dictionary = def.get("names", {})
	return str(names.get(faction_id, def.get("name", "Gebäude")))


## Kurzbeschriftung eines Gebäudes (Platzhalter) für eine Fraktion
func get_building_label(def: Dictionary, faction_id: String) -> String:
	var labels: Dictionary = def.get("labels", {})
	return str(labels.get(faction_id, def.get("label", "")))


func get_research(id: String) -> Dictionary:
	return research_by_id.get(id, {})


## Forschungen einer Fraktion (dazu alle mit faction "any"), in Datei-Reihenfolge
func get_research_for_faction(faction_id: String) -> Array:
	var list: Array = []
	for r in research:
		if r["faction"] == faction_id or r["faction"] == "any":
			list.append(r)
	return list


func get_spell(id: String) -> Dictionary:
	return spell_by_id.get(id, {})


## Zauber einer Fraktion in Datei-Reihenfolge
func get_spells_for_faction(faction_id: String) -> Array:
	var list: Array = []
	for sp in spells:
		if sp["faction"] == faction_id or sp["faction"] == "any":
			list.append(sp)
	return list


## Forschung der Fraktion, die diese Freischaltung bringt ({} wenn keine)
func find_research_unlocking(faction_id: String, unlock_id: String) -> Dictionary:
	for r in get_research_for_faction(faction_id):
		for e in r.get("effects", []):
			if e.get("type", "") == "unlock" and str(e.get("id", "")) == unlock_id:
				return r
	return {}


## Lesbarer Name einer Freischaltung: "unit:elite_good" -> "Ritter",
## "building:infirmary" -> "Krankenstation", "spell:x" -> "Zauber „…“"
func describe_unlock(unlock_id: String, faction_id: String) -> String:
	var parts := unlock_id.split(":", true, 1)
	if parts.size() < 2:
		return unlock_id
	match parts[0]:
		"unit":
			return str(get_unit_type(parts[1]).get("name", parts[1]))
		"building":
			return get_building_name(get_building(parts[1]), faction_id)
		"spell":
			return "Zauber „%s“" % str(get_spell(parts[1]).get("name", parts[1]))
		"summon":
			# "summon:<gebäude>:<einheit>" (Bündnis oder Aufnahme eines Dorfs)
			var unit_id := parts[1].get_slice(":", 1)
			return str(get_unit_type(unit_id).get("name", unit_id))
	return unlock_id


## Lesbarer Text für fehlende Freischaltungen: "Lichtsegen (Forschung)" bzw.
## mehrere durch Komma getrennt. Nennt die Forschung, die sie bringt.
func describe_requirement(unlock_ids: Array, faction_id: String) -> String:
	var parts: PackedStringArray = []
	for id in unlock_ids:
		var uid := str(id)
		if uid.begins_with("research:"):
			parts.append(str(get_research(uid.substr(9)).get("name", uid)))
			continue
		var r := find_research_unlocking(faction_id, uid)
		parts.append(str(r.get("name", describe_unlock(uid, faction_id))))
	return ", ".join(parts)


## Name einer Wirkungsquelle: "spell:<id>" -> Zaubername, "research:<id>" -> Forschung,
## "upgrade:<id>" -> Kampfpunkt-Verbesserung (für Tooltips und das Auswahlfenster);
## ab Phase 6 auch "alliance:<dorf>", "annex:<dorf>", "treaty:<dorf>", "people:<volk>",
## "daynight", "difficulty" und "event:<id>"
func describe_effect_source(source: String) -> String:
	match source:
		"daynight":
			return "Tageszeit"
		"difficulty":
			return "Schwierigkeit"
	var parts := source.split(":", true, 1)
	if parts.size() < 2:
		return source
	match parts[0]:
		"spell":
			return str(get_spell(parts[1]).get("name", parts[1]))
		"research":
			return str(get_research(parts[1]).get("name", parts[1]))
		"upgrade":
			for up in mag("upgrades", []):
				if str(up.get("id", "")) == parts[1]:
					return str(up.get("name", parts[1]))
		"ability":
			# "ability:<id>" bzw. "ability:<id>#<held>"; Führung: "ability:leadership[_<heldentyp>]"
			var aid := parts[1].get_slice("#", 0)
			if aid.begins_with("leadership"):
				var htype := aid.trim_prefix("leadership").trim_prefix("_")
				return "Führung" if htype.is_empty() else "Führung (%s)" % str(get_hero_type(htype).get("name", htype))
			return str(get_ability(aid).get("name", aid))
		"hero":
			return "Heldenstufe"
		"alliance":
			return "Bündnis"
		"annex":
			return "Aufgenommenes Dorf"
		"treaty":
			return "Vertrag"
		"people":
			return get_people_name(parts[1])
		"daynight":
			return "Tageszeit"
		"difficulty":
			return "Schwierigkeit"
		"event":
			return "Ereignis"
	return parts[1]


## Farbe einer Wirkungsquelle (Zauberfarbe, sonst weiss)
func get_effect_source_color(source: String) -> Color:
	if source.begins_with("spell:"):
		return get_spell(source.substr(6)).get("color", Color.WHITE)
	if source.begins_with("ability:"):
		var aid := source.substr(8).get_slice("#", 0)
		if aid.begins_with("leadership"):
			return Color(1.0, 0.85, 0.35)
		return get_ability(aid).get("color", Color.WHITE)
	if source.begins_with("alliance:") or source.begins_with("annex:") or source.begins_with("treaty:"):
		return Color(0.95, 0.82, 0.4)
	if source.begins_with("people:"):
		return get_people(source.substr(7)).get("color", Color.WHITE)
	return Color.WHITE


## Lesbarer additiver Zuschlag: "cap.mana" +40 -> "+40 Mana-Maximum",
## "mana_regen" 0.05 -> "+3.0 Mana pro Minute (Burg)", "spell_range" 8 -> "+8 Felder Zauberreichweite"
func describe_bonus(key: String, add: float) -> String:
	match key:
		"cap.mana":
			return "%+d Mana-Maximum" % roundi(add)
		"mana_regen":
			return "%+.1f Mana pro Minute (Burg)" % (add * 60.0)
		"spell_range":
			return "%+d Felder Zauberreichweite ausserhalb des Gebiets" % roundi(add)
		"hero_train_cap":
			return "Ausbildung der Helden bis Stufe %d (%+d)" % [int(hero_cfg("training.max_level", 5)) + roundi(add), roundi(add)]
		"hero_slots":
			return "%+d Heldenplatz" % roundi(add)
	if key.begins_with("cap."):
		return "%+d Lager (%s)" % [roundi(add), str(get_resource(key.substr(4)).get("name", key.substr(4)))]
	return "%+g %s" % [add, key]


const _MOD_NAMES := {"attack": "Angriff", "armor": "Rüstung", "hp": "Leben", "speed": "Tempo",
	"range": "Reichweite", "regen": "Erholung", "heal": "Heilung", "gather": "Sammeltempo",
	"build": "Bautempo", "production": "Produktion", "research": "Forschungstempo",
	"summon": "Beschwörungstempo", "growth": "Wachstum", "food_use": "Nahrungsverbrauch",
	"aggro_range": "Sichtweite im Kampf", "sight": "Sichtweite", "mana_regen": "Mana der Burg",
	"spell_cost": "Zauberkosten", "spell_cooldown": "Abklingzeit der Zauber",
	"spell_radius": "Zauberradius", "spell_duration": "Zauberdauer", "spell_power": "Zauberstärke",
	"hero_xp": "Erfahrung der Helden", "ability_power": "Stärke der Heldenfähigkeiten", "lifesteal": "Lebensraub",
	"damage_taken": "erlittener Schaden"}
const _TIER_NAMES := {"fighter": "Kämpfer", "archer": "Schützen", "elite": "Elite", "scout": "Späher",
	"medic": "Heiler", "king": "König", "villager": "Bewohner", "summon": "Beschworene", "hero": "Helden",
	"militia": "Miliz", "special": "Volkskrieger", "messenger": "Boten"}
const _ROLE_NAMES := {"combat": "alle Truppen ohne Helden", "worker": "Bewohner", "support": "Heiler",
	"king": "König", "monster": "Monster", "hero": "Helden", "messenger": "Boten"}


## Lesbare Wirkung eines Modifikators, z. B. "+10 % Angriff (Kämpfer)".
## Rüstung als Faktor ("Rüstung ×1,3"), Angriffspause als Angriffstempo.
func describe_modifier(key: String, factor: float) -> String:
	var stat := key
	var qualifier := ""
	var role_parts := key.split("@", true, 1)
	if role_parts.size() > 1:
		stat = role_parts[0]
		qualifier = str(_ROLE_NAMES.get(role_parts[1], role_parts[1]))
	else:
		var parts := key.split(".", true, 1)
		stat = parts[0]
		if parts.size() > 1:
			if stat == "production" or stat == "gather" or stat == "cap":
				qualifier = str(get_resource(parts[1]).get("name", parts[1]))
			else:
				qualifier = str(_TIER_NAMES.get(parts[1], parts[1]))
	var suffix := "" if qualifier.is_empty() else " (%s)" % qualifier
	match stat:
		"armor":
			return "Rüstung ×%s%s" % [String.num(factor, 2).replace(".", ","), suffix]
		"attack_interval":
			# Kürzere Pause zwischen Angriffen = schnelleres Zuschlagen
			return "%+d %% Angriffstempo%s" % [roundi((1.0 / maxf(factor, 0.01) - 1.0) * 100.0), suffix]
		"cap":
			return "%+d %% Lager%s" % [roundi((factor - 1.0) * 100.0), suffix]
	return "%+d %% %s%s" % [roundi((factor - 1.0) * 100.0), str(_MOD_NAMES.get(stat, stat)), suffix]


## Liest einen Wert aus spells.json (Einstellungen, Mana-Verbesserungen) über einen Punkt-Pfad.
func mag(path: String, default_value: Variant = null) -> Variant:
	var node: Variant = magic
	for key in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return default_value
	return node


## Pfad der Gebäudegrafik für eine Fraktion ("" wenn keine angegeben)
func get_building_sprite(def: Dictionary, faction_id: String) -> String:
	if def.has("sprite"):
		return str(def["sprite"])
	var sprites: Dictionary = def.get("sprites", {})
	return str(sprites.get(faction_id, sprites.get("good", "")))


## Kosten als lesbarer Text, z. B. "25 Holz, 10 Stein"
func cost_to_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r in resources:
		var amount := float(cost.get(r["id"], 0.0))
		if amount > 0.0:
			parts.append("%d %s" % [ceili(amount), r["name"]])
	return "kostenlos" if parts.is_empty() else ", ".join(parts)


# ---------------------------------------------------------------------------
# Intern
# ---------------------------------------------------------------------------

func _load_biomes() -> void:
	var data := _load_json("biomes.json")
	biomes = data.get("biomes", [])
	biome_index_by_id.clear()
	if biomes.size() > 255:
		push_error("biomes.json: Maximal 255 Biome erlaubt.")
		biomes.resize(255)
	for i in biomes.size():
		var b: Dictionary = biomes[i]
		b["index"] = i
		b["color"] = _parse_color(b.get("color", "#ff00ff"))
		b["movement_cost"] = float(b.get("movement_cost", 1.0))
		b["defense_bonus"] = float(b.get("defense_bonus", 0.0))
		b["buildable"] = bool(b.get("buildable", true))
		if not b.has("conditions"):
			b["conditions"] = {}
		if not b.has("sprites"):
			b["sprites"] = []
		biome_index_by_id[b.get("id", "biome_%d" % i)] = i
	default_biome_index = biome_index_by_id.get(data.get("default_biome", ""), maxi(biomes.size() - 1, 0))
	if biomes.is_empty():
		push_error("biomes.json enthält keine Biome – die Karte kann nicht erzeugt werden.")


func _load_resources() -> void:
	deposit_cfg = _load_json("resources.json")
	resources = deposit_cfg.get("resources", [])
	resource_by_id.clear()
	for r in resources:
		r["color"] = _parse_color(r.get("color", "#ffffff"))
		resource_by_id[r["id"]] = r
	deposits = deposit_cfg.get("deposits", [])
	deposit_index_by_id.clear()
	if deposits.size() > 254:
		push_error("resources.json: Maximal 254 Vorkommen erlaubt.")
		deposits.resize(254)
	for i in deposits.size():
		var d: Dictionary = deposits[i]
		d["index"] = i
		d["color"] = _parse_color(d.get("color", "#ffffff"))
		var amount: Variant = d.get("amount", [100, 100])
		if amount is Array:
			d["amount"] = [int(amount[0]), int(amount[amount.size() - 1])]
		else:
			d["amount"] = [int(amount), int(amount)]
		d["max_gatherers"] = int(d.get("max_gatherers", 1))
		d["gatherable"] = bool(d.get("gatherable", true))
		d["biome_deposit"] = bool(d.get("biome_deposit", false))
		d["regrow_per_hour"] = int(d.get("regrow_per_hour", 0))
		if not resource_by_id.has(d.get("resource", "")):
			push_warning("Vorkommen '%s': unbekannte Ressource '%s'" % [d.get("id"), d.get("resource")])
		deposit_index_by_id[d["id"]] = i


func _load_buildings() -> void:
	var data := _load_json("buildings.json")
	buildings = data.get("buildings", [])
	building_by_id.clear()
	for b in buildings:
		var size: Array = b.get("size", [2, 2])
		b["size"] = Vector2i(int(size[0]), int(size[1]))
		b["color"] = _parse_color(b.get("color", "#888888"))
		var cost := {}
		for k in b.get("cost", {}):
			cost[k] = float(b["cost"][k])
		b["cost"] = cost
		b["build_time"] = float(b.get("build_time", 10.0))
		b["housing"] = int(b.get("housing", 0))
		b["territory_radius"] = int(b.get("territory_radius", 0))
		b["workers"] = int(b.get("workers", 0))
		b["gather_radius"] = int(b.get("gather_radius", 0))
		b["gather_bonus"] = float(b.get("gather_bonus", 0.0))
		b["player_buildable"] = bool(b.get("player_buildable", true))
		b["is_road"] = bool(b.get("is_road", false))
		b["hp"] = float(b.get("hp", 300.0))
		b["armor"] = float(b.get("armor", 0.0))
		b["sight"] = float(b.get("sight", 5.0))
		if not b.has("summons"):
			b["summons"] = []
		if not b.has("dropoff"):
			b["dropoff"] = []
		building_by_id[b["id"]] = b


func _load_jobs() -> void:
	var data := _load_json("jobs.json")
	jobs = data.get("jobs", [])
	job_by_id.clear()
	for j in jobs:
		var indices := PackedInt32Array()
		for dep_id in j.get("deposits", []):
			if deposit_index_by_id.has(dep_id):
				indices.append(deposit_index_by_id[dep_id])
			else:
				push_warning("Beruf '%s': unbekanntes Vorkommen '%s'" % [j.get("id"), dep_id])
		j["deposit_indices"] = indices
		# Maske über den Kartenwert (Vorkommen-Index + 1) für schnelle Suchen
		var mask := PackedByteArray()
		mask.resize(256)
		for idx in indices:
			mask[idx + 1] = 1
		j["deposit_mask"] = mask
		if not j.has("buildings"):
			j["buildings"] = []
		job_by_id[j["id"]] = j


func _load_units() -> void:
	var data := _load_json("units.json")
	units = data.get("units", [])
	unit_by_id.clear()
	for u in units:
		_normalize_unit(u)
		unit_by_id[u["id"]] = u


## Werte eines Einheitentyps vereinheitlichen (Zahlen, Standardwerte, Verhalten).
## Auch für Helden (heroes.json → stats).
func _normalize_unit(u: Dictionary) -> void:
	u["speed"] = float(u.get("speed", 2.0))
	u["radius"] = float(u.get("radius", 13.0))
	u["food_per_day"] = float(u.get("food_per_day", 0.0))
	u["can_work"] = bool(u.get("can_work", false))
	u["carry"] = int(u.get("carry", 0))
	u["needs_housing"] = bool(u.get("needs_housing", false))
	u["faction"] = str(u.get("faction", "any"))
	u["tier"] = str(u.get("tier", ""))
	u["role"] = str(u.get("role", "worker"))
	u["letter"] = str(u.get("letter", ""))
	for key in ["hp", "attack", "attack_interval", "range", "armor", "aggro_range", "regen", "heal",
			"heal_range", "summon_time", "kill_points"]:
		u[key] = float(u.get(key, 0.0))
	u["hp"] = maxf(u["hp"], 1.0)
	u["attack_interval"] = maxf(u["attack_interval"], 0.1)
	u["sight"] = float(u.get("sight", 6.0))
	u["building_damage"] = float(u.get("building_damage", 1.0))
	u["people"] = str(u.get("people", ""))
	var req: Array = u.get("requires", [])
	u["requires"] = req
	# Verhalten: aus der Rolle abgeleitet, wenn nicht ausdrücklich angegeben
	var role: String = u["role"]
	u["flee_on_hit"] = bool(u.get("flee_on_hit", role == "worker"))
	u["joins_fights"] = bool(u.get("joins_fights", role in ["combat", "king", "monster", "hero"]))
	u["target_priority"] = float(u.get("target_priority", 1.6 if role == "worker" else 1.0))
	var rank := 0
	if role == "worker" or role == "support":
		rank = 2
	elif u["range"] >= 2.0:
		rank = 1
	u["formation_rank"] = int(u.get("formation_rank", rank))
	if u.has("color"):
		u["color"] = _parse_color(u["color"])
	var cost := {}
	for k in u.get("cost", {}):
		cost[k] = float(u["cost"][k])
	u["cost"] = cost
	u["projectile"] = str(u.get("projectile", ""))


func _load_heroes() -> void:
	hero_data = _load_json("heroes.json")
	hero_types = hero_data.get("heroes", [])
	hero_type_by_id.clear()
	for h in hero_types:
		var id := str(h.get("id", ""))
		h["faction"] = str(h.get("faction", "any"))
		h["color"] = _parse_color(h.get("color", "#ffffff"))
		var cost := {}
		for res in h.get("cost", {}):
			cost[res] = float(h["cost"][res])
		h["cost"] = cost
		var talents: Array = h.get("talents", [])
		h["talents"] = talents
		var leadership: Array = h.get("leadership", [])
		h["leadership"] = leadership
		hero_type_by_id[id] = h
		# Als Einheitentyp eintragen (nur in unit_by_id, nicht in units: sonst
		# fänden Stufen-Abfragen wie get_unit_for_tier auch Helden)
		var u: Dictionary = (h.get("stats", {}) as Dictionary).duplicate(true)
		u["id"] = id
		u["name"] = str(h.get("name", id))
		u["description"] = str(h.get("description", ""))
		u["faction"] = h["faction"]
		u["tier"] = "hero"
		u["role"] = "hero"
		u["letter"] = str(h.get("letter", "H"))
		u["color"] = h.get("color", Color.WHITE)
		u["sprite"] = str(h.get("sprite", ""))
		u["cost"] = cost
		u["summon_time"] = float(h.get("recruit_time", 30.0))
		u["kill_points"] = 0.0
		u["can_work"] = false
		u["needs_housing"] = false
		u["joins_fights"] = true
		u["flee_on_hit"] = false
		if unit_by_id.has(id):
			push_error("Helden-ID doppelt (schon in units.json): %s" % id)
		_normalize_unit(u)
		unit_by_id[id] = u
	abilities = hero_data.get("abilities", [])
	ability_by_id.clear()
	for a in abilities:
		a["kind"] = str(a.get("kind", "active"))
		a["target"] = str(a.get("target", "none"))
		a["color"] = _parse_color(a.get("color", "#ffffff"))
		for key in ["range", "radius", "cooldown"]:
			a[key] = float(a.get(key, 0.0))
		a["autocast"] = bool(a.get("autocast", false))
		var ranks: Array = a.get("ranks", [])
		a["ranks"] = ranks
		ability_by_id[a["id"]] = a


## Wert aus heroes.json → settings über einen Punkt-Pfad
func hero_cfg(path: String, default_value: Variant = null) -> Variant:
	var node: Variant = hero_data.get("settings", {})
	for key in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return default_value
	return node


func get_hero_type(id: String) -> Dictionary:
	return hero_type_by_id.get(id, {})


## Heldentypen einer Fraktion (dazu alle mit faction "any"), in Datei-Reihenfolge
func get_hero_types_for_faction(faction_id: String) -> Array:
	var list: Array = []
	for h in hero_types:
		if h["faction"] == faction_id or h["faction"] == "any":
			list.append(h)
	return list


func get_ability(id: String) -> Dictionary:
	return ability_by_id.get(id, {})


func _load_research() -> void:
	var data := _load_json("research.json")
	research_branches = data.get("branches", [])
	research = data.get("research", [])
	research_by_id.clear()
	for r in research:
		r["faction"] = str(r.get("faction", "any"))
		r["branch"] = str(r.get("branch", ""))
		r["tier"] = int(r.get("tier", 1))
		r["time"] = maxf(float(r.get("time", 30.0)), 0.1)
		var cost := {}
		for k in r.get("cost", {}):
			cost[k] = float(r["cost"][k])
		r["cost"] = cost
		var req: Array = r.get("requires", [])
		r["requires"] = req
		var effects: Array = r.get("effects", [])
		r["effects"] = effects
		research_by_id[r["id"]] = r


func _load_spells() -> void:
	magic = _load_json("spells.json")
	spells = magic.get("spells", [])
	spell_by_id.clear()
	for sp in spells:
		sp["faction"] = str(sp.get("faction", "any"))
		# requires: Liste von Freischaltungen (ein einzelner Text wird zur Liste)
		var req: Variant = sp.get("requires", [])
		if req is String:
			req = [] if (req as String).is_empty() else [req]
		sp["requires"] = req
		sp["school"] = str(sp.get("school", ""))
		sp["color"] = _parse_color(sp.get("color", "#ffffff"))
		for key in ["mana_cost", "cooldown", "radius", "duration", "upkeep"]:
			sp[key] = float(sp.get(key, 0.0))
		spell_by_id[sp["id"]] = sp


func _load_json(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("Datendatei fehlt: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("Fehler in %s, Zeile %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		push_error("%s: Oberste Ebene muss ein Objekt { ... } sein." % path)
		return {}
	return json.data


func _parse_color(value: Variant) -> Color:
	if value is Color:
		return value
	var s := str(value)
	if Color.html_is_valid(s):
		return Color.html(s)
	push_warning("Ungültige Farbe in Daten: %s" % s)
	return Color.MAGENTA


func _find_by_id(list: Array, id: String) -> Dictionary:
	for entry in list:
		if entry is Dictionary and entry.get("id") == id:
			return entry
	return {}
