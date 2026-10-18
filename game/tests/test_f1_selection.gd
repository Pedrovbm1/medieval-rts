extends TestSuite
## F1: integration on the real main scene. Synthetic touches go through
## PointerManager exactly like device input does.

var main: Node
var pointer: PointerManager
var selection: SelectionController
var camera: CameraController
var hud: Hud
var world: World
var t: int = 1000000


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	pointer.process_event(e, t)


func _drag(index: int, pos: Vector2) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	pointer.process_event(e, t)


func _tap(pos: Vector2) -> void:
	t += 1000
	_touch(0, pos, true)
	t += 80
	_touch(0, pos, false)


func _box(from_pos: Vector2, to_pos: Vector2) -> void:
	t += 1000
	_touch(0, from_pos, true)
	t += 400
	pointer._dispatch(pointer.classifier.update(t))
	_drag(0, (from_pos + to_pos) * 0.5)
	t += 50
	_drag(0, to_pos)
	t += 50
	_touch(0, to_pos, false)


func _screen(unit: Unit) -> Vector2:
	return camera.world_to_screen(unit.position)


func test_00_setup() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	main.scenario = "sandbox"
	add_to_tree(main)
	await frames(2)
	pointer = main.get_node("PointerManager")
	selection = main.get_node("SelectionController")
	camera = main.get_node("CameraController")
	hud = main.get_node("Hud")
	world = main.get_node("World")
	check(world.units.size() == 5, "5 placeholder units spawned")
	var on_grass: bool = true
	for unit: Unit in world.units:
		if world.get_terrain_id(world.world_to_cell(unit.position)) != 0:
			on_grass = false
	check(on_grass, "test units spawn on grass")


func test_01_tap_selects_one_unit() -> void:
	_tap(_screen(world.units[0]))
	check(selection.selected.size() == 1 and selection.selected[0] == world.units[0], "tap on a unit selects exactly that unit")
	check(world.units[0].selected, "selected unit shows its ring")
	check(hud.selection_panel.visible, "HUD selection panel appears")


func test_02_box_selects_three() -> void:
	var a: Vector2 = _screen(world.units[0]) - Vector2(30, 30)
	var b: Vector2 = _screen(world.units[2]) + Vector2(30, 30)
	_box(a, b)
	check(selection.selected.size() == 3, "hold-and-drag box over 3 units selects 3 (got %d)" % selection.selected.size())


func test_03_tap_ground_moves_group() -> void:
	var before: Array[Vector2] = []
	for u: Unit in selection.selected:
		before.append(u.position)
	var target_screen: Vector2 = _screen(world.units[2]) + Vector2(0, 160)
	var target_world: Vector2 = camera.screen_to_world(target_screen)
	_tap(target_screen)
	check(selection.selected.size() == 3, "tap on ground keeps the selection")
	var all_moving: bool = selection.selected.all(func(u: Unit) -> bool: return u.is_moving())
	check(all_moving, "every selected unit received the move order")
	check(main.get_node("World/OrderMarker").visible, "order marker (line + ring) is shown")
	await physics_frames(150)
	var arrived: int = 0
	var distinct: Dictionary = {}
	for u: Unit in selection.selected:
		if u.position.distance_to(target_world) < 90.0 and not u.is_moving():
			arrived += 1
		distinct[Vector2i(u.position)] = true
	check(arrived == 3, "3 units arrive around the target (got %d)" % arrived)
	check(distinct.size() == 3, "units end on distinct formation slots, not stacked")
	check(not world.units[3].is_moving() and not world.units[4].is_moving(), "unselected villagers did not move")


func test_04_double_tap_selects_same_type() -> void:
	selection.clear_selection()
	var p: Vector2 = _screen(world.units[0])
	_tap(p)
	t += 120
	_touch(0, p, true)
	t += 60
	_touch(0, p, false)
	var all_militia: bool = selection.selected.all(func(u: Unit) -> bool: return u.unit_type == "militia")
	check(selection.selected.size() == 3 and all_militia, "double tap on militia selects the 3 militia on screen (got %d)" % selection.selected.size())


