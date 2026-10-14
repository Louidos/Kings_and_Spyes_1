# Grafikliste

Alle Grafiken, die das Spiel braucht, mit Dateinamen und Ablageort.
Fehlt eine Datei, erzeugt das Spiel automatisch einen Platzhalter.
Liegt die Datei am richtigen Ort, wird sie beim nächsten Start verwendet – ohne Code-Änderung.

**Status:**
- ✅ = wird bereits verwendet
- 🕓 = vorläufig, Name und Umfang werden in der genannten Phase festgelegt

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
Heldenleiste). Fehlt eine Datei, zeichnet das Spiel einen Kreis in der Heldenfarbe mit Buchstaben.

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

## 🕓 Phase 6 – Neutrale Völker

Dorfzentren (128 × 128): `village_dwarves.png`, `village_halflings.png`, `village_wood_elves.png`,
`village_lizardfolk.png`, `village_nomads.png`, `village_giants.png`, `village_water_spirits.png`,
`village_kobold_traders.png`
Einheiten: `messenger.png` (Bote), `trader.png` (Händler/Karawane)

## 🕓 Phase 7 – Gegner und Spionage

`spy_good.png`, `spy_evil.png`, Völker-Einheiten der Gegenseite (Liste folgt)

## 🕓 Phase 8 – Monster, Ereignisse

Weitere Monster: `monster_wyvern.png` (Wolf, Spinne und Golem: siehe Phase 3)
Weitere: `refugee.png` (Flüchtling), Ereignis-Icons `event_drought.png`, `event_plague.png`,
`event_magic_storm.png`, `event_monster_wave.png`, `event_refugees.png`

## 🕓 Phase 9 – Belagerung

`wall.png`, `tower_good.png` / `tower_evil.png`, `gate_good.png` / `gate_evil.png`,
`siege_ram.png`, `siege_catapult.png`
