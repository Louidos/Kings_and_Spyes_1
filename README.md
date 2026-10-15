# Königreiche (Arbeitstitel)

2D-Echtzeit-Strategie- und Aufbauspiel in **Godot 4** (GDScript), Ansicht von oben.
Du bist ein König, wählst die Fraktion GUT oder BÖSE, baust dein Dorf aus,
beschwörst Einheiten, schliesst Bündnisse mit neutralen Völkern und besiegst die Gegenseite.

## Voraussetzungen

- Godot **4.4 oder neuer**, Standard-Version (nicht .NET). Getestet mit 4.4.1 und 4.7.
- Renderer: *Compatibility* (OpenGL), läuft auch auf älteren Grafikkarten.

## Starten

1. Godot öffnen → **Importieren** → `project.godot` in diesem Ordner wählen.
2. **F5** drücken (Projekt starten) → Hauptmenü → *Neues Spiel* (oder *Tutorial*, *Fortsetzen* / *Laden*).
   Zum Kennenlernen: **Tutorial** (siehe unten).
   F5 startet nur im Editor das Projekt – im laufenden Spiel ist F5 *Schnellspeichern*.

## Steuerung

| Aktion | Taste / Maus |
|---|---|
| Kamera verschieben | WASD, Pfeiltasten, Maus an den Bildschirmrand, mittlere Maustaste ziehen |
| Zoomen | Mausrad (zum Mauszeiger hin), Q / E, Bild↑ / Bild↓ |
| Zur Burg springen | H, Pos1 |
| Minikarte | Linksklick oder Ziehen springt zur Stelle |
| Pause an/aus | Leertaste, P |
| Spieltempo | + / − (oder die Buttons oben rechts: Pause-Symbol ❚❚, 0.5x, 1x, 2x, 3x) |
| Gebäude bauen | Baumenü unten anklicken → Vorschau (grün = möglich, rot = Grund wird angezeigt) → Linksklick |
| Mehrere gleiche Gebäude | Umschalttaste beim Klicken gedrückt halten |
| Baumenü-Reiter | Dorf / Militär & Wissen / Verteidigung (über den Knöpfen des Baumenüs) |
| Strassen | „Strasse“ im Baumenü → Maustaste gedrückt halten und ziehen (bleibt aktiv bis Rechtsklick/Esc) |
| Mauer | Baumenü → Verteidigung → „Mauer“: wie Strassen ziehen (über eigenen Strassen entstehen Tore) |
| Tor | Baumenü → Verteidigung → „Tor“ auf ein eigenes Mauerstück oder eine eigene Strasse setzen; Tor auswählen → „Verriegeln“ / „Öffnen“ |
| Abreissen | X oder „Abreissen“ im Baumenü: Strassen und eigene Mauern anklicken/überziehen, Gebäude anklicken → Auswahlfenster |
| Bauen abbrechen | Rechtsklick oder Esc |
| Auswählen | Linksklick auf Einheit oder Gebäude (Klick ins Leere / Esc hebt auf), Umschalttaste = hinzufügen |
| Rahmenauswahl | Linke Maustaste gedrückt ziehen – wählt eigene Truppen (Bewohner nur, wenn keine Truppen im Rahmen sind) |
| Alle gleichen Einheiten | Doppelklick auf eine Einheit (alle dieses Typs im Bild) |
| Bewegen / Angreifen | Rechtsklick ins Gelände bzw. auf einen Feind (Monster, Höhle) |
| Angreifend vorrücken | Strg + Rechtsklick (kämpft unterwegs) oder Button „Angriff-Vorrücken“, dann Klick ins Gelände (Esc bricht ab) |
| Armee speichern / wählen | Strg + 1…9 speichern, Umschalt + 1…9 hinzufügen, 1…9 auswählen, zweimal drücken = Kamera hin |
| Formation Block / Linie / Keil / Kreis | F (wechselt reihum) oder Button im Auswahlfenster bzw. im Truppenfenster |
| Truppenfenster | T oder Button „Truppen · 24“ oben (Strich = Leben aller Truppen, roter Punkt = Truppen im Kampf): alle Krieger nach Typ (Anzahl, Leben gesamt/Ø, untätig / im Kampf / unterwegs / bei der Arbeit), Helden, Armeen 1–9 (Anzahl, Stärke, Ort, Befehl); „Wählen“ / „Hin“ / „✕“ (Armee auflösen); rechts Auswahl (alle Krieger, Untätige, Verwundete, Auswahl → Armee 1–9) und Befehle an die Gruppe: Sammeln an der Burg, Rückzug zur Burg, Angreifend vorrücken / Bewegen / Patrouille (danach Ziel anklicken, Esc bricht ab), Halten, Formation, Haltung. T oder Esc schliesst |
| Alle Krieger auswählen | Strg + A (alle eigenen Truppen und Helden, ohne Bewohner und König) |
| Haltung | im Truppenfenster: **aggressiv** (verfolgt weit, auch vom Posten weg), **verteidigend** (Standard: kehrt nach kurzer Verfolgung auf den Posten zurück), **passiv** (greift nie von selbst an und wehrt sich nicht – nur auf Angriffsbefehl) |
| Sammelpunkt | Burg/Kaserne/Krankenstation auswählen → Rechtsklick in die Welt |
| Einheiten beschwören | Burg (Späher), Kaserne (Kämpfer, Schützen, Elite – nach Forschung), Krankenstation (Heiler) auswählen → Buttons |
| Forschung | R oder Button „Forschung“ oben: Forschungsbaum und Reiter „Kampfpunkte“ (Esc oder R schliesst) |
| Zaubern | Zauber in der Zauberleiste (unten rechts) anklicken → Kreis an die Stelle führen → Linksklick; Rechtsklick/Esc bricht ab |
| Heldenfenster | G oder Button „Helden“ oben: eigene Helden (Stufenwahl, Ausbildung, Wiederbelebung) und Anwerben |
| Helden auswählen | Heldenleiste unten links über dem Infobereich (Klick wählt, Doppelklick springt hin, Rechtsklick öffnet das Heldenfenster; gefallener Held: Klick belebt wieder, sobald es geht) – Helden sind auch Teil von Armeen |
| Heldenfähigkeiten | C / V / B (oder die Knöpfe im Auswahlfenster) – auch wenn die ganze Armee ausgewählt ist; Tab wechselt den Helden; Rechtsklick auf einen Knopf schaltet „selbst auslösen“ um (goldener Rahmen). Fähigkeiten mit Ziel: Feind bzw. Stelle anklicken, Rechtsklick/Esc bricht ab |
| Diplomatie | N oder Button „Diplomatie“ oben: Reiter „Dörfer“ (alle neutralen Dörfer mit Ruf, Vertrag, Entfernung und Stärke; Geschenke, Verträge, Handel, Aufnahme, Drohung, Krieg/Frieden), „Reiche“ (feindliche Königreiche: Volk, Kriege, geschätzte Stärke – nur mit Kundschaft) und „Handelswege“. Esc oder N schliesst. Ein Dorfgebäude, eine Miliz oder ein Bote auswählen → Knopf „Diplomatie (N)“ im Auswahlfenster |
| Spionage | K oder Button „Spionage · 42“ oben (Zahl und Strich = dein Entdeckungswert, roter Punkt = fremder Spion entdeckt oder ein Reich ist aufmerksamer geworden): Reiter „Übersicht“ (Ursachen, Reichstarnung), „Reiche & Dörfer“ (Kundschaft), „Spione“ (beschwören, Aufträge). Esc oder K schliesst |
| Spion: Auftrag | Spion auswählen → „Auftrag (K)“ im Auswahlfenster, oder Spionagefenster, Reiter „Spione“: Auftrag, Ziel (und Zweitziel) wählen → „Auftrag erteilen“; „Zurückrufen“ holt ihn heim |
| Handelswege | N → Reiter „Handelswege“ oder L → Reiter „Handel“: Karawanen, Ladung, Lieferungen, Verluste, „Weg freigeben“, gesichtete fremde Wege, Versorgung |
| Belagerungswaffen | Forschung „Belagerungskunst“ → Belagerungswerkstatt (Baumenü → Verteidigung) auswählen → Rammbock / Katapult (BÖSE: Sturmbock / Schädelschleuder) beschwören → Rechtsklick auf ein feindliches Gebäude, Tor oder Mauerstück |
| Krieg gegen ein Dorf | mit eigenen Truppen zweimal Rechtsklick (innerhalb von 3 s) auf eine Einheit oder ein Gebäude des Dorfs – der erste Klick warnt nur – oder „Krieg erklären“ im Diplomatiefenster |
| Reichsübersicht | L oder Button „Reich“ oben (Zufriedenheit, Ereignisse, Volk und Tageszeit, Handel; Esc oder L schliesst). Gesicht in der Ressourcenleiste und Sonne/Mond neben dem Datum öffnen sie ebenfalls |
| Flüchtlinge aufnehmen | Meldung, Ereignisleiste (oben Mitte) oder einen Flüchtling anklicken → „Aufnehmen“ / „Abweisen“ |
| Überläufer aufhalten | dem Überläufer einen Befehl geben (z. B. Rechtsklick ins Gelände oder „Halt“) |
| Meldungen | Klick springt zur Stelle; Meldungen zur Stufenwahl oder Wiederbelebung öffnen das Heldenfenster |
| Arbeitsverteilung ein/aus | J |
| Hilfe (alle Tasten, Spielablauf, Schwierigkeit) | F1 (auch im Spielmenü: „Hilfe (F1)“) |
| Tutorial | Hauptmenü → „Tutorial“ oder beim neuen Spiel „Tipps/Tutorial anzeigen“; Fenster rechts: „Weiter“, „Überspringen“, „Beenden“ (zweimal klicken), „–“ klappt ein, „Zeigen“ springt zum Pfeil; Esc → „Tutorial fortsetzen“ / „Tutorial starten“ / „Tutorial von vorn“ |
| Meldungsprotokoll | M oder Knopf „Protokoll (M)“ über den Meldungen: alle Meldungen der Partie, Filter, Klick springt zur Stelle |
| Schnellspeichern / Schnellladen | F5 / F8 (vorige Schnellspeicherung bleibt als Sicherung) |
| Spielmenü | Esc (wenn kein Fenster offen ist und nichts gebaut/ausgewählt wird): Fortsetzen, **Speichern**, **Laden**, **Einstellungen**, Hilfe, Hauptmenü, Beenden |
| Grösse der Oberfläche | Esc → Einstellungen → „Grösse der Oberfläche“ (75–150 %; wirkt sofort auf HUD, Fenster, Menüs) |
| Debug-Anzeige (FPS, Zoom, Chunks) | F3 – dabei gibt F9 +100 von jeder Ressource, F10 fügt dem König 150 Schaden zu, F11 setzt 3 Wölfe an die Maus, Umschalt+F11 einen Übungsgolem, Strg+F11 einen feindlichen Rammbock (marschiert zur Burg), F12 gibt dem ausgewählten Helden eine Stufe (zum Testen); im Spionagefenster erscheinen Debug-Knöpfe (Aufmerksamkeit, Kundschaft, KI-Angriff, KI-Reich besiegen, Rivalen-Krieg), in der Reichsübersicht (L) Knöpfe für Ereignisse, Zufriedenheit und Tageszeit |

