class_name SelectionController
extends Node
## Turns classified gestures into selection changes and orders.
## Owns the human player's current selection (units, or one building).
## Smart orders: what the finger touches decides the order (gather, hunt,
## deliver, move) per selected unit.

signal selection_changed(units: Array[Unit])
signal building_selected(building: Building)

const ORDER_COLORS: Dictionary = {
	"move": Color(0.45, 1.0, 0.45),
	"gather": Color(1.0, 0.85, 0.3),
	"hunt": Color(1.0, 0.45, 0.35),
	"deliver": Color(0.5, 0.8, 1.0),
}

var world: World
var camera: CameraController
var order_marker: OrderMarker
var player_id: int = GameState.PLAYER_HUMAN
var selected: Array[Unit] = []
var selected_building: Building = null

var _pick_radius_screen: float = 40.0
var _log: bool = false


func setup(p_world: World, p_camera: CameraController, p_marker: OrderMarker) -> void:
	world = p_world
	camera = p_camera
	order_marker = p_marker
	_pick_radius_screen = float(DataLoader.rule("input", "pick_radius_px", 40))
	_log = bool(DataLoader.rule("debug", "log_input", false)) and OS.is_debug_build()
	EventBus.unit_removed.connect(_on_unit_removed)
	EventBus.building_removed.connect(_on_building_removed)


