extends TestSuite
## F9 defence (from the gameplay review): walls traced in a line, gates that
## close on enemies, a Town Center that shoots, the AI's peace window, armies
## that reach and break walls, and the Town Center roof changing with the era.

var main: Node
var world: World
var scen: ScenarioRunner


func _open(scenario: String, ai: Dictionary = {}) -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = scenario
	if not ai.is_empty():
		main.ai_override = ai
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")
	scen = main.get_node("ScenarioRunner")


func _close() -> void:
	Engine.time_scale = 1.0
	main.queue_free()
	await frames(2)


func _wait_until(cond: Callable, max_game_s: float) -> void:
	var t0: float = scen.elapsed
	while not cond.call() and scen.elapsed - t0 < max_game_s:
		await physics_frames(1)


func _villager() -> Unit:
	for u: Unit in world.units:
		if u.owner_id == 0 and u.can_gather():
			return u
	return null


func test_a_wall_line_is_built_and_blocks() -> void:
	await _open("eco12")
	var v: Unit = _villager()
	GameState.add_resource(0, "wood", 500)
	var a: Vector2i = world.world_to_cell(v.position) + Vector2i(3, -4)
	var b: Vector2i = a + Vector2i(0, 9)
	var cells: Array[Vector2i] = World.line_cells(a, b)
	check(cells.size() == 10 and cells[0] == a and cells[9] == b, "a line from A to B has every cell in between (%d)" % cells.size())
	var wood: int = GameState.get_resource(0, "wood")
	var made: Array[Building] = world.construction.start_wall_line(0, "palisade", cells, [v] as Array[Unit])
	check(made.size() == 10, "10 palisade foundations go up (%d)" % made.size())
	check(GameState.get_resource(0, "wood") == wood - 50, "each segment costs 5 wood (paid %d)" % (wood - GameState.get_resource(0, "wood")))
	check(v.task is BuildTask and (v.task as BuildTask).queue.size() == 9, "the builder queues the other 9 segments")
	check(not world.nav.is_walkable(cells[5]), "a wall cell is blocked for walking")
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return made.all(func(w: Building) -> bool: return not is_instance_valid(w) or w.is_complete()), 240.0)
	Engine.time_scale = 1.0
	check(made.all(func(w: Building) -> bool: return is_instance_valid(w) and w.is_complete()), "all 10 segments get built")
	GameState.add_resource(0, "wood", -GameState.get_resource(0, "wood"))
	GameState.add_resource(0, "wood", 12)
	var more: Array[Building] = world.construction.start_wall_line(0, "palisade", World.line_cells(b + Vector2i(1, 0), b + Vector2i(6, 0)), [v] as Array[Unit])
	check(more.size() == 2, "with 12 wood only 2 of 6 segments are placed (%d)" % more.size())
	await _close()


func test_b_gate_opens_for_us_and_closes_on_enemies() -> void:
	await _open("arena")
	var gate: Building = world.place_building("gate", 0, Vector2i(60, 60))
	gate.add_progress(1.0)
	check(gate.is_open and world.nav.is_walkable(Vector2i(60, 60)), "a new gate stands open and is walkable")
	var foe: Unit = world.spawn_unit("militia", 1, world.cell_center(Vector2i(63, 60)))
	foe.stance = "passive"
	Engine.time_scale = 4.0
	await _wait_until(func() -> bool: return not gate.is_open, 10.0)
	check(not gate.is_open and not world.nav.is_walkable(Vector2i(60, 60)), "an enemy 3 cells away closes it and the cell blocks")
	foe.position = world.cell_center(Vector2i(80, 60))
	await _wait_until(func() -> bool: return gate.is_open, 15.0)
	Engine.time_scale = 1.0
	check(gate.is_open and world.nav.is_walkable(Vector2i(60, 60)), "once the enemy is gone it reopens")
	var wall: Building = world.place_building("palisade", 0, Vector2i(60, 62))
	GameState.add_resource(0, "wood", 200)
	var wood: int = GameState.get_resource(0, "wood")
	var g2: Building = world.construction.start_construction(0, "gate", Vector2i(60, 62), [] as Array[Unit])
	check(g2 != null and not is_instance_valid(wall) or (g2 != null and not world.buildings.has(wall)), "a gate can replace an own wall segment")
	check(GameState.get_resource(0, "wood") == wood - 30 + 5, "the replaced segment refunds its wood")
	await _close()


func test_c_town_center_shoots_raiders_but_not_a_push() -> void:
	await _open("arena")
	var tc: Building = world.place_building("town_center", 0, Vector2i(60, 60))
	check(not Dictionary(tc.data.get("combat", {})).is_empty(), "the Town Center has arrows")
	var raiders: Array[Unit] = []
	for i: int in 4:
		var r: Unit = world.spawn_unit("militia", 1, tc.position + Vector2(220 + (i % 2) * 30, (i / 2) * 30))
		world.behavior.assign(r, AttackTask.new(r, world, tc, true))
		raiders.append(r)
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return raiders.all(func(u: Unit) -> bool: return u.is_dead or not world.units.has(u)), 160.0)
	var dead: int = raiders.filter(func(u: Unit) -> bool: return u.is_dead or not world.units.has(u)).size()
	check(dead == 4, "4 militia hitting the Town Center die to its arrows (%d dead)" % dead)
	var push: Array[Unit] = []
	for i: int in 16:
		push.append(world.spawn_unit("swordsman", 1, tc.position + Vector2(200 + (i % 4) * 30, -60 + (i / 4) * 30)))
	world.combat.attack_move(push, tc.position)
	var tc_id: int = tc.get_instance_id()
	await _wait_until(func() -> bool: return instance_from_id(tc_id) == null, 240.0)
	Engine.time_scale = 1.0
	check(instance_from_id(tc_id) == null, "16 swordsmen still raze it")
	await _close()


