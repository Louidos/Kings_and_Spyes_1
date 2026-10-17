## FigureArt
##
## Prozedurale Spielfiguren (statt Scheiben mit Buchstaben), solange keine echte Grafik in
## assets/sprites/ liegt: Körper, Kopf, Kopfbedeckung, Waffe oder Werkzeug je Klasse bzw.
## Beruf, Farbe nach Reich (oder Aussehen/Skin), Licht und Finsternis unterscheidbar
## (Finsternis: graue Haut, glühende Augen, dunkles Eisen mit Hörnern und Dornen).
## Helden tragen Umhang und Aura/Krone/Heiligenschein, Spione eine Kapuze, Reiter sitzen
## auf Pferd oder Wolf, Monster haben je Art eine eigene Form, Belagerungswaffen und
## Karawanen sind Fahrzeuge.
##
## Welche Teile eine Figur hat, steht in data/units.json → figures (je Stufe, Beruf und
## Fraktion) und optional als "figure" am Einheitentyp bzw. Helden (heroes.json).
## spec_for() setzt daraus eine Beschreibung zusammen, make_figure() zeichnet sie einmal;
## Assets.figure() merkt sich das Bild je Beschreibung (Leistung bei vielen Einheiten).
##
## Koordinaten beim Zeichnen: x von −50 bis 50, y von −95 (oben) bis 5; die Füsse stehen
## bei (0, 0). Gezeichnet wird doppelt so gross und danach verkleinert (Kantenglättung).
class_name FigureArt
extends RefCounted

## Überabtastung wie bei der Platzhalter-Kunst
const SS := 2
## Anteil der Bildhöhe, auf dem die Füsse stehen (y = 0)
const FEET := 0.95
## Kopfoberkante einer Figur in Bildhöhen über den Füssen (für Rangabzeichen)
const HEAD_TOP := 0.84
## Oberkante je Figurenart, wenn sie von HEAD_TOP abweicht (Tiere, Geräte, Wagen)
const TOP_BY_KIND := {"mounted": 0.8, "wolf": 0.5, "spider": 0.49, "golem": 0.8, "wyvern": 0.86, "spirit": 0.78,
		"ram": 0.55, "catapult": 0.72, "caravan": 0.54}


## Oberkante der Figur dieser Art in Bildhöhen über den Füssen
static func head_top(kind: String) -> float:
	return float(TOP_BY_KIND.get(kind, HEAD_TOP))

const WOOD := Color(0.47, 0.32, 0.18)
const WOOD_DARK := Color(0.32, 0.21, 0.12)
const GOLD := Color(0.98, 0.8, 0.28)
const LEATHER := Color(0.36, 0.24, 0.15)
const BONE := Color(0.9, 0.87, 0.78)
const OUTLINE := Color(0.07, 0.06, 0.08)


## Zeichenstift: Bild, Ursprung (Füsse) und Massstab in Pixeln je Einheit
class Pen:
	extends RefCounted
	var img: Image
	var origin: Vector2
	var k: float
	var flip := 1.0

	func _init(p_img: Image, p_origin: Vector2, p_k: float) -> void:
		img = p_img
		origin = p_origin
		k = p_k

	func p(x: float, y: float) -> Vector2:
		return origin + Vector2(x * flip, y) * k

	func poly(pts: Array, color: Color) -> void:
		var out := PackedVector2Array()
		for v in pts:
			var q: Vector2 = v
			out.append(p(q.x, q.y))
		PlaceholderArt._polygon(img, out, color)

	func ell(x: float, y: float, rx: float, ry: float, color: Color) -> void:
		PlaceholderArt._ellipse(img, p(x, y), Vector2(rx, ry) * k, color)

	func shaded(x: float, y: float, rx: float, ry: float, color: Color) -> void:
		PlaceholderArt._shaded_ellipse(img, p(x, y), Vector2(rx, ry) * k, color, 0.35, 0.4)

	func line(x1: float, y1: float, x2: float, y2: float, width: float, color: Color) -> void:
		PlaceholderArt._thick_line(img, p(x1, y1), p(x2, y2), width * k, color)

	func glow(x: float, y: float, radius: float, color: Color, alpha: float) -> void:
		PlaceholderArt._radial_glow(img, p(x, y), radius * k, color, alpha)

	func ring(x: float, y: float, rx: float, ry: float, width: float, color: Color) -> void:
		PlaceholderArt._ring(img, p(x, y), Vector2(rx, ry) * k, width * k, color)

	## Bogen als dicke Linie (Winkel in Grad, 0 = rechts, 90 = unten)
	func arc(x: float, y: float, radius: float, from_deg: float, to_deg: float, width: float, color: Color) -> void:
		var steps := 10
		var last := Vector2(x, y) + Vector2.from_angle(deg_to_rad(from_deg)) * radius
		for i in range(1, steps + 1):
			var a := deg_to_rad(lerpf(from_deg, to_deg, float(i) / steps))
			var q := Vector2(x, y) + Vector2.from_angle(a) * radius
			line(last.x, last.y, q.x, q.y, width, color)
			last = q


# ---------------------------------------------------------------------------
# Beschreibung zusammensetzen
# ---------------------------------------------------------------------------

