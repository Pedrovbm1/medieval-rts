class_name MovementSystem
extends Node
## Moves every unit on the map in one loop per physics frame:
## 1. computes queued paths (amortised budget),
## 2. rebuilds the spatial hash,
## 3. re-paths units whose route was cut (or could now be shorter),
## 4. steers each unit: follow waypoints + separation + wall sliding.
## Groups share one A* path; each unit joins it and peels off to its slot.

var nav: NavGrid
var units: Array[Unit] = []
var queue: PathQueue = PathQueue.new()
var spatial: SpatialHash = SpatialHash.new(64.0)

var _spacing: float = 40.0
var _waypoint_reach: float = 24.0
var _separation_gain: float = 6.0
var _stall_seconds: float = 1.0
var _max_repaths: int = 3
var _next_group_id: int = 1
## Cost of the last physics step of this system, for profiling.
var last_step_usec: int = 0
var last_queue_usec: int = 0


func setup(p_nav: NavGrid, p_units: Array[Unit]) -> void:
	nav = p_nav
	units = p_units
	queue.budget = int(DataLoader.rule("movement", "paths_per_frame", 8))
	queue.budget_usec = int(DataLoader.rule("movement", "path_budget_usec", 2500))
	_spacing = float(DataLoader.rule("movement", "formation_spacing_px", 40))
	_waypoint_reach = float(DataLoader.rule("movement", "waypoint_reach_px", 24))
	_separation_gain = float(DataLoader.rule("movement", "separation_gain", 6.0))
	_stall_seconds = float(DataLoader.rule("movement", "stall_seconds", 1.0))
	_max_repaths = int(DataLoader.rule("movement", "max_repaths", 3))


## Group order: one shared path, formation slots at the destination.
## `formation`: "none" spreads the group around the point; "line", "box"
## and "wedge" arrange it by role, facing the direction of the march.
func command_move(group: Array[Unit], target: Vector2, formation: String = "none") -> void:
	var movers: Array[Unit] = group.filter(func(u: Unit) -> bool: return is_instance_valid(u))
	if movers.is_empty() or nav == null:
		return
	var goal_cell: Vector2i = nav.nearest_walkable(nav.to_cell(target), 40, movers[0].owner_id)
	if nav.to_cell(target) != goal_cell:
		target = nav.cell_center(goal_cell)
	var positions: Array[Vector2] = []
	for u: Unit in movers:
		positions.append(u.position)
	var assigned: Array[Vector2]
	if formation != "none" and movers.size() > 1:
		assigned = FormationLayout.layout(formation, target, target - Formation.centroid(positions), movers, _spacing, nav)
	else:
		var slots: Array[Vector2] = Formation.walkable_slots(target, movers.size(), _spacing, nav)
		assigned = Formation.assign(positions, slots)
	var group_id: int = _next_group_id
	_next_group_id += 1
	for i: int in movers.size():
		_begin(movers[i], assigned[i], group_id)
	if movers.size() == 1:
		_request_individual(movers[0])
		return
	var leader: Unit = _closest_to(movers, Formation.centroid(positions))
	queue.request(-group_id, leader.position, target, _on_group_path.bind(group_id, target), leader.owner_id)


## Single unit order (used by unit behaviours: go gather, go build, chase...).
func move_unit(unit: Unit, target: Vector2) -> void:
	if nav == null:
		return
	var cell: Vector2i = nav.nearest_walkable(nav.to_cell(target), 40, unit.owner_id)
	if cell != nav.to_cell(target):
		target = nav.cell_center(cell)
	_begin(unit, target, 0)
	_request_individual(unit)


func stop(unit: Unit) -> void:
	queue.cancel(unit.get_instance_id())
	unit.clear_move()
	unit.attack_move = false


func _begin(unit: Unit, goal: Vector2, group_id: int) -> void:
	queue.cancel(unit.get_instance_id())
	unit.goal = goal
	unit.group_id = group_id
	unit.path = PackedVector2Array()
	unit.path_i = 0
	unit.waiting_path = true
	unit.repaths = 0
	unit.stall_timer = 0.0
	unit.best_goal_dist = INF


func _request_individual(unit: Unit) -> void:
	unit.waiting_path = true
	queue.request(unit.get_instance_id(), unit.position, unit.goal, _on_unit_path.bind(unit, unit.goal), unit.owner_id)


func _on_unit_path(path: PackedVector2Array, unit: Unit, goal: Vector2) -> void:
	if not is_instance_valid(unit) or unit.goal != goal:
		return
	if path.is_empty():
		unit.fail_move()
		return
	unit.path = path
	unit.path_i = 1 if path.size() > 1 else 0
	unit.waiting_path = false


func _on_group_path(shared: PackedVector2Array, group_id: int, target: Vector2) -> void:
	for unit: Unit in units:
		if unit.group_id != group_id or not unit.waiting_path:
			continue
		if shared.is_empty():
			unit.fail_move()
			continue
		var joined: PackedVector2Array = _join_shared(unit, shared)
		if joined.is_empty():
			_request_individual(unit)
		else:
			unit.path = joined
			unit.path_i = 0
			unit.waiting_path = false


## Builds a unit path that joins the shared route and ends at the unit's slot.
## Empty when the unit cannot see the route (it then gets its own A*).
func _join_shared(unit: Unit, shared: PackedVector2Array) -> PackedVector2Array:
	var join: int = -1
	for j: int in range(mini(4, shared.size() - 1), 0, -1):
		if nav.has_los(unit.position, shared[j], 10.0, unit.owner_id):
			join = j
			break
	if join == -1:
		return PackedVector2Array()
	var body: PackedVector2Array = shared.slice(join, shared.size() - 1)
	var last: Vector2 = unit.position if body.is_empty() else body[body.size() - 1]
	var end: Vector2 = shared[shared.size() - 1]
	if not nav.has_los(last, unit.goal, 10.0, unit.owner_id):
		if not nav.has_los(end, unit.goal, 10.0, unit.owner_id):
			return PackedVector2Array()
		body.append(end)
	body.append(unit.goal)
	return body


