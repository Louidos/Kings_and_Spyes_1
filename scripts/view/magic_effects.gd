## MagicEffects
##
## Darstellung der Magie in der Spielwelt (reine Darstellung, verändert keinen
## Spielzustand):
## - Zauberblitz beim Wirken: GUT goldener Lichtring mit Strahlen, BÖSE dunkel-
##   violetter Fluchwirbel mit Rauch; Heilung mit aufsteigenden Funken,
##   Beschwörung als Lichtsäule (GUT) bzw. dunkles Tor (BÖSE)
## - Wettergebiete: Segensregen (Nieselregen über einer blau-goldenen Fläche),
##   Finsterer Nebel (treibende violette Schwaden)
## - Auren unter verzauberten Einheiten in der Farbe des Zaubers, Schimmer um
##   getarnte eigene Einheiten
## - Verpuffen beschworener Einheiten, wenn ihre Zeit abläuft
##
## Wie bei den Kampfeffekten zeichnet eine einzige Node (keine Node je Effekt).
## Diese Node liegt UNTER den Einheiten (Gebiete, Auren); Zauberblitze liegen auf
## einer zweiten Ebene ÜBER den Einheiten. Alles läuft mit GameClock.frame_delta
## (steht in der Pause) und wird nur im Sichtbereich und nur bei Bedarf gezeichnet.
class_name MagicEffects
extends Node2D

## Dauer eines Zauberblitzes und eines Verpuffens (Spielsekunden)
const BURST_TIME := 0.9
const PUFF_TIME := 0.7
## Höchstzahl gleichzeitiger Blitze/Verpuffungen (die ältesten fallen weg)
const MAX_BURSTS := 24
const MAX_PUFFS := 40
## Wettergebiete blenden so lange ein bzw. aus (Spielsekunden)
const ZONE_FADE := 1.2
## Rand um den Sichtbereich (Weltpixel)
const VIEW_MARGIN := 128.0
## Ebene der Zauberblitze: über Einheiten (5) und Kampfeffekten (25), unter dem UnitOverlay (30)
const TOP_Z := 26
## Höchstzahl Regenstriche und Nebelschwaden je Gebiet
const MAX_DROPS := 140
const FOG_BLOBS := 18

const LIGHT_CORE := Color(1.0, 0.98, 0.88)
const LIGHT_GOLD := Color(1.0, 0.84, 0.35)
const DARK_VIOLET := Color(0.45, 0.14, 0.66)
const DARK_SMOKE := Color(0.14, 0.03, 0.2)
const CURSE_RING := Color(0.78, 0.4, 1.0)
const CURSE_SPARK := Color(0.88, 0.62, 1.0)
const RAIN_DISC := Color(0.55, 0.78, 1.0)
const RAIN_DROP := Color(0.78, 0.9, 1.0)
const RAIN_GOLD := Color(1.0, 0.88, 0.5)
const FOG_COLOR := Color(0.5, 0.22, 0.68)


## Zauberblitz an einer Stelle
class Burst:
	var pos := Vector2.ZERO
	var radius := 64.0
	var t := 0.0
	var color := Color.WHITE
	## GUT (Licht) oder BÖSE (Fluch)
	var light := true
	## "combat", "healing", "stealth", "weather", "summon"
	var school := ""
	var angle := 0.0


## Verpuffen einer beschworenen Einheit
class Puff:
	var pos := Vector2.ZERO
	var t := 0.0
	var color := Color.WHITE
	var radius := 14.0


var game: Node

var _bursts: Array[Burst] = []
var _puffs: Array[Puff] = []
## Zonen-id -> Spielzeit, ab der das Gebiet gezeichnet wird (für das Einblenden)
var _zone_seen: Dictionary = {}
## Laufende Animationszeit (Spielsekunden, steht in der Pause)
var _anim := 0.0
var _view := Rect2()
var _zoom := 1.0
## Beim letzten Zeichnen war etwas zu sehen (dann einmal leer zeichnen)
var _drawn_any := false
var _top: Node2D


