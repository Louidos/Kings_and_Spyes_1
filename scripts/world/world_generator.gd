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
## Von aussen setzen, um die Erzeugung abzubrechen (Spiel wird beendet)
var cancelled := false


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
		if cancelled:
			return world

	# 3: Grenzgebirge
	_report(0.55, "Forme Grenzgebirge …")
	layers[0] = _apply_border(layers[0], size)

	# 4: Biome zuordnen
	_report(0.62, "Verteile Biome …")
	_classify(world, layers)
	if cancelled:
		return world
	world.elevation = layers[0]
	world.moisture = layers[1]

	# 5: Übersichtsbild
	_report(0.85, "Zeichne Landkarte …")
	world.overview_image = _build_overview(world)

	if cancelled:
		return world
	# 6: Rohstoffvorkommen
	_report(0.9, "Verteile Rohstoffe …")
	_place_biome_deposits(world)
	_place_scattered_deposits(world)

	# 7: Startplatz und gesicherte Rohstoffe in seiner Nähe
	_report(0.95, "Suche Startplatz …")
	world.start_cell = _find_start_cell(world)
	_prepare_start_area(world)

	# 8: Monsterlager (die Höhlen selbst setzt das MonsterSystem beim Spielstart)
	_place_camps(world)

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
			if cancelled:
				return
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
			var shade := WorldData.SHADE_BASE + e * WorldData.SHADE_PER_HEIGHT
			if x > 0 and y > 0:
				shade += clampf((e - float(elev[i - w - 1])) * WorldData.SHADE_SLOPE,
						-WorldData.SHADE_SLOPE_MAX, WorldData.SHADE_SLOPE_MAX)
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
# Rohstoffvorkommen
# ---------------------------------------------------------------------------

## Biom-Vorkommen (z. B. Holz im Wald) liegen auf jeder Kachel des Bioms.
## Die Menge wird per Hash aus Kachel und Seed bestimmt (schnell und reproduzierbar).
func _place_biome_deposits(world: WorldData) -> void:
	var by_biome := PackedInt32Array()  # Biom-Index -> Vorkommen-Index + 1
	by_biome.resize(DataDB.biomes.size())
	var amount_min := PackedInt32Array()
	var amount_span := PackedInt32Array()
	amount_min.resize(DataDB.deposits.size())
	amount_span.resize(DataDB.deposits.size())
	var any := false
	for d in DataDB.deposits:
		amount_min[d["index"]] = d["amount"][0]
		amount_span[d["index"]] = maxi(1, d["amount"][1] - d["amount"][0] + 1)
		if not d["biome_deposit"]:
			continue
		for biome_id in d.get("on_biomes", []):
			if DataDB.biome_index_by_id.has(biome_id):
				by_biome[DataDB.biome_index_by_id[biome_id]] = d["index"] + 1
				any = true
	if not any:
		return
	var bio := world.biomes
	var types := world.deposit_type
	var amounts := world.deposit_amount
	var salt := world.world_seed & 0x7fffffff
	for i in bio.size():
		var t := by_biome[bio[i]]
		if t == 0:
			continue
		types[i] = t
		var h := ((i * 2654435761) ^ salt) & 0x7fffffff
		amounts[i] = amount_min[t - 1] + (h >> 7) % amount_span[t - 1]


## Verstreute Vorkommen (Steine, Erz, Beeren, Manaquellen ...) in kleinen Gruppen.
func _place_scattered_deposits(world: WorldData) -> void:
	var border := int(DataDB.worldgen.get("border", {}).get("width", 0))
	var total_tiles := world.width * world.height
	for d in DataDB.deposits:
		if d["biome_deposit"]:
			continue
		var allowed := _biome_mask(d.get("on_biomes", []))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(world.world_seed + 7919 * (d["index"] + 1))
		var groups := int(round(float(d.get("per_1000_tiles", 0.0)) * total_tiles / 1000.0))
		var cluster: Array = d.get("cluster", [1, 1])
		var placed := 0
		var attempts := 0
		while placed < groups and attempts < groups * 6:
			attempts += 1
			var c := Vector2i(rng.randi_range(border, world.width - 1 - border),
					rng.randi_range(border, world.height - 1 - border))
			if not _can_hold_deposit(world, c, allowed, d):
				continue
			placed += 1
			_put_deposit(world, c, d, rng)
			var extra := rng.randi_range(int(cluster[0]), int(cluster[cluster.size() - 1])) - 1
			for _k in extra:
				var n := c + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
				if _can_hold_deposit(world, n, allowed, d):
					_put_deposit(world, n, d, rng)


