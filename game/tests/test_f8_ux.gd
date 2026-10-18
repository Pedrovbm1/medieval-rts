extends TestSuite
## F8: fog of war, minimap, attack alerts, control groups, save/load,
## autosave and the title menu.

var main: Node
var world: World


func _open(scenario: String, override: Dictionary = {}, load_data: Dictionary = {}) -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = scenario
	main.ai_override = override
	main.load_data = load_data
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")


func _close() -> void:
	Engine.time_scale = 1.0
	main.queue_free()
	await frames(2)


func test_a_fog_reveals_fast_and_hides_enemies() -> void:
	await _open("skirmish")
	var vision: VisionSystem = world.vision
	check(vision.fog_enabled and vision.fog_layer != null, "skirmish draws fog of war")
	var enemy_tc: Building = world.buildings.filter(func(b: Building) -> bool: return b.owner_id == 1)[0]
	check(not enemy_tc.visible, "the enemy Town Center is hidden while unexplored")
	var scout: Unit = world.units.filter(func(u: Unit) -> bool: return u.owner_id == 0 and u.unit_type == "scout")[0]
	var far: Vector2 = Vector2(60, 60) * 64.0
	check(vision.grid.state(0, Vector2i(60, 60)) == VisionGrid.UNSEEN, "the map centre starts unexplored")
	scout.position = far
	var t0: int = Time.get_ticks_msec()
	while vision.grid.state(0, Vector2i(60, 60)) != VisionGrid.VISIBLE and Time.get_ticks_msec() - t0 < 2000:
		await physics_frames(1)
	var waited: float = (Time.get_ticks_msec() - t0) / 1000.0
	check(waited <= 0.5, "fog clears around a unit in %.2f s (< 0.5)" % waited)
	check(vision.last_update_usec < 30000, "a vision + fog update costs %.1f ms" % (vision.last_update_usec / 1000.0))
	scout.position = enemy_tc.position + Vector2(300, 0)
	await physics_frames(20)
	check(enemy_tc.visible, "the enemy base shows once a unit sees it")
	scout.position = far
	await physics_frames(20)
	check(not enemy_tc.visible, "and hides again when it is out of sight")
	check(vision.grid.state(0, world.world_to_cell(enemy_tc.position)) == VisionGrid.EXPLORED, "its area stays explored (dim) on the map")
	await _close()


func test_b_minimap_and_alerts() -> void:
	await _open("skirmish")
	var hud: Hud = main.get_node("Hud")
	var cam: CameraController = main.get_node("CameraController")
	var mm: Minimap = hud.minimap
	check(mm != null and mm.size.x >= 180.0, "the minimap is on screen (%s)" % str(mm.size))
	var target: Vector2 = world.map_size_px * 0.5
	mm.jump_to.emit(mm.to_world(mm.to_local_point(target)))
	await frames(1)
	check(cam.position.distance_to(target) < 2.0, "tapping the minimap moves the camera there")
	check(hud.is_point_over_ui(mm.get_global_rect().get_center()), "touches on the minimap never reach the map")
	var villager: Unit = world.units.filter(func(u: Unit) -> bool: return u.owner_id == 0 and u.can_gather())[0]
	var raider: Unit = world.spawn_unit("militia", 1, villager.position + Vector2(40, 0))
	world.combat.apply_hit(raider, villager, 3)
	await frames(1)
	check(mm._alerts.size() == 1, "an attack on our villager pings the minimap")
	check(hud.banner.visible and hud.banner.text == tr("ALERT_UNDER_ATTACK"), "and shows %s" % tr("ALERT_UNDER_ATTACK"))
	await _close()


func test_c_control_groups() -> void:
	await _open("sandbox")
	var sel: SelectionController = main.get_node("SelectionController")
	var hud: Hud = main.get_node("Hud")
	var militia: Array[Unit] = world.units.filter(func(u: Unit) -> bool: return u.unit_type == "militia")
	sel.set_selection(militia)
	hud.group_held.emit(1)
	sel.clear_selection()
	hud.group_pressed.emit(1)
	check(sel.selected.size() == 3, "holding group 1 stores 3 militia, tapping recalls them")
	check(hud.group_buttons[0].text.ends_with("3"), "the group button shows its size (%s)" % hud.group_buttons[0].text)
	check(hud.is_point_over_ui(hud.group_buttons[0].get_global_rect().get_center()), "group buttons never leak taps into the map")
	world.remove_unit(militia[0])
	hud.group_pressed.emit(1)
	check(sel.selected.size() == 2, "dead units drop out of the group")
	await _close()


