# Daten anpassen (Modding)

Fast alles, was das Spiel ausmacht – Kosten, Bauzeiten, Kampfwerte, Forschung, Zauber, Völker, Ereignisse, KI –
steht in **JSON-Dateien im Ordner `data/`**. Diese Dateien lassen sich mit jedem Texteditor ändern, ohne eine Zeile
Code. Beim nächsten Start (F5 im Editor) gilt der neue Wert.

## Inhalt

1. [Grundregeln](#grundregeln)
2. [Alle Dateien im Überblick](#alle-dateien-im-überblick)
3. [Die Dateien im Einzelnen](#die-dateien-im-einzelnen)
4. [Beispiele](#beispiele)
   - [Billigere Häuser](#billigere-häuser)
   - [Stärkere Ritter](#stärkere-ritter)
   - [Mehr Dörfer](#mehr-dörfer)
   - [Neue Einheit hinzufügen](#neue-einheit-hinzufügen)
   - [Neues Ereignis](#neues-ereignis)
   - [Weitere schnelle Änderungen](#weitere-schnelle-änderungen)
5. [Balancing selbst nachjustieren](#balancing-selbst-nachjustieren)
6. [Nach dem Ändern prüfen](#nach-dem-ändern-prüfen)
7. [Spielstände und Datenänderungen](#spielstände-und-datenänderungen)

## Grundregeln

- **Erklärungen stehen in der Datei selbst:** Jede Datei hat oben ein Feld `"_hinweis"` mit der Bedeutung aller
  Felder. Es wird vom Spiel ignoriert – lesen lohnt sich.
- **JSON ist streng:** Texte in `"Anführungszeichen"`, Kommas zwischen Einträgen, **kein** Komma nach dem letzten
  Eintrag, Dezimalzahlen mit Punkt (`0.25`, nicht `0,25`). Ein guter Editor (z. B. VS Code) zeigt Fehler sofort an.
- **Zeiten** sind Spielsekunden (bei Tempo 1x echte Sekunden). Ein Spieltag = 600 s, eine Spielstunde = 25 s.
- **Prozente** sind Faktoren: `0.25` = 25 %, `1.1` = +10 %, `0.9` = −10 %.
- **Ressourcen-IDs:** `wood` (Holz), `stone` (Stein), `ore` (Erz), `food` (Nahrung), `mana` (Mana).
- **IDs** (`"id": "house"`) nie umbenennen – andere Dateien und Spielstände verweisen darauf. Anzeigenamen
  (`"name"`) dürfen frei geändert werden.
- Nur `scripts/autoload/data_db.gd` liest die Dateien. Neue Felder, die kein Code kennt, haben keine Wirkung.
- Nach Änderungen an Werten, die in der [Spielanleitung](spielanleitung.md) stehen, einmal
  `python3 tools/doku_tabellen.py` ausführen – dann stimmen auch die Tabellen der Anleitung wieder.

## Alle Dateien im Überblick

| Datei | Steuert |
|---|---|
| [`game_config.json`](#game_configjson) | Kartengrössen, Kamera, Länge eines Tages, Tempostufen, Speichern |
| [`worldgen.json`](#worldgenjson) | Weltgenerierung: Rauschen, Grenzgebirge, Startplatz, Plätze der KI-Reiche, Dörfer |
| [`biomes.json`](#biomesjson) | Biome: Regeln, Farben, Bewegungskosten, Verteidigung, Bebaubarkeit, Kachelgrafiken |
| [`resources.json`](#resourcesjson) | die fünf Ressourcen und die Vorkommen auf der Karte (Bäume, Steine, Erz, Beeren, Manaquellen) |
| [`factions.json`](#factionsjson) | Fraktionen GUT, BÖSE, NEUTRAL, Wilde Monster |
| [`peoples.json`](#peoplesjson) | alle 22 Völker: Stärken, Schwächen, Gelände- und Tageszeitboni, Dorfdaten |
| [`economy.json`](#economyjson) | Startausstattung, Wachstum, Hunger, Strassen, Rückerstattung |
| [`buildings.json`](#buildingsjson) | alle Gebäude: Kosten, Bauzeit, Wohnraum, Gebiet, Produktion, Beschwörungen |
| [`jobs.json`](#jobsjson) | Berufe der Bewohner |
| [`units.json`](#unitsjson) | alle Einheiten: Bewohner, König, Truppen, Monster, Milizen, Volkskrieger, Spione, Belagerung |
| [`troops.json`](#troopsjson) | Truppenklassen und Konter, Schmiede, Ränge und Wertepunkte, Aussehen (Skins) |
| [`combat.json`](#combatjson) | Kampfregeln, Formationen, Rückzug, Monsterlager, Streifzüge |
| [`research.json`](#researchjson) | Forschungsbaum beider Fraktionen |
| [`spells.json`](#spellsjson) | Zauber des Königs und Kampfpunkt-Verbesserungen |
| [`heroes.json`](#heroesjson) | Helden, Fähigkeiten, Talente, Stufen |
| [`diplomacy.json`](#diplomacyjson) | Ruf, Geschenke, Verträge, Handel, Aufnahme, Drohung, Dörfer, Boten |
| [`espionage.json`](#espionagejson) | Entdeckung, Aufmerksamkeit, Kundschaft, Reichstarnung, Spione |
| [`ai.json`](#aijson) | Gegner-KI: Namen, Persönlichkeiten, Schwierigkeit, Bauliste, Armee, Wellen |
| [`difficulties.json`](#difficultiesjson) | Schwierigkeitsgrade |
| [`satisfaction.json`](#satisfactionjson) | Zufriedenheit, Überlaufen, Verrat, Feste |
| [`events.json`](#eventsjson) | Zufallsereignisse |
| [`daynight.json`](#daynightjson) | Tageszeiten und ihre Wirkungen |
| [`siege.json`](#siegejson) | Mauern, Tore, Türme, Bresche, Reparatur |
| [`trade.json`](#tradejson) | Handelswege, Karawanen, Versorgung |
| [`help.json`](#helpjson) | Inhalt des Hilfefensters (F1) |
| [`tutorial.json`](#tutorialjson) | Tutorial: Partie, Schutz, alle Schritte |

## Die Dateien im Einzelnen

### game_config.json

| Feld | Bedeutung |
|---|---|
| `map.sizes` | Kartengrössen im Menü (`tiles` = Kacheln je Seite) |
| `map.default_size` | vorgewählte Grösse |
| `camera.zoom_max`, `zoom_start`, `pan_speed`, `edge_scroll_margin` | Kamera |
| `time.seconds_per_day` | echte Sekunden pro Spieltag bei 1x (600) |
| `time.start_hour` | Uhrzeit beim Start (8) |
| `time.speed_steps` | Tempostufen (`[0.5, 1.0, 2.0, 3.0]`) |
| `save.*` | Autospeicher-Plätze und Mindestabstand |

### worldgen.json

Rauschebenen (`layers`: Höhe, Feuchte, Hitze, Vulkan), Grenzgebirge am Kartenrand (`border`), Startplatz (`start`),
Plätze der KI-Reiche (`kingdom_sites`) und **Dörfer** (`villages`: `count_by_size` = Anzahl je Kartengrösse,
`min_dist_start` = Abstand zum Start, `size` = Hütten je Dorf). Änderungen hier ergeben bei gleichem Seed eine andere
Welt (siehe [Spielstände](#spielstände-und-datenänderungen)).

### biomes.json

Je Biom: `conditions` (Regeln mit `height_min`, `moisture_max` … als Flächenanteil 0–1; das **erste** passende Biom
gewinnt), `color` und `pattern` (Platzhalter), `movement_cost` (1.0 = normal), `defense_bonus` (0.2 = +20 %),
`buildable` und `sprites` (Kachelgrafiken). Beispiel: mehr Berge – bei *Berge* `height_min` senken (0.84 → 0.78).

### resources.json

`resources`: Name, Farbe, Icon und `cap` (Lagergrenze, z. B. Mana 100). `deposits`: Vorkommen mit `amount`
(Menge, −1 = unendlich), `per_1000_tiles` (Häufigkeit), `cluster` (Gruppengrösse), `regrow_per_hour`.
`start_guarantees`: was garantiert in Startnähe liegt.

### factions.json

Name, Farbe und `playable` je Fraktion. Die Völker stehen in `peoples.json`.

### peoples.json

Je Volk: `name`, `faction` (`good` / `evil` / `neutral`), `color`, `description`, `preferred_biomes`,
`strengths` / `weaknesses` (nur Text für Menüs!), die echten Wirkungen in `terrain_bonus` (je Biom `attack`,
`defense`, `speed`, `regen`), `day_bonus`, `night_bonus`, `base_bonus`, dazu `leaning` und `affinity` (Startruf).
Neutrale Völker zusätzlich: `village_title`, `village_names`, `produces` (je Minute), `tribute`, `gift_preferences`,
`trade_rates`, `trade_bonus`, `delivery`, `annex_gift`, `militia_unit`, `special_unit`.

> **Wichtig:** Ändert man eine Wirkung (z. B. `terrain_bonus`), sollte man auch den Text in `strengths` /
> `weaknesses` anpassen – das Spiel zeigt den Text, rechnet aber mit den Zahlen.

### economy.json

`start` (Startressourcen, Bewohner, Berufe), `population` (`growth_interval` 45 s, `growth_food_min`,
`growth_food_cost`), `starvation.work_factor` (0.5), `road.speed_mult` (1.6), `demolish_refund` (0.5),
`cancel_refund` (1.0).

### buildings.json

| Feld | Bedeutung |
|---|---|
| `name`, `names.good` / `names.evil` | Anzeigename (je Fraktion) |
| `label` / `labels` | kurzer Text auf dem Platzhalter |
| `size` | `[Breite, Höhe]` in Kacheln |
| `cost`, `build_time` | Baukosten, Bauarbeit in Sekunden eines Bauarbeiters |
| `housing` | Wohnplätze |
| `territory_radius` | Gebiet in Kacheln |
| `hp`, `armor` | Leben, Rüstung |
| `dropoff`, `gather_radius`, `gather_bonus` | Annahmestelle und Sammelbonus (0.25 = +25 %) |
| `workers`, `job`, `production`, `base_production` | Arbeitsplätze und Produktion je Arbeiter und Sekunde |
| `biome_efficiency` | Faktor je Biom (Bauernhof in der Wüste 0.35) |
| `summons` | Einheitenstufen oder Einheiten-IDs, die hier beschworen werden |
| `requires` / `requires_buildings` / `requires_deposit` | Forschung, Gebäude, Vorkommen als Voraussetzung |
| `menu` | Reiter im Baumenü: `economy`, `military`, `defense` |
| `max_per_kingdom`, `satisfaction`, `heal_aura`, `tower`, `forge`, `research` … | Sonderfunktionen (siehe `_hinweis`) |
| `sprites` / `sprite` | Grafik je Fraktion (siehe [Grafiken](grafiken.md)) |

### jobs.json

Berufe: `type` (`builder`, `gather`, `building`), `resource`, `deposits`, `gather_rate` (je Sekunde), `work_rate`,
`max_per_site`, `name`, `hint` (Text, wenn er nichts findet), `food_job` (arbeitet auch bei Hunger voll).

### units.json

| Feld | Bedeutung |
|---|---|
| `id`, `name`, `description`, `letter` | Kennung, Anzeige, Buchstabe auf dem Platzhalter |
| `faction` | `good`, `evil`, `any`, `neutral`, `wild` |
| `tier` | Stufe (`fighter`, `archer`, `spearman` …) – Gebäude beschwören nach Stufe die Einheit der eigenen Fraktion |
| `role` | `worker`, `king`, `combat`, `support`, `monster`, `spy`, … |
| `class` | Truppenklasse: `infantry`, `cavalry`, `ranged`, `mage`, `siege`, `support` |
| `hp`, `attack`, `attack_interval`, `range`, `armor`, `speed`, `regen`, `sight`, `aggro_range` | Kampfwerte |
| `bonus_vs` | Zuschlag gegen Klassen: `{"cavalry": 1.0}` = +100 % |
| `armor_pierce`, `splash_radius`, `splash_factor`, `building_damage`, `heal`, `heal_range`, `projectile` | Besonderheiten |
| `cost`, `summon_time`, `kill_points` | Kosten, Beschwörungsdauer, Kampfpunkte für den Sieger |
| `requires` | Freischaltungen, z. B. `["unit:elite_good"]` (gibt eine Forschung frei) |
| `sprite` | Grafik (64 × 64 PNG) |

### troops.json

- `counters`: Angreifer-Klasse → `{Ziel-Klasse: Zuschlag}` (`"cavalry": {"ranged": 0.35}` = Reiter +35 % gegen
  Schützen).
- `forge.upgrades`: Schmiede-Stufen je Klasse – `per_level` (`{"attack": 0.1}` = +10 % je Stufe) und `cost` (eine
  Liste, ein Eintrag je Stufe; ein vierter Eintrag = vierte Stufe).
- `veterancy`: `ranks` (Name, nötige EP, Wertepunkte), `stats` (Wirkung je Wertepunkt), `max_per_stat`,
  `rank_bonus`, `xp_per_damage`, `kill_xp`, `auto_priority`.
- `skins.variants`: Aussehen (`id`, `name`, `faction`, `tint`, `trim`, `emblem`, `min_rank`).

### combat.json

`territory_bonus` (Heimvorteil 0.15), `damage_variance`, `armor_cap`, `regen_delay`, `leash_radius` (Monster
folgen so weit), `formation` (Abstand, Formen), `rest` (Rückzug zur Burg), `raids` (Monster-Streifzüge),
`lair_growth`, `new_lairs`, `camps` (Monsterlager: `per_1000_tiles`, Übungslager `near_start`, Monster je Biom).

### research.json

Je Forschung: `faction`, `branch` (`military`, `magic`, `economy`, `mana`), `tier` (1–4), `cost`, `time`,
`requires` (andere Forschungen) und `effects`:

- `{"type": "unlock", "id": "unit:elite_good"}` – schaltet Einheit, Gebäude (`building:<id>`), Zauber
  (`spell:<id>`) oder Beschwörung in einem Gebäude (`summon:<gebäude>:<einheit>`) frei.
- `{"type": "modifier", "key": "attack.fighter", "factor": 1.1}` – Faktor auf einen Wert (Schlüssel siehe
  `_hinweis`: `hp@combat` = alle Truppen, `attack#cavalry` = eine Klasse, `production.food`, `spell_cost` …).
- `{"type": "bonus", "key": "spell_range", "add": 8}` – Zuschlag (Zauberreichweite, Zufriedenheit, Spione …).

### spells.json

`settings.cast_range_outside` (16 Felder ausserhalb des Gebiets), `upgrades` (Kampfpunkt-Verbesserungen mit
`cost_kill_points` je Stufe) und `spells`: `mana_cost`, `upkeep` (Mana/s), `cooldown`, `radius`, `duration`,
`effects`.

### heroes.json

`settings` (`max_heroes`, Kosten je weiterem Held `cost_per_owned`, Erfahrung `levels`, Teilung `xp_share`,
`training`, Wiederbelebung `revive_*`, Führung `leadership`, Talente `generic_talents`, Namen), `heroes` (Werte unter
`stats`, `cost`, `abilities`, `leadership`, `talents`) und `abilities` (Werte je Rang I–III).

### diplomacy.json

`reputation.tiers` (Stufen und Farben), `events` (Ruf-Änderungen: `attack: -5`, `declare_war: -30`, Gerüchte
`rumour_*`), `gifts` (`value_per_point`, `max_per_gift`, Ermüdung `saturation` / `half_life`), `treaties` (je Vertrag
`min_reputation`, `keep_min`, `rep_per_hour`, `cancel_penalty`; Annahme-Chance `chance_base` / `chance_span`),
`trade` (`base_margin`, `daily_value_limit`), `annex` (`min_reputation`, `intimidation_ratio`), `threat`,
`village` (Milizen, Nachschub), `messenger` (Boten).

### espionage.json

`discovery` (Gewichte der Gebäude, `per_population`, `per_army_power`, Stufen `tiers`), `aggression`, `cloak`
(`reduction` 0.4), `awareness` (`rumour` 30, `discovered` 60, `rise_per_minute`), `intel`, `reports`, `spies`
(`max_base`, `levels`, `detect_base`, `vigilance`, Dauer der Aufträge).

### ai.json

`kingdom_names`, `personalities` (z. B. `aggressive`: mehr Armee, frühere Wellen), `people_personality`,
`difficulty.<stufe>` (Anzahl Reiche je Kartengrösse `kingdoms`, erste Welle `first_attack_minutes`,
`patience_minutes`, `wave_interval`, `wave_min_size`, `first_wave_max`, `army_size_mult`, `awareness_mult`,
`retreat_ratio`), `build_order`, `jobs`, `research`, `army` (`composition`, `size_by_minute`, `max_units`), `waves`,
`rivalry` (`war_at`, `peace_at`), `forge`, `fortify`, `siege`, `routes`.

### difficulties.json

Je Stufe: `enemy_income_mult`, `enemy_strength_mult`, `ai_think_interval`, `ai_aggression_mult`,
`monster_strength_mult`, `monster_growth_mult`, `monster_raid_mult`, `player_start_resources_mult`, `description`.
`default` = vorgewählte Stufe.

### satisfaction.json

`base` (60), Ursachen `food`, `housing`, `safety`, `idle`, Grundwerte je `faction` / `people`, `effects.work_curve`
(Arbeitsleistung je Zufriedenheit), `defection` (Überlaufen unter `below` 25), `betrayal` (Verrat unter 20),
`hidden_spy`, `feast` (Kosten, Bonus, Dauer, Abklingzeit).

### events.json

`settings` (Würfeltakt `check_interval`, Chance `chance_per_check`, frühestens `first_event_minutes`, Pausen
`global_min_gap` und `kingdom_min_gap`, Häufigkeit und Stärke je Schwierigkeit) und `events` (siehe
[Neues Ereignis](#neues-ereignis)).

### daynight.json

`phases` (Uhrzeit von Morgen, Tag, Abend, Nacht), `global` (Wirkung auf alle, z. B. nachts `sight: 0.8`),
`wild` (Monster), `monsters` (Streifzüge und Nachwuchs nachts), `tint` (Farbe der Abdunklung).

### siege.json

`nav` (eingeschlossene Flächen), `breach` (Bresche), `repair` (Reparatur durch Bauarbeiter), `towers`, `safety`
(Zufriedenheit durch Mauerring und Türme), `segments` (`line_max`).

### trade.json

`caravan_unit`, `caravan_cost`, `respawn_seconds`, `loot_share`, `routes`, `cut` (wann ein Weg abgeschnitten ist und
wieder öffnet), `supply` (Versorgung fern vom Gebiet).

### help.json

`sections`: die Zeilen des Reiters „Steuerung“ – je Zeile `action` (Name aus `project.godot`, die Taste wird
automatisch gelesen) oder `keys` (fester Text) und `text`. `topics`: die Kurztexte des Reiters „Spielablauf“.
Der Reiter „Schwierigkeit“ entsteht aus `difficulties.json`.

### tutorial.json

`game` (Seed, Kartengrösse, Schwierigkeit der Tutorial-Partie), `settings` (Weiter-Pause, Schutzdauer
`protect_max_minutes`, Schonfrist `grace_minutes`, Schwellen für Kamera, Zoom und Strassen), `aliases`
(fraktionsabhängige Forschung und Zauber) und `steps`: je Schritt `chapter`, `id`, `title`, `text` (mit Platzhaltern
`{b:house}`, `{u:scout}`, `{r:healing}`, `{s:heal_spell}`, `{key:toggle_help}`), `highlight`, `world`, `condition`,
`skippable`, `grant`, `promote`, `focus`, `requires_hud` – alle Werte stehen im `_hinweis` der Datei.

## Beispiele

### Billigere Häuser

`data/buildings.json`, Eintrag `"id": "house"`:

```json
"cost": {"wood": 25},
"build_time": 20,
"housing": 4,
```

ändern zu

```json
"cost": {"wood": 15},
"build_time": 12,
"housing": 5,
```

Häuser kosten jetzt 15 Holz, stehen schneller und bieten 5 statt 4 Plätze. Die KI profitiert genauso.

### Stärkere Ritter

`data/units.json`, Eintrag `"id": "elite_good"` (BÖSE: `elite_evil`, der Schreckensritter):

```json
"hp": 285,
"attack": 26,
"armor": 0.36,
```

ändern zu

```json
"hp": 330,
"attack": 30,
"armor": 0.4,
"bonus_vs": {"infantry": 0.15},
```

`bonus_vs` gibt ihnen zusätzlich +15 % Schaden gegen Fusstruppen. Rüstung höchstens bis `combat.json → armor_cap`.
Ebenso: Speerträger noch stärker gegen Reiter – `spearman_good` → `"bonus_vs": {"cavalry": 1.5}` (+150 %); Reiter
weniger stark gegen Schützen – `troops.json` → `counters.cavalry.ranged` 0.35 → 0.2.

### Mehr Dörfer

`data/worldgen.json`, Abschnitt `villages`:

```json
"count_by_size": [[256, 6], [512, 10], [1024, 16]],
```

ändern zu

```json
"count_by_size": [[256, 8], [512, 14], [1024, 22]],
```

Kleine Karten haben jetzt 8 Dörfer, mittlere 14, grosse 22. Liegen sie zu dicht, `min_between` senken; näher am
Start: `min_dist_start` (50) senken. Grössere Dörfer: `"size": [3, 5]` (Hütten je Dorf).

> Achtung: Das ändert die Welt bei gleichem Seed – ältere Spielstände lassen sich danach nicht mehr laden (siehe
> [Spielstände](#spielstände-und-datenänderungen)).

### Neue Einheit hinzufügen

Beispiel: ein **Hellebardier** (GUT) und sein BÖSES Gegenstück, die **Schnitter**, in der Kaserne nach der
Forschung *Schildwall* / *Dornenpanzer*.

**1. Einheit anlegen** – `data/units.json`, in der Liste `units` zwei Einträge ergänzen (am einfachsten einen
bestehenden wie `spearman_good` kopieren und anpassen). Wichtig ist eine **neue Stufe** (`tier`), denn Gebäude
beschwören je Stufe die Einheit der eigenen Fraktion:

```json
{
  "id": "halberdier_good",
  "name": "Hellebardier",
  "faction": "good",
  "tier": "halberdier",
  "role": "combat",
  "class": "infantry",
  "letter": "Hb",
  "description": "Lange Hellebarde: gut gegen Reiter und schwere Fusstruppen.",
  "requires": ["unit:halberdier_good"],
  "bonus_vs": {"cavalry": 0.6, "infantry": 0.15},
  "speed": 1.9, "radius": 16, "sight": 6, "food_per_day": 8, "can_work": true, "carry": 10,
  "hp": 170, "attack": 15, "attack_interval": 1.4, "range": 1.3, "armor": 0.28,
  "aggro_range": 5, "regen": 0.6,
  "cost": {"wood": 40, "ore": 25, "food": 15, "mana": 8},
  "summon_time": 20,
  "kill_points": 3,
  "sprite": "res://assets/sprites/units/halberdier_good.png"
},
```

Den BÖSEN Eintrag genauso mit `"id": "halberdier_evil"`, `"name": "Schnitter"`, `"faction": "evil"`,
`"requires": ["unit:halberdier_evil"]` und `halberdier_evil.png`.

**2. Gebäude zuordnen** – `data/buildings.json`, Eintrag `barracks`: die neue Stufe in `summons` ergänzen:

```json
"summons": ["fighter", "spearman", "archer", "crossbow", "heavy", "elite", "halberdier"],
```

**3. Freischalten** – `data/research.json`: in den `effects` von `good_shields` (Schildwall) bzw. `evil_thorns`
(Dornenpanzer) ergänzen:

```json
{"type": "unlock", "id": "unit:halberdier_good"}
```

Ohne Schritt 3 (und ohne `requires` in Schritt 1) ist die Einheit sofort verfügbar.

**4. Grafik (optional)** – `assets/sprites/units/halberdier_good.png` und `halberdier_evil.png`, 64 × 64,
transparent. Ohne Datei zeichnet das Spiel einen Kreis mit dem Buchstaben „Hb“. Skins: `halberdier_good_royal.png`
usw. (siehe [Grafiken](grafiken.md)). Neue Dateien in `assets_liste.md` eintragen.

**5. KI (optional)** – `data/ai.json` → `army.composition`: `"halberdier": 1.5` – sonst beschwört die KI die neue
Einheit nicht gezielt.

**6. Prüfen** – Spiel starten, Kaserne bauen, Forschung abschliessen (mit F3 → F9 gibt es Rohstoffe), die Einheit
beschwören; der Tooltip des Knopfs zeigt Klasse und Konter. Dann `tests/run_smoke.sh 600` (siehe
[Testen](testen.md)) und `python3 tools/doku_tabellen.py` für die Tabellen der Anleitung.

### Neues Ereignis

Ereignisse brauchen eine **bekannte Art** (`kind`): `drought` (Dürre-artig, mit Gebiet), `plague`, `magic_storm`,
`monster_wave`, `refugees`, `wanderers` oder `kingdom_buff` (Wirkung auf ein Reich – die einfachste Art). Beispiel:
eine **Goldene Ader**, die Bergleuten eine Weile mehr Erz bringt – in `data/events.json` in die Liste `events`:

```json
{
  "id": "golden_vein",
  "name": "Goldene Ader",
  "kind": "kingdom_buff",
  "positive": true,
  "letter": "G",
  "color": "#e8c84a",
  "icon": "res://assets/ui/icons/event_golden_vein.png",
  "description": "Bergleute stossen auf eine reiche Ader: mehr Erz und gute Laune.",
  "weight": 2,
  "min_minutes": 30,
  "cooldown_minutes": 120,
  "duration": [480, 720],
  "targets": ["player", "ai"],
  "modifiers": {"gather.ore": 1.5},
  "satisfaction": 4
},
```

- `weight` – wie oft es im Vergleich zu den anderen gewählt wird; `min_minutes` – frühestens ab Spielminute;
  `cooldown_minutes` – Pause, bis es wieder kommen kann; `duration` – Dauer in Sekunden (von–bis).
- `modifiers` – Faktoren wie bei der Forschung (`gather.ore`, `production.food`, `speed`, `spell_cost` …).
- Ein **schlechtes** Ereignis: `"positive": false` und z. B. `"modifiers": {"gather": 0.85, "speed": 0.9}`,
  `"satisfaction": -5` („Kältewelle“).
- Das Symbol ist optional (ohne Datei: farbiger Kreis mit `letter`).
- Testen: F3 → Reichsübersicht (L) → Ereignis auswählen → „Auslösen“.

### Weitere schnelle Änderungen

| Wunsch | Datei → Feld |
|---|---|
| Längere Tage | `game_config.json` → `time.seconds_per_day` erhöhen |
| Andere Tempostufen | `game_config.json` → `time.speed_steps` |
| Mehr Startvorräte | `economy.json` → `start.resources` |
| Mehr Nahrung pro Bauer | `buildings.json` → `farm` → `production.food` |
| Schnellere Bewohner | `units.json` → `villager` → `speed` |
| Billigere Truppen | `units.json` → `cost` und `summon_time` |
| Mehr oder weniger Monsterlager | `combat.json` → `camps.per_1000_tiles`, Übungslager `camps.near_start` |
| Stärkerer Heimvorteil | `combat.json` → `territory_bonus` |
| Schnellere Forschung | `research.json` → `time` (Sekunden), Kosten unter `cost` |
| Billigere Zauber | `spells.json` → `mana_cost`, `cooldown`; Reichweite `settings.cast_range_outside` |
| Mehr Mana-Maximum | `resources.json` → `mana` → `cap`; Kampfpunkt-Verbesserungen `spells.json` → `upgrades` |
| Helden | `heroes.json` → `heroes` (`stats`, `cost`, Fähigkeiten, Talente), `abilities` (Werte je Rang), `settings` (`levels`, `xp_share`, `training`, `max_heroes`) |
| Schmiede | `troops.json` → `forge.upgrades` (`"per_level": {"attack": 0.15}` = +15 % je Stufe) |
| Schnellere Ränge | `troops.json` → `veterancy.ranks` (`"xp": 40` für Soldat …), mehr Punkte `"points"`; Wirkung je Punkt `veterancy.stats` |
| Neues Aussehen | `troops.json` → `skins.variants`: `{"id": "winter", "name": "Winterwacht", "faction": "good", "tint": "#cfe3ff", "trim": "#ffffff", "emblem": "star"}`, Grafik `assets/sprites/units/<einheit>_winter.png` |
| Ruf schneller verbessern | `diplomacy.json` → `gifts.value_per_point` senken; Lieblingswaren `peoples.json` → `gift_preferences` |
| Verträge leichter | `diplomacy.json` → `treaties.<protection/trade/alliance>.min_reputation` |
| Bessere Handelskurse | `diplomacy.json` → `trade.base_margin`; je Volk `peoples.json` → `trade_rates`, `trade_bonus` |
| Spätere erste Welle | `ai.json` → `difficulty.normal.first_attack_minutes` 45 → 60 |
| Spione schwerer zu entdecken | `espionage.json` → `spies.detect_base` 0.03 → 0.02 |
| Neues Volk | `peoples.json`: Eintrag mit `"faction": "neutral"`, `village_title`, `village_names`, `produces`, `militia_unit` und `special_unit` (beide in `units.json` anlegen) – Dörfer dieses Volks entstehen dann automatisch |

## Balancing selbst nachjustieren

| Was | Datei → Schlüssel |
|---|---|
| Wie früh und hart die KI angreift | `ai.json` → `difficulty.<stufe>`: `first_attack_minutes`, `patience_minutes`, `wave_interval`, `first_wave_max`, `army_size_mult` |
| Wachstum der KI-Armee über lange Partien | `ai.json` → `army.size_by_minute` (bis 32 h), `army.max_units` |
| Wie schnell die KI den Spieler bemerkt | `espionage.json` → `awareness` (`rise_per_minute`, `rumour`, `discovered`, `patience_floor`) |
| Stärke und Ertrag der Gegner, Startvorräte | `difficulties.json` |
| Häufigkeit der Ereignisse | `events.json` (`chance_per_check`, Abstände, Abklingzeiten) |
| Monster-Streifzüge, Wachstum der Lager | `combat.json` (`raids`, `lair_growth`) |
| Zufriedenheit, Überläufer | `satisfaction.json` |
| Wirtschaft (Ertrag, Verbrauch) | `economy.json`, `buildings.json` |

Messwerte und Hintergründe: [Balancing](balancing.md).

## Nach dem Ändern prüfen

1. Spiel im Editor starten (F5). Ein Tippfehler im JSON erscheint als roter Fehler unten im Editor
   (*Ausgabe*) – meist ein fehlendes oder überzähliges Komma.
2. Für grössere Änderungen den Rauchtest laufen lassen: `GODOT=/pfad/zu/godot tests/run_smoke.sh 600`
   (siehe [Testen](testen.md)). Er spielt beide Fraktionen im Zeitraffer und meldet Fehler.
3. `python3 tools/doku_tabellen.py` – erneuert die Tabellen der [Spielanleitung](spielanleitung.md).
   `python3 tools/doku_tabellen.py --check` prüft nur, ob sie aktuell sind.

## Spielstände und Datenänderungen

- Geänderte Spieldaten: alte Spielstände laden weiter, die Liste zeigt einen gelben Hinweis.
- Ergibt derselbe Seed eine **andere Welt** (Änderungen an `worldgen.json` oder `biomes.json`), lassen sich alte
  Spielstände nicht mehr laden – sie werden in der Liste als nicht ladbar angezeigt. Wer am Generator arbeitet, erhöht
  `WorldGenerator.VERSION` (siehe [Architektur](architektur.md#speichern-und-laden)).
- IDs nicht umbenennen: Spielstände speichern Gebäude, Einheiten und Forschung über ihre ID.
