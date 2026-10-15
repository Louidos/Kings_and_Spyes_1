## CombatEffects
##
## Kampfeffekte in der Spielwelt (reine Darstellung, verändert keinen
## Spielzustand): Geschosse, Treffer, Gefallene, Befehlsmarkierungen, die
## Sammelpunkt-Fahne ausgewählter Gebäude und (ab Phase 7) die Ruinen gefallener
## Reiche (Zustand in VictorySystem.ruins; blockieren nichts).
##
## Eine einzige Node zeichnet alle Effekte (keine Node je Effekt): das spart
## Zeichenaufrufe auch bei grossen Schlachten. Nur Gefallene und die
## gestrichelte Sammelpunkt-Linie liegen auf einer zweiten Zeichenebene
## UNTER den Einheiten (Bodenebene), damit sie lebende Einheiten nicht verdecken.
##
## Zeit: Geschosse, Treffer, Gefallene und die Fahne laufen mit
## GameClock.frame_delta (Pause friert sie ein, Tempo beschleunigt sie).
## Befehlsmarkierungen stehen in der Pause ebenfalls still, laufen sonst aber
## in Echtzeit: sie sind die Rückmeldung auf einen Klick und sollen bei 3x
## Tempo nicht dreimal so schnell verschwinden.
## Neu gezeichnet wird nur, solange Effekte existieren oder eine Fahne sichtbar ist.
class_name CombatEffects
extends Node2D

## Höchstzahl gleichzeitiger Effekte (die ältesten fallen weg)
const MAX_PROJECTILES := 300
const MAX_SPARKS := 200
const MAX_CORPSES := 200
const MAX_MARKERS := 24
## Dauer eines Treffers und einer Befehlsmarkierung (Sekunden)
const SPARK_TIME := 0.25
const MARKER_TIME := 0.6
## Gezeichnet wird nur im Sichtbereich plus dieser Rand (Weltpixel)
const VIEW_MARGIN := 64.0
## Bodenebene: über Strassen (1) und Gebietsgrenze (2), unter Gebäuden und Einheiten (5)
const GROUND_Z := 4
## Pfeile fliegen im Bogen: Scheitelhöhe = Flugweite × Faktor (höchstens ARC_MAX)
const ARC_FACTOR := 0.15
const ARC_MAX := 48.0
const ARROW_TEXTURE := "res://assets/sprites/effects/arrow.png"
const BOLT_TEXTURE := "res://assets/sprites/effects/bolt.png"
const STONE_TEXTURE := "res://assets/sprites/effects/stone.png"
## Steine (Katapulte, Phase 9) fliegen in einem hohen Bogen
const STONE_ARC_FACTOR := 0.35
const STONE_ARC_MAX := 140.0
## Art eines Geschosses
const KIND_ARROW := 0
const KIND_BOLT := 1
const KIND_STONE := 2
const RUIN_TEXTURE := "res://assets/sprites/effects/ruin.png"
const RUIN_FRAME := Color(0.42, 0.36, 0.3)
const RUIN_FILL := Color(0.3, 0.27, 0.24, 0.55)
## Ruinen verblassen in diesem letzten Anteil ihrer Lebensdauer
const RUIN_FADE_SHARE := 0.1

const MARKER_COLORS := {
	"move": Color(0.35, 0.95, 0.4),
	"attack_move": Color(1.0, 0.6, 0.15),
	"attack": Color(1.0, 0.25, 0.2),
	"rally": Color(1.0, 0.88, 0.25),
	"patrol": Color(0.4, 0.75, 1.0),
}
const SPARK_UNIT_COLOR := Color(1.0, 0.22, 0.15)
const SPARK_BUILDING_COLOR := Color(1.0, 0.6, 0.15)
const ARROW_SHAFT := Color(0.45, 0.29, 0.14)
const ARROW_TIP := Color(0.88, 0.88, 0.82)
const ARROW_FLETCH := Color(0.95, 0.93, 0.85)
const BOLT_GLOW := Color(0.68, 0.34, 1.0)
const BOLT_CORE := Color(0.28, 0.08, 0.42)
const BOLT_SHINE := Color(0.82, 0.62, 1.0)


