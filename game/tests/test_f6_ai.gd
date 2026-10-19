extends TestSuite
## F6: the AI beats a passive player in 15-20 min (Normal), never attacks
## what it has not explored, and the match ends with a result screen.

var main: Node
var world: World
var rules: MatchRules


func _open(scenario: String, override: Dictionary = {}, seed: int = 1) -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = scenario
	main.ai_override = override
	main.ai_seed = seed
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")
	rules = main.get_node("MatchRules")


func _close() -> void:
	Engine.time_scale = 1.0
	main.queue_free()
	await frames(2)


func test_a_passive_player_loses_in_15_to_20_minutes() -> void:
	await _open("skirmish")
	var ai: AIController = main.ais[0]
	check(ai.player_id == 1 and ai.difficulty_id == "normal", "skirmish puts a Normal AI on player 2")
	var villagers_at_8: Array[int] = [0]
	Engine.time_scale = 8.0
	while not rules.ended and ai.elapsed < 1500.0:
		await physics_frames(1)
		if villagers_at_8[0] == 0 and ai.elapsed >= 480.0:
			villagers_at_8[0] = world.units.filter(func(u: Unit) -> bool: return u.owner_id == 1 and u.can_gather()).size()
	Engine.time_scale = 1.0
	var minutes: float = rules.elapsed / 60.0
	check(rules.ended and rules.winner_id == 1, "the AI destroys a passive player's base")
	# 15-22: the Town Center's arrows (F9 defence) slow a push by a minute or two.
	check(minutes >= 15.0 and minutes <= 22.0, "it takes %.1f min (target 15-22)" % minutes)
	# The AI pauses villagers at 18 to "click up" to Era II (data/ai.json saving.pause_villagers_at).
	check(villagers_at_8[0] >= 18, "AI economy: %d villagers at minute 8" % villagers_at_8[0])
	var unexplored: Array = ai.attack_log.filter(func(a: Dictionary) -> bool: return not bool(a["explored"]))
	check(not ai.attack_log.is_empty() and unexplored.is_empty(), "all %d attack orders targeted explored ground" % ai.attack_log.size())
	var hud: Hud = main.get_node("Hud")
	check(hud.end_panel != null, "the defeat screen is shown")
	check(int(Dictionary(GameState.stats[1]).get("trained", 0)) > 20, "match stats count trained units (%d)" % int(Dictionary(GameState.stats[1]).get("trained", 0)))
	await _close()


func test_b_no_attack_without_scouting() -> void:
	await _open("skirmish")
	var ai: AIController = main.ais[0]
	# Blind the AI: no scout, and jump straight to the push phase with an army.
	for u: Unit in world.units.duplicate():
		if u.owner_id == 1 and u.unit_type == "scout":
			world.remove_unit(u)
	ai.elapsed = 17.0 * 60.0
	var home: Vector2 = ai.home
	for i: int in 20:
		world.spawn_unit("militia", 1, world.nav.cell_center(world.nav.nearest_walkable(world.world_to_cell(home + Vector2(200 + (i % 5) * 40, 200 + (i / 5) * 40)))))
	Engine.time_scale = 4.0
	await physics_frames(240)
	Engine.time_scale = 1.0
	check(ai.phase == "push", "the AI is in its push phase (%s)" % ai.phase)
	check(ai.known_buildings.is_empty(), "without scouting it knows no enemy building")
	check(ai.attack_log.is_empty(), "so it sends no attack (orders: %d)" % ai.attack_log.size())
	# Now one of its soldiers sees the human Town Center: the attack follows.
	var human_tc: Building = world.buildings.filter(func(b: Building) -> bool: return b.owner_id == 0)[0]
	var spy: Unit = world.spawn_unit("militia", 1, human_tc.position + Vector2(260, 0))
	spy.stance = "passive"
	world.vision.refresh()
	ai.think()
	check(not ai.known_buildings.is_empty(), "once seen, the enemy base is remembered")
	check(not ai.attack_log.is_empty() and bool(ai.attack_log[0]["explored"]), "and the push goes for that explored target")
	await _close()


func test_c_victory_screen() -> void:
	await _open("skirmish")
	var hud: Hud = main.get_node("Hud")
	for b: Building in world.buildings.duplicate():
		if b.owner_id == 1:
			b.take_damage(99999, null)
	await physics_frames(90)
	check(rules.ended and rules.winner_id == 0, "destroying every enemy building wins the match")
	check(hud.end_panel != null and hud.is_point_over_ui(Vector2(5, 5)), "the victory screen is shown and blocks map input")
	var title: Label = hud.end_panel.find_children("*", "Label", true, false)[0]
	check(title.text == tr("END_VICTORY"), "it says %s" % title.text)
	await _close()


func test_d_no_instant_win_without_a_rival() -> void:
	await _open("eco12")
	await physics_frames(150)
	check(not rules.ended, "a scenario without an enemy base never declares a winner")
	check((main.get_node("Hud") as Hud).end_panel == null, "and shows no end screen")
	await _close()
