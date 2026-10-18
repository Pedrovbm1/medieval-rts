extends TestSuite
## F2: NavGrid paths, group movement around a lake, dynamic obstacles, budget.


func _nav_for(map_id: String) -> NavGrid:
	var map_def: Dictionary = DataLoader.get_map(map_id)
	var terrain: Dictionary = DataLoader.get_table("terrain")
	var grid: PackedByteArray = MapGenerator.generate(map_def, terrain)
	var nav: NavGrid = NavGrid.new()
	nav.build(grid, int(map_def["width"]), int(map_def["height"]), int(terrain["tile_size"]), terrain)
	return nav


func _path_is_clear(nav: NavGrid, path: PackedVector2Array) -> bool:
	for i: int in range(1, path.size()):
		if not nav.has_los(path[i - 1], path[i], 0.0):
			return false
	return true


func _path_length(path: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func test_lake_path_goes_around() -> void:
	var nav: NavGrid = _nav_for("test_lake")
	var a: Vector2 = Vector2(30, 60) * 64.0
	var b: Vector2 = Vector2(92, 60) * 64.0
	check(not nav.is_walkable_world(Vector2(60, 60) * 64.0), "lake centre is not walkable")
	var path: PackedVector2Array = nav.find_path(a, b)
	check(path.size() >= 3, "path around the lake has corners (%d points)" % path.size())
	check(path[0] == a and path[path.size() - 1] == b, "path starts at the unit and ends at the target")
	check(_path_is_clear(nav, path), "every smoothed segment stays on walkable cells")
	check(_path_length(path) > a.distance_to(b) * 1.2, "path is longer than the straight line (goes around)")


func test_smoothing_removes_grid_zigzag() -> void:
	var nav: NavGrid = _nav_for("test_lake")
	var a: Vector2 = Vector2(10, 10) * 64.0
	var b: Vector2 = Vector2(25, 18) * 64.0
	var path: PackedVector2Array = nav.find_path(a, b)
	check(path.size() == 2, "open-ground path is a single straight segment after smoothing (%d points)" % path.size())


func test_no_corner_cutting() -> void:
	var nav: NavGrid = _nav_for("test_lake")
	nav.set_blocked([Vector2i(11, 10), Vector2i(10, 11)], true)
	check(not nav.has_los(nav.cell_center(Vector2i(10, 10)), nav.cell_center(Vector2i(11, 11)), 0.0), "LOS refuses to squeeze between two diagonal blocks")
	var path: PackedVector2Array = nav.find_path(nav.cell_center(Vector2i(10, 10)), nav.cell_center(Vector2i(11, 11)))
	check(path.size() >= 3 and _path_is_clear(nav, path), "path walks around the diagonal gap")


func test_blocked_target_uses_nearest_walkable() -> void:
	var nav: NavGrid = _nav_for("test_lake")
	var path: PackedVector2Array = nav.find_path(Vector2(30, 60) * 64.0, Vector2(60, 60) * 64.0)
	check(not path.is_empty(), "ordering into the lake still finds a path")
	check(nav.is_walkable_world(path[path.size() - 1]), "the path ends on the shore, not in the water")


func test_block_counts_stack() -> void:
	var nav: NavGrid = _nav_for("test_lake")
	var cell: Vector2i = Vector2i(5, 5)
	nav.set_blocked([cell], true)
	nav.set_blocked([cell], true)
	nav.set_blocked([cell], false)
	check(not nav.is_walkable(cell), "two obstacles on a cell: removing one keeps it blocked")
	nav.set_blocked([cell], false)
	check(nav.is_walkable(cell), "removing both unblocks it")
	var v: int = nav.version
	nav.set_blocked([Vector2i(60, 60)], true)
	check(nav.version == v, "blocking water (already solid) does not bump the version")


func test_queue_budget() -> void:
	var nav: NavGrid = _nav_for("test_open")
	var q: PathQueue = PathQueue.new()
	q.budget = 8
	q.budget_usec = 1000000
	var results: Array[int] = [0]
	for i: int in 30:
		q.request(i, Vector2(10, 10) * 64.0, Vector2(100, 100 - i) * 64.0, func(_p: PackedVector2Array) -> void: results[0] += 1)
	q.request(5, Vector2(10, 10) * 64.0, Vector2(50, 50) * 64.0, func(_p: PackedVector2Array) -> void: results[0] += 1)
	check(q.size() == 30, "a newer request from the same owner replaces the old one")
	check(q.process(nav) == 8 and results[0] == 8, "at most 8 paths per frame")
	q.process(nav)
	q.process(nav)
	q.process(nav)
	check(q.size() == 0 and results[0] == 30, "all 30 paths done after 4 frames")


func test_lake50_group_arrives() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = "lake50"
	add_to_tree(main)
	await frames(1)
	var runner: ScenarioRunner = main.get_node("ScenarioRunner")
	var world: World = main.get_node("World")
	check(runner.spawned.size() == 50, "lake50 spawns 50 units")
	Engine.time_scale = 6.0
	var worst_off_grid: int = 0
	var ticks: int = 0
	while runner.finished_at < 0.0 and runner.elapsed < 150.0:
		await physics_frames(1)
		ticks += 1
		if ticks % 15 == 0:
			var off: int = 0
			for u: Unit in runner.spawned:
				if not world.nav.is_walkable_world(u.position):
					off += 1
			worst_off_grid = maxi(worst_off_grid, off)
	Engine.time_scale = 1.0
	var east: int = 0
	for u: Unit in runner.spawned:
		if u.position.x > 80.0 * 64.0:
			east += 1
	check(runner.finished_at > 0.0, "every unit finished its move (t=%.1f s game time)" % runner.elapsed)
	check(east == 50, "50/50 units are east of the lake (got %d)" % east)
	check(runner.arrived_count == 50, "50/50 report arrived, none gave up (got %d)" % runner.arrived_count)
	check(worst_off_grid == 0, "no unit ever stood on water (worst sample %d)" % worst_off_grid)
	main.queue_free()
	await frames(1)


func test_obstacle_reroutes() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = "stress150"
	add_to_tree(main)
	await frames(1)
	var runner: ScenarioRunner = main.get_node("ScenarioRunner")
	var world: World = main.get_node("World")
	runner.def.erase("wander")
	var group: Array[Unit] = []
	for i: int in 10:
		group.append(runner.spawned[i])
	for i: int in range(10, runner.spawned.size()):
		world.remove_unit(runner.spawned[i])
	await frames(1)
	var target: Vector2 = Vector2(75, 46) * 64.0
	world.movement.command_move(group, target)
	await physics_frames(20)
	var wall: Array[Vector2i] = []
	for y: int in range(30, 62):
		wall.append(Vector2i(55, y))
	var computed_before: int = world.movement.queue.total_computed
	world.nav.set_blocked(wall, true)
	await physics_frames(12)
	check(world.movement.queue.total_computed > computed_before, "blocking the route triggers new paths")
	var clear: bool = true
	for u: Unit in group:
		if u.is_moving() and not u.waiting_path:
			var prev: Vector2 = u.position
			for i: int in range(u.path_i, u.path.size()):
				if not world.nav.has_los(prev, u.path[i], 0.0):
					clear = false
				prev = u.path[i]
	check(clear, "re-planned routes avoid the new wall")
	Engine.time_scale = 6.0
	var waited: int = 0
	while group.any(func(u: Unit) -> bool: return u.is_moving()) and waited < 2400:
		await physics_frames(1)
		waited += 1
	Engine.time_scale = 1.0
	var near: int = group.filter(func(u: Unit) -> bool: return u.position.distance_to(target) < 200.0).size()
	check(near == 10, "10/10 units reach the target around the wall (got %d)" % near)
	var inside: int = group.filter(func(u: Unit) -> bool: return not world.nav.is_walkable_world(u.position)).size()
	check(inside == 0, "no unit ends inside the wall")
	# Unblocking while moving: everyone re-plans (shorter route may exist).
	world.movement.command_move(group, Vector2(30, 46) * 64.0)
	await physics_frames(10)
	var before_unblock: int = world.movement.queue.total_computed
	world.nav.set_blocked(wall, false)
	await physics_frames(30)
	check(world.movement.queue.total_computed >= before_unblock + group.filter(func(u: Unit) -> bool: return u.is_moving()).size(),
		"removing the wall re-plans every moving unit")
	main.queue_free()
	await frames(1)


func test_stress150_cost() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = "stress150"
	add_to_tree(main)
	await frames(1)
	var runner: ScenarioRunner = main.get_node("ScenarioRunner")
	check(runner.spawned.size() == 150, "stress150 spawns 150 units")
	await physics_frames(150)
	var world: World = main.get_node("World")
	var samples: int = 0
	var total_ms: float = 0.0
	var worst_ms: float = 0.0
	var worst_queue_ms: float = 0.0
	var all_ms: Array[float] = []
	for i: int in 240:
		await physics_frames(1)
		worst_queue_ms = maxf(worst_queue_ms, world.movement.last_queue_usec / 1000.0)
		var ms: float = world.movement.last_step_usec / 1000.0
		all_ms.append(ms)
		total_ms += ms
		worst_ms = maxf(worst_ms, ms)
		samples += 1
	var moving: int = runner.spawned.filter(func(u: Unit) -> bool: return u.is_moving()).size()
	all_ms.sort()
	var median: float = all_ms[all_ms.size() / 2]
	print("  info  stress150 movement median=%.2f avg=%.2f ms worst=%.2f ms (worst path queue %.2f ms) moving=%d" % [median, total_ms / samples, worst_ms, worst_queue_ms, moving])
	check(moving > 20, "units keep moving under wander orders (%d moving)" % moving)
	check(median < 3.0, "150 units: movement step median under 3 ms on desktop (%.2f ms)" % median)
	main.queue_free()
	await frames(1)