## Ein fliegendes Geschoss (Weltpixel, Spielsekunden)
class Projectile:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	## 0 Pfeil, 1 Bolzen, 2 Stein
	var kind := 0
	var t := 0.0
	var dur := 0.1
	## Scheitelhöhe des Bogens (0 = gerade)
	var arc := 0.0
	## Treffer beim Einschlag zeigen: 0 = keiner, 1 = Einheit, 2 = Gebäude
	var hit := 0
	var hit_size := 10.0


## Aufblitzen eines Treffers
class Spark:
	var pos := Vector2.ZERO
	var t := 0.0
	var building := false
	var size := 10.0
	## Drehung der Funkenstrahlen (damit nicht alle gleich aussehen)
	var angle := 0.0


## Gefallene Einheit, die langsam verblasst
class Corpse:
	var pos := Vector2.ZERO
	var t := 0.0
	var dur := 4.0
	var color := Color.GRAY
	var radius := 12.0
	var rot := 0.0


## Kurze Markierung nach einem Befehl
class Marker:
	var pos := Vector2.ZERO
	var t := 0.0
	var color := Color.WHITE
	## Angriffsbefehle zeigen ein Kreuz statt eines Punkts
	var cross := false


var game: Node

var _projectiles: Array[Projectile] = []
var _sparks: Array[Spark] = []
var _corpses: Array[Corpse] = []
var _markers: Array[Marker] = []
## Ausgewählte eigene Gebäude, die einen Sammelpunkt haben können
var _rally_buildings: Array = []
## Gebäude, deren Fahne gerade gezeichnet wird (jeden Frame geprüft)
var _flags: Array = []
var _flag_points := PackedVector2Array()
## Zuletzt abgefeuertes Geschoss: der gleich folgende Treffer (Signal attacked)
## wird erst beim Einschlag gezeigt statt beim Abschuss.
var _last_fired: Projectile
var _last_fired_frame := -1
var _corpse_seconds := 4.0
## Animationszeit der Fahne (Spielsekunden, steht in der Pause)
var _wave_time := 0.0
var _view := Rect2()
var _zoom := 1.0
## Etwas hat sich geändert -> neu zeichnen
var _dirty := false
## Beim letzten Zeichnen war etwas zu sehen (dann einmal leer zeichnen)
var _drawn_any := false
var _rng := RandomNumberGenerator.new()
var _arrow_tex: Texture2D
var _bolt_tex: Texture2D
var _stone_tex: Texture2D
var _ruin_tex: Texture2D
## Ruinen sind zu sehen (dann wird die Bodenebene bei Kamerabewegung neu gezeichnet)
var _has_ruins := false
## Bodenebene unter den Einheiten (Gefallene, Sammelpunkt-Linie)
var _ground: Node2D


func setup(p_game: Node) -> void:
	game = p_game
	_corpse_seconds = maxf(float(DataDB.cmb("corpse_seconds", 4.0)), 0.1)
	_arrow_tex = Assets.texture(ARROW_TEXTURE)
	_bolt_tex = Assets.texture(BOLT_TEXTURE)
	_stone_tex = Assets.texture(STONE_TEXTURE)
	_ruin_tex = Assets.texture(RUIN_TEXTURE)
	_rng.seed = 7341
	_ground = Node2D.new()
	_ground.name = "GroundEffects"
	_ground.z_as_relative = false
	_ground.z_index = GROUND_Z
	add_child(_ground)
	_ground.draw.connect(_draw_ground)
	var combat: Node = game.combat_system
	combat.projectile_fired.connect(_on_projectile_fired)
	combat.attacked.connect(_on_attacked)
	combat.unit_died.connect(_on_unit_died)
	var sel: Node = game.selection
	if sel.has_signal("command_issued"):
		sel.connect("command_issued", _on_command_issued)
	sel.connect("selection_changed", _on_selection_changed)
	var victory: Variant = game.get("victory_system")
	if victory is Object and (victory as Object).has_signal("ruins_changed"):
		(victory as Object).connect("ruins_changed", _on_ruins_changed)


