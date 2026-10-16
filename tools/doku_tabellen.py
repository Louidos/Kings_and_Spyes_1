#!/usr/bin/env python3
"""Erzeugt die Tabellen der Spielanleitung aus den Spieldaten (data/*.json).

In docs/spielanleitung.md stehen Abschnitte zwischen Markierungen:

    <!-- AUTO:gebaeude -->
    ... (wird bei jedem Lauf ersetzt) ...
    <!-- /AUTO:gebaeude -->

Aufruf im Projektordner (nur Python 3, keine Zusatzpakete):

    python3 tools/doku_tabellen.py          # Tabellen in docs/spielanleitung.md erneuern
    python3 tools/doku_tabellen.py --check  # nur prüfen, ob sie aktuell sind (Rückgabe 1 = veraltet)

Nach jeder Änderung an den Werten in data/ einmal laufen lassen, damit die Anleitung stimmt.
"""
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
DOC = os.path.join(ROOT, "docs", "spielanleitung.md")


def load(name):
    with open(os.path.join(ROOT, "data", name + ".json"), encoding="utf-8") as f:
        return json.load(f)


PEOPLES = load("peoples")["peoples"]
BUILDINGS = load("buildings")["buildings"]
UNITS = load("units")["units"]
TROOPS = load("troops")
RESEARCH = load("research")
SPELLS = load("spells")
HEROES = load("heroes")
EVENTS = load("events")
DIFFS = load("difficulties")["difficulties"]
AI = load("ai")
JOBS = load("jobs")["jobs"]
RES_NAMES = {r["id"]: r["name"] for r in load("resources")["resources"]}
BIOME_NAMES = {b["id"]: b["name"] for b in load("biomes")["biomes"]}
CLASS_NAMES = {k: v["name"] for k, v in TROOPS["classes"].items()}
UNIT_BY_ID = {u["id"]: u for u in UNITS}
BUILDING_BY_ID = {b["id"]: b for b in BUILDINGS}
MENU_NAMES = {"economy": "Dorf", "military": "Militär & Wissen", "defense": "Verteidigung"}
TIER_ORDER = ["scout", "fighter", "spearman", "archer", "crossbow", "heavy", "elite", "cavalry", "battlemage",
              "medic", "spy", "ram", "catapult"]


def num(v):
    """Zahl im deutschen Format (Komma), ohne unnötige Nachkommastellen."""
    if isinstance(v, float) and not v.is_integer():
        return ("%.2f" % v).rstrip("0").rstrip(".").replace(".", ",")
    return str(int(v))


def pct(v):
    return num(round(v * 100, 1)) + " %"


def cost(d):
    if not d:
        return "–"
    order = ["wood", "stone", "ore", "food", "mana"]
    keys = sorted(d, key=lambda k: order.index(k) if k in order else 99)
    return ", ".join("%s %s" % (num(d[k]), RES_NAMES.get(k, k)) for k in keys)


def cell(text):
    return str(text).replace("|", "/").replace("\n", " ")


def table(head, rows):
    out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    for r in rows:
        out.append("| " + " | ".join(cell(c) for c in r) + " |")
    return "\n".join(out)


def faction_name(b, faction):
    return b.get("names", {}).get(faction, b["name"])


def research_unlocking(key, faction=None):
    names = []
    for r in RESEARCH["research"]:
        if faction and r["faction"] not in (faction, "any"):
            continue
        for e in r.get("effects", []):
            if e.get("type") == "unlock" and e.get("id") == key:
                names.append(r["name"])
    return names


def unit_class(u):
    if "class" in u:
        return u["class"]
    d = TROOPS["classes_default"]
    if u.get("tier") in d["by_tier"]:
        return d["by_tier"][u["tier"]]
    if u.get("role") in d["by_role"]:
        return d["by_role"][u["role"]]
    return "ranged" if float(u.get("range", 0.8)) >= 2.0 else "infantry"


def summon_building(u, faction):
    names = []
    # Freischaltung per Forschung: "summon:<gebäude>:<einheit>" (z. B. Spione in der Burg)
    for r in RESEARCH["research"]:
        for e in r.get("effects", []):
            parts = str(e.get("id", "")).split(":")
            if e.get("type") == "unlock" and len(parts) == 3 and parts[0] == "summon" and parts[2] == u["id"]:
                names.append(faction_name(BUILDING_BY_ID[parts[1]], faction))
    for b in BUILDINGS:
        if u.get("tier") in b.get("summons", []):
            name = faction_name(b, faction)
            if name not in names:
                names.append(name)
    return ", ".join(names) or "–"


