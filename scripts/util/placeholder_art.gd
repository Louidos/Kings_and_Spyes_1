## PlaceholderArt
##
## Zentrale Stelle für Grafiken: lädt echte PNG-Dateien, wenn vorhanden, und
## erzeugt sonst automatisch Platzhalter (farbige Formen).
##
## So lassen sich später alle Platzhalter durch Anime-Grafiken ersetzen, indem
## man einfach eine PNG-Datei mit dem richtigen Namen in /assets/sprites legt
## (siehe assets_liste.md) – ohne Code zu ändern.
class_name PlaceholderArt
extends RefCounted


## Lädt ein Bild aus res:// (importiert oder als rohe PNG). Gibt null zurück,
## wenn die Datei fehlt oder nicht lesbar ist.
static func load_image(path: String) -> Image:
	if path.is_empty():
		return null
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			img = tex.get_image()
	elif FileAccess.file_exists(path):
		# Noch nicht vom Editor importierte Datei direkt lesen
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Erzeugt eine Platzhalter-Kachel: Grundfarbe mit leichtem Rauschen plus ein
## einfaches Muster, damit man die Biome auch ohne Beschriftung erkennt.
static func make_terrain_tile(base: Color, pattern: String, variant: int, size: int) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pattern) + variant * 7919

	# Grundfläche mit feinem Farbrauschen
	for y in size:
		for x in size:
			var f := rng.randf_range(-0.045, 0.045)
			img.set_pixel(x, y, Color(base.r + f, base.g + f, base.b + f))

	var s := float(size) / 64.0  # Skalierung, falls tile_size nicht 64 ist
	match pattern:
		"grass":
			_pattern_grass(img, base, rng, s)
		"trees":
			_pattern_trees(img, base, rng, s)
		"peaks":
			_pattern_peaks(img, base, rng, s)
		"dunes":
			_pattern_dunes(img, base, rng, s)
		"reeds":
			_pattern_reeds(img, base, rng, s)
		"lava":
			_pattern_lava(img, base, rng, s)
	return img


# ---------------------------------------------------------------------------
# Muster
# ---------------------------------------------------------------------------

static func _pattern_grass(img: Image, base: Color, rng: RandomNumberGenerator, s: float) -> void:
	for i in 16:
		var x := rng.randi_range(int(4 * s), img.get_width() - int(6 * s))
		var y := rng.randi_range(int(4 * s), img.get_height() - int(8 * s))
		var c := base.lightened(0.18) if i % 2 == 0 else base.darkened(0.15)
		img.fill_rect(Rect2i(x, y, maxi(1, int(2 * s)), maxi(2, int(4 * s))), c)
	# ein paar Blumen
	for i in 2:
		var p := Vector2(rng.randf_range(8, 56), rng.randf_range(8, 56)) * s
		_circle(img, p, 1.6 * s, Color(1.0, 0.9, 0.4) if i == 0 else Color(0.95, 0.95, 1.0))


static func _pattern_trees(img: Image, base: Color, rng: RandomNumberGenerator, s: float) -> void:
	var count := rng.randi_range(2, 4)
	for i in count:
		var r := rng.randf_range(8.0, 12.0) * s
		var p := Vector2(rng.randf_range(r + 2, 64 * s - r - 2), rng.randf_range(r + 2, 64 * s - r - 4))
		_circle(img, p + Vector2(2, 3) * s, r, base.darkened(0.45))  # Schatten
		_circle(img, p, r, base.darkened(0.15))                       # Krone
		_circle(img, p - Vector2(r, r) * 0.3, r * 0.45, base.lightened(0.2))  # Glanzlicht


static func _pattern_peaks(img: Image, base: Color, rng: RandomNumberGenerator, s: float) -> void:
	var count := rng.randi_range(1, 2)
	for i in count:
		var w := rng.randf_range(22.0, 30.0) * s
		var h := rng.randf_range(24.0, 34.0) * s
		var cx := rng.randf_range(w * 0.5 + 3, 64 * s - w * 0.5 - 3)
		var by := rng.randf_range(h + 4, 64 * s - 4)
		var top := Vector2(cx, by - h)
		var left := Vector2(cx - w * 0.5, by)
		var right := Vector2(cx + w * 0.5, by)
		var mid := Vector2(cx, by)
		_triangle(img, top, left, mid, base.darkened(0.25))   # Schattenseite
		_triangle(img, top, mid, right, base.lightened(0.15)) # Lichtseite
		# Schneekappe
		var cap := 0.3
		_triangle(img, top, top.lerp(left, cap), top.lerp(right, cap), Color(0.95, 0.96, 1.0))


static func _pattern_dunes(img: Image, base: Color, rng: RandomNumberGenerator, s: float) -> void:
	var size := img.get_width()
	for i in 3:
		var y0 := (12.0 + i * 18.0 + rng.randf_range(-3, 3)) * s
		var phase := rng.randf_range(0, TAU)
		for x in range(int(4 * s), size - int(4 * s)):
			var y := int(y0 + sin(x / (9.0 * s) + phase) * 3.0 * s)
			if y >= 1 and y < size - 2:
				img.set_pixel(x, y, base.darkened(0.18))
				img.set_pixel(x, y + 1, base.lightened(0.12))