func test_05_stop_and_hold() -> void:
	_tap(_screen(world.units[3]) + Vector2(400, 0))
	check(selection.selected.all(func(u: Unit) -> bool: return u.is_moving()), "group is moving before Stop")
	hud.stop_button.pressed.emit()
	check(selection.selected.all(func(u: Unit) -> bool: return not u.is_moving()), "Stop halts every selected unit")
	hud.hold_button.pressed.emit()
	check(selection.selected.all(func(u: Unit) -> bool: return u.stance == "hold"), "Hold sets stance HOLD")


func test_06_touch_on_hud_does_not_leak() -> void:
	var count: int = selection.selected.size()
	var moving_before: bool = selection.selected.any(func(u: Unit) -> bool: return u.is_moving())
	var on_button: Vector2 = hud.stop_button.get_global_rect().get_center()
	check(hud.is_point_over_ui(on_button), "HUD reports the Stop button as UI")
	_tap(on_button)
	check(selection.selected.size() == count, "tap on HUD does not change selection")
	var moving_after: bool = selection.selected.any(func(u: Unit) -> bool: return u.is_moving())
	check(moving_before == moving_after and not moving_after, "tap on HUD does not issue a move order")


func test_07_pan_does_not_select_or_order() -> void:
	selection.clear_selection()
	var cam_before: Vector2 = camera.position
	t += 1000
	var p: Vector2 = _screen(world.units[0])
	_touch(0, p, true)
	t += 40
	_drag(0, p + Vector2(-120, 0))
	t += 40
	_drag(0, p + Vector2(-240, 0))
	t += 40
	_touch(0, p + Vector2(-240, 0), false)
	check(selection.selected.is_empty(), "a quick drag that starts on a unit pans and does not select it")
	check(camera.position.x > cam_before.x + 200.0, "the camera panned with the finger")


func test_08_pinch_zoom_stays_in_range() -> void:
	t += 1000
	_touch(0, Vector2(500, 360), true)
	_touch(1, Vector2(700, 360), true)
	t += 30
	_drag(1, Vector2(1200, 360))
	check(is_equal_approx(camera.get_zoom_factor(), 1.5), "pinch out clamps at 1.5x (got %.2f)" % camera.get_zoom_factor())
	_drag(1, Vector2(520, 360))
	check(is_equal_approx(camera.get_zoom_factor(), 0.5), "pinch in clamps at 0.5x (got %.2f)" % camera.get_zoom_factor())
	_touch(1, Vector2(520, 360), false)
	_touch(0, Vector2(500, 360), false)
	check(selection.selected.is_empty(), "pinch never selects")
	camera.zoom_at(Vector2(640, 360), 1.0)


func test_09_ten_order_cycles() -> void:
	# Acceptance proxy for "10/10 attempts": select 1, box 3, order, repeat.
	var ok: int = 0
	for i: int in 10:
		camera.center_on(world.units[1].position)
		await frames(1)
		_tap(_screen(world.units[i % 5]))
		var one: bool = selection.selected.size() == 1
		var a: Vector2 = _screen(world.units[0])
		var b: Vector2 = a
		for u: Unit in world.units:
			a = a.min(_screen(u))
			b = b.max(_screen(u))
		_box(a - Vector2(30, 30), b + Vector2(30, 30))
		var five: bool = selection.selected.size() == 5
		var dir: Vector2 = Vector2.from_angle(TAU * i / 10.0) * 150.0
		_tap(camera.world_to_screen(Formation.centroid(_positions())) + dir)
		var ordered: bool = selection.selected.all(func(u: Unit) -> bool: return u.is_moving())
		await physics_frames(90)
		if one and five and ordered:
			ok += 1
	check(ok == 10, "10/10 cycles of tap-select, box-select and move order (got %d)" % ok)


func test_99_teardown() -> void:
	main.queue_free()
	await frames(1)


func _positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for u: Unit in world.units:
		out.append(u.position)
	return out