Alle Tasten lassen sich im Editor unter *Projekt → Projekteinstellungen → Eingabe-Zuordnung* ändern.

## Ordnerstruktur

```
project.godot            Projekteinstellungen, Autoloads, Tastenbelegung
assets_liste.md          Liste aller Grafiken (für die Bild-KI)
data/                    Spieldaten (JSON) – ohne Code änderbar
  game_config.json         Kartengrössen, Kamera, Zeit/Tempo
  worldgen.json            Weltgenerierung (Rauschen, Grenzgebirge, Startplatz)
  biomes.json              Biome: Farben, Regeln, Bewegung, Verteidigung, Grafiken
  factions.json            Fraktionen
  peoples.json             Völker (alle 22): Stärken/Schwächen, Gelände- und Tag/Nacht-Boni, Dorfdaten
  diplomacy.json           Ruf, Geschenke, Verträge, Handel, Aufnahme, Drohung, Dörfer, Boten
  difficulties.json        Schwierigkeitsgrade (KI, Monster, Startvorrat, Beschreibung)
  help.json                Hilfefenster F1 (Tasten, Spielablauf)
  tutorial.json            Tutorial: Partie (Seed, Karte, Schwierigkeit), Schutz, Schritte mit Text, Ziel, Bedingung
  ai.json                  Gegner-KI: Namen, Persönlichkeiten, Schwierigkeit (Reiche, erste Welle, Faktoren),
                           Bauliste, Berufe, Forschung, Armee, Wellen, Lager, Rivalität, Niederlage
  espionage.json           Entdeckung, Aggression, Reichstarnung, Aufmerksamkeit, Kundschaft, Berichte, Spione
  resources.json           Ressourcen und Rohstoffvorkommen (Bäume, Steine, Erz, Beeren, Manaquellen)
  buildings.json           Gebäude: Kosten, Bauzeit, Wohnraum, Gebiet, Annahme, Produktion
  jobs.json                Berufe der Bewohner (Holzfäller, Bauer, Bauarbeiter ...)
  units.json               Einheitentypen: Bewohner, König, Späher, Kämpfer, Schützen, Elite, Heiler, Monster,
                           Dorfmilizen, Volkskrieger, Bote
  combat.json              Kampfregeln (Gebietsbonus, Streuung, Erholung, Leine), Formationen, Monsterlager
  economy.json             Startausstattung, Wachstum, Hunger, Strassen, Rückerstattung
scenes/                  Szenen (.tscn)
  main_menu.tscn           Hauptmenü
  game.tscn                Spielszene
  ui/                      HUD, Spielmenü, Ladebildschirm
scripts/
  autoload/                Globale Dienste: DataDB, Settings, GameSession, GameClock, Assets, Notify, SaveManager
  save/                    Spielstände: SaveGame (Inhalt, Laden), SaveCodec (Typen in JSON), SaveMigration
  kingdoms/                Schwierigkeit (Difficulty), Sieg und Niederlage (VictorySystem)
  tutorial/                TutorialSystem (Schritte, Bedingungen, Schutz, Spielstand)
  world/                   Kartendaten, Generator, Chunk-Darstellung, Tilesets, Gebiet, Wegfindung
  economy/                 Reich (Kingdom), Gebäude, BuildingSystem, EconomySystem
  units/                   Einheiten, UnitSystem (Bewegung), WorkSystem (Berufe), CombatSystem (Kampf),
                           CommandSystem (Befehle, Formationen, Armeen), SummonSystem, MonsterSystem
  diplomacy/               VillageSystem (Dörfer), DiplomacySystem (Ruf, Verträge, Handel), MessengerSystem (Boten)
  ai/                      AISystem (KI-Reiche gründen, Takt), AIBrain (Gehirn je Reich) mit den Modulen AIEconomy,
                           AIMilitary, AIDiplomacy; AIRivalry (Spannung zwischen KI-Reichen)
  espionage/               EspionageSystem (Entdeckung, Aufmerksamkeit, Kundschaft, Tarnung), SpySystem (Spione)
  kingdoms/                VictorySystem (Niederlage der KI-Reiche, Ruinen, Sieg)
  camera/                  Strategie-Kamera
  view/                    Darstellung über der Welt: Lebensbalken/Auswahlringe, Kampfeffekte
  ui/                      HUD-Panels, Bauvorschau, Auswahl und Befehle, Spielende, Speichern/Laden,
                           Einstellungen, Hilfe (F1), Meldungsprotokoll (M), Truppenfenster (T, TroopPanel)
  util/                    Hilfen (Grafik laden / Platzhalter erzeugen und zeichnen)
assets/
  sprites/                 terrain/, units/, buildings/, heroes/, resources/, effects/
  ui/                      Theme (theme.tres), Icons, Menü-Hintergrund
  audio/                   music/, sfx/
tests/                   Prüfungen ohne Fenster
  check_scripts.sh         alle Skripte auf Fehler und Warnungen prüfen
  run_smoke.sh             Rauchtest beider Fraktionen (smoke_test.tscn + smoke_phase6…10.gd; tutorial=1: smoke_tutorial.gd)
  run_balance.sh           Balancing-Läufe (balance_phase10.gd), Ausgabe nach build/balance
export_presets.cfg       Export-Vorlagen Windows/Linux (ohne Zugangsdaten)
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
  `CommandSystem` (Befehle mit Bedeutungstabelle `COMMANDS`, Formationen Block/Linie/Keil/Kreis, Gruppenmarsch
  hinter einem Anführer, Armeen 1–9 je Reich; Truppenfenster: `order_gather`, `order_retreat` → Befehl `rest`,
  `order_patrol`, `order_reform`, `set_stance` mit Haltung `Unit.stance`, die das `CombatSystem` über
  `stance_allows_engage`/`leash_for` fragt – dieselben Funktionen kann die KI nutzen), `SummonSystem` (Beschwörung mit Warteschlange und Sammelpunkt),
  `MonsterSystem` (Monsterlager; Lager ohne fremde Einheiten in der Nähe ruhen und kosten nichts),
  `ResearchSystem` (Forschung mit Warteschlange je Reich, Kampfpunkt-Verbesserungen),
  `MagicSystem` (Zauber des Königs: Wirkungen, Wettergebiete, Tarnung, Beschwörung),
  `HeroSystem` (Helden: Anwerben über die Beschwörungs-Warteschlange der Heldenhalle, Erfahrung, Stufen mit
  Wahl, Fähigkeiten, Führung, Tod und Wiederbelebung).
- **Helden-Oberfläche** (`scripts/ui/`): `HeroPanel` (Heldenfenster G, Reiter „Meine Helden“ und „Anwerben“),
  `HeroBar` (Heldenleiste), `HeroSelectionBox` (Helden-Abschnitt im Auswahlfenster: Fähigkeiten, Burg:
  Wiederbeleben, Halle: Ausbildung), `AbilityButton` (Fähigkeitsknopf auf Basis des Zauberknopfs),
  `HeroPortrait`, `HeroUI` (gemeinsame Texte). Fähigkeiten mit Ziel nutzen den Zielmodus von
  `SpellTargeting` (`start_ability`), der aktive Held einer Auswahl steht im `SelectionController`
  (`get_focus_hero`, `cycle_hero`). Alles ruft nur die Schnittstelle des `HeroSystem` auf.
- **Helden** sind Einheiten mit Rolle `hero`; ihr Zustand (Stufe, Erfahrung, Ränge, Talente, Tod) liegt als
  einfacher Eintrag in `Kingdom.heroes`, alles Abgeleitete (Werte, Auren, Mana-Zuschläge) baut
  `HeroSystem.rebuild_runtime()` neu auf. Ein wiederbelebter Held bekommt dieselbe Einheitennummer und bleibt
  so in seinen Armeen. Fähigkeitsschaden geht über `CombatSystem.ability_damage` (Rüstung zur Hälfte).
- **Neutrale Dörfer** (`scripts/diplomacy/`): Jedes Dorf ist ein eigenes `Kingdom` (`controller = "neutral"`,
  Feld `people_id`). Die Weltgenerierung legt Plätze vom Typ `"village"` (Volk, Grösse) und – für Phase 7 –
  `"kingdom"` an (`WorldData.get_sites`). Drei Systeme:
  - `VillageSystem`: gründet die Dörfer (Dorfzentrum, Hütten, Milizen auf Wachposten), vereinfachte
    Dorfwirtschaft (Produktion ins Dorflager, Tribut, Milizen nachfüllen), Alarm, Bündnishilfe,
    Eroberung (`try_capture`: Dorfzentren werden bei 0 Leben erobert statt zerstört) und
    `transfer_settlement` (Aufnahme/Eroberung: Gebäude über `BuildingSystem.transfer_building`,
    Milizen über `UnitSystem.transfer_unit`, Gebiet wechselt mit).
  - `DiplomacySystem`: Ruf je Dorf und Reich (−100 … +100, Stufen, Verfall zum Grundwert, Verlauf),
    Geschenke, Verträge (Schutz, Handel, Bündnis) mit Pflichten und Lieferungen, Tauschhandel mit
    Tageslimit, Aufnahme, Drohung, Krieg/Frieden, Seitenwechsel, Gebietsverletzung. Alle Aktionen haben
    `Kingdom`-Parameter (Spieler-Oberfläche und ab Phase 7 die KI rufen dieselben Funktionen auf);
    Prüfungen geben `""` oder einen deutschen Grund zurück.
  - `MessengerSystem`: angegriffene Dörfer schicken sichtbare Boten (Befehl `"travel"`, kämpfen nie,
    sprinten vor Feinden) zum nächsten Gegnerreich bzw. Nachbardorf; abgefangene Boten melden nichts.
  Kampfsignale (`kingdom_attacked`, `unit_died`, `building_destroyed`) feuern mitten in den Schleifen des
  CombatSystems – Folgen (Alarm, Boten, Vertragsende) landen deshalb in einer Warteschlange und laufen
  im eigenen Takt. Zustand je System in einfachen Feldern (`to_dict`/`from_dict`/`rebuild_runtime`).
- **Gegnerische Königreiche** (`scripts/ai/`, Phase 7): Das `AISystem` gründet je nach Schwierigkeit und
  Kartengrösse KI-Reiche (Fraktion der Gegenseite, eigenes Volk, `controller = "ai"`) auf den Plätzen vom Typ
  `"kingdom"`, setzt die Faktoren der Schwierigkeit (Quelle `"difficulty"`) und lässt die Gehirne gestaffelt
  denken (alle paar Spielsekunden eines; dazu ein billiger Schnelltakt für Verteidigung und Wellen).
  `AIBrain` hält nur Laufzeit – der Zustand liegt als einfache Werte in `Kingdom.ai_state`. Die Module sind
  statische Funktionen: `AIEconomy` (Bauliste, reaktives Bauen, Bauplatzsuche mit Prüfbudget, Berufe –
  Soll-Verteilung zwischengespeichert, Umverteilung gedrosselt –, Forschung), `AIMilitary` (Beschwören,
  Helden, Zauber, Verteidigung, Lager räumen, Angriffswellen mit Sammeln, Marsch und Rückzug) und
  `AIDiplomacy` (Dörfer umwerben, Späher, Spione, Reichstarnung). Die KI benutzt nur die öffentlichen
  Schnittstellen, die auch der Spieler nutzt. Angriffe auf den Spieler kommen erst, wenn er **entdeckt**
  ist und die Zeitsperre der Schwierigkeit (`first_attack_minutes`, Normal 45 min) abgelaufen ist.
  `AIRivalry` lässt die KI-Reiche untereinander Spannung aufbauen bis zum Krieg.
- **Entdeckung und Spionage** (`scripts/espionage/`): Das `EspionageSystem` berechnet je Reich einen
  **Entdeckungswert** (Gebäude, Bevölkerung, Armee, Helden, abklingende Aggression; Reichstarnung −40 %),
  daraus je Beobachter und Ziel die **Aufmerksamkeit** (Nähe, Sprünge durch Angriffe, Boten, ertappte
  Spione; Stufen Gerüchte und entdeckt) und die **Kundschaft** (Stufe 0–3 mit Alter; Quellen: Späher,
  Spione, Boten, Angriffe). Was der Spieler über fremde Reiche sieht (Auswahlfenster, Diplomatie, Spionage),
  hängt nur an `get_intel_level`, `details_visible`, `estimate_strength` und `get_kingdom_summary`. Das
  `SpySystem` führt Spione (Stufe der Einheit `spy`, immer getarnt) mit Aufträgen *Auskundschaften*, *Dorf
  aufhetzen*, *Rivalen aufhetzen* (Befehle `infiltrate`/`spy`/`return` über `CommandSystem.order_travel`),
  würfelt die Entdeckung gegen die Wachsamkeit des Gastgebers und lässt Spione mit Erfahrung aufsteigen.
- **Sieg und Niederlage** (`scripts/kingdoms/victory_system.gd`): Fällt die Burg oder stirbt der König eines
  KI-Reichs, zerfällt es im eigenen Takt (Gebäude werden zu Ruinen, Truppen lösen sich auf, Verträge enden,
  das Gebiet verschwindet). Sind alle feindlichen Reiche gefallen, zeigt `game.gd` den Siegbildschirm mit
  Statistik („Weiterspielen“ möglich). Fällt die Burg oder der König des Spielers, ist das Spiel verloren.
- **Spionage-Oberfläche** (`scripts/ui/`): `EspionagePanel` (Fenster K, Reiter „Übersicht“, „Reiche &
  Dörfer“, „Spione“), Knopf „Spionage“ oben mit Entdeckungsbalken (`HUD`), Spion-Abschnitt und
  Kundschaft im `SelectionPanel`, Burgsymbole und Ruinen in der `Minimap`, Ruinen in der Welt
  (`CombatEffects`). Die vier Fenster in der Mitte (Forschung, Helden, Diplomatie, Spionage) schliessen sich
  gegenseitig; Esc schliesst das offene zuerst.
- **Diplomatie-Oberfläche** (`scripts/ui/`): `DiplomacyPanel` (Fenster N, Reiter „Dörfer“ und „Reiche“),
  Dorf-Abschnitt im `SelectionPanel`, Kriegsbestätigung im `SelectionController` (zweiter
  Rechtsklick), Dorf- und Botensymbole in der `Minimap`, Gebietsname im Infobereich des HUD.
- **Quellen**: Was ein Reich verändert, wird mit seiner Quelle gespeichert (`"research:<id>"`,
  `"upgrade:<id>"`, `"spell:<id>"`, Bündnisse `"alliance:<dorf-id>"`, aufgenommene Dörfer
  `"annex:<dorf-id>"` – beide schalten den Volkskrieger in der Kaserne frei): Freischaltungen (`grant_unlock`),
  Faktoren (`set_modifiers`), Zuschläge (`set_bonus`, z. B. Mana-Maximum) und laufende Kosten
  (`set_upkeep`, zieht das `EconomySystem` ab). Eine Quelle kann so alles wieder entziehen, ohne
  andere zu stören; beim Laden baut `ResearchSystem.restore` alles aus dem Forschungsstand neu auf.
- **Zauberwirkungen** auf Einheiten laufen nur über `MagicSystem.add_unit_effect` (mit Ablaufzeit);
  `Unit.refresh_stats()` rechnet daraus die Werte und die Tarnung ab.
- **Einheiten**: Bewohner, Truppen, König und Monster sind alle `Unit`. Ihre Werte kommen aus
  `units.json` und werden mit Modifikatoren des Reichs (Forschung, Schwierigkeit) und Wirkungen
  (Zauber, Helden) in `Unit.refresh_stats()` berechnet. Wer arbeitet (Befehl leer), wird nur vom
  WorkSystem gesteuert; ein Befehl unterbricht die Arbeit, „Zur Arbeit“ setzt sie fort.
- **Beziehungen**: `Game.set_relation(a, b, "war" | "peace" | "alliance")`; Kampf nur bei Krieg.
  Die wilden Monster sind ein eigenes Reich, mit allen im Krieg. `Game.can_see` ist die Stelle für
  Sichtbarkeit (ab Phase 7: Entdeckung, Spione).
- **Völker, Tag/Nacht, Zufriedenheit, Ereignisse (Phase 8)**:
  - `PeopleSystem` (`scripts/world/`): Grundbonus des Volks als Quelle `"people:<id>"`, Geländeboni je Einheit
    im abgeleiteten Feld `Unit.terrain_mods` (nur bei Biomwechsel neu, höchstens 250 Einheiten je Takt).
  - `DayNightSystem` (`scripts/world/`): Abschnitte Morgen/Tag/Abend/Nacht aus der Uhrzeit, Quelle `"daynight"`
    je Reich (globale Nachtwerte, Tag-/Nachtboni des Volks, eigene Werte für Monster); `DayNightView`
    (CanvasModulate) dunkelt nur die Welt ab, `DayClock` zeigt Sonne bzw. Mond.
  - `SatisfactionSystem` (`scripts/economy/`): `Unit.satisfaction` je Bewohner nähert sich einem Ziel aus
    Reichs- und persönlichen Ursachen; Folgen über `Unit.work_mult` (Arbeitsleistung), Überlaufen (Befehl
    `"defect"`, am Ziel `UnitSystem.transfer_unit`) und Verrat (`EspionageSystem.report_betrayal`); Feste als
    Quelle `"feast"`. Neue Gebäude Taverne und Tempel (`satisfaction` in buildings.json). Sicherheit ab Phase 9
    auch durch Mauerring und Türme (`SiegeSystem.get_safety_bonus`, `siege.json` → `safety`); verlorene
    Mauerstücke und Tore zählen nicht als „Gebäude verloren“. Das Zielreich greift Überläufer nicht an.
  - `EventSystem` (`scripts/events/`): seltene Zufallsereignisse aus `data/events.json` (Dürre, Seuche,
    Magiesturm, Monsterwelle, Flüchtlinge, Wanderer, Erntedank, Manablüte) für alle Reiche; Quellen
    `"event:<id>#<nr>"`, Einheitenwirkungen `"event:<id>"`. Flüchtlinge und Wanderer gehören dem Reich
    „Wanderer“ (Befehl `"seek_refuge"`), die KI entscheidet selbst. `EventEffects` zeichnet Gebiete und Blitze.
  - `MonsterSystem` (ausgebaut): Streifzüge zu nahen Siedlungen (nachts häufiger), Monsterwellen
    (`spawn_wave`), wachsende Lager, neue Lager an freien Plätzen, untätige heimatlose Monster schliessen
    sich an. Schwierigkeit: `monster_growth_mult` (Nachwuchs, Wachstum, neue Lager), `monster_raid_mult`.
  - Daten: `data/events.json`, `data/satisfaction.json`, `data/daynight.json`; Oberfläche `KingdomPanel`,
    `EventBanner`, `RefugeeDialog`, `MoodIcon`. Jedes System hat `to_dict`/`from_dict`/`rebuild_runtime`.
- **Spielende**: `Game.defeat_kingdom` – stirbt der König des Spielers oder fällt seine Burg, ist das Spiel
  verloren; sind alle feindlichen Königreiche gefallen, ist es gewonnen (`VictorySystem`).
- **Trennung Simulation/Darstellung**: Die Systeme kennen weder Karte noch HUD. Die Darstellung hört
  auf Signale (`WorldData.cell_changed`, `road_changed`, `TerritorySystem.changed` …). Das ist die
  Grundlage für Speichern/Laden in Phase 10.
- **Wegfindung** (`NavGrid`, A* über die ganze Karte): Gelände kostet unterschiedlich viel, Strassen
  sind schneller, Gebäude blockieren. Ab Phase 9: Tore sind im Grundzustand blockiert und werden je
  Suche nur für Reiche geöffnet, die hindurch dürfen (`gate_rule` vom SiegeSystem); von Mauern
  eingeschlossene Flächen („Ringe“) bekommen Labels (lokale Flutfüllung nach jeder Änderung), damit
  ein eingemauertes Ziel A* nie die ganze Karte absuchen lässt; `last_fail` nennt den Grund.
- **Belagerung und Handel** (Phase 9, `data/siege.json`, `data/trade.json`):
  - `SiegeSystem` (`scripts/units/`): meldet Mauern, Tore und Türme (normale Gebäude mit
    `fortification`) beim NavGrid an, Türme schiessen selbsttätig, `find_breach_target` sucht das Mauerstück,
    das einen Weg versperrt (Bresche), `find_siege_target` die Ziele für Rammböcke und Katapulte.
  - `TradeRouteSystem` (`scripts/economy/`): Handelswege zu Dörfern mit Handelsvertrag oder Bündnis;
    Lieferungen fahren als Karawane (Befehl `"haul"`), Überfälle bringen Beute, Verluste oder Feinde am Weg
    schneiden ihn ab. `TradeRouteView` (`scripts/view/`) zeichnet die Wege gestrichelt, die Minikarte auch.
    Die Liste (`TradeRouteList`) steht im Diplomatiefenster (Reiter „Handelswege“) und in der
    Reichsübersicht (Reiter „Handel“).
  - `SupplySystem` (`scripts/economy/`): fern vom eigenen bzw. verbündeten Gebiet und offenen Handelswegen
    erholen sich verletzte Einheiten nicht (Wirkung `supply:regen` über das MagicSystem).
  - KI: `AISiege` (`scripts/ai/`) baut Türme und einen Mauerring bei Bedrohung, bringt Belagerungswaffen
    gegen befestigte Ziele und schliesst früh einen Handelsvertrag.
- **Tutorial** (`scripts/tutorial/tutorial_system.gd`, `scripts/ui/tutorial_overlay.gd`, `data/tutorial.json`): Das
  `TutorialSystem` (Node unter *Systems*, im Spielstand als `"tutorial"`) führt durch die Schritte der Datei. Bedingungen
  wie `building_placed:house` oder `window_opened:heroes` liest es alle 0,25 echte Sekunden aus dem Zustand des Spiels
  (läuft auch in der Pause); Aktionen ohne bleibenden Zustand (Bewegungsbefehl, Speichern, Tempo) merkt es sich über
  Signale (`SelectionController.command_issued`, `SaveManager.save_finished`, `GameClock.speed_changed`). Der Schutz
  (`TutorialSystem.protects(game, kingdom)`) wird von `AIMilitary` (Wellenziele), `EventSystem` (Ereignisziele) und
  `MonsterSystem` (Streifzüge) abgefragt. `TutorialOverlay` (Ebene 30) zeigt Fenster, Rahmen und Pfeil und lässt alle
  Klicks zum Ziel durch.
- **Gebiet**: Jedes fertige Gebäude beansprucht einen Kreis; bei Überschneidung gewinnt das ältere.
  Gebaut werden darf nur im eigenen Gebiet; Sammler holen nichts aus fremdem Gebiet (z. B. eines Dorfs).

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
- Schnellere Forschung: `research.json` → `time` (Sekunden), Kosten unter `cost`.
- Billigere Zauber: `spells.json` → `mana_cost`, `cooldown`; Reichweite ausserhalb des Gebiets: `settings.cast_range_outside`.
- Mehr Mana-Maximum: `resources.json` → *mana* → `cap`; Kampfpunkt-Verbesserungen: `spells.json` → `upgrades`.
- Helden: `heroes.json` → `heroes` (Werte unter `stats`, Kosten, Fähigkeiten, Talente), `abilities` (Werte je Rang),
  `settings` (Erfahrung je Stufe `levels`, Teilung `xp_share`, Ausbildung, Wiederbelebung, höchstens `max_heroes`).
- Mehr oder weniger Dörfer: `worldgen.json` → `villages.count_by_size` (z. B. `[256, 6]` → `[256, 8]`),
  Abstand zum Start `min_dist_start`, Hütten je Dorf `size`.
- Ruf: `diplomacy.json` → `reputation.tiers` (Stufen und Farben), `events` (z. B. Angriff `attack: -5`,
  Kriegserklärung `declare_war: -30`, Gerüchte `rumour_*`), Verfall `reputation.decay_per_interval`.
- Geschenke: `diplomacy.json` → `gifts` (`value_per_point`, `max_per_gift`, Ermüdung `saturation`/`half_life`);
  Lieblingswaren je Volk: `peoples.json` → `gift_preferences` (z. B. Zwerge `"food": 1.5`).
- Verträge: `diplomacy.json` → `treaties.<protection|trade|alliance>` (`min_reputation`, `keep_min`,
  `rep_per_hour`, `cancel_penalty`, Schutzfrist `help_seconds`); Tribut und Lieferungen je Volk:
  `peoples.json` → `tribute`, `delivery`; Annahme-Chance `treaties.chance_base` / `chance_span`.
- Handel: `diplomacy.json` → `trade` (`base_margin`, `daily_value_limit`); Kurse je Volk `trade_rates`
  (`sells` < 1 = billiger, `buys` > 1 = zahlt mehr) und `trade_bonus` (Koboldhändler 0.25).
- Aufnahme und Drohung: `diplomacy.json` → `annex` (`min_reputation`, `intimidation_ratio`, `gift_size_scale`),
  `threat` (`min_ratio`, `tribute_max`, `cooldown`); grosses Geschenk je Volk `peoples.json` → `annex_gift`.
- Dörfer und Milizen: `diplomacy.json` → `village` (`militia_base`, `militia_per_size`, `refill_seconds`,
  `start_stock`); Werte der Milizen und Volkskrieger in `units.json` (`militia_*`, z. B. `dwarf_ironguard`).
- Boten: `diplomacy.json` → `messenger` (`cooldown`, `max_village_distance`, `sprint_mult`).
- Gegner-KI: `ai.json` → `difficulty.<id>` (Anzahl Reiche je Kartengrösse `kingdoms`, erste Welle gegen den
  Spieler `first_attack_minutes`, Pause `wave_interval`, Wellengrösse `wave_min_size`/`first_wave_max`,
  `army_size_mult`, `awareness_mult`), Bauliste `build_order`, Persönlichkeiten `personalities`
  (z. B. `aggressive`: mehr Armee, frühere Wellen), Rückzug `difficulty.<id>.retreat_ratio`, Rivalität `rivalry`
  (`war_at`, `peace_at`), Berufe `jobs` (Drosselung `rebalance_every`, `rebalance_min_gap`, `targets_seconds`).
  Beispiel: spätere erste Welle auf Normal – `difficulty.normal.first_attack_minutes` 45 → 60.
- Entdeckung und Spionage: `espionage.json` → `discovery.building_weights` (z. B. `barracks: 2.5`),
  `per_population`, `per_army_power`, Stufen `discovery.tiers`; Aufmerksamkeit `awareness` (`rumour` 30,
  `discovered` 60, `rise_per_minute`); Reichstarnung `cloak` (`reduction` 0.4, `upkeep_per_point`); Spione
  `spies` (`max_base`, `levels` mit Geschick und Tempo, `detect_base`, `vigilance.buildings`, Dauer der
  Aufträge `scout_duration`, `incite_duration`). Beispiel: Spione schwerer zu entdecken – `spies.detect_base`
  0.03 → 0.02.
- Neues Volk: in `peoples.json` einen Eintrag mit `"faction": "neutral"`, `village_title`, `village_names`,
  `produces`, `militia_unit` und `special_unit` (beide in `units.json` anlegen) – Dörfer dieses Volks
  entstehen dann automatisch bei der Weltgenerierung.

## Tutorial

**Starten:** Hauptmenü → **Tutorial**: eine feste, freundliche Partie (Seed „Lernreich“, kleine Karte, *Leicht*, ein
Gegnerreich) mit der zuletzt gewählten Fraktion. Oder im Dialog *Neues Spiel* den Haken **„Tipps/Tutorial anzeigen“**
setzen – dann läuft das Tutorial in der Partie mit den eigenen Einstellungen.

**Ablauf:** Rechts erscheint ein Fenster mit Kapitel, „Schritt 5/30“, Titel, kurzem Text und der Aufgabe. Ein pulsierender
goldener Rahmen zeigt das Bedienelement (Baumenü-Knopf – liegt er in einem anderen Reiter, wird der Reiter gezeigt –,
Knöpfe oben, Arbeitsverteilung, Minikarte, Auswahlfenster, Zauberleiste …), ein Pfeil die Stelle in der Welt (Burg,
Manaquelle, nächstes Dorf; ausserhalb des Bildes am Rand). Klicks gehen durch Rahmen und Pfeil hindurch. Ist die
Aufgabe erfüllt, steht „✓ Geschafft!“ und es geht nach gut einer Sekunde weiter; reine Erklärschritte haben „Weiter“.
Lange Schritte (Haus fertig, Truppen, Forschung, Zauber, Held, Geschenk …) lassen sich **überspringen**. „Beenden“
(zweimal klicken) blendet das Tutorial aus; im **Spielmenü (Esc)** steht dann „Tutorial fortsetzen (Schritt 7/30)“,
nach dem Abschluss „Tutorial starten“, während es läuft „Tutorial von vorn“.

**Kapitel** (30 Schritte): Erste Schritte (Kamera, Zoom/Minikarte, Pause, Tempo) · Dein Dorf (Vorräte, Wohnhaus,
Bauernhof, Strassen, Berufe mit J, Manabrunnen) · Einheiten (Späher aus der Burg, Auswählen, Bewegen, Kaserne, Truppen,
Armee mit Strg+1, Angriff-Vorrücken) · Wissen und Magie (Bibliothek, Forschung mit R, Zauber) · Helden (Heldenhalle,
Anwerben mit G) · Reich und Nachbarn (Diplomatie mit N, Geschenk, Spionage mit K, Reichsübersicht mit L) · Speichern und
Hilfe (F5, F1). Ein Schritt mit `requires_hud` erscheint nur, wenn das HUD das Fenster hat (z. B. ein späteres
Armeefenster mit T).

**Damit nichts dazwischenkommt:** Solange das Tutorial läuft (höchstens 120 Spielminuten ab dem ersten Start), wählen die KI-Reiche den
Spieler nicht als Wellenziel, Zufallsereignisse (auch Monsterwellen und Flüchtlinge) und Monster-Streifzüge treffen ihn
nicht; nach dem Ende gilt das noch 10 Minuten, danach wieder die normalen Regeln der Schwierigkeit (z. B. erste Welle
frühestens nach `first_attack_minutes`). Der Hofschatzmeister schenkt bei einigen Schritten die nötigen Rohstoffe
(einmal je Partie, auch nach „von vorn“ nicht doppelt), damit niemand lange warten muss. Ein im Spielmenü nachträglich
gestartetes Tutorial in einer normalen Partie schützt nicht.

**Spielstand:** Schritt, Zustand, Schutz und bezahlte Geschenke werden gespeichert (`TutorialSystem.to_dict`); nach
dem Laden geht es beim gleichen Schritt weiter.

**Anpassen** (`data/tutorial.json`): `game` (Seed, Karte, Schwierigkeit), `settings` (Weiter-Pause, Schutzdauer,
Schonfrist, Schwellen für Kamera/Zoom/Strassen), `aliases` (fraktionsabhängige Forschung/Zauber), `steps` (Text mit
Platzhaltern `{b:house}`, `{u:scout}`, `{r:healing}`, `{s:heal_spell}`, `{key:toggle_help}`; `highlight`, `world`,
`condition`, `skippable`, `grant`, `focus`, `requires_hud` – alle Werte stehen im `_hinweis` der Datei).

**Rauchtest:** `GODOT=… tests/run_smoke.sh 900 tutorial=1` startet je Fraktion eine Tutorial-Partie und spielt alle
Schritte über dieselben Schnittstellen wie die Oberfläche durch (Gebäude setzen, Berufe, Beschwören, Befehle, Forschung,
Zauber, Helden, Fenster, Geschenk, Schnellspeichern, Hilfe). Geprüft werden: „Weiter“ ist vor der Aufgabe gesperrt,
jede Bedingung wird erfüllt, Rahmen und Pfeil finden ihr Ziel, Geschenke, der Schutz (Ereignis- und Wellenziele), Laden
des Spielstands aus dem Schritt „Speichern“, Beenden und Fortsetzen über das Spielmenü. Ohne `tutorial=1` prüft der
normale Rauchtest, dass das Tutorial aus ist und nicht schützt.

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
   Bogenschützen beschwören; Ritter erst nach der Forschung *Ritterorden* (ab Phase 4, siehe unten). Mit Rechtsklick in die Welt einen **Sammelpunkt** setzen.
4. Truppen mit gedrückter linker Maustaste **einrahmen** (Bewohner werden dabei nicht mitgenommen).
   **Rechtsklick** ins Gelände: sie marschieren in Formation (F wechselt Block/Linie/Keil/Kreis).
5. **Strg+1** speichert die Auswahl als Armee 1 (Leiste über dem Auswahlfenster), **1** wählt sie,
   zweimal **1** springt mit der Kamera hin.
6. Armee auswählen, **Rechtsklick auf eine Monsterhöhle** oder ein Monster → Angriff. Bogenschützen
   schiessen Pfeile, Treffer blitzen auf, Gefallene verblassen. Eine zerstörte Höhle gibt Beute und
   **Kampfpunkte** (gekreuzte Schwerter oben neben Mana). Bewohner sammeln nicht in der Nähe von Höhlen.
7. Verletzte erholen sich nach 5 Sekunden ohne Kampf; **Krankenstation** (heilt in der Nähe) und
   **Heiler** heilen schneller. Die Krankenstation gibt es ab Phase 4 erst nach der Forschung
   *Heilkunde* (Bibliothek bauen, R drücken, Magie Stufe 1).
8. Wird ein Bewohner angegriffen, flieht er zur Burg und arbeitet danach weiter. Ein Späher, der als
   Holzfäller arbeitet, wehrt sich und arbeitet danach weiter. Beschworene Einheiten brauchen zum
   Arbeiten Wohnraum.
9. Spielende testen: F3 (Debug) und dann mehrmals F10 → der König verliert Leben, flieht verletzt in
   die Burg; stirbt er, erscheint „Der König ist gefallen“ mit „Neu starten (gleiche Karte)“.

## Phase 4 testen

Tipp: Mit F3 (Debug) gibt F9 Ressourcen und F11 setzt 3 Wölfe an die Maus – so lassen sich Flüche,
Nebel, Tarnung und Heilung auch im eigenen Gebiet ausprobieren. Monster folgen bis 12 Felder von
ihrer Höhle; man kann sie also auch an die Grenze locken.

1. Neues Spiel. **Bibliothek** bauen (GUT; BÖSE: *Dunkles Archiv*, 40 Holz, 80 Stein, 10 Mana).
   **R** oder der Button „Forschung (R)“ oben öffnet den Forschungsbaum: vier Zweige (Militär, Magie,
   Wirtschaft, Mana), Stufen 1–4. Ohne Bibliothek steht im Fenster, was zu bauen ist.
2. **Heilkunde** (Magie, Stufe 1) anklicken: die Kosten werden bezahlt, oben laufen Fortschritt und
   Restzeit, der Button zeigt „Forschung (R) · 45 %“. Bis zu 3 Forschungen einreihen; Klick auf eine
   laufende oder eingereihte bricht sie ab (zweiter Klick bestätigt, volle Erstattung). Ist die
   Bibliothek untätig, zeigt der Button gelb „Forschung ruht“. Eine zweite Bibliothek forscht 25 % schneller.
3. Nach *Heilkunde*: die **Krankenstation** ist baubar (vorher grau, Tooltip „Benötigt Forschung:
   Heilkunde“) und der Zauber *Heilendes Licht* ist in der Zauberleiste frei. Nach *Ritterorden*
   (Militär 2): Ritter in der Kaserne. Wirkungen wie „+10 % Angriff“ zeigt der Tooltip der Werte im
   Auswahlfenster („Angriff 12 → 13,2 (Waffenschmiede +10 %)“).
4. **Mana**: Maximum 100 („80/100“ oben; voll = gelb, Überschuss geht verloren). **Kampfpunkte**
   (gekreuzte Schwerter oben, ein Klick öffnet sie) gibt es für besiegte Monster und zerstörte Höhlen.
   Im Forschungsfenster, Reiter „Kampfpunkte“: *Manakristall* (+40 Maximum je Stufe) und *Manaherz*
   (die Burg erzeugt Mana). Ist eine Verbesserung bezahlbar, kommt einmal eine Meldung und der
   Forschungs-Button bekommt einen Punkt.
5. **Zaubern** (nur der König; stirbt er, ist das Spiel verloren): Zauber in der Leiste anklicken –
   gesperrte zeigen, welche Forschung fehlt. Der Kreis folgt der Maus; erlaubt ist das eigene Gebiet
   und 16 Felder darum (leicht eingefärbt). Neben der Maus steht, wie viele Einheiten getroffen werden.
   Linksklick zaubert (Mana und Abklingzeit), Rechtsklick/Esc bricht ab. Ein Kreis, der niemanden
   trifft, wird abgelehnt – es geht kein Mana verloren.
6. **GUT** (Licht, gold/weiss): *Lichtsegen* auf eigene Truppen (+25 % Angriff, mehr Rüstung; im
   Auswahlfenster „Lichtsegen · 24 s“), *Heilendes Licht*, *Lichtschleier* (Truppen werden durchsichtig,
   Monster lassen von ihnen ab, sie greifen selbst nicht an – erst ein Angriffsbefehl oder
   Angriff-Vorrücken hebt die Tarnung auf; kostet 0,5 Mana/s), *Segensregen* über Höfen und
   Holzfällern (+50 % Nahrung und Holz), *Ruf des Lichts* (3 Lichtgeister für 60 Sekunden).
7. **BÖSE** (dunkel violett, Flüche): *Fluch der Schwäche* auf Monster (schwächer, schlechter
   geschützt), *Dunkle Erneuerung*, *Schattenmantel*, *Finsterer Nebel* (Feinde werden langsam und
   verlieren Ziele, die mehr als 2 Felder entfernt sind – damit entkommt man), *Schattenbrut*.
8. Forschung *Manafokus* (Mana 2) senkt alle Zauberkosten um 20 %, *Zauberfluss* (Mana 3) die
   Abklingzeiten um 25 %, *Weitreichende Magie* / *Lange Schatten* (Magie 2) erweitert die Reichweite
   um 8 Felder. Die Werte im Tooltip der Zauberleiste ändern sich entsprechend.

## Phase 5 testen

Tipp: F3 (Debug) einschalten. F9 gibt Ressourcen, F12 gibt dem ausgewählten Helden eine Stufe, F11 setzt
Wölfe und Umschalt+F11 einen Übungsgolem (viel Leben, Rüstung) an die Maus. Im Heldenfenster erscheinen im
F3-Modus zusätzlich Knöpfe „+1 Stufe“, „Abklingzeiten“, „Sofort wiederbeleben“ und „Held fällt“.

1. Kaserne bauen, dann die **Heldenhalle** (BÖSE: *Halle der Schatten*; braucht eine Kaserne, nur eine pro
   Reich). **G** oder „Helden (G)“ oben öffnet das Heldenfenster, Reiter „Anwerben“ (oder die Halle anklicken
   → „Helden anwerben“ im Auswahlfenster): drei Helden je Fraktion
   (GUT: Paladin, Sternenmagierin, Waldläuferin – BÖSE: Nekromant, Kriegsherr, Klingentänzerin).
2. Einen Helden anwerben (Nahrung, Erz, Mana; jeder weitere Held kostet mehr). Nach 30 Sekunden erscheint er
   an der Halle, mit eigenem Namen. Jeden Typ gibt es einmal, höchstens drei Helden.
3. Der Held erscheint in der **Heldenleiste** links. Auswählen → im Auswahlfenster Stufe, Erfahrung (EP) und
   seine Fähigkeiten. **C / V / B** wirken sie (Feind oder Stelle anklicken; ist das Ziel zu weit weg, läuft
   der Held hin). Das geht auch, wenn er mit seiner Armee zusammen ausgewählt ist (Tab wechselt den Helden).
   Rechtsklick auf einen Fähigkeitsknopf schaltet „selbst auslösen“ (goldener Rahmen) um.
4. Helden sind **Generäle**: eigene Truppen in ihrer Nähe schlagen härter zu (Führung), dazu hat jeder Held
   eine eigene Führungseigenschaft. Marschiert eine Armee mit Held, führt der Held sie an.
5. **Erfahrung**: besiegte Feinde in der Nähe (mehrere Helden teilen sich nicht alles: jeder bekommt einen
   Anteil), zerstörte Höhlen zählen 1,5-fach, dazu **Ausbildung** in der Halle (Nahrung, Holz, Stein; bis
   Stufe 5, mit der Forschung *Heldenlehre* bis 7). Bei jedem Stufenaufstieg wählst du eine von zwei
   Verbesserungen: eine Fähigkeitsstufe (I–III) oder ein Talent des Helden.
6. **Tod**: fällt ein Held, kann er nach 60 Sekunden in der Burg wiederbelebt werden (Burg anklicken, Heldenleiste
   oder Heldenfenster) – gegen Kosten, mit gleicher Stufe, und er ist wieder in seiner Armee.
7. Fähigkeiten zum Ausprobieren (gegen F11-Wölfe oder den Umschalt+F11-Golem):
   GUT – *Lichtschlag*, *Heilige Aura*, *Göttlicher Schild* (Paladin); *Sternenfeuer*, *Sternensprung*,
   *Sternenquelle* (mehr Mana, Sternenmagierin); *Pfeilhagel*, *Schlachtruf*, *Adlerauge* (Waldläuferin).
   BÖSE – *Seelenblitz*, *Totenerweckung*, *Fluchaura* (Nekromant); *Wirbelwind*, *Kriegsschrei*, *Blutzoll*
   (Kriegsherr); *Schattenschritt*, *Giftklinge*, *Ausweichen* (Klingentänzerin).

## Phase 6 testen

Tipp: F3 (Debug) einschalten – F9 gibt Ressourcen. Im Diplomatiefenster erscheinen im F3-Modus die Knöpfe
„Ruf +20“, „Ruf −20“ und „Bote senden (Test)“.

1. Rund um dein Reich liegen **neutrale Dörfer** (kleine Karte 6, mittlere 10, grosse 16) mit einer Grenze in
   der Volksfarbe; auf der Minikarte steht je Dorf ein Haussymbol. Fährt die Maus über ein Dorfgebiet, zeigt
   der Infobereich unten links „Gebiet: Zwergendorf Eisenhall (Neutral)“. Deine Sammler holen dort nichts.
2. Ein **Dorfzentrum** (oder eine Miliz) anklicken: im Auswahlfenster Volk, Ruf mit Stufe (farbig), Vertrag,
   Produktion und Miliz, darunter der Knopf **„Diplomatie (N)“**.
3. **N** (oder „Diplomatie (N)“ oben) öffnet das Diplomatiefenster: links alle Dörfer mit Ruf-Balken,
   Vertrag bzw. Krieg, Entfernung und grober Stärke; rechts das gewählte Dorf mit Beschreibung, Stärken und
   Schwächen des Volks, Produktion, Vorrat, Ruf-Verlauf und Beziehungen. Forschungs-, Helden- und
   Diplomatiefenster schliessen sich gegenseitig; Esc schliesst.
4. **Geschenk**: Ware und Menge wählen – die Zeile darunter zeigt den Rufgewinn („Ruf +6,3“, Lieblingswaren
   zählen mehr, viele Geschenke kurz nacheinander wirken weniger) – dann „Schenken“.
5. **Handel**: Menge und Ware wählen, die du gibst, und die Ware, die du bekommst; die Zeile zeigt Menge, Kurs
   und das restliche Tageslimit. Koboldhändler und Nomaden haben die besten Kurse, ein Handelsvertrag senkt die
   Marge und erhöht das Limit.
6. **Verträge**: Die Annahme-Chance steht auf dem Knopf („Schutz (75 %)“), Bedingungen und Gegenleistung im
   Tooltip, gesperrte Verträge nennen den Grund. *Schutzvertrag*: das Dorf zahlt Tribut – wird es angegriffen,
   schicke binnen 60 s Truppen hin (sonst sinkt der Ruf; der Knopf oben bekommt einen roten Punkt).
   *Handelsvertrag*: regelmässige Lieferungen und bessere Kurse. *Bündnis* (ab Freundlich): Milizen helfen dir
   in der Nähe, der **Volkskrieger** erscheint in der Kaserne. „Vertrag kündigen“ braucht einen zweiten Klick.
7. **Aufnahme**: ab *Ergeben* (oder ab *Freundlich* mit grossem Geschenk bzw. starker Armee in der Nähe) –
   „Aufnehmen“ zweimal klicken. Das Dorfzentrum wird dein Aussenposten mit Gebiet, die Milizen werden deine
   Truppen, die Produktion fliesst in dein Lager (Auswahlfenster zeigt den Ertrag).
8. **Drohen**: mit genug Truppen in der Nähe zahlt das Dorf Tribut, sonst lacht es dich aus – der Ruf sinkt so
   oder so, andere Dörfer hören davon.
9. **Krieg**: mit Truppen zweimal Rechtsklick auf eine Miliz oder ein Gebäude des Dorfs (der erste Klick warnt
   nur) oder „Krieg erklären“ im Fenster. Das Dorf schickt einen **Boten** (Meldung mit Klick, blinkendes
   weisses Quadrat auf der Minikarte) zum nächsten Dorf – fange ihn ab, sonst sinkt dein Ruf auch dort.
   Dorfzentrum auf 0 Leben → **erobert** (gemindert produktiv, andere Dörfer misstrauen dir). Frieden geht
   nach 60 s ohne Angriff, wenn der Ruf nicht zu tief ist.
10. Sinkt der Ruf unter −50, wird ein Dorf feindlich (ab Phase 7 schliesst es sich dann dem Gegner an).

## Phase 7 testen

Tipp: F3 (Debug) einschalten – im Spionagefenster erscheinen dann „Aufmerksamkeit +30“, „Volle Kundschaft“,
„KI greift jetzt an“, „KI-Reich besiegen“ und „Rivalen: Krieg“, im Diplomatiefenster (Reiter „Reiche“)
„Besiegen (Test)“; F9 gibt Ressourcen.

1. Neues Spiel (Normal, mittlere Karte). In mittlerer Entfernung liegen zwei feindliche Königreiche (bei BÖSE
   gute, bei GUT böse), jedes mit eigenem Volk und Namen. Ihre Grenzen in der Volksfarbe und ihre Burgen
   (Burgsymbol auf der Minikarte, roter Ring) sind sichtbar.
2. Burg eines Feindes anklicken: ohne Kundschaft steht im Auswahlfenster nur „Keine Kundschaft“, fremde
   Einheiten zeigen „?“ statt Werten. Späher hinschicken: Das Auswahlfenster zeigt dann die Heeresgrösse
   ungefähr („Kundschaft: Bericht“).
3. Die KI baut auf (Häuser, Höfe, Kaserne, Bibliothek …), beschwört Truppen, räumt Monsterlager in ihrer Nähe
   und umwirbt Dörfer (Geschenke, Verträge – im Diplomatiefenster sichtbar, sobald du Kundschaft hast).
4. Oben „Spionage · 12“: dein Entdeckungswert. Er steigt mit Gebäuden, Bevölkerung, Armee und Angriffen
   (Aggression klingt ab). Die Ursachen stehen im Spionagefenster (K), Reiter „Übersicht“.
5. Forschung *Kundschafter* (BÖSE: *Spitzel*), dann im Spionagefenster, Reiter „Spione“, „Spion beschwören“
   (Burg; mit *Spionagenetz* bzw. *Schattennetz* im Kundschafterhaus eine Stufe höher). Auftrag
   *Auskundschaften* auf ein Reich → genaue Kundschaft (Stufe 3, Diplomatie → „Reiche“ zeigt Stärke, Kriege,
   Verträge). *Dorf aufhetzen* senkt den Ruf eines Dorfs gegenüber einem Reich. *Rivalen aufhetzen* (bei zwei
   KI-Reichen) treibt sie in den Krieg gegeneinander. Die Vorschau zeigt die Entdeckungsgefahr am Ziel.
   Spione können entdeckt werden (Meldung, kurz sichtbar, sie fliehen heim) und steigen mit Erfahrung bis
   Stufe 3. Einen Spion auswählen → „Auftrag (K)“ öffnet ihn im Spionagefenster.
6. Fremde Spione kommen zu dir, wenn ein Reich Gerüchte über dich hört. Späher, eigene Spione und das
   Kundschafterhaus entdecken sie (roter Punkt am Spionage-Knopf); entdeckte Spione kann man angreifen.
7. Auf Normal greift die KI frühestens nach 45 Minuten an und erst, wenn sie dich entdeckt hat (Meldung).
   Späher melden Truppen nahe der Grenze, Feinde im eigenen Gebiet werden immer gemeldet. Wird eine Welle zu
   stark geschwächt, zieht sie sich zurück.
8. *Reichsschleier* (BÖSE: *Reichsschatten*, Magie Stufe 4): ein Klick in der Zauberleiste oder „Tarnung
   einschalten“ im Spionagefenster senkt den Entdeckungswert um 40 % und kostet laufend Mana (endet bei
   Manamangel).
9. Ein Reich fällt, wenn sein König stirbt oder seine Burg zerstört wird: Gebäude werden zu Ruinen, Truppen
   lösen sich auf, das Gebiet verschwindet. Sind alle feindlichen Reiche gefallen, erscheint der
   **Siegbildschirm** mit Statistik („Weiterspielen“ oder Hauptmenü). Fällt deine Burg, ist das Spiel
   verloren. Schneller Test: F3 → Spionagefenster → „KI-Reich besiegen“.

Rauchtest mit echter KI über lange Zeit (ohne Debug-Stufen):
`godot --headless res://tests/smoke_test.tscn -- faction=evil seconds=3600 p7=natural size=medium`
(`passive=1`: der Spieler tut nichts; der Bericht zeigt Zeitleiste, Wellen und Denkzeit der KI).

