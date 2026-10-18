class_name PlaceholderTileset
extends RefCounted
## Builds a flat-colour TileSet at runtime from terrain.json.
## Zero binary assets: replaced by real art in F9 without touching World.

const BORDER_PX: int = 2


## One atlas column per terrain type, ordered by its "id".
static func build(terrain_def: Dictionary) -> TileSet:
	var tile_size: int = int(terrain_def.get("tile_size", 64))
	var types: Dictionary = terrain_def.get("types", {})
	var count: int = maxi(1, types.size())

	var image: Image = Image.create(tile_size * count, tile_size, false, Image.FORMAT_RGBA8)
	image.fill(Color.MAGENTA)  # visible if a terrain id has no colour
	for type_name: String in types.keys():
		var entry: Dictionary = types[type_name]
		var terrain_id: int = int(entry.get("id", 0))
		if terrain_id < 0 or terrain_id >= count:
			push_error("PlaceholderTileset: terrain id out of range for " + type_name)
			continue
		var base: Color = Color.html(String(entry.get("color", "#ff00ff")))
		var origin: Vector2i = Vector2i(terrain_id * tile_size, 0)
		image.fill_rect(Rect2i(origin, Vector2i(tile_size, tile_size)), base)
		# Thin darker border so camera pan/zoom is readable on a flat colour.
		var edge: Color = base.darkened(0.18)
		image.fill_rect(Rect2i(origin, Vector2i(tile_size, BORDER_PX)), edge)
		image.fill_rect(Rect2i(origin, Vector2i(BORDER_PX, tile_size)), edge)

	var texture: ImageTexture = ImageTexture.create_from_image(image)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(tile_size, tile_size)
	for column: int in count:
		source.create_tile(Vector2i(column, 0))

	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = Vector2i(tile_size, tile_size)
	tile_set.add_source(source, 0)
	return tile_set