## Beschreibung der Figur eines Einheitentyps (units.json bzw. Held als Einheitentyp):
## figures.tiers[Stufe] ← "figure" des Typs ← Werkzeug des Berufs (Bewohner), jeweils mit
## by_faction-Zusätzen. color = Grundfarbe (Reich oder Typ), skin = Skin-Daten oder {}.
static func spec_for(type_def: Dictionary, faction_id: String, color: Color, skin: Dictionary,
		job_id: String = "") -> Dictionary:
	var cfg: Dictionary = DataDB.unit_figures()
	var tiers: Dictionary = cfg.get("tiers", {})
	var tier := str(type_def.get("tier", ""))
	var merged := {}
	_merge(merged, tiers.get("default", {}), faction_id)
	_merge(merged, tiers.get(tier, {}), faction_id)
	var hero := DataDB.get_hero_type(str(type_def.get("id", ""))) if tier == "hero" else {}
	_merge(merged, hero.get("figure", type_def.get("figure", {})), faction_id)
	if bool(merged.get("tool_by_job", false)):
		var jobs: Dictionary = cfg.get("jobs", {})
		merged["gear"] = str(jobs.get(job_id, jobs.get("idle", "none")))
	var align := faction_id if faction_id in ["good", "evil"] else ("wild" if faction_id == "wild" else "neutral")
	if merged.has("align"):
		align = str(merged["align"])
	var looks: Dictionary = cfg.get("factions", {})
	var look: Dictionary = looks.get(align, looks.get("neutral", {}))
	var body := color
	var trim: Color = _color(merged.get("trim", ""), body.lightened(0.45))
	var pattern := str(merged.get("pattern", ""))
	if not skin.is_empty():
		var mix := float(DataDB.trp("skins.tint_mix", 0.55))
		body = color.lerp(skin.get("tint", color), mix)
		trim = skin.get("trim", trim)
		pattern = str(skin.get("pattern", pattern))
	var cape_default: Variant = merged.get("cape", "")
	var spec := {
		"kind": str(merged.get("kind", "humanoid")),
		"outfit": str(merged.get("outfit", "soldier")),
		"armor": str(merged.get("armor", "light")),
		"head": str(merged.get("head", "none")),
		"gear": str(merged.get("gear", "none")),
		"offhand": str(merged.get("offhand", "")),
		"shield": str(merged.get("shield", "")),
		"mount": str(merged.get("mount", "")),
		"mark": str(merged.get("mark", "")),
		"pattern": pattern,
		"align": align,
		"body": body.to_html(false),
		"trim": trim.to_html(false),
		"cape": "" if str(cape_default).is_empty() else _color(cape_default, body).to_html(false),
		"skin": str(merged.get("skin_color", look.get("skin", "#d9ad82"))),
		"metal": str(merged.get("metal", look.get("metal", "#b8bcc4"))),
		"eyes": str(look.get("eyes", "#222222")),
		"glow_eyes": bool(look.get("glow_eyes", false)),
		"horns": bool(merged.get("horns", look.get("horns", false))),
		"accent": str(merged.get("accent", look.get("accent", "#9fd8ff"))),
	}
	return spec


## Schlüssel für den Zwischenspeicher (gleiche Beschreibung = gleiches Bild)
static func spec_key(spec: Dictionary, size: int) -> String:
	var keys := spec.keys()
	keys.sort()
	var parts := PackedStringArray([str(size)])
	for key in keys:
		parts.append("%s=%s" % [key, str(spec[key])])
	return "figure:" + "|".join(parts)


static func _merge(into: Dictionary, src: Variant, faction_id: String) -> void:
	if not (src is Dictionary):
		return
	var d: Dictionary = src
	for key in d:
		if str(key) != "by_faction" and not str(key).begins_with("_"):
			into[key] = d[key]
	var by_faction: Dictionary = d.get("by_faction", {})
	if by_faction.has(faction_id):
		_merge(into, by_faction[faction_id], faction_id)


static func _color(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	var s := str(v)
	if s.is_empty() or not Color.html_is_valid(s):
		return fallback
	return Color.html(s)


# ---------------------------------------------------------------------------
# Zeichnen
# ---------------------------------------------------------------------------

## Zeichnet die Figur (quadratisch, size × size Pixel, Füsse bei FEET der Höhe)
static func make_figure(spec: Dictionary, size: int = 64) -> Image:
	var s := size * SS
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pen := Pen.new(img, Vector2(s * 0.5, s * FEET), s / 100.0)
	var kind := str(spec.get("kind", "humanoid"))
	# Bodenschatten
	pen.ell(0, 0, 24 if kind in ["humanoid", "skeleton", "spirit"] else 36, 6, Color(0, 0, 0, 0.28))
	match kind:
		"mounted":
			_mount(pen, spec)
			var rider := Pen.new(img, pen.p(0, -18), pen.k * 0.72)
			_humanoid(rider, spec, true)
		"wolf":
			_wolf(pen, Color.html(str(spec["body"])), Color(1.0, 0.75, 0.2))
		"spider":
			_spider(pen, Color.html(str(spec["body"])))
		"golem":
			_golem(pen, Color.html(str(spec["body"])))
		"wyvern":
			_wyvern(pen, Color.html(str(spec["body"])))
		"ram":
			_ram(pen, spec)
		"catapult":
			_catapult(pen, spec)
		"caravan":
			_caravan(pen, spec)
		"spirit":
			_spirit(pen, spec)
		"skeleton":
			var bones := spec.duplicate()
			bones["skin"] = BONE.to_html(false)
			bones["body"] = BONE.darkened(0.15).to_html(false)
			bones["outfit"] = "skeleton"
			_humanoid(pen, bones, false)
		_:
			_humanoid(pen, spec, false)
	var out := PlaceholderArt._downsample(img, size, SS)
	_outline(out)
	return out


## Dunkle Kontur (1 Pixel) um die Figur, damit sie sich vom Boden abhebt
static func _outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.get_data()
	for y in h:
		for x in w:
			if src[(y * w + x) * 4 + 3] >= 110:
				continue
			var near := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and src[(ny * w + nx) * 4 + 3] >= 170:
					near = true
					break
			if near:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(Color(OUTLINE, 0.75)))


