# Königreiche (Arbeitstitel)

2D-Echtzeit-Strategie- und Aufbauspiel in **Godot 4** (GDScript), Ansicht von oben.
Du bist ein König, wählst die Fraktion GUT oder BÖSE, baust dein Dorf aus,
beschwörst Einheiten, schliesst Bündnisse mit neutralen Völkern und besiegst die Gegenseite.

## Voraussetzungen

- Godot **4.4 oder neuer**, Standard-Version (nicht .NET). Getestet mit 4.4.1 und 4.7.
- Renderer: *Compatibility* (OpenGL), läuft auch auf älteren Grafikkarten.

## Starten

1. Godot öffnen → **Importieren** → `project.godot` in diesem Ordner wählen.
2. **F5** drücken (Projekt starten) → Hauptmenü → *Neues Spiel*.

## Steuerung

| Aktion | Taste / Maus |
|---|---|
| Kamera verschieben | WASD, Pfeiltasten, Maus an den Bildschirmrand, mittlere Maustaste ziehen |
| Zoomen | Mausrad (zum Mauszeiger hin), Q / E, Bild↑ / Bild↓ |
| Zur Burg springen | H, Pos1 |
| Minikarte | Linksklick oder Ziehen springt zur Stelle |
| Pause an/aus | Leertaste, P |
| Spieltempo | + / − (oder die Buttons oben rechts: Pause, 0.5x, 1x, 2x, 3x) |
| Gebäude bauen | Baumenü unten anklicken → Vorschau (grün = möglich, rot = Grund wird angezeigt) → Linksklick |
| Mehrere gleiche Gebäude | Umschalttaste beim Klicken gedrückt halten |
| Strassen | „Strasse“ im Baumenü → Maustaste gedrückt halten und ziehen (bleibt aktiv bis Rechtsklick/Esc) |
| Abreissen | X oder „Abreissen“ im Baumenü: Strassen anklicken/überziehen, Gebäude anklicken → Auswahlfenster |
| Bauen abbrechen | Rechtsklick oder Esc |
| Auswählen | Linksklick auf Einheit oder Gebäude (Klick ins Leere / Esc hebt auf), Umschalttaste = hinzufügen |
| Rahmenauswahl | Linke Maustaste gedrückt ziehen – wählt eigene Truppen (Bewohner nur, wenn keine Truppen im Rahmen sind) |
| Alle gleichen Einheiten | Doppelklick auf eine Einheit (alle dieses Typs im Bild) |
| Bewegen / Angreifen | Rechtsklick ins Gelände bzw. auf einen Feind (Monster, Höhle) |
| Angreifend vorrücken | Strg + Rechtsklick (kämpft unterwegs) oder Button „Angriff-Vorrücken“ |
| Armee speichern / wählen | Strg + 1…9 speichern, Umschalt + 1…9 hinzufügen, 1…9 auswählen, zweimal drücken = Kamera hin |
| Formation Block / Linie | F oder Button im Auswahlfenster |
| Sammelpunkt | Burg/Kaserne/Krankenstation auswählen → Rechtsklick in die Welt |
| Einheiten beschwören | Burg (Späher), Kaserne (Kämpfer, Schützen, Elite), Krankenstation (Heiler) auswählen → Buttons |
| Arbeitsverteilung ein/aus | J |
| Spielmenü | Esc (wenn nichts gebaut/ausgewählt wird) |
| Debug-Anzeige (FPS, Zoom, Chunks) | F3 – dabei gibt F9 +100 von jeder Ressource, F10 fügt dem König 150 Schaden zu (zum Testen) |

Alle Tasten lassen sich im Editor unter *Projekt → Projekteinstellungen → Eingabe-Zuordnung* ändern.

## Ordnerstruktur

