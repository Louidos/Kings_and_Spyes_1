## SpellTargeting
##
## Zielmodus für Zauber (liegt in der Welt, über allem anderen):
## - Der Wirkungskreis folgt der Maus (Zauberfarbe; rot mit Grund, wenn hier
##   nicht gezaubert werden kann), daneben Name, Anzahl der Getroffenen
##   ("4 eigene Einheiten" / "3 Feinde") bzw. der Grund in Bildschirmgrösse.
##   Wer getroffen würde, bekommt einen kleinen Ring.
## - Der erlaubte Bereich (eigenes Gebiet + Zauberreichweite davor) ist schwach
##   in der Zauberfarbe eingefärbt. Er wird nur bei Gebiets- oder
##   Reichweitenänderung neu berechnet, nie pro Bild.
## - Linksklick zaubert und beendet den Modus (Umschalt: bleibt aktiv, solange
##   der Zauber gleich wieder bereit ist); geht es nicht, erscheint der Grund
##   als Meldung und der Modus bleibt.
## - Rechtsklick oder Esc (über Game) bricht ab, Bauen beendet den Modus.
## Der Knoten ist das letzte Kind von Game: sein _unhandled_input kommt vor
## Auswahl und Bauvorschau dran, die Mausklicks werden hier verbraucht – die
## Auswahl bleibt erhalten.
## Legt ausserdem die Zauberleiste (SpellBar) an (eigene CanvasLayer), damit
## das HUD-Skript nicht angefasst werden muss.
class_name SpellTargeting
extends Node2D

## Zielmodus an/aus (spell_id leer = aus)
signal targeting_changed(spell_id: String)

## can_cast mit Reichweitenprüfung höchstens so oft (Sekunden)
const CHECK_INTERVAL := 0.1
## Auch ohne Mausbewegung neu prüfen (Mana, Abklingzeit, Einheiten laufen)
const RECHECK_INTERVAL := 0.25
## Kleine Wirkungskreise (Beschwörung) mindestens so gross zeigen (Kacheln)
const MIN_MARKER_TILES := 1.5
const COLOR_BAD := Color(1.0, 0.3, 0.24)
const COLOR_BAD_TEXT := Color(1.0, 0.56, 0.48)
const COLOR_HINT := Color(0.84, 0.82, 0.78)
const COLOR_COUNT := Color(0.97, 0.96, 0.9)
const FONT_SIZE := 18
## Abstand des Textes vom Mauszeiger (Bildschirmpixel)
const LABEL_OFFSET := Vector2(24, 28)
## Ebene der Zauberleiste (wie das HUD)
const BAR_LAYER := 10
## Erlaubter Bereich: über der Gebietsgrenze (z 2), unter Magie-Effekten (4) und Einheiten (5)
const AREA_Z := 3
const AREA_FILL_ALPHA := 0.1
const AREA_LINE_ALPHA := 0.7
## Linienbreite der Bereichsgrenze in Bildschirmpixeln
const AREA_LINE_PX := 2.0
## Ring um getroffene Einheiten (Weltpixel)
const TARGET_RING := 17.0

var game: Node
var spell_id := ""
## Zauberleiste (unten rechts)
var bar: SpellBar

var _def: Dictionary = {}
var _color := Color.WHITE
## "own", "enemy" oder "" (Gebiet, Beschwörung: keine Anzahl)
var _side := ""
## Grund von can_cast an der Mausposition ("" = möglich)
var _reason := ""
## Wirkungskreis in Kacheln (nach Forschung, aus get_cast_params)
var _radius_tiles := 1.0
## Einheiten, die der Zauber an der Mausposition träfe (nur zum Zeichnen,
## vor jedem Zugriff mit is_instance_valid prüfen)
var _targets: Array = []
var _check_age := 0.0
var _check_cell := Vector2i(-2147483647, -2147483647)
## Letzte Mausposition (Bildschirm) aus den Ereignissen – auch für Testereignisse
var _mouse_screen := Vector2.ZERO
var _mouse_seen := false
var _mouse_world := Vector2.ZERO
var _over_ui := false
var _spin := 0.0

