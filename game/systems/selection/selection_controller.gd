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
	"attack": Color(1.0, 0.3, 0.25),
	"build": Color(1.0, 0.85, 0.3),
}

const WORK_KINDS: PackedStringArray = ["gather", "build", "hunt", "deliver", "repair", "garrison"]

var world: World
var camera: CameraController
var order_marker: OrderMarker
## Every order leaves through here as a plain command (local play applies it
## at once; a networked match schedules it for a later turn on both devices).
var bus: CommandBus = null
var player_id: int = GameState.PLAYER_HUMAN
var selected: Array[Unit] = []
## Battle formation for group orders (FormationLayout.KINDS; "none" = spread).
var formation: String = "none"
## The next tap on the ground is an attack-move for the selected soldiers.
var attack_armed: bool = false
signal attack_armed_changed(armed: bool)
signal formation_changed(kind: String)


## Cycles none -> line -> box -> wedge -> none. Returns the new kind.
func cycle_formation() -> String:
	var i: int = FormationLayout.KINDS.find(formation)
	formation = FormationLayout.KINDS[(i + 1) % FormationLayout.KINDS.size()]
	formation_changed.emit(formation)
	return formation


func arm_attack_move(on: bool) -> void:
	if attack_armed == on:
		return
	attack_armed = on
	attack_armed_changed.emit(on)
var selected_building: Building = null
## Control groups 1-5: number -> Array[Unit]
var groups: Dictionary = {}

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
	if bus == null:
		# Stand-alone use (tests without the match scene): a private local bus.
		bus = CommandBus.new()
		bus.name = "CommandBus"
		bus.setup(world)
		add_child(bus)


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
		bus.submit({"type": "rally", "player": player_id, "building": selected_building.sim_id, "pos": OrderResolver.vec_to_arr(world_pos)})
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
	# With villagers selected, a tap first means "work there": resources,
	# trees, own farms / drop-offs / foundations win over another villager
	# standing next to them, and the touch zone is generous (fingers are
	# not precise, least of all zoomed out).
	if selected.any(func(u: Unit) -> bool: return is_instance_valid(u) and u.can_gather()):
		var work: Dictionary = _work_target(world_pos, radius)
		if not work.is_empty():
			return work
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
		if b.owner_id < 0:
			return {"kind": "neutral_building", "ref": b}  # the trade post: nobody attacks it
		return {"kind": "own_building" if b.owner_id == player_id else "enemy_building", "ref": b}
	var cell: Vector2i = world.world_to_cell(world_pos)
	if world.is_tree(cell):
		return {"kind": "tree", "ref": cell}
	return {"kind": "ground", "ref": null}


## Something villagers can work on near the tap, or {} if nothing.
func _work_target(world_pos: Vector2, radius: float) -> Dictionary:
	var slack: float = radius * float(DataLoader.rule("input", "work_pick_factor", 0.8))
	var node: ResourceNode = world.nearest_node_at(world_pos, slack)
	if node != null:
		return {"kind": "node", "ref": node}
	var b: Building = world.building_near(world_pos, slack * 0.5)
	if b != null and b.owner_id == player_id and _any_task_for({"kind": "own_building", "ref": b}):
		return {"kind": "own_building", "ref": b}
	var animal: Unit = world.pick_any_unit(world_pos, radius)
	if animal != null and animal.is_animal():
		return {"kind": "animal", "ref": animal}
	var cell: Vector2i = world.tree_near_point(world_pos, slack + world.tile_size * 0.5)
	if cell.x >= 0:
		return {"kind": "tree", "ref": cell}
	return {}


