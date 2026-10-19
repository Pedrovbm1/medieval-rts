extends TestSuite
## F3: villagers gather, deliver and never get stuck; animals; idle bell; data-driven rates.

var main: Node
var world: World
var scen: ScenarioRunner


func _open(scenario: String) -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = scenario
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")
	scen = main.get_node("ScenarioRunner")


func _close() -> void:
	Engine.time_scale = 1.0
	main.queue_free()
	await frames(2)


## Advances `seconds` of game time at `scale`, calling `probe` every `every` seconds.
## Note: time_scale keeps ~60 physics steps per real second but makes each
## step longer, so game time is read from the scenario clock, not counted.
func _run(seconds: float, scale: float, every: float = 0.0, probe: Callable = Callable()) -> void:
	Engine.time_scale = scale
	var t0: float = scen.elapsed
	var t: float = 0.0
	var next_probe: float = every
	while t < seconds:
		await physics_frames(1)
		t = scen.elapsed - t0
		if every > 0.0 and t >= next_probe:
			next_probe += every
			probe.call(t)
	Engine.time_scale = 1.0


func _villagers(player: int = 0) -> Array[Unit]:
	return world.units.filter(func(u: Unit) -> bool: return u.owner_id == player and u.can_gather())


func test_a_setup_matches_data() -> void:
	await _open("eco12")
	check(_villagers().size() == 12, "eco12 has 12 villagers")
	var tc: Building = world.buildings.filter(func(b: Building) -> bool: return b.building_type == "town_center")[0]
	check(tc.accepts("gold") and tc.accepts("wood") and tc.accepts("food"), "Town Center accepts every resource")
	var lumber: Building = world.buildings.filter(func(b: Building) -> bool: return b.building_type == "lumber_camp")[0]
	check(lumber.accepts("wood") and not lumber.accepts("gold"), "lumber camp takes wood only")
	check(GameState.pop_cap(0) == 15 and GameState.pop_used(0) == 12, "pop 12/15 from TC + 2 houses (got %d/%d)" % [GameState.pop_used(0), GameState.pop_cap(0)])
	var home: Vector2 = scen.start_of(0)
	var near_gold: int = world.resource_nodes.filter(func(n: ResourceNode) -> bool: return n.subtype == "gold" and n.position.distance_to(home) < 800.0).size()
	var near_berries: int = world.resource_nodes.filter(func(n: ResourceNode) -> bool: return n.subtype == "berries" and n.position.distance_to(home) < 600.0).size()
	check(near_gold == 2, "start layout: 2 gold mines near the start (got %d)" % near_gold)
	check(near_berries == 5, "start layout: a cluster of 5 berry bushes (got %d)" % near_berries)
	var busy: int = _villagers().filter(func(u: Unit) -> bool: return u.task != null).size()
	check(busy == 12, "all 12 villagers got a gather task (got %d)" % busy)
	await _close()


func test_b_ten_minutes_no_stuck_no_lost_load() -> void:
	await _open("eco12")
	var last_pos: Dictionary = {}
	var still_for: Dictionary = {}
	var worst_still: Array[float] = [0.0]
	var probe: Callable = func(_t: float) -> void:
		for u: Unit in _villagers():
			var key: int = u.get_instance_id()
			var p: Vector2 = u.position
			var gathering: bool = u.task is GatherTask and (u.task as GatherTask).step == GatherTask.Step.GATHERING
			if last_pos.has(key) and p.distance_to(last_pos[key]) < 4.0 and not gathering:
				still_for[key] = float(still_for.get(key, 0.0)) + 5.0
			else:
				still_for[key] = 0.0
			worst_still[0] = maxf(worst_still[0], float(still_for[key]))
			last_pos[key] = p
	var trees_before: int = _count_forest()
	await _run(600.0, 10.0, 5.0, probe)
	for u: Unit in _villagers():
		if float(still_for.get(u.get_instance_id(), 0.0)) > 20.0 or u.is_idle():
			var g: GatherTask = u.task as GatherTask
			print("  diag %s idle=%s task=%s step=%s target=%s sub=%s carry=%.1f %s pos=%s moving=%s attempts=%s dropoff=%s" % [
				u.name, u.is_idle(), (u.task as UnitTask).kind if u.task else "none",
				str(g.step) if g else "-", str(g.target) if g else "-", g.subtype if g else "-",
				u.carry_amount, u.carry_type, u.position, u.is_moving(), str(g._attempts) if g else "-",
				str(g.dropoff.building_type) if g and g.dropoff else "null"])
	var idle: int = world.economy.idle_villagers(0).size()
	check(idle == 0, "after 10 min no villager is idle (resources left) (idle=%d)" % idle)
	check(worst_still[0] <= 20.0, "no villager stood still off-task for more than 20 s (worst %.0f s)" % worst_still[0])
	var ok: bool = true
	var report: PackedStringArray = PackedStringArray()
	for res: String in ["food", "wood", "gold", "stone"]:
		var taken: float = float(Dictionary(world.economy.taken.get(0, {})).get(res, 0.0))
		var dropped: float = float(Dictionary(world.economy.dropped.get(0, {})).get(res, 0.0))
		var carried: float = 0.0
		for u: Unit in _villagers():
			if u.carry_type == res:
				carried += u.carry_amount
		var delivered: float = float(GameState.gathered(0, res))
		report.append("%s %d=%d+%.1f+%.1f" % [res, int(taken), int(delivered), carried, dropped])
		if absf(taken - (delivered + carried + dropped)) > 0.5:
			ok = false
	check(ok, "no load is lost: taken = delivered + carried + dropped (%s)" % ", ".join(report))
	for res: String in ["food", "wood", "gold", "stone"]:
		check(GameState.gathered(0, res) > 150, "%s gathered in 10 min: %d" % [res, GameState.gathered(0, res)])
	var cut: int = trees_before - _count_forest()
	check(cut >= 5, "trees were cut down (%d)" % cut)
	await _close()