func _on_ruins_changed() -> void:
	var victory: Variant = game.get("victory_system")
	_has_ruins = victory is Object and not ((victory as Object).get("ruins") as Array).is_empty()
	_dirty = true


## Anzahl laufender Effekte (für Tests und die Debug-Anzeige)
func get_counts() -> Dictionary:
	return {"projectiles": _projectiles.size(), "sparks": _sparks.size(), "corpses": _corpses.size(),
			"markers": _markers.size(), "flags": _flags.size()}


# ---------------------------------------------------------------------------
# Signale
# ---------------------------------------------------------------------------

func _on_projectile_fired(from_pos: Vector2, to_pos: Vector2, kind: String, flight_time: float) -> void:
	var p := Projectile.new()
	p.from = from_pos
	p.to = to_pos
	p.kind = KIND_BOLT if kind == "bolt" else (KIND_STONE if kind == "stone" else KIND_ARROW)
	p.dur = maxf(flight_time, 0.05)
	if p.kind == KIND_ARROW:
		p.arc = minf(from_pos.distance_to(to_pos) * ARC_FACTOR, ARC_MAX)
	elif p.kind == KIND_STONE:
		p.arc = minf(from_pos.distance_to(to_pos) * STONE_ARC_FACTOR, STONE_ARC_MAX)
		p.dur = maxf(p.dur * 1.6, 0.3)
	if _projectiles.size() >= MAX_PROJECTILES:
		_projectiles.remove_at(0)
	_projectiles.append(p)
	_last_fired = p
	_last_fired_frame = Engine.get_process_frames()
	_dirty = true


## Parameter ohne Objekttyp: ein Opfer kann schon freigegeben sein.
func _on_attacked(attacker: Variant, victim: Variant, _damage: float) -> void:
	var proj := _last_fired
	_last_fired = null
	if not is_instance_valid(victim):
		return
	var on_building := not (victim is Unit)
	var pos: Vector2 = victim.position
	var radius: float = victim.get_radius()
	var size := clampf(radius * 0.8, 8.0, 28.0)
	# Fernkampf: Treffer zeigen, wenn das Geschoss ankommt
	if proj != null and _last_fired_frame == Engine.get_process_frames() and proj.to == pos \
			and is_instance_valid(attacker) and attacker is Node2D and (attacker as Node2D).position == proj.from:
		proj.hit = 2 if on_building else 1
		proj.hit_size = size
		return
	_add_spark(pos, on_building, size)


func _on_unit_died(unit: Variant, _killer: Variant) -> void:
	if not is_instance_valid(unit) or not (unit is Unit):
		return
	var u: Unit = unit
	if u.inside != null:
		return
	var c := Corpse.new()
	c.pos = u.position
	c.dur = _corpse_seconds
	var base: Color = u.type_def.get("color", u.kingdom.color if u.kingdom != null else Color.GRAY)
	c.color = base.darkened(0.45)
	c.radius = u.get_radius()
	c.rot = _rng.randf_range(-0.35, 0.35)
	if _corpses.size() >= MAX_CORPSES:
		_corpses.remove_at(0)
	_corpses.append(c)
	_dirty = true


func _on_command_issued(pos: Vector2, kind: String) -> void:
	var m := Marker.new()
	m.pos = pos
	m.color = MARKER_COLORS.get(kind, Color.WHITE)
	m.cross = kind == "attack" or kind == "attack_move"
	if _markers.size() >= MAX_MARKERS:
		_markers.remove_at(0)
	_markers.append(m)
	_dirty = true


## Merkt sich ausgewählte eigene Gebäude; ob sie einen Sammelpunkt haben,
## wird jeden Frame geprüft (set_rally/clear_rally melden sich nicht).
func _on_selection_changed(objs: Array) -> void:
	_rally_buildings.clear()
	var player: Kingdom = game.player
	for o in objs:
		if is_instance_valid(o) and o is Building and o.kingdom == player:
			_rally_buildings.append(o)
	_dirty = true