def specials(u):
    parts = []
    for k, v in u.get("bonus_vs", {}).items():
        parts.append("+%s gegen %s" % (pct(v), CLASS_NAMES.get(k, k)))
    if u.get("armor_pierce"):
        parts.append("ignoriert %s Rüstung" % pct(u["armor_pierce"]))
    if u.get("splash_radius"):
        parts.append("Flächenschaden (%s Felder)" % num(u["splash_radius"]))
    if u.get("heal"):
        parts.append("heilt %s/s" % num(u["heal"]))
    if u.get("targets") == "buildings":
        parts.append("greift nur Gebäude an")
    bd = u.get("building_damage")
    if bd is not None and bd != 1.0 and u.get("attack", 0):
        parts.append("gegen Gebäude ×%s" % num(bd))
    if u.get("stealth"):
        parts.append("immer getarnt")
    return ", ".join(parts) or "–"


def atk(u):
    return num(u["attack"]) if u.get("attack") else "–"


def rng(u):
    if not u.get("attack"):
        return "–"
    r = float(u.get("range", 0.8))
    return "Nahkampf" if r < 1.5 else num(r)


# ---------------------------------------------------------------- Abschnitte


def sec_voelker():
    out = []
    for fac, title in (("good", "GUT"), ("evil", "BÖSE")):
        rows = []
        for p in PEOPLES:
            if p["faction"] != fac:
                continue
            biomes = ", ".join(BIOME_NAMES.get(b, b) for b in p.get("preferred_biomes", []))
            rows.append(["**%s**" % p["name"], p.get("description", ""), biomes,
                         "<br>".join(p.get("strengths", [])), "<br>".join(p.get("weaknesses", []))])
        out.append("**%s** – spielbare Völker\n\n" % title + table(
            ["Volk", "Beschreibung", "Lieblingsgelände", "Stärken", "Schwächen"], rows))
    rows = []
    for p in PEOPLES:
        if p["faction"] != "neutral":
            continue
        special = UNIT_BY_ID.get(p.get("special_unit", ""), {}).get("name", "–")
        militia = UNIT_BY_ID.get(p.get("militia_unit", ""), {}).get("name", "–")
        rows.append(["**%s**" % p["name"], p.get("village_title", ""),
                     "<br>".join(p.get("strengths", [])), "<br>".join(p.get("weaknesses", [])),
                     cost(p.get("produces", {})), militia, special])
    out.append("**NEUTRAL** – Völker der Dörfer (nicht spielbar)\n\n" + table(
        ["Volk", "Dorf", "Stärken", "Schwächen", "Produktion je Minute", "Miliz", "Volkskrieger"], rows))
    return "\n\n".join(out)


def sec_gebaeude():
    rows = []
    for b in BUILDINGS:
        if b.get("player_buildable", True) is False:
            continue
        name = b["name"]
        evil = b.get("names", {}).get("evil")
        if evil and evil != b.get("names", {}).get("good", name):
            name = "%s / %s" % (b.get("names", {}).get("good", name), evil)
        req = []
        for r in b.get("requires", []):
            if r.startswith("building:"):
                req.append("Forschung " + " / ".join(research_unlocking(r)))
        for rb in b.get("requires_buildings", []):
            req.append(faction_name(BUILDING_BY_ID[rb], "good"))
        if b.get("requires_deposit"):
            req.append("auf einer Manaquelle")
        extra = []
        if b.get("housing"):
            extra.append("Wohnraum %d" % b["housing"])
        if b.get("workers"):
            extra.append("%d Arbeitsplätze" % b["workers"])
        if b.get("max_per_kingdom"):
            extra.append("höchstens %d" % b["max_per_kingdom"])
        size = "%d×%d" % tuple(b["size"])
        rows.append(["**%s**" % name, MENU_NAMES.get(b.get("menu", "economy"), "Dorf"), cost(b.get("cost", {})),
                     num(b.get("build_time", 0)) + " s", size, num(b.get("hp", 300)), ", ".join(req) or "–",
                     b.get("description", "") + (" *(%s)*" % ", ".join(extra) if extra else "")])
    return table(["Gebäude (GUT / BÖSE)", "Baumenü", "Kosten", "Bauzeit", "Grösse", "Leben", "Voraussetzung",
                  "Zweck"], rows) + "\n\nNicht baubar, aber auf der Karte: " + ", ".join(
        "**%s** (%s)" % (b["name"], b.get("description", "")) for b in BUILDINGS
        if b.get("player_buildable", True) is False)