func setup(p_game: Node) -> void:
	game = p_game
	_top = Node2D.new()
	_top.name = "MagicBursts"
	_top.z_as_relative = false
	_top.z_index = TOP_Z
	add_child(_top)
	_top.draw.connect(_draw_top)
	var magic: MagicSystem = game.magic_system
	magic.spell_cast.connect(_on_spell_cast)
	magic.summon_expired.connect(_on_summon_expired)


## Anzahl laufender Effekte (für Tests)
func get_counts() -> Dictionary:
	return {"bursts": _bursts.size(), "puffs": _puffs.size(), "zones": game.magic_system.zones.size()}


# ---------------------------------------------------------------------------
# Signale
# ---------------------------------------------------------------------------

func _on_spell_cast(_k: Kingdom, spell_id: String, pos: Vector2, radius_px: float) -> void:
	var def := DataDB.get_spell(spell_id)
	var b := Burst.new()
	b.pos = pos
	b.radius = maxf(radius_px, 48.0)
	b.color = def.get("color", Color.WHITE)
	b.light = str(def.get("faction", "good")) != "evil"
	b.school = str(def.get("school", ""))
	b.angle = fposmod(pos.x * 0.013 + pos.y * 0.007, TAU)
	if _bursts.size() >= MAX_BURSTS:
		_bursts.remove_at(0)
	_bursts.append(b)


## Die Einheit wird gleich gelöscht: nur Ort und Farbe übernehmen, nie die Einheit behalten
func _on_summon_expired(u: Unit) -> void:
	if not is_instance_valid(u):
		return
	var p := Puff.new()
	p.pos = u.position
	p.color = u.type_def.get("color", u.kingdom.color)
	p.radius = u.get_radius()
	if _puffs.size() >= MAX_PUFFS:
		_puffs.remove_at(0)
	_puffs.append(p)


# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if game == null:
		return
	var dt: float = GameClock.frame_delta
	_anim += dt
	for i in range(_bursts.size() - 1, -1, -1):
		_bursts[i].t += dt
		if _bursts[i].t >= BURST_TIME:
			_bursts.remove_at(i)
	for i in range(_puffs.size() - 1, -1, -1):
		_puffs[i].t += dt
		if _puffs[i].t >= PUFF_TIME:
			_puffs.remove_at(i)
	var magic: MagicSystem = game.magic_system
	var active := not magic.zones.is_empty() or not magic.get_affected_units().is_empty()
	# In der Pause steht alles still: dann nicht ständig neu zeichnen
	if active and (dt > 0.0 or not _drawn_any):
		queue_redraw()
	elif not active and _drawn_any:
		queue_redraw()
	if not _bursts.is_empty() or not _puffs.is_empty():
		_top.queue_redraw()
	elif _top.get_meta("drawn", false):
		_top.queue_redraw()
	if magic.zones.is_empty() and not _zone_seen.is_empty():
		_zone_seen.clear()


# ---------------------------------------------------------------------------
# Zeichnen: Bodenebene (unter den Einheiten)
# ---------------------------------------------------------------------------

func _draw() -> void:
	_drawn_any = false
	if game == null:
		return
	_view = game.camera.get_view_rect().grow(VIEW_MARGIN)
	_zoom = maxf(game.camera.zoom.x, 0.01)
	var magic: MagicSystem = game.magic_system
	var now: float = GameClock.game_time
	for z in magic.zones:
		var pos: Vector2 = z["pos"]
		var radius := float(z["radius"])
		if not _view.intersects(Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)):
			continue
		var id := int(z["id"])
		if not _zone_seen.has(id):
			_zone_seen[id] = now
		var alpha := clampf((now - float(_zone_seen[id])) / ZONE_FADE, 0.0, 1.0)
		var until := float(z["until"])
		if until >= 0.0:
			alpha = minf(alpha, clampf((until - now) / ZONE_FADE, 0.0, 1.0))
		if alpha <= 0.0:
			continue
		match str(z["kind"]):
			"rain":
				_draw_rain(pos, radius, alpha, id)
			"fog":
				_draw_fog(pos, radius, alpha, id)
			_:
				draw_circle(pos, radius, Color(1, 1, 1, 0.08 * alpha))
		_drawn_any = true
	_draw_auras(magic)


