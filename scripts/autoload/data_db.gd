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
## Gebäudewerte je Ausbaustufe (buildings.json → levels): id -> [Werte Stufe 2, Werte Stufe 3, …]
var building_level_defs: Dictionary = {}
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
## Gezeichnete Spielfiguren (units.json → figures, FigureArt)
var figures_cfg: Dictionary = {}
## Helden (heroes.json): Einstellungen, Heldentypen (auch als Einheitentyp in
## unit_by_id, Rolle "hero"), Fähigkeiten
var hero_data: Dictionary = {}
var hero_types: Array = []
var hero_type_by_id: Dictionary = {}
var abilities: Array = []
var ability_by_id: Dictionary = {}
## Diplomatie mit neutralen Dörfern (diplomacy.json): Ruf, Verträge, Handel, Dörfer, Boten
var diplomacy: Dictionary = {}
## Gegner-KI (ai.json): Völker, Persönlichkeiten, Schwierigkeit, Bauliste, Armee, Wellen, Rivalität
var ai_cfg: Dictionary = {}
## Entdeckung, Aufmerksamkeit, Kundschaft und Spione (espionage.json)
var espionage: Dictionary = {}
## Zufallsereignisse (events.json): Einstellungen und Ereignisse (Phase 8)
var events_cfg: Dictionary = {}
var event_by_id: Dictionary = {}
## Zufriedenheit der Bewohner (satisfaction.json) und Tag/Nacht (daynight.json)
var satisfaction_cfg: Dictionary = {}
var daynight_cfg: Dictionary = {}
## Belagerung: Ringe, Bresche, Reparatur, Türme (siege.json, Phase 9)
var siege_cfg: Dictionary = {}
## Handelswege, Karawanen, Versorgung (trade.json, Phase 9)
var trade_cfg: Dictionary = {}
## Hilfefenster F1 (help.json): Tasten-Abschnitte, Spielablauf-Themen
var help_cfg: Dictionary = {}
## Tutorial (tutorial.json): Partie, Einstellungen, Schritte
var tutorial_cfg: Dictionary = {}
## Bewerber (recruits.json)
var recruits_cfg: Dictionary = {}
## Truppen (troops.json): Klassen und Konter, Schmiede, Erfahrung und Ränge, Aussehen
var troops_cfg: Dictionary = {}
## Schmiede-Verbesserung (troops.json → forge.upgrades) nach ID
var forge_upgrade_by_id: Dictionary = {}
## Aussehen (troops.json → skins.variants) nach ID
var skin_by_id: Dictionary = {}
## md5 über alle Texte in data/*.json (Spielstände merken sich, mit welchen Daten sie entstanden)
var data_fingerprint: String = ""


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
	# Truppenklassen vor den Einheiten (Klasse und Konter werden beim Normalisieren gesetzt)
	_load_troops()
	_load_units()
	diplomacy = _load_json("diplomacy.json")
	_prepare_diplomacy()
	combat = _load_json("combat.json")
	siege_cfg = _load_json("siege.json")
	trade_cfg = _load_json("trade.json")
	_load_research()
	_load_spells()
	_load_heroes()
	ai_cfg = _load_json("ai.json")
	espionage = _load_json("espionage.json")
	_load_events()
	satisfaction_cfg = _load_json("satisfaction.json")
	daynight_cfg = _load_json("daynight.json")
	help_cfg = _load_json("help.json")
	tutorial_cfg = _load_json("tutorial.json")
	recruits_cfg = _load_json("recruits.json")
	_validate_peoples()
	data_fingerprint = _compute_fingerprint()


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
	return _dig(diplomacy, path, default_value)


## Ruf-Stufen aus diplomacy.json (sortiert nach min aufsteigend, color als Color)
func get_reputation_tiers() -> Array:
	return diplo("reputation.tiers", [])


## Wert aus ai.json über einen Punkt-Pfad, z. B. "waves.gather_seconds"
func ai(path: String, default_value: Variant = null) -> Variant:
	return _dig(ai_cfg, path, default_value)