LEVEL_LABELS = {"housing": "Wohnraum", "workers": "Arbeitsplätze", "gather_radius": "Sammelradius",
                "gather_bonus": "Sammeltempo", "production": "Ertrag", "base_production": "Grundertrag", "hp": "Leben",
                "armor": "Rüstung", "tower.attack": "Angriff", "tower.range": "Reichweite",
                "satisfaction.capacity": "versorgt", "satisfaction.bonus": "Zufriedenheit",
                "summon_speed": "Beschwörungstempo", "research_speed": "Forschungstempo",
                "forge_discount": "Schmiede günstiger", "heal_aura.hp_per_sec": "Heilung"}
LEVEL_INT = {"housing", "workers", "gather_radius", "territory_radius", "satisfaction.capacity", "heal_aura.radius"}
LEVEL_PERCENT = {"gather_bonus", "armor", "forge_discount"}


def _dig(d, path):
    for k in path.split("."):
        if not isinstance(d, dict) or k not in d:
            return None
        d = d[k]
    return d


def level_effects(b, entry):
    """Wirkung einer Ausbaustufe als Text (Werte wie im Spiel: Faktor auf Stufe I, dann set)."""
    parts = []
    for path, factor in entry.get("mult", {}).items():
        base = _dig(b, path)
        if base is None and path == "hp":
            base = 300
        label = LEVEL_LABELS.get(path, path)
        if isinstance(base, dict) or base is None:
            parts.append("%s ×%s" % (label, num(factor)))
        elif path in LEVEL_INT:
            parts.append("%s %d" % (label, round(base * factor)))
        elif path in LEVEL_PERCENT:
            parts.append("%s +%s" % (label, pct(base * factor)))
        else:
            parts.append("%s %s" % (label, num(round(base * factor, 1))))
    for key, value in entry.get("set", {}).items():
        if isinstance(value, dict):
            if "plague_spread_mult" in value:
                parts.append("Seuchen ×%s" % num(value["plague_spread_mult"]))
            if "discover_bonus" in value:
                parts.append("Entdeckung +%s" % pct(value["discover_bonus"]))
            continue
        label = LEVEL_LABELS.get(key, key)
        if key.endswith("_speed"):
            parts.append("%s +%s" % (label, pct(value - 1.0)))
        elif key in LEVEL_PERCENT:
            parts.append("%s %s" % (label, pct(value)))
        else:
            parts.append("%s %s" % (label, num(value)))
    return ", ".join(parts)


def sec_ausbau():
    rows = []
    for b in BUILDINGS:
        levels = b.get("levels", [])
        if not levels:
            continue
        cols = []
        for i in range(2):
            if i >= len(levels):
                cols.append("–")
                continue
            e = levels[i]
            text = "%s · %s s · %s" % (cost(e.get("cost", {})), num(e.get("build_time", 0)), level_effects(b, e))
            if e.get("requires_castle_level"):
                text += " · ab Burgstufe %d" % e["requires_castle_level"]
            cols.append(text)
        rows.append(["**%s**" % faction_name(b, "good")] + cols)
    return table(["Gebäude", "Stufe II (Kosten · Arbeit · Wirkung)", "Stufe III"], rows)


def sec_berufe():
    rows = []
    for j in JOBS:
        if j["type"] == "idle":
            continue
        if j["type"] == "gather":
            work = "sammelt %s (%s je s)" % (RES_NAMES.get(j["resource"], j["resource"]), num(j["gather_rate"]))
        elif j["type"] == "builder":
            work = "baut Baustellen, Strassen und repariert (höchstens %d je Baustelle)" % j.get("max_per_site", 4)
        else:
            work = "arbeitet in: " + ", ".join(faction_name(BUILDING_BY_ID[b], "good") for b in j.get("buildings", []))
        rows.append(["**%s**" % j["name"], work, j.get("hint", "")])
    return table(["Beruf", "Arbeit", "Hinweis, wenn er nichts findet"], rows)


