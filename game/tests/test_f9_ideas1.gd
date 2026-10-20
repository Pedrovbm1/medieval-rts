extends TestSuite
## IDEAS-AOE2 batch 1: town bell and garrison, repairs, siege with a charge
## and visible breaches, alerts in three levels with a minimap icon and an
## on-screen arrow, the end-of-match report and the fair AI.

var main: Node
var world: World
var scen: ScenarioRunner
var hud: Hud


func _open(scenario: String, ai: Dictionary = {}, fair: bool = true) -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = scenario
	main.fair_ai = fair
	if not ai.is_empty():
		main.ai_override = ai
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")
	scen = main.get_node("ScenarioRunner")
	hud = main.get_node("Hud")


func _close() -> void:
	Engine.time_scale = 1.0
	main.queue_free()
	await frames(2)


func _wait_until(cond: Callable, max_game_s: float) -> void:
	var t0: float = scen.elapsed
	while not cond.call() and scen.elapsed - t0 < max_game_s:
		await physics_frames(1)


func _tc(owner: int) -> Building:
	for b: Building in world.buildings:
		if b.owner_id == owner and b.building_type == "town_center":
			return b
	return null


func _villagers(owner: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in world.units:
		if u.owner_id == owner and u.can_gather() and not u.is_dead:
			out.append(u)
	return out


func test_a_bell_shelters_villagers_and_arms_the_town_center() -> void:
	await _open("eco12")
	var tc: Building = _tc(0)
	var before: int = _villagers(0).size()
	var pop: int = GameState.pop_used(0)
	check(tc.garrison_slots() == 15 and tc.can_garrison(_villagers(0)[0]), "the Town Center shelters up to 15 villagers")
	var sent: int = main.ring_bell()
	check(sent == before and main.bell_on, "the bell sends every villager nearby inside (%d/%d)" % [sent, before])
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return tc.garrison.size() == sent, 60.0)
	Engine.time_scale = 1.0
	check(tc.garrison.size() == sent, "they all get in (%d/%d)" % [tc.garrison.size(), sent])
	check(_villagers(0).is_empty() and not tc.garrison[0].visible, "sheltered villagers are hidden and out of the unit list")
	check(GameState.pop_used(0) == pop, "population still counts them (%d)" % GameState.pop_used(0))
	check(tc.garrison_arrows() == mini(sent, 10), "each one adds an arrow, ten at most (%d)" % tc.garrison_arrows())
	var foe: Unit = world.spawn_unit("militia", 1, tc.position + Vector2(200, 0))
	foe.stance = "passive"
	await physics_frames(2)
	var shots: int = world.combat.shots_fired
	tc.attack_cooldown = 0.0
	world.combat._towers(0.25)
	check(world.combat.shots_fired - shots == 1 + tc.garrison_arrows(), "one volley = 1 + garrison arrows (%d)" % (world.combat.shots_fired - shots))
	world.remove_unit(foe)
	var out: int = main.ring_bell()
	await physics_frames(2)
	check(out == sent and not main.bell_on and tc.garrison.is_empty(), "the second ring lets everyone out (%d)" % out)
	check(_villagers(0).size() == before, "the villagers are back in the match (%d)" % _villagers(0).size())
	var working: int = 0
	for v: Unit in _villagers(0):
		if v.task is GatherTask:
			working += 1
	check(working >= before / 2, "most go back to the work they were doing (%d/%d)" % [working, before])
	await _close()


func test_b_villagers_repair_damaged_buildings() -> void:
	await _open("arena")
	var house: Building = world.place_building("house", 0, Vector2i(60, 60))
	house.add_progress(1.0)
	var v: Unit = world.spawn_unit("villager", 0, world.cell_center(Vector2i(57, 60)))
	check(not RepairTask.can_repair(v, house), "a whole building needs no repair")
	house.hp = 100
	var foundation: Building = world.place_building("house", 0, Vector2i(66, 60))
	foundation.make_foundation()
	check(RepairTask.can_repair(v, house) and not RepairTask.can_repair(v, foundation), "only finished, damaged, own buildings can be repaired")
	GameState.add_resource(0, "wood", 100 - GameState.get_resource(0, "wood"))
	world.behavior.assign(v, RepairTask.new(v, world, house))
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return house.repairers.has(v), 20.0)
	check(house.repairers.has(v), "the villager shows up as a repairer (hammer icon)")
	await _wait_until(func() -> bool: return house.hp >= house.max_hp, 90.0)
	Engine.time_scale = 1.0
	check(house.hp == house.max_hp, "the house is whole again (%d/%d)" % [house.hp, house.max_hp])
	var paid: int = 100 - GameState.get_resource(0, "wood")
	check(paid >= 10 and paid <= 12, "repairing 300 HP of a 30-wood house costs about half the share: %d wood" % paid)
	await physics_frames(2)
	check(house.repairers.is_empty() and not (v.task is RepairTask), "done: the repairer leaves")
	house.hp = 100
	GameState.add_resource(0, "wood", -GameState.get_resource(0, "wood"))
	world.behavior.assign(v, RepairTask.new(v, world, house))
	Engine.time_scale = 8.0
	await _wait_until(func() -> bool: return not (v.task is RepairTask), 30.0)
	Engine.time_scale = 1.0
	# The first wood is due after ~27 HP (0.0375 wood per HP): it stops there.
	check(house.hp <= 130 and not (v.task is RepairTask), "with no wood the repair stops as soon as the first wood is due (hp %d)" % house.hp)
	await _close()