# Erlaubter Bereich (eigene Zeichenebene unter den Einheiten)
var _area: Node2D
var _area_dirty := true
var _area_range := -1
var _area_fill: Array[Rect2] = []
var _area_lines := PackedVector2Array()
var _area_zoom := 1.0


func _ready() -> void:
	# z_index 40 steht in game.tscn; gezeichnet wird nur im Zielmodus
	set_process(false)
	_area = Node2D.new()
	_area.name = "CastArea"
	_area.z_as_relative = false
	_area.z_index = AREA_Z
	_area.visible = false
	_area.draw.connect(_draw_area)
	add_child(_area)


func setup(p_game: Node) -> void:
	game = p_game
	var territory: TerritorySystem = game.territory
	territory.changed.connect(_on_territory_changed)
	# Reich und HUD gibt es erst am Ende von Game._start_game
	_create_bar.call_deferred()


func is_active() -> bool:
	return not spell_id.is_empty()


## Zielmodus für einen Zauber starten (Bauen und Angriff-Vorrücken enden,
## die Auswahl bleibt)
func start(p_spell_id: String) -> void:
	if game == null or game.player == null:
		return
	var def := DataDB.get_spell(p_spell_id)
	if def.is_empty():
		return
	game.placement.cancel()
	game.selection.cancel_arm()
	spell_id = p_spell_id
	_def = def
	_color = def.get("color", Color.WHITE)
	_side = game.magic_system.get_target_side(p_spell_id)
	_reason = ""
	_targets.clear()
	_spin = 0.0
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	set_process(true)
	if not _mouse_seen:
		_mouse_screen = get_viewport().get_mouse_position()
	if _area_dirty or game.magic_system.get_cast_range(game.player) != _area_range:
		_rebuild_area()
	_area_zoom = game.camera.zoom.x
	_area.visible = true
	_area.queue_redraw()
	_update_mouse()
	_check(true)
	queue_redraw()
	targeting_changed.emit(spell_id)


func cancel() -> void:
	if spell_id.is_empty():
		return
	spell_id = ""
	_def = {}
	_reason = ""
	_targets.clear()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	set_process(false)
	_area.visible = false
	queue_redraw()
	targeting_changed.emit("")


# ---------------------------------------------------------------------------
# Ablauf
# ---------------------------------------------------------------------------

func _create_bar() -> void:
	if game == null or game.player == null or bar != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "SpellBarLayer"
	layer.layer = BAR_LAYER
	add_child(layer)
	bar = SpellBar.new()
	bar.name = "SpellBar"
	layer.add_child(bar)
	bar.setup(game)


func _process(delta: float) -> void:
	if not is_active():
		set_process(false)
		return
	# Bauen gestartet, Menü, Spielende oder kein König mehr: Zielmodus endet
	var king: Variant = game.player.king
	if game.placement.is_active() or not game.camera.input_enabled \
			or not is_instance_valid(king) or not (king as Unit).is_alive():
		cancel()
		return
	_spin = fmod(_spin + delta * 0.6, TAU)
	# Gebiet oder Reichweite (Forschung) geändert: Bereich neu berechnen
	if _area_dirty or game.magic_system.get_cast_range(game.player) != _area_range:
		_rebuild_area()
		_area.queue_redraw()
	# Linienbreite in Bildschirmpixeln halten: nur bei spürbarer Zoomänderung neu zeichnen
	var zoom: float = game.camera.zoom.x
	if absf(zoom - _area_zoom) > _area_zoom * 0.04:
		_area_zoom = zoom
		_area.queue_redraw()
	_update_mouse()
	_check(false)
	queue_redraw()


## Mausposition merken (auch über dem HUD, damit der Kreis gleich richtig steht)
func _input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		_mouse_screen = mm.position
		_mouse_seen = true


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		# Auch das Loslassen verbrauchen: die Auswahl soll nichts davon merken
		get_viewport().set_input_as_handled()
		if mb.pressed:
			_mouse_screen = mb.position
			_mouse_seen = true
			_try_cast(_screen_to_world(mb.position), mb.shift_pressed)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		if mb.pressed:
			cancel()


