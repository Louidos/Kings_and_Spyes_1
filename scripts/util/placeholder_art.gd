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


static func _pattern_lava(img: Image, base: Color, rng: RandomNumberGenerator, s: float) -> void:
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