func test_c_ram_in_era_three_charges_and_walls_leave_a_breach() -> void:
	var ram: Dictionary = DataLoader.get_entry("units", "ram")
	check(int(ram["era"]) == 3 and float(ram["speed"]) >= 0.85, "the ram comes in Era III and is a bit faster")
	check(int(DataLoader.get_entry("buildings", "stone_wall")["hp"]) == 1200, "stone walls have 1200 HP")
	await _open("arena")
	var wall: Building = world.place_building("stone_wall", 1, Vector2i(60, 60))
	wall.add_progress(1.0)
	var r: Unit = world.spawn_unit("ram", 0, world.cell_center(Vector2i(57, 60)))
	world.behavior.assign(r, AttackTask.new(r, world, wall, true))
	Engine.time_scale = 4.0
	await _wait_until(func() -> bool: return wall.hp < wall.max_hp, 30.0)
	Engine.time_scale = 1.0
	var first: int = wall.max_hp - wall.hp
	check(first == 154, "the first blow is a charge: double damage (%d)" % first)
	check(r.charge_cd > 0.0, "then the charge recharges (%.0f s)" % r.charge_cd)
	var breached: Array = []
	EventBus.wall_breached.connect(func(p: int, pos: Vector2) -> void: breached.append([p, pos]))
	var cracks_before: int = wall.hp
	wall.hp = int(wall.max_hp * 0.2)
	wall.queue_redraw()
	check(wall.hp < cracks_before, "a badly damaged wall draws cracks (state below 30%%)")
	wall.take_damage(99999, r)
	await physics_frames(2)
	check(breached.size() == 1 and int(breached[0][0]) == 1, "the owner is told the wall was breached")
	var rubble: int = 0
	for n: Node in world.get_node("Entities").get_children():
		if n is Rubble:
			rubble += 1
	check(rubble == 1 and world.nav.is_walkable(Vector2i(60, 60)), "rubble marks the gap and the cell is walkable")
	await _close()


func test_d_alerts_come_in_three_levels_with_minimap_icons() -> void:
	await _open("eco12")
	var tc: Building = _tc(0)
	var foe: Unit = world.spawn_unit("militia", 1, tc.position + Vector2(300, 0))
	foe.stance = "passive"
	tc.take_damage(5, foe)
	check(hud.last_banner_level == "critical" and hud.banner.text == tr("ALERT_TC_ATTACK"), "Town Center hit: critical banner")
	check(hud.minimap.alert_kinds().has("attack"), "and a red pulse on the minimap")
	var v: Unit = _villagers(0)[0]
	v.take_damage(1, foe)
	check(hud.last_banner_level == "important" and hud.banner.text == tr("ALERT_VILLAGERS"), "villager hit: important banner that names the bell")
	check(hud.minimap.alert_kinds().has("villagers"), "and a yellow pulse on the minimap")
	EventBus.wall_breached.emit(0, tc.position + Vector2(400, 0))
	check(hud.last_banner_level == "critical" and hud.banner.text == tr("ALERT_BREACH") and hud.minimap.alert_kinds().has("breach"), "wall breached: critical banner and a cross on the minimap")
	EventBus.population_changed.emit(0, 20, 20)
	check(hud.last_banner_level == "soft" and hud.banner.text == tr("ALERT_POP_FULL"), "population full: soft banner")
	var cam: CameraController = main.get_node("CameraController")
	cam.center_on(Vector2(200, 200))
	hud.alert_arrow.point(world.map_size_px - Vector2(200, 200))
	check(hud.alert_arrow.is_showing(), "an attack off screen shows the edge arrow")
	cam.center_on(world.map_size_px - Vector2(200, 200))
	check(not hud.alert_arrow.is_showing(), "once the camera is there the arrow goes")
	check(Sfx.has_sound("bell") and Sfx.has_sound("alert_soft"), "the bell and the soft chime exist")
	await _close()


