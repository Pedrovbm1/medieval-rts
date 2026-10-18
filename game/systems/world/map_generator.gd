class_name MapGenerator
extends RefCounted
## Pure terrain generation: map definition + terrain table in, grid of terrain ids out.
## No nodes, no rendering. Deterministic for a given seed.


## Returns a width*height PackedByteArray of terrain ids (row-major, y*width + x).
static func generate(map_def: Dictionary, terrain_def: Dictionary) -> PackedByteArray:
	var types: Dictionary = terrain_def.get("types", {})
	var grass_id: int = _type_id(types, "grass", 0)
	var water_id: int = _type_id(types, "water", 1)
	var forest_id: int = _type_id(types, "forest", 2)

	var width: int = int(map_def.get("width", 120))
	var height: int = int(map_def.get("height", 120))
	var seed_value: int = int(map_def.get("seed", 1))
	var water_threshold: float = float(map_def.get("water_threshold", -0.3))
	var forest_threshold: float = float(map_def.get("forest_threshold", 0.28))
	var shore_margin: float = float(map_def.get("shore_margin", 0.1))

	var height_noise: FastNoiseLite = _make_noise(seed_value, map_def.get("height_noise", {}))
	var forest_noise: FastNoiseLite = _make_noise(seed_value + 1, map_def.get("forest_noise", {}))

	var grid: PackedByteArray = PackedByteArray()
	grid.resize(width * height)
	for y: int in height:
		for x: int in width:
			var elevation: float = height_noise.get_noise_2d(float(x), float(y))
			var terrain_id: int = grass_id
			if elevation < water_threshold:
				terrain_id = water_id
			elif elevation > water_threshold + shore_margin \
					and forest_noise.get_noise_2d(float(x), float(y)) > forest_threshold:
				terrain_id = forest_id
			grid[y * width + x] = terrain_id
	return grid


## Counts how many cells of each terrain id exist. Useful for tests and balance checks.
static func count_terrain(grid: PackedByteArray) -> Dictionary:
	var counts: Dictionary = {}
	for terrain_id: int in grid:
		counts[terrain_id] = int(counts.get(terrain_id, 0)) + 1
	return counts


static func _make_noise(seed_value: int, params: Dictionary) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = float(params.get("frequency", 0.05))
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = int(params.get("octaves", 3))
	return noise


static func _type_id(types: Dictionary, type_name: String, fallback: int) -> int:
	var entry: Dictionary = types.get(type_name, {})
	return int(entry.get("id", fallback))