## Wert aus espionage.json über einen Punkt-Pfad, z. B. "awareness.rumour"
func esp(path: String, default_value: Variant = null) -> Variant:
	return _dig(espionage, path, default_value)


## Wert aus events.json (Abschnitt settings) über Punkt-Pfad, z. B. "difficulty.normal.frequency"
func evt(path: String, default_value: Variant = null) -> Variant:
	return _dig(events_cfg.get("settings", {}), path, default_value)


## Ereignis nach ID ({} wenn unbekannt)
func get_event(id: String) -> Dictionary:
	return event_by_id.get(id, {})


## Alle Ereignisse in Datei-Reihenfolge
func get_events() -> Array:
	return events_cfg.get("events", [])


## Wert aus satisfaction.json über Punkt-Pfad, z. B. "defection.below"
func sat(path: String, default_value: Variant = null) -> Variant:
	return _dig(satisfaction_cfg, path, default_value)


## Wert aus daynight.json über Punkt-Pfad, z. B. "phases.night"
func dn(path: String, default_value: Variant = null) -> Variant:
	return _dig(daynight_cfg, path, default_value)


## Wert aus siege.json über Punkt-Pfad, z. B. "repair.hp_per_work"
func siege(path: String, default_value: Variant = null) -> Variant:
	return _dig(siege_cfg, path, default_value)


## Wert aus trade.json über Punkt-Pfad, z. B. "cut.losses"
func trade(path: String, default_value: Variant = null) -> Variant:
	return _dig(trade_cfg, path, default_value)


## Wert aus tutorial.json über Punkt-Pfad, z. B. "settings.grace_minutes"
## Bewerber (recruits.json)
func rec(path: String, default_value: Variant = null) -> Variant:
	return _dig(recruits_cfg, path, default_value)


func tut(path: String, default_value: Variant = null) -> Variant:
	return _dig(tutorial_cfg, path, default_value)


## Schwierigkeit für die KI: Eintrag aus difficulties.json, ergänzt um ai.json →
## difficulty[id] (eine Kopie; Rückfall auf "normal", wenn die id unbekannt ist)
func get_ai_difficulty(id: String) -> Dictionary:
	var base := get_difficulty(id)
	if base.is_empty():
		base = get_difficulty("normal")
	var result: Dictionary = base.duplicate(true)
	var extra: Variant = ai("difficulty." + id, null)
	if not (extra is Dictionary):
		extra = ai("difficulty.normal", {})
	var extra_dict: Dictionary = extra
	for key in extra_dict:
		var value: Variant = extra_dict[key]
		result[key] = (value as Dictionary).duplicate(true) if value is Dictionary else value
	return result


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


## Gebäudewerte auf einer Ausbaustufe (1 = Grundwerte aus buildings.json; zu hohe Stufen
## werden auf die höchste begrenzt). Die Werte sind fertig gerechnet (mult/set angewendet).
func get_building_at_level(id: String, level: int) -> Dictionary:
	var list: Array = building_level_defs.get(id, [])
	if level <= 1 or list.is_empty():
		return get_building(id)
	return list[mini(level, list.size() + 1) - 2]


## Höchste Ausbaustufe eines Gebäudetyps (1 ohne levels)
func get_building_max_level(id: String) -> int:
	return 1 + (building_level_defs.get(id, []) as Array).size()


## Eintrag aus levels, der auf diese Stufe führt (Kosten, Bauzeit, Bedingungen); {} für Stufe 1
## oder unbekannte Stufen
func get_building_level_entry(id: String, level: int) -> Dictionary:
	var levels: Array = get_building(id).get("levels", [])
	if level < 2 or level - 2 >= levels.size():
		return {}
	return levels[level - 2]


## Name einer Burgstufe (buildings.json → castle.level_names), z. B. "Dorf"
func castle_level_name(level: int) -> String:
	var names: Array = get_building("castle").get("level_names", [])
	if level >= 1 and level <= names.size():
		return str(names[level - 1])
	return "Stufe %s" % level_numeral(level)