## Segensregen: blau-goldene Fläche, Rand und fallende Tropfen
func _draw_rain(pos: Vector2, radius: float, alpha: float, seed_id: int) -> void:
	draw_circle(pos, radius, Color(RAIN_DISC, 0.13 * alpha))
	draw_circle(pos, radius * 0.6, Color(RAIN_GOLD, 0.05 * alpha))
	draw_arc(pos, radius, 0.0, TAU, 72, Color(RAIN_GOLD, 0.55 * alpha), maxf(2.0, 1.6 / _zoom), true)
	if _zoom < 0.25:
		return
	var count := mini(MAX_DROPS, int(radius * radius / 1400.0))
	var fall := Vector2(-0.18, 1.0)
	var length := 14.0
	var width := maxf(1.2, 1.0 / _zoom)
	for i in count:
		# Feste Zufallslage je Tropfen (aus Index und Gebiet), Fallhöhe aus der Zeit
		var h := _hash(i * 7919 + seed_id * 104729)
		var ang := h * TAU
		var dist := sqrt(_hash(i * 31 + seed_id * 17 + 5)) * radius * 0.96
		var base := pos + Vector2.from_angle(ang) * dist
		var phase := fposmod(_anim * 1.6 + _hash(i * 13 + 3), 1.0)
		var p := base + fall * (phase - 0.5) * 36.0
		if p.distance_squared_to(pos) > radius * radius:
			continue
		var c := RAIN_GOLD if i % 7 == 0 else RAIN_DROP
		draw_line(p, p + fall * length, Color(c, 0.55 * alpha * (1.0 - absf(phase - 0.5))), width, true)


## Finsterer Nebel: dunkle Grundfläche und langsam kreisende violette Schwaden
func _draw_fog(pos: Vector2, radius: float, alpha: float, seed_id: int) -> void:
	draw_circle(pos, radius, Color(DARK_SMOKE, 0.24 * alpha))
	draw_circle(pos, radius * 0.75, Color(DARK_VIOLET, 0.08 * alpha))
	for i in FOG_BLOBS:
		var h := _hash(i * 977 + seed_id * 31)
		var orbit := (0.25 + 0.6 * _hash(i * 53 + seed_id)) * radius
		var speed := (0.08 + 0.1 * h) * (1.0 if i % 2 == 0 else -1.0)
		var ang := h * TAU + _anim * speed
		var p := pos + Vector2.from_angle(ang) * orbit
		var blob := radius * (0.28 + 0.18 * _hash(i * 7 + 11)) * (0.9 + 0.1 * sin(_anim * 0.7 + i))
		# Schwaden am Rand dünner, damit das Gebiet weich ausläuft
		var edge := clampf(1.0 - (orbit + blob * 0.5 - radius * 0.7) / (radius * 0.6), 0.25, 1.0)
		var c := FOG_COLOR if i % 3 != 0 else DARK_VIOLET
		draw_circle(p, blob, Color(c, 0.17 * alpha * edge))
	draw_arc(pos, radius, 0.0, TAU, 72, Color(DARK_VIOLET, 0.45 * alpha), maxf(2.0, 1.6 / _zoom), true)


## Auren unter verzauberten Einheiten (je Zauber ein Ring) und Schimmer der Tarnung
func _draw_auras(magic: MagicSystem) -> void:
	if _zoom < 0.3:
		return
	var affected: Dictionary = magic.get_affected_units()
	if affected.is_empty():
		return
	var width := maxf(2.0, 1.4 / _zoom)
	var pulse := 0.75 + 0.25 * sin(_anim * 4.0)
	for uid in affected:
		var u: Variant = affected[uid]
		if not is_instance_valid(u) or u.inside != null or u.hp <= 0.0:
			continue
		var unit: Unit = u
		if not _view.has_point(unit.position) or not game.can_see(game.player, unit):
			continue
		var rad := unit.get_radius()
		var center := unit.position + Vector2(0.0, rad * 0.35)
		var ring := 0
		var seen := {}
		for e in unit.effects:
			var source := str(e.get("source", ""))
			if source.is_empty() or seen.has(source):
				continue
			seen[source] = true
			var c: Color = DataDB.get_effect_source_color(source)
			if str(e.get("key", "")) == "stealth":
				# Getarnt: gestrichelter, langsam drehender Schimmer
				var segs := 8
				for s in segs:
					var a0 := _anim * 1.2 + TAU * s / segs
					draw_arc(center, rad + 6.0 + ring * 3.0, a0, a0 + TAU / segs * 0.55, 6, Color(c, 0.7), width, true)
			else:
				draw_arc(center, rad + 4.0 + ring * 3.0, 0.0, TAU, 28, Color(c, 0.8 * pulse), width, true)
			ring += 1
		if ring > 0:
			_drawn_any = true


