class_name GatherTask
extends UnitTask
## Villager economy loop: walk to the resource, gather until full, walk to the
## nearest accepting drop-off, deliver, repeat. When the target runs out it
## looks for another of the same subtype nearby; if none, it delivers what it
## carries and goes idle (so the idle bell can call the player).

enum Target { NODE, TREE, FARM, NONE }
enum Step { TO_TARGET, GATHERING, TO_DROPOFF }

const REACH_SLACK: float = 28.0
const MAX_MOVE_ATTEMPTS: int = 4
const RETARGET_NODE_PX: float = 640.0
const RETARGET_TREE_CELLS: int = 10

var target: Target = Target.NONE
var node: ResourceNode = null
var tree_cell: Vector2i = Vector2i(-1, -1)
var farm: Building = null
var resource: String = ""
var subtype: String = ""
var step: Step = Step.TO_TARGET
var dropoff: Building = null
## Where the last target was: retargeting searches around here.
var anchor: Vector2 = Vector2.ZERO
var _attempts: int = 0


static func for_node(p_unit: Unit, p_world: World, p_node: ResourceNode) -> GatherTask:
	var t: GatherTask = GatherTask.new(p_unit, p_world)
	t._set_node(p_node)
	return t


static func for_tree(p_unit: Unit, p_world: World, cell: Vector2i) -> GatherTask:
	var t: GatherTask = GatherTask.new(p_unit, p_world)
	t._set_tree(cell)
	return t


static func for_farm(p_unit: Unit, p_world: World, building: Building) -> GatherTask:
	var t: GatherTask = GatherTask.new(p_unit, p_world)
	t.target = Target.FARM
	t.farm = building
	var info: Dictionary = building.gather_info()
	t.resource = String(info.get("resource", "food"))
	t.subtype = String(info.get("subtype", "farm"))
	t.anchor = building.position
	return t


## Only deliver what the unit carries to `building`, then go idle.
static func deliver_to(p_unit: Unit, p_world: World, building: Building) -> GatherTask:
	var t: GatherTask = GatherTask.new(p_unit, p_world)
	t.target = Target.NONE
	t.resource = p_unit.carry_type
	t.dropoff = building
	t.step = Step.TO_DROPOFF
	return t


func _init(p_unit: Unit, p_world: World) -> void:
	super(p_unit, p_world)
	kind = "gather"


func tick(delta: float) -> void:
	match step:
		Step.TO_TARGET:
			_tick_to_target()
		Step.GATHERING:
			_tick_gathering(delta)
		Step.TO_DROPOFF:
			_tick_to_dropoff()


func cancel() -> void:
	if farm != null and is_instance_valid(farm):
		farm.workers.erase(unit)


# ------------------------------------------------------------------ steps

func _tick_to_target() -> void:
	if not _target_valid():
		if not _retarget():
			_wrap_up()
		return
	var rect: Rect2 = _target_rect()
	if _in_reach(rect):
		world.movement.stop(unit)
		_attempts = 0
		step = Step.GATHERING
		return
	if unit.is_moving():
		return
	if _attempts >= MAX_MOVE_ATTEMPTS:
		# Could not get next to it (crowded or walled in): try another one.
		_attempts = 0
		if not _retarget(true):
			_wrap_up()
		return
	_attempts += 1
	go_to(_stand_point(rect))


func _tick_gathering(delta: float) -> void:
	if not _target_valid():
		if unit.carry_amount >= 1.0:
			_begin_dropoff()
		elif not _retarget():
			_wrap_up()
		else:
			step = Step.TO_TARGET
		return
	if not _in_reach(_target_rect()):
		step = Step.TO_TARGET
		return
	if unit.carry_type != resource:
		# Switching resource drops the old load (genre rule).
		if unit.carry_amount > 0.0:
			world.economy.record_dropped(unit.owner_id, unit.carry_type, unit.carry_amount)
		unit.carry_type = resource
		unit.carry_amount = 0.0
	var before: int = int(unit.carry_amount)
	var want: float = world.economy.gather_rate(unit, subtype) * delta
	var got: float = _take(want)
	world.economy.record_taken(unit.owner_id, resource, got)
	unit.carry_amount += got
	if int(unit.carry_amount) != before:
		unit.queue_redraw()
	if unit.carry_amount >= world.economy.carry_capacity(unit) or not _target_valid():
		_begin_dropoff()


