extends TestSuite
## F5.5: every new unit has a distinct role that wins its matchup, and every
## unit type is used in at least one army test.

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
	var spacing: float = 36.0
	var origin: Vector2 = world.cell_center(cell) - Vector2(spacing * 0.5, spacing * (count / 2) * 0.5)
	for i: int in count:
		out.append(world.spawn_unit(type_id, player, origin + Vector2(i % 2, i / 2) * spacing))
	return out


func _alive(units: Array[Unit]) -> Array[Unit]:
	return units.filter(func(u: Unit) -> bool: return is_instance_valid(u) and not u.is_dead and world.units.has(u))


func _fight(a: Array[Unit], b: Array[Unit], max_s: float) -> float:
	Engine.time_scale = 4.0
	var t0: float = scen.elapsed
	var next_order: float = 0.0
	while not _alive(a).is_empty() and not _alive(b).is_empty() and scen.elapsed - t0 < max_s:
		if scen.elapsed - t0 >= next_order:
			next_order += 5.0
			_engage(_alive(a), _alive(b))
			_engage(_alive(b), _alive(a))
		await physics_frames(1)
	Engine.time_scale = 1.0
	return scen.elapsed - t0


## Idle units attack-move toward the enemy centre (a player keeping the fight going).
func _engage(mine: Array[Unit], theirs: Array[Unit]) -> void:
	var idle: Array[Unit] = mine.filter(func(u: Unit) -> bool: return u.task == null and not u.data.has("heal"))
	if idle.is_empty() or theirs.is_empty():
		return
	var pos: Array[Vector2] = []
	for u: Unit in theirs:
		pos.append(u.position)
	world.combat.attack_move(idle, Formation.centroid(pos))


func _duel(winner_type: String, loser_type: String, count: int, label: String, min_left: int = 1) -> void:
	await _open()
	var a: Array[Unit] = _army(winner_type, 0, count, Vector2i(55, 60))
	var b: Array[Unit] = _army(loser_type, 1, count, Vector2i(61, 60))
	var t: float = await _fight(a, b, 150.0)
	check(_alive(b).is_empty() and _alive(a).size() >= min_left,
		"%s: %d %s beat %d %s (%d left, %.0f s)" % [label, count, winner_type, count, loser_type, _alive(a).size(), t])
	await _close()


func test_a_skirmishers_hunt_archers() -> void:
	await _duel("skirmisher", "archer", 10, "anti-archer", 6)


func test_b_swordsmen_outclass_militia() -> void:
	await _duel("swordsman", "militia", 10, "heavy infantry", 6)


func test_c_camels_counter_knights() -> void:
	await _duel("camel_rider", "knight", 10, "anti-cavalry", 4)


func test_d_mangonel_splash_hits_groups() -> void:
	await _open()
	var blob: Array[Unit] = _army("archer", 1, 12, Vector2i(64, 60))
	for u: Unit in blob:
		u.stance = "passive"
	var mangonel: Unit = world.spawn_unit("mangonel", 0, world.cell_center(Vector2i(57, 60)))
	world.behavior.assign(mangonel, AttackTask.new(mangonel, world, blob[5], true))
	Engine.time_scale = 4.0
	var shots: int = world.combat.shots_fired
	while world.combat.shots_fired == shots and scen.elapsed < 30.0:
		await physics_frames(1)
	await physics_frames(60)
	Engine.time_scale = 1.0
	var hurt: int = blob.filter(func(u: Unit) -> bool: return not world.units.has(u) or u.hp < u.max_hp).size()
	check(hurt >= 3, "one mangonel stone hurts a group of archers (%d hit)" % hurt)
	await _close()


func test_e_mangonel_backs_off_when_rushed() -> void:
	await _open()
	var mangonel: Unit = world.spawn_unit("mangonel", 0, world.cell_center(Vector2i(60, 60)))
	var target: Unit = world.spawn_unit("archer", 1, world.cell_center(Vector2i(61, 60)))
	target.stance = "passive"
	world.behavior.assign(mangonel, AttackTask.new(mangonel, world, target, true))
	var start_gap: float = Combat.gap(mangonel, target)
	await physics_frames(120)
	check(Combat.gap(mangonel, target) > start_gap + 32.0, "a mangonel too close to its target backs off before firing")
	await _close()


func test_f_monks_keep_their_side_alive() -> void:
	await _open()
	var a: Array[Unit] = _army("militia", 0, 6, Vector2i(56, 60))
	var monks: Array[Unit] = _army("monk", 0, 2, Vector2i(53, 60))
	var b: Array[Unit] = _army("militia", 1, 6, Vector2i(61, 60))
	var t: float = await _fight(a, b, 120.0)
	check(_alive(b).is_empty() and not _alive(a).is_empty(), "6 militia + 2 monks beat 6 militia (%d left, %.0f s)" % [_alive(a).size(), t])
	check(world.combat.healed >= 40, "the monks healed %d HP during the fight" % world.combat.healed)
	check(_alive(monks).size() == 2, "monks stayed behind the line and survived")
	await _close()


func test_g_unique_unit_is_faction_only() -> void:
	check(ConstructionSystem.unit_allowed(0, "camel_rider"), "Northvale can train its camel riders")
	var saved: Dictionary = GameState.civs.duplicate()
	GameState.civs[1] = "other_faction"
	check(not ConstructionSystem.unit_allowed(1, "camel_rider"), "another faction cannot")
	check(ConstructionSystem.unit_allowed(1, "knight"), "regular units stay available to everyone")
	GameState.civs = saved


func test_h_full_roster_army() -> void:
	await _open()
	var types: Array[String] = ["militia", "spearman", "swordsman", "archer", "skirmisher", "knight", "camel_rider", "scout", "mangonel", "monk"]
	var a: Array[Unit] = []
	var b: Array[Unit] = []
	var row: int = 0
	for type_id: String in types:
		a.append_array(_army(type_id, 0, 2, Vector2i(52, 44 + row * 3)))
		b.append_array(_army(type_id, 1, 2, Vector2i(66, 44 + row * 3)))
		row += 1
	var house: Building = world.place_building("house", 1, Vector2i(72, 58))
	var rams: Array[Unit] = _army("ram", 0, 2, Vector2i(64, 76))
	for r: Unit in rams:
		world.behavior.assign(r, AttackTask.new(r, world, house, true))
	var t: float = await _fight(a, b, 120.0)
	var left_a: Array = _alive(a).map(func(u: Unit) -> String: return "%s(%d,%s%s)" % [u.unit_type, u.hp, u.task.kind if u.task != null else "idle", "/moving" if u.is_moving() else ""])
	var left_b: Array = _alive(b).map(func(u: Unit) -> String: return "%s(%d,%s%s)" % [u.unit_type, u.hp, u.task.kind if u.task != null else "idle", "/moving" if u.is_moving() else ""])
	print("  info  roster battle left a=%s b=%s" % [left_a, left_b])
	check(_alive(a).is_empty() or _alive(b).is_empty(), "a 20v20 army with every unit type ends in %.0f s" % t)
	var used: PackedStringArray = PackedStringArray()
	for type_id: String in types + ["ram"]:
		if int(world.combat.damage_by_type.get(type_id, 0)) > 0:
			used.append(type_id)
	if world.combat.healed > 0:
		used.append("monk")
	var missing: Array = (types + ["ram"]).filter(func(t2: String) -> bool: return not used.has(t2))
	check(missing.is_empty(), "every unit type did its job in the battle (missing: %s)" % str(missing))
	await _close()
