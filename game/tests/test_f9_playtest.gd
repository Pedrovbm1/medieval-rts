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
