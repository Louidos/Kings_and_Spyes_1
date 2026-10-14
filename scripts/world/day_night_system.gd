## DayNightSystem
##
## Tag und Nacht (Phase 8): bestimmt aus der Uhrzeit (GameClock) den Abschnitt
## (Morgendämmerung, Tag, Abenddämmerung, Nacht) und setzt bei jedem Wechsel für
## jedes Reich die Quelle "daynight": globale Tag-/Nachtwerte (daynight.json → global,
## global_bonus) und die Tag-/Nachtboni seines Volks (peoples.json → day_bonus,
## night_bonus); die wilden Monster bekommen eigene Werte (wild). In der Dämmerung
## wirken Tag- und Nachtwerte je zu twilight_strength.
## Die Abdunklung der Welt zeichnet DayNightView, das Symbol oben DayClock.
##
## Zustand: phase (aktueller Abschnitt), override_phase (Debug), day_notified (wie viele
## Tag/Nacht-Meldungen schon kamen). Die Reichs-Modifikatoren stehen in
## Kingdom.modifier_sources/bonus_sources und werden in apply_all neu gesetzt.
class_name DayNightSystem
extends Node

## Neuer Abschnitt ("dawn", "day", "dusk", "night")
signal phase_changed(new_phase: String)

const PHASES := ["dawn", "day", "dusk", "night"]
const PHASE_NAMES := {"dawn": "Morgendämmerung", "day": "Tag", "dusk": "Abenddämmerung", "night": "Nacht"}
## Angezeigte Uhrzeit bei erzwungenem Abschnitt (Debug)
const OVERRIDE_HOURS := {"night": 0.0, "dawn": 5.75, "day": 12.0, "dusk": 19.75}

var game: Node
## Aktueller Abschnitt ("" = noch nicht bestimmt)
var phase := ""
## Erzwungener Abschnitt (Debug, "" = echte Zeit)
var override_phase := ""
## Anzahl Tag/Nacht-Meldungen an den Spieler bisher
var day_notified := 0
## Abschnittswechsel seit Spielbeginn (Laufzeit, Rauchtest)
var changes := 0

var _acc := 0.0


func setup(p_game: Node) -> void:
	game = p_game
	GameClock.sim_tick.connect(_on_sim_tick)


## Abschnitt bestimmen (ohne Signal) und "daynight" für alle Reiche setzen
func apply_all() -> void:
	phase = get_phase()
	for k in game.kingdoms:
		apply_kingdom(k)


## Faktoren und Zuschläge der Tageszeit für ein Reich
func apply_kingdom(k: Kingdom) -> void:
	if k == null:
		return
	var p := phase if not phase.is_empty() else get_phase()
	k.replace_modifiers("daynight", compute_modifiers(k, p))
	var bonuses := _compute_bonuses(k, p)
	if bonuses.is_empty():
		if k.bonus_sources.has("daynight"):
			k.clear_bonuses("daynight")
	elif k.bonus_sources.get("daynight", {}) != bonuses:
		k.clear_bonuses("daynight")
		for key in bonuses:
			k.set_bonus("daynight", str(key), float(bonuses[key]))


## Faktoren der Tageszeit p für das Reich k (Volk, global bzw. wild)
func compute_modifiers(k: Kingdom, p: String) -> Dictionary:
	var w := _weights(p)
	var res := {}
	if k.controller == "wild":
		_blend(res, DataDB.dn("wild.day", {}), w.x)
		_blend(res, DataDB.dn("wild.night", {}), w.y)
	else:
		_blend(res, DataDB.dn("global.day", {}), w.x)
		_blend(res, DataDB.dn("global.night", {}), w.y)
		if not k.people_id.is_empty() and not bool(k.flags.get("wanderers", false)):
			var people := DataDB.get_people(k.people_id)
			_blend(res, people.get("day_bonus", {}), w.x)
			_blend(res, people.get("night_bonus", {}), w.y)
	for key in res.keys():
		if absf(float(res[key]) - 1.0) < 0.001:
			res.erase(key)
	return res


