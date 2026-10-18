extends Node
## Headless test runner. Runs as a normal scene so autoloads are available:
##   godot --headless --path game tests/run_tests.tscn
## Exit code 0 = all passed, 1 = at least one failure.

var _failures: int = 0
var _passes: int = 0


func _ready() -> void:
	print("== REALM tests ==")
	test_data_tables_load()
	test_map_generator_is_deterministic()
	test_map_generator_has_all_terrains()
	test_camera_clamp_keeps_view_inside_map()
	test_camera_clamp_centres_when_map_is_smaller()
	test_game_state_roundtrip()
	test_save_manager_roundtrip()
	print("== %d passed, %d failed ==" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  " + message)
	else:
		_failures += 1
		print("  FAIL  " + message)


func test_data_tables_load() -> void:
	_check(DataLoader.load_errors.is_empty(), "data tables load without errors: " + str(DataLoader.load_errors))
	var terrain: Dictionary = DataLoader.get_table("terrain")
	var types: Dictionary = terrain.get("types", {})
	_check(types.size() == 3, "terrain.json defines 3 types")
	var ids: Array = []
	for type_name: String in types.keys():
		ids.append(int(types[type_name].get("id", -1)))
	ids.sort()
	_check(ids == [0, 1, 2], "terrain ids are 0,1,2")
	var civ: Dictionary = DataLoader.get_entry("civs", "northvale")
	var starting: Dictionary = civ.get("starting_resources", {})
	_check(starting.size() == 4, "northvale has 4 starting resources")
	var map_def: Dictionary = DataLoader.get_map("skirmish_120")
	_check(int(map_def.get("width", 0)) == 120 and int(map_def.get("height", 0)) == 120, "skirmish_120 is 120x120")


func test_map_generator_is_deterministic() -> void:
	var map_def: Dictionary = DataLoader.get_map("skirmish_120")
	var terrain: Dictionary = DataLoader.get_table("terrain")
	var a: PackedByteArray = MapGenerator.generate(map_def, terrain)
	var b: PackedByteArray = MapGenerator.generate(map_def, terrain)
	_check(a.size() == 120 * 120, "grid has 14400 cells")
	_check(a == b, "same seed produces the same grid")
	var other: Dictionary = map_def.duplicate(true)
	other["seed"] = int(map_def.get("seed", 1)) + 7
	_check(MapGenerator.generate(other, terrain) != a, "different seed produces a different grid")


func test_map_generator_has_all_terrains() -> void:
	var grid: PackedByteArray = MapGenerator.generate(DataLoader.get_map("skirmish_120"), DataLoader.get_table("terrain"))
	var counts: Dictionary = MapGenerator.count_terrain(grid)
	_check(counts.has(0) and counts.has(1) and counts.has(2), "grass, water and forest all appear: " + str(counts))
	var grass_ratio: float = float(counts.get(0, 0)) / float(grid.size())
	_check(grass_ratio > 0.4 and grass_ratio < 0.9, "grass covers 40-90%% of the map (%.2f)" % grass_ratio)


func test_camera_clamp_keeps_view_inside_map() -> void:
	var bounds: Rect2 = Rect2(0, 0, 7680, 7680)
	var view: Vector2 = Vector2(1280, 720)
	var far_out: Vector2 = CameraController.clamp_to_bounds(Vector2(-5000, 99999), bounds, view, 0.5)
	_check(far_out == Vector2(1280, 6960), "zoom 0.5: clamped to (1280, 6960), got " + str(far_out))
	var inside: Vector2 = CameraController.clamp_to_bounds(Vector2(3000, 3000), bounds, view, 1.0)
	_check(inside == Vector2(3000, 3000), "zoom 1.0: interior position untouched")
	var corner: Vector2 = CameraController.clamp_to_bounds(Vector2.ZERO, bounds, view, 1.5)
	_check(corner.is_equal_approx(Vector2(1280.0 / 3.0, 240.0)), "zoom 1.5: corner clamped to half view, got " + str(corner))


func test_camera_clamp_centres_when_map_is_smaller() -> void:
	var tiny: Rect2 = Rect2(0, 0, 500, 500)
	var centred: Vector2 = CameraController.clamp_to_bounds(Vector2(9, 9), tiny, Vector2(1280, 720), 0.5)
	_check(centred == Vector2(250, 250), "map smaller than view: camera centres on map")


func test_game_state_roundtrip() -> void:
	GameState.new_match("skirmish_120", "northvale", "northvale")
	_check(GameState.get_resource(0, "food") == 200, "human starts with 200 food from civs.json")
	GameState.add_resource(0, "wood", -50)
	var snapshot: Dictionary = GameState.to_dict()
	GameState.add_resource(0, "wood", 999)
	GameState.from_dict(snapshot)
	_check(GameState.get_resource(0, "wood") == 150, "to_dict/from_dict restores wood=150")
	GameState.add_resource(0, "gold", -99999)
	_check(GameState.get_resource(0, "gold") == 0, "resources never go below zero")


func test_save_manager_roundtrip() -> void:
	var slot: String = "test"
	GameState.new_match("skirmish_120", "northvale", "northvale")
	GameState.add_resource(0, "stone", 25)
	_check(SaveManager.save_game(slot) == OK, "save_game writes user://save_test.json")
	GameState.add_resource(0, "stone", 1000)
	_check(SaveManager.load_game(slot) == OK, "load_game reads the slot back")
	_check(GameState.get_resource(0, "stone") == 125, "loaded state restores stone=125")
	_check(SaveManager.delete_save(slot) == OK and not SaveManager.has_save(slot), "delete_save removes the slot")
	_check(SaveManager.load_game("missing") == ERR_DOES_NOT_EXIST, "loading a missing slot reports ERR_DOES_NOT_EXIST")
