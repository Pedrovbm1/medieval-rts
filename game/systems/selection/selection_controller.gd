class_name SelectionController
extends Node
## Turns classified gestures into selection changes and orders.
## Owns the current selection of the human player.

signal selection_changed(units: Array[Unit])

var world: World
var camera: CameraController
var order_marker: OrderMarker
var player_id: int = GameState.PLAYER_HUMAN
var selected: Array[Unit] = []

var _pick_radius_screen: float = 40.0
var _spacing: float = 40.0
var _log: bool = false


func setup(p_world: World, p_camera: CameraController, p_marker: OrderMarker) -> void:
	world = p_world
	camera = p_camera
	order_marker = p_marker
	_pick_radius_screen = float(DataLoader.rule("input", "pick_radius_px", 40))
	_spacing = float(DataLoader.rule("movement", "formation_spacing_px", 40))
	_log = bool(DataLoader.rule("debug", "log_input", false)) and OS.is_debug_build()


## Single tap: select the unit under the finger, or move the selection there.
func on_tap(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = camera.screen_to_world(screen_pos)
	var unit: Unit = _pick(world_pos)
	if unit != null:
		set_selection([unit])
		Sfx.play("select")
	elif not selected.is_empty():
		order_move(world_pos)
	_trace("tap", world_pos)


## Double tap on a unit: every own unit of that type on screen.
## On ground: same as a tap when something is selected, else glide the camera there.
func on_double_tap(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = camera.screen_to_world(screen_pos)
	var unit: Unit = _pick(world_pos)
	if unit != null:
		var same_type: Array[Unit] = []
		for candidate: Unit in world.units_in_rect(camera.visible_world_rect(), player_id):
			if candidate.unit_type == unit.unit_type:
				same_type.append(candidate)
		set_selection(same_type)
		Sfx.play("select")
	elif not selected.is_empty():
		order_move(world_pos)
	else:
		camera.center_on_smooth(world_pos)
	_trace("double_tap", world_pos)


## Box released: select own units inside it (empty box clears the selection).
func on_box_end(screen_from: Vector2, screen_to: Vector2) -> void:
	var a: Vector2 = camera.screen_to_world(screen_from)
	var b: Vector2 = camera.screen_to_world(screen_to)
	var rect: Rect2 = Rect2(a, Vector2.ZERO).expand(b)
	set_selection(world.units_in_rect(rect, player_id))
	if not selected.is_empty():
		Sfx.play("select")
	_trace("box_end", rect.get_center())


func order_move(world_pos: Vector2) -> void:
	_prune()
	if selected.is_empty():
		return
	var positions: Array[Vector2] = []
	for unit: Unit in selected:
		positions.append(unit.position)
		unit.stance = Unit.Stance.AGGRESSIVE
	world.movement.command_move(selected, world_pos)
	if order_marker != null:
		order_marker.show_order(Formation.centroid(positions), world_pos, Color(0.45, 1.0, 0.45))
	Sfx.play("order_move")


func order_stop() -> void:
	_prune()
	for unit: Unit in selected:
		world.movement.stop(unit)
	if not selected.is_empty():
		Sfx.play("order_stop")
	_trace("stop", Vector2.ZERO)


func order_hold() -> void:
	_prune()
	for unit: Unit in selected:
		world.movement.stop(unit)
		unit.stance = Unit.Stance.HOLD
	if not selected.is_empty():
		Sfx.play("order_stop")
	_trace("hold", Vector2.ZERO)


func clear_selection() -> void:
	set_selection([])
	_trace("clear", Vector2.ZERO)


func set_selection(units: Array[Unit]) -> void:
	for unit: Unit in selected:
		if is_instance_valid(unit):
			unit.selected = false
	selected = units.duplicate()
	for unit: Unit in selected:
		unit.selected = true
	selection_changed.emit(selected)


func _pick(world_pos: Vector2) -> Unit:
	return world.pick_unit(world_pos, _pick_radius_screen / camera.get_zoom_factor(), player_id)


func _prune() -> void:
	selected = selected.filter(func(u: Unit) -> bool: return is_instance_valid(u))


func _trace(action: String, world_pos: Vector2) -> void:
	if _log:
		print("[REALM] %s selected=%d at=(%d,%d)" % [action, selected.size(), int(world_pos.x), int(world_pos.y)])