## Höchste Burgstufe (1 + Einträge in castle.levels)
func get_castle_max_level() -> int:
	return get_building_max_level("castle")


## Gebäude, die genau ab dieser Burgstufe gebaut werden dürfen (Namen für die Fraktion)
func buildings_unlocked_at(castle_level: int, faction_id: String) -> PackedStringArray:
	var names: PackedStringArray = []
	for b in buildings:
		if bool(b.get("player_buildable", true)) and int(b.get("requires_castle_level", 1)) == castle_level:
			names.append(get_building_name(b, faction_id))
	return names


## Stufe als römische Zahl (I, II, III, IV …)
func level_numeral(level: int) -> String:
	const NUMERALS := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	return NUMERALS[clampi(level, 1, NUMERALS.size()) - 1] if level <= NUMERALS.size() else str(level)


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


## Gezeichnete Spielfiguren (units.json → figures)
func unit_figures() -> Dictionary:
	return figures_cfg


## Grafikpfad eines Einheitentyps für eine Fraktion ("" wenn keiner)
func get_unit_sprite(def: Dictionary, faction_id: String) -> String:
	if def.has("sprite"):
		return str(def["sprite"])
	var sprites: Dictionary = def.get("sprites", {})
	return str(sprites.get(faction_id, sprites.get("good", "")))


## Liest einen Wert aus troops.json über einen Punkt-Pfad, z. B. "veterancy.max_per_stat".
func trp(path: String, default_value: Variant = null) -> Variant:
	return _dig(troops_cfg, path, default_value)


## Schmiede-Verbesserung nach ID ({} wenn unbekannt)
func get_forge_upgrade(id: String) -> Dictionary:
	return forge_upgrade_by_id.get(id, {})


## Name einer Truppenklasse ("cavalry" -> "Reiterei")
func get_class_name(class_id: String) -> String:
	return str((trp("classes", {}) as Dictionary).get(class_id, {}).get("name", class_id))


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
			# "summon:<gebäude>:<einheit>" (Forschung, Bündnis oder Aufnahme eines Dorfs)
			var building_id := parts[1].get_slice(":", 0)
			var unit_id := parts[1].get_slice(":", 1)
			return "Beschwörung in %s: %s" % [get_building_name(get_building(building_id), faction_id),
					str(get_unit_type(unit_id).get("name", unit_id))]
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
## "daynight", "difficulty" und "event:<id>"; ab Phase 7 "espionage:<wirkung>" (Spione)
func describe_effect_source(source: String) -> String:
	match source:
		"supply":
			return "Ohne Versorgung"
		"daynight":
			return "Tageszeit"
		"difficulty":
			return "Schwierigkeit"
		"feast":
			return "Fest"
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
			# Schmiede (troops.json): "Schmiede: Waffen der Fusstruppen"
			if forge_upgrade_by_id.has(parts[1]):
				return "Schmiede: %s" % str(get_forge_upgrade(parts[1]).get("name", parts[1]))
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
			# "event:<id>#<nr>" (Reich) bzw. "event:<id>" (Einheit)
			var event_id := parts[1].get_slice("#", 0).get_slice(":", 0)
			return str(get_event(event_id).get("name", "Ereignis"))
		"feast":
			return "Fest"
		"espionage":
			return "Spionage"
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
	if source.begins_with("espionage:"):
		return Color(0.7, 0.75, 1.0)
	if source.begins_with("event:"):
		return get_event(source.substr(6).get_slice("#", 0).get_slice(":", 0)).get("color", Color.WHITE)
	if source == "daynight":
		return Color(0.62, 0.7, 1.0)
	if source == "feast" or source.begins_with("feast:"):
		return Color(0.95, 0.82, 0.4)
	if source == "supply":
		return Color(0.95, 0.45, 0.35)
	if source.begins_with("upgrade:forge"):
		return Color(0.95, 0.68, 0.42)
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
		"spy_skill":
			return "%+d %% Geschick der Spione" % roundi(add * 100.0)
		"vigilance":
			return "%s Wachsamkeit gegen fremde Spione" % ("%+.1f" % add).replace(".", ",")
		"spy_slots":
			return "%+d Spion" % roundi(add)
		"satisfaction":
			return "%+d Zufriedenheit aller Bewohner" % roundi(add)
		"loyalty":
			return "−%d %% Überlaufen und Verrat" % roundi(add * 100.0)
		"tower_range":
			return "%s Felder Turmreichweite" % ("%+.1f" % add).replace(".", ",")
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
	"damage_taken": "erlittener Schaden", "defense": "Verteidigung", "feast_cost": "Kosten für Feste",
	"fort_hp": "Leben von Mauern, Toren und Türmen", "tower_attack": "Turmschaden"}
