## AIRecruits
##
## Bewerber für ein KI-Reich (recruits.json → ai_accept): dieselben Regeln wie beim Spieler
## (RecruitSystem.can_accept/accept, Requirements). Die KI nimmt einen Bewerber auf, sobald alle
## Bedingungen erfüllt sind, das Geschenk über der Reserve bezahlt werden kann und danach noch
## min_food Nahrung bleibt; sonst prüft sie alle recheck_seconds erneut, bis er weiterzieht.
## Nur statische Funktionen, der Zustand liegt im Bewerber (ai_decide_at).
class_name AIRecruits
extends RefCounted


## Ein Denkvorgang: offene Bewerber des Reichs entscheiden
static func tick(b: AIBrain, now: float) -> void:
	var rs: Variant = b.game.get("recruit_system")
	if rs == null:
		return
	var recheck := float(DataDB.rec("ai_accept.recheck_seconds", 10))
	for rec in (rs as RecruitSystem).get_recruits(b.k):
		var r: Dictionary = rec
		if str(r["state"]) != "waiting" or now < float(r.get("ai_decide_at", -1.0)):
			continue
		r["ai_decide_at"] = now + recheck
		if wants(b, r) and (rs as RecruitSystem).accept(b.k, int(r["id"])).is_empty():
			b.log_first("first_recruit", now)


## Nimmt die KI diesen Bewerber jetzt auf?
static func wants(b: AIBrain, r: Dictionary) -> bool:
	if not Requirements.all_met(r["reqs"], b.k, b.game):
		return false
	var gift := {}
	for req in r["reqs"]:
		if str((req as Dictionary).get("type", "")) == "gift":
			var cost: Dictionary = (req as Dictionary).get("cost", {})
			for res in cost:
				gift[res] = float(gift.get(res, 0.0)) + float(cost[res])
	if not gift.is_empty() and not b.can_spend(gift):
		return false
	return b.k.get_amount("food") - float(gift.get("food", 0.0)) >= float(DataDB.rec("ai_accept.min_food", 30))
