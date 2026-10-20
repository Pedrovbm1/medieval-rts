class_name FormationLayout
extends RefCounted
## Battle formations for a group order (IDEAS-AOE2 batch 2c). Three shapes,
## all facing the order's direction:
## - "line": ranks across the march: melee in front, ranged behind, siege
##   and support last.
## - "box": ranged and support packed in the middle, melee on the ring.
## - "wedge": an arrowhead with the cavalry at the tip, melee behind it and
##   the ranged at the base.
## "none" keeps the plain spread (Formation.walkable_slots). Every slot is
## snapped to the nearest walkable cell, so a formation never asks a unit to
## stand in water. Within one role the slots are handed out greedily (the
## nearest unit takes each slot) so the lines do not cross.

const KINDS: PackedStringArray = ["none", "line", "box", "wedge"]


## Role of a unit for the layout: "cavalry", "melee", "ranged" or "support".
static func role_of(u: Unit) -> String:
	var combat: Dictionary = u.data.get("combat", {})
	var classes: Array = Combat.classes_of(u.data)
	if u.can_gather() or combat.is_empty() or u.data.has("heal"):
		return "support"
	if classes.has("siege"):
		return "ranged"
	if float(combat.get("range_px", 0.0)) > 0.0:
		return "ranged"
	if classes.has("cavalry"):
		return "cavalry"
	return "melee"


## Slots aligned with `units` (same index order) for `kind` around `center`,
## facing `facing` (unit vector), `spacing` px apart, snapped with `nav`.
static func layout(kind: String, center: Vector2, facing: Vector2, units: Array[Unit], spacing: float, nav: NavGrid) -> Array[Vector2]:
	var out: Array[Vector2] = []
	out.resize(units.size())
	if units.is_empty():
		return out
	if facing == Vector2.ZERO:
		facing = Vector2.RIGHT
	facing = facing.normalized()
	var side: Vector2 = facing.orthogonal()
	var by_role: Dictionary = {"cavalry": [], "melee": [], "ranged": [], "support": []}
	for i: int in units.size():
		(by_role[role_of(units[i])] as Array).append(i)
	var slots_by_role: Dictionary = {}
	match kind:
		"line":
			slots_by_role = _line(center, facing, side, by_role, spacing)
		"box":
			slots_by_role = _box(center, by_role, spacing)
		"wedge":
			slots_by_role = _wedge(center, facing, side, by_role, spacing)
		_:
			var plain: Array[Vector2] = Formation.walkable_slots(center, units.size(), spacing, nav)
			var positions: Array[Vector2] = []
			for u: Unit in units:
				positions.append(u.position)
			return Formation.assign(positions, plain)
	for role: String in by_role.keys():
		var idx: Array = by_role[role]
		if idx.is_empty():
			continue
		var positions: Array[Vector2] = []
		for i: int in idx:
			positions.append(units[i].position)
		var slots: Array[Vector2] = []
		for s: Vector2 in slots_by_role.get(role, []):
			slots.append(_snap(s, nav))
		var assigned: Array[Vector2] = Formation.assign(positions, slots)
		for k: int in idx.size():
			out[int(idx[k])] = assigned[k]
	return out


static func _snap(p: Vector2, nav: NavGrid) -> Vector2:
	if nav == null or nav.is_walkable_world(p):
		return p
	return nav.cell_center(nav.nearest_walkable(nav.to_cell(p)))


## A rank of `n` slots centred on `at`, spread along `side`.
static func _rank(at: Vector2, side: Vector2, n: int, spacing: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i: int in n:
		out.append(at + side * (float(i) - float(n - 1) * 0.5) * spacing)
	return out


## Ranks that wrap: at most `width` per rank, deeper ranks behind.
static func _ranks(front: Vector2, facing: Vector2, side: Vector2, n: int, width: int, spacing: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var row: int = 0
	var left: int = n
	while left > 0:
		var take: int = mini(width, left)
		out.append_array(_rank(front - facing * row * spacing, side, take, spacing))
		left -= take
		row += 1
	return out


static func _line(center: Vector2, facing: Vector2, side: Vector2, by_role: Dictionary, spacing: float) -> Dictionary:
	var total: int = 0
	for r: String in by_role.keys():
		total += (by_role[r] as Array).size()
	var width: int = maxi(3, int(ceil(sqrt(float(total)) * 1.6)))
	var out: Dictionary = {}
	var depth: int = 0
	# Front to back: cavalry and melee share the front ranks, then ranged, then support.
	for group: Array in [["cavalry", "melee"], ["ranged"], ["support"]]:
		var n: int = 0
		for r: String in group:
			n += (by_role[r] as Array).size()
		if n == 0:
			continue
		var slots: Array[Vector2] = _ranks(center - facing * depth * spacing, facing, side, n, width, spacing)
		var k: int = 0
		for r: String in group:
			var cnt: int = (by_role[r] as Array).size()
			out[r] = slots.slice(k, k + cnt)
			k += cnt
		depth += int(ceil(float(n) / width))
	return out


static func _box(center: Vector2, by_role: Dictionary, spacing: float) -> Dictionary:
	var inner_n: int = (by_role["ranged"] as Array).size() + (by_role["support"] as Array).size()
	var outer_n: int = (by_role["melee"] as Array).size() + (by_role["cavalry"] as Array).size()
	var out: Dictionary = {}
	var inner: Array[Vector2] = Formation.slots(center, inner_n, spacing)
	out["ranged"] = inner.slice(0, (by_role["ranged"] as Array).size())
	out["support"] = inner.slice((by_role["ranged"] as Array).size(), inner_n)
	# The ring: a square just outside the inner block, slots spread along it.
	var half: float = (ceil(sqrt(float(maxi(inner_n, 1))) * 0.5) + 1.0) * spacing
	var ring: Array[Vector2] = []
	if outer_n > 0:
		var perimeter: float = half * 8.0
		for i: int in outer_n:
			var t: float = perimeter * float(i) / outer_n
			ring.append(center + _on_square(t, half))
	out["melee"] = ring.slice(0, (by_role["melee"] as Array).size())
	out["cavalry"] = ring.slice((by_role["melee"] as Array).size(), outer_n)
	return out


## Point at distance `t` along the perimeter of a square of half-size `half`
## (starting at the top-left corner, clockwise).
static func _on_square(t: float, half: float) -> Vector2:
	var edge: float = half * 2.0
	var k: float = fmod(t, edge * 4.0)
	if k < edge:
		return Vector2(-half + k, -half)
	if k < edge * 2.0:
		return Vector2(half, -half + (k - edge))
	if k < edge * 3.0:
		return Vector2(half - (k - edge * 2.0), half)
	return Vector2(-half, half - (k - edge * 3.0))


static func _wedge(center: Vector2, facing: Vector2, side: Vector2, by_role: Dictionary, spacing: float) -> Dictionary:
	# Rows of 1, 2, 3... from the tip back; cavalry first, then melee, then
	# ranged, then support, in that order of rows.
	var order: Array = []
	for r: String in ["cavalry", "melee", "ranged", "support"]:
		for _i: int in (by_role[r] as Array).size():
			order.append(r)
	var out: Dictionary = {"cavalry": [], "melee": [], "ranged": [], "support": []}
	var row: int = 0
	var i: int = 0
	var tip: Vector2 = center + facing * spacing * 1.5
	while i < order.size():
		var take: int = mini(row + 1, order.size() - i)
		var rank: Array[Vector2] = _rank(tip - facing * row * spacing * 0.9, side, take, spacing)
		for k: int in take:
			(out[order[i + k]] as Array).append(rank[k])
		i += take
		row += 1
	return out
