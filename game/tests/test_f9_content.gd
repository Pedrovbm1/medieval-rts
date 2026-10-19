extends TestSuite
## F9: curated symmetric maps (fair, connected, selectable) and the guided
## tutorial (5 missions completed through the real game systems).

var main: Node
var world: World
var scen: ScenarioRunner

const CURATED: Array[String] = ["valle_rio", "bosque_cerrado", "tierras_doradas"]


func _open(scenario: String, map_id: String = "") -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = scenario
	main.map_override = map_id
	if scenario == "skirmish":
		main.ai_override = {1: "easy"}
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")
	scen = main.get_node("ScenarioRunner")


func _close() -> void:
	Engine.time_scale = 1.0
	main.queue_free()
	await frames(2)


func _count_near(start: Vector2i, radius_cells: float) -> Dictionary:
	var out: Dictionary = {}
	var center: Vector2 = world.cell_center(start)
	var r: float = radius_cells * world.tile_size
	for n: ResourceNode in world.resource_nodes:
		if n.position.distance_to(center) <= r:
			out[n.resource_type] = int(out.get(n.resource_type, 0)) + 1
	for u: Unit in world.units:
		if u.owner_id < 0 and u.position.distance_to(center) <= r:
			out["animal:" + u.unit_type] = int(out.get("animal:" + u.unit_type, 0)) + 1
	return out


func test_a_curated_maps_are_fair_and_connected() -> void:
	var listed: Array = DataLoader.get_entry("scenarios", "_maps").get("list", [])
	for id: String in CURATED:
		check(listed.has(id), "%s is offered in the map menu" % id)
		var def: Dictionary = DataLoader.get_map(id)
		check(not def.is_empty() and String(def.get("symmetry", "")) == "point", "%s is a point-symmetric map" % id)
		await _open("skirmish", id)
		check(world.map_id == id, "%s loads from the menu choice" % id)
		var w: int = world.map_width
		var h: int = world.map_height
		var mismatched: int = 0
		for y: int in h:
			for x: int in w:
				if world.terrain_grid[y * w + x] != world.terrain_grid[(h - 1 - y) * w + (w - 1 - x)]:
					mismatched += 1
		check(mismatched == 0, "%s terrain is mirrored (%d cells differ)" % [id, mismatched])
		var starts: Array[Vector2i] = MapPopulator.starts_of(def)
		var a: Dictionary = _count_near(starts[0], 26.0)
		var b: Dictionary = _count_near(starts[1], 26.0)
		check(a == b and a.get("gold_mine", 0) >= 2, "%s gives both players the same resources nearby %s" % [id, a])
		var from: Vector2 = world.cell_center(world.nav.nearest_walkable(starts[0] + Vector2i(4, 4)))
		var to: Vector2 = world.cell_center(world.nav.nearest_walkable(starts[1] - Vector2i(4, 4)))
		var path: PackedVector2Array = world.nav.find_path(from, to)
		check(path.size() > 1 and path[path.size() - 1].distance_to(to) < world.tile_size * 2.0, "%s: the two bases are connected by land" % id)
		await _close()