func _add_spark(pos: Vector2, on_building: bool, size: float) -> void:
	# Nur sichtbare Treffer: ausserhalb des Bildes würde man ihn nie sehen
	if game == null or not game.camera.get_view_rect().grow(VIEW_MARGIN).has_point(pos):
		return
	var s := Spark.new()
	s.pos = pos + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-6.0, 2.0))
	s.building = on_building
	s.size = size
	s.angle = _rng.randf() * TAU
	if _sparks.size() >= MAX_SPARKS:
		_sparks.remove_at(0)
	_sparks.append(s)
	_dirty = true


# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if game == null or game.world == null:
		return
	var gd := GameClock.frame_delta
	if gd > 0.0:
		_advance(gd)
	if gd > 0.0 and not _markers.is_empty():
		_advance_markers(delta)
	_update_flags(gd > 0.0)
	var has_any := _has_ruins or not (_projectiles.is_empty() and _sparks.is_empty() and _corpses.is_empty()
			and _markers.is_empty() and _flags.is_empty())
	var view: Rect2 = game.camera.get_view_rect().grow(VIEW_MARGIN)
	var zoom: float = maxf(game.camera.zoom.x, 0.02)
	# Kamera bewegt (auch in der Pause): Ausschnitt neu zeichnen
	var view_changed := view != _view or zoom != _zoom
	_view = view
	_zoom = zoom
	if _dirty or (has_any and view_changed) or (_drawn_any and not has_any):
		_dirty = false
		_drawn_any = has_any
		queue_redraw()
		_ground.queue_redraw()


## Spielzeit-Effekte weiterlaufen lassen (steht in der Pause)
func _advance(gd: float) -> void:
	_wave_time += gd
	if not _projectiles.is_empty():
		_dirty = true
		var landed := 0
		for p in _projectiles:
			p.t += gd
			if p.t >= p.dur:
				landed += 1
		if landed > 0:
			var keep: Array[Projectile] = []
			for p in _projectiles:
				if p.t < p.dur:
					keep.append(p)
				elif p.hit != 0:
					# Steine schlagen doppelt so gross ein
					_add_spark(p.to, p.hit == 2, p.hit_size * (2.0 if p.kind == KIND_STONE else 1.0))
			_projectiles = keep
	if not _sparks.is_empty():
		_dirty = true
		for s in _sparks:
			s.t += gd
		while not _sparks.is_empty() and _sparks[0].t >= SPARK_TIME:
			_sparks.remove_at(0)  # gleiche Dauer: die ältesten stehen vorne
	if not _corpses.is_empty():
		_dirty = true
		for c in _corpses:
			c.t += gd
		while not _corpses.is_empty() and _corpses[0].t >= _corpses[0].dur:
			_corpses.remove_at(0)


func _advance_markers(delta: float) -> void:
	_dirty = true
	for m in _markers:
		m.t += delta
	while not _markers.is_empty() and _markers[0].t >= MARKER_TIME:
		_markers.remove_at(0)


## Welche ausgewählten Gebäude zeigen gerade eine Fahne? Neu zeichnen, wenn
## die Fahne weht (Spiel läuft) oder ein Sammelpunkt versetzt/gelöscht wurde.
func _update_flags(game_running: bool) -> void:
	if _rally_buildings.is_empty() and _flags.is_empty():
		return
	var flags: Array = []
	var points := PackedVector2Array()
	for b in _rally_buildings:
		if is_instance_valid(b) and b.has_rally and b.constructed:
			flags.append(b)
			points.append(b.rally_point)
	if points != _flag_points or (game_running and not flags.is_empty()):
		_dirty = true
	_flags = flags
	_flag_points = points


# ---------------------------------------------------------------------------
# Zeichnen
# ---------------------------------------------------------------------------

func _draw() -> void:
	if game == null or game.world == null:
		return
	_draw_projectiles()
	_draw_sparks()
	_draw_markers()
	_draw_flags()