def sec_truppen():
    out = []
    for fac, title in (("good", "GUT"), ("evil", "BÖSE")):
        rows = []
        for tier in TIER_ORDER:
            for u in UNITS:
                if u.get("tier") != tier or u.get("faction") != fac:
                    continue
                unlock = []
                for r in u.get("requires", []):
                    unlock += research_unlocking(r, fac)
                if tier == "spy":
                    unlock = research_unlocking("unit:" + u["id"], fac)
                rows.append(["**%s**" % u["name"], CLASS_NAMES.get(unit_class(u), unit_class(u)),
                             summon_building(u, fac), ", ".join(unlock) or "–", num(u.get("hp", 0)),
                             atk(u), (num(u.get("attack_interval", 1.0)) + " s") if u.get("attack") else "–", rng(u),
                             pct(u.get("armor", 0)), num(u.get("speed", 0)), cost(u.get("cost", {})),
                             num(u.get("summon_time", 0)) + " s", specials(u)])
        out.append("**%s**\n\n" % title + table(
            ["Einheit", "Klasse", "Gebäude", "Forschung", "Leben", "Angriff", "Takt", "Reichweite", "Rüstung",
             "Tempo", "Kosten", "Dauer", "Besonderheit"], rows))
    rows = []
    for u in UNITS:
        if u.get("tier") != "special":
            continue
        people = next((p["name"] for p in PEOPLES if p["id"] == u.get("people")), "")
        rows.append(["**%s**" % u["name"], people, CLASS_NAMES.get(unit_class(u), unit_class(u)), num(u["hp"]),
                     atk(u), rng(u), pct(u.get("armor", 0)), num(u["speed"]), cost(u.get("cost", {})),
                     specials(u)])
    out.append("**Volkskrieger** (Kaserne, nach Bündnis mit oder Aufnahme eines Dorfs dieses Volks)\n\n" + table(
        ["Einheit", "Volk", "Klasse", "Leben", "Angriff", "Reichweite", "Rüstung", "Tempo", "Kosten",
         "Besonderheit"], rows))
    return "\n\n".join(out)


def sec_konter():
    classes = ["infantry", "cavalry", "ranged", "mage", "siege", "support", "beast"]
    rows = []
    for a, row in TROOPS["counters"].items():
        if not row:
            continue
        cells = []
        for c in classes:
            v = row.get(c)
            cells.append(("+" if v > 0 else "−") + pct(abs(v)) if v else "·")
        rows.append(["**%s**" % CLASS_NAMES.get(a, a)] + cells)
    return table(["Angreifer ↓ / Ziel →"] + [CLASS_NAMES[c] for c in classes], rows)


def sec_raenge():
    v = TROOPS["veterancy"]
    rows = [["**%s**" % r["name"], num(r["xp"]), num(r["points"])] for r in v["ranks"]]
    t1 = table(["Rang", "nötige EP", "Wertepunkte beim Aufstieg"], rows)
    rows = []
    for s in v["stats"]:
        eff = "+%s" % pct(s["mult"]) if "mult" in s else "+%s Prozentpunkte" % num(s["add"] * 100)
        rows.append(["**%s +**" % s["name"], eff + " je Punkt"])
    t2 = table(["Knopf", "Wirkung"], rows)
    rb = v["rank_bonus"]
    return (t1 + "\n\n" + t2 + "\n\nHöchstens %d Punkte je Wert. Jeder Rang gibt ausserdem +%s Leben und +%s Angriff; "
            "beim Aufstieg heilt die Truppe %s ihres Lebens. EP gibt es je Schadenspunkt (%s EP) und für den "
            "letzten Treffer (%s EP + %s EP je Kampfpunkt des Opfers). Helden bekommen ab Stufe 2 je Stufe %s."
            % (v["max_per_stat"], pct(rb["hp"]), pct(rb["attack"]), pct(v["rank_heal"]), num(v["xp_per_damage"]),
               num(v["kill_xp"]), num(v["kill_xp_per_point"]),
               "einen Wertepunkt" if v["hero_points_per_level"] == 1 else "%d Wertepunkte" % v["hero_points_per_level"]))