func _try_cast(pos: Vector2, keep: bool) -> void:
	var k: Kingdom = game.player
	var ms: MagicSystem = game.magic_system
	var reason := ms.can_cast(k, spell_id, pos)
	if not reason.is_empty():
		Notify.warning(reason)
		_reason = reason
		queue_redraw()
		return
	if not ms.cast(k, spell_id, pos):
		Notify.warning("Der Zauber ist misslungen.")
		return
	# Umschalt: weiter zielen – aber nur, wenn der Zauber gleich wieder geht
	# (sonst stünde nur ein roter Kreis mit der Abklingzeit da)
	if keep and ms.can_cast_now(k, spell_id).is_empty():
		_check(true)
	else:
		cancel()


func _update_mouse() -> void:
	_mouse_world = _screen_to_world(_mouse_screen)
	_over_ui = get_viewport().gui_get_hovered_control() != null


## can_cast an der Mausposition: bei neuer Kachel (höchstens 10× pro Sekunde)
## oder alle 0.25 s (Mana, Abklingzeit und Einheiten ändern sich auch ohne Mausbewegung)
func _check(force: bool) -> void:
	_check_age += get_process_delta_time()
	var cell: Vector2i = game.world.world_to_cell(_mouse_world)
	if not force:
		if _check_age < CHECK_INTERVAL:
			return
		if cell == _check_cell and _check_age < RECHECK_INTERVAL:
			return
	_check_age = 0.0
	_check_cell = cell
	var k: Kingdom = game.player
	var ms: MagicSystem = game.magic_system
	_reason = ms.can_cast(k, spell_id, _mouse_world)
	_radius_tiles = float(ms.get_cast_params(k, spell_id).get("radius", 1.0))
	_targets = ms.get_targets(k, spell_id, _mouse_world) if not _side.is_empty() else []


func _screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p


func _on_territory_changed(_kingdom_id: int, _bbox: Rect2i, _dirty: Rect2i) -> void:
	# Erst beim nächsten Zielmodus bzw. im nächsten Bild neu berechnen
	_area_dirty = true


# ---------------------------------------------------------------------------
# Erlaubter Bereich
# ---------------------------------------------------------------------------