## Bodenebene: Ruinen, Gefallene und gestrichelte Linie zum Sammelpunkt
func _draw_ground() -> void:
	if game == null or game.world == null:
		return
	if _has_ruins:
		_draw_ruins()
	for c in _corpses:
		if not _view.has_point(c.pos):
			continue
		var s := c.t / c.dur
		# Erst gut sichtbar, in der zweiten Hälfte verblassen
		var alpha := clampf((1.0 - s) * 2.0, 0.0, 1.0)
		_ground.draw_set_transform(c.pos + Vector2(0, c.radius * 0.35), c.rot, Vector2(1.0, 0.45))
		_ground.draw_circle(Vector2.ZERO, c.radius * 1.15, Color(0, 0, 0, 0.3 * alpha))
		_ground.draw_circle(Vector2.ZERO, c.radius * 0.95, Color(c.color, 0.85 * alpha))
		_ground.draw_arc(Vector2.ZERO, c.radius * 0.95, 0.0, TAU, 20, Color(c.color.darkened(0.5), 0.9 * alpha), 2.0)
	_ground.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var k := _ui_scale()
	for b in _flags:
		if not is_instance_valid(b):
			continue
		var from: Vector2 = b.get_center()
		var to: Vector2 = b.rally_point
		if not _view.intersects(Rect2(from, Vector2.ZERO).expand(to).grow(1.0)):
			continue
		var kc: Color = b.kingdom.color
		_ground.draw_dashed_line(from, to, Color(0, 0, 0, 0.45), 4.0 * k, 12.0 * k)
		_ground.draw_dashed_line(from, to, Color(kc.lightened(0.35), 0.9), 2.0 * k, 12.0 * k)


## Ruinen im Sichtbereich: Grafik auf die Grundfläche gestreckt, sonst ein Platzhalter
## (graubrauner Rahmen mit Bruchlinien, "Ruine" ab Zoom 0,5); verblassen am Ende
func _draw_ruins() -> void:
	var victory: Object = game.get("victory_system")
	var ts := float(game.world.tile_size)
	var now := GameClock.game_time
	var life := maxf(float(DataDB.ai("defeat.ruin_seconds", 1800)), 1.0)
	for ruin in victory.get("ruins"):
		var cell: Vector2i = ruin["cell"]
		var ruin_size: Vector2i = ruin["size"]
		var rect := Rect2(Vector2(cell) * ts, Vector2(ruin_size) * ts)
		if not _view.intersects(rect):
			continue
		var left := float(ruin["until"]) - now
		var alpha := clampf(left / (life * RUIN_FADE_SHARE), 0.0, 1.0)
		if _ruin_tex != null:
			_ground.draw_texture_rect(_ruin_tex, rect, false, Color(1, 1, 1, alpha))
			continue
		var inner := rect.grow(-ts * 0.15)
		_ground.draw_rect(inner, Color(RUIN_FILL, RUIN_FILL.a * alpha), true)
		_ground.draw_rect(inner, Color(RUIN_FRAME, alpha), false, 4.0)
		var c := inner.get_center()
		var crack := Color(RUIN_FRAME.darkened(0.3), alpha)
		_ground.draw_line(inner.position + Vector2(inner.size.x * 0.2, 0), c + Vector2(-ts * 0.2, ts * 0.1), crack, 3.0)
		_ground.draw_line(c + Vector2(-ts * 0.2, ts * 0.1), Vector2(inner.end.x - inner.size.x * 0.3, inner.end.y), crack, 3.0)
		_ground.draw_line(Vector2(inner.end.x, inner.position.y + inner.size.y * 0.35), c + Vector2(ts * 0.25, -ts * 0.05), crack, 3.0)
		if _zoom >= 0.5:
			_ground.draw_string(ThemeDB.fallback_font, c + Vector2(-ts * 0.45, ts * 0.12), "Ruine", HORIZONTAL_ALIGNMENT_CENTER,
					ts * 0.9, 18, Color(0.92, 0.88, 0.8, alpha))


