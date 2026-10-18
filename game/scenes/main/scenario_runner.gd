class_name ScenarioRunner
extends Node
## Sets up a scenario from data/scenarios.json: map resources, buildings,
## units, gather assignments, camera, and optional scripted orders (tests and
## device benchmarks). Logs "[REALM] scenario ..." lines in debug builds.

signal all_arrived(seconds: float)

var world: World
var camera: CameraController
var scenario_id: String = ""
var def: Dictionary = {}
var spawned: Array[Unit] = []
var placed: Array[Building] = []
var starts: Array[Vector2] = []
var elapsed: float = 0.0
var arrived_count: int = 0
var finished_at: float = -1.0

var _pending_orders: Array[Dictionary] = []
var _wander_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _report_timer: float = 0.0
var _ordered: bool = false
## player -> next free spawn slot index around its start
var _slot_index: Dictionary = {}


func start(p_id: String, p_world: World, p_camera: CameraController) -> void:
	scenario_id = p_id
	world = p_world
	camera = p_camera
	# Copy: data tables are shared and must stay read-only.
	def = DataLoader.get_entry("scenarios", scenario_id).duplicate(true)
	_rng.seed = 4242
	var tile: float = float(world.tile_size)

	for s: Vector2i in MapPopulator.starts_of(world.map_def):
		starts.append(world.cell_center(s))
	if bool(def.get("populate", false)):
		MapPopulator.populate(world, world.map_def)

	var origin: Vector2 = world.map_size_px * 0.5
	if bool(def.get("spawn_near_center", false)):
		origin = world.find_open_area(origin, 3)

	# Optional starting stockpile override per player: {"0": {"wood": 600}}.
	var stock: Dictionary = def.get("resources", {})
	for key: Variant in stock.keys():
		var bag: Dictionary = stock[key]
		for res: String in bag.keys():
			GameState.add_resource(int(key), res, int(bag[res]) - GameState.get_resource(int(key), res))

	for b: Variant in def.get("buildings", []):
		_place_building(b)

	var row: Array[Dictionary] = []
	for group: Variant in def.get("units", []):
		var g: Dictionary = group
		if g.has("block"):
			_spawn_block(g, tile)
		elif g.has("near"):
			_spawn_near_start(g)
		else:
			for i: int in int(g.get("count", 1)):
				row.append(g)
	_spawn_row(row, origin)

	_apply_assignments()

	var cam: Variant = def.get("camera", "spawn")
	if cam is Array:
		camera.center_on(Vector2(float(cam[0]), float(cam[1])) * tile)
	elif String(cam) == "start" and not starts.is_empty():
		camera.center_on(starts[GameState.PLAYER_HUMAN])
	else:
		camera.center_on(origin)
	if def.has("zoom"):
		camera.zoom_at(camera.get_viewport_rect().size * 0.5, float(def["zoom"]))
	for order: Variant in def.get("auto_orders", []):
		_pending_orders.append(order)
	for unit: Unit in spawned:
		unit.arrived.connect(_on_arrived)
	_log("start units=%d buildings=%d nodes=%d" % [spawned.size(), placed.size(), world.resource_nodes.size()])


func start_of(player_id: int) -> Vector2:
	if player_id >= 0 and player_id < starts.size():
		return starts[player_id]
	return world.map_size_px * 0.5


# ------------------------------------------------------------------ setup helpers

func _place_building(b: Dictionary) -> void:
	var type_id: String = String(b.get("type", "house"))
	var player: int = int(b.get("player", 0))
	var home: Vector2 = start_of(player)
	var cell: Vector2i = Vector2i(-1, -1)
	if String(b.get("at", "")) == "start":
		var fp_arr: Array = DataLoader.get_entry("buildings", type_id).get("footprint", [3, 3])
		cell = world.world_to_cell(home) - Vector2i(int(fp_arr[0]) / 2, int(fp_arr[1]) / 2)
	else:
		var near: Vector2 = _near_point(String(b.get("near", "start")), home)
		cell = world.find_building_spot(type_id, near)
	if cell.x < 0:
		push_warning("Scenario: no spot for " + type_id)
		return
	placed.append(world.place_building(type_id, player, cell))


## Where a building "near X" should go: between the resource and the start.
func _near_point(what: String, home: Vector2) -> Vector2:
	match what:
		"wood":
			var tree: Vector2i = world.find_tree_near(home, 30)
			if tree.x >= 0:
				var t: Vector2 = world.cell_center(tree)
				return t + (home - t).normalized() * world.tile_size * 2.5
		"gold", "stone":
			var n: ResourceNode = world.find_node_near(what, home, 4000.0)
			if n != null:
				return n.position + (home - n.position).normalized() * world.tile_size * 3.0
	return home + Vector2(world.tile_size * 4, 0).rotated(_rng.randf() * TAU)