## Mensch, Elf, Ork … von vorn. rider = auf einem Reittier (ohne Beine)
static func _humanoid(pen: Pen, spec: Dictionary, rider: bool) -> void:
	var body := Color.html(str(spec["body"]))
	var trim := Color.html(str(spec["trim"]))
	var skin := Color.html(str(spec["skin"]))
	var metal := Color.html(str(spec["metal"]))
	var outfit := str(spec["outfit"])
	var armor := str(spec["armor"])
	var gear := str(spec["gear"])
	var mark := str(spec["mark"])
	var evil := str(spec["align"]) == "evil"
	var dark := body.darkened(0.45)
	var skeleton := outfit == "skeleton"
	# Hinter der Figur: Aura, Umhang, Bündel
	if mark == "aura":
		pen.glow(0, -46, 50, trim, 0.55)
	if not str(spec["cape"]).is_empty():
		var cape := Color.html(str(spec["cape"]))
		pen.poly([Vector2(-15, -58), Vector2(15, -58), Vector2(23, -3), Vector2(0, -7), Vector2(-23, -3)], cape.darkened(0.25))
		pen.poly([Vector2(-13, -58), Vector2(13, -58), Vector2(19, -8), Vector2(-19, -8)], cape)
	if gear == "bundle":
		pen.shaded(-9, -50, 12, 11, Color(0.6, 0.48, 0.32))
	if gear == "bow":
		_bow(pen, metal)
	# Beine bzw. Gewand
	var long_robe := armor in ["robe", "cloak"]
	if not rider:
		if long_robe:
			pen.poly([Vector2(-12, -40), Vector2(12, -40), Vector2(17, -2), Vector2(-17, -2)], body.darkened(0.12))
			pen.ell(-6, -1, 5, 2.6, LEATHER.darkened(0.3))
			pen.ell(6, -1, 5, 2.6, LEATHER.darkened(0.3))
		else:
			var legs := metal.darkened(0.15) if armor == "heavy" else (BONE if skeleton else dark)
			var lw := 2.6 if skeleton else 0.0
			if skeleton:
				pen.line(-5, -30, -6, -3, lw, legs)
				pen.line(5, -30, 6, -3, lw, legs)
			else:
				pen.poly([Vector2(-10, -31), Vector2(-1.5, -31), Vector2(-2, -3), Vector2(-9, -3)], legs)
				pen.poly([Vector2(1.5, -31), Vector2(10, -31), Vector2(9, -3), Vector2(2, -3)], legs.darkened(0.12))
			pen.ell(-6, -2, 5.5, 3, LEATHER if not evil else Color(0.18, 0.15, 0.17))
			pen.ell(6, -2, 5.5, 3, LEATHER if not evil else Color(0.18, 0.15, 0.17))
	# Rumpf
	if skeleton:
		pen.line(0, -58, 0, -30, 3, BONE)
		for i in 4:
			var yy := -54.0 + i * 6.0
			pen.line(-9 + i, yy, 9 - i, yy, 2.2, BONE.darkened(0.08))
		pen.ell(0, -30, 8, 3, BONE.darkened(0.2))
	else:
		var hem := -22.0 if outfit in ["villager", "messenger", "refugee", "militia"] and not long_robe else -28.0
		pen.poly([Vector2(-14, -58), Vector2(14, -58), Vector2(12.5, hem), Vector2(-12.5, hem)], body)
		pen.poly([Vector2(-14, -58), Vector2(-5, -58), Vector2(-5, hem), Vector2(-12.5, hem)], body.lightened(0.12))
		_pattern(pen, str(spec["pattern"]), trim, hem)
		if armor == "heavy":
			pen.poly([Vector2(-10, -56), Vector2(10, -56), Vector2(8.5, -34), Vector2(-8.5, -34)], metal)
			pen.poly([Vector2(-10, -56), Vector2(-2, -56), Vector2(-2, -34), Vector2(-8.5, -34)], metal.lightened(0.2))
			pen.line(0, -55, 0, -36, 1.2, metal.darkened(0.35))
		elif armor == "light" and outfit == "soldier":
			pen.poly([Vector2(-9, -56), Vector2(9, -56), Vector2(7, -44), Vector2(-7, -44)], LEATHER.lightened(0.1))
		# Gürtel
		var belt := trim if outfit in ["soldier", "hero", "king"] else LEATHER
		pen.poly([Vector2(-12.6, -33), Vector2(12.6, -33), Vector2(12.4, -29.5), Vector2(-12.4, -29.5)], belt.darkened(0.15))
		pen.ell(0, -31.3, 2.2, 1.9, GOLD if outfit in ["hero", "king"] else metal)
	# Schultern
	if armor == "heavy" or outfit in ["hero", "king"]:
		pen.shaded(-15, -55, 7, 5, metal)
		pen.shaded(15, -55, 7, 5, metal)
		pen.ell(-15, -51, 7, 1.4, trim)
		pen.ell(15, -51, 7, 1.4, trim)
		if evil:
			pen.poly([Vector2(-19, -58), Vector2(-16, -58), Vector2(-21, -66)], BONE)
			pen.poly([Vector2(16, -58), Vector2(19, -58), Vector2(21, -66)], BONE)
	# Arme
	var arm := BONE if skeleton else body.darkened(0.1)
	var aw := 2.6 if skeleton else 5.5
	pen.line(-14, -54, -18, -36, aw, arm)
	pen.line(14, -54, 18, -39, aw, arm)
	pen.ell(-18, -35, 3.4, 3.4, skin)
	pen.ell(18, -38, 3.4, 3.4, skin)
	# Spionage-Umhang über dem Körper
	if armor == "cloak":
		pen.poly([Vector2(-15, -60), Vector2(15, -60), Vector2(19, -8), Vector2(5, -12), Vector2(0, -6),
				Vector2(-5, -12), Vector2(-19, -8)], body.darkened(0.35))
		pen.poly([Vector2(-2, -58), Vector2(2, -58), Vector2(1, -12), Vector2(-1, -12)], body.darkened(0.55))
	# Kopf
	pen.line(0, -60, 0, -57, 5, skin.darkened(0.15))
	if skeleton:
		pen.shaded(0, -68, 9.5, 10, BONE)
		pen.ell(-3.5, -68, 2.6, 2.8, Color(0.08, 0.06, 0.08))
		pen.ell(3.5, -68, 2.6, 2.8, Color(0.08, 0.06, 0.08))
		pen.glow(-3.5, -68, 4, Color(0.6, 1.0, 0.5), 0.9)
		pen.glow(3.5, -68, 4, Color(0.6, 1.0, 0.5), 0.9)
		pen.line(-3, -61.5, 3, -61.5, 1.2, Color(0.2, 0.18, 0.18))
	else:
		_head(pen, spec, skin, metal, body, trim)
	# Waffe oder Werkzeug (rechte Hand), Schild (linker Arm)
	_gear(pen, gear, spec, metal, trim)
	var offhand := str(spec["offhand"])
	if not offhand.is_empty():
		pen.flip = -1.0
		_gear(pen, offhand, spec, metal, trim)
		pen.flip = 1.0
	if not str(spec["shield"]).is_empty():
		_shield(pen, str(spec["shield"]), body, trim, metal, str(spec["pattern"]))
	# Abzeichen über dem Kopf
	match mark:
		"halo":
			pen.ring(0, -86, 9, 2.8, 2.2, GOLD)
		"crown":
			_crown(pen, -82, 8)


