## CombatEffects
##
## Kampfeffekte in der Spielwelt (reine Darstellung, verändert keinen
## Spielzustand): Geschosse, Treffer, Gefallene, Befehlsmarkierungen und die
## Sammelpunkt-Fahne ausgewählter Gebäude.
##
## Eine einzige Node zeichnet alle Effekte (keine Node je Effekt): das spart
## Zeichenaufrufe auch bei grossen Schlachten. Nur Gefallene und die
## gestrichelte Sammelpunkt-Linie liegen auf einer zweiten Zeichenebene
## UNTER den Einheiten (Bodenebene), damit sie lebende Einheiten nicht verdecken.
##
## Zeit: Geschosse, Treffer, Gefallene und die Fahne laufen mit
## GameClock.frame_delta (Pause friert sie ein, Tempo beschleunigt sie).
## Befehlsmarkierungen laufen in Echtzeit – sie sind die Rückmeldung auf einen
## Klick und sollen auch in der Pause und bei 3x Tempo gleich lang sichtbar sein.
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

const MARKER_COLORS := {
	"move": Color(0.35, 0.95, 0.4),
	"attack_move": Color(1.0, 0.6, 0.15),
	"attack": Color(1.0, 0.25, 0.2),
	"rally": Color(1.0, 0.88, 0.25),
}
const SPARK_UNIT_COLOR := Color(1.0, 0.22, 0.15)
const SPARK_BUILDING_COLOR := Color(1.0, 0.6, 0.15)
const ARROW_SHAFT := Color(0.45, 0.29, 0.14)
const ARROW_TIP := Color(0.88, 0.88, 0.82)
const ARROW_FLETCH := Color(0.95, 0.93, 0.85)
const BOLT_GLOW := Color(0.62, 0.3, 0.95, 0.32)
const BOLT_CORE := Color(0.28, 0.08, 0.42)
const BOLT_SHINE := Color(0.82, 0.62, 1.0)


## Ein fliegendes Geschoss (Weltpixel, Spielsekunden)
class Projectile:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var bolt := false
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
## Bodenebene unter den Einheiten (Gefallene, Sammelpunkt-Linie)
var _ground: Node2D