func test_e_report_explains_the_match_and_fair_ai_has_no_bonus() -> void:
	check(AIController.bonus_text("hard").contains("+30%") and AIController.bonus_text("hard").contains("+50%"), "Hard's hidden bonus is spelled out: %s" % AIController.bonus_text("hard"))
	check(AIController.bonus_text("normal") == "", "Normal has none")
	check(AIController.human_bonus_text("easy").contains("+20%"), "Easy says what the human gets: %s" % AIController.human_bonus_text("easy"))
	var card: String = load("res://scenes/ui/main_menu.gd").difficulty_card("hard", true)
	check(card.contains(tr("MENU_NO_BONUS")), "with fair AI the Hard card says 'no bonuses': %s" % card)
	await _open("skirmish", {1: "hard"})
	var ai: AIController = main.ais[0]
	check(ai.fair and is_equal_approx(float(ai.diff.get("gather_mult", 1.0)), 1.0), "fair Hard: no gather multiplier")
	check(is_equal_approx(float(Dictionary(GameState.multipliers.get(1, {})).get("gather.wood", 1.0)), 1.0), "and no hidden gather bonus applied")
	var rules: MatchRules = main.get_node("MatchRules")
	EventBus.under_attack.emit(0, Vector2.ZERO)
	EventBus.era_changed.emit(1, 2)
	var lines: Array[String] = rules.report_lines(0, 1, false)
	check(lines.size() >= 5 and lines[0].begins_with(tr("REPORT_FIRST_ATTACK").split(":")[0]), "the report starts with the first attack: %s" % lines[0])
	check(lines[1].contains("II"), "and lists the eras reached: %s" % lines[1])
	check(lines[lines.size() - 1] != "", "and ends with a hint: %s" % lines[lines.size() - 1])
	await _close()
	await _open("skirmish", {1: "hard"}, false)
	check(not main.ais[0].fair and is_equal_approx(float(Dictionary(GameState.multipliers.get(1, {})).get("gather.wood", 1.0)), 1.3), "with fair AI off Hard gathers +30%")
	await _close()


func test_f_garrison_survives_a_save() -> void:
	await _open("eco12")
	var tc: Building = _tc(0)
	var vs: Array[Unit] = _villagers(0)
	world.garrison_unit(vs[0], tc)
	world.garrison_unit(vs[1], tc)
	var pop: int = GameState.pop_used(0)
	var data: Dictionary = SaveGame.snapshot(main)
	var saved: int = 0
	for b: Dictionary in data["buildings"]:
		saved += Array(b.get("garrison", [])).size()
	var outside: int = 0
	for u: Dictionary in data["units"]:
		if int(u["owner"]) == 0 and String(u["type"]) == "villager":
			outside += 1
	check(saved == 2 and outside == vs.size() - 2, "the save keeps 2 villagers inside the Town Center and %d outside" % outside)
	await _close()
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = "eco12"
	main.load_data = data
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")
	var tc2: Building = _tc(0)
	check(tc2.garrison.size() == 2 and GameState.pop_used(0) == pop, "after loading they are still inside and counted (%d, pop %d)" % [tc2.garrison.size(), GameState.pop_used(0)])
	await _close()


func test_g_tapping_own_buildings_repairs_or_shelters() -> void:
	await _open("eco12")
	var sel: SelectionController = main.get_node("SelectionController")
	var tc: Building = _tc(0)
	var v: Unit = _villagers(0)[0]
	var house: Building = world.place_building("house", 0, world.world_to_cell(tc.position) + Vector2i(6, 0))
	house.add_progress(1.0)
	house.hp = 50
	check(sel._task_for(v, "own_building", house) is RepairTask, "a villager tapped on a damaged house repairs it")
	house.hp = house.max_hp
	check(sel._task_for(v, "own_building", house) == null, "a whole house gives no task")
	v.carry_type = ""
	v.carry_amount = 0.0
	check(sel._task_for(v, "own_building", tc) == null, "in peace a villager tapped on the Town Center gives no task (the tap selects it)")
	tc.last_hit_s = Time.get_ticks_msec() / 1000.0
	check(sel._task_for(v, "own_building", tc) is GarrisonTask, "with the Town Center just hit, the same tap sends the villager inside")
	v.carry_type = "food"
	v.carry_amount = 5.0
	var t: UnitTask = sel._task_for(v, "own_building", tc)
	check(t is GatherTask and t.kind == "gather", "carrying food it delivers instead")
	var m: Unit = world.spawn_unit("militia", 0, tc.position + Vector2(0, 200))
	check(sel._task_for(m, "own_building", tc) is GarrisonTask, "a soldier tapped on the Town Center garrisons")
	check(sel._task_for(m, "own_building", house) == null, "but not in a house")
	await _close()