## Aktueller Abschnitt: Debug-Vorgabe, sonst aus der Uhrzeit
func get_phase() -> String:
	if not override_phase.is_empty():
		return override_phase
	return phase_for_hour(GameClock.get_hour_float())


## Abschnitt zu einer Uhrzeit (Stunden 0–24)
static func phase_for_hour(h: float) -> String:
	var dawn := float(DataDB.dn("phases.dawn", 5.0))
	var day := float(DataDB.dn("phases.day", 6.5))
	var dusk := float(DataDB.dn("phases.dusk", 19.0))
	var night := float(DataDB.dn("phases.night", 20.5))
	if h >= night or h < dawn:
		return "night"
	if h < day:
		return "dawn"
	if h < dusk:
		return "day"
	return "dusk"


func get_phase_name(p: String = "") -> String:
	return str(PHASE_NAMES.get(p if not p.is_empty() else get_phase(), "?"))


## Nacht oder Abenddämmerung (Monster aktiver, Wellen grösser)
func is_night() -> bool:
	var p := get_phase()
	return p == "night" or p == "dusk"


## Uhrzeit für Anzeige und Tönung (bei Debug-Vorgabe eine typische Zeit des Abschnitts)
func get_display_hour() -> float:
	if not override_phase.is_empty():
		return float(OVERRIDE_HOURS.get(override_phase, 12.0))
	return GameClock.get_hour_float()


## Tageslicht 0 (Nacht) … 1 (Tag), weich über die Dämmerung
func get_daylight() -> float:
	var h := get_display_hour()
	var dawn := float(DataDB.dn("phases.dawn", 5.0))
	var day := float(DataDB.dn("phases.day", 6.5))
	var dusk := float(DataDB.dn("phases.dusk", 19.0))
	var night := float(DataDB.dn("phases.night", 20.5))
	if h >= day and h < dusk:
		return 1.0
	if h >= dawn and h < day:
		return smoothstep(dawn, day, h)
	if h >= dusk and h < night:
		return 1.0 - smoothstep(dusk, night, h)
	return 0.0


## Nächster Abschnitt und Spielsekunden bis dahin
func seconds_to_next() -> Dictionary:
	var p := get_phase()
	var next := str(PHASES[(PHASES.find(p) + 1) % PHASES.size()])
	if not override_phase.is_empty():
		return {"phase": next, "seconds": -1.0}
	var start := float(DataDB.dn("phases." + next, 0.0))
	var hours := fposmod(start - GameClock.get_hour_float(), 24.0)
	return {"phase": next, "seconds": hours / 24.0 * GameClock.seconds_per_day}


## Wirkungen der Tageszeit auf ein Reich als Zeilen ("Nacht: +15 % Angriff (Untote)" …)
func describe_kingdom(k: Kingdom) -> PackedStringArray:
	var lines: PackedStringArray = []
	if k == null:
		return lines
	var p := get_phase()
	var w := _weights(p)
	var label := get_phase_name(p)
	var people := DataDB.get_people(k.people_id)
	var people_name := str(people.get("name", ""))
	var global := {}
	_blend(global, DataDB.dn("global.day", {}), w.x)
	_blend(global, DataDB.dn("global.night", {}), w.y)
	for key in global:
		if absf(float(global[key]) - 1.0) >= 0.001:
			lines.append("%s (alle): %s" % [label, DataDB.describe_modifier(str(key), float(global[key]))])
	var bonuses := _compute_bonuses(k, p)
	for key in bonuses:
		lines.append("%s (alle): %s" % [label, DataDB.describe_bonus(str(key), float(bonuses[key]))])
	if not people.is_empty():
		var own := {}
		_blend(own, people.get("day_bonus", {}), w.x)
		_blend(own, people.get("night_bonus", {}), w.y)
		for key in own:
			if absf(float(own[key]) - 1.0) >= 0.001:
				lines.append("%s: %s (%s)" % [label, DataDB.describe_modifier(str(key), float(own[key])), people_name])
	return lines


