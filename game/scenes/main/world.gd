class_name World
extends Node2D
## Owns the terrain grid and every entity on the map.
## Generation is delegated to MapGenerator; visuals to PlaceholderTileset.

const TERRAIN_SOURCE_ID: int = 0
const UNIT_SCENE: PackedScene = preload("res://scenes/units/unit.tscn")

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var entities: Node2D = $Entities
@onready var movement: MovementSystem = $MovementSystem

var map_width: int = 0
var map_height: int = 0
var tile_size: int = 64
var terrain_grid: PackedByteArray = PackedByteArray()
var map_size_px: Vector2 = Vector2.ZERO
var units: Array[Unit] = []
var nav: NavGrid = NavGrid.new()
var _grass_id: int = 0


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
	var grass: Dictionary = Dictionary(terrain_def.get("types", {})).get("grass", {})
	_grass_id = int(grass.get("id", 0))

	terrain_grid = MapGenerator.generate(map_def, terrain_def)
	terrain_layer.tile_set = PlaceholderTileset.build(terrain_def)
	_paint_terrain()
	nav.build(terrain_grid, map_width, map_height, tile_size, terrain_def)
	movement.setup(nav, units)
	EventBus.map_generated.emit(map_width, map_height, tile_size)


func get_terrain_id(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
		return -1
	return terrain_grid[cell.y * map_width + cell.x]


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / tile_size), floori(world_pos.y / tile_size))


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size)


## Finds the grass cell closest to `near` whose whole (2*margin+1)^2 block is grass.
func find_open_area(near: Vector2, margin: int) -> Vector2:
	var origin: Vector2i = world_to_cell(near)
	for ring: int in range(0, maxi(map_width, map_height)):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				var cell: Vector2i = origin + Vector2i(dx, dy)
				if _block_is_grass(cell, margin):
					return cell_center(cell)
	return near


func spawn_unit(type_id: String, player_id: int, world_pos: Vector2) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.setup(type_id, player_id, world_pos)
	entities.add_child(unit)
	units.append(unit)
	return unit


func remove_unit(unit: Unit) -> void:
	units.erase(unit)
	movement.stop(unit)
	unit.queue_free()


## Closest unit of `player_id` within `radius` of world_pos, or null.
func pick_unit(world_pos: Vector2, radius: float, player_id: int) -> Unit:
	var best: Unit = null
	var best_dist: float = INF
	for unit: Unit in units:
		if unit.owner_id != player_id:
			continue
		var dist: float = unit.position.distance_to(world_pos) - unit.radius
		if dist <= radius and dist < best_dist:
			best = unit
			best_dist = dist
	return best


func units_in_rect(rect: Rect2, player_id: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit: Unit in units:
		if unit.owner_id == player_id and rect.grow(unit.radius).has_point(unit.position):
			result.append(unit)
	return result


func _block_is_grass(center: Vector2i, margin: int) -> bool:
	for dy: int in range(-margin, margin + 1):
		for dx: int in range(-margin, margin + 1):
			if get_terrain_id(center + Vector2i(dx, dy)) != _grass_id:
				return false
	return true


func _paint_terrain() -> void:
	terrain_layer.clear()
	for y: int in map_height:
		for x: int in map_width:
			var terrain_id: int = terrain_grid[y * map_width + x]
			terrain_layer.set_cell(Vector2i(x, y), TERRAIN_SOURCE_ID, Vector2i(terrain_id, 0))
