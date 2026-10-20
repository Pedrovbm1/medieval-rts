extends TestSuite
## F4: build mode with the finger, live validation, construction, cancel
## refunds, production queues, population and rally points.

var main: Node
var world: World
var scen: ScenarioRunner
var pointer: PointerManager
var sel: SelectionController
var cam: CameraController
var hud: Hud
var place: PlacementController
var t: int = 5000000


func _open(scenario: String) -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = scenario
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")
	scen = main.get_node("ScenarioRunner")
	pointer = main.get_node("PointerManager")
	sel = main.get_node("SelectionController")
	cam = main.get_node("CameraController")
	hud = main.get_node("Hud")
	place = main.get_node("World/PlacementController")


func _close() -> void:
	Engine.time_scale = 1.0
	main.queue_free()
	await frames(2)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	pointer.process_event(e, t)


func _drag(index: int, pos: Vector2) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	pointer.process_event(e, t)


func _tap(pos: Vector2) -> void:
	t += 1000
	_touch(0, pos, true)
	t += 80
	_touch(0, pos, false)


func _box(from_pos: Vector2, to_pos: Vector2) -> void:
	t += 1000
	_touch(0, from_pos, true)
	t += 400
	pointer._dispatch(pointer.classifier.update(t))
	_drag(0, to_pos)
	t += 50
	_touch(0, to_pos, false)


func _villagers() -> Array[Unit]:
	return world.units.filter(func(u: Unit) -> bool: return u.owner_id == 0 and u.can_gather())


## Selects `units` with a hold-and-drag box over them, like a player would.
func _box_select(units: Array[Unit]) -> void:
	var pos: Array[Vector2] = []
	for u: Unit in units:
		pos.append(u.position)
	cam.center_on(Formation.centroid(pos))
	await frames(1)
	var a: Vector2 = cam.world_to_screen(pos[0])
	var b: Vector2 = a
	for p: Vector2 in pos:
		a = a.min(cam.world_to_screen(p))
		b = b.max(cam.world_to_screen(p))
	_box(a - Vector2(28, 28), b + Vector2(28, 28))


## Full finger flow: Build button -> type -> tap spot -> ✓. Returns the foundation.
func _finger_build(type_id: String, near: Vector2) -> Building:
	hud.build_button.pressed.emit()
	await frames(1)
	if not hud.type_buttons.has(type_id):
		return null
	(hud.type_buttons[type_id] as Button).pressed.emit()
	await frames(1)
	var spot: Vector2i = world.find_building_spot(type_id, near)
	var fp_arr: Array = DataLoader.get_entry("buildings", type_id)["footprint"]
	var center: Vector2 = (Vector2(spot) + Vector2(int(fp_arr[0]), int(fp_arr[1])) * 0.5) * world.tile_size
	cam.center_on(center)
	await frames(1)
	_tap(cam.world_to_screen(center))
	await frames(1)
	if hud.confirm_button == null:
		return null
	var before: int = world.buildings.size()
	hud.confirm_button.pressed.emit()
	await frames(1)
	if world.buildings.size() == before:
		return null
	return world.buildings[world.buildings.size() - 1]


func _wait_complete(b: Building, max_game_s: float) -> void:
	var t0: float = scen.elapsed
	while is_instance_valid(b) and not b.is_complete() and scen.elapsed - t0 < max_game_s:
		await physics_frames(1)


func test_a_live_validation() -> void:
	await _open("build4min")
	var cs: ConstructionSystem = world.construction
	var mine: ResourceNode = world.find_node_near("gold", scen.start_of(0), 9999.0)
	check(cs.placement_error(0, "house", mine.cell) == "occupied", "cannot build on a gold mine")
	var tree: Vector2i = world.find_tree_near(scen.start_of(0), 30)
	check(cs.placement_error(0, "house", tree) == "occupied", "cannot build on trees")
	var v: Unit = _villagers()[0]
	var on_unit: Vector2i = world.world_to_cell(v.position)
	check(cs.placement_error(0, "house", on_unit) == "occupied", "cannot build on top of a unit")
	check(cs.placement_error(0, "house", on_unit, [v]) == "" or cs.placement_error(0, "house", on_unit, [v]) == "occupied", "builders themselves can be ignored")
	var free: Vector2i = world.find_building_spot("house", scen.start_of(0) + Vector2(400, 0))
	check(cs.placement_error(0, "house", free) == "", "a free spot is valid")
	check(cs.placement_error(0, "town_center", free) == "era", "a second Town Center needs Era III")
	GameState.add_resource(0, "wood", -GameState.get_resource(0, "wood"))
	check(cs.placement_error(0, "house", free) == "cost", "no wood -> invalid (cost)")
	# Ghost turns red/green live while dragging.
	await _box_select(_villagers())
	GameState.add_resource(0, "wood", 600)
	hud.build_button.pressed.emit()
	await frames(1)
	(hud.type_buttons["house"] as Button).pressed.emit()
	await frames(1)
	check(place.active, "choosing House enters build mode with a ghost")
	cam.center_on(mine.position)
	await frames(1)
	_tap(cam.world_to_screen(mine.position))
	check(place.error == "occupied" and hud.confirm_button.disabled, "ghost over the mine is red and ✓ is disabled")
	var good: Vector2 = (Vector2(free) + Vector2.ONE) * world.tile_size
	cam.center_on(good)
	await frames(1)
	_tap(cam.world_to_screen(good))
	check(place.error == "" and not hud.confirm_button.disabled, "ghost on free grass is green and ✓ is enabled")
	hud.cancel_place_button.pressed.emit()
	check(not place.active and GameState.get_resource(0, "wood") == 600, "✕ leaves build mode without spending")
	await _close()