static func _head(pen: Pen, spec: Dictionary, skin: Color, metal: Color, body: Color, trim: Color) -> void:
	var head := str(spec["head"])
	var evil := str(spec["align"]) == "evil"
	var eyes := Color.html(str(spec["eyes"]))
	var glow := bool(spec["glow_eyes"])
	if head == "hood":
		# Kapuze: Gesicht im Schatten, nur die Augen leuchten
		var hood := body.darkened(0.35)
		pen.poly([Vector2(-13, -60), Vector2(-14, -70), Vector2(-8, -80), Vector2(0, -84), Vector2(8, -80),
				Vector2(14, -70), Vector2(13, -60)], hood)
		pen.ell(0, -67, 7.5, 8, hood.darkened(0.6))
		var shine := Color(1.0, 0.35, 0.2) if evil else Color(0.85, 0.95, 1.0)
		pen.ell(-3, -68, 1.5, 1.2, shine)
		pen.ell(3, -68, 1.5, 1.2, shine)
		return
	pen.shaded(0, -68, 9.5, 10, skin)
	pen.ell(-3.5, -68, 1.6, 1.8, eyes)
	pen.ell(3.5, -68, 1.6, 1.8, eyes)
	if glow:
		pen.glow(-3.5, -68, 3.5, eyes, 0.8)
		pen.glow(3.5, -68, 3.5, eyes, 0.8)
	if evil and head != "helmet":
		# Spitze Ohren bzw. Hauer der Finsternis
		pen.poly([Vector2(-9, -70), Vector2(-15, -76), Vector2(-9, -65)], skin.darkened(0.1))
		pen.poly([Vector2(9, -70), Vector2(15, -76), Vector2(9, -65)], skin.darkened(0.1))
	match head:
		"helmet":
			pen.poly([Vector2(-10.5, -67), Vector2(-10, -74), Vector2(-6, -79), Vector2(0, -80.5), Vector2(6, -79),
					Vector2(10, -74), Vector2(10.5, -67)], metal)
			pen.poly([Vector2(-10.5, -67), Vector2(-10, -74), Vector2(-6, -79), Vector2(-2, -80), Vector2(-3, -67)],
					metal.lightened(0.18))
			pen.line(0, -70, 0, -63, 1.6, metal.darkened(0.3))
			if bool(spec["horns"]):
				_horns(pen)
			else:
				pen.line(0, -80, 0, -86, 2.4, trim)
				pen.line(0, -86, -4, -82, 2.0, trim)
		"crown":
			pen.ell(0, -76, 9, 4.5, Color(0.35, 0.22, 0.15))
			_crown(pen, -76, 9)
		"cap":
			pen.poly([Vector2(-10, -71), Vector2(-8, -78), Vector2(0, -80), Vector2(8, -78), Vector2(10, -71)], body.darkened(0.3))
			pen.ell(0, -71.5, 10.5, 1.8, body.darkened(0.45))
		"hat":
			pen.poly([Vector2(-11, -74), Vector2(11, -74), Vector2(4, -96), Vector2(-1, -95)], body.darkened(0.2))
			pen.ell(0, -74, 15, 3.6, body.darkened(0.35))
			pen.ell(1.5, -88, 2.2, 2.2, trim)
		"brim":
			pen.ell(0, -74, 15, 3.8, WOOD.darkened(0.1))
			pen.ell(0, -78, 8, 5, WOOD)
		"hair":
			pen.poly([Vector2(-10, -66), Vector2(-10, -74), Vector2(-5, -79), Vector2(5, -79), Vector2(10, -74),
					Vector2(10, -66), Vector2(7, -73), Vector2(-7, -73)], trim.darkened(0.35))
			pen.poly([Vector2(-10, -70), Vector2(-12, -54), Vector2(-7, -60)], trim.darkened(0.35))
		"horns":
			_horns(pen)
		"beard":
			pen.poly([Vector2(-8, -66), Vector2(8, -66), Vector2(5, -55), Vector2(0, -52), Vector2(-5, -55)], Color(0.55, 0.3, 0.16))
			pen.poly([Vector2(-10.5, -68), Vector2(-10, -74), Vector2(-6, -79), Vector2(0, -80.5), Vector2(6, -79),
					Vector2(10, -74), Vector2(10.5, -68)], metal)