# ---------------------------------------------------------------------------
# Zeichnen: obere Ebene (über den Einheiten)
# ---------------------------------------------------------------------------

func _draw_top() -> void:
	var drawn := false
	if game != null:
		_view = game.camera.get_view_rect().grow(VIEW_MARGIN)
		_zoom = maxf(game.camera.zoom.x, 0.01)
		for b in _bursts:
			if _view.grow(b.radius).has_point(b.pos):
				_draw_burst(b)
				drawn = true
		for p in _puffs:
			if _view.has_point(p.pos):
				_draw_puff(p)
				drawn = true
	_top.set_meta("drawn", drawn)


func _draw_burst(b: Burst) -> void:
	var k := b.t / BURST_TIME
	var fade := 1.0 - k
	var width := maxf(3.0, 2.5 / _zoom)
	match b.school:
		"summon":
			_draw_summon(b, k, fade)
			return
		"healing":
			_draw_heal(b, k, fade)
	if b.light:
		# Licht: weisser Blitz, wachsender goldener Ring, Strahlen nach aussen
		var r := b.radius * (0.35 + 0.65 * _ease_out(k))
		_top.draw_circle(b.pos, r, Color(LIGHT_CORE, 0.42 * fade * fade))
		_top.draw_circle(b.pos, r * 0.5, Color(LIGHT_GOLD, 0.25 * fade))
		# Leuchtender Ring: breiter, weicher Schein unter einer hellen Linie
		_top.draw_arc(b.pos, r, 0.0, TAU, 64, Color(LIGHT_GOLD, 0.25 * fade), width * 5.0, true)
		_top.draw_arc(b.pos, r, 0.0, TAU, 64, Color(LIGHT_GOLD, 0.6 * fade), width * 2.4, true)
		_top.draw_arc(b.pos, r, 0.0, TAU, 64, Color(LIGHT_CORE, fade), width, true)
		var rays := 12
		for i in rays:
			var a := b.angle + TAU * i / rays + k * 0.6
			var d := Vector2.from_angle(a)
			var r0 := b.radius * (0.1 + 0.5 * k)
			var r1 := r0 + b.radius * 0.4
			_top.draw_line(b.pos + d * r0, b.pos + d * r1, Color(LIGHT_GOLD, 0.5 * fade), width * 2.6, true)
			_top.draw_line(b.pos + d * r0, b.pos + d * r1, Color(LIGHT_CORE, 0.9 * fade), width, true)
	else:
		# Fluch: Ring zieht sich zusammen und springt dann auf, Rauchwirbel, Funken
		var r := b.radius * (1.0 - 0.35 * sin(k / 0.4 * PI * 0.5) if k < 0.4 else 0.65 + 0.45 * (k - 0.4) / 0.6)
		_top.draw_circle(b.pos, r, Color(DARK_SMOKE, 0.48 * fade))
		var blobs := 10
		for i in blobs:
			var a := b.angle + TAU * i / blobs - k * 2.4
			var p := b.pos + Vector2.from_angle(a) * r * (0.45 + 0.4 * k)
			_top.draw_circle(p, b.radius * (0.17 + 0.1 * k), Color(DARK_VIOLET, 0.55 * fade))
			_top.draw_circle(p, b.radius * (0.08 + 0.05 * k), Color(DARK_SMOKE, 0.5 * fade))
		_top.draw_arc(b.pos, r, 0.0, TAU, 64, Color(CURSE_RING, 0.3 * fade), width * 4.0, true)
		_top.draw_arc(b.pos, r, 0.0, TAU, 64, Color(CURSE_RING, fade), width * 1.4, true)
		var sparks := 9
		for i in sparks:
			var a := b.angle * 1.7 + TAU * i / sparks + k * 1.3
			var p := b.pos + Vector2.from_angle(a) * b.radius * (0.3 + 0.75 * k)
			_top.draw_circle(p, maxf(4.0, 3.0 / _zoom), Color(CURSE_SPARK, fade))


