class_name PlacementController
extends Node2D
## Build mode with the finger: a ghost of the building follows taps and drags,
## turns green/red as placement is validated live, and is confirmed with the
## ✓ button or a double tap (✕ cancels). Draws the ghost itself (world space).

signal state_changed(active: bool, error: String)
signal placed(building: Building)
## Line mode (walls): segments in the current line and what they cost.
signal line_changed(anchored: bool, count: int, cost: Dictionary)

var world: World
var camera: CameraController
var player_id: int = GameState.PLAYER_HUMAN
var active: bool = false
var type_id: String = ""
var cell: Vector2i = Vector2i.ZERO
var builders: Array[Unit] = []
var error: String = ""
var _footprint: Vector2i = Vector2i(2, 2)
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
## Walls: first tap anchors the start, later taps move the end; ✓ builds
## one segment per free cell along the line.
var line_mode: bool = false
var line_anchor: Vector2i = Vector2i(-1, -1)
var line_cells: Array[Vector2i] = []
var _line_ok: Dictionary = {}  # cell -> bool


func setup(p_world: World, p_camera: CameraController) -> void:
	world = p_world
	camera = p_camera
	z_index = 60
	visible = false


func begin(p_type: String, p_builders: Array[Unit]) -> void:
	type_id = p_type
	builders = p_builders.duplicate()
	var def: Dictionary = DataLoader.get_entry("buildings", type_id)
	var fp: Array = def.get("footprint", [2, 2])
	_footprint = Vector2i(int(fp[0]), int(fp[1]))
	line_mode = bool(def.get("line", false))
	line_anchor = Vector2i(-1, -1)
	line_cells.clear()
	_line_ok.clear()
	active = true
	visible = true
	_place_at_world(camera.position)
	if line_mode:
		line_changed.emit(false, 0, {})
	_log("begin %s" % type_id)


func cancel() -> void:
	if not active:
		return
	active = false
	visible = false
	_dragging = false
	state_changed.emit(false, "")
	_log("cancel")


## Tries to build here. Returns the new foundation or null (ghost stays red).
func confirm() -> Building:
	if not active:
		return null
	if line_mode:
		return _confirm_line()
	_revalidate()
	if error != "":
		Sfx.play("order_stop")
		return null
	var b: Building = world.construction.start_construction(player_id, type_id, cell, builders)
	if b == null:
		_revalidate()
		return null
	active = false
	visible = false
	Sfx.play("place_building")
	state_changed.emit(false, "")
	placed.emit(b)
	_log("placed %s at=(%d,%d)" % [type_id, cell.x, cell.y])
	return b


## Line mode: builds every affordable free segment from the anchor on.
func _confirm_line() -> Building:
	if line_anchor.x < 0:
		Sfx.play("order_stop")
		return null
	var made: Array[Building] = world.construction.start_wall_line(player_id, type_id, line_cells, builders)
	if made.is_empty():
		Sfx.play("error")
		_revalidate()
		return null
	# Stay in line mode so the next wall starts where this one ended.
	line_anchor = line_cells[line_cells.size() - 1]
	line_cells = [line_anchor]
	Sfx.play("place_building")
	if made.size() < line_cells.size():
		Sfx.play("error")
	_revalidate()
	placed.emit(made[0])
	_log("placed %s line n=%d" % [type_id, made.size()])
	return made[0]


## Gesture routing while active. Returns true if the gesture was consumed.
func handle_gesture(g: Dictionary) -> bool:
	if not active:
		return false
	match String(g["type"]):
		"tap":
			if line_mode:
				_line_tap(camera.screen_to_world(g["pos"]))
				return true
			_place_at_world(camera.screen_to_world(g["pos"]))
			return true
		"double_tap":
			_place_at_world(camera.screen_to_world(g["pos"]))
			confirm()
			return true
		"pan":
			if line_mode:
				return false  # pans move the camera while tracing a wall
			if bool(g.get("first", false)):
				var start_world: Vector2 = camera.screen_to_world(g["start"])
				_dragging = ghost_rect().grow(24.0).has_point(start_world)
				_drag_offset = ghost_rect().get_center() - start_world
			if _dragging:
				_place_at_world(camera.screen_to_world(g["pos"]) + _drag_offset)
				return true
			return false
		"pan_end":
			var was: bool = _dragging
			_dragging = false
			return was
		"box_armed", "box_update", "box_end", "long_press":
			return true
	return false


