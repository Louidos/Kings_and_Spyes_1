## Difficulty
##
## Schwierigkeitsgrade an einer Stelle: Werte aus difficulties.json (ergänzt um
## ai.json → difficulty) und ihre Wirkung auf die Reiche. Alle Wirkungen laufen als
## Quelle "difficulty" über Kingdom.set_modifiers und sind idempotent (gleiche Werte
## = keine Änderung), damit sie beim Laden einfach neu gesetzt werden können.
## - KI-Reiche (apply_ai): Ertrag, Stärke, Tempo, Wachsamkeit
## - Wilde Monster (apply_wild): Stärke der Monster und Höhlen
## - Spieler (apply_player_start): Startressourcen (nur bei einer neuen Partie)
## Weitere Werte lesen die Systeme selbst über value() (z. B. Lagerwachstum der
## Monster, Angriffslust der KI; ab Phase 8 Monster-Streifzüge und Ereignisse).
class_name Difficulty
extends RefCounted

## Werte für describe(): Schlüssel, Text, Art ("mult" = ×Faktor, "min" = Minuten, "s" = Sekunden, "n" = Zahl)
const DESCRIBE_ROWS := [
	["enemy_income_mult", "KI-Ertrag", "mult"],
	["enemy_strength_mult", "KI-Stärke (Leben, Angriff, Gebäude)", "mult"],
	["ai_think_interval", "KI-Denkpause", "s"],
	["build_mult", "KI-Bautempo", "mult"],
	["army_size_mult", "KI-Armeegrösse", "mult"],
	["ai_aggression_mult", "KI-Angriffslust", "mult"],
	["first_attack_minutes", "Erste Angriffswelle frühestens nach", "min"],
	["wave_interval", "Pause zwischen Wellen", "s"],
	["awareness_mult", "KI-Aufmerksamkeit", "mult"],
	["max_heroes", "KI-Helden höchstens", "n"],
	["monster_strength_mult", "Monster-Stärke", "mult"],
	["monster_growth_mult", "Nachwuchs der Monsterlager", "mult"],
	["monster_raid_mult", "Monster-Streifzüge", "mult"],
	["player_start_resources_mult", "Deine Startressourcen", "mult"],
]


## Schwierigkeit (leer = die der Partie): difficulties.json + ai.json → difficulty (Kopie)
static func get_def(id: String = "") -> Dictionary:
	return DataDB.get_ai_difficulty(id if not id.is_empty() else GameSession.difficulty_id)


## Zahlenwert der aktuellen Schwierigkeit
static func value(key: String, default_value: float) -> float:
	return float(get_def().get(key, default_value))


## KI-Reich: Ertrag (gather, production), Stärke (hp, attack, building_hp), Tempo (build,
## summon, research) und Wachsamkeit gegen Spione (Zuschlag)
static func apply_ai(k: Kingdom) -> void:
	var d := get_def()
	var inc := float(d.get("enemy_income_mult", 1.0))
	var strength := float(d.get("enemy_strength_mult", 1.0))
	_set_factors(k, {"gather": inc, "production": inc, "hp": strength, "attack": strength,
			"building_hp": strength, "build": float(d.get("build_mult", 1.0)), "summon": float(d.get("summon_mult", 1.0)),
			"research": float(d.get("research_mult", 1.0))})
	var vigilance := float(d.get("vigilance_bonus", 0.0))
	if float((k.bonus_sources.get("difficulty", {}) as Dictionary).get("vigilance", -1.0)) != vigilance:
		k.set_bonus("difficulty", "vigilance", vigilance)


## Wilde Monster: Stärke von Monstern und Höhlen (vor dem Setzen der Höhlen aufrufen,
## weil Building.max_hp beim Aufbau festgelegt wird)
static func apply_wild(k: Kingdom) -> void:
	var m := value("monster_strength_mult", 1.0)
	_set_factors(k, {"hp": m, "attack": m, "building_hp": m})


## Spieler, nur bei einer neuen Partie: Startressourcen × player_start_resources_mult
static func apply_player_start(k: Kingdom) -> void:
	var mult := value("player_start_resources_mult", 1.0)
	if mult == 1.0:
		return
	for res in k.resources.keys():
		k.resources[res] = float(k.resources[res]) * mult
	k.resources_changed.emit()


## Laden: Schwierigkeit für alle KI-Reiche und die Monster neu setzen (geänderte Daten wirken)
static func reapply_all(game: Node) -> void:
	for k in game.kingdoms:
		if k.controller == "ai":
			apply_ai(k)
		elif k.controller == "wild":
			apply_wild(k)


## Kurzbeschreibung für das Hauptmenü: "KI ×1,3 Ertrag · ×1,15 Stärke · erste Welle ab 30 min"
static func short_text(id: String) -> String:
	var d := get_def(id)
	return "KI ×%s Ertrag · ×%s Stärke · erste Welle ab %d min · Monster ×%s" % [
			_num(float(d.get("enemy_income_mult", 1.0))), _num(float(d.get("enemy_strength_mult", 1.0))),
			int(d.get("first_attack_minutes", 45)), _num(float(d.get("monster_strength_mult", 1.0)))]


## Mehrzeilige Beschreibung aller Werte (Tooltip, Hilfe)
static func describe(id: String) -> String:
	var d := get_def(id)
	var lines: PackedStringArray = []
	var text := str(d.get("description", ""))
	if not text.is_empty():
		lines.append(text)
	for row in DESCRIBE_ROWS:
		var key := str(row[0])
		if not d.has(key):
			continue
		var v := float(d[key])
		match str(row[2]):
			"mult":
				lines.append("%s: ×%s" % [row[1], _num(v)])
			"min":
				lines.append("%s %d min" % [row[1], int(v)])
			"s":
				lines.append("%s: %s s" % [row[1], _num(v)])
			_:
				lines.append("%s: %d" % [row[1], int(v)])
	var kingdoms: Dictionary = d.get("kingdoms", {})
	if not kingdoms.is_empty():
		lines.append("Gegnerische Reiche (klein/mittel/gross): %d/%d/%d" % [int(kingdoms.get("small", 1)),
				int(kingdoms.get("medium", 1)), int(kingdoms.get("large", 1))])
	return "\n".join(lines)


## Faktoren der Quelle "difficulty" setzen, nur wenn sie sich ändern (idempotent)
static func _set_factors(k: Kingdom, factors: Dictionary) -> void:
	var current: Dictionary = k.modifier_sources.get("difficulty", {})
	var same := current.size() == factors.size()
	if same:
		for key in factors:
			if not current.has(key) or float(current[key]) != float(factors[key]):
				same = false
				break
	if not same:
		k.clear_modifiers("difficulty")
		k.set_modifiers("difficulty", factors)


## Zahl mit Komma: "1,15", "2"
static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.001:
		return str(roundi(v))
	return String.num(v, 2).replace(".", ",")
