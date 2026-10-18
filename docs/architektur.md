# Architektur

Technische Dokumentation für alle, die am Code von **Königreiche** arbeiten. Spielregeln stehen in der
[Spielanleitung](spielanleitung.md), die Datenfelder in [Daten anpassen](daten-anpassen.md), die Prüfungen in
[Testen](testen.md).

## Inhalt

1. [Grundsätze](#grundsätze)
2. [Ordnerstruktur](#ordnerstruktur)
3. [Globale Dienste (Autoloads)](#globale-dienste-autoloads)
4. [Spielszene und Aufbau-Reihenfolge](#spielszene-und-aufbau-reihenfolge)
5. [Karte und Welt](#karte-und-welt)
6. [Reiche, Beziehungen und Gebiet](#reiche-beziehungen-und-gebiet)
7. [Die Systeme](#die-systeme)
8. [Das Quellen-Prinzip](#das-quellen-prinzip)
9. [Einheiten, Werte und Zauberwirkungen](#einheiten-werte-und-zauberwirkungen)
10. [Helden](#helden)
11. [Neutrale Dörfer und Diplomatie](#neutrale-dörfer-und-diplomatie)
12. [Gegner-KI](#gegner-ki)
13. [Entdeckung und Spionage](#entdeckung-und-spionage)
14. [Völker, Tag/Nacht, Zufriedenheit, Ereignisse](#völker-tagnacht-zufriedenheit-ereignisse)
15. [Wegfindung, Belagerung und Handel](#wegfindung-belagerung-und-handel)
16. [Truppen: Klassen, Schmiede, Ränge, Aussehen](#truppen-klassen-schmiede-ränge-aussehen)
17. [Tutorial](#tutorial)
18. [Sieg und Niederlage](#sieg-und-niederlage)
19. [Oberfläche](#oberfläche)
20. [Speichern und Laden](#speichern-und-laden)
21. [Exportieren](#exportieren)
22. [Konventionen](#konventionen)

## Grundsätze

- **Godot 4.4+**, GDScript, Renderer *Compatibility* (OpenGL), 2D von oben. Kein C#, keine Erweiterungen.
- **Daten statt Code:** Alle Spielwerte stehen in `data/*.json`. Nur `DataDB` liest JSON.
- **Ein Regelwerk für alle Reiche:** Spieler, KI-Reiche, neutrale Dörfer, Monster und Wanderer sind alle `Kingdom`.
  Die Systeme behandeln sie gleich; der Spieler ist nur das Reich mit `controller = "player"`. Die KI ruft dieselben
  öffentlichen Funktionen auf wie die Oberfläche.
- **Simulation getrennt von der Darstellung:** Die Systeme kennen weder Karte noch HUD. Die Darstellung hört auf
  Signale. Das ist die Grundlage für Speichern/Laden und für die Tests ohne Fenster.
- **Eine Zeitquelle:** `GameClock`. Spielobjekte nutzen `GameClock.frame_delta` statt `delta`.
- **Quellen:** Jede Wirkung auf ein Reich wird mit ihrer Quelle gespeichert und kann so einzeln entzogen werden
  ([Quellen-Prinzip](#das-quellen-prinzip)).
- **Platzhalter statt Pflichtgrafiken:** Fehlt eine Grafik, zeichnet `PlaceholderArt` einen Ersatz
  ([Grafiken](grafiken.md)).
- **Prüfbar:** Skripte ohne Warnungen (`tests/check_scripts.sh` behandelt Warnungen als Fehler), Rauchtests für beide
  Fraktionen ([Testen](testen.md)).

## Ordnerstruktur

```
project.godot            Projekteinstellungen, Autoloads, Tastenbelegung
export_presets.cfg       Export-Vorlagen Windows/Linux (ohne Zugangsdaten)
assets_liste.md          Liste aller Grafiken (für die Bild-KI)
data/                    Spieldaten (JSON) – siehe docs/daten-anpassen.md
docs/                    Dokumentation (für Godot ausgeblendet mit .gdignore), Bilder in docs/bilder/
tools/                   Hilfsprogramme ausserhalb des Spiels (doku_tabellen.py)
scenes/
  main_menu.tscn           Hauptmenü
  game.tscn                Spielszene (Karte, Einheiten, Systeme, HUD, Menüs)
  ui/                      HUD, Spielmenü, Ladebildschirm
scripts/
  game.gd                  Spielszene: Weltgenerierung, Aufbau, globale Tasten, Speichern
  autoload/                DataDB, Settings, GameSession, GameClock, Assets, Notify, SaveManager
  world/                   WorldData, WorldGenerator, WorldMap (Chunks), Tilesets, TerritorySystem, NavGrid,
                           PeopleSystem, DayNightSystem
  economy/                 Kingdom, Building, BuildingSystem, EconomySystem, SatisfactionSystem,
                           TradeRouteSystem, SupplySystem
  units/                   Unit, UnitSystem, WorkSystem, CombatSystem, CommandSystem, SummonSystem, MonsterSystem,
                           SiegeSystem, TroopSystem, TroopRules, SpatialIndex
  magic/                   ResearchSystem, MagicSystem
  heroes/                  HeroSystem
  diplomacy/               VillageSystem, DiplomacySystem, MessengerSystem
  ai/                      AISystem, AIBrain, AIEconomy, AIMilitary, AIDiplomacy, AISiege, AISatisfaction, AIRivalry
  espionage/               EspionageSystem, SpySystem
  events/                  EventSystem
  kingdoms/                Difficulty, VictorySystem
  tutorial/                TutorialSystem
  save/                    SaveGame, SaveCodec, SaveMigration
  camera/                  RTSCamera
  view/                    Darstellung über der Welt: UnitOverlay, CombatEffects, MagicEffects, EventEffects,
                           DayNightView, TradeRouteView
  ui/                      HUD und alle Fenster, Bauvorschau, Auswahl, Zielmodus, Menüs, UiStyle
  util/                    PlaceholderArt, SpriteDraw
assets/
  sprites/                 terrain/, units/, buildings/, heroes/, resources/, effects/
  ui/                      theme.tres, icons/, Menü-Hintergrund
  audio/                   music/, sfx/ (noch leer)
tests/                   Skriptprüfung, Rauchtests, Balancing-Läufe, Bildschirmfotos (siehe docs/testen.md)
```

## Globale Dienste (Autoloads)

| Autoload | Aufgabe |
|---|---|
| `DataDB` | lädt alle JSON-Dateien aus `data/` (in fester Reihenfolge, `reload()`), ergänzt Standardwerte, prüft Verweise (z. B. Völker → Milizen), Hilfsfunktionen (`get_unit_for_tier`, `describe_requirement`, `cost_to_text`) und einen Fingerabdruck der Daten für Spielstände |
| `Settings` | Einstellungen (`user://settings.cfg`): Grafik, Ton, Steuerung, Oberfläche, Spiel (siehe [Oberfläche](#oberfläche)) |
| `GameSession` | Parameter der Partie: Fraktion, Volk, Schwierigkeit, Karte, Seed, Optionen des neuen Spiels (`options`: Gegnerreiche, Dörfer, Startvorräte, Monster, Ereignisse – gespeichert im Spielstand und im Kopf, damit der Weltgenerator beim Laden dieselbe Welt erzeugt), Tutorial, vorgemerkter Spielstand |
| `GameClock` | einzige Zeitquelle der Spielwelt: Pause, Tempo, Tag und Uhrzeit, `frame_delta`, Signal `sim_tick` (10 Schritte pro Spielsekunde) |
| `Assets` | lädt Texturen über ihren Pfad mit Zwischenspeicher (auch Fehltreffer); erzeugt Platzhalter-Figuren und Abzeichen |
| `Notify` | Meldungen (Info, Warnung, Gefahr, gut) mit Ort bzw. Fensterverweis, Protokoll (höchstens 300) |
| `SaveManager` | Spielstände schreiben/lesen im Hintergrund, Plätze, Autospeicher reihum |

Kamera und UI laufen immer in Echtzeit; seltene Logik (Wirtschaft, KI) hängt am Signal `sim_tick`.

## Spielszene und Aufbau-Reihenfolge

`scenes/game.tscn` enthält Karte (`WorldMap`), Einheiten-Ebene, Darstellungs-Ebenen, Kamera, alle Systeme unter dem
Knoten *Systems*, Auswahl, Bauvorschau, Zielmodus, HUD und Spielmenü. Andere Systeme erreichen sich über die
Spielszene (`game.building_system`, `game.player` …).

**Start einer Partie** (`scripts/game.gd`):

1. `_ready`: Uhr anhalten, Ladebildschirm, **Weltgenerierung im Hintergrund-Thread** (`_generate_world`: Spielstand
   lesen, `WorldGenerator.generate`, Fingerabdruck vergleichen, Änderungen anwenden, `NavGrid.build`).
2. `_start_game` → **`_setup_world_and_systems`** in dieser Reihenfolge (spätere Systeme hören auf Signale der
   früheren):
   BuildingSystem → UnitSystem → WorkSystem → EconomySystem → CombatSystem → CommandSystem → SummonSystem →
   ResearchSystem → MagicSystem → HeroSystem → VillageSystem → DiplomacySystem → MessengerSystem →
   EspionageSystem → SpySystem → AISystem → VictorySystem → PeopleSystem → DayNightSystem →
   SatisfactionSystem → EventSystem → SiegeSystem → TradeRouteSystem → SupplySystem → TroopSystem →
   TutorialSystem, danach Bauvorschau, Auswahl und die Darstellungs-Ebenen.
3. Neue Partie: **`_found_new_world`** – Spieler-Reich mit Volk und Burg, Startausstattung der Schwierigkeit,
   Monster-Reich, MonsterSystem, neutrale Dörfer, KI-Reiche, Reich „Wanderer“, Monsterlager, Volks- und
   Tageszeitboni. Geladene Partie: `SaveGame.restore`.
4. `_finish_start`: Kamera, HUD, Tutorial-Oberfläche, Uhr starten, Begrüssung bzw. Ladehinweis.

## Karte und Welt

- `WorldData` (reine Daten: Biome, Höhen, Vorkommen, Strassen, Besitzer, Belegung) ← `WorldGenerator` (läuft im
  Hintergrund-Thread) → `WorldMap` (Darstellung). Gleicher **Seed** = gleiche Welt.
- Nur die **Chunks** (32 × 32 Kacheln) im Sichtfeld werden gebaut; weit herausgezoomt wird nur ein Übersichtsbild
  gezeichnet (1 Pixel pro Kachel).
- Die Weltgenerierung legt Plätze an (`WorldData.get_sites`): `"village"` (Volk, Grösse) und `"kingdom"` (KI-Reiche).
- Signale `WorldData.cell_changed`, `road_changed` → NavGrid und Darstellung.

## Reiche, Beziehungen und Gebiet

- **`Kingdom`** hält Ressourcen, Gebäude, Einheiten, Forschung, Modifikatoren, Helden (`Kingdom.heroes`), KI-Zustand
  (`ai_state`) usw. `Game.create_kingdom`, `Game.found_settlement` gründen Reiche und Siedlungen.
- **Beziehungen:** `Game.set_relation(a, b, "war" | "peace" | "alliance")`; Kampf nur bei Krieg. Die wilden Monster
  sind ein eigenes Reich, mit allen im Krieg. `Game.can_see` ist die Stelle für Sichtbarkeit (Entdeckung, Tarnung).
- **Gebiet** (`TerritorySystem`): Jedes fertige Gebäude beansprucht einen Kreis; bei Überschneidung gewinnt das
  ältere. Gebaut werden darf nur im eigenen Gebiet; Sammler holen nichts aus fremdem Gebiet. Signal `changed`.

## Die Systeme

Alle Systeme sind Nodes unter *Systems* in `game.tscn`, bekommen `setup(game)` und haben die
Speicher-Schnittstelle `to_dict` / `from_dict` / `rebuild_runtime` ([Speichern](#speichern-und-laden)).

| System | Aufgabe |
|---|---|
| `BuildingSystem` | Bauen, Strassen, Linien (Mauern), Produktion, Abreissen, Reparatur, Übergabe von Gebäuden (`transfer_building`), Ausbaustufen (`can_upgrade`, `start_upgrade`, `cancel_upgrade`; die Werte je Stufe rechnet `DataDB.get_building_at_level` vorab, `Building.def` zeigt immer auf die aktuelle Stufe) |
| `UnitSystem` | Einheiten erzeugen, bewegen, Wegberechnung mit Zeitbudget, lange Wege in Abschnitten, Übergabe (`transfer_unit`) |
| `WorkSystem` | Berufe, Sammeln, Bauen, Abliefern; Zwischenspeicher für erfolglose Vorkommen-Suchen |
| `EconomySystem` | Nahrung, Hunger, Wachstum, Burg-Mana, laufende Kosten (`set_upkeep`) |
| `CombatSystem` | Zielsuche, Schaden (immer über `apply_damage`), Konter, Heilung, Tod; Fähigkeitsschaden über `ability_damage` |
| `CommandSystem` | Befehle mit Bedeutungstabelle `COMMANDS`, Formationen Block/Linie/Keil/Kreis, Gruppenmarsch hinter einem Anführer, Armeen 1–9 je Reich; `order_gather`, `order_retreat` (Befehl `rest`), `order_patrol`, `order_reform`, `order_travel`, `set_stance` |
| `SummonSystem` | Beschwörung mit Warteschlange, Sammelpunkt, Rückerstattung |
| `MonsterSystem` | Monsterlager (ruhen, wenn keine fremden Einheiten in der Nähe sind), Streifzüge, Wellen (`spawn_wave`), wachsende und neue Lager |
| `ResearchSystem` | Forschung mit Warteschlange je Reich, Kampfpunkt-Verbesserungen, `restore` aus dem Forschungsstand |
| `MagicSystem` | Zauber des Königs: Wirkungen, Wettergebiete, Tarnung, Beschwörung; `add_unit_effect` |
| `HeroSystem` | Helden: Anwerben, Erfahrung, Stufen mit Wahl, Fähigkeiten, Führung, Tod und Wiederbelebung |
| `VillageSystem`, `DiplomacySystem`, `MessengerSystem` | neutrale Dörfer, Ruf und Verträge, Boten |
| `EspionageSystem`, `SpySystem` | Entdeckung, Aufmerksamkeit, Kundschaft, Tarnung; Spione |
| `AISystem` | gründet KI-Reiche und lässt die Gehirne (`AIBrain`) gestaffelt denken |
| `VictorySystem` | Niederlage der Reiche, Ruinen, Sieg |
| `PeopleSystem`, `DayNightSystem` | Volksboni und Geländeboni, Tageszeiten |
| `SatisfactionSystem`, `EventSystem` | Zufriedenheit, Überlaufen, Verrat, Feste; Zufallsereignisse |
| `RecruitSystem` | Bewerber (`recruits.json`): erscheinen am Gebietsrand, Bedingungen über `Requirements` (gemeinsam mit den Helden), Aufnehmen/Abweisen für Spieler (`RecruitDialog`) und KI (`AIRecruits`) |
| `StationSystem` | Bündnisse (`diplomacy.json` → `station`): Truppen bei verbündeten Dörfern stationieren (Ruf, Abgaben, Verteidigung für die KI-Zielwahl), Hilferufe, Miliz anfordern; Spieler (Diplomatie- und Armeefenster) und KI (`AIDiplomacy.tick_stations`) |
| `SiegeSystem`, `TradeRouteSystem`, `SupplySystem` | Mauern, Tore, Türme; Handelswege; Versorgung |
| `TroopSystem` | Erfahrung, Ränge, Wertepunkte, Schmiede, Aussehen |
| `TutorialSystem` | Schritte, Bedingungen, Schutz, Spielstand des Tutorials |

**Signale im Kampf:** `kingdom_attacked`, `unit_died`, `building_destroyed` feuern mitten in den Schleifen des
CombatSystems. Folgen (Alarm, Boten, Vertragsende …) landen deshalb in einer Warteschlange und laufen im eigenen Takt.

## Das Quellen-Prinzip

Was ein Reich verändert, wird **mit seiner Quelle** gespeichert:

| Quelle | Beispiel |
|---|---|
| `"research:<id>"` | Forschung |
| `"upgrade:<id>"` | Kampfpunkt- und Schmiede-Verbesserungen |
| `"spell:<id>"` | Zauber |
| `"alliance:<dorf-id>"`, `"annex:<dorf-id>"` | Bündnis, aufgenommenes Dorf (schalten den Volkskrieger in der Kaserne frei) |
| `"difficulty"` | Schwierigkeit (KI-Reiche, Monster) |
| `"people:<id>"`, `"daynight"` | Volksbonus, Tageszeit |
| `"event:<id>#<nr>"`, `"feast"` | Ereignisse, Feste |

Arten von Wirkungen: Freischaltungen (`grant_unlock`), Faktoren (`set_modifiers`), Zuschläge (`set_bonus`, z. B.
Mana-Maximum) und laufende Kosten (`set_upkeep`, zieht das EconomySystem ab). Eine Quelle kann so alles wieder
entziehen, ohne andere zu stören; beim Laden baut `ResearchSystem.restore` alles aus dem Forschungsstand neu auf.

## Einheiten, Werte und Zauberwirkungen

- Bewohner, Truppen, König, Helden und Monster sind alle `Unit`. Ihre Werte kommen aus `units.json` und werden mit den
  Modifikatoren des Reichs (Forschung, Schwierigkeit, Volk, Tageszeit, Schmiede) und Wirkungen (Zauber, Helden,
  Ränge) in **`Unit.refresh_stats()`** berechnet.
- Zauberwirkungen auf Einheiten laufen nur über `MagicSystem.add_unit_effect` (mit Ablaufzeit); `refresh_stats`
  rechnet daraus Werte und Tarnung ab.
- Wer arbeitet (Befehl leer), wird nur vom WorkSystem gesteuert; ein Befehl unterbricht die Arbeit, „Zur Arbeit“
  setzt sie fort.
- Haltung: `Unit.stance`; das CombatSystem fragt `stance_allows_engage` / `leash_for` – dieselben Funktionen nutzt
  die KI.

## Helden

- Helden sind Einheiten mit Rolle `hero`; ihr Zustand (Stufe, Erfahrung, Ränge, Talente, Tod, `stat_alloc`) liegt als
  einfacher Eintrag in `Kingdom.heroes`. Alles Abgeleitete (Werte, Auren, Mana-Zuschläge) baut
  `HeroSystem.rebuild_runtime()` neu auf. Ein wiederbelebter Held bekommt dieselbe Einheitennummer und bleibt so in
  seinen Armeen. Fähigkeitsschaden geht über `CombatSystem.ability_damage` (Rüstung zur Hälfte).
- Oberfläche (`scripts/ui/`): `HeroPanel` (Fenster G, Reiter „Meine Helden“ und „Anwerben“), `HeroBar`
  (Heldenleiste), `HeroSelectionBox` (Helden-Abschnitt im Auswahlfenster: Fähigkeiten, Burg: Wiederbeleben, Halle:
  Ausbildung), `AbilityButton`, `HeroPortrait`, `HeroUI` (gemeinsame Texte). Fähigkeiten mit Ziel nutzen den
  Zielmodus von `SpellTargeting` (`start_ability`); der aktive Held einer Auswahl steht im `SelectionController`
  (`get_focus_hero`, `cycle_hero`). Alles ruft nur die Schnittstelle des HeroSystem auf.

## Neutrale Dörfer und Diplomatie

Jedes Dorf ist ein eigenes `Kingdom` (`controller = "neutral"`, Feld `people_id`).

- **`VillageSystem`**: gründet die Dörfer (Dorfzentrum, Hütten, Milizen auf Wachposten), vereinfachte Dorfwirtschaft
  (Produktion ins Dorflager, Tribut, Milizen nachfüllen), Alarm, Bündnishilfe, Eroberung (`try_capture`:
  Dorfzentren werden bei 0 Leben erobert statt zerstört) und `transfer_settlement` (Aufnahme/Eroberung: Gebäude über
  `BuildingSystem.transfer_building`, Milizen über `UnitSystem.transfer_unit`, Gebiet wechselt mit).
- **`VillageResidents`** (Teil des VillageSystem, `village_system.residents`): sichtbare Dorfbewohner (`units.json`
  Stufe `resident`, je Volk `resident_unit`). Reine Darstellung: Tagesablauf (Arbeitsort → arbeiten → Ware ins
  Dorfzentrum → ruhen), nachts in den Hütten, bei Alarm im Dorfzentrum; Befehl `village_life` (kämpft nie, wehrt sich
  nicht). Ihr Zustand steht im Dorf-Datensatz (`residents`), die Einheiten selbst speichert SaveGame wie alle anderen.
  Alltagswege laufen über `UnitSystem.move_to_background` (eigene Warteschlange mit niedrigem Vorrang), damit viele
  Dörfer keine Armeen oder Karawanen bremsen.
- **Dorf-Baustellen** (`VillageSystem.tick_growth`, `tick_sites`): Ein Wachstumsschritt setzt eine Baustelle
  (`BuildingSystem.place_building(…, free, build_time)` mit eigener Bauzeit in `Building.extra.build_time`), die
  Bewohner bauen über `Building.add_work` daran (ohne Bewohner baut das Dorf selbst wie ein Bauarbeiter). Erst die
  fertige Hütte zählt (`_complete_growth`: Grösse, Einwohner, Milizposten, `village_grew`). Zusatzgebäude
  (`village_well`, `village_field`, `village_workshop`, `diplomacy.json` → `village.growth.extras_at_size`) stehen im
  Dorf-Datensatz unter `extra_uids`, offene Baustellen unter `sites`.
- **`DiplomacySystem`**: Ruf je Dorf und Reich (−100 … +100, Stufen, Verfall zum Grundwert, Verlauf), Geschenke,
  Verträge (Schutz, Handel, Bündnis) mit Pflichten und Lieferungen, Tauschhandel mit Tageslimit, Aufnahme, Drohung,
  Krieg/Frieden, Seitenwechsel, Gebietsverletzung. Alle Aktionen haben `Kingdom`-Parameter (Spieler und KI rufen
  dieselben Funktionen auf); Prüfungen geben `""` oder einen deutschen Grund zurück.
- **`MessengerSystem`**: angegriffene Dörfer schicken sichtbare Boten (Befehl `"travel"`, kämpfen nie, sprinten vor
  Feinden) zum nächsten Gegnerreich bzw. Nachbardorf; abgefangene Boten melden nichts.
- Oberfläche: `DiplomacyPanel` (Fenster N, Reiter „Dörfer“, „Reiche“, „Handelswege“), Dorf-Abschnitt im
  `SelectionPanel`, Kriegsbestätigung im `SelectionController` (zweiter Rechtsklick), Dorf- und Botensymbole in der
  `Minimap`, Gebietsname im Infobereich.

## Gegner-KI

- Das **`AISystem`** gründet je nach Schwierigkeit und Kartengrösse KI-Reiche (Fraktion der Gegenseite, eigenes Volk,
  `controller = "ai"`) auf den Plätzen vom Typ `"kingdom"`, setzt die Faktoren der Schwierigkeit (Quelle
  `"difficulty"`) und lässt die Gehirne gestaffelt denken (alle paar Spielsekunden eines; dazu ein billiger
  Schnelltakt für Verteidigung und Wellen).
- **`AIBrain`** hält nur Laufzeit – der Zustand liegt als einfache Werte in `Kingdom.ai_state`. Die Module sind
  statische Funktionen:
  - `AIEconomy` – Bauliste, reaktives Bauen, Bauplatzsuche mit Prüfbudget, Berufe (Soll-Verteilung
    zwischengespeichert, Umverteilung gedrosselt), Forschung, Gebäude ausbauen (`tick_building_upgrades`).
  - `AIMilitary` – Beschwören, Helden, Zauber, Verteidigung, Lager räumen, Angriffswellen mit Sammeln, Marsch und
    Rückzug; `tick_forge` kauft Schmiede-Stufen.
  - `AIDiplomacy` – Dörfer umwerben, Späher, Spione, Reichstarnung.
  - `AISiege` – Türme und Mauerring bei Bedrohung, Belagerungswaffen gegen befestigte Ziele, früher Handelsvertrag.
  - `AISatisfaction` – Zufriedenheit der KI-Reiche (Taverne bzw. Tempel bauen, Feste feiern).
  - `AIRivalry` – Spannung zwischen KI-Reichen bis zum Krieg.
- Die KI benutzt nur die öffentlichen Schnittstellen, die auch der Spieler nutzt. Angriffe auf den Spieler kommen
  erst, wenn er **entdeckt** ist und die Zeitsperre der Schwierigkeit (`first_attack_minutes`, Normal 67,5 min)
  abgelaufen ist.

## Entdeckung und Spionage

- Das **`EspionageSystem`** berechnet je Reich einen **Entdeckungswert** (Gebäude, Bevölkerung, Armee, Helden,
  abklingende Aggression; Reichstarnung −40 %), daraus je Beobachter und Ziel die **Aufmerksamkeit** (Nähe, Sprünge
  durch Angriffe, Boten, ertappte Spione; Stufen Gerüchte und entdeckt) und die **Kundschaft** (Stufe 0–3 mit Alter;
  Quellen: Späher, Spione, Boten, Angriffe).
- Was der Spieler über fremde Reiche sieht (Auswahlfenster, Diplomatie, Spionage), hängt nur an `get_intel_level`,
  `details_visible`, `estimate_strength` und `get_kingdom_summary`.
- Das **`SpySystem`** führt Spione (Stufe der Einheit `spy`, immer getarnt) mit den Aufträgen *Auskundschaften*,
  *Dorf aufhetzen*, *Rivalen aufhetzen* (Befehle `infiltrate` / `spy` / `return` über `CommandSystem.order_travel`),
  würfelt die Entdeckung gegen die Wachsamkeit des Gastgebers und lässt Spione mit Erfahrung aufsteigen.
- Oberfläche: `EspionagePanel` (Fenster K), Knopf „Spionage“ mit Entdeckungsbalken (`HUD`), Spion-Abschnitt und
  Kundschaft im `SelectionPanel`, Burgsymbole und Ruinen in der `Minimap`, Ruinen in der Welt (`CombatEffects`).

## Völker, Tag/Nacht, Zufriedenheit, Ereignisse

- **`PeopleSystem`** (`scripts/world/`): Grundbonus des Volks als Quelle `"people:<id>"`, Geländeboni je Einheit im
  abgeleiteten Feld `Unit.terrain_mods` (nur bei Biomwechsel neu, höchstens 250 Einheiten je Takt).
- **`DayNightSystem`** (`scripts/world/`): Abschnitte Morgen/Tag/Abend/Nacht aus der Uhrzeit, Quelle `"daynight"` je
  Reich (globale Nachtwerte, Tag-/Nachtboni des Volks, eigene Werte für Monster). `DayNightView` (CanvasModulate)
  dunkelt nur die Welt ab, `DayClock` zeigt Sonne bzw. Mond.
- **`SatisfactionSystem`** (`scripts/economy/`): `Unit.satisfaction` je Bewohner nähert sich einem Ziel aus Reichs-
  und persönlichen Ursachen. Folgen über `Unit.work_mult` (Arbeitsleistung), Überlaufen (Befehl `"defect"`, am Ziel
  `UnitSystem.transfer_unit`; das Zielreich greift Überläufer nicht an) und Verrat
  (`EspionageSystem.report_betrayal`); Feste als Quelle `"feast"`. Taverne und Tempel über `satisfaction` in
  `buildings.json`. Sicherheit auch durch Mauerring und Türme (`SiegeSystem.get_safety_bonus`); verlorene Mauerstücke
  und Tore zählen nicht als „Gebäude verloren“.
- **`EventSystem`** (`scripts/events/`): seltene Zufallsereignisse aus `events.json` für alle Reiche; Quellen
  `"event:<id>#<nr>"`, Einheitenwirkungen `"event:<id>"`. Flüchtlinge und Wanderer gehören dem Reich „Wanderer“
  (Befehl `"seek_refuge"`), die KI entscheidet selbst. `EventEffects` zeichnet Gebiete und Blitze.
- **`MonsterSystem`** (ausgebaut): Streifzüge zu nahen Siedlungen (nachts häufiger), Monsterwellen, wachsende Lager,
  neue Lager an freien Plätzen, untätige heimatlose Monster schliessen sich an. Schwierigkeit:
  `monster_growth_mult`, `monster_raid_mult`.
- Oberfläche: `KingdomPanel` (Fenster L), `EventBanner`, `RefugeeDialog`, `MoodIcon`.

## Wegfindung, Belagerung und Handel

- **`NavGrid`** (A* über die ganze Karte): Gelände kostet unterschiedlich viel, Strassen sind schneller, Gebäude
  blockieren. Tore sind im Grundzustand blockiert und werden je Suche nur für Reiche geöffnet, die hindurch dürfen
  (`gate_rule` vom SiegeSystem). Von Mauern eingeschlossene Flächen („Ringe“) bekommen Labels (lokale Flutfüllung nach
  jeder Änderung), damit ein eingemauertes Ziel A* nie die ganze Karte absuchen lässt; `last_fail` nennt den Grund.
- **`SiegeSystem`** (`scripts/units/`): meldet Mauern, Tore und Türme (normale Gebäude mit `fortification`) beim
  NavGrid an, Türme schiessen selbsttätig, `find_breach_target` sucht das Mauerstück, das einen Weg versperrt
  (Bresche), `find_siege_target` die Ziele für Rammböcke und Katapulte.
- **`TradeRouteSystem`** (`scripts/economy/`): Handelswege zu Dörfern mit Handelsvertrag oder Bündnis; Lieferungen
  fahren als Karawane (Befehl `"haul"`), Überfälle bringen Beute, Verluste oder Feinde am Weg schneiden ihn ab.
  `TradeRouteView` zeichnet die Wege gestrichelt, die Minikarte auch. Die Liste (`TradeRouteList`) steht im
  Diplomatiefenster (Reiter „Handelswege“) und in der Reichsübersicht (Reiter „Handel“).
- **`SupplySystem`** (`scripts/economy/`): fern vom eigenen bzw. verbündeten Gebiet und offenen Handelswegen erholen
  sich verletzte Einheiten nicht (Wirkung `supply:regen` über das MagicSystem).

## Truppen: Klassen, Schmiede, Ränge, Aussehen

`data/troops.json`, `scripts/units/troop_system.gd`, `troop_rules.gd`, UI `TroopSelectionBox`:

- **Klasse** (`class` in units.json: infantry, cavalry, ranged, mage, siege, support). Der Schaden in
  `CombatSystem._damage_value` wird mit dem **Konter** multipliziert: Klassen-Tabelle `troops.json → counters` plus
  `bonus_vs` der Einheit (DataDB legt beides als `counter_vs` je Typ zusammen); `armor_pierce` senkt die wirksame
  Rüstung des Opfers.
- **Schmiede** (Gebäude mit `"forge": true`): Stufen je Klasse (`forge.upgrades`), gemerkt in `Kingdom.forge_levels`,
  Wirkung als Modifikatoren mit Quelle `"upgrade:<id>"` und dem Schlüssel `"<wert>#<klasse>"` (z. B.
  `attack#cavalry`; `Unit._stat_from` liest ihn zusätzlich zu Stufe und Rolle).
- **Erfahrung und Ränge**: das TroopSystem hört auf `CombatSystem.attacked` (EP je Schaden) und `unit_died` (EP für
  den letzten Treffer, `Unit.last_hit_by`). Ränge Rekrut → Soldat → Veteran → Elite → Held der Truppe
  (`veterancy.ranks`) bringen Wertepunkte; Rang und Punkte wirken als `Unit.vet_mods` (wie `hero_mods`).
  `Kingdom.auto_stat_points` (Spieler aus, KI und Dörfer an) verteilt neue Punkte selbst. Helden bekommen einen Punkt
  je Stufe (`stat_alloc` im Heldeneintrag, beim Wiederbeleben und Laden übernommen).
- **Aussehen**: `Kingdom.unit_skins` (Typ → Skin) und `Unit.skin` (einzelne Einheit); `Unit.refresh_look` lädt
  `<einheit>_<skin>.png` oder zeichnet den Platzhalter (`PlaceholderArt.make_unit_skin_token`, `make_emblem`). Die
  Bilder in Fenstern (`UnitIcon`: Beschwören-Knöpfe, Warteschlange, Armeefenster) zeigen dasselbe Aussehen
  (`TroopRules.type_skin`).
- Gespeichert: `Unit.SAVE_OPTIONAL` (`vet_xp`, `vet_rank`, `stat_points`, `stat_alloc`, `skin`), die Felder der Reiche
  automatisch; `TroopSystem.rebuild_runtime` setzt die Schmiede-Modifikatoren neu.
- KI: `ai.json → army.composition` mit den neuen Stufen, Gebäude in `build_order`, `AIMilitary.tick_forge` kauft
  Schmiede-Stufen (`ai.json → forge`).
- **Armeefenster** (`TroopPanel`, Taste T): Übersicht je Typ, Helden, Armeen; Befehle über die Funktionen des
  CommandSystem (siehe [Die Systeme](#die-systeme)).

## Tutorial

`scripts/tutorial/tutorial_system.gd`, `scripts/ui/tutorial_overlay.gd`, `data/tutorial.json`:

- Das **`TutorialSystem`** (Node unter *Systems*, im Spielstand als `"tutorial"`) führt durch die 37 Schritte der
  Datei. Bedingungen wie `building_placed:house` oder `window_opened:heroes` liest es alle 0,25 echte Sekunden aus dem
  Zustand des Spiels (läuft auch in der Pause); Aktionen ohne bleibenden Zustand (Bewegungsbefehl, Speichern, Tempo)
  merkt es sich über Signale (`SelectionController.command_issued`, `SaveManager.save_finished`,
  `GameClock.speed_changed`).
- Der **Schutz** (`TutorialSystem.protects(game, kingdom)`) wird von `AIMilitary` (Wellenziele), `EventSystem`
  (Ereignisziele) und `MonsterSystem` (Streifzüge) abgefragt: höchstens 120 Spielminuten ab dem ersten Start, nach dem
  Ende noch 10 Minuten. Ein im Spielmenü nachträglich gestartetes Tutorial in einer normalen Partie schützt nicht.
- Geschenke des Hofschatzmeisters (`grant`) gibt es einmal je Partie, auch nach „von vorn“ nicht doppelt. Beim
  Schritt „Ränge und Wertepunkte“ steigt ein Krieger einmal auf (`promote`).
- **`TutorialOverlay`** (Ebene 30) zeigt Fenster, Rahmen und Pfeil und lässt alle Klicks zum Ziel durch.
- Spielstand: Schritt, Zustand, Schutz und bezahlte Geschenke (`TutorialSystem.to_dict`); nach dem Laden geht es beim
  gleichen Schritt weiter.

## Sieg und Niederlage

- `Game.defeat_kingdom` – stirbt der König des Spielers oder fällt seine Burg, ist das Spiel verloren.
- **`VictorySystem`** (`scripts/kingdoms/victory_system.gd`): Fällt die Burg oder stirbt der König eines KI-Reichs,
  zerfällt es im eigenen Takt (Gebäude werden zu Ruinen, Truppen lösen sich auf, Verträge enden, das Gebiet
  verschwindet). Sind alle feindlichen Reiche gefallen, zeigt `game.gd` den Siegbildschirm mit Statistik
  („Weiterspielen“ möglich).

## Oberfläche

- **`UiStyle`**: gemeinsamer Fensterstil – `window_style`, `window_header`, `header_add`, `tab_button`,
  `section_label`, `footer_label` geben allen Fenstern denselben Rahmen, dieselbe Titelzeile und dieselben Reiter
  (Rahmen und Titel in der Farbe der Fraktion: GUT Gold, BÖSE Violett). Es ist immer nur ein Fenster in der Mitte
  offen; Esc schliesst das offene zuerst (`hud.close_top_panel`).
- **UI-Grösse**: HUD, Spielmenü, Hilfe, Protokoll und Sieg/Niederlage sind als Ebenen angemeldet
  (`register_scaled_layer`: Ebene skaliert, Wurzel = Viewport / Faktor); die zentrierten Fenster platzieren sich mit
  `UiStyle.place_window` (Faktor, aber nie grösser als der Bildschirm), die Zauberleiste folgt der skalierten
  Minikarte. Die obere Leiste passt sich an (`hud._fit_top_bar`: Reichsname ausblenden, sonst verkleinern).
- **Aufbau des HUD**:
  - *Obere Leiste* in drei Gruppen: links Ressourcen, Kampfpunkte, Bewohner, Zufriedenheit und König; in der Mitte die
    Fenster-Knöpfe *Forschung · Helden · Armee · Diplomatie · Spionage · Reich* (Zahl, Strich und roter Punkt zeigen
    den Stand, die Taste steht im Tooltip); rechts Tageszeit, Datum und Tempo.
  - *Links*: oben die Arbeitsverteilung (`JobPanel`, J); sie klappt sich von selbst ein, solange das Auswahlfenster
    darunter den Platz braucht. Unten das Auswahlfenster (`SelectionPanel`), Armee- und Heldenleiste und der
    Infobereich.
  - *Auswahlfenster*: Name, Leben, Kampfwerte, Zustand; bei Truppen Rang mit Erfahrungsbalken, „Wertepunkte“ mit
    „automatisch“ und „Aussehen“, die vier Wertepunkt-Knöpfe nur bei freien Punkten, dann **Haltung** und die Befehle.
    Gebäude mit vielen Einheitentypen (Kaserne) zeigen die Beschwören-Knöpfe in zwei Spalten.
  - *Unten Mitte* das Baumenü (`BuildMenu`) mit Steuerungshinweis; es steht immer zwischen linker Spalte und
    Minikarte und bekommt bei wenig Platz eine Zeile mehr.
  - *Rechts*: Meldungen (`NotificationPanel`) und Protokoll-Knopf oben, Zauberleiste (`SpellBar`) und Minikarte unten.
    Meldungen reichen nie über die Zauberleiste.
- Fenster: `ResearchPanel` (R), `HeroPanel` (G), `TroopPanel` (T), `DiplomacyPanel` (N), `EspionagePanel` (K),
  `KingdomPanel` (L), `MessageLogPanel` (M), `HelpPanel` (F1), `PauseMenu`, `SaveLoadPanel`, `SettingsForm`,
  `GameOverScreen`, `RefugeeDialog`, `TutorialOverlay`.
- **Einstellungen** (`Settings`, `SettingsForm` im Haupt- und Spielmenü, Reiter Grafik · Ton · Steuerung ·
  Oberfläche · Spiel): Vollbild, VSync, Bildrate (`Engine.max_fps`), Abdunklung; Lautstärken (Busse Master, Music,
  SFX, UI); Rand-Scrollen, Kamera-, Rand- und Zoomtempo (`RTSCamera`); UI-Grösse, Lebensbalken
  (`Settings.shows_hp_bar` für `UnitOverlay` und `Building`), Meldungsdauer (`NotificationPanel.lifetime`),
  Minikarten-Grösse (`HUD._apply_minimap_scale`); automatisch speichern, Kompression, Starttempo
  (`GameClock.start_new_game`), Rückfrage vor Kriegserklärung (`SelectionController`, `DiplomacyPanel`),
  Tooltip-Verzögerung (nur beim Start gelesen: `user://project_override.cfg` über
  `application/config/project_settings_override`). Fehlende Schlüssel älterer Dateien behalten ihren Standardwert.

## Speichern und Laden

- **Ablage**: `user://saves/<name>.save` – unter Windows `%APPDATA%\Koenigreiche\saves`, unter Linux
  `~/.local/share/Koenigreiche/saves` (`project.godot`: eigener Benutzerordner „Koenigreiche“; dort liegt auch
  `settings.cfg`). Plätze: beliebig viele mit Namen, `quicksave` (F5/F8), `autosave_1…3` (reihum).
- **Datei**: Zeile 1 `KOENIGREICHE-SAVE 1`, Zeile 2 Kopf als JSON (Name, Datum, Spielzeit, Fraktion, Schwierigkeit,
  Karte, Seed, Versionen, Prüfsumme), danach die Daten als JSON (zstd-komprimiert, abschaltbar). Geschrieben wird nach
  `.tmp`, die alte Datei wird zur Sicherung `.bak`, dann umbenannt; Codieren und Schreiben laufen im Hintergrund
  (`SaveManager`).
- **Inhalt** (`SaveGame`): Die Welt wird aus dem Seed neu erzeugt; gespeichert werden nur ihre Änderungen
  (`WorldData.changed_cells`, Strassen, nachwachsende Vorkommen) und ein Fingerabdruck der frischen Welt. Dazu alle
  Reiche (`Kingdom.to_dict` speichert jedes Feld ausser abgeleiteten und `_`-Feldern automatisch), Gebäude
  (`Building.to_dict`), Einheiten (`Unit.to_dict`, Verweise als uid, laufende Wege), alle Systeme, Uhr, Sitzung und
  das Meldungsprotokoll.
- **Typen** (`SaveCodec`): int/float, Vektoren, Farben, gepackte Arrays, Dictionaries mit Zahlen-Schlüsseln und
  64-Bit-Zahlen bleiben erhalten (`{"#v2": [x, y]}`, `{"#d": [[k, v]]}` …).
- **Schnittstelle jedes Systems**: `to_dict()` (nur einfache Werte, Kopien), `from_dict(d)` (nur Daten, keine
  Signale) und `rebuild_runtime()` (Zwischenspeicher und Wirkungen neu, idempotent). Register `SaveGame.SYSTEMS`
  (fehlende Systeme werden übersprungen; weitere Nodes unter *Systems* mit den drei Methoden werden automatisch
  mitgespeichert), Reihenfolge des Neuaufbaus `SaveGame.REBUILD_ORDER`.
- **Laden**: Kopf prüfen → Welt im Thread erzeugen, Fingerabdruck vergleichen, Änderungen anwenden, Wege berechnen →
  Reiche, Gebäude (ohne Signale), Gebiet, Einheiten, Verweise, Systeme (`from_dict`, dann `rebuild_runtime`), zuletzt
  Leben und Meldungen. Arbeiter suchen ihren Arbeitsschritt neu, Gruppenmärsche gehen einzeln weiter. Laden ist
  idempotent (zweimal laden ergibt denselben Zustand).
- **Regeln für neue Felder**: neues Feld → in `to_dict`/`from_dict` mit Standardwert (Kingdom: automatisch). Feld
  umbenannt oder umgedeutet → `SaveGame.SAVE_VERSION + 1` und ein Schritt in `SaveMigration.migrate`. Ergibt derselbe
  Seed eine andere Welt (Generator oder `worldgen.json` / `biomes.json` geändert) → `WorldGenerator.VERSION + 1`
  (alte Spielstände werden als nicht ladbar angezeigt). Geänderte Spieldaten sonst: nur ein gelber Hinweis in der
  Liste.
- **Schwierigkeit** (`Difficulty`, `data/difficulties.json`): Quelle `"difficulty"` auf KI-Reichen (Ertrag, Stärke,
  Tempo, Wachsamkeit) und den wilden Monstern (Stärke), Startressourcen des Spielers, Angriffslust der KI, Nachwuchs
  der Monsterlager, Streifzüge und Ereignisse. Beim Laden neu gesetzt.

## Exportieren

1. Im Editor **Editor → Export-Vorlagen verwalten** → Vorlagen für die eigene Godot-Version (z. B. 4.4.1)
   herunterladen.
2. `export_presets.cfg` liegt im Projekt (ohne Zugangsdaten): „Windows Desktop“ und „Linux“, je 64 Bit, PCK
   eingebettet, `include_filter="data/*.json"` (die Spieldaten), `exclude_filter="tests/*"`. Der Ordner `docs/` ist
   mit `.gdignore` für Godot unsichtbar und kommt nicht in den Export.
3. Einmal importieren, dann exportieren:
   ```
   godot --headless --import
   godot --headless --export-release "Windows Desktop" build/windows/Koenigreiche.exe
   godot --headless --export-release "Linux" build/linux/koenigreiche.x86_64
   ```
   Ohne Vorlagen lässt sich nur das Datenpaket bauen: `godot --headless --export-pack "Linux" build/koenigreiche.pck`
   (Start: `godot --main-pack build/koenigreiche.pck`). Der Ordner `build/` ist von Git ausgenommen.
4. Spielstände und Einstellungen liegen ausserhalb des Programmordners (siehe
   [Speichern und Laden](#speichern-und-laden)). Eigene Grafiken (`assets/…`, siehe `assets_liste.md`) vor dem Export
   ins Projekt legen und im Editor importieren.

## Konventionen

- **Sprache**: Code-Bezeichner englisch, Kommentare, Texte, Meldungen und Doku deutsch (Schweizer Schreibweise, immer
  ss statt Eszett).
- **Typisierung**: statische Typen (`var x: int`, `:=`), keine Warnungen – `tests/check_scripts.sh` behandelt alle
  GDScript-Warnungen als Fehler.
- **`.uid`-Dateien** (Godot 4.4) gehören zu jedem Skript und werden mit eingecheckt; `check_scripts.sh` erzeugt
  fehlende einmal über den Editor.
- **Einrückung**: Tabs in `.gd`, sonst Leerzeichen (siehe `.editorconfig`), Zeilenenden LF (`.gitattributes`).
- **Neues System**: Node unter *Systems* in `game.tscn`, `setup(game)` in `_setup_world_and_systems` an passender
  Stelle, `to_dict` / `from_dict` / `rebuild_runtime`, Eintrag in `SaveGame.SYSTEMS` und `REBUILD_ORDER`, ein Abschnitt
  im Rauchtest.
- **Commits**: deutsche Commit-Nachrichten, kurz und beschreibend; vor dem Einchecken `tests/check_scripts.sh` und
  `tests/run_smoke.sh 600` laufen lassen ([Testen](testen.md)).