def sec_schmiede():
    rows = []
    for up in TROOPS["forge"]["upgrades"]:
        eff = ", ".join("+%s %s" % (pct(f), {"attack": "Angriff", "armor": "Rüstung", "hp": "Leben"}.get(k, k))
                        for k, f in up["per_level"].items())
        names = up.get("names", {})
        rows.append(["**%s**" % up["name"], "%s / %s" % (names.get("good", "–"), names.get("evil", "–")),
                     eff + " je Stufe"] + [cost(c) for c in up["cost"]])
    return table(["Verbesserung", "Name GUT / BÖSE", "Wirkung", "Stufe 1", "Stufe 2", "Stufe 3"], rows)


def sec_skins():
    rows = []
    for s in TROOPS["skins"]["variants"]:
        fac = {"good": "GUT", "evil": "BÖSE", "any": "alle"}.get(s["faction"], s["faction"])
        rows.append(["**%s**" % s["name"], "`%s`" % s["id"], fac, s.get("description", "")])
    return table(["Aussehen", "id (Dateiname)", "Fraktion", "Beschreibung"], rows)


def sec_forschung():
    out = []
    branches = {b["id"]: b["name"] for b in RESEARCH["branches"]}
    by_id = {r["id"]: r for r in RESEARCH["research"]}
    for fac, title in (("good", "GUT"), ("evil", "BÖSE")):
        rows = []
        for br in branches:
            for r in sorted((r for r in RESEARCH["research"] if r["branch"] == br and r["faction"] in (fac, "any")),
                            key=lambda r: (r["tier"], r["name"])):
                req = ", ".join(by_id[q]["name"] for q in r.get("requires", []))
                rows.append([branches[br], num(r["tier"]), "**%s**" % r["name"], r.get("description", ""),
                             req or "–", cost(r.get("cost", {})), num(r["time"]) + " s"])
        out.append("**%s**\n\n" % title + table(
            ["Zweig", "Stufe", "Forschung", "Wirkung", "braucht", "Kosten", "Dauer"], rows))
    return "\n\n".join(out)


def sec_zauber():
    rows = []
    for s in SPELLS["spells"]:
        fac = {"good": "GUT", "evil": "BÖSE"}.get(s.get("faction"), "alle")
        unlock = ", ".join(research_unlocking("spell:" + s["id"])) or "von Anfang an"
        dur = s.get("duration", 0)
        dur_t = "an/aus" if dur == -1 else ("–" if not dur else num(dur) + " s")
        upkeep = (", %s Mana/s" % num(s["upkeep"])) if s.get("upkeep") else ""
        rows.append(["**%s**" % s["name"], fac, num(s.get("mana_cost", 0)) + upkeep, num(s.get("cooldown", 0)) + " s",
                     num(s["radius"]) if s.get("radius") else "ganzes Reich", dur_t, unlock, s.get("description", "")])
    t = table(["Zauber", "Fraktion", "Mana", "Abklingzeit", "Radius", "Dauer", "Forschung", "Wirkung"], rows)
    rows = []
    for u in SPELLS["upgrades"]:
        rows.append(["**%s**" % u["name"], u.get("description", ""),
                     " · ".join(num(c) for c in u["cost_kill_points"])])
    return t + "\n\n**Kampfpunkt-Verbesserungen** (Forschungsfenster, Reiter „Kampfpunkte“)\n\n" + table(
        ["Verbesserung", "Wirkung", "Kampfpunkte je Stufe"], rows)


def sec_helden():
    abil = HEROES["abilities"]
    if isinstance(abil, list):
        abil = {a["id"]: a for a in abil}
    rows = []
    for h in HEROES["heroes"]:
        fac = {"good": "GUT", "evil": "BÖSE"}.get(h["faction"], h["faction"])
        ab = "<br>".join("**%s** – %s" % (abil[a]["name"], abil[a].get("description", "")) for a in h["abilities"])
        st = h.get("stats", {})
        rows.append(["**%s**" % h["name"], fac, h.get("title", ""), "%s / %s" % (num(st.get("hp", 0)),
                     num(st.get("attack", 0))), h.get("leadership_text", "–"), ab])
    return table(["Held", "Fraktion", "Rolle", "Leben / Angriff", "Führung", "Fähigkeiten (C / V / B)"], rows)


