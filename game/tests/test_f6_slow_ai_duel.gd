extends TestSuite
## F6 (slow, ~16 min real): Hard AI vs Normal AI, 4 matches with different
## seeds and alternating start positions. Gate: Hard wins at least 3 of 4.
## Run with: godot --headless --path game tests/run_tests.tscn -- slow


const DUEL_MAP: String = "tierras_doradas"


func _duel(hard_player: int, seed: int) -> Dictionary:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = "skirmish"
	# A point-symmetric map: on the noise map the start corner decided more
	# than the difficulty (Hard won every match from one corner, drew from
	# the other).
	main.map_override = DUEL_MAP
	var normal_player: int = 1 - hard_player
	main.ai_override = {hard_player: "hard", normal_player: "normal"}
	main.ai_seed = seed
	add_to_tree(main)
	await frames(1)
	var rules: MatchRules = main.get_node("MatchRules")
	Engine.time_scale = 8.0
	var world: World = main.get_node("World")
	var next_report: float = 600.0
	while not rules.ended and rules.elapsed < 45.0 * 60.0:
		await physics_frames(1)
		if rules.elapsed >= next_report:
			next_report += 600.0
			print("        t=%.0f min  %s | %s" % [rules.elapsed / 60.0, _state(world, hard_player, "hard"), _state(world, normal_player, "normal")])
	Engine.time_scale = 1.0
	var result: Dictionary = {"ended": rules.ended, "hard_won": rules.ended and rules.winner_id == hard_player, "minutes": rules.elapsed / 60.0}
	main.queue_free()
	await frames(2)
	return result


func test_hard_beats_normal_three_of_four() -> void:
	var wins: int = 0
	var report: PackedStringArray = PackedStringArray()
	for i: int in 4:
		var hard_player: int = i % 2
		var r: Dictionary = await _duel(hard_player, 11 + i * 7)
		if bool(r["hard_won"]):
			wins += 1
		report.append("%s %.0f min" % ["hard" if bool(r["hard_won"]) else ("normal" if bool(r["ended"]) else "draw"), float(r["minutes"])])
		print("  info  duel %d (hard = player %d): %s" % [i + 1, hard_player, report[report.size() - 1]])
	check(wins >= 3, "Hard beats Normal in %d of 4 matches (%s)" % [wins, ", ".join(report)])


func _state(world: World, p: int, label: String) -> String:
	var vil: int = 0
	var mil: int = 0
	for u: Unit in world.units:
		if u.owner_id == p and not u.is_dead:
			if u.can_gather():
				vil += 1
			else:
				mil += 1
	var bld: int = world.buildings.filter(func(b: Building) -> bool: return b.owner_id == p).size()
	return "%s vil=%d mil=%d bld=%d era=%d" % [label, vil, mil, bld, GameState.era_of(p)]
