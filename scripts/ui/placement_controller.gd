## PlacementController
##
## Bauvorschau und Platzieren mit der Maus (liegt in der Spielwelt):
## - Gebäude: Vorschau folgt der Maus (grün = möglich, rot = nicht möglich,
##   mit Grund). Linksklick baut; mit gedrückter Umschalttaste bleibt der
##   Baumodus aktiv. Für Annahmestellen wird der Sammelbereich angezeigt.
## - Linien (Strassen, ab Phase 9 Mauern; placement = "line" in den Daten):
##   Maustaste gedrückt halten und ziehen (erst waagrecht, dann senkrecht).
##   Der Modus bleibt aktiv, bis Rechtsklick oder Esc.
## - Abreissen: Strassen anklicken oder überziehen entfernt sie; ein Klick auf
##   ein Gebäude wählt es aus (Abreissen dann im Auswahlfenster).
class_name PlacementController
extends Node2D

signal placement_started(def: Dictionary)
signal placement_ended

const MODE_NONE := ""
const MODE_BUILD := "build"
const MODE_ROAD := "road"
const MODE_DEMOLISH := "demolish"

var game: Node
var world: WorldData
var mode: String = MODE_NONE
var def: Dictionary = {}

var _mouse_cell := Vector2i(-1, -1)
var _mouse_pos := Vector2.ZERO
var _dragging := false
var _drag_start := Vector2i.ZERO
## Gebäude: obere linke Kachel der Vorschau
var _top_left := Vector2i.ZERO
var _reason: String = ""


func setup(p_game: Node) -> void:
	game = p_game
	world = game.world


func start(p_def: Dictionary) -> void:
	game.spell_targeting.cancel()
	def = p_def
	mode = MODE_ROAD if str(def.get("placement", "")) == "line" else MODE_BUILD
	_dragging = false
	game.selection.clear()
	placement_started.emit(def)
	_update_preview()


func start_demolish() -> void:
	game.spell_targeting.cancel()
	def = {}
	mode = MODE_DEMOLISH
	_dragging = false
	placement_started.emit(def)
	_update_preview()


func cancel() -> void:
	if mode == MODE_NONE:
		return
	mode = MODE_NONE
	def = {}
	_dragging = false
	placement_ended.emit()
	queue_redraw()


func is_active() -> bool:
	return mode != MODE_NONE


func _process(_delta: float) -> void:
	if not is_active():
		return
	_update_preview()


func _update_preview() -> void:
	_mouse_pos = get_global_mouse_position()
	_mouse_cell = world.world_to_cell(_mouse_pos)
	if mode == MODE_BUILD:
		var size: Vector2i = def.get("size", Vector2i(2, 2))
		# Grundfläche um den Mauszeiger zentrieren
		var f := _mouse_pos / float(world.tile_size) - Vector2(size) * 0.5 + Vector2(0.5, 0.5)
		_top_left = Vector2i(floori(f.x), floori(f.y))
		_reason = game.building_system.can_place(def, _top_left, game.player)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_update_preview()
			match mode:
				MODE_BUILD:
					if mb.pressed:
						_try_place_building(mb.shift_pressed)
				MODE_ROAD, MODE_DEMOLISH:
					if mb.pressed:
						_dragging = true
						_drag_start = _mouse_cell
						var b: Object = world.get_building_at(_mouse_cell)
						if mode == MODE_DEMOLISH and b != null:
							_dragging = false
							if b.kingdom == game.player:
								game.selection.select([b])
					elif _dragging:
						_dragging = false
						_finish_drag()
			get_viewport().set_input_as_handled()


func _try_place_building(keep_mode: bool) -> void:
	if not _reason.is_empty():
		Notify.warning(_reason)
		return
	var b: Building = game.building_system.place_building(def, _top_left, game.player)
	if b == null:
		return
	if game.work_system.get_job_count(game.player, "builder") == 0:
		Notify.warning("Keine Bauarbeiter – weise in der Arbeitsverteilung (J) Bauarbeiter zu.", b.get_center())
	if not keep_mode:
		cancel()


func _finish_drag() -> void:
	var cells := _drag_path(_drag_start, _mouse_cell)
	if mode == MODE_ROAD:
		var placed: int = game.building_system.place_roads(cells, game.player)
		if placed == 0:
			var cost: Dictionary = def.get("cost", {})
			var reason: String = game.player.missing_text(cost)
			if reason.is_empty() and not cells.is_empty():
				reason = game.building_system.can_place_road(cells[0], game.player)
			if not reason.is_empty():
				Notify.warning(reason)
		elif game.work_system.get_job_count(game.player, "builder") == 0:
			Notify.warning("Keine Bauarbeiter – weise in der Arbeitsverteilung (J) Bauarbeiter zu.")
	elif mode == MODE_DEMOLISH:
		for c in cells:
			if world.roads.has(c):
				game.building_system.remove_road(c, game.player)


## Kacheln eines Ziehvorgangs: erst waagrecht, dann senkrecht
static func _drag_path(from: Vector2i, to: Vector2i) -> Array:
	var cells: Array = []
	var step_x := 1 if to.x >= from.x else -1
	var x := from.x
	while true:
		cells.append(Vector2i(x, from.y))
		if x == to.x:
			break
		x += step_x
	var step_y := 1 if to.y >= from.y else -1
	var y := from.y
	while y != to.y:
		y += step_y
		cells.append(Vector2i(to.x, y))
	return cells


