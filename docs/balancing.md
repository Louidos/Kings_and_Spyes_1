# Balancing

Messwerte aus den Balancing-Läufen (Stand 1.0) und die Stellschrauben, mit denen sich das Spiel ohne Code
nachjustieren lässt.

## Inhalt

1. [So wurde gemessen](#so-wurde-gemessen)
2. [Ergebnisse](#ergebnisse)
3. [Beobachtungen](#beobachtungen)
4. [Leistung](#leistung)
5. [Anpassungen in Phase 10](#anpassungen-in-phase-10)
6. [Entdeckung langsamer (nach 1.1.0)](#entdeckung-langsamer-nach-110)
7. [Längere Partien (nach 1.1.0)](#längere-partien-nach-110)
8. [Brunnen, Kornspeicher und Markt (nach 1.2.1)](#brunnen-kornspeicher-und-markt-nach-121)
9. [Selbst nachjustieren](#selbst-nachjustieren)

## So wurde gemessen

`tests/run_balance.sh` (Modul `tests/balance_phase10.gd`, Aufruf `balance=1`, siehe [Testen](testen.md)):

- echte KI, der Spieler tut nichts (passiv),
- Karte *medium*, 2 KI-Reiche,
- 3 Spielstunden (10 800 s = 18 Spieltage) je Fraktion und Schwierigkeit,
- ohne Fenster im Zeitraffer, Seed 12345.

Alle `sample=` Spielsekunden schreibt der Lauf eine Zeile je Reich, am Ende Ergebnis, Leistung und die Grösse aller
Listen der Systeme (`[balance] LISTEN …`). „Unverwundbar“ = `immortal=1`: Burg und König des passiven Spielers
werden geheilt, damit der Lauf die vollen 3 Stunden geht.

## Ergebnisse

| Lauf | Erste Welle gegen den Spieler | Wellen in 3 h | Passiver Spieler fällt | Ereignisse beim Spieler (alle Reiche) | KI nach 3 h (Gebäude / Einheiten / Armee) | Ø Zufriedenheit KI |
|---|---|---|---|---|---|---|
| Normal, GUT, medium | 72 min | 3 | nach 101 min | 2 (5), erstes nach 29 min | 149 / 200 / 38 | 72–82 |
| Normal, BÖSE, medium | 71 min | 5–8 | nach 100 min | 2 (5), erstes nach 29 min | 136 / 164 / 38 | 81–83 |
| Schwer, GUT, medium | 61 min | – | nach 65 min | 1 (2) in 65 min | 61 / 119 / 23 (bei 65 min) | 78 |
| Schwer, BÖSE, medium | 54 min | – | nach 64 min | 1 (2) in 64 min | 58 / 118 / 23 (bei 64 min) | 88 |
| Schwer, GUT, large (unverwundbar) | 63 min | 10 (12 → 24 Einheiten) | – | 3 (7), erstes nach 23 min | 51–82 / 140–195 / 50 | 71–76 |

## Beobachtungen

- **KI-Wachstum:** Die KI wächst über die ganze Zeit (Armee-Soll bis 32 Spielstunden, höchstens 90 je Reich), greift
  den Spieler frühestens nach `first_attack_minutes` und erst nach Kundschaft an; Wellen kommen danach etwa alle
  `wave_interval` und werden je Welle um 2 Einheiten grösser (bis 1.1.0: 3).
- **Ereignisse** bleiben selten (2–3 beim Spieler in 3 Stunden, frühestens nach 20 min).
- **Monster** wachsen bis etwa zum Doppelten des Starts (medium 52 → 98, large 198 → 371) und bleiben dort.
- **Zufriedenheit:** KI-Reiche 70–90; ein passiver Spieler ohne Häuser und Nahrung sinkt auf 25–45 (Überläufer 2–9
  in 3 h) – so gewollt.
- **Listen über lange Partien:** Meldungsprotokoll höchstens 300, Ereignisverlauf 20, Ruf-Verlauf 8 je Dorf; alle
  übrigen Laufzeit-Listen hängen an lebenden Einheiten/Gebäuden und werden mit ihnen aufgeräumt
  (`[balance] LISTEN gewachsen` meldet nur das Protokoll bis zu seiner Grenze).

## Leistung

Ohne Fenster, eine Partie je Kern:

- Simulationsschritt Ø 5,1 ms (medium, 580 Einheiten) bzw. 6,4 ms (large, 860 Einheiten). Bei 10 Schritten je
  Spielsekunde sind das 5–6 % eines Kerns bei Tempo 1x.
- KI-Denkzeit Ø 2,8–3,6 ms je Denkvorgang (ein Reich alle paar Sekunden).
- Grösste Posten: Kampf, Arbeit, Monster.

## Anpassungen in Phase 10

- `ai.json` → `difficulty.*.patience_minutes` (neu; vorher fest 120 min: ein stiller Spieler wurde auf Normal erst
  nach etwa 140 min angegriffen).
- `ai.json` → `army.size_by_minute` bis 1920 min und `army.max_units`.
- Im Code ein Zwischenspeicher für erfolglose Vorkommen-Suchen (Arbeit 4–6 ms → 1,4 ms je Schritt in späten
  Partien).

## Entdeckung langsamer (nach 1.1.0)

Gemessen mit einer Messpartie ohne Fenster: Karte *medium*, Normal, GUT, 3 KI-Reiche, passiver Spieler, Seeds 11, 22
und 33, je 1–2 Läufe vorher und nachher. Gemessen wird, wann das erste Gegnerreich den Spieler entdeckt (Spielminuten).

| Seed | vorher | nachher |
|---|---|---|
| 11 | 71, 77 | 129, 129 |
| 22 | 74, 84 | 109, 132 |
| 33 | 52, 58 | 36, nicht bis min 105 (4 Läufe) |
| Ø | 69 | etwa 105–115 |

Ein stilles Reich wird jetzt also rund 50–70 % später entdeckt. Seed 33 streut stark: Dort lösen Ereignisse wie
eine Verräter-Meldung oder Späher im Gebiet die Entdeckung aus. In vier von fünf Läufen fiel der passive Spieler
nach 105 Minuten anderen Gefahren zum Opfer, bevor ihn ein Reich entdeckte. Angriffe entdecken weiterhin sofort
(Rauchtest *Entdeckung*).

Geänderte Werte:

- `espionage.json` → `awareness`: `rise_per_minute` 3 → 1,8 (−40 %), `discovered` 60 → 75 (+25 %), `rumour` 30 → 37,5,
  `patience_floor` 35 → 44 (bleibt über der Gerüchte-Schwelle), `scout_inside` 2 → 1,2. Neu ist
  `scout_confirm_seconds` 240: KI-Späher bestätigen die Entdeckung erst nach 4 Minuten am Stück im Gebiet (vorher
  wie Spione nach 60 s).
- `espionage.json` → `discovery.per_army_power` 0,12 → 0,084 (−30 %).
- `ai.json` → `difficulty.*.patience_minutes` ×1,5: leicht 135, normal 90, schwer 75, episch 52,5. Die Abstufung nach
  Schwierigkeit bleibt, ebenso `awareness_mult` (0,7 / 1 / 1,2 / 1,4).
  Der Ersatzwert ohne KI (`espionage.json` → `awareness.patience_minutes`) steigt ebenso von 120 auf 180.

## Längere Partien (nach 1.1.0)

Alle Startzeiten der KI-Aggression sind ×1,5, und die Wellen wachsen langsamer. Die Länge des Spieltags
(`time.seconds_per_day`) bleibt gleich.

- `ai.json` → `difficulty.*.first_attack_minutes`: leicht 75 → 112,5, normal 45 → 67,5, schwer 30 → 45, episch
  20 → 30.
- `ai.json` → `difficulty.*.first_village_attack_minutes`: leicht 50 → 75, normal 30 → 45, schwer 20 → 30, episch
  15 → 22,5.
- `ai.json` → `villages.min_minute` 10 → 15 (Dorfdiplomatie), `lairs.min_minute` 10 → 15 (Angriffe auf
  Monsterlager), `fortify.min_minute` 25 → 37,5 (Türme und Mauern).
- `ai.json` → `waves.growth_per_wave` 3 → 2.
- `patience_minutes` (×1,5) gehört zur Gruppe „Entdeckung langsamer“, siehe oben.

Gemessen mit `DISCOVERED=1 DIFFS=normal TIME_SCALE=6 tests/run_balance.sh <ordner> 7200` (Karte *medium*, 2
KI-Reiche, passiver Spieler, Seed 12345). Mit `DISCOVERED=1` kennen die KI-Reiche den Spieler von Anfang an, wie
bei einem aktiven Spieler. So hängt die erste Welle nur an `first_attack_minutes` und am Aufbau der KI:

| Lauf | Erste Welle gegen den Spieler | Passiver Spieler fällt |
|---|---|---|
| Normal, GUT, vorher | 45,0 min | 48,8 min |
| Normal, GUT, nachher | 67,6 min | 71,4 min |
| Normal, BÖSE, vorher | 45,0 min | 49,0 min |
| Normal, BÖSE, nachher | 67,5 min | 71,0 min |

Die erste Welle kommt 50 % später, und eine Partie gegen einen untätigen Spieler dauert rund 45 % länger. Die KI
gewinnt also nicht schneller als vorher. Ein stilles Reich, das die KI noch nicht kennt, wird zusätzlich erst nach
etwa 105–115 Minuten entdeckt (siehe oben), statt wie in 1.1.0 nach etwa 70 Minuten mit der ersten Welle.

## Brunnen, Kornspeicher und Markt (nach 1.2.1)

Drei neue Gebäude für Spieler und KI (`buildings.json`), Werte an ähnlichen Gebäuden ausgerichtet:

| Gebäude | Kosten · Bauzeit · Leben | Voraussetzung | Wirkung | Vergleich |
|---|---|---|---|---|
| **Brunnen** (BÖSE: Zisterne), 1×1 | 15 Holz, 35 Stein · 20 s · 250 | – | +5 Zufriedenheit für alle Bewohner im Umkreis von 8 Feldern (`satisfaction_aura`, mehrere zählen nicht doppelt) | Taverne: +10 für 20 Bewohner, 60 Holz/20 Stein/30 Nahrung, Burgstufe 2. Der Brunnen ist billig und früh, wirkt aber nur halb so stark und nur nahe dem Brunnen – mehrere Brunnen lohnen erst für weit verteilte Siedlungen |
| **Kornspeicher** (Vorratsgrube), 2×2 | 45 Holz, 15 Stein · 30 s · 350 | – | Annahmestelle nur für Nahrung (Sammelradius 12, +15 % Sammeltempo); das Reich verbraucht 10 % weniger Nahrung (`kingdom_mods.food_use`, einmal je Reich) | Lager (40 Holz/10 Stein, alle Waren, ohne Bonus) und Jägerhütte (25 Holz, nur Nahrung, +25 %). Der Kornspeicher kostet etwas mehr als das Lager, sammelt langsamer als die Jägerhütte, spart dafür dauerhaft Nahrung |
| **Markt** (Basar), 3×3 | 80 Holz, 50 Stein, 20 Nahrung · 45 s · 450 | Burgstufe 2 | Handelsmarge −10 Prozentpunkte bei allen Dörfern (`kingdom_bonus.trade_bonus`, einmal je Reich): bessere Kurse beim Tausch und bei der Bezahlung der Handelslieferungen | Handelsvertrag: −15 Punkte (`treaties.trade.rate_bonus`), Ruf 100: −15 Punkte. Der Markt ist etwas schwächer als ein Vertrag, gilt dafür bei allen Dörfern; die Marge bleibt durch `trade.min_margin` (5 %) begrenzt |

**Ersatz-Wirkung:** Nahrung hat im Spiel keine Lagergrenze (nur Mana, `resources.json` → `cap`). „Mehr Lagerplatz
für Nahrung“ hätte deshalb keine Wirkung; der Kornspeicher senkt stattdessen den Nahrungsverbrauch (gut gelagerte
Vorräte verderben weniger) – im Spiel messbar an „Nahrungsverbrauch“ im Reichsfenster und im Einkommen.
Für die Zufriedenheit im Umkreis gab es keinen Haken; der Brunnen nutzt die persönlichen Ursachen des
Zufriedenheitssystems („Brunnen in der Nähe“ beim Bewohner), der Markt den vorhandenen Abzug in
`DiplomacySystem.trade_margin` (wie Vertrag und Volk).

**KI:** `ai.json` → `build_order` baut einen Brunnen nach dem 4. Wohnhaus, den Kornspeicher nach dem 3. Bauernhof,
den Markt nach der Heldenhalle und einen zweiten Brunnen nach dem 6. Wohnhaus – also nachdem die Grundwirtschaft und
die erste Kaserne stehen, damit sich der Burgausbau nicht verzögert.

## Selbst nachjustieren

Nur Daten, kein Code (Details in [Daten anpassen](daten-anpassen.md)):

| Was | Datei → Schlüssel |
|---|---|
| Wie früh und hart die KI angreift | `ai.json` → `difficulty.<stufe>`: `first_attack_minutes`, `patience_minutes`, `wave_interval`, `first_wave_max`, `army_size_mult` |
| Wachstum der KI-Armee über lange Partien | `ai.json` → `army.size_by_minute` (bis 32 h), `army.max_units` |
| Wie das eigene Heer auf den Ruf der Dörfer wirkt | `diplomacy.json` → `strength_attitude` (`friendly_per_interval`, `friendly_cap`, `hostile_per_interval`, `reference_power`) |
| Grösse und Wachstum der Dörfer | `worldgen.json` → `villages.size`, `diplomacy.json` → `village.growth`, `village.militia_max` |
| Startvorsprung der KI-Reiche | `ai.json` → `start_bonus` (Bewohner, Gebäude) |
| Preise nach Angebot und Nachfrage | `trade.json` → `prices` (`reference_stock`, `elasticity`, `min_factor`, `max_factor`) |
| Einstellbare Handelsrouten, Ruf je Lieferung | `trade.json` → `order` (`amount_steps`, `interval_steps`), `reputation_per_delivery`; KI: `ai.json` → `routes.order` |
| Stationierte Truppen bei Verbündeten (Ruf, Abgaben, Hilferufe, KI) | `diplomacy.json` → `station` |
| Wie schnell die KI den Spieler bemerkt | `espionage.json` → `awareness` (`rise_per_minute`, `rumour`, `discovered`, `patience_floor`, `scout_confirm_seconds`, `scout_inside`), `discovery.per_army_power`; Wartezeit `ai.json` → `difficulty.<stufe>.patience_minutes` |
| Stärke und Ertrag der Gegner, Startvorräte | `difficulties.json` |
| Häufigkeit der Ereignisse | `events.json` (`chance_per_check`, Abstände, Abklingzeiten) |
| Monster-Streifzüge, Wachstum der Lager | `combat.json` (`raids`, `lair_growth`) |
| Zufriedenheit, Überläufer | `satisfaction.json` |
| Wirtschaft (Ertrag, Verbrauch) | `economy.json`, `buildings.json` |
| Brunnen, Kornspeicher, Markt | `buildings.json` → `well.satisfaction_aura`, `granary.kingdom_mods`, `market.kingdom_bonus`; KI: `ai.json` → `build_order` |

Nach einer Änderung die Läufe wiederholen: `GODOT=/pfad/zu/godot tests/run_balance.sh` (Ausgabe in
`build/balance/`; die vier Läufe laufen im Zeitraffer parallel und brauchen trotzdem eine Weile).
