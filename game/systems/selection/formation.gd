class_name Formation
extends RefCounted
## Pure helpers to spread a group around a target point so units do not stack.


## Grid slots around `center`, nearest first (a filled square spiral).
static func slots(center: Vector2, count: int, spacing: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if count <= 0:
		return result
	var ring: int = 0
	while result.size() < count:
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				result.append(center + Vector2(dx, dy) * spacing)
		ring += 1
	result.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(center) < b.distance_squared_to(center))
	result.resize(count)
	return result


## Greedy assignment: each slot (nearest to target first) takes the closest free unit.
## Returns an Array of positions aligned with `positions` (same index order).
static func assign(positions: Array[Vector2], slot_list: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	result.resize(positions.size())
	var taken: Array[bool] = []
	taken.resize(positions.size())
	taken.fill(false)
	for slot: Vector2 in slot_list:
		var best: int = -1
		var best_dist: float = INF
		for i: int in positions.size():
			if taken[i]:
				continue
			var d: float = positions[i].distance_squared_to(slot)
			if d < best_dist:
				best_dist = d
				best = i
		if best == -1:
			break
		taken[best] = true
		result[best] = slot
	return result


static func centroid(positions: Array[Vector2]) -> Vector2:
	if positions.is_empty():
		return Vector2.ZERO
	var sum: Vector2 = Vector2.ZERO
	for p: Vector2 in positions:
		sum += p
	return sum / positions.size()
