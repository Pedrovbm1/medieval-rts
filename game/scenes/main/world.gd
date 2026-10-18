class_name World
extends Node2D
## Owns the terrain grid and paints it into a TileMapLayer.
## Generation is delegated to MapGenerator; visuals to PlaceholderTileset.

const TERRAIN_SOURCE_ID: int = 0

@onready var terrain_layer: TileMapLayer = $TerrainLayer

var map_width: int = 0
var map_height: int = 0
var tile_size: int = 64
var terrain_grid: PackedByteArray = PackedByteArray()
var map_size_px: Vector2 = Vector2.ZERO


func _ready() -> void:
	build_from_map(GameState.current_map_id)


## Generates and paints the map described by data/maps/<map_id>.json.
func build_from_map(map_id: String) -> void:
	var map_def: Dictionary = DataLoader.get_map(map_id)
	var terrain_def: Dictionary = DataLoader.get_table("terrain")
	if map_def.is_empty() or terrain_def.is_empty():
		push_error("World: missing map '%s' or terrain table" % map_id)
		return

	map_width = int(map_def.get("width", 120))
	map_height = int(map_def.get("height", 120))
	tile_size = int(terrain_def.get("tile_size", 64))
	map_size_px = Vector2(map_width * tile_size, map_height * tile_size)

	terrain_grid = MapGenerator.generate(map_def, terrain_def)
	terrain_layer.tile_set = PlaceholderTileset.build(terrain_def)
	_paint_terrain()
	EventBus.map_generated.emit(map_width, map_height, tile_size)


func get_terrain_id(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
		return -1
	return terrain_grid[cell.y * map_width + cell.x]


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / tile_size), floori(world_pos.y / tile_size))


func _paint_terrain() -> void:
	terrain_layer.clear()
	for y: int in map_height:
		for x: int in map_width:
			var terrain_id: int = terrain_grid[y * map_width + x]
			terrain_layer.set_cell(Vector2i(x, y), TERRAIN_SOURCE_ID, Vector2i(terrain_id, 0))
