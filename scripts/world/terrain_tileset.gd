## TerrainTileset
##
## Baut zur Laufzeit ein TileSet für das Gelände aus biomes.json:
## Alle Kacheln aller Biome landen in EINEM Atlas-Bild (Spalte = Variante,
## Zeile = Biom). Eine einzige Textur erlaubt dem Renderer, die Karte in
## wenigen Draw-Calls zu zeichnen.
##
## Pro Kachel wird zuerst die PNG-Datei aus "sprites" geladen; fehlt sie,
## wird ein Platzhalter erzeugt (siehe PlaceholderArt).
class_name TerrainTileset
extends RefCounted

## ID der Atlas-Quelle im TileSet
const SOURCE_ID := 0


static func build(tile_size: int, variants: int) -> TileSet:
	var biome_count := DataDB.biomes.size()
	var atlas := Image.create_empty(tile_size * variants, tile_size * biome_count, false, Image.FORMAT_RGBA8)
	var loaded := 0
	for b in biome_count:
		var biome: Dictionary = DataDB.biomes[b]
		var sprites: Array = biome.get("sprites", [])
		for v in variants:
			# Gibt es weniger Grafiken als Varianten, werden sie wiederholt.
			var path: String = sprites[v % sprites.size()] if not sprites.is_empty() else ""
			var tile := PlaceholderArt.load_image(path)
			if tile != null:
				loaded += 1
				if tile.get_size() != Vector2i(tile_size, tile_size):
					tile.resize(tile_size, tile_size, Image.INTERPOLATE_LANCZOS)
			else:
				tile = PlaceholderArt.make_terrain_tile(biome["color"], biome.get("pattern", ""), v, tile_size)
			atlas.blit_rect(tile, Rect2i(0, 0, tile_size, tile_size), Vector2i(v * tile_size, b * tile_size))
	if loaded > 0:
		print("Terrain: %d echte Kachelgrafiken geladen, Rest Platzhalter." % loaded)

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(tile_size, tile_size)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(atlas)
	source.texture_region_size = Vector2i(tile_size, tile_size)
	# Verhindert, dass beim Skalieren Nachbarkacheln aus dem Atlas durchscheinen
	source.use_texture_padding = true
	tileset.add_source(source, SOURCE_ID)
	for b in biome_count:
		for v in variants:
			source.create_tile(Vector2i(v, b))
	return tileset