func _tick_to_dropoff() -> void:
	if dropoff == null or not is_instance_valid(dropoff) or not dropoff.accepts(unit.carry_type):
		dropoff = world.economy.nearest_dropoff(unit.owner_id, unit.carry_type, unit.position)
		if dropoff == null:
			return  # Nowhere to deliver: wait here with the load.
	var rect: Rect2 = dropoff.rect()
	if World.distance_to_rect(unit.position, rect) <= unit.radius + REACH_SLACK:
		world.movement.stop(unit)
		world.economy.deliver(unit)
		unit.queue_redraw()
		_attempts = 0
		if target == Target.NONE:
			finish()
		elif _target_valid() or _retarget():
			step = Step.TO_TARGET
		else:
			if OS.is_debug_build() and bool(DataLoader.rule("debug", "log_tasks", false)):
				print("[REALM] task end_after_delivery %s target=%d sub=%s node_valid=%s farm=%s" % [unit.name, target, subtype,
					str(node != null and is_instance_valid(node) and not node.is_depleted()),
					("%d workers %s" % [farm.workers.size(), str(farm.workers.map(func(w: Unit) -> String: return w.name))]) if farm != null and is_instance_valid(farm) else "-"])
			finish()
		return
	if unit.is_moving():
		return
	if _attempts >= MAX_MOVE_ATTEMPTS * 2:
		_attempts = 0
		dropoff = null
		return
	_attempts += 1
	go_to(world.approach_point(rect, unit.position))


func _begin_dropoff() -> void:
	step = Step.TO_DROPOFF
	_attempts = 0
	dropoff = world.economy.nearest_dropoff(unit.owner_id, unit.carry_type, unit.position)


## Out of targets: deliver whatever is carried, then idle.
func _wrap_up() -> void:
	if OS.is_debug_build() and bool(DataLoader.rule("debug", "log_tasks", false)):
		print("[REALM] task wrap_up %s target=%d sub=%s valid=%s farm_workers=%s" % [unit.name, target, subtype, _target_valid(),
			str(farm.workers.size()) if farm != null and is_instance_valid(farm) else "-"])
	target = Target.NONE
	if unit.carry_amount >= 1.0:
		_begin_dropoff()
	else:
		finish()


# ------------------------------------------------------------------ target helpers

func _set_node(n: ResourceNode) -> void:
	target = Target.NODE
	node = n
	resource = n.resource
	subtype = n.subtype
	anchor = n.position


func _set_tree(cell: Vector2i) -> void:
	target = Target.TREE
	tree_cell = cell
	resource = "wood"
	subtype = "wood"
	anchor = world.cell_center(cell)


func _target_valid() -> bool:
	match target:
		Target.NODE:
			return node != null and is_instance_valid(node) and not node.is_depleted()
		Target.TREE:
			return world.is_tree(tree_cell)
		Target.FARM:
			return farm != null and is_instance_valid(farm) and farm.is_complete() and farm.has_free_work_slot(unit)
	return false


func _target_rect() -> Rect2:
	match target:
		Target.NODE:
			return node.rect()
		Target.TREE:
			return world.cell_rect(tree_cell)
		Target.FARM:
			return farm.rect()
	return Rect2()


func _stand_point(rect: Rect2) -> Vector2:
	if target == Target.FARM:
		return rect.get_center()
	return world.approach_point(rect, unit.position)


func _in_reach(rect: Rect2) -> bool:
	if target == Target.FARM:
		if rect.grow(-6.0).has_point(unit.position):
			if not farm.workers.has(unit):
				farm.workers.append(unit)
			return true
		return false
	return World.distance_to_rect(unit.position, rect) <= unit.radius + REACH_SLACK


func _take(want: float) -> float:
	match target:
		Target.NODE:
			return node.take(want)
		Target.TREE:
			return world.take_from_tree(tree_cell, want)
		Target.FARM:
			return want
	return 0.0


## Finds another target of the same subtype around the anchor.
## `skip_current` avoids picking the same blocked target again.
func _retarget(skip_current: bool = false) -> bool:
	match target:
		Target.NODE:
			var old: ResourceNode = node
			var found: ResourceNode = world.find_node_near(subtype, anchor, RETARGET_NODE_PX)
			if found != null and (not skip_current or found != old):
				_set_node(found)
				return true
		Target.TREE:
			var exclude: Vector2i = tree_cell
			var cell: Vector2i = world.find_tree_near(anchor, RETARGET_TREE_CELLS)
			if skip_current and cell == exclude:
				cell = world.find_tree_near(anchor + Vector2(world.tile_size * 2, 0), RETARGET_TREE_CELLS)
			if cell.x >= 0 and (not skip_current or cell != exclude):
				_set_tree(cell)
				return true
	return false
