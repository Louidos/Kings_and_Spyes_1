## WorldMap
##
## Zeichnet die Spielwelt effizient:
## - Übersichtsbild (1 Pixel pro Kachel, hochskaliert) liegt immer ganz unten.
##   Es wird allein angezeigt, wenn weit herausgezoomt ist (Detailstufe/LOD).
## - Darüber liegen Chunks (z. B. 32×32 Kacheln) als TileMapLayer. Es werden nur
##   die Chunks im Sichtbereich der Kamera aufgebaut (Culling); weit entfernte
##   werden abgebaut und ihre Nodes wiederverwendet (Pool).
## - Pro Frame werden nur wenige Chunks gebaut, damit das Bild nicht ruckelt.
## - Jeder Chunk hat eine zweite Ebene für Rohstoffvorkommen. Strassen liegen
##   in einer gemeinsamen, dünn besetzten Ebene. Darüber die Reichsgrenze.
## - Ändert sich eine Kachel (abgeholzt, abgebaut), wird nur diese neu gesetzt.
class_name WorldMap
extends Node2D

## Kachel unter dem Mauszeiger hat sich geändert (-1,-1 = ausserhalb)
signal hovered_cell_changed(cell: Vector2i)

var world: WorldData
var tileset: TileSet
var deposit_tileset: TileSet
var road_tileset: TileSet
var overview_texture: ImageTexture
## Reichsgrenze des Spielers (wird von der Spielszene gefüllt)
var territory_border: TerritoryBorder
var hovered_cell := Vector2i(-1, -1)

var chunk_size: int = 32
var tile_variants: int = 4
var detail_min_zoom: float = 0.2
var max_builds_per_frame: int = 3

var _overview: Sprite2D
var _chunk_root: Node2D
var _cursor: CellCursor
var _roads: TileMapLayer
## Chunk-Koordinate -> TileMapLayer (Gelände; Kind 0 = Vorkommen-Ebene)
var _chunks: Dictionary = {}
var _pool: Array[TileMapLayer] = []
var _chunk_count := Vector2i.ZERO
## Übersichtsbild höchstens so oft neu hochladen (Sekunden)
var _overview_refresh_interval := 1.0
var _overview_timer := 0.0


func _ready() -> void:
	chunk_size = int(DataDB.cfg("map.chunk_size", chunk_size))
	tile_variants = maxi(1, int(DataDB.cfg("map.tile_variants", tile_variants)))
	detail_min_zoom = float(DataDB.cfg("camera.terrain_detail_min_zoom", detail_min_zoom))
	max_builds_per_frame = int(DataDB.cfg("camera.max_chunk_builds_per_frame", max_builds_per_frame))


## Übernimmt eine fertig erzeugte Welt und baut die Darstellung auf.
func setup(world_data: WorldData) -> void:
	world = world_data
	_clear()
	tileset = TerrainTileset.build(world.tile_size, tile_variants)
	deposit_tileset = DepositTileset.build(world.tile_size)
	road_tileset = DepositTileset.build_roads(world.tile_size)
	world.cell_changed.connect(refresh_cell)
	world.road_changed.connect(func(c: Vector2i) -> void: set_road_visual(c, world.get_road(c)))

	overview_texture = ImageTexture.create_from_image(world.overview_image)
	_overview = Sprite2D.new()
	_overview.name = "Overview"
	_overview.texture = overview_texture
	_overview.centered = false
	_overview.scale = Vector2(world.tile_size, world.tile_size)
	_overview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overview.z_index = -10
	add_child(_overview)

	_chunk_root = Node2D.new()
	_chunk_root.name = "Chunks"
	add_child(_chunk_root)

	_roads = TileMapLayer.new()
	_roads.name = "Roads"
	_roads.tile_set = road_tileset
	_roads.collision_enabled = false
	_roads.navigation_enabled = false
	_roads.z_index = 1
	add_child(_roads)

	territory_border = TerritoryBorder.new()
	territory_border.name = "TerritoryBorder"
	territory_border.z_index = 2
	add_child(territory_border)

	_cursor = CellCursor.new()
	_cursor.name = "CellCursor"
	_cursor.tile_size = world.tile_size
	_cursor.z_index = 10
	add_child(_cursor)

	_chunk_count = Vector2i(ceili(float(world.width) / chunk_size), ceili(float(world.height) / chunk_size))


