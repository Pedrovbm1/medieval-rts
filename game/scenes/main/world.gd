class_name World
extends Node2D
## Owns the terrain grid and every entity on the map: units, buildings,
## resource nodes and the tree field (forest cells hold wood as plain data,
## not nodes, so thousands of trees cost nothing to draw or update).

const TERRAIN_SOURCE_ID: int = 0
const UNIT_SCENE: PackedScene = preload("res://scenes/units/unit.tscn")

const TERRAIN_Z: int = -10

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

# --- simulation identity and clock (lockstep multiplayer, replays) ---
## Physics ticks simulated so far and the game seconds they add up to. Every
## device of a networked match runs the same ticks, so these match too.
var tick: int = 0
var sim_time: float = 0.0
## The match's random source for anything that changes the game (never the
## global randf): seeded by the lobby so every device rolls the same numbers.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Simulation ids handed out in creation order (units, buildings and nodes
## share one counter); 0 = never assigned.
var _next_sim_id: int = 1
var _unit_by_id: Dictionary = {}
var _building_by_id: Dictionary = {}
var _node_by_id: Dictionary = {}

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

	rng.seed = int(map_def.get("seed", 1)) * 31 + 7
	terrain_grid = MapGenerator.generate(map_def, terrain_def)
	terrain_layer.tile_set = PlaceholderTileset.build(terrain_def)
	terrain_layer.z_index = TERRAIN_Z  # below ground buildings (farms, z -1)
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


# ---------------------------------------------------------------- simulation clock

## Runs before every child system in the same physics tick (parents first).
func _physics_process(delta: float) -> void:
	if map_width == 0:
		return
	tick += 1
	sim_time += delta


## Lockstep / replay mode: the same inputs must give the same world on every
## device, so the path queue computes a fixed number of routes per tick.
func set_deterministic(on: bool) -> void:
	movement.set_deterministic(on)


## Re-seeds the match RNG (the lobby's shared seed).
func set_match_seed(seed_value: int) -> void:
	rng.seed = seed_value


func _assign_sim_id(node: Node2D) -> void:
	node.set("sim_id", _next_sim_id)
	_next_sim_id += 1


func unit_by_id(id: int) -> Unit:
	var u: Variant = _unit_by_id.get(id)
	return u if u is Unit and is_instance_valid(u) else null


func building_by_id(id: int) -> Building:
	var b: Variant = _building_by_id.get(id)
	return b if b is Building and is_instance_valid(b) else null


func node_by_id(id: int) -> ResourceNode:
	var n: Variant = _node_by_id.get(id)
	return n if n is ResourceNode and is_instance_valid(n) else null


## A number that sums up the whole simulation: tick, stockpiles and every
## unit / building / node with its exact position, HP and job. Two devices
## with the same hash at the same tick are running the same match; the first
## different hash tells the turn a desync began. Order is the arrays' order,
## which is itself part of the state.
func state_hash() -> int:
	var acc: Array = [tick, units.size(), buildings.size(), resource_nodes.size()]
	for p: int in [0, 1]:
		for res: String in GameState.RESOURCE_IDS:
			acc.append(GameState.get_resource(p, res))
		acc.append(GameState.pop_used(p))
		acc.append(GameState.era_of(p))
	for u: Unit in units:
		acc.append(u.sim_id)
		acc.append(u.owner_id)
		acc.append(u.position.x)
		acc.append(u.position.y)
		acc.append(u.hp)
		acc.append(u.carry_amount)
		acc.append(u.task.kind if u.task != null else "")
		acc.append(u.goal.x if u.goal != Vector2.INF else 0.0)
		acc.append(u.goal.y if u.goal != Vector2.INF else 0.0)
	for b: Building in buildings:
		acc.append(b.sim_id)
		acc.append(b.owner_id)
		acc.append(b.hp)
		acc.append(b.build_progress)
		acc.append(b.queue.size())
		acc.append(b.train_elapsed)
		acc.append(b.garrison.size())
	for n: ResourceNode in resource_nodes:
		acc.append(n.sim_id)
		acc.append(n.amount)
	return acc.hash()


