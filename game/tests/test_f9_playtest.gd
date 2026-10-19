extends TestSuite
## Fixes from Pedro's first full-match playtest (docs/PLAYTEST-NOTES-2026-10-18.md):
## villagers go back to work after building, the AI looks for an enemy it
## has not found, a market trades surplus for gold, and the selection ring
## comes from the atlas (no batch breaks).

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


func test_a_villager_goes_back_to_work_after_building() -> void:
	await _open("eco12")
	var v: Unit = null
	for u: Unit in world.units:
		if u.owner_id == 0 and u.can_gather():
			v = u
			break
	var cell: Vector2i = world.find_tree_near(v.position, 30)
	world.behavior.assign(v, GatherTask.for_tree(v, world, cell))
	Engine.time_scale = 4.0
	await _wait_until(func() -> bool: return v.carry_amount >= 1.0, 60.0)
	GameState.add_resource(0, "wood", 200)
	var spot: Vector2i = world.find_building_spot("house", v.position)
	var house: Building = world.construction.start_construction(0, "house", spot, [v] as Array[Unit])
	check(house != null and v.task is BuildTask, "the villager starts building a house")
	await _wait_until(func() -> bool: return house.is_complete(), 120.0)
	await physics_frames(5)
	Engine.time_scale = 1.0
	check(house.is_complete(), "the house gets built")
	check(v.task is GatherTask and (v.task as GatherTask).resource == "wood", "then the villager goes back to cutting wood (task: %s)" % [v.task])
	await _close()


func test_b_ai_replaces_its_scout_and_explores_with_the_army() -> void:
	await _open("skirmish", {1: "normal"})
	var ai: AIController = main.ais[0]
	for u: Unit in world.units.duplicate():
		if u.owner_id == 1 and u.unit_type == "scout":
			u.take_damage(99999, null)
	await physics_frames(2)
	GameState.add_resource(1, "food", 500)
	ai.elapsed = 6.0 * 60.0
	ai.known_buildings.clear()
	ai.think()
	var tc: Building = null
	for b: Building in world.buildings:
		if b.owner_id == 1 and b.building_type == "town_center":
			tc = b
	check(tc != null and tc.queue.has("scout"), "with its scout dead and no enemy found, the AI trains another scout")
	# Push phase, nothing known, an idle army at home: part of it explores.
	for i: int in 8:
		world.spawn_unit("militia", 1, tc.position + Vector2(200 + (i % 4) * 34, 120 + (i / 4) * 34))
	ai.elapsed = 18.0 * 60.0
	ai.known_buildings.clear()
	ai.think()
	check(ai._explorers.size() == 6, "a group of 6 soldiers goes exploring (%d)" % ai._explorers.size())
	await physics_frames(10)
	check(ai._explorers.all(func(u: Unit) -> bool: return u.is_moving() and u.attack_move), "they attack-move toward unexplored ground")
	await _close()


func test_c_market_trades_surplus_for_gold() -> void:
	await _open("arena")
	var eco: EconomySystem = world.economy
	GameState.add_resource(0, "food", 1000 - GameState.get_resource(0, "food"))
	check(eco.sell_error(0, "food") == "no_market", "without a market there is nothing to sell")
	var market: Building = world.place_building("market", 0, Vector2i(60, 60))
	market.add_progress(1.0)
	check(market.is_complete(), "a market stands")
	var gold0: int = GameState.get_resource(0, "gold")
	var price: int = eco.market_price(0, "food")
	check(eco.sell(0, "food"), "sell 100 food")
	check(GameState.get_resource(0, "food") == 900 and GameState.get_resource(0, "gold") == gold0 + price, "100 food became %d gold" % price)
	check(eco.market_price(0, "food") < price, "each sale lowers the price (%d -> %d)" % [price, eco.market_price(0, "food")])
	check(eco.market_price(0, "wood") == price, "other resources keep their price")
	var low: int = eco.market_price(0, "food")
	eco.tick_market(float(DataLoader.rule("market", "recover_s", 20)) + 0.1)
	check(eco.market_price(0, "food") > low, "prices recover over time")
	var saved: Dictionary = GameState.to_dict()
	GameState.market_prices = {}
	GameState.from_dict(saved)
	check(eco.market_price(0, "food") == low + int(DataLoader.rule("market", "recover", 2)), "prices survive save and load")
	GameState.add_resource(0, "stone", -GameState.get_resource(0, "stone"))
	check(not eco.sell(0, "stone"), "cannot sell what you do not have")
	await _close()