static func _horns(pen: Pen) -> void:
	pen.poly([Vector2(-8, -75), Vector2(-11, -74), Vector2(-18, -82), Vector2(-17, -90), Vector2(-14, -82)], BONE)
	pen.poly([Vector2(8, -75), Vector2(11, -74), Vector2(18, -82), Vector2(17, -90), Vector2(14, -82)], BONE)


static func _crown(pen: Pen, y: float, w: float) -> void:
	pen.poly([Vector2(-w, y + 3), Vector2(-w, y - 5), Vector2(-w * 0.5, y - 1), Vector2(0, y - 8), Vector2(w * 0.5, y - 1),
			Vector2(w, y - 5), Vector2(w, y + 3)], GOLD)
	pen.ell(0, y - 1, 1.6, 1.6, Color(0.85, 0.15, 0.2))


## Muster des Aussehens (Skin) auf dem Wappenrock
static func _pattern(pen: Pen, pattern: String, trim: Color, hem: float) -> void:
	match pattern:
		"stripes":
			pen.poly([Vector2(-3, -58), Vector2(3, -58), Vector2(3, hem), Vector2(-3, hem)], trim)
		"chevron":
			pen.poly([Vector2(-13, -50), Vector2(0, -38), Vector2(13, -50), Vector2(13, -44), Vector2(0, -32), Vector2(-13, -44)], trim)
		"quartered":
			pen.poly([Vector2(-14, -58), Vector2(0, -58), Vector2(0, -43), Vector2(-13.3, -43)], trim)
			pen.poly([Vector2(0, -43), Vector2(13.3, -43), Vector2(12.5, hem), Vector2(0, hem)], trim)
		"sash":
			pen.poly([Vector2(-14, -58), Vector2(-7, -58), Vector2(13, -36), Vector2(13, -29), Vector2(9, -29)], trim)
		"border":
			pen.poly([Vector2(-12.5, hem - 4), Vector2(12.5, hem - 4), Vector2(12.5, hem), Vector2(-12.5, hem)], trim)
			pen.poly([Vector2(-14, -58), Vector2(14, -58), Vector2(14, -55), Vector2(-14, -55)], trim)


static func _gear(pen: Pen, gear: String, spec: Dictionary, metal: Color, trim: Color) -> void:
	var evil := str(spec["align"]) == "evil"
	var blade := metal.lightened(0.35) if not evil else metal.lightened(0.1)
	var accent := Color.html(str(spec["accent"]))
	match gear:
		"sword":
			pen.line(19, -41, 25, -68, 3.2, blade)
			pen.line(14.5, -41, 23, -39, 2.6, GOLD if not evil else metal.darkened(0.2))
		"greatsword":
			pen.line(19, -41, 28, -84, 4.4, blade)
			pen.line(13.5, -42, 24, -39, 3.0, GOLD if not evil else metal.darkened(0.2))
		"dagger":
			pen.line(19, -40, 23, -52, 2.4, blade)
			pen.line(16, -40, 22, -39, 1.8, LEATHER)
		"spear":
			pen.line(21, -6, 21, -88, 2.2, WOOD)
			pen.poly([Vector2(17.5, -86), Vector2(24.5, -86), Vector2(21, -96)], blade)
		"lance":
			pen.line(10, -24, 36, -84, 3.0, WOOD)
			pen.poly([Vector2(33, -81), Vector2(38.5, -79), Vector2(39, -94)], blade)
			pen.poly([Vector2(17, -40), Vector2(24, -50), Vector2(16, -50)], trim)
		"crossbow":
			pen.line(-6, -44, 25, -44, 3.4, WOOD)
			pen.arc(22, -44, 10, -90, 90, 2.4, metal)
			pen.line(22, -54, 22, -34, 0.8, Color(0.85, 0.85, 0.8))
		"staff", "staff_heal", "staff_dark":
			pen.line(21, -6, 21, -82, 2.6, WOOD_DARK if evil else WOOD)
			var orb := accent
			if gear == "staff_heal":
				orb = Color(0.65, 1.0, 0.7)
			elif gear == "staff_dark":
				orb = Color(0.6, 1.0, 0.35)
			pen.glow(21, -86, 12, orb, 0.75)
			pen.shaded(21, -86, 5, 5, orb)
			if gear == "staff_heal":
				pen.line(21, -90, 21, -82, 1.5, Color.WHITE)
				pen.line(17, -86, 25, -86, 1.5, Color.WHITE)
		"sceptre":
			pen.line(19, -34, 23, -62, 2.4, GOLD)
			pen.shaded(23, -64, 3.8, 3.8, Color(0.85, 0.2, 0.3))
		"mace":
			pen.line(19, -34, 22, -58, 2.6, WOOD_DARK)
			pen.shaded(22.5, -61, 5.5, 5.5, metal)
			for a in [0.0, 90.0, 180.0, 270.0]:
				var d := Vector2.from_angle(deg_to_rad(a))
				pen.line(22.5 + d.x * 5, -61 + d.y * 5, 22.5 + d.x * 8, -61 + d.y * 8, 1.6, metal.darkened(0.2))
		"club":
			pen.poly([Vector2(16, -36), Vector2(20, -38), Vector2(31, -72), Vector2(24, -75)], WOOD)
		"axe":
			pen.line(18, -30, 22, -64, 2.4, WOOD)
			pen.poly([Vector2(21, -64), Vector2(30, -70), Vector2(31, -56), Vector2(22, -57)], blade)
		"hammer":
			pen.line(18, -33, 21, -54, 2.2, WOOD)
			pen.poly([Vector2(15, -54), Vector2(27, -55), Vector2(27, -60), Vector2(15, -59)], metal.darkened(0.15))
		"pick":
			pen.line(18, -30, 21, -60, 2.2, WOOD)
			pen.arc(21, -50, 12, -150, -30, 2.4, metal)
		"sickle":
			pen.line(18, -34, 20, -44, 2.2, WOOD)
			pen.arc(25, -48, 6, 160, 380, 1.8, blade)
		"basket":
			pen.ell(-19, -30, 8, 5.5, WOOD.lightened(0.15))
			pen.line(-26, -32, -12, -32, 1.2, WOOD_DARK)
			pen.ell(-21, -34, 1.8, 1.8, Color(0.85, 0.15, 0.2))
			pen.ell(-17, -35, 1.8, 1.8, Color(0.85, 0.15, 0.2))
			pen.ell(-19, -36.5, 1.8, 1.8, Color(0.25, 0.6, 0.25))
		"orb":
			pen.glow(20, -42, 10, Color(0.65, 0.45, 1.0), 0.8)
			pen.shaded(20, -42, 4.5, 4.5, Color(0.7, 0.55, 1.0))
		"scroll":
			pen.line(14, -40, 25, -36, 4.2, Color(0.93, 0.87, 0.7))
			pen.ell(-11, -38, 6, 5, LEATHER)
		"sling":
			pen.line(18, -38, 24, -50, 1.0, LEATHER)
			pen.ell(24.5, -51, 2.2, 2.2, Color(0.55, 0.55, 0.55))
		"bomb":
			pen.shaded(22, -42, 5.5, 5.5, Color(0.15, 0.15, 0.18))
			pen.line(23, -47, 26, -52, 1.0, WOOD)
			pen.glow(26.5, -53, 4, Color(1.0, 0.7, 0.2), 0.95)


