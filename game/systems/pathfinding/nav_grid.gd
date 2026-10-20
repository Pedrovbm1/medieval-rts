class_name NavGrid
extends RefCounted
## Walkability grid + A* for the whole map. Wraps AStarGrid2D.
## - Terrain decides base walkability (terrain.json "walkable").
## - Dynamic obstacles (buildings, trees, walls) add a block count per cell,
##   so overlapping obstacles unblock correctly.
## - Paths are smoothed with grid line-of-sight (string pulling).

var width: int = 0
var height: int = 0
var cell_size: float = 64.0
## Bumped every time walkability changes; movers compare it to re-path.
var version: int = 0
## Cells whose walkability changed since the last consume_changes().
var changed_blocked: bool = false
var changed_unblocked: bool = false

var _astar: AStarGrid2D = AStarGrid2D.new()
var _terrain_walkable: PackedByteArray = PackedByteArray()
var _block_count: PackedInt32Array = PackedInt32Array()
## Closed gates: cell index -> owner. A closed gate is a wall for everyone
## except its owner, so the shared grid (`_astar`, used for placement and
## line of sight without an owner) ignores gates and each player gets a
## grid of their own where the other side's closed gates are solid.
var _gate_owner: Dictionary = {}
var _astar_by_owner: Dictionary = {}
## Grid used for owner -1 (animals, no owner): every closed gate blocks.
const NOBODY: int = -1


## Builds from a terrain id grid and the terrain table ("types" with "id"/"walkable").
func build(terrain_grid: PackedByteArray, map_width: int, map_height: int, tile_size: int, terrain_def: Dictionary) -> void:
	width = map_width
	height = map_height
	cell_size = float(tile_size)
	var walkable_by_id: Dictionary = {}
	for type_name: String in Dictionary(terrain_def.get("types", {})).keys():
		var entry: Dictionary = terrain_def["types"][type_name]
		walkable_by_id[int(entry.get("id", 0))] = bool(entry.get("walkable", true))

	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, width, height)
	_astar.cell_size = Vector2(cell_size, cell_size)
	_astar.offset = Vector2(cell_size * 0.5, cell_size * 0.5)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()

	_terrain_walkable.resize(width * height)
	_block_count.resize(width * height)
	_block_count.fill(0)
	for y: int in height:
		for x: int in width:
			var i: int = y * width + x
			var walk: bool = bool(walkable_by_id.get(int(terrain_grid[i]), true))
			_terrain_walkable[i] = 1 if walk else 0
			if not walk:
				_astar.set_point_solid(Vector2i(x, y), true)
	_gate_owner.clear()
	_astar_by_owner.clear()
	version += 1


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


## Base walkability: terrain and solid obstacles. Gates do not count here
## (placement and other owner-less checks); see is_walkable_for.
func is_walkable(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	var i: int = cell.y * width + cell.x
	return _terrain_walkable[i] == 1 and _block_count[i] == 0


## Walkability for a unit of `owner`: a closed gate lets its owner through
## and stops everyone else (owner -1 = animals: every closed gate blocks).
func is_walkable_for(cell: Vector2i, owner: int) -> bool:
	if not is_walkable(cell):
		return false
	var i: int = cell.y * width + cell.x
	return not _gate_owner.has(i) or int(_gate_owner[i]) == owner


func is_walkable_world(world_pos: Vector2) -> bool:
	return is_walkable(to_cell(world_pos))


func is_walkable_world_for(world_pos: Vector2, owner: int) -> bool:
	return is_walkable_for(to_cell(world_pos), owner)


## A* grid for one owner, made on first use from the shared one plus the
## other side's closed gates.
func _grid_for(owner: int) -> AStarGrid2D:
	if _astar_by_owner.has(owner):
		return _astar_by_owner[owner]
	var g: AStarGrid2D = AStarGrid2D.new()
	g.region = Rect2i(0, 0, width, height)
	g.cell_size = Vector2(cell_size, cell_size)
	g.offset = Vector2(cell_size * 0.5, cell_size * 0.5)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	for y: int in height:
		for x: int in width:
			var c: Vector2i = Vector2i(x, y)
			if not is_walkable_for(c, owner):
				g.set_point_solid(c, true)
	_astar_by_owner[owner] = g
	return g


## A gate of `owner` closed (true) or opened (false) on these cells: solid
## for every other owner's grid, open on its owner's and on the shared one.
func set_gate(cells: Array[Vector2i], owner: int, closed: bool) -> void:
	var flipped: bool = false
	for cell: Vector2i in cells:
		if not in_bounds(cell):
			continue
		var i: int = cell.y * width + cell.x
		if closed:
			_gate_owner[i] = owner
		else:
			_gate_owner.erase(i)
		for other: int in _astar_by_owner.keys():
			if other == owner:
				continue
			var solid: bool = not is_walkable_for(cell, other)
			var g: AStarGrid2D = _astar_by_owner[other]
			if g.is_point_solid(cell) != solid:
				g.set_point_solid(cell, solid)
				flipped = true
	if flipped or not cells.is_empty():
		version += 1
		if closed:
			changed_blocked = true
		else:
			changed_unblocked = true


func to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / cell_size), floori(world_pos.y / cell_size))


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)


