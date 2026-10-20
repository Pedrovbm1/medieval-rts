extends TestSuite
## IDEAS-AOE2 batch 2c: three touch formations (line, box, wedge) and an
## attack-move button for the player's army.

var main: Node
var world: World
var scen: ScenarioRunner


func _open(scenario: String) -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = scenario
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


func _army() -> Array[Unit]:
	var out: Array[Unit] = []
	var at: Vector2 = world.cell_center(Vector2i(50, 60))
	for i: int in 4:
		out.append(world.spawn_unit("militia", 0, at + Vector2(0, i * 30)))
	for i: int in 4:
		out.append(world.spawn_unit("archer", 0, at + Vector2(-40, i * 30)))
	for i: int in 2:
		out.append(world.spawn_unit("knight", 0, at + Vector2(-80, i * 30)))
	return out


## Average projection of a role's slots along `facing` (bigger = more forward).
func _depth(units: Array[Unit], slots: Array[Vector2], role: String, facing: Vector2) -> float:
	var sum: float = 0.0
	var n: int = 0
	for i: int in units.size():
		if FormationLayout.role_of(units[i]) == role:
			sum += slots[i].dot(facing)
			n += 1
	return sum / maxf(1.0, n)


func test_a_line_puts_melee_in_front_and_ranged_behind() -> void:
	await _open("arena")
	var units: Array[Unit] = _army()
	var facing: Vector2 = Vector2.RIGHT
	var center: Vector2 = world.cell_center(Vector2i(70, 60))
	var slots: Array[Vector2] = FormationLayout.layout("line", center, facing, units, 40.0, world.nav)
	check(slots.size() == units.size(), "one slot per unit")
	check(_depth(units, slots, "melee", facing) > _depth(units, slots, "ranged", facing) + 30.0, "melee ranks ahead of the archers")
	check(absf(_depth(units, slots, "cavalry", facing) - _depth(units, slots, "melee", facing)) < 45.0, "knights share the front with the infantry")
	var roles: Dictionary = {}
	for u: Unit in units:
		roles[FormationLayout.role_of(u)] = int(roles.get(FormationLayout.role_of(u), 0)) + 1
	check(roles == {"melee": 4, "ranged": 4, "cavalry": 2}, "roles are read from the data: %s" % [roles])
	await _close()


func test_b_box_keeps_ranged_inside_and_wedge_leads_with_cavalry() -> void:
	await _open("arena")
	var units: Array[Unit] = _army()
	var center: Vector2 = world.cell_center(Vector2i(70, 60))
	var box: Array[Vector2] = FormationLayout.layout("box", center, Vector2.RIGHT, units, 40.0, world.nav)
	var ranged_far: float = 0.0
	var melee_near: float = INF
	for i: int in units.size():
		var d: float = box[i].distance_to(center)
		if FormationLayout.role_of(units[i]) == "ranged":
			ranged_far = maxf(ranged_far, d)
		else:
			melee_near = minf(melee_near, d)
	check(ranged_far < melee_near, "box: every archer is closer to the middle than any melee (%.0f < %.0f)" % [ranged_far, melee_near])
	var facing: Vector2 = Vector2.DOWN
	var wedge: Array[Vector2] = FormationLayout.layout("wedge", center, facing, units, 40.0, world.nav)
	var tip: float = -INF
	var tip_role: String = ""
	for i: int in units.size():
		var p: float = wedge[i].dot(facing)
		if p > tip:
			tip = p
			tip_role = FormationLayout.role_of(units[i])
	check(tip_role == "cavalry", "wedge: a knight is at the tip")
	check(_depth(units, wedge, "cavalry", facing) > _depth(units, wedge, "melee", facing) and _depth(units, wedge, "melee", facing) > _depth(units, wedge, "ranged", facing), "wedge: cavalry, then melee, then archers")
	var plain: Array[Vector2] = FormationLayout.layout("none", center, facing, units, 40.0, world.nav)
	check(plain.size() == units.size() and plain.all(func(p: Vector2) -> bool: return p.distance_to(center) < 200.0), "'none' is the plain spread around the point")
	await _close()


func test_c_group_orders_use_the_chosen_formation() -> void:
	await _open("arena")
	var units: Array[Unit] = _army()
	var sel: SelectionController = main.get_node("SelectionController")
	sel.set_selection(units)
	check(sel.formation == "none" and sel.cycle_formation() == "line", "the formation cycles none -> line")
	var target: Vector2 = world.cell_center(Vector2i(70, 60))
	sel.order_move(target)
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return units.all(func(u: Unit) -> bool: return not u.is_moving()), 60.0)
	Engine.time_scale = 1.0
	var facing: Vector2 = Vector2.RIGHT
	var melee_x: float = 0.0
	var ranged_x: float = 0.0
	for u: Unit in units:
		if FormationLayout.role_of(u) == "melee":
			melee_x += u.position.dot(facing) / 4.0
		elif FormationLayout.role_of(u) == "ranged":
			ranged_x += u.position.dot(facing) / 4.0
	check(melee_x > ranged_x + 20.0, "after a line move the militia stand ahead of the archers (%.0f vs %.0f)" % [melee_x, ranged_x])
	check(sel.cycle_formation() == "box" and sel.cycle_formation() == "wedge" and sel.cycle_formation() == "none", "and on through box, wedge, none")
	await _close()


func test_d_attack_move_button_arms_the_next_tap() -> void:
	await _open("arena")
	var units: Array[Unit] = _army()
	var sel: SelectionController = main.get_node("SelectionController")
	var hud: Hud = main.get_node("Hud")
	sel.set_selection(units)
	await frames(1)
	check(hud.attack_button != null and hud.formation_button != null, "soldiers get Attack and Formation buttons")
	hud.attack_button.pressed.emit()
	check(sel.attack_armed, "the Attack button arms the next tap")
	var target: Vector2 = world.cell_center(Vector2i(70, 60))
	sel.order_move(target)
	check(units.all(func(u: Unit) -> bool: return u.attack_move and u.is_moving()), "the tap becomes an attack-move for the whole group")
	check(not sel.attack_armed, "and the button disarms")
	var v: Unit = world.spawn_unit("villager", 0, world.cell_center(Vector2i(50, 50)))
	sel.set_selection([v] as Array[Unit])
	await frames(1)
	check(hud.attack_button == null, "villagers alone get no Attack button")
	await _close()