## The same state as readable lines, one per entity (desync debugging: diff
## two devices' dumps and the first differing line names the culprit).
func state_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	out.append("tick=%d time=%.5f units=%d buildings=%d nodes=%d" % [tick, sim_time, units.size(), buildings.size(), resource_nodes.size()])
	for p: int in [0, 1]:
		out.append("p%d f=%d w=%d g=%d s=%d pop=%d era=%d" % [p, GameState.get_resource(p, "food"), GameState.get_resource(p, "wood"), GameState.get_resource(p, "gold"), GameState.get_resource(p, "stone"), GameState.pop_used(p), GameState.era_of(p)])
	for u: Unit in units:
		out.append("u%d %s o=%d pos=(%.4f,%.4f) hp=%d spd=%.2f carry=%.3f task=%s goal=(%.1f,%.1f) path=%d/%d wait=%s" % [u.sim_id, u.unit_type, u.owner_id, u.position.x, u.position.y, u.hp, u.speed_px, u.carry_amount, u.task.kind if u.task != null else "-", u.goal.x if u.goal != Vector2.INF else 0.0, u.goal.y if u.goal != Vector2.INF else 0.0, u.path_i, u.path.size(), str(u.waiting_path)])
	for b: Building in buildings:
		out.append("b%d %s o=%d hp=%d prog=%.3f queue=%d train=%.3f garrison=%d" % [b.sim_id, b.building_type, b.owner_id, b.hp, b.build_progress, b.queue.size(), b.train_elapsed, b.garrison.size()])
	for n: ResourceNode in resource_nodes:
		out.append("n%d %s amount=%.3f" % [n.sim_id, n.resource_type, n.amount])
	return out


# ---------------------------------------------------------------- terrain

## Tile to draw for a cell: grass next to water becomes shore.
func _terrain_coords(terrain_id: int, cell: Vector2i) -> Vector2i:
	var water_id: int = int(Dictionary(Dictionary(DataLoader.get_table("terrain").get("types", {})).get("water", {})).get("id", 1))
	var shore: bool = false
	if terrain_id == _grass_id:
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if get_terrain_id(cell + o) == water_id:
				shore = true
				break
	return PlaceholderTileset.atlas_coords(terrain_id, cell, shore, Dictionary(DataLoader.get_table("terrain").get("types", {})).size())


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
		terrain_layer.set_cell(cell, TERRAIN_SOURCE_ID, _terrain_coords(_grass_id, cell))
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
	_assign_sim_id(unit)
	_unit_by_id[unit.sim_id] = unit
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
	_unit_by_id.erase(unit.sim_id)
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
	if unit.relic:
		unit.relic = false
		drop_relic(unit.position)
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
	b.world = self
	_assign_sim_id(b)
	_building_by_id[b.sim_id] = b
	b.recompute_stats()
	if player_id >= 0:
		# Scenario / save placement skips can_place: a neutral building
		# (the trade post) in the way gives up its spot.
		for other: Building in buildings.duplicate():
			if other.owner_id < 0 and other.rect().intersects(b.rect()):
				remove_building(other)
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
	eject_all(b)
	if b.relics > 0:
		# The vault falls: its relics spill out around it, up for grabs.
		var n: int = b.relics
		b.relics = 0
		for i: int in n:
			var ang: float = TAU * float(i) / n
			drop_relic(approach_point(b.rect(), b.position + Vector2.from_angle(ang) * 400.0) + Vector2.from_angle(ang) * 20.0)
	buildings.erase(b)
	_building_by_id.erase(b.sim_id)
	if not b.walkable:
		nav.set_blocked(b.cells(), false)
	elif b.is_gate() and not b.is_open:
		nav.set_gate(b.cells(), b.owner_id, false)
	if b.hp <= 0 and b.is_complete():
		add_rubble(b.rect())
		if (b.is_wall() or b.is_gate()) and b.owner_id >= 0:
			EventBus.wall_breached.emit(b.owner_id, b.position)
	EventBus.building_removed.emit(b)
	b.queue_free()
	economy.refresh_population()


## Dark stones where a building fell; they fade over rules walls.rubble_s.
func add_rubble(rect: Rect2) -> void:
	var r: Rubble = Rubble.new()
	r.setup(rect, float(DataLoader.rule("walls", "rubble_s", 90.0)))
	entities.add_child(r)


# ------------------------------------------------------------------ garrison