## Gives each selected unit the order that fits the target: builds one
## "order" command and submits it (CommandBus / OrderResolver do the rest).
## The marker colour and which villagers leave the selection are predicted
## here from the same resolver, so they work even when the command only
## applies two turns later in a networked match.
func issue_order(world_pos: Vector2, target: Dictionary) -> void:
	_prune()
	if selected.is_empty():
		return
	var kind: String = String(target["kind"])
	var armed: bool = attack_armed
	if armed:
		arm_attack_move(false)
	var order_kind: String = "move"
	var workers: Array[Unit] = []
	for unit: Unit in selected:
		if armed and not unit.can_gather() and not unit.data.get("combat", {}).is_empty():
			order_kind = "attack"
			continue
		var task: UnitTask = OrderResolver.task_for(world, unit, kind, target.get("ref"))
		if task != null:
			order_kind = task.kind if task.kind != "gather" or kind != "own_building" else "deliver"
			if unit.can_gather() and WORK_KINDS.has(task.kind):
				workers.append(unit)
	bus.submit(CommandBus.order_cmd(player_id, selected, target, world_pos, formation, armed))
	if order_marker != null:
		var positions: Array[Vector2] = []
		for unit: Unit in selected:
			positions.append(unit.position)
		order_marker.show_order(Formation.centroid(positions), world_pos, ORDER_COLORS.get(order_kind, ORDER_COLORS["move"]))
	Sfx.play("order_move")
	_trace("order_" + order_kind, world_pos)
	_release_workers(workers)


## Monks (not gatherers) still take relic work from a tap.
## Villagers that just got work (gather, build, hunt, deliver) leave the
## selection, so the next tap does not pull them off the job. Soldiers stay
## selected: they usually get several orders in a row.
func _release_workers(workers: Array[Unit]) -> void:
	if not bool(DataLoader.rule("input", "deselect_after_work_order", true)) or workers.is_empty():
		return
	var keep: Array[Unit] = selected.filter(func(u: Unit) -> bool: return not workers.has(u))
	if keep.size() != selected.size():
		set_selection(keep)


## Releases these villagers from the selection (after placing a building).
func release(units: Array[Unit]) -> void:
	if not bool(DataLoader.rule("input", "deselect_after_work_order", true)):
		return
	var keep: Array[Unit] = selected.filter(func(u: Unit) -> bool: return not units.has(u))
	if keep.size() != selected.size():
		set_selection(keep)


## Plain move for the whole selection (tests, HUD).
func order_move(world_pos: Vector2) -> void:
	issue_order(world_pos, {"kind": "ground", "ref": null})


## What a unit would do with this target (the shared resolver decides).
func _task_for(unit: Unit, kind: String, ref: Variant) -> UnitTask:
	return OrderResolver.task_for(world, unit, kind, ref)


func _any_task_for(target: Dictionary) -> bool:
	for unit: Unit in selected:
		if is_instance_valid(unit) and _task_for(unit, String(target["kind"]), target.get("ref")) != null:
			return true
	return false


func order_stop() -> void:
	_prune()
	if not selected.is_empty():
		bus.submit({"type": "stop", "player": player_id, "units": OrderResolver.ids_of(selected)})
		Sfx.play("order_stop")
	_trace("stop", Vector2.ZERO)


func order_hold() -> void:
	_prune()
	if not selected.is_empty():
		bus.submit({"type": "hold", "player": player_id, "units": OrderResolver.ids_of(selected)})
		Sfx.play("order_stop")
	_trace("hold", Vector2.ZERO)


## Saves the current unit selection as group `n` (1-5).
func assign_group(n: int) -> void:
	_prune()
	groups[n] = selected.duplicate()
	Sfx.play("order_stop")
	_trace("group_assign_%d" % n, Vector2.ZERO)


## Selects group `n`; selecting it again while already selected centres the camera.
func recall_group(n: int) -> void:
	var members: Array = groups.get(n, [])
	var alive: Array[Unit] = []
	for u: Variant in members:
		if is_instance_valid(u) and world.units.has(u):
			alive.append(u)
	groups[n] = alive
	if alive.is_empty():
		return
	var same: bool = alive.size() == selected.size() and alive.all(func(u: Unit) -> bool: return selected.has(u))
	set_selection(alive)
	Sfx.play("select")
	if same:
		var pos: Array[Vector2] = []
		for u: Unit in alive:
			pos.append(u.position)
		camera.center_on_smooth(Formation.centroid(pos))
	_trace("group_recall_%d" % n, Vector2.ZERO)


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
