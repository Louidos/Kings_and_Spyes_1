## SpellTargeting
##
## Zielmodus für Zauber (liegt in der Welt, über allem anderen):
## - Der Wirkungskreis folgt der Maus (Zauberfarbe; rot mit Grund, wenn hier
##   nicht gezaubert werden kann), daneben Name bzw. Grund in Bildschirmgrösse.
## - Linksklick zaubert und beendet den Modus (Umschalt: bleibt aktiv);
##   geht es nicht, erscheint der Grund als Meldung und der Modus bleibt.
## - Rechtsklick oder Esc (über Game) bricht ab.
## Der Knoten ist das letzte Kind von Game: sein _unhandled_input kommt vor
## Auswahl und Bauvorschau dran, die Mausklicks werden hier verbraucht.
## Legt ausserdem die Zauberleiste (SpellBar) an.
class_name SpellTargeting
extends Node2D

## Zielmodus an/aus (spell_id leer = aus)
signal targeting_changed(spell_id: String)

## can_cast mit Reichweitenprüfung höchstens so oft (Sekunden)
const CHECK_INTERVAL := 0.1
## Auch ohne Mausbewegung neu prüfen (Mana, Abklingzeit)
const RECHECK_INTERVAL := 0.25
## Kleine Wirkungskreise (Beschwörung) mindestens so gross zeigen (Kacheln)
const MIN_MARKER_TILES := 1.5
const COLOR_BAD := Color(1.0, 0.3, 0.24)
const COLOR_HINT := Color(0.92, 0.9, 0.86)
const FONT_SIZE := 17
## Ebene der Zauberleiste (wie das HUD)
const BAR_LAYER := 10

var game: Node
var spell_id := ""
## Zauberleiste (unten rechts)
var bar: SpellBar

var _def: Dictionary = {}
var _color := Color.WHITE
## Grund von can_cast an der Mausposition ("" = möglich)
var _reason := ""
var _check_age := 0.0
var _check_cell := Vector2i(-2147483647, -2147483647)
## Letzte Mausposition (Bildschirm) aus den Ereignissen – auch für Testereignisse
var _mouse_screen := Vector2.ZERO
var _mouse_world := Vector2.ZERO
var _over_ui := false
var _spin := 0.0


func _ready() -> void:
	# z_index 40 steht in game.tscn; gezeichnet wird nur im Zielmodus
	set_process(false)


func setup(p_game: Node) -> void:
	game = p_game
	# Reich und HUD gibt es erst am Ende von Game._start_game
	_create_bar.call_deferred()


func is_active() -> bool:
	return not spell_id.is_empty()


## Zielmodus für einen Zauber starten (Bauen und Angriff-Vorrücken enden)
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
	_spin = 0.0
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	set_process(true)
	if _mouse_screen == Vector2.ZERO:
		_mouse_screen = get_viewport().get_mouse_position()
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
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	set_process(false)
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
	# Bauen gestartet, Menü oder Spielende: Zielmodus endet
	if game.placement.is_active() or not game.camera.input_enabled or not is_instance_valid(game.player.king):
		cancel()
		return
	_spin = fmod(_spin + delta * 0.6, TAU)
	_update_mouse()
	_check(false)
	queue_redraw()


## Mausposition merken (auch über dem HUD, damit der Kreis gleich richtig steht)
func _input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		_mouse_screen = mm.position


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if mb.pressed:
			_mouse_screen = mb.position
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
		return
	if keep:
		_check(true)
	else:
		cancel()


func _update_mouse() -> void:
	_mouse_world = _screen_to_world(_mouse_screen)
	_over_ui = get_viewport().gui_get_hovered_control() != null


## can_cast an der Mausposition: bei neuer Kachel (höchstens 10× pro Sekunde)
## oder alle 0.25 s (Mana und Abklingzeit ändern sich auch ohne Mausbewegung)
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
	_reason = game.magic_system.can_cast(game.player, spell_id, _mouse_world)


func _screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p


# ---------------------------------------------------------------------------
# Zeichnen
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
	var radius := maxf(float(_def.get("radius", 1.0)), MIN_MARKER_TILES) * ts
	var c := _mouse_world

	# Fläche, dunkler Saum (Kontrast auf hellem Gelände) und Rand
	draw_circle(c, radius, Color(col, 0.16 if ok else 0.13))
	draw_arc(c, radius, 0.0, TAU, 96, Color(0, 0, 0, 0.45), 5.0 * px, true)
	draw_arc(c, radius, 0.0, TAU, 96, Color(line_col, 0.95), 2.5 * px, true)
	# Langsam kreisende Runenbögen innen
	var inner := radius - 7.0 * px
	if inner > 6.0 * px:
		for i in 6:
			var a := _spin + TAU * float(i) / 6.0
			draw_arc(c, inner, a, a + 0.42, 10, Color(line_col, 0.55), 2.0 * px, true)
	# Mitte
	var m := 6.0 * px
	draw_line(c - Vector2(m, 0), c + Vector2(m, 0), Color(line_col, 0.9), 2.0 * px, true)
	draw_line(c - Vector2(0, m), c + Vector2(0, m), Color(line_col, 0.9), 2.0 * px, true)

	# Text neben dem Mauszeiger in Bildschirmgrösse
	var lines: PackedStringArray = [str(_def.get("name", spell_id))]
	var colors: Array[Color] = [SpellTargeting._readable(_color)]
	if ok:
		lines.append("Linksklick: zaubern  ·  Rechtsklick: abbrechen")
		colors.append(COLOR_HINT)
	else:
		lines.append(_reason)
		colors.append(Color(1.0, 0.5, 0.42))
	draw_set_transform(c, 0.0, Vector2(px, px))
	_draw_lines(lines, colors, Vector2(22, 26))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_lines(lines: PackedStringArray, colors: Array[Color], offset: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var y := offset.y
	for i in lines.size():
		var fs := FONT_SIZE + (1 if i == 0 else -2)
		var pos := Vector2(offset.x, y)
		draw_string_outline(font, pos, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
		draw_string(font, pos, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colors[i])
		y += float(fs) * 1.25


## Dunkle Zauberfarben für Linien und Text aufhellen
static func _readable(col: Color) -> Color:
	return col.lightened(0.35) if col.get_luminance() < 0.42 else col


func _exit_tree() -> void:
	if is_active():
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