static func _pattern_reeds(img: Image, base: Color, rng: RandomNumberGenerator, s: float) -> void:
	var water := Color(0.22, 0.32, 0.30)
	for i in 2:
		var p := Vector2(rng.randf_range(16, 48), rng.randf_range(16, 48)) * s
		_ellipse(img, p, Vector2(rng.randf_range(8, 13), rng.randf_range(5, 8)) * s, water)
		_ellipse(img, p - Vector2(2, 1) * s, Vector2(3, 1.5) * s, water.lightened(0.25))
	for i in 10:
		var x := rng.randi_range(int(4 * s), img.get_width() - int(5 * s))
		var y := rng.randi_range(int(10 * s), img.get_height() - int(4 * s))
		var h := int(rng.randf_range(5, 9) * s)
		img.fill_rect(Rect2i(x, y - h, maxi(1, int(s)), h), base.darkened(0.35))
		img.fill_rect(Rect2i(x, y - h - int(2 * s), maxi(1, int(2 * s)), maxi(1, int(2 * s))), Color(0.45, 0.3, 0.15))


static func _pattern_lava(img: Image, _base: Color, rng: RandomNumberGenerator, s: float) -> void:
	var size := img.get_width()
	# Glühende Risse als zufällige Pfade
	for i in 3:
		var p := Vector2(rng.randf_range(10, 54), rng.randf_range(10, 54)) * s
		var dir := Vector2.from_angle(rng.randf_range(0, TAU))
		for step in int(22 * s):
			dir = dir.rotated(rng.randf_range(-0.5, 0.5))
			p += dir
			if p.x < 2 or p.y < 2 or p.x > size - 3 or p.y > size - 3:
				break
			img.set_pixelv(Vector2i(p), Color(1.0, 0.45, 0.08))
			img.set_pixelv(Vector2i(p) + Vector2i(1, 0), Color(0.9, 0.25, 0.05))
	for i in 3:
		var c := Vector2(rng.randf_range(8, 56), rng.randf_range(8, 56)) * s
		_circle(img, c, 2.2 * s, Color(1.0, 0.75, 0.2))


# ---------------------------------------------------------------------------
# Einheiten
# ---------------------------------------------------------------------------

## Abzeichen eines Skins: runde Plakette in dunkler Farbe mit Symbol in trim.
## (Die Spielfiguren selbst zeichnet FigureArt.)
## kind: crown, sun, skull, fang, star, moon, shield (unbekannt = Punkt)
static func make_emblem(kind: String, trim: Color, size: int = 24) -> Image:
	var s := size * _SS
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(s, s) * 0.5
	var r := s * 0.46
	var back := trim.darkened(0.72)
	_circle(img, c, r, Color(0, 0, 0, 0.85))
	_circle(img, c, r * 0.86, back)
	var w := r * 0.62
	match kind:
		"crown":
			_polygon(img, PackedVector2Array([c + Vector2(-w, w * 0.55), c + Vector2(-w, -w * 0.45), c + Vector2(-w * 0.45, 0),
					c + Vector2(0, -w * 0.75), c + Vector2(w * 0.45, 0), c + Vector2(w, -w * 0.45), c + Vector2(w, w * 0.55)]), trim)
		"sun":
			for i in 8:
				var d := Vector2.RIGHT.rotated(TAU * i / 8.0)
				var o := d.orthogonal() * w * 0.2
				_triangle(img, c + d * w * 0.45 - o, c + d * w * 0.45 + o, c + d * w * 1.05, trim)
			_circle(img, c, w * 0.5, trim)
		"skull":
			_circle(img, c + Vector2(0, -w * 0.15), w * 0.72, trim)
			_polygon(img, PackedVector2Array([c + Vector2(-w * 0.4, w * 0.3), c + Vector2(w * 0.4, w * 0.3),
					c + Vector2(w * 0.3, w * 0.85), c + Vector2(-w * 0.3, w * 0.85)]), trim)
			_circle(img, c + Vector2(-w * 0.28, -w * 0.15), w * 0.2, back)
			_circle(img, c + Vector2(w * 0.28, -w * 0.15), w * 0.2, back)
		"fang":
			_triangle(img, c + Vector2(-w * 0.85, -w * 0.6), c + Vector2(-w * 0.15, -w * 0.6), c + Vector2(-w * 0.45, w * 0.9), trim)
			_triangle(img, c + Vector2(w * 0.15, -w * 0.6), c + Vector2(w * 0.85, -w * 0.6), c + Vector2(w * 0.45, w * 0.9), trim)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var rr := w if i % 2 == 0 else w * 0.42
				pts.append(c + Vector2.UP.rotated(TAU * i / 10.0) * rr)
			_polygon(img, pts, trim)
		"moon":
			_circle(img, c, w * 0.85, trim)
			_circle(img, c + Vector2(w * 0.38, -w * 0.22), w * 0.7, back)
		"shield":
			_polygon(img, PackedVector2Array([c + Vector2(-w * 0.75, -w * 0.75), c + Vector2(w * 0.75, -w * 0.75),
					c + Vector2(w * 0.7, w * 0.15), c + Vector2(0, w * 0.9), c + Vector2(-w * 0.7, w * 0.15)]), trim)
		_:
			_circle(img, c, w * 0.45, trim)
	return _downsample(img, size, _SS)


