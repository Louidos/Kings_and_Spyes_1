## HeroUI
##
## Gemeinsame Texte und Hilfen der Helden-Oberfläche (Heldenfenster, Heldenleiste,
## Auswahlfenster, Zielmodus): Rang als römische Zahl, Werte einer Fähigkeit je
## Rang, farbige Tooltips (BBCode), Zustand eines Helden, Kosten mit fehlenden
## Rohstoffen in Rot. Nur Anzeige – die Logik liegt im HeroSystem.
class_name HeroUI
extends RefCounted

## Tasten der drei Fähigkeiten (physisch C / V / B, siehe project.godot)
const ABILITY_KEYS := ["C", "V", "B"]
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.74, 0.71, 0.66)
const COLOR_BAD := Color(1.0, 0.45, 0.38)
const COLOR_WARN := Color(1.0, 0.75, 0.32)
const COLOR_GOOD := Color(0.55, 0.88, 0.5)
## Erfahrungsbalken
const COLOR_XP := Color(0.86, 0.66, 0.22)
## Goldener Rahmen: "selbst auslösen" ist an
const COLOR_AUTOCAST := Color(1.0, 0.8, 0.26)
## Markierung "Stufenwahl offen"
const COLOR_PENDING := Color(1.0, 0.78, 0.2)
const COLOR_DEAD := Color(0.62, 0.6, 0.58)
## Gründe von HeroSystem.can_use, die nur "Ziel fehlt noch" bedeuten (= bereit)
const TARGET_REASONS := ["Wähle einen Feind als Ziel", "Wähle eine Stelle"]
const STAT_NAMES := {"attack": "Angriff", "armor": "Rüstung", "speed": "Tempo", "hp": "Leben",
	"range": "Reichweite", "sight": "Sichtweite", "aggro_range": "Kampfsicht", "regen": "Erholung",
	"lifesteal": "Lebensraub", "hp_per_sec": "Leben/s", "damage_taken": "erlittener Schaden",
	"attack_interval": "Angriffstempo"}
const SIDE_NAMES := {"enemy": "Feinde", "own": "eigene Truppen", "own_kingdom": "eigene Truppen"}


static func roman(n: int) -> String:
	return ["–", "I", "II", "III", "IV", "V"][clampi(n, 0, 5)]


## Bereit (evtl. fehlt nur noch das Ziel)?
static func is_ready_reason(reason: String) -> bool:
	return reason.is_empty() or TARGET_REASONS.has(reason)


## Braucht die Fähigkeit ein Ziel (Feind oder Stelle)? Dann gibt es einen Zielmodus.
static func needs_target(ability_id: String) -> bool:
	var target := str(DataDB.get_ability(ability_id).get("target", "none"))
	return target == "enemy" or target == "point"


## Nur Fähigkeiten auf einen Feind oder rund um den Helden lösen selbst aus
static func can_autocast(ability_id: String) -> bool:
	var def := DataDB.get_ability(ability_id)
	if def.is_empty() or str(def["kind"]) != "active":
		return false
	return str(def["target"]) == "enemy" or str(def["target"]) == "none"


static func is_passive(ability_id: String) -> bool:
	return str(DataDB.get_ability(ability_id).get("kind", "active")) != "active"


## "Ziel: ein Feind", "Wirkt rund um den Helden", "Passiv – wirkt von selbst"
static func target_text(ability_id: String) -> String:
	var def := DataDB.get_ability(ability_id)
	if str(def.get("kind", "active")) != "active":
		return "Passiv – wirkt von selbst"
	match str(def.get("target", "none")):
		"enemy":
			return "Ziel: ein Feind (anklicken)"
		"point":
			return "Ziel: eine Stelle (anklicken)"
		"self":
			return "Wirkt auf den Helden selbst"
	return "Wirkt rund um den Helden"


## Lesbare Zahl ("1,5", "12")
static func num(v: float) -> String:
	return ResourceBar.format_number(v)


## Eine Wirkung {key, mult|add} als Text: "+20 % Angriff", "−8 Leben/s"
static func effect_text(e: Dictionary) -> String:
	var key := str(e.get("key", ""))
	var stat_name := str(STAT_NAMES.get(key, key))
	var text := ""
	if e.has("mult"):
		var f := float(e["mult"])
		if key == "attack_interval":
			# Kürzere Pause zwischen Angriffen = schnelleres Zuschlagen
			text = "%+d %% Angriffstempo" % roundi((1.0 / maxf(f, 0.01) - 1.0) * 100.0)
		else:
			text = "%+d %% %s" % [roundi((f - 1.0) * 100.0), stat_name]
	elif e.has("add"):
		var a := float(e["add"])
		match key:
			"hp_per_sec":
				text = "%s Leben/s" % ResourceBar.format_signed(a)
			"armor", "lifesteal":
				text = "%+d %% %s" % [roundi(a * 100.0), stat_name]
			"range", "sight", "aggro_range":
				text = "%s Felder %s" % [ResourceBar.format_signed(a), stat_name]
			_:
				text = "%s %s" % [ResourceBar.format_signed(a), stat_name]
	return text.replace("-", "−")


