class_name PlaceholderTileset
extends RefCounted
## Builds the terrain TileSet at runtime from terrain.json with original
## textured tiles (NaturePainter), VARIANTS per terrain so large areas do not
## look tiled. Atlas column = terrain_id * VARIANTS + variant.

const VARIANTS: int = 3


static func build(terrain_def: Dictionary) -> TileSet:
	var tile_size: int = int(terrain_def.get("tile_size", 64))
	var types: Dictionary = terrain_def.get("types", {})
	var count: int = maxi(1, types.size())
	# One extra group of columns after the terrain types: grass touching water.
	var image: Image = Image.create(tile_size * (count + 1) * VARIANTS, tile_size, false, Image.FORMAT_RGBA8)
	image.fill(Color.MAGENTA)  # visible if a terrain id has no tile
	for type_name: String in types.keys():
		var entry: Dictionary = types[type_name]
		var terrain_id: int = int(entry.get("id", 0))
		if terrain_id < 0 or terrain_id >= count:
			push_error("PlaceholderTileset: terrain id out of range for " + type_name)
			continue
		var base: Color = Color.html(String(entry.get("color", "#ff00ff")))
		for v: int in VARIANTS:
			var tile_img: Image = NaturePainter.tile(type_name, base, v, tile_size)
			image.blit_rect(tile_img, Rect2i(0, 0, tile_size, tile_size), Vector2i((terrain_id * VARIANTS + v) * tile_size, 0))

	var grass_col: Color = Color.html(String(Dictionary(types.get("grass", {})).get("color", "#6aa84f")))
	for v: int in VARIANTS:
		var shore_img: Image = NaturePainter.tile("shore", grass_col, v, tile_size)
		image.blit_rect(shore_img, Rect2i(0, 0, tile_size, tile_size), Vector2i((count * VARIANTS + v) * tile_size, 0))
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(tile_size, tile_size)
	for column: int in (count + 1) * VARIANTS:
		source.create_tile(Vector2i(column, 0))

	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(tile_size, tile_size)
	tile_set.add_source(source, 0)
	return tile_set


## Atlas coordinates of a terrain id at a cell (stable variant per cell).
## `shore` picks the sandy grass used next to water (terrain id = type count).
static func atlas_coords(terrain_id: int, cell: Vector2i, shore: bool = false, type_count: int = 3) -> Vector2i:
	var h: int = absi(cell.x * 73856093 ^ cell.y * 19349663) % VARIANTS
	var col: int = (type_count if shore else terrain_id) * VARIANTS + h
	return Vector2i(col, 0)