# ---------------------------------------------------------------------------
# Zeichen-Helfer (direkt auf Image)
# ---------------------------------------------------------------------------

static func _circle(img: Image, center: Vector2, r: float, color: Color) -> void:
	_ellipse(img, center, Vector2(r, r), color)


static func _ellipse(img: Image, center: Vector2, radii: Vector2, color: Color) -> void:
	var x0 := maxi(0, floori(center.x - radii.x))
	var x1 := mini(img.get_width() - 1, ceili(center.x + radii.x))
	var y0 := maxi(0, floori(center.y - radii.y))
	var y1 := mini(img.get_height() - 1, ceili(center.y + radii.y))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2((x + 0.5 - center.x) / radii.x, (y + 0.5 - center.y) / radii.y)
			if d.length_squared() <= 1.0:
				img.set_pixel(x, y, color)


static func _triangle(img: Image, a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	var x0 := maxi(0, floori(minf(a.x, minf(b.x, c.x))))
	var x1 := mini(img.get_width() - 1, ceili(maxf(a.x, maxf(b.x, c.x))))
	var y0 := maxi(0, floori(minf(a.y, minf(b.y, c.y))))
	var y1 := mini(img.get_height() - 1, ceili(maxf(a.y, maxf(b.y, c.y))))
	var poly := PackedVector2Array([a, b, c])
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				img.set_pixel(x, y, color)


# ---------------------------------------------------------------------------
# Rohstoff-Vorkommen und Strassen
# ---------------------------------------------------------------------------

## Überabtastung: Icons und Strassen werden in dieser Vergrösserung gezeichnet
## und danach verkleinert. So bekommen alle Kanten eine weiche Kantenglättung.
const _SS := 2

## Lichtrichtung für alle Schattierungen (von oben links, Blick von oben).
const _LIGHT := Vector3(-0.5, -0.65, 0.6)


## Erzeugt ein Platzhalter-Icon für ein Rohstoff-Vorkommen: transparenter
## Hintergrund, mittig, nutzt etwa 80 % der Kachel.
## pattern: "trees", "rocks", "ore", "berries", "mana"; unbekannte Muster
## ergeben einen gefüllten Kreis. empty = true liefert die "leere" Variante
## (abgeerntet bzw. am Nachwachsen): beim Beerenbusch ohne Beeren, sonst
## entsättigt, dunkler und halb durchsichtig.
static func make_deposit_icon(pattern: String, color: Color, size: int, empty: bool = false) -> Image:
	var hi := Image.create_empty(size * _SS, size * _SS, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pattern)
	var s := float(size * _SS) / 64.0  # alle Masse sind für 64 px entworfen
	match pattern:
		"trees":
			_icon_trees(hi, color, rng, s)
		"rocks":
			_icon_rocks(hi, color, rng, s)
		"ore":
			_icon_ore(hi, color, rng, s)
		"berries":
			_icon_berries(hi, color, rng, s, empty)
		"mana":
			_icon_mana(hi, color, rng, s)
		_:
			var c := Vector2(32, 32) * s
			_ellipse(hi, c + Vector2(3, 3.5) * s, Vector2(20, 18) * s, Color(0, 0, 0, 0.28))
			_circle(hi, c, 21.5 * s, color.darkened(0.6))
			_shaded_ellipse(hi, c, Vector2(19.5, 19.5) * s, color)
	var img := _downsample(hi, size, _SS)
	if empty and pattern != "berries":
		_fade_image(img)
	return img


## Erzeugt eine Strassen-Kachel: gestampfte, braungraue Erde mit dezentem
## Kopfsteinpflaster. Der Rand bleibt überall gleich (nur Erde), damit
## benachbarte Strassenkacheln nahtlos ineinander übergehen.
## planned = true: dieselbe Kachel zu 45 % deckend mit gestrichelter, heller
## Umrandung (geplant bzw. im Bau).
static func make_road_tile(size: int, planned: bool) -> Image:
	var hs := size * _SS
	var hi := Image.create_empty(hs, hs, false, Image.FORMAT_RGBA8)
	var s := float(hs) / 64.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("road")
	var earth := Color(0.53, 0.46, 0.37)

	# Erde mit grobkörnigem Rauschen (Körner von ca. 2 px Endgrösse)
	var grain := maxi(1, roundi(2.0 * s))
	for gy in range(0, hs, grain):
		for gx in range(0, hs, grain):
			var f := rng.randf_range(-0.035, 0.035)
			hi.fill_rect(Rect2i(gx, gy, grain, grain), Color(earth.r + f, earth.g + f * 0.9, earth.b + f * 0.8))

	# Pflastersteine: unregelmässige, flache Steine in 5 Reihen, jede zweite
	# Reihe mit 4 statt 5 Steinen, also versetzt (wie ein Läuferverband). Jeder Stein
	# bleibt in seiner Zelle, am Kachelrand bleibt ein schmaler Streifen Erde.
	# Rand oben/links ist schmaler als unten/rechts, weil der Fugenschatten
	# nach unten rechts fällt; zusammen ergeben sie etwa die Fugenbreite innen.
	var stone := Color(0.60, 0.56, 0.50)
	var cell := float(hs) / 5.0
	var gap := 0.8 * s
	var m_lo := 1.2 * s
	var m_hi := 2.3 * s
	var stones: Array[Vector4] = []  # Mitte x, y, Radien x, y
	for gy in 5:
		var xs := PackedFloat32Array([0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
		if gy % 2 == 1:
			xs = PackedFloat32Array([0.0, 1.25, 2.5, 3.75, 5.0])
		for k in xs.size() - 1:
			if rng.randf() < 0.06:
				continue  # Lücke: hier ist nur Erde
			var box_lo := Vector2(xs[k] * cell + gap, gy * cell + gap)
			var box_hi := Vector2(xs[k + 1] * cell - gap, (gy + 1) * cell - gap)
			box_lo = box_lo.max(Vector2(m_lo, m_lo))
			box_hi = box_hi.min(Vector2(hs - m_hi, hs - m_hi))
			var avail := box_hi - box_lo
			var rx := rng.randf_range(0.46, 0.5) * avail.x
			var ry := rng.randf_range(0.44, 0.5) * avail.y
			var c := Vector2(rng.randf_range(box_lo.x + rx, box_hi.x - rx), rng.randf_range(box_lo.y + ry, box_hi.y - ry))
			stones.append(Vector4(c.x, c.y, rx, ry))
	for st in stones:
		var c := Vector2(st.x, st.y)
		var pts := _rough_poly(c, Vector2(st.z, st.w), rng)
		var tone := stone.lerp(earth, rng.randf_range(0.0, 0.3)).lightened(rng.randf_range(-0.03, 0.05))
		_polygon(hi, _offset_poly(pts, Vector2(0.6, 0.8) * s), earth.darkened(0.25))  # Fuge / Schatten
		_polygon(hi, pts, tone.darkened(0.05))
		_polygon(hi, _scale_poly(pts, c + Vector2(-0.5, -0.6) * s, 0.8), tone.lightened(0.04))

	# Ein paar kleine Kiesel (nicht am Rand)
	for i in 8:
		var p := Vector2(rng.randf_range(4.0, 60.0), rng.randf_range(4.0, 60.0)) * s
		var pc := earth.lightened(0.18) if i % 2 == 0 else earth.darkened(0.22)
		_circle(hi, p, rng.randf_range(0.7, 1.1) * s, pc)

	var img := _downsample(hi, size, _SS)
	if planned:
		_scale_alpha(img, 0.45)
		_dashed_border(img, Color(0.98, 0.94, 0.78, 0.95))
	return img


# ---------------------------------------------------------------------------
# Vorkommen-Motive (Masse in 64-px-Einheiten, mal s skaliert)
# ---------------------------------------------------------------------------

## Baumgruppe: drei runde Kronen mit kleinen Stämmen und Schlagschatten.
static func _icon_trees(img: Image, color: Color, rng: RandomNumberGenerator, s: float) -> void:
	# Von hinten (oben) nach vorne (unten) sortiert
	var crowns: Array[Vector3] = [
		Vector3(42, 22, 11.5), Vector3(22, 25, 12.5), Vector3(33, 38, 13.5)]
	var shadow := Color(0, 0, 0, 0.28)
	for t in crowns:
		_ellipse(img, Vector2(t.x + 3.5, t.y + 4.5) * s, Vector2(t.z, t.z * 0.85) * s, shadow)
	var outline := color.darkened(0.7)
	var trunk := Color(0.45, 0.29, 0.15)
	for t in crowns:
		var p := Vector2(t.x, t.y) * s
		var r := t.z * s
		# Stamm: schaut unten ein wenig unter der Krone hervor
		var trunk_rect := Rect2(p.x - 2.2 * s, p.y + r * 0.5, 4.4 * s, r * 0.5 + 3.5 * s)
		img.fill_rect(Rect2i(trunk_rect.grow(1.2 * s)), outline)
		img.fill_rect(Rect2i(trunk_rect), trunk)
		img.fill_rect(Rect2i(Rect2(trunk_rect.position, Vector2(1.4 * s, trunk_rect.size.y))), trunk.lightened(0.2))
		# Krone aus einem Mittelkreis und einem Kranz kleinerer Laubbüschel
		var lobes: Array[Vector3] = [Vector3(p.x, p.y, r * 0.72)]
		var rot := rng.randf_range(0.0, TAU)
		for k in 7:
			var dir := Vector2.from_angle(rot + TAU * k / 7.0)
			var q := p + dir * r * rng.randf_range(0.52, 0.6)
			lobes.append(Vector3(q.x, q.y, r * rng.randf_range(0.4, 0.46)))
		for l in lobes:
			_circle(img, Vector2(l.x, l.y), l.z + 1.5 * s, outline)
		_shaded_blob(img, lobes, p, r, color.lightened(0.08), 0.5, 0.42)


## Steinbrocken: Haufen aus vier kantigen grauen Felsen.
static func _icon_rocks(img: Image, color: Color, rng: RandomNumberGenerator, s: float) -> void:
	# Von hinten nach vorne: Mitte (x, y), Radien (z, w)
	var rocks: Array[Vector4] = [
		Vector4(27, 24, 11.5, 9.5), Vector4(43, 28, 10.5, 9.0),
		Vector4(19, 38, 11.5, 10.0), Vector4(37, 41, 13.5, 11.0)]
	var shadow := Color(0, 0, 0, 0.28)
	for r in rocks:
		_ellipse(img, Vector2(r.x + 3, r.y + 3.5) * s, Vector2(r.z, r.w) * s, shadow)
	for r in rocks:
		_lowpoly_rock(img, Vector2(r.x, r.y) * s, Vector2(r.z, r.w) * s, color, rng, 1.5 * s)


## Erzader: dunkler Felsbrocken mit blaustählernen Kristallen und Glanzpunkten.
static func _icon_ore(img: Image, color: Color, rng: RandomNumberGenerator, s: float) -> void:
	var center := Vector2(32, 39) * s
	var radii := Vector2(22, 14) * s
	_ellipse(img, center + Vector2(3, 3.5) * s, radii, Color(0, 0, 0, 0.3))
	_lowpoly_rock(img, center, radii, Color(0.34, 0.33, 0.37), rng, 1.5 * s)
	# Adern: zackige Linien in Kristallfarbe über den Fels
	var veins: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(15, 40), Vector2(21, 43), Vector2(26, 41), Vector2(31, 46)]),
		PackedVector2Array([Vector2(37, 45), Vector2(42, 42), Vector2(48, 44)]),
	]
	for v in veins:
		for i in v.size() - 1:
			_thick_line(img, v[i] * s, v[i + 1] * s, 1.6 * s, color.lightened(0.15))
	# Kristalle: Basis (x, y), Winkel in Grad, Länge, Breite – von hinten nach vorne
	var shards: Array[PackedFloat32Array] = [
		PackedFloat32Array([33, 33, -95, 20, 8.0]),
		PackedFloat32Array([25, 35, -125, 15, 6.5]),
		PackedFloat32Array([42, 35, -62, 16, 7.0]),
		PackedFloat32Array([18, 40, -150, 10, 5.5]),
		PackedFloat32Array([30, 40, -80, 11, 6.0]),
	]
	var tips := PackedVector2Array()
	for sh in shards:
		var tip := _crystal(img, Vector2(sh[0], sh[1]) * s, deg_to_rad(sh[2]), sh[3] * s, sh[4] * s, color, 1.4 * s)
		tips.append(tip)
	# Glanzpunkte an einigen Kristallspitzen
	for i: int in [0, 2, 4]:
		var dir := (tips[i] - Vector2(shards[i][0], shards[i][1]) * s).normalized()
		_sparkle(img, tips[i] - dir * 3.5 * s, rng.randf_range(3.0, 4.0) * s, Color(1, 1, 1, 0.95))