func test_d_save_and_load_identical() -> void:
	await _open("skirmish")
	var rules: MatchRules = main.get_node("MatchRules")
	Engine.time_scale = 8.0
	while rules.elapsed < 240.0:
		await physics_frames(1)
	Engine.time_scale = 1.0
	var saved: Dictionary = SaveGame.snapshot(main)
	check(SaveManager.save_payload("test_match", saved) == OK, "a 4-minute match saves to user://")
	var data: Dictionary = SaveManager.load_payload("test_match")
	var before: Dictionary = _summary(world, rules)
	await _close()
	await _open(String(data["scenario"]), {1: "normal"}, data)
	var after: Dictionary = _summary(world, main.get_node("MatchRules"))
	var diffs: PackedStringArray = PackedStringArray()
	for key: String in before.keys():
		if str(before[key]) != str(after[key]):
			diffs.append("%s: %s != %s" % [key, str(before[key]).left(80), str(after[key]).left(80)])
	check(diffs.is_empty(), "loading restores the same state (%d keys compared) %s" % [before.size(), str(diffs)])
	var tasks: int = world.units.filter(func(u: Unit) -> bool: return u.task != null).size()
	check(tasks >= int(before["busy"]) - 1, "villagers resume their work after loading (%d busy)" % tasks)
	await physics_frames(60)
	check(world.units.size() >= int(before["units"]) - 1, "the loaded match keeps running")
	SaveManager.delete_save("test_match")
	await _close()


## Order-independent digest of a match for save/load comparisons.
func _summary(w: World, rules: MatchRules) -> Dictionary:
	var s: Dictionary = {}
	s["units"] = w.units.size()
	s["buildings"] = w.buildings.size()
	s["nodes"] = w.resource_nodes.size()
	s["busy"] = w.units.filter(func(u: Unit) -> bool: return u.task != null).size()
	var unit_list: PackedStringArray = PackedStringArray()
	for u: Unit in w.units:
		unit_list.append("%s/%d/%d,%d/%d/%.0f" % [u.unit_type, u.owner_id, roundi(u.position.x), roundi(u.position.y), u.hp, u.carry_amount])
	unit_list.sort()
	s["unit_list"] = unit_list
	var bl: PackedStringArray = PackedStringArray()
	for b: Building in w.buildings:
		bl.append("%s/%d/%d,%d/%d/%.2f/%s" % [b.building_type, b.owner_id, b.cell.x, b.cell.y, b.hp, b.build_progress, str(b.queue)])
	bl.sort()
	s["building_list"] = bl
	var nl: PackedStringArray = PackedStringArray()
	for n: ResourceNode in w.resource_nodes:
		nl.append("%s/%d,%d/%.0f" % [n.resource_type, roundi(n.position.x), roundi(n.position.y), n.amount])
	nl.sort()
	s["node_list"] = nl
	for p: int in [0, 1]:
		for res: String in ["food", "wood", "gold", "stone"]:
			s["res%d.%s" % [p, res]] = GameState.get_resource(p, res)
		s["era%d" % p] = GameState.era_of(p)
		s["explored%d" % p] = snappedf(w.vision.grid.explored_ratio(p), 0.001)
	s["trees"] = w.tree_amounts_dict().size()
	s["clock"] = snappedf(rules.elapsed, 0.1)
	return s


func test_e_autosave() -> void:
	SaveManager.delete_save("auto")
	await _open("skirmish")
	Engine.time_scale = 8.0
	var rules: MatchRules = main.get_node("MatchRules")
	while rules.elapsed < 130.0:
		await physics_frames(1)
	Engine.time_scale = 1.0
	check(SaveManager.has_save("auto"), "the match autosaves after 2 minutes")
	check(SaveManager.latest_slot() == "auto", "and the title menu will offer to continue it")
	await _close()
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_to_tree(menu)
	await frames(1)
	var texts: PackedStringArray = PackedStringArray()
	for b: Node in menu.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	check(texts.has(tr("MENU_CONTINUE")) and texts.has(tr("MENU_NEW_GAME")), "title menu offers %s" % str(texts))
	menu.queue_free()
	SaveManager.delete_save("auto")
	await frames(1)