## Räumt den Platz für die Burg frei und stellt sicher, dass die wichtigsten
## Rohstoffe in der Nähe des Startplatzes vorkommen.
func _prepare_start_area(world: WorldData) -> void:
	var cfg := DataDB.deposit_cfg
	var keep := int(cfg.get("start_keep_clear_radius", 4))
	var start := world.start_cell
	for dy in range(-keep, keep + 1):
		for dx in range(-keep, keep + 1):
			var c := start + Vector2i(dx, dy)
			var d := world.get_deposit(c)
			if not d.is_empty() and not d["biome_deposit"]:
				world.set_deposit(c, -1, 0)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world.world_seed + 4243)
	for g in cfg.get("start_guarantees", []):
		var d := DataDB.get_deposit_by_id(str(g.get("deposit", "")))
		if d.is_empty():
			continue
		var radius := int(g.get("radius", 12))
		var allowed := _biome_mask(d.get("on_biomes", []) + g.get("allow_biomes", []))
		# Vorhandene zählen (ausserhalb des freigehaltenen Bereichs)
		var have := 0
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c := start + Vector2i(dx, dy)
				if Vector2(dx, dy).length() <= radius and world.get_deposit_index(c) == d["index"]:
					have += 1
		var missing := int(g.get("count", 1)) - have
		var tries := 0
		while missing > 0 and tries < 400:
			tries += 1
			var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(keep + 1.5, radius)
			var c := start + Vector2i(roundi(off.x), roundi(off.y))
			if maxi(absi(c.x - start.x), absi(c.y - start.y)) <= keep:
				continue
			if not _can_hold_deposit(world, c, allowed, d):
				continue
			_put_deposit(world, c, d, rng)
			missing -= 1


## Biom-IDs -> Maske (1 = erlaubt) über alle Biom-Indizes
func _biome_mask(biome_ids: Array) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(DataDB.biomes.size())
	for id in biome_ids:
		if DataDB.biome_index_by_id.has(id):
			mask[DataDB.biome_index_by_id[id]] = 1
	return mask


## Kachel frei für ein verstreutes Vorkommen? Biom-Vorkommen (Wald) zählen als
## frei. Direkt neben Vorkommen mit eigenem Bauplatz (Manaquelle) bleibt alles frei.
## Braucht das Vorkommen selbst einen Bauplatz (needs_footprint), muss es einen
## bebaubaren, freien Bereich dieser Grösse geben, der die Kachel enthält.
func _can_hold_deposit(world: WorldData, c: Vector2i, allowed: PackedByteArray, d: Dictionary = {}) -> bool:
	if not world.in_bounds(c):
		return false
	var i := world.cell_index(c)
	if allowed[world.biomes[i]] == 0:
		return false
	if not _is_free_for_deposit(world, c):
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := world.get_deposit(c + Vector2i(dx, dy))
			if not n.is_empty() and n.has("needs_footprint"):
				return false
	if d.has("needs_footprint"):
		var fp: Array = d["needs_footprint"]
		return _has_free_footprint(world, c, Vector2i(int(fp[0]), int(fp[1])))
	return true


## Kein verstreutes Vorkommen auf der Kachel (Wald zählt als frei)
func _is_free_for_deposit(world: WorldData, c: Vector2i) -> bool:
	var existing := world.deposit_type[world.cell_index(c)]
	return existing == 0 or DataDB.deposits[existing - 1]["biome_deposit"]


## Gibt es einen size-grossen, bebaubaren Bereich ohne andere Vorkommen, der c enthält?
func _has_free_footprint(world: WorldData, c: Vector2i, size: Vector2i) -> bool:
	for oy in range(size.y):
		for ox in range(size.x):
			var top_left := c - Vector2i(ox, oy)
			var ok := true
			for y in range(top_left.y, top_left.y + size.y):
				for x in range(top_left.x, top_left.x + size.x):
					var cell := Vector2i(x, y)
					if not world.in_bounds(cell) or not world.get_biome(cell).get("buildable", false) \
							or (cell != c and not _is_free_for_deposit(world, cell)):
						ok = false
						break
				if not ok:
					break
			if ok:
				return true
	return false


