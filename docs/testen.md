# Testen

Automatische Prüfungen (ohne Fenster, auch in GitHub Actions) und Checklisten zum Testen von Hand, Schritt für
Schritt je Ausbaustufe.

## Inhalt

1. [Automatische Prüfungen](#automatische-prüfungen)
   - [Skriptprüfung](#skriptprüfung-check_scriptssh)
   - [Rauchtest](#rauchtest-run_smokesh)
   - [Tutorial-Rauchtest](#tutorial-rauchtest)
   - [Bildschirmfotos](#bildschirmfotos-ui_shots)
   - [Balancing-Läufe](#balancing-läufe-run_balancesh)
   - [Alle Argumente des Rauchtests](#alle-argumente-des-rauchtests)
   - [GitHub Actions](#github-actions)
   - [Tabellen der Anleitung](#tabellen-der-anleitung)
2. [Von Hand testen](#von-hand-testen)
   - [Phase 2 – Dorf und Wirtschaft](#phase-2--dorf-und-wirtschaft)
   - [Phase 3 – Einheiten und Kampf](#phase-3--einheiten-und-kampf)
   - [Phase 4 – Forschung und Magie](#phase-4--forschung-und-magie)
   - [Phase 5 – Helden](#phase-5--helden)
   - [Phase 6 – Neutrale Dörfer und Diplomatie](#phase-6--neutrale-dörfer-und-diplomatie)
   - [Phase 7 – Gegner, Entdeckung und Spionage](#phase-7--gegner-entdeckung-und-spionage)
   - [Phase 8 – Völker, Tag/Nacht, Zufriedenheit, Ereignisse](#phase-8--völker-tagnacht-zufriedenheit-ereignisse)
   - [Phase 9 – Belagerung und Handelswege](#phase-9--belagerung-und-handelswege)
   - [Phase 10 – Speichern, Schwierigkeit, Oberfläche](#phase-10--speichern-schwierigkeit-oberfläche)
   - [Truppen – Klassen, Schmiede, Ränge, Aussehen](#truppen--klassen-schmiede-ränge-aussehen)
   - [Armeefenster](#armeefenster)
   - [Tutorial](#tutorial)

---

## Automatische Prüfungen

Alle Skripte liegen in `tests/` und werden im Projektordner aufgerufen. `GODOT` zeigt auf die Godot-Programmdatei
(4.4 oder neuer, Standard-Version). Unter Linux z. B.:

```bash
export GODOT=/pfad/zu/Godot_v4.4.1-stable_linux.x86_64
$GODOT --headless --editor --quit        # einmal: Projekt importieren (legt .godot/ an)
tests/check_scripts.sh                   # Skripte prüfen
tests/run_smoke.sh 600                   # Rauchtest beider Fraktionen
```

Spielstände der Tests landen im Benutzerordner von Godot. Wer den eigenen Ordner sauber halten will, setzt vorher
`XDG_DATA_HOME` auf einen leeren Ordner (so macht es auch GitHub Actions).

### Skriptprüfung (`check_scripts.sh`)

```bash
GODOT=/pfad/zu/godot tests/check_scripts.sh
```

Lädt alle GDScript-Dateien (`tests/load_all.tscn`) und behandelt dabei **alle Warnungen als Fehler** (über eine
vorübergehende `override.cfg`, die am Ende wieder gelöscht wird). Fehlt der Ordner `.godot/` oder hat ein Skript noch
keine `.uid`-Datei, läuft vorher einmal der Editor ohne Fenster (Import, Klassen-Zwischenspeicher, `.uid`-Dateien).
Ausgabe am Ende: `OK: keine Fehler oder Warnungen`, sonst Rückgabewert 1.

### Rauchtest (`run_smoke.sh`)

```bash
GODOT=/pfad/zu/godot tests/run_smoke.sh 600 [weitere key=value]
```

Startet für **GUT und BÖSE** je eine Partie ohne Fenster (`tests/smoke_test.tscn`) und lässt sie im Zeitraffer laufen
(erste Zahl = Spielsekunden). Schlägt fehl bei jedem `SCRIPT ERROR`, jeder `ERROR:`-Zeile und jedem nicht erfüllten
Prüfpunkt. Geprüft werden unter anderem:

- **Helden** (in `smoke_test.gd`): Anwerben, Fähigkeiten mit Zielmodus, Tod und Wiederbelebung.
- **Phase 6** (`smoke_phase6.gd`): Dörfer, Ruf, Geschenke, Verträge, Handel, Aufnahme, Krieg, Boten, KI-Verträge.
- **Phase 7** (`smoke_phase7.gd`): KI-Reiche, Entdeckung, Spione, Wellen, Niederlage eines KI-Reichs, Sieg.
- **Phase 8** (`smoke_phase8.gd`): Völker, Tag/Nacht, Zufriedenheit, Überläufer, Verrat, Ereignisse, Monster.
- **Phase 9** (`smoke_phase9.gd`): Mauern, Tore, Türme, Belagerungswaffen, Handelswege, Versorgung.
- **Phase 10** (`smoke_phase10.gd`): Speichern → Laden in eine frische Szene → Vergleich → Weiterspielen
  (Rundlauf), UI-Grösse, Tooltips aller Knöpfe und Fenster.
- **Armeefenster** (`smoke_army.gd`): Fenster, Auswahl, Befehle über das Fenster, passiv/verteidigend gegen einen
  Golem, Speichern der Haltung, Fenstergrösse bei 100/150 %, Tooltips.
- **Truppen** (`smoke_troops.gd`): jede neue Truppe beschwören, Konter, Schmiede, Rang und Wertepunkte, Aussehen und
  dessen Erhalt im Speichern-Laden-Rundlauf.
- **Spione** (`smoke_spies.gd`, eigene Szene `smoke_spies.tscn`): zu Spielbeginn hat kein Reich Spione; ein im
  Spionagefenster beschworener Spion existiert genau einmal (Einheit, Datensatz, Liste, Fenster), auch mit Auftrag
  und nach Speichern und Laden. Spionagebericht: ohne Kundschaft „unbekannt“, ein Spion der höchsten Stufe liefert
  Truppen, Türme, Gesamtstärke, Burgstufe und Bewohner genau wie im Spielzustand (Fenster und Protokoll).
- **Neue Funktionen** (`smoke_features.gd`, eigene Szene `smoke_features.tscn`, ein Modul je Thema, einzeln mit
  `only=<Thema>`): **Stärke** (`smoke_strength.gd`) – bei gleichem Heer steigt der Ruf beim freundlichen Dorf, beim
  neutralen nicht, beim misstrauischen sinkt er leicht; eine Drohung senkt ihn weiterhin.
- **Dörfer** (`smoke_villages.gd`, Modul in `smoke_features.gd`): neue Dörfer mit 4–7 Hütten, KI-Reiche mit
  Startvorsprung, 30 Minuten Frieden lassen ein Dorf wachsen (Hütten, Bewohner, Milizplätze, Turm), Krieg hält es an,
  Grösse und Hütten überstehen Speichern und Laden.
- **Helden** (`smoke_new_heroes.gd`, Modul in `smoke_features.gd`): fünf Helden je Fraktion mit ✓/✗ im Heldenfenster;
  die zwei neuen Helden der Fraktion lassen sich anwerben, haben eine eigene Figur, und jede Fähigkeit wirkt
  (Reichs-Zuschlag, Aura, Wirkung auf Freund oder Feind, Beschwörung).
- **Handel** (`smoke_trade.gd`, Modul in `smoke_features.gd`): Holzpreis im holzreichen Dorf billiger als im
  holzarmen (auch beim Tausch), Preise im Diplomatiefenster; Handelsroute mit Menge und Abstand einstellen, unerlaubte
  Werte abgelehnt, Fluss je Minute im Reiter Handelswege; die Karawane liefert ohne Klicken, der Ruf steigt;
  Einstellung und Route überstehen Speichern und Laden.
- **Bündnis** (`smoke_alliance.gd`, Modul in `smoke_features.gd`): beim Nicht-Verbündeten gesperrt mit Grund (auch in
  der Dorfliste des Armeefensters); fünf Krieger beim verbündeten Dorf stationiert, angekommen, zählen zur
  Verteidigung; Speichern und Laden; Ruf steigt, Abgabe kommt an; Angreifer am Dorf werden angegriffen;
  Zurückrufen; Hilferuf ablehnen kostet Ruf; Kündigung zieht die Truppen ab; die KI stationiert ebenfalls.
- **Entdeckung** (`smoke_discovery.gd`, Modul in `smoke_features.gd`): Abstufung nach Schwierigkeit (Faktor steigt,
  Wartezeit sinkt von leicht bis episch), Schwellen (Wartezeit hält über der Gerüchte-Schwelle), Anstieg
  in einer Minute höchstens `rise_per_minute` (ohne Sprünge), ein Angriff entdeckt den Angreifer sofort.
- **Welt** (`smoke_world_compat.gd`, Modul in `smoke_features.gd`): derselbe Seed ergibt dieselbe Welt wie in 1.1.0
  (Fingerabdruck von Biomen, Vorkommen, Plätzen und Start). Sonst laden alte Spielstände nicht mehr. Ändert sich die
  Welt absichtlich, `WorldGenerator.VERSION` erhöhen und die Werte im Test erneuern.
- **Bewerber** (`smoke_recruits.gd`): langsames Wachstum, Taverne verkürzt die Wartezeit, Bewerber mit Bedingungen,
  Aufnehmen im Bewerberfenster gesperrt und wieder frei, Bewohner +1, Geschenk, Fachkraft schneller, Abweisen,
  wartender Bewerber im Speichern-Laden-Rundlauf. `recruits=off` schaltet die Bewerber ab (Balancing: das
  natürliche Wachstum allein reicht für Burgstufe 2).
- **Ausbaustufen** (`smoke_levels.gd`): Ausbau gesperrt ohne Rohstoffe, Ausbau beginnen und abbrechen, Bauarbeiter
  bauen Hof und Haus aus, Werte steigen (Nahrung, Wohnraum, Leben), Abriss erstattet Ausbauten anteilig, Spielstand
  ohne Stufe lädt auf Stufe I, Stufen bleiben im Speichern-Laden-Rundlauf erhalten.
- Ohne `tutorial=1`: das Tutorial ist aus und schützt nicht.

> **Mindestens 600 Spielsekunden.** Mit weniger (z. B. 300) wird der Phase-7-Test nicht fertig und meldet
> „Phase-7-Test nicht fertig geworden“. 600 Sekunden dauern auf einem normalen Rechner etwa anderthalb Minuten für
> beide Fraktionen; 900 oder 1200 prüfen gründlicher.

### Tutorial-Rauchtest

```bash
GODOT=/pfad/zu/godot tests/run_smoke.sh 900 tutorial=1
```

Startet je Fraktion eine Tutorial-Partie und spielt alle 37 Schritte über dieselben Schnittstellen wie die
Oberfläche durch (Gebäude setzen, Berufe, Beschwören, Befehle, Forschung, Zauber, Helden, Armeefenster, Haltung,
Schmiede, Wertepunkte, Fenster, Geschenk, Schnellspeichern, Hilfe; `smoke_tutorial.gd`). Geprüft werden: „Weiter“ ist
vor der Aufgabe gesperrt, jede Bedingung wird erfüllt, Rahmen und Pfeil finden ihr Ziel, Geschenke, der Schutz
(Ereignis- und Wellenziele), Laden des Spielstands aus dem Schritt „Speichern“, Beenden und Fortsetzen über das
Spielmenü.

### Bildschirmfotos (`ui_shots`)

Braucht ein echtes Fenster – unter Linux ohne Bildschirm mit `xvfb-run`:

```bash
XDG_DATA_HOME=/tmp/kr-data xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --rendering-driver opengl3 \
  --resolution 1920x1080 res://tests/smoke_test.tscn -- ui_shots=1 shots=/tmp/shots win=1920x1080 faction=good
```

`tests/ui_shots.gd` baut ein kleines Reich auf (Kaserne, Schmiede, Reitstall, Magierturm, Heldenhalle, je Truppentyp
ein paar Einheiten mit Rängen, ein Held) und fotografiert nacheinander: leere Oberfläche, Kaserne, Schmiede, einzelne
Truppe, gemischte Gruppe, Held und alle Fenster (Forschung, Helden, Diplomatie, Spionage, Reich, Armee, Hilfe,
Speichern), danach je eine Figur jedes Einheitentyps (`15_figuren`) und über 300 zusätzliche Truppen auf einmal
(`16_viele_einheiten`, mit gemessener Bildzeit `[smoke] Figuren: … ms je Bild`). Dateien: `<fraktion>_<win>_<ui_scale>_<nr>_<name>.png`. Mit `ui_scale=1.25` bzw. `1.5` lässt sich die
Oberflächengrösse prüfen. Die Bilder in `docs/bilder/` sind so entstanden (auf 1280 px verkleinert, JPEG).

Auch die übrigen Rauchtests fotografieren mit `shots=<ordner>` an wichtigen Stellen, wenn ein Fenster da ist.

### Balancing-Läufe (`run_balance.sh`)

```bash
GODOT=/pfad/zu/godot tests/run_balance.sh [ausgabeordner] [Spielsekunden] [Karte]
```

Echte KI, passiver Spieler, ohne Fenster im Zeitraffer (`balance=1`, Modul `tests/balance_phase10.gd`). Standard: 3
Spielstunden (10 800 s), Karte *medium*, GUT/BÖSE × Normal/Schwer, parallel (`JOBS`, Standard 3), Ausgabe nach
`build/balance`. Umgebung: `DIFFS` („normal hard“), `TIME_SCALE` (4; höher verwirft Schritte), `IMMORTAL=1` (Burg und
König des Spielers unverwundbar: Lauf über die volle Dauer, wiederholte Wellen), `DISCOVERED=1` (die KI kennt den
Spieler von Anfang an wie einen aktiven Spieler; die erste Welle hängt dann nur an `first_attack_minutes`).
Ergebnisse: [Balancing](balancing.md).

Feste Prüfungen (Zeilen `[balance] PRÜFUNG OK/FEHLER`, ein Fehler lässt den Lauf scheitern): nach 10 Spielminuten hat
kein KI-Reich Gebäude ab Burgstufe 3, nach 30 Minuten hat mindestens eines ein ausgebautes Gebäude, nach 40 Minuten
mindestens eines Burgstufe 3 und jedes mindestens doppelt so viele Bewohner wie zu Beginn, nach 60 Minuten hat
mindestens eines einen Helden angeworben. Mit `recruits=off` (ohne
Bewerber, direkt über `smoke_test.tscn`) prüft der Lauf stattdessen, dass das natürliche Wachstum allein für
Burgstufe 2 reicht. Je Probe gibt der Lauf ausserdem die Gebäude je Typ und die Berufe jedes KI-Reichs aus.

### Alle Argumente des Rauchtests

Argumente stehen nach `--` (bei `run_smoke.sh` einfach hinten anhängen):

| Argument | Bedeutung |
|---|---|
| `faction=good` / `evil` | Fraktion (run_smoke.sh macht beide) |
| `seconds=600` | Spielsekunden (run_smoke.sh: erste Zahl) |
| `difficulty=normal` | Schwierigkeit (`easy`, `normal`, `hard`, `epic`) |
| `size=small` | Kartengrösse (`small`, `medium`, `large`) |
| `seed=12345` | Seed |
| `people=<id>` | bestimmtes Volk, z. B. `people=orcs` |
| `ai=2` | Anzahl KI-Reiche (statt nach Schwierigkeit) |
| `passive=1` | der Spieler tut nichts (nur der Bericht über die KI) |
| `p7=natural`, `p8=natural` | Phase 7/8 ohne Debug-Abkürzungen, mit echter KI über lange Zeit |
| `p10=off` | Speichern-Laden-Rundlauf auslassen |
| `ui_scale=1.25` | Grösse der Oberfläche |
| `time_scale=8` | Zeitraffer der Engine |
| `tutorial=1` | Tutorial-Rauchtest |
| `ui_shots=1`, `shots=<ordner>`, `win=1920x1080` | Bildschirmfotos (nur mit Fenster) |
| `balance=1`, `immortal=1`, `discovered=1` | Balancing-Lauf |

Beispiel – lange Partie mit echter KI: `$GODOT --headless res://tests/smoke_test.tscn -- faction=evil seconds=3600
p7=natural size=medium` (der Bericht zeigt Zeitleiste, Wellen und Denkzeit der KI); ein bestimmtes Volk mit
`people=<id>`, Phase 8 lang mit `p8=natural seconds=3600 size=medium`.

### GitHub Actions

`.github/workflows/tests.yml` läuft bei jedem Push und Pull Request:

1. Godot 4.4.1 (Linux, Standard-Version) herunterladen – zwischengespeichert, also nur beim ersten Lauf.
2. Projekt importieren: `godot --headless --editor --quit`.
3. `tests/check_scripts.sh`.
4. `tests/run_smoke.sh 600`.

`XDG_DATA_HOME` zeigt dabei auf einen Ordner im Temp-Verzeichnis des Runners. Das Ergebnis steht im Reiter
**Actions** des Repositorys und als Abzeichen oben in der README.

### Tabellen der Anleitung

```bash
python3 tools/doku_tabellen.py           # Tabellen in docs/spielanleitung.md aus data/*.json erneuern
python3 tools/doku_tabellen.py --check   # nur prüfen (Rückgabe 1 = veraltet)
```

---

## Von Hand testen

Schritt für Schritt je Ausbaustufe; die automatischen Prüfungen decken dasselbe ab. Fast überall hilft die
**Debug-Anzeige (F3)**: dann gibt F9 +100 jeder Ressource, F10 kostet den König 150 Leben, F11 setzt 3 Wölfe an die
Maus, Umschalt+F11 einen Übungsgolem, Strg+F11 einen feindlichen Rammbock, F12 gibt dem ausgewählten Helden eine
Stufe (siehe [Steuerung](steuerung.md#testhilfen-debug)).

### Phase 2 – Dorf und Wirtschaft

1. Neues Spiel starten. Die Burg steht im eigenen Gebiet (farbige Grenze), 5 Bewohner laufen los: 2 Holzfäller,
   1 Sammler, 2 Bauarbeiter (siehe Arbeitsverteilung links, Taste J).
2. Oben steigen Holz und Nahrung langsam an (der Tooltip über der Zahl zeigt den Ertrag pro Minute).
3. **Wohnhaus** im Baumenü wählen, im Gebiet platzieren → Baustelle, die Bauarbeiter bauen sie. Danach steigt
   „Bewohner P/H“ um 4 Wohnplätze, das Gebiet wächst etwas.
4. Nach etwa drei Minuten wartet ein **Bewerber** am Gebietsrand (Meldung anklicken): das Bewerberfenster zeigt
   seine Bedingungen mit ✓/✗, „Aufnehmen“ geht erst, wenn alle erfüllt sind; er arbeitet dann gleich im Wunschberuf.
   Von selbst kommt nur etwa alle 4 Minuten ein Bewohner (Wohnraum frei, ≥ 30 Nahrung, Zufriedenheit ≥ 50); er ist
   *unbeschäftigt* – in der Arbeitsverteilung mit „+“ einem Beruf zuweisen.
5. **Strasse** wählen und mit gedrückter Maustaste ziehen → Bauarbeiter legen sie an; Bewohner laufen darauf
   schneller und nutzen sie für ihre Wege.
6. **Holzfällerhütte** nahe an Bäumen bauen → Holzfäller liefern dort ab (kürzere Wege, +25 %). Die Auswahl der Hütte
   zeigt „Liefern hier an: N“.
7. **Bauernhof** bauen, in der Arbeitsverteilung Bauern zuweisen → dauerhaft Nahrung.
8. **Manabrunnen** auf einer Manaquelle (violett leuchtend) bauen, Manawirker zuweisen → Mana steigt.
9. Alle Sammler auf „−“ setzen → nach einigen Minuten *Hungersnot* (Meldung, Nahrung rot, Arbeit halb so schnell).
   Sammler wieder einsetzen → die Hungersnot endet.
10. Mit X oder „Abreissen“ Strassen entfernen; ein Gebäude auswählen → „Abreissen“ (zweimal klicken).

### Phase 3 – Einheiten und Kampf

1. Neues Spiel. Vor der Burg steht der **König** (Krone). Er verteidigt die Burg, verlässt aber nie das eigene Gebiet.
   Auf der Minikarte sind **Monsterlager** orange markiert; zwei kleine Übungslager liegen 30–45 Kacheln vom Start.
2. **Burg anklicken** → im Auswahlfenster „Späher“ beschwören (Kosten auf dem Knopf, Dauer im Tooltip). Nach
   8 Sekunden erscheint er vor der Burg. Mehrfach klicken = Warteschlange (max. 5); Klick auf ein Symbol in der
   Warteschlange bricht ab (Kosten zurück).
3. **Kaserne** bauen (braucht Mana: Manabrunnen + Manawirker). Fertig auswählen → Schwertkämpfer, Bogenschützen
   beschwören; Ritter erst nach der Forschung *Ritterorden*. Mit Rechtsklick in die Welt einen **Sammelpunkt** setzen.
4. Truppen mit gedrückter linker Maustaste **einrahmen** (Bewohner werden dabei nicht mitgenommen). **Rechtsklick**
   ins Gelände: sie marschieren in Formation (F wechselt Block/Linie/Keil/Kreis).
5. **Strg+1** speichert die Auswahl als Armee 1 (Leiste über dem Auswahlfenster), **1** wählt sie, zweimal **1**
   springt mit der Kamera hin.
6. Armee auswählen, **Rechtsklick auf eine Monsterhöhle** oder ein Monster → Angriff. Bogenschützen schiessen Pfeile,
   Treffer blitzen auf, Gefallene verblassen. Eine zerstörte Höhle gibt Beute und **Kampfpunkte** (gekreuzte Schwerter
   oben neben Mana). Bewohner sammeln nicht in der Nähe von Höhlen.
7. Verletzte erholen sich nach 5 Sekunden ohne Kampf; **Krankenstation** (heilt in der Nähe, nach der Forschung
   *Heilkunde*: Bibliothek bauen, R, Magie Stufe 1) und **Heiler** heilen schneller.
8. Wird ein Bewohner angegriffen, flieht er zur Burg und arbeitet danach weiter. Ein Späher, der als Holzfäller
   arbeitet, wehrt sich und arbeitet danach weiter. Beschworene Einheiten brauchen zum Arbeiten Wohnraum.
9. Spielende testen: F3 und dann mehrmals F10 → der König verliert Leben, flieht verletzt in die Burg; stirbt er,
   erscheint „Der König ist gefallen“ mit „Neu starten (gleiche Karte)“.

### Phase 4 – Forschung und Magie

Tipp: F3, dann gibt F9 Ressourcen und F11 setzt 3 Wölfe an die Maus – so lassen sich Flüche, Nebel, Tarnung und
Heilung auch im eigenen Gebiet ausprobieren. Monster folgen bis 12 Felder von ihrer Höhle; man kann sie also auch an
die Grenze locken.

1. Neues Spiel. **Bibliothek** bauen (GUT; BÖSE: *Dunkles Archiv*, 40 Holz, 80 Stein, 10 Mana). **R** oder der Knopf
   „Forschung“ oben öffnet den Forschungsbaum: vier Zweige (Militär, Magie, Wirtschaft, Mana), Stufen 1–4. Ohne
   Bibliothek steht im Fenster, was zu bauen ist.
2. **Heilkunde** (Magie, Stufe 1) anklicken: die Kosten werden bezahlt, oben laufen Fortschritt und Restzeit, der
   Knopf zeigt „Forschung · 45 %“. Bis zu 3 Forschungen einreihen; Klick auf eine laufende oder eingereihte bricht sie
   ab (zweiter Klick bestätigt, volle Erstattung). Ist die Bibliothek untätig, zeigt der Knopf gelb „Forschung ruht“.
   Eine zweite Bibliothek forscht 25 % schneller.
3. Nach *Heilkunde*: die **Krankenstation** ist baubar (vorher grau, Tooltip „Benötigt Forschung: Heilkunde“) und der
   Zauber *Heilendes Licht* ist in der Zauberleiste frei. Nach *Ritterorden* (Militär 2): Ritter in der Kaserne.
   Wirkungen wie „+10 % Angriff“ zeigt der Tooltip der Werte im Auswahlfenster („Angriff 12 → 13,2 (Waffenschmiede
   +10 %)“).
4. **Mana**: Maximum 100 („80/100“ oben; voll = gelb, Überschuss geht verloren). **Kampfpunkte** (gekreuzte Schwerter
   oben, ein Klick öffnet sie) gibt es für besiegte Monster und zerstörte Höhlen. Im Forschungsfenster, Reiter
   „Kampfpunkte“: *Manakristall* (+40 Maximum je Stufe) und *Manaherz* (die Burg erzeugt Mana). Ist eine Verbesserung
   bezahlbar, kommt einmal eine Meldung und der Forschungs-Knopf bekommt einen Punkt.
5. **Zaubern** (nur der König; stirbt er, ist das Spiel verloren): Zauber in der Leiste anklicken – gesperrte zeigen,
   welche Forschung fehlt. Der Kreis folgt der Maus; erlaubt ist das eigene Gebiet und 16 Felder darum (leicht
   eingefärbt). Neben der Maus steht, wie viele Einheiten getroffen werden. Linksklick zaubert (Mana und
   Abklingzeit), Rechtsklick/Esc bricht ab. Ein Kreis, der niemanden trifft, wird abgelehnt – es geht kein Mana
   verloren.
6. **GUT** (Licht, gold/weiss): *Lichtsegen* auf eigene Truppen (+25 % Angriff, mehr Rüstung; im Auswahlfenster
   „Lichtsegen · 24 s“), *Heilendes Licht*, *Lichtschleier* (Truppen werden durchsichtig, Monster lassen von ihnen
   ab, sie greifen selbst nicht an – erst ein Angriffsbefehl oder Angriff-Vorrücken hebt die Tarnung auf; kostet
   0,5 Mana/s), *Segensregen* über Höfen und Holzfällern (+50 % Nahrung und Holz), *Ruf des Lichts* (3 Lichtgeister
   für 60 Sekunden).
7. **BÖSE** (dunkel violett, Flüche): *Fluch der Schwäche* auf Monster (schwächer, schlechter geschützt), *Dunkle
   Erneuerung*, *Schattenmantel*, *Finsterer Nebel* (Feinde werden langsam und verlieren Ziele, die mehr als 2 Felder
   entfernt sind – damit entkommt man), *Schattenbrut*.
8. Forschung *Manafokus* (Mana 2) senkt alle Zauberkosten um 20 %, *Zauberfluss* (Mana 3) die Abklingzeiten um 25 %,
   *Weitreichende Magie* / *Lange Schatten* (Magie 2) erweitert die Reichweite um 8 Felder. Die Werte im Tooltip der
   Zauberleiste ändern sich entsprechend.

### Phase 5 – Helden

Tipp: F3 einschalten. F9 gibt Ressourcen, F12 gibt dem ausgewählten Helden eine Stufe, F11 setzt Wölfe und
Umschalt+F11 einen Übungsgolem (viel Leben, Rüstung) an die Maus. Im Heldenfenster erscheinen im F3-Modus zusätzlich
Knöpfe „+1 Stufe“, „Abklingzeiten“, „Sofort wiederbeleben“ und „Held fällt“.

1. Kaserne bauen, dann die **Heldenhalle** (BÖSE: *Halle der Schatten*; braucht eine Kaserne, nur eine pro Reich).
   **G** oder der Knopf „Helden“ oben öffnet das Heldenfenster, Reiter „Anwerben“ (oder die Halle anklicken →
   „Helden anwerben“ im Auswahlfenster): drei Helden je Fraktion (GUT: Paladin, Sternenmagierin, Waldläuferin –
   BÖSE: Nekromant, Kriegsherr, Klingentänzerin).
2. Einen Helden anwerben (Nahrung, Erz, Mana; jeder weitere Held kostet mehr). Nach 30 Sekunden erscheint er an der
   Halle, mit eigenem Namen. Jeden Typ gibt es einmal, höchstens drei Helden.
3. Der Held erscheint in der **Heldenleiste** links. Auswählen → im Auswahlfenster Stufe, Erfahrung (EP) und seine
   Fähigkeiten. **C / V / B** wirken sie (Feind oder Stelle anklicken; ist das Ziel zu weit weg, läuft der Held hin).
   Das geht auch, wenn er mit seiner Armee zusammen ausgewählt ist (Tab wechselt den Helden). Rechtsklick auf einen
   Fähigkeitsknopf schaltet „selbst auslösen“ (goldener Rahmen) um.
4. Helden sind **Generäle**: eigene Truppen in ihrer Nähe schlagen härter zu (Führung), dazu hat jeder Held eine
   eigene Führungseigenschaft. Marschiert eine Armee mit Held, führt der Held sie an.
5. **Erfahrung**: besiegte Feinde in der Nähe (mehrere Helden teilen sich nicht alles: jeder bekommt einen Anteil),
   zerstörte Höhlen zählen 1,5-fach, dazu **Ausbildung** in der Halle (Nahrung, Holz, Stein; bis Stufe 5, mit der
   Forschung *Heldenlehre* bis 7). Bei jedem Stufenaufstieg wählst du eine von zwei Verbesserungen: eine
   Fähigkeitsstufe (I–III) oder ein Talent des Helden.
6. **Tod**: fällt ein Held, kann er nach 60 Sekunden in der Burg wiederbelebt werden (Burg anklicken, Heldenleiste
   oder Heldenfenster) – gegen Kosten, mit gleicher Stufe, und er ist wieder in seiner Armee.
7. Fähigkeiten zum Ausprobieren (gegen F11-Wölfe oder den Umschalt+F11-Golem):
   GUT – *Lichtschlag*, *Heilige Aura*, *Göttlicher Schild* (Paladin); *Sternenfeuer*, *Sternensprung*,
   *Sternenquelle* (mehr Mana, Sternenmagierin); *Pfeilhagel*, *Schlachtruf*, *Adlerauge* (Waldläuferin).
   BÖSE – *Seelenblitz*, *Totenerweckung*, *Fluchaura* (Nekromant); *Wirbelwind*, *Kriegsschrei*, *Blutzoll*
   (Kriegsherr); *Schattenschritt*, *Giftklinge*, *Ausweichen* (Klingentänzerin).

### Phase 6 – Neutrale Dörfer und Diplomatie

Tipp: F3 einschalten – F9 gibt Ressourcen. Im Diplomatiefenster erscheinen im F3-Modus die Knöpfe „Ruf +20“,
„Ruf −20“ und „Bote senden (Test)“.

1. Rund um dein Reich liegen **neutrale Dörfer** (kleine Karte 6, mittlere 10, grosse 16) mit einer Grenze in der
   Volksfarbe; auf der Minikarte steht je Dorf ein Haussymbol. Fährt die Maus über ein Dorfgebiet, zeigt der
   Infobereich unten links „Gebiet: Zwergendorf Eisenhall (Neutral)“. Deine Sammler holen dort nichts.
2. Ein **Dorfzentrum** (oder eine Miliz) anklicken: im Auswahlfenster Volk, Ruf mit Stufe (farbig), Vertrag,
   Produktion und Miliz, darunter der Knopf **„Diplomatie (N)“**.
3. **N** (oder der Knopf „Diplomatie“ oben) öffnet das Diplomatiefenster: links alle Dörfer mit Ruf-Balken, Vertrag
   bzw. Krieg, Entfernung und grober Stärke; rechts das gewählte Dorf mit Beschreibung, Stärken und Schwächen des
   Volks, Produktion, Vorrat, Ruf-Verlauf und Beziehungen. Es ist immer nur ein Fenster offen; Esc schliesst.
4. **Geschenk**: Ware und Menge wählen – die Zeile darunter zeigt den Rufgewinn („Ruf +6,3“, Lieblingswaren zählen
   mehr, viele Geschenke kurz nacheinander wirken weniger) – dann „Schenken“.
5. **Handel**: Menge und Ware wählen, die du gibst, und die Ware, die du bekommst; die Zeile zeigt Menge, Kurs und das
   restliche Tageslimit. Koboldhändler und Nomaden haben die besten Kurse, ein Handelsvertrag senkt die Marge und
   erhöht das Limit.
6. **Verträge**: Die Annahme-Chance steht auf dem Knopf („Schutz (75 %)“), Bedingungen und Gegenleistung im Tooltip,
   gesperrte Verträge nennen den Grund. *Schutzvertrag*: das Dorf zahlt Tribut – wird es angegriffen, schicke binnen
   60 s Truppen hin (sonst sinkt der Ruf; der Knopf oben bekommt einen roten Punkt). *Handelsvertrag*: regelmässige
   Lieferungen und bessere Kurse. *Bündnis* (ab Freundlich): Milizen helfen dir in der Nähe, der **Volkskrieger**
   erscheint in der Kaserne. „Vertrag kündigen“ braucht einen zweiten Klick.
7. **Aufnahme**: ab *Ergeben* (oder ab *Freundlich* mit grossem Geschenk bzw. starker Armee in der Nähe) –
   „Aufnehmen“ zweimal klicken. Das Dorfzentrum wird dein Aussenposten mit Gebiet, die Milizen werden deine Truppen,
   die Produktion fliesst in dein Lager (Auswahlfenster zeigt den Ertrag).
8. **Drohen**: mit genug Truppen in der Nähe zahlt das Dorf Tribut, sonst lacht es dich aus – der Ruf sinkt so oder
   so, andere Dörfer hören davon.
9. **Krieg**: mit Truppen zweimal Rechtsklick auf eine Miliz oder ein Gebäude des Dorfs (der erste Klick warnt nur)
   oder „Krieg erklären“ im Fenster. Das Dorf schickt einen **Boten** (Meldung mit Klick, blinkendes weisses Quadrat
   auf der Minikarte) zum nächsten Dorf – fange ihn ab, sonst sinkt dein Ruf auch dort. Dorfzentrum auf 0 Leben →
   **erobert** (gemindert produktiv, andere Dörfer misstrauen dir). Frieden geht nach 60 s ohne Angriff, wenn der
   Ruf nicht zu tief ist.
10. Sinkt der Ruf unter −50, wird ein Dorf feindlich und schliesst sich dem Gegner an.

### Phase 7 – Gegner, Entdeckung und Spionage

Tipp: F3 einschalten – im Spionagefenster erscheinen dann „Aufmerksamkeit +30“, „Volle Kundschaft“, „KI greift jetzt
an“, „KI-Reich besiegen“ und „Rivalen: Krieg“, im Diplomatiefenster (Reiter „Reiche“) „Besiegen (Test)“; F9 gibt
Ressourcen.

1. Neues Spiel (Normal, mittlere Karte). In mittlerer Entfernung liegen zwei feindliche Königreiche (bei BÖSE gute,
   bei GUT böse), jedes mit eigenem Volk und Namen. Ihre Grenzen in der Volksfarbe und ihre Burgen (Burgsymbol auf der
   Minikarte, roter Ring) sind sichtbar.
2. Burg eines Feindes anklicken: ohne Kundschaft steht im Auswahlfenster nur „Keine Kundschaft“, fremde Einheiten
   zeigen „?“ statt Werten. Späher hinschicken: Das Auswahlfenster zeigt dann die Heeresgrösse ungefähr („Kundschaft:
   Bericht“).
3. Die KI baut auf (Häuser, Höfe, Kaserne, Bibliothek …), beschwört Truppen, räumt Monsterlager in ihrer Nähe und
   umwirbt Dörfer (Geschenke, Verträge – im Diplomatiefenster sichtbar, sobald du Kundschaft hast).
4. Oben „Spionage · 12“: dein Entdeckungswert. Er steigt mit Gebäuden, Bevölkerung, Armee und Angriffen (Aggression
   klingt ab). Die Ursachen stehen im Spionagefenster (K), Reiter „Übersicht“.
5. Forschung *Kundschafter* (BÖSE: *Spitzel*), dann im Spionagefenster, Reiter „Spione“, „Spion beschwören“ (Burg; mit
   *Spionagenetz* bzw. *Schattennetz* im Kundschafterhaus eine Stufe höher). Auftrag *Auskundschaften* auf ein Reich →
   genaue Kundschaft (Stufe 3, Diplomatie → „Reiche“ zeigt Stärke, Kriege, Verträge). *Dorf aufhetzen* senkt den Ruf
   eines Dorfs gegenüber einem Reich. *Rivalen aufhetzen* (bei zwei KI-Reichen) treibt sie in den Krieg
   gegeneinander. Die Vorschau zeigt die Entdeckungsgefahr am Ziel. Spione können entdeckt werden (Meldung, kurz
   sichtbar, sie fliehen heim) und steigen mit Erfahrung bis Stufe 3. Einen Spion auswählen → „Auftrag (K)“ öffnet ihn
   im Spionagefenster.
6. Fremde Spione kommen zu dir, wenn ein Reich Gerüchte über dich hört. Späher, eigene Spione und das
   Kundschafterhaus entdecken sie (roter Punkt am Spionage-Knopf); entdeckte Spione kann man angreifen.
7. Auf Normal greift die KI frühestens nach 67,5 Minuten an und erst, wenn sie dich entdeckt hat (Meldung). Späher
   melden Truppen nahe der Grenze, Feinde im eigenen Gebiet werden immer gemeldet. Wird eine Welle zu stark
   geschwächt, zieht sie sich zurück.
8. *Reichsschleier* (BÖSE: *Reichsschatten*, Magie Stufe 4): ein Klick in der Zauberleiste oder „Tarnung
   einschalten“ im Spionagefenster senkt den Entdeckungswert um 40 % und kostet laufend Mana (endet bei Manamangel).
9. Ein Reich fällt, wenn sein König stirbt oder seine Burg zerstört wird: Gebäude werden zu Ruinen, Truppen lösen
   sich auf, das Gebiet verschwindet. Sind alle feindlichen Reiche gefallen, erscheint der **Siegbildschirm** mit
   Statistik („Weiterspielen“ oder Hauptmenü). Fällt deine Burg, ist das Spiel verloren. Schneller Test: F3 →
   Spionagefenster → „KI-Reich besiegen“.

Rauchtest mit echter KI über lange Zeit (ohne Debug-Abkürzungen):
`$GODOT --headless res://tests/smoke_test.tscn -- faction=evil seconds=3600 p7=natural size=medium`
(`passive=1`: der Spieler tut nichts; der Bericht zeigt Zeitleiste, Wellen und Denkzeit der KI).

### Phase 8 – Völker, Tag/Nacht, Zufriedenheit, Ereignisse

Tipp: F3 einschalten → in der Reichsübersicht (L) erscheinen Debug-Knöpfe: Ereignis auslösen, Alle beenden,
Monsterstreifzug, Zufriedenheit ±30, Überläufer jetzt, Verrat jetzt, Tag/Nacht/Dämmerung/echte Zeit (F9 =
Ressourcen).

1. **Neues Spiel:** Unter der Fraktion wählst du dein **Volk**; Stärken und Schwächen stehen darunter. Oben links
   steht der Name deines Volks (in der Farbe der Fraktion, Tooltip mit Fraktion).
2. **Tag und Nacht:** Oben neben dem Datum zeigt ein Symbol Sonne bzw. Mond (Tooltip: Boni deines Volks). Abends wird
   die Welt dunkler, nachts sinkt die Sicht, Monster werden aktiver und streifen häufiger umher. Im Auswahlfenster
   zeigt die Werteherkunft „Tageszeit“. Abdunklung abschaltbar in den Einstellungen.
3. **Gelände:** Einheiten auf dem Lieblingsgelände ihres Volks sind stärker oder schneller (Auswahlfenster: „Wald
   (Hochelfen): +10 % Angriff …“). Die Tabelle steht in der Reichsübersicht unter „Volk & Tageszeit“.
4. **Zufriedenheit:** Oben in der Leiste ein Gesicht mit dem Durchschnitt (Tooltip: Ursachen). Bewohner anklicken
   zeigt ihre eigene Zufriedenheit. Hunger, Überfüllung, Feinde im Gebiet und Angriffe senken sie; **Taverne**
   (Schenke), **Tempel** (Schattenschrein, braucht eine Bibliothek), Truppen, volle Speicher und **Feste** heben sie.
   - Unter 50 sinkt die Arbeitsleistung.
   - Unter 25 laufen Bewohner über (sichtbar zu einem Nachbarreich, Dorf oder an den Kartenrand; ein Befehl hält sie
     auf).
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
   Wohnraum, Nahrung und Geschenken → Aufnehmen oder Abweisen. Aufgenommene werden Bewohner; unter ihnen kann ein Spion
   sein, den ein Tempel eher entlarvt. Abgewiesene ziehen weiter, zu einem Dorf oder zum Gegner.
7. **Wilde Monster:** Lager wachsen mit der Zeit. Zerstörte Lager entstehen später woanders neu. Monster ziehen auf
   Streifzüge zu nahen Siedlungen, auch zur KI und zu Dörfern (Minikarte: oranger Ring mit Pfeil).

Rauchtest: `tests/run_smoke.sh 600` (prüft Phase 8 in `tests/smoke_phase8.gd`); lange Läufe mit
`p8=natural seconds=3600 size=medium`, ein bestimmtes Volk mit `people=<id>`.

### Phase 9 – Belagerung und Handelswege

Tipp: F3 an, F9 = Rohstoffe.

1. Baumenü → *Verteidigung* → Mauer: mit gedrückter Maustaste einen Ring um ein Stück Land ziehen. Über eine Strasse
   entsteht automatisch ein Tor. Schliesst du den Ring ohne Tor, warnt eine Meldung.
2. Ein Tor auf ein Mauerstück setzen. Eigene Bewohner und Truppen gehen hindurch. Tor auswählen → „Verriegeln“.
3. F11 setzt Wölfe vor die Mauer. Sie finden keinen Weg und greifen Mauer oder Tor an. Sind sie weg, reparieren
   Bauarbeiter die Schäden (Stein wird abgezogen).
4. Wachturm bauen: Die Vorschau zeigt die Reichweite. Er schiesst sichtbare Pfeile auf Wölfe und Feinde.
5. Forschung → Militär „Belagerungskunst“ → Belagerungswerkstatt → Rammbock und Katapult. Rechtsklick auf ein
   feindliches Gebäude oder Lager: Katapulte schiessen von weit, Rammböcke greifen nur Gebäude an. Strg+F11 schickt
   einen feindlichen Rammbock gegen deine Burg.
6. Diplomatie (N): Handelsvertrag mit einem Dorf. Eine Karawane pendelt (gestrichelte Linie auf Karte und Minikarte).
   N → Reiter „Handelswege“ (oder L → Reiter „Handel“) zeigt Ladung, Lieferungen und Verluste.
7. Wölfe (F11) auf den Weg setzen oder die Karawane über den F3-Knopf überfallen: Erst geht die Ladung verloren, dann
   ist der Weg abgeschnitten (rotes ✕). Sind keine Feinde mehr da, öffnet er sich nach einigen Minuten, oder du gibst
   ihn über den Knopf frei.
8. KI-Karawanen (gestrichelt braun, sobald gesichtet) überfallen: Du bekommst Beute, ihre Lieferungen fallen aus.
9. Armee weit aus dem Gebiet schicken: Verletzte erholen sich nicht (Wirkung „Ohne Versorgung“). Im eigenen Gebiet,
   nahe einem offenen Handelsweg oder durch Heiler geht es wieder.
10. KI: Nach Angriffen baut sie Türme, auf Normal später auch einen Mauerring. Gegen deine Mauern bringt sie
    Rammböcke und Katapulte.

### Phase 10 – Speichern, Schwierigkeit, Oberfläche

1. Neues Spiel, ein paar Minuten spielen, **F5**, ein Gebäude abreissen, **F8** → alles wie vorher (Gebäude im Bau,
   Warteschlangen, Sammelpunkte, Helden, Zauberzonen, Monsterlager).
2. **Esc → Speichern** mit Namen; noch einmal mit gleichem Namen → Rückfrage „überschreiben?“.
3. **Hauptmenü → Laden**: Liste mit Datum, Spielzeit, Fraktion, Schwierigkeit, Karte, Seed; Löschen mit Rückfrage;
   „Fortsetzen“ lädt den neuesten Spielstand. Unten rechts steht „Version 1.2.0 · Godot 4.x.y“.
4. **Einstellungen**: Autospeichern 5 min → nach 5 min Hinweis „Automatisch gespeichert“ oben rechts, höchstens
   3 Autospeicherstände.
5. Grösse der Oberfläche **125 %** und **150 %** → HUD, Zauberleiste, alle Fenster (Forschung, Helden, Armee,
   Diplomatie, Spionage, Reich, Flüchtlinge, Hilfe, Protokoll, Sieg/Niederlage) und Menüs werden grösser, Klicks
   treffen weiter. Die obere Leiste passt immer auf den Bildschirm: zuerst wird der Reichsname ausgeblendet (steht
   dann im Tooltip von „Reich“), reicht das nicht, wird die Leiste als Ganzes etwas verkleinert.
6. **F1** Hilfe (Steuerung, Spielablauf, Schwierigkeit), **M** Protokoll mit Klick zur Stelle.
7. Schwierigkeit *Leicht*: Monster schwächer (Auswahlfenster einer Höhle), mehr Startvorräte; *Episch*: frühe, grosse
   Wellen.
8. Eine Kaserne mit voller Warteschlange abreissen → Kosten zurück; wird sie von Feinden zerstört, ist der Einsatz
   verloren.
9. Jeder Knopf hat einen Tooltip (der Rauchtest prüft HUD, alle Fenster mit allen Reitern und das Spielmenü).
10. Rauchtest `tests/run_smoke.sh 1200` – mit Rundlauf, UI-Grössen- und Tooltip-Prüfung.

### Truppen – Klassen, Schmiede, Ränge, Aussehen

Tipp: F3 einschalten – F9 gibt Ressourcen, F11 setzt Wölfe an die Maus, im Auswahlfenster einer Truppe gibt
„+50 EP (Test)“ Erfahrung.

1. **Neue Truppen**: Kaserne bauen. Forschung *Waffenschmiede* (BÖSE: *Schwarze Klingen*) schaltet Speerträger
   (Pfähler) und Armbrustschützen (Höllenschützen) frei, *Ritterorden* (*Schreckensorden*) den **Reitstall**
   (*Wolfszwinger*) mit Lanzenreitern (Wolfsreitern), *Schildwall* (*Dornenpanzer*) die Schildwache (Eisenhauer),
   *Lichtsegen* (*Fluch der Schwäche*) den **Magierturm** (*Hexenturm*) mit Kampfmagiern (Hexern). Der Tooltip der
   Beschwören-Knöpfe nennt Klasse und Konter („Stark gegen Reiterei (+100 %)“).
2. **Konter**: Reiter gegen Bogenschützen schicken – sie gewinnen deutlich; Speerträger gegen Reiter – die Reiter
   verlieren. Armbrüste schaden schweren Fusstruppen mehr (halbe Rüstung durchschlagen), Magier treffen Gruppen
   (Flächenschaden).
3. **Schmiede** (BÖSE: Blutschmiede, braucht eine Kaserne) bauen und anklicken: je Klasse „Waffen 0/3“ und
   „Rüstung 0/3“. Ein Klick kauft die nächste Stufe; der Tooltip der Kampfwerte einer Truppe zeigt „Schmiede: Waffen
   der Fusstruppen +10 %“.
4. **Erfahrung**: Truppen gegen Wölfe (F11) kämpfen lassen. Nach 60 EP wird ein Rekrut zum Soldaten (ein silberner
   Winkel über dem Kopf, Veteran zwei, Elite drei goldene, Held der Truppe ein Stern). Truppe anklicken: Rang,
   Erfahrungsbalken und „Wertepunkte: 1 frei“ → „Angriff +“ (die vier Knöpfe erscheinen nur bei freien Punkten) – der
   Angriff steigt um 6 %.
5. Mehrere Truppen auswählen → „Verteilen“. Das Häkchen „automatisch“ lässt das Reich neue Punkte immer selbst
   verteilen (bei der KI immer an).
6. **Helden**: ab Stufe 2 ein Wertepunkt je Stufe – Held anklicken, gleiche Knöpfe.
7. **Aussehen**: Truppe anklicken → Knopf „Aussehen“ → „Alle: Königsgarde“ (BÖSE: Schattenwache, Blutbanner) färbt
   alle Einheiten dieses Typs um (Rand, Abzeichen); „Diese: …“ nur die eine. Das Heldenbanner gibt es ab Rang Elite.
   Die Beschwören-Knöpfe der Kaserne zeigen das gewählte Aussehen.
8. F5/F8: Ränge, Punkte, Aussehen und Schmiede-Stufen bleiben erhalten.

Rauchtest: `tests/run_smoke.sh 900` (prüft die Truppen in `tests/smoke_troops.gd`).

### Armeefenster

1. Neues Spiel, Kaserne bauen und einige Kämpfer und Schützen beschwören (F3 → F9 gibt Rohstoffe).
2. **T** (oder Knopf „Armee · 6“ oben neben „Helden“) → Fenster „Armee“ in der Mitte; ein offenes Forschungs-,
   Helden-, Diplomatie-, Spionage- oder Reichsfenster schliesst sich. **T** oder **Esc** schliesst es wieder.
3. Links je Einheitentyp eine Zeile mit Bild, Anzahl, Lebensbalken („gesamt / Höchstwert (Ø …)“) und „6 untätig ·
   2 unterwegs …“; darunter die Helden (Stufe, Zustand, Armee) und die Armeen mit Stärke, Ort („Eigenes Gebiet,
   12 Kacheln östlich der Burg“) und Befehl. „Bewohner und König zeigen“ nimmt sie dazu.
4. **Strg+A** (oder „Alle Krieger auswählen“): alle Truppen und Helden sind ausgewählt, keine Bewohner, nicht der
   König. „Untätige“ / „Verwundete“ (unter 70 % Leben) wählen nur diese.
5. Einige Einheiten auswählen → rechts „Auswahl als Armee speichern“ **9** → Zeile „Armee 9“ erscheint (auch in der
   Armeeleiste); „Wählen“ macht sie zur Befehlsgruppe (Name hervorgehoben), „Hin“ springt hin, „✕“ löst sie auf.
6. **Angreifend vorrücken …** → Fenster schliesst, Mauszeiger wird zum Kreuz → Klick ins Gelände: die Gruppe
   marschiert und kämpft unterwegs (Esc bricht den Zielmodus ab). Ebenso **Bewegen …** (ohne zu kämpfen) und
   **Patrouille …** (läuft zwischen ihrem Ort und dem Ziel hin und her, blaue Zielmarke).
7. **Halten**, **Sammeln an der Burg** (Marsch in Formation zum Platz vor der Burg) und **Rückzug zur Burg** (läuft
   ohne zu kämpfen hin, Befehl „erholt sich an der Burg“: deutlich schnellere Heilung, `combat.json` → `rest`).
8. **Formation** Block / Linie / Keil / Kreis: gilt für die nächsten Marschbefehle (auch Taste F, reihum), die
   Befehlsgruppe stellt sich sofort an ihrem Ort so auf.
9. **Haltung passiv** (im Armeefenster oder in der Zeile „Haltung“ des Auswahlfensters) → F3, Umschalt+F11 setzt
   einen Übungsgolem neben die Truppe: niemand greift an, auch nicht, wenn der Golem zuschlägt. **Verteidigend** → sie
   greifen an und kehren danach auf den Posten zurück; **aggressiv** → sie verfolgen ihn auch weit vom Posten weg.
   Angriffsbefehle (Rechtsklick auf einen Feind, angreifend vorrücken) gelten in jeder Haltung.
10. **F5** / **F8**: Haltung und Patrouille bleiben erhalten.

Rauchtest: `tests/run_smoke.sh 900` (enthält `tests/smoke_army.gd`).

### Tutorial

1. Hauptmenü → **Tutorial**: feste Partie (Seed „Lernreich“, kleine Karte, *Leicht*, ein Gegnerreich) mit der zuletzt
   gewählten Fraktion. Rechts erscheint das Tutorial-Fenster mit Kapitel, „Schritt 1/37“, Titel, Text und Aufgabe.
2. Ein pulsierender goldener Rahmen zeigt das Bedienelement (Baumenü-Knopf – liegt er in einem anderen Reiter, wird der
   Reiter gezeigt –, Knöpfe oben, Arbeitsverteilung, Minikarte, Auswahlfenster, Zauberleiste …), ein Pfeil die Stelle
   in der Welt (Burg, Manaquelle, nächstes Dorf; ausserhalb des Bildes am Rand). Klicks gehen durch Rahmen und Pfeil.
3. Aufgabe erfüllen → „✓ Geschafft!“, nach gut einer Sekunde der nächste Schritt; reine Erklärschritte haben
   „Weiter“ (vor der Aufgabe gesperrt). Lange Schritte (Haus fertig, Truppen, Forschung, Zauber, Held, Geschenk …)
   lassen sich **überspringen**.
4. Bei einigen Schritten schenkt der Hofschatzmeister die nötigen Rohstoffe (einmal je Partie, auch nach „von vorn“
   nicht doppelt). Beim Schritt „Ränge und Wertepunkte“ steigt ein Krieger einmal auf.
5. Kapitel (37 Schritte): Erste Schritte (Kamera, Zoom/Minikarte, Pause, Tempo) · Dein Dorf (Vorräte, Wohnhaus,
   Bauernhof, Strassen, Berufe mit J, Manabrunnen) · Einheiten (Späher aus der Burg, Auswählen, Bewegen, Kaserne,
   Truppen, Armee mit Strg+1, Angriff-Vorrücken) · Armee und Truppen (Armeefenster mit T, alle Krieger mit Strg+A,
   Haltung, Schmiede mit einer Waffenstufe, Rang-Aufstieg und Wertepunkt) · Wissen und Magie (Bibliothek, Forschung
   mit R, Zauber) · Helden (Heldenhalle, Anwerben mit G) · Reich und Nachbarn (Diplomatie mit N, Geschenk, Spionage
   mit K, Reichsübersicht mit L) · Speichern und Hilfe (F5, F1).
6. Solange das Tutorial läuft (höchstens 120 Spielminuten ab dem ersten Start), wählen die KI-Reiche den Spieler nicht
   als Wellenziel, Zufallsereignisse (auch Monsterwellen und Flüchtlinge) und Monster-Streifzüge treffen ihn nicht;
   nach dem Ende gilt das noch 10 Minuten, danach wieder die normalen Regeln der Schwierigkeit.
7. „Beenden“ (zweimal klicken) blendet das Tutorial aus; im **Spielmenü (Esc)** steht dann „Tutorial fortsetzen
   (Schritt 7/35)“, nach dem Abschluss „Tutorial starten“, während es läuft „Tutorial von vorn“. Ein im Spielmenü
   nachträglich gestartetes Tutorial in einer normalen Partie schützt nicht.
8. F5 im Schritt „Speichern“, dann F8: es geht beim gleichen Schritt weiter.
9. Neues Spiel mit Haken **„Tipps/Tutorial anzeigen“**: das Tutorial läuft in der Partie mit den eigenen
   Einstellungen.

Rauchtest: `tests/run_smoke.sh 900 tutorial=1` (siehe oben).