## Beerenbusch: runder grüner Busch mit roten Beeren. empty = ohne Beeren,
## Laub etwas blasser.
static func _icon_berries(img: Image, color: Color, rng: RandomNumberGenerator, s: float, empty: bool) -> void:
	var p := Vector2(32, 32) * s
	var r := 19.0 * s
	var leaf := Color(0.33, 0.58, 0.24)
	if empty:
		var g := leaf.get_luminance()
		leaf = leaf.lerp(Color(g, g, g), 0.45).darkened(0.08)
	_ellipse(img, p + Vector2(3, 4) * s, Vector2(r, r * 0.88), Color(0, 0, 0, 0.28))
	var lobes: Array[Vector3] = [Vector3(p.x, p.y, r * 0.7)]
	for k in 9:
		var dir := Vector2.from_angle(0.3 + TAU * k / 9.0)
		var q := p + dir * r * rng.randf_range(0.6, 0.66)
		lobes.append(Vector3(q.x, q.y, r * rng.randf_range(0.34, 0.4)))
	var outline := leaf.darkened(0.7)
	for l in lobes:
		_circle(img, Vector2(l.x, l.y), l.z + 1.5 * s, outline)
	_shaded_blob(img, lobes, p, r, leaf, 0.5, 0.35)
	if empty:
		return
	# Beeren gleichmässig verteilt (Zufall mit Mindestabstand, aber fester Seed)
	var berries := PackedVector2Array()
	var tries := 0
	while berries.size() < 9 and tries < 400:
		tries += 1
		var cand := p + Vector2.from_angle(rng.randf_range(0.0, TAU)) * sqrt(rng.randf()) * r * 0.78
		var ok := true
		for b in berries:
			if b.distance_to(cand) < 7.0 * s:
				ok = false
				break
		if ok:
			berries.append(cand)
	var berry_dark := color.darkened(0.6)
	for b in berries:
		_circle(img, b, 3.6 * s, berry_dark)
		_shaded_ellipse(img, b, Vector2(2.7, 2.7) * s, color, 0.45, 0.3)
		_circle(img, b - Vector2(0.9, 0.9) * s, 0.8 * s, Color(1, 1, 1, 0.9))