func _draw_projectiles() -> void:
	var k := _fx_scale()
	# Erst alle Schatten am Boden (unter den Geschossen), dann die Geschosse.
	# Gezeichnet wird in lokalen Koordinaten (draw_set_transform): Dreiecke an
	# grossen Weltkoordinaten scheitern sonst an der Rechengenauigkeit.
	for p in _projectiles:
		if p.arc <= 0.0:
			continue
		var s := clampf(p.t / p.dur, 0.0, 1.0)
		var ground := p.from.lerp(p.to, s)
		var lift := p.arc * 4.0 * s * (1.0 - s)
		if lift < 3.0 or not _view.has_point(ground):
			continue
		var gdir := (p.to - p.from).normalized()
		# Schatten wird blasser, je höher der Pfeil fliegt
		var a := 0.28 - 0.14 * clampf(lift / ARC_MAX, 0.0, 1.0)
		draw_line(ground - gdir * 14.0 * k, ground, Color(0, 0, 0, a), 2.5 * k)
	for p in _projectiles:
		var s := clampf(p.t / p.dur, 0.0, 1.0)
		var ground := p.from.lerp(p.to, s)
		if not _view.has_point(ground):
			continue
		var lift := p.arc * 4.0 * s * (1.0 - s)
		var pos := ground - Vector2(0, lift)
		# Flugrichtung = Ableitung der Bahn (im Bogen kippt die Spitze nach unten)
		var vel := (p.to - p.from) - Vector2(0, p.arc * 4.0 * (1.0 - 2.0 * s))
		var angle := vel.angle() if vel.length_squared() > 0.01 else 0.0
		draw_set_transform(pos, angle, Vector2(k, k))
		if p.kind == KIND_STONE:
			if _stone_tex != null:
				draw_texture_rect(_stone_tex, Rect2(-8.0, -8.0, 16.0, 16.0), false)
			else:
				draw_circle(Vector2.ZERO, 8.5, Color(0.15, 0.13, 0.12))
				draw_circle(Vector2.ZERO, 7.0, Color(0.55, 0.53, 0.5))
			continue
		var tex := _bolt_tex if p.kind == KIND_BOLT else _arrow_tex
		if tex != null:
			# Grafik zeigt nach rechts, die Spitze liegt am rechten Rand
			var ts := tex.get_size()
			draw_texture(tex, Vector2(-ts.x, -ts.y * 0.5))
		elif p.kind == KIND_BOLT:
			_draw_bolt()
		else:
			_draw_arrow()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Pfeil (lokal, Spitze bei 0, zeigt nach rechts): brauner Schaft mit dunklem
## Rand (auf hellem Boden sichtbar), helle Spitze, Federn
func _draw_arrow() -> void:
	draw_line(Vector2(-23.0, 0), Vector2(-4.0, 0), Color(0, 0, 0, 0.35), 3.5)
	draw_line(Vector2(-22.0, 0), Vector2(-4.0, 0), ARROW_SHAFT, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(2.5, 0), Vector2(-6.5, 3.6), Vector2(-6.5, -3.6)]),
			Color(0, 0, 0, 0.45))
	draw_colored_polygon(PackedVector2Array([Vector2(1.5, 0), Vector2(-6.0, 2.8), Vector2(-6.0, -2.8)]),
			ARROW_TIP)
	draw_line(Vector2(-17.0, 0), Vector2(-22.5, -3.8), ARROW_FLETCH, 1.6)
	draw_line(Vector2(-17.0, 0), Vector2(-22.5, 3.8), ARROW_FLETCH, 1.6)


## Magisches Geschoss (lokal): violetter Schein, Schweif, dunkler Kern, heller Kopf
func _draw_bolt() -> void:
	draw_circle(Vector2(-5.0, 0), 11.0, Color(BOLT_GLOW, 0.22))
	draw_circle(Vector2(-3.0, 0), 6.5, Color(BOLT_GLOW, 0.45))
	draw_line(Vector2(-30.0, 0), Vector2(-10.0, 0), Color(BOLT_SHINE, 0.3), 3.0)
	draw_line(Vector2(-16.0, 0), Vector2(0, 0), BOLT_CORE, 5.0)
	draw_line(Vector2(-14.0, 0), Vector2(-1.0, 0), BOLT_SHINE, 2.0)
	draw_circle(Vector2.ZERO, 3.0, Color(0.95, 0.85, 1.0))


