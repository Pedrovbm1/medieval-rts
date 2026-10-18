extends TestSuite
## F5: typed damage, counters, battles, stances, siege and pooling (no leaks).

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


## Spawns `count` units of `type` for `player` in a block of 2-unit-wide rows centred on cell.
func _army(type_id: String, player: int, count: int, cell: Vector2i) -> Array[Unit]:
	var out: Array[Unit] = []
	var spacing: float = 34.0
	var cols: int = 2
	var origin: Vector2 = world.cell_center(cell) - Vector2(spacing * 0.5, spacing * (count / cols) * 0.5)
	for i: int in count:
		out.append(world.spawn_unit(type_id, player, origin + Vector2(i % cols, i / cols) * spacing))
	return out


func _alive(units: Array[Unit]) -> Array[Unit]:
	return units.filter(func(u: Unit) -> bool: return is_instance_valid(u) and not u.is_dead and world.units.has(u))


func _hp(units: Array[Unit]) -> int:
	var total: int = 0
	for u: Unit in _alive(units):
		total += u.hp
	return total


## Runs until one side is wiped out or `max_s` game seconds pass.
## With `commander`, both sides re-issue an attack-move at the other army's
## centre every 5 s, like a player keeping the fight going.
func _fight(a: Array[Unit], b: Array[Unit], max_s: float, commander: bool = false) -> float:
	Engine.time_scale = 4.0
	var t0: float = scen.elapsed
	var next_order: float = 5.0
	while not _alive(a).is_empty() and not _alive(b).is_empty() and scen.elapsed - t0 < max_s:
		await physics_frames(1)
		if commander and scen.elapsed - t0 >= next_order:
			next_order += 5.0
			_reengage(_alive(a), _alive(b))
			_reengage(_alive(b), _alive(a))
	Engine.time_scale = 1.0
	return scen.elapsed - t0


func _reengage(mine: Array[Unit], theirs: Array[Unit]) -> void:
	var idle: Array[Unit] = mine.filter(func(u: Unit) -> bool: return u.task == null)
	if idle.is_empty() or theirs.is_empty():
		return
	var pos: Array[Vector2] = []
	for u: Unit in theirs:
		pos.append(u.position)
	world.combat.attack_move(idle, Formation.centroid(pos))


func test_a_damage_formula() -> void:
	var spear: Dictionary = DataLoader.get_entry("units", "spearman")
	var knight: Dictionary = DataLoader.get_entry("units", "knight")
	var archer: Dictionary = DataLoader.get_entry("units", "archer")
	var militia: Dictionary = DataLoader.get_entry("units", "militia")
	var vs_knight: int = Combat.damage(spear["combat"], Combat.classes_of(knight), knight["armor"])
	check(vs_knight == 1 + 18, "spearman vs knight: (3 pierce - 2 armor) + 18 bonus = 19 (got %d)" % vs_knight)
	var vs_militia: int = Combat.damage(spear["combat"], Combat.classes_of(militia), militia["armor"])
	check(vs_militia == 1, "spearman vs militia: 3 pierce - 3 armor -> minimum 1 (got %d)" % vs_militia)
	var arrow_spear: int = Combat.damage(archer["combat"], Combat.classes_of(spear), spear["armor"])
	check(arrow_spear == 9, "archer vs spearman: 5 pierce + 4 bonus = 9 (got %d)" % arrow_spear)
	var ram: Dictionary = DataLoader.get_entry("units", "ram")
	var house: Dictionary = DataLoader.get_entry("buildings", "house")
	check(Combat.damage(ram["combat"], Combat.classes_of(house), house["armor"]) == 77, "ram vs building: 2 crush + 75 bonus = 77")
	check(Combat.damage(archer["combat"], Combat.classes_of(house), house["armor"]) == 1, "arrows barely scratch buildings (1)")


func test_b_spearmen_counter_knights() -> void:
	await _open()
	var spears: Array[Unit] = _army("spearman", 0, 10, Vector2i(56, 60))
	var knights: Array[Unit] = _army("knight", 1, 10, Vector2i(61, 60))
	var start_hp: int = _hp(spears)
	var t: float = await _fight(spears, knights, 120.0)
	var lost: float = 1.0 - float(_hp(spears)) / start_hp
	check(_alive(knights).is_empty() and not _alive(spears).is_empty(), "10 spearmen beat 10 knights (%d spears left, %.0f s)" % [_alive(spears).size(), t])
	check(lost < 0.5, "spearmen lose under 50%% of their HP (%.0f%%)" % (lost * 100.0))
	await _close()


func test_c_archers_counter_spearmen() -> void:
	await _open()
	var archers: Array[Unit] = _army("archer", 0, 10, Vector2i(55, 60))
	var spears: Array[Unit] = _army("spearman", 1, 10, Vector2i(60, 60))
	var t: float = await _fight(archers, spears, 120.0)
	var dead: int = 10 - _alive(archers).size()
	check(_alive(spears).is_empty(), "10 archers beat 10 spearmen (%.0f s)" % t)
	check(dead <= 4, "losing at most 4 archers (lost %d)" % dead)
	await _close()


func test_d_knights_counter_archers() -> void:
	await _open()
	var knights: Array[Unit] = _army("knight", 0, 10, Vector2i(55, 60))
	var archers: Array[Unit] = _army("archer", 1, 10, Vector2i(61, 60))
	await _fight(knights, archers, 120.0)
	check(_alive(archers).is_empty() and _alive(knights).size() >= 7, "knights run down archers (%d knights left)" % _alive(knights).size())
	await _close()