## Manaquelle: leuchtendes violettes Becken mit hellem Kern, Steinrand,
## Lichtschimmer und Funken.
static func _icon_mana(img: Image, color: Color, rng: RandomNumberGenerator, s: float) -> void:
	var c := Vector2(32, 36) * s
	# Weiches Leuchten mit Alpha-Abfall nach aussen
	var glow := color.lightened(0.3)
	var glow_r := 28.0 * s
	_radial_glow(img, c, glow_r, glow, 0.6)
	# Senkrechte Lichtschimmer über dem Becken
	for i in 3:
		var x := (24.0 + i * 8.0 + rng.randf_range(-1.0, 1.0)) * s
		var top := (8.0 + rng.randf_range(0.0, 6.0)) * s
		var w := (2.0 if i != 1 else 3.0) * s
		for y in range(int(top), int(c.y)):
			var a := 0.45 * (float(y) - top) / (c.y - top)
			for xx in range(int(x - w * 0.5), int(x + w * 0.5)):
				_blend_px(img, xx, y, Color(color.lightened(0.7), a))
	# Becken: dunkler Rand, Farbverlauf zum hellen Kern
	var radii := Vector2(17, 11.5) * s
	_ellipse(img, c, radii + Vector2(2.0, 2.0) * s, color.darkened(0.65))
	var core := c + Vector2(-2.5, -2.0) * s
	var deep := color.darkened(0.25)
	var bright := color.lightened(0.85)
	var x0 := floori(c.x - radii.x)
	var y0 := floori(c.y - radii.y)
	for y in range(y0, ceili(c.y + radii.y) + 1):
		for x in range(x0, ceili(c.x + radii.x) + 1):
			var px := Vector2(x + 0.5, y + 0.5)
			if ((px - c) / radii).length_squared() > 1.0:
				continue
			var t := clampf(((px - core) / radii).length(), 0.0, 1.0)
			var col := bright.lerp(color.lightened(0.2), smoothstep(0.0, 0.55, t))
			col = col.lerp(deep, smoothstep(0.55, 1.0, t))
			img.set_pixel(x, y, col)
	# Wellenring
	_ring(img, c + Vector2(-1, -0.5) * s, radii * 0.62, 0.9 * s, Color(1, 1, 1, 0.35))
	# Randsteine, oben zuerst gezeichnet
	var stones: Array[Vector2] = []
	for k in 11:
		var a := TAU * k / 11.0 + rng.randf_range(-0.12, 0.12)
		stones.append(c + Vector2(cos(a) * (radii.x + 2.2 * s), sin(a) * (radii.y + 2.0 * s)))
	stones.sort_custom(func(u: Vector2, v: Vector2) -> bool: return u.y < v.y)
	for st in stones:
		var sr := Vector2(rng.randf_range(3.4, 4.2), rng.randf_range(2.8, 3.4)) * s
		_lowpoly_rock(img, st, sr, Color(0.6, 0.57, 0.64), rng, 1.1 * s)
	# Funken rund um die Quelle
	var sparks: Array[Vector3] = [
		Vector3(15, 17, 3.8), Vector3(47, 12, 4.6), Vector3(54, 29, 3.2),
		Vector3(10, 34, 3.0), Vector3(33, 9, 3.0), Vector3(27, 33, 2.6)]
	for sp in sparks:
		_sparkle(img, Vector2(sp.x, sp.y) * s, sp.z * s, Color(1.0, 0.96, 1.0, 1.0))


