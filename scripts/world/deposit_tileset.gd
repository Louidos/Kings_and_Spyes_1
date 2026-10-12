## DepositTileset
##
## Baut zur Laufzeit die TileSets für Rohstoffvorkommen und Strassen.
## Vorkommen: Zeile = Vorkommen-Index, Spalte 0 = normal, Spalte 1 = leer
## (z. B. abgeerntete Beeren, die nachwachsen). Biom-Vorkommen wie Wald haben
## kein eigenes Bild – dort ist das Gelände selbst die Grafik.
## Strassen: (0,0) = fertig, (1,0) = geplant / im Bau.
## Für jede Grafik wird zuerst die PNG-Datei gesucht, sonst ein Platzhalter erzeugt.
class_name DepositTileset
extends RefCounted

const SOURCE_ID := 0
const COLUMN_NORMAL := 0
const COLUMN_EMPTY := 1
const ROAD_BUILT_COORDS := Vector2i(0, 0)
const ROAD_PLANNED_COORDS := Vector2i(1, 0)


static func build(tile_size: int) -> TileSet:
	var count := maxi(DataDB.deposits.size(), 1)
	var atlas := Image.create_empty(tile_size * 2, tile_size * count, false, Image.FORMAT_RGBA8)
	for d in DataDB.deposits:
		if d["biome_deposit"]:
			continue
		var normal := PlaceholderArt.load_image(str(d.get("sprite", "")))
		var empty: Image = null
		if normal != null:
			_fit(normal, tile_size)
			# Leere Variante aus der echten Grafik ableiten (blasser, durchscheinend)
			empty = normal.duplicate()
			_fade(empty)
			var empty_path := str(d.get("sprite_empty", ""))
			var custom_empty := PlaceholderArt.load_image(empty_path)
			if custom_empty != null:
				_fit(custom_empty, tile_size)
				empty = custom_empty
		else:
			var pattern := str(d.get("pattern", ""))
			normal = PlaceholderArt.make_deposit_icon(pattern, d["color"], tile_size, false)
			empty = PlaceholderArt.make_deposit_icon(pattern, d["color"], tile_size, true)
		var row: int = d["index"]
		atlas.blit_rect(normal, Rect2i(0, 0, tile_size, tile_size), Vector2i(COLUMN_NORMAL * tile_size, row * tile_size))
		atlas.blit_rect(empty, Rect2i(0, 0, tile_size, tile_size), Vector2i(COLUMN_EMPTY * tile_size, row * tile_size))
	return _make_tileset(atlas, tile_size, Vector2i(2, count))


static func build_roads(tile_size: int) -> TileSet:
	var road_def := DataDB.get_building("road")
	var built := PlaceholderArt.load_image(DataDB.get_building_sprite(road_def, "good"))
	var planned: Image
	if built != null:
		_fit(built, tile_size)
		planned = built.duplicate()
		_fade(planned)
	else:
		built = PlaceholderArt.make_road_tile(tile_size, false)
		planned = PlaceholderArt.make_road_tile(tile_size, true)
	var atlas := Image.create_empty(tile_size * 2, tile_size, false, Image.FORMAT_RGBA8)
	atlas.blit_rect(built, Rect2i(0, 0, tile_size, tile_size), ROAD_BUILT_COORDS * tile_size)
	atlas.blit_rect(planned, Rect2i(0, 0, tile_size, tile_size), ROAD_PLANNED_COORDS * tile_size)
	return _make_tileset(atlas, tile_size, Vector2i(2, 1))


static func _make_tileset(atlas: Image, tile_size: int, grid: Vector2i) -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(tile_size, tile_size)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(atlas)
	source.texture_region_size = Vector2i(tile_size, tile_size)
	source.use_texture_padding = true
	tileset.add_source(source, SOURCE_ID)
	for y in grid.y:
		for x in grid.x:
			source.create_tile(Vector2i(x, y))
	return tileset


static func _fit(img: Image, tile_size: int) -> void:
	if img.get_size() != Vector2i(tile_size, tile_size):
		img.resize(tile_size, tile_size, Image.INTERPOLATE_LANCZOS)


## Macht ein Bild blass und halb durchsichtig (für "leer" bzw. "geplant").
static func _fade(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var grey := c.get_luminance()
			img.set_pixel(x, y, Color(lerpf(c.r, grey, 0.6), lerpf(c.g, grey, 0.6), lerpf(c.b, grey, 0.6), c.a * 0.5))