func _process(delta: float) -> void:
	if world == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	_update_chunks(cam)
	_update_hover(cam)
	# Geänderte Kacheln (z. B. abgeholzter Wald) im Übersichtsbild nachziehen
	_overview_timer += delta
	if world.overview_dirty and _overview_timer >= _overview_refresh_interval:
		_overview_timer = 0.0
		world.overview_dirty = false
		overview_texture.update(world.overview_image)


# ---------------------------------------------------------------------------
# Chunk-Verwaltung (Streaming + Culling)
# ---------------------------------------------------------------------------

func _update_chunks(cam: Camera2D) -> void:
	var show_detail := cam.zoom.x >= detail_min_zoom
	_chunk_root.visible = show_detail
	_roads.visible = show_detail
	if not show_detail:
		return  # Fernansicht: nur Übersichtsbild, keine Chunks nachladen

	var view := _camera_world_rect(cam)
	var chunk_px := float(chunk_size * world.tile_size)
	# Sichtbarer Bereich in Chunk-Koordinaten, plus 1 Chunk Vorrat am Rand
	var cmin := Vector2i(floori(view.position.x / chunk_px) - 1, floori(view.position.y / chunk_px) - 1)
	var cmax := Vector2i(floori(view.end.x / chunk_px) + 1, floori(view.end.y / chunk_px) + 1)
	cmin = cmin.clamp(Vector2i.ZERO, _chunk_count - Vector2i.ONE)
	cmax = cmax.clamp(Vector2i.ZERO, _chunk_count - Vector2i.ONE)

	# Chunks deutlich ausserhalb des Sichtbereichs freigeben (1 Chunk Toleranz,
	# damit an der Grenze nicht ständig auf- und abgebaut wird)
	for c in _chunks.keys():
		if c.x < cmin.x - 1 or c.y < cmin.y - 1 or c.x > cmax.x + 1 or c.y > cmax.y + 1:
			_release_chunk(c)

	# Fehlende Chunks sammeln, die nächsten zur Bildmitte zuerst bauen
	var missing: Array[Vector2i] = []
	for cy in range(cmin.y, cmax.y + 1):
		for cx in range(cmin.x, cmax.x + 1):
			var c := Vector2i(cx, cy)
			if not _chunks.has(c):
				missing.append(c)
	if missing.is_empty():
		return
	var center := view.get_center() / chunk_px
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(center) \
				< (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(center))
	for i in mini(max_builds_per_frame, missing.size()):
		_build_chunk(missing[i])


func _build_chunk(c: Vector2i) -> void:
	var layer: TileMapLayer
	var deposits: TileMapLayer
	if _pool.is_empty():
		layer = _new_layer(tileset)
		_chunk_root.add_child(layer)
		deposits = _new_layer(deposit_tileset)
		layer.add_child(deposits)
	else:
		layer = _pool.pop_back()
		layer.clear()
		layer.visible = true
		deposits = layer.get_child(0)
		deposits.clear()

	var x0 := c.x * chunk_size
	var y0 := c.y * chunk_size
	var x1 := mini(x0 + chunk_size, world.width)
	var y1 := mini(y0 + chunk_size, world.height)
	layer.position = Vector2(x0 * world.tile_size, y0 * world.tile_size)
	var biomes := world.biomes
	var w := world.width
	for y in range(y0, y1):
		var row := y * w
		for x in range(x0, x1):
			var variant := _variant_for(x, y)
			layer.set_cell(Vector2i(x - x0, y - y0), TerrainTileset.SOURCE_ID, Vector2i(variant, biomes[row + x]))
			if world.deposit_type[row + x] != 0:
				_set_deposit_tile(deposits, Vector2i(x, y), Vector2i(x - x0, y - y0))
	_chunks[c] = layer


