## WorldGenerator
##
## Erzeugt aus Seed und Grösse eine komplette WorldData:
##   1. Rauschfelder für Höhe, Feuchtigkeit, Hitze und Vulkanaktivität
##   2. Ausgleich jeder Ebene (Werte = Flächenanteil, siehe worldgen.json)
##   3. Grenzgebirge am Kartenrand
##   4. Biom-Zuordnung nach den Regeln in biomes.json
##   5. Übersichtsbild (1 Pixel pro Kachel) mit Relief-Schattierung
##   6. Startplatz für den Spieler
##
## Läuft in einem Hintergrund-Thread: hier dürfen KEINE Nodes oder der
## Szenenbaum angefasst werden, nur Daten.
## Gleicher Seed + gleiche Daten = immer die gleiche Welt.
class_name WorldGenerator
extends RefCounted

## Reihenfolge der Rauschebenen; entspricht den Bedingungs-Präfixen in biomes.json
const LAYERS := ["height", "moisture", "heat", "volcanic"]

## Optionaler Fortschritts-Callback: func(progress: float 0..1, text: String)
var progress_callback: Callable


func generate(world_seed: int, size: int) -> WorldData:
	var t_start := Time.get_ticks_msec()
	var tile_size := int(DataDB.cfg("map.tile_size", 64))
	var world := WorldData.new()
	world.setup(world_seed, size, size, tile_size)
	var layer_cfg: Dictionary = DataDB.worldgen.get("layers", {})

	# 1 + 2: Rauschebenen erzeugen und ausgleichen
	var layers: Array[PackedByteArray] = []
	for i in LAYERS.size():
		var layer_name: String = LAYERS[i]
		_report(0.05 + 0.12 * i, "Erzeuge %s …" % _layer_label(layer_name))
		var raw := _noise_layer(world_seed, size, layer_cfg.get(layer_name, {}))
		layers.append(_equalize(raw))

	# 3: Grenzgebirge
	_report(0.55, "Forme Grenzgebirge …")
	layers[0] = _apply_border(layers[0], size)

	# 4: Biome zuordnen
	_report(0.62, "Verteile Biome …")
	_classify(world, layers)
	world.elevation = layers[0]
	world.moisture = layers[1]

	# 5: Übersichtsbild
	_report(0.85, "Zeichne Landkarte …")
	world.overview_image = _build_overview(world)

	# 6: Startplatz
	_report(0.95, "Suche Startplatz …")
	world.start_cell = _find_start_cell(world)

	_report(1.0, "Fertig")
	print("Welt erzeugt: %d×%d Kacheln, Seed %d, %d ms" % [size, size, world_seed, Time.get_ticks_msec() - t_start])
	return world


# ---------------------------------------------------------------------------
# Rauschen
# ---------------------------------------------------------------------------

func _noise_layer(world_seed: int, size: int, c: Dictionary) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	# Jede Ebene bekommt einen eigenen, aber vom Welt-Seed abgeleiteten Seed.
	noise.seed = hash(world_seed + int(c.get("seed_offset", 0)))
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = float(c.get("frequency", 0.005))
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = int(c.get("octaves", 4))
	noise.fractal_lacunarity = float(c.get("lacunarity", 2.0))
	noise.fractal_gain = float(c.get("gain", 0.5))
	var warp := float(c.get("domain_warp", 0.0))
	if warp > 0.0:
		# Verzerrt das Rauschen -> natürlichere, weniger "runde" Formen
		noise.domain_warp_enabled = true
		noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
		noise.domain_warp_amplitude = warp
		noise.domain_warp_frequency = noise.frequency * 2.0
		noise.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
		noise.domain_warp_fractal_octaves = 3
	# get_image arbeitet nativ (C++) und ist damit viel schneller als eine
	# GDScript-Schleife über get_noise_2d.
	var img := noise.get_image(size, size, false, false, true)
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	return img.get_data()