# ---------------------------------------------------------------------------
# Weitere Zeichen-Helfer (Arbeitsbild in Überabtastung)
# ---------------------------------------------------------------------------

## Mischt eine Farbe (mit Alpha) über das vorhandene Pixel.
static func _blend_px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


## Bildet die Helligkeit t (0 = Schatten, 0.5 = Grundfarbe, 1 = Licht) auf
## eine Farbe ab.
static func _shade(base: Color, t: float, light: float, dark: float) -> Color:
	if t < 0.5:
		return base.darkened(dark).lerp(base, t * 2.0)
	return base.lerp(base.lightened(light), t * 2.0 - 1.0)


## Ellipse mit Kugel-Schattierung (Licht von oben links).
static func _shaded_ellipse(img: Image, center: Vector2, radii: Vector2, base: Color,
		light: float = 0.4, dark: float = 0.45) -> void:
	var l_dir := _LIGHT.normalized()
	for y in range(maxi(0, floori(center.y - radii.y)), mini(img.get_height(), ceili(center.y + radii.y) + 1)):
		for x in range(maxi(0, floori(center.x - radii.x)), mini(img.get_width(), ceili(center.x + radii.x) + 1)):
			var d := Vector2((x + 0.5 - center.x) / radii.x, (y + 0.5 - center.y) / radii.y)
			var l2 := d.length_squared()
			if l2 > 1.0:
				continue
			var n := Vector3(d.x, d.y, sqrt(1.0 - l2))
			var t := clampf((n.dot(l_dir) + 0.2) / 1.2, 0.0, 1.0)
			img.set_pixel(x, y, _shade(base, t, light, dark))