## Volksboni bei Tag und bei Nacht als kurzer Text ("Nacht +15 % Angriff; Tag −15 % Angriff")
static func people_daynight_text(people_id: String) -> String:
	var people := DataDB.get_people(people_id)
	var parts: PackedStringArray = []
	for pair in [["night_bonus", "Nacht"], ["day_bonus", "Tag"]]:
		var bonus: Dictionary = people.get(str(pair[0]), {})
		var texts: PackedStringArray = []
		for key in bonus:
			texts.append(DataDB.describe_modifier(str(key), float(bonus[key])))
		if not texts.is_empty():
			parts.append("%s %s" % [str(pair[1]), ", ".join(texts)])
	return "; ".join(parts)


## Debug: Abschnitt erzwingen ("" = wieder echte Zeit)
func debug_force_phase(p: String) -> void:
	override_phase = p if PHASES.has(p) else ""
	var before := phase
	apply_all()
	if phase != before:
		changes += 1
	phase_changed.emit(phase)


# ---------------------------------------------------------------------------
# Takt
# ---------------------------------------------------------------------------

func _on_sim_tick(dt: float) -> void:
	_acc += dt
	if _acc < 1.0:
		return
	_acc = 0.0
	var p := get_phase()
	if p == phase:
		return
	var first := phase.is_empty()
	phase = p
	apply_all()
	if first:
		return
	changes += 1
	phase_changed.emit(p)
	_notify(p)


## Meldung an den Spieler bei Nacht- und Tagesbeginn (nur die ersten notify_days Tage)
func _notify(p: String) -> void:
	if p != "night" and p != "day":
		return
	var player: Kingdom = game.player
	if player == null or day_notified >= int(DataDB.dn("notify_days", 2)) * 2:
		return
	day_notified += 1
	if p == "night":
		var text := "Die Nacht bricht herein – Monster werden aktiver, die Sicht sinkt."
		var people := DataDB.get_people(player.people_id)
		var own: PackedStringArray = []
		var bonus: Dictionary = people.get("night_bonus", {})
		for key in bonus:
			own.append(DataDB.describe_modifier(str(key), float(bonus[key])))
		if not own.is_empty():
			text += " Dein Volk: " + ", ".join(own) + "."
		player.notify(text, "info")
	else:
		player.notify("Ein neuer Tag beginnt.", "info")


## Gewichte (Tag, Nacht) eines Abschnitts
func _weights(p: String) -> Vector2:
	var tw := float(DataDB.dn("twilight_strength", 0.5))
	match p:
		"day":
			return Vector2(1.0, 0.0)
		"night":
			return Vector2(0.0, 1.0)
	return Vector2(tw, tw)


## Additive Zuschläge (global_bonus, z. B. Wachsamkeit) für Nicht-Monster
func _compute_bonuses(k: Kingdom, p: String) -> Dictionary:
	var res := {}
	if k.controller == "wild":
		return res
	var w := _weights(p)
	for pair in [["day", w.x], ["night", w.y]]:
		var entry: Dictionary = DataDB.dn("global_bonus." + str(pair[0]), {})
		for key in entry:
			res[key] = float(res.get(key, 0.0)) + float(entry[key]) * float(pair[1])
	for key in res.keys():
		if absf(float(res[key])) < 0.0001:
			res.erase(key)
	return res


## res[key] = res[key] × (1 + (f − 1) × w)
static func _blend(res: Dictionary, factors: Variant, w: float) -> void:
	if not (factors is Dictionary) or w <= 0.0:
		return
	var dict: Dictionary = factors
	for key in dict:
		res[str(key)] = float(res.get(str(key), 1.0)) * (1.0 + (float(dict[key]) - 1.0) * w)


# ---------------------------------------------------------------------------
# Speichern (Phase 10)
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"phase": phase, "override_phase": override_phase, "day_notified": day_notified}


func from_dict(d: Dictionary) -> void:
	phase = str(d.get("phase", ""))
	override_phase = str(d.get("override_phase", ""))
	day_notified = int(d.get("day_notified", 0))


## "daynight" aller Reiche neu setzen (idempotent)
func rebuild_runtime() -> void:
	_acc = 0.0
	apply_all()