func test_b_tutorial_five_missions() -> void:
	await _open("tutorial")
	var tut: TutorialDirector = main.tutorial
	check(tut != null and tut.index == 0, "the tutorial starts at mission 1")
	if tut == null:
		await _close()
		return
	check(main.get_node("Hud").find_child("TutorialPanel", true, false) != null, "the tip panel is on screen")
	var sel: SelectionController = main.get_node("SelectionController")
	var villagers: Array[Unit] = []
	for u: Unit in world.units:
		if u.owner_id == 0 and u.can_gather():
			villagers.append(u)
	sel.set_selection([villagers[0]] as Array[Unit])
	await physics_frames(2)
	check(tut.current().get("id") == "move", "selecting a villager completes step 1")
	sel.order_move(villagers[0].position + Vector2(260, 0))
	Engine.time_scale = 4.0
	await _wait_until(func() -> bool: return tut.current().get("id") != "move", 30.0)
	check(tut.current().get("id") == "gather", "moving it completes mission 1")
	var bush: ResourceNode = world.find_node_near("berries", villagers[0].position, 3000.0)
	for v: Unit in villagers:
		world.behavior.assign(v, GatherTask.for_node(v, world, bush))
	await _wait_until(func() -> bool: return tut.current().get("id") != "gather", 90.0)
	check(tut.current().get("id") == "house", "delivering food completes mission 2")
	var tc: Building = tut._own_tc()
	var spot: Vector2i = world.find_building_spot("house", tc.position)
	world.construction.start_construction(0, "house", spot, villagers)
	await _wait_until(func() -> bool: return tut.current().get("id") != "house", 120.0)
	check(tut.current().get("id") == "train", "building a house completes mission 3")
	world.construction.enqueue(tc, "villager")
	await _wait_until(func() -> bool: return tut.current().get("id") != "train", 90.0)
	check(tut.current().get("id") == "barracks", "training a villager completes mission 4; mission 5 asks for barracks")
	var bspot: Vector2i = world.find_building_spot("barracks", tc.position)
	var barracks: Building = world.construction.start_construction(0, "barracks", bspot, villagers)
	check(barracks != null, "the tutorial gives enough wood for a barracks")
	await _wait_until(func() -> bool: return tut.current().get("id") != "barracks", 200.0)
	check(tut.current().get("id") == "militia", "a finished barracks asks for 2 militia")
	world.construction.enqueue(barracks, "militia")
	world.construction.enqueue(barracks, "militia")
	await _wait_until(func() -> bool: return tut.current().get("id") != "militia", 120.0)
	check(tut.current().get("id") == "fight", "2 militia trained: the raiders come")
	check(tut.enemies().size() == 2, "mission 6 brings raiders")
	var squad: Array[Unit] = world.units.filter(func(u: Unit) -> bool: return u.owner_id == 0 and u.unit_type == "militia")
	check(squad.size() == 4, "the player has 4 militia (2 trained + 2 given)")
	world.combat.attack_move(squad, tut.enemies()[0].position)
	await _wait_until(func() -> bool: return tut.current().get("id") != "fight", 90.0)
	check(tut.current().get("id") == "walls", "beating the raiders leads to the wall mission")
	GameState.add_resource(0, "wood", 100)
	var origin: Vector2i = world.world_to_cell(villagers[0].position)
	var line: Array[Vector2i] = []
	for dy: int in range(-12, 13):
		for dx: int in range(-12, 9):
			var a: Vector2i = origin + Vector2i(dx, dy)
			var cells: Array[Vector2i] = World.line_cells(a, a + Vector2i(3, 0))
			if cells.all(func(c: Vector2i) -> bool: return world.can_place("palisade", c, villagers)):
				line = cells
				break
		if not line.is_empty():
			break
	var made: Array[Building] = world.construction.start_wall_line(0, "palisade", line, villagers)
	check(made.size() == 4, "4 palisade foundations placed for the last mission (%d)" % made.size())
	await _wait_until(func() -> bool: return tut.done, 200.0)
	check(tut.done, "4 palisade segments finish the tutorial")
	check(not main.rules.ended, "the tutorial does not trigger a defeat or victory")
	await _close()


func test_c_every_text_row_has_both_languages() -> void:
	var f: FileAccess = FileAccess.open("res://data/i18n/ui.csv", FileAccess.READ)
	var bad: Array[String] = []
	var count: int = 0
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() == 1 and row[0] == "":
			continue
		count += 1
		if row.size() != 3 or row[1].strip_edges() == "" or row[2].strip_edges() == "":
			bad.append(row[0])
	check(count > 100 and bad.is_empty(), "all %d text rows have key, Spanish and English (bad: %s)" % [count, bad])
	check(tr("TUT_1_TIP").ends_with("recuadro."), "a tip with commas is read whole")


func _wait_until(cond: Callable, max_game_s: float) -> void:
	var t0: float = scen.elapsed
	while not cond.call() and scen.elapsed - t0 < max_game_s:
		await physics_frames(1)