func test_c_cut_tree_frees_path() -> void:
	await _open("eco12")
	var cell: Vector2i = world.find_tree_near(scen.start_of(0), 30)
	check(not world.nav.is_walkable(cell), "a tree cell blocks paths")
	var got: float = world.take_from_tree(cell, 1000.0)
	check(is_equal_approx(got, 100.0), "a tree holds 100 wood (resources.json), got %.1f" % got)
	check(world.nav.is_walkable(cell) and not world.is_tree(cell), "the emptied tree becomes walkable grass")
	await _close()


func test_d_rates_come_from_json_and_modifiers() -> void:
	await _open("eco12")
	var v: Unit = _villagers()[11]
	var bush: ResourceNode = world.find_node_near("berries", v.position, 9999.0)
	var task: GatherTask = GatherTask.for_node(v, world, bush)
	world.behavior.assign(v, task)
	world.movement.stop(v)
	v.position = world.approach_point(bush.rect(), v.position)
	v.carry_amount = 0.0
	v.carry_type = "food"
	task.step = GatherTask.Step.GATHERING
	var rate: float = float(Dictionary(DataLoader.get_entry("units", "villager")["gather_rates"])["berries"])
	task.tick(1.0)
	check(is_equal_approx(v.carry_amount, rate), "1 s on berries gives the JSON rate %.2f (got %.2f)" % [rate, v.carry_amount])
	Dictionary(GameState.multipliers[0])["gather.berries"] = 2.0
	task.tick(1.0)
	check(is_equal_approx(v.carry_amount, rate * 3.0), "a x2 modifier doubles the next second (got %.2f)" % v.carry_amount)
	Dictionary(GameState.multipliers[0]).erase("gather.berries")
	await _close()


func test_e_idle_bell_selects_and_centers() -> void:
	await _open("eco12")
	var v: Unit = _villagers()[0]
	world.behavior.assign(v, null)
	world.movement.stop(v)
	main._refresh_idle()
	var hud: Hud = main.get_node("Hud")
	check(hud.idle_button.text.ends_with("1"), "idle bell shows 1 idle villager (%s)" % hud.idle_button.text)
	main._on_idle_pressed()
	var sel: SelectionController = main.get_node("SelectionController")
	check(sel.selected.size() == 1 and sel.selected[0] == v, "idle bell selects the idle villager")
	await frames(30)
	var cam: CameraController = main.get_node("CameraController")
	check(cam.position.distance_to(v.position) < 64.0 or cam.visible_world_rect().has_point(v.position), "camera moved to the idle villager")
	await _close()


func test_f_smart_orders() -> void:
	await _open("eco12")
	var sel: SelectionController = main.get_node("SelectionController")
	var v: Unit = _villagers()[0]
	sel.set_selection([v])
	var tree: Vector2i = world.find_tree_near(v.position, 30)
	sel.issue_order(world.cell_center(tree), sel.resolve_target(world.cell_center(tree)))
	check(v.task is GatherTask and (v.task as GatherTask).target == GatherTask.Target.TREE, "tap on a tree = gather wood")
	var mine: ResourceNode = world.find_node_near("gold", v.position, 9999.0)
	sel.set_selection([v])  # villagers leave the selection after a work order (F9)
	sel.issue_order(mine.position, sel.resolve_target(mine.position))
	check(v.task is GatherTask and (v.task as GatherTask).subtype == "gold", "tap on a gold mine = gather gold")
	var farm: Building = world.buildings.filter(func(b: Building) -> bool: return b.building_type == "farm")[0]
	sel.set_selection([v])
	sel.issue_order(farm.position, sel.resolve_target(farm.position))
	check(v.task is GatherTask and (v.task as GatherTask).target == GatherTask.Target.FARM, "tap on a farm = farm")
	var ground: Vector2 = scen.start_of(0) + Vector2(0, 400)
	sel.set_selection([v])
	sel.issue_order(ground, sel.resolve_target(ground))
	check(v.task == null and v.is_moving(), "tap on ground = move and drop the task")
	await _close()


