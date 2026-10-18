## HudIcons
##
## Kleine Symbole der oberen Leiste, im Code gezeichnet (keine Grafikdateien nötig): Fenster-Knöpfe
## (Forschung, Helden, Armee, Diplomatie, Spionage, Reich), Bewohner und König. Doppelt so gross
## gezeichnet und verkleinert (Kantenglättung wie PlaceholderArt), je Art einmal erzeugt.
class_name HudIcons
extends RefCounted

## Kantenlänge der fertigen Symbole (Pixel)
const SIZE := 20
const SS := 3
const LIGHT := Color(0.95, 0.91, 0.82)
const GOLD := Color(0.98, 0.8, 0.3)
const DARK := Color(0.07, 0.06, 0.05, 0.9)

static var _cache: Dictionary = {}


## Symbol einer Art: "research", "heroes", "army", "diplomacy", "espionage", "kingdom", "population", "king",
## "open" / "closed" (Dreieck eines aufgeklappten bzw. zugeklappten Abschnitts)
static func get_icon(kind: String) -> Texture2D:
	if _cache.has(kind):
		return _cache[kind]
	var n := SIZE * SS
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var s := float(n)
	match kind:
		"research":
			# Aufgeschlagenes Buch
			_poly(img, [Vector2(0.08, 0.28), Vector2(0.48, 0.36), Vector2(0.48, 0.86), Vector2(0.08, 0.76)], s, DARK, 0.06)
			_poly(img, [Vector2(0.52, 0.36), Vector2(0.92, 0.28), Vector2(0.92, 0.76), Vector2(0.52, 0.86)], s, DARK, 0.06)
			_poly(img, [Vector2(0.11, 0.31), Vector2(0.47, 0.39), Vector2(0.47, 0.82), Vector2(0.11, 0.73)], s, LIGHT)
			_poly(img, [Vector2(0.53, 0.39), Vector2(0.89, 0.31), Vector2(0.89, 0.73), Vector2(0.53, 0.82)], s, LIGHT)
			for i in 3:
				var y := 0.47 + i * 0.1
				_line(img, Vector2(0.17, y), Vector2(0.41, y + 0.05), s, Color(0.45, 0.4, 0.33), 0.035)
				_line(img, Vector2(0.59, y + 0.05), Vector2(0.83, y), s, Color(0.45, 0.4, 0.33), 0.035)
		"heroes":
			_star(img, Vector2(0.5, 0.52), 0.44, 0.19, s, DARK)
			_star(img, Vector2(0.5, 0.52), 0.38, 0.16, s, GOLD)
		"army":
			for flip in [false, true]:
				var a := Vector2(0.86, 0.14) if flip else Vector2(0.14, 0.14)
				var b := Vector2(0.24, 0.8) if flip else Vector2(0.76, 0.8)
				_line(img, a, b, s, DARK, 0.17)
				_line(img, a, b, s, LIGHT, 0.09)
				var side := Vector2(0.14, 0.14) if not flip else Vector2(-0.14, 0.14)
				var guard := b - (b - a).normalized() * 0.12
				_line(img, guard - Vector2(side.y, -side.x), guard + Vector2(side.y, -side.x), s, GOLD.darkened(0.2), 0.08)
		"diplomacy":
			# Schriftrolle mit Siegel
			_poly(img, [Vector2(0.16, 0.18), Vector2(0.84, 0.18), Vector2(0.84, 0.82), Vector2(0.16, 0.82)], s, DARK, 0.06)
			_poly(img, [Vector2(0.2, 0.22), Vector2(0.8, 0.22), Vector2(0.8, 0.78), Vector2(0.2, 0.78)], s, Color(0.93, 0.86, 0.68))
			for i in 3:
				_line(img, Vector2(0.28, 0.33 + i * 0.12), Vector2(0.72, 0.33 + i * 0.12), s, Color(0.45, 0.38, 0.28), 0.04)
			_circle(img, Vector2(0.66, 0.72), 0.13, s, Color(0.75, 0.15, 0.15))
		"espionage":
			# Auge
			_ellipse(img, Vector2(0.5, 0.5), Vector2(0.46, 0.28), s, DARK)
			_ellipse(img, Vector2(0.5, 0.5), Vector2(0.4, 0.22), s, LIGHT)
			_circle(img, Vector2(0.5, 0.5), 0.16, s, Color(0.3, 0.55, 0.8))
			_circle(img, Vector2(0.5, 0.5), 0.07, s, DARK)
		"kingdom":
			# Burg mit Zinnen
			_poly(img, [Vector2(0.12, 0.3), Vector2(0.88, 0.3), Vector2(0.88, 0.9), Vector2(0.12, 0.9)], s, DARK, 0.05)
			_poly(img, [Vector2(0.16, 0.36), Vector2(0.84, 0.36), Vector2(0.84, 0.86), Vector2(0.16, 0.86)], s, LIGHT)
			for i in 4:
				var x := 0.14 + i * 0.21
				_poly(img, [Vector2(x, 0.16), Vector2(x + 0.12, 0.16), Vector2(x + 0.12, 0.38), Vector2(x, 0.38)], s, LIGHT)
			_poly(img, [Vector2(0.4, 0.58), Vector2(0.6, 0.58), Vector2(0.6, 0.86), Vector2(0.4, 0.86)], s, Color(0.35, 0.25, 0.15))
		"population":
			# Zwei Köpfe mit Schultern
			for p in [[Vector2(0.34, 0.34), Color(0.75, 0.72, 0.66)], [Vector2(0.62, 0.38), LIGHT]]:
				var c: Vector2 = p[0]
				_circle(img, c, 0.15, s, DARK)
				_circle(img, c, 0.12, s, p[1])
				_ellipse(img, c + Vector2(0.0, 0.42), Vector2(0.22, 0.2), s, DARK)
				_ellipse(img, c + Vector2(0.0, 0.42), Vector2(0.18, 0.17), s, p[1])
		"king":
			# Krone
			var crown := [Vector2(0.12, 0.78), Vector2(0.12, 0.3), Vector2(0.32, 0.52), Vector2(0.5, 0.2), Vector2(0.68, 0.52),
					Vector2(0.88, 0.3), Vector2(0.88, 0.78)]
			_poly(img, crown, s, DARK, 0.06)
			_poly(img, crown, s, GOLD)
			_circle(img, Vector2(0.5, 0.64), 0.07, s, Color(0.8, 0.2, 0.25))
		"open":
			_poly(img, [Vector2(0.2, 0.32), Vector2(0.8, 0.32), Vector2(0.5, 0.74)], s, Color(0.8, 0.78, 0.72))
		"closed":
			_poly(img, [Vector2(0.32, 0.2), Vector2(0.74, 0.5), Vector2(0.32, 0.8)], s, Color(0.8, 0.78, 0.72))
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_cache[kind] = tex
	return tex