```
project.godot            Projekteinstellungen, Autoloads, Tastenbelegung
assets_liste.md          Liste aller Grafiken (für die Bild-KI)
data/                    Spieldaten (JSON) – ohne Code änderbar
  game_config.json         Kartengrössen, Kamera, Zeit/Tempo
  worldgen.json            Weltgenerierung (Rauschen, Grenzgebirge, Startplatz)
  biomes.json              Biome: Farben, Regeln, Bewegung, Verteidigung, Grafiken
  factions.json            Fraktionen und Völker
  difficulties.json        Schwierigkeitsgrade
  resources.json           Ressourcen und Rohstoffvorkommen (Bäume, Steine, Erz, Beeren, Manaquellen)
  buildings.json           Gebäude: Kosten, Bauzeit, Wohnraum, Gebiet, Annahme, Produktion
  jobs.json                Berufe der Bewohner (Holzfäller, Bauer, Bauarbeiter ...)
  units.json               Einheitentypen: Bewohner, König, Späher, Kämpfer, Schützen, Elite, Heiler, Monster
  combat.json              Kampfregeln (Gebietsbonus, Streuung, Erholung, Leine), Formationen, Monsterlager
  economy.json             Startausstattung, Wachstum, Hunger, Strassen, Rückerstattung
scenes/                  Szenen (.tscn)
  main_menu.tscn           Hauptmenü
  game.tscn                Spielszene
  ui/                      HUD, Spielmenü, Ladebildschirm
scripts/
  autoload/                Globale Dienste: DataDB, Settings, GameSession, GameClock, Assets, Notify
  world/                   Kartendaten, Generator, Chunk-Darstellung, Tilesets, Gebiet, Wegfindung
  economy/                 Reich (Kingdom), Gebäude, BuildingSystem, EconomySystem
  units/                   Einheiten, UnitSystem (Bewegung), WorkSystem (Berufe), CombatSystem (Kampf),
                           CommandSystem (Befehle, Formationen, Armeen), SummonSystem, MonsterSystem
  camera/                  Strategie-Kamera
  view/                    Darstellung über der Welt: Lebensbalken/Auswahlringe, Kampfeffekte
  ui/                      HUD-Panels, Bauvorschau, Auswahl und Befehle, Spielende
  util/                    Hilfen (Grafik laden / Platzhalter erzeugen und zeichnen)
assets/
  sprites/                 terrain/, units/, buildings/, heroes/, resources/, effects/
  ui/                      Theme (theme.tres), Icons, Menü-Hintergrund
  audio/                   music/, sfx/
```

## Aufbau (Architektur)

- **DataDB** lädt alle JSON-Dateien aus `data/`. Kein anderes System liest JSON direkt.
- **GameClock** ist die einzige Zeitquelle der Spielwelt: Pause, Tempo, Tag und Uhrzeit.
  Spielobjekte nutzen `GameClock.frame_delta` statt `delta`; seltene Logik
  (Wirtschaft, KI) hängt am Signal `sim_tick` (10 Schritte pro Spielsekunde).
  Kamera und UI laufen immer in Echtzeit.
- **GameSession** hält die Partie-Parameter (Fraktion, Schwierigkeit, Karte, Seed).
- **Karte**: `WorldData` (reine Daten) ← `WorldGenerator` (läuft im Hintergrund-Thread)
  → `WorldMap` (Darstellung). Es werden nur die Chunks (32×32 Kacheln) im Sichtfeld
  gebaut; weit herausgezoomt wird nur ein Übersichtsbild gezeichnet (1 Pixel pro Kachel).
- Gleicher **Seed** = gleiche Welt.
- **Reiche** (`Kingdom`) halten Ressourcen, Gebäude und Einheiten. Alle Systeme arbeiten für jedes
  Reich gleich – der Spieler ist nur ein Reich mit `controller = "player"`. Ab Phase 7 nutzen die
  KI-Reiche dieselben Systeme (`Game.create_kingdom`, `Game.found_settlement`).
- **Systeme** (in `game.tscn` unter *Systems*): `BuildingSystem` (Bauen, Strassen, Produktion),
  `UnitSystem` (Einheiten bewegen, Wegberechnung mit Zeitbudget, lange Wege in Abschnitten),
  `WorkSystem` (Berufe, Sammeln, Bauen, Abliefern), `EconomySystem` (Nahrung, Hunger, Wachstum),
  `CombatSystem` (Zielsuche, Schaden, Heilung, Tod; Schaden immer über `apply_damage`),
  `CommandSystem` (Befehle mit Bedeutungstabelle `COMMANDS`, Formationen, Gruppenmarsch hinter einem
  Anführer, Armeen 1–9 je Reich), `SummonSystem` (Beschwörung mit Warteschlange und Sammelpunkt),
  `MonsterSystem` (Monsterlager; Lager ohne fremde Einheiten in der Nähe ruhen und kosten nichts).
