# Änderungen

Alle wichtigen Änderungen an **Königreiche**, neueste zuerst. Die Versionsnummer steht in `project.godot`
(`config/version`) und unten rechts im Hauptmenü.

## Unveröffentlicht

### Behoben

- Helden: Eisenhaltung löst sich mit Selbstauslösung im Kampf von selbst aus; Steinwall und andere Hilfen für die
  eigenen Truppen lösen nur noch aus, wenn jemand kämpft oder verwundet ist, statt im Leerlauf abzuklingen. KI-Helden
  beschwören jetzt auch (Schattenruf, Totenerwecken) und nutzen Rauchschleier (#37).
- Spionagebericht: Ein Dorf mit Bündnis steht nicht mehr doppelt unter „Bündnisse“ (#37).

## 1.2.0 – 2026-10-17

Alte Spielstände (1.1.0) laden weiter (#33): Dörfer behalten ihre Grösse und wachsen ab jetzt weiter, Handelsrouten
laufen mit Menge ×1 und dem bisherigen Abstand, Stationierungen gibt es noch keine.

### Hinzugefügt

- Spione liefern einen genauen Bericht: Truppen, Helden, Verteidigung, Burgstufe, Vorräte und Bündnisse des Ziels
  (#17).
- Dörfer sind grösser und wachsen im Lauf der Partie; gegnerische Reiche starten grösser und bauen weiter aus (#21).
- Zwei neue Helden je Fraktion mit eigenen Fähigkeiten und Bedingungen: Meisterspionin und Baumeister (GUT),
  Dämonenruferin und Eisenwall (BÖSE) (#22).
- Bündnisse: Truppen lassen sich zum Schutz bei Verbündeten stationieren; Verbündete danken mit Ruf und Abgaben.
  Befehl im Diplomatiefenster (Zeile „Bündnis“) und im Armeefenster, bei Nicht-Verbündeten gesperrt mit Grund. Dazu
  Hilferufe angegriffener Verbündeter (annehmen oder ablehnen), gemeinsame Ziele und „Miliz anfordern“; die KI
  stationiert ebenfalls (#27).

### Geändert

- Alle Figuren haben jetzt ein eigenes Aussehen statt Punkten: Truppen je Klasse, Helden, Bewohner, Spione und
  Monster (#15).
- Ein starkes Heer macht dich nicht mehr bei allen gefürchtet: Verbündete fühlen sich sicherer, nur Angriffe und
  Drohungen machen Angst (#19).
- Handel überarbeitet: Preise nach Angebot und Nachfrage, dauerhafte Handelsrouten mit Karawanen. Preise je Dorf
  stehen im Diplomatiefenster; Menge und Abstand jeder Route lassen sich im Reiter Handelswege einstellen, dort steht
  auch, was der Handel je Minute bringt und kostet. Jede Lieferung verbessert den Ruf, die KI handelt nach denselben
  Regeln (#25).
- Gegnerische Reiche entdecken dich langsamer: Die Aufmerksamkeit steigt langsamer, Gerüchte und Entdeckung brauchen
  mehr, Späher müssen länger in deinem Gebiet bleiben, und ein stilles Reich fällt erst später auf. Bei normaler
  Schwierigkeit kommt die Entdeckung rund 50–70 % später; Angriffe entdecken dich weiterhin sofort (#29).
- Partien dauern länger: Die Gegner greifen später an und rüsten langsamer auf. Die erste Angriffswelle kommt rund
  die Hälfte später (Normal frühestens nach 67,5 statt 45 Minuten), Dörfer werden später angegriffen, und jede Welle
  wächst um 2 statt 3 Einheiten. Die Länge eines Spieltags bleibt gleich (#31).

### Behoben

- Spione erscheinen nicht mehr doppelt: Ein Spion bekommt nur noch einen Eintrag und eine Nummer, auch nach dem
  Laden. Zu Spielbeginn hat kein Reich Spione; ein neuer Test sichert beides ab (#13).

## 1.1.0 – 2026-10-16

Alte Spielstände (1.0.0) laden weiter: Gebäude stehen auf Stufe 1, die Burg auf Burgstufe 1.

### Hinzugefügt

- Gebäude lassen sich auf Stufe 2 und 3 ausbauen und werden dabei stärker: Knopf „Ausbauen“ im Auswahlfenster,
  Bauarbeiter erledigen den Ausbau, das Gebäude arbeitet weiter; Stufe als Schild I/II/III auf der Karte. Haus, Lager,
  Sammelhütten, Bauernhof, Manabrunnen, Kaserne, Bibliothek, Taverne, Tempel, Wachturm und Schmiede. Die KI baut
  ebenfalls aus, Wirtschaftsgebäude zuerst (#4).
- Die Königsburg wächst in vier Stufen (Weiler, Dorf, Stadt, Königssitz); viele Gebäude werden erst mit höherer
  Burgstufe freigeschaltet, Gebäude auf Stufe 3 erst ab der Stadt. Jede Burgstufe braucht Rohstoffe, Bewohner und
  bestimmte Gebäude. Gesperrte Gebäude bleiben im Baumenü sichtbar und nennen, was fehlt; das Reichsfenster hat den
  neuen Reiter „Burg“. Das Tutorial baut die Burg als Geschenk aus, die KI hält sich an dieselben Regeln (#5).

### Geändert

- Jeder Held stellt eigene Bedingungen, bevor er sich anwerben lässt (Burgstufe, Gebäude, Forschung, besiegte Feinde,
  zerstörte Monsterhöhlen). Gesperrte Helden stehen mit ✓/✗ je Bedingung im Heldenfenster; der erste Held jeder
  Fraktion ist mit der Heldenhalle erreichbar, die übrigen deutlich später. Die KI hält sich an dieselben Bedingungen
  (#7).
- Neue Bewohner kommen nicht mehr von selbst: Bewerber stellen eigene Bedingungen, und man entscheidet, wen man
  aufnimmt. Jeder Bewerber hat Namen, Wunschberuf und 1–3 Bedingungen (✓/✗ im Bewerberfenster und im Reichsfenster,
  Reiter „Bewerber“), Fachleute arbeiten im Wunschberuf 20 % schneller. Die Taverne lockt mehr Bewerber an. Das
  natürliche Wachstum ist selten geworden (etwa alle 4 Minuten, nur bei zufriedenen Bewohnern). Die KI nimmt Bewerber
  nach denselben Regeln auf (#6).
- Heldenhalle, Tempel, Schmiede, Reitstall, Magierturm und Belagerungswerkstatt kosten rund 40 % mehr und brauchen
  länger zum Bauen (#5).

### Dokumentation und Repository

- README als übersichtliche Startseite mit Bildschirmfotos, Funktionsüberblick, Schnellstart und wichtigsten Tasten.
- Ausführliche Anleitungen im Ordner `docs/`: Spielanleitung (mit Tabellen aller Völker, Gebäude, Truppen,
  Forschungen, Zauber, Helden und Ereignisse), Steuerung, Daten anpassen (Modding), Grafiken austauschen, Architektur,
  Testen, Balancing.
- `tools/doku_tabellen.py` erzeugt die Tabellen der Spielanleitung aus `data/*.json`.
- Frische Bildschirmfotos in `docs/bilder/`.
- GitHub Actions (`.github/workflows/tests.yml`): Skriptprüfung und Rauchtest bei jedem Push und Pull Request.
- `.editorconfig`, Vorlagen für Fehlermeldungen und Ideen (`.github/ISSUE_TEMPLATE/`), `.gitattributes` und
  `.gitignore` ergänzt.

## 1.0.0 – 2026-10-15

### Erweiterungen nach Phase 10

- **Oberfläche aufgeräumt** – alle Fenster im selben Stil (`UiStyle`: Rahmen und Titel in der Fraktionsfarbe, Reiter,
  Fusszeile), obere Leiste in drei Gruppen (Ressourcen · Fenster-Knöpfe · Zeit), Arbeitsverteilung einklappbar,
  Haltung direkt im Auswahlfenster, Baumenü mit drei Reitern.
- **Truppen** – neue Einheiten je Fraktion: Speerträger/Pfähler, Armbrustschützen/Höllenschützen,
  Schildwache/Eisenhauer, Lanzenreiter/Wolfsreiter (Reitstall/Wolfszwinger), Kampfmagier/Hexer
  (Magierturm/Hexenturm). Truppenklassen mit Kontern, **Schmiede** mit Waffen- und Rüstungsstufen je Klasse,
  **Erfahrung und Ränge** (Rekrut bis Held der Truppe) mit Wertepunkten, **Aussehen** (Skins) je Typ oder Einheit.
- **Tutorial** – geführte Partie in 35 Schritten und acht Kapiteln mit Hervorhebung (Rahmen und Pfeil), Geschenken
  des Hofschatzmeisters, Schutz vor Gegnern und Ereignissen, Fortsetzen über das Spielmenü und eigenem Rauchtest.
- **Armeefenster (T)** – Übersicht aller Krieger nach Typ, Helden und Armeen 1–9; Befehle an die ganze Gruppe
  (Sammeln, Rückzug zur Burg, Angreifend vorrücken, Bewegen, Patrouille, Halten), Formationen Keil und Kreis,
  **Haltungen** aggressiv / verteidigend / passiv, Strg + A wählt alle Krieger.

### Phase 10 – Speichern, Schwierigkeit, Feinschliff (14.10.2026)

- Speichern und Laden: benannte Plätze, Schnellspeichern (F5/F8), Autospeichern reihum, Hintergrund-Schreiben mit
  Sicherung, komprimierte Dateien, Prüfsumme, Migration; Laden idempotent.
- Schwierigkeitsgrade Leicht, Normal, Schwer, Episch (KI, Monster, Startvorräte, Ereignisse).
- Einstellungen (Ton, Kamera, Vollbild, Grösse der Oberfläche 75–150 %, Abdunklung, Autospeichern), Hilfe (F1),
  Meldungsprotokoll (M), Spielmenü.
- Balancing-Läufe über 3 Spielstunden, Leistungsmessung, Export-Vorlagen für Windows und Linux.

### Phase 9 – Belagerung und Handelswege (14.10.2026)

- Mauern, Tore (verriegelbar) und Wachtürme; Wegfindung um Mauerringe, Bresche, Reparatur durch Bauarbeiter.
- Belagerungswerkstatt mit Rammbock und Katapult; die KI befestigt sich und belagert.
- Handelswege mit Karawanen, Überfälle, abgeschnittene Wege; Versorgung fern vom eigenen Gebiet.

### Phase 8 – Völker, Zufriedenheit, Ereignisse, Tag/Nacht (14.10.2026)

- 22 Völker mit Gelände- und Tageszeitboni, Volkswahl beim neuen Spiel.
- Zufriedenheit der Bewohner mit Taverne, Tempel und Festen; Überläufer und Verrat.
- Zufallsereignisse: Dürre, Seuche, Magiesturm, Monsterwelle, Flüchtlinge, Wanderer, Erntedank, Manablüte.
- Wachsende Monsterlager, Streifzüge, Tag-Nacht-Wechsel mit Abdunklung.

### Phase 7 – Gegnerische Königreiche und Spionage (14.10.2026)

- KI-Reiche mit Persönlichkeiten, Aufbau, Forschung, Helden, Zaubern, Dorfdiplomatie und Angriffswellen;
  Rivalität zwischen KI-Reichen.
- Entdeckungswert, Aufmerksamkeit und Kundschaft; Spione mit Aufträgen; Reichstarnung.
- Niederlage von Reichen (Ruinen), Siegbildschirm.

### Phase 6 – Neutrale Dörfer und Diplomatie (14.10.2026)

- Neutrale Dörfer der zehn freien Völker mit Milizen und Dorfwirtschaft.
- Ruf, Geschenke, Tauschhandel, Schutz- und Handelsvertrag, Bündnis mit Volkskriegern, Aufnahme, Drohung, Krieg und
  Eroberung, Boten.

### Phase 5 – Helden (14.10.2026)

- Heldenhalle, drei Helden je Fraktion mit je drei Fähigkeiten, Stufen mit Wahl (Fähigkeit oder Talent), Führung,
  Ausbildung, Tod und Wiederbelebung, Heldenfenster (G) und Heldenleiste.
- Werkzeuge: Skriptprüfung (Warnungen als Fehler) und Rauchtest für beide Fraktionen ohne Fenster.

### Phase 4 – Forschung, Mana und Magie (12.–13.10.2026)

- Bibliothek und Forschungsbaum (vier Zweige, vier Stufen) je Fraktion, Forschungsfenster (R).
- Mana-Maximum, Kampfpunkte und ihre Verbesserungen.
- Zauber des Königs mit Zielkreis (Segen/Fluch, Heilung, Tarnung, Wetter, Beschwörung).

### Phase 3 – Einheiten, Kampf und Armeen (12.10.2026)

- Beschwören in Burg und Kaserne mit Warteschlange und Sammelpunkt, Auswahl, Bewegung in Formation, Armeen 1–9.
- Kampf mit Fernkampf, Heimvorteil, Erholung, Krankenstation und Heilern; König, Monsterlager mit Beute und
  Kampfpunkten; Spielende.

### Phase 2 – Dorf und Wirtschaft (12.10.2026)

- Gebäude, Baustellen und Bauarbeiter, Strassen, Gebiet, Ressourcen und Vorkommen.
- Bewohner mit Berufen und Arbeitsverteilung, Wachstum, Hungersnot.

### Phase 1 – Grundlagen (11.10.2026)

- Projekt-Setup (Godot 4, GDScript), Strategie-Kamera, prozedurale Karte mit Biomen und Chunks, Spieltempo und Pause,
  Hauptmenü.