func test_d_ai_sells_surplus_when_short_of_gold() -> void:
	await _open("skirmish", {1: "normal"})
	var ai: AIController = main.ais[0]
	var tc: Building = null
	for b: Building in world.buildings:
		if b.owner_id == 1 and b.building_type == "town_center":
			tc = b
	var market: Building = world.place_building("market", 1, world.world_to_cell(tc.position) + Vector2i(-8, -8))
	market.add_progress(1.0)
	GameState.add_resource(1, "gold", -GameState.get_resource(1, "gold"))
	GameState.add_resource(1, "food", 2000)
	ai.think()
	check(GameState.get_resource(1, "gold") > 0, "an AI with no gold and lots of food sells at its market (gold %d)" % GameState.get_resource(1, "gold"))
	await _close()


func test_e_selection_ring_is_in_the_atlas() -> void:
	PlaceholderArt._texture = null
	PlaceholderArt.load_or_build()
	var r: Rect2 = PlaceholderArt.ring_region()
	check(r.size == Vector2(96, 48), "the selection ring is baked into the atlas (%s)" % r)
	var src: String = FileAccess.get_file_as_string("res://scenes/units/unit.gd")
	check(not src.contains("draw_arc("), "units draw no arcs (they break batching: 57 selected = 270 draw calls)")


func test_f_speed_button_cycles_and_resets() -> void:
	await _open("arena")
	var hud: Hud = main.get_node("Hud")
	Engine.time_scale = 1.0
	check(hud.speed_button != null and hud.speed_button.text == "x1", "there is a speed button showing x1")
	await frames(2)
	check(hud.is_point_over_ui(hud.speed_button.get_global_rect().get_center()), "a tap on the speed button never reaches the map (no stray orders)")
	hud.cycle_speed()
	check(is_equal_approx(Engine.time_scale, 2.0) and hud.speed_button.text == "x2", "one tap: x2")
	hud.cycle_speed()
	check(is_equal_approx(Engine.time_scale, 3.0) and hud.speed_button.text == "x3", "two taps: x3")
	hud.cycle_speed()
	check(is_equal_approx(Engine.time_scale, 1.0) and hud.speed_button.text == "x1", "three taps: back to x1")
	hud.cycle_speed()
	hud.show_end(true, 60.0, {}, {})
	check(is_equal_approx(Engine.time_scale, 1.0), "the end screen resets the speed to x1")
	await _close()


func test_g_player_can_resign() -> void:
	await _open("skirmish", {1: "easy"})
	var hud: Hud = main.get_node("Hud")
	var rules: MatchRules = main.get_node("MatchRules")
	check(hud.can_resign, "a real match offers Resign in the pause menu")
	hud.menu_resign_pressed.emit()
	await frames(2)
	check(rules.ended and rules.winner_id == 1, "resigning ends the match: the AI wins")
	check(hud.end_panel != null, "and the defeat screen shows")
	await _close()


func test_h_farms_are_drawn_under_units() -> void:
	await _open("arena")
	var farm: Building = world.place_building("farm", 0, Vector2i(60, 60))
	var house: Building = world.place_building("house", 0, Vector2i(66, 60))
	var v: Unit = world.spawn_unit("villager", 0, farm.position + Vector2(0, -40))
	check(farm.z_index < v.z_index, "a farm (ground) draws under units even where y-sort would put it on top")
	check(house.z_index == v.z_index, "solid buildings still y-sort with units")
	check(world.terrain_layer.z_index < farm.z_index, "the terrain stays under the farm")
	await _close()


func test_i_easy_gives_the_human_a_bonus_once() -> void:
	await _open("skirmish", {1: "easy"})
	var g: float = GameState.modifier(0, "gather.wood")
	var t: float = GameState.modifier(0, "train_speed")
	check(is_equal_approx(g, 1.2) and is_equal_approx(t, 1.25), "on Easy the player gathers +20%% and trains +25%% faster (%.2f, %.2f)" % [g, t])
	check(is_equal_approx(GameState.modifier(1, "gather.wood"), 1.0), "the Easy AI gets no bonus")
	main.save_match("bonus_test")
	await _close()
	GameState.launch = {"load": "bonus_test"}
	main = load("res://scenes/main/main.tscn").instantiate()
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")
	scen = main.get_node("ScenarioRunner")
	check(is_equal_approx(GameState.modifier(0, "gather.wood"), 1.2), "after loading the save the bonus is still x1.2, not doubled (%.2f)" % GameState.modifier(0, "gather.wood"))
	SaveManager.delete_save("bonus_test")
	await _close()