# ---------------------------------------------------------------------------
# Zeichnen (in Weltkoordinaten)
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not is_active():
		return
	var ts := float(world.tile_size)
	var zoom := get_viewport().get_camera_2d().zoom.x if get_viewport().get_camera_2d() else 1.0
	var font_size := clampi(int(17.0 / zoom), 12, 400)
	match mode:
		MODE_BUILD:
			_draw_building_preview(ts, font_size)
		MODE_ROAD:
			_draw_road_preview(ts, font_size)
		MODE_DEMOLISH:
			_draw_demolish_preview(ts, font_size)


func _draw_building_preview(ts: float, font_size: int) -> void:
	var size: Vector2i = def.get("size", Vector2i(2, 2))
	var rect := Rect2(Vector2(_top_left) * ts, Vector2(size) * ts)
	var ok := _reason.is_empty()
	var color := Color(0.3, 1.0, 0.4) if ok else Color(1.0, 0.3, 0.25)
	# Sammelbereich von Annahmestellen anzeigen
	var gather := int(def.get("gather_radius", 0))
	if gather > 0:
		var center_cell := _top_left + Vector2i(size.x >> 1, size.y >> 1)
		var area := Rect2(Vector2(center_cell - Vector2i(gather, gather)) * ts, Vector2(gather * 2 + 1, gather * 2 + 1) * ts)
		draw_rect(area, Color(1, 1, 1, 0.06), true)
		draw_rect(area, Color(1, 1, 1, 0.5), false, 2.0)
	var tex := Assets.texture(DataDB.get_building_sprite(def, game.player.faction_id))
	SpriteDraw.draw_entity(self, tex, rect, def.get("color", Color.GRAY), DataDB.get_building_label(def, game.player.faction_id), "rect", Color(1, 1, 1, 0.6))
	draw_rect(rect, Color(color, 0.25), true)
	draw_rect(rect, color, false, 3.0)
	var lines: PackedStringArray = [DataDB.get_building_name(def, game.player.faction_id)]
	if ok:
		lines.append("Kosten: " + DataDB.cost_to_text(def.get("cost", {})))
		var eff := _preview_efficiency(size)
		if eff >= 0.0:
			lines.append("Ertrag: %d %%" % roundi(eff * 100.0))
	else:
		lines.append(_reason)
	_draw_text_block(lines, rect.get_center() + Vector2(0, rect.size.y * 0.5 + font_size * 0.9), font_size, color)


func _draw_road_preview(ts: float, font_size: int) -> void:
	var cells := _drag_path(_drag_start, _mouse_cell) if _dragging else [_mouse_cell]
	var cost: Dictionary = def.get("cost", {})
	var valid := 0
	for c in cells:
		var ok: bool = game.building_system.can_place_road(c, game.player).is_empty()
		if ok:
			valid += 1
		var color := Color(0.3, 1.0, 0.4) if ok else Color(1.0, 0.3, 0.25)
		var rect := Rect2(Vector2(c) * ts, Vector2(ts, ts))
		draw_rect(rect, Color(color, 0.3), true)
		draw_rect(rect, color, false, 2.0)
	var total := {}
	for res_id in cost:
		total[res_id] = float(cost[res_id]) * valid
	var lines: PackedStringArray = ["%d Strassen – %s" % [valid, DataDB.cost_to_text(total)]]
	var missing: String = game.player.missing_text(total)
	if not missing.is_empty():
		lines.append(missing)
	if not _dragging:
		lines.append("Maustaste halten und ziehen")
	var anchor := world.cell_to_world(_mouse_cell) + Vector2(0, ts * 0.9)
	_draw_text_block(lines, anchor, font_size, Color.WHITE if missing.is_empty() else Color(1.0, 0.5, 0.4))


func _draw_demolish_preview(ts: float, font_size: int) -> void:
	var cells := _drag_path(_drag_start, _mouse_cell) if _dragging else [_mouse_cell]
	for c in cells:
		if world.roads.has(c):
			var rect := Rect2(Vector2(c) * ts, Vector2(ts, ts))
			draw_rect(rect, Color(1, 0.2, 0.2, 0.35), true)
			draw_rect(rect, Color(1, 0.3, 0.3), false, 2.0)
	var b: Building = world.get_building_at(_mouse_cell)
	if b != null:
		var fp := b.get_footprint()
		draw_rect(Rect2(Vector2(fp.position) * ts, Vector2(fp.size) * ts), Color(1, 0.6, 0.2), false, 3.0)
	_draw_text_block(["Abreissen: Strassen anklicken oder überziehen, Gebäude anklicken"],
			world.cell_to_world(_mouse_cell) + Vector2(0, ts * 0.9), font_size, Color(1, 0.75, 0.6))


## Ertrag einer Vorschau-Position (-1 wenn das Gebäude keinen Geländefaktor hat)
func _preview_efficiency(size: Vector2i) -> float:
	var table: Dictionary = def.get("biome_efficiency", {})
	if table.is_empty():
		return -1.0
	var total := 0.0
	for y in range(_top_left.y, _top_left.y + size.y):
		for x in range(_top_left.x, _top_left.x + size.x):
			total += float(table.get(world.get_biome(Vector2i(x, y)).get("id", ""), 1.0))
	return total / float(size.x * size.y)


func _draw_text_block(lines: PackedStringArray, top_center: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var y := top_center.y
	for line in lines:
		var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := Vector2(top_center.x - w * 0.5, y)
		draw_string_outline(font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(4, font_size >> 2), Color(0, 0, 0, 0.85))
		draw_string(font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		y += font_size * 1.2
