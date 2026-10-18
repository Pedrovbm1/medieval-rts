class_name Building
extends Node2D
## A building placed on the grid. Stats from buildings.json.
## Blocks its footprint cells in NavGrid unless "walkable" (farms).
## F3: placed already built. F4 adds construction progress and production.

signal destroyed(building: Building)

var building_type: String = ""
var owner_id: int = 0
var data: Dictionary = {}
var cell: Vector2i = Vector2i.ZERO
var footprint: Vector2i = Vector2i(2, 2)
var tile_size: float = 64.0
var hp: int = 1
var max_hp: int = 1
var walkable: bool = false
## 0..1. Fully built buildings work (drop-off, pop, farm). F4 grows it.
var build_progress: float = 1.0
## Workers currently assigned (farms limit this).
var workers: Array[Unit] = []
var selected: bool = false:
	set(value):
		if selected != value:
			selected = value
			queue_redraw()


func setup(type_id: String, player_id: int, origin_cell: Vector2i, p_tile_size: float) -> void:
	building_type = type_id
	owner_id = player_id
	cell = origin_cell
	tile_size = p_tile_size
	data = DataLoader.get_entry("buildings", type_id)
	if data.is_empty():
		push_error("Building: unknown type " + type_id)
	var fp: Array = data.get("footprint", [2, 2])
	footprint = Vector2i(int(fp[0]), int(fp[1]))
	max_hp = int(data.get("hp", 100))
	hp = max_hp
	walkable = bool(data.get("walkable", false))
	# Node origin at the footprint centre so y-sorting looks right.
	position = (Vector2(cell) + Vector2(footprint) * 0.5) * tile_size
	name = "%s_%d" % [type_id, get_instance_id()]


func is_complete() -> bool:
	return build_progress >= 1.0


func rect() -> Rect2:
	return Rect2(Vector2(cell) * tile_size, Vector2(footprint) * tile_size)


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in footprint.y:
		for x: int in footprint.x:
			out.append(cell + Vector2i(x, y))
	return out


func accepts(resource: String) -> bool:
	return is_complete() and Array(data.get("dropoff", [])).has(resource)


func pop_bonus() -> int:
	return int(data.get("pop_bonus", 0)) if is_complete() else 0


## Farm-like buildings: {"resource", "subtype", "workers"}; empty otherwise.
func gather_info() -> Dictionary:
	return data.get("gather", {})


func has_free_work_slot(unit: Unit) -> bool:
	workers = workers.filter(func(u: Unit) -> bool: return is_instance_valid(u) and not u.is_dead)
	if workers.has(unit):
		return true
	return workers.size() < int(gather_info().get("workers", 1))


func take_damage(amount: int, _source: Unit) -> void:
	hp = maxi(0, hp - maxi(1, amount))
	queue_redraw()
	if hp == 0:
		destroyed.emit(self)


func _draw() -> void:
	var tex: Texture2D = PlaceholderArt.texture()
	var region: Rect2 = PlaceholderArt.building_region(building_type, owner_id)
	var half: Vector2 = Vector2(footprint) * tile_size * 0.5
	draw_texture_rect_region(tex, Rect2(-half, region.size), region)
	if selected:
		draw_rect(Rect2(-half, half * 2.0), Color(0.35, 1.0, 0.35), false, 3.0)
	if hp < max_hp:
		var top: Vector2 = Vector2(-half.x + 8.0, -half.y - 10.0)
		var w: float = half.x * 2.0 - 16.0
		draw_texture_rect_region(tex, Rect2(top, Vector2(w, 6.0)), PlaceholderArt.WHITE_RECT, Color(0.1, 0.1, 0.1, 0.85))
		draw_texture_rect_region(tex, Rect2(top + Vector2(1, 1), Vector2((w - 2.0) * float(hp) / max_hp, 4.0)), PlaceholderArt.WHITE_RECT, Color(0.3, 0.9, 0.3))