func test_b_full_base_under_four_minutes() -> void:
	await _open("build4min")
	var start: float = scen.elapsed
	var home: Vector2 = scen.start_of(0)
	var vs: Array[Unit] = _villagers()
	var team_a: Array[Unit] = [vs[0], vs[1]]
	var team_b: Array[Unit] = [vs[2], vs[3]]
	Engine.time_scale = 4.0
	var plan_a: Array = [["house", home + Vector2(-300, 250)], ["house", home + Vector2(-300, -250)], ["barracks", home + Vector2(400, 300)]]
	var tree: Vector2 = world.cell_center(world.find_tree_near(home, 30))
	var plan_b: Array = [["farm", home + Vector2(0, 300)], ["lumber_camp", tree + (home - tree).normalized() * 160.0]]
	var built: Array[Building] = []
	var ok: bool = true
	# Two crews work in parallel; each crew starts its next building when the last one is done.
	var crew_a: Building = null
	var crew_b: Building = null
	var ia: int = 0
	var ib: int = 0
	while (ia < plan_a.size() or ib < plan_b.size() or (crew_a != null and not crew_a.is_complete()) or (crew_b != null and not crew_b.is_complete())) and scen.elapsed - start < 300.0:
		if (crew_a == null or crew_a.is_complete()) and ia < plan_a.size():
			Engine.time_scale = 1.0
			await _box_select(team_a)
			crew_a = await _finger_build(plan_a[ia][0], plan_a[ia][1])
			ok = ok and crew_a != null
			if crew_a != null:
				built.append(crew_a)
			ia += 1
			Engine.time_scale = 4.0
		if (crew_b == null or crew_b.is_complete()) and ib < plan_b.size():
			Engine.time_scale = 1.0
			await _box_select(team_b)
			crew_b = await _finger_build(plan_b[ib][0], plan_b[ib][1])
			ok = ok and crew_b != null
			if crew_b != null:
				built.append(crew_b)
			ib += 1
			Engine.time_scale = 4.0
		await physics_frames(1)
	Engine.time_scale = 1.0
	var game_s: float = scen.elapsed - start
	var done: int = built.filter(func(b: Building) -> bool: return is_instance_valid(b) and b.is_complete()).size()
	check(ok, "every build was placed through the finger flow (Build -> type -> tap -> ✓)")
	check(done == 5, "2 houses, farm, lumber camp and barracks completed (%d/5)" % done)
	check(game_s < 240.0, "the whole base took %.0f s of game time (< 240)" % game_s)
	check(GameState.pop_cap(0) == 15, "two finished houses raise the cap to 15 (got %d)" % GameState.pop_cap(0))
	var choppers: int = team_b.filter(func(u: Unit) -> bool: return u.task is GatherTask and (u.task as GatherTask).resource == "wood").size()
	check(choppers == 2, "builders of the lumber camp start chopping wood (%d/2)" % choppers)
	await _close()


func test_c_cancel_refunds_half() -> void:
	await _open("build4min")
	await _box_select([_villagers()[0]])
	var wood: int = GameState.get_resource(0, "wood")
	var b: Building = await _finger_build("barracks", scen.start_of(0) + Vector2(450, 0))
	check(b != null and GameState.get_resource(0, "wood") == wood - 150, "placing a barracks spends 150 wood")
	await physics_frames(60)
	sel.select_building(b)
	await frames(1)
	check(hud.cancel_construction_button != null, "an unfinished building offers Cancel")
	hud.cancel_construction_button.pressed.emit()
	await frames(1)
	check(not is_instance_valid(b) or not world.buildings.has(b), "cancel removes the foundation")
	check(GameState.get_resource(0, "wood") == wood - 75, "cancel refunds 50%% (wood %d, expected %d)" % [GameState.get_resource(0, "wood"), wood - 75])
	var free_again: bool = world.nav.is_walkable(world.world_to_cell(b.position)) if is_instance_valid(b) else true
	check(free_again, "the cancelled footprint is walkable again")
	await _close()