## Changes the terrain walkability of a cell (e.g. a tree was cut down).
func set_terrain_walkable(cell: Vector2i, walkable: bool) -> void:
	if not in_bounds(cell):
		return
	var i: int = cell.y * width + cell.x
	var before: bool = is_walkable(cell)
	_terrain_walkable[i] = 1 if walkable else 0
	var after: bool = is_walkable(cell)
	if before != after:
		_astar.set_point_solid(cell, not after)
		_sync_owner_grids(cell)
		version += 1
		if after:
			changed_unblocked = true
		else:
			changed_blocked = true


## Keeps every owner grid in step with the shared one for a cell.
func _sync_owner_grids(cell: Vector2i) -> void:
	for owner: int in _astar_by_owner.keys():
		(_astar_by_owner[owner] as AStarGrid2D).set_point_solid(cell, not is_walkable_for(cell, owner))


## Adds (blocked=true) or removes one block from each cell. Returns how many cells flipped.
func set_blocked(cells: Array[Vector2i], blocked: bool) -> int:
	var flipped: int = 0
	for cell: Vector2i in cells:
		if not in_bounds(cell):
			continue
		var i: int = cell.y * width + cell.x
		var before: bool = is_walkable(cell)
		_block_count[i] = maxi(0, _block_count[i] + (1 if blocked else -1))
		var after: bool = is_walkable(cell)
		if before != after:
			_astar.set_point_solid(cell, not after)
			_sync_owner_grids(cell)
			flipped += 1
			if after:
				changed_unblocked = true
			else:
				changed_blocked = true
	if flipped > 0:
		version += 1
	return flipped


## Returns {blocked, unblocked} flags since the last call and clears them.
func consume_changes() -> Dictionary:
	var out: Dictionary = {"blocked": changed_blocked, "unblocked": changed_unblocked}
	changed_blocked = false
	changed_unblocked = false
	return out


## Closest walkable cell to `cell` (searching outward in square rings).
## Returns `cell` if none. `owner` >= -1 also respects closed gates
## (null = shared grid, gates ignored).
func nearest_walkable(cell: Vector2i, max_ring: int = 40, owner: Variant = null) -> Vector2i:
	if _walkable_q(cell, owner):
		return cell
	for ring: int in range(1, max_ring + 1):
		var best: Vector2i = Vector2i(-1, -1)
		var best_d: float = INF
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				var c: Vector2i = cell + Vector2i(dx, dy)
				if _walkable_q(c, owner):
					var d: float = Vector2(dx, dy).length_squared()
					if d < best_d:
						best_d = d
						best = c
		if best.x >= 0:
			return best
	return cell


func _walkable_q(cell: Vector2i, owner: Variant) -> bool:
	return is_walkable(cell) if owner == null else is_walkable_for(cell, int(owner))


## Smoothed world-space path from `from_world` to `to_world` for a unit of
## `owner` (null = ignore gates). The first point is the start position, the
## last is `to_world` (or the nearest walkable point to it). Empty if
## unreachable.
func find_path(from_world: Vector2, to_world: Vector2, owner: Variant = null) -> PackedVector2Array:
	var start: Vector2i = nearest_walkable(to_cell(from_world), 40, owner)
	var goal: Vector2i = nearest_walkable(to_cell(to_world), 40, owner)
	if not _walkable_q(start, owner) or not _walkable_q(goal, owner):
		return PackedVector2Array()
	var end_point: Vector2 = to_world if to_cell(to_world) == goal else cell_center(goal)
	var start_point: Vector2 = from_world if to_cell(from_world) == start else cell_center(start)
	if start == goal:
		return PackedVector2Array([start_point, end_point])
	# Partial paths: a walled-in goal still gets a route up to the wall, so an
	# army arrives at the obstacle (and fights it) instead of giving up.
	var grid: AStarGrid2D = _astar if owner == null else _grid_for(int(owner))
	var raw: PackedVector2Array = grid.get_point_path(start, goal, true)
	if raw.is_empty():
		return PackedVector2Array()
	if raw.size() >= 2 and to_cell(raw[raw.size() - 1]) != goal:
		raw[0] = start_point
		return smooth(raw, owner)
	raw[0] = start_point
	raw[raw.size() - 1] = end_point
	return smooth(raw, owner)


