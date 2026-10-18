class_name World
extends Node2D
## Owns the terrain grid and every entity on the map: units, buildings,
## resource nodes and the tree field (forest cells hold wood as plain data,
## not nodes, so thousands of trees cost nothing to draw or update).

const TERRAIN_SOURCE_ID: int = 0
const UNIT_SCENE: PackedScene = preload("res://scenes/units/unit.tscn")

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var entities: Node2D = $Entities
@onready var movement: MovementSystem = $MovementSystem
@onready var behavior: BehaviorSystem = $BehaviorSystem
@onready var construction: ConstructionSystem = $ConstructionSystem
@onready var combat: CombatSystem = $CombatSystem
@onready var vision: VisionSystem = $VisionSystem

var map_id: String = ""
var map_def: Dictionary = {}
var map_width: int = 0
var map_height: int = 0
var tile_size: int = 64
var terrain_grid: PackedByteArray = PackedByteArray()
var map_size_px: Vector2 = Vector2.ZERO
var units: Array[Unit] = []
var buildings: Array[Building] = []
var resource_nodes: Array[ResourceNode] = []
var nav: NavGrid = NavGrid.new()
var economy: EconomySystem = EconomySystem.new()
var tech: TechSystem = TechSystem.new()
## Dead units waiting for reuse, by type: type_id -> Array[Unit] (out of the tree).
var unit_pool: Dictionary = {}
var units_created: int = 0

var _grass_id: int = 0
var _forest_id: int = 2
## cell key (y * width + x) -> wood left, only for trees already touched.
var _tree_amount: Dictionary = {}
var _tree_default: float = 100.0


## Generates and paints the map described by data/maps/<map_id>.json.
func build_from_map(p_map_id: String) -> void:
	map_id = p_map_id
	map_def = DataLoader.get_map(map_id)
	var terrain_def: Dictionary = DataLoader.get_table("terrain")
	if map_def.is_empty() or terrain_def.is_empty():
		push_error("World: missing map '%s' or terrain table" % map_id)
		return

	map_width = int(map_def.get("width", 120))
	map_height = int(map_def.get("height", 120))
	tile_size = int(terrain_def.get("tile_size", 64))
	map_size_px = Vector2(map_width * tile_size, map_height * tile_size)
	var types: Dictionary = terrain_def.get("types", {})
	_grass_id = int(Dictionary(types.get("grass", {})).get("id", 0))
	_forest_id = int(Dictionary(types.get("forest", {})).get("id", 2))
	_tree_default = float(DataLoader.get_entry("resources", "tree").get("amount", 100))

	terrain_grid = MapGenerator.generate(map_def, terrain_def)
	terrain_layer.tile_set = PlaceholderTileset.build(terrain_def)
	_paint_terrain()
	nav.build(terrain_grid, map_width, map_height, tile_size, terrain_def)
	movement.setup(nav, units)
	economy.setup(self)
	tech.setup(self)
	behavior.setup(self)
	construction.setup(self)
	combat.setup(self)
	vision.setup(self)
	EventBus.map_generated.emit(map_width, map_height, tile_size)


# ---------------------------------------------------------------- terrain

func get_terrain_id(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
		return -1
	return terrain_grid[cell.y * map_width + cell.x]


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / tile_size), floori(world_pos.y / tile_size))


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size)


func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * tile_size, Vector2(tile_size, tile_size))


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


# ---------------------------------------------------------------- trees

func is_tree(cell: Vector2i) -> bool:
	return get_terrain_id(cell) == _forest_id


func tree_amount(cell: Vector2i) -> float:
	if not is_tree(cell):
		return 0.0
	return float(_tree_amount.get(cell.y * map_width + cell.x, _tree_default))


## Takes up to `want` wood from a tree cell. A tree that runs out becomes grass
## and stops blocking paths.
func take_from_tree(cell: Vector2i, want: float) -> float:
	if not is_tree(cell):
		return 0.0
	var key: int = cell.y * map_width + cell.x
	var left: float = float(_tree_amount.get(key, _tree_default))
	var got: float = minf(want, left)
	left -= got
	if left <= 0.0001:
		_tree_amount.erase(key)
		terrain_grid[key] = _grass_id
		terrain_layer.set_cell(cell, TERRAIN_SOURCE_ID, Vector2i(_grass_id, 0))
		nav.set_terrain_walkable(cell, true)
		EventBus.tree_depleted.emit(cell)
	else:
		_tree_amount[key] = left
	return got


## Nearest tree within `max_cells` that a villager can stand next to.
## Returns Vector2i(-1, -1) if none.
func find_tree_near(world_pos: Vector2, max_cells: int) -> Vector2i:
	var origin: Vector2i = world_to_cell(world_pos)
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for ring: int in range(0, max_cells + 1):
		if best.x >= 0 and float(ring) > sqrt(best_d) + 1.0:
			break
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				var c: Vector2i = origin + Vector2i(dx, dy)
				if is_tree(c) and _has_open_neighbour(c):
					var d: float = Vector2(dx, dy).length_squared()
					if d < best_d:
						best_d = d
						best = c
	return best


