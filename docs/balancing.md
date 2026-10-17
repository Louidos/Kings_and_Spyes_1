# Balancing

Messwerte aus den Balancing-Läufen (Stand 1.0) und die Stellschrauben, mit denen sich das Spiel ohne Code
nachjustieren lässt.

## Inhalt

1. [So wurde gemessen](#so-wurde-gemessen)
2. [Ergebnisse](#ergebnisse)
3. [Beobachtungen](#beobachtungen)
4. [Leistung](#leistung)
5. [Anpassungen in Phase 10](#anpassungen-in-phase-10)
6. [Selbst nachjustieren](#selbst-nachjustieren)

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
  `wave_interval` und werden je Welle um 3 Einheiten grösser.
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

## Selbst nachjustieren

Nur Daten, kein Code (Details in [Daten anpassen](daten-anpassen.md)):

| Was | Datei → Schlüssel |
|---|---|
| Wie früh und hart die KI angreift | `ai.json` → `difficulty.<stufe>`: `first_attack_minutes`, `patience_minutes`, `wave_interval`, `first_wave_max`, `army_size_mult` |
| Wachstum der KI-Armee über lange Partien | `ai.json` → `army.size_by_minute` (bis 32 h), `army.max_units` |
| Wie das eigene Heer auf den Ruf der Dörfer wirkt | `diplomacy.json` → `strength_attitude` (`friendly_per_interval`, `friendly_cap`, `hostile_per_interval`, `reference_power`) |
| Wie schnell die KI den Spieler bemerkt | `espionage.json` → `awareness` (`rise_per_minute`, `rumour`, `discovered`, `patience_floor`) |
| Stärke und Ertrag der Gegner, Startvorräte | `difficulties.json` |
| Häufigkeit der Ereignisse | `events.json` (`chance_per_check`, Abstände, Abklingzeiten) |
| Monster-Streifzüge, Wachstum der Lager | `combat.json` (`raids`, `lair_growth`) |
| Zufriedenheit, Überläufer | `satisfaction.json` |
| Wirtschaft (Ertrag, Verbrauch) | `economy.json`, `buildings.json` |

Nach einer Änderung die Läufe wiederholen: `GODOT=/pfad/zu/godot tests/run_balance.sh` (Ausgabe in
`build/balance/`; die vier Läufe laufen im Zeitraffer parallel und brauchen trotzdem eine Weile).