func ghost_rect() -> Rect2:
	return Rect2(Vector2(cell) * world.tile_size, Vector2(_footprint) * world.tile_size)


func _place_at_world(world_pos: Vector2) -> void:
	cell = world.world_to_cell(world_pos) - _footprint / 2
	cell = cell.clamp(Vector2i.ONE, Vector2i(world.map_width, world.map_height) - _footprint - Vector2i.ONE)
	_revalidate()


func _line_tap(world_pos: Vector2) -> void:
	var c: Vector2i = world.world_to_cell(world_pos).clamp(Vector2i.ONE, Vector2i(world.map_width - 2, world.map_height - 2))
	if line_anchor.x < 0:
		line_anchor = c
	line_cells = World.line_cells(line_anchor, c)
	_revalidate()


func _revalidate() -> void:
	builders = builders.filter(func(u: Unit) -> bool: return is_instance_valid(u) and not u.is_dead)
	if line_mode:
		_line_ok.clear()
		var count: int = 0
		for c: Vector2i in line_cells:
			var err: String = world.construction.placement_error(player_id, type_id, c, builders)
			_line_ok[c] = err == "" or err == "cost"
			if _line_ok[c]:
				count += 1
		var unit_cost: Dictionary = DataLoader.get_entry("buildings", type_id).get("cost", {})
		var total: Dictionary = {}
		for res: String in unit_cost.keys():
			total[res] = int(unit_cost[res]) * count
		error = "" if line_anchor.x >= 0 and count > 0 else "line"
		if error == "" and not GameState.can_afford(player_id, total):
			error = "cost"
		queue_redraw()
		state_changed.emit(true, error)
		line_changed.emit(line_anchor.x >= 0, count, total)
		return
	error = world.construction.placement_error(player_id, type_id, cell, builders)
	queue_redraw()
	state_changed.emit(true, error)


func _process(_delta: float) -> void:
	if active and line_mode:
		return
	if active:
		# Units walk around: keep validity live even if the ghost does not move.
		var before: String = error
		error = world.construction.placement_error(player_id, type_id, cell, builders)
		if error != before:
			queue_redraw()
			state_changed.emit(true, error)


func _draw() -> void:
	if not active:
		return
	if line_mode:
		var region2: Rect2 = PlaceholderArt.building_region(type_id, player_id)
		var ts: float = world.tile_size
		if line_anchor.x < 0:
			# No anchor yet: a faint ring where the first tap will land.
			return
		for c: Vector2i in line_cells:
			var ok2: bool = bool(_line_ok.get(c, false))
			var t2: Color = Color(0.4, 1.0, 0.4, 0.6) if ok2 else Color(1.0, 0.35, 0.3, 0.45)
			draw_texture_rect_region(PlaceholderArt.texture(), Rect2(Vector2(c) * ts, Vector2(ts, ts)), region2, t2)
		return
	var rect: Rect2 = ghost_rect()
	var ok: bool = error == ""
	var tint: Color = Color(0.4, 1.0, 0.4, 0.55) if ok else Color(1.0, 0.35, 0.3, 0.55)
	var region: Rect2 = PlaceholderArt.building_region(type_id, player_id)
	draw_texture_rect_region(PlaceholderArt.texture(), Rect2(rect.position, region.size), region, tint)
	draw_rect(rect, Color(tint, 0.95), false, 3.0)


func _log(msg: String) -> void:
	if OS.is_debug_build() and bool(DataLoader.rule("debug", "log_input", false)):
		print("[REALM] build " + msg)