func _has_open_neighbour(cell: Vector2i) -> bool:
	for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if nav.is_walkable(cell + off):
			return true
	return false


# ---------------------------------------------------------------- units

func spawn_unit(type_id: String, player_id: int, world_pos: Vector2) -> Unit:
	var unit: Unit = null
	var pool: Array = unit_pool.get(type_id, [])
	if not pool.is_empty():
		unit = pool.pop_back()
	else:
		unit = UNIT_SCENE.instantiate() as Unit
		units_created += 1
	unit.setup(type_id, player_id, world_pos)
	entities.add_child(unit)
	units.append(unit)
	unit.died.connect(_on_unit_died)
	EventBus.unit_spawned.emit(unit)
	economy.refresh_population()
	return unit


## Takes a unit out of the match. Dead units linger as a corpse (CombatSystem)
## before recycling; others go straight back to the pool.
func remove_unit(unit: Unit, as_corpse: bool = false) -> void:
	if not units.has(unit):
		return
	units.erase(unit)
	movement.stop(unit)
	behavior.release(unit)
	EventBus.unit_removed.emit(unit)
	economy.refresh_population()
	if as_corpse:
		combat.add_corpse(unit)
	else:
		recycle_unit(unit)


## Puts a unit node back in the pool (removed from the tree, state cleared).
func recycle_unit(unit: Unit) -> void:
	if unit.get_parent() == entities:
		entities.remove_child(unit)
	unit.reset_for_pool()
	var pool: Array = unit_pool.get(unit.unit_type, [])
	pool.append(unit)
	unit_pool[unit.unit_type] = pool


## Re-applies tech modifiers to every unit and building of a player.
func refresh_stats(player_id: int) -> void:
	for u: Unit in units:
		if u.owner_id == player_id:
			u.recompute_stats()
	for b: Building in buildings:
		if b.owner_id == player_id:
			b.recompute_stats()


func pooled_units() -> int:
	var n: int = 0
	for key: String in unit_pool.keys():
		n += (unit_pool[key] as Array).size()
	return n


func _exit_tree() -> void:
	# Pooled nodes live outside the tree: free them with the match.
	if combat != null:
		combat.clear()
	for key: String in unit_pool.keys():
		for u: Unit in unit_pool[key]:
			u.free()
	unit_pool.clear()


func _on_unit_died(unit: Unit) -> void:
	var carcass: String = String(Dictionary(unit.data.get("animal", {})).get("carcass", ""))
	if carcass != "":
		spawn_carcass(carcass, unit.position)
	remove_unit(unit, true)


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


## Closest unit of any owner within radius (for orders on animals/enemies).
func pick_any_unit(world_pos: Vector2, radius: float) -> Unit:
	var best: Unit = null
	var best_dist: float = INF
	for unit: Unit in units:
		var dist: float = unit.position.distance_to(world_pos) - unit.radius
		if dist <= radius and dist < best_dist:
			best = unit
			best_dist = dist
	return best


