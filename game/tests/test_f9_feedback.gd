extends TestSuite
## Pedro's second playtest: victory on the Town Center, buildings fall
## faster and are recognisable, blocked era-ups say why, every building and
## unit explains itself, and units show a power rating.

var main: Node
var world: World
var scen: ScenarioRunner


func _open(scenario: String, ai: Dictionary = {}) -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = scenario
	if not ai.is_empty():
		main.ai_override = ai
	add_to_tree(main)
	await frames(1)
	world = main.get_node("World")
	scen = main.get_node("ScenarioRunner")


func _close() -> void:
	Engine.time_scale = 1.0
	main.queue_free()
	await frames(2)


func test_a_destroying_the_town_center_wins() -> void:
	await _open("skirmish", {1: "easy"})
	var rules: MatchRules = main.get_node("MatchRules")
	var tc: Building = null
	for b: Building in world.buildings:
		if b.owner_id == 1 and b.building_type == "town_center":
			tc = b
	world.place_building("house", 1, world.world_to_cell(tc.position) + Vector2i(6, 0))
	tc.take_damage(99999, null)
	await physics_frames(70)
	check(rules.ended and rules.winner_id == 0 and rules.reason == "town_center", "losing the Town Center ends the match even with other buildings standing")
	var hud: Hud = main.get_node("Hud")
	check(hud.end_panel != null, "and the end screen shows")
	await _close()


func test_b_buildings_fall_faster() -> void:
	var b: Dictionary = DataLoader.get_table("buildings")
	check(int(b["house"]["hp"]) <= 400 and int(b["barracks"]["hp"]) <= 1000 and int(b["town_center"]["hp"]) <= 2000, "house/barracks/Town Center HP lowered (%d/%d/%d)" % [int(b["house"]["hp"]), int(b["barracks"]["hp"]), int(b["town_center"]["hp"])])
	await _open("arena")
	var house: Building = world.place_building("house", 1, Vector2i(62, 58))
	var squad: Array[Unit] = []
	for i: int in 6:
		squad.append(world.spawn_unit("militia", 0, world.cell_center(Vector2i(58, 57 + i))))
	world.combat.attack_move(squad, house.position)
	var id: int = house.get_instance_id()
	Engine.time_scale = 8.0
	var t0: float = scen.elapsed
	while instance_from_id(id) != null and scen.elapsed - t0 < 90.0:
		await physics_frames(1)
	Engine.time_scale = 1.0
	check(instance_from_id(id) == null and scen.elapsed - t0 < 45.0, "6 militia raze a house in under 45 s (%.0f s)" % (scen.elapsed - t0))
	await _close()


func test_c_buildings_carry_a_sign() -> void:
	PlaceholderArt._texture = null
	PlaceholderArt.load_or_build()
	var img: Image = PlaceholderArt.texture().get_image()
	var plain: Image = BuildingPainter.paint("house", Vector2i(128, 128), Color.BLUE)
	for id: String in ["barracks", "archery_range", "stable", "blacksmith", "university", "monastery", "market"]:
		var r: Rect2 = PlaceholderArt.building_region(id, 0)
		var sign: Image = img.get_region(Rect2i(int(r.position.x) + 12, int(r.position.y) + int(r.size.y * 0.52), 30, 26))
		var light: int = 0
		for y: int in sign.get_height():
			for x: int in sign.get_width():
				if sign.get_pixel(x, y).v > 0.8:
					light += 1
		check(light > 100, "%s shows a light sign board with its symbol (%d bright px)" % [id, light])
	check(plain.get_width() == 128, "houses have no sign (they are the common building)")


