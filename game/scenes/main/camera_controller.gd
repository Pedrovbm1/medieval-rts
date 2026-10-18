class_name CameraController
extends Camera2D
## Touch-first RTS camera: one-finger pan, two-finger pinch zoom (0.5x-1.5x),
## always clamped so the view never leaves the map.
## Mouse wheel zoom is kept for desktop testing only.

const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 1.5
const WHEEL_ZOOM_STEP: float = 0.1

var map_bounds: Rect2 = Rect2()

## Active pointers: touch index -> last known screen position.
var _touches: Dictionary = {}
var _pinch_start_distance: float = 0.0
var _pinch_start_zoom: float = 1.0


func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	position_smoothing_enabled = false
	make_current()


## Sets the world rectangle the camera may show, then re-clamps.
func set_map_bounds(bounds: Rect2) -> void:
	map_bounds = bounds
	position = _clamped(position)


func center_on(world_pos: Vector2) -> void:
	position = _clamped(world_pos)


func get_zoom_factor() -> float:
	return zoom.x


## Sets the zoom factor keeping the world point under screen_point fixed.
func zoom_at(screen_point: Vector2, new_factor: float) -> void:
	var factor: float = clampf(new_factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(factor, zoom.x):
		return
	var before: Vector2 = screen_to_world(screen_point)
	zoom = Vector2(factor, factor)
	var after: Vector2 = screen_to_world(screen_point)
	position = _clamped(position + before - after)
	EventBus.camera_zoom_changed.emit(factor)


func screen_to_world(screen_point: Vector2) -> Vector2:
	var view_size: Vector2 = get_viewport_rect().size
	return position + (screen_point - view_size * 0.5) / zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 2:
			_begin_pinch()
	else:
		_touches.erase(event.index)
		if _touches.size() == 2:
			_begin_pinch()


func _on_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		_touches[event.index] = event.position
		return
	if _touches.size() == 1:
		_touches[event.index] = event.position
		position = _clamped(position - event.relative / zoom.x)
		return
	# Two or more fingers: pan by the midpoint delta, zoom by the distance ratio.
	var ids: Array = _touches.keys()
	var old_mid: Vector2 = (_touches[ids[0]] + _touches[ids[1]]) * 0.5
	_touches[event.index] = event.position
	var a: Vector2 = _touches[ids[0]]
	var b: Vector2 = _touches[ids[1]]
	var new_mid: Vector2 = (a + b) * 0.5
	position = _clamped(position - (new_mid - old_mid) / zoom.x)
	if _pinch_start_distance > 0.0:
		var ratio: float = a.distance_to(b) / _pinch_start_distance
		zoom_at(new_mid, _pinch_start_zoom * ratio)


func _on_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_at(event.position, zoom.x + WHEEL_ZOOM_STEP)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_at(event.position, zoom.x - WHEEL_ZOOM_STEP)


func _begin_pinch() -> void:
	var ids: Array = _touches.keys()
	var a: Vector2 = _touches[ids[0]]
	var b: Vector2 = _touches[ids[1]]
	_pinch_start_distance = maxf(a.distance_to(b), 1.0)
	_pinch_start_zoom = zoom.x


func _clamped(world_pos: Vector2) -> Vector2:
	return clamp_to_bounds(world_pos, map_bounds, get_viewport_rect().size, zoom.x)


## Pure clamp so the visible rectangle stays inside bounds. Static for unit tests.
## If the view is larger than the map on an axis, the camera centres on that axis.
static func clamp_to_bounds(world_pos: Vector2, bounds: Rect2, view_size: Vector2, zoom_factor: float) -> Vector2:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return world_pos
	var half_view: Vector2 = view_size * 0.5 / zoom_factor
	var min_pos: Vector2 = bounds.position + half_view
	var max_pos: Vector2 = bounds.end - half_view
	var result: Vector2 = world_pos
	if max_pos.x < min_pos.x:
		result.x = bounds.get_center().x
	else:
		result.x = clampf(world_pos.x, min_pos.x, max_pos.x)
	if max_pos.y < min_pos.y:
		result.y = bounds.get_center().y
	else:
		result.y = clampf(world_pos.y, min_pos.y, max_pos.y)
	return result