## Vieleck in Anteilen der Bildgrösse; grow > 0: um so viel (Anteil) nach aussen erweitert (Rand)
static func _poly(img: Image, pts: Array, s: float, color: Color, grow: float = 0.0) -> void:
	var out := PackedVector2Array()
	var center := Vector2.ZERO
	for p in pts:
		center += p
	center /= maxf(float(pts.size()), 1.0)
	for p in pts:
		var q: Vector2 = p
		if grow > 0.0:
			q = center + (q - center) * (1.0 + grow * 2.0)
		out.append(q * s)
	PlaceholderArt._polygon(img, out, color)


static func _line(img: Image, a: Vector2, b: Vector2, s: float, color: Color, width: float) -> void:
	PlaceholderArt._thick_line(img, a * s, b * s, width * s, color)


static func _circle(img: Image, c: Vector2, r: float, s: float, color: Color) -> void:
	PlaceholderArt._ellipse(img, c * s, Vector2(r, r) * s, color)


static func _ellipse(img: Image, c: Vector2, radii: Vector2, s: float, color: Color) -> void:
	PlaceholderArt._ellipse(img, c * s, radii * s, color)


static func _star(img: Image, c: Vector2, outer: float, inner: float, s: float, color: Color) -> void:
	var pts: Array = []
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		pts.append(c + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * r)
	_poly(img, pts, s, color)
