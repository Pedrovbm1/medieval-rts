class_name VisionGrid
extends RefCounted
## Per-player visibility on the tile grid, three states per cell:
## 0 = never seen, 1 = explored (seen before), 2 = visible now.
## Updated a few times per second from unit and building sight radii.
## The AI reads it to stay honest (no map hack); F8 draws it as fog of war.

const UNSEEN: int = 0
const EXPLORED: int = 1
const VISIBLE: int = 2

var width: int = 0
var height: int = 0
var cell_size: float = 64.0
## player_id -> PackedByteArray of states
var states: Dictionary = {}
## player_id -> PackedInt32Array of cells visible after the last update
var _visible_now: Dictionary = {}
## radius (cells) -> PackedInt32Array of packed (dx, dy) offsets
var _circles: Dictionary = {}


func setup(map_width: int, map_height: int, tile_size: float, players: Array) -> void:
	width = map_width
	height = map_height
	cell_size = tile_size
	states.clear()
	_visible_now.clear()
	for p: Variant in players:
		var grid: PackedByteArray = PackedByteArray()
		grid.resize(width * height)
		grid.fill(UNSEEN)
		states[int(p)] = grid
		_visible_now[int(p)] = PackedInt32Array()


## Recomputes what each player sees now. `sources`: player -> Array of [Vector2 pos, float sight_px].
func update(sources: Dictionary) -> void:
	for p: int in states.keys():
		var grid: PackedByteArray = states[p]
		var was: PackedInt32Array = _visible_now[p]
		for i: int in was:
			grid[i] = EXPLORED
		var now: PackedInt32Array = PackedInt32Array()
		for src: Array in sources.get(p, []):
			_stamp(grid, now, src[0], float(src[1]))
		_visible_now[p] = now
		states[p] = grid


func state(player_id: int, cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height or not states.has(player_id):
		return UNSEEN
	return (states[player_id] as PackedByteArray)[cell.y * width + cell.x]


func is_visible(player_id: int, world_pos: Vector2) -> bool:
	return state(player_id, _cell(world_pos)) == VISIBLE


func is_explored(player_id: int, world_pos: Vector2) -> bool:
	return state(player_id, _cell(world_pos)) >= EXPLORED


## Fraction of the map this player has ever seen (0..1).
func explored_ratio(player_id: int) -> float:
	if not states.has(player_id):
		return 0.0
	var seen: int = 0
	for v: int in (states[player_id] as PackedByteArray):
		if v != UNSEEN:
			seen += 1
	return float(seen) / float(width * height)


## Reveals everything for a player (debug / end-of-match view).
func reveal_all(player_id: int) -> void:
	if states.has(player_id):
		(states[player_id] as PackedByteArray).fill(EXPLORED)


func _cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / cell_size), floori(world_pos.y / cell_size))


func _stamp(grid: PackedByteArray, now: PackedInt32Array, pos: Vector2, sight_px: float) -> void:
	var r: int = maxi(1, int(ceilf(sight_px / cell_size)))
	var offsets: PackedInt32Array = _circle(r)
	var c: Vector2i = _cell(pos)
	for packed: int in offsets:
		var x: int = c.x + (packed >> 16) - 1024
		var y: int = c.y + (packed & 0xFFFF) - 1024
		if x < 0 or y < 0 or x >= width or y >= height:
			continue
		var i: int = y * width + x
		if grid[i] != VISIBLE:
			grid[i] = VISIBLE
			now.append(i)


func _circle(r: int) -> PackedInt32Array:
	if _circles.has(r):
		return _circles[r]
	var out: PackedInt32Array = PackedInt32Array()
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r + r:
				out.append(((dx + 1024) << 16) | (dy + 1024))
	_circles[r] = out
	return out