func test_d_blocked_era_up_says_why() -> void:
	await _open("skirmish", {1: "easy"})
	var hud: Hud = main.get_node("Hud")
	var tc: Building = null
	for b: Building in world.buildings:
		if b.owner_id == 0 and b.building_type == "town_center":
			tc = b
	GameState.add_resource(0, "food", 1000)
	var item: String = TechSystem.era_item(2)
	var why: String = hud.enqueue_reason(tc, item)
	check(why.contains(tr("BLDG_BARRACKS_NAME")) and why.contains("0"), "with no era buildings the reason names what counts: %s" % why)
	for id: String in ["barracks", "lumber_camp"]:
		var spot: Vector2i = world.find_building_spot(id, tc.position)
		world.place_building(id, 0, spot)
	GameState.add_resource(0, "food", -GameState.get_resource(0, "food"))
	why = hud.enqueue_reason(tc, item)
	check(why.contains("350") and why.contains(tr("RESOURCE_FOOD_NAME").to_lower()), "with the buildings up but no food it lists the missing food: %s" % why)
	GameState.add_resource(0, "food", 1000)
	check(hud.enqueue_reason(tc, item) == "", "with everything in place there is no reason")
	main.get_node("SelectionController").select_building(tc)
	await frames(1)
	var btn: Button = hud.type_buttons.get(item)
	check(btn != null and not btn.disabled, "the era button stays pressable so a tap can explain")
	# Pressing it must really queue the era (it was refused silently once the
	# order layer checked research items like units).
	var food: int = GameState.get_resource(0, "food")
	main._on_train_pressed(item)
	await physics_frames(2)
	check(tc.queue.has(item) and GameState.get_resource(0, "food") == food - 350, "pressing the era button queues the era and pays 350 food (queue %s)" % [tc.queue])
	main._on_train_pressed(TechSystem.PREFIX + "loom")
	await physics_frames(2)
	check(tc.queue.has(TechSystem.PREFIX + "loom"), "a tech button queues its research too (queue %s)" % [tc.queue])
	await _close()


func test_e_everything_explains_itself() -> void:
	var missing: Array[String] = []
	for id: String in DataLoader.get_table("buildings").keys():
		var key: String = String(DataLoader.get_entry("buildings", id).get("desc_key", ""))
		if key == "" or tr(key) == key:
			missing.append(id)
	for id: String in DataLoader.get_table("units").keys():
		var key: String = String(DataLoader.get_entry("units", id).get("desc_key", ""))
		if key == "" or tr(key) == key:
			missing.append(id)
	check(missing.is_empty(), "every building and unit has a description (missing: %s)" % [missing])
	await _open("eco12")
	var hud: Hud = main.get_node("Hud")
	var sel: SelectionController = main.get_node("SelectionController")
	var tc: Building = null
	for b: Building in world.buildings:
		if b.owner_id == 0 and b.building_type == "town_center":
			tc = b
	sel.select_building(tc)
	await frames(1)
	check(hud.info_label != null and hud.info_label.visible and hud.info_label.text.contains(tr("UNIT_VILLAGER_DESC")), "the Town Center panel says what it is for and what a villager does")
	var v: Unit = null
	for u: Unit in world.units:
		if u.owner_id == 0 and u.can_gather():
			v = u
	sel.set_selection([v] as Array[Unit])
	await frames(1)
	check(hud.info_label.visible and hud.info_label.text.contains(tr("UNIT_VILLAGER_DESC")), "a selected villager shows its description")
	await _close()


func test_f_power_stars_rank_units() -> void:
	var knight: int = Hud.unit_power("knight")
	var militia: int = Hud.unit_power("militia")
	var villager: int = Hud.unit_power("villager")
	check(knight > militia and militia > villager, "knight > militia > villager in power stars (%d/%d/%d)" % [knight, militia, villager])
	check(Hud.unit_power("monk") == 0, "healers have no power rating")
	check(Hud.counters_text("spearman").contains(tr("CLASS_CAVALRY")), "spearmen say they are strong against cavalry")
	check(Hud.counters_text("ram").contains(tr("CLASS_BUILDING")), "rams say they are strong against buildings")
	check(Hud.unit_role_text("knight").contains("★"), "the role line shows stars")
