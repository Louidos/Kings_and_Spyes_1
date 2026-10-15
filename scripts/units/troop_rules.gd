## TroopRules
##
## Regeln der Truppen aus data/troops.json als reine Hilfsfunktionen ohne Zustand:
## Klassen und Konter, Erfahrung und Ränge, Wertepunkte (daraus die Zuschläge
## Unit.vet_mods) und Aussehen (Skins). Benutzt von Unit (Werte, Grafik), dem
## TroopSystem (Ablauf), dem CombatSystem (Konter) und der Oberfläche (Texte).
class_name TroopRules
extends RefCounted

## Wertepunkte in fester Reihenfolge (Knöpfe im Auswahlfenster)
const STAT_IDS: Array[String] = ["attack", "hp", "armor", "speed"]
## Kurzer Name der Ränge ohne Daten (Rückfall)
const FALLBACK_RANK := "Rekrut"


# ---------------------------------------------------------------------------
# Klassen und Konter
# ---------------------------------------------------------------------------

## Konter-Faktor eines Angreifers (Einheit) gegen ein Opfer (Einheit): 1 + Zuschlag
static func counter_factor(attacker: Unit, victim: Unit) -> float:
	return 1.0 + float(attacker.counter_vs.get(victim.unit_class, 0.0))


## "Stark gegen Reiterei (+100 %) · schwach gegen Reiterei (−20 %)" für einen Einheitentyp ("" ohne Konter)
static func counter_text(def: Dictionary) -> String:
	var strong: PackedStringArray = []
	var weak: PackedStringArray = []
	var counters: Dictionary = def.get("counter_vs", {})
	for c in counters:
		var v := float(counters[c])
		if absf(v) < 0.005:
			continue
		var text := "%s (%s)" % [DataDB.get_class_name(str(c)), _percent(v)]
		if v > 0.0:
			strong.append(text)
		else:
			weak.append(text)
	var parts: PackedStringArray = []
	if not strong.is_empty():
		parts.append("Stark gegen " + ", ".join(strong))
	if not weak.is_empty():
		parts.append("schwach gegen " + ", ".join(weak))
	var pierce := float(def.get("armor_pierce", 0.0))
	if pierce > 0.0:
		parts.append("durchschlägt %d %% Rüstung" % roundi(pierce * 100.0))
	return " · ".join(parts)


## "Klasse: Reiterei" und Konter in einer Zeile (für Tooltips)
static func class_line(def: Dictionary) -> String:
	var line := "Klasse: %s" % DataDB.get_class_name(str(def.get("class", "")))
	var counters := counter_text(def)
	if not counters.is_empty():
		line += " · " + counters
	return line


static func _percent(v: float) -> String:
	return ("%+d %%" % roundi(v * 100.0)).replace("-", "−")


# ---------------------------------------------------------------------------
# Erfahrung und Ränge
# ---------------------------------------------------------------------------

static func ranks() -> Array:
	return DataDB.trp("veterancy.ranks", [])


## Höchster Rang (Index; 0 = nur Rekrut)
static func max_rank() -> int:
	return maxi(ranks().size() - 1, 0)


static func rank_name(rank: int) -> String:
	var list := ranks()
	if list.is_empty():
		return FALLBACK_RANK
	return str((list[clampi(rank, 0, list.size() - 1)] as Dictionary).get("name", FALLBACK_RANK))


## Nötige Erfahrung für einen Rang
static func xp_for_rank(rank: int) -> float:
	var list := ranks()
	if list.is_empty():
		return INF
	if rank >= list.size():
		return INF
	return float((list[maxi(rank, 0)] as Dictionary).get("xp", 0.0))


## Wertepunkte, die der Aufstieg auf diesen Rang bringt
static func points_for_rank(rank: int) -> int:
	var list := ranks()
	if rank <= 0 or rank >= list.size():
		return 0
	return int((list[rank] as Dictionary).get("points", 0))


## Rang zu einer Erfahrung
static func rank_for_xp(xp: float) -> int:
	var rank := 0
	var list := ranks()
	for i in list.size():
		if xp + 0.0001 >= float((list[i] as Dictionary).get("xp", 0.0)):
			rank = i
	return rank


## Sammelt diese Einheit Erfahrung und Ränge? (Truppen der Rollen veterancy.roles,
## keine Helden, keine beschworenen Zaubereinheiten, keine ausgeschlossenen Stufen)
static func is_veteran_type(def: Dictionary) -> bool:
	var roles: Array = DataDB.trp("veterancy.roles", ["combat"])
	if not roles.has(str(def.get("role", ""))):
		return false
	if bool(def.get("temporary", false)):
		return false
	return not (DataDB.trp("veterancy.exclude_tiers", []) as Array).has(str(def.get("tier", "")))


static func is_eligible(u: Unit) -> bool:
	return u != null and u.hero_id == 0 and u.expires_at < 0.0 and is_veteran_type(u.type_def)


# ---------------------------------------------------------------------------
# Wertepunkte
# ---------------------------------------------------------------------------

## Daten eines Wertepunkts (veterancy.stats): {"id", "name", "mult"|"add"}
static func stat_def(stat_id: String) -> Dictionary:
	for s in DataDB.trp("veterancy.stats", []):
		if str((s as Dictionary).get("id", "")) == stat_id:
			return s
	return {}


static func stat_name(stat_id: String) -> String:
	return str(stat_def(stat_id).get("name", stat_id))


static func max_per_stat() -> int:
	return int(DataDB.trp("veterancy.max_per_stat", 4))


