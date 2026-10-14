## AISatisfaction
##
## Zufriedenheit für die KI (Phase 8): bei unzufriedenen Bewohnern baut die KI eine
## Taverne bzw. einen Tempel (reaktiver Bau, AIEconomy) und feiert Feste (AIBrain,
## jeder 3. Denkvorgang). Nur statische Funktionen mit dem Gehirn als Parameter;
## alle Aktionen über dieselben Schnittstellen wie beim Spieler (SatisfactionSystem).
class_name AISatisfaction
extends RefCounted


## Reaktiver Bau: "tavern" oder "temple", wenn die Zufriedenheit unter build_below liegt
## (und die Plätze nicht reichen), sonst ""
static func building_need(b: AIBrain) -> String:
	var ss: Variant = b.game.get("satisfaction_system")
	if ss == null:
		return ""
	var avg := float(ss.get_average(b.k))
	if avg < 0.0 or avg >= float(DataDB.ai("satisfaction.build_below", 45)):
		return ""
	var bs: BuildingSystem = b.game.building_system
	var pop := 0
	for u in b.k.units:
		if bool(u.type_def.get("needs_housing", false)):
			pop += 1
	for id in ["tavern", "temple"]:
		var def := DataDB.get_building(id)
		if def.is_empty() or not bs.can_build_type(def, b.k).is_empty():
			continue
		if _has_site(b.k, id):
			return ""
		var cap := 0
		for bld in b.k.buildings:
			if str(bld.def.get("id", "")) == id:
				cap += int((bld.def.get("satisfaction", {}) as Dictionary).get("capacity", 0))
		if cap < pop:
			return id
	return ""


## Fest feiern, wenn die Zufriedenheit unter feast_below liegt und es möglich ist
static func tick_feast(b: AIBrain) -> void:
	var ss: Variant = b.game.get("satisfaction_system")
	if ss == null:
		return
	var avg := float(ss.get_average(b.k))
	if avg >= 0.0 and avg < float(DataDB.ai("satisfaction.feast_below", 35)) and str(ss.can_hold_feast(b.k)).is_empty():
		ss.hold_feast(b.k)


static func _has_site(k: Kingdom, id: String) -> bool:
	for bld in k.buildings:
		if not bld.constructed and str(bld.def.get("id", "")) == id:
			return true
	return false