func _put_deposit(world: WorldData, c: Vector2i, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var amount: int = -1 if d["amount"][0] < 0 else rng.randi_range(d["amount"][0], d["amount"][1])
	var i := world.cell_index(c)
	# Liegt hier Wald, entsteht eine Lichtung (sonst bliebe nach dem Abbau Wald ohne Holz)
	var existing := world.deposit_type[i]
	if existing != 0:
		var after := str(DataDB.deposits[existing - 1].get("depleted_biome", ""))
		if DataDB.biome_index_by_id.has(after):
			world.set_biome(c, DataDB.biome_index_by_id[after])
	world.deposit_type[i] = d["index"] + 1
	world.deposit_amount[i] = amount


# ---------------------------------------------------------------------------
# Monsterlager
# ---------------------------------------------------------------------------

## Wählt Plätze für Monsterhöhlen (2×2): weit genug vom Startplatz und
## voneinander entfernt, nicht im Grenzgebirge, ohne Rohstoffvorkommen.
## Ergebnis in world.camps als {"cell": obere linke Kachel, "biome": Biom-ID},
## Übungslager zusätzlich mit "kinds" (Monsterarten) und "size" (Anzahl).
func _place_camps(world: WorldData) -> void:
	var cfg: Dictionary = DataDB.combat.get("camps", {})
	var area := world.width * world.height
	var count := maxi(int(cfg.get("min_count", 3)), roundi(float(cfg.get("per_1000_tiles", 0.05)) * area / 1000.0))
	var min_start := float(cfg.get("min_distance_from_start", 28))
	var min_between := float(cfg.get("min_distance_between", 12))
	var by_biome: Dictionary = cfg.get("by_biome", {})
	var bw := int(DataDB.worldgen.get("border", {}).get("width", 0))
	var lo := bw + 1
	var hi_x := world.width - bw - 3
	var hi_y := world.height - bw - 3
	if hi_x <= lo or hi_y <= lo:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world.world_seed + 6007)
	var start := Vector2(world.start_cell)
	var bounds := Rect2i(lo, lo, hi_x - lo + 1, hi_y - lo + 1)

	# Zuerst kleine Übungslager in Startnähe (feste Monster, wenige)
	var near: Dictionary = cfg.get("near_start", {})
	var near_biomes: Array = near.get("biomes", [])
	var near_placed := 0
	for _a in int(near.get("count", 0)) * 300:
		if near_placed >= int(near.get("count", 0)):
			break
		var dist := rng.randf_range(float(near.get("min", 30)), float(near.get("max", 45)))
		var c := Vector2i((start + Vector2.from_angle(rng.randf() * TAU) * dist).round()) - Vector2i.ONE
		if not bounds.has_point(c) or not _camp_spot_ok(world, c, min_between):
			continue
		var biome_id := str(world.get_biome(c).get("id", ""))
		if not near_biomes.is_empty() and not near_biomes.has(biome_id):
			continue
		world.camps.append({"cell": c, "biome": biome_id, "kinds": near.get("monsters", []),
				"size": int(near.get("size", 3))})
		near_placed += 1

	# Dann die übrigen Lager über die ganze Karte
	var placed := 0
	for _a in count * 40:
		if placed >= count:
			break
		var c := Vector2i(rng.randi_range(lo, hi_x), rng.randi_range(lo, hi_y))
		if (Vector2(c) + Vector2.ONE).distance_to(start) < min_start:
			continue
		var biome_id := str(world.get_biome(c).get("id", ""))
		if not by_biome.has(biome_id) or not _camp_spot_ok(world, c, min_between):
			continue
		world.camps.append({"cell": c, "biome": biome_id})
		placed += 1


## 2×2 frei von Vorkommen und weit genug von anderen Lagern?
func _camp_spot_ok(world: WorldData, c: Vector2i, min_between: float) -> bool:
	for y in range(c.y, c.y + 2):
		for x in range(c.x, c.x + 2):
			if not _is_free_for_deposit(world, Vector2i(x, y)):
				return false
	var center := Vector2(c) + Vector2.ONE
	for other in world.camps:
		if center.distance_to(Vector2(other["cell"]) + Vector2.ONE) < min_between:
			return false
	return true


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
