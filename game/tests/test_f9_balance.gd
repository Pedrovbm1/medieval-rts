extends TestSuite
## F9: balance and closing games. A push must be able to finish a base.

var main: Node
var world: World
var scen: ScenarioRunner


func _open() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = "arena"
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")
	scen = main.get_node("ScenarioRunner")


func _close() -> void:
	Engine.time_scale = 1.0
	main.queue_free()
	await frames(2)


func _army(type_id: String, player: int, count: int, cell: Vector2i) -> Array[Unit]:
	var out: Array[Unit] = []
	for i: int in count:
		out.append(world.spawn_unit(type_id, player, world.cell_center(cell) + Vector2((i % 3) * 34.0, (i / 3) * 34.0)))
	return out


func _alive(units: Array[Unit]) -> Array[Unit]:
	return units.filter(func(u: Unit) -> bool: return is_instance_valid(u) and not u.is_dead and world.units.has(u))


func test_a_wave_razes_town_center() -> void:
	await _open()
	var tc: Building = world.place_building("town_center", 1, Vector2i(70, 60))
	var house: Building = world.place_building("house", 1, Vector2i(66, 56))
	var wave: Array[Unit] = []
	for t: String in ["militia", "militia", "militia", "spearman", "spearman", "spearman", "swordsman", "swordsman", "swordsman", "archer", "archer", "archer", "skirmisher", "knight", "knight", "knight", "ram", "ram"]:
		wave.append_array(_army(t, 0, 1, Vector2i(40 + wave.size() % 6, 58 + wave.size() / 6)))
	world.combat.attack_move(wave, tc.position)
	Engine.time_scale = 4.0
	var t0: float = scen.elapsed
	var tc_id: int = tc.get_instance_id()
	var log_t: float = 0.0
	while instance_from_id(tc_id) != null and scen.elapsed - t0 < 240.0:
		await physics_frames(1)
		if scen.elapsed - t0 >= log_t:
			log_t += 20.0
			var busy: int = 0
			var idle: int = 0
			for u: Unit in _alive(wave):
				if u.task != null:
					busy += 1
				elif not u.is_moving():
					idle += 1
			var hp: int = tc.hp if instance_from_id(tc_id) != null else 0
			print("  info  t=%.0f tc_hp=%d alive=%d busy=%d idle=%d" % [scen.elapsed - t0, hp, _alive(wave).size(), busy, idle])
	Engine.time_scale = 1.0
	check(instance_from_id(tc_id) == null, "an 18-unit mixed wave razes an undefended Town Center (%.0f s)" % (scen.elapsed - t0))
	await _close()


func test_b_raiders_turn_on_defenders() -> void:
	await _open()
	var house: Building = world.place_building("house", 1, Vector2i(62, 58))
	var raiders: Array[Unit] = _army("militia", 0, 4, Vector2i(56, 58))
	world.combat.attack_move(raiders, house.position)
	Engine.time_scale = 4.0
	var t0: float = scen.elapsed
	while scen.elapsed - t0 < 30.0 and not raiders.any(func(u: Unit) -> bool: return u.task is AttackTask and (u.task as AttackTask).target == house):
		await physics_frames(1)
	check(raiders.any(func(u: Unit) -> bool: return u.task is AttackTask and (u.task as AttackTask).target == house), "attack-moving raiders start hitting the house")
	var defenders: Array[Unit] = _army("swordsman", 1, 2, Vector2i(64, 62))
	for d: Unit in defenders:
		world.behavior.assign(d, AttackTask.new(d, world, raiders[0], true))
	t0 = scen.elapsed
	var turned: bool = false
	while scen.elapsed - t0 < 15.0 and not turned:
		await physics_frames(1)
		turned = _alive(raiders).any(func(u: Unit) -> bool: return u.task is AttackTask and (u.task as AttackTask).target is Unit)
	Engine.time_scale = 1.0
	check(turned, "when soldiers arrive the raiders fight them instead of the wall")
	await _close()


func test_c_wave_razes_economy_buildings() -> void:
	await _open()
	var farm: Building = world.place_building("farm", 1, Vector2i(66, 60))
	var camp: Building = world.place_building("lumber_camp", 1, Vector2i(69, 62))
	var wave: Array[Unit] = _army("militia", 0, 10, Vector2i(50, 60))
	var farm_id: int = farm.get_instance_id()
	var camp_id: int = camp.get_instance_id()
	world.combat.attack_move(wave, farm.position)
	Engine.time_scale = 4.0
	var t0: float = scen.elapsed
	while (instance_from_id(farm_id) != null or instance_from_id(camp_id) != null) and scen.elapsed - t0 < 150.0:
		await physics_frames(1)
	Engine.time_scale = 1.0
	var busy: Array = _alive(wave).map(func(u: Unit) -> String: return str(u.task.kind if u.task != null else "none") + ("/move" if u.is_moving() else ""))
	print("  info  farm alive=%s camp alive=%s units=%s" % [instance_from_id(farm_id) != null, instance_from_id(camp_id) != null, busy])
	check(instance_from_id(farm_id) == null, "an attack-move wave razes a farm")
	check(instance_from_id(camp_id) == null, "and then the lumber camp in sight next to it")
	await _close()


func test_d_ai_resigns_when_hopeless() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = "skirmish"
	main.ai_override = {1: "normal"}
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")
	scen = main.get_node("ScenarioRunner")
	var rules: MatchRules = main.get_node("MatchRules")
	for u: Unit in world.units.duplicate():
		if u.owner_id == 1:
			u.take_damage(99999, null)
	GameState.add_resource(1, "food", -GameState.get_resource(1, "food"))
	Engine.time_scale = 4.0
	var t0: float = scen.elapsed
	while not rules.ended and scen.elapsed - t0 < 60.0:
		await physics_frames(1)
	Engine.time_scale = 1.0
	check(rules.ended and rules.winner_id == 0, "an AI with no villagers, no army and no food resigns (%.0f s)" % (scen.elapsed - t0))
	check(world.buildings.any(func(b: Building) -> bool: return b.owner_id == 1), "even though its Town Center still stands")
	await _close()