func _physics_process(delta: float) -> void:
	if nav == null:
		return
	var t0: int = Time.get_ticks_usec()
	_step(delta)
	last_step_usec = Time.get_ticks_usec() - t0


func _step(delta: float) -> void:
	var tq: int = Time.get_ticks_usec()
	queue.process(nav)
	last_queue_usec = Time.get_ticks_usec() - tq
	spatial.clear()
	for unit: Unit in units:
		spatial.insert(unit, unit.position)
	_handle_nav_changes()
	for unit: Unit in units:
		_steer(unit, delta)
		unit.animate(delta)


func _handle_nav_changes() -> void:
	var changes: Dictionary = nav.consume_changes()
	if not changes["blocked"] and not changes["unblocked"]:
		return
	for unit: Unit in units:
		if not unit.is_moving() or unit.waiting_path:
			continue
		if not nav.is_walkable_world_for(unit.goal, unit.owner_id):
			unit.goal = nav.cell_center(nav.nearest_walkable(nav.to_cell(unit.goal), 40, unit.owner_id))
			_request_individual(unit)
		elif changes["unblocked"] or not _route_clear(unit):
			_request_individual(unit)


func _route_clear(unit: Unit) -> bool:
	var prev: Vector2 = unit.position
	for i: int in range(unit.path_i, unit.path.size()):
		if not nav.has_los(prev, unit.path[i], 0.0, unit.owner_id):
			return false
		prev = unit.path[i]
	return true


func _steer(unit: Unit, delta: float) -> void:
	var velocity: Vector2 = _separation(unit)
	var moving: bool = unit.is_moving() and not unit.waiting_path and not unit.path.is_empty()
	if moving:
		var wp: Vector2 = unit.path[unit.path_i]
		var to_wp: Vector2 = wp - unit.position
		var dist: float = to_wp.length()
		var is_last: bool = unit.path_i >= unit.path.size() - 1
		var reach: float = unit.arrive_distance if is_last else _waypoint_reach
		if dist <= maxf(reach, unit.speed_px * delta):
			if is_last:
				unit.position = _slide(unit, unit.position, wp)
				unit.finish_move()
				return
			unit.path_i += 1
			wp = unit.path[unit.path_i]
			to_wp = wp - unit.position
			dist = to_wp.length()
		if dist > 0.001:
			velocity += to_wp / dist * unit.speed_px
		velocity = velocity.limit_length(unit.speed_px * 1.1)
		_track_progress(unit, delta)
	else:
		velocity = velocity.limit_length(unit.speed_px * 0.6)
	if velocity.length_squared() > 0.01:
		unit.position = _slide(unit, unit.position, unit.position + velocity * delta)
	if not nav.is_walkable_world_for(unit.position, unit.owner_id):
		# Something was built on top of the unit (or a gate closed on an
		# intruder): walk it out to free ground.
		var free: Vector2 = nav.cell_center(nav.nearest_walkable(nav.to_cell(unit.position), 40, unit.owner_id))
		unit.position = unit.position.move_toward(free, unit.speed_px * delta)


## Push away from overlapping neighbours. Moving units yield less than idle ones.
func _separation(unit: Unit) -> Vector2:
	var push: Vector2 = Vector2.ZERO
	for other: Object in spatial.query(unit.position, unit.radius * 2.0 + 8.0):
		if other == unit:
			continue
		var o: Unit = other as Unit
		var offset: Vector2 = unit.position - o.position
		var min_dist: float = unit.radius + o.radius + 2.0
		var d2: float = offset.length_squared()
		if d2 >= min_dist * min_dist:
			continue
		var d: float = sqrt(d2)
		var dir: Vector2 = offset / d if d > 0.01 else Vector2.from_angle(float(unit.get_instance_id() % 628) * 0.01)
		var weight: float = 0.5 if unit.is_moving() and o.is_moving() else 1.0
		push += dir * (min_dist - d) * _separation_gain * weight
	return push


## Moves toward `to`, sliding along walls instead of entering blocked cells
## (a closed gate is a wall for everyone but its owner).
func _slide(unit: Unit, from: Vector2, to: Vector2) -> Vector2:
	if nav.is_walkable_world_for(to, unit.owner_id):
		return to
	var try_x: Vector2 = Vector2(to.x, from.y)
	if nav.is_walkable_world_for(try_x, unit.owner_id):
		return try_x
	var try_y: Vector2 = Vector2(from.x, to.y)
	if nav.is_walkable_world_for(try_y, unit.owner_id):
		return try_y
	return from


## Stall handling: crowded at the destination -> done; stuck elsewhere -> re-path, then give up.
func _track_progress(unit: Unit, delta: float) -> void:
	var goal_dist: float = unit.position.distance_to(unit.goal)
	if goal_dist < unit.best_goal_dist - 4.0:
		unit.best_goal_dist = goal_dist
		unit.stall_timer = 0.0
		return
	unit.stall_timer += delta
	if unit.stall_timer < _stall_seconds:
		return
	unit.stall_timer = 0.0
	unit.best_goal_dist = goal_dist
	if goal_dist < _spacing * 2.5:
		unit.finish_move()
	elif unit.repaths < _max_repaths:
		unit.repaths += 1
		_request_individual(unit)
	else:
		unit.fail_move()


func _closest_to(group: Array[Unit], point: Vector2) -> Unit:
	var best: Unit = group[0]
	var best_d: float = INF
	for u: Unit in group:
		var d: float = u.position.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = u
	return best