- **Einheiten**: Bewohner, Truppen, König und Monster sind alle `Unit`. Ihre Werte kommen aus
  `units.json` und werden mit Modifikatoren des Reichs (Forschung, Schwierigkeit) und Wirkungen
  (Zauber, Helden) in `Unit.refresh_stats()` berechnet. Wer arbeitet (Befehl leer), wird nur vom
  WorkSystem gesteuert; ein Befehl unterbricht die Arbeit, „Zur Arbeit“ setzt sie fort.
- **Beziehungen**: `Game.set_relation(a, b, "war" | "peace" | "alliance")`; Kampf nur bei Krieg.
  Die wilden Monster sind ein eigenes Reich, mit allen im Krieg. `Game.can_see` ist die Stelle für
  Sichtbarkeit (ab Phase 7: Entdeckung, Spione).
- **Spielende**: `Game.defeat_kingdom` – stirbt der König des Spielers, ist das Spiel verloren.
- **Trennung Simulation/Darstellung**: Die Systeme kennen weder Karte noch HUD. Die Darstellung hört
  auf Signale (`WorldData.cell_changed`, `road_changed`, `TerritorySystem.changed` …). Das ist die
  Grundlage für Speichern/Laden in Phase 10.
- **Wegfindung** (`NavGrid`, A* über die ganze Karte): Gelände kostet unterschiedlich viel, Strassen
  sind schneller, Gebäude blockieren.
- **Gebiet**: Jedes fertige Gebäude beansprucht einen Kreis; bei Überschneidung gewinnt das ältere.
  Gebaut werden darf nur im eigenen Gebiet.

## Daten anpassen

Alle Dateien in `data/` enthalten `_hinweis`-Felder mit Erklärungen. Beispiele:

- Mehr Berge: in `biomes.json` bei *Berge* `height_min` senken (0.84 → 0.78).
- Längere Tage: in `game_config.json` `time.seconds_per_day` erhöhen.
- Andere Tempostufen: `time.speed_steps`.
- Kartengrössen: `map.sizes`.
- Billigere Häuser: in `buildings.json` bei *house* `cost` ändern.
- Mehr Nahrung pro Bauer: `buildings.json` → *farm* → `production.food`.
- Schnellere Bewohner: `units.json` → *villager* → `speed`.
- Andere Startausstattung: `economy.json` → `start`.
- Stärkere Ritter: `units.json` → *elite_good* → `attack`, `hp`, `armor`.
- Billigere Truppen: `units.json` → `cost` und `summon_time`.
- Weniger oder mehr Monsterlager: `combat.json` → `camps.per_1000_tiles`, Übungslager `camps.near_start`.
- Stärkerer Heimvorteil: `combat.json` → `territory_bonus`.

## Phase 2 testen

1. Neues Spiel starten. Die Burg steht im eigenen Gebiet (farbige Grenze), 5 Bewohner laufen los:
   2 Holzfäller, 1 Sammler, 2 Bauarbeiter (siehe *Arbeitsverteilung* links, Taste J).
2. Oben steigen Holz und Nahrung langsam an (Tooltip über der Zahl zeigt den Ertrag pro Minute).
3. **Wohnhaus** im Baumenü wählen, im Gebiet platzieren → Baustelle, die Bauarbeiter bauen sie.
   Danach steigt „Bewohner P/H“ um 4 Wohnplätze, das Gebiet wächst etwas.
4. Alle ~45 Sekunden kommt ein neuer Bewohner (wenn Wohnraum frei ist und ≥ 30 Nahrung da ist).
   Er ist *unbeschäftigt* – in der Arbeitsverteilung mit „+“ einem Beruf zuweisen.
5. **Strasse** wählen und mit gedrückter Maustaste ziehen → Bauarbeiter legen sie an; Bewohner laufen
   darauf schneller und nutzen sie für ihre Wege.
6. **Holzfällerhütte** nahe an Bäumen bauen → Holzfäller liefern dort ab (kürzere Wege, +25 %).
   Auswahl der Hütte zeigt „Liefern hier an: N“.
