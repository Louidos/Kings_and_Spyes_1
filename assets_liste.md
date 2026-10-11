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

## 🕓 Phase 2 – Dorf und Wirtschaft

**Ressourcen-Icons** (`assets/ui/icons/`, 32 × 32):
`icon_wood.png` (Holz), `icon_stone.png` (Stein), `icon_ore.png` (Erz), `icon_food.png` (Nahrung),
`icon_mana.png` (Mana), `icon_population.png` (Bewohner), `icon_happiness.png` (Zufriedenheit)

**Ressourcen auf der Karte** (`assets/sprites/resources/`, 64 × 64):
`res_wood.png` (Baumgruppe), `res_stone.png` (Felsbrocken), `res_ore.png` (Erzader),
`res_food.png` (Beerensträucher / Wild), `res_mana_spring.png` (leuchtende Manaquelle)

**Gebäude** (`assets/sprites/buildings/`, 128 × 128) – je Fraktion eine eigene Optik:
`castle_good.png` / `castle_evil.png` (Königsburg, 256 × 256),
`house_good.png` / `house_evil.png`, `farm_good.png` / `farm_evil.png`,
`lumberyard_good.png` / `lumberyard_evil.png`, `quarry_good.png` / `quarry_evil.png`,
`mine_good.png` / `mine_evil.png`, `storehouse_good.png` / `storehouse_evil.png`,
`road.png` (Strassenkachel 64 × 64)

**Bewohner** (`assets/sprites/units/`, 64 × 64):
`villager_good.png`, `villager_evil.png`

## 🕓 Phase 3 – Einheiten

(`assets/sprites/units/`, 64 × 64)
`king_good.png`, `king_evil.png`,
`scout_good.png` (schwacher Mensch), `scout_evil.png` (kleines Monster),
`fighter_good.png`, `fighter_evil.png`, `elite_good.png`, `elite_evil.png`,
`medic_good.png`, `medic_evil.png`, `archer_good.png`, `archer_evil.png`

Gebäude: `barracks_good.png` / `barracks_evil.png`, `infirmary_good.png` / `infirmary_evil.png`

Effekte (`assets/sprites/effects/`): `selection_ring.png`, `move_marker.png`

## 🕓 Phase 4 – Forschung und Magie

Gebäude: `mana_tower_good.png` / `mana_tower_evil.png`, `library_good.png` / `sanctum_evil.png`
Zauber-Icons (`assets/ui/icons/`, 32 × 32): je Zauber `spell_<name>.png`
Effekte: `fx_heal.png`, `fx_summon.png`, `fx_stealth.png`, `fx_weather.png`

## 🕓 Phase 5 – Helden

Pro Held: `hero_<name>.png` (64 × 64) und `hero_<name>_portrait.png` (128 × 128)

## 🕓 Phase 6 – Neutrale Völker

Dorfzentren (128 × 128): `village_dwarves.png`, `village_halflings.png`, `village_wood_elves.png`,
`village_lizardfolk.png`, `village_nomads.png`, `village_giants.png`, `village_water_spirits.png`,
`village_kobold_traders.png`
Einheiten: `messenger.png` (Bote), `trader.png` (Händler/Karawane)

## 🕓 Phase 7 – Gegner und Spionage

`spy_good.png`, `spy_evil.png`, Völker-Einheiten der Gegenseite (Liste folgt)

## 🕓 Phase 8 – Monster, Ereignisse

Monster: `monster_wolf.png`, `monster_spider.png`, `monster_golem.png`, `monster_wyvern.png`
Weitere: `refugee.png` (Flüchtling), Ereignis-Icons `event_drought.png`, `event_plague.png`,
`event_magic_storm.png`, `event_monster_wave.png`, `event_refugees.png`

## 🕓 Phase 9 – Belagerung

`wall.png`, `tower_good.png` / `tower_evil.png`, `gate_good.png` / `gate_evil.png`,
`siege_ram.png`, `siege_catapult.png`
