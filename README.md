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
| Zum Startplatz springen | H, Pos1 |
| Minikarte | Linksklick oder Ziehen springt zur Stelle |
| Pause an/aus | Leertaste, P |
| Spieltempo | + / − (oder die Buttons oben rechts: Pause, 0.5x, 1x, 2x, 3x) |
| Spielmenü | Esc |
| Debug-Anzeige (FPS, Zoom, Chunks) | F3 |

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
scenes/                  Szenen (.tscn)
  main_menu.tscn           Hauptmenü
  game.tscn                Spielszene
  ui/                      HUD, Spielmenü, Ladebildschirm
scripts/
  autoload/                Globale Dienste: DataDB, Settings, GameSession, GameClock
  world/                   Kartendaten, Generator, Chunk-Darstellung, Tileset
  camera/                  Strategie-Kamera
  ui/                      Oberflächen-Skripte
  util/                    Hilfen (Grafik laden / Platzhalter erzeugen)
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
- Gleicher **Seed** = gleiche Welt. Ein Spielstand braucht daher nur Seed + Änderungen.

## Daten anpassen

Alle Dateien in `data/` enthalten `_hinweis`-Felder mit Erklärungen. Beispiele:

- Mehr Berge: in `biomes.json` bei *Berge* `height_min` senken (0.84 → 0.78).
- Längere Tage: in `game_config.json` `time.seconds_per_day` erhöhen.
- Andere Tempostufen: `time.speed_steps`.
- Kartengrössen: `map.sizes`.

## Grafiken austauschen

Alle Grafiken sind zunächst automatisch erzeugte Platzhalter. Legt man eine PNG-Datei
mit dem in **`assets_liste.md`** genannten Namen in den passenden Ordner, wird sie
beim nächsten Start automatisch verwendet – ohne Code-Änderung.

## Entwicklungsstand

- [x] Phase 1 – Projekt-Setup, Kamera, prozedurale Karte mit Biomen, Spieltempo und Pause
- [ ] Phase 2 – Dorf: Gebäude, Ressourcen, Bewohner, Arbeitsverteilung
- [ ] Phase 3 – Einheiten: Beschwören, Auswahl, Bewegung, Kampf, Armeen
- [ ] Phase 4 – Forschung, Mana und Magie
- [ ] Phase 5 – Helden
- [ ] Phase 6 – Neutrale Dörfer, Diplomatie, Handel, Ruf, Boten
- [ ] Phase 7 – Gegnerische Königreiche mit KI, Entdeckung, Spionage
- [ ] Phase 8 – Zufriedenheit, Verrat, Flüchtlinge, Ereignisse, Monster, Tag/Nacht
- [ ] Phase 9 – Belagerungen und Handelswege
- [ ] Phase 10 – Speichern/Laden, Schwierigkeitsgrade, UI-Feinschliff, Balancing
