class_name MapPopulator
extends RefCounted
## Places resource nodes and wild animals from the map definition:
## - "starts": [[x, y], ...] player start cells (Town Center centre).
## - "start_layout": entries placed around EVERY start the same way
##   {"type", "count", "min", "max", "kind": "node"|"animal", "cluster": bool}
## - "extra_resources": {"type", "count", "min_from_start"} scattered elsewhere.
## Deterministic for the map seed.


static func populate(world: World, map_def: Dictionary) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(map_def.get("seed", 1)) * 7919 + 17
	var starts: Array[Vector2i] = starts_of(map_def)
	if bool(map_def.get("center_veins", false)):
		# A reason to fight for the middle: a rich gold vein and a big quarry
		# at the centre of the map (self-symmetric, placed before mirroring),
		# and the neutral trade post caravans travel to.
		_place_center(world)
		_place_trade_post(world)
	if String(map_def.get("symmetry", "")) == "point" and starts.size() == 2:
		# Fair curated maps: lay out the first player's half, then mirror it.
		var nodes_before: int = world.resource_nodes.size()
		var units_before: int = world.units.size()
		for entry: Variant in map_def.get("start_layout", []):
			_place_around(world, rng, starts[0], entry)
		for entry: Variant in map_def.get("extra_resources", []):
			_place_extra(world, rng, starts, entry, true)
		if bool(map_def.get("center_veins", false)):
			_place_relics(world, true)
		_mirror_new(world, nodes_before, units_before)
		world.recount_relics()
		return
	for start: Vector2i in starts:
		for entry: Variant in map_def.get("start_layout", []):
			_place_around(world, rng, start, entry)
	for entry: Variant in map_def.get("extra_resources", []):
		_place_extra(world, rng, starts, entry)
	if bool(map_def.get("center_veins", false)):
		_place_relics(world, false)
	world.recount_relics()


## Relics in pairs around the middle (rules relics.pairs): each pair is a
## spot and its point mirror, so both players are the same distance away.
## On a symmetric map only the first of each pair is placed here (the
## mirroring step adds the other); elsewhere both are placed.
static func _place_relics(world: World, half: bool) -> void:
	var size: Vector2i = Vector2i(world.map_width, world.map_height)
	var center: Vector2i = size / 2
	var offsets: Array[Vector2i] = [Vector2i(-15, 9), Vector2i(10, -17), Vector2i(-20, -4), Vector2i(6, 20)]
	var pairs: int = mini(int(DataLoader.rule("relics", "pairs", 2)), offsets.size())
	for i: int in pairs:
		var cell: Vector2i = _place_near(world, "relic", center + offsets[i], 6)
		if cell.x >= 0 and not half:
			_place_near(world, "relic", size - cell - Vector2i(1, 1), 6)


## Copies every node and animal placed since the given counts to the
## point-mirrored spot (same footprint, rotated 180 degrees).
static func _mirror_new(world: World, nodes_before: int, units_before: int) -> void:
	var size: Vector2i = Vector2i(world.map_width, world.map_height)
	for n: ResourceNode in world.resource_nodes.slice(nodes_before, world.resource_nodes.size()):
		world.place_resource(n.resource_type, size - n.cell - n.footprint)
	for u: Unit in world.units.slice(units_before, world.units.size()):
		world.spawn_unit(u.unit_type, Unit.OWNER_GAIA, world.map_size_px - u.position)


## Gold vein on the exact centre (a 2x2 at size/2 - 1 is its own mirror
## image) and a quarry a few cells to the side plus its mirror. Forest or
## water in the way: the nearest free cell in a ring, still inside the
## mirrored half so the quarry's mirror lands on the other side.
static func _place_center(world: World) -> void:
	var center: Vector2i = Vector2i(world.map_width / 2 - 1, world.map_height / 2 - 1)
	_place_near(world, "gold_vein", center, 8)
	var quarry: Vector2i = _place_near(world, "stone_quarry", center + Vector2i(5, -3), 8)
	if quarry.x >= 0:
		var size: Vector2i = Vector2i(world.map_width, world.map_height)
		_place_near(world, "stone_quarry", size - quarry - Vector2i(2, 2), 8)


## Neutral trade post a few cells off the centre (never on the veins).
static func _place_trade_post(world: World) -> void:
	if DataLoader.get_entry("buildings", "trade_post").is_empty():
		return
	var center: Vector2 = world.map_size_px * 0.5
	var cell: Vector2i = world.find_building_spot("trade_post", center + Vector2(-5.0, 4.0) * world.tile_size, 12)
	if cell.x >= 0:
		var post: Building = world.place_building("trade_post", Unit.OWNER_GAIA, cell)
		post.add_progress(1.0)