## Phase 8 testen

Tipp: F3 einschalten → in der Reichsübersicht (L) erscheinen Debug-Knöpfe: Ereignis auslösen, Alle beenden,
Monsterstreifzug, Zufriedenheit ±30, Überläufer jetzt, Verrat jetzt, Tag/Nacht/Dämmerung/echte Zeit
(F9 = Ressourcen).

1. **Neues Spiel:** Unter der Fraktion wählst du dein **Volk**; Stärken und Schwächen stehen darunter. Oben links
   steht der Name deines Volks (in der Farbe der Fraktion, Tooltip mit Fraktion).
2. **Tag und Nacht:** Oben neben dem Datum zeigt ein Symbol Sonne bzw. Mond (Tooltip: Boni deines Volks). Abends
   wird die Welt dunkler, nachts sinkt die Sicht, Monster werden aktiver und streifen häufiger umher. Im
   Auswahlfenster zeigt die Werteherkunft „Tageszeit“. Abdunklung abschaltbar in den Einstellungen.
3. **Gelände:** Einheiten auf dem Lieblingsgelände ihres Volks sind stärker oder schneller (Auswahlfenster:
   „Wald (Hochelfen): +10 % Angriff …“). Die Tabelle steht in der Reichsübersicht unter „Volk & Tageszeit“.