func test_g_sheep_join_and_get_eaten() -> void:
	await _open("eco12")
	var v: Unit = _villagers()[0]
	world.behavior.assign(v, null)
	var sheep: Unit = world.spawn_unit("sheep", Unit.OWNER_GAIA, v.position + Vector2(120, 0))
	await physics_frames(20)
	check(sheep.owner_id == 0, "a wild sheep near a villager joins that player")
	var sheep_id: int = sheep.get_instance_id()
	world.behavior.assign(v, HuntTask.new(v, world, sheep))
	await _run(25.0, 4.0)
	check(_gone(sheep_id), "the villager slaughters the sheep")
	check(v.task is GatherTask and v.carry_type == "food" or GameState.gathered(0, "food") > 0, "then gathers its meat")
	await _close()


func test_h_deer_flees_but_is_hunted() -> void:
	await _open("eco12")
	var v: Unit = _villagers()[0]
	var deer: Unit = world.spawn_unit("deer", Unit.OWNER_GAIA, v.position + Vector2(200, 60))
	var deer_id: int = deer.get_instance_id()
	world.behavior.assign(v, HuntTask.new(v, world, deer))
	var start: Vector2 = deer.position
	var fled: Array[bool] = [false]
	await _run(40.0, 4.0, 0.5, func(_t: float) -> void:
		var d: Unit = instance_from_id(deer_id) as Unit
		if d != null and world.units.has(d) and d.position.distance_to(start) > 100.0:
			fled[0] = true)
	check(fled[0], "the deer ran away when hit")
	check(_gone(deer_id), "the hunter still brought it down")
	check(v.carry_type == "food" and (v.carry_amount > 0.0 or GameState.gathered(0, "food") > 0), "and gathers venison")
	await _close()


func test_i_boar_lure_with_helpers() -> void:
	await _open("eco12")
	var hunter: Unit = _villagers()[0]
	var home: Vector2 = scen.start_of(0)
	var spot: Vector2 = world.nav.cell_center(world.nav.nearest_walkable(world.world_to_cell(home + Vector2(-700, 300))))
	var boar: Unit = world.spawn_unit("boar", Unit.OWNER_GAIA, spot)
	var boar_id: int = boar.get_instance_id()
	# Three villagers resting by the Town Center: the helpers the lure brings the boar to.
	var tc: Building = world.buildings.filter(func(b: Building) -> bool: return b.building_type == "town_center")[0]
	for i: int in range(1, 4):
		var helper: Unit = _villagers()[i]
		world.behavior.assign(helper, null)
		world.movement.stop(helper)
		helper.position = world.approach_point(tc.rect(), spot) + Vector2(0, 30 * (i - 2))
	world.movement.stop(hunter)
	hunter.position = spot + Vector2(100, 0)
	world.behavior.assign(hunter, HuntTask.new(hunter, world, boar))
	var max_helpers: Array[int] = [0]
	await _run(90.0, 4.0, 0.1, func(_t: float) -> void:
		var n: int = _villagers().filter(func(u: Unit) -> bool: return u.task is HuntTask).size()
		max_helpers[0] = maxi(max_helpers[0], n))
	check(_gone(boar_id), "the boar is killed")
	check(max_helpers[0] >= 2, "villagers near home joined the boar hunt (max hunters %d)" % max_helpers[0])
	var carcass: Array = world.resource_nodes.filter(func(n: ResourceNode) -> bool: return n.resource_type == "carcass_boar")
	check(carcass.is_empty() or carcass[0].position.distance_to(home) < 900.0, "the boar fell near the Town Center (lured)")
	await _close()


## Dead units are pooled, not freed: "gone" means no longer alive in the match.
func _gone(id: int) -> bool:
	var o: Object = instance_from_id(id)
	return o == null or not world.units.has(o)


func _count_forest() -> int:
	var n: int = 0
	for y: int in world.map_height:
		for x: int in world.map_width:
			if world.is_tree(Vector2i(x, y)):
				n += 1
	return n