## Werte eines Rangs als eine Zeile, z. B. "80 Schaden · Reichweite 1,5 · Abklingzeit 12 s".
## v: ein Rang aus heroes.json oder HeroSystem.get_ability_values (mit Talenten).
static func values_text(ability_id: String, v: Dictionary) -> String:
	var def := DataDB.get_ability(ability_id)
	if def.is_empty():
		return ""
	var parts: PackedStringArray = []
	var damage := float(v.get("damage", 0.0))
	if damage > 0.0:
		parts.append("%s Schaden" % num(damage))
	var heal := float(v.get("heal", 0.0))
	if heal > 0.0:
		parts.append("%s Heilung" % num(heal))
	var unit_effects: Array = v.get("unit_effects", [])
	if not unit_effects.is_empty():
		var texts: PackedStringArray = []
		for e in unit_effects:
			texts.append(effect_text(e))
		var side := str((unit_effects[0] as Dictionary).get("side", "own"))
		parts.append("%s (%s)" % [", ".join(texts), str(SIDE_NAMES.get(side, side))])
	var self_effects: Array = v.get("self_effects", [])
	if not self_effects.is_empty():
		var texts: PackedStringArray = []
		for e in self_effects:
			texts.append(effect_text(e))
		parts.append(", ".join(texts))
	var summon: Dictionary = v.get("summon", {})
	if not summon.is_empty():
		var unit_name := str(DataDB.get_unit_type(str(summon.get("unit", ""))).get("name", "?"))
		parts.append("ruft %d× %s" % [int(summon.get("count", 1)), unit_name])
	if bool(v.get("teleport", false)):
		parts.append("Sprung")
	var aura: Dictionary = v.get("aura", {})
	if not aura.is_empty():
		var texts: PackedStringArray = []
		var side := "own"
		for e in aura.get("effects", []):
			texts.append(effect_text(e))
			side = str((e as Dictionary).get("side", side))
		parts.append("Aura: %s (%s)" % [", ".join(texts), str(SIDE_NAMES.get(side, side))])
	var stat: Dictionary = v.get("stat", {})
	for key in stat:
		var entry: Dictionary = stat[key]
		var e := {"key": str(key)}
		if entry.has("mult"):
			e["mult"] = entry["mult"]
		else:
			e["add"] = entry.get("add", 0.0)
		parts.append(effect_text(e))
	if v.has("mana_cap"):
		parts.append("%+d Mana-Maximum" % roundi(float(v["mana_cap"])))
	if v.has("mana_regen"):
		parts.append("%s Mana/min" % ResourceBar.format_signed(float(v["mana_regen"]) * 60.0))
	var duration := float(v.get("duration", 0.0))
	if duration > 0.0:
		parts.append("%s s" % num(duration))
	var target := str(def["target"])
	var radius := float(v.get("radius", def["radius"]))
	if radius > 0.0 and (target == "point" or target == "none" or not aura.is_empty()):
		parts.append("Kreis %s Felder" % num(radius))
	var range_tiles := float(v.get("range", def["range"]))
	if str(def["kind"]) == "active" and (target == "enemy" or target == "point") and range_tiles > 0.0:
		parts.append("Reichweite %s" % num(range_tiles))
	var cooldown := float(v.get("cooldown", def["cooldown"]))
	if str(def["kind"]) == "active" and cooldown > 0.0:
		parts.append("Abklingzeit %s s" % num(cooldown))
	return " · ".join(parts)