4. **Zufriedenheit:** Oben in der Leiste ein Gesicht mit dem Durchschnitt (Tooltip: Ursachen). Bewohner anklicken
   zeigt ihre eigene Zufriedenheit. Hunger, Überfüllung, Feinde im Gebiet und Angriffe senken sie; **Taverne**
   (Schenke), **Tempel** (Schattenschrein, braucht eine Bibliothek), Truppen, volle Speicher und **Feste** heben sie.
   - Unter 50 sinkt die Arbeitsleistung.
   - Unter 25 laufen Bewohner über (sichtbar zu einem Nachbarreich, Dorf oder an den Kartenrand; ein Befehl hält
     sie auf).
   - Unter 20 droht Verrat (der Gegner erfährt mehr über dich).
   - Schnelltest: F3 → „Zufriedenheit −30“ zweimal → „Überläufer jetzt“.
5. **Ereignisse** sind selten (frühestens nach 20 Minuten, danach etwa alle 30 Minuten irgendwo im Land). Aktive
   Ereignisse stehen oben in der Mitte mit Restzeit. Sofort testen: F3 → Reichsübersicht → Ereignis auswählen →
   „Auslösen“.
   - Dürre: Höfe liefern halb so viel; Segensregen hilft.
   - Seuche: Kranke arbeiten kaum, stecken andere an; Krankenstation, Heiler und Tempel helfen.
   - Magiesturm: Mana springt, Zauber sind billiger, Blitze.
   - Monsterwelle: Meldung mit Herkunft.
   - Erntedank und Manablüte.