func _spawn_block(group: Dictionary, tile: float) -> void:
	var count: int = int(group.get("count", 1))
	var spacing: float = float(DataLoader.rule("movement", "formation_spacing_px", 40))
	var block: Array = group["block"]
	var start: Vector2 = Vector2(float(block[0]), float(block[1])) * tile
	var cols: int = int(block[2])
	for i: int in count:
		var pos: Vector2 = start + Vector2(i % cols, i / cols) * spacing
		spawned.append(world.spawn_unit(String(group.get("type", "militia")), int(group.get("player", 0)), pos))


## Units around their player's start, on free cells just outside the Town Center.
func _spawn_near_start(group: Dictionary) -> void:
	var player: int = int(group.get("player", 0))
	var home: Vector2 = start_of(player)
	var slots: Array[Vector2] = Formation.walkable_slots(home, 40, 44.0, world.nav)
	for i: int in int(group.get("count", 1)):
		var idx: int = int(_slot_index.get(player, 0))
		_slot_index[player] = idx + 1
		var pos: Vector2 = slots[mini(idx, slots.size() - 1)]
		spawned.append(world.spawn_unit(String(group.get("type", "villager")), player, pos))


## Places single units in one centred row (sandbox).
func _spawn_row(row: Array[Dictionary], origin: Vector2) -> void:
	var step: float = 72.0
	var row_start: float = origin.x - step * (row.size() - 1) * 0.5
	for i: int in row.size():
		var g: Dictionary = row[i]
		spawned.append(world.spawn_unit(String(g.get("type", "militia")), int(g.get("player", 0)), Vector2(row_start + step * i, origin.y)))


## "assign": [{"count": 4, "gather": "wood"}, ...] for the first villagers of player 0.
func _apply_assignments() -> void:
	var villagers: Array[Unit] = spawned.filter(func(u: Unit) -> bool: return u.can_gather() and u.owner_id == GameState.PLAYER_HUMAN)
	var next: int = 0
	var home: Vector2 = start_of(GameState.PLAYER_HUMAN)
	var farms: Array[Building] = placed.filter(func(b: Building) -> bool: return not b.gather_info().is_empty())
	var farm_i: int = 0
	for a: Variant in def.get("assign", []):
		var what: String = String(a.get("gather", "wood"))
		for i: int in int(a.get("count", 1)):
			if next >= villagers.size():
				return
			var v: Unit = villagers[next]
			next += 1
			var task: UnitTask = null
			match what:
				"wood":
					var cell: Vector2i = world.find_tree_near(home, 30)
					if cell.x >= 0:
						task = GatherTask.for_tree(v, world, cell)
				"farm":
					if farm_i < farms.size():
						task = GatherTask.for_farm(v, world, farms[farm_i])
						farm_i += 1
				_:
					var n: ResourceNode = world.find_node_near(what, home, 4000.0)
					if n != null:
						task = GatherTask.for_node(v, world, n)
			if task != null:
				world.behavior.assign(v, task)


# ------------------------------------------------------------------ scripted runtime

func _physics_process(delta: float) -> void:
	if world == null:
		return
	elapsed += delta
	for order: Dictionary in _pending_orders.duplicate():
		if elapsed >= float(order.get("after_s", 0.0)):
			_pending_orders.erase(order)
			var target: Array = order["target"]
			world.movement.command_move(spawned, Vector2(float(target[0]), float(target[1])) * float(world.tile_size))
			_ordered = true
			_log("order target=(%d,%d)" % [int(target[0]), int(target[1])])
	if def.has("wander"):
		_wander(delta)
	if bool(def.get("report_arrival", false)) and _ordered:
		_report_timer += delta
		if _report_timer >= 1.0:
			_report_timer = 0.0
			var moving: int = spawned.filter(func(u: Unit) -> bool: return u.is_moving()).size()
			_log("progress t=%.1f arrived=%d moving=%d" % [elapsed, arrived_count, moving])
			if moving == 0 and finished_at < 0.0:
				finished_at = elapsed
				_log("done t=%.1f arrived=%d/%d" % [elapsed, arrived_count, spawned.size()])
				all_arrived.emit(elapsed)


func _wander(delta: float) -> void:
	var w: Dictionary = def["wander"]
	_wander_timer += delta
	if _wander_timer < float(w.get("every_s", 2.0)):
		return
	_wander_timer = 0.0
	var region: Array = w.get("region", [10, 10, 110, 110])
	var batch: int = int(w.get("batch", 10))
	var alive: Array[Unit] = spawned.filter(func(u: Unit) -> bool: return is_instance_valid(u) and not u.is_dead)
	var start: int = _rng.randi_range(0, maxi(0, alive.size() - batch))
	var group: Array[Unit] = []
	for i: int in range(start, mini(start + batch, alive.size())):
		group.append(alive[i])
	var target: Vector2 = Vector2(_rng.randf_range(float(region[0]), float(region[2])), _rng.randf_range(float(region[1]), float(region[3]))) * float(world.tile_size)
	world.movement.command_move(group, target)


func _on_arrived(_unit: Unit) -> void:
	arrived_count += 1


func _log(msg: String) -> void:
	if OS.is_debug_build():
		print("[REALM] scenario %s %s" % [scenario_id, msg])