func test_d_production_queue_and_pop() -> void:
	await _open("build4min")
	var tc: Building = world.buildings.filter(func(b: Building) -> bool: return b.building_type == "town_center")[0]
	sel.select_building(tc)
	await frames(1)
	check(hud.type_buttons.has("villager") and hud.type_buttons.has("scout"), "Town Center panel offers Villager and Scout")
	var food: int = GameState.get_resource(0, "food")
	var vdef: Dictionary = DataLoader.get_entry("units", "villager")
	var vcost: int = int(Dictionary(vdef.get("cost", {})).get("food", 50))
	var vtime: float = float(vdef.get("train_time", 20))
	(hud.type_buttons["villager"] as Button).pressed.emit()
	check(tc.queue.size() == 1 and GameState.get_resource(0, "food") == food - vcost, "training a villager costs %d food up front" % vcost)
	var before: int = _villagers().size()
	Engine.time_scale = 4.0
	var t0: float = scen.elapsed
	while _villagers().size() == before and scen.elapsed - t0 < 40.0:
		await physics_frames(1)
	Engine.time_scale = 1.0
	var took: float = scen.elapsed - t0
	check(_villagers().size() == before + 1, "a villager came out")
	check(absf(took - vtime) < 1.5, "after its train_time from units.json (%.1f s, data %.0f s)" % [took, vtime])
	check(GameState.pop_used(0) == 5, "population counts the new unit (5)")
	# Population cap blocks the queue.
	GameState.add_resource(0, "food", 1000)
	for i: int in 5:
		world.construction.enqueue(tc, "villager")
	check(tc.queue.size() == 5 and not world.construction.enqueue(tc, "villager"), "queue holds at most 5")
	var food_before: int = GameState.get_resource(0, "food")
	world.construction.dequeue(tc, 4)
	check(GameState.get_resource(0, "food") == food_before + vcost, "removing from the queue refunds in full")
	Engine.time_scale = 6.0
	t0 = scen.elapsed
	while not tc.blocked_by_pop and scen.elapsed - t0 < 120.0:
		await physics_frames(1)
	Engine.time_scale = 1.0
	check(tc.blocked_by_pop and GameState.pop_used(0) == GameState.pop_cap(0), "at 5/5 the queue waits for a house (pop %d/%d)" % [GameState.pop_used(0), GameState.pop_cap(0)])
	await _close()


func test_e_rally_point_to_trees() -> void:
	await _open("build4min")
	var tc: Building = world.buildings.filter(func(b: Building) -> bool: return b.building_type == "town_center")[0]
	sel.select_building(tc)
	await frames(1)
	var tree: Vector2i = world.find_tree_near(tc.position, 30)
	cam.center_on(world.cell_center(tree))
	await frames(1)
	_tap(cam.world_to_screen(world.cell_center(tree)))
	check(tc.rally_point.distance_to(world.cell_center(tree)) < 2.0, "tap with the TC selected sets its rally point")
	world.construction.enqueue(tc, "villager")
	Engine.time_scale = 6.0
	var t0: float = scen.elapsed
	var count: int = _villagers().size()
	while _villagers().size() == count and scen.elapsed - t0 < 40.0:
		await physics_frames(1)
	Engine.time_scale = 1.0
	var newest: Unit = _villagers()[_villagers().size() - 1]
	check(newest.task is GatherTask and (newest.task as GatherTask).resource == "wood", "a villager trained with a rally on trees goes chop wood")
	await _close()


func test_f_farm_builder_farms() -> void:
	await _open("build4min")
	var v: Unit = _villagers()[0]
	await _box_select([v])
	var farm: Building = await _finger_build("farm", scen.start_of(0) + Vector2(0, 320))
	check(farm != null and v.task is BuildTask, "the selected villager is sent to build the farm")
	Engine.time_scale = 4.0
	await _wait_complete(farm, 60.0)
	await physics_frames(10)
	Engine.time_scale = 1.0
	check(farm.is_complete(), "one villager finishes the farm (15 s build time)")
	check(v.task is GatherTask and (v.task as GatherTask).target == GatherTask.Target.FARM, "and then farms it")
	await _close()


func test_g_tap_own_building_with_selection() -> void:
	await _open("build4min")
	var vs: Array[Unit] = _villagers()
	await _box_select(vs)
	var tc: Building = world.buildings[0]
	cam.center_on(tc.position)
	await frames(1)
	_tap(cam.world_to_screen(tc.position))
	check(sel.selected_building == tc and sel.selected.is_empty(), "tapping the TC with idle villagers selected selects the TC")
	await _box_select(vs)
	var house: Building = await _finger_build("house", scen.start_of(0) + Vector2(-320, 0))
	world.behavior.assign(vs[3], null)
	sel.set_selection([vs[3]])
	cam.center_on(house.position)
	await frames(1)
	_tap(cam.world_to_screen(house.position))
	check(vs[3].task is BuildTask, "tapping a foundation sends the selected villager to help build")
	await _close()