def sec_ereignisse():
    rows = []
    for e in EVENTS["events"]:
        dur = e.get("duration")
        dur_t = ("%s–%s min" % (num(dur[0] / 60), num(dur[1] / 60)) if dur[0] != dur[1] else num(dur[0] / 60) + " min") \
            if dur else "–"
        good = "gut" if e.get("positive") else ("Angebot" if e.get("kind") in ("refugees", "wanderers") else "schlecht")
        rows.append(["**%s**" % e["name"], good, e.get("description", ""), "ab Minute %s" % num(e.get("min_minutes", 0)),
                     dur_t])
    s = EVENTS["settings"]
    return table(["Ereignis", "Art", "Wirkung", "frühestens", "Dauer"], rows) + (
        "\n\nEreignisse sind selten: frühestens nach %s Minuten, danach mindestens %s Minuten Pause zwischen zwei "
        "Ereignissen auf der ganzen Karte, ein Reich höchstens alle %s Minuten." % (
            num(s["first_event_minutes"]), num(s["global_min_gap"] / 60), num(s["kingdom_min_gap"] / 60)))


def sec_schwierigkeit():
    rows = []
    aid = AI["difficulty"]
    for d in DIFFS:
        a = aid.get(d["id"], {})
        k = a.get("kingdoms", {})
        rows.append(["**%s**" % d["name"], d.get("description", ""),
                     "%s / %s / %s" % (k.get("small", "?"), k.get("medium", "?"), k.get("large", "?")),
                     "%s min" % num(a.get("first_attack_minutes", 0)),
                     "×%s / ×%s" % (num(d["enemy_income_mult"]), num(d["enemy_strength_mult"])),
                     "×%s" % num(d["monster_strength_mult"]), "×%s" % num(d["player_start_resources_mult"])])
    return table(["Stufe", "Beschreibung", "KI-Reiche (klein / mittel / gross)", "erste Welle frühestens",
                  "KI Ertrag / Stärke", "Monster", "deine Startvorräte"], rows)


def sec_monster():
    rows = []
    for u in UNITS:
        if u.get("faction") != "wild":
            continue
        rows.append(["**%s**" % u["name"], num(u["hp"]), num(u["attack"]), pct(u.get("armor", 0)), num(u["speed"]),
                     num(u.get("kill_points", 0))])
    return table(["Monster", "Leben", "Angriff", "Rüstung", "Tempo", "Kampfpunkte"], rows)


SECTIONS = {
    "voelker": sec_voelker, "gebaeude": sec_gebaeude, "ausbau": sec_ausbau, "berufe": sec_berufe, "truppen": sec_truppen,
    "konter": sec_konter, "raenge": sec_raenge, "schmiede": sec_schmiede, "skins": sec_skins,
    "forschung": sec_forschung, "zauber": sec_zauber, "helden": sec_helden, "ereignisse": sec_ereignisse,
    "schwierigkeit": sec_schwierigkeit, "monster": sec_monster,
}


def main():
    with open(DOC, encoding="utf-8") as f:
        text = f.read()
    new = text
    missing = False
    for name, fn in SECTIONS.items():
        pat = re.compile(r"(<!-- AUTO:%s -->\n).*?(<!-- /AUTO:%s -->)" % (name, name), re.S)
        if not pat.search(new):
            print("Markierung fehlt: <!-- AUTO:%s --> … <!-- /AUTO:%s -->" % (name, name))
            missing = True
            continue
        body = fn()
        new = pat.sub(lambda m: m.group(1) + "\n" + body + "\n\n" + m.group(2), new)
    if "--check" in sys.argv:
        if new != text or missing:
            print("docs/spielanleitung.md ist nicht aktuell – python3 tools/doku_tabellen.py ausführen")
            return 1
        print("OK: Tabellen sind aktuell")
        return 0
    if new != text:
        with open(DOC, "w", encoding="utf-8") as f:
            f.write(new)
        print("docs/spielanleitung.md erneuert")
    else:
        print("Nichts zu tun – Tabellen sind aktuell")
    return 0


if __name__ == "__main__":
    sys.exit(main())