func test_j_villagers_leave_selection_after_work_order() -> void:
	await _open("eco12")
	var sel: SelectionController = main.get_node("SelectionController")
	var villagers: Array[Unit] = world.units.filter(func(u: Unit) -> bool: return u.owner_id == 0 and u.can_gather())
	var two: Array[Unit] = villagers.slice(0, 2)
	sel.set_selection(two)
	var bush: ResourceNode = world.find_node_near("berries", two[0].position, 3000.0)
	sel.issue_order(bush.position, sel.resolve_target(bush.position))
	check(two.all(func(u: Unit) -> bool: return u.task is GatherTask), "the villagers start gathering")
	check(sel.selected.is_empty(), "and leave the selection, so the next tap does not pull them away")
	var soldier: Unit = world.spawn_unit("militia", 0, two[0].position + Vector2(100, 0))
	sel.set_selection([soldier] as Array[Unit])
	sel.order_move(soldier.position + Vector2(300, 0))
	check(sel.selected.has(soldier), "soldiers stay selected after a move")
	sel.set_selection([villagers[2]] as Array[Unit])
	sel.order_move(villagers[2].position + Vector2(200, 0))
	check(sel.selected.has(villagers[2]), "a villager told only to walk stays selected")
	await _close()


func test_k_tap_near_a_resource_with_a_villager_selected_means_work() -> void:
	await _open("eco12")
	var sel: SelectionController = main.get_node("SelectionController")
	var cam: CameraController = main.get_node("CameraController")
	var villagers: Array[Unit] = world.units.filter(func(u: Unit) -> bool: return u.owner_id == 0 and u.can_gather())
	var mine: ResourceNode = world.find_node_near("gold", villagers[0].position, 4000.0)
	# Another villager already works right at the mine.
	villagers[1].position = mine.position + Vector2(mine.rect().size.x * 0.5 + 10, 0)
	sel.set_selection([villagers[0]] as Array[Unit])
	var near_edge: Vector2 = mine.position + Vector2(mine.rect().size.x * 0.5 + 12, 0)
	var t: Dictionary = sel.resolve_target(near_edge)
	check(String(t["kind"]) == "node" and (t["ref"] as ResourceNode).subtype == "gold", "tapping next to a mine (where another villager stands) targets the mine, not the villager (%s, mine at %s size %s, tap %s)" % [t["kind"], mine.position, mine.rect().size, near_edge])
	sel.issue_order(near_edge, t)
	check(villagers[0].task is GatherTask and (villagers[0].task as GatherTask).resource == "gold", "the selected villager goes to mine gold")
	# A tap a little off a tree still means "cut that tree".
	var cell: Vector2i = world.find_tree_near(villagers[2].position, 30)
	sel.set_selection([villagers[2]] as Array[Unit])
	var off: Vector2 = world.cell_center(cell) + Vector2(world.tile_size * 0.9, 0)
	if world.is_tree(world.world_to_cell(off)):
		off = world.cell_center(cell)
	var tt: Dictionary = sel.resolve_target(off)
	check(String(tt["kind"]) == "tree", "a tap just beside a tree targets the tree (%s)" % tt["kind"])
	# Without villagers selected, a tap on a villager still selects it.
	sel.clear_selection()
	var t2: Dictionary = sel.resolve_target(villagers[1].position)
	check(String(t2["kind"]) == "own_unit", "with nothing selected, tapping a villager selects it")
	await _close()


func test_l_build_orders_queue_up() -> void:
	await _open("eco12")
	var v: Unit = null
	for u: Unit in world.units:
		if u.owner_id == 0 and u.can_gather():
			v = u
			break
	GameState.add_resource(0, "wood", 500)
	var spot1: Vector2i = world.find_building_spot("house", v.position)
	var h1: Building = world.construction.start_construction(0, "house", spot1, [v] as Array[Unit])
	var spot2: Vector2i = world.find_building_spot("house", v.position + Vector2(400, 0))
	var h2: Building = world.construction.start_construction(0, "house", spot2, [v] as Array[Unit])
	check(h1 != null and h2 != null, "two houses ordered one after the other")
	check(v.task is BuildTask and (v.task as BuildTask).building == h1, "the villager keeps building the first house")
	check((v.task as BuildTask).queue.has(h2), "the second house waits in its queue")
	Engine.time_scale = 4.0
	await _wait_until(func() -> bool: return h1.is_complete() and h2.is_complete(), 180.0)
	Engine.time_scale = 1.0
	check(h1.is_complete() and h2.is_complete(), "both houses get built, in order")
	await _close()