## Histogramm-Ausgleich: danach bedeutet ein Wert v (0–255), dass etwa
## v/255 der Karte niedriger liegt. So sind die Biom-Schwellen Flächenanteile.
func _equalize(data: PackedByteArray) -> PackedByteArray:
	var hist := PackedInt32Array()
	hist.resize(256)
	for v in data:
		hist[v] += 1
	var lut := PackedByteArray()
	lut.resize(256)
	var total := float(data.size())
	var below := 0
	for v in 256:
		# Mitte des Bereichs, den dieser Wert abdeckt
		lut[v] = clampi(roundi((below + hist[v] * 0.5) / total * 255.0), 0, 255)
		below += hist[v]
	var out := PackedByteArray()
	out.resize(data.size())
	for i in data.size():
		out[i] = lut[data[i]]
	return out


## Hebt die Höhe zum Rand hin an -> natürliches Grenzgebirge statt Meer.
func _apply_border(h: PackedByteArray, size: int) -> PackedByteArray:
	var border: Dictionary = DataDB.worldgen.get("border", {})
	var bw := int(border.get("width", 0))
	var solid := clampf(float(border.get("solid", 0.4)), 0.0, 0.95)
	if bw <= 0:
		return h
	for y in size:
		var dy := mini(y, size - 1 - y)
		for x in size:
			var d := mini(mini(x, size - 1 - x), dy)
			if d >= bw:
				continue
			# Äusserer Teil (solid) ganz hoch, danach linear auslaufend. Die
			# ursprüngliche Höhe sorgt für einen unregelmässigen Innenrand.
			var t := clampf((1.0 - float(d) / bw) / (1.0 - solid), 0.0, 1.0)
			var i := y * size + x
			h[i] = clampi(roundi(lerpf(h[i], 255.0, t)), 0, 255)
	return h


# ---------------------------------------------------------------------------
# Biome
# ---------------------------------------------------------------------------

## Ordnet jeder Kachel ein Biom zu. Die Regeln werden vorab in flache
## Zahlen-Arrays übersetzt, damit die Schleife über alle Kacheln schnell bleibt.
func _classify(world: WorldData, layers: Array[PackedByteArray]) -> void:
	var rule_count := DataDB.biomes.size()
	var layer_count := LAYERS.size()
	var mins := PackedInt32Array()
	var maxs := PackedInt32Array()
	mins.resize(rule_count * layer_count)
	maxs.resize(rule_count * layer_count)
	for r in rule_count:
		var cond: Dictionary = DataDB.biomes[r].get("conditions", {})
		for l in layer_count:
			var key: String = LAYERS[l]
			mins[r * layer_count + l] = roundi(float(cond.get(key + "_min", 0.0)) * 255.0)
			maxs[r * layer_count + l] = roundi(float(cond.get(key + "_max", 1.0)) * 255.0)

	var h := layers[0]
	var m := layers[1]
	var t := layers[2]
	var v := layers[3]
	var out := world.biomes
	var counts := PackedInt32Array()
	counts.resize(rule_count)
	var fallback := DataDB.default_biome_index
	var n := out.size()
	for i in n:
		var hv := h[i]
		var mv := m[i]
		var tv := t[i]
		var vv := v[i]
		var biome := fallback
		for r in rule_count:
			var o := r * layer_count
			if hv >= mins[o] and hv <= maxs[o] \
					and mv >= mins[o + 1] and mv <= maxs[o + 1] \
					and tv >= mins[o + 2] and tv <= maxs[o + 2] \
					and vv >= mins[o + 3] and vv <= maxs[o + 3]:
				biome = r
				break
		out[i] = biome
		counts[biome] += 1
		if i % 131072 == 0:
			_report(0.62 + 0.22 * float(i) / n, "Verteile Biome …")
	world.biomes = out
	world.biome_counts = counts


# ---------------------------------------------------------------------------
# Übersichtsbild
# ---------------------------------------------------------------------------