## String pulling: keep only the waypoints needed to stay in line of sight.
## From each anchor, find the farthest visible raw point with an exponential
## probe followed by a binary search (visibility along an A* path is nearly
## monotonic), so a long open path costs a handful of LOS checks, not n^2.
func smooth(points: PackedVector2Array, owner: Variant = null) -> PackedVector2Array:
	var n: int = points.size()
	if n <= 2:
		return points
	var out: PackedVector2Array = PackedVector2Array([points[0]])
	var anchor: int = 0
	while anchor < n - 1:
		var next: int = _farthest_visible(points, anchor, owner)
		out.append(points[next])
		anchor = next
	return out


func _farthest_visible(points: PackedVector2Array, anchor: int, owner: Variant = null) -> int:
	var n: int = points.size()
	if has_los(points[anchor], points[n - 1], 10.0, owner):
		return n - 1
	var ok: int = anchor + 1
	var step: int = 2
	var bad: int = n - 1
	while anchor + step < n - 1:
		if has_los(points[anchor], points[anchor + step], 10.0, owner):
			ok = anchor + step
			step *= 2
		else:
			bad = anchor + step
			break
	while bad - ok > 1:
		var mid: int = (ok + bad) / 2
		if has_los(points[anchor], points[mid], 10.0, owner):
			ok = mid
		else:
			bad = mid
	return ok


## True if the straight segment a->b only crosses walkable cells, without
## squeezing diagonally between two blocked corners. Checked with a margin so a
## unit's body (not just its centre) stays off blocked cells. `owner` makes
## the other side's closed gates count as walls.
func has_los(a: Vector2, b: Vector2, margin: float = 10.0, owner: Variant = null) -> bool:
	if not _segment_clear(a, b, owner):
		return false
	if margin <= 0.0:
		return true
	var dir: Vector2 = b - a
	if dir.length_squared() < 0.0001:
		return true
	var side: Vector2 = dir.normalized().orthogonal() * margin
	return _segment_clear(a + side, b + side, owner) and _segment_clear(a - side, b - side, owner)


## Supercover grid traversal (Amanatides-Woo) over every cell the segment touches.
func _segment_clear(a: Vector2, b: Vector2, owner: Variant = null) -> bool:
	var cell: Vector2i = to_cell(a)
	var end_cell: Vector2i = to_cell(b)
	if not _walkable_q(cell, owner) or not _walkable_q(end_cell, owner):
		return false
	var d: Vector2 = b - a
	var step_x: int = 1 if d.x > 0.0 else -1
	var step_y: int = 1 if d.y > 0.0 else -1
	var t_delta_x: float = INF if is_zero_approx(d.x) else absf(cell_size / d.x)
	var t_delta_y: float = INF if is_zero_approx(d.y) else absf(cell_size / d.y)
	var next_x: float = (cell.x + (1 if step_x > 0 else 0)) * cell_size
	var next_y: float = (cell.y + (1 if step_y > 0 else 0)) * cell_size
	var t_max_x: float = INF if is_zero_approx(d.x) else (next_x - a.x) / d.x
	var t_max_y: float = INF if is_zero_approx(d.y) else (next_y - a.y) / d.y
	var guard: int = width + height + 4
	while cell != end_cell and guard > 0:
		guard -= 1
		if absf(t_max_x - t_max_y) < 0.000001:
			# Passing exactly through a corner: both neighbours must be open.
			if not _walkable_q(cell + Vector2i(step_x, 0), owner) or not _walkable_q(cell + Vector2i(0, step_y), owner):
				return false
			cell += Vector2i(step_x, step_y)
			t_max_x += t_delta_x
			t_max_y += t_delta_y
		elif t_max_x < t_max_y:
			cell.x += step_x
			t_max_x += t_delta_x
		else:
			cell.y += step_y
			t_max_y += t_delta_y
		if not _walkable_q(cell, owner):
			return false
	return true
