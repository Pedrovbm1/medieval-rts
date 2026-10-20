extends TestSuite
## IDEAS-AOE2 batch 3: the wonder (build it in Era IV, hold it 3 minutes)
## and caravans trading with the neutral post in the middle of the map.

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


func _caravan_of(owner: int) -> Unit:
	for u: Unit in world.units:
		if u.unit_type == "caravan" and u.owner_id == owner:
			return u
	return null


func _tc(owner: int) -> Building:
	for b: Building in world.buildings:
		if b.owner_id == owner and b.building_type == "town_center":
			return b
	return null


func test_a_wonder_needs_era_four_and_wins_when_it_stands() -> void:
	await _open("skirmish", {1: "easy"})
	var rules: MatchRules = main.get_node("MatchRules")
	var hud: Hud = main.get_node("Hud")
	var cs: ConstructionSystem = world.construction
	var tc: Building = _tc(0)
	var spot: Vector2i = world.find_building_spot("wonder", tc.position + Vector2(500, 0))
	for res: String in ["wood", "stone", "gold"]:
		GameState.add_resource(0, res, 1200)
	check(cs.placement_error(0, "wonder", spot) == "era", "the wonder needs Era IV")
	GameState.set_era(0, 4)
	check(cs.placement_error(0, "wonder", spot) == "", "in Era IV it may go up")
	var v: Unit = null
	for u: Unit in world.units:
		if u.owner_id == 0 and u.can_gather():
			v = u
	var wood_before: int = GameState.get_resource(0, "wood")
	var wonder: Building = cs.start_construction(0, "wonder", spot, [v] as Array[Unit])
	check(wonder != null and GameState.get_resource(0, "wood") == wood_before - 1000, "it costs 1000 of each (wood %d -> %d)" % [wood_before, GameState.get_resource(0, "wood")])
	check(cs.placement_error(0, "wonder", world.find_building_spot("wonder", tc.position + Vector2(0, 500))) == "limit", "only one wonder")
	await physics_frames(70)
	check(rules.wonder_countdown(0) < 0.0, "a wonder under construction starts no clock")
	wonder.add_progress(1.0)
	await physics_frames(70)
	check(rules.wonder_countdown(0) > 0.0 and rules.wonder_countdown(0) <= 180.0, "finished: the 3-minute clock runs (%.0f s)" % rules.wonder_countdown(0))
	check(hud.last_banner_level == "critical" and hud.banner.text.begins_with(tr("ALERT_WONDER_MINE").split("%")[0].strip_edges()), "critical banner: 'wonder complete, defend it'")
	var foe: Unit = world.spawn_unit("militia", 1, wonder.position + Vector2(300, 0))
	foe.stance = "passive"
	wonder.take_damage(10, foe)
	check(hud.banner.text == tr("ALERT_WONDER_ATTACK"), "hitting it: 'your wonder is under attack'")
	rules.wonder_victory_s = 3.0
	Engine.time_scale = 4.0
	await _wait_until(func() -> bool: return rules.ended, 30.0)
	Engine.time_scale = 1.0
	check(rules.ended and rules.winner_id == 0 and rules.reason == "wonder", "when the clock runs out the builder wins")
	await _close()


func test_b_destroying_the_wonder_stops_the_clock() -> void:
	await _open("skirmish", {1: "easy"})
	var rules: MatchRules = main.get_node("MatchRules")
	var tc: Building = _tc(1)
	var wonder: Building = world.place_building("wonder", 1, world.find_building_spot("wonder", tc.position + Vector2(400, 0)))
	wonder.add_progress(1.0)
	await physics_frames(70)
	check(rules.wonder_countdown(1) > 0.0, "the rival's finished wonder starts its clock")
	var hud: Hud = main.get_node("Hud")
	await _wait_until(func() -> bool: return hud.wonder_label != null and hud.wonder_label.visible, 5.0)
	check(hud.last_banner_level == "critical" and hud.wonder_label != null and hud.wonder_label.visible, "we are warned and the HUD shows the clock (banner '%s' %s)" % [hud.banner.text, hud.last_banner_level])
	wonder.take_damage(99999, null)
	await physics_frames(70)
	check(rules.wonder_countdown(1) < 0.0 and not rules.ended, "razing it stops the clock")
	await _close()