const _TIER_NAMES := {"fighter": "Kämpfer", "archer": "Schützen", "elite": "Elite", "scout": "Späher",
	"spearman": "Speerträger", "crossbow": "Armbrustschützen", "heavy": "Schwere Fusstruppen", "cavalry": "Reiter",
	"battlemage": "Kampfmagier",
	"medic": "Heiler", "king": "König", "villager": "Bewohner", "summon": "Beschworene", "hero": "Helden",
	"militia": "Miliz", "resident": "Dorfbewohner", "special": "Volkskrieger", "messenger": "Boten", "spy": "Spione", "refugee": "Flüchtlinge",
	"ram": "Rammböcke", "catapult": "Katapulte", "caravan": "Karawanen"}
const _ROLE_NAMES := {"combat": "alle Truppen ohne Helden", "worker": "Bewohner", "support": "Heiler",
	"king": "König", "monster": "Monster", "hero": "Helden", "messenger": "Boten", "spy": "Spione",
	"caravan": "Karawanen"}


## Lesbare Wirkung eines Modifikators, z. B. "+10 % Angriff (Kämpfer)".
## Rüstung als Faktor ("Rüstung ×1,3"), Angriffspause als Angriffstempo.
func describe_modifier(key: String, factor: float) -> String:
	var stat := key
	var qualifier := ""
	var role_parts := key.split("@", true, 1)
	var class_parts := key.split("#", true, 1)
	if class_parts.size() > 1:
		# Truppenklasse (Schmiede): "attack#cavalry" -> "(Reiterei)"
		stat = class_parts[0]
		qualifier = get_class_name(class_parts[1])
	elif role_parts.size() > 1:
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


## Pfad der Gebäudegrafik für eine Fraktion ("" wenn keine angegeben). people_id
## (optional): zuerst die Grafik dieses Volks (people_sprites, Dorfgebäude; bei
## Gebäuden mit Fraktionsgrafik wie der Burg nur, wenn die Datei existiert), zuletzt
## sprite_fallback.
func get_building_sprite(def: Dictionary, faction_id: String, people_id: String = "") -> String:
	if not people_id.is_empty():
		var by_people: Dictionary = def.get("people_sprites", {})
		if by_people.has(people_id):
			var people_path := str(by_people[people_id])
			# Sonst ersetzte ein Platzhalter die vorhandene Fraktionsgrafik (Burg)
			if not def.has("sprites") or ResourceLoader.exists(people_path):
				return people_path
	if def.has("sprite"):
		return str(def["sprite"])
	var sprites: Dictionary = def.get("sprites", {})
	var path := str(sprites.get(faction_id, sprites.get("good", "")))
	if path.is_empty():
		path = str(def.get("sprite_fallback", ""))
	return path


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
		# Phase 9: Befestigungen, Baumenü-Reiter, Reparatur
		b["segment"] = bool(b.get("segment", false))
		b["fortification"] = str(b.get("fortification", ""))
		b["replaces"] = b.get("replaces", []) if b.get("replaces", []) is Array else []
		b["allow_on_road"] = bool(b.get("allow_on_road", false))
		b["menu"] = str(b.get("menu", "economy"))
		b["max_builders"] = int(b.get("max_builders", 0))
		b["requires_castle_level"] = maxi(int(b.get("requires_castle_level", 1)), 1)
		b["repairable"] = bool(b.get("repairable", b["player_buildable"] or str(b.get("id", "")) == "castle"))
		if b.get("tower", null) is Dictionary:
			var tw: Dictionary = b["tower"]
			tw["attack"] = float(tw.get("attack", 10.0))
			tw["interval"] = maxf(float(tw.get("interval", 1.5)), 0.1)
			tw["range"] = float(tw.get("range", 6.0))
			tw["projectile"] = str(tw.get("projectile", "arrow"))
			if not (tw.get("priority", null) is Dictionary):
				tw["priority"] = {}
		if not b.has("summons"):
			b["summons"] = []
		if not b.has("dropoff"):
			b["dropoff"] = []
		building_by_id[b["id"]] = b
	building_level_defs.clear()
	for b in buildings:
		_prepare_levels(b)


