extends TestSuite
## IDEAS-AOE2 batch 2a: finite farms that reseed themselves, a second Town
## Center from Era III, rich veins in the middle of every map and buying at
## the market.

var main: Node
var world: World
var scen: ScenarioRunner


func _open(scenario: String, ai: Dictionary = {}, map: String = "") -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = scenario
	if map != "":
		main.map_override = map
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


func test_a_farms_run_out_and_reseed_themselves() -> void:
	await _open("arena")
	var farm: Building = world.place_building("farm", 0, Vector2i(60, 60))
	farm.add_progress(1.0)
	check(is_equal_approx(farm.food_left, 250.0) and not farm.fallow, "a farm starts with 250 food")
	var v: Unit = world.spawn_unit("villager", 0, world.cell_center(Vector2i(59, 59)))
	GameState.add_resource(0, "wood", 100 - GameState.get_resource(0, "wood"))
	world.behavior.assign(v, GatherTask.for_farm(v, world, farm))
	farm.food_left = 3.0
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return farm.reseeds >= 1, 30.0)
	Engine.time_scale = 1.0
	check(farm.reseeds == 1 and farm.food_left > 200.0 and not farm.fallow, "when the sowing runs out it reseeds itself (%d left)" % int(farm.food_left))
	check(GameState.get_resource(0, "wood") == 40, "for the farm's cost in wood (60): %d left" % GameState.get_resource(0, "wood"))
	check(v.task is GatherTask, "the farmer keeps farming")
	GameState.add_resource(0, "wood", -GameState.get_resource(0, "wood"))
	farm.food_left = 3.0
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return farm.fallow, 30.0)
	check(farm.fallow and farm.reseeds == 1, "with no wood it lies fallow")
	await physics_frames(30)
	check(v.task is GatherTask and not v.is_moving(), "the farmer waits by the fallow farm")
	GameState.add_resource(0, "wood", 60)
	await _wait_until(func() -> bool: return not farm.fallow, 20.0)
	Engine.time_scale = 1.0
	check(not farm.fallow and farm.reseeds == 2 and GameState.get_resource(0, "wood") == 0, "wood comes in: the farm reseeds and the wood is spent")
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return v.carry_amount > 1.0, 30.0)
	Engine.time_scale = 1.0
	check(v.carry_amount > 1.0 and v.carry_type == "food", "and the farmer is harvesting again")
	await _close()


func test_b_second_town_center_from_era_three() -> void:
	await _open("eco12")
	var cs: ConstructionSystem = world.construction
	var tc: Building = null
	for b: Building in world.buildings:
		if b.owner_id == 0 and b.building_type == "town_center":
			tc = b
	var spot: Vector2i = world.find_building_spot("town_center", tc.position + Vector2(700, 0))
	GameState.add_resource(0, "wood", 2000)
	GameState.add_resource(0, "stone", 1000)
	check(cs.placement_error(0, "town_center", spot) == "era", "in Era I a second Town Center is not allowed (era)")
	GameState.set_era(0, 3)
	check(ConstructionSystem.count_limit(0, "town_center") == 2 and cs.placement_error(0, "town_center", spot) == "", "in Era III the limit is 2 and the second one may go up")
	var v: Unit = null
	for u: Unit in world.units:
		if u.owner_id == 0 and u.can_gather():
			v = u
	var second: Building = cs.start_construction(0, "town_center", spot, [v] as Array[Unit])
	check(second != null and second.building_type == "town_center", "the foundation is placed")
	var spot2: Vector2i = world.find_building_spot("town_center", tc.position + Vector2(0, 700))
	check(cs.placement_error(0, "town_center", spot2) == "limit", "a third one says 'limit' in Era III")
	GameState.set_era(0, 4)
	check(cs.placement_error(0, "town_center", spot2) == "", "and is allowed in Era IV (limit 3)")
	var rules: MatchRules = main.get_node("MatchRules")
	second.add_progress(1.0)
	tc.take_damage(99999, null)
	await physics_frames(70)
	check(not rules.ended, "losing one Town Center while another stands is not the end")
	await _close()


func test_c_every_map_has_rich_veins_in_the_middle() -> void:
	for map_id: String in ["valle_rio", "bosque_cerrado", "tierras_doradas", "skirmish_120"]:
		await _open("skirmish", {1: "easy"}, map_id)
		var veins: Array[ResourceNode] = []
		var quarries: Array[ResourceNode] = []
		for n: ResourceNode in world.resource_nodes:
			if n.resource_type == "gold_vein":
				veins.append(n)
			elif n.resource_type == "stone_quarry":
				quarries.append(n)
		var center: Vector2 = world.map_size_px * 0.5
		check(veins.size() == 1 and veins[0].position.distance_to(center) < world.tile_size * 10, "%s: one gold vein (1500) near the centre (%d px)" % [map_id, int(veins[0].position.distance_to(center)) if not veins.is_empty() else -1])
		check(quarries.size() == 2 and quarries[0].position.distance_to(center) < world.tile_size * 12, "%s: two quarries (1000) by the centre" % map_id)
		check(not veins.is_empty() and is_equal_approx(veins[0].amount, 1500.0), "%s: the vein holds 1500 gold" % map_id)
		await _close()
	PlaceholderArt._texture = null
	PlaceholderArt.load_or_build()
	check(PlaceholderArt.resource_region("gold_vein").size.x > 0, "the vein has art in the atlas")


func test_d_market_buys_too() -> void:
	await _open("arena")
	var market: Building = world.place_building("market", 0, Vector2i(60, 60))
	market.add_progress(1.0)
	var eco: EconomySystem = world.economy
	GameState.add_resource(0, "gold", 500 - GameState.get_resource(0, "gold"))
	var food: int = GameState.get_resource(0, "food")
	check(eco.buy_price(0, "food") == 91, "buying costs the sell price plus 30%%: %d gold" % eco.buy_price(0, "food"))
	check(eco.buy(0, "food"), "a lot of food can be bought")
	check(GameState.get_resource(0, "food") == food + 100 and GameState.get_resource(0, "gold") == 409, "100 food arrive, 91 gold leave")
	check(eco.market_price(0, "food") == 73 and eco.buy_price(0, "food") == 95, "buying pushes the price up (sell %d, buy %d)" % [eco.market_price(0, "food"), eco.buy_price(0, "food")])
	check(not eco.buy(0, "gold"), "gold itself is not for sale")
	GameState.add_resource(0, "gold", -GameState.get_resource(0, "gold"))
	check(eco.buy_error(0, "wood") == "cost" and not eco.buy(0, "wood"), "with no gold the buy is refused")
	var hud: Hud = main.get_node("Hud")
	GameState.add_resource(0, "gold", 300)
	main.get_node("SelectionController").select_building(market)
	await frames(1)
	check(hud.type_buttons.has("buy:food") and not (hud.type_buttons["buy:food"] as Button).disabled, "the market panel has a Buy button per resource")
	await _close()


func test_e_farm_state_survives_a_save() -> void:
	await _open("eco12")
	var farm: Building = world.place_building("farm", 0, Vector2i(30, 30))
	farm.add_progress(1.0)
	farm.food_left = 77.0
	farm.reseeds = 2
	var data: Dictionary = SaveGame.snapshot(main)
	await _close()
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = "eco12"
	main.load_data = data
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")
	var again: Building = null
	for b: Building in world.buildings:
		if b.building_type == "farm" and b.cell == Vector2i(30, 30):
			again = b
	check(again != null and is_equal_approx(again.food_left, 77.0) and again.reseeds == 2, "a farm's food left and reseeds come back from a save")
	await _close()
