class_name ResourceNode
extends Node2D
## A gatherable object: gold/stone mine, berry bush, animal carcass.
## Trees are NOT nodes (see World tree field). Stats from resources.json.

signal depleted(node: ResourceNode)

var resource_type: String = ""
var data: Dictionary = {}
var resource: String = ""
var subtype: String = ""
var amount: float = 0.0
var max_amount: float = 0.0
var cell: Vector2i = Vector2i.ZERO
var footprint: Vector2i = Vector2i(1, 1)
var tile_size: float = 64.0
var walkable: bool = false
var decay_per_s: float = 0.0
var _depleted: bool = false


func setup(type_id: String, origin_cell: Vector2i, p_tile_size: float) -> void:
	resource_type = type_id
	cell = origin_cell
	tile_size = p_tile_size
	data = DataLoader.get_entry("resources", type_id)
	if data.is_empty():
		push_error("ResourceNode: unknown type " + type_id)
	resource = String(data.get("resource", "food"))
	subtype = String(data.get("subtype", resource))
	max_amount = float(data.get("amount", 100))
	amount = max_amount
	var fp: Array = data.get("footprint", [1, 1])
	footprint = Vector2i(int(fp[0]), int(fp[1]))
	walkable = bool(data.get("walkable", false))
	decay_per_s = float(data.get("decay_per_s", 0.0))
	position = (Vector2(cell) + Vector2(footprint) * 0.5) * tile_size
	name = "%s_%d" % [type_id, get_instance_id()]


## Carcasses spawn wherever the animal fell, not on the grid.
func place_free(world_pos: Vector2) -> void:
	position = world_pos
	cell = Vector2i(floori(world_pos.x / tile_size), floori(world_pos.y / tile_size))


func rect() -> Rect2:
	return Rect2(position - Vector2(footprint) * tile_size * 0.5, Vector2(footprint) * tile_size)


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in footprint.y:
		for x: int in footprint.x:
			out.append(cell + Vector2i(x, y))
	return out


func is_depleted() -> bool:
	return _depleted


## Removes up to `want` and returns what was actually taken.
func take(want: float) -> float:
	if _depleted:
		return 0.0
	var got: float = minf(want, amount)
	amount -= got
	if amount <= 0.0001:
		_mark_depleted()
	return got


func decay(delta: float) -> void:
	if decay_per_s <= 0.0 or _depleted:
		return
	amount -= decay_per_s * delta
	if amount <= 0.0:
		_mark_depleted()


func _mark_depleted() -> void:
	if _depleted:
		return
	_depleted = true
	amount = 0.0
	depleted.emit(self)


func _draw() -> void:
	var region: Rect2 = PlaceholderArt.resource_region(resource_type)
	if region.size == Vector2.ZERO:
		return
	draw_texture_rect_region(PlaceholderArt.texture(), Rect2(-region.size * 0.5, region.size), region)