## Shelters `unit` inside `b`: hidden, out of World.units (nobody targets or
## selects it), still counted for population. Remembers its gather/build task
## so it can go back to work when it comes out.
func garrison_unit(unit: Unit, b: Building, p_resume: GatherTask = null) -> bool:
	if not b.can_garrison(unit) or not units.has(unit):
		return false
	var resume: UnitTask = p_resume
	if resume == null:
		resume = unit.task
		if resume is BuildTask:
			resume = (resume as BuildTask).resume
		elif resume is GarrisonTask:
			resume = (resume as GarrisonTask).resume
		elif not (resume is GatherTask):
			resume = null
	units.erase(unit)
	movement.stop(unit)
	behavior.release(unit)
	unit.selected = false
	unit.visible = false
	unit.attack_move = false
	unit.garrisoned_in = b
	unit.position = b.position
	b.garrison.append(unit)
	if resume != null:
		b.garrison_resume[unit] = resume
	EventBus.unit_removed.emit(unit)
	EventBus.garrison_changed.emit(b)
	economy.refresh_population()
	b.queue_redraw()
	return true


## Brings `unit` out next to the building and sends it back to what it was
## doing (gathering) if that still makes sense.
func eject(unit: Unit, b: Building) -> void:
	if not b.garrison.has(unit):
		return
	b.garrison.erase(unit)
	var toward: Vector2 = b.rally_point if b.rally_point != Vector2.INF else b.position + Vector2(0, b.rect().size.y)
	unit.position = approach_point(b.rect(), toward) + Vector2(rng.randf_range(-10.0, 10.0), rng.randf_range(-6.0, 6.0))
	unit.visible = true
	unit.garrisoned_in = null
	units.append(unit)
	EventBus.unit_spawned.emit(unit)
	var old: UnitTask = b.garrison_resume.get(unit)
	b.garrison_resume.erase(unit)
	if old is GatherTask:
		var again: GatherTask = GatherTask.resume_like(old as GatherTask, unit, self)
		if again != null:
			behavior.assign(unit, again)
	EventBus.garrison_changed.emit(b)
	economy.refresh_population()
	b.queue_redraw()


func eject_all(b: Building) -> void:
	for u: Unit in b.garrison.duplicate():
		eject(u, b)


# ------------------------------------------------------------------ relics

## Relics on the map at the start (on the ground + carried + stored never
## changes); 0 = the map has none and the relic victory is off.
var relic_total: int = 0


func recount_relics() -> void:
	var n: int = 0
	for r: ResourceNode in resource_nodes:
		if r.is_relic():
			n += 1
	for u: Unit in units:
		if u.relic:
			n += 1
	for b: Building in buildings:
		n += b.relics
		for u: Unit in b.garrison:
			if u.relic:
				n += 1
	relic_total = n


## Relics stored in a player's finished monasteries.
func relics_held(player_id: int) -> int:
	var n: int = 0
	for b: Building in buildings:
		if b.owner_id == player_id and b.is_complete():
			n += b.relics
	return n


## Nearest finished monastery (relic vault) of a player.
func nearest_vault(player_id: int, from: Vector2) -> Building:
	var best: Building = null
	var best_d: float = INF
	for b: Building in buildings:
		if b.owner_id == player_id and b.is_complete() and bool(b.data.get("relic_vault", false)):
			var d: float = from.distance_squared_to(b.position)
			if d < best_d:
				best_d = d
				best = b
	return best


## Nearest finished market of a player (caravans trade from it).
func nearest_market(player_id: int, from: Vector2) -> Building:
	var best: Building = null
	var best_d: float = INF
	for b: Building in buildings:
		if b.owner_id == player_id and b.is_complete() and b.data.has("market"):
			var d: float = from.distance_squared_to(b.position)
			if d < best_d:
				best_d = d
				best = b
	return best


## The neutral trade post nearest to `from` (null on maps without one).
func nearest_trade_post(from: Vector2) -> Building:
	var best: Building = null
	var best_d: float = INF
	for b: Building in buildings:
		if bool(b.data.get("trade_post", false)):
			var d: float = from.distance_squared_to(b.position)
			if d < best_d:
				best_d = d
				best = b
	return best


## A player's finished wonder, or null.
func wonder_of(player_id: int) -> Building:
	for b: Building in buildings:
		if b.owner_id == player_id and b.is_complete() and bool(b.data.get("wonder", false)):
			return b
	return null


## Puts a relic on the ground (a fallen monk, a razed monastery).
func drop_relic(world_pos: Vector2) -> ResourceNode:
	var cell: Vector2i = nav.nearest_walkable(world_to_cell(world_pos))
	return spawn_carcass("relic", cell_center(cell))