7. **Bauernhof** bauen, in der Arbeitsverteilung Bauern zuweisen → dauerhaft Nahrung.
8. **Manabrunnen** auf einer Manaquelle (violett leuchtend) bauen, Manawirker zuweisen → Mana steigt.
9. Alle Sammler auf „−“ setzen → nach einigen Minuten *Hungersnot* (Meldung, Nahrung rot,
   Arbeit halb so schnell). Sammler wieder einsetzen → die Hungersnot endet.
10. Mit X oder „Abreissen“ Strassen entfernen; ein Gebäude auswählen → „Abreissen“ (zweimal klicken).

## Phase 3 testen

1. Neues Spiel. Vor der Burg steht der **König** (Krone). Er verteidigt die Burg, verlässt aber nie
   das eigene Gebiet. Auf der Minikarte sind **Monsterlager** orange markiert; zwei kleine Übungslager
   liegen 30–45 Kacheln vom Start entfernt.
2. **Burg anklicken** → im Auswahlfenster „Späher“ beschwören (Kosten im Tooltip). Nach 8 Sekunden
   erscheint er vor der Burg. Mehrfach klicken = Warteschlange (max. 5); Klick auf ein Symbol in der
   Warteschlange bricht ab (Kosten zurück).
3. **Kaserne** bauen (braucht Mana: Manabrunnen + Manawirker). Fertig auswählen → Schwertkämpfer,
   Bogenschützen, Ritter beschwören. Mit Rechtsklick in die Welt einen **Sammelpunkt** setzen.
4. Truppen mit gedrückter linker Maustaste **einrahmen** (Bewohner werden dabei nicht mitgenommen).
   **Rechtsklick** ins Gelände: sie marschieren in Formation (F wechselt Block/Linie).
5. **Strg+1** speichert die Auswahl als Armee 1 (Leiste über dem Auswahlfenster), **1** wählt sie,
   zweimal **1** springt mit der Kamera hin.
6. Armee auswählen, **Rechtsklick auf eine Monsterhöhle** oder ein Monster → Angriff. Bogenschützen
   schiessen Pfeile, Treffer blitzen auf, Gefallene verblassen. Eine zerstörte Höhle gibt Beute und
   **Kampfpunkte** (Tooltip bei „Truppen“ oben). Bewohner sammeln nicht in der Nähe von Höhlen.
7. Verletzte erholen sich nach 5 Sekunden ohne Kampf; **Krankenstation** (heilt in der Nähe) und
   **Heiler** heilen schneller.
8. Wird ein Bewohner angegriffen, flieht er zur Burg und arbeitet danach weiter. Ein Späher, der als
   Holzfäller arbeitet, wehrt sich und arbeitet danach weiter. Beschworene Einheiten brauchen zum
   Arbeiten Wohnraum.
9. Spielende testen: F3 (Debug) und dann mehrmals F10 → der König verliert Leben, flieht verletzt in
   die Burg; stirbt er, erscheint „Der König ist gefallen“ mit „Neu starten (gleiche Karte)“.

## Grafiken austauschen

Alle Grafiken sind zunächst automatisch erzeugte Platzhalter. Legt man eine PNG-Datei
mit dem in **`assets_liste.md`** genannten Namen in den passenden Ordner, wird sie
beim nächsten Start automatisch verwendet – ohne Code-Änderung.

## Entwicklungsstand

- [x] Phase 1 – Projekt-Setup, Kamera, prozedurale Karte mit Biomen, Spieltempo und Pause
- [x] Phase 2 – Dorf: Gebäude, Ressourcen, Bewohner, Arbeitsverteilung
- [x] Phase 3 – Einheiten: Beschwören, Auswahl, Bewegung, Kampf, Armeen
- [ ] Phase 4 – Forschung, Mana und Magie
- [ ] Phase 5 – Helden
- [ ] Phase 6 – Neutrale Dörfer, Diplomatie, Handel, Ruf, Boten
- [ ] Phase 7 – Gegnerische Königreiche mit KI, Entdeckung, Spionage
- [ ] Phase 8 – Zufriedenheit, Verrat, Flüchtlinge, Ereignisse, Monster, Tag/Nacht
- [ ] Phase 9 – Belagerungen und Handelswege
- [ ] Phase 10 – Speichern/Laden, Schwierigkeitsgrade, UI-Feinschliff, Balancing