6. **Flüchtlinge und Wanderer** kommen an den Rand deines Gebiets. Meldung oder Leiste anklicken → Dialog mit
   Wohnraum, Nahrung und Geschenken → Aufnehmen oder Abweisen. Aufgenommene werden Bewohner; unter ihnen kann ein
   Spion sein, den ein Tempel eher entlarvt. Abgewiesene ziehen weiter, zu einem Dorf oder zum Gegner.
7. **Wilde Monster:** Lager wachsen mit der Zeit. Zerstörte Lager entstehen später woanders neu. Monster ziehen auf
   Streifzüge zu nahen Siedlungen, auch zur KI und zu Dörfern (Minikarte: oranger Ring mit Pfeil).

Rauchtest: `tests/run_smoke.sh 600` (prüft Phase 8 in `tests/smoke_phase8.gd`); lange Läufe mit
`p8=natural seconds=3600 size=medium`, ein bestimmtes Volk mit `people=<id>`.

## Phase 9 testen

Tipp: F3 an, F9 = Rohstoffe.

1. Baumenü → Verteidigung → Mauer: mit gedrückter Maustaste einen Ring um ein Stück Land ziehen. Über eine
   Strasse entsteht automatisch ein Tor. Schliesst du den Ring ohne Tor, warnt eine Meldung.