static func _bow(pen: Pen, metal: Color) -> void:
	pen.arc(-15, -46, 20, 110, 250, 2.4, WOOD)
	var top := Vector2(-15, -46) + Vector2.from_angle(deg_to_rad(250)) * 20
	var bottom := Vector2(-15, -46) + Vector2.from_angle(deg_to_rad(110)) * 20
	pen.line(top.x, top.y, bottom.x, bottom.y, 0.8, Color(0.9, 0.9, 0.85))
	pen.line(-19, -46, 8, -46, 1.2, metal.darkened(0.2))


static func _shield(pen: Pen, shape: String, body: Color, trim: Color, metal: Color, pattern: String) -> void:
	var face := body.darkened(0.08)
	match shape:
		"round":
			pen.ell(-18, -42, 10.5, 10.5, trim.darkened(0.25))
			pen.shaded(-18, -42, 9, 9, face)
			if not pattern.is_empty():
				pen.line(-18, -50, -18, -34, 2.6, trim)
			pen.shaded(-18, -42, 2.8, 2.8, metal)
		"kite":
			pen.poly([Vector2(-28, -54), Vector2(-9, -54), Vector2(-9, -40), Vector2(-18.5, -24), Vector2(-28, -40)], trim.darkened(0.25))
			pen.poly([Vector2(-26.5, -52.5), Vector2(-10.5, -52.5), Vector2(-10.5, -40.5), Vector2(-18.5, -27),
					Vector2(-26.5, -40.5)], face)
			pen.poly([Vector2(-20, -52.5), Vector2(-17, -52.5), Vector2(-17, -30), Vector2(-20, -30)], trim)
			if pattern in ["chevron", "quartered"]:
				pen.poly([Vector2(-26.5, -46), Vector2(-10.5, -46), Vector2(-10.5, -43), Vector2(-26.5, -43)], trim)
		"tower":
			pen.poly([Vector2(-30, -62), Vector2(-8, -62), Vector2(-8, -16), Vector2(-30, -16)], trim.darkened(0.25))
			pen.poly([Vector2(-28.5, -60.5), Vector2(-9.5, -60.5), Vector2(-9.5, -17.5), Vector2(-28.5, -17.5)], face)
			pen.poly([Vector2(-28.5, -44), Vector2(-9.5, -44), Vector2(-9.5, -40), Vector2(-28.5, -40)], trim)
			pen.shaded(-19, -42, 3, 3, metal)


## Reittier unter dem Reiter: Pferd mit Schabracke oder (Finsternis) Wolf
static func _mount(pen: Pen, spec: Dictionary) -> void:
	var body := Color.html(str(spec["body"]))
	var trim := Color.html(str(spec["trim"]))
	if str(spec["mount"]) == "wolf":
		_wolf(pen, Color(0.32, 0.31, 0.36), Color(1.0, 0.3, 0.2))
	else:
		var horse := Color(0.5, 0.33, 0.2)
		for leg: Vector4 in [Vector4(-20, -18, -22, 0), Vector4(-11, -18, -12, 0), Vector4(13, -18, 14, 0), Vector4(21, -18, 23, 0)]:
			pen.line(leg.x, leg.y, leg.z, leg.w, 4.2, horse.darkened(0.2))
			pen.ell(leg.z, leg.w - 1, 2.8, 1.8, Color(0.15, 0.12, 0.1))
		pen.line(-29, -30, -37, -14, 3.0, Color(0.2, 0.14, 0.1))
		pen.shaded(0, -27, 30, 12, horse)
		pen.poly([Vector2(20, -34), Vector2(28, -50), Vector2(35, -47), Vector2(30, -28)], horse)
		pen.shaded(37, -46, 8, 5, horse)
		pen.poly([Vector2(29, -50), Vector2(31, -57), Vector2(33, -50)], horse.darkened(0.2))
		pen.line(21, -36, 28, -52, 2.2, Color(0.2, 0.14, 0.1))
	# Schabracke in Reichs- bzw. Skin-Farben
	pen.poly([Vector2(-15, -36), Vector2(15, -36), Vector2(17, -15), Vector2(-17, -15)], body)
	pen.poly([Vector2(-17, -18), Vector2(17, -18), Vector2(17, -15), Vector2(-17, -15)], trim)