func setup(p_game: Node) -> void:
	game = p_game
	_corpse_seconds = maxf(float(DataDB.cmb("corpse_seconds", 4.0)), 0.1)
	_arrow_tex = Assets.texture(ARROW_TEXTURE)
	_bolt_tex = Assets.texture(BOLT_TEXTURE)
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
	p.bolt = kind == "bolt"
	p.dur = maxf(flight_time, 0.05)
	if not p.bolt:
		p.arc = minf(from_pos.distance_to(to_pos) * ARC_FACTOR, ARC_MAX)
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
	if not _markers.is_empty():
		_advance_markers(delta)
	_update_flags(gd > 0.0)
	var has_any := not (_projectiles.is_empty() and _sparks.is_empty() and _corpses.is_empty()
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
					_add_spark(p.to, p.hit == 2, p.hit_size)
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


## Bodenebene: Gefallene und gestrichelte Linie zum Sammelpunkt
func _draw_ground() -> void:
	if game == null or game.world == null:
		return
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


func _draw_projectiles() -> void:
	var has_tex := _arrow_tex != null or _bolt_tex != null
	for p in _projectiles:
		var s := clampf(p.t / p.dur, 0.0, 1.0)
		var ground := p.from.lerp(p.to, s)
		if not _view.has_point(ground):
			continue
		var lift := p.arc * 4.0 * s * (1.0 - s)
		var pos := ground - Vector2(0, lift)
		# Flugrichtung = Ableitung der Bahn (Bogen kippt die Spitze nach unten)
		var vel := (p.to - p.from) - Vector2(0, p.arc * 4.0 * (1.0 - 2.0 * s))
		var dir := vel.normalized() if vel.length_squared() > 0.01 else Vector2.RIGHT
		var tex := _bolt_tex if p.bolt else _arrow_tex
		if tex != null:
			# Grafik zeigt nach rechts, Spitze an der Position
			var ts := tex.get_size()
			draw_set_transform(pos, dir.angle(), Vector2.ONE)
			draw_texture(tex, Vector2(-ts.x, -ts.y * 0.5))
			continue
		if p.bolt:
			_draw_bolt(pos, dir)
		else:
			_draw_arrow(pos, ground, dir, lift)
	if has_tex:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Pfeil: brauner Schaft, helle Spitze, Federn; Schatten am Boden zeigt die Höhe
func _draw_arrow(pos: Vector2, ground: Vector2, dir: Vector2, lift: float) -> void:
	var n := dir.orthogonal()
	if lift > 2.0:
		var gdir := Vector2(dir.x, 0.0).normalized() if absf(dir.x) > 0.05 else dir
		draw_line(ground - gdir * 16.0, ground, Color(0, 0, 0, 0.22), 2.0)
	var tail := pos - dir * 22.0
	draw_line(tail, pos - dir * 5.0, ARROW_SHAFT, 2.0)
	draw_colored_polygon(PackedVector2Array([pos + dir * 1.5, pos - dir * 6.0 + n * 3.2, pos - dir * 6.0 - n * 3.2]),
			ARROW_TIP)
	draw_line(tail + dir * 5.0, tail - n * 3.5, ARROW_FLETCH, 1.5)
	draw_line(tail + dir * 5.0, tail + n * 3.5, ARROW_FLETCH, 1.5)


## Magisches Geschoss: violetter Schein, dunkler Kern, heller Kopf
func _draw_bolt(pos: Vector2, dir: Vector2) -> void:
	draw_circle(pos - dir * 4.0, 9.0, BOLT_GLOW)
	draw_line(pos - dir * 28.0, pos - dir * 12.0, Color(BOLT_SHINE, 0.25), 3.0)
	draw_line(pos - dir * 15.0, pos, BOLT_CORE, 5.0)
	draw_line(pos - dir * 13.0, pos - dir * 1.0, BOLT_SHINE, 2.0)
	draw_circle(pos, 3.0, BOLT_SHINE)


func _draw_sparks() -> void:
	for sp in _sparks:
		if not _view.has_point(sp.pos):
			continue
		var s := clampf(sp.t / SPARK_TIME, 0.0, 1.0)
		var base := SPARK_BUILDING_COLOR if sp.building else SPARK_UNIT_COLOR
		var alpha := 1.0 - s
		var r := sp.size * (0.45 + 0.9 * s)
		if s < 0.5:
			# Heller Kern im ersten Moment
			draw_circle(sp.pos, sp.size * 0.45 * (1.0 - s * 2.0), Color(1.0, 0.92, 0.7, 0.9 * alpha))
		draw_arc(sp.pos, r, 0.0, TAU, 18, Color(base, alpha), 1.0 + 2.5 * alpha)
		for i in 4:
			var d := Vector2.RIGHT.rotated(sp.angle + i * TAU * 0.25)
			draw_line(sp.pos + d * r * 0.6, sp.pos + d * r * 1.25, Color(base.lightened(0.3), alpha), 1.5)


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


## Fahne am Sammelpunkt: Stange und weisendes Dreieck in Reichsfarbe
func _draw_flags() -> void:
	var k := _ui_scale()
	for b in _flags:
		if not is_instance_valid(b):
			continue
		var p: Vector2 = b.rally_point
		if not _view.has_point(p):
			continue
		var kc: Color = b.kingdom.color
		var top := p + Vector2(0, -34.0 * k)
		var wave := sin(_wave_time * 4.0) * 2.0 * k
		draw_set_transform(p, 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 7.0 * k, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_line(p, top, Color(0.12, 0.08, 0.04), 4.0 * k)
		draw_line(p, top, Color(0.55, 0.38, 0.2), 2.0 * k)
		var flag := PackedVector2Array([top, top + Vector2(20.0 * k, 6.0 * k + wave), top + Vector2(0, 13.0 * k)])
		draw_colored_polygon(flag, kc)
		var outline := flag.duplicate()
		outline.append(top)
		draw_polyline(outline, Color(0, 0, 0, 0.75), 1.5 * k)
		draw_circle(top, 2.5 * k, Color(1.0, 0.85, 0.3))


## Vergrösserung für Fahne und Linie: beim Herauszoomen gut sichtbar bleiben
func _ui_scale() -> float:
	return clampf(1.0 / _zoom, 1.0, 4.0)
