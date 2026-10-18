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
	for start: Vector2i in starts:
		for entry: Variant in map_def.get("start_layout", []):
			_place_around(world, rng, start, entry)
	for entry: Variant in map_def.get("extra_resources", []):
		_place_extra(world, rng, starts, entry)


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


static func _place_extra(world: World, rng: RandomNumberGenerator, starts: Array[Vector2i], entry: Dictionary) -> void:
	var type_id: String = String(entry.get("type", ""))
	var min_from_start: float = float(entry.get("min_from_start", 18))
	var is_animal: bool = String(entry.get("kind", "node")) == "animal"
	var margin: int = 6
	for i: int in int(entry.get("count", 1)):
		for attempt: int in 80:
			var cell: Vector2i = Vector2i(rng.randi_range(margin, world.map_width - margin), rng.randi_range(margin, world.map_height - margin))
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