## Werte je Ausbaustufe vorab berechnen (levels: mult auf die Werte der Stufe 1, dann set)
func _prepare_levels(b: Dictionary) -> void:
	var levels: Array = b.get("levels", []) if b.get("levels", []) is Array else []
	b["levels"] = levels
	var list: Array = []
	for i in levels.size():
		var entry: Dictionary = levels[i] if levels[i] is Dictionary else {}
		var cost := {}
		for k in entry.get("cost", {}):
			cost[k] = float(entry["cost"][k])
		entry["cost"] = cost
		entry["build_time"] = maxf(float(entry.get("build_time", b.get("build_time", 10.0))), 0.01)
		entry["requires_castle_level"] = int(entry.get("requires_castle_level", 0))
		entry["requires_population"] = int(entry.get("requires_population", 0))
		entry["requires_upgraded_buildings"] = int(entry.get("requires_upgraded_buildings", 0))
		levels[i] = entry
		var d: Dictionary = b.duplicate(true)
		d.erase("levels")
		d["level"] = i + 2
		var mult: Dictionary = entry.get("mult", {})
		for path in mult:
			_mult_path(d, str(path), float(mult[path]))
		var set_values: Dictionary = entry.get("set", {})
		for key in set_values:
			_merge_value(d, str(key), set_values[key])
		d["housing"] = int(d.get("housing", 0))
		d["workers"] = int(d.get("workers", 0))
		d["gather_radius"] = int(d.get("gather_radius", 0))
		d["territory_radius"] = int(d.get("territory_radius", 0))
		list.append(d)
	if not list.is_empty():
		building_level_defs[b["id"]] = list


## Ganzzahlige Gebäudewerte (werden nach einem Faktor gerundet)
const LEVEL_INT_PATHS := ["housing", "workers", "gather_radius", "territory_radius", "satisfaction.capacity",
		"heal_aura.radius"]


func _mult_path(d: Dictionary, path: String, factor: float) -> void:
	var keys := path.split(".")
	var node: Dictionary = d
	for i in keys.size() - 1:
		if not (node.get(keys[i], null) is Dictionary):
			push_warning("Gebäude '%s', levels: unbekannter Wert '%s'" % [d.get("id"), path])
			return
		node = node[keys[i]]
	var last := keys[keys.size() - 1]
	if not node.has(last):
		push_warning("Gebäude '%s', levels: unbekannter Wert '%s'" % [d.get("id"), path])
		return
	if node[last] is Dictionary:
		var table: Dictionary = node[last]
		for res_id in table:
			table[res_id] = float(table[res_id]) * factor
	elif LEVEL_INT_PATHS.has(path):
		node[last] = roundi(float(node[last]) * factor)
	else:
		node[last] = float(node[last]) * factor