static func _wolf(pen: Pen, fur: Color, eye: Color) -> void:
	for leg: Vector4 in [Vector4(-18, -16, -20, 0), Vector4(-9, -16, -10, 0), Vector4(12, -16, 13, 0), Vector4(20, -16, 22, 0)]:
		pen.line(leg.x, leg.y, leg.z, leg.w, 4.0, fur.darkened(0.25))
	pen.poly([Vector2(-24, -28), Vector2(-38, -40), Vector2(-34, -26)], fur.darkened(0.1))
	pen.shaded(0, -24, 26, 11, fur)
	pen.shaded(-2, -18, 18, 5, fur.lightened(0.2))
	pen.shaded(24, -32, 10, 9, fur)
	pen.poly([Vector2(28, -34), Vector2(42, -28), Vector2(40, -24), Vector2(28, -26)], fur.lightened(0.1))
	pen.ell(41, -27, 2, 1.8, Color(0.08, 0.06, 0.06))
	pen.poly([Vector2(18, -38), Vector2(20, -48), Vector2(24, -39)], fur.darkened(0.15))
	pen.poly([Vector2(24, -39), Vector2(28, -48), Vector2(30, -37)], fur.darkened(0.15))
	pen.glow(27, -34, 3.5, eye, 0.9)
	pen.ell(27, -34, 1.6, 1.4, eye)


static func _spider(pen: Pen, color: Color) -> void:
	for i in 4:
		var y0 := -30.0 + i * 5.0
		var knee_y := -48.0 + i * 9.0
		for side: float in [-1.0, 1.0]:
			pen.line(side * 8, y0, side * (26 + i * 3), knee_y, 2.6, color.darkened(0.35))
			pen.line(side * (26 + i * 3), knee_y, side * (34 + i * 3), -1 - i * 1.5, 2.2, color.darkened(0.35))
	pen.shaded(0, -34, 17, 15, color)
	pen.shaded(0, -18, 10, 8, color.lightened(0.1))
	pen.ell(0, -38, 5, 7, color.lightened(0.35))
	for e: Vector2 in [Vector2(-3.5, -18), Vector2(3.5, -18), Vector2(-6, -15), Vector2(6, -15)]:
		pen.ell(e.x, e.y, 1.6, 1.6, Color(1.0, 0.2, 0.2))


static func _golem(pen: Pen, color: Color) -> void:
	var stone := color
	pen.poly([Vector2(-14, -30), Vector2(-4, -30), Vector2(-5, -1), Vector2(-15, -1)], stone.darkened(0.2))
	pen.poly([Vector2(4, -30), Vector2(14, -30), Vector2(15, -1), Vector2(5, -1)], stone.darkened(0.25))
	pen.poly([Vector2(-22, -66), Vector2(22, -66), Vector2(18, -26), Vector2(-18, -26)], stone)
	pen.poly([Vector2(-22, -66), Vector2(-4, -66), Vector2(-6, -26), Vector2(-18, -26)], stone.lightened(0.12))
	pen.poly([Vector2(-34, -64), Vector2(-23, -64), Vector2(-24, -28), Vector2(-35, -28)], stone.darkened(0.1))
	pen.poly([Vector2(23, -64), Vector2(34, -64), Vector2(35, -28), Vector2(24, -28)], stone.darkened(0.15))
	pen.poly([Vector2(-9, -80), Vector2(9, -80), Vector2(8, -66), Vector2(-8, -66)], stone.lightened(0.05))
	pen.line(-12, -58, -3, -44, 1.2, stone.darkened(0.5))
	pen.line(8, -52, 14, -38, 1.2, stone.darkened(0.5))
	pen.glow(-3.5, -73, 4, Color(1.0, 0.6, 0.2), 0.9)
	pen.glow(3.5, -73, 4, Color(1.0, 0.6, 0.2), 0.9)
	pen.glow(0, -48, 7, Color(1.0, 0.55, 0.15), 0.6)


static func _wyvern(pen: Pen, color: Color) -> void:
	var wing := color.darkened(0.15)
	pen.poly([Vector2(-6, -52), Vector2(-46, -84), Vector2(-40, -58), Vector2(-48, -44), Vector2(-14, -38)], wing)
	pen.poly([Vector2(6, -52), Vector2(46, -84), Vector2(40, -58), Vector2(48, -44), Vector2(14, -38)], wing)
	pen.line(-6, -52, -46, -84, 1.8, color.darkened(0.45))
	pen.line(6, -52, 46, -84, 1.8, color.darkened(0.45))
	pen.line(-8, -28, -30, -10, 4.0, color.darkened(0.1))
	pen.line(-30, -10, -40, -16, 3.0, color.darkened(0.1))
	pen.line(-6, -22, -8, -2, 3.2, color.darkened(0.3))
	pen.line(6, -22, 8, -2, 3.2, color.darkened(0.3))
	pen.shaded(0, -38, 13, 17, color)
	pen.shaded(0, -34, 7, 11, color.lightened(0.3))
	pen.line(0, -52, 6, -70, 6.0, color)
	pen.shaded(8, -73, 8, 6, color)
	pen.poly([Vector2(12, -76), Vector2(24, -72), Vector2(13, -69)], color.lightened(0.1))
	pen.poly([Vector2(3, -77), Vector2(-1, -86), Vector2(7, -79)], BONE)
	pen.ell(10, -75, 1.6, 1.4, Color(1.0, 0.85, 0.2))


