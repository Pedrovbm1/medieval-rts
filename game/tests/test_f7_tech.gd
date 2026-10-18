extends TestSuite
## F7: eras with requirements, 24 techs in 3 branches, every tech reachable
## and visible, towers, and the AI reaching Era IV within 25 minutes.

var main: Node
var world: World


func _open(scenario: String, override: Dictionary = {}) -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = scenario
	main.ai_override = override
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")


func _close() -> void:
	Engine.time_scale = 1.0
	main.queue_free()
	await frames(2)


func test_a_tree_has_no_orphans() -> void:
	var techs: Dictionary = DataLoader.get_table("techs")
	check(techs.size() == 24, "24 technologies (got %d)" % techs.size())
	var branches: Dictionary = {}
	var problems: PackedStringArray = PackedStringArray()
	for id: String in techs.keys():
		var t: Dictionary = techs[id]
		branches[String(t.get("branch", "?"))] = int(branches.get(String(t.get("branch", "?")), 0)) + 1
		var bdef: Dictionary = DataLoader.get_entry("buildings", String(t.get("researched_at", "")))
		if bdef.is_empty():
			problems.append("%s: no building" % id)
		elif not bool(bdef.get("buildable", true)) and String(t["researched_at"]) != "town_center":
			problems.append("%s: building cannot be built" % id)
		elif int(bdef.get("era", 1)) > int(t.get("era", 1)):
			problems.append("%s: building comes in a later era" % id)
		if int(t.get("era", 1)) < 1 or int(t.get("era", 1)) > 4:
			problems.append("%s: bad era" % id)
		if Array(t.get("effects", [])).is_empty():
			problems.append("%s: no effect" % id)
		for e: Variant in t.get("effects", []):
			var key: String = String(e["key"])
			var consumed: bool = false
			for prefix: String in TechSystem.CONSUMED_KEYS:
				if key.begins_with(prefix):
					consumed = true
			if not consumed:
				problems.append("%s: effect %s is read by nothing" % [id, key])
		if TranslationServer.translate(String(t.get("name_key", ""))) == String(t.get("name_key", "")):
			problems.append("%s: missing translation" % id)
	check(branches.size() == 3, "3 branches: %s" % str(branches))
	check(problems.is_empty(), "every tech is researchable somewhere and every effect is used: %s" % str(problems))


func test_b_every_tech_changes_a_number() -> void:
	await _open("arena")
	var probe_units: Dictionary = {}
	for type_id: String in ["villager", "militia", "archer", "knight", "ram"]:
		probe_units[type_id] = world.spawn_unit(type_id, 0, world.cell_center(Vector2i(40 + probe_units.size() * 3, 40)))
	var dummy: Unit = world.spawn_unit("militia", 1, world.cell_center(Vector2i(40, 50)))
	var house: Building = world.place_building("house", 0, Vector2i(60, 60))
	var tower: Building = world.place_building("watch_tower", 0, Vector2i(64, 60))
	var unchanged: PackedStringArray = PackedStringArray()
	for id: String in DataLoader.get_table("techs").keys():
		var before: Dictionary = _snapshot(probe_units, dummy, house, tower)
		world.tech.complete(0, "#" + id)
		var after: Dictionary = _snapshot(probe_units, dummy, house, tower)
		if before == after:
			unchanged.append(id)
	check(unchanged.is_empty(), "each of the 24 techs changes at least one measurable stat (no effect: %s)" % str(unchanged))
	await _close()


## Every number a tech may touch, for player 0.
func _snapshot(units: Dictionary, dummy: Unit, house: Building, tower: Building) -> Dictionary:
	var s: Dictionary = {}
	var v: Unit = units["villager"]
	for sub: String in ["berries", "farm", "wood", "gold", "stone", "meat"]:
		s["gather." + sub] = world.economy.gather_rate(v, sub)
	s["carry"] = world.economy.carry_capacity(v)
	s["build"] = GameState.modifier(0, "build_speed")
	for type_id: String in units.keys():
		var u: Unit = units[type_id]
		s[type_id + ".hp"] = u.max_hp
		s[type_id + ".speed"] = u.speed_px
		s[type_id + ".armor"] = Combat.armor_of(u)
		s[type_id + ".sight"] = Combat.sight_of(u, 256.0)
		if not u.data.get("combat", {}).is_empty():
			s[type_id + ".dmg"] = Combat.hit_damage(u, dummy)
			s[type_id + ".range"] = Combat.range_of(u)
			s[type_id + ".repeat"] = Combat.repeat_of(u)
	s["house.hp"] = house.max_hp
	s["house.armor"] = Combat.armor_of(house)
	s["house.sight"] = Combat.sight_of(house, 256.0)
	s["tower.dmg"] = Combat.hit_damage(tower, dummy)
	s["tower.range"] = Combat.range_of(tower)
	return s