## Wirkung eines Punktes als Text: "+6 % Angriff", "+3 % Rüstung" (Prozentpunkte)
static func stat_effect_text(stat_id: String, points: int = 1) -> String:
	var d := stat_def(stat_id)
	if d.has("add"):
		return "+%d %% %s" % [roundi(float(d["add"]) * 100.0 * points), str(d.get("name", stat_id))]
	return "+%d %% %s" % [roundi(float(d.get("mult", 0.0)) * 100.0 * points), str(d.get("name", stat_id))]


## Zuschläge aus Rang und verteilten Punkten: Schlüssel -> {"add", "mult", "parts": [[Text, add, mult], …]}
## (wie Unit.hero_mods). Leeres Dictionary, wenn nichts wirkt.
static func build_mods(rank: int, alloc: Dictionary) -> Dictionary:
	var mods := {}
	if rank > 0:
		var bonus: Dictionary = DataDB.trp("veterancy.rank_bonus", {})
		for key in bonus:
			_part(mods, str(key), "Rang %s" % rank_name(rank), 0.0, 1.0 + float(bonus[key]) * rank)
	for stat_id in alloc:
		var n := int(alloc[stat_id])
		if n <= 0:
			continue
		var d := stat_def(str(stat_id))
		if d.is_empty():
			continue
		var label := "Wertepunkte (%d)" % n
		if d.has("add"):
			_part(mods, str(stat_id), label, float(d["add"]) * n, 1.0)
		else:
			_part(mods, str(stat_id), label, 0.0, 1.0 + float(d.get("mult", 0.0)) * n)
	return mods


static func _part(mods: Dictionary, key: String, label: String, add: float, mult: float) -> void:
	var m: Dictionary = mods.get(key, {"add": 0.0, "mult": 1.0, "parts": []})
	m["add"] = float(m["add"]) + add
	m["mult"] = float(m["mult"]) * mult
	(m["parts"] as Array).append([label, add, mult])
	mods[key] = m


## Summe der verteilten Punkte
static func spent_points(alloc: Dictionary) -> int:
	var n := 0
	for key in alloc:
		n += int(alloc[key])
	return n


## Reihenfolge beim automatischen Verteilen für eine Klasse
static func auto_priority(class_id: String) -> Array:
	var table: Dictionary = DataDB.trp("veterancy.auto_priority", {})
	return table.get(class_id, table.get("default", STAT_IDS))


## Nächster Wert beim automatischen Verteilen ("" = alle voll): bevorzugt die vorderen
## Werte der Reihenfolge, verteilt aber gleichmässig (Punkte + halber Rangplatz)
static func pick_auto_stat(class_id: String, alloc: Dictionary) -> String:
	var order := auto_priority(class_id)
	var best := ""
	var best_score := INF
	var cap := max_per_stat()
	for i in order.size():
		var stat_id := str(order[i])
		var n := int(alloc.get(stat_id, 0))
		if n >= cap:
			continue
		var score := float(n) + i * 0.5
		if score < best_score:
			best_score = score
			best = stat_id
	return best


# ---------------------------------------------------------------------------
# Aussehen (Skins)
# ---------------------------------------------------------------------------

## Hat dieser Einheitentyp Skins? (Rollen skins.roles, keine ausgeschlossenen Stufen)
static func has_skins(def: Dictionary) -> bool:
	if not (DataDB.trp("skins.roles", ["combat"]) as Array).has(str(def.get("role", ""))):
		return false
	if bool(def.get("temporary", false)):
		return false
	return not (DataDB.trp("skins.exclude_tiers", []) as Array).has(str(def.get("tier", "")))


static func skin_def(skin_id: String) -> Dictionary:
	return DataDB.skin_by_id.get(skin_id, {})


static func skin_name(skin_id: String) -> String:
	return str(skin_def(skin_id).get("name", "Standard"))


## Darf ein Reich diesen Skin benutzen? (Fraktion passt)
static func skin_allowed(k: Kingdom, skin_id: String) -> bool:
	var s := skin_def(skin_id)
	if s.is_empty():
		return false
	var f := str(s.get("faction", "any"))
	return f == "any" or (k != null and f == k.faction_id)


## Skins zur Wahl: für den ganzen Typ (rank < 0: ohne Rang-Skins) oder für eine
## Einheit mit diesem Rang. Liste von Skin-IDs in Datenreihenfolge.
static func skins_for(k: Kingdom, def: Dictionary, rank: int = -1) -> Array:
	var list: Array = []
	if not has_skins(def):
		return list
	for v in DataDB.trp("skins.variants", []):
		var s: Dictionary = v
		var sid := str(s.get("id", ""))
		if not skin_allowed(k, sid):
			continue
		var need := int(s.get("min_rank", 0))
		if need > 0 and (rank < 0 or rank < need):
			continue
		list.append(sid)
	return list


## Grafik eines Skins: res://assets/sprites/units/<einheit>_<skin>.png
## Aussehen, das ein Typ im Reich trägt (Wahl "Alle: …"; ohne Rang-Skins), sonst "standard"
static func type_skin(k: Kingdom, def: Dictionary) -> String:
	if k == null or not has_skins(def):
		return "standard"
	var sid := str(k.unit_skins.get(str(def.get("id", "")), "standard"))
	if skin_allowed(k, sid) and int(skin_def(sid).get("min_rank", 0)) <= 0:
		return sid
	return "standard"


static func skin_sprite(type_id: String, skin_id: String) -> String:
	return "res://assets/sprites/units/%s_%s.png" % [type_id, skin_id]