func _merge_value(d: Dictionary, key: String, value: Variant) -> void:
	if value is Dictionary and d.get(key, null) is Dictionary:
		var target: Dictionary = d[key]
		for k in value:
			_merge_value(target, str(k), value[k])
	else:
		d[key] = value.duplicate(true) if (value is Dictionary or value is Array) else value


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


## Völker aus peoples.json (Rückfall: Liste "peoples" in factions.json). Farbe als
## Color, fehlende Listen und Tabellen leer, Zahlen als float.
func _load_peoples(faction_data: Dictionary) -> void:
	var data := faction_data
	if FileAccess.file_exists(DATA_DIR + "peoples.json"):
		data = _load_json("peoples.json")
	peoples = data.get("peoples", [])
	people_by_id.clear()
	for p in peoples:
		p["color"] = _parse_color(p.get("color", "#cccccc"))
		p["letter"] = str(p.get("letter", ""))
		for key in ["leaning", "affinity", "terrain_bonus", "day_bonus", "night_bonus", "base_bonus", "produces",
				"tribute", "gift_preferences", "trade_rates", "delivery", "annex_gift"]:
			if not (p.get(key, null) is Dictionary):
				p[key] = {}
		for key in ["preferred_biomes", "strengths", "weaknesses", "village_names"]:
			if not (p.get(key, null) is Array):
				p[key] = []
		for table in [["trade_rates", "sells"], ["trade_rates", "buys"], ["delivery", "give"], ["delivery", "take"]]:
			var outer: Dictionary = p[table[0]]
			if not (outer.get(table[1], null) is Dictionary):
				outer[table[1]] = {}
		p["trade_bonus"] = float(p.get("trade_bonus", 0.0))
		p["militia_factor"] = float(p.get("militia_factor", 1.0))
		people_by_id[str(p.get("id", ""))] = p


## Prüft die Dorfdaten der Völker (Milizen und Spezialeinheiten müssen in units.json stehen)
func _validate_peoples() -> void:
	for p in peoples:
		for key in ["militia_unit", "special_unit"]:
			var unit_id := str(p.get(key, ""))
			if not unit_id.is_empty() and not unit_by_id.has(unit_id):
				push_error("peoples.json: Volk '%s' – %s '%s' fehlt in units.json" % [p.get("id"), key, unit_id])


## Ruf-Stufen nach Untergrenze sortieren, Farben umwandeln
func _prepare_diplomacy() -> void:
	var tiers: Array = diplo("reputation.tiers", [])
	for tier in tiers:
		tier["color"] = _parse_color(tier.get("color", "#ffffff"))
		tier["min"] = float(tier.get("min", -100.0))
	tiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["min"]) < float(b["min"]))


func _load_units() -> void:
	var data := _load_json("units.json")
	units = data.get("units", [])
	figures_cfg = data.get("figures", {})
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
	if role == "worker" or role == "support" or role == "messenger" or role == "spy" or role == "caravan":
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
	# Phase 9: Belagerungswaffen und Karawanen
	u["unit_damage"] = float(u.get("unit_damage", 1.0))
	u["targets"] = str(u.get("targets", ""))
	u["splash_radius"] = float(u.get("splash_radius", 0.0))
	u["splash_factor"] = float(u.get("splash_factor", 0.0))
	u["mechanical"] = bool(u.get("mechanical", false))
	u["commandable"] = bool(u.get("commandable", true))
	# Truppen (troops.json): Klasse, Konter (Klassen-Tabelle + bonus_vs der Einheit), Rüstungsdurchschlag
	if str(u.get("class", "")).is_empty():
		u["class"] = _default_unit_class(u)
	u["class"] = str(u["class"])
	var counter: Dictionary = (_dig(troops_cfg, "counters." + str(u["class"]), {}) as Dictionary).duplicate()
	var bonus_vs: Variant = u.get("bonus_vs", {})
	if bonus_vs is Dictionary:
		for c in bonus_vs:
			counter[str(c)] = float(counter.get(str(c), 0.0)) + float(bonus_vs[c])
	for c in counter:
		counter[c] = float(counter[c])
	u["counter_vs"] = counter
	u["armor_pierce"] = clampf(float(u.get("armor_pierce", 0.0)), 0.0, 1.0)