2. Ein Tor auf ein Mauerstück setzen. Eigene Bewohner und Truppen gehen hindurch. Tor auswählen → „Verriegeln“.
3. F11 setzt Wölfe vor die Mauer. Sie finden keinen Weg und greifen Mauer oder Tor an. Sind sie weg,
   reparieren Bauarbeiter die Schäden (Stein wird abgezogen).
4. Wachturm bauen: Die Vorschau zeigt die Reichweite. Er schiesst sichtbare Pfeile auf Wölfe und Feinde.
5. Forschung → Militär „Belagerungskunst“ → Belagerungswerkstatt → Rammbock und Katapult. Rechtsklick auf ein
   feindliches Gebäude oder Lager: Katapulte schiessen von weit, Rammböcke greifen nur Gebäude an.
   Strg+F11 schickt einen feindlichen Rammbock gegen deine Burg.
6. Diplomatie (N): Handelsvertrag mit einem Dorf. Eine Karawane pendelt (gestrichelte Linie auf Karte und
   Minikarte). N → Reiter „Handelswege“ (oder L → Reiter „Handel“) zeigt Ladung, Lieferungen und Verluste.
7. Wölfe (F11) auf den Weg setzen oder die Karawane über den F3-Knopf überfallen: Erst geht die Ladung
   verloren, dann ist der Weg abgeschnitten (rotes ✕). Sind keine Feinde mehr da, öffnet er sich nach einigen
   Minuten, oder du gibst ihn über den Knopf frei.