## Wolkige Form aus mehreren Kreisen (lobes: Vector3(x, y, Radius)), z. B.
## Baumkrone oder Busch. Die Schattierung mischt die Wölbung der Gesamtform
## (Mitte center, Radius radius) mit der des einzelnen Büschels.
static func _shaded_blob(img: Image, lobes: Array[Vector3], center: Vector2, radius: float,
		base: Color, light: float, dark: float) -> void:
	var l_dir := _LIGHT.normalized()
	var x0 := img.get_width()
	var y0 := img.get_height()
	var x1 := 0
	var y1 := 0
	for l in lobes:
		x0 = mini(x0, floori(l.x - l.z))
		y0 = mini(y0, floori(l.y - l.z))
		x1 = maxi(x1, ceili(l.x + l.z))
		y1 = maxi(y1, ceili(l.y + l.z))
	for y in range(maxi(0, y0), mini(img.get_height(), y1 + 1)):
		for x in range(maxi(0, x0), mini(img.get_width(), x1 + 1)):
			var px := Vector2(x + 0.5, y + 0.5)
			var best := -1.0
			var local := Vector3.ZERO
			for l in lobes:
				var d := (px - Vector2(l.x, l.y)) / l.z
				var l2 := d.length_squared()
				if l2 <= 1.0:
					var z := sqrt(1.0 - l2)
					if z > best:
						best = z
						local = Vector3(d.x, d.y, z)
			if best < 0.0:
				continue
			var g := (px - center) / radius
			var whole := Vector3(g.x, g.y, sqrt(maxf(0.0, 1.0 - g.length_squared())))
			var n := (local * 0.6 + whole).normalized()
			var t := clampf((n.dot(l_dir) + 0.15) / 1.15, 0.0, 1.0)
			img.set_pixel(x, y, _shade(base, t, light, dark))


## Gefülltes Polygon (deckend).
static func _polygon(img: Image, pts: PackedVector2Array, color: Color) -> void:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	for y in range(maxi(0, floori(r.position.y)), mini(img.get_height(), ceili(r.end.y) + 1)):
		for x in range(maxi(0, floori(r.position.x)), mini(img.get_width(), ceili(r.end.x) + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				img.set_pixel(x, y, color)


## Unregelmässiges, rundliches Polygon um center (für Pflastersteine).
static func _rough_poly(center: Vector2, radii: Vector2, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 7
	var a0 := rng.randf_range(0.0, TAU)
	for i in n:
		var a := a0 + TAU * i / n + rng.randf_range(-0.2, 0.2)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y) * rng.randf_range(0.94, 1.08))
	return pts


## Verschiebt alle Punkte eines Polygons.
static func _offset_poly(pts: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + offset)
	return out


## Skaliert ein Polygon um den Punkt pivot.
static func _scale_poly(pts: PackedVector2Array, pivot: Vector2, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(pivot + (p - pivot) * factor)
	return out


## Kantiger Felsbrocken (Low-Poly): unregelmässiger Umriss, Facetten als
## Fächer um einen erhöhten Punkt, jede Facette flach schattiert.
static func _lowpoly_rock(img: Image, center: Vector2, radii: Vector2, base: Color,
		rng: RandomNumberGenerator, outline_w: float) -> void:
	var n := 8
	var pts := PackedVector2Array()
	var a0 := rng.randf_range(0.0, TAU / n)
	for i in n:
		var a := a0 + TAU * i / n + rng.randf_range(-0.18, 0.18)
		var k := rng.randf_range(0.86, 1.05)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y) * k)
	# Umriss: das Polygon etwas vergrössert in dunkler Farbe
	var outer := PackedVector2Array()
	for p in pts:
		outer.append(p + (p - center).normalized() * outline_w)
	_polygon(img, outer, base.darkened(0.68))
	var peak := center + Vector2(-0.2 * radii.x, -0.25 * radii.y)
	var peak3 := Vector3(peak.x, peak.y, minf(radii.x, radii.y) * 0.85)
	var l_dir := _LIGHT.normalized()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var nrm := (Vector3(a.x, a.y, 0.0) - peak3).cross(Vector3(b.x, b.y, 0.0) - peak3).normalized()
		if nrm.z < 0.0:
			nrm = -nrm
		var t := clampf((nrm.dot(l_dir) + 0.1) / 1.0, 0.0, 1.0)
		_triangle(img, peak, a, b, _shade(base, t, 0.4, 0.5))


## Kristallsplitter von base in Richtung angle; linke Facette hell, rechte
## dunkel. Gibt die Spitze zurück.
static func _crystal(img: Image, base: Vector2, angle: float, length: float, width: float,
		color: Color, outline_w: float) -> Vector2:
	var dir := Vector2.from_angle(angle)
	var side := dir.orthogonal() * width * 0.5
	var tip := base + dir * length
	var shoulder := base + dir * length * 0.72
	var grow := side.normalized() * outline_w
	_polygon(img, PackedVector2Array([base - side - grow, shoulder - side - grow, tip + dir * outline_w * 1.6,
			shoulder + side + grow, base + side + grow]), color.darkened(0.7))
	_polygon(img, PackedVector2Array([base - side, shoulder - side, tip, base]), color.lightened(0.35))
	_polygon(img, PackedVector2Array([base, tip, shoulder + side, base + side]), color.darkened(0.2))
	# Heller Grat in der Mitte
	_thick_line(img, base.lerp(tip, 0.1), tip.lerp(base, 0.12), width * 0.12, color.lightened(0.7))
	return tip