## Every unit of a player inside any building (bell state, saves, tests).
func garrisoned_units(player_id: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for b: Building in buildings:
		if b.owner_id == player_id:
			out.append_array(b.garrison)
	return out


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
	if n != null and n.is_relic():
		return null
	if n != null and not n.is_depleted():
		return GatherTask.for_node(unit, self, n)
	var b: Building = building_at(point)
	if b != null and b.owner_id == unit.owner_id and not b.gather_info().is_empty() and b.is_complete():
		return GatherTask.for_farm(unit, self, b)
	var cell: Vector2i = world_to_cell(point)
	if is_tree(cell):
		return GatherTask.for_tree(unit, self, cell)
	return null


## Cells of a straight wall from `a` to `b` (Bresenham), both ends included.
static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx: int = absi(b.x - a.x)
	var dy: int = -absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var err: int = dx + dy
	var p: Vector2i = a
	for _i: int in 4096:
		out.append(p)
		if p == b:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return out


## Own wall segment standing exactly on this cell (for gates replacing it).
func wall_at(owner: int, c: Vector2i) -> Building:
	for b: Building in buildings:
		if b.owner_id == owner and b.cell == c and b.footprint == Vector2i.ONE and b.is_wall() and not b.is_gate():
			return b
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
	_assign_sim_id(n)
	_node_by_id[n.sim_id] = n
	entities.add_child(n)
	resource_nodes.append(n)
	if not n.walkable:
		nav.set_blocked(n.cells(), true)
	n.depleted.connect(remove_resource)


func remove_resource(n: ResourceNode) -> void:
	if not resource_nodes.has(n):
		return
	resource_nodes.erase(n)
	_node_by_id.erase(n.sim_id)
	if not n.walkable:
		nav.set_blocked(n.cells(), false)
	n.queue_free()


func node_at(world_pos: Vector2, slack: float = 0.0) -> ResourceNode:
	for n: ResourceNode in resource_nodes:
		if n.rect().grow(slack).has_point(world_pos):
			return n
	return null


## Closest non-depleted node whose rect, grown by `slack`, contains the point.
func nearest_node_at(world_pos: Vector2, slack: float) -> ResourceNode:
	var best: ResourceNode = null
	var best_d: float = INF
	for n: ResourceNode in resource_nodes:
		if n.is_depleted() or n.is_relic() or not n.rect().grow(slack).has_point(world_pos):
			continue
		var d: float = n.position.distance_squared_to(world_pos)
		if d < best_d:
			best_d = d
			best = n
	return best


## Closest tree cell whose centre is within `radius` px of the point, or (-1, -1).
func tree_near_point(world_pos: Vector2, radius: float) -> Vector2i:
	var c: Vector2i = world_to_cell(world_pos)
	var r: int = ceili(radius / tile_size)
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = radius * radius
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var cell: Vector2i = c + Vector2i(dx, dy)
			if not is_tree(cell):
				continue
			var d: float = cell_center(cell).distance_squared_to(world_pos)
			if d <= best_d:
				best_d = d
				best = cell
	return best


## First building whose rect, grown by `slack`, contains the point.
func building_near(world_pos: Vector2, slack: float) -> Building:
	var exact: Building = building_at(world_pos)
	if exact != null:
		return exact
	for b: Building in buildings:
		if b.rect().grow(slack).has_point(world_pos):
			return b
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


## Saved tree amounts (cell key -> wood left), for SaveGame.
func tree_amounts_dict() -> Dictionary:
	var out: Dictionary = {}
	for key: int in _tree_amount.keys():
		out[str(key)] = _tree_amount[key]
	return out


## Applies a saved terrain grid (trees cut since the map was generated) and
## the partial tree amounts. Cells that became grass are freed for paths.
func apply_terrain(saved: PackedByteArray, trees: Dictionary) -> void:
	if saved.size() == terrain_grid.size():
		for i: int in saved.size():
			if saved[i] != terrain_grid[i]:
				terrain_grid[i] = saved[i]
				var cell: Vector2i = Vector2i(i % map_width, i / map_width)
				terrain_layer.set_cell(cell, TERRAIN_SOURCE_ID, _terrain_coords(saved[i], cell))
				nav.set_terrain_walkable(cell, saved[i] != _forest_id)
	_tree_amount.clear()
	for key: Variant in trees.keys():
		_tree_amount[int(key)] = float(trees[key])
	nav.consume_changes()


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
			terrain_layer.set_cell(Vector2i(x, y), TERRAIN_SOURCE_ID, _terrain_coords(terrain_id, Vector2i(x, y)))