8. KI-Karawanen (gestrichelt braun, sobald gesichtet) überfallen: Du bekommst Beute, ihre Lieferungen fallen aus.
9. Armee weit aus dem Gebiet schicken: Verletzte erholen sich nicht (Wirkung „Ohne Versorgung“). Im eigenen
   Gebiet, nahe einem offenen Handelsweg oder durch Heiler geht es wieder.
10. KI: Nach Angriffen baut sie Türme, auf Normal später auch einen Mauerring. Gegen deine Mauern bringt sie
    Rammböcke und Katapulte.

## Speichern und Laden (Phase 10)

- **Ablage**: `user://saves/<name>.save` – unter Windows `%APPDATA%\Koenigreiche\saves`, unter Linux
  `~/.local/share/Koenigreiche/saves` (`project.godot`: eigener Benutzerordner „Koenigreiche“; dort liegt auch
  `settings.cfg` – frühere Einstellungen gelten deshalb einmalig nicht mehr). Plätze: beliebig viele mit Namen,
  `quicksave` (F5/F8), `autosave_1…3` (reihum, Abstand in den Einstellungen).
- **Datei**: Zeile 1 `KOENIGREICHE-SAVE 1`, Zeile 2 Kopf als JSON (Name, Datum, Spielzeit, Fraktion, Schwierigkeit,
  Karte, Seed, Versionen, Prüfsumme), danach die Daten als JSON (zstd-komprimiert, abschaltbar). Geschrieben
  wird nach `.tmp`, die alte Datei wird zur Sicherung `.bak`, dann umbenannt; Codieren und Schreiben laufen im
  Hintergrund (`SaveManager`).
- **Inhalt** (`SaveGame`): Die Welt wird aus dem Seed neu erzeugt; gespeichert werden nur ihre Änderungen
  (`WorldData.changed_cells`, Strassen, nachwachsende Vorkommen) und ein Fingerabdruck der frischen Welt.
  Dazu alle Reiche (`Kingdom.to_dict` speichert jedes Feld ausser abgeleiteten und `_`-Feldern automatisch),
  Gebäude (`Building.to_dict`), Einheiten (`Unit.to_dict`, Verweise als uid, laufende Wege), alle Systeme,
  Uhr, Sitzung und das Meldungsprotokoll.
- **Typen** (`SaveCodec`): int/float, Vektoren, Farben, gepackte Arrays, Dictionaries mit Zahlen-Schlüsseln und
  64-Bit-Zahlen bleiben erhalten (`{"#v2": [x, y]}`, `{"#d": [[k, v]]}` …).
- **Schnittstelle jedes Systems**: `to_dict()` (nur einfache Werte, Kopien), `from_dict(d)` (nur Daten, keine
  Signale) und `rebuild_runtime()` (Zwischenspeicher und Wirkungen neu, idempotent). Register `SaveGame.SYSTEMS`
  (fehlende Systeme werden übersprungen; weitere Nodes unter *Systems* mit den drei Methoden werden automatisch
  mitgespeichert), Reihenfolge des Neuaufbaus `SaveGame.REBUILD_ORDER`.
- **Laden**: Kopf prüfen → Welt im Thread erzeugen, Fingerabdruck vergleichen, Änderungen anwenden, Wege
  berechnen → Reiche, Gebäude (ohne Signale), Gebiet, Einheiten, Verweise, Systeme (`from_dict`, dann
  `rebuild_runtime`), zuletzt Leben und Meldungen. Arbeiter suchen ihren Arbeitsschritt neu, Gruppenmärsche
  gehen einzeln weiter.
- **Regeln für neue Felder**: neues Feld → in `to_dict`/`from_dict` mit Standardwert (Kingdom: automatisch).
  Feld umbenannt oder umgedeutet → `SaveGame.SAVE_VERSION + 1` und ein Schritt in `SaveMigration.migrate`.
  Ergibt derselbe Seed eine andere Welt (Generator oder `worldgen.json`/`biomes.json` geändert) →
  `WorldGenerator.VERSION + 1` (alte Spielstände werden als nicht ladbar angezeigt). Geänderte Spieldaten sonst:
  nur ein gelber Hinweis in der Liste.
- **Schwierigkeit** (`Difficulty`, `data/difficulties.json`): Quelle `"difficulty"` auf KI-Reichen (Ertrag,
  Stärke, Tempo, Wachsamkeit) und den wilden Monstern (Stärke), Startressourcen des Spielers, Angriffslust der
  KI, Nachwuchs der Monsterlager; ab Phase 8 auch Streifzüge und Ereignisse. Beim Laden neu gesetzt.
- **Einstellungen** (`Settings`, `SettingsForm` im Haupt- und Spielmenü): Lautstärken (Busse Master, Music,
  SFX, UI), Kamera, Vollbild, Grösse der Oberfläche, Tag-Nacht-Abdunklung, automatisch speichern, Kompression.
- **UI-Grösse** (`UiStyle`): HUD, Spielmenü, Hilfe, Protokoll und Sieg/Niederlage sind als Ebenen angemeldet
  (`register_scaled_layer`: Ebene skaliert, Wurzel = Viewport / Faktor); die zentrierten Fenster platzieren sich
  mit `UiStyle.place_window` (Faktor, aber nie grösser als der Bildschirm), die Zauberleiste folgt der
  skalierten Minikarte. Die obere Leiste passt sich an (`hud._fit_top_bar`: Reichsname ausblenden, sonst
  verkleinern).

## Phase 10 testen

1. Neues Spiel, ein paar Minuten spielen, **F5**, ein Gebäude abreissen, **F8** → alles wie vorher (Gebäude im
   Bau, Warteschlangen, Sammelpunkte, Helden, Zauberzonen, Monsterlager).
2. **Esc → Speichern** mit Namen; noch einmal mit gleichem Namen → Rückfrage „überschreiben?“.
3. **Hauptmenü → Laden**: Liste mit Datum, Spielzeit, Fraktion, Schwierigkeit, Karte, Seed; Löschen mit
   Rückfrage; „Fortsetzen“ lädt den neuesten Spielstand. Unten rechts steht „Version 1.0.0“.
4. **Einstellungen**: Autospeichern 5 min → nach 5 min Hinweis „Automatisch gespeichert“ oben rechts,
   höchstens 3 Autospeicherstände.
5. Grösse der Oberfläche **125 %** und **150 %** → HUD, Zauberleiste, alle Fenster (Forschung, Helden,
   Diplomatie, Spionage, Reich, Flüchtlinge, Hilfe, Protokoll, Sieg/Niederlage) und Menüs werden grösser,
   Klicks treffen weiter. Die obere Leiste passt immer auf den Bildschirm: zuerst wird der Reichsname
   ausgeblendet (steht dann im Tooltip von „Reich“), reicht das nicht, wird die Leiste als Ganzes etwas
   verkleinert.
6. **F1** Hilfe (Steuerung, Spielablauf, Schwierigkeit), **M** Protokoll mit Klick zur Stelle.
7. Schwierigkeit *Leicht*: Monster schwächer (Auswahlfenster einer Höhle), mehr Startvorräte; *Episch*: frühe,
   grosse Wellen.
8. Eine Kaserne mit voller Warteschlange abreissen → Kosten zurück; wird sie von Feinden zerstört, ist der
   Einsatz verloren.
9. Jeder Knopf hat einen Tooltip (der Rauchtest prüft HUD, alle Fenster mit allen Reitern und das Spielmenü).
10. Rauchtest `tests/run_smoke.sh 1200` – enthält den Rundlauf Speichern → Laden in eine frische Szene →
   Vergleich → Weiterspielen (abschaltbar mit `p10=off`), die UI-Grössen-Prüfung und die Tooltip-Prüfung.
   Balancing: `tests/run_balance.sh` (siehe unten).

## Truppenfenster testen

