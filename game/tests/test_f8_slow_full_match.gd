extends TestSuite
## F8 gate (slow): a complete match from start to finish with every system on
## (fog, AI on both sides, autosave every 2 min, end screen), no crash.
## Hard AI plays player 0, Easy AI player 1. Run with `-- slow`.


func test_full_match_ends_cleanly() -> void:
	SaveManager.delete_save("auto")
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = "skirmish"
	main.ai_override = {0: "hard", 1: "easy"}
	main.fair_ai = false
	main.ai_seed = 7
	add_to_tree(main)
	await frames(1)
	var world: World = main.get_node("World")
	var rules: MatchRules = main.get_node("MatchRules")
	check(world.vision.fog_enabled, "fog of war is on")
	Engine.time_scale = 8.0
	var autosaves: int = 0
	var last_saved: bool = false
	var max_units: int = 0
	var next_report: float = 300.0
	while not rules.ended and rules.elapsed < 50.0 * 60.0:
		await physics_frames(1)
		if rules.elapsed >= next_report:
			next_report += 300.0
			print("  info  t=%.0f min  %s | %s" % [rules.elapsed / 60.0, _state(world, 0), _state(world, 1)])
			for ai: AIController in main.ais:
				print("        ai%d phase=%s saving_era=%s(%s) saving_tech=%s waves=%d failed=%d bank=f%d w%d g%d s%d" % [ai.player_id, ai.phase, ai.saving_for_era, ai.saving_reason, ai.saving_for_tech, ai.waves, ai.failed_waves,
					GameState.get_resource(ai.player_id, "food"), GameState.get_resource(ai.player_id, "wood"), GameState.get_resource(ai.player_id, "gold"), GameState.get_resource(ai.player_id, "stone")])
		max_units = maxi(max_units, world.units.size())
		var has: bool = SaveManager.has_save("auto")
		if has and not last_saved:
			autosaves += 1
		last_saved = has
	Engine.time_scale = 1.0
	print("  info  full match: ended=%s winner=%d at %.1f min, peak units %d" % [rules.ended, rules.winner_id, rules.elapsed / 60.0, max_units])
	check(rules.ended, "the match reaches an end (%.1f min)" % (rules.elapsed / 60.0))
	check(rules.winner_id == 0, "the Hard AI beats the Easy AI")
	check(autosaves >= 1, "autosave ran during the match")
	var saved: Dictionary = SaveManager.load_payload("auto")
	check(not saved.is_empty() and Array(saved.get("units", [])).size() > 0, "the autosave is a loadable match")
	main.queue_free()
	await frames(2)
	SaveManager.delete_save("auto")


## One-line summary of a player: villagers, soldiers, buildings, era.
func _state(world: World, p: int) -> String:
	var vil: int = 0
	var mil: int = 0
	for u: Unit in world.units:
		if u.owner_id == p and not u.is_dead:
			if u.can_gather():
				vil += 1
			else:
				mil += 1
	var bld: int = world.buildings.filter(func(b: Building) -> bool: return b.owner_id == p).size()
	return "p%d vil=%d mil=%d bld=%d era=%d" % [p, vil, mil, bld, GameState.era_of(p)]