## Dicke Linie aus aneinandergereihten Kreisen.
static func _thick_line(img: Image, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var steps := maxi(1, ceili(a.distance_to(b) * 2.0))
	for i in steps + 1:
		_circle(img, a.lerp(b, float(i) / steps), width * 0.5, color)


## Vierzackiger Funkelstern.
static func _sparkle(img: Image, p: Vector2, r: float, color: Color) -> void:
	var w := r * 0.24
	var dark := Color(0.25, 0.1, 0.35, 0.35)
	# Dezenter dunkler Hof, damit der Funke auch auf hellem Boden sichtbar ist
	_radial_glow(img, p, r * 0.9, dark, 0.6)
	for d: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		var o := d.orthogonal() * w
		_triangle(img, p - o, p + o, p + d * r, color)
	_circle(img, p, w * 1.3, color)


## Ellipsenring (Rand der Breite width) mit Alpha-Mischung.
static func _ring(img: Image, center: Vector2, radii: Vector2, width: float, color: Color) -> void:
	var outer := radii + Vector2(width, width) * 0.5
	var inner := radii - Vector2(width, width) * 0.5
	for y in range(maxi(0, floori(center.y - outer.y)), mini(img.get_height(), ceili(center.y + outer.y) + 1)):
		for x in range(maxi(0, floori(center.x - outer.x)), mini(img.get_width(), ceili(center.x + outer.x) + 1)):
			var px := Vector2(x + 0.5, y + 0.5) - center
			if (px / outer).length_squared() <= 1.0 and (px / inner).length_squared() > 1.0:
				_blend_px(img, x, y, color)


## Weiches, kreisförmiges Leuchten: Alpha fällt von der Mitte nach aussen ab.
static func _radial_glow(img: Image, center: Vector2, radius: float, color: Color, alpha: float) -> void:
	for y in range(maxi(0, floori(center.y - radius)), mini(img.get_height(), ceili(center.y + radius) + 1)):
		for x in range(maxi(0, floori(center.x - radius)), mini(img.get_width(), ceili(center.x + radius) + 1)):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center) / radius
			if d < 1.0:
				_blend_px(img, x, y, Color(color, alpha * pow(1.0 - d, 1.8)))


## Verkleinert ein Arbeitsbild um factor (Mittelwert mit vormultipliziertem
## Alpha, damit an transparenten Rändern keine dunklen Säume entstehen).
static func _downsample(src: Image, out_size: int, factor: int) -> Image:
	var sw := src.get_width()
	var data := src.get_data()
	var out := PackedByteArray()
	out.resize(out_size * out_size * 4)
	var n := float(factor * factor)
	for y in out_size:
		for x in out_size:
			var r := 0
			var g := 0
			var b := 0
			var a := 0
			for sy in factor:
				var row := ((y * factor + sy) * sw + x * factor) * 4
				for sx in factor:
					var i := row + sx * 4
					var pa := data[i + 3]
					r += data[i] * pa
					g += data[i + 1] * pa
					b += data[i + 2] * pa
					a += pa
			if a > 0:
				var o := (y * out_size + x) * 4
				out[o] = roundi(float(r) / a)
				out[o + 1] = roundi(float(g) / a)
				out[o + 2] = roundi(float(b) / a)
				out[o + 3] = roundi(a / n)
	return Image.create_from_data(out_size, out_size, false, Image.FORMAT_RGBA8, out)


## "Leere" Variante: entsättigt, dunkler und zu 60 % deckend.
static func _fade_image(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var l := c.get_luminance()
			var f := Color(l, l, l).lerp(c, 0.25).darkened(0.3)
			f.a = c.a * 0.6
			img.set_pixel(x, y, f)


## Multipliziert den Alphakanal aller Pixel mit factor.
static func _scale_alpha(img: Image, factor: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			c.a *= factor
			img.set_pixel(x, y, c)


## Gestrichelte Umrandung 2 px innerhalb des Kachelrands (Baustellen-Look).
## Die Striche sind so verteilt, dass an jeder Ecke ein Winkel entsteht.
static func _dashed_border(img: Image, color: Color) -> void:
	var size := img.get_width()
	var sf := float(size) / 64.0
	var inset := maxi(1, roundi(2.0 * sf))
	var thick := maxi(1, roundi(2.0 * sf))
	var side := float(size - 2 * inset)  # Kantenlänge der Umrandung
	var period := side / 6.0
	var dash := period * 0.6
	for y in range(inset, size - inset):
		for x in range(inset, size - inset):
			var lx := x - inset
			var ly := y - inset
			var last := size - 2 * inset - 1
			var t := -1.0
			if ly < thick:
				t = lx + 0.5
			elif lx > last - thick:
				t = ly + 0.5
			elif ly > last - thick:
				t = last - lx + 0.5
			elif lx < thick:
				t = last - ly + 0.5
			if t < 0.0:
				continue
			if fmod(t + dash * 0.5, period) < dash:
				img.set_pixel(x, y, color)