func test_c_stats_shown_before_and_after() -> void:
	await _open("arena")
	var m: Unit = world.spawn_unit("militia", 0, world.cell_center(Vector2i(50, 50)))
	var before: String = Hud.unit_stats_text(m)
	world.tech.complete(0, "#forging")
	world.tech.complete(0, "#mail_armor")
	var after: String = Hud.unit_stats_text(m)
	check(before.contains("ATQ 6") and before.contains("ARM 1/3"), "militia panel before: %s" % before)
	check(after.contains("ATQ 7") and after.contains("ARM 2/4"), "after Forging + Mail armor: %s" % after)
	await _close()


func test_d_era_requirements_and_unlocks() -> void:
	await _open("build4min")
	GameState.add_resource(0, "food", 5000)
	GameState.add_resource(0, "gold", 5000)
	GameState.add_resource(0, "wood", 5000)
	var tc: Building = world.buildings.filter(func(b: Building) -> bool: return b.building_type == "town_center")[0]
	check(world.tech.research_error(tc, "#era2") == "requires", "Era II needs 2 buildings of Era I first")
	var home: Vector2 = tc.position
	for type_id: String in ["lumber_camp", "barracks"]:
		var b: Building = world.place_building(type_id, 0, world.find_building_spot(type_id, home + Vector2(400, 0)))
		check(b.is_complete(), "%s placed" % type_id)
	var barracks: Building = world.buildings.filter(func(b: Building) -> bool: return b.building_type == "barracks")[0]
	check(world.construction.can_enqueue(barracks, "spearman") == "era", "spearmen are locked in Era I")
	check(world.construction.enqueue(tc, "#era2"), "with 2 Era I buildings the Town Center starts Era II")
	var sel: SelectionController = main.get_node("SelectionController")
	sel.select_building(tc)
	await frames(1)
	var hud: Hud = main.get_node("Hud")
	Engine.time_scale = 8.0
	var scen: ScenarioRunner = main.get_node("ScenarioRunner")
	var t0: float = scen.elapsed
	while GameState.era_of(0) < 2 and scen.elapsed - t0 < 90.0:
		await physics_frames(1)
	Engine.time_scale = 1.0
	check(GameState.era_of(0) == 2, "Era II after its research time (%.0f s)" % (scen.elapsed - t0))
	check(hud.banner.visible and hud.banner.text.contains(tr("ERA_2_NAME")), "the new-era banner shows: %s" % hud.banner.text)
	check(hud.era_label.text.contains(tr("ERA_2_NAME")), "the top bar shows the era")
	check(world.construction.can_enqueue(barracks, "spearman") == "", "spearmen unlock in Era II")
	sel.select_building(barracks)
	await frames(1)
	check(hud.type_buttons.has("spearman"), "the barracks panel now offers spearmen")
	var bs: Building = world.place_building("blacksmith", 0, world.find_building_spot("blacksmith", home + Vector2(-400, 0)))
	sel.select_building(bs)
	await frames(1)
	check(hud.type_buttons.has("#forging") and not hud.type_buttons.has("#plate_armor"), "the blacksmith offers Era II techs, not Era IV ones")
	await _close()


func test_e_towers_shoot_and_battlements_help() -> void:
	await _open("arena")
	var tower: Building = world.place_building("watch_tower", 0, Vector2i(60, 60))
	var base_range: float = Combat.range_of(tower)
	var target: Unit = world.spawn_unit("militia", 1, tower.position + Vector2(base_range - 40.0, 0))
	target.stance = "passive"
	var hp0: int = target.hp
	await physics_frames(150)
	check(not world.units.has(target) or target.hp < hp0, "a watch tower shoots an enemy in range")
	world.tech.complete(0, "#battlements")
	check(is_equal_approx(Combat.range_of(tower), base_range + 64.0), "Battlements: +64 tower range (%.0f -> %.0f)" % [base_range, Combat.range_of(tower)])
	await _close()


## "Era IV is reachable in 25 minutes": shown by the Hard AI (good economy).
## The Normal AI is the pacing opponent for the passive-player test in F6.
func test_f_ai_reaches_era_four_in_25_minutes() -> void:
	await _open("skirmish", {1: "hard"})
	var ai: AIController = main.ais[0]
	var rules: MatchRules = main.get_node("MatchRules")
	rules.set_physics_process(false)  # keep playing after the passive human falls
	Engine.time_scale = 8.0
	var era_times: Dictionary = {}
	while ai.elapsed < 25.0 * 60.0:
		await physics_frames(1)
		var e: int = GameState.era_of(1)
		if not era_times.has(e):
			era_times[e] = ai.elapsed / 60.0
	Engine.time_scale = 1.0
	check(GameState.era_of(1) == 4 and float(era_times.get(4, 99.0)) <= 25.0, "the Hard AI reaches Era IV by minute %.1f (eras at %s)" % [float(era_times.get(4, 99.0)), str(era_times)])
	var researched: int = Dictionary(GameState.researched.get(1, {})).size()
	check(researched >= 2, "and has researched %d techs by minute 25 (it saves for eras most of the game)" % researched)
	await _close()
