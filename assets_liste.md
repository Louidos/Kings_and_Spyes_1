# Grafikliste

Alle Grafiken, die das Spiel braucht, mit Dateinamen und Ablageort.
Fehlt eine Datei, erzeugt das Spiel automatisch einen Platzhalter.
Liegt die Datei am richtigen Ort, wird sie beim nächsten Start verwendet – ohne Code-Änderung.

**Status:** ✅ = das Spiel lädt diese Datei, sobald sie da ist (alle Phasen 1–10 sind fertig; jede Datei,
die der Code laden kann, steht in dieser Liste). Eine Prüfung: jeder Pfad `res://assets/…` aus `data/*.json`
und `scripts/` kommt hier vor.

Wie man Grafiken mit der Bild-KI erzeugt, verkleinert, ablegt und in Godot importiert, steht in
**[docs/grafiken.md](docs/grafiken.md)**.

## Inhalt

- [Allgemeine Regeln](#allgemeine-regeln) (Grössen, Format, Stil, Prompt-Vorlagen)
- [Phase 1 – Gelände](#-phase-1--gelände-64--64-nahtlos) · [Menü](#-menü)
- [Phase 2 – Dorf und Wirtschaft](#-phase-2--dorf-und-wirtschaft)
- [Phase 3 – Einheiten, Kampf, Monster](#-phase-3--einheiten-kampf-monster)
- [Phase 4 – Forschung und Magie](#-phase-4--forschung-und-magie)
- [Phase 5 – Helden](#-phase-5--helden)
- [Phase 6 – Neutrale Völker](#-phase-6--neutrale-völker)
- [Phase 7 – Gegner und Spionage](#-phase-7--gegner-und-spionage)
- [Phase 8 – Zufriedenheit, Ereignisse, Monster, Tag/Nacht](#-phase-8--zufriedenheit-ereignisse-monster-tagnacht)
- [Phase 9 – Belagerung und Handel](#-phase-9--belagerung-und-handel)
- [Phase 10 – Speichern, Einstellungen, Hilfe](#-phase-10--speichern-einstellungen-hilfe)
- [Truppen – neue Einheiten, Schmiede, Aussehen](#-truppen--neue-einheiten-schmiede-aussehen-skins)
- [Oberfläche](#-oberfläche-fenster-obere-leiste-auswahlfenster)
- [Übersicht der Ordner](#übersicht-der-ordner)

---

## Allgemeine Regeln

| Kategorie | Grösse (px) | Hintergrund | Ordner |
|---|---|---|---|
| Gelände-Kacheln | 64 × 64 | **voll deckend**, nahtlos kachelbar | `assets/sprites/terrain/` |
| Einheiten | 64 × 64 | transparent | `assets/sprites/units/` |
| Helden | 64 × 64 (+ Porträt 128 × 128) | transparent | `assets/sprites/heroes/` |
| Gebäude | 128 × 128 (gross: 256 × 256) | transparent | `assets/sprites/buildings/` |
| Ressourcen auf der Karte | 64 × 64 | transparent | `assets/sprites/resources/` |
| Effekte | 64 × 64 | transparent | `assets/sprites/effects/` |
| UI-Icons | 32 × 32 | transparent | `assets/ui/icons/` |
| Menü-Hintergrund | 1920 × 1080 | voll deckend | `assets/ui/` |

- Format: **PNG**, Dateinamen klein, ohne Umlaute und Leerzeichen.
- Stil: **Anime, von oben (Top-Down)**, farbenfroh, klare Silhouetten, gut lesbare Umrisse.
- Einheiten und Gebäude zentriert, mit etwas Rand, kein Schlagschatten auf dem Hintergrund.
- Blickrichtung der Einheiten: nach unten (zum Betrachter). Spiegelung für links/rechts macht das Spiel.

### Prompt-Vorlagen für die Bild-KI

Einheit / Gebäude:
> anime style game sprite, top-down view, **[MOTIV]**, vibrant colors, clean bold outlines,
> clear silhouette, centered, transparent background, no text, 64x64 pixel game asset

Gelände-Kachel:
> seamless tileable texture, top-down view, anime style, **[GELÄNDE]**, vibrant colors,
> flat even lighting, no shadows from objects, fills the entire square, 64x64 pixel game tile

Tipp: Bild in hoher Auflösung erzeugen (z. B. 512 × 512) und danach auf die Zielgrösse verkleinern.
Gelände-Kacheln vor dem Verkleinern auf Nahtlosigkeit prüfen (Kachel 2 × 2 nebeneinanderlegen).

---

## ✅ Phase 1 – Gelände (64 × 64, nahtlos)

Je Biom 4 Varianten. Die Varianten werden auf der Karte zufällig gemischt, damit kein Muster entsteht.
Die Varianten sollten sich nur leicht unterscheiden (gleiche Grundfarbe, andere Details).

| Datei | Biom | Inhalt |
|---|---|---|
| `terrain_plains_1.png` … `terrain_plains_4.png` | Ebene | saftiges Gras, vereinzelte Blumen |
| `terrain_forest_1.png` … `terrain_forest_4.png` | Wald | dichte Baumkronen von oben |
| `terrain_mountains_1.png` … `terrain_mountains_4.png` | Berge | graue Felsen, Gipfel mit Schnee |
| `terrain_swamp_1.png` … `terrain_swamp_4.png` | Sumpf | Morast, Wasserpfützen, Schilf |
| `terrain_desert_1.png` … `terrain_desert_4.png` | Wüste | Sand mit Dünenwellen |
| `terrain_volcanic_1.png` … `terrain_volcanic_4.png` | Vulkangebiet | dunkles Gestein, glühende Lavarisse |

Ablage: `assets/sprites/terrain/` (24 Dateien). Weniger als 4 Varianten gehen auch –
dann in `data/biomes.json` bei `sprites` einfach weniger Pfade eintragen.

## ✅ Menü

| Datei | Inhalt |
|---|---|
| `assets/ui/menu_background.png` | Hintergrund des Hauptmenüs (1920 × 1080), z. B. zwei Königreiche, Licht gegen Schatten |

---

## ✅ Phase 2 – Dorf und Wirtschaft

**Ressourcen-Icons** (`assets/ui/icons/`, 32 × 32, transparent) – Ressourcenleiste oben:

| Datei | Inhalt |
|---|---|
| `icon_wood.png` | Holz (Holzscheite) |
| `icon_stone.png` | Stein (Steinblock) |
| `icon_ore.png` | Erz (Erzbrocken mit blauem Schimmer) |
| `icon_food.png` | Nahrung (Brotlaib, Äpfel) |
| `icon_mana.png` | Mana (leuchtender violetter Kristall) |

**Rohstoffvorkommen auf der Karte** (`assets/sprites/resources/`, 64 × 64, transparent, von oben):

| Datei | Inhalt |
|---|---|
| `res_trees.png` | Baumgruppe (2–3 Baumkronen) auf freiem Feld |
| `res_stone.png` | Haufen grauer Felsbrocken |
| `res_ore.png` | dunkler Fels mit blauen Erzkristallen |
| `res_berries.png` | Beerenstrauch / Wildspuren |
| `res_berries_empty.png` | derselbe Strauch abgeerntet (ohne Beeren) – optional |
| `res_mana_spring.png` | leuchtende violette Quelle mit Steinkreis |

Wald selbst braucht kein eigenes Bild – das Waldgelände ist die Grafik.

**Strasse** (`assets/sprites/terrain/`, 64 × 64, **voll deckend, nahtlos kachelbar**):
`terrain_road.png` – festgetretener Weg / Kopfsteinpflaster. Die Kanten müssen so gestaltet sein,
dass beliebig viele Strassenkacheln nebeneinander einen durchgehenden Weg ergeben.

**Gebäude** (`assets/sprites/buildings/`, transparent, von oben) – je Fraktion eine eigene Optik
(GUT: hell, Fachwerk/Stein, blaue Dächer – BÖSE: dunkel, Stacheln, rote Akzente):

| Datei GUT | Datei BÖSE | Gebäude | Grösse |
|---|---|---|---|
| `castle_good.png` | `castle_evil.png` | Königsburg | 256 × 256 |
| `house_good.png` | `house_evil.png` | Wohnhaus | 128 × 128 |
| `storehouse_good.png` | `storehouse_evil.png` | Lager | 128 × 128 |
| `lumberyard_good.png` | `lumberyard_evil.png` | Holzfällerhütte | 128 × 128 |
| `quarry_good.png` | `quarry_evil.png` | Steinmetzhütte | 128 × 128 |
| `mine_good.png` | `mine_evil.png` | Erzmine | 128 × 128 |
| `hunter_good.png` | `hunter_evil.png` | Jägerhütte | 128 × 128 |
| `farm_good.png` | `farm_evil.png` | Bauernhof (mit Feldern) | 128 × 128 |
| `mana_well_good.png` | `mana_well_evil.png` | Manabrunnen | 128 × 128 |

Die Grafik füllt die Grundfläche des Gebäudes (Burg 4 × 4 Felder, sonst 2 × 2 Felder).
Baustellen zeichnet das Spiel selbst (halbtransparent mit Gerüst).

**Bewohner** (`assets/sprites/units/`, 64 × 64, transparent):
`villager_good.png` (einfacher Mensch in Leinen, freundlich), `villager_evil.png` (kleiner Kobold/Goblin-Diener).
Die Figur steht mit den Füssen im unteren Drittel des Bildes. Der Beruf wird vom Spiel nicht über die
Grafik gezeigt (später eventuell eigene Grafiken pro Beruf).

## ✅ Phase 3 – Einheiten, Kampf, Monster

**Einheiten** (`assets/sprites/units/`, 64 × 64, transparent, von oben, Blick nach unten,
Füsse im unteren Drittel). Fehlt eine Datei, zeichnet das Spiel einen farbigen Kreis mit Buchstaben
(Monster: Raute).

| Datei GUT | Datei BÖSE | Einheit | Aussehen |
|---|---|---|---|
| `king_good.png` | `king_evil.png` | König / Dunkler König | prächtig, Krone, Umhang (gut: Gold/Blau, böse: Schwarz/Rot) |
| `scout_good.png` | `scout_evil.png` | Späher / Kobold | gut: schwacher Mensch mit Lederkappe; böse: kleines, flinkes Monster |
| `fighter_good.png` | `fighter_evil.png` | Schwertkämpfer / Schattenkrieger | Schwert und Schild |
| `archer_good.png` | `archer_evil.png` | Bogenschütze / Dunkelschütze | Bogen bzw. Armbrust |
| `elite_good.png` | `elite_evil.png` | Ritter / Schreckensritter | schwere Rüstung, gut: glänzend, böse: Stacheln |
| `medic_good.png` | `medic_evil.png` | Heiler / Blutpriester | Robe, Heilstab bzw. Ritualdolch |

**Monster** (`assets/sprites/units/`, 64 × 64, transparent):

| Datei | Monster |
|---|---|
| `monster_wolf.png` | Wolf (grau-braun, sprungbereit) |
| `monster_spider.png` | Riesenspinne (dunkelviolett) |
| `monster_golem.png` | Steingolem (grosser Felskörper) |

**Gebäude** (`assets/sprites/buildings/`, 128 × 128, transparent):

| Datei GUT | Datei BÖSE | Gebäude |
|---|---|---|
| `barracks_good.png` | `barracks_evil.png` | Kaserne (Übungsplatz, Waffenständer) |
| `infirmary_good.png` | `infirmary_evil.png` | Krankenstation (Zelt/Haus mit Heilzeichen) |
| `monster_lair.png` | – | Monsterhöhle (Felshöhle mit Knochen, eine Grafik für alle) |

**Effekte** (`assets/sprites/effects/`, transparent):

| Datei | Grösse | Inhalt |
|---|---|---|
| `arrow.png` | 32 × 8 | Pfeil, Spitze nach rechts (wird in Flugrichtung gedreht) |
| `bolt.png` | 32 × 8 | dunkles Geschoss mit violettem Schimmer, Spitze nach rechts |

Lebensbalken, Auswahlringe, Rahmenauswahl, Befehlsmarkierungen, Sammelpunkt-Fahne, Treffer und
Gefallene zeichnet das Spiel selbst.

## ✅ Phase 4 – Forschung und Magie

GUT = helles Licht (Gold, Weiss), BÖSE = dunkles Violett, Flüche.

**Gebäude** (`assets/sprites/buildings/`, 128 × 128, transparent):

| Datei GUT | Datei BÖSE | Gebäude |
|---|---|---|
| `library_good.png` | `library_evil.png` | Bibliothek (heller Turm mit Büchern, Gold) / Dunkles Archiv (violett, Schriftrollen, Kerzen) |

**Beschworene Einheiten** (`assets/sprites/units/`, 64 × 64, transparent):

| Datei | Einheit | Aussehen |
|---|---|---|
| `light_guardian.png` | Lichtgeist (GUT) | leuchtende, halb durchsichtige Gestalt aus goldenem Licht, Schwert |
| `shadow_servant.png` | Schattendiener (BÖSE) | dunkle, rauchige Gestalt mit violetten Augen, Klauen |

**Zauber-Symbole** (`assets/ui/icons/`, 64 × 64, transparent – werden in der Zauberleiste auf ~56 px
verkleinert). Fehlt eine Datei, zeichnet das Spiel ein Feld in der Zauberfarbe mit Buchstaben.

| Datei | Zauber | Motiv |
|---|---|---|
| `spell_light_blessing.png` | Lichtsegen (GUT) | goldenes Schwert in einem Lichtkranz |
| `spell_healing_light.png` | Heilendes Licht (GUT) | weiss-goldene Hand mit Lichtfunken |
| `spell_light_veil.png` | Lichtschleier (GUT) | heller, durchscheinender Schleier |
| `spell_blessed_rain.png` | Segensregen (GUT) | Wolke mit goldenen Regentropfen über einer Ähre |
| `spell_call_guardians.png` | Ruf des Lichts (GUT) | Lichtsäule mit Gestalt |
| `spell_curse_weakness.png` | Fluch der Schwäche (BÖSE) | gebrochenes Schwert in violettem Rauch |
| `spell_dark_mending.png` | Dunkle Erneuerung (BÖSE) | violettes Herz mit dunklen Ranken |
| `spell_shadow_cloak.png` | Schattenmantel (BÖSE) | Kapuzenumhang aus Schatten |
| `spell_dark_fog.png` | Finsterer Nebel (BÖSE) | violette Nebelschwaden mit Augen |
| `spell_shadow_brood.png` | Schattenbrut (BÖSE) | dunkles Portal mit Klauen |

Zauberwirkungen (Lichtringe, Regen, Nebel, Auren, Beschwörungs-Licht), Forschungsfenster und
Zauberleiste zeichnet das Spiel selbst.

## ✅ Phase 5 – Helden

**Helden** (`assets/sprites/heroes/`): Figur 64 × 64 (transparent, von oben, Blick nach unten, etwas
grösser und prächtiger als normale Einheiten) und Porträt 128 × 128 (Brustbild, für Heldenfenster und
Heldenleiste). Fehlt eine Datei, zeichnet das Spiel einen Kreis in der Heldenfarbe mit Buchstaben (als
Porträt auf dunklem Grund in der Heldenfarbe, gefallene Helden grau).

| Figur | Porträt | Held | Aussehen |
|---|---|---|---|
| `hero_paladin.png` | `portrait_paladin.png` | Paladin (GUT) | Ritter in goldweisser Rüstung, Schild mit Sonne, Lichtschimmer |
| `hero_star_mage.png` | `portrait_star_mage.png` | Sternenmagierin (GUT) | Magierin in dunkelblauer Robe mit Sternen, leuchtender Stab |
| `hero_ranger.png` | `portrait_ranger.png` | Waldläuferin (GUT) | Elfe in grünem Umhang, Langbogen, Köcher |
| `hero_necromancer.png` | `portrait_necromancer.png` | Nekromant (BÖSE) | hagere Gestalt in violett-schwarzer Robe, Schädelstab |
| `hero_warlord.png` | `portrait_warlord.png` | Kriegsherr (BÖSE) | grosser Orkhäuptling, Axt, Fellumhang, Kriegsbemalung |
| `hero_blade_dancer.png` | `portrait_blade_dancer.png` | Klingentänzerin (BÖSE) | Blutelfe mit zwei gebogenen Klingen, rot-schwarz |

**Gebäude** (`assets/sprites/buildings/`, 128 × 128): `hero_hall_good.png` (Heldenhalle: Halle mit Bannern
und Statuen, Gold) / `hero_hall_evil.png` (Halle der Schatten: dunkle Halle mit violetten Fackeln).

**Beschwörung** (`assets/sprites/units/`, 64 × 64): `skeleton.png` (Skelett mit rostigem Schwert).

**Fähigkeiten-Symbole** (`assets/ui/icons/`, 64 × 64, in der Farbe der Fähigkeit):

| Datei | Fähigkeit | Datei | Fähigkeit |
|---|---|---|---|
| `ability_holy_strike.png` | Lichtschlag | `ability_soul_bolt.png` | Seelenblitz |
| `ability_holy_aura.png` | Heilige Aura | `ability_raise_dead.png` | Totenerweckung |
| `ability_divine_shield.png` | Göttlicher Schild | `ability_curse_aura.png` | Fluchaura |
| `ability_starfire.png` | Sternenfeuer | `ability_whirlwind.png` | Wirbelwind |
| `ability_star_jump.png` | Sternensprung | `ability_war_cry.png` | Kriegsschrei |
| `ability_star_well.png` | Sternenquelle | `ability_blood_toll.png` | Blutzoll |
| `ability_arrow_rain.png` | Pfeilhagel | `ability_shadow_step.png` | Schattenschritt |
| `ability_battle_cry.png` | Schlachtruf | `ability_venom_blade.png` | Giftklinge |
| `ability_eagle_eye.png` | Adlerauge | `ability_evasion.png` | Ausweichen |

Heldenmarkierung, Fähigkeitseffekte, Stufenaufstieg und EP-Anzeigen zeichnet das Spiel selbst.

## ✅ Phase 6 – Neutrale Völker

Acht neutrale Völker leben in Dörfern. Jedes Dorf zeigt sein Volk über die Grafiken; fehlt eine Datei,
zeichnet das Spiel ein Feld in der **Volksfarbe** (siehe `data/peoples.json` → `color`) mit Beschriftung.
Wird ein Dorf aufgenommen oder erobert, behält es seine Grafik (das Dorfzentrum heisst dann *Aussenposten*).

**Dorfzentren** (`assets/sprites/buildings/`, 128 × 128, transparent, 3 × 3 Kacheln):

| Datei | Volk | Motiv |
|---|---|---|
| `village_dwarves.png` | Zwerge | steinerne Halle am Fels, Schmiedeesse mit Glut, Ambosse, Erzkarren |
| `village_halflings.png` | Halblinge | runde Hügelhöhle mit grüner Tür, Gemüsegarten, Pfeifenrauch |
| `village_wood_elves.png` | Waldelfen | Baumhalle aus lebenden Ästen, Laternen mit Mondlicht, Lianen |
| `village_lizardfolk.png` | Echsenvolk | Pfahlbau aus Schilf im Sumpf, Totems mit Schuppenmustern |
| `village_nomads.png` | Nomaden | grosses buntes Zelt, Teppiche, Kamelsattel, Handelskisten |
| `village_giants.png` | Riesen | grobe Steinhalle aus Felsblöcken, riesige Keule an der Wand |
| `village_water_spirits.png` | Wassergeister | Quelltempel mit Wasserbecken, leuchtende blaue Perlen, Nebel |
| `village_kobold_traders.png` | Koboldhändler | schiefer Markthügel mit Ständen, Münzhaufen, violette Laternen |
| `village_hall.png` | Rückfall | einfaches Dorfzentrum (Holzhalle mit Glocke), wenn ein Volk keine Grafik hat |

**Hütten** (`assets/sprites/buildings/`, 128 × 128, transparent, 2 × 2 Kacheln) – kleine Wohnhütte im Stil
des Volks (wie das Dorfzentrum, aber schlichter):
`village_hut_dwarves.png`, `village_hut_halflings.png`, `village_hut_wood_elves.png`,
`village_hut_lizardfolk.png`, `village_hut_nomads.png`, `village_hut_giants.png`,
`village_hut_water_spirits.png`, `village_hut_kobold_traders.png`

**Dorfmilizen** (`assets/sprites/units/`, 64 × 64, transparent):

| Datei | Einheit | Aussehen |
|---|---|---|
| `militia_dwarves.png` | Zwergenwache | gedrungener Zwerg mit Helm, Axt und Rundschild |
| `militia_halflings.png` | Halblingschleuderer | kleiner Halbling mit Schleuder, Lederweste |
| `militia_wood_elves.png` | Waldelfenwache | schlanke Elfe in Grün mit Kurzbogen |
| `militia_lizardfolk.png` | Echsenkrieger | Echsenmensch mit Speer und Schilfschild |
| `militia_nomads.png` | Nomadenwache | Wüstenkrieger mit Turban und Krummsäbel |
| `militia_giants.png` | Riesenwächter | Hügelriese mit Baumstamm-Keule (wirkt grösser als andere) |
| `militia_water_spirits.png` | Quellwächter | halb durchsichtige Wassergestalt mit Wasserkugel |
| `militia_kobold_traders.png` | Koboldwache | Kobold mit Laterne und Funkenstab |

**Volkskrieger** (`assets/sprites/units/`, 64 × 64, transparent – in der Kaserne bei Bündnis oder Aufnahme):

| Datei | Einheit | Aussehen |
|---|---|---|
| `dwarf_ironguard.png` | Eisenwache | schwer gepanzerter Zwerg, Turmschild, Kriegshammer |
| `halfling_slinger.png` | Schleudermeister | Halbling mit verzierter Schleuder und Steinbeutel |
| `wood_elf_ranger.png` | Blattschütze | Elfe mit Langbogen, Blätterumhang |
| `lizard_skirmisher.png` | Sumpfjäger | flinker Echsenmensch mit zwei Wurfspeeren |
| `nomad_rider.png` | Steppenreiter | Reiter auf Wüstenpferd mit Lanze |
| `giant_brute.png` | Hügelriese | riesiger Riese mit Felsbrocken auf der Schulter |
| `water_spirit_healer.png` | Quellgeist | leuchtender Wassergeist mit heilenden Tropfen |
| `kobold_bombardier.png` | Koboldsprenger | Kobold mit rauchender Bombe und Schutzbrille |

**Bote** (`assets/sprites/units/`, 64 × 64): `messenger.png` – leichtfüssiger Läufer mit Schriftrolle und
Umhängetasche (kämpft nie). Auf der Minikarte blinkt er als weiss umrandetes Quadrat.

Diplomatiefenster, Verträge und Ruf kommen ohne eigene Symbole aus (Text, Volksfarbe, Ruf-Balken) – dafür
sind keine Grafiken nötig.

Haussymbol der Dörfer und Ringe (rot = Krieg, gold = Bündnis) auf der Minikarte, Gebietsgrenzen in der
Volksfarbe und Ruf-Balken zeichnet das Spiel selbst. Händler/Karawane: siehe Phase 9 (`caravan_*.png`).

## ✅ Phase 7 – Gegner und Spionage

Gegnerische Königreiche bauen mit denselben Gebäuden und Einheiten wie der Spieler (Fraktion der
Gegenseite). Ihre Grenzen und Platzhalter erscheinen in der **Volksfarbe** (`data/peoples.json` → `color`).

**Spione** (`assets/sprites/units/`, 64 × 64, transparent – getarnt halb durchsichtig, enttarnt normal):

| Datei | Einheit | Aussehen |
|---|---|---|
| `spy_good.png` | Kundschafterin (GUT) | schlanke Gestalt mit hellblauem Kapuzenumhang, Fernrohr am Gürtel |
| `spy_evil.png` | Schattenspion (BÖSE) | geduckte Gestalt in violettem Schattenmantel, Dolch, glühende Augen |

**Gebäude** (`assets/sprites/buildings/`, 128 × 128, transparent):

| Datei | Gebäude | Motiv |
|---|---|---|
| `spy_den_good.png` | Kundschafterhaus (GUT) | schmales Holzhaus mit Ausguck, Brieftauben, Landkarten am Fenster |
| `spy_den_evil.png` | Schattenloge (BÖSE) | dunkles Steinhaus mit verhängten Fenstern, violette Laterne, Raben |

**Burgen je Volk** (`assets/sprites/buildings/`, 256 × 256, transparent, optional – ohne Datei nimmt das
Spiel die Burg der Fraktion `castle_good.png` / `castle_evil.png`):

| Datei | Volk | Motiv |
|---|---|---|
| `castle_humans.png` | Menschen | Steinburg mit blauen Bannern, Zinnen, Torhaus |
| `castle_high_elves.png` | Hochelfen | schlanke weisse Türme mit goldenen Spitzen |
| `castle_druids.png` | Druiden | Burg aus lebendem Holz, Steinkreis, Efeu |
| `castle_light_wardens.png` | Lichtwächter | helle Festung mit Sonnensymbol und Leuchtfeuer |
| `castle_griffin_riders.png` | Greifenreiter | Bergfeste mit Greifenhorsten auf den Türmen |
| `castle_star_mages.png` | Sternenmagier | Turmburg mit Sternwarte und blauen Kuppeln |
| `castle_blood_elves.png` | Blutelfen | rot-goldene Türme, scharfe Spitzen, Glutkristalle |
| `castle_orcs.png` | Orks | grobe Palisadenfeste mit Schädeln und Eisenspitzen |
| `castle_night_riders.png` | Nachtreiter | schwarze Festung mit Ställen und Mondbannern |
| `castle_warlocks.png` | Hexenmeister | Basaltburg am Lavastrom, violette Runen |
| `castle_undead.png` | Untote | verfallene Gruft-Festung, grüne Geisterlichter |
| `castle_demon_summoners.png` | Dämonenbeschwörer | Obsidianfeste mit Beschwörungskreis und Feuer |
| `castle_shadow_cult.png` | Schattenkult | Tempelburg im Nebel, schwarze Schleier |
| `castle_trolls.png` | Trolle | Felsenburg aus aufgetürmten Steinen, Knochenzaun |

**Effekte** (`assets/sprites/effects/`, 128 × 128, transparent): `ruin.png` – Trümmerhaufen von oben
(eingestürzte Mauern, verkohlte Balken); wird auf die Grundfläche des zerstörten Gebäudes gestreckt. Ohne
Datei zeichnet das Spiel einen graubraunen Rahmen mit Bruchlinien.

**Zauber-Symbole** (`assets/ui/icons/`, 64 × 64, wie die übrigen Zauber-Symbole):

| Datei | Zauber | Motiv |
|---|---|---|
| `spell_realm_veil.png` | Reichsschleier (GUT) | Burg hinter einem hellblauen, durchscheinenden Schleier |
| `spell_realm_shroud.png` | Reichsschatten (BÖSE) | Burg, von violettem Schattennebel verhüllt |

Burgsymbole und Ruinen-Kreuze auf der Minikarte, Kundschaft-Punkte, der Entdeckungsbalken oben und die
Fenster zeichnet das Spiel selbst.

## ✅ Phase 8 – Zufriedenheit, Ereignisse, Monster, Tag/Nacht

**Gebäude** (`assets/sprites/buildings/`, 128 × 128):

| Datei | Motiv |
|---|---|
| `tavern_good.png` | Fachwerk-Gasthaus mit Schild und Laternen |
| `tavern_evil.png` | düstere Schenke, grüne Laternen |
| `temple_good.png` | weisser Tempel mit Sonnenkuppel (3×3 – Grafik 128 × 128, gestreckt wie die Heldenhalle) |
| `temple_evil.png` | Schattenschrein aus schwarzem Stein, violette Flammen |

**Einheiten** (`assets/sprites/units/`, 64 × 64):

| Datei | Motiv |
|---|---|
| `refugee.png` | Flüchtling mit Bündel, zerlumpt |
| `wanderer.png` | Reisender mit Rucksack und Wanderstab |
| `monster_wyvern.png` | grüne Wyvern von oben, Flügel angelegt (Wolf, Spinne und Golem: siehe Phase 3) |

**Ereignis-Symbole** (`assets/ui/icons/`, 32 × 32):

| Datei | Motiv |
|---|---|
| `event_drought.png` | rissige Erde, Sonne |
| `event_plague.png` | grüne Wolke, Totenkopf |
| `event_magic_storm.png` | violetter Wirbel mit Blitz |
| `event_monster_wave.png` | Monsterkrallen |
| `event_refugees.png` | Menschen mit Bündeln |
| `event_wanderers.png` | Stab und Rucksack |
| `event_harvest_festival.png` | Garbe und Kürbis |
| `event_mana_bloom.png` | blaue Blüte |

**Stimmung** (`assets/ui/icons/`, 32 × 32, optional – sonst gezeichnet): `mood_angry.png`, `mood_unhappy.png`,
`mood_content.png`, `mood_happy.png`

**Tageszeit** (`assets/ui/icons/`, 32 × 32, optional): `daytime_sun.png`, `daytime_moon.png`

**Effekte** (`assets/sprites/effects/`, 256 × 256, optional, gestreckt über das Gebiet): `event_drought.png`,
`event_magic_storm.png`

Tönung bei Nacht, Blitze, Seuchenwolken und Ereignisgebiete zeichnet das Spiel selbst.

Die Völker der Königreiche (Spieler und KI) benutzen die Einheiten ihrer Fraktion (Phase 3); eigene Grafiken
je Volk gibt es nur für Burgen (Phase 7) und Dörfer (Phase 6).

## ✅ Phase 9 – Belagerung und Handel

Ordner `assets/sprites/` (Unterordner wie angegeben). Fehlt eine Datei, zeichnet das Spiel einen Platzhalter:
Mauern als verbundene Steinpfeiler, Tore als Holztür (verriegelt mit rotem Riegel), Türme, Werkstatt und
Einheiten als farbige Formen mit Buchstaben, Steine als graue Kreise. Handelswege (gestrichelte Linien,
rotes ✕) und Karawanen auf der Minikarte (Goldquadrate) zeichnet das Spiel selbst.

| Datei(en) | Motiv | Grösse |
|---|---|---|
| `buildings/wall_good.png` / `wall_evil.png` | Mauerstück von oben (hell behauener Stein / schwarzer Stein mit Dornen), waagrecht, an den Seiten nahtlos | 64 × 64 |
| `buildings/gate_good.png` / `gate_evil.png` | Tor im Mauerstück (Holz mit Eisenbändern / dunkles Eisengitter) | 64 × 64 |
| `buildings/tower_good.png` / `tower_evil.png` | runder Wachturm mit Zinnen und Feuerkorb / Dornenturm mit violettem Feuer | 128 × 128 |
| `buildings/siege_workshop_good.png` / `siege_workshop_evil.png` | Werkstatt mit Kran und Holzgerüst / Kriegsschmiede mit Ketten und Glut | 128 × 128 |
| `units/ram_good.png` / `ram_evil.png` | Rammbock unter Holzdach / Sturmbock mit Dornenschild | 64 × 64 |
| `units/catapult_good.png` / `catapult_evil.png` | Holzkatapult / Schädelschleuder | 64 × 64 |
| `units/caravan_good.png` / `caravan_evil.png` | Ochsenkarren mit Kisten, helle Plane / dunkle Plane | 64 × 64 |
| `effects/stone.png` | Felsbrocken (Geschoss) | 64 × 64 (wird klein gezeichnet) |

## ✅ Phase 10 – Speichern, Einstellungen, Hilfe

Keine neuen Grafiken: Speichern/Laden, Einstellungen, Hilfe (F1), Meldungsprotokoll (M), Sieg- und
Niederlage-Bildschirm und Hauptmenü bestehen aus Text und gezeichneten Formen; der Hintergrund des
Hauptmenüs ist `assets/ui/menu_background.png` (siehe „Menü“).

Ton: Die Busse *Master*, *Music*, *SFX* und *UI* sind angelegt (Lautstärken in den Einstellungen); das Spiel
spielt zurzeit keine Tondateien ab. Musik und Geräusche gehören später nach `assets/audio/music/` bzw.
`assets/audio/sfx/` (OGG).

## ✅ Truppen – neue Einheiten, Schmiede, Aussehen (Skins)

**Neue Einheiten** (`assets/sprites/units/`, 64 × 64, transparent, von oben, Blick nach unten). Fehlt eine Datei,
zeichnet das Spiel einen Kreis in Reichsfarbe mit Buchstaben.

| Datei GUT | Datei BÖSE | Einheit | Aussehen |
|---|---|---|---|
| `spearman_good.png` | `spearman_evil.png` | Speerträger / Pfähler | langer Speer, Rundschild / Hakenspiess, Stachelhelm |
| `crossbow_good.png` | `crossbow_evil.png` | Armbrustschütze / Höllenschütze | schwere Armbrust, Helm / Armbrust mit Widerhakenbolzen |
| `heavy_good.png` | `heavy_evil.png` | Schildwache / Eisenhauer | Plattenrüstung mit Turmschild / Zweihandaxt, Stachelpanzer |
| `cavalry_good.png` | `cavalry_evil.png` | Lanzenreiter / Wolfsreiter | Ritter auf Pferd mit Lanze / Ork auf grossem Wolf |
| `battlemage_good.png` | `battlemage_evil.png` | Kampfmagier / Hexer | Robe mit Sternenstab, leuchtende Hand / Kapuze, violette Flammen |

**Neue Gebäude** (`assets/sprites/buildings/`, 128 × 128, transparent):

| Datei GUT | Datei BÖSE | Gebäude | Aussehen |
|---|---|---|---|
| `forge_good.png` | `forge_evil.png` | Schmiede / Blutschmiede | Esse mit Amboss und Waffenständer / dunkle Esse mit roter Glut und Ketten |
| `stable_good.png` | `stable_evil.png` | Reitstall / Wolfszwinger (3 × 2 Felder, 192 × 128) | Holzstall mit Koppel / Pfahlzwinger mit Knochen |
| `mage_tower_good.png` | `mage_tower_evil.png` | Magierturm / Hexenturm | schlanker blauer Turm mit Sternenkuppel / schiefer Turm mit violettem Feuer |

**Aussehen (Skins)** – rein kosmetisch, im Auswahlfenster wählbar (Knopf „Aussehen“: für alle Einheiten eines Typs
oder eine einzelne Einheit). Die Bilder der Beschwören-Knöpfe, der Warteschlange und des Armeefensters zeigen dieselbe
Grafik im gewählten Aussehen. Datei: `assets/sprites/units/<einheit>_<skin>.png` (64 × 64). Fehlt sie, nimmt das Spiel die Grafik des
Typs leicht getönt, sonst einen Platzhalter in den Skin-Farben (Rand in Saumfarbe) – dazu immer ein kleines
gezeichnetes Abzeichen oben links.

| Skin-ID | Name | Fraktion | Farben / Abzeichen |
|---|---|---|---|
| `standard` | Standard | alle | Farben des Reichs (die normale Grafik, keine eigene Datei) |
| `royal` | Königsgarde | GUT | königsblau mit Gold, Krone |
| `sunwatch` | Sonnenwacht | GUT | hellgelb mit Weiss, Sonne |
| `shadow` | Schattenwache | BÖSE | schwarzviolett, Mond |
| `blood` | Blutbanner | BÖSE | dunkelrot, Reisszahn |
| `hero_banner` | Heldenbanner | alle (nur einzelne Einheiten ab Rang Elite) | Gold mit Weiss, Stern |

Einheiten mit Skins und ihre Dateien (je Einheit `<id>_<skin>.png`):

| Einheiten GUT (Skins `royal`, `sunwatch`, `hero_banner`) | Einheiten BÖSE (Skins `shadow`, `blood`, `hero_banner`) |
|---|---|
| `scout_good`, `fighter_good`, `spearman_good`, `archer_good`, `crossbow_good`, `heavy_good`, `elite_good`, `cavalry_good`, `battlemage_good`, `medic_good`, `ram_good`, `catapult_good` | `scout_evil`, `fighter_evil`, `spearman_evil`, `archer_evil`, `crossbow_evil`, `heavy_evil`, `elite_evil`, `cavalry_evil`, `battlemage_evil`, `medic_evil`, `ram_evil`, `catapult_evil` |

Beispiele: `units/fighter_good_royal.png` (Schwertkämpfer der Königsgarde), `units/cavalry_evil_blood.png`
(Wolfsreiter mit Blutbanner), `units/spearman_good_hero_banner.png`. Volkskrieger der Dörfer (z. B.
`dwarf_ironguard`) tragen im Reich des Spielers die Skins seiner Fraktion: `dwarf_ironguard_royal.png` usw.

Rangabzeichen (Winkel und Stern über den Einheiten) und die Abzeichen der Skins zeichnet das Spiel selbst.

## ✅ Oberfläche (Fenster, obere Leiste, Auswahlfenster)

Keine neuen Grafiken: Rahmen, Titelzeilen, Reiter, Wappen (Sonne GUT / Mondsichel BÖSE) und die Gruppen der oberen
Leiste zeichnet das Spiel selbst (`UiStyle`); Farben und Schrift kommen aus `assets/ui/theme.tres`.

## Übersicht der Ordner

| Ordner | Inhalt (Phase) |
|---|---|
| `assets/sprites/terrain/` | Gelände je Biom, 4 Varianten (1) |
| `assets/sprites/resources/` | Vorkommen auf der Karte (2) |
| `assets/sprites/buildings/` | Gebäude je Fraktion (2–4, 7–9; Schmiede, Reitstall, Magierturm: Truppen), Burgen je Volk (7), Dörfer und Hütten je Volk (6) |
| `assets/sprites/units/` | Bewohner, König, Truppen je Fraktion (2–3), Monster (3, 8), Milizen und Volkskrieger (6), Bote (6), Spione (7), Flüchtlinge/Wanderer (8), Belagerungswaffen und Karawanen (9), neue Truppen und Skins `<einheit>_<skin>.png` (Truppen) |
| `assets/sprites/heroes/` | Helden und Porträts (5) |
| `assets/sprites/effects/` | Geschosse (3, 9), Ruinen (7), Ereignisflächen (8) |
| `assets/ui/icons/` | Ressourcen (2), Zauber (4, 7), Ereignisse, Stimmung, Tageszeit (8) |
| `assets/ui/` | Menü-Hintergrund |