func test_c_caravans_trade_with_the_post_in_the_middle() -> void:
	for map_id: String in ["valle_rio", "tierras_doradas"]:
		await _open("skirmish", {1: "easy"}, map_id)
		var posts: Array[Building] = world.buildings.filter(func(b: Building) -> bool: return b.building_type == "trade_post")
		check(posts.size() == 1 and posts[0].owner_id < 0 and posts[0].position.distance_to(world.map_size_px * 0.5) < world.tile_size * 12, "%s: one neutral trade post near the middle" % map_id)
		await _close()
	await _open("skirmish", {1: "easy"})
	var post: Building = world.nearest_trade_post(Vector2.ZERO)
	var tc: Building = _tc(0)
	var market: Building = world.place_building("market", 0, world.find_building_spot("market", tc.position + Vector2(300, 0)))
	market.add_progress(1.0)
	GameState.set_era(0, 3)
	GameState.add_resource(0, "wood", 500)
	GameState.add_resource(0, "gold", 500)
	for i: int in 2:  # room in the population for the caravan
		world.place_building("house", 0, world.find_building_spot("house", tc.position + Vector2(-300, i * 150))).add_progress(1.0)
	world.economy.refresh_population()
	check(world.construction.can_enqueue(market, "caravan") == "", "the market trains caravans from Era III")
	world.construction.enqueue(market, "caravan")
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return _caravan_of(0) != null, 60.0)
	var caravan: Unit = _caravan_of(0)
	check(caravan != null and caravan.task is TradeTask, "a new caravan starts trading on its own")
	var gold: int = GameState.get_resource(0, "gold")
	var expected: int = TradeTask.trip_gold(caravan, market, post)
	check(expected >= 20, "a trip from this market pays %d gold" % expected)
	await _wait_until(func() -> bool: return GameState.get_resource(0, "gold") >= gold + expected, 240.0)
	Engine.time_scale = 1.0
	check(GameState.get_resource(0, "gold") >= gold + expected, "and after one round trip the gold arrives (+%d)" % (GameState.get_resource(0, "gold") - gold))
	var foe: Unit = world.spawn_unit("militia", 1, caravan.position + Vector2(100, 0))
	foe.stance = "passive"
	var hud: Hud = main.get_node("Hud")
	caravan.take_damage(1, foe)
	check(hud.banner.text == tr("ALERT_CARAVAN"), "a hit on the caravan warns: 'your caravan is under attack'")
	await _close()


func test_d_the_ai_trades_and_hits_the_wonder() -> void:
	await _open("skirmish", {1: "normal"})
	var ai: AIController = main.ais[0]
	GameState.set_era(1, 3)
	var tc1: Building = _tc(1)
	var market: Building = world.place_building("market", 1, world.find_building_spot("market", tc1.position + Vector2(300, 0)))
	market.add_progress(1.0)
	GameState.add_resource(1, "wood", 800)
	GameState.add_resource(1, "gold", 800)
	for i: int in 30:
		world.spawn_unit("villager", 1, tc1.position + Vector2(-200 + i * 10, 200))
	ai.think()
	check(market.queue.has("caravan"), "with a market, Era III and villagers the AI queues a caravan")
	var tc0: Building = _tc(0)
	var wonder: Building = world.place_building("wonder", 0, world.find_building_spot("wonder", tc0.position + Vector2(400, 0)))
	wonder.add_progress(1.0)
	ai.known_buildings[wonder.get_instance_id()] = {"pos": wonder.position, "type": "wonder", "ref": wonder}
	for i: int in 8:
		world.spawn_unit("militia", 1, tc1.position + Vector2(300 + i * 20, 0))
	await physics_frames(70)
	ai.think()
	check(not ai.attack_log.is_empty() and String(ai.attack_log[-1]["kind"]) == "wonder", "the rival's finished wonder is attacked at once")
	await _close()