func units_in_rect(rect: Rect2, player_id: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit: Unit in units:
		if unit.owner_id == player_id and not unit.is_animal() and rect.grow(unit.radius).has_point(unit.position):
			result.append(unit)
	return result


# ---------------------------------------------------------------- buildings

func place_building(type_id: String, player_id: int, origin_cell: Vector2i) -> Building:
	var b: Building = Building.new()
	b.setup(type_id, player_id, origin_cell, tile_size)
	b.recompute_stats()
	entities.add_child(b)
	buildings.append(b)
	if not b.walkable:
		nav.set_blocked(b.cells(), true)
	b.destroyed.connect(remove_building)
	EventBus.building_added.emit(b)
	economy.refresh_population()
	return b


func remove_building(b: Building) -> void:
	if not buildings.has(b):
		return
	buildings.erase(b)
	if not b.walkable:
		nav.set_blocked(b.cells(), false)
	EventBus.building_removed.emit(b)
	b.queue_free()
	economy.refresh_population()


func building_at(world_pos: Vector2) -> Building:
	for b: Building in buildings:
		if b.rect().has_point(world_pos):
			return b
	return null


## True if a footprint fits: every cell walkable terrain, not blocked, no node,
## no building (walkable farms included), no unit standing there (except
## `ignore`, e.g. the builders) and inside the map with a 1-cell margin.
func can_place(type_id: String, origin_cell: Vector2i, ignore: Array[Unit] = []) -> bool:
	var fp_arr: Array = DataLoader.get_entry("buildings", type_id).get("footprint", [2, 2])
	var fp: Vector2i = Vector2i(int(fp_arr[0]), int(fp_arr[1]))
	if origin_cell.x < 1 or origin_cell.y < 1 or origin_cell.x + fp.x > map_width - 1 or origin_cell.y + fp.y > map_height - 1:
		return false
	var area: Rect2 = Rect2(Vector2(origin_cell) * tile_size, Vector2(fp) * tile_size)
	for y: int in fp.y:
		for x: int in fp.x:
			if not nav.is_walkable(origin_cell + Vector2i(x, y)):
				return false
	for b: Building in buildings:
		if b.rect().intersects(area):
			return false
	for n: ResourceNode in resource_nodes:
		if n.rect().intersects(area):
			return false
	for u: Unit in units:
		if not ignore.has(u) and area.grow(-2.0).has_point(u.position):
			return false
	return true


## The gather task a villager should get for a point (rally points, AI).
func task_for_point(unit: Unit, point: Vector2) -> UnitTask:
	var n: ResourceNode = node_at(point, 16.0)
	if n != null and not n.is_depleted():
		return GatherTask.for_node(unit, self, n)
	var b: Building = building_at(point)
	if b != null and b.owner_id == unit.owner_id and not b.gather_info().is_empty() and b.is_complete():
		return GatherTask.for_farm(unit, self, b)
	var cell: Vector2i = world_to_cell(point)
	if is_tree(cell):
		return GatherTask.for_tree(unit, self, cell)
	return null


## Nearest origin cell (spiral search) where `type_id` fits near `near`, leaving
## a free ring around it so paths stay open. Vector2i(-1, -1) if none.
func find_building_spot(type_id: String, near: Vector2, max_ring: int = 20) -> Vector2i:
	var fp_arr: Array = DataLoader.get_entry("buildings", type_id).get("footprint", [2, 2])
	var fp: Vector2i = Vector2i(int(fp_arr[0]), int(fp_arr[1]))
	var origin: Vector2i = world_to_cell(near) - fp / 2
	for ring: int in range(0, max_ring + 1):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				var c: Vector2i = origin + Vector2i(dx, dy)
				if can_place(type_id, c) and _ring_clear(c, fp):
					return c
	return Vector2i(-1, -1)


func _ring_clear(origin_cell: Vector2i, fp: Vector2i) -> bool:
	for x: int in range(-1, fp.x + 1):
		for y: int in [-1, fp.y]:
			if not nav.is_walkable(origin_cell + Vector2i(x, y)):
				return false
	for y: int in range(0, fp.y):
		for x: int in [-1, fp.x]:
			if not nav.is_walkable(origin_cell + Vector2i(x, y)):
				return false
	return true


# ---------------------------------------------------------------- resource nodes

func place_resource(type_id: String, origin_cell: Vector2i) -> ResourceNode:
	var n: ResourceNode = ResourceNode.new()
	n.setup(type_id, origin_cell, tile_size)
	_add_node(n)
	return n


func spawn_carcass(type_id: String, world_pos: Vector2) -> ResourceNode:
	var n: ResourceNode = ResourceNode.new()
	n.setup(type_id, world_to_cell(world_pos), tile_size)
	n.place_free(world_pos)
	_add_node(n)
	return n


func _add_node(n: ResourceNode) -> void:
	entities.add_child(n)
	resource_nodes.append(n)
	if not n.walkable:
		nav.set_blocked(n.cells(), true)
	n.depleted.connect(remove_resource)


func remove_resource(n: ResourceNode) -> void:
	if not resource_nodes.has(n):
		return
	resource_nodes.erase(n)
	if not n.walkable:
		nav.set_blocked(n.cells(), false)
	n.queue_free()


func node_at(world_pos: Vector2, slack: float = 0.0) -> ResourceNode:
	for n: ResourceNode in resource_nodes:
		if n.rect().grow(slack).has_point(world_pos):
			return n
	return null


## Nearest non-depleted node with the given subtype within max_dist of world_pos.
func find_node_near(subtype: String, world_pos: Vector2, max_dist: float) -> ResourceNode:
	var best: ResourceNode = null
	var best_d: float = max_dist
	for n: ResourceNode in resource_nodes:
		if n.subtype != subtype or n.is_depleted():
			continue
		var d: float = n.position.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = n
	return best


# ---------------------------------------------------------------- interaction

## Walkable point next to `rect` closest to `from` (where a worker stands).
func approach_point(rect: Rect2, from: Vector2) -> Vector2:
	var c0: Vector2i = world_to_cell(rect.position)
	var c1: Vector2i = world_to_cell(rect.end - Vector2(1, 1))
	var best: Vector2 = rect.get_center()
	var best_d: float = INF
	for y: int in range(c0.y - 1, c1.y + 2):
		for x: int in range(c0.x - 1, c1.x + 2):
			if x >= c0.x and x <= c1.x and y >= c0.y and y <= c1.y:
				continue
			var c: Vector2i = Vector2i(x, y)
			if not nav.is_walkable(c):
				continue
			# Stand at the edge of the free cell that touches the rect.
			var p: Vector2 = cell_center(c)
			p = p.clamp(rect.position - Vector2(tile_size * 0.3, tile_size * 0.3), rect.end + Vector2(tile_size * 0.3, tile_size * 0.3))
			var d: float = p.distance_squared_to(from)
			if d < best_d:
				best_d = d
				best = p
	return best


## Distance from a unit's edge to a rect's edge (0 when touching/inside).
static func distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var clamped: Vector2 = point.clamp(rect.position, rect.end)
	return point.distance_to(clamped)


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