## Klasse eines Einheitentyps ohne "class": troops.json → classes_default (Stufe, dann Rolle),
## sonst Fernkämpfer ab Reichweite 2, sonst Fusstruppen
func _default_unit_class(u: Dictionary) -> String:
	var by_tier: Dictionary = _dig(troops_cfg, "classes_default.by_tier", {})
	if by_tier.has(str(u.get("tier", ""))):
		return str(by_tier[str(u["tier"])])
	var by_role: Dictionary = _dig(troops_cfg, "classes_default.by_role", {})
	if by_role.has(str(u.get("role", ""))):
		return str(by_role[str(u["role"])])
	return "ranged" if float(u.get("range", 0.0)) >= 2.0 else "infantry"


## troops.json: Schmiede-Verbesserungen (Kosten als Liste von Dictionaries mit Zahlen) und Skins nach ID
func _load_troops() -> void:
	troops_cfg = _load_json("troops.json")
	forge_upgrade_by_id.clear()
	for up in _dig(troops_cfg, "forge.upgrades", []):
		var entry: Dictionary = up
		var costs: Array = []
		for c in entry.get("cost", []):
			var cost := {}
			for res in (c as Dictionary):
				cost[str(res)] = float(c[res])
			costs.append(cost)
		entry["cost"] = costs
		entry["max_level"] = costs.size()
		entry["class"] = str(entry.get("class", "infantry"))
		if not (entry.get("per_level", null) is Dictionary):
			entry["per_level"] = {}
		forge_upgrade_by_id[str(entry.get("id", ""))] = entry
	skin_by_id.clear()
	for v in _dig(troops_cfg, "skins.variants", []):
		var skin: Dictionary = v
		skin["faction"] = str(skin.get("faction", "any"))
		skin["min_rank"] = int(skin.get("min_rank", 0))
		skin["emblem"] = str(skin.get("emblem", ""))
		if skin.has("tint"):
			skin["tint"] = _parse_color(skin["tint"])
		if skin.has("trim"):
			skin["trim"] = _parse_color(skin["trim"])
		skin_by_id[str(skin.get("id", ""))] = skin


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


## Wert in einem verschachtelten Dictionary über einen Punkt-Pfad ("a.b.c")
## Ereignisse aus events.json: Farbe parsen, duration/group als [min, max] (Floats)
func _load_events() -> void:
	events_cfg = _load_json("events.json")
	event_by_id.clear()
	for e in events_cfg.get("events", []):
		var ev: Dictionary = e
		ev["color"] = _parse_color(ev.get("color", "#ffffff"))
		for key in ["duration", "group", "region_radius", "spawn_distance", "start_infected"]:
			if ev.has(key):
				var range_list: Array = ev[key]
				ev[key] = [float(range_list[0]), float(range_list[range_list.size() - 1])]
		ev["kind"] = str(ev.get("kind", ev.get("id", "")))
		ev["positive"] = bool(ev.get("positive", false))
		if not ev.has("targets"):
			ev["targets"] = ["player", "ai"]
		event_by_id[str(ev.get("id", ""))] = ev


func _dig(root: Dictionary, path: String, default_value: Variant) -> Variant:
	var node: Variant = root
	for key in path.split("."):
		if node is Dictionary and node.has(key):
			node = node[key]
		else:
			return default_value
	return node


## md5 über alle Datendateien (alphabetisch), für den Kopf der Spielstände
func _compute_fingerprint() -> String:
	var names: Array = []
	for f in DirAccess.get_files_at(DATA_DIR):
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for f in names:
		ctx.update(FileAccess.get_file_as_bytes(DATA_DIR + str(f)))
	return ctx.finish().hex_encode()


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