func test_d_ai_waits_for_its_first_attack_minute() -> void:
	await _open("skirmish", {1: "normal"})
	var ai: AIController = main.ais[0]
	var first_min: float = float(ai.diff.get("first_attack_min", 0))
	check(first_min >= 10.0, "Normal waits at least 10 minutes before attacking (%d)" % int(first_min))
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return ai.elapsed >= (first_min - 0.5) * 60.0, first_min * 60.0)
	Engine.time_scale = 1.0
	check(ai.attack_log.is_empty(), "no attack order before minute %d (%d orders)" % [int(first_min), ai.attack_log.size()])
	await _close()


func test_e_army_reaches_a_walled_base_and_breaks_in() -> void:
	await _open("arena")
	var tc: Building = world.place_building("town_center", 1, Vector2i(70, 60))
	var ring: Array[Vector2i] = []
	for x: int in range(66, 77):
		ring.append(Vector2i(x, 56))
		ring.append(Vector2i(x, 66))
	for y: int in range(57, 66):
		ring.append(Vector2i(66, y))
		ring.append(Vector2i(76, y))
	for c: Vector2i in ring:
		world.place_building("palisade", 1, c)
	var path: PackedVector2Array = world.nav.find_path(world.cell_center(Vector2i(50, 60)), tc.position)
	var end_cell: Vector2i = world.world_to_cell(path[path.size() - 1]) if path.size() > 0 else Vector2i(-1, -1)
	var inside: bool = end_cell.x > 66 and end_cell.x < 76 and end_cell.y > 56 and end_cell.y < 66
	var near_wall: bool = ring.any(func(c: Vector2i) -> bool: return (c - end_cell).length() <= 1.5)
	check(path.size() > 1 and not inside and near_wall, "with the base walled in, the path still leads up to the wall (ends at %s)" % [end_cell])
	var army: Array[Unit] = []
	for i: int in 12:
		army.append(world.spawn_unit("swordsman", 0, world.cell_center(Vector2i(50 + (i % 4), 58 + (i / 4)))))
	for i: int in 2:
		army.append(world.spawn_unit("ram", 0, world.cell_center(Vector2i(48, 59 + i * 2))))
	world.combat.attack_move(army, tc.position)
	Engine.time_scale = 8.0
	var tc_id: int = tc.get_instance_id()
	await _wait_until(func() -> bool: return instance_from_id(tc_id) == null, 400.0)
	Engine.time_scale = 1.0
	var walls_left: int = world.buildings.filter(func(b: Building) -> bool: return b.owner_id == 1 and b.is_wall()).size()
	check(walls_left < ring.size(), "the army breaks through the palisade (%d of %d segments left)" % [walls_left, ring.size()])
	check(instance_from_id(tc_id) == null, "and razes the Town Center behind it")
	await _close()


func test_f_town_center_roof_changes_with_the_era() -> void:
	PlaceholderArt._texture = null
	PlaceholderArt.load_or_build()
	var e1: Rect2 = PlaceholderArt.building_region("town_center", 0, 1)
	var e4: Rect2 = PlaceholderArt.building_region("town_center", 0, 4)
	check(e1 != e4 and e4.size != Vector2.ZERO, "the Town Center has an Era IV look")
	var img: Image = PlaceholderArt.texture().get_image()
	check(img.get_region(Rect2i(e1)).get_data() != img.get_region(Rect2i(e4)).get_data(), "and it differs from Era I")
	for id: String in ["palisade", "stone_wall", "gate", "gate_open"]:
		check(PlaceholderArt.building_region(id, 0).size == Vector2(64, 64), "%s has a 64 px sprite" % id)


func test_g_tutorial_has_a_wall_mission() -> void:
	var steps: Array = DataLoader.get_table("tutorial").get("steps", [])
	check(steps.size() == 7 and String(Dictionary(steps[6]).get("id", "")) == "walls", "mission 6 asks for a palisade")
	await _open("tutorial")
	var tut: TutorialDirector = main.tutorial
	tut._go(6)
	check(tut.current().get("id") == "walls", "the director reaches the wall mission")
	var v: Unit = _villager()
	var a: Vector2i = world.world_to_cell(v.position) + Vector2i(4, 2)
	world.construction.start_wall_line(0, "palisade", World.line_cells(a, a + Vector2i(3, 0)), [v] as Array[Unit])
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return tut.done, 200.0)
	Engine.time_scale = 1.0
	check(tut.done, "building 4 segments finishes the tutorial")
	await _close()
