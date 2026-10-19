extends TestSuite
## F9: procedural art (one atlas, every sprite present, animation poses,
## terrain variants) and audio (every sound loads, world sounds only on
## screen, battle music when fighting is seen).

var main: Node
var world: World
var scen: ScenarioRunner


func _open(scenario: String = "arena") -> void:
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


func test_a_atlas_has_every_sprite() -> void:
	PlaceholderArt.build()
	var missing: Array[String] = []
	var players: int = (DataLoader.rule("players", "colors", ["#3a6fd8", "#d84a3a"]) as Array).size()
	for type_id: String in DataLoader.get_table("units").keys():
		for p: int in players:
			for pose: String in PlaceholderArt.POSES:
				if PlaceholderArt.region("unit:%s@p%d#%s" % [type_id, p, pose]).size == Vector2.ZERO:
					missing.append("%s/p%d/%s" % [type_id, p, pose])
	for type_id: String in DataLoader.get_table("buildings").keys():
		for p: int in players:
			if PlaceholderArt.building_region(type_id, p).size == Vector2.ZERO:
				missing.append("bldg %s/p%d" % [type_id, p])
	for res: String in ["food", "wood", "gold", "stone"]:
		if PlaceholderArt.icon_region(res).size == Vector2.ZERO:
			missing.append("icon " + res)
	check(missing.is_empty(), "every unit pose, building and icon is in the atlas (missing: %s)" % [missing.slice(0, 5)])
	var tex: Texture2D = PlaceholderArt.texture()
	check(tex.get_width() <= 2048 and tex.get_height() <= 2048, "the atlas fits one 2048 texture (%dx%d)" % [tex.get_width(), tex.get_height()])
	var walk0: Rect2 = PlaceholderArt.unit_frame("militia", 0, "walk0")
	var walk1: Rect2 = PlaceholderArt.unit_frame("militia", 0, "walk1")
	var img: Image = tex.get_image()
	check(img.get_region(Rect2i(walk0)).get_data() != img.get_region(Rect2i(walk1)).get_data(), "walk frames differ (the legs move)")
	var blue: Rect2 = PlaceholderArt.building_region("barracks", 0)
	var red: Rect2 = PlaceholderArt.building_region("barracks", 1)
	check(img.get_region(Rect2i(blue)).get_data() != img.get_region(Rect2i(red)).get_data(), "buildings carry the player's colour")


func test_a2_baked_atlas_is_fresh_and_fast() -> void:
	check(PlaceholderArt.baked_is_fresh(), "the baked atlas matches the current data and painters (else run tests/tools/bake_art.tscn)")
	PlaceholderArt._texture = null
	var t0: int = Time.get_ticks_msec()
	PlaceholderArt.load_or_build()
	var ms: int = Time.get_ticks_msec() - t0
	check(ms < 1000, "loading the atlas at startup takes %d ms (painting it takes ~8 s)" % ms)
	check(PlaceholderArt.unit_frame("villager", 0, "walk1").size == Vector2(64, 64), "unit frames are 64 px")


func test_b_terrain_variants() -> void:
	var ts: TileSet = PlaceholderTileset.build(DataLoader.get_table("terrain"))
	var src: TileSetAtlasSource = ts.get_source(0)
	var types: int = Dictionary(DataLoader.get_table("terrain").get("types", {})).size()
	check(src.get_tiles_count() == types * PlaceholderTileset.VARIANTS, "%d variants per terrain type" % PlaceholderTileset.VARIANTS)
	var seen: Dictionary = {}
	for x: int in 20:
		seen[PlaceholderTileset.atlas_coords(0, Vector2i(x, 3))] = true
	check(seen.size() > 1, "neighbouring grass cells use different variants")
	check(PlaceholderTileset.atlas_coords(1, Vector2i(5, 9)) == PlaceholderTileset.atlas_coords(1, Vector2i(5, 9)), "a cell's variant is stable")


func test_c_units_animate_and_face() -> void:
	await _open()
	var u: Unit = world.spawn_unit("militia", 0, world.cell_center(Vector2i(60, 60)))
	await physics_frames(2)
	check(u.pose == "idle", "a standing unit is idle")
	world.movement.command_move([u], world.cell_center(Vector2i(50, 60)))
	var poses: Dictionary = {}
	for i: int in 60:
		await physics_frames(1)
		poses[u.pose] = true
	check(poses.has("walk0") and poses.has("walk1"), "a walking unit alternates walk frames")
	check(u.face_left, "walking west faces left (sprite flipped)")
	await _close()


func test_d_work_swing_plays_sound_on_screen() -> void:
	await _open("eco12")
	var cam: Camera2D = main.get_node("CameraController")
	var v: Unit = null
	for u: Unit in world.units:
		if u.owner_id == 0 and u.can_gather():
			v = u
			break
	var trees: Vector2i = Vector2i(-1, -1)
	var best: float = INF
	for y: int in world.map_height:
		for x: int in world.map_width:
			if world.get_terrain_id(Vector2i(x, y)) == world._forest_id:
				var d: float = world.cell_center(Vector2i(x, y)).distance_to(v.position)
				if d < best:
					best = d
					trees = Vector2i(x, y)
	world.behavior.assign(v, GatherTask.for_tree(v, world, trees))
	Engine.time_scale = 4.0
	var before: int = int(Sfx.played.get("chop", 0))
	var swung: bool = false
	var t0: float = scen.elapsed
	while scen.elapsed - t0 < 60.0 and int(Sfx.played.get("chop", 0)) == before:
		cam.position = v.position
		await physics_frames(1)
		swung = swung or v.pose == "attack1"
	Engine.time_scale = 1.0
	check(swung, "a gathering villager swings its tool")
	check(int(Sfx.played.get("chop", 0)) > before, "the swing plays a chop sound when on screen")
	check(not Sfx.on_screen(cam.get_screen_center_position() + Vector2(4000, 0)), "a spot far from the camera is off screen (no sound)")
	await _close()


func test_e_every_sound_loads_and_music_switches() -> void:
	var missing: Array[String] = []
	for id: String in Dictionary(DataLoader.get_table("audio").get("sfx", {})).keys():
		if not Sfx.has_sound(id):
			missing.append(id)
	check(missing.is_empty(), "every sound effect id loads (missing: %s)" % [missing])
	var count: int = 0
	for f: String in DirAccess.get_files_at("res://assets/audio/sfx"):
		if f.ends_with(".wav") or f.ends_with(".wav.import"):
			count += 1 if f.ends_with(".wav.import") else 0
	check(count >= 40, "at least 40 sound effect files (%d)" % count)
	check(Dictionary(DataLoader.get_table("audio").get("music", {})).size() >= 3, "3 music themes")
	Music.play_theme("peace")
	check(Music.current == "peace", "the calm theme plays in a match")
	var hold: float = Music._battle_hold_s
	Music._battle_hold_s = 0.2
	Music.combat_ping()
	check(Music.current == "battle", "fighting on screen switches to the battle theme")
	await (Engine.get_main_loop() as SceneTree).create_timer(0.5).timeout
	await frames(2)
	check(Music.current == "peace", "the calm theme returns after the fighting stops")
	Music._battle_hold_s = hold
	Music.stop()