## 1 Pixel pro Kachel in Biom-Farbe, mit Licht von Nordwesten für ein Relief.
func _build_overview(world: WorldData) -> Image:
	var w := world.width
	var hgt := world.height
	var rule_count := DataDB.biomes.size()
	var base := PackedFloat32Array()
	base.resize(rule_count * 3)
	for r in rule_count:
		var c: Color = DataDB.biomes[r]["color"]
		base[r * 3] = c.r * 255.0
		base[r * 3 + 1] = c.g * 255.0
		base[r * 3 + 2] = c.b * 255.0

	var elev := world.elevation
	var bio := world.biomes
	var px := PackedByteArray()
	px.resize(w * hgt * 3)
	var o := 0
	for y in hgt:
		for x in w:
			var i := y * w + x
			var e := float(elev[i])
			# Höhe hellt leicht auf, Hang zur Lichtquelle (NW) hellt auf, Gegenhang dunkelt ab
			var shade := 0.82 + e * 0.0011
			if x > 0 and y > 0:
				shade += clampf((e - float(elev[i - w - 1])) * 0.012, -0.18, 0.18)
			var b := bio[i] * 3
			px[o] = clampi(int(base[b] * shade), 0, 255)
			px[o + 1] = clampi(int(base[b + 1] * shade), 0, 255)
			px[o + 2] = clampi(int(base[b + 2] * shade), 0, 255)
			o += 3
	return Image.create_from_data(w, hgt, false, Image.FORMAT_RGB8, px)


# ---------------------------------------------------------------------------
# Startplatz
# ---------------------------------------------------------------------------

## Sucht eine Stelle mit viel bebaubarem Land um sich herum, nicht zu nah am Rand.
## (Ab Phase 6/7 werden hier auch gegnerische Königreiche und neutrale Dörfer platziert.)
func _find_start_cell(world: WorldData) -> Vector2i:
	var cfg: Dictionary = DataDB.worldgen.get("start", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world.world_seed + 9001)
	var margin := int(world.width * float(cfg.get("edge_margin", 0.12)))
	var radius := int(cfg.get("check_radius", 6))
	var min_ratio := float(cfg.get("min_buildable_ratio", 0.85))
	var attempts := int(cfg.get("attempts", 400))
	# Biome, auf denen der Startplatz selbst liegen soll (z. B. Ebene)
	var center_ok := PackedByteArray()
	center_ok.resize(DataDB.biomes.size())
	var center_ids: Array = cfg.get("center_biomes", [])
	for r in DataDB.biomes.size():
		center_ok[r] = 1 if center_ids.is_empty() or DataDB.biomes[r].get("id") in center_ids else 0

	var buildable := PackedByteArray()
	buildable.resize(DataDB.biomes.size())
	for r in DataDB.biomes.size():
		buildable[r] = 1 if DataDB.biomes[r].get("buildable", true) else 0

	var best := Vector2i(world.width >> 1, world.height >> 1)
	var best_ratio := -1.0
	for _a in attempts:
		var c := Vector2i(rng.randi_range(margin, world.width - 1 - margin),
				rng.randi_range(margin, world.height - 1 - margin))
		if center_ok[world.biomes[world.cell_index(c)]] == 0:
			continue
		var ok := 0
		var total := 0
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var cell := c + Vector2i(dx, dy)
				if world.in_bounds(cell):
					total += 1
					ok += buildable[world.biomes[world.cell_index(cell)]]
		var ratio := float(ok) / maxi(total, 1)
		if ratio > best_ratio:
			best_ratio = ratio
			best = c
		if ratio >= min_ratio:
			break
	return best


# ---------------------------------------------------------------------------

func _report(p: float, text: String) -> void:
	if progress_callback.is_valid():
		progress_callback.call(p, text)


func _layer_label(layer: String) -> String:
	match layer:
		"height": return "Höhenkarte"
		"moisture": return "Feuchtigkeit"
		"heat": return "Klimazonen"
		"volcanic": return "Vulkangebiete"
	return layer