func _draw_sparks() -> void:
	var k := _fx_scale()
	for sp in _sparks:
		if not _view.has_point(sp.pos):
			continue
		var s := clampf(sp.t / SPARK_TIME, 0.0, 1.0)
		var base := SPARK_BUILDING_COLOR if sp.building else SPARK_UNIT_COLOR
		var alpha := 1.0 - s
		var size := sp.size * k
		var r := size * (0.45 + 0.9 * s)
		if s < 0.5:
			# Heller Kern im ersten Moment
			draw_circle(sp.pos, size * 0.45 * (1.0 - s * 2.0), Color(1.0, 0.92, 0.7, 0.9 * alpha))
		draw_arc(sp.pos, r, 0.0, TAU, 18, Color(0, 0, 0, 0.3 * alpha), (2.5 + 2.5 * alpha) * k)
		draw_arc(sp.pos, r, 0.0, TAU, 18, Color(base, alpha), (1.0 + 2.5 * alpha) * k)
		for i in 4:
			var d := Vector2.RIGHT.rotated(sp.angle + i * TAU * 0.25)
			draw_line(sp.pos + d * r * 0.6, sp.pos + d * r * 1.3, Color(base.lightened(0.3), alpha), 1.5 * k)


func _draw_markers() -> void:
	var px := 1.0 / _zoom  # Bildschirmpixel in Weltpixeln: Grösse bleibt beim Zoomen gleich
	for m in _markers:
		if not _view.has_point(m.pos):
			continue
		var s := clampf(m.t / MARKER_TIME, 0.0, 1.0)
		var alpha := 1.0 - s * 0.75
		var r := (6.0 + 18.0 * (1.0 - s)) * px
		var c := Color(m.color, alpha)
		draw_arc(m.pos, r + 1.0 * px, 0.0, TAU, 28, Color(0, 0, 0, 0.45 * alpha), 4.5 * px)
		draw_arc(m.pos, r, 0.0, TAU, 28, c, 2.5 * px)
		if m.cross:
			var k := 4.5 * px
			draw_line(m.pos + Vector2(-k, -k), m.pos + Vector2(k, k), c, 2.0 * px)
			draw_line(m.pos + Vector2(-k, k), m.pos + Vector2(k, -k), c, 2.0 * px)
		else:
			draw_circle(m.pos, 2.5 * px, c)


## Fahne am Sammelpunkt: Stange und wehendes Dreieck in Reichsfarbe
## (lokal um den Fusspunkt gezeichnet, siehe _draw_projectiles)
func _draw_flags() -> void:
	var k := _ui_scale()
	for b in _flags:
		if not is_instance_valid(b):
			continue
		var p: Vector2 = b.rally_point
		if not _view.has_point(p):
			continue
		var kc: Color = b.kingdom.color
		var wave := sin(_wave_time * 4.0) * 2.0
		draw_set_transform(p, 0.0, Vector2(k, k * 0.4))
		draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.3))
		draw_set_transform(p, 0.0, Vector2(k, k))
		var top := Vector2(0, -40.0)
		draw_line(Vector2.ZERO, top, Color(0.12, 0.08, 0.04), 4.5)
		draw_line(Vector2.ZERO, top, Color(0.55, 0.38, 0.2), 2.5)
		var flag := PackedVector2Array([top, top + Vector2(25.0, 7.5 + wave), top + Vector2(0, 16.0)])
		draw_colored_polygon(flag, kc)
		flag.append(top)
		draw_polyline(flag, Color(0, 0, 0, 0.75), 1.5)
		draw_circle(top, 3.0, Color(1.0, 0.85, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Vergrösserung für Fahne und Linie: beim Herauszoomen gut sichtbar bleiben
func _ui_scale() -> float:
	return clampf(1.0 / _zoom, 1.0, 4.0)


## Vergrösserung für Geschosse und Treffer: beim Herauszoomen etwas grösser,
## damit Kämpfe aus der Ferne erkennbar bleiben (nah: Originalgrösse)
func _fx_scale() -> float:
	return clampf(0.7 / _zoom, 1.0, 3.0)
