extends TestSuite
## IDEAS-AOE2 batch 2b: relics. Four relics lie in the middle of every map;
## monks carry them to a monastery, each stored relic trickles gold, and
## holding all of them for a while wins. Dropped on death / when the
## monastery falls; the AI goes for them too.

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


func _relics_on_ground() -> Array[ResourceNode]:
	return world.resource_nodes.filter(func(n: ResourceNode) -> bool: return n.is_relic())


func test_a_four_relics_wait_in_the_middle_of_every_map() -> void:
	for map_id: String in ["valle_rio", "bosque_cerrado", "tierras_doradas", "skirmish_120"]:
		await _open("skirmish", {1: "easy"}, map_id)
		var relics: Array[ResourceNode] = _relics_on_ground()
		var center: Vector2 = world.map_size_px * 0.5
		var far: float = 0.0
		for r: ResourceNode in relics:
			far = maxf(far, r.position.distance_to(center))
		check(relics.size() == 4 and world.relic_total == 4, "%s: 4 relics (%d)" % [map_id, relics.size()])
		check(far < world.tile_size * 26 and far > world.tile_size * 6, "%s: all around the middle, none at the starts (farthest %d cells)" % [map_id, int(far / world.tile_size)])
		check(relics.all(func(r: ResourceNode) -> bool: return world.nav.is_walkable(r.cell)), "%s: relics do not block the way" % map_id)
		await _close()


func test_b_monk_carries_a_relic_to_the_monastery_and_gold_trickles() -> void:
	await _open("arena")
	var relic: ResourceNode = world.place_resource("relic", Vector2i(60, 60))
	var monastery: Building = world.place_building("monastery", 0, Vector2i(66, 58))
	monastery.add_progress(1.0)
	var monk: Unit = world.spawn_unit("monk", 0, world.cell_center(Vector2i(57, 60)))
	var v: Unit = world.spawn_unit("villager", 0, world.cell_center(Vector2i(57, 63)))
	var sel: SelectionController = main.get_node("SelectionController")
	check(sel._task_for(v, "node", relic) == null, "villagers cannot gather a relic")
	check(sel._task_for(monk, "node", relic) is RelicTask, "a monk tapped on a relic goes to fetch it")
	var taken: Array = []
	EventBus.relic_taken.connect(func(p: int, _pos: Vector2) -> void: taken.append(p))
	world.behavior.assign(monk, RelicTask.new(monk, world, relic))
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return monk.relic, 30.0)
	check(monk.relic and _relics_on_ground().is_empty() and taken == [0], "the monk picks it up: the relic leaves the ground and the owner is told")
	await _wait_until(func() -> bool: return monastery.relics == 1, 40.0)
	Engine.time_scale = 1.0
	check(monastery.relics == 1 and not monk.relic, "and stores it in the monastery")
	check(world.relics_held(0) == 1, "the player holds 1 relic")
	var gold: int = GameState.get_resource(0, "gold")
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return GameState.get_resource(0, "gold") >= gold + 5, 30.0)
	Engine.time_scale = 1.0
	check(GameState.get_resource(0, "gold") >= gold + 5 and scen.elapsed > 0.0, "a stored relic trickles gold (+%d)" % (GameState.get_resource(0, "gold") - gold))
	await _close()


func test_c_relics_drop_when_the_carrier_dies_or_the_monastery_falls() -> void:
	await _open("arena")
	var monk: Unit = world.spawn_unit("monk", 0, world.cell_center(Vector2i(57, 60)))
	monk.relic = true
	monk.take_damage(99999, null)
	await physics_frames(3)
	var ground: Array[ResourceNode] = _relics_on_ground()
	check(ground.size() == 1 and ground[0].position.distance_to(world.cell_center(Vector2i(57, 60))) < 80.0, "a monk that dies drops its relic where it fell")
	var monastery: Building = world.place_building("monastery", 1, Vector2i(66, 58))
	monastery.add_progress(1.0)
	monastery.relics = 2
	check(world.relics_held(1) == 2, "the rival holds 2")
	monastery.take_damage(99999, null)
	await physics_frames(3)
	check(_relics_on_ground().size() == 3 and world.relics_held(1) == 0, "a razed monastery spills its relics (%d on the ground)" % _relics_on_ground().size())
	await _close()


func test_d_holding_every_relic_long_enough_wins() -> void:
	await _open("skirmish", {1: "easy"})
	var rules: MatchRules = main.get_node("MatchRules")
	var hud: Hud = main.get_node("Hud")
	for r: ResourceNode in _relics_on_ground():
		world.remove_resource(r)
	var tc: Building = null
	for b: Building in world.buildings:
		if b.owner_id == 0 and b.building_type == "town_center":
			tc = b
	var monastery: Building = world.place_building("monastery", 0, world.find_building_spot("monastery", tc.position))
	monastery.add_progress(1.0)
	monastery.relics = 3
	world.relic_total = 4  # the fourth is "somewhere else" (carried, lost)
	await physics_frames(70)
	check(rules.relic_countdown(0) < 0.0, "with 3 of 4 relics there is no countdown")
	monastery.relics = 4
	await physics_frames(70)
	check(rules.relic_countdown(0) > 0.0 and rules.relic_countdown(0) <= 180.0, "with all 4 the countdown starts (%.0f s left)" % rules.relic_countdown(0))
	check(hud.last_banner_level == "critical" and hud.banner.text.contains(tr("ALERT_RELICS_MINE").split("%")[0]), "critical banner: 'you hold every relic'")
	check(hud.relic_label != null and hud.relic_label.visible, "the HUD shows the relic countdown")
	monastery.relics = 3
	await physics_frames(70)
	check(rules.relic_countdown(0) < 0.0, "losing one stops the countdown")
	monastery.relics = 4
	rules.relic_victory_s = 3.0
	Engine.time_scale = 4.0
	await _wait_until(func() -> bool: return rules.ended, 30.0)
	Engine.time_scale = 1.0
	check(rules.ended and rules.winner_id == 0 and rules.reason == "relics", "holding them to the end wins by relics")
	await _close()


func test_e_the_ai_goes_for_relics() -> void:
	await _open("arena", {1: "normal"})
	GameState.set_era(1, 3)
	var ai: AIController = main.ais[0]
	var monastery: Building = world.place_building("monastery", 1, Vector2i(70, 70))
	monastery.add_progress(1.0)
	var monk: Unit = world.spawn_unit("monk", 1, world.cell_center(Vector2i(68, 70)))
	world.spawn_unit("villager", 1, world.cell_center(Vector2i(72, 72)))  # not hopeless: the AI keeps thinking
	var relic: ResourceNode = world.place_resource("relic", Vector2i(66, 66))
	world.recount_relics()
	world.vision.refresh()
	check(world.vision.grid.is_explored(1, relic.position), "the AI has seen the relic")
	ai.think()
	check(monk.task is RelicTask, "an idle monk near a relic the AI has seen is sent for it")
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return monastery.relics == 1, 60.0)
	Engine.time_scale = 1.0
	check(monastery.relics == 1 and _relics_on_ground().is_empty(), "and it ends up in the AI's monastery")
	await _close()