## Tries `cell` then a square spiral around it; returns the cell used or (-1,-1).
static func _place_near(world: World, type_id: String, cell: Vector2i, max_ring: int) -> Vector2i:
	for ring: int in max_ring + 1:
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				var c: Vector2i = cell + Vector2i(dx, dy)
				if _try_place(world, type_id, c, false):
					return c
	return Vector2i(-1, -1)


static func starts_of(map_def: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s: Variant in map_def.get("starts", []):
		out.append(Vector2i(int(s[0]), int(s[1])))
	return out


static func _place_around(world: World, rng: RandomNumberGenerator, start: Vector2i, entry: Dictionary) -> void:
	var type_id: String = String(entry.get("type", ""))
	var count: int = int(entry.get("count", 1))
	var min_d: float = float(entry.get("min", 5))
	var max_d: float = float(entry.get("max", 8))
	var is_animal: bool = String(entry.get("kind", "node")) == "animal"
	var clustered: bool = bool(entry.get("cluster", false))
	var fp_arr: Array = DataLoader.get_entry("resources", type_id).get("footprint", [1, 1])
	var step: int = maxi(int(fp_arr[0]), int(fp_arr[1]))
	var cluster: Array[Vector2i] = []
	for i: int in count:
		for attempt: int in 60:
			var cell: Vector2i
			if clustered and not cluster.is_empty():
				# Grow the cluster: touch a random member on one side.
				var base: Vector2i = cluster[rng.randi_range(0, cluster.size() - 1)]
				var dirs: Array[Vector2i] = [Vector2i(step, 0), Vector2i(-step, 0), Vector2i(0, step), Vector2i(0, -step)]
				cell = base + dirs[rng.randi_range(0, 3)]
			else:
				var ang: float = rng.randf() * TAU
				var dist: float = rng.randf_range(min_d, max_d)
				cell = start + Vector2i(roundi(cos(ang) * dist), roundi(sin(ang) * dist))
			if _try_place(world, type_id, cell, is_animal, clustered and not cluster.is_empty()):
				cluster.append(cell)
				break


## `half`: only in the first half of a point-symmetric map (it gets mirrored).
static func _place_extra(world: World, rng: RandomNumberGenerator, starts: Array[Vector2i], entry: Dictionary, half: bool = false) -> void:
	var type_id: String = String(entry.get("type", ""))
	var min_from_start: float = float(entry.get("min_from_start", 18))
	var is_animal: bool = String(entry.get("kind", "node")) == "animal"
	var margin: int = 6
	for i: int in int(entry.get("count", 1)):
		for attempt: int in 80:
			var cell: Vector2i = Vector2i(rng.randi_range(margin, world.map_width - margin), rng.randi_range(margin, world.map_height - margin))
			if half and cell.x + cell.y > world.map_width - 6:
				continue
			var far: bool = true
			for s: Vector2i in starts:
				if Vector2(cell - s).length() < min_from_start:
					far = false
			if far and _try_place(world, type_id, cell, is_animal):
				break


## `touching`: members of a cluster may sit next to each other (only the
## footprint itself must be free); lone nodes keep a free ring around them.
static func _try_place(world: World, type_id: String, cell: Vector2i, is_animal: bool, touching: bool = false) -> bool:
	if is_animal:
		if not world.nav.is_walkable(cell):
			return false
		world.spawn_unit(type_id, Unit.OWNER_GAIA, world.cell_center(cell))
		return true
	var data: Dictionary = DataLoader.get_entry("resources", type_id)
	var fp_arr: Array = data.get("footprint", [1, 1])
	var fp: Vector2i = Vector2i(int(fp_arr[0]), int(fp_arr[1]))
	# Footprint plus a one-cell walkable ring, so workers can always reach it.
	var ring: int = 0 if touching else 1
	for y: int in range(-ring, fp.y + ring):
		for x: int in range(-ring, fp.x + ring):
			if not world.nav.is_walkable(cell + Vector2i(x, y)):
				return false
	var area: Rect2 = Rect2(Vector2(cell - Vector2i(ring, ring)) * world.tile_size, Vector2(fp + Vector2i(ring * 2, ring * 2)) * world.tile_size).grow(-1.0)
	for n: ResourceNode in world.resource_nodes:
		if n.rect().intersects(area):
			return false
	for b: Building in world.buildings:
		if b.rect().intersects(area):
			return false
	world.place_resource(type_id, cell)
	return true