## Single tap: select what is under the finger, or order the selection there.
func on_tap(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = camera.screen_to_world(screen_pos)
	var target: Dictionary = resolve_target(world_pos)
	var kind: String = String(target["kind"])
	var has_gatherers: bool = selected.any(func(u: Unit) -> bool: return u.can_gather())
	if kind == "own_unit" and not (has_gatherers and (target["ref"] as Unit).is_animal()):
		set_selection([target["ref"]])
		Sfx.play("select")
	elif selected.is_empty() and selected_building != null and is_instance_valid(selected_building) 			and kind != "own_building" and not selected_building.trains().is_empty():
		# A producing building is selected: the tap sets its rally point.
		selected_building.rally_point = world_pos
		if order_marker != null:
			order_marker.show_order(selected_building.position, world_pos, Color(0.5, 0.8, 1.0))
		Sfx.play("order_move")
	elif kind == "own_building" and not _any_task_for(target):
		# Nothing to do there for the selection (not a foundation, farm or
		# drop-off they need): the tap selects the building instead.
		select_building(target["ref"])
		Sfx.play("select")
	elif not selected.is_empty():
		issue_order(world_pos, target)
	elif kind == "own_building":
		select_building(target["ref"])
		Sfx.play("select")
	_trace("tap", world_pos)


## Double tap on a unit: every own unit of that type on screen.
## On ground: same as a tap when something is selected, else glide the camera there.
func on_double_tap(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = camera.screen_to_world(screen_pos)
	var unit: Unit = _pick_own(world_pos)
	if unit != null and not unit.is_animal():
		var same_type: Array[Unit] = []
		for candidate: Unit in world.units_in_rect(camera.visible_world_rect(), player_id):
			if candidate.unit_type == unit.unit_type:
				same_type.append(candidate)
		set_selection(same_type)
		Sfx.play("select")
	elif not selected.is_empty():
		issue_order(world_pos, resolve_target(world_pos))
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


## What is at a world point, from the player's point of view.
## kind: own_unit | animal | enemy_unit | node | own_building | enemy_building | tree | ground
func resolve_target(world_pos: Vector2) -> Dictionary:
	var radius: float = _pick_radius_screen / camera.get_zoom_factor()
	var own: Unit = world.pick_unit(world_pos, radius, player_id)
	if own != null:
		return {"kind": "own_unit", "ref": own}
	var any: Unit = world.pick_any_unit(world_pos, radius)
	if any != null:
		return {"kind": "animal" if any.is_animal() else "enemy_unit", "ref": any}
	var node: ResourceNode = world.node_at(world_pos, radius * 0.5)
	if node != null:
		return {"kind": "node", "ref": node}
	var b: Building = world.building_at(world_pos)
	if b != null:
		return {"kind": "own_building" if b.owner_id == player_id else "enemy_building", "ref": b}
	var cell: Vector2i = world.world_to_cell(world_pos)
	if world.is_tree(cell):
		return {"kind": "tree", "ref": cell}
	return {"kind": "ground", "ref": null}


## Gives each selected unit the order that fits the target.
func issue_order(world_pos: Vector2, target: Dictionary) -> void:
	_prune()
	if selected.is_empty():
		return
	var kind: String = String(target["kind"])
	var movers: Array[Unit] = []
	var order_kind: String = "move"
	for unit: Unit in selected:
		var task: UnitTask = _task_for(unit, kind, target.get("ref"))
		if task != null:
			world.behavior.assign(unit, task)
			order_kind = task.kind if task.kind != "gather" or kind != "own_building" else "deliver"
		else:
			world.behavior.assign(unit, null)
			unit.stance = Unit.Stance.AGGRESSIVE
			movers.append(unit)
	if not movers.is_empty():
		world.movement.command_move(movers, world_pos)
	if order_marker != null:
		var positions: Array[Vector2] = []
		for unit: Unit in selected:
			positions.append(unit.position)
		order_marker.show_order(Formation.centroid(positions), world_pos, ORDER_COLORS.get(order_kind, ORDER_COLORS["move"]))
	Sfx.play("order_move")
	_trace("order_" + order_kind, world_pos)


## Plain move for the whole selection (tests, HUD).
func order_move(world_pos: Vector2) -> void:
	issue_order(world_pos, {"kind": "ground", "ref": null})


func _task_for(unit: Unit, kind: String, ref: Variant) -> UnitTask:
	if not unit.can_gather():
		return null
	match kind:
		"tree":
			return GatherTask.for_tree(unit, world, ref)
		"node":
			return GatherTask.for_node(unit, world, ref)
		"animal", "own_unit":
			var prey: Unit = ref
			if prey != null and prey.is_animal():
				return HuntTask.new(unit, world, prey)
		"own_building":
			var b: Building = ref
			if not b.is_complete():
				return BuildTask.new(unit, world, b)
			if not b.gather_info().is_empty():
				return GatherTask.for_farm(unit, world, b)
			if unit.carry_amount >= 1.0 and b.accepts(unit.carry_type):
				return GatherTask.deliver_to(unit, world, b)
	return null


func _any_task_for(target: Dictionary) -> bool:
	for unit: Unit in selected:
		if is_instance_valid(unit) and _task_for(unit, String(target["kind"]), target.get("ref")) != null:
			return true
	return false


func order_stop() -> void:
	_prune()
	for unit: Unit in selected:
		world.behavior.assign(unit, null)
		world.movement.stop(unit)
	if not selected.is_empty():
		Sfx.play("order_stop")
	_trace("stop", Vector2.ZERO)


func order_hold() -> void:
	_prune()
	for unit: Unit in selected:
		world.behavior.assign(unit, null)
		world.movement.stop(unit)
		unit.stance = Unit.Stance.HOLD
	if not selected.is_empty():
		Sfx.play("order_stop")
	_trace("hold", Vector2.ZERO)


func clear_selection() -> void:
	set_selection([])
	_trace("clear", Vector2.ZERO)


func set_selection(units: Array[Unit]) -> void:
	_set_building(null)
	for unit: Unit in selected:
		if is_instance_valid(unit):
			unit.selected = false
	selected = units.duplicate()
	for unit: Unit in selected:
		unit.selected = true
	selection_changed.emit(selected)


func select_building(b: Building) -> void:
	set_selection([])
	_set_building(b)


func _set_building(b: Building) -> void:
	if selected_building != null and is_instance_valid(selected_building):
		selected_building.selected = false
	selected_building = b
	if b != null:
		b.selected = true
	building_selected.emit(b)


func _pick_own(world_pos: Vector2) -> Unit:
	return world.pick_unit(world_pos, _pick_radius_screen / camera.get_zoom_factor(), player_id)


func _prune() -> void:
	selected = selected.filter(func(u: Unit) -> bool: return is_instance_valid(u) and not u.is_dead)


func _on_unit_removed(unit: Unit) -> void:
	if selected.has(unit):
		selected.erase(unit)
		selection_changed.emit(selected)


func _on_building_removed(b: Building) -> void:
	if selected_building == b:
		selected_building = null
		building_selected.emit(null)


func _trace(action: String, world_pos: Vector2) -> void:
	if _log:
		print("[REALM] %s selected=%d at=(%d,%d)" % [action, selected.size(), int(world_pos.x), int(world_pos.y)])