## Alle Kacheln, deren Abstand zur nächsten eigenen Kachel höchstens die
## Zauberreichweite ist (wie MagicSystem.in_range: dx² + dy² ≤ r²).
## Exakter euklidischer Abstand in zwei Durchgängen (Spalten, dann Zeilen mit
## der unteren Hülle der Parabeln nach Felzenszwalb) – linear in der Fläche.
## Ergebnis: Füllstreifen je Zeile und die Grenzlinie als Segmente.
func _rebuild_area() -> void:
	_area_dirty = false
	_area_fill.clear()
	_area_lines = PackedVector2Array()
	var k: Kingdom = game.player
	var world: WorldData = game.world
	var r: int = game.magic_system.get_cast_range(k)
	_area_range = r
	var bbox := TerritorySystem.kingdom_bbox(k, world)
	if not bbox.has_area():
		return
	var rect := bbox.grow(r).intersection(Rect2i(0, 0, world.width, world.height))
	var w := rect.size.x
	var h := rect.size.y
	var ox := rect.position.x
	var oy := rect.position.y
	var terr := world.territory
	var ww := world.width
	var kid := k.id
	var r2 := r * r
	var far := r + 1

	# 1. Senkrechter Abstand zur nächsten eigenen Kachel derselben Spalte (ab r+1 egal)
	var col_d := PackedInt32Array()
	col_d.resize(w * h)
	for x in w:
		var d := far
		for y in h:
			if terr[(oy + y) * ww + ox + x] == kid:
				d = 0
			elif d < far:
				d += 1
			col_d[y * w + x] = d
		d = far
		for y in range(h - 1, -1, -1):
			var i := y * w + x
			if col_d[i] == 0:
				d = 0
			elif d < far:
				d += 1
			if d < col_d[i]:
				col_d[i] = d

	# 2. Zeilenweise: kleinster Wert von (x − x')² + Spaltenabstand(x')²
	var inside := PackedByteArray()
	inside.resize(w * h)
	var f := PackedInt32Array()
	f.resize(w)
	var v := PackedInt32Array()
	v.resize(w)
	var z := PackedFloat32Array()
	z.resize(w + 1)
	for y in h:
		var row := y * w
		var n := -1
		for q in w:
			var dq := col_d[row + q]
			if dq > r:
				continue
			var fq := dq * dq
			f[q] = fq
			if n < 0:
				n = 0
				v[0] = q
				z[0] = -INF
				z[1] = INF
				continue
			var p := v[n]
			var s := float(fq + q * q - f[p] - p * p) / float(2 * (q - p))
			# z[0] ist −∞: die Schleife endet spätestens bei n = 0
			while s <= z[n]:
				n -= 1
				p = v[n]
				s = float(fq + q * q - f[p] - p * p) / float(2 * (q - p))
			n += 1
			v[n] = q
			z[n] = s
			z[n + 1] = INF
		if n < 0:
			continue
		var j := 0
		for q in w:
			while z[j + 1] < float(q):
				j += 1
			var p := v[j]
			if (q - p) * (q - p) + f[p] <= r2:
				inside[row + q] = 1

	# 3. Füllstreifen und Grenzlinie (Weltpixel)
	var ts := float(world.tile_size)
	for y in h:
		var row := y * w
		var py := float(oy + y) * ts
		var run := -1
		var top_run := -1
		var bottom_run := -1
		for x in w + 1:
			var on := x < w and inside[row + x] == 1
			if on and run < 0:
				run = x
			elif not on and run >= 0:
				var x0 := float(ox + run) * ts
				var x1 := float(ox + x) * ts
				_area_fill.append(Rect2(x0, py, x1 - x0, ts))
				_area_lines.append_array([Vector2(x0, py), Vector2(x0, py + ts), Vector2(x1, py), Vector2(x1, py + ts)])
				run = -1
			# Obere und untere Kanten (zu einer Linie je Strecke zusammengefasst)
			var top := on and (y == 0 or inside[row - w + x] == 0)
			if top and top_run < 0:
				top_run = x
			elif not top and top_run >= 0:
				_area_lines.append_array([Vector2(float(ox + top_run) * ts, py), Vector2(float(ox + x) * ts, py)])
				top_run = -1
			var bottom := on and (y == h - 1 or inside[row + w + x] == 0)
			if bottom and bottom_run < 0:
				bottom_run = x
			elif not bottom and bottom_run >= 0:
				_area_lines.append_array([Vector2(float(ox + bottom_run) * ts, py + ts), Vector2(float(ox + x) * ts, py + ts)])
				bottom_run = -1


func _draw_area() -> void:
	if not is_active() or _area_fill.is_empty():
		return
	var fill := Color(_color, AREA_FILL_ALPHA)
	for r in _area_fill:
		_area.draw_rect(r, fill, true)
	if _area_lines.size() >= 2:
		var line := Color(SpellTargeting._readable(_color), AREA_LINE_ALPHA)
		_area.draw_multiline(_area_lines, line, AREA_LINE_PX / maxf(_area_zoom, 0.01))