func _new_layer(source_set: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = source_set
	# Ein Chunk = ein Render-Quadrant -> wenige Draw-Calls
	layer.rendering_quadrant_size = chunk_size
	layer.collision_enabled = false
	layer.navigation_enabled = false
	return layer


## Setzt das Bild des Vorkommens einer Kachel (oder löscht es).
func _set_deposit_tile(deposits: TileMapLayer, cell: Vector2i, local: Vector2i) -> void:
	var d := world.get_deposit(cell)
	if d.is_empty() or d["biome_deposit"]:
		deposits.erase_cell(local)
		return
	var empty := world.regrowing.has(cell) or world.get_deposit_amount(cell) == 0
	var column := DepositTileset.COLUMN_EMPTY if empty else DepositTileset.COLUMN_NORMAL
	deposits.set_cell(local, DepositTileset.SOURCE_ID, Vector2i(column, d["index"]))


## Zeichnet eine einzelne Kachel neu (Biom und Vorkommen), falls ihr Chunk geladen ist.
func refresh_cell(cell: Vector2i) -> void:
	var c := Vector2i(floori(float(cell.x) / chunk_size), floori(float(cell.y) / chunk_size))
	if not _chunks.has(c):
		return
	var layer: TileMapLayer = _chunks[c]
	var local := cell - c * chunk_size
	layer.set_cell(local, TerrainTileset.SOURCE_ID, Vector2i(_variant_for(cell.x, cell.y), world.get_biome_index(cell)))
	_set_deposit_tile(layer.get_child(0), cell, local)


## Zeichnet alles aus den Weltdaten neu, was nicht in Chunks liegt
## (Strassen, Übersichtsbild) – z. B. nach dem Laden eines Spielstands.
func refresh_all() -> void:
	_roads.clear()
	for c in world.roads:
		set_road_visual(c, world.roads[c])
	for c in _chunks.keys():
		_release_chunk(c)
	overview_texture.update(world.overview_image)
	world.overview_dirty = false


## Strassenbild setzen: state = WorldData.ROAD_NONE / ROAD_PLANNED / ROAD_BUILT
func set_road_visual(cell: Vector2i, state: int) -> void:
	match state:
		WorldData.ROAD_BUILT:
			_roads.set_cell(cell, DepositTileset.SOURCE_ID, DepositTileset.ROAD_BUILT_COORDS)
		WorldData.ROAD_PLANNED:
			_roads.set_cell(cell, DepositTileset.SOURCE_ID, DepositTileset.ROAD_PLANNED_COORDS)
		_:
			_roads.erase_cell(cell)


func _release_chunk(c: Vector2i) -> void:
	var layer: TileMapLayer = _chunks[c]
	_chunks.erase(c)
	layer.visible = false
	_pool.append(layer)


## Deterministische "zufällige" Kachelvariante, damit die Karte nicht gekachelt wirkt.
func _variant_for(x: int, y: int) -> int:
	# Ganzzahl-Hash mit guter Durchmischung, sonst entstehen sichtbare Muster
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return (h & 0x7fffffff) % tile_variants


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	_chunks.clear()
	_pool.clear()


# ---------------------------------------------------------------------------
# Maus-Hover
# ---------------------------------------------------------------------------

func _update_hover(cam: Camera2D) -> void:
	var cell := world.world_to_cell(get_global_mouse_position())
	if not world.in_bounds(cell):
		cell = Vector2i(-1, -1)
	_cursor.visible = cell.x >= 0 and cam.zoom.x >= detail_min_zoom
	if cell != hovered_cell:
		hovered_cell = cell
		_cursor.position = Vector2(cell * world.tile_size)
		hovered_cell_changed.emit(cell)


# ---------------------------------------------------------------------------
# Hilfen
# ---------------------------------------------------------------------------

## Sichtbarer Weltbereich der Kamera in Pixeln
static func _camera_world_rect(cam: Camera2D) -> Rect2:
	var size := cam.get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - size * 0.5, size)


## Anzahl aktuell aufgebauter Chunks (für Debug-Anzeige)
func get_loaded_chunk_count() -> int:
	return _chunks.size()