1. Neues Spiel, Kaserne bauen und einige Kämpfer und Schützen beschwören (F3 → F9 gibt Rohstoffe).
2. **T** (oder Knopf „Truppen · 6“ oben neben „Helden“) → Fenster in der Mitte; ein offenes Forschungs-,
   Helden-, Diplomatie-, Spionage- oder Reichsfenster schliesst sich. **T** oder **Esc** schliesst es wieder.
3. Links je Einheitentyp eine Zeile mit Bild, Anzahl, Lebensbalken („gesamt / Höchstwert (Ø …)“) und
   „6 untätig · 2 unterwegs …“; darunter die Helden (Stufe, Zustand, Armee) und die Armeen mit Stärke, Ort
   („Eigenes Gebiet, 12 Kacheln östlich der Burg“) und Befehl. „Bewohner und König zeigen“ nimmt sie dazu.
4. **Strg+A** (oder „Alle Krieger auswählen“): alle Truppen und Helden sind ausgewählt, keine Bewohner, nicht
   der König. „Untätige“ / „Verwundete“ (unter 70 % Leben) wählen nur diese.
5. Einige Einheiten auswählen → rechts „Auswahl als Armee speichern“ **9** → Zeile „Armee 9“ erscheint (auch in
   der Armeeleiste); „Wählen“ macht sie zur Befehlsgruppe (Name hervorgehoben), „Hin“ springt hin, „✕“ löst sie auf.
6. **Angreifend vorrücken …** → Fenster schliesst, Mauszeiger wird zum Kreuz → Klick ins Gelände: die Gruppe
   marschiert und kämpft unterwegs (Esc bricht den Zielmodus ab). Ebenso **Bewegen …** (ohne zu kämpfen) und
   **Patrouille …** (läuft zwischen ihrem Ort und dem Ziel hin und her, blaue Zielmarke).
7. **Halten**, **Sammeln an der Burg** (Marsch in Formation zum Platz vor der Burg) und **Rückzug zur Burg**
   (läuft ohne zu kämpfen hin, Befehl „erholt sich an der Burg“: deutlich schnellere Heilung, `combat.json` → `rest`).
8. **Formation** Block / Linie / Keil / Kreis: gilt für die nächsten Marschbefehle (auch Taste F, reihum), die
   Befehlsgruppe stellt sich sofort an ihrem Ort so auf.
9. **Haltung passiv** → F3, Umschalt+F11 setzt einen Übungsgolem neben die Truppe: niemand greift an, auch
   nicht, wenn der Golem zuschlägt. **Verteidigend** → sie greifen an und kehren danach auf den Posten zurück;
   **aggressiv** → sie verfolgen ihn auch weit vom Posten weg. Angriffsbefehle (Rechtsklick auf einen Feind,
   angreifend vorrücken) gelten in jeder Haltung.
10. **F5** / **F8**: Haltung und Patrouille bleiben erhalten.
11. Rauchtest `tests/run_smoke.sh 900` enthält `tests/smoke_army.gd` (Fenster, Auswahl, Befehle über das Fenster,
   passiv/verteidigend gegen einen Golem, Speichern der Haltung, Fenstergrösse bei 100/150 %, Tooltips).

## Balancing

Gemessen mit `tests/run_balance.sh` (Modul `tests/balance_phase10.gd`, Aufruf `balance=1`): echte KI, Spieler
tut nichts (passiv), Karte *medium*, 2 KI-Reiche, 3 Spielstunden (10 800 s = 18 Spieltage) je Fraktion und
Schwierigkeit, ohne Fenster im Zeitraffer. Alle `sample=` Spielsekunden eine Zeile je Reich, am Ende
Ergebnis, Leistung und die Grösse aller Listen der Systeme (`[balance] LISTEN …`).

Ergebnisse (Stand 1.0, Seed 12345; „unverwundbar“ = `immortal=1`, Burg und König des passiven Spielers
werden geheilt, damit der Lauf die vollen 3 Stunden geht):

| Lauf | Erste Welle gegen den Spieler | Wellen in 3 h | Passiver Spieler fällt | Ereignisse beim Spieler (alle Reiche) | KI nach 3 h (Gebäude / Einheiten / Armee) | Ø Zufriedenheit KI |
|---|---|---|---|---|---|---|
| Normal, GUT, medium | 72 min | 3 | nach 101 min | 2 (5), erstes nach 29 min | 149 / 200 / 38 | 72–82 |
| Normal, BÖSE, medium | 71 min | 5–8 | nach 100 min | 2 (5), erstes nach 29 min | 136 / 164 / 38 | 81–83 |
| Schwer, GUT, medium | 61 min | – | nach 65 min | 1 (2) in 65 min | 61 / 119 / 23 (bei 65 min) | 78 |
| Schwer, BÖSE, medium | 54 min | – | nach 64 min | 1 (2) in 64 min | 58 / 118 / 23 (bei 64 min) | 88 |
| Schwer, GUT, large (unverwundbar) | 63 min | 10 (12 → 24 Einheiten) | – | 3 (7), erstes nach 23 min | 51–82 / 140–195 / 50 | 71–76 |

- Die KI wächst über die ganze Zeit (Armee-Soll bis 32 Spielstunden, höchstens 90 je Reich), greift den
  Spieler frühestens nach `first_attack_minutes` und erst nach Kundschaft an; Wellen kommen danach etwa alle
  `wave_interval` und werden je Welle um 3 Einheiten grösser.
- Ereignisse bleiben selten (2–3 beim Spieler in 3 Stunden, frühestens nach 20 min); Monster wachsen bis etwa
  zum Doppelten des Starts (medium 52 → 98, large 198 → 371) und bleiben dort.
- Zufriedenheit: KI-Reiche 70–90; ein passiver Spieler ohne Häuser und Nahrung sinkt auf 25–45 (Überläufer 2–9
  in 3 h) – so gewollt.
- Leistung (ohne Fenster, eine Partie je Kern): Simulationsschritt Ø 5,1 ms (medium, 580 Einheiten) bzw.
  6,4 ms (large, 860 Einheiten), bei 10 Schritten je Spielsekunde also 5–6 % eines Kerns bei 1x;
  KI-Denkzeit Ø 2,8–3,6 ms je Denkvorgang (ein Reich alle paar Sekunden). Grösste Posten: Kampf, Arbeit,
  Monster.
- Listen über lange Partien: Meldungsprotokoll höchstens 300, Ereignisverlauf 20, Ruf-Verlauf 8 je Dorf;
  alle übrigen Laufzeit-Listen hängen an lebenden Einheiten/Gebäuden und werden mit ihnen aufgeräumt
  (`[balance] LISTEN gewachsen` meldet nur das Protokoll bis zu seiner Grenze).
- Phase-10-Anpassungen: `ai.json` → `difficulty.*.patience_minutes` (neu, vorher fest 120 min: ein stiller
  Spieler wurde auf Normal erst nach etwa 140 min angegriffen), `army.size_by_minute` bis 1920 min und
  `army.max_units`; im Code ein Zwischenspeicher für erfolglose Vorkommen-Suchen (Arbeit 4–6 ms → 1,4 ms je
  Schritt in späten Partien).

**Selbst nachjustieren** (nur Daten, kein Code):

| Was | Datei → Schlüssel |
|---|---|
| Wie früh/hart die KI angreift | `ai.json` → `difficulty.<stufe>`: `first_attack_minutes`, `patience_minutes`, `wave_interval`, `first_wave_max`, `army_size_mult` |
| Wachstum der KI-Armee über lange Partien | `ai.json` → `army.size_by_minute` (bis 32 h), `army.max_units` |
| Wie schnell die KI den Spieler bemerkt | `espionage.json` → `awareness` (`rise_per_minute`, `rumour`, `discovered`, `patience_floor`) |
| Stärke/Ertrag der Gegner, Startvorräte | `difficulties.json` |
| Häufigkeit der Ereignisse | `events.json` (`chance`, Abstände, Abklingzeiten) |
| Monsterstreifzüge, Wachstum der Lager | `combat.json` (`raids`, `lair_growth`) |
| Zufriedenheit, Überläufer | `satisfaction.json` |
| Wirtschaft (Ertrag, Verbrauch) | `economy.json`, `buildings.json` |

## Exportieren

1. Im Editor **Editor → Export-Vorlagen verwalten** → Vorlagen für die eigene Godot-Version (z. B. 4.4.1)
   herunterladen.
2. `export_presets.cfg` liegt im Projekt (ohne Zugangsdaten): „Windows Desktop“ und „Linux“, je 64 Bit,
   PCK eingebettet, `include_filter="data/*.json"` (die Spieldaten), `exclude_filter="tests/*"`.
3. Einmal importieren, dann exportieren:
   ```
   godot --headless --import
   godot --headless --export-release "Windows Desktop" build/windows/Koenigreiche.exe
   godot --headless --export-release "Linux" build/linux/koenigreiche.x86_64
   ```
   Ohne Vorlagen lässt sich nur das Datenpaket bauen: `godot --headless --export-pack "Linux" build/koenigreiche.pck`
   (Start: `godot --main-pack build/koenigreiche.pck`).
4. Spielstände und Einstellungen liegen ausserhalb des Programmordners: Windows `%APPDATA%\Koenigreiche`,
   Linux `~/.local/share/Koenigreiche` (siehe „Speichern und Laden“). Eigene Grafiken (`assets/…`, siehe
   `assets_liste.md`) vor dem Export ins Projekt legen.

## Grafiken austauschen

Alle Grafiken sind zunächst automatisch erzeugte Platzhalter. Legt man eine PNG-Datei
mit dem in **`assets_liste.md`** genannten Namen in den passenden Ordner, wird sie
beim nächsten Start automatisch verwendet – ohne Code-Änderung.

## Entwicklungsstand

- [x] Phase 1 – Projekt-Setup, Kamera, prozedurale Karte mit Biomen, Spieltempo und Pause
- [x] Phase 2 – Dorf: Gebäude, Ressourcen, Bewohner, Arbeitsverteilung
- [x] Phase 3 – Einheiten: Beschwören, Auswahl, Bewegung, Kampf, Armeen
- [x] Phase 4 – Forschung, Mana und Magie
- [x] Phase 5 – Helden
- [x] Phase 6 – Neutrale Dörfer, Diplomatie, Handel, Ruf, Boten
- [x] Phase 7 – Gegnerische Königreiche mit KI, Entdeckung, Spionage
- [x] Phase 8 – Zufriedenheit, Verrat, Flüchtlinge, Ereignisse, Monster, Tag/Nacht
- [x] Phase 9 – Belagerungen und Handelswege
- [x] Phase 10 – Speichern/Laden, Schwierigkeitsgrade, UI-Feinschliff, Balancing
- [x] Truppenfenster – Übersicht und Befehle für alle Krieger, Haltung, Patrouille, Rückzug, Formationen Keil/Kreis