## Beschworene Geister (Licht, Schatten, Wassergeist): durchscheinend, ohne Beine
static func _spirit(pen: Pen, spec: Dictionary) -> void:
	var color := Color.html(str(spec["body"]))
	var evil := str(spec["align"]) == "evil"
	pen.glow(0, -44, 42, color, 0.7)
	pen.poly([Vector2(-13, -58), Vector2(13, -58), Vector2(9, -26), Vector2(4, -10), Vector2(0, -4), Vector2(-4, -12),
			Vector2(-9, -26)], Color(color, 0.85))
	pen.poly([Vector2(-6, -56), Vector2(6, -56), Vector2(3, -24), Vector2(0, -12), Vector2(-3, -24)], Color(color.lightened(0.4), 0.8))
	pen.line(-13, -55, -21, -38, 4.5, Color(color, 0.8))
	pen.line(13, -55, 21, -40, 4.5, Color(color, 0.8))
	pen.shaded(0, -68, 9, 10, color.lightened(0.15))
	var eye := Color(1.0, 0.25, 0.4) if evil else Color(1.0, 1.0, 0.9)
	pen.glow(-3.5, -68, 3.5, eye, 1.0)
	pen.glow(3.5, -68, 3.5, eye, 1.0)
	_gear(pen, str(spec["gear"]), spec, Color.html(str(spec["metal"])), Color.html(str(spec["trim"])))


static func _wheel(pen: Pen, x: float, y: float, r: float) -> void:
	pen.ell(x, y, r, r, WOOD_DARK)
	pen.ell(x, y, r * 0.7, r * 0.7, WOOD)
	pen.line(x - r * 0.7, y, x + r * 0.7, y, 1.2, WOOD_DARK)
	pen.line(x, y - r * 0.7, x, y + r * 0.7, 1.2, WOOD_DARK)
	pen.ell(x, y, r * 0.22, r * 0.22, Color(0.35, 0.35, 0.38))


static func _ram(pen: Pen, spec: Dictionary) -> void:
	var body := Color.html(str(spec["body"]))
	var metal := Color.html(str(spec["metal"]))
	pen.poly([Vector2(-34, -16), Vector2(30, -16), Vector2(30, -12), Vector2(-34, -12)], WOOD_DARK)
	pen.line(-30, -26, 40, -26, 7.0, WOOD)
	pen.poly([Vector2(38, -32), Vector2(48, -30), Vector2(48, -22), Vector2(38, -20)], metal)
	pen.poly([Vector2(-36, -16), Vector2(-26, -50), Vector2(22, -50), Vector2(32, -16), Vector2(24, -16), Vector2(18, -42),
			Vector2(-20, -42), Vector2(-28, -16)], WOOD.darkened(0.1))
	pen.poly([Vector2(-28, -42), Vector2(-24, -54), Vector2(20, -54), Vector2(26, -42)], body)
	pen.poly([Vector2(-26, -48), Vector2(22, -48), Vector2(23, -46), Vector2(-27, -46)], Color.html(str(spec["trim"])))
	for x: float in [-26.0, -6.0, 14.0]:
		_wheel(pen, x, -8, 8)


static func _catapult(pen: Pen, spec: Dictionary) -> void:
	var body := Color.html(str(spec["body"]))
	pen.poly([Vector2(-32, -18), Vector2(30, -18), Vector2(30, -12), Vector2(-32, -12)], WOOD_DARK)
	pen.poly([Vector2(-6, -18), Vector2(0, -44), Vector2(6, -44), Vector2(10, -18)], WOOD)
	pen.line(-26, -22, 30, -72, 3.6, WOOD.lightened(0.1))
	pen.ell(32, -74, 7, 4, LEATHER)
	pen.shaded(32, -78, 4.5, 4.5, Color(0.55, 0.55, 0.56))
	pen.poly([Vector2(-30, -22), Vector2(-30, -42), Vector2(-18, -38), Vector2(-30, -34)], body)
	pen.line(-30, -18, -30, -44, 1.6, WOOD_DARK)
	_wheel(pen, -22, -8, 8)
	_wheel(pen, 20, -8, 8)


static func _caravan(pen: Pen, spec: Dictionary) -> void:
	var body := Color.html(str(spec["body"]))
	var trim := Color.html(str(spec["trim"]))
	pen.poly([Vector2(-34, -30), Vector2(26, -30), Vector2(26, -14), Vector2(-34, -14)], WOOD)
	pen.poly([Vector2(-32, -30), Vector2(-28, -54), Vector2(20, -54), Vector2(24, -30)], body.lightened(0.25))
	pen.poly([Vector2(-31, -40), Vector2(23, -40), Vector2(23.5, -37), Vector2(-31.5, -37)], trim)
	pen.poly([Vector2(26, -26), Vector2(44, -24), Vector2(44, -22), Vector2(26, -22)], WOOD_DARK)
	pen.poly([Vector2(-22, -30), Vector2(-22, -38), Vector2(-12, -38), Vector2(-12, -30)], Color(0.6, 0.45, 0.25))
	_wheel(pen, -22, -9, 9)
	_wheel(pen, 14, -9, 9)