## Farbiger Tooltip einer Fähigkeit: Name, Rang, Beschreibung, Ziel, Werte je
## Rang (aktueller hervorgehoben, mit Talenten), Zustand und Bedienung.
## u: lebende Einheit (für den Zustand) oder null; key: "C" / "V" / "B" oder "".
static func ability_tip(hs: HeroSystem, rec: Dictionary, ability_id: String, u: Unit, key: String) -> String:
	var def := DataDB.get_ability(ability_id)
	if def.is_empty() or rec.is_empty():
		return ""
	var tip := ResearchTipButton
	var rank := hs.get_rank(rec, ability_id)
	var ranks: Array = def["ranks"]
	var lines: PackedStringArray = []
	var head := "[b][color=%s]%s[/color][/b]" % [SpellButton.text_color_html(def.get("color", Color.WHITE)),
			tip.esc(str(def.get("name", ability_id)))]
	if rank > 0:
		head += "   " + tip.colored("Rang %s von %s" % [roman(rank), roman(ranks.size())], COLOR_DIM)
	else:
		head += "   " + tip.colored("noch nicht gelernt", COLOR_BAD)
	lines.append(head)
	lines.append(tip.esc(SpellButton.wrap_text(str(def.get("description", "")))))
	lines.append(tip.colored(target_text(ability_id), COLOR_DIM))
	lines.append("")
	for i in ranks.size():
		var text := values_text(ability_id, ranks[i])
		if i + 1 == rank:
			# Aktueller Rang mit Talenten
			text = values_text(ability_id, hs.get_ability_values(rec, ability_id))
			lines.append("[b]%s[/b]" % tip.colored("%s: %s" % [roman(i + 1), text], COLOR_TEXT))
		else:
			lines.append(tip.colored("%s: %s" % [roman(i + 1), text], COLOR_DIM))
	lines.append("")
	if str(def["kind"]) != "active":
		lines.append(tip.colored("Wirkt von selbst, solange der Held lebt", COLOR_GOOD))
	elif rank <= 0:
		lines.append(tip.colored("Wählbar bei einem Stufenaufstieg (Stufenwahl)", COLOR_WARN))
	else:
		var reason := "Der Held lebt nicht" if u == null else hs.can_use(u, ability_id)
		if reason.begins_with("Bereit in"):
			lines.append(tip.colored(reason, COLOR_WARN))
		elif not is_ready_reason(reason):
			lines.append(tip.colored(reason, COLOR_BAD))
		else:
			var how := "Klick" if key.is_empty() else "Taste %s oder Klick" % key
			match str(def["target"]):
				"enemy":
					how += ": Feind anklicken (zu weit: der Held läuft hin)"
				"point":
					how += ": Stelle anklicken (zu weit: der Held läuft hin)"
				_:
					how += ": sofort wirken"
			lines.append(tip.colored(how, COLOR_GOOD))
		if can_autocast(ability_id):
			var on := hs.is_autocast(rec, ability_id)
			lines.append(tip.colored("Selbst auslösen: %s (Rechtsklick, goldener Rahmen)" % ("an" if on else "aus"),
					COLOR_AUTOCAST if on else COLOR_DIM))
	return "\n".join(lines)


## "EP 45 / 140" bzw. "Höchste Stufe"
static func xp_text(hs: HeroSystem, rec: Dictionary) -> String:
	var need := hs.xp_for_next(rec)
	if need <= 0:
		return "Höchste Stufe"
	return "EP %d / %d" % [int(rec["xp"]), need]


## Zustand: "Gefallen – Wiederbelebung in 42 s", sonst was die Einheit gerade tut
static func state_text(hs: HeroSystem, rec: Dictionary, u: Unit) -> String:
	if bool(rec["dead"]):
		var wait := hs.revive_ready_in(rec)
		if wait > 0.0:
			return "Gefallen – Wiederbelebung in %d s" % ceili(wait)
		return "Gefallen – kann in der Burg wiederbelebt werden"
	if u == null:
		return ""
	var text := u.get_status_text().replace("⚠", "(!)")
	if u.inside != null:
		text = "im Gebäude"
	return text.left(1).to_upper() + text.substr(1)


## Talente als Text: "Gesegnete Klinge, Stärke ×2"
static func talents_text(hs: HeroSystem, rec: Dictionary) -> String:
	var counts := {}
	var order: Array = []
	for t in hs.get_talents(rec):
		var tname := str((t as Dictionary).get("name", ""))
		if not counts.has(tname):
			order.append(tname)
		counts[tname] = int(counts.get(tname, 0)) + 1
	var parts: PackedStringArray = []
	for tname in order:
		var n := int(counts[tname])
		parts.append(str(tname) if n == 1 else "%s ×%d" % [str(tname), n])
	return ", ".join(parts)


## Kosten als BBCode, fehlende Rohstoffe rot: "80 Nahrung, 50 Holz"
static func cost_bbcode(k: Kingdom, cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r in DataDB.resources:
		var res_id := str(r["id"])
		var amount := float(cost.get(res_id, 0.0))
		if amount <= 0.0:
			continue
		var text := "%d %s" % [ceili(amount), str(r["name"])]
		parts.append(ResearchTipButton.colored(text, COLOR_BAD if k.get_amount(res_id) + 0.0001 < amount else COLOR_TEXT))
	return "kostenlos" if parts.is_empty() else ", ".join(parts)


## Lebende Einheit eines Helden der Spieler-Seite, oder null
static func hero_unit(game: Node, hero_id: int) -> Unit:
	if game == null or game.player == null:
		return null
	return game.hero_system.get_unit(game.player, hero_id)