func test_e_battle_20v20_under_60s() -> void:
	await _open()
	var a: Array[Unit] = []
	var b: Array[Unit] = []
	var row: int = 0
	for type_id: String in ["militia", "spearman", "archer", "knight"]:
		a.append_array(_army(type_id, 0, 5, Vector2i(54, 54 + row * 4)))
		b.append_array(_army(type_id, 1, 5, Vector2i(61, 54 + row * 4)))
		row += 1
	var proj_before: int = world.combat.shots_fired
	# Both players order an attack-move at the other army, as a player would.
	world.combat.attack_move(a, world.cell_center(Vector2i(63, 60)))
	world.combat.attack_move(b, world.cell_center(Vector2i(52, 60)))
	var t: float = await _fight(a, b, 90.0, true)
	check(_alive(a).is_empty() or _alive(b).is_empty(), "the 20v20 battle has a winner")
	check(t < 60.0, "and ends in %.0f s (< 60)" % t)
	check(world.combat.shots_fired > proj_before, "archers shot arrows (%d)" % (world.combat.shots_fired - proj_before))
	await _close()


func test_f_ram_razes_buildings() -> void:
	await _open()
	var house: Building = world.place_building("house", 1, Vector2i(62, 58))
	var rams: Array[Unit] = _army("ram", 0, 2, Vector2i(56, 59))
	var archers: Array[Unit] = _army("archer", 0, 4, Vector2i(56, 64))
	for r: Unit in rams:
		world.behavior.assign(r, AttackTask.new(r, world, house, true))
	var house_hp: int = house.max_hp
	Engine.time_scale = 4.0
	var t0: float = scen.elapsed
	var house_id: int = house.get_instance_id()
	while instance_from_id(house_id) != null and scen.elapsed - t0 < 90.0:
		await physics_frames(1)
	Engine.time_scale = 1.0
	check(instance_from_id(house_id) == null, "2 rams destroy a house (%d HP) in %.0f s" % [house_hp, scen.elapsed - t0])
	check(world.nav.is_walkable(Vector2i(62, 58)), "the ruined footprint is walkable again")
	var tc: Building = world.place_building("town_center", 1, Vector2i(66, 63))
	for ar: Unit in archers:
		world.behavior.assign(ar, AttackTask.new(ar, world, tc, true))
	await physics_frames(240)
	check(tc.hp > tc.max_hp * 0.95, "4 archers barely scratch a Town Center (%d/%d)" % [tc.hp, tc.max_hp])
	await _close()


func test_g_stances() -> void:
	await _open()
	var holder: Unit = world.spawn_unit("militia", 0, world.cell_center(Vector2i(50, 50)))
	holder.stance = "hold"
	var bait: Unit = world.spawn_unit("archer", 1, world.cell_center(Vector2i(54, 50)))
	bait.stance = "passive"
	var start: Vector2 = holder.position
	await physics_frames(120)
	check(holder.position.distance_to(start) < 8.0, "hold stance does not chase an enemy 4 tiles away")
	var chaser: Unit = world.spawn_unit("militia", 0, world.cell_center(Vector2i(50, 70)))
	var prey: Unit = world.spawn_unit("archer", 1, world.cell_center(Vector2i(53, 70)))
	prey.stance = "passive"
	Engine.time_scale = 4.0
	await physics_frames(240)
	Engine.time_scale = 1.0
	check(not is_instance_valid(prey) or prey.is_dead or not world.units.has(prey), "aggressive stance hunts an enemy in sight")
	var farmer: Unit = world.spawn_unit("villager", 0, world.cell_center(Vector2i(70, 80)))
	var passer: Unit = world.spawn_unit("militia", 1, world.cell_center(Vector2i(72, 80)))
	passer.stance = "passive"
	await physics_frames(60)
	check(farmer.task == null, "passive villagers do not start fights on their own")
	await _close()


func test_h_two_hundred_deaths_no_leaks() -> void:
	await _open()
	await physics_frames(5)
	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var kills_before: int = world.combat.kills
	var waves: int = 0
	Engine.time_scale = 4.0
	while world.combat.kills - kills_before < 200 and waves < 20:
		var a: Array[Unit] = _army("militia", 0, 12, Vector2i(56, 60))
		var b: Array[Unit] = _army("militia", 1, 12, Vector2i(60, 60))
		world.combat.attack_move(a, world.cell_center(Vector2i(60, 60)))
		world.combat.attack_move(b, world.cell_center(Vector2i(56, 60)))
		await _fight(a, b, 60.0)
		Engine.time_scale = 4.0
		# Mop up the survivors so every wave ends with no units left.
		for u: Unit in _alive(a) + _alive(b):
			u.take_damage(9999, null)
		await physics_frames(80)
		waves += 1
	Engine.time_scale = 1.0
	await physics_frames(80)
	var deaths: int = world.combat.kills - kills_before
	var in_tree: int = world.entities.get_children().filter(func(n: Node) -> bool: return n is Unit).size()
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - orphans_before
	check(deaths >= 200, "%d units died over %d waves" % [deaths, waves])
	check(world.units.is_empty() and in_tree == 0, "no unit nodes left in the tree after the waves (%d)" % in_tree)
	check(world.units_created <= 30, "only %d unit nodes were ever created: the pool reuses them" % world.units_created)
	check(orphans <= world.pooled_units(), "orphan nodes (%d) are exactly the pooled units (%d): nothing leaks" % [orphans, world.pooled_units()])
	check(world.combat.active_projectiles() == 0, "no arrows left in flight")
	await _close()