# ---------------------------------------------------------------------------
# Zeichnen (Kreis und Text an der Maus)
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not is_active() or _over_ui:
		return
	var zoom := maxf(game.camera.zoom.x, 0.01)
	var px := 1.0 / zoom
	var ts := float(game.world.tile_size)
	var ok := _reason.is_empty()
	var col := _color if ok else COLOR_BAD
	var line_col := SpellTargeting._readable(col)
	var radius := maxf(_radius_tiles, MIN_MARKER_TILES) * ts
	var c := _mouse_world

	# Getroffene Einheiten: kleiner Ring in der Zauberfarbe
	for t in _targets:
		if not is_instance_valid(t):
			continue
		var u := t as Unit
		draw_arc(u.position, TARGET_RING, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 4.0 * px, true)
		draw_arc(u.position, TARGET_RING, 0.0, TAU, 24, Color(line_col, 0.95), 2.0 * px, true)

	# Fläche, dunkler Saum (Kontrast auf hellem Gelände) und Rand
	draw_circle(c, radius, Color(col, 0.16 if ok else 0.13))
	draw_arc(c, radius, 0.0, TAU, 96, Color(0, 0, 0, 0.45), 5.0 * px, true)
	draw_arc(c, radius, 0.0, TAU, 96, Color(line_col, 0.95), 2.5 * px, true)
	# Langsam kreisende Runenbögen innen
	var inner := radius - 8.0 * px
	if inner > 8.0 * px:
		for i in 6:
			var a := _spin + TAU * float(i) / 6.0
			draw_arc(c, inner, a, a + 0.42, 10, Color(line_col, 0.55), 2.0 * px, true)
	# Mitte
	var m := 7.0 * px
	draw_line(c - Vector2(m, 0), c + Vector2(m, 0), Color(line_col, 0.9), 2.0 * px, true)
	draw_line(c - Vector2(0, m), c + Vector2(0, m), Color(line_col, 0.9), 2.0 * px, true)

	# Text neben dem Mauszeiger in Bildschirmgrösse
	var lines: PackedStringArray = [str(_def.get("name", spell_id))]
	var colors: Array[Color] = [SpellTargeting._readable(_color)]
	if not ok:
		lines.append(_reason)
		colors.append(COLOR_BAD_TEXT)
	else:
		var info := _count_text() if not _side.is_empty() else _area_info()
		if not info.is_empty():
			lines.append(info)
			colors.append(COLOR_COUNT)
		lines.append("Linksklick: zaubern  ·  Rechtsklick: abbrechen")
		colors.append(COLOR_HINT)
	draw_set_transform(c, 0.0, Vector2(px, px))
	_draw_lines(lines, colors)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## "4 eigene Einheiten" / "1 Feind" (leer bei Gebiet und Beschwörung)
func _count_text() -> String:
	if _side.is_empty():
		return ""
	var n := 0
	for t in _targets:
		if is_instance_valid(t):
			n += 1
	if _side == "enemy":
		return "1 Feind" if n == 1 else "%d Feinde" % n
	return "1 eigene Einheit" if n == 1 else "%d eigene Einheiten" % n


## Gebiet und Beschwörung: was an dieser Stelle entsteht
func _area_info() -> String:
	var summon: Dictionary = _def.get("summon", {})
	if not summon.is_empty():
		var unit_name := str(DataDB.get_unit_type(str(summon.get("unit", ""))).get("name", "?"))
		return "%d× %s erscheinen hier" % [int(summon.get("count", 1)), unit_name]
	if _def.has("zone"):
		return "Wirkt auf alles im Kreis"
	return ""


## Zeilen rechts unter dem Mauszeiger; am Bildschirmrand auf die andere Seite
func _draw_lines(lines: PackedStringArray, colors: Array[Color]) -> void:
	var font := ThemeDB.fallback_font
	var sizes: Array[int] = []
	var width := 0.0
	var height := 0.0
	for i in lines.size():
		var fs := FONT_SIZE + (2 if i == 0 else -1)
		sizes.append(fs)
		width = maxf(width, font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		height += float(fs) * 1.25
	var view := get_viewport().get_visible_rect().size
	var offset := LABEL_OFFSET
	if _mouse_screen.x + offset.x + width > view.x - 8.0:
		offset.x = -offset.x - width
	if _mouse_screen.y + offset.y + height > view.y - 8.0:
		offset.y = -12.0 - height
	var y := offset.y
	for i in lines.size():
		var fs := sizes[i]
		y += float(fs)
		var pos := Vector2(offset.x, y)
		draw_string_outline(font, pos, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
		draw_string(font, pos, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colors[i])
		y += float(fs) * 0.25


## Dunkle Zauberfarben für Linien und Text aufhellen
static func _readable(col: Color) -> Color:
	return col.lightened(0.35) if col.get_luminance() < 0.42 else col


func _exit_tree() -> void:
	if is_active():
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