## Heilung: kleine Kreuze steigen auf
func _draw_heal(b: Burst, k: float, fade: float) -> void:
	var count := 9
	var size := maxf(5.0, 4.0 / _zoom)
	var width := maxf(2.0, 1.6 / _zoom)
	var c := Color(LIGHT_CORE, fade) if b.light else Color(b.color.lightened(0.35), fade)
	for i in count:
		var h := _hash(i * 37 + int(b.angle * 1000.0))
		var p := b.pos + Vector2.from_angle(h * TAU) * b.radius * (0.2 + 0.7 * _hash(i * 11 + 1))
		p.y -= k * 40.0
		_top.draw_line(p - Vector2(size, 0), p + Vector2(size, 0), c, width, true)
		_top.draw_line(p - Vector2(0, size), p + Vector2(0, size), c, width, true)


## Beschwörung: Lichtsäule (GUT) bzw. dunkles Tor (BÖSE)
func _draw_summon(b: Burst, k: float, fade: float) -> void:
	var w := 96.0
	if b.light:
		var h := 280.0 * _ease_out(minf(k * 1.6, 1.0))
		var rect := Rect2(b.pos + Vector2(-w * 0.5, -h), Vector2(w, h))
		_top.draw_rect(rect, Color(LIGHT_GOLD, 0.22 * fade), true)
		_top.draw_rect(rect.grow_individual(-w * 0.3, 0, -w * 0.3, 0), Color(LIGHT_CORE, 0.4 * fade), true)
		_top.draw_circle(b.pos, w * 0.9, Color(LIGHT_GOLD, 0.3 * fade))
		_top.draw_arc(b.pos, w * (0.6 + 0.6 * k), 0.0, TAU, 48, Color(b.color, 0.9 * fade), maxf(3.0, 2.0 / _zoom), true)
	else:
		# Flaches Tor: zwei ineinander drehende Ellipsen aus Rauch
		var open := _ease_out(minf(k * 1.8, 1.0))
		_top.draw_set_transform(b.pos, 0.0, Vector2(1.0, 0.45))
		_top.draw_circle(Vector2.ZERO, w * open, Color(DARK_SMOKE, 0.7 * fade))
		for i in 6:
			var a := TAU * i / 6.0 + k * 5.0
			_top.draw_circle(Vector2.from_angle(a) * w * 0.7 * open, w * 0.25, Color(DARK_VIOLET, 0.5 * fade))
		_top.draw_arc(Vector2.ZERO, w * open, 0.0, TAU, 48, Color(CURSE_RING, 0.35 * fade), maxf(10.0, 6.0 / _zoom), true)
		_top.draw_arc(Vector2.ZERO, w * open, 0.0, TAU, 48, Color(CURSE_RING, fade), maxf(3.0, 2.0 / _zoom), true)
		_top.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_puff(p: Puff) -> void:
	var k := p.t / PUFF_TIME
	var fade := 1.0 - k
	_top.draw_circle(p.pos, p.radius * (1.0 + k * 1.2), Color(p.color, 0.4 * fade))
	for i in 5:
		var a := TAU * i / 5.0 + k
		var q := p.pos + Vector2.from_angle(a) * p.radius * (0.8 + 1.4 * k) - Vector2(0, k * 18.0)
		_top.draw_circle(q, maxf(2.5, 2.0 / _zoom), Color(p.color.lightened(0.4), fade))


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

## Feste Pseudozufallszahl 0..1 aus einer ganzen Zahl (gleich in jedem Bild)
func _hash(n: int) -> float:
	var x := (n * 374761393 + 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float(x % 10007) / 10007.0


func _ease_out(k: float) -> float:
	return 1.0 - (1.0 - k) * (1.0 - k)
